import Foundation
import ViftyCore

package protocol SMCConnection: Sendable {
    func read(_ key: String) throws -> SMCValue
    func write(_ key: String, dataType: String, bytes: [UInt8]) throws
}

extension SMCClient: SMCConnection {}

public struct LocalFanHelperClient: Sendable {
    private struct PreparedWrite: Sendable {
        let key: String
        let dataType: String
        let bytes: [UInt8]
    }

    private struct MutationPlan: Sendable {
        let fanID: Int
        let modeKey: String
        let manualMode: PreparedWrite
        let automaticMode: PreparedWrite
        let requestedTarget: PreparedWrite?
        let hygieneTarget: PreparedWrite?
        let forceTestEnable: PreparedWrite?
        let forceTestDisable: PreparedWrite?
        let forceTestInitiallyDisabled: Bool
        let warnings: [String]
    }

    private struct Observation: Sendable {
        let mode: FanHardwareMode?
        let targetRPM: Int?
        let forceTestDisabled: Bool
        let errors: [String]
    }

    private struct ReadbackMismatch: Error, LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    private let smcFactory: @Sendable () throws -> any SMCConnection
    private let unlockTimeoutSeconds: TimeInterval
    private let unlockRetryIntervalSeconds: TimeInterval
    private let monotonicNow: @Sendable () -> TimeInterval
    private let sleep: @Sendable (TimeInterval) -> Void

    public init() {
        self.init(smcFactory: { try SMCClient() })
    }

    package init(
        smcFactory: @escaping @Sendable () throws -> any SMCConnection,
        unlockTimeoutSeconds: TimeInterval = 10,
        unlockRetryIntervalSeconds: TimeInterval = 0.1,
        monotonicNow: @escaping @Sendable () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        sleep: @escaping @Sendable (TimeInterval) -> Void = {
            Thread.sleep(forTimeInterval: $0)
        }
    ) {
        self.smcFactory = smcFactory
        self.unlockTimeoutSeconds = max(0, unlockTimeoutSeconds)
        self.unlockRetryIntervalSeconds = max(0, unlockRetryIntervalSeconds)
        self.monotonicNow = monotonicNow
        self.sleep = sleep
    }

