import Foundation

public enum ViftyAgentRuleWorkloadCommandMode: String, CaseIterable, Identifiable, Sendable {
    case run
    case preflight

    public var id: String { rawValue }
}

public struct ViftyAgentRuleCommands: Codable, Equatable, Sendable {
    public var viftyctlCommand: String
    public var capabilitiesCommand: String
    public var diagnoseCommand: String
    public var guardedRunCommand: String
    public var guardedRunPreflightCommand: String

    public init(
        viftyctlCommand: String,
        capabilitiesCommand: String,
        diagnoseCommand: String,
        guardedRunCommand: String,
        guardedRunPreflightCommand: String
    ) {
        self.viftyctlCommand = viftyctlCommand
        self.capabilitiesCommand = capabilitiesCommand
        self.diagnoseCommand = diagnoseCommand
        self.guardedRunCommand = guardedRunCommand
        self.guardedRunPreflightCommand = guardedRunPreflightCommand
    }
}

public struct ViftyAgentRuleJSONMarkerPair: Codable, Equatable, Sendable {
    public var begin: String
    public var end: String

    public init(begin: String, end: String) {
        self.begin = begin
        self.end = end
    }
}

public struct ViftyAgentRuleJSONMarkers: Codable, Equatable, Sendable {
    public var capabilities: ViftyAgentRuleJSONMarkerPair
    public var diagnose: ViftyAgentRuleJSONMarkerPair
    public var decision: ViftyAgentRuleJSONMarkerPair

    public init(
        capabilities: ViftyAgentRuleJSONMarkerPair,
        diagnose: ViftyAgentRuleJSONMarkerPair,
        decision: ViftyAgentRuleJSONMarkerPair
    ) {
        self.capabilities = capabilities
        self.diagnose = diagnose
        self.decision = decision
    }
}

public struct ViftyCtlAgentRuleReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var schemaID: String
    public var command: String
    public var generatedAt: Date
    public var rule: String
    public var viftyctlCommand: String
    public var capabilitiesCommand: String
    public var diagnoseCommand: String
    public var repairHelperRecoveryActions: [String]?
    public var guardedRunDecisionSchemaID: String
    public var guardedRunJSONMarkers: ViftyAgentRuleJSONMarkers
    public var guardedRunCommand: String
    public var guardedRunPreflightCommand: String
    public var schemaRequirements: [String]
    public var safetyRequirements: [String]
    public var forbiddenActions: [String]
    public var workloadTemplateIDs: [String]

    public init(
        schemaVersion: Int = 1,
        schemaID: String = ViftyCtlSchemaReferences.schemaIDs.agentRule,
        command: String = "agent-rule",
        generatedAt: Date,
        rule: String,
        commands: ViftyAgentRuleCommands,
        repairHelperRecoveryActions: [String]? = ViftyAgentRule.repairHelperRecoveryActions,
        guardedRunDecisionSchemaID: String = ViftyAgentRule.guardedRunDecisionSchemaID,
        guardedRunJSONMarkers: ViftyAgentRuleJSONMarkers = ViftyAgentRule.guardedRunJSONMarkers,
        schemaRequirements: [String] = ViftyAgentRule.schemaRequirements,
        safetyRequirements: [String] = ViftyAgentRule.safetyRequirements,
        forbiddenActions: [String] = ViftyAgentRule.forbiddenActions,
        workloadTemplateIDs: [String] = ViftyCtlWorkloadTemplate.auditedTemplates.map(\.id)
    ) {
        self.schemaVersion = schemaVersion
        self.schemaID = schemaID
        self.command = command
        self.generatedAt = generatedAt
        self.rule = rule
        self.viftyctlCommand = commands.viftyctlCommand
        self.capabilitiesCommand = commands.capabilitiesCommand
        self.diagnoseCommand = commands.diagnoseCommand
        self.repairHelperRecoveryActions = repairHelperRecoveryActions
        self.guardedRunDecisionSchemaID = guardedRunDecisionSchemaID
        self.guardedRunJSONMarkers = guardedRunJSONMarkers
        self.guardedRunCommand = commands.guardedRunCommand
        self.guardedRunPreflightCommand = commands.guardedRunPreflightCommand
        self.schemaRequirements = schemaRequirements
        self.safetyRequirements = safetyRequirements
        self.forbiddenActions = forbiddenActions
        self.workloadTemplateIDs = workloadTemplateIDs
    }
}

