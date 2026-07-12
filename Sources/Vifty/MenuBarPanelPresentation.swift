import Foundation
import ViftyCore

struct MenuBarFanLine: Equatable {
    let title: String
    let detail: String
}

enum MenuBarPanelAction: Equatable {
    case openMainWindow
    case restoreAuto
    case quit
}

struct MenuBarPanelPresentation: Equatable {
    struct Input: Equatable {
        let controlSession: ControlSessionPresentation
        let ownerText: String
        let attentionText: String?
        let fans: [Fan]
        let isManualControlActive: Bool
    }

    let stateTitle: String
    let headline: String
    let ownerText: String
    let attentionText: String?
    let fanLines: [MenuBarFanLine]
    let primaryAction: MenuBarPanelAction
    let primaryActionTitle: String
    let primaryActionHelp: String
    let showsRestoreAuto: Bool

    var visibleActionTitles: [String] {
        [primaryActionTitle] + (showsRestoreAuto ? ["Restore Auto"] : []) + ["Quit"]
    }

    static func resolve(input: Input) -> MenuBarPanelPresentation {
        let stateTitle = input.controlSession.title
        let headline = headline(for: input.controlSession)
        var attentionText = input.attentionText ?? attentionText(for: input.controlSession)
        if attentionText == stateTitle || attentionText == headline {
            attentionText = nil
        }

        return MenuBarPanelPresentation(
            stateTitle: stateTitle,
            headline: headline,
            ownerText: input.ownerText,
            attentionText: attentionText,
            fanLines: input.fans.map {
                MenuBarFanLine(
                    title: $0.name,
                    detail: "\($0.currentRPM) RPM · \($0.percentage)%"
                )
            },
            primaryAction: .openMainWindow,
            primaryActionTitle: "Open Vifty",
            primaryActionHelp: "Open the main Vifty window.",
            showsRestoreAuto: input.controlSession.primaryAction == .restoreAuto
                || (input.isManualControlActive && input.controlSession.state != .blocked)
        )
    }

    private static func headline(for controlSession: ControlSessionPresentation) -> String {
        switch controlSession.state {
        case .checking:
            "Checking helper status"
        case .ready:
            "macOS controls fans"
        case .attention:
            "Check Vifty before changing control"
        case .blocked:
            "Open Vifty for recovery"
        case .manual:
            "Vifty controls fans"
        case .agentCooling:
            controlSession.title == "Agent cooling active"
                ? "Bounded workload cooling"
                : "Cooling ownership needs review"
        }
    }

    private static func attentionText(for controlSession: ControlSessionPresentation) -> String? {
        guard controlSession.state == .agentCooling,
              controlSession.title != "Agent cooling active" else {
            return nil
        }
        return "Restore Auto before another workload"
    }
}
