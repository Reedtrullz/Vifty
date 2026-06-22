import AppKit
import Foundation
import ViftyCore

enum AgentWorkflowSupport {
    static let copyHelp = "Copy a pasteable AGENTS.md/Codex rule that checks viftyctl capabilities, viftyctl diagnose readiness, and guarded-run wrappers before any agent/build/test cooling."
    static let copyCommandHelp = "Copy an audited guarded-run command or read-only preflight for a common developer workload."
    static let copiedMessage = "Copied safe agent rule"
    static let copiedCommandMessage = "Copied safe workload command"

    private static let canonicalAppPath = "/Applications/Vifty.app"
    private static let guardedRunResourcePath = "Contents/Resources/viftyctl-wrappers/guarded-run.sh"

    typealias WorkloadCommandTemplate = ViftyCtlWorkloadTemplate

    enum WorkloadCommandMode: String, CaseIterable, Identifiable {
        case run
        case preflight

        var id: String { rawValue }

        var menuTitle: String {
            switch self {
            case .run:
                "Run with cooling"
            case .preflight:
                "Read-only preflight"
            }
        }
    }

    static let safeWorkloadCommandTemplates: [WorkloadCommandTemplate] = ViftyCtlWorkloadTemplate.auditedTemplates

    static func agentRule(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> String {
        let paths = agentWorkflowPaths(bundleURL: bundleURL, fileManager: fileManager)
        let capabilitiesCommand = "\(shellQuote(paths.viftyCtlPath)) capabilities --json"
        let diagnoseCommand = "\(shellQuote(paths.viftyCtlPath)) diagnose --json"
        let swiftTestTemplate = safeWorkloadCommandTemplates[0]
        let runCommand = workloadCommand(swiftTestTemplate, mode: .run, bundleURL: bundleURL, fileManager: fileManager)
        let preflightCommand = workloadCommand(swiftTestTemplate, mode: .preflight, bundleURL: bundleURL, fileManager: fileManager)

        return """
        For long local build/test/model workloads on this Mac, use Vifty only through the guarded local CLI.

        Before requesting cooling, run:

        ```sh
        \(capabilitiesCommand)
        \(diagnoseCommand)
        ```

        From capabilities, require `schemaVersion: 1`, `schemaIDs.diagnose`, `schemaIDs.commandError`, `schemaIDs.run`, `wrapperResources`, `workloadTemplates`, `runLifecycle.resolvedChildExecutableReported: true`, `policyStatusAvailable: true`, `policy.enabled: true`, and support for the requested workload before trusting policy limits, copied command templates, or wrapper output.

        Use `wrapperResources.bundleDirectory`, `wrapperResources.sourceDirectory`, `wrapperResources.guardedRunScript`, `wrapperResources.workloadScripts`, and `workloadTemplates` to choose the installed or source wrapper and audited workload defaults instead of inventing unaudited fan-control commands.

        If `state` is `blocked`, `safeToRequestCooling` is false, `daemonControlPathReady` is false, `manualControlActive` is true, or `coolingBlockerIDs` is non-empty, do not request cooling. Show the JSON to the user and stop.

        Prefer the guarded wrapper for one child workload:

        ```sh
        \(runCommand)
        ```

        For read-only planning, use preflight mode:

        ```sh
        \(preflightCommand)
        ```

        When guarded-run refuses before cooling or completes preflight-only, extract only the JSON payload between `guarded-run: BEGIN_VIFTY_CAPABILITIES_JSON` / `guarded-run: END_VIFTY_CAPABILITIES_JSON`, `guarded-run: BEGIN_VIFTY_DIAGNOSE_JSON` / `guarded-run: END_VIFTY_DIAGNOSE_JSON`, or `guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON` / `guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON`. Decision payloads use `schemaID: https://vifty.local/schemas/guarded-run-decision.schema.json`, include `decisionReason`, and preflight-only success must report `coolingRequested: false`. Do not parse surrounding recovery prose.

        Leave `VIFTY_GUARDED_RUN_FORCE_RETRY` and `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED` unset unless the user explicitly approves that supervised behavior after seeing Vifty's structured readiness output. Do not catch a guarded-run failure and rerun the same workload without Vifty.

        Never call `ViftyHelper setFixed`, `ViftyHelper auto`, `sudo`, raw SMC tools, direct fan RPM writes, or unguarded `viftyctl prepare` from an agent.
        """
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
        let paths = agentWorkflowPaths(bundleURL: bundleURL, fileManager: fileManager)

        switch mode {
        case .run:
            let shortcutPath = wrapperScriptPath(named: template.shortcutScript, guardedRunPath: paths.guardedRunPath)
            return ([shortcutPath] + template.shortcutArguments)
                .map(shellQuote)
                .joined(separator: " ")
        case .preflight:
            let arguments = [
                paths.guardedRunPath,
                "--preflight-only",
                template.workload,
                template.duration,
                "\(template.maxRPMPercent)",
                template.reason,
                "--"
            ] + template.childArguments
            return arguments.map(shellQuote).joined(separator: " ")
        }
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

    private static func agentWorkflowPaths(
        bundleURL: URL,
        fileManager: FileManager
    ) -> (viftyCtlPath: String, guardedRunPath: String) {
        let bundledTool = bundleURL.appendingPathComponent("Contents/MacOS/viftyctl", isDirectory: false)
        let bundledGuardedRun = bundleURL.appendingPathComponent(guardedRunResourcePath, isDirectory: false)
        if bundleURL.pathExtension == "app",
           fileManager.isExecutableFile(atPath: bundledTool.path),
           fileManager.isExecutableFile(atPath: bundledGuardedRun.path) {
            return (bundledTool.path, bundledGuardedRun.path)
        }

        return (
            "\(canonicalAppPath)/Contents/MacOS/viftyctl",
            "\(canonicalAppPath)/\(guardedRunResourcePath)"
        )
    }

    private static func wrapperScriptPath(named scriptName: String, guardedRunPath: String) -> String {
        let guardedRunURL = URL(fileURLWithPath: guardedRunPath)
        return guardedRunURL
            .deletingLastPathComponent()
            .appendingPathComponent(scriptName, isDirectory: false)
            .path
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
