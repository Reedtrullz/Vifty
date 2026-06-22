import AppKit
import Foundation

enum AgentWorkflowSupport {
    static let copyHelp = "Copy a pasteable AGENTS.md/Codex rule that checks viftyctl capabilities, viftyctl diagnose readiness, and guarded-run wrappers before any agent/build/test cooling."
    static let copyCommandHelp = "Copy an audited guarded-run command or read-only preflight for a common developer workload."
    static let copiedMessage = "Copied safe agent rule"
    static let copiedCommandMessage = "Copied safe workload command"

    private static let canonicalAppPath = "/Applications/Vifty.app"
    private static let guardedRunResourcePath = "Contents/Resources/viftyctl-wrappers/guarded-run.sh"

    struct WorkloadCommandTemplate: Identifiable, Equatable {
        let id: String
        let title: String
        let workload: String
        let duration: String
        let maxRPMPercent: Int
        let reason: String
        let childArguments: [String]
        let shortcutScript: String
        let shortcutArguments: [String]
    }

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

    static let safeWorkloadCommandTemplates: [WorkloadCommandTemplate] = [
        WorkloadCommandTemplate(
            id: "swift-test",
            title: "Swift test",
            workload: "test",
            duration: "20m",
            maxRPMPercent: 70,
            reason: "swift test",
            childArguments: ["swift", "test"],
            shortcutScript: "swift-test.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "swift-release-build",
            title: "Swift release build",
            workload: "build",
            duration: "25m",
            maxRPMPercent: 75,
            reason: "swift release build",
            childArguments: ["swift", "build", "-c", "release"],
            shortcutScript: "swift-release-build.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "xcode-build",
            title: "Xcode build",
            workload: "build",
            duration: "30m",
            maxRPMPercent: 75,
            reason: "xcodebuild build",
            childArguments: ["xcodebuild", "build"],
            shortcutScript: "xcode-build.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "xcode-test",
            title: "Xcode test",
            workload: "test",
            duration: "30m",
            maxRPMPercent: 75,
            reason: "xcodebuild test",
            childArguments: ["xcodebuild", "test"],
            shortcutScript: "xcode-test.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "make-build",
            title: "Make build",
            workload: "build",
            duration: "25m",
            maxRPMPercent: 75,
            reason: "make build",
            childArguments: ["make", "build"],
            shortcutScript: "make-build.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "make-test",
            title: "Make test",
            workload: "test",
            duration: "20m",
            maxRPMPercent: 70,
            reason: "make test",
            childArguments: ["make", "test"],
            shortcutScript: "make-test.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "make-verify",
            title: "Make verify",
            workload: "test",
            duration: "30m",
            maxRPMPercent: 75,
            reason: "make verify",
            childArguments: ["make", "verify"],
            shortcutScript: "make-verify.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "npm-build",
            title: "npm build",
            workload: "build",
            duration: "25m",
            maxRPMPercent: 75,
            reason: "npm run build",
            childArguments: ["npm", "run", "build"],
            shortcutScript: "npm-build.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "npm-test",
            title: "npm test",
            workload: "test",
            duration: "20m",
            maxRPMPercent: 70,
            reason: "npm test",
            childArguments: ["npm", "test"],
            shortcutScript: "npm-test.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "pnpm-build",
            title: "pnpm build",
            workload: "build",
            duration: "25m",
            maxRPMPercent: 75,
            reason: "pnpm build",
            childArguments: ["pnpm", "build"],
            shortcutScript: "pnpm-build.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "pnpm-test",
            title: "pnpm test",
            workload: "test",
            duration: "20m",
            maxRPMPercent: 70,
            reason: "pnpm test",
            childArguments: ["pnpm", "test"],
            shortcutScript: "pnpm-test.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "bun-build",
            title: "Bun build",
            workload: "build",
            duration: "25m",
            maxRPMPercent: 75,
            reason: "bun run build",
            childArguments: ["bun", "run", "build"],
            shortcutScript: "bun-build.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "bun-test",
            title: "Bun test",
            workload: "test",
            duration: "20m",
            maxRPMPercent: 70,
            reason: "bun test",
            childArguments: ["bun", "test"],
            shortcutScript: "bun-test.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "go-build",
            title: "Go build",
            workload: "build",
            duration: "25m",
            maxRPMPercent: 75,
            reason: "go build",
            childArguments: ["go", "build"],
            shortcutScript: "go-build.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "go-test",
            title: "Go test",
            workload: "test",
            duration: "20m",
            maxRPMPercent: 70,
            reason: "go test",
            childArguments: ["go", "test"],
            shortcutScript: "go-test.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "cargo-build",
            title: "Cargo build",
            workload: "build",
            duration: "25m",
            maxRPMPercent: 75,
            reason: "cargo build",
            childArguments: ["cargo", "build"],
            shortcutScript: "cargo-build.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "cargo-test",
            title: "Cargo test",
            workload: "test",
            duration: "20m",
            maxRPMPercent: 70,
            reason: "cargo test",
            childArguments: ["cargo", "test"],
            shortcutScript: "cargo-test.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "uv-build",
            title: "uv build",
            workload: "build",
            duration: "25m",
            maxRPMPercent: 75,
            reason: "uv build",
            childArguments: ["uv", "build"],
            shortcutScript: "uv-build.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "uv-test",
            title: "uv pytest",
            workload: "test",
            duration: "20m",
            maxRPMPercent: 70,
            reason: "uv pytest",
            childArguments: ["uv", "run", "pytest"],
            shortcutScript: "uv-test.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "pytest",
            title: "pytest",
            workload: "test",
            duration: "20m",
            maxRPMPercent: 70,
            reason: "pytest",
            childArguments: ["python3", "-m", "pytest"],
            shortcutScript: "pytest.sh",
            shortcutArguments: []
        ),
        WorkloadCommandTemplate(
            id: "local-model-template",
            title: "Local model template",
            workload: "localModel",
            duration: "30m",
            maxRPMPercent: 75,
            reason: "local model run",
            childArguments: ["./run-local-model.sh"],
            shortcutScript: "local-model.sh",
            shortcutArguments: ["--", "./run-local-model.sh"]
        ),
        WorkloadCommandTemplate(
            id: "custom-workload-template",
            title: "Custom workload template",
            workload: "custom",
            duration: "15m",
            maxRPMPercent: 65,
            reason: "custom workload",
            childArguments: ["./scripts/smoke-test.sh"],
            shortcutScript: "custom-workload.sh",
            shortcutArguments: ["15m", "65", "custom workload", "--", "./scripts/smoke-test.sh"]
        )
    ]

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

        From capabilities, require `schemaVersion: 1`, `schemaIDs.diagnose`, `schemaIDs.commandError`, `schemaIDs.run`, `wrapperResources`, `runLifecycle.resolvedChildExecutableReported: true`, `policyStatusAvailable: true`, `policy.enabled: true`, and support for the requested workload before trusting policy limits or wrapper output.

        Use `wrapperResources.bundleDirectory`, `wrapperResources.sourceDirectory`, `wrapperResources.guardedRunScript`, and `wrapperResources.workloadScripts` to choose the installed or source wrapper instead of inventing unaudited fan-control commands.

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
