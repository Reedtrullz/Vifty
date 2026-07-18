import Foundation
import ViftyCore

enum ControlSessionState: Equatable {
    case checking
    case ready
    case attention
    case blocked
    case draft
    case manual
    case agentCooling
}

enum ControlSessionAction: Equatable {
    case none
    case apply
    case restoreAuto
    case repairHelper
    case copyDiagnostics
}

struct ControlSessionInput: Equatable {
    var helperHealth: HelperHealthState
    var helperHealthNeedsAttention: Bool
    var helperRepairActionAvailable: Bool
    var manualFanControlAvailable: Bool
    var controlOwnershipNeedsAttention: Bool
    var controlOwnershipSummary: String
    var agentCoolingSummary: String?
    var hasAgentCoolingLease: Bool = false
    var agentCoolingNeedsAttention: Bool
    var manualControlAttentionSummary: String?
    var selectedMode: ModeSelection
    var applyState: FanControlApplyState
    var manualSessionExpiresAt: Date?
    var ownershipStatus: FanControlOwnershipStatus?
}

struct ControlSessionPresentation: Equatable {
    var state: ControlSessionState
    var title: String
    var summary: String
    var detail: String?
    var expiryText: String?
    var primaryAction: ControlSessionAction
    var primaryActionTitle: String
    var primaryActionHelp: String
    var primaryActionDisabled: Bool

    func resolvingHelperAction(
        _ helperAction: HelperActionPresentation
    ) -> ControlSessionPresentation {
        guard primaryAction == .repairHelper else { return self }
        var resolved = self
        resolved.detail = helperAction.description
        guard helperAction.isAvailable else {
            resolved.primaryAction = .copyDiagnostics
            resolved.primaryActionTitle = "Copy Support Evidence"
            resolved.primaryActionHelp = "Copy read-only helper and fan diagnostics."
            resolved.primaryActionDisabled = false
            return resolved
        }
        resolved.primaryActionTitle = helperAction.title
        resolved.primaryActionHelp = helperAction.help
        resolved.primaryActionDisabled = false
        return resolved
    }

