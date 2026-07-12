import Foundation
import ViftyCore

struct FanStatusPresentation: Equatable {
    let currentText: String
    let targetText: String?
    let deltaText: String?
    let ownershipText: String
    let currentFraction: Double
    let targetFraction: Double?
    let draftTargetText: String?
    let draftTargetFraction: Double?
    let needsAttention: Bool

    static func make(fan: Fan, targetRPM: Int?) -> FanStatusPresentation {
        make(fan: fan, appliedTargetRPM: targetRPM, draftTargetRPM: nil)
    }

    static func make(
        fan: Fan,
        appliedTargetRPM: Int?,
        draftTargetRPM: Int?
    ) -> FanStatusPresentation {
        let currentText = "\(fan.currentRPM) RPM"
        let targetText = appliedTargetRPM.map { "Target \($0) RPM" }
        let targetDeltaText = appliedTargetRPM.map { deltaText(currentRPM: fan.currentRPM, targetRPM: $0) }
        let distinctDraftTargetRPM = draftTargetRPM.flatMap { draftRPM in
            draftRPM == appliedTargetRPM ? nil : draftRPM
        }

        return FanStatusPresentation(
            currentText: currentText,
            targetText: targetText,
            deltaText: targetDeltaText,
            ownershipText: ownershipText(for: fan.hardwareMode),
            currentFraction: fraction(for: fan.currentRPM, in: fan),
            targetFraction: appliedTargetRPM.map { fraction(for: $0, in: fan) },
            draftTargetText: distinctDraftTargetRPM.map { "Draft \($0) RPM" },
            draftTargetFraction: distinctDraftTargetRPM.map { fraction(for: $0, in: fan) },
            needsAttention: fan.hardwareMode == .forced
                && appliedTargetRPM.map { abs(fan.currentRPM - $0) >= 75 } == true
        )
    }

    private static func ownershipText(for mode: FanHardwareMode?) -> String {
        switch mode {
        case .automatic:
            "macOS Auto"
        case .system:
            "macOS System control"
        case .forced:
            "Manual hardware control"
        case .unknown, nil:
            "Hardware mode unknown"
        }
    }

    private static func fraction(for rpm: Int, in fan: Fan) -> Double {
        guard fan.maximumRPM > fan.minimumRPM else { return 0 }
        let fraction = Double(rpm - fan.minimumRPM) / Double(fan.maximumRPM - fan.minimumRPM)
        return min(max(fraction, 0), 1)
    }

    private static func deltaText(currentRPM: Int, targetRPM: Int) -> String {
        let difference = targetRPM - currentRPM
        guard difference != 0 else { return "On target" }
        let direction = difference > 0 ? "below" : "above"
        return "\(abs(difference)) RPM \(direction) target"
    }
}

enum TemperatureDisplayFormatter {
    static func whole(_ temperature: Double) -> String {
        "\(Int(temperature.rounded())) °C"
    }

    static func decimal(_ temperature: Double) -> String {
        String(format: "%.1f °C", temperature)
    }
}
