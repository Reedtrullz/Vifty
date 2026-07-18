import Foundation
import SwiftUI
import ViftyCore

/// Stable application-side identifiers consumed by the separate, non-bundled
/// Accessibility evidence collector. Keep these values byte-for-byte aligned
/// with `AXEvidenceIdentifier` without making the app depend on evidence code.
enum ViftyAccessibilityIdentifier {
    static let controlSession = "vifty.ax.control-session"
    static let controlSessionTitle = "vifty.ax.control-session.title"
    static let controlSessionSummary = "vifty.ax.control-session.summary"

    static let fanStatus = "vifty.ax.fan-status"
    static let leftFanDraftTarget = "vifty.ax.fan-status.fan-0.draft-target"
    static let rightFanDraftTarget = "vifty.ax.fan-status.fan-1.draft-target"

    static let curveChart = "vifty.ax.curve.chart"
    static let curveSeparateFans = "vifty.ax.curve.separate-fans"
    static let curveEffectiveSummaries = "vifty.ax.curve.effective-summaries"
    static let leftFanEffectiveSummary = "vifty.ax.curve.fan-0.effective-summary"
    static let rightFanEffectiveSummary = "vifty.ax.curve.fan-1.effective-summary"
    static let curveStartTemperature = "vifty.ax.curve.start.temperature"
    static let curveStartRPM = "vifty.ax.curve.start.rpm"
    static let curveRampTemperature = "vifty.ax.curve.ramp.temperature"
    static let curveRampRPM = "vifty.ax.curve.ramp.rpm"
    static let curveHighTemperature = "vifty.ax.curve.high.temperature"
    static let curveHighRPM = "vifty.ax.curve.high.rpm"
    static let curveControls = [
        curveStartTemperature,
        curveStartRPM,
        curveRampTemperature,
        curveRampRPM,
        curveHighTemperature,
        curveHighRPM
    ]

    static func curveEffectiveSummary(fanID: Int) -> String {
        switch fanID {
        case 0: leftFanEffectiveSummary
        case 1: rightFanEffectiveSummary
        default: "vifty.ax.curve.fan-\(fanID).effective-summary"
        }
    }

    static let sensorList = "vifty.ax.sensors"
    static let sensorCPU = "vifty.ax.sensor.cpu-efficiency"
    static let sensorGPU = "vifty.ax.sensor.gpu-hotspot"
    static let sensorPalm = "vifty.ax.sensor.palm"

    static let temperatureMetrics = "vifty.ax.temperature.metrics"
    static let curveSensorMetric = "vifty.ax.temperature.curve-sensor"
    static let highestTemperatureMetric = "vifty.ax.temperature.highest"

    static let notifications = "vifty.ax.notifications"
    static let notificationOpenSettings = "vifty.ax.notifications.open-settings"
    static let notificationSendTest = "vifty.ax.notifications.send-test"
    static let notificationHelperFailure = "vifty.ax.notifications.event.helper-failure"
    static let notificationThermalPressure = "vifty.ax.notifications.event.high-thermal-pressure"
    static let notificationAutoRestore = "vifty.ax.notifications.event.auto-restore-failure"
    static let notificationBatteryDrain = "vifty.ax.notifications.event.plugged-in-battery-drain"
    static let notificationAgentCooling = "vifty.ax.notifications.event.agent-cooling-attention"
    static let notificationEvents = [
        notificationHelperFailure,
        notificationThermalPressure,
        notificationAutoRestore,
        notificationBatteryDrain,
        notificationAgentCooling
    ]

    static let settings = "vifty.ax.settings"
    static let settingsTabs = "vifty.ax.settings.tabs"
    static let settingsTabGeneral = "vifty.ax.settings.tab.general"
    static let settingsTabMenuBar = "vifty.ax.settings.tab.menu-bar"
    static let settingsTabNotifications = "vifty.ax.settings.tab.notifications"
    static let settingsTabAgentWorkflows = "vifty.ax.settings.tab.agent-workflows"
    static let settingsPaneGeneral = "vifty.ax.settings.pane.general"
    static let settingsLaunchAtLogin = "vifty.ax.settings.general.launch-at-login"
    static let settingsUpdateAutomatic = "vifty.ax.settings.general.update.automatic"
    static let settingsUpdateStatus = "vifty.ax.settings.general.update.status"
    static let settingsUpdateCheck = "vifty.ax.settings.general.update.check"
    static let settingsUpdateLatest = "vifty.ax.settings.general.update.latest"