    static func resolve(_ input: ControlSessionInput) -> ControlSessionPresentation {
        let ownership = FanControlOwnershipPresentation.resolve(input.ownershipStatus)

        if input.helperHealth == .checking, input.ownershipStatus == nil {
            return ControlSessionPresentation(
                state: .checking,
                title: "Checking fan control",
                summary: input.helperHealth.summary,
                detail: nil,
                expiryText: nil,
                primaryAction: .none,
                primaryActionTitle: "",
                primaryActionHelp: "",
                primaryActionDisabled: true
            )
        }

        if ownership.owner == .agent {
            let agentCoolingSummary = input.agentCoolingSummary ?? "The daemon confirms an active agent cooling transaction."
            return ControlSessionPresentation(
                state: .agentCooling,
                title: input.agentCoolingNeedsAttention ? "Agent cooling needs attention" : "Agent cooling active",
                summary: agentCoolingSummary,
                detail: input.agentCoolingNeedsAttention ? "Restore Auto before starting another workload." : nil,
                expiryText: nil,
                primaryAction: .restoreAuto,
                primaryActionTitle: "Restore Auto",
                primaryActionHelp: "Restore automatic macOS fan control.",
                primaryActionDisabled: false
            )
        }

        if ownership.owner == .recovery {
            return ControlSessionPresentation(
                state: .attention,
                title: "Fan recovery pending",
                summary: ownership.ownerText,
                detail: "Restore Auto and wait for every expected fan to return to macOS ownership.",
                expiryText: nil,
                primaryAction: .restoreAuto,
                primaryActionTitle: "Restore Auto",
                primaryActionHelp: "Resume the daemon's journaled Auto recovery transaction.",
                primaryActionDisabled: false
            )
        }

        if ownership.owner == .viftyManual,
           (input.selectedMode == .auto
                || input.manualControlAttentionSummary != nil
                || input.helperHealthNeedsAttention) {
            return ControlSessionPresentation(
                state: .attention,
                title: "Fan control needs attention",
                summary: input.manualControlAttentionSummary ?? ownership.ownerText,
                detail: "Restore Auto before repairing or changing manual fan control.",
                expiryText: expiryText(for: input.manualSessionExpiresAt),
                primaryAction: .restoreAuto,
                primaryActionTitle: "Restore Auto",
                primaryActionHelp: "Restore automatic macOS fan control.",
                primaryActionDisabled: false
            )
        }

        if input.helperHealthNeedsAttention, !input.manualFanControlAvailable {
            let action: ControlSessionAction = input.helperRepairActionAvailable ? .repairHelper : .copyDiagnostics
            let actionTitle = input.helperRepairActionAvailable ? "Repair Helper" : "Copy Support Evidence"
            return ControlSessionPresentation(
                state: .blocked,
                title: "Manual fan control blocked",
                summary: input.helperHealth.summary,
                detail: input.helperHealth.recoverySuggestion,
                expiryText: nil,
                primaryAction: action,
                primaryActionTitle: actionTitle,
                primaryActionHelp: input.helperRepairActionAvailable
                    ? "Repair or approve the helper before fan writes."
                    : "Copy read-only diagnostics for support or validation.",
                primaryActionDisabled: false
            )
        }

        if ownership.owner == .mixedOrUnknown
            || (ownership.owner == .macOS && input.controlOwnershipNeedsAttention) {
            return ControlSessionPresentation(
                state: .attention,
                title: "Fan ownership requires confirmation",
                summary: ownership.ownerText,
                detail: "Control stays blocked until daemon ownership and fresh fan telemetry agree.",
                expiryText: nil,
                primaryAction: .copyDiagnostics,
                primaryActionTitle: "Copy Support Evidence",
                primaryActionHelp: "Copy read-only ownership and fan diagnostics.",
                primaryActionDisabled: false
            )
        }

        if ownership.owner != .agent, let agentCoolingSummary = input.agentCoolingSummary {
            return ControlSessionPresentation(
                state: .attention,
                title: "Agent cooling status unavailable",
                summary: agentCoolingSummary,
                detail: "Do not start another workload until agent status can be confirmed.",
                expiryText: nil,
                primaryAction: .copyDiagnostics,
                primaryActionTitle: "Copy Support Evidence",
                primaryActionHelp: "Copy read-only diagnostics for support or validation.",
                primaryActionDisabled: false
            )
        }

        if ownership.owner == .macOS, input.selectedMode == .auto {
            if input.helperHealth == .checking {
                return ControlSessionPresentation(
                    state: .checking,
                    title: "Checking fan control",
                    summary: input.helperHealth.summary,
                    detail: nil,
                    expiryText: nil,
                    primaryAction: .none,
                    primaryActionTitle: "",
                    primaryActionHelp: "",
                    primaryActionDisabled: true
                )
            }
            return ControlSessionPresentation(
                state: .ready,
                title: "Auto control active",
                summary: ownership.ownerText,
                detail: nil,
                expiryText: nil,
                primaryAction: .none,
                primaryActionTitle: "",
                primaryActionHelp: "",
                primaryActionDisabled: true
            )
        }

        if ownership.owner == .viftyManual {
            return confirmedManualPresentation(input, ownership: ownership)
        }

        return draftPresentation(input, ownership: ownership)
    }

