import Foundation

enum ControlSessionState: Equatable {
    case checking
    case ready
    case attention
    case blocked
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

    static func resolve(_ input: ControlSessionInput) -> ControlSessionPresentation {
        if input.hasAgentCoolingLease, let agentCoolingSummary = input.agentCoolingSummary {
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

        if !input.hasAgentCoolingLease, let agentCoolingSummary = input.agentCoolingSummary {
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

        if input.controlOwnershipNeedsAttention || input.manualControlAttentionSummary != nil {
            return ControlSessionPresentation(
                state: .attention,
                title: "Fan control needs attention",
                summary: input.manualControlAttentionSummary ?? input.controlOwnershipSummary,
                detail: "Restore Auto before changing manual fan control.",
                expiryText: expiryText(for: input.manualSessionExpiresAt),
                primaryAction: .restoreAuto,
                primaryActionTitle: "Restore Auto",
                primaryActionHelp: "Restore automatic macOS fan control.",
                primaryActionDisabled: false
            )
        }

        if input.selectedMode == .auto {
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
                summary: input.controlOwnershipSummary,
                detail: nil,
                expiryText: nil,
                primaryAction: .none,
                primaryActionTitle: "",
                primaryActionHelp: "",
                primaryActionDisabled: true
            )
        }

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
                summary: input.controlOwnershipSummary,
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
                title: "Manual fan control needs attention",
                summary: message,
                actionTitle: "Apply Changes"
            )
        case .pending:
            return manualPresentation(
                input,
                title: "Manual fan control pending",
                summary: input.controlOwnershipSummary,
                actionTitle: "Apply Changes"
            )
        case .applied:
            return manualPresentation(
                input,
                title: "Manual fan control",
                summary: input.controlOwnershipSummary,
                actionTitle: "Apply"
            )
        }
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
