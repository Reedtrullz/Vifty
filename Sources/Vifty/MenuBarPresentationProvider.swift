import Foundation
import ViftyCore

struct MenuBarPresentationInput: Equatable {
    var displayMode: MenuBarDisplayMode
    var customFields: [MenuBarField]
    var snapshotIsAvailable: Bool
    var selectedTemperature: TemperatureSensor?
    var selectedTemperatureLabel: String?
    var fans: [Fan]
    var power: PowerSnapshot?
    var thermalPressure: ThermalPressure
    var temperatureAttentionSummary: String?
    var fanWriteBlockedWhileHotSummary: String?
    var helperState: HelperHealthState
    var hasCompletedHardwarePoll: Bool
    var daemonReachable: Bool
    var daemonResponding: Bool
    var lastErrorIsPresent: Bool
    var agentCoolingMenuSummary: String?
    var agentStatusIsUnavailable: Bool
    var shouldPreferHelperRecoveryOverAgentStatusError: Bool
    var hasAgentLease: Bool
    var agentLeaseNeedsAttention: Bool
    var fanControlOwnershipStatus: FanControlOwnershipStatus?
    var controlMode: FanMode
    var controlOwnershipNeedsAttention: Bool
    var autoHardwareModeIsUncertain: Bool
    var codexUsageSnapshot: CodexUsageSnapshot?
    var codexUsageDisplayPreferences: CodexUsageDisplayPreferences
    var currentDate: Date
}

struct MenuBarPresentation: Equatable {
    var title: String
    var panelTitle: String
    var labelText: String
    var statusItemText: String?
    var fanOwnerText: String
    var labelNeedsTelemetryPrime: Bool
    var displaysCodexUsage: Bool
    var allowsPlaceholderStatusItemText: Bool
    var labelUsesFanIcon: Bool
    var panelAttentionText: String?
    var statusItemPresentation: MenuBarStatusItemPresentation
}

