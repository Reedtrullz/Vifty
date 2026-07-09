import Foundation

enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable {
    case fanIcon
    case temperature
    case fanRPM
    case averageFanRPM
    case adapterWattage
    case codexUsage
    case custom
    case temperatureAndRPM
    case ownerTemperatureAndRPM
    case compactSummary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fanIcon:
            return "Icon only"
        case .temperature:
            return "Temperature"
        case .fanRPM:
            return "Fan RPM"
        case .averageFanRPM:
            return "Average fan RPM"
        case .adapterWattage:
            return "Adapter wattage"
        case .codexUsage:
            return "Codex usage"
        case .custom:
            return "Custom"
        case .temperatureAndRPM:
            return "Temperature + RPM"
        case .ownerTemperatureAndRPM:
            return "Owner + Temp/RPM"
        case .compactSummary:
            return "Compact summary"
        }
    }
}

enum MenuBarField: String, Codable, CaseIterable, Identifiable {
    case owner
    case temperature
    case fanStrength
    case fanRPM
    case averageFanRPM
    case adapterWattage
    case codexUsage

    var id: String { rawValue }

    static let defaultCustomFields: [MenuBarField] = [.temperature, .fanStrength, .codexUsage]

    var label: String {
        switch self {
        case .owner:
            return "Owner"
        case .temperature:
            return "Temperature"
        case .fanStrength:
            return "Fan %"
        case .fanRPM:
            return "Fan RPM"
        case .averageFanRPM:
            return "Average RPM"
        case .adapterWattage:
            return "Adapter"
        case .codexUsage:
            return "Codex quota"
        }
    }

    var requiresHardwareTelemetry: Bool {
        self != .codexUsage
    }

    static func orderedUnique(_ fields: [MenuBarField]) -> [MenuBarField] {
        allCases.filter { field in fields.contains(field) }
    }

    static func normalized(_ fields: [MenuBarField]) -> [MenuBarField] {
        let unique = orderedUnique(fields)
        return unique.isEmpty ? defaultCustomFields : unique
    }
}

struct MenuBarStatusItemPresentation: Equatable {
    enum Content: Equatable {
        case fanIcon(accessibilityDescription: String)
        case text(String)
    }

    var content: Content
    var tooltip: String
    var accessibilityLabel: String
    var needsTelemetryPrime: Bool

    static let placeholder = MenuBarStatusItemPresentation(
        content: .fanIcon(accessibilityDescription: "Vifty"),
        tooltip: "Vifty",
        accessibilityLabel: "Vifty",
        needsTelemetryPrime: true
    )
}

enum ViftyStatusItemPresentation {
    static func resolvedText(
        statusItemText: String?,
        fallbackStatusItemText: String? = nil,
        labelNeedsTelemetryPrime: Bool,
        allowsPlaceholderText: Bool
    ) -> String? {
        guard !labelNeedsTelemetryPrime else {
            return fallbackStatusItemText
        }
        guard let statusItemText else {
            return fallbackStatusItemText
        }
        guard allowsPlaceholderText || !statusItemText.contains("--") else { return fallbackStatusItemText }
        return statusItemText
    }
}
