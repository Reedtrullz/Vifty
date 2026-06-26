import Foundation
import XCTest

final class ManualSmokeReadinessScriptTests: XCTestCase {
    func testReadinessPassesWhenDiagnoseSupportsHumanManualSmoke() throws {
        let harness = try ManualSmokeReadinessHarness()

        let result = try harness.runReadiness(["--viftyctl", harness.viftyctlURL.path])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Manual smoke readiness: ready"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Read-only preflight passed; no cooling command was run."), result.stdout)
        XCTAssertTrue(result.stdout.contains("safeToRequestCooling=true daemonControlPathReady=true manualControlActive=false"), result.stdout)
        XCTAssertEqual(try harness.loggedArguments(), ["diagnose --json"])
        XCTAssertFalse(try harness.loggedArguments().contains { invocation in
            ["prepare", "run", "restore-auto", "setFixed", "auto"].contains { invocation.hasPrefix($0) }
        })
    }

    func testReadinessBlocksWhenManualControlIsActive() throws {
        let harness = try ManualSmokeReadinessHarness(
            diagnoseJSON: #"{"state":"degraded","modelIdentifier":"MacBookPro18,1","isAppleSilicon":true,"isMacBookPro":true,"recommendedAgentAction":"restoreAutoBeforeRequestingCooling","recommendedRecoveryAction":"restoreAutoBeforeRetry","safeToRequestCooling":false,"daemonControlPathReady":true,"manualControlActive":true,"fanCount":2,"controllableFanCount":2,"temperatureSensorCount":6,"thermalPressure":"nominal","failedCheckIDs":["manualControlClear"],"coolingBlockerIDs":["manualControlClear"],"appPreferences":{"startupMode":"Curve","startupModeSource":"persisted","readError":null}}"#
        )

        let result = try harness.runReadiness(["--viftyctl", harness.viftyctlURL.path])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        XCTAssertTrue(result.stdout.contains("Manual smoke readiness: blocked"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Do not run manual Fixed/Curve fan-write smoke."), result.stdout)
        XCTAssertTrue(result.stdout.contains("- manual control active before manual smoke"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Startup mode: Curve (persisted)"), result.stdout)
        XCTAssertTrue(result.stdout.contains("Restore Auto in Vifty, wait until manualControlActive=false"), result.stdout)
        XCTAssertEqual(try harness.loggedArguments(), ["diagnose --json"])
    }

    func testJSONOutputKeepsMachineReadableReadOnlyDecision() throws {
        let operatorRecoveryCommands = #"""
        [{"id":"restore-auto-current-app","title":"Restore Auto from this Vifty app bundle","command":"'/Applications/Vifty.app/Contents/MacOS/viftyctl' restore-auto --json --reason 'operator recovery before agent cooling'","workingDirectoryHint":"Run from any directory.","requiresUserApproval":true,"safeForAgentsToRunAutomatically":false,"notes":["Requires an explicit human decision.","Run at most once."]}]
        """#
        let harness = try ManualSmokeReadinessHarness(
            diagnoseJSON: #"{"state":"degraded","modelIdentifier":"MacBookPro18,1","isAppleSilicon":true,"isMacBookPro":true,"recommendedAgentAction":"restoreAutoBeforeRequestingCooling","recommendedRecoveryAction":"restoreAutoBeforeRetry","operatorRecoveryCommands":\#(operatorRecoveryCommands),"safeToRequestCooling":false,"daemonControlPathReady":true,"manualControlActive":true,"fanCount":2,"controllableFanCount":2,"temperatureSensorCount":6,"thermalPressure":"nominal","failedCheckIDs":["manualControlClear"],"coolingBlockerIDs":["manualControlClear"],"appPreferences":{"startupMode":"Curve","startupModeSource":"persisted","readError":null}}"#
        )

        let result = try harness.runReadiness([
            "--viftyctl", harness.viftyctlURL.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        let summary = try XCTUnwrap(ManualSmokeReadinessHarness.parseJSON(result.stdout))
        XCTAssertEqual(summary["kind"] as? String, "vifty-manual-smoke-readiness")
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(summary["schemaID"] as? String, "https://vifty.local/schemas/manual-smoke-readiness.schema.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["manualSmokeReady"] as? Bool, false)
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(summary["diagnoseExitStatus"] as? Int, 0)
        XCTAssertEqual(summary["modelIdentifier"] as? String, "MacBookPro18,1")
        XCTAssertEqual(summary["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(summary["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(summary["manualControlActive"] as? Bool, true)
        XCTAssertEqual(summary["failedCheckIDs"] as? [String], ["manualControlClear"])
        XCTAssertEqual(summary["coolingBlockerIDs"] as? [String], ["manualControlClear"])
        XCTAssertEqual(
            summary["blockers"] as? [String],
            [
                "diagnose reported safeToRequestCooling is not true",
                "manual control active before manual smoke",
                "diagnose recommended action is not requestCooling or requestCoolingWithCaution"
            ]
        )
        let appPreferences = try XCTUnwrap(summary["appPreferences"] as? [String: Any])
        XCTAssertEqual(appPreferences["startupMode"] as? String, "Curve")
        XCTAssertEqual(appPreferences["startupModeSource"] as? String, "persisted")

        let recoverySteps = try XCTUnwrap(summary["recoverySteps"] as? [[String: Any]])
        XCTAssertEqual(recoverySteps.map { $0["id"] as? String }, ["restoreAutoBeforeRetry"])
        XCTAssertTrue((recoverySteps.first?["text"] as? String)?.contains("Restore Auto in Vifty") == true)
        let commands = try XCTUnwrap(summary["operatorRecoveryCommands"] as? [[String: Any]])
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?["id"] as? String, "restore-auto-current-app")
        XCTAssertEqual(commands.first?["requiresUserApproval"] as? Bool, true)
        XCTAssertEqual(commands.first?["safeForAgentsToRunAutomatically"] as? Bool, false)
        XCTAssertEqual(commands.first?["command"] as? String, "'/Applications/Vifty.app/Contents/MacOS/viftyctl' restore-auto --json --reason 'operator recovery before agent cooling'")
    }

    func testJSONOutputBlocksMalformedDiagnoseOperatorRecoveryCommandsBeforeManualSmoke() throws {
        let harness = try ManualSmokeReadinessHarness(
            diagnoseJSON: #"{"state":"ready","modelIdentifier":"MacBookPro18,1","isAppleSilicon":true,"isMacBookPro":true,"recommendedAgentAction":"requestCooling","recommendedRecoveryAction":"none","operatorRecoveryCommands":[{"id":"restore-auto-current-app","title":"Unsafe","command":"viftyctl restore-auto","workingDirectoryHint":"Run anywhere.","requiresUserApproval":true,"safeForAgentsToRunAutomatically":true,"notes":["unsafe"]}],"safeToRequestCooling":true,"daemonControlPathReady":true,"manualControlActive":false,"fanCount":2,"controllableFanCount":2,"temperatureSensorCount":6,"thermalPressure":"nominal","failedCheckIDs":[],"coolingBlockerIDs":[],"appPreferences":{"startupMode":"Auto","startupModeSource":"persisted","readError":null}}"#
        )

        let result = try harness.runReadiness([
            "--viftyctl", harness.viftyctlURL.path,
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        let summary = try XCTUnwrap(ManualSmokeReadinessHarness.parseJSON(result.stdout))
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["manualSmokeReady"] as? Bool, false)
        XCTAssertEqual(summary["operatorRecoveryCommands"] as? [[String: AnyHashable]], [])
        XCTAssertTrue((summary["blockers"] as? [String])?.contains("diagnose operatorRecoveryCommands are malformed") == true)
        XCTAssertEqual(try harness.loggedArguments(), ["diagnose --json"])
    }

    func testJSONOutputCanBeSavedAsValidationSummaryEvidence() throws {
        let harness = try ManualSmokeReadinessHarness()
        let summaryURL = harness.rootURL.appendingPathComponent("manual-smoke-readiness.json")

        let result = try harness.runReadiness([
            "--viftyctl", harness.viftyctlURL.path,
            "--json",
            "--summary", summaryURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(FileManager.default.fileExists(atPath: summaryURL.path))

        let printedSummary = try XCTUnwrap(ManualSmokeReadinessHarness.parseJSON(result.stdout))
        let savedSummary = try XCTUnwrap(ManualSmokeReadinessHarness.readJSON(summaryURL))
        XCTAssertEqual(savedSummary as NSDictionary, printedSummary as NSDictionary)
        XCTAssertEqual(savedSummary["kind"] as? String, "vifty-manual-smoke-readiness")
        XCTAssertEqual(savedSummary["status"] as? String, "ready")
        XCTAssertEqual(savedSummary["manualSmokeReady"] as? Bool, true)
        XCTAssertEqual(savedSummary["readOnly"] as? Bool, true)
        XCTAssertEqual(savedSummary["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(savedSummary["recoverySteps"] as? [[String: AnyHashable]], [])
        XCTAssertEqual(try harness.loggedArguments(), ["diagnose --json"])
    }

    func testJSONOutputBlocksWhenExpectedDaemonDoesNotMatchInstalledDaemon() throws {
        let harness = try ManualSmokeReadinessHarness(expectedDaemonContents: "different daemon")

        let result = try harness.runReadiness([
            "--viftyctl", harness.viftyctlURL.path,
            "--expected-daemon", harness.expectedDaemonURL.path,
            "--require-daemon-match",
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        let summary = try XCTUnwrap(ManualSmokeReadinessHarness.parseJSON(result.stdout))
        XCTAssertEqual(summary["kind"] as? String, "vifty-manual-smoke-readiness")
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(summary["schemaID"] as? String, "https://vifty.local/schemas/manual-smoke-readiness.schema.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["manualSmokeReady"] as? Bool, false)
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(summary["blockers"] as? [String], ["installed daemon does not match expected build daemon"])
        let recoverySteps = try XCTUnwrap(summary["recoverySteps"] as? [[String: Any]])
        XCTAssertEqual(recoverySteps.map { $0["id"] as? String }, ["installMatchingDaemon"])
        XCTAssertTrue((recoverySteps.first?["text"] as? String)?.contains("Install or repair the freshly built app/helper") == true)

        let daemonRuntime = try XCTUnwrap(summary["daemonRuntime"] as? [String: Any])
        XCTAssertEqual(daemonRuntime["installedDaemonPath"] as? String, harness.installedDaemonURL.path)
        XCTAssertEqual(daemonRuntime["installedDaemonPresent"] as? Bool, true)
        XCTAssertNotNil(daemonRuntime["installedDaemonSHA256"] as? String)
        XCTAssertEqual(daemonRuntime["expectedDaemonPath"] as? String, harness.expectedDaemonURL.path)
        XCTAssertNotNil(daemonRuntime["expectedDaemonSHA256"] as? String)
        XCTAssertEqual(daemonRuntime["matchesExpectedDaemon"] as? Bool, false)
        XCTAssertEqual(daemonRuntime["matchRequired"] as? Bool, true)
        XCTAssertEqual(try harness.loggedArguments(), ["diagnose --json"])
    }

    func testJSONOutputListsEveryRecoveryStepWhenMultipleBlockersExist() throws {
        let harness = try ManualSmokeReadinessHarness(
            diagnoseJSON: #"{"state":"degraded","modelIdentifier":"MacBookPro18,1","isAppleSilicon":true,"isMacBookPro":true,"recommendedAgentAction":"restoreAutoBeforeRequestingCooling","recommendedRecoveryAction":"restoreAutoBeforeRetry","safeToRequestCooling":false,"daemonControlPathReady":true,"manualControlActive":true,"fanCount":2,"controllableFanCount":2,"temperatureSensorCount":6,"thermalPressure":"nominal","failedCheckIDs":["manualControlClear"],"coolingBlockerIDs":["manualControlClear"],"appPreferences":{"startupMode":"Curve","startupModeSource":"persisted","readError":null}}"#,
            expectedDaemonContents: "different daemon"
        )

        let result = try harness.runReadiness([
            "--viftyctl", harness.viftyctlURL.path,
            "--expected-daemon", harness.expectedDaemonURL.path,
            "--require-daemon-match",
            "--json"
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        let summary = try XCTUnwrap(ManualSmokeReadinessHarness.parseJSON(result.stdout))
        XCTAssertEqual(
            summary["blockers"] as? [String],
            [
                "installed daemon does not match expected build daemon",
                "diagnose reported safeToRequestCooling is not true",
                "manual control active before manual smoke",
                "diagnose recommended action is not requestCooling or requestCoolingWithCaution"
            ]
        )
        let recoverySteps = try XCTUnwrap(summary["recoverySteps"] as? [[String: Any]])
        XCTAssertEqual(recoverySteps.map { $0["id"] as? String }, ["restoreAutoBeforeRetry", "installMatchingDaemon"])
        XCTAssertTrue((recoverySteps[0]["text"] as? String)?.contains("Restore Auto in Vifty") == true)
        XCTAssertTrue((recoverySteps[1]["text"] as? String)?.contains("installed LaunchDaemon helper hash matches") == true)
        let nextAction = try XCTUnwrap(summary["nextAction"] as? String)
        XCTAssertTrue(nextAction.contains("repair the freshly built app/helper"), nextAction)
        XCTAssertTrue(nextAction.contains("restore Auto"), nextAction)
        XCTAssertTrue(nextAction.contains("switch startup mode to Auto"), nextAction)
    }

    func testReadinessSchemaIsDocumentedForEvidenceConsumers() throws {
        let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/manual-smoke-readiness.schema.json")
        let schema = try XCTUnwrap(ManualSmokeReadinessHarness.readJSON(schemaURL))

        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(schema["$id"] as? String, "https://vifty.local/schemas/manual-smoke-readiness.schema.json")
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertEqual((properties["schemaVersion"] as? [String: Any])?["const"] as? Int, 1)
        XCTAssertEqual((properties["schemaID"] as? [String: Any])?["const"] as? String, "https://vifty.local/schemas/manual-smoke-readiness.schema.json")
        XCTAssertEqual((properties["readOnly"] as? [String: Any])?["const"] as? Bool, true)
        XCTAssertEqual((properties["coolingCommandsRun"] as? [String: Any])?["const"] as? Bool, false)
        XCTAssertNotNil(properties["recoverySteps"] as? [String: Any])
        XCTAssertNotNil(properties["operatorRecoveryCommands"] as? [String: Any])
        XCTAssertNotNil(properties["failedCheckIDs"] as? [String: Any])
        XCTAssertNotNil(properties["coolingBlockerIDs"] as? [String: Any])
        XCTAssertNotNil(properties["appPreferences"] as? [String: Any])
        XCTAssertNotNil(properties["daemonRuntime"] as? [String: Any])

        let required = try XCTUnwrap(schema["required"] as? [String])
        XCTAssertTrue(required.contains("operatorRecoveryCommands"))
    }
}

private struct ManualSmokeReadinessProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

private final class ManualSmokeReadinessHarness {
    let repositoryRoot: URL
    let rootURL: URL
    let viftyctlURL: URL
    let logURL: URL
    let installedDaemonURL: URL
    let expectedDaemonURL: URL
    private let diagnoseJSON: String
    private let diagnoseExitCode: Int

    init(
        diagnoseJSON: String = #"{"state":"ready","modelIdentifier":"MacBookPro18,1","isAppleSilicon":true,"isMacBookPro":true,"recommendedAgentAction":"requestCooling","recommendedRecoveryAction":"none","safeToRequestCooling":true,"daemonControlPathReady":true,"manualControlActive":false,"fanCount":2,"controllableFanCount":2,"temperatureSensorCount":6,"thermalPressure":"nominal","failedCheckIDs":[],"coolingBlockerIDs":[],"appPreferences":{"startupMode":"Auto","startupModeSource":"persisted","readError":null}}"#,
        diagnoseExitCode: Int = 0,
        installedDaemonContents: String = "installed daemon",
        expectedDaemonContents: String = "installed daemon"
    ) throws {
        repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-manual-smoke-readiness-\(UUID().uuidString)", isDirectory: true)
        viftyctlURL = rootURL.appendingPathComponent("fake-bin/viftyctl")
        logURL = rootURL.appendingPathComponent("viftyctl.log")
        installedDaemonURL = rootURL.appendingPathComponent("installed-daemon")
        expectedDaemonURL = rootURL.appendingPathComponent("expected-daemon")
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

    func runReadiness(_ arguments: [String]) throws -> ManualSmokeReadinessProcessResult {
        let script = repositoryRoot.appendingPathComponent("scripts/check-manual-smoke-readiness.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = repositoryRoot
        process.arguments = [script.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "VIFTY_TEST_SHELL_FIXTURES": "1",
            "VIFTY_FAKE_LOG": logURL.path,
            "VIFTY_FAKE_DIAGNOSE_JSON": diagnoseJSON,
            "VIFTY_FAKE_DIAGNOSE_EXIT": "\(diagnoseExitCode)",
            "VIFTY_MANUAL_SMOKE_INSTALLED_DAEMON_PATH": installedDaemonURL.path
        ]) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return ManualSmokeReadinessProcessResult(
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

    private func writeFakeViftyCtl() throws {
        let script = """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$VIFTY_FAKE_LOG"
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