public enum ViftyAgentRule {
    public static let canonicalAppPath = "/Applications/Vifty.app"
    public static let canonicalViftyCtlPath = "/Applications/Vifty.app/Contents/MacOS/viftyctl"
    public static let guardedRunResourcePath = "Contents/Resources/viftyctl-wrappers/guarded-run.sh"
    public static let guardedRunDecisionSchemaID = "https://vifty.local/schemas/guarded-run-decision.schema.json"
    public static let guardedRunJSONMarkers = ViftyAgentRuleJSONMarkers(
        capabilities: ViftyAgentRuleJSONMarkerPair(
            begin: "guarded-run: BEGIN_VIFTY_CAPABILITIES_JSON",
            end: "guarded-run: END_VIFTY_CAPABILITIES_JSON"
        ),
        diagnose: ViftyAgentRuleJSONMarkerPair(
            begin: "guarded-run: BEGIN_VIFTY_DIAGNOSE_JSON",
            end: "guarded-run: END_VIFTY_DIAGNOSE_JSON"
        ),
        decision: ViftyAgentRuleJSONMarkerPair(
            begin: "guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON",
            end: "guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON"
        )
    )

    public static let schemaRequirements = [
        "schemaVersion == 1",
        "schemaIDs.capabilities",
        "schemaIDs.diagnose",
        "schemaIDs.commandError",
        "schemaIDs.run",
        "schemaIDs.agentRule",
        "guardedRunDecisionSchemaID",
        "guardedRunJSONMarkers",
        "wrapperResources",
        "workloadTemplates",
        "runLifecycle.resolvedChildExecutableReported == true"
    ]

    public static let safetyRequirements = [
        "policyStatusAvailable == true",
        "policy.enabled == true",
        "safeToRequestCooling == true",
        "daemonControlPathReady == true",
        "manualControlActive == false",
        "coolingBlockerIDs is empty"
    ]

    public static let repairHelperRecoveryActions = [
        "Open Vifty and use Repair/Reinstall Helper, then approve Login Items if macOS asks.",
        "In a source checkout, run make repair-helper for the same explicit administrator-approved LaunchDaemon repair.",
        "After repair, rerun diagnose --json and require safe readiness before requesting cooling."
    ]

    public static let forbiddenActions = [
        "ViftyHelper setFixed",
        "ViftyHelper auto",
        "sudo",
        "raw SMC tools",
        "direct fan RPM writes",
        "unguarded viftyctl prepare"
    ]

