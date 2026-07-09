import Foundation

enum MainWindowPaneRole: String, Equatable {
    case stackedFlow
    case splitControl
    case splitTelemetry
    case workbenchControlRail
    case workbenchEditor
    case workbenchTelemetry
}

enum MainWindowSection: String, CaseIterable, Equatable, Identifiable {
    case safetyMode
    case fanControl
    case settingsAndTools
    case telemetryEvidence

    var id: Self { self }
}

struct MainWindowSectionPlacement: Equatable {
    let safetyMode: MainWindowPaneRole
    let fanControl: MainWindowPaneRole
    let telemetryEvidence: MainWindowPaneRole
    let settingsAndTools: MainWindowPaneRole

    func paneRole(for section: MainWindowSection) -> MainWindowPaneRole {
        switch section {
        case .safetyMode:
            safetyMode
        case .fanControl:
            fanControl
        case .settingsAndTools:
            settingsAndTools
        case .telemetryEvidence:
            telemetryEvidence
        }
    }

    func sections(in role: MainWindowPaneRole) -> [MainWindowSection] {
        MainWindowSection.allCases.filter { paneRole(for: $0) == role }
    }

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
