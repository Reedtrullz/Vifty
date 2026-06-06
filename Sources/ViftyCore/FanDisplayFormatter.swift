import Foundation

public enum FanDisplayFormatter {
    public static func subtitle(for fan: Fan) -> String {
        var parts: [String] = []
        if let hardwareMode = fan.hardwareMode {
            parts.append(hardwareMode.displayName)
        }
        if let targetRPM = fan.targetRPM, fan.hardwareMode == .forced {
            parts.append("Target \(targetRPM) RPM")
        }
        return parts.isEmpty ? "Hardware mode unknown" : parts.joined(separator: " · ")
    }
}
