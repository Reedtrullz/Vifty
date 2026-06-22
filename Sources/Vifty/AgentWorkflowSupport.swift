import AppKit
import Foundation
import ViftyCore

enum AgentWorkflowSupport {
    static let copyHelp = "Copy a pasteable AGENTS.md/Codex rule that checks viftyctl capabilities, viftyctl diagnose readiness, and guarded-run wrappers before any agent/build/test cooling."
    static let copyCommandHelp = "Copy an audited guarded-run command or read-only preflight for a common developer workload."
    static let copiedMessage = "Copied safe agent rule"
    static let copiedCommandMessage = "Copied safe workload command"

    typealias WorkloadCommandTemplate = ViftyCtlWorkloadTemplate
    typealias WorkloadCommandMode = ViftyAgentRuleWorkloadCommandMode
}

extension ViftyAgentRuleWorkloadCommandMode {
    var menuTitle: String {
        switch self {
        case .run:
            "Run with cooling"
        case .preflight:
            "Read-only preflight"
        }
    }
}

extension AgentWorkflowSupport {
    static let safeWorkloadCommandTemplates: [WorkloadCommandTemplate] = ViftyCtlWorkloadTemplate.auditedTemplates

    static func agentRule(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> String {
        ViftyAgentRule.rule(bundleURL: bundleURL, fileManager: fileManager)
    }

    @discardableResult
    @MainActor
    static func copyAgentRule(
        bundleURL: URL = Bundle.main.bundleURL,
        pasteboard: NSPasteboard = .general
    ) -> String {
        let rule = agentRule(bundleURL: bundleURL)
        pasteboard.clearContents()
        pasteboard.setString(rule, forType: .string)
        return rule
    }

    static func workloadCommand(
        _ template: WorkloadCommandTemplate,
        mode: WorkloadCommandMode,
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> String {
        ViftyAgentRule.workloadCommand(
            template,
            mode: mode,
            bundleURL: bundleURL,
            fileManager: fileManager
        )
    }

    @discardableResult
    @MainActor
    static func copyWorkloadCommand(
        _ template: WorkloadCommandTemplate,
        mode: WorkloadCommandMode,
        bundleURL: URL = Bundle.main.bundleURL,
        pasteboard: NSPasteboard = .general
    ) -> String {
        let command = workloadCommand(template, mode: mode, bundleURL: bundleURL)
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        return command
    }
}