    private static func confirmedManualPresentation(
        _ input: ControlSessionInput,
        ownership: FanControlOwnershipPresentation
    ) -> ControlSessionPresentation {
        switch input.applyState {
        case .blocked(let reason):
            return ControlSessionPresentation(
                state: .blocked,
                title: "Manual fan control blocked",
                summary: reason,
                detail: input.helperHealth.recoverySuggestion,
                expiryText: nil,
                primaryAction: .copyDiagnostics,
                primaryActionTitle: "Copy Support Evidence",
                primaryActionHelp: "Copy read-only diagnostics for support or validation.",
                primaryActionDisabled: false
            )
        case .applying:
            return ControlSessionPresentation(
                state: .manual,
                title: "Applying manual fan control",
                summary: ownership.ownerText,
                detail: nil,
                expiryText: expiryText(for: input.manualSessionExpiresAt),
                primaryAction: .apply,
                primaryActionTitle: "Applying…",
                primaryActionHelp: "Applying the selected fan-control draft.",
                primaryActionDisabled: true
            )
        case .failed(let message):
            return manualPresentation(
                input,
                title: "Vifty controls fans · changes failed",
                summary: message,
                actionTitle: "Apply Changes"
            )
        case .pending:
            return manualPresentation(
                input,
                title: "Vifty controls fans · changes pending",
                summary: ownership.ownerText,
                actionTitle: "Apply Changes"
            )
        case .applied:
            return manualPresentation(
                input,
                title: "Vifty manual control active",
                summary: ownership.ownerText,
                actionTitle: "Apply"
            )
        }
    }

    private static func draftPresentation(
        _ input: ControlSessionInput,
        ownership: FanControlOwnershipPresentation
    ) -> ControlSessionPresentation {
        switch input.applyState {
        case .blocked(let reason):
            return ControlSessionPresentation(
                state: .blocked,
                title: "Manual fan-control draft blocked",
                summary: reason,
                detail: input.helperHealth.recoverySuggestion,
                expiryText: nil,
                primaryAction: .copyDiagnostics,
                primaryActionTitle: "Copy Support Evidence",
                primaryActionHelp: "Copy read-only diagnostics for support or validation.",
                primaryActionDisabled: false
            )
        case .applying:
            return ControlSessionPresentation(
                state: .draft,
                title: "Applying manual fan-control draft",
                summary: ownership.ownerText,
                detail: "Ownership is not claimed until the daemon confirms the complete transaction.",
                expiryText: nil,
                primaryAction: .apply,
                primaryActionTitle: "Applying…",
                primaryActionHelp: "Applying the selected fan-control draft.",
                primaryActionDisabled: true
            )
        case .failed(let message):
            return draftManualPresentation(
                title: "Manual draft needs attention",
                summary: message,
                actionTitle: "Apply Changes"
            )
        case .pending:
            return draftManualPresentation(
                title: "Manual draft pending",
                summary: ownership.ownerText,
                actionTitle: "Apply Changes"
            )
        case .applied:
            return draftManualPresentation(
                title: "Manual draft not active",
                summary: ownership.ownerText,
                actionTitle: "Apply"
            )
        }
    }

    private static func draftManualPresentation(
        title: String,
        summary: String,
        actionTitle: String
    ) -> ControlSessionPresentation {
        ControlSessionPresentation(
            state: .draft,
            title: title,
            summary: summary,
            detail: "macOS remains the confirmed owner until Apply succeeds.",
            expiryText: nil,
            primaryAction: .apply,
            primaryActionTitle: actionTitle,
            primaryActionHelp: "Apply the selected manual fan-control draft.",
            primaryActionDisabled: false
        )
    }

    private static func manualPresentation(
        _ input: ControlSessionInput,
        title: String,
        summary: String,
        actionTitle: String
    ) -> ControlSessionPresentation {
        ControlSessionPresentation(
            state: .manual,
            title: title,
            summary: summary,
            detail: nil,
            expiryText: expiryText(for: input.manualSessionExpiresAt),
            primaryAction: .apply,
            primaryActionTitle: actionTitle,
            primaryActionHelp: "Apply the selected manual fan-control draft.",
            primaryActionDisabled: false
        )
    }

    private static func expiryText(for expiresAt: Date?) -> String? {
        expiresAt.map { "Auto restore scheduled at \($0.formatted(date: .omitted, time: .shortened))" }
    }
}
