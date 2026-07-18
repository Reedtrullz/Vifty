import Foundation

public enum HardwareSnapshotProbeFormatter {
    public static func lines(for snapshot: HardwareSnapshot) -> [String] {
        var lines = [
            "model=\(snapshot.modelIdentifier) appleSilicon=\(snapshot.isAppleSilicon) macBookPro=\(snapshot.isMacBookPro)",
            "fans=\(snapshot.fans.count)"
        ]

        for fan in snapshot.fans {
            lines.append(line(for: fan))
        }

        lines.append("temperatures=\(snapshot.temperatureSensors.count)")
        for sensor in snapshot.temperatureSensors {
            lines.append(line(for: sensor))
        }

        return lines
    }

    public static func string(for snapshot: HardwareSnapshot) -> String {
        lines(for: snapshot).joined(separator: "\n")
    }

    private static func line(for fan: Fan) -> String {
        let hardwareMode = fan.hardwareMode?.displayName ?? "unknown"
        let hardwareModeRawValue = fan.hardwareMode.map { String($0.rawValue) } ?? "nil"
        let hardwareModeKey = fan.hardwareModeKey ?? "nil"
        let targetRPM = fan.targetRPM.map(String.init) ?? "nil"
        let reasons = fan.controlEligibility.reasons.map(\.rawValue).joined(separator: ",")
        return "fan[\(fan.id)] name=\"\(fan.name)\" rpm=\(fan.currentRPM) min=\(fan.minimumRPM) max=\(fan.maximumRPM) controllable=\(fan.controllable) hardwareMode=\(hardwareMode) hardwareModeRawValue=\(hardwareModeRawValue) hardwareModeKey=\(hardwareModeKey) targetRPM=\(targetRPM) canApplyFixedRPM=\(fan.controlEligibility.canApplyFixedRPM) canRestoreOSManagedMode=\(fan.controlEligibility.canRestoreOSManagedMode) controlIneligibilityReasons=\(reasons.isEmpty ? "none" : reasons)"
    }

    private static func line(for sensor: TemperatureSensor) -> String {
        "temp[\(sensor.id)] name=\"\(sensor.name)\" celsius=\(String(format: "%.1f", sensor.celsius)) source=\(sensor.source.rawValue)"
    }
}
