import Foundation
import XCTest

final class AgentRunSmokeReadinessScriptTests: XCTestCase {
    func testReadinessPassesWhenCapabilitiesAndDiagnoseSupportAgentRunSmoke() throws {
        let harness = try AgentRunSmokeReadinessHarness()

        let result = try harness.runReadiness(["--viftyctl", harness.viftyctlURL.path])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke readiness: ready"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Read-only preflight passed; no cooling command was run."), result.stdout)
        XCTAssertTrue(result.stdout.contains("safeToRequestCooling=true daemonControlPathReady=true manualControlActive=false"), result.stdout)
        XCTAssertTrue(result.stdout.contains("capabilities: daemonStatusAvailable=true policyStatusAvailable=true policyEnabled=true runLifecycleSafe=true"), result.stdout)
        XCTAssertEqual(try harness.loggedArguments(), ["capabilities --json", "diagnose --json"])
        XCTAssertFalse(try harness.loggedArguments().contains { invocation in
            ["prepare", "run", "restore-auto", "setFixed", "auto"].contains { invocation.hasPrefix($0) }
        })
    }

    func testJSONOutputBlocksWhenExpectedDaemonDoesNotMatchInstalledDaemon() throws {
        let harness = try AgentRunSmokeReadinessHarness(expectedDaemonContents: "different daemon")

        let result = try harness.runReadiness([
            "--viftyctl", harness.viftyctlURL.path,
            "--expected-daemon", harness.expectedDaemonURL.path,
            "--require-daemon-match",
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        let summary = try XCTUnwrap(AgentRunSmokeReadinessHarness.parseJSON(result.stdout))
        XCTAssertEqual(summary["kind"] as? String, "vifty-agent-run-smoke-readiness")
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(summary["schemaID"] as? String, "https://vifty.local/schemas/agent-run-smoke-readiness.schema.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["agentRunSmokeReady"] as? Bool, false)
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(summary["duration"] as? String, "2m")
        XCTAssertEqual(summary["durationSeconds"] as? Int, 120)
        XCTAssertEqual(summary["maxRPMPercent"] as? Int, 55)
        XCTAssertEqual(summary["capabilitiesExitStatus"] as? Int, 0)
        XCTAssertEqual(summary["diagnoseExitStatus"] as? Int, 0)
        XCTAssertEqual(summary["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(summary["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(summary["manualControlActive"] as? Bool, false)
        XCTAssertEqual(summary["blockers"] as? [String], ["installed daemon does not match expected build daemon"])

        let capabilities = try XCTUnwrap(summary["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilities["capabilitiesSchemaID"] as? String, "https://vifty.local/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(capabilities["diagnoseSchemaID"] as? String, "https://vifty.local/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(capabilities["commandErrorSchemaID"] as? String, "https://vifty.local/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(capabilities["runSchemaID"] as? String, "https://vifty.local/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(capabilities["daemonStatusAvailable"] as? Bool, true)
        XCTAssertEqual(capabilities["policyStatusAvailable"] as? Bool, true)
        XCTAssertEqual(capabilities["policyEnabled"] as? Bool, true)
        XCTAssertEqual(capabilities["runCommandAvailable"] as? Bool, true)
        XCTAssertEqual(capabilities["testWorkloadAvailable"] as? Bool, true)
        XCTAssertEqual(capabilities["runLifecycleSafe"] as? Bool, true)
        XCTAssertEqual(capabilities["wrapperResourcesSafe"] as? Bool, true)
        XCTAssertEqual(capabilities["requestedDurationWithinPolicy"] as? Bool, true)
        XCTAssertEqual(capabilities["requestedRPMPercentWithinPolicy"] as? Bool, true)
        XCTAssertEqual(capabilities["reasonWithinMetadataLimit"] as? Bool, true)

        let daemonRuntime = try XCTUnwrap(summary["daemonRuntime"] as? [String: Any])
        XCTAssertEqual(daemonRuntime["installedDaemonPath"] as? String, harness.installedDaemonURL.path)
        XCTAssertEqual(daemonRuntime["installedDaemonPresent"] as? Bool, true)
        XCTAssertNotNil(daemonRuntime["installedDaemonSHA256"] as? String)
        XCTAssertEqual(daemonRuntime["expectedDaemonPath"] as? String, harness.expectedDaemonURL.path)
        XCTAssertNotNil(daemonRuntime["expectedDaemonSHA256"] as? String)
        XCTAssertEqual(daemonRuntime["matchesExpectedDaemon"] as? Bool, false)
        XCTAssertEqual(daemonRuntime["matchRequired"] as? Bool, true)

        let parseErrors = try XCTUnwrap(summary["parseErrors"] as? [String: Any])
        XCTAssertTrue(parseErrors["capabilities"] is NSNull)
        XCTAssertTrue(parseErrors["diagnose"] is NSNull)
        XCTAssertEqual(try harness.loggedArguments(), ["capabilities --json", "diagnose --json"])
    }

    func testReadinessBlocksFallbackCapabilitiesBeforeCoolingBoundary() throws {
        let harness = try AgentRunSmokeReadinessHarness(
            capabilitiesJSON: AgentRunSmokeReadinessHarness.capabilitiesJSON(
                daemonStatusAvailable: false,
                policyStatusAvailable: false,
                policySource: "fallbackUnavailable",
                policyEnabled: false
            ),
            capabilitiesExitCode: 69
        )

        let result = try harness.runReadiness(["--viftyctl", harness.viftyctlURL.path])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke readiness: blocked"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Do not run supervised viftyctl run smoke."), result.stdout)
        XCTAssertTrue(result.stdout.contains("- capabilities preflight did not complete successfully"), result.stdout)
        XCTAssertTrue(result.stdout.contains("- capabilities are not daemon-backed"), result.stdout)
        XCTAssertTrue(result.stdout.contains("- capabilities policy status is unavailable"), result.stdout)
        XCTAssertTrue(result.stdout.contains("- agent cooling policy is disabled"), result.stdout)
        XCTAssertEqual(try harness.loggedArguments(), ["capabilities --json", "diagnose --json"])
    }

    func testReadinessSchemaIsDocumentedForEvidenceConsumers() throws {
        let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/agent-run-smoke-readiness.schema.json")
        let schema = try XCTUnwrap(AgentRunSmokeReadinessHarness.readJSON(schemaURL))

        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(schema["$id"] as? String, "https://vifty.local/schemas/agent-run-smoke-readiness.schema.json")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual((properties["schemaVersion"] as? [String: Any])?["const"] as? Int, 1)
        XCTAssertEqual((properties["schemaID"] as? [String: Any])?["const"] as? String, "https://vifty.local/schemas/agent-run-smoke-readiness.schema.json")
        XCTAssertEqual((properties["readOnly"] as? [String: Any])?["const"] as? Bool, true)
        XCTAssertEqual((properties["coolingCommandsRun"] as? [String: Any])?["const"] as? Bool, false)
        XCTAssertNotNil(properties["capabilities"] as? [String: Any])
        XCTAssertNotNil(properties["daemonRuntime"] as? [String: Any])
        XCTAssertNotNil(properties["failedCheckIDs"] as? [String: Any])
        XCTAssertNotNil(properties["coolingBlockerIDs"] as? [String: Any])
        XCTAssertNotNil(properties["appPreferences"] as? [String: Any])
    }
}

private struct AgentRunSmokeReadinessProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

private final class AgentRunSmokeReadinessHarness {
    let repositoryRoot: URL
    let rootURL: URL
    let viftyctlURL: URL
    let logURL: URL
    let installedDaemonURL: URL
    let expectedDaemonURL: URL
    private let capabilitiesJSON: String
    private let capabilitiesExitCode: Int
    private let diagnoseJSON: String
    private let diagnoseExitCode: Int

    init(
        capabilitiesJSON: String = AgentRunSmokeReadinessHarness.capabilitiesJSON(),
        capabilitiesExitCode: Int = 0,
        diagnoseJSON: String = AgentRunSmokeReadinessHarness.diagnoseJSON(),
        diagnoseExitCode: Int = 0,
        installedDaemonContents: String = "installed daemon",
        expectedDaemonContents: String = "installed daemon"
    ) throws {
        repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-agent-run-smoke-readiness-\(UUID().uuidString)", isDirectory: true)
        viftyctlURL = rootURL.appendingPathComponent("fake-bin/viftyctl")
        logURL = rootURL.appendingPathComponent("viftyctl.log")
        installedDaemonURL = rootURL.appendingPathComponent("installed-daemon")
        expectedDaemonURL = rootURL.appendingPathComponent("expected-daemon")
        self.capabilitiesJSON = capabilitiesJSON
        self.capabilitiesExitCode = capabilitiesExitCode
        self.diagnoseJSON = diagnoseJSON
        self.diagnoseExitCode = diagnoseExitCode

        try FileManager.default.createDirectory(
            at: viftyctlURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try installedDaemonContents.write(to: installedDaemonURL, atomically: true, encoding: .utf8)
        try expectedDaemonContents.write(to: expectedDaemonURL, atomically: true, encoding: .utf8)
        try writeFakeViftyCtl()
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func runReadiness(_ arguments: [String]) throws -> AgentRunSmokeReadinessProcessResult {
        let script = repositoryRoot.appendingPathComponent("scripts/check-agent-run-smoke-readiness.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = repositoryRoot
        process.arguments = [script.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "VIFTY_TEST_SHELL_FIXTURES": "1",
            "VIFTY_FAKE_LOG": logURL.path,
            "VIFTY_FAKE_CAPABILITIES_JSON": capabilitiesJSON,
            "VIFTY_FAKE_CAPABILITIES_EXIT": "\(capabilitiesExitCode)",
            "VIFTY_FAKE_DIAGNOSE_JSON": diagnoseJSON,
            "VIFTY_FAKE_DIAGNOSE_EXIT": "\(diagnoseExitCode)",
            "VIFTY_AGENT_RUN_SMOKE_INSTALLED_DAEMON_PATH": installedDaemonURL.path
        ]) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return AgentRunSmokeReadinessProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    func loggedArguments() throws -> [String] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return [] }
        return try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    static func parseJSON(_ text: String) throws -> [String: Any]? {
        let data = Data(text.utf8)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func readJSON(_ url: URL) throws -> [String: Any]? {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func capabilitiesJSON(
        daemonStatusAvailable: Bool = true,
        policyStatusAvailable: Bool = true,
        policySource: String = "daemonStatus",
        policyEnabled: Bool = true
    ) -> String {
        """
        {"schemaVersion":1,"daemonStatusAvailable":\(daemonStatusAvailable),"policyStatusAvailable":\(policyStatusAvailable),"policySource":"\(policySource)","commands":["status","capabilities","diagnose","audit","prepare","restore-auto","run"],"workloads":["build","test","render","localModel","custom"],"supportsForceRetry":true,"policy":{"enabled":\(policyEnabled),"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true,"resolvedChildExecutableReported":true},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256},"wrapperResources":{"sourceDirectory":"examples/viftyctl","bundleDirectory":"Contents/Resources/viftyctl-wrappers","guardedRunScript":"guarded-run.sh","workloadScripts":["cargo-build.sh","cargo-test.sh","custom-workload.sh","go-build.sh","go-test.sh","local-model.sh","make-build.sh","make-test.sh","make-verify.sh","npm-build.sh","npm-test.sh","pytest.sh","swift-release-build.sh","swift-test.sh","xcode-build.sh","xcode-test.sh"]},"schemaIDs":{"capabilities":"https://vifty.local/schemas/viftyctl-capabilities.schema.json","audit":"https://vifty.local/schemas/viftyctl-audit.schema.json","diagnose":"https://vifty.local/schemas/viftyctl-diagnose.schema.json","status":"https://vifty.local/schemas/viftyctl-status.schema.json","commandError":"https://vifty.local/schemas/viftyctl-command-error.schema.json","run":"https://vifty.local/schemas/viftyctl-run.schema.json"}}
        """
    }

    static func diagnoseJSON(
        state: String = "ready",
        recommendedAgentAction: String = "requestCooling",
        recommendedRecoveryAction: String = "none",
        safeToRequestCooling: Bool = true,
        daemonControlPathReady: Bool = true,
        manualControlActive: Bool = false
    ) -> String {
        """
        {"schemaVersion":1,"schemaID":"https://vifty.local/schemas/viftyctl-diagnose.schema.json","state":"\(state)","modelIdentifier":"MacBookPro18,1","isAppleSilicon":true,"isMacBookPro":true,"recommendedAgentAction":"\(recommendedAgentAction)","recommendedRecoveryAction":"\(recommendedRecoveryAction)","safeToRequestCooling":\(safeToRequestCooling),"daemonControlPathReady":\(daemonControlPathReady),"manualControlActive":\(manualControlActive),"fanCount":2,"controllableFanCount":2,"temperatureSensorCount":6,"thermalPressure":"nominal","failedCheckIDs":[],"coolingBlockerIDs":[],"appPreferences":{"startupMode":"Auto","startupModeSource":"persisted","readError":null}}
        """
    }

    private func writeFakeViftyCtl() throws {
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$VIFTY_FAKE_LOG"
        if [ "$*" = "capabilities --json" ]; then
          printf '%s\\n' "$VIFTY_FAKE_CAPABILITIES_JSON"
          exit "$VIFTY_FAKE_CAPABILITIES_EXIT"
        fi
        if [ "$*" = "diagnose --json" ]; then
          printf '%s\\n' "$VIFTY_FAKE_DIAGNOSE_JSON"
          exit "$VIFTY_FAKE_DIAGNOSE_EXIT"
        fi
        echo "unexpected viftyctl args: $*" >&2
        exit 64
        """
        try script.write(to: viftyctlURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: viftyctlURL.path)
    }
}