enum MenuBarPresentationProvider {
    static func resolve(_ input: MenuBarPresentationInput) -> MenuBarPresentation {
        let displaysCodexUsage = displaysCodexUsage(
            input.displayMode,
            customFields: input.customFields
        )
        let allowsPlaceholderText = displaysCodexUsage && input.hasCompletedHardwarePoll
        let helperAttentionIsActionable = input.helperState.needsAttention
            && (input.hasCompletedHardwarePoll
                || input.daemonReachable
                || input.daemonResponding
                || input.agentStatusIsUnavailable
                || input.lastErrorIsPresent)
        let fanOwnerText = FanControlOwnershipPresentation
            .resolve(input.fanControlOwnershipStatus)
            .conciseOwnerText
        let temperatureText = input.selectedTemperature.map { "\(Int($0.celsius.rounded())) C" }
        let temperatureDetailText = temperatureText.map { temperatureText in
            guard let label = input.selectedTemperatureLabel, !label.isEmpty else {
                return temperatureText
            }
            return "\(label) \(temperatureText)"
        }
        let fanText = input.fans.first.map { "\($0.currentRPM) RPM" }
        let fanStrengthText = averageFanStrengthText(input.fans)
        let averageFanText = averageFanRPMText(input.fans)
        let powerText = input.power.map { PowerDisplayFormatter.summary(for: $0) }
        let metricAttentionSummary: String? = if input.fanWriteBlockedWhileHotSummary != nil {
            "Fan writes blocked"
        } else if helperAttentionIsActionable {
            input.helperState.menuSummary
        } else {
            nil
        }

        func menuSummary(includePower: Bool, detailedTemperature: Bool) -> String {
            var parts: [String]
            if input.snapshotIsAvailable {
                parts = [detailedTemperature ? temperatureDetailText : temperatureText, fanText]
                    .compactMap(\.self)
                if parts.isEmpty {
                    parts = ["Vifty"]
                }
                if includePower, let powerText {
                    parts.append(powerText)
                }
            } else {
                parts = includePower ? [powerText ?? "Vifty"] : ["Vifty"]
            }
            if let thermal = input.thermalPressure.menuSummary {
                parts.append(thermal)
            } else if let temperatureAttentionSummary = input.temperatureAttentionSummary {
                parts.append(temperatureAttentionSummary)
            }
            if input.fanWriteBlockedWhileHotSummary != nil {
                parts.append("Fan writes blocked")
            } else if helperAttentionIsActionable {
                parts.append(input.helperState.menuSummary)
            }
            if let agentCoolingMenuSummary = input.agentCoolingMenuSummary {
                parts.append(agentCoolingMenuSummary)
            }
            return parts.joined(separator: " | ")
        }

        let title = menuSummary(includePower: true, detailedTemperature: true)
        let panelTitle = menuSummary(includePower: false, detailedTemperature: true)

        func text(for field: MenuBarField) -> String? {
            switch field {
            case .owner:
                fanOwnerText
            case .temperature:
                temperatureText ?? "-- C"
            case .fanStrength:
                fanStrengthText ?? "--% fan"
            case .fanRPM:
                fanText ?? "-- RPM"
            case .averageFanRPM:
                averageFanText ?? "-- RPM avg"
            case .adapterWattage:
                powerText ?? "-- W"
            case .codexUsage:
                CodexUsageFormatter.menuBarText(
                    for: input.codexUsageSnapshot,
                    options: input.codexUsageDisplayPreferences,
                    now: { input.currentDate }
                )
            }
        }

        func labelWithAttention(_ label: String) -> String {
            guard let metricAttentionSummary,
                  !label.contains(metricAttentionSummary) else {
                return label
            }
            return "\(label) | \(metricAttentionSummary)"
        }

        let customParts = input.customFields.compactMap { text(for: $0) }
        let customLabel = customParts.isEmpty ? title : customParts.joined(separator: " | ")
        let labelText: String = switch input.displayMode {
        case .fanIcon:
            title
        case .temperature:
            labelWithAttention(temperatureText ?? "-- C")
        case .fanRPM:
            labelWithAttention(fanText ?? "-- RPM")
        case .averageFanRPM:
            labelWithAttention(averageFanText ?? "-- RPM avg")
        case .adapterWattage:
            labelWithAttention(powerText ?? "-- W")
        case .codexUsage:
            CodexUsageFormatter.menuBarText(
                for: input.codexUsageSnapshot,
                options: input.codexUsageDisplayPreferences,
                now: { input.currentDate }
            )
        case .custom:
            labelWithAttention(customLabel)
        case .temperatureAndRPM:
            labelWithAttention("\(temperatureText ?? "-- C") | \(fanText ?? "-- RPM")")
        case .ownerTemperatureAndRPM:
            labelWithAttention([
                fanOwnerText,
                temperatureText ?? "-- C",
                fanText ?? "-- RPM"
            ].joined(separator: " | "))
        case .compactSummary:
            menuSummary(includePower: true, detailedTemperature: false)
        }

        let needsTelemetryPrime: Bool
        if !input.hasCompletedHardwarePoll {
            needsTelemetryPrime = true
        } else if input.displayMode == .codexUsage {
            needsTelemetryPrime = false
        } else if input.displayMode == .custom {
            needsTelemetryPrime = input.customFields.contains { field in
                field.requiresHardwareTelemetry && (text(for: field)?.contains("--") ?? false)
            }
        } else {
            needsTelemetryPrime = labelText.contains("--")
        }

        let labelUsesFanIcon = input.displayMode == .fanIcon
        let accessibilityLabel = if let temperatureText, let temperatureDetailText,
                                    !labelText.contains(temperatureDetailText) {
            labelText.replacingOccurrences(of: temperatureText, with: temperatureDetailText)
        } else {
            labelText
        }
        let statusItemText: String? = if labelUsesFanIcon {
            nil
        } else if allowsPlaceholderText || !labelText.contains("--") {
            labelText
        } else {
            nil
        }
        let resolvedStatusItemText = ViftyStatusItemPresentation.resolvedText(
            statusItemText: statusItemText,
            fallbackStatusItemText: labelUsesFanIcon ? nil : labelText,
            labelNeedsTelemetryPrime: needsTelemetryPrime,
            allowsPlaceholderText: allowsPlaceholderText
        )
        let content: MenuBarStatusItemPresentation.Content = if let resolvedStatusItemText {
            .text(resolvedStatusItemText)
        } else {
            .fanIcon(accessibilityDescription: accessibilityLabel)
        }

        return MenuBarPresentation(
            title: title,
            panelTitle: panelTitle,
            labelText: labelText,
            statusItemText: statusItemText,
            fanOwnerText: fanOwnerText,
            labelNeedsTelemetryPrime: needsTelemetryPrime,
            displaysCodexUsage: displaysCodexUsage,
            allowsPlaceholderStatusItemText: allowsPlaceholderText,
            labelUsesFanIcon: labelUsesFanIcon,
            panelAttentionText: input.fanWriteBlockedWhileHotSummary
                ?? input.thermalPressure.menuSummary
                ?? input.temperatureAttentionSummary,
            statusItemPresentation: MenuBarStatusItemPresentation(
                content: content,
                tooltip: title,
                accessibilityLabel: accessibilityLabel,
                needsTelemetryPrime: needsTelemetryPrime
            )
        )
    }

    static func displaysCodexUsage(
        _ mode: MenuBarDisplayMode,
        customFields: [MenuBarField]
    ) -> Bool {
        switch mode {
        case .codexUsage:
            true
        case .custom:
            customFields.contains(.codexUsage)
        case .fanIcon, .temperature, .fanRPM, .averageFanRPM, .adapterWattage,
             .temperatureAndRPM, .ownerTemperatureAndRPM, .compactSummary:
            false
        }
    }

    private static func averageFanStrengthText(_ fans: [Fan]) -> String? {
        guard !fans.isEmpty else { return nil }
        let average = Double(fans.reduce(0) { $0 + $1.percentage }) / Double(fans.count)
        return "\(Int(average.rounded()))% fan"
    }

    private static func averageFanRPMText(_ fans: [Fan]) -> String? {
        guard !fans.isEmpty else { return nil }
        let average = Double(fans.reduce(0) { $0 + $1.currentRPM }) / Double(fans.count)
        return "\(Int(average.rounded())) RPM avg"
    }
}
