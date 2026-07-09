import Foundation

enum MainWindowPaneRole: String, Equatable {
    case stackedFlow
    case splitControl
    case splitTelemetry
    case workbenchControlRail
    case workbenchEditor
    case workbenchTelemetry
}

struct MainWindowSectionPlacement: Equatable {
    let safetyMode: MainWindowPaneRole
    let fanControl: MainWindowPaneRole
    let telemetryEvidence: MainWindowPaneRole
    let settingsAndTools: MainWindowPaneRole

    static func resolve(layout: MainWindowLayout) -> MainWindowSectionPlacement {
        switch layout.mode {
        case .stacked:
            MainWindowSectionPlacement(
                safetyMode: .stackedFlow,
                fanControl: .stackedFlow,
                telemetryEvidence: .stackedFlow,
                settingsAndTools: .stackedFlow
            )
        case .split:
            MainWindowSectionPlacement(
                safetyMode: .splitControl,
                fanControl: .splitControl,
                telemetryEvidence: .splitTelemetry,
                settingsAndTools: .splitControl
            )
        case .workbench:
            MainWindowSectionPlacement(
                safetyMode: .workbenchControlRail,
                fanControl: .workbenchEditor,
                telemetryEvidence: .workbenchTelemetry,
                settingsAndTools: .workbenchControlRail
            )
        }
    }
}