    static let mainScroll = "vifty.ax.scroll.main"
    static let mainScrollEnd = "vifty.ax.scroll.main.end"
    static let settingsGeneralScroll = "vifty.ax.scroll.settings.general"
    static let settingsGeneralScrollEnd = "vifty.ax.scroll.settings.general.end"
    static let settingsMenuBarScroll = "vifty.ax.scroll.settings.menu-bar"
    static let settingsMenuBarScrollEnd = "vifty.ax.scroll.settings.menu-bar.end"
    static let settingsNotificationsScroll = "vifty.ax.scroll.settings.notifications"
    static let settingsNotificationsScrollEnd = "vifty.ax.scroll.settings.notifications.end"
    static let settingsAgentWorkflowsScroll = "vifty.ax.scroll.settings.agent-workflows"
    static let settingsAgentWorkflowsScrollEnd = "vifty.ax.scroll.settings.agent-workflows.end"

    static func fanDraftTarget(fanID: Int) -> String {
        switch fanID {
        case 0: leftFanDraftTarget
        case 1: rightFanDraftTarget
        default: "vifty.ax.fan-status.fan-\(fanID).draft-target"
        }
    }

    static func sensor(id: String, name: String) -> String {
        switch (id, name) {
        case ("cpu-efficiency", _), (_, "CPU Efficiency"):
            sensorCPU
        case ("gpu-hotspot", _), ("gpu", _), (_, "GPU Hotspot"):
            sensorGPU
        case ("palm", _), (_, "Palm Rest"):
            sensorPalm
        default:
            "vifty.ax.sensor.\(stableComponent(id))"
        }
    }

    private static func stableComponent(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        let normalized = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return normalized.isEmpty ? "unknown" : normalized
    }
}

enum ViftySettingsAccessibilityPane: CaseIterable, Equatable {
    case general
    case menuBar
    case notifications
    case agentWorkflows

    var scrollIdentifier: String {
        switch self {
        case .general: ViftyAccessibilityIdentifier.settingsGeneralScroll
        case .menuBar: ViftyAccessibilityIdentifier.settingsMenuBarScroll
        case .notifications: ViftyAccessibilityIdentifier.settingsNotificationsScroll
        case .agentWorkflows: ViftyAccessibilityIdentifier.settingsAgentWorkflowsScroll
        }
    }

    var endAnchorIdentifier: String {
        switch self {
        case .general: ViftyAccessibilityIdentifier.settingsGeneralScrollEnd
        case .menuBar: ViftyAccessibilityIdentifier.settingsMenuBarScrollEnd
        case .notifications: ViftyAccessibilityIdentifier.settingsNotificationsScrollEnd
        case .agentWorkflows: ViftyAccessibilityIdentifier.settingsAgentWorkflowsScrollEnd
        }
    }

    var scopeIdentifier: String? {
        switch self {
        case .general: ViftyAccessibilityIdentifier.settingsPaneGeneral
        case .notifications: ViftyAccessibilityIdentifier.notifications
        case .menuBar, .agentWorkflows: nil
        }
    }

    var scopeLabel: String? {
        switch self {
        case .general: "General settings"
        case .notifications: "Notification settings"
        case .menuBar, .agentWorkflows: nil
        }
    }
}

enum ViftyCurveAccessibilityControl: CaseIterable, Equatable, Identifiable {
    case startTemperature
    case startRPM
    case rampTemperature
    case rampRPM
    case highTemperature
    case highRPM

    var id: String { identifier }

