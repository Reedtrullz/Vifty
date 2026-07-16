import Foundation

public struct AgentControlPolicy: Equatable, Sendable {
    public var enabled: Bool
    public var minimumAgentRPMPercent: Int
    public var maximumAllowedRPMPercent: Int
    public var maxDurationSeconds: Int
    public var prepareCooldownSeconds: Int

    public init(enabled: Bool = false, minimumAgentRPMPercent: Int = 35, maximumAllowedRPMPercent: Int = 80, maxDurationSeconds: Int = 30 * 60, prepareCooldownSeconds: Int = 30) {
        self.enabled = enabled
        self.minimumAgentRPMPercent = minimumAgentRPMPercent
        self.maximumAllowedRPMPercent = maximumAllowedRPMPercent
        self.maxDurationSeconds = maxDurationSeconds
        self.prepareCooldownSeconds = prepareCooldownSeconds
    }

    public var snapshot: AgentControlPolicySnapshot {
        AgentControlPolicySnapshot(
            enabled: enabled,
            minimumAgentRPMPercent: minimumAgentRPMPercent,
            maximumAllowedRPMPercent: maximumAllowedRPMPercent,
            maxDurationSeconds: maxDurationSeconds,
            prepareCooldownSeconds: prepareCooldownSeconds
        )
    }

    public func evaluate(_ request: AgentControlRequest, snapshot: HardwareSnapshot, thermalPressure: ThermalPressure) -> AgentControlDecision {
        guard enabled else { return .denied(.disabled, message: "Agent fan control is disabled in Vifty settings.") }
        guard request.metadataValidationFailureMessage == nil else {
            return .denied(
                .invalidArguments,
                message: request.metadataValidationFailureMessage ?? "Agent cooling request metadata is invalid."
            )
        }
        guard snapshot.isAppleSilicon, snapshot.isMacBookPro else { return .denied(.unsupportedHardware, message: "Agent fan control is only supported on Apple Silicon MacBook Pro hardware.") }
        guard thermalPressure != .critical else { return .denied(.thermalCritical, message: "Thermal pressure is critical; the workload should pause or reduce CPU/GPU work instead.") }
        guard !snapshot.temperatureSensors.isEmpty else { return .denied(.temperatureSensorUnavailable, message: "At least one temperature sensor is required before agent fan control can run.") }
        guard request.durationSeconds > 0, request.durationSeconds <= maxDurationSeconds else { return .denied(.durationTooLong, message: "Duration must be between 1 second and \(maxDurationSeconds) seconds.") }
        guard request.maxRPMPercent >= minimumAgentRPMPercent, request.maxRPMPercent <= maximumAllowedRPMPercent else { return .denied(.rpmOutOfRange, message: "RPM percent must be between \(minimumAgentRPMPercent) and \(maximumAllowedRPMPercent).") }

        let physicalFans = snapshot.fans
        guard !physicalFans.isEmpty else {
            return .denied(
                .noControllableFans,
                message: "No fan has trusted telemetry for daemon-owned fixed-RPM control."
            )
        }

        var seenFanIDs = Set<Int>()
        for fan in physicalFans {
            guard seenFanIDs.insert(fan.id).inserted else {
                return .denied(.policyDenied, message: "Physical fan telemetry contains duplicate fan ID \(fan.id).")
            }
            guard SMCFanControlKeys.isValidFanID(fan.id) else {
                return .denied(.policyDenied, message: "Physical fan telemetry contains invalid fan ID \(fan.id); SMC fan IDs must be 0 through 9.")
            }
            guard fan.controlEligibility.canRestoreOSManagedMode else {
                return .denied(
                    .policyDenied,
                    message: "Physical fan telemetry lacks trusted restore-mode eligibility for fan ID \(fan.id)."
                )
            }
        }

        let fixedEligibleFans = physicalFans.filter { $0.controlEligibility.canApplyFixedRPM }
        guard !fixedEligibleFans.isEmpty else {
            return .denied(
                .noControllableFans,
                message: "No fan has trusted telemetry for daemon-owned fixed-RPM control."
            )
        }
        for fan in fixedEligibleFans {
            guard fan.maximumRPM > 0, fan.minimumRPM >= 0, fan.minimumRPM <= fan.maximumRPM else {
                return .denied(.policyDenied, message: "Fixed-eligible fan telemetry contains an invalid RPM range for fan ID \(fan.id).")
            }
        }

        let targets = Dictionary(uniqueKeysWithValues: fixedEligibleFans.map { fan in
            let span = fan.maximumRPM - fan.minimumRPM
            let rpm = fan.minimumRPM + Int((Double(span) * Double(request.maxRPMPercent) / 100.0).rounded())
            return (fan.id, FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM))
        })

        var warnings: [String] = []
        if thermalPressure == .serious {
            warnings.append("Thermal pressure is serious; consider reducing the workload if it rises further.")
        }
        return .allowed(targetRPMByFanID: targets, warnings: warnings)
    }
}
