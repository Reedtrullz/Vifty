import Foundation

public protocol SMCConnection: Sendable {
    func read(_ key: String) throws -> SMCValue
    func write(_ key: String, dataType: String, bytes: [UInt8]) throws
}

extension SMCClient: SMCConnection {}

public struct LocalFanHelperClient: Sendable {
    private struct ResolvedModeKey {
        var key: String
        var dataType: String
        var size: Int
    }

    private let smcFactory: @Sendable () throws -> any SMCConnection
    private let unlockTimeoutSeconds: TimeInterval
    private let unlockRetryIntervalSeconds: TimeInterval

    public init(
        smcFactory: @escaping @Sendable () throws -> any SMCConnection = { try SMCClient() },
        unlockTimeoutSeconds: TimeInterval = 10,
        unlockRetryIntervalSeconds: TimeInterval = 0.1
    ) {
        self.smcFactory = smcFactory
        self.unlockTimeoutSeconds = unlockTimeoutSeconds
        self.unlockRetryIntervalSeconds = unlockRetryIntervalSeconds
    }

    public func apply(_ command: FanCommand, fan: Fan) throws {
        try validateFanID(fan.id)
        guard fan.controllable, fan.maximumRPM > fan.minimumRPM else {
            throw ViftyError.noControllableFans
        }
        guard command.fanID == fan.id else {
            throw ViftyError.helperRejected("Fan command ID \(command.fanID) does not match hardware fan ID \(fan.id)")
        }

        switch command.mode {
        case .fixedRPM(let rpm):
            let clamped = FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
            try writeFixedRPM(clamped, fanID: fan.id)
        case .temperatureCurve(let curve):
            throw ViftyError.helperRejected("Curve commands must be resolved to fixed RPM before reaching the helper. \(curve.points.count) points were provided.")
        case .auto:
            try restoreAuto(fan: fan)
        }
    }

    public func restoreAuto(fan: Fan) throws {
        try validateFanID(fan.id)
        let smc = try smcFactory()
        let modeKey = try resolveModeKey(fanID: fan.id, smc: smc)
        // Common SMC convention: F{n}Md = 0 returns a fan to automatic mode.
        try writeMode(0, modeKey: modeKey, smc: smc)
        let targetInfo = try smc.read(SMCFanControlKeys.targetKey(forFanID: fan.id))
        try smc.write(
            SMCFanControlKeys.targetKey(forFanID: fan.id),
            dataType: targetInfo.dataType,
            bytes: SMCDecoding.encodeRPM(fan.minimumRPM, dataType: targetInfo.dataType, size: targetInfo.bytes.count)
        )
        try disableForceTestIfAvailable(smc: smc)
    }

    private func writeFixedRPM(_ rpm: Int, fanID: Int) throws {
        let smc = try smcFactory()
        let modeKey = try resolveModeKey(fanID: fanID, smc: smc)
        // Common SMC convention: F{n}Md = 1 enables forced/manual mode and F{n}Tg stores target RPM as fpe2.
        do {
            try writeMode(1, modeKey: modeKey, smc: smc)
        } catch {
            try unlockManualControl(modeKey: modeKey, smc: smc, triggeringError: error)
        }

        let targetInfo = try smc.read(SMCFanControlKeys.targetKey(forFanID: fanID))
        try smc.write(
            SMCFanControlKeys.targetKey(forFanID: fanID),
            dataType: targetInfo.dataType,
            bytes: SMCDecoding.encodeRPM(rpm, dataType: targetInfo.dataType, size: targetInfo.bytes.count)
        )
    }

    private func validateFanID(_ fanID: Int) throws {
        guard SMCFanControlKeys.isValidFanID(fanID) else {
            throw ViftyError.helperRejected("Invalid fan ID \(fanID); SMC fan IDs must be 0 through 9.")
        }
    }

    private func resolveModeKey(fanID: Int, smc: any SMCConnection) throws -> ResolvedModeKey {
        var lastError: Error?
        for key in SMCFanControlKeys.modeKeyCandidates(forFanID: fanID) {
            do {
                let value = try smc.read(key)
                return ResolvedModeKey(key: key, dataType: value.dataType, size: value.bytes.count)
            } catch {
                lastError = error
            }
        }
        if let lastError {
            throw lastError
        }
        throw ViftyError.smcKeyUnavailable(SMCFanControlKeys.modeKeyCandidates(forFanID: fanID)[0])
    }

    private func writeMode(_ mode: UInt8, modeKey: ResolvedModeKey, smc: any SMCConnection) throws {
        try smc.write(
            modeKey.key,
            dataType: modeKey.dataType,
            bytes: encodeByte(mode, dataType: modeKey.dataType, size: modeKey.size)
        )
    }

    private func unlockManualControl(
        modeKey: ResolvedModeKey,
        smc: any SMCConnection,
        triggeringError: Error
    ) throws {
        do {
            try writeForceTest(1, smc: smc)
        } catch ViftyError.smcKeyUnavailable {
            throw triggeringError
        } catch {
            throw triggeringError
        }

        let deadline = Date().addingTimeInterval(unlockTimeoutSeconds)
        var lastError = triggeringError
        repeat {
            do {
                try writeMode(1, modeKey: modeKey, smc: smc)
                return
            } catch {
                lastError = error
            }
            if unlockRetryIntervalSeconds > 0 {
                Thread.sleep(forTimeInterval: unlockRetryIntervalSeconds)
            }
        } while Date() < deadline

        throw ViftyError.helperRejected("Fan control remained protected after Ftst unlock attempt: \(lastError.localizedDescription)")
    }

    private func disableForceTestIfAvailable(smc: any SMCConnection) throws {
        do {
            try writeForceTest(0, smc: smc)
        } catch ViftyError.smcKeyUnavailable {
            return
        }
    }

    private func writeForceTest(_ value: UInt8, smc: any SMCConnection) throws {
        let forceTest = try smc.read("Ftst")
        try smc.write(
            "Ftst",
            dataType: forceTest.dataType,
            bytes: encodeByte(value, dataType: forceTest.dataType, size: forceTest.bytes.count)
        )
    }

    private func encodeByte(_ value: UInt8, dataType: String, size: Int) -> [UInt8] {
        if dataType == "flt " || size == 4 {
            var float = Float(value)
            return withUnsafeBytes(of: &float) { Array($0) }
        }
        if size == 2 {
            return [0, value]
        }
        return [value]
    }
}