    var identifier: String {
        switch self {
        case .startTemperature: ViftyAccessibilityIdentifier.curveStartTemperature
        case .startRPM: ViftyAccessibilityIdentifier.curveStartRPM
        case .rampTemperature: ViftyAccessibilityIdentifier.curveRampTemperature
        case .rampRPM: ViftyAccessibilityIdentifier.curveRampRPM
        case .highTemperature: ViftyAccessibilityIdentifier.curveHighTemperature
        case .highRPM: ViftyAccessibilityIdentifier.curveHighRPM
        }
    }

    var label: String {
        switch self {
        case .startTemperature: "Start temperature"
        case .startRPM: "Start RPM"
        case .rampTemperature: "Ramp temperature"
        case .rampRPM: "Ramp RPM"
        case .highTemperature: "High temperature"
        case .highRPM: "High RPM"
        }
    }

    var isTemperature: Bool {
        switch self {
        case .startTemperature, .rampTemperature, .highTemperature: true
        case .startRPM, .rampRPM, .highRPM: false
        }
    }

    func valueText(
        startTemperature: Double,
        startRPM: Double,
        rampTemperature: Double,
        rampRPM: Double,
        highTemperature: Double,
        highRPM: Double
    ) -> String {
        switch self {
        case .startTemperature: TemperatureDisplayFormatter.whole(startTemperature)
        case .startRPM: "\(Int(startRPM.rounded())) RPM"
        case .rampTemperature: TemperatureDisplayFormatter.whole(rampTemperature)
        case .rampRPM: "\(Int(rampRPM.rounded())) RPM"
        case .highTemperature: TemperatureDisplayFormatter.whole(highTemperature)
        case .highRPM: "\(Int(highRPM.rounded())) RPM"
        }
    }
}

struct FanDraftTargetAccessibilityPresentation: Equatable {
    let identifier: String
    let label: String
    let value: String

    static func resolve(
        fanID: Int,
        fanName: String,
        draftTargetText: String?
    ) -> FanDraftTargetAccessibilityPresentation? {
        guard let draftTargetText else { return nil }
        return FanDraftTargetAccessibilityPresentation(
            identifier: ViftyAccessibilityIdentifier.fanDraftTarget(fanID: fanID),
            label: "\(fanName) draft target",
            value: draftTargetText
        )
    }
}

struct SensorAccessibilityPresentation: Equatable {
    let identifier: String
    let label: String
    let value: String
    let isSelected: Bool

    static func resolve(
        sensor: TemperatureSensor,
        selectedSensorID: String?
    ) -> SensorAccessibilityPresentation {
        SensorAccessibilityPresentation(
            identifier: ViftyAccessibilityIdentifier.sensor(id: sensor.id, name: sensor.name),
            label: sensor.name,
            value: String(
                format: "%.1f degrees Celsius, %@",
                sensor.celsius,
                sensor.source.rawValue
            ),
            isSelected: sensor.id == selectedSensorID
        )
    }
}

struct TemperatureMetricAccessibilityPresentation: Equatable {
    let curveSensorLabel: String
    let curveSensorValue: String
    let highestTemperatureLabel: String
    let highestTemperatureValue: String

    static func resolve(
        sensors: [TemperatureSensor],
        effectiveSensorID: String?
    ) -> TemperatureMetricAccessibilityPresentation? {
        guard let highest = sensors.max(by: { $0.celsius < $1.celsius }) else {
            return nil
        }
        let curveSensor = effectiveSensorID
            .flatMap { selectedID in sensors.first { $0.id == selectedID } }
            ?? sensors.first
        guard let curveSensor else { return nil }
        return TemperatureMetricAccessibilityPresentation(
            curveSensorLabel: "Curve sensor",
            curveSensorValue: "Curve sensor · \(curveSensor.name)",
            highestTemperatureLabel: "Highest temperature",
            highestTemperatureValue: "Highest \(TemperatureDisplayFormatter.decimal(highest.celsius))"
        )
    }
}

struct ViftyAccessibilityScrollEndAnchor: View {
    let identifier: String

    var body: some View {
        Text("End of content")
            .viftyFont(.caption2)
            .foregroundStyle(.secondary.opacity(0.01))
            .frame(maxWidth: .infinity, minHeight: 1, alignment: .leading)
            .accessibilityLabel("End of content")
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(false)
    }
}
