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
        XCTAssertTrue(try harness.read("README.txt").contains("`resolvedChildExecutableReported=true`"))
        XCTAssertTrue(try harness.read("README.txt").contains("`recommendedAgentAction` is either `requestCooling` or `requestCoolingWithCaution`"))
        XCTAssertTrue(try harness.read("README.txt").contains("`manualControlActive=false`"))
        XCTAssertTrue(try harness.read("README.txt").contains("Do not run this smoke test when readiness is blocked"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("readOnly=false"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("coolingCommandsRun=true"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("installSource=not-recorded"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("sourceRef="))
        XCTAssertTrue(try harness.read("metadata.txt").contains("sourceSHA="))
        XCTAssertTrue(try harness.read("metadata.txt").contains("sourceArtifactName="))
        XCTAssertTrue(try harness.read("metadata.txt").contains("installedDaemonPath=\(harness.installedDaemonURL.path)"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("installedDaemonPresent=true"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("daemonMatchesExpected=unknown"))

        let daemonRuntime = try harness.read("daemon-runtime.tsv")
        XCTAssertTrue(daemonRuntime.contains("installedDaemonPresent\ttrue"))
        XCTAssertTrue(daemonRuntime.contains("daemonMatchesExpected\tunknown"))

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
        XCTAssertEqual(summary["installSource"] as? String, "not-recorded")
        XCTAssertEqual(summary["sourceRef"] as? String, "")
        XCTAssertEqual(summary["sourceSHA"] as? String, "")
        XCTAssertEqual(summary["sourceArtifactName"] as? String, "")
        XCTAssertEqual(summary["sourceArtifactSHA256"] as? String, "")
        XCTAssertEqual(summary["sourceArtifactBytes"] as? String, "")
        let daemonRuntimeSummary = try XCTUnwrap(summary["daemonRuntime"] as? [String: Any])
        XCTAssertEqual(daemonRuntimeSummary["installedDaemonPath"] as? String, harness.installedDaemonURL.path)
        XCTAssertEqual(daemonRuntimeSummary["installedDaemonPresent"] as? Bool, true)
        XCTAssertNotNil(daemonRuntimeSummary["installedDaemonSHA256"] as? String)
        XCTAssertTrue(daemonRuntimeSummary["expectedDaemonPath"] is NSNull)
        XCTAssertTrue(daemonRuntimeSummary["expectedDaemonSHA256"] is NSNull)
        XCTAssertTrue(daemonRuntimeSummary["matchesExpectedDaemon"] is NSNull)
        XCTAssertEqual(daemonRuntimeSummary["matchRequired"] as? Bool, false)
        XCTAssertEqual(summary["workload"] as? String, "test")
        XCTAssertEqual(summary["duration"] as? String, "2m")
        XCTAssertEqual(summary["maxRPMPercent"] as? Int, 55)
        XCTAssertEqual(summary["reason"] as? String, "agent run smoke test")
        XCTAssertEqual(summary["childCommand"] as? [String], ["/bin/sleep", "5"])
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["state"] as? String, "ready")
        XCTAssertEqual(preflight["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(preflight["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(preflight["manualControlActive"] as? Bool, false)
        XCTAssertEqual(preflight["capabilitiesExitStatus"] as? Int, 0)
        XCTAssertEqual(preflight["daemonStatusAvailable"] as? Bool, true)
        XCTAssertEqual(preflight["policySource"] as? String, "daemonStatus")
        XCTAssertEqual(preflight["policyStatusAvailable"] as? Bool, true)
        XCTAssertEqual(preflight["policyEnabled"] as? Bool, true)
        XCTAssertEqual(preflight["capabilitiesSchemaVersion"] as? Int, 1)
        XCTAssertEqual(
            preflight["capabilitiesSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-capabilities.schema.json"
        )
        XCTAssertEqual(
            preflight["diagnoseSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-diagnose.schema.json"
        )
        XCTAssertEqual(
            preflight["commandErrorSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-command-error.schema.json"
        )
        XCTAssertEqual(
            preflight["runSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-run.schema.json"
        )
        XCTAssertEqual(preflight["resolvedChildExecutableReported"] as? Bool, true)
        XCTAssertEqual(preflight["recommendedAgentAction"] as? String, "requestCooling")
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertEqual(run["exitStatus"] as? Int, 0)
        XCTAssertEqual(run["stdout"] as? String, "viftyctl-run.json")
        XCTAssertEqual(run["schemaVersion"] as? Int, 1)
        XCTAssertEqual(run["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(run["command"] as? String, "run")
        XCTAssertEqual(run["coolingLeasePrepared"] as? Bool, true)
        XCTAssertEqual(run["autoRestoreAttempted"] as? Bool, true)
        XCTAssertEqual(run["autoRestoreSucceeded"] as? Bool, true)
        XCTAssertEqual(run["childExitCode"] as? Int, 0)
        XCTAssertEqual(run["resolvedChildExecutable"] as? String, "/bin/sleep")
        let rateLimitRetry = try XCTUnwrap(summary["rateLimitRetry"] as? [String: Any])
        XCTAssertEqual(rateLimitRetry["attempted"] as? Bool, false)
        XCTAssertTrue(rateLimitRetry["retryAfterSeconds"] is NSNull)
        XCTAssertTrue(rateLimitRetry["initialExitStatus"] is NSNull)
        XCTAssertTrue(rateLimitRetry["stdout"] is NSNull)
        XCTAssertTrue(rateLimitRetry["stderr"] is NSNull)
        let commands = try XCTUnwrap(summary["commands"] as? [[String: Any]])
        XCTAssertEqual(commands.count, 7)

        let checksums = try harness.read("checksums.tsv")
        XCTAssertTrue(checksums.contains("sha256\tbytes\tfile"))
        XCTAssertTrue(checksums.contains("\tREADME.txt"))
        XCTAssertTrue(checksums.contains("\tmetadata.txt"))
        XCTAssertTrue(checksums.contains("\tdaemon-runtime.tsv"))
        XCTAssertTrue(checksums.contains("\tmanifest.tsv"))
        XCTAssertTrue(checksums.contains("\tagent-run-smoke-evidence-summary.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-run.json"))
        XCTAssertTrue(checksums.contains("\tpost-audit.json"))
        XCTAssertFalse(checksums.contains("\tchecksums.tsv"))
    }

    func testSmokeCollectorRecordsSourceProvenanceForLocalAdHocBuilds() throws {
        let harness = try AgentRunSmokeEvidenceHarness()
        let sourceSHA = String(repeating: "A", count: 40)

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--install-source", "local-ad-hoc-build",
            "--source-ref", "main",
            "--source-sha", sourceSHA
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let metadata = try harness.read("metadata.txt")
        XCTAssertTrue(metadata.contains("installSource=local-ad-hoc-build"))
        XCTAssertTrue(metadata.contains("sourceRef=main"))
        XCTAssertTrue(metadata.contains("sourceSHA=\(String(repeating: "a", count: 40))"))

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["installSource"] as? String, "local-ad-hoc-build")
        XCTAssertEqual(summary["sourceRef"] as? String, "main")
        XCTAssertEqual(summary["sourceSHA"] as? String, String(repeating: "a", count: 40))
        XCTAssertEqual(summary["sourceArtifactName"] as? String, "")
        XCTAssertEqual(summary["sourceArtifactSHA256"] as? String, "")
        XCTAssertEqual(summary["sourceArtifactBytes"] as? String, "")
    }

    func testSmokeCollectorRecordsExpectedDaemonMatchWhenRequested() throws {
        let harness = try AgentRunSmokeEvidenceHarness()

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--expected-daemon", harness.expectedDaemonURL.path,
            "--require-daemon-match"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(try harness.loggedArguments().contains { $0.hasPrefix("run ") })

        let daemonRuntime = try harness.read("daemon-runtime.tsv")
        XCTAssertTrue(daemonRuntime.contains("expectedDaemonPath\t\(harness.expectedDaemonURL.path)"))
        XCTAssertTrue(daemonRuntime.contains("daemonMatchesExpected\ttrue"))
        XCTAssertTrue(daemonRuntime.contains("daemonMatchRequired\t1"))

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        let daemonRuntimeSummary = try XCTUnwrap(summary["daemonRuntime"] as? [String: Any])
        XCTAssertEqual(daemonRuntimeSummary["expectedDaemonPath"] as? String, harness.expectedDaemonURL.path)
        XCTAssertNotNil(daemonRuntimeSummary["expectedDaemonSHA256"] as? String)
        XCTAssertEqual(daemonRuntimeSummary["matchesExpectedDaemon"] as? Bool, true)
        XCTAssertEqual(daemonRuntimeSummary["matchRequired"] as? Bool, true)
    }

    func testSmokeCollectorBlocksBeforeRunWhenRequiredDaemonDoesNotMatchExpectedBuild() throws {
        let harness = try AgentRunSmokeEvidenceHarness(expectedDaemonMatchesInstalled: false)

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--expected-daemon", harness.expectedDaemonURL.path,
            "--require-daemon-match"
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        assertSkippedEvidenceOutput(result, harness: harness)
        XCTAssertTrue(result.stdout.contains("installed daemon does not match expected build daemon"), result.stdout)
        XCTAssertFalse(try harness.loggedArguments().contains { $0.hasPrefix("run ") })

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        let daemonRuntimeSummary = try XCTUnwrap(summary["daemonRuntime"] as? [String: Any])
        XCTAssertEqual(daemonRuntimeSummary["matchesExpectedDaemon"] as? Bool, false)
        XCTAssertEqual(daemonRuntimeSummary["matchRequired"] as? Bool, true)
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertEqual(run["skippedReason"] as? String, "installed daemon does not match expected build daemon")
    }

    func testSmokeCollectorRejectsLocalAdHocProvenanceWithoutSourceSHA() throws {
        let harness = try AgentRunSmokeEvidenceHarness()

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--install-source", "local-ad-hoc-build",
            "--source-ref", "main"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("local-ad-hoc-build evidence requires --source-sha"), result.stderr)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.outputURL.path))
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
        assertSkippedEvidenceOutput(result, harness: harness)
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
        let rateLimitRetry = try XCTUnwrap(summary["rateLimitRetry"] as? [String: Any])
        XCTAssertEqual(rateLimitRetry["attempted"] as? Bool, false)
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["state"] as? String, "blocked")
        XCTAssertEqual(preflight["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(preflight["daemonControlPathReady"] as? Bool, false)
        XCTAssertTrue(preflight["manualControlActive"] is NSNull)
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertTrue(run["exitStatus"] is NSNull)
        XCTAssertEqual(run["skippedReason"] as? String, "readiness blocked before smoke run")
        XCTAssertTrue(run["coolingLeasePrepared"] is NSNull)
        XCTAssertTrue(run["autoRestoreAttempted"] is NSNull)
        XCTAssertTrue(run["autoRestoreSucceeded"] is NSNull)
        XCTAssertTrue(run["childExitCode"] is NSNull)
        XCTAssertTrue(run["resolvedChildExecutable"] is NSNull)
    }

    func testSmokeCollectorBlocksBeforeRunWhenManualControlIsActive() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            diagnoseJSON: #"{"state":"degraded","recommendedAgentAction":"requestCooling","safeToRequestCooling":true,"daemonControlPathReady":true,"manualControlActive":true,"recommendedRecoveryAction":"restoreAutoBeforeRetry","appPreferences":{"startupMode":"Curve","startupModeSource":"persisted","readError":null},"checks":[]}"#
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke skipped"), result.stdout)
        XCTAssertTrue(result.stdout.contains("manual control active before smoke run"), result.stdout)
        XCTAssertFalse(try harness.loggedArguments().contains { $0.hasPrefix("run ") })

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["manualControlActive"] as? Bool, true)
        XCTAssertEqual(preflight["safeToRequestCooling"] as? Bool, true)
        let appPreferences = try XCTUnwrap(preflight["appPreferences"] as? [String: Any])
        XCTAssertEqual(appPreferences["startupMode"] as? String, "Curve")
        XCTAssertEqual(appPreferences["startupModeSource"] as? String, "persisted")
        XCTAssertTrue(appPreferences["readError"] is NSNull)
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertEqual(run["skippedReason"] as? String, "manual control active before smoke run")
    }

    func testSmokeCollectorBlocksBeforeRunWhenCapabilitiesDoNotAdvertiseSafeRunLifecycle() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            capabilitiesJSON: #"{"schemaVersion":1,"daemonStatusAvailable":true,"policyStatusAvailable":true,"policySource":"daemonStatus","commands":["status","capabilities","diagnose","audit","prepare","restore-auto"],"workloads":["build","test"],"supportsForceRetry":true,"policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"exitCodes":{"success":0,"commandFailure":1,"usage":64,"unavailable":69,"blockedReadiness":75},"runLifecycle":{"childCommandPreflightBeforeCooling":false,"signalsForwardedToChild":["INT"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256}}"#
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
        XCTAssertTrue(run["coolingLeasePrepared"] is NSNull)
        XCTAssertTrue(run["autoRestoreAttempted"] is NSNull)
        XCTAssertTrue(run["autoRestoreSucceeded"] is NSNull)
        XCTAssertTrue(run["childExitCode"] is NSNull)
        XCTAssertTrue(run["resolvedChildExecutable"] is NSNull)
    }

    func testSmokeCollectorBlocksBeforeRunWhenPolicyStatusIsUnavailable() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            capabilitiesJSON: #"{"schemaVersion":1,"daemonStatusAvailable":true,"policyStatusAvailable":false,"policySource":"daemonStatus","commands":["status","capabilities","diagnose","audit","prepare","restore-auto","run"],"workloads":["build","test","render","localModel","custom"],"supportsForceRetry":true,"policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"exitCodes":{"success":0,"commandFailure":1,"usage":64,"unavailable":69,"blockedReadiness":75},"runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true},"directControlLifecycle":{"prepareUsesIdempotencyKey":true,"restoreAutoAcceptsIdempotencyKey":false,"restoreAutoScopedByIdempotencyKey":false,"preferRunForSingleChildWorkloads":true},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256}}"#
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke skipped"), result.stdout)
        XCTAssertTrue(result.stdout.contains("capabilities preflight did not advertise safe viftyctl run"), result.stdout)
        XCTAssertFalse(try harness.loggedArguments().contains { $0.hasPrefix("run ") })

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertTrue(run["exitStatus"] is NSNull)
        XCTAssertEqual(run["skippedReason"] as? String, "capabilities preflight did not advertise safe viftyctl run")
    }

    func testSmokeCollectorBlocksBeforeRunWhenPolicyIsDisabled() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            capabilitiesJSON: AgentRunSmokeEvidenceHarness.defaultCapabilitiesJSON
                .replacingOccurrences(of: #""enabled":true"#, with: #""enabled":false"#)
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke skipped"), result.stdout)
        XCTAssertTrue(result.stdout.contains("capabilities preflight did not advertise safe viftyctl run"), result.stdout)
        XCTAssertFalse(try harness.loggedArguments().contains { $0.hasPrefix("run ") })

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["policyEnabled"] as? Bool, false)
        XCTAssertEqual(preflight["capabilitiesSchemaVersion"] as? Int, 1)
        XCTAssertEqual(
            preflight["capabilitiesSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-capabilities.schema.json"
        )
        XCTAssertEqual(
            preflight["diagnoseSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-diagnose.schema.json"
        )
        XCTAssertEqual(
            preflight["commandErrorSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-command-error.schema.json"
        )
        XCTAssertEqual(
            preflight["runSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-run.schema.json"
        )
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertTrue(run["exitStatus"] is NSNull)
        XCTAssertEqual(run["skippedReason"] as? String, "capabilities preflight did not advertise safe viftyctl run")
    }

    func testSmokeCollectorBlocksBeforeRunWhenCapabilitiesSchemaIdentityDrifts() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            capabilitiesJSON: AgentRunSmokeEvidenceHarness.defaultCapabilitiesJSON
                .replacingOccurrences(of: #""schemaVersion":1"#, with: #""schemaVersion":2"#)
                .replacingOccurrences(
                    of: #"https://vifty.local/schemas/viftyctl-capabilities.schema.json"#,
                    with: #"https://example.invalid/viftyctl-capabilities.schema.json"#
                )
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke skipped"), result.stdout)
        XCTAssertTrue(result.stdout.contains("capabilities preflight did not advertise safe viftyctl run"), result.stdout)
        XCTAssertFalse(try harness.loggedArguments().contains { $0.hasPrefix("run ") })

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["capabilitiesSchemaVersion"] as? Int, 2)
        XCTAssertEqual(
            preflight["capabilitiesSchemaID"] as? String,
            "https://example.invalid/viftyctl-capabilities.schema.json"
        )
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertTrue(run["exitStatus"] is NSNull)
        XCTAssertEqual(run["skippedReason"] as? String, "capabilities preflight did not advertise safe viftyctl run")
    }

    func testSmokeCollectorBlocksBeforeRunWhenAdvertisedDiagnoseOrCommandErrorSchemaIDsDrift() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            capabilitiesJSON: AgentRunSmokeEvidenceHarness.defaultCapabilitiesJSON
                .replacingOccurrences(
                    of: #"https://vifty.local/schemas/viftyctl-diagnose.schema.json"#,
                    with: #"https://example.invalid/viftyctl-diagnose.schema.json"#
                )
                .replacingOccurrences(
                    of: #"https://vifty.local/schemas/viftyctl-command-error.schema.json"#,
                    with: #"https://example.invalid/viftyctl-command-error.schema.json"#
                )
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke skipped"), result.stdout)
        XCTAssertTrue(result.stdout.contains("capabilities preflight did not advertise safe viftyctl run"), result.stdout)
        XCTAssertFalse(try harness.loggedArguments().contains { $0.hasPrefix("run ") })

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(
            preflight["diagnoseSchemaID"] as? String,
            "https://example.invalid/viftyctl-diagnose.schema.json"
        )
        XCTAssertEqual(
            preflight["commandErrorSchemaID"] as? String,
            "https://example.invalid/viftyctl-command-error.schema.json"
        )
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertTrue(run["exitStatus"] is NSNull)
        XCTAssertEqual(run["skippedReason"] as? String, "capabilities preflight did not advertise safe viftyctl run")
    }

    func testSmokeCollectorBlocksBeforeRunWhenCapabilitiesAreNotDaemonBacked() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            capabilitiesJSON: #"{"schemaVersion":1,"daemonStatusAvailable":false,"policyStatusAvailable":true,"policySource":"fallbackUnavailable","commands":["status","capabilities","diagnose","audit","prepare","restore-auto","run"],"workloads":["build","test","render","localModel","custom"],"supportsForceRetry":true,"policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"exitCodes":{"success":0,"commandFailure":1,"usage":64,"unavailable":69,"blockedReadiness":75},"runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true},"directControlLifecycle":{"prepareUsesIdempotencyKey":true,"restoreAutoAcceptsIdempotencyKey":false,"restoreAutoScopedByIdempotencyKey":false,"preferRunForSingleChildWorkloads":true},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256}}"#
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 75, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent run smoke skipped"), result.stdout)
        XCTAssertTrue(result.stdout.contains("capabilities preflight did not advertise safe viftyctl run"), result.stdout)
        XCTAssertFalse(try harness.loggedArguments().contains { $0.hasPrefix("run ") })

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "blocked")
        let preflight = try XCTUnwrap(summary["preflight"] as? [String: Any])
        XCTAssertEqual(preflight["capabilitiesExitStatus"] as? Int, 0)
        XCTAssertEqual(preflight["daemonStatusAvailable"] as? Bool, false)
        XCTAssertEqual(preflight["policySource"] as? String, "fallbackUnavailable")
        XCTAssertEqual(preflight["policyStatusAvailable"] as? Bool, true)
    }

    func testSmokeCollectorDerivesPassedRunLifecycleProofWhenRunStdoutIsChildOutput() throws {
        let harness = try AgentRunSmokeEvidenceHarness(runJSON: "child stdout that is not JSON")

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "passed")
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertEqual(run["exitStatus"] as? Int, 0)
        XCTAssertEqual(run["coolingLeasePrepared"] as? Bool, true)
        XCTAssertEqual(run["autoRestoreAttempted"] as? Bool, true)
        XCTAssertEqual(run["autoRestoreSucceeded"] as? Bool, true)
        XCTAssertEqual(run["childExitCode"] as? Int, 0)
        XCTAssertTrue(run["resolvedChildExecutable"] is NSNull)
    }

    func testSmokeCollectorRunsWhenReadinessAllowsCoolingWithCaution() throws {
        let harness = try AgentRunSmokeEvidenceHarness(
            diagnoseJSON: #"{"state":"degraded","recommendedAgentAction":"requestCoolingWithCaution","safeToRequestCooling":true,"daemonControlPathReady":true,"manualControlActive":false,"recommendedRecoveryAction":"none","checks":[]}"#
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
        XCTAssertEqual(preflight["manualControlActive"] as? Bool, false)
        XCTAssertEqual(preflight["recommendedAgentAction"] as? String, "requestCoolingWithCaution")
    }

    func testSmokeCollectorWaitsOnceAndRetriesWhenRunIsPrepareRateLimited() throws {
        let rateLimitedJSON = """
        {"schemaVersion":1,"command":"run","errorCode":"PREPARE_RATE_LIMITED","message":"Wait before retrying","safeToProceed":false,"recommendedRecoveryAction":"waitBeforeRetry","coolingLeasePrepared":false,"autoRestoreAttempted":false,"autoRestoreSucceeded":null,"retryAfterSeconds":2}
        """
        let harness = try AgentRunSmokeEvidenceHarness(
            runJSONs: [
                rateLimitedJSON,
                AgentRunSmokeEvidenceHarness.runSuccessJSON
            ],
            runExitCodes: [1, 0]
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stderr.contains("rate-limited"), result.stderr)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "capabilities --json",
                "diagnose --json",
                "run --workload test --duration 2m --max-rpm-percent 55 --reason agent run smoke test --json -- /bin/sleep 5",
                "run --workload test --duration 2m --max-rpm-percent 55 --reason agent run smoke test --json -- /bin/sleep 5",
                "capabilities --json",
                "status --json",
                "audit --limit 20 --json",
                "diagnose --json"
            ]
        )

        let manifest = try harness.read("manifest.tsv")
        XCTAssertTrue(manifest.contains("viftyctl-run\t1\tviftyctl-run.json\tviftyctl-run.stderr"))
        XCTAssertTrue(manifest.contains("viftyctl-run-retry\t0\tviftyctl-run-retry.json\tviftyctl-run-retry.stderr"))
        XCTAssertEqual(try harness.read("viftyctl-run.status").trimmingCharacters(in: .whitespacesAndNewlines), "1")
        XCTAssertEqual(try harness.read("viftyctl-run-retry.status").trimmingCharacters(in: .whitespacesAndNewlines), "0")

        let summary = try harness.readJSON("agent-run-smoke-evidence-summary.json")
        XCTAssertEqual(summary["status"] as? String, "passed")
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, true)
        let rateLimitRetry = try XCTUnwrap(summary["rateLimitRetry"] as? [String: Any])
        XCTAssertEqual(rateLimitRetry["attempted"] as? Bool, true)
        XCTAssertEqual(rateLimitRetry["retryAfterSeconds"] as? Int, 2)
        XCTAssertEqual(rateLimitRetry["initialExitStatus"] as? Int, 1)
        XCTAssertEqual(rateLimitRetry["stdout"] as? String, "viftyctl-run.json")
        XCTAssertEqual(rateLimitRetry["stderr"] as? String, "viftyctl-run.stderr")
        let run = try XCTUnwrap(summary["run"] as? [String: Any])
        XCTAssertEqual(run["exitStatus"] as? Int, 0)
        XCTAssertEqual(run["stdout"] as? String, "viftyctl-run-retry.json")
        XCTAssertEqual(run["stderr"] as? String, "viftyctl-run-retry.stderr")
        XCTAssertEqual(run["coolingLeasePrepared"] as? Bool, true)
        XCTAssertEqual(run["autoRestoreAttempted"] as? Bool, true)
        XCTAssertEqual(run["autoRestoreSucceeded"] as? Bool, true)
        XCTAssertEqual(run["childExitCode"] as? Int, 0)
        XCTAssertEqual(run["resolvedChildExecutable"] as? String, "/bin/sleep")
        let commands = try XCTUnwrap(summary["commands"] as? [[String: Any]])
        XCTAssertEqual(commands.count, 8)

        let checksums = try harness.read("checksums.tsv")
        XCTAssertTrue(checksums.contains("\tviftyctl-run.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-run-retry.json"))
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
            "installSource",
            "sourceRef",
            "sourceSHA",
            "sourceArtifactName",
            "sourceArtifactSHA256",
            "sourceArtifactBytes",
            "daemonRuntime",
            "preflight",
            "run",
            "commands"
        ] {
            XCTAssertTrue(required.contains(field), "missing required field \(field)")
        }

        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let daemonRuntime = try XCTUnwrap(defs["daemonRuntime"] as? [String: Any])
        let daemonRuntimeRequired = try XCTUnwrap(daemonRuntime["required"] as? [String])
        for field in [
            "installedDaemonPath",
            "installedDaemonPresent",
            "installedDaemonSHA256",
            "expectedDaemonPath",
            "expectedDaemonSHA256",
            "matchesExpectedDaemon",
            "matchRequired"
        ] {
            XCTAssertTrue(daemonRuntimeRequired.contains(field), "daemonRuntime should require \(field)")
        }
        let run = try XCTUnwrap(defs["run"] as? [String: Any])
        let runRequired = try XCTUnwrap(run["required"] as? [String])
        for field in [
            "schemaVersion",
            "schemaID",
            "command",
            "coolingLeasePrepared",
            "autoRestoreAttempted",
            "autoRestoreSucceeded",
            "childExitCode",
            "resolvedChildExecutable"
        ] {
            XCTAssertTrue(runRequired.contains(field), "run should require \(field)")
        }
        let rateLimitRetry = try XCTUnwrap(defs["rateLimitRetry"] as? [String: Any])
        let rateLimitRetryRequired = try XCTUnwrap(rateLimitRetry["required"] as? [String])
        for field in [
            "attempted",
            "retryAfterSeconds",
            "initialExitStatus",
            "stdout",
            "stderr"
        ] {
            XCTAssertTrue(rateLimitRetryRequired.contains(field), "rateLimitRetry should require \(field)")
        }
        let preflight = try XCTUnwrap(defs["preflight"] as? [String: Any])
        let preflightRequired = try XCTUnwrap(preflight["required"] as? [String])
        for field in [
            "capabilitiesExitStatus",
            "capabilitiesSchemaVersion",
            "capabilitiesSchemaID",
            "diagnoseSchemaID",
            "commandErrorSchemaID",
            "runSchemaID",
            "resolvedChildExecutableReported",
            "daemonStatusAvailable",
            "policySource",
            "policyStatusAvailable",
            "policyEnabled",
            "state",
            "recommendedAgentAction",
            "recommendedRecoveryAction",
            "safeToRequestCooling",
            "daemonControlPathReady",
            "manualControlActive"
        ] {
            XCTAssertTrue(preflightRequired.contains(field), "preflight should require \(field)")
        }
        let preflightProperties = try XCTUnwrap(preflight["properties"] as? [String: Any])
        XCTAssertEqual(
            (preflightProperties["appPreferences"] as? [String: Any])?["$ref"] as? String,
            "#/$defs/appPreferencesDiagnostic"
        )
        let appPreferences = try XCTUnwrap(defs["appPreferencesDiagnostic"] as? [String: Any])
        let appPreferencesRequired = try XCTUnwrap(appPreferences["required"] as? [String])
        for field in [
            "startupMode",
            "startupModeSource",
            "readError"
        ] {
            XCTAssertTrue(appPreferencesRequired.contains(field), "appPreferences should require \(field)")
        }
    }

    private func assertSkippedEvidenceOutput(
        _ result: AgentRunSmokeProcessResult,
        harness: AgentRunSmokeEvidenceHarness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(result.stdout.contains("Agent run smoke skipped"), result.stdout, file: file, line: line)
        XCTAssertTrue(
            result.stdout.contains("Agent run smoke evidence written to \(harness.outputURL.path)"),
            result.stdout,
            file: file,
            line: line
        )
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
    let installedDaemonURL: URL
    let expectedDaemonURL: URL
    let logURL: URL
    private let capabilitiesJSON: String
    private let diagnoseJSON: String
    private let diagnoseExitCode: Int
    private let statusJSON: String
    private let auditJSON: String
    private let runJSONs: [String]
    private let runExitCodes: [Int]

    init(
        capabilitiesJSON: String = AgentRunSmokeEvidenceHarness.defaultCapabilitiesJSON,
        diagnoseJSON: String = #"{"state":"ready","recommendedAgentAction":"requestCooling","safeToRequestCooling":true,"daemonControlPathReady":true,"manualControlActive":false,"recommendedRecoveryAction":"none","checks":[]}"#,
        diagnoseExitCode: Int = 0,
        statusJSON: String = #"{"enabled":true,"activeLease":null,"lastDecision":null}"#,
        auditJSON: String = #"{"readOnly":true,"coolingCommandsRun":false,"events":[]}"#,
        runJSON: String = AgentRunSmokeEvidenceHarness.runSuccessJSON,
        runExitCode: Int = 0,
        runJSONs: [String]? = nil,
        runExitCodes: [Int]? = nil,
        expectedDaemonMatchesInstalled: Bool = true
    ) throws {
        repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-agent-run-smoke-\(UUID().uuidString)", isDirectory: true)
        outputURL = rootURL.appendingPathComponent("smoke", isDirectory: true)
        viftyctlURL = rootURL.appendingPathComponent("fake-bin/viftyctl")
        installedDaemonURL = rootURL.appendingPathComponent("installed/tech.reidar.vifty.daemon")
        expectedDaemonURL = rootURL.appendingPathComponent("expected/ViftyDaemon")
        logURL = rootURL.appendingPathComponent("viftyctl.log")
        self.capabilitiesJSON = capabilitiesJSON
        self.diagnoseJSON = diagnoseJSON
        self.diagnoseExitCode = diagnoseExitCode
        self.statusJSON = statusJSON
        self.auditJSON = auditJSON
        self.runJSONs = runJSONs ?? [runJSON]
        self.runExitCodes = runExitCodes ?? [runExitCode]

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try writeFakeDaemonFiles(expectedDaemonMatchesInstalled: expectedDaemonMatchesInstalled)
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
        var environment = ProcessInfo.processInfo.environment.merging([
            "VIFTY_FAKE_LOG": logURL.path,
            "VIFTY_FAKE_CAPABILITIES_JSON": capabilitiesJSON,
            "VIFTY_FAKE_DIAGNOSE_JSON": diagnoseJSON,
            "VIFTY_FAKE_DIAGNOSE_EXIT": "\(diagnoseExitCode)",
            "VIFTY_FAKE_STATUS_JSON": statusJSON,
            "VIFTY_FAKE_AUDIT_JSON": auditJSON,
            "VIFTY_FAKE_RUN_JSON": self.runJSONs.last ?? #"{"schemaVersion":1,"schemaID":"https://vifty.local/schemas/viftyctl-run.schema.json","command":"run","coolingLeasePrepared":true,"autoRestoreAttempted":true,"autoRestoreSucceeded":true,"childExitCode":0,"resolvedChildExecutable":"/bin/sleep","autoRestoreError":null,"generatedAt":700000000}"#,
            "VIFTY_FAKE_RUN_EXIT": "\(self.runExitCodes.last ?? 0)",
            "VIFTY_AGENT_RUN_SMOKE_SKIP_RETRY_SLEEP": "1",
            "VIFTY_AGENT_RUN_SMOKE_INSTALLED_DAEMON_PATH": installedDaemonURL.path
        ]) { _, new in new }
        for (index, json) in self.runJSONs.enumerated() {
            environment["VIFTY_FAKE_RUN_JSON_\(index + 1)"] = json
        }
        for (index, exitCode) in self.runExitCodes.enumerated() {
            environment["VIFTY_FAKE_RUN_EXIT_\(index + 1)"] = "\(exitCode)"
        }
        process.environment = environment

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
            count_file="${VIFTY_FAKE_LOG}.run-count"
            count=0
            if [ -f "${count_file}" ]; then
              count="$(cat "${count_file}")"
            fi
            count=$((count + 1))
            printf '%s\\n' "${count}" > "${count_file}"
            json="$(printenv "VIFTY_FAKE_RUN_JSON_${count}" || true)"
            exit_code="$(printenv "VIFTY_FAKE_RUN_EXIT_${count}" || true)"
            if [ -z "${json}" ]; then
              json="${VIFTY_FAKE_RUN_JSON}"
            fi
            if [ -z "${exit_code}" ]; then
              exit_code="${VIFTY_FAKE_RUN_EXIT}"
            fi
            printf '%s\\n' "${json}"
            exit "${exit_code}"
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

    private func writeFakeDaemonFiles(expectedDaemonMatchesInstalled: Bool) throws {
        try FileManager.default.createDirectory(
            at: installedDaemonURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: expectedDaemonURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("installed-daemon".utf8).write(to: installedDaemonURL)
        let expectedContents = expectedDaemonMatchesInstalled ? "installed-daemon" : "different-daemon"
        try Data(expectedContents.utf8).write(to: expectedDaemonURL)
    }

    static let defaultCapabilitiesJSON = """
    {"schemaVersion":1,"schemaIDs":{"capabilities":"https://vifty.local/schemas/viftyctl-capabilities.schema.json","diagnose":"https://vifty.local/schemas/viftyctl-diagnose.schema.json","status":"https://vifty.local/schemas/viftyctl-status.schema.json","audit":"https://vifty.local/schemas/viftyctl-audit.schema.json","commandError":"https://vifty.local/schemas/viftyctl-command-error.schema.json","run":"https://vifty.local/schemas/viftyctl-run.schema.json"},"daemonStatusAvailable":true,"policyStatusAvailable":true,"policySource":"daemonStatus","commands":["status","capabilities","diagnose","audit","prepare","restore-auto","run"],"workloads":["build","test","render","localModel","custom"],"supportsForceRetry":true,"policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"exitCodes":{"success":0,"commandFailure":1,"usage":64,"unavailable":69,"blockedReadiness":75},"runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true,"resolvedChildExecutableReported":true},"directControlLifecycle":{"prepareUsesIdempotencyKey":true,"restoreAutoAcceptsIdempotencyKey":false,"restoreAutoScopedByIdempotencyKey":false,"preferRunForSingleChildWorkloads":true},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256},"wrapperResources":{"sourceDirectory":"examples/viftyctl","bundleDirectory":"Contents/Resources/viftyctl-wrappers","guardedRunScript":"guarded-run.sh","workloadScripts":["cargo-build.sh","cargo-test.sh","custom-workload.sh","local-model.sh","make-build.sh","make-test.sh","make-verify.sh","npm-build.sh","npm-test.sh","pytest.sh","swift-release-build.sh","swift-test.sh","xcode-build.sh","xcode-test.sh"]}}
    """

    static let runSuccessJSON = #"{"schemaVersion":1,"schemaID":"https://vifty.local/schemas/viftyctl-run.schema.json","command":"run","coolingLeasePrepared":true,"autoRestoreAttempted":true,"autoRestoreSucceeded":true,"childExitCode":0,"resolvedChildExecutable":"/bin/sleep","autoRestoreError":null,"generatedAt":700000000}"#
}
