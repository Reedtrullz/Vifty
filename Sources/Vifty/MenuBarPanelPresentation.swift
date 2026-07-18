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
        let ownershipStatus: FanControlOwnershipStatus?
        let attentionText: String?
        let fans: [Fan]
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
        let ownership = FanControlOwnershipPresentation.resolve(input.ownershipStatus)
        let stateTitle = input.controlSession.title
        let headline = headline(for: ownership.owner)
        var attentionText = input.attentionText ?? attentionText(for: input.controlSession)
        if attentionText == stateTitle || attentionText == headline {
            attentionText = nil
        }

        return MenuBarPanelPresentation(
            stateTitle: stateTitle,
            headline: headline,
            ownerText: ownership.ownerText,
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
            showsRestoreAuto: ownership.canRequestRestoreAuto
        )
    }

    private static func headline(for owner: ConfirmedFanControlOwner) -> String {
        switch owner {
        case .macOS:
            "macOS controls fans"
        case .viftyManual:
            "Vifty controls fans"
        case .agent:
            "Bounded workload cooling"
        case .recovery:
            "Auto recovery pending"
        case .mixedOrUnknown:
            "Fan ownership needs confirmation"
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
