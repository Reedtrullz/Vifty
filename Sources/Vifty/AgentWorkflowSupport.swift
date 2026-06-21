import AppKit
import Foundation

enum AgentWorkflowSupport {
    static let copyHelp = "Copy a pasteable AGENTS.md/Codex rule that uses viftyctl diagnose and guarded-run wrappers before any agent/build/test cooling."
    static let copiedMessage = "Copied safe agent rule"

    private static let canonicalAppPath = "/Applications/Vifty.app"
    private static let guardedRunResourcePath = "Contents/Resources/viftyctl-wrappers/guarded-run.sh"

    static func agentRule(
        bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> String {
        let paths = agentWorkflowPaths(bundleURL: bundleURL, fileManager: fileManager)
        let diagnoseCommand = "\(shellQuote(paths.viftyCtlPath)) diagnose --json"
        let runCommand = "\(shellQuote(paths.guardedRunPath)) test 20m 70 'swift test' -- swift test"
        let preflightCommand = "\(shellQuote(paths.guardedRunPath)) --preflight-only test 20m 70 'swift test' -- swift test"

        return """
        For long local build/test/model workloads on this Mac, use Vifty only through the guarded local CLI.

        Before requesting cooling, run:

        ```sh
        \(diagnoseCommand)
        ```

        If `state` is `blocked`, `safeToRequestCooling` is false, `daemonControlPathReady` is false, `manualControlActive` is true, or `coolingBlockerIDs` is non-empty, do not request cooling. Show the JSON to the user and stop.

        Prefer the guarded wrapper for one child workload:

        ```sh
        \(runCommand)
        ```

        For read-only planning, use preflight mode:

        ```sh
        \(preflightCommand)
        ```

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

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