    public static func rule(
        bundleURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> String {
        let commands = agentRuleCommands(bundleURL: bundleURL, fileManager: fileManager)

        return """
        For long local build/test/model workloads on this Mac, use Vifty only through the guarded local CLI.

        Before requesting cooling, run:

        ```sh
        \(commands.capabilitiesCommand)
        \(commands.diagnoseCommand)
        ```

        From capabilities, require `schemaVersion: 1`, `schemaIDs.capabilities`, `schemaIDs.diagnose`, `schemaIDs.commandError`, `schemaIDs.run`, `schemaIDs.agentRule`, `wrapperResources`, `workloadTemplates`, `runLifecycle.resolvedChildExecutableReported: true`, `policyStatusAvailable: true`, `policy.enabled: true`, and support for the requested workload before trusting policy limits, copied command templates, or wrapper output.

        Use `wrapperResources.bundleDirectory`, `wrapperResources.sourceDirectory`, `wrapperResources.guardedRunScript`, `wrapperResources.workloadScripts`, and `workloadTemplates` to choose the installed or source wrapper and audited workload defaults instead of inventing unaudited fan-control commands.

        If `state` is `blocked`, `safeToRequestCooling` is false, `daemonControlPathReady` is false, `manualControlActive` is true, or `coolingBlockerIDs` is non-empty, do not request cooling. Show the JSON to the user and stop.

        If `recommendedRecoveryAction` is `repairHelper`, show `repairHelperRecoveryActions` from this report when present: open Vifty and use Repair/Reinstall Helper, or in a source checkout run `make repair-helper` as an explicit administrator-approved repair, then rerun `diagnose --json`. Do not request cooling, use uncooled fallback, or call direct SMC/helper commands while repair is pending.

        Prefer the guarded wrapper for one child workload:

        ```sh
        \(commands.guardedRunCommand)
        ```

        For read-only planning, use preflight mode:

        ```sh
        \(commands.guardedRunPreflightCommand)
        ```

        When guarded-run refuses before cooling or completes preflight-only, extract only the JSON payload between the marker pairs in `guardedRunJSONMarkers`: use `guardedRunJSONMarkers.capabilities.begin` / `.end`, `guardedRunJSONMarkers.diagnose.begin` / `.end`, and `guardedRunJSONMarkers.decision.begin` / `.end` instead of hardcoding marker strings. Decision payloads must use the `guardedRunDecisionSchemaID` from this report, include `decisionReason` and `recoverySteps`, and preflight-only success must report `coolingRequested: false`. Do not parse surrounding recovery prose.

        Leave `VIFTY_GUARDED_RUN_FORCE_RETRY` and `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED` unset unless the user explicitly approves that supervised behavior after seeing Vifty's structured readiness output. Do not catch a guarded-run failure and rerun the same workload without Vifty.

        Never call `ViftyHelper setFixed`, `ViftyHelper auto`, `sudo`, raw SMC tools, direct fan RPM writes, or unguarded `viftyctl prepare` from an agent.
        """
    }

    public static func report(
        generatedAt: Date,
        bundleURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> ViftyCtlAgentRuleReport {
        let commands = agentRuleCommands(bundleURL: bundleURL, fileManager: fileManager)
        return ViftyCtlAgentRuleReport(
            generatedAt: generatedAt,
            rule: rule(bundleURL: bundleURL, fileManager: fileManager),
            commands: commands
        )
    }

    public static func agentRuleCommands(
        bundleURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> ViftyAgentRuleCommands {
        let paths = agentWorkflowPaths(bundleURL: bundleURL, fileManager: fileManager)
        let viftyctl = shellQuote(paths.viftyCtlPath)
        let swiftTestTemplate = ViftyCtlWorkloadTemplate.auditedTemplates[0]
        return ViftyAgentRuleCommands(
            viftyctlCommand: viftyctl,
            capabilitiesCommand: "\(viftyctl) capabilities --json",
            diagnoseCommand: "\(viftyctl) diagnose --json",
            guardedRunCommand: workloadCommand(
                swiftTestTemplate,
                mode: .run,
                bundleURL: bundleURL,
                fileManager: fileManager
            ),
            guardedRunPreflightCommand: workloadCommand(
                swiftTestTemplate,
                mode: .preflight,
                bundleURL: bundleURL,
                fileManager: fileManager
            )
        )
    }

    public static func workloadCommand(
        _ template: ViftyCtlWorkloadTemplate,
        mode: ViftyAgentRuleWorkloadCommandMode,
        bundleURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> String {
        let paths = agentWorkflowPaths(bundleURL: bundleURL, fileManager: fileManager)

        switch mode {
        case .run:
            let shortcutPath = wrapperScriptPath(named: template.shortcutScript, guardedRunPath: paths.guardedRunPath)
            let command = ([shortcutPath] + template.shortcutArguments)
                .map(shellQuote)
                .joined(separator: " ")
            return commandWithViftyCtlEnvironmentIfNeeded(command, paths: paths)
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
            let command = arguments.map(shellQuote).joined(separator: " ")
            return commandWithViftyCtlEnvironmentIfNeeded(command, paths: paths)
        }
    }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func agentWorkflowPaths(
        bundleURL: URL?,
        fileManager: FileManager
    ) -> (viftyCtlPath: String, guardedRunPath: String, requiresExplicitViftyCtlEnvironment: Bool) {
        if let bundleURL {
            let bundledTool = bundleURL.appendingPathComponent("Contents/MacOS/viftyctl", isDirectory: false)
            let bundledGuardedRun = bundleURL.appendingPathComponent(guardedRunResourcePath, isDirectory: false)
            if bundleURL.pathExtension == "app",
               fileManager.isExecutableFile(atPath: bundledTool.path),
               fileManager.isExecutableFile(atPath: bundledGuardedRun.path) {
                return (
                    bundledTool.path,
                    bundledGuardedRun.path,
                    bundledTool.path != canonicalViftyCtlPath
                )
            }

            if bundleURL.pathExtension != "app",
               let sourcePaths = sourceCheckoutPaths(near: bundleURL, fileManager: fileManager) {
                return sourcePaths
            }
        }

        return (
            canonicalViftyCtlPath,
            "\(canonicalAppPath)/\(guardedRunResourcePath)",
            false
        )
    }

    private static func sourceCheckoutPaths(
        near bundleURL: URL,
        fileManager: FileManager
    ) -> (viftyCtlPath: String, guardedRunPath: String, requiresExplicitViftyCtlEnvironment: Bool)? {
        for candidate in ancestorDirectories(startingAt: bundleURL) {
            let packageManifest = candidate.appendingPathComponent("Package.swift", isDirectory: false)
            let guardedRun = candidate.appendingPathComponent("examples/viftyctl/guarded-run.sh", isDirectory: false)
            guard fileManager.fileExists(atPath: packageManifest.path),
                  fileManager.isExecutableFile(atPath: guardedRun.path)
            else {
                continue
            }

            let candidateViftyCtlPaths = [
                bundleURL.appendingPathComponent("ViftyCtl", isDirectory: false),
                candidate.appendingPathComponent(".build/debug/ViftyCtl", isDirectory: false),
                candidate.appendingPathComponent(".build/release/ViftyCtl", isDirectory: false),
                candidate.appendingPathComponent(".build/Vifty.app/Contents/MacOS/viftyctl", isDirectory: false)
            ]
            guard let viftyCtl = candidateViftyCtlPaths.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) else {
                continue
            }
            return (viftyCtl.path, guardedRun.path, true)
        }
        return nil
    }

    private static func ancestorDirectories(startingAt url: URL) -> [URL] {
        var result: [URL] = []
        var visited: Set<String> = []
        var currentPath = (url.path as NSString).standardizingPath

        for _ in 0..<128 {
            guard !currentPath.isEmpty, visited.insert(currentPath).inserted else {
                break
            }
            result.append(URL(fileURLWithPath: currentPath, isDirectory: true))

            let parentPath = (currentPath as NSString).deletingLastPathComponent
            if parentPath.isEmpty || parentPath == currentPath {
                break
            }
            currentPath = parentPath
        }
        return result
    }

    private static func wrapperScriptPath(named scriptName: String, guardedRunPath: String) -> String {
        let guardedRunURL = URL(fileURLWithPath: guardedRunPath)
        return guardedRunURL
            .deletingLastPathComponent()
            .appendingPathComponent(scriptName, isDirectory: false)
            .path
    }

    private static func commandWithViftyCtlEnvironmentIfNeeded(
        _ command: String,
        paths: (viftyCtlPath: String, guardedRunPath: String, requiresExplicitViftyCtlEnvironment: Bool)
    ) -> String {
        guard paths.requiresExplicitViftyCtlEnvironment else {
            return command
        }
        return "VIFTYCTL=\(shellQuote(paths.viftyCtlPath)) \(command)"
    }
}
