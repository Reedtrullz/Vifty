import Foundation
import XCTest

final class AgentRunSmokeEvidenceScriptTests: XCTestCase {
    func testSmokeCollectorRunsBoundedRunAfterReadyDiagnoseAndCapturesFollowupEvidence() throws {
        let harness = try AgentRunSmokeEvidenceHarness()

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke evidence written"), result.stdout)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "capabilities --json",
                "diagnose --json",
                "run --workload test --duration 2m --max-rpm-percent 55 --reason agent run smoke test --json -- /bin/sleep 5",
                "capabilities --json",
                "status --json",
                "audit --limit 20 --json",
                "diagnose --json"
            ]
        )
        XCTAssertFalse(try harness.loggedArguments().contains { invocation in
            ["prepare", "restore-auto", "setFixed", "auto"].contains { invocation.hasPrefix($0) }
        })

        XCTAssertTrue(try harness.read("README.txt").contains("requests one bounded `viftyctl run --json` cooling lease"))
        XCTAssertTrue(try harness.read("README.txt").contains("supported Apple Silicon MacBook Pro hardware"))
        XCTAssertTrue(try harness.read("README.txt").contains("safe `runLifecycle` contract used by guarded wrappers"))
        XCTAssertTrue(try harness.read("README.txt").contains("`recommendedAgentAction` is either `requestCooling` or `requestCoolingWithCaution`"))
        XCTAssertTrue(try harness.read("README.txt").contains("Do not run this smoke test when readiness is blocked"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("readOnly=false"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("coolingCommandsRun=true"))

        let manifest = try harness.read("manifest.tsv")
        XCTAssertTrue(manifest.contains("name\tstatus\tstdout\tstderr"))
        XCTAssertTrue(manifest.contains("pre-capabilities\t0\tpre-capabilities.json\tpre-capabilities.stderr"))
        XCTAssertTrue(manifest.contains("pre-diagnose\t0\tpre-diagnose.json\tpre-diagnose.stderr"))
        XCTAssertTrue(manifest.contains("viftyctl-run\t0\tviftyctl-run.json\tviftyctl-run.stderr"))
        XCTAssertTrue(manifest.contains("post-capabilities\t0\tpost-capabilities.json\tpost-capabilities.stderr"))
        XCTAssertTrue(manifest.contains("post-status\t0\tpost-status.json\tpost-status.stderr"))
        XCTAssertTrue(manifest.contains("post-audit\t0\tpost-audit.json\tpost-audit.stderr"))
        XCTAssertTrue(manifest.contains("post-diagnose\t0\tpost-diagnose.json\tpost-diagnose.stderr"))
        XCTAssertEqual(try harness.read("viftyctl-run.status").trimmingCharacters(in: .whitespacesAndNewlines), "0")

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            summary["schemaID"] as? String,
            "https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json"
        )
        XCTAssertEqual(summary["kind"] as? String, "vifty-agent-run-smoke")
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["readOnly"] as? Bool, false)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, true)
        XCTAssertEqual(summary["workload"] as? String, "test")
        XCTAssertEqual(summary["duration"] as? String, "2m")
        XCTAssertEqual(summary["maxRPMPercent"] as? Int, 55)
        XCTAssertEqual(summary["reason"] as? String, "agent run smoke test")
        XCTAssertEqual(summary["childCommand"] as? [String], ["/bin/sleep", "5"])
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["state"] as? String, "ready")
        XCTAssertEqual(preflight["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(preflight["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(preflight["recommendedAgentAction"] as? String, "requestCooling")
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertEqual(run["exitStatus"] as? Int, 0)
        XCTAssertEqual(run["stdout"] as? String, "viftyctl-run.json")
        let commands = try XCTUnwrap(summary["commands"] as? [[String: Any]])
        XCTAssertEqual(commands.count, 7)

        let checksums = try harness.read("checksums.tsv")
        XCTAssertTrue(checksums.contains("sha256\tbytes\tfile"))
        XCTAssertTrue(checksums.contains("\tREADME.txt"))
        XCTAssertTrue(checksums.contains("\tmetadata.txt"))
        XCTAssertTrue(checksums.contains("\tmanifest.tsv"))
        XCTAssertTrue(checksums.contains("\tagent-run-smoke-evidence-summary.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-run.json"))
        XCTAssertTrue(checksums.contains("\tpost-audit.json"))
        XCTAssertFalse(checksums.contains("\tchecksums.tsv"))
    }

    func testSmokeCollectorBlocksBeforeRunWhenDiagnoseIsBlocked() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            diagnoseJSON: #"{"state":"blocked","recommendedAgentAction":"doNotRequestCooling","safeToRequestCooling":false,"daemonControlPathReady":false,"recommendedRecoveryAction":"repairHelper","checks":[]}"#,
            diagnoseExitCode: 75
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke skipped"), result.stdout)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "capabilities --json",
                "diagnose --json",
                "status --json",
                "audit --limit 20 --json"
            ]
        )
        XCTAssertFalse(try harness.loggedArguments().contains { $0.hasPrefix("run ") })
        XCTAssertEqual(try harness.read("pre-diagnose.status").trimmingCharacters(in: .whitespacesAndNewlines), "75")
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.outputURL.appendingPathComponent("viftyctl-run.status").path))

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(
            summary["schemaID"] as? String,
            "https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json"
        )
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["state"] as? String, "blocked")
        XCTAssertEqual(preflight["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(preflight["daemonControlPathReady"] as? Bool, false)
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertTrue(run["exitStatus"] is NSNull)
        XCTAssertEqual(run["skippedReason"] as? String, "readiness blocked before smoke run")
    }

    func testSmokeCollectorBlocksBeforeRunWhenCapabilitiesDoNotAdvertiseSafeRunLifecycle() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            capabilitiesJSON: #"{"schemaVersion":1,"daemonStatusAvailable":true,"policySource":"daemonStatus","commands":["status","capabilities","diagnose","audit","prepare","restore-auto"],"workloads":["build","test"],"supportsForceRetry":true,"policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"exitCodes":{"success":0,"commandFailure":1,"usage":64,"unavailable":69,"blockedReadiness":75},"runLifecycle":{"childCommandPreflightBeforeCooling":false,"signalsForwardedToChild":["INT"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256}}"#
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke skipped"), result.stdout)
        XCTAssertTrue(result.stdout.contains("capabilities preflight did not advertise safe viftyctl run"), result.stdout)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "capabilities --json",
                "diagnose --json",
                "status --json",
                "audit --limit 20 --json"
            ]
        )
        XCTAssertFalse(try harness.loggedArguments().contains { $0.hasPrefix("run ") })

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["state"] as? String, "ready")
        XCTAssertEqual(preflight["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(preflight["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(preflight["recommendedAgentAction"] as? String, "requestCooling")
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertTrue(run["exitStatus"] is NSNull)
        XCTAssertEqual(run["skippedReason"] as? String, "capabilities preflight did not advertise safe viftyctl run")
    }

    func testSmokeCollectorRunsWhenReadinessAllowsCoolingWithCaution() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            diagnoseJSON: #"{"state":"degraded","recommendedAgentAction":"requestCoolingWithCaution","safeToRequestCooling":true,"daemonControlPathReady":true,"recommendedRecoveryAction":"none","checks":[]}"#
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke evidence written"), result.stdout)
        XCTAssertTrue(try harness.loggedArguments().contains {
            $0 == "run --workload test --duration 2m --max-rpm-percent 55 --reason agent run smoke test --json -- /bin/sleep 5"
        })

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "passed")
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["state"] as? String, "degraded")
        XCTAssertEqual(preflight["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(preflight["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(preflight["recommendedAgentAction"] as? String, "requestCoolingWithCaution")
    }

    func testSmokeCollectorRejectsEmptyCustomChildBeforeCallingViftyCtl() throws {
        let harness = try AgentRunSmokeEvidenceHarness()

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("custom child command after -- cannot be empty"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.outputURL.path))
    }

    func testEvidenceSummarySchemaDocumentsCollectorContract() throws {
        let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/agent-run-smoke-evidence-summary.schema.json")
        let schema = try AgentRunSmokeEvidenceHarness.readJSON(schemaURL)

        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(
            schema["$id"] as? String,
            "https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json"
        )

        let required = try XCTUnwrap(schema["required"] as? [String])
        for field in [
            "schemaVersion",
            "schemaID",
            "kind",
            "status",
            "readOnly",
            "coolingCommandsRun",
            "preflight",
            "run",
            "commands"
        ] {
            XCTAssertTrue(required.contains(field), "missing required field \(field)")
        }
    }
}

