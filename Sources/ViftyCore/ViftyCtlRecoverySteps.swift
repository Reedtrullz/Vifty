import Foundation

public enum ViftyCtlRecoverySteps {
    public static let repairHelper = ViftyAgentRule.repairHelperRecoveryActions

    public static let restoreAutoBeforeRetry = [
        "Restore Auto once with Vifty or viftyctl restore-auto --json, then rerun diagnose --json.",
        "If manualControlActive remains true, switch Vifty/default startup mode to Auto before requesting cooling."
    ]

    public static let backOffWorkload = [
        "Pause or reduce the workload and let macOS thermal pressure recover.",
        "Rerun diagnose --json before requesting cooling."
    ]

    public static let inspectPolicy = [
        "Run viftyctl status --json and capabilities --json to inspect local policy/status.",
        "Do not request cooling until policy.enabled and policyStatusAvailable are true."
    ]

    public static let collectHardwareEvidence = [
        "Collect read-only validation evidence before requesting cooling on this hardware.",
        "Do not run fan-write smoke until reviewed readiness is safe."
    ]

    public static let runDiagnose = [
        "Run viftyctl diagnose --json and follow its readiness fields before requesting cooling."
    ]

    public static let fixArguments = [
        "Fix the viftyctl or wrapper arguments, then rerun the command."
    ]

    public static let fixChildCommand = [
        "Fix the workload command/path or show the launch error; do not treat this as a helper failure."
    ]

    public static let waitBeforeRetry = [
        "Wait for retryAfterSeconds before retrying, or show the JSON to the user if no retryAfterSeconds is present."
    ]

    public static func steps(for action: ViftyCtlReadinessRecoveryAction) -> [String] {
        switch action {
        case .none:
            return []
        case .repairHelper:
            return repairHelper
        case .restoreAutoBeforeRetry:
            return restoreAutoBeforeRetry
        case .backOffWorkload:
            return backOffWorkload
        case .inspectPolicy:
            return inspectPolicy
        case .collectHardwareEvidence:
            return collectHardwareEvidence
        }
    }

    public static func steps(for action: ViftyCtlCommandErrorRecoveryAction) -> [String] {
        switch action {
        case .runDiagnose:
            return runDiagnose
        case .repairHelper:
            return repairHelper
        case .fixArguments:
            return fixArguments
        case .fixChildCommand:
            return fixChildCommand
        case .restoreAutoBeforeRetry:
            return restoreAutoBeforeRetry
        case .waitBeforeRetry:
            return waitBeforeRetry
        }
    }
}
