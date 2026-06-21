import Foundation
import XCTest

final class AgentCoolingEvidenceScriptTests: XCTestCase {
    func testCollectorCapturesOnlyReadOnlyAgentEvidence() throws {
        let harness = try AgentCoolingEvidenceHarness()

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Agent cooling evidence written"))
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "capabilities --json",
                "diagnose --json",
                "status --json",
                "audit --limit 20 --json"
            ]
        )
        XCTAssertFalse(try harness.loggedArguments().contains { invocation in
            ["prepare", "run", "restore-auto", "setFixed", "auto"].contains { invocation.hasPrefix($0) }
        })

        XCTAssertTrue(try harness.read("README.txt").contains("does not request cooling leases"))
        XCTAssertTrue(try harness.read("README.txt").contains("use sudo, or write SMC keys"))
        XCTAssertTrue(try harness.read("README.txt").contains("safeToRequestCooling=false"))
        XCTAssertTrue(try harness.read("README.txt").contains("privacy-review.tsv"))
        XCTAssertTrue(try harness.read("README.txt").contains("app-info-plist.txt"))
        XCTAssertTrue(try harness.read("README.txt").contains("launchctl-print-daemon.txt"))
        XCTAssertTrue(try harness.read("README.txt").contains("Nonzero status rows for these files are evidence"))
        XCTAssertTrue(try harness.read("README.txt").contains("If this report comes from the published v1.1.0 release"))
        XCTAssertTrue(try harness.read("README.txt").contains("move to the v1.1.1 source-first hotfix"))
        XCTAssertTrue(try harness.read("README.txt").contains("Do not retag v1.1.0 or replace its unsigned-dev assets"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("readOnly=true"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("coolingCommandsRun=false"))
        XCTAssertTrue(try harness.read("metadata.txt").contains("auditLimit=20"))

        let manifest = try harness.read("manifest.tsv")
        XCTAssertTrue(manifest.contains("name\tstatus\tstdout\tstderr"))
        XCTAssertTrue(manifest.contains("viftyctl-capabilities\t0\tviftyctl-capabilities.json\tviftyctl-capabilities.stderr"))
        XCTAssertTrue(manifest.contains("viftyctl-diagnose\t0\tviftyctl-diagnose.json\tviftyctl-diagnose.stderr"))
        XCTAssertTrue(manifest.contains("viftyctl-status\t0\tviftyctl-status.json\tviftyctl-status.stderr"))
        XCTAssertTrue(manifest.contains("viftyctl-audit\t0\tviftyctl-audit.json\tviftyctl-audit.stderr"))
        XCTAssertTrue(manifest.contains("launchctl-print-daemon\t"))
        XCTAssertTrue(manifest.contains("\tlaunchctl-print-daemon.txt\tlaunchctl-print-daemon.stderr"))
        XCTAssertTrue(manifest.contains("launchdaemon-plist\t"))
        XCTAssertTrue(manifest.contains("\tlaunchdaemon-plist.txt\tlaunchdaemon-plist.stderr"))
        XCTAssertTrue(manifest.contains("helper-file-metadata\t"))
        XCTAssertTrue(manifest.contains("\thelper-file-metadata.txt\thelper-file-metadata.stderr"))
        XCTAssertTrue(manifest.contains("app-info-plist\t0\tapp-info-plist.txt\tapp-info-plist.stderr"))
        XCTAssertTrue(manifest.contains("privacy-review\t0\tprivacy-review.tsv\tprivacy-review.stderr"))
        XCTAssertEqual(try harness.read("viftyctl-diagnose.status").trimmingCharacters(in: .whitespacesAndNewlines), "0")
        XCTAssertEqual(try harness.read("app-info-plist.status").trimmingCharacters(in: .whitespacesAndNewlines), "0")
        XCTAssertEqual(try harness.read("privacy-review.status").trimmingCharacters(in: .whitespacesAndNewlines), "0")
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("none\t-\t-\tpassed"))
        XCTAssertFalse(try harness.read("launchctl-print-daemon.status").isEmpty)
        XCTAssertFalse(try harness.read("launchdaemon-plist.status").isEmpty)
        XCTAssertFalse(try harness.read("helper-file-metadata.status").isEmpty)
        XCTAssertTrue(try harness.read("app-info-plist.txt").contains("CFBundleShortVersionString"))
        XCTAssertTrue(try harness.read("app-info-plist.txt").contains("1.1.1"))
        XCTAssertTrue(try harness.read("app-info-plist.txt").contains("tech.reidar.vifty"))

        XCTAssertTrue(try harness.read("viftyctl-capabilities.json").contains("\"daemonStatusAvailable\":true"))
        XCTAssertTrue(try harness.read("viftyctl-capabilities.json").contains("\"runLifecycle\""))
        XCTAssertTrue(try harness.read("viftyctl-capabilities.json").contains("\"directControlLifecycle\""))
        XCTAssertTrue(try harness.read("viftyctl-capabilities.json").contains("\"metadataLimits\""))
        XCTAssertTrue(try harness.read("viftyctl-diagnose.json").contains("\"state\":\"ready\""))
        XCTAssertTrue(try harness.read("viftyctl-audit.json").contains("\"coolingCommandsRun\":false"))

        let summary = try harness.readJSON("agent-cooling-evidence-summary.json")
        XCTAssertEqual(summary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            summary["schemaID"] as? String,
            "https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json"
        )
        XCTAssertEqual(summary["readOnly"] as? Bool, true)
        XCTAssertEqual(summary["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(summary["auditLimit"] as? Int, 20)
        let commands = try XCTUnwrap(summary["commands"] as? [[String: Any]])
        XCTAssertEqual(commands.count, 9)
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "viftyctl-audit"
                && command["status"] as? Int == 0
                && command["stdout"] as? String == "viftyctl-audit.json"
        })
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "launchctl-print-daemon"
                && command["stdout"] as? String == "launchctl-print-daemon.txt"
        })
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "launchdaemon-plist"
                && command["stdout"] as? String == "launchdaemon-plist.txt"
        })
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "helper-file-metadata"
                && command["stdout"] as? String == "helper-file-metadata.txt"
        })
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "app-info-plist"
                && command["status"] as? Int == 0
                && command["stdout"] as? String == "app-info-plist.txt"
        })
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "privacy-review"
                && command["status"] as? Int == 0
                && command["stdout"] as? String == "privacy-review.tsv"
        })

        let checksums = try harness.read("checksums.tsv")
        XCTAssertTrue(checksums.contains("sha256\tbytes\tfile"))
        XCTAssertTrue(checksums.contains("\tREADME.txt"))
        XCTAssertTrue(checksums.contains("\tmetadata.txt"))
        XCTAssertTrue(checksums.contains("\tmanifest.tsv"))
        XCTAssertTrue(checksums.contains("\tagent-cooling-evidence-summary.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-capabilities.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-diagnose.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-status.json"))
        XCTAssertTrue(checksums.contains("\tviftyctl-audit.json"))
        XCTAssertTrue(checksums.contains("\tlaunchctl-print-daemon.txt"))
        XCTAssertTrue(checksums.contains("\tlaunchctl-print-daemon.status"))
        XCTAssertTrue(checksums.contains("\tlaunchdaemon-plist.txt"))
        XCTAssertTrue(checksums.contains("\thelper-file-metadata.txt"))
        XCTAssertTrue(checksums.contains("\tapp-info-plist.txt"))
        XCTAssertTrue(checksums.contains("\tapp-info-plist.status"))
        XCTAssertTrue(checksums.contains("\tprivacy-review.tsv"))
        XCTAssertTrue(checksums.contains("\tprivacy-review.status"))
        XCTAssertFalse(checksums.contains("\tchecksums.tsv"))
    }

    func testCollectorCopiesOptionalUIContextIntoEvidenceBundle() throws {
        let harness = try AgentCoolingEvidenceHarness()
        let contextURL = harness.rootURL.appendingPathComponent("ui-context-source.txt", isDirectory: false)
        try """
        selectedMode=Curve
        manualRun=Until changed
        helper=Read-only fan telemetry
        """.write(to: contextURL, atomically: true, encoding: .utf8)

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--ui-context-file", contextURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try harness.read("ui-context.txt"),
            """
            selectedMode=Curve
            manualRun=Until changed
            helper=Read-only fan telemetry
            """
        )
        XCTAssertTrue(try harness.read("checksums.tsv").contains("\tui-context.txt"))
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("none\t-\t-\tpassed"))
        XCTAssertFalse(try harness.read("manifest.tsv").contains("ui-context"))
    }

    func testCollectorCopiesGuardedRunStderrAndReviewerSummarizesDecision() throws {
        let harness = try AgentCoolingEvidenceHarness(
            diagnoseJSON: #"""
            {
              "state": "blocked",
              "recommendedAgentAction": "doNotRequestCooling",
              "safeToRequestCooling": false,
              "daemonControlPathReady": true,
              "manualControlActive": true,
              "recommendedRecoveryAction": "restoreAutoBeforeRetry",
              "failedCheckIDs": ["manualControlClear"],
              "coolingBlockerIDs": ["manualControlClear"],
              "appPreferences": {
                "startupMode": "Curve",
                "startupModeSource": "persisted",
                "readError": null
              },
              "checks": []
            }
            """#,
            diagnoseExitCode: 75
        )
        let guardedRunStderrURL = harness.rootURL.appendingPathComponent("guarded-run-source.stderr")
        try """
        guarded-run: Vifty readiness state blocked does not allow cooling.
        guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON
        {"schemaVersion":1,"schemaID":"https://vifty.local/schemas/guarded-run-decision.schema.json","command":"guarded-run","safeToProceed":false,"coolingRequested":false,"uncooledFallbackRequested":false,"uncooledFallbackAllowed":false,"decisionReason":"readinessBlocked","exitCode":75,"message":"Vifty readiness state blocked does not allow cooling.","recommendedAgentAction":"doNotRequestCooling","recommendedRecoveryAction":"restoreAutoBeforeRetry","diagnoseState":"blocked","safeToRequestCooling":false,"daemonControlPathReady":true,"manualControlActive":true,"startupMode":"Curve","failedCheckIDs":["manualControlClear"],"coolingBlockerIDs":["manualControlClear"]}
        guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON
        """.write(to: guardedRunStderrURL, atomically: true, encoding: .utf8)

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--guarded-run-stderr-file", guardedRunStderrURL.path
        ])

        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)
        XCTAssertTrue(try harness.read("README.txt").contains("guarded-run-stderr.txt"))
        XCTAssertTrue(try harness.read("guarded-run-stderr.txt").contains("BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON"))
        XCTAssertTrue(try harness.read("checksums.tsv").contains("\tguarded-run-stderr.txt"))
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("none\t-\t-\tpassed"))
        XCTAssertFalse(try harness.read("manifest.tsv").contains("guarded-run-stderr"))

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 0, reviewResult.stderr)
        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        let guardedRunDecision = try XCTUnwrap(reviewSummary["guardedRunDecision"] as? [String: Any])
        XCTAssertEqual(guardedRunDecision["present"] as? Bool, true)
        XCTAssertEqual(guardedRunDecision["sourceFile"] as? String, "guarded-run-stderr.txt")
        XCTAssertEqual(guardedRunDecision["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            guardedRunDecision["schemaID"] as? String,
            "https://vifty.local/schemas/guarded-run-decision.schema.json"
        )
        XCTAssertEqual(guardedRunDecision["safeToProceed"] as? Bool, false)
        XCTAssertEqual(guardedRunDecision["coolingRequested"] as? Bool, false)
        XCTAssertEqual(guardedRunDecision["uncooledFallbackRequested"] as? Bool, false)
        XCTAssertEqual(guardedRunDecision["uncooledFallbackAllowed"] as? Bool, false)
        XCTAssertEqual(guardedRunDecision["decisionReason"] as? String, "readinessBlocked")
        XCTAssertEqual(guardedRunDecision["exitCode"] as? Int, 75)
        XCTAssertEqual(guardedRunDecision["recommendedAgentAction"] as? String, "doNotRequestCooling")
        XCTAssertEqual(guardedRunDecision["recommendedRecoveryAction"] as? String, "restoreAutoBeforeRetry")
        XCTAssertEqual(guardedRunDecision["diagnoseState"] as? String, "blocked")
        XCTAssertEqual(guardedRunDecision["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(guardedRunDecision["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(guardedRunDecision["manualControlActive"] as? Bool, true)
        XCTAssertEqual(guardedRunDecision["startupMode"] as? String, "Curve")
        XCTAssertEqual(guardedRunDecision["failedCheckIDs"] as? [String], ["manualControlClear"])
        XCTAssertEqual(guardedRunDecision["coolingBlockerIDs"] as? [String], ["manualControlClear"])
    }

    func testReviewerRejectsUnsupportedGuardedRunDecisionReason() throws {
        let harness = try AgentCoolingEvidenceHarness(
            diagnoseJSON: #"""
            {
              "state": "blocked",
              "recommendedAgentAction": "doNotRequestCooling",
              "safeToRequestCooling": false,
              "daemonControlPathReady": true,
              "manualControlActive": true,
              "recommendedRecoveryAction": "restoreAutoBeforeRetry",
              "failedCheckIDs": ["manualControlClear"],
              "coolingBlockerIDs": ["manualControlClear"],
              "appPreferences": {
                "startupMode": "Curve",
                "startupModeSource": "persisted",
                "readError": null
              },
              "checks": []
            }
            """#,
            diagnoseExitCode: 75
        )
        let guardedRunStderrURL = harness.rootURL.appendingPathComponent("guarded-run-source.stderr")
        try """
        guarded-run: Vifty readiness state blocked does not allow cooling.
        guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON
        {"schemaVersion":1,"schemaID":"https://vifty.local/schemas/guarded-run-decision.schema.json","command":"guarded-run","safeToProceed":false,"coolingRequested":false,"uncooledFallbackRequested":false,"uncooledFallbackAllowed":false,"decisionReason":"parseTheMessagePlease","exitCode":75,"message":"Vifty readiness state blocked does not allow cooling.","recommendedAgentAction":"doNotRequestCooling","recommendedRecoveryAction":"restoreAutoBeforeRetry","diagnoseState":"blocked","safeToRequestCooling":false,"daemonControlPathReady":true,"manualControlActive":true,"startupMode":"Curve","failedCheckIDs":["manualControlClear"],"coolingBlockerIDs":["manualControlClear"]}
        guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON
        """.write(to: guardedRunStderrURL, atomically: true, encoding: .utf8)
        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--guarded-run-stderr-file", guardedRunStderrURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("guarded-run decision decisionReason is unsupported"), reviewResult.stderr)
        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "failed")
        let guardedRunDecision = try XCTUnwrap(reviewSummary["guardedRunDecision"] as? [String: Any])
        XCTAssertEqual(guardedRunDecision["decisionReason"] as? String, "parseTheMessagePlease")
        XCTAssertTrue((reviewSummary["failures"] as? [String])?.contains("guarded-run decision decisionReason is unsupported") == true)
    }

    func testCollectorPreservesBlockedDiagnoseExitAsEvidence() throws {
        let harness = try AgentCoolingEvidenceHarness(
            diagnoseJSON: #"{"state":"blocked","recommendedAgentAction":"doNotRequestCooling","safeToRequestCooling":false,"daemonControlPathReady":false,"recommendedRecoveryAction":"repairHelper","checks":[]}"#,
            diagnoseExitCode: 75
        )

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--audit-limit", "7"
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "capabilities --json",
                "diagnose --json",
                "status --json",
                "audit --limit 7 --json"
            ]
        )
        XCTAssertEqual(try harness.read("viftyctl-diagnose.status").trimmingCharacters(in: .whitespacesAndNewlines), "75")
        XCTAssertTrue(try harness.read("viftyctl-diagnose.json").contains("\"state\":\"blocked\""))
        XCTAssertTrue(try harness.read("README.txt").contains("readiness was blocked"))

        let summary = try harness.readJSON("agent-cooling-evidence-summary.json")
        XCTAssertEqual(summary["auditLimit"] as? Int, 7)
        let commands = try XCTUnwrap(summary["commands"] as? [[String: Any]])
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "viftyctl-diagnose"
                && command["status"] as? Int == 75
        })
    }

    func testCollectorFlagsLikelyPrivateIdentifiersWithoutRunningCoolingCommands() throws {
        let harness = try AgentCoolingEvidenceHarness(includePrivacyLeak: true)

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try harness.loggedArguments(),
            [
                "capabilities --json",
                "diagnose --json",
                "status --json",
                "audit --limit 20 --json"
            ]
        )
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("redaction-needed\tviftyctl-status.json"))
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("serial-number-label"))
        XCTAssertTrue(try harness.read("privacy-review.tsv").contains("user-home-path"))
        XCTAssertTrue(try harness.read("privacy-review.stderr").contains("privacy review found local identifiers"))
        XCTAssertTrue(try harness.read("manifest.tsv").contains("privacy-review\t1\tprivacy-review.tsv"))

        let summary = try harness.readJSON("agent-cooling-evidence-summary.json")
        let commands = try XCTUnwrap(summary["commands"] as? [[String: Any]])
        XCTAssertTrue(commands.contains { command in
            command["name"] as? String == "privacy-review"
                && command["status"] as? Int == 1
                && command["stdout"] as? String == "privacy-review.tsv"
        })
    }

    func testCollectorRejectsUnboundedAuditLimitBeforeCallingViftyCtl() throws {
        let harness = try AgentCoolingEvidenceHarness()

        let result = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path,
            "--audit-limit", "1000"
        ])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("--audit-limit must be an integer from 1 through 200"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.logURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.outputURL.path))
    }

    func testReviewerAcceptsCollectorBundleAndWritesSummary() throws {
        let harness = try AgentCoolingEvidenceHarness()
        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 0, reviewResult.stderr)
        XCTAssertTrue(reviewResult.stdout.contains("Agent cooling evidence OK"))

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            reviewSummary["schemaID"] as? String,
            "https://vifty.local/schemas/agent-cooling-evidence-review.schema.json"
        )
        XCTAssertEqual(reviewSummary["status"] as? String, "passed")
        let summaryBundlePath = try XCTUnwrap(reviewSummary["bundlePath"] as? String)
        XCTAssertEqual(summaryBundlePath, harness.outputURL.lastPathComponent)
        XCTAssertFalse(summaryBundlePath.contains(harness.rootURL.path))
        XCTAssertFalse(summaryBundlePath.hasPrefix("/"))
        XCTAssertEqual(reviewSummary["readOnly"] as? Bool, true)
        XCTAssertEqual(reviewSummary["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(reviewSummary["commandsReviewed"] as? Int, 9)
        let diagnoseDecision = try XCTUnwrap(reviewSummary["diagnoseDecision"] as? [String: Any])
        XCTAssertEqual(diagnoseDecision["exitStatus"] as? Int, 0)
        XCTAssertEqual(diagnoseDecision["state"] as? String, "ready")
        XCTAssertEqual(diagnoseDecision["recommendedAgentAction"] as? String, "requestCooling")
        XCTAssertEqual(diagnoseDecision["recommendedRecoveryAction"] as? String, "none")
        XCTAssertEqual(diagnoseDecision["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(diagnoseDecision["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(diagnoseDecision["manualControlActive"] as? Bool, false)
        XCTAssertEqual(diagnoseDecision["failedCheckIDs"] as? [String], [])
        XCTAssertEqual(diagnoseDecision["coolingBlockerIDs"] as? [String], [])
        let appPreferences = try XCTUnwrap(diagnoseDecision["appPreferences"] as? [String: Any])
        XCTAssertEqual(appPreferences["startupMode"] as? String, "Auto")
        XCTAssertEqual(appPreferences["startupModeSource"] as? String, "persisted")
        XCTAssertTrue(appPreferences["readError"] is NSNull)
        let capabilitiesDecision = try XCTUnwrap(reviewSummary["capabilitiesDecision"] as? [String: Any])
        XCTAssertEqual(capabilitiesDecision["exitStatus"] as? Int, 0)
        XCTAssertEqual(capabilitiesDecision["schemaVersion"] as? Int, 1)
        XCTAssertEqual(
            capabilitiesDecision["capabilitiesSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-capabilities.schema.json"
        )
        XCTAssertEqual(
            capabilitiesDecision["diagnoseSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-diagnose.schema.json"
        )
        XCTAssertEqual(
            capabilitiesDecision["commandErrorSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-command-error.schema.json"
        )
        XCTAssertEqual(
            capabilitiesDecision["runSchemaID"] as? String,
            "https://vifty.local/schemas/viftyctl-run.schema.json"
        )
        XCTAssertEqual(capabilitiesDecision["daemonStatusAvailable"] as? Bool, true)
        XCTAssertEqual(capabilitiesDecision["policySource"] as? String, "daemonStatus")
        XCTAssertEqual(capabilitiesDecision["policyStatusAvailable"] as? Bool, true)
        XCTAssertEqual(capabilitiesDecision["policyEnabled"] as? Bool, true)
        XCTAssertEqual(capabilitiesDecision["supportsRunCommand"] as? Bool, true)
        XCTAssertEqual(capabilitiesDecision["supportsForceRetry"] as? Bool, true)
        XCTAssertEqual(capabilitiesDecision["runLifecycleSafe"] as? Bool, true)
        XCTAssertEqual(capabilitiesDecision["directControlLifecycleSafe"] as? Bool, true)
        XCTAssertEqual(capabilitiesDecision["metadataLimitsPresent"] as? Bool, true)
        XCTAssertEqual(capabilitiesDecision["unavailableExitCode"] as? Int, 69)
        let appInfo = try XCTUnwrap(reviewSummary["appInfo"] as? [String: Any])
        XCTAssertEqual(appInfo["exitStatus"] as? Int, 0)
        XCTAssertEqual(appInfo["bundleIdentifier"] as? String, "tech.reidar.vifty")
        XCTAssertEqual(appInfo["shortVersion"] as? String, "1.1.1")
        XCTAssertEqual(appInfo["bundleVersion"] as? String, "1")
        let guardedRunDecision = try XCTUnwrap(reviewSummary["guardedRunDecision"] as? [String: Any])
        XCTAssertEqual(guardedRunDecision["present"] as? Bool, false)
        XCTAssertTrue(guardedRunDecision["sourceFile"] is NSNull)
        XCTAssertTrue(guardedRunDecision["schemaID"] is NSNull)
        XCTAssertTrue(guardedRunDecision["decisionReason"] is NSNull)
        XCTAssertEqual(guardedRunDecision["failedCheckIDs"] as? [String], [])
        XCTAssertEqual(guardedRunDecision["coolingBlockerIDs"] as? [String], [])
        XCTAssertTrue((reviewSummary["acceptedCommandErrors"] as? [String])?.isEmpty == true)
        XCTAssertTrue((reviewSummary["failures"] as? [String])?.isEmpty == true)
    }

    func testReviewerSummarizesDiagnoseCheckIDsAndRejectsContradictoryCoolingBlockers() throws {
        let harness = try AgentCoolingEvidenceHarness(
            diagnoseJSON: #"{"state":"degraded","recommendedAgentAction":"requestCoolingWithCaution","safeToRequestCooling":true,"daemonControlPathReady":true,"manualControlActive":false,"recommendedRecoveryAction":"none","failedCheckIDs":["thermalPressureSafe"],"coolingBlockerIDs":["manualControlClear"],"appPreferences":{"startupMode":"Auto","startupModeSource":"persisted","readError":null},"checks":[]}"#
        )
        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("coolingBlockerIDs must be empty when safeToRequestCooling is true"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "failed")
        let diagnoseDecision = try XCTUnwrap(reviewSummary["diagnoseDecision"] as? [String: Any])
        XCTAssertEqual(diagnoseDecision["failedCheckIDs"] as? [String], ["thermalPressureSafe"])
        XCTAssertEqual(diagnoseDecision["coolingBlockerIDs"] as? [String], ["manualControlClear"])
        XCTAssertTrue((reviewSummary["failures"] as? [String])?.contains("coolingBlockerIDs must be empty when safeToRequestCooling is true") == true)
    }

    func testReviewerAcceptsBlockedDiagnoseAsReadOnlyEvidence() throws {
        let harness = try AgentCoolingEvidenceHarness(
            diagnoseJSON: #"{"state":"blocked","recommendedAgentAction":"doNotRequestCooling","safeToRequestCooling":false,"daemonControlPathReady":false,"recommendedRecoveryAction":"repairHelper","checks":[]}"#,
            diagnoseExitCode: 75
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 0, reviewResult.stderr)
        XCTAssertTrue(reviewResult.stdout.contains("Agent cooling evidence OK"))
    }

    func testReviewerAcceptsLegacyReadyEvidenceWithoutNewReadinessFields() throws {
        let harness = try AgentCoolingEvidenceHarness(
            capabilitiesJSON: try AgentCoolingEvidenceHarness.jsonString(
                removingTopLevelKeys: ["metadataLimits"],
                from: AgentCoolingEvidenceHarness.defaultCapabilitiesJSON
            ),
            diagnoseJSON: #"{"state":"ready","recommendedAgentAction":"requestCooling","safeToRequestCooling":true,"recommendedRecoveryAction":"none","checks":[]}"#
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 0, reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("missing metadataLimits"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("missing daemonControlPathReady"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "passed")
        let diagnoseDecision = try XCTUnwrap(reviewSummary["diagnoseDecision"] as? [String: Any])
        XCTAssertEqual(diagnoseDecision["daemonControlPathReady"] as? Bool, true)
        let capabilitiesDecision = try XCTUnwrap(reviewSummary["capabilitiesDecision"] as? [String: Any])
        XCTAssertEqual(capabilitiesDecision["metadataLimitsPresent"] as? Bool, false)
        let warnings = try XCTUnwrap(reviewSummary["warnings"] as? [String])
        XCTAssertTrue(warnings.contains { $0.contains("legacy read-only evidence") })
        XCTAssertTrue(warnings.contains { $0.contains("inferred true") })
        XCTAssertTrue(warnings.contains { $0.contains("missing appPreferences") })
        let appPreferences = try XCTUnwrap(diagnoseDecision["appPreferences"] as? [String: Any])
        XCTAssertTrue(appPreferences["startupMode"] is NSNull)
        XCTAssertTrue(appPreferences["startupModeSource"] is NSNull)
        XCTAssertTrue(appPreferences["readError"] is NSNull)
    }

    func testReviewerSurfacesManualControlStartupModeForAgentTriage() throws {
        let harness = try AgentCoolingEvidenceHarness(
            diagnoseJSON: #"""
            {
              "state": "degraded",
              "recommendedAgentAction": "restoreAutoBeforeRequestingCooling",
              "safeToRequestCooling": false,
              "daemonControlPathReady": true,
              "manualControlActive": true,
              "recommendedRecoveryAction": "restoreAutoBeforeRetry",
              "appPreferences": {
                "startupMode": "Curve",
                "startupModeSource": "persisted",
                "readError": null
              },
              "checks": []
            }
            """#
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 0, reviewResult.stderr)
        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "passed")
        let diagnoseDecision = try XCTUnwrap(reviewSummary["diagnoseDecision"] as? [String: Any])
        XCTAssertEqual(diagnoseDecision["manualControlActive"] as? Bool, true)
        let appPreferences = try XCTUnwrap(diagnoseDecision["appPreferences"] as? [String: Any])
        XCTAssertEqual(appPreferences["startupMode"] as? String, "Curve")
        XCTAssertEqual(appPreferences["startupModeSource"] as? String, "persisted")
        XCTAssertTrue(appPreferences["readError"] is NSNull)
        let warnings = try XCTUnwrap(reviewSummary["warnings"] as? [String])
        XCTAssertTrue(warnings.contains { warning in
            warning.contains("manualControlActive is true")
                && warning.contains("default startup mode is Curve")
                && warning.contains("switch the default mode to Auto")
        })
    }

    func testReviewerAcceptsLegacyHelperRepairEvidenceWithoutDaemonReadyField() throws {
        let harness = try AgentCoolingEvidenceHarness(
            capabilitiesJSON: try AgentCoolingEvidenceHarness.jsonString(
                removingTopLevelKeys: ["metadataLimits"],
                from: AgentCoolingEvidenceHarness.defaultUnavailableCapabilitiesJSON
            ),
            capabilitiesExitCode: 69,
            diagnoseJSON: #"{"state":"blocked","recommendedAgentAction":"doNotRequestCooling","safeToRequestCooling":false,"recommendedRecoveryAction":"repairHelper","checks":[]}"#,
            diagnoseExitCode: 75,
            statusJSON: AgentCoolingEvidenceHarness.commandErrorJSON(command: "status"),
            statusExitCode: 1,
            auditJSON: AgentCoolingEvidenceHarness.commandErrorJSON(command: "audit"),
            auditExitCode: 1
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 0, reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("accepted structured HELPER_UNREACHABLE command error"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("inferred false"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "passed")
        XCTAssertEqual(reviewSummary["acceptedCommandErrors"] as? [String], [
            "viftyctl-status",
            "viftyctl-audit"
        ])
        let diagnoseDecision = try XCTUnwrap(reviewSummary["diagnoseDecision"] as? [String: Any])
        XCTAssertEqual(diagnoseDecision["daemonControlPathReady"] as? Bool, false)
        let capabilitiesDecision = try XCTUnwrap(reviewSummary["capabilitiesDecision"] as? [String: Any])
        XCTAssertEqual(capabilitiesDecision["metadataLimitsPresent"] as? Bool, false)
    }

    func testReviewerRejectsCapabilitiesSchemaIdentityDrift() throws {
        let driftedVersion = try AgentCoolingEvidenceHarness.jsonString(
            replacing: "\"schemaVersion\":1",
            with: "\"schemaVersion\":2",
            in: AgentCoolingEvidenceHarness.defaultCapabilitiesJSON
        )
        let driftedSchemaID = try AgentCoolingEvidenceHarness.jsonString(
            replacing: "\"https://vifty.local/schemas/viftyctl-capabilities.schema.json\"",
            with: "\"https://example.invalid/viftyctl-capabilities.schema.json\"",
            in: driftedVersion
        )
        let driftedDiagnoseSchemaID = try AgentCoolingEvidenceHarness.jsonString(
            replacing: "\"https://vifty.local/schemas/viftyctl-diagnose.schema.json\"",
            with: "\"https://example.invalid/viftyctl-diagnose.schema.json\"",
            in: driftedSchemaID
        )
        let driftedCommandErrorSchemaID = try AgentCoolingEvidenceHarness.jsonString(
            replacing: "\"https://vifty.local/schemas/viftyctl-command-error.schema.json\"",
            with: "\"https://example.invalid/viftyctl-command-error.schema.json\"",
            in: driftedDiagnoseSchemaID
        )
        let harness = try AgentCoolingEvidenceHarness(capabilitiesJSON: driftedCommandErrorSchemaID)

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("viftyctl-capabilities.json schemaVersion must be 1"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("viftyctl-capabilities.json schemaIDs.capabilities"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("viftyctl-capabilities.json schemaIDs.diagnose"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("viftyctl-capabilities.json schemaIDs.commandError"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "failed")
        let capabilitiesDecision = try XCTUnwrap(reviewSummary["capabilitiesDecision"] as? [String: Any])
        XCTAssertEqual(capabilitiesDecision["schemaVersion"] as? Int, 2)
        XCTAssertEqual(
            capabilitiesDecision["capabilitiesSchemaID"] as? String,
            "https://example.invalid/viftyctl-capabilities.schema.json"
        )
        XCTAssertEqual(
            capabilitiesDecision["diagnoseSchemaID"] as? String,
            "https://example.invalid/viftyctl-diagnose.schema.json"
        )
        XCTAssertEqual(
            capabilitiesDecision["commandErrorSchemaID"] as? String,
            "https://example.invalid/viftyctl-command-error.schema.json"
        )
    }

    func testReviewerAcceptsHelperUnreachableCommandErrorsWhenDiagnoseRequiresRepair() throws {
        let harness = try AgentCoolingEvidenceHarness(
            capabilitiesJSON: AgentCoolingEvidenceHarness.defaultUnavailableCapabilitiesJSON,
            capabilitiesExitCode: 69,
            diagnoseJSON: #"{"state":"blocked","recommendedAgentAction":"doNotRequestCooling","safeToRequestCooling":false,"daemonControlPathReady":false,"recommendedRecoveryAction":"repairHelper","checks":[]}"#,
            diagnoseExitCode: 75,
            statusJSON: AgentCoolingEvidenceHarness.commandErrorJSON(command: "status"),
            statusExitCode: 1,
            auditJSON: AgentCoolingEvidenceHarness.commandErrorJSON(command: "audit"),
            auditExitCode: 1
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 0, reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("accepted structured HELPER_UNREACHABLE command error"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "passed")
        XCTAssertEqual(reviewSummary["acceptedCommandErrors"] as? [String], [
            "viftyctl-status",
            "viftyctl-audit"
        ])
        let diagnoseDecision = try XCTUnwrap(reviewSummary["diagnoseDecision"] as? [String: Any])
        XCTAssertEqual(diagnoseDecision["exitStatus"] as? Int, 75)
        XCTAssertEqual(diagnoseDecision["recommendedRecoveryAction"] as? String, "repairHelper")
        XCTAssertEqual(diagnoseDecision["daemonControlPathReady"] as? Bool, false)
        let capabilitiesDecision = try XCTUnwrap(reviewSummary["capabilitiesDecision"] as? [String: Any])
        XCTAssertEqual(capabilitiesDecision["exitStatus"] as? Int, 69)
        XCTAssertEqual(capabilitiesDecision["daemonStatusAvailable"] as? Bool, false)
        XCTAssertEqual(capabilitiesDecision["policySource"] as? String, "fallbackUnavailable")
        XCTAssertEqual(capabilitiesDecision["policyStatusAvailable"] as? Bool, false)
        XCTAssertEqual(capabilitiesDecision["supportsRunCommand"] as? Bool, true)
    }

    func testReviewerRejectsHelperUnreachableCommandErrorSchemaIdentityDrift() throws {
        let driftedStatusJSON = try AgentCoolingEvidenceHarness.jsonString(
            replacing: "https://vifty.local/schemas/viftyctl-command-error.schema.json",
            with: "https://example.invalid/viftyctl-command-error.schema.json",
            in: AgentCoolingEvidenceHarness.commandErrorJSON(command: "status")
        )
        let harness = try AgentCoolingEvidenceHarness(
            capabilitiesJSON: AgentCoolingEvidenceHarness.defaultUnavailableCapabilitiesJSON,
            capabilitiesExitCode: 69,
            diagnoseJSON: #"{"state":"blocked","recommendedAgentAction":"doNotRequestCooling","safeToRequestCooling":false,"daemonControlPathReady":false,"recommendedRecoveryAction":"repairHelper","checks":[]}"#,
            diagnoseExitCode: 75,
            statusJSON: driftedStatusJSON,
            statusExitCode: 1,
            auditJSON: AgentCoolingEvidenceHarness.commandErrorJSON(command: "audit"),
            auditExitCode: 1
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("viftyctl-status.json command-error schemaID"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("viftyctl-command-error.schema.json"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "failed")
        let acceptedCommandErrors = try XCTUnwrap(reviewSummary["acceptedCommandErrors"] as? [String])
        XCTAssertFalse(acceptedCommandErrors.contains("viftyctl-status"))
        XCTAssertTrue(acceptedCommandErrors.contains("viftyctl-audit"))
    }

    func testReviewerWarnsWhenKnownV110HelperIssueEvidenceIsCaptured() throws {
        let harness = try AgentCoolingEvidenceHarness(
            capabilitiesJSON: AgentCoolingEvidenceHarness.defaultUnavailableCapabilitiesJSON,
            capabilitiesExitCode: 69,
            diagnoseJSON: #"{"state":"blocked","recommendedAgentAction":"doNotRequestCooling","safeToRequestCooling":false,"daemonControlPathReady":false,"recommendedRecoveryAction":"repairHelper","checks":[]}"#,
            diagnoseExitCode: 75,
            statusJSON: AgentCoolingEvidenceHarness.commandErrorJSON(command: "status"),
            statusExitCode: 1,
            auditJSON: AgentCoolingEvidenceHarness.commandErrorJSON(command: "audit"),
            auditExitCode: 1,
            appShortVersion: "1.1.0"
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 0, reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("known v1.1.0 helper-unreachable issue"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("v1.1.1 source-first hotfix"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        let appInfo = try XCTUnwrap(reviewSummary["appInfo"] as? [String: Any])
        XCTAssertEqual(appInfo["shortVersion"] as? String, "1.1.0")
        let warnings = try XCTUnwrap(reviewSummary["warnings"] as? [String])
        XCTAssertTrue(warnings.contains { warning in
            warning.contains("known v1.1.0 helper-unreachable issue")
                && warning.contains("v1.1.1 source-first hotfix")
        })
    }

    func testReviewerRejectsNonzeroStatusWhenDiagnoseDoesNotRequireHelperRepair() throws {
        let harness = try AgentCoolingEvidenceHarness(
            statusJSON: AgentCoolingEvidenceHarness.commandErrorJSON(command: "status"),
            statusExitCode: 1
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("viftyctl-status must exit 0 unless blocked diagnose recommends repairHelper"), reviewResult.stderr)
        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "failed")
        XCTAssertTrue((reviewSummary["acceptedCommandErrors"] as? [String])?.isEmpty == true)
    }

    func testReviewerRejectsDiagnoseDecisionDrift() throws {
        let harness = try AgentCoolingEvidenceHarness(
            diagnoseJSON: #"{"state":"blocked","recommendedAgentAction":"requestCooling","safeToRequestCooling":true,"daemonControlPathReady":false,"recommendedRecoveryAction":"none","checks":[]}"#,
            diagnoseExitCode: 75
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("blocked diagnose must recommend doNotRequestCooling"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("blocked diagnose must set safeToRequestCooling false"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("daemonControlPathReady false must recommend repairHelper"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "failed")
        let diagnoseDecision = try XCTUnwrap(reviewSummary["diagnoseDecision"] as? [String: Any])
        XCTAssertEqual(diagnoseDecision["state"] as? String, "blocked")
        XCTAssertEqual(diagnoseDecision["recommendedAgentAction"] as? String, "requestCooling")
        XCTAssertEqual(diagnoseDecision["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(diagnoseDecision["daemonControlPathReady"] as? Bool, false)
    }

    func testReviewerKeepsMalformedDiagnoseDecisionSummarySchemaSafe() throws {
        let harness = try AgentCoolingEvidenceHarness(
            diagnoseJSON: #"{"state":"mystery","recommendedAgentAction":"fullSend","safeToRequestCooling":"yes","daemonControlPathReady":"no","recommendedRecoveryAction":"shrug","checks":[]}"#
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("state is missing or unsupported"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("recommendedAgentAction is missing or unsupported"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("safeToRequestCooling must be boolean"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("daemonControlPathReady must be boolean"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "failed")
        let diagnoseDecision = try XCTUnwrap(reviewSummary["diagnoseDecision"] as? [String: Any])
        XCTAssertEqual(diagnoseDecision["exitStatus"] as? Int, 0)
        XCTAssertTrue(diagnoseDecision["state"] is NSNull)
        XCTAssertTrue(diagnoseDecision["recommendedAgentAction"] is NSNull)
        XCTAssertTrue(diagnoseDecision["recommendedRecoveryAction"] is NSNull)
        XCTAssertTrue(diagnoseDecision["safeToRequestCooling"] is NSNull)
        XCTAssertTrue(diagnoseDecision["daemonControlPathReady"] is NSNull)
    }

    func testReviewerRejectsCapabilitiesContractDrift() throws {
        let harness = try AgentCoolingEvidenceHarness(
            capabilitiesJSON: #"{"schemaVersion":1,"daemonStatusAvailable":true,"policySource":"daemonStatus","policyStatusAvailable":"yes","commands":["capabilities","diagnose","status","audit"],"workloads":["build","test"],"supportsForceRetry":"yes","exitCodes":{"unavailable":69},"runLifecycle":{"childCommandPreflightBeforeCooling":false,"signalsForwardedToChild":["INT"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true},"directControlLifecycle":{"prepareUsesIdempotencyKey":true,"restoreAutoAcceptsIdempotencyKey":true,"restoreAutoScopedByIdempotencyKey":false,"preferRunForSingleChildWorkloads":true},"metadataLimits":{"maximumReasonLength":0,"maximumIdempotencyKeyLength":256}}"#
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("commands must include run"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("workloads must include build, test, and custom"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("policyStatusAvailable must be boolean"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("supportsForceRetry must be boolean"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("runLifecycle is missing or unsafe"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("directControlLifecycle is missing or unsafe"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("metadataLimits are invalid"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "failed")
        let capabilitiesDecision = try XCTUnwrap(reviewSummary["capabilitiesDecision"] as? [String: Any])
        XCTAssertEqual(capabilitiesDecision["supportsRunCommand"] as? Bool, false)
        XCTAssertEqual(capabilitiesDecision["runLifecycleSafe"] as? Bool, false)
        XCTAssertEqual(capabilitiesDecision["directControlLifecycleSafe"] as? Bool, false)
        XCTAssertEqual(capabilitiesDecision["metadataLimitsPresent"] as? Bool, false)
    }

    func testReviewerRejectsCapabilitiesWithoutResolvedExecutableRunProvenance() throws {
        let harness = try AgentCoolingEvidenceHarness(
            capabilitiesJSON: try AgentCoolingEvidenceHarness.jsonString(
                replacing: "\"resolvedChildExecutableReported\":true",
                with: "\"resolvedChildExecutableReported\":false",
                in: AgentCoolingEvidenceHarness.defaultCapabilitiesJSON
            )
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("runLifecycle is missing or unsafe"), reviewResult.stderr)
        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        let capabilitiesDecision = try XCTUnwrap(reviewSummary["capabilitiesDecision"] as? [String: Any])
        XCTAssertEqual(capabilitiesDecision["runLifecycleSafe"] as? Bool, false)
    }

    func testReviewerRejectsDisabledPolicyForSuccessfulCapabilities() throws {
        let harness = try AgentCoolingEvidenceHarness(
            capabilitiesJSON: try AgentCoolingEvidenceHarness.jsonString(
                replacing: "\"enabled\":true",
                with: "\"enabled\":false",
                in: AgentCoolingEvidenceHarness.defaultCapabilitiesJSON
            )
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewSummaryURL = harness.outputURL.appendingPathComponent("agent-cooling-evidence-review.json")
        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path,
            "--summary", reviewSummaryURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("successful capabilities review requires policy.enabled true"), reviewResult.stderr)

        let reviewSummary = try AgentCoolingEvidenceHarness.readJSON(reviewSummaryURL)
        XCTAssertEqual(reviewSummary["status"] as? String, "failed")
        let capabilitiesDecision = try XCTUnwrap(reviewSummary["capabilitiesDecision"] as? [String: Any])
        XCTAssertEqual(capabilitiesDecision["policyEnabled"] as? Bool, false)
    }

    func testReviewerRejectsNonzeroCapabilitiesWithoutFallbackUnavailablePolicy() throws {
        let harness = try AgentCoolingEvidenceHarness(
            capabilitiesExitCode: 69
        )

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("nonzero capabilities exit requires daemonStatusAvailable false"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("nonzero capabilities exit requires policySource fallbackUnavailable"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("nonzero capabilities exit requires policyStatusAvailable false"), reviewResult.stderr)
    }

    func testReviewerRejectsPrivacyFindings() throws {
        let harness = try AgentCoolingEvidenceHarness(includePrivacyLeak: true)

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("privacy-review"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("redaction-needed"), reviewResult.stderr)
    }

    func testReviewerRejectsSummarySchemaIDDrift() throws {
        let harness = try AgentCoolingEvidenceHarness()

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        var summary = try harness.readJSON("agent-cooling-evidence-summary.json")
        summary["schemaID"] = "https://example.invalid/schema.json"
        let driftedSummary = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try driftedSummary.write(to: harness.outputURL.appendingPathComponent("agent-cooling-evidence-summary.json"))

        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("schemaID"), reviewResult.stderr)
    }

    func testReviewerRejectsMissingChecksumEntry() throws {
        let harness = try AgentCoolingEvidenceHarness()

        let collectResult = try harness.runCollector([
            "--viftyctl", harness.viftyctlURL.path,
            "--output", harness.outputURL.path
        ])
        XCTAssertEqual(collectResult.exitCode, 0, collectResult.stderr)

        let checksums = try harness.read("checksums.tsv")
        let filteredChecksums = checksums
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.contains("\tviftyctl-diagnose.json") }
            .joined(separator: "\n")
        try harness.write("checksums.tsv", filteredChecksums + "\n")

        let reviewResult = try harness.runReviewer([
            "--bundle", harness.outputURL.path
        ])

        XCTAssertEqual(reviewResult.exitCode, 65)
        XCTAssertTrue(reviewResult.stderr.contains("checksum"), reviewResult.stderr)
        XCTAssertTrue(reviewResult.stderr.contains("viftyctl-diagnose.json"), reviewResult.stderr)
    }

    func testEvidenceSummarySchemaDocumentsCollectorContract() throws {
        let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/agent-cooling-evidence-summary.schema.json")
        let schema = try AgentCoolingEvidenceHarness.readJSON(schemaURL)

        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(
            schema["$id"] as? String,
            "https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json"
        )

        let required = try XCTUnwrap(schema["required"] as? [String])
        for field in [
            "schemaVersion",
            "schemaID",
            "generatedAtUTC",
            "readOnly",
            "coolingCommandsRun",
            "viftyctl",
            "auditLimit",
            "commands"
        ] {
            XCTAssertTrue(required.contains(field), "schema should require \(field)")
        }
    }

    func testEvidenceReviewSchemaDocumentsReviewerContract() throws {
        let schemaURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas/agent-cooling-evidence-review.schema.json")
        let schema = try AgentCoolingEvidenceHarness.readJSON(schemaURL)

        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(
            schema["$id"] as? String,
            "https://vifty.local/schemas/agent-cooling-evidence-review.schema.json"
        )

        let required = try XCTUnwrap(schema["required"] as? [String])
        for field in [
            "schemaVersion",
            "schemaID",
            "generatedAtUTC",
            "bundlePath",
            "status",
            "readOnly",
            "coolingCommandsRun",
            "commandsReviewed",
            "diagnoseDecision",
            "capabilitiesDecision",
            "appInfo",
            "guardedRunDecision",
            "acceptedCommandErrors",
            "failures",
            "warnings"
        ] {
            XCTAssertTrue(required.contains(field), "schema should require \(field)")
        }

        let defs = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let diagnoseDecision = try XCTUnwrap(defs["diagnoseDecision"] as? [String: Any])
        let diagnoseRequired = try XCTUnwrap(diagnoseDecision["required"] as? [String])
        for field in [
            "exitStatus",
            "state",
            "recommendedAgentAction",
            "recommendedRecoveryAction",
            "safeToRequestCooling",
            "daemonControlPathReady",
            "manualControlActive",
            "failedCheckIDs",
            "coolingBlockerIDs",
            "appPreferences"
        ] {
            XCTAssertTrue(diagnoseRequired.contains(field), "diagnoseDecision should require \(field)")
        }

        let diagnoseProperties = try XCTUnwrap(diagnoseDecision["properties"] as? [String: Any])
        XCTAssertEqual(diagnoseProperties["failedCheckIDs"] as? [String: String], ["$ref": "#/$defs/stringArray"])
        XCTAssertEqual(diagnoseProperties["coolingBlockerIDs"] as? [String: String], ["$ref": "#/$defs/stringArray"])
        XCTAssertEqual(diagnoseProperties["appPreferences"] as? [String: String], ["$ref": "#/$defs/appPreferencesDiagnostic"])

        let appPreferencesDiagnostic = try XCTUnwrap(defs["appPreferencesDiagnostic"] as? [String: Any])
        let appPreferencesRequired = try XCTUnwrap(appPreferencesDiagnostic["required"] as? [String])
        XCTAssertEqual(appPreferencesRequired, ["startupMode", "startupModeSource", "readError"])

        let capabilitiesDecision = try XCTUnwrap(defs["capabilitiesDecision"] as? [String: Any])
        let capabilitiesRequired = try XCTUnwrap(capabilitiesDecision["required"] as? [String])
        for field in [
            "exitStatus",
            "schemaVersion",
            "capabilitiesSchemaID",
            "diagnoseSchemaID",
            "commandErrorSchemaID",
            "runSchemaID",
            "daemonStatusAvailable",
            "policySource",
            "policyStatusAvailable",
            "policyEnabled",
            "supportsRunCommand",
            "supportsForceRetry",
            "runLifecycleSafe",
            "directControlLifecycleSafe",
            "metadataLimitsPresent",
            "unavailableExitCode"
        ] {
            XCTAssertTrue(capabilitiesRequired.contains(field), "capabilitiesDecision should require \(field)")
        }

        let appInfo = try XCTUnwrap(defs["appInfo"] as? [String: Any])
        let appInfoRequired = try XCTUnwrap(appInfo["required"] as? [String])
        for field in [
            "exitStatus",
            "bundleIdentifier",
            "shortVersion",
            "bundleVersion"
        ] {
            XCTAssertTrue(appInfoRequired.contains(field), "appInfo should require \(field)")
        }

        let guardedRunDecision = try XCTUnwrap(defs["guardedRunDecision"] as? [String: Any])
        let guardedRunRequired = try XCTUnwrap(guardedRunDecision["required"] as? [String])
        for field in [
            "present",
            "sourceFile",
            "schemaVersion",
            "schemaID",
            "safeToProceed",
            "coolingRequested",
            "uncooledFallbackRequested",
            "uncooledFallbackAllowed",
            "decisionReason",
            "exitCode",
            "message",
            "recommendedAgentAction",
            "recommendedRecoveryAction",
            "diagnoseState",
            "safeToRequestCooling",
            "daemonControlPathReady",
            "manualControlActive",
            "startupMode",
            "failedCheckIDs",
            "coolingBlockerIDs"
        ] {
            XCTAssertTrue(guardedRunRequired.contains(field), "guardedRunDecision should require \(field)")
        }
    }
}

private struct AgentCoolingEvidenceProcessResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

private final class AgentCoolingEvidenceHarness {
    let repositoryRoot: URL
    let rootURL: URL
    let outputURL: URL
    let viftyctlURL: URL
    let appInfoPlistURL: URL
    let logURL: URL
    private let capabilitiesJSONURL: URL
    private let diagnoseJSONURL: URL
    private let statusJSONURL: URL
    private let auditJSONURL: URL
    private let capabilitiesJSON: String
    private let capabilitiesExitCode: Int
    private let diagnoseJSON: String
    private let diagnoseExitCode: Int
    private let statusJSON: String
    private let statusExitCode: Int
    private let auditJSON: String
    private let auditExitCode: Int
    private let includePrivacyLeak: Bool
    private let appShortVersion: String

    init(
        capabilitiesJSON: String = AgentCoolingEvidenceHarness.defaultCapabilitiesJSON,
        capabilitiesExitCode: Int = 0,
        diagnoseJSON: String = #"{"state":"ready","recommendedAgentAction":"requestCooling","safeToRequestCooling":true,"daemonControlPathReady":true,"manualControlActive":false,"recommendedRecoveryAction":"none","failedCheckIDs":[],"coolingBlockerIDs":[],"appPreferences":{"startupMode":"Auto","startupModeSource":"persisted","readError":null},"checks":[]}"#,
        diagnoseExitCode: Int = 0,
        statusJSON: String = #"{"enabled":true,"activeLease":null,"lastDecision":null}"#,
        statusExitCode: Int = 0,
        auditJSON: String = #"{"readOnly":true,"coolingCommandsRun":false,"events":[]}"#,
        auditExitCode: Int = 0,
        includePrivacyLeak: Bool = false,
        appShortVersion: String = "1.1.1"
    ) throws {
        repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-agent-evidence-\(UUID().uuidString)", isDirectory: true)
        outputURL = rootURL.appendingPathComponent("evidence", isDirectory: true)
        let appBundleURL = rootURL.appendingPathComponent("Vifty.app", isDirectory: true)
        viftyctlURL = appBundleURL.appendingPathComponent("Contents/MacOS/viftyctl")
        appInfoPlistURL = appBundleURL.appendingPathComponent("Contents/Info.plist")
        logURL = rootURL.appendingPathComponent("viftyctl.log")
        capabilitiesJSONURL = rootURL.appendingPathComponent("capabilities.json")
        diagnoseJSONURL = rootURL.appendingPathComponent("diagnose.json")
        statusJSONURL = rootURL.appendingPathComponent("status.json")
        auditJSONURL = rootURL.appendingPathComponent("audit.json")
        self.capabilitiesJSON = capabilitiesJSON
        self.capabilitiesExitCode = capabilitiesExitCode
        self.diagnoseJSON = diagnoseJSON
        self.diagnoseExitCode = diagnoseExitCode
        self.statusJSON = statusJSON
        self.statusExitCode = statusExitCode
        self.auditJSON = auditJSON
        self.auditExitCode = auditExitCode
        self.includePrivacyLeak = includePrivacyLeak
        self.appShortVersion = appShortVersion

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try writeFakeJSONFixtures()
        try writeFakeAppInfoPlist()
        try writeFakeViftyCtl()
    }

    deinit {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func runCollector(_ arguments: [String]) throws -> AgentCoolingEvidenceProcessResult {
        let script = repositoryRoot.appendingPathComponent("scripts/collect-agent-cooling-evidence.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = repositoryRoot
        process.arguments = [script.path] + arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "VIFTY_FAKE_LOG": logURL.path,
            "VIFTY_TEST_SHELL_FIXTURES": "1",
            "VIFTY_FAKE_CAPABILITIES_JSON_FILE": capabilitiesJSONURL.path,
            "VIFTY_FAKE_CAPABILITIES_EXIT": "\(capabilitiesExitCode)",
            "VIFTY_FAKE_DIAGNOSE_JSON_FILE": diagnoseJSONURL.path,
            "VIFTY_FAKE_DIAGNOSE_EXIT": "\(diagnoseExitCode)",
            "VIFTY_FAKE_STATUS_JSON_FILE": statusJSONURL.path,
            "VIFTY_FAKE_STATUS_EXIT": "\(statusExitCode)",
            "VIFTY_FAKE_AUDIT_JSON_FILE": auditJSONURL.path,
            "VIFTY_FAKE_AUDIT_EXIT": "\(auditExitCode)"
        ]) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return AgentCoolingEvidenceProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    func runReviewer(_ arguments: [String]) throws -> AgentCoolingEvidenceProcessResult {
        let script = repositoryRoot.appendingPathComponent("scripts/review-agent-cooling-evidence.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = repositoryRoot
        process.arguments = [script.path] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        return AgentCoolingEvidenceProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    func read(_ relativePath: String) throws -> String {
        try String(contentsOf: outputURL.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func write(_ relativePath: String, _ contents: String) throws {
        try contents.write(to: outputURL.appendingPathComponent(relativePath), atomically: true, encoding: .utf8)
    }

    func readJSON(_ relativePath: String) throws -> [String: Any] {
        try Self.readJSON(outputURL.appendingPathComponent(relativePath))
    }

    static func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func jsonString(removingTopLevelKeys keys: [String], from json: String) throws -> String {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        for key in keys {
            object.removeValue(forKey: key)
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    static func jsonString(replacing needle: String, with replacement: String, in json: String) throws -> String {
        XCTAssertTrue(json.contains(needle))
        return json.replacingOccurrences(of: needle, with: replacement)
    }

    func loggedArguments() throws -> [String] {
        guard FileManager.default.fileExists(atPath: logURL.path) else {
            return []
        }
        return try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
    }

    private func writeFakeJSONFixtures() throws {
        try capabilitiesJSON.write(to: capabilitiesJSONURL, atomically: true, encoding: .utf8)
        try diagnoseJSON.write(to: diagnoseJSONURL, atomically: true, encoding: .utf8)
        try statusJSON.write(to: statusJSONURL, atomically: true, encoding: .utf8)
        try auditJSON.write(to: auditJSONURL, atomically: true, encoding: .utf8)
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
            cat "${VIFTY_FAKE_CAPABILITIES_JSON_FILE:?}"
            printf '\\n'
            exit "${VIFTY_FAKE_CAPABILITIES_EXIT}"
            ;;
          diagnose)
            test "${2:-}" = "--json"
            cat "${VIFTY_FAKE_DIAGNOSE_JSON_FILE:?}"
            printf '\\n'
            exit "${VIFTY_FAKE_DIAGNOSE_EXIT}"
            ;;
          status)
            test "${2:-}" = "--json"
            if [ "\(includePrivacyLeak ? "1" : "0")" = "1" ]; then
              printf '%s\\n' '{"enabled":true,"activeLease":null,"lastDecision":null,"debug":"Serial Number: C02SECRET1234 /Users/private-user/Vifty.app"}'
            else
              cat "${VIFTY_FAKE_STATUS_JSON_FILE:?}"
              printf '\\n'
            fi
            exit "${VIFTY_FAKE_STATUS_EXIT}"
            ;;
          audit)
            test "${2:-}" = "--limit"
            test "${4:-}" = "--json"
            cat "${VIFTY_FAKE_AUDIT_JSON_FILE:?}"
            printf '\\n'
            exit "${VIFTY_FAKE_AUDIT_EXIT}"
            ;;
          *)
            echo "unexpected mutating or unsupported command: $*" >&2
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

    private func writeFakeAppInfoPlist() throws {
        try FileManager.default.createDirectory(
            at: appInfoPlistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>tech.reidar.vifty</string>
            <key>CFBundleName</key>
            <string>Vifty</string>
            <key>CFBundleShortVersionString</key>
            <string>\(appShortVersion)</string>
            <key>CFBundleVersion</key>
            <string>1</string>
        </dict>
        </plist>
        """
        try plist.write(to: appInfoPlistURL, atomically: true, encoding: .utf8)
    }

    fileprivate static let defaultCapabilitiesJSON = """
    {"schemaVersion":1,"daemonStatusAvailable":true,"policyStatusAvailable":true,"policySource":"daemonStatus","agentControlStatusError":null,"commands":["status","capabilities","diagnose","audit","prepare","restore-auto","run"],"workloads":["build","test","render","localModel","custom"],"supportsForceRetry":true,"policy":{"enabled":true,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"exitCodes":{"success":0,"commandFailure":1,"usage":64,"unavailable":69,"blockedReadiness":75},"runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true,"resolvedChildExecutableReported":true},"directControlLifecycle":{"prepareUsesIdempotencyKey":true,"restoreAutoAcceptsIdempotencyKey":false,"restoreAutoScopedByIdempotencyKey":false,"preferRunForSingleChildWorkloads":true},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256},"schemas":{"capabilities":"docs/schemas/viftyctl-capabilities.schema.json","audit":"docs/schemas/viftyctl-audit.schema.json","diagnose":"docs/schemas/viftyctl-diagnose.schema.json","status":"docs/schemas/viftyctl-status.schema.json","commandError":"docs/schemas/viftyctl-command-error.schema.json","run":"docs/schemas/viftyctl-run.schema.json"},"schemaResources":{"capabilities":"Contents/Resources/schemas/viftyctl-capabilities.schema.json","audit":"Contents/Resources/schemas/viftyctl-audit.schema.json","diagnose":"Contents/Resources/schemas/viftyctl-diagnose.schema.json","status":"Contents/Resources/schemas/viftyctl-status.schema.json","commandError":"Contents/Resources/schemas/viftyctl-command-error.schema.json","run":"Contents/Resources/schemas/viftyctl-run.schema.json"},"schemaIDs":{"capabilities":"https://vifty.local/schemas/viftyctl-capabilities.schema.json","audit":"https://vifty.local/schemas/viftyctl-audit.schema.json","diagnose":"https://vifty.local/schemas/viftyctl-diagnose.schema.json","status":"https://vifty.local/schemas/viftyctl-status.schema.json","commandError":"https://vifty.local/schemas/viftyctl-command-error.schema.json","run":"https://vifty.local/schemas/viftyctl-run.schema.json"}}
    """

    fileprivate static let defaultUnavailableCapabilitiesJSON = """
    {"schemaVersion":1,"daemonStatusAvailable":false,"policyStatusAvailable":false,"policySource":"fallbackUnavailable","agentControlStatusError":"daemon unavailable","commands":["status","capabilities","diagnose","audit","prepare","restore-auto","run"],"workloads":["build","test","render","localModel","custom"],"supportsForceRetry":true,"policy":{"enabled":false,"minimumAgentRPMPercent":35,"maximumAllowedRPMPercent":80,"maxDurationSeconds":1800,"prepareCooldownSeconds":30},"exitCodes":{"success":0,"commandFailure":1,"usage":64,"unavailable":69,"blockedReadiness":75},"runLifecycle":{"childCommandPreflightBeforeCooling":true,"signalsForwardedToChild":["INT","TERM","HUP"],"autoRestoreAfterChildExit":true,"structuredPreChildFailures":true,"cleanupStateReportedOnLaunchFailure":true,"resolvedChildExecutableReported":true},"directControlLifecycle":{"prepareUsesIdempotencyKey":true,"restoreAutoAcceptsIdempotencyKey":false,"restoreAutoScopedByIdempotencyKey":false,"preferRunForSingleChildWorkloads":true},"metadataLimits":{"maximumReasonLength":512,"maximumIdempotencyKeyLength":256},"schemas":{"capabilities":"docs/schemas/viftyctl-capabilities.schema.json","audit":"docs/schemas/viftyctl-audit.schema.json","diagnose":"docs/schemas/viftyctl-diagnose.schema.json","status":"docs/schemas/viftyctl-status.schema.json","commandError":"docs/schemas/viftyctl-command-error.schema.json","run":"docs/schemas/viftyctl-run.schema.json"},"schemaResources":{"capabilities":"Contents/Resources/schemas/viftyctl-capabilities.schema.json","audit":"Contents/Resources/schemas/viftyctl-audit.schema.json","diagnose":"Contents/Resources/schemas/viftyctl-diagnose.schema.json","status":"Contents/Resources/schemas/viftyctl-status.schema.json","commandError":"Contents/Resources/schemas/viftyctl-command-error.schema.json","run":"Contents/Resources/schemas/viftyctl-run.schema.json"},"schemaIDs":{"capabilities":"https://vifty.local/schemas/viftyctl-capabilities.schema.json","audit":"https://vifty.local/schemas/viftyctl-audit.schema.json","diagnose":"https://vifty.local/schemas/viftyctl-diagnose.schema.json","status":"https://vifty.local/schemas/viftyctl-status.schema.json","commandError":"https://vifty.local/schemas/viftyctl-command-error.schema.json","run":"https://vifty.local/schemas/viftyctl-run.schema.json"}}
    """

    fileprivate static func commandErrorJSON(command: String) -> String {
        """
        {"schemaVersion":1,"schemaID":"https://vifty.local/schemas/viftyctl-command-error.schema.json","command":"\(command)","errorCode":"HELPER_UNREACHABLE","message":"daemon unavailable","safeToProceed":false,"recommendedRecoveryAction":"repairHelper","coolingLeasePrepared":false,"autoRestoreAttempted":false,"autoRestoreSucceeded":null,"generatedAt":700000000}
        """
    }
}