private struct AgentRunSmokeProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

private final class AgentRunSmokeEvidenceHarness {
    let repositoryRoot: URL
    let rootURL: URL
    let outputURL: URL
    let viftyctlURL: URL
    let logURL: URL
    private let capabilitiesJSON: String
    private let diagnoseJSON: String
    private let diagnoseExitCode: Int
    private let statusJSON: String
    private let auditJSON: String
    private let runJSON: String
    private let runExitCode: Int

    init(
        capabilitiesJSON: String = AgentRunSmokeEvidenceHarness.defaultCapabilitiesJSON,
        diagnoseJSON: String = #"{"state":"ready","recommendedAgentAction":"requestCooling","safeToRequestCooling":true,"daemonControlPathReady":true,"recommendedRecoveryAction":"none","checks":[]}"#,
        diagnoseExitCode: Int = 0,
        statusJSON: String = #"{"enabled":true,"activeLease":null,"lastDecision":null}"#,
        auditJSON: String = #"{"readOnly":true,"coolingCommandsRun":false,"events":[]}"#,
        runJSON: String = #"{"schemaVersion":1,"command":"run","coolingLeasePrepared":true,"autoRestoreAttempted":true,"autoRestoreSucceeded":true,"childExitCode":0}"#,
        runExitCode: Int = 0
    ) throws {
        repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-agent-run-smoke-\(UUID().uuidString)", isDirectory: true)
        outputURL = rootURL.appendingPathComponent("smoke", isDirectory: true)
        viftyctlURL = rootURL.appendingPathComponent("Vifty.app/Contents/MacOS/viftyctl")
        logURL = rootURL.appendingPathComponent("viftyctl.log")
        self.capabilitiesJSON = capabilitiesJSON
        self.diagnoseJSON = diagnoseJSON
        self.diagnoseExitCode = diagnoseExitCode
        self.statusJSON = statusJSON
        self.auditJSON = auditJSON
        self.runJSON = runJSON
        self.runExitCode = runExitCode

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try writeFakeViftyCtl()
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func runCollector(_ arguments: [String]) throws -> AgentRunSmokeProcessResult {
        let script = repositoryRoot.appendingPathComponent("scripts/collect-agent-run-smoke-evidence.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = repositoryRoot
        process.arguments = [script.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "VIFTY_FAKE_LOG": logURL.path,
            "VIFTY_FAKE_CAPABILITIES_JSON": capabilitiesJSON,
            "VIFTY_FAKE_DIAGNOSE_JSON": diagnoseJSON,
            "VIFTY_FAKE_DIAGNOSE_EXIT": "\(diagnoseExitCode)",
            "VIFTY_FAKE_STATUS_JSON": statusJSON,
            "VIFTY_FAKE_AUDIT_JSON": auditJSON,
            "VIFTY_FAKE_RUN_JSON": runJSON,
            "VIFTY_FAKE_RUN_EXIT": "\(runExitCode)"
        ]) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return AgentRunSmokeProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    func read(_ relativePath: String) throws -> String {
        try String(contentsOf: outputURL.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func readJSON(_ relativePath: String) throws -> [String: Any] {
        try Self.readJSON(outputURL.appendingPathComponent(relativePath))
    }

    static func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func loggedArguments() throws -> [String] {
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return []
        }
        return try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    private func writeFakeViftyCtl() throws {
        try FileManager.default.createDirectory(
            at: viftyctlURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let script = """
        #!/bin/sh
        set -eu

        printf '%s\\n' "$*" >> "${VIFTY_FAKE_LOG}"

        case "$1" in
          capabilities)
            test "${2:-}" = "--json"
            printf '%s\\n' "${VIFTY_FAKE_CAPABILITIES_JSON}"
            ;;
          diagnose)
            test "${2:-}" = "--json"
            printf '%s\\n' "${VIFTY_FAKE_DIAGNOSE_JSON}"
            exit "${VIFTY_FAKE_DIAGNOSE_EXIT}"
            ;;
          status)
            test "${2:-}" = "--json"
            printf '%s\\n' "${VIFTY_FAKE_STATUS_JSON}"
            ;;
          audit)
            test "${2:-}" = "--limit"
            test "${4:-}" = "--json"
            printf '%s\\n' "${VIFTY_FAKE_AUDIT_JSON}"
            ;;
          run)
            printf '%s\\n' "${VIFTY_FAKE_RUN_JSON}"
            exit "${VIFTY_FAKE_RUN_EXIT}"
            ;;
          *)
            echo "unexpected command: $*" >&2
            exit 99
            ;;
        esac
        """
        try script.write(to: viftyctlURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: viftyctlURL.path
        )
    }

    private static let defaultCapabilitiesJSON = """
    {"schemaVersion":1,"daemonStatusAvailable":true,"policySource":"daemonStatus","commands":["status","capabilities","diagnose","audit","prepare","restore-auto","run"],"workloads":["build","test","render","localModel","custom"],"supportsForceRetry":true,"policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"exitCodes":{"success":0,"commandFailure":1,"usage":64,"unavailable":69,"blockedReadiness":75},"runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true},"directControlLifecycle":{"prepareUsesIdempotencyKey":true,"restoreAutoAcceptsIdempotencyKey":false,"restoreAutoScopedByIdempotencyKey":false,"preferRunForSingleChildWorkloads":true},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256}}
    """
}