    @discardableResult
    public func apply(_ command: FanCommand, fan: Fan) throws -> FanMutationReceipt {
        try validateFanID(fan.id)
        guard command.fanID == fan.id else {
            throw ViftyError.helperRejected(
                "Fan command ID \(command.fanID) does not match hardware fan ID \(fan.id)"
            )
        }

        switch command.mode {
        case .fixedRPM(let rpm):
            try validateFixedWritableFan(fan)
            return try applyFixedRPM(
                FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM),
                fan: fan
            )
        case .temperatureCurve(let curve):
            throw ViftyError.helperRejected(
                "Curve commands must be resolved to fixed RPM before reaching the helper. \(curve.points.count) points were provided."
            )
        case .auto:
            return try restoreAuto(fan: fan)
        }
    }

    @discardableResult
    public func restoreAuto(fan: Fan) throws -> FanMutationReceipt {
        try validateFanID(fan.id)
        guard fan.controlEligibility.canRestoreOSManagedMode else {
            throw ViftyError.helperRejected(
                "Fan \(fan.id) lacks trusted mode telemetry for Auto recovery."
            )
        }

        let smc = try smcFactory()
        let plan = try preflight(fan: fan, requestedRPM: nil, smc: smc)
        var warnings = plan.warnings

        do {
            try perform(plan.automaticMode, smc: smc)

            if let hygieneTarget = plan.hygieneTarget {
                do {
                    try perform(hygieneTarget, smc: smc)
                } catch {
                    warnings.append(
                        "Target reset was skipped after OS-managed mode was requested: \(describe(error))."
                    )
                }
            }

            if let forceTestDisable = plan.forceTestDisable {
                try perform(forceTestDisable, smc: smc)
            }

            let observation = observe(plan: plan, smc: smc)
            guard recoveryObservationErrors(observation).isEmpty,
                  isOSManaged(observation.mode),
                  observation.forceTestDisabled else {
                throw ReadbackMismatch(
                    message: readbackMessage(
                        expected: "Auto or System",
                        observation: observation
                    )
                )
            }

            return receipt(
                plan: plan,
                requestedMode: .automatic,
                observation: observation,
                recoveryConfirmed: true,
                warnings: warnings
            )
        } catch {
            try failAfterMutation(
                primaryError: error,
                requestedMode: .automatic,
                plan: plan,
                smc: smc,
                warnings: warnings
            )
        }
    }

    private func applyFixedRPM(
        _ rpm: Int,
        fan: Fan
    ) throws -> FanMutationReceipt {
        let smc = try smcFactory()
        let plan = try preflight(fan: fan, requestedRPM: rpm, smc: smc)

        do {
            let usedForceTest = try enterManualMode(plan: plan, smc: smc)
            guard let requestedTarget = plan.requestedTarget else {
                throw ViftyError.helperRejected("Fixed-RPM preflight produced no target write.")
            }
            try perform(requestedTarget, smc: smc)

            if (usedForceTest || !plan.forceTestInitiallyDisabled),
               let forceTestDisable = plan.forceTestDisable {
                try perform(forceTestDisable, smc: smc)
            }

            let observation = observe(plan: plan, smc: smc)
            guard observation.errors.isEmpty,
                  observation.mode == .forced,
                  observation.targetRPM == rpm,
                  observation.forceTestDisabled else {
                throw ReadbackMismatch(
                    message: readbackMessage(
                        expected: "Forced at \(rpm) RPM with Ftst disabled",
                        observation: observation
                    )
                )
            }

            return receipt(
                plan: plan,
                requestedMode: .forced,
                observation: observation,
                recoveryConfirmed: false,
                warnings: plan.warnings
            )
        } catch {
            try failAfterMutation(
                primaryError: error,
                requestedMode: .forced,
                plan: plan,
                smc: smc,
                warnings: plan.warnings
            )
        }
    }

    private func preflight(
        fan: Fan,
        requestedRPM: Int?,
        smc: any SMCConnection
    ) throws -> MutationPlan {
        let modeValue = try resolveModeValue(fan: fan, smc: smc)
        guard let currentModeByte = SMCDecoding.decodeFanControlByte(modeValue),
              let currentMode = FanHardwareMode(rawValue: Int(currentModeByte)),
              !isUnknown(currentMode),
              let manualBytes = SMCDecoding.encodeFanControlByte(
                  1,
                  dataType: modeValue.dataType,
                  size: modeValue.bytes.count
              ), let automaticBytes = SMCDecoding.encodeFanControlByte(
                  0,
                  dataType: modeValue.dataType,
                  size: modeValue.bytes.count
              ) else {
            throw unsupportedLayout(value: modeValue, purpose: "fan mode")
        }

        let targetKey = SMCFanControlKeys.targetKey(forFanID: fan.id)
        let targetValue: SMCValue?
        var warnings: [String] = []
        if requestedRPM != nil {
            targetValue = try smc.read(targetKey)
        } else {
            do {
                targetValue = try smc.read(targetKey)
            } catch ViftyError.smcKeyUnavailable {
                targetValue = nil
                warnings.append("Target key \(targetKey) is unavailable; Auto recovery is mode-only.")
            }
        }

        let requestedTarget: PreparedWrite?
        if let requestedRPM, let targetValue {
            guard let bytes = SMCDecoding.encodeFanTargetRPM(
                requestedRPM,
                dataType: targetValue.dataType,
                size: targetValue.bytes.count
            ) else {
                throw unsupportedLayout(value: targetValue, purpose: "fan target")
            }
            requestedTarget = PreparedWrite(
                key: targetValue.key,
                dataType: targetValue.dataType,
                bytes: bytes
            )
        } else {
            requestedTarget = nil
        }

        let hygieneTarget: PreparedWrite?
        let minimumRPMIsTrusted = !fan.controlEligibility.reasons.contains(.missingMinimumRPM)
            && !fan.controlEligibility.reasons.contains(.invalidRPMRange)
        if let targetValue,
           minimumRPMIsTrusted,
           fan.minimumRPM >= 0,
           fan.maximumRPM > fan.minimumRPM {
            if let bytes = SMCDecoding.encodeFanTargetRPM(
                fan.minimumRPM,
                dataType: targetValue.dataType,
                size: targetValue.bytes.count
            ) {
                hygieneTarget = PreparedWrite(
                    key: targetValue.key,
                    dataType: targetValue.dataType,
                    bytes: bytes
                )
            } else if requestedRPM != nil {
                throw unsupportedLayout(value: targetValue, purpose: "fan target")
            } else {
                hygieneTarget = nil
                warnings.append(
                    "Target key \(targetKey) has an unsupported layout; Auto recovery is mode-only."
                )
            }
        } else {
            hygieneTarget = nil
            if requestedRPM == nil, targetValue != nil {
                warnings.append("Target reset was skipped because no trusted minimum RPM is available.")
            }
        }

        let forceTestValue: SMCValue?
        do {
            forceTestValue = try smc.read("Ftst")
        } catch ViftyError.smcKeyUnavailable {
            forceTestValue = nil
        }

        let forceTestEnable: PreparedWrite?
        let forceTestDisable: PreparedWrite?
        let forceTestInitiallyDisabled: Bool
        if let forceTestValue {
            guard let enableBytes = SMCDecoding.encodeFanControlByte(
                1,
                dataType: forceTestValue.dataType,
                size: forceTestValue.bytes.count
            ), let disableBytes = SMCDecoding.encodeFanControlByte(
                0,
                dataType: forceTestValue.dataType,
                size: forceTestValue.bytes.count
            ), let decoded = SMCDecoding.decodeFanControlByte(forceTestValue),
               decoded <= 1 else {
                throw unsupportedLayout(value: forceTestValue, purpose: "force-test")
            }
            forceTestEnable = PreparedWrite(
                key: forceTestValue.key,
                dataType: forceTestValue.dataType,
                bytes: enableBytes
            )
            forceTestDisable = PreparedWrite(
                key: forceTestValue.key,
                dataType: forceTestValue.dataType,
                bytes: disableBytes
            )
            forceTestInitiallyDisabled = decoded == 0
        } else {
            forceTestEnable = nil
            forceTestDisable = nil
            forceTestInitiallyDisabled = true
        }

        return MutationPlan(
            fanID: fan.id,
            modeKey: modeValue.key,
            manualMode: PreparedWrite(
                key: modeValue.key,
                dataType: modeValue.dataType,
                bytes: manualBytes
            ),
            automaticMode: PreparedWrite(
                key: modeValue.key,
                dataType: modeValue.dataType,
                bytes: automaticBytes
            ),
            requestedTarget: requestedTarget,
            hygieneTarget: hygieneTarget,
            forceTestEnable: forceTestEnable,
            forceTestDisable: forceTestDisable,
            forceTestInitiallyDisabled: forceTestInitiallyDisabled,
            warnings: warnings
        )
    }

    private func enterManualMode(
        plan: MutationPlan,
        smc: any SMCConnection
    ) throws -> Bool {
        do {
            try perform(plan.manualMode, smc: smc)
            return false
        } catch {
            let directError = error
            guard let forceTestEnable = plan.forceTestEnable else {
                throw directError
            }

            do {
                try perform(forceTestEnable, smc: smc)
            } catch {
                throw ViftyError.helperRejected(
                    "Manual mode write failed (\(describe(directError))); Ftst unlock failed (\(describe(error)))."
                )
            }

            let deadline = monotonicNow() + unlockTimeoutSeconds
            var lastError = directError
            while true {
                do {
                    try perform(plan.manualMode, smc: smc)
                    return true
                } catch {
                    lastError = error
                }

                guard monotonicNow() < deadline,
                      unlockRetryIntervalSeconds > 0 else {
                    break
                }
                sleep(unlockRetryIntervalSeconds)
            }

            throw ViftyError.helperRejected(
                "Fan control remained protected after Ftst unlock attempt: \(describe(lastError))"
            )
        }
    }

    private func failAfterMutation(
        primaryError: Error,
        requestedMode: FanHardwareMode,
        plan: MutationPlan,
        smc: any SMCConnection,
        warnings: [String]
    ) throws -> Never {
        var cleanupErrors: [String] = []
        var receiptWarnings = warnings

        do {
            try perform(plan.automaticMode, smc: smc)
        } catch {
            cleanupErrors.append("Auto mode cleanup failed: \(describe(error))")
        }

        if let hygieneTarget = plan.hygieneTarget {
            do {
                try perform(hygieneTarget, smc: smc)
            } catch {
                let warning = "Target hygiene failed: \(describe(error))"
                cleanupErrors.append(warning)
                receiptWarnings.append(warning)
            }
        }

        if let forceTestDisable = plan.forceTestDisable {
            do {
                try perform(forceTestDisable, smc: smc)
            } catch {
                cleanupErrors.append("Ftst cleanup failed: \(describe(error))")
            }
        }

        let observation = observe(plan: plan, smc: smc)
        cleanupErrors.append(contentsOf: observation.errors)
        if !isOSManaged(observation.mode) {
            cleanupErrors.append(
                "Auto cleanup readback observed \(observation.mode?.displayName ?? "missing mode")."
            )
        }
        if !observation.forceTestDisabled {
            cleanupErrors.append("Auto cleanup could not confirm Ftst=0.")
        }

        let recoveryConfirmed = isOSManaged(observation.mode)
            && observation.forceTestDisabled
            && observation.errors.allSatisfy { !$0.hasPrefix("Mode readback") && !$0.hasPrefix("Ftst readback") }
        let mutationReceipt = receipt(
            plan: plan,
            requestedMode: requestedMode,
            observation: observation,
            recoveryConfirmed: recoveryConfirmed,
            warnings: receiptWarnings
        )
        let code: FanMutationErrorCode
        if !recoveryConfirmed {
            code = .recoveryUnconfirmed
        } else if primaryError is ReadbackMismatch {
            code = .readbackMismatch
        } else {
            code = .mutationFailed
        }

        throw FanMutationError(
            code: code,
            primaryError: describe(primaryError),
            cleanupErrors: cleanupErrors,
            receipt: mutationReceipt
        )
    }

    private func observe(
        plan: MutationPlan,
        smc: any SMCConnection
    ) -> Observation {
        var mode: FanHardwareMode?
        var targetRPM: Int?
        var forceTestDisabled = plan.forceTestDisable == nil
        var errors: [String] = []

        do {
            let value = try smc.read(plan.modeKey)
            if let decoded = SMCDecoding.decodeFanControlByte(value) {
                mode = FanHardwareMode(rawValue: Int(decoded))
            } else {
                errors.append("Mode readback could not decode \(value.key).")
            }
        } catch {
            errors.append("Mode readback failed: \(describe(error))")
        }

        if let targetKey = plan.requestedTarget?.key ?? plan.hygieneTarget?.key {
            do {
                let value = try smc.read(targetKey)
                if let decoded = SMCDecoding.decodeFanTargetRPM(value) {
                    targetRPM = decoded
                } else {
                    errors.append("Target readback could not decode \(targetKey).")
                }
            } catch {
                errors.append("Target readback failed: \(describe(error))")
            }
        }

        if plan.forceTestDisable != nil {
            do {
                let value = try smc.read("Ftst")
                if let decoded = SMCDecoding.decodeFanControlByte(value) {
                    forceTestDisabled = decoded == 0
                } else {
                    errors.append("Ftst readback could not be decoded.")
                }
            } catch {
                errors.append("Ftst readback failed: \(describe(error))")
            }
        }

        return Observation(
            mode: mode,
            targetRPM: targetRPM,
            forceTestDisabled: forceTestDisabled,
            errors: errors
        )
    }

    private func receipt(
        plan: MutationPlan,
        requestedMode: FanHardwareMode,
        observation: Observation,
        recoveryConfirmed: Bool,
        warnings: [String]
    ) -> FanMutationReceipt {
        FanMutationReceipt(
            fanID: plan.fanID,
            requestedMode: requestedMode,
            observedMode: observation.mode,
            observedTargetRPM: observation.targetRPM,
            forceTestDisabled: observation.forceTestDisabled,
            recoveryConfirmed: recoveryConfirmed,
            warnings: warnings + observation.errors
        )
    }

    private func perform(
        _ write: PreparedWrite,
        smc: any SMCConnection
    ) throws {
        try smc.write(write.key, dataType: write.dataType, bytes: write.bytes)
    }

    private func resolveModeValue(
        fan: Fan,
        smc: any SMCConnection
    ) throws -> SMCValue {
        let candidates = SMCFanControlKeys.modeKeyCandidates(forFanID: fan.id)
        if let hardwareModeKey = fan.hardwareModeKey {
            guard candidates.contains(hardwareModeKey) else {
                throw ViftyError.helperRejected(
                    "Fan \(fan.id) reported invalid mode key \(hardwareModeKey)."
                )
            }
            return try smc.read(hardwareModeKey)
        }

        var lastError: Error?
        for key in candidates {
            do {
                return try smc.read(key)
            } catch {
                lastError = error
            }
        }
        if let lastError {
            throw lastError
        }
        throw ViftyError.smcKeyUnavailable(
            candidates[0]
        )
    }

    private func validateFanID(_ fanID: Int) throws {
        guard SMCFanControlKeys.isValidFanID(fanID) else {
            throw ViftyError.helperRejected(
                "Invalid fan ID \(fanID); SMC fan IDs must be 0 through 9."
            )
        }
    }

    private func validateFixedWritableFan(_ fan: Fan) throws {
        guard fan.controllable,
              fan.controlEligibility.canApplyFixedRPM,
              fan.maximumRPM > fan.minimumRPM else {
            throw ViftyError.noControllableFans
        }
    }

    private func unsupportedLayout(
        value: SMCValue,
        purpose: String
    ) -> ViftyError {
        .helperRejected(
            "Unsupported \(purpose) layout for \(value.key): type \(value.dataType), size \(value.bytes.count)."
        )
    }

    private func readbackMessage(
        expected: String,
        observation: Observation
    ) -> String {
        let details = [
            "expected \(expected)",
            "observed mode \(observation.mode?.displayName ?? "missing")",
            "target \(observation.targetRPM.map(String.init) ?? "missing")",
            "Ftst disabled \(observation.forceTestDisabled)",
            observation.errors.joined(separator: "; ")
        ].filter { !$0.isEmpty }
        return details.joined(separator: ", ")
    }

    private func isOSManaged(_ mode: FanHardwareMode?) -> Bool {
        mode == .automatic || mode == .system
    }

    private func recoveryObservationErrors(_ observation: Observation) -> [String] {
        observation.errors.filter {
            $0.hasPrefix("Mode readback") || $0.hasPrefix("Ftst readback")
        }
    }

    private func isUnknown(_ mode: FanHardwareMode) -> Bool {
        if case .unknown = mode { return true }
        return false
    }

    private func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
