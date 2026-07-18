import Foundation
import XCTest
@testable import ViftyCore

final class ViftyCtlRunnerTests: XCTestCase {
    private static let restoreAutoRecoverySteps = [
        "Restore Auto once with Vifty or viftyctl restore-auto --json, then rerun diagnose --json.",
        "If manualControlActive remains true, switch Vifty/default startup mode to Auto before requesting cooling."
    ]

    func testCommandErrorRecoveryActionsMapSafeNextSteps() {
        XCTAssertEqual(ViftyCtlCommandErrorRecoveryAction.recommended(for: .helperUnreachable), .repairHelper)
        XCTAssertEqual(ViftyCtlCommandErrorRecoveryAction.recommended(for: .invalidArguments), .fixArguments)
        XCTAssertEqual(ViftyCtlCommandErrorRecoveryAction.recommended(for: .childCommandFailed), .fixChildCommand)
        XCTAssertEqual(ViftyCtlCommandErrorRecoveryAction.recommended(for: .restoreRequested), .restoreAutoBeforeRetry)
        XCTAssertEqual(ViftyCtlCommandErrorRecoveryAction.recommended(for: .prepareRateLimited), .waitBeforeRetry)
        XCTAssertEqual(ViftyCtlCommandErrorRecoveryAction.recommended(for: .thermalCritical), .runDiagnose)
        XCTAssertEqual(ViftyCtlCommandErrorRecoveryAction.recommended(for: nil), .runDiagnose)
    }

    func testStatusReturnsJSONAndDoesNotMutate() async throws {
        let client = FakeAgentControlClient(
            status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil
            )
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.status(json: true))

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(json["generatedAt"] as? Double, 721_692_800)
        XCTAssertEqual(json["enabled"] as? Bool, true)
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testStatusJSONReturnsStructuredErrorWhenDaemonUnavailable() async throws {
        let client = FakeAgentControlClient(
            statusError: ViftyError.helperRejected("Daemon request timed out.")
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.status(json: true))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(json["command"] as? String, "status")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.helperUnreachable.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.repairHelper.rawValue)
        XCTAssertEqual(json["recoverySteps"] as? [String], ViftyAgentRule.repairHelperRecoveryActions)
        XCTAssertTrue((json["message"] as? String)?.contains("Daemon request timed out") == true)
    }

    func testStatusHumanReadableStillThrowsWhenDaemonUnavailable() async throws {
        let expected = ViftyError.helperRejected("Daemon request timed out.")
        let client = FakeAgentControlClient(statusError: expected)
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            manualControlActiveReader: { false }
        )

        do {
            _ = try await runner.run(.status(json: false))
            XCTFail("Expected non-JSON status to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, expected.localizedDescription)
        }
    }

    func testCapabilitiesReturnsSupportedCommands() async throws {
        let runner = ViftyCtlRunner(
            client: FakeAgentControlClient(status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true, maximumAllowedRPMPercent: 75, maxDurationSeconds: 1_800, prepareCooldownSeconds: 12).snapshot
            )),
            processRunner: FakeProcessRunner()
        )

        let result = try await runner.run(.capabilities(json: false))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("status"))
        XCTAssertTrue(result.stdout.contains("diagnose"))
        XCTAssertTrue(result.stdout.contains("prepare"))
        XCTAssertTrue(result.stdout.contains("agent-rule"))
    }

    func testAgentRuleReturnsPasteableRuleWithoutDaemonMutation() async throws {
        let client = FakeAgentControlClient(
            status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil
            )
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner()
        )

        let result = try await runner.run(.agentRule(json: false))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        XCTAssertTrue(result.stdout.contains("For long local build/test/model workloads on this Mac"))
        XCTAssertTrue(result.stdout.contains("'/Applications/Vifty.app/Contents/MacOS/viftyctl' capabilities --json"))
        XCTAssertTrue(result.stdout.contains("'/Applications/Vifty.app/Contents/MacOS/viftyctl' diagnose --json"))
        XCTAssertTrue(result.stdout.contains("workloadTemplates"))
        XCTAssertTrue(result.stdout.contains("guarded-run.sh"))
        XCTAssertTrue(result.stdout.contains("Never call `ViftyHelper setFixed`, `ViftyHelper auto`, `sudo`, raw SMC tools, direct fan RPM writes, or unguarded `viftyctl prepare` from an agent."))
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testAgentRuleJSONIsSchemaBackedAndMachineReadable() async throws {
        let runner = ViftyCtlRunner(
            client: FakeAgentControlClient(status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil
            )),
            processRunner: FakeProcessRunner(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.agentRule(json: true))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-agent-rule.schema.json")
        XCTAssertEqual(json["command"] as? String, "agent-rule")
        XCTAssertEqual(json["generatedAt"] as? Double, 721_692_800)
        let rule = try XCTUnwrap(json["rule"] as? String)
        XCTAssertTrue(rule.contains("safeToRequestCooling"))
        XCTAssertTrue(rule.contains("guardedRunJSONMarkers.capabilities.begin"))
        XCTAssertTrue(rule.contains("guardedRunJSONMarkers.diagnose.begin"))
        XCTAssertTrue(rule.contains("guardedRunJSONMarkers.decision.begin"))
        XCTAssertTrue(rule.contains("repairHelperRecoveryActions"))
        XCTAssertTrue(rule.contains("make repair-helper"))
        XCTAssertEqual(json["viftyctlCommand"] as? String, "'/Applications/Vifty.app/Contents/MacOS/viftyctl'")
        XCTAssertEqual(json["capabilitiesCommand"] as? String, "'/Applications/Vifty.app/Contents/MacOS/viftyctl' capabilities --json")
        XCTAssertEqual(json["diagnoseCommand"] as? String, "'/Applications/Vifty.app/Contents/MacOS/viftyctl' diagnose --json")
        XCTAssertEqual(
            json["strictDiagnoseCommand"] as? String,
            "'/Applications/Vifty.app/Contents/MacOS/viftyctl' diagnose --json --require-safe"
        )
        XCTAssertEqual(
            json["agentCoolingEvidenceCommand"] as? String,
            "umask 077; out=\"$HOME/Library/Application Support/Vifty/Support Evidence/vifty-agent-cooling-$(date -u +%Y%m%dT%H%M%SZ)\"; '/Applications/Vifty.app/Contents/Resources/collect-agent-cooling-evidence.sh' --viftyctl '/Applications/Vifty.app/Contents/MacOS/viftyctl' --output \"$out\""
        )
        XCTAssertEqual(
            json["agentCoolingPreflightEvidenceCommand"] as? String,
            "umask 077; out=\"$HOME/Library/Application Support/Vifty/Support Evidence/vifty-agent-cooling-$(date -u +%Y%m%dT%H%M%SZ)\"; '/Applications/Vifty.app/Contents/Resources/collect-agent-cooling-evidence.sh' --viftyctl '/Applications/Vifty.app/Contents/MacOS/viftyctl' --output \"$out\" --guarded-run-script '/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/guarded-run.sh' --guarded-run-preflight 'test' '20m' '70' 'swift test' '--' 'swift' 'test'"
        )
        XCTAssertEqual(json["repairHelperRecoveryActions"] as? [String], ViftyAgentRule.repairHelperRecoveryActions)
        XCTAssertEqual(json["guardedRunDecisionSchemaID"] as? String, "https://vifty.local/schemas/guarded-run-decision.schema.json")
        let guardedRunJSONMarkers = try XCTUnwrap(json["guardedRunJSONMarkers"] as? [String: [String: String]])
        XCTAssertEqual(guardedRunJSONMarkers["capabilities"]?["begin"], "guarded-run: BEGIN_VIFTY_CAPABILITIES_JSON")
        XCTAssertEqual(guardedRunJSONMarkers["capabilities"]?["end"], "guarded-run: END_VIFTY_CAPABILITIES_JSON")
        XCTAssertEqual(guardedRunJSONMarkers["diagnose"]?["begin"], "guarded-run: BEGIN_VIFTY_DIAGNOSE_JSON")
        XCTAssertEqual(guardedRunJSONMarkers["diagnose"]?["end"], "guarded-run: END_VIFTY_DIAGNOSE_JSON")
        XCTAssertEqual(guardedRunJSONMarkers["decision"]?["begin"], "guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON")
        XCTAssertEqual(guardedRunJSONMarkers["decision"]?["end"], "guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON")
        XCTAssertTrue((json["guardedRunCommand"] as? String)?.contains("swift-test.sh") == true)
        XCTAssertTrue((json["guardedRunPreflightCommand"] as? String)?.contains("--preflight-only") == true)
        XCTAssertTrue((json["schemaRequirements"] as? [String])?.contains("schemaIDs.agentRule") == true)
        XCTAssertTrue((json["schemaRequirements"] as? [String])?.contains("guardedRunJSONMarkers") == true)
        XCTAssertTrue((json["schemaRequirements"] as? [String])?.contains("agentCoolingEvidenceCommand") == true)
        XCTAssertTrue((json["schemaRequirements"] as? [String])?.contains("agentCoolingPreflightEvidenceCommand") == true)
        XCTAssertTrue((json["safetyRequirements"] as? [String])?.contains("daemonControlPathReady == true") == true)
        XCTAssertTrue((json["safetyRequirements"] as? [String])?.contains("daemonRuntime.matchRequired != true || daemonRuntime.matchesExpectedDaemon == true") == true)
        XCTAssertTrue((json["forbiddenActions"] as? [String])?.contains("ViftyHelper setFixed") == true)
        XCTAssertTrue((json["workloadTemplateIDs"] as? [String])?.contains("swift-test") == true)
    }

    func testAgentRuleJSONCanUseSourceCheckoutBundleURL() async throws {
        let root = try temporaryDirectory()
        try Data("swift-tools-version: 6.0\n".utf8).write(to: root.appendingPathComponent("Package.swift"))

        let buildURL = root.appendingPathComponent(".build/debug", isDirectory: true)
        let wrappersURL = root.appendingPathComponent("examples/viftyctl", isDirectory: true)
        try FileManager.default.createDirectory(at: buildURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wrappersURL, withIntermediateDirectories: true)

        let viftyCtlURL = buildURL.appendingPathComponent("ViftyCtl", isDirectory: false)
        let guardedRunURL = wrappersURL.appendingPathComponent("guarded-run.sh", isDirectory: false)
        let swiftTestURL = wrappersURL.appendingPathComponent("swift-test.sh", isDirectory: false)
        let evidenceCollectorURL = root.appendingPathComponent("scripts/collect-agent-cooling-evidence.sh", isDirectory: false)
        try FileManager.default.createDirectory(at: evidenceCollectorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        for executableURL in [viftyCtlURL, guardedRunURL, swiftTestURL, evidenceCollectorURL] {
            try Data("#!/bin/sh\n".utf8).write(to: executableURL)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: executableURL.path)
        }

        let runner = ViftyCtlRunner(
            client: FakeAgentControlClient(status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil
            )),
            processRunner: FakeProcessRunner(),
            agentRuleBundleURL: buildURL,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.agentRule(json: true))

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["viftyctlCommand"] as? String, "'\(viftyCtlURL.path)'")
        XCTAssertEqual(json["capabilitiesCommand"] as? String, "'\(viftyCtlURL.path)' capabilities --json")
        XCTAssertEqual(json["diagnoseCommand"] as? String, "'\(viftyCtlURL.path)' diagnose --json")
        XCTAssertEqual(json["strictDiagnoseCommand"] as? String, "'\(viftyCtlURL.path)' diagnose --json --require-safe")
        XCTAssertTrue((json["agentCoolingEvidenceCommand"] as? String)?.contains("'\(evidenceCollectorURL.path)' --viftyctl '\(viftyCtlURL.path)' --output \"$out\"") == true)
        XCTAssertTrue((json["agentCoolingPreflightEvidenceCommand"] as? String)?.contains("'\(evidenceCollectorURL.path)' --viftyctl '\(viftyCtlURL.path)' --output \"$out\" --guarded-run-script '\(guardedRunURL.path)' --guarded-run-preflight") == true)
        XCTAssertTrue((json["guardedRunCommand"] as? String)?.contains("VIFTYCTL='\(viftyCtlURL.path)' '\(swiftTestURL.path)'") == true)
        XCTAssertTrue((json["guardedRunPreflightCommand"] as? String)?.contains("VIFTYCTL='\(viftyCtlURL.path)' '\(guardedRunURL.path)' '--preflight-only'") == true)
        XCTAssertFalse((json["guardedRunCommand"] as? String)?.contains("/Applications/Vifty.app") == true)
        XCTAssertFalse((json["guardedRunPreflightCommand"] as? String)?.contains("/Applications/Vifty.app") == true)
    }

    func testCapabilitiesJSONIncludesPolicyAndWorkloads() async throws {
        let runner = ViftyCtlRunner(
            client: FakeAgentControlClient(status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true, maximumAllowedRPMPercent: 75, maxDurationSeconds: 1_800, prepareCooldownSeconds: 12).snapshot
            )),
            processRunner: FakeProcessRunner()
        )

        let result = try await runner.run(.capabilities(json: true))

        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["daemonStatusAvailable"] as? Bool, true)
        XCTAssertEqual(json["policyStatusAvailable"] as? Bool, true)
        XCTAssertEqual(json["policySource"] as? String, ViftyCtlPolicySource.daemonStatus.rawValue)
        XCTAssertNil(json["agentControlStatusError"] as? String)
        XCTAssertTrue((json["commands"] as? [String])?.contains("run") == true)
        XCTAssertTrue((json["workloads"] as? [String])?.contains("build") == true)
        let schemas = try XCTUnwrap(json["schemas"] as? [String: Any])
        XCTAssertEqual(schemas["capabilities"] as? String, "docs/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(schemas["audit"] as? String, "docs/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(schemas["diagnose"] as? String, "docs/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(schemas["status"] as? String, "docs/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(schemas["commandError"] as? String, "docs/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(schemas["run"] as? String, "docs/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(schemas["agentRule"] as? String, "docs/schemas/viftyctl-agent-rule.schema.json")
        let schemaResources = try XCTUnwrap(json["schemaResources"] as? [String: Any])
        XCTAssertEqual(schemaResources["capabilities"] as? String, "Contents/Resources/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(schemaResources["audit"] as? String, "Contents/Resources/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(schemaResources["diagnose"] as? String, "Contents/Resources/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(schemaResources["status"] as? String, "Contents/Resources/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(schemaResources["commandError"] as? String, "Contents/Resources/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(schemaResources["run"] as? String, "Contents/Resources/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(schemaResources["agentRule"] as? String, "Contents/Resources/schemas/viftyctl-agent-rule.schema.json")
        let wrapperResources = try XCTUnwrap(json["wrapperResources"] as? [String: Any])
        XCTAssertEqual(wrapperResources["sourceDirectory"] as? String, "examples/viftyctl")
        XCTAssertEqual(wrapperResources["bundleDirectory"] as? String, "Contents/Resources/viftyctl-wrappers")
        XCTAssertEqual(wrapperResources["guardedRunScript"] as? String, "guarded-run.sh")
        XCTAssertTrue((wrapperResources["workloadScripts"] as? [String])?.contains("swift-test.sh") == true)
        XCTAssertTrue((wrapperResources["workloadScripts"] as? [String])?.contains("make-build.sh") == true)
        XCTAssertTrue((wrapperResources["workloadScripts"] as? [String])?.contains("pnpm-build.sh") == true)
        XCTAssertTrue((wrapperResources["workloadScripts"] as? [String])?.contains("pnpm-test.sh") == true)
        XCTAssertTrue((wrapperResources["workloadScripts"] as? [String])?.contains("bun-build.sh") == true)
        XCTAssertTrue((wrapperResources["workloadScripts"] as? [String])?.contains("bun-test.sh") == true)
        XCTAssertTrue((wrapperResources["workloadScripts"] as? [String])?.contains("go-build.sh") == true)
        XCTAssertTrue((wrapperResources["workloadScripts"] as? [String])?.contains("go-test.sh") == true)
        XCTAssertTrue((wrapperResources["workloadScripts"] as? [String])?.contains("custom-workload.sh") == true)
        let workloadTemplates = try XCTUnwrap(json["workloadTemplates"] as? [[String: Any]])
        XCTAssertEqual(workloadTemplates.count, ViftyCtlWorkloadTemplate.auditedTemplates.count)
        let swiftTestTemplate = try XCTUnwrap(workloadTemplates.first { ($0["id"] as? String) == "swift-test" })
        XCTAssertEqual(swiftTestTemplate["title"] as? String, "Swift test")
        XCTAssertEqual(swiftTestTemplate["workload"] as? String, "test")
        XCTAssertEqual(swiftTestTemplate["duration"] as? String, "20m")
        XCTAssertEqual(swiftTestTemplate["maxRPMPercent"] as? Int, 70)
        XCTAssertEqual(swiftTestTemplate["reason"] as? String, "swift test")
        XCTAssertEqual(swiftTestTemplate["childArguments"] as? [String], ["swift", "test"])
        XCTAssertEqual(swiftTestTemplate["shortcutScript"] as? String, "swift-test.sh")
        XCTAssertEqual(swiftTestTemplate["shortcutArguments"] as? [String], [])
        let customTemplate = try XCTUnwrap(workloadTemplates.first { ($0["id"] as? String) == "custom-workload-template" })
        XCTAssertEqual(customTemplate["workload"] as? String, "custom")
        XCTAssertEqual(customTemplate["shortcutScript"] as? String, "custom-workload.sh")
        XCTAssertEqual(
            customTemplate["shortcutArguments"] as? [String],
            ["15m", "65", "custom workload", "--", "./scripts/smoke-test.sh"]
        )
        XCTAssertEqual(
            Set(workloadTemplates.compactMap { $0["shortcutScript"] as? String }),
            Set(ViftyCtlWrapperResources.workloadScriptNames)
        )
        let schemaIDs = try XCTUnwrap(json["schemaIDs"] as? [String: Any])
        XCTAssertEqual(schemaIDs["capabilities"] as? String, "https://vifty.local/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(schemaIDs["audit"] as? String, "https://vifty.local/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(schemaIDs["diagnose"] as? String, "https://vifty.local/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(schemaIDs["status"] as? String, "https://vifty.local/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(schemaIDs["commandError"] as? String, "https://vifty.local/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(schemaIDs["run"] as? String, "https://vifty.local/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(schemaIDs["agentRule"] as? String, "https://vifty.local/schemas/viftyctl-agent-rule.schema.json")
        let exitCodes = try XCTUnwrap(json["exitCodes"] as? [String: Any])
        XCTAssertEqual(exitCodes["success"] as? Int, 0)
        XCTAssertEqual(exitCodes["commandFailure"] as? Int, 1)
        XCTAssertEqual(exitCodes["usage"] as? Int, 64)
        XCTAssertEqual(exitCodes["unavailable"] as? Int, 69)
        XCTAssertEqual(exitCodes["blockedReadiness"] as? Int, 75)
        let runLifecycle = try XCTUnwrap(json["runLifecycle"] as? [String: Any])
        XCTAssertEqual(runLifecycle["childCommandPreflightBeforeCooling"] as? Bool, true)
        XCTAssertEqual(runLifecycle["signalsForwardedToChild"] as? [String], ["INT", "TERM", "HUP"])
        XCTAssertEqual(runLifecycle["autoRestoreAfterChildExit"] as? Bool, true)
        XCTAssertEqual(runLifecycle["structuredPreChildFailures"] as? Bool, true)
        XCTAssertEqual(runLifecycle["cleanupStateReportedOnLaunchFailure"] as? Bool, true)
        XCTAssertEqual(runLifecycle["resolvedChildExecutableReported"] as? Bool, true)
        XCTAssertEqual(runLifecycle["signalScope"] as? String, ViftyCtlSignalScope.processGroup.rawValue)
        XCTAssertEqual(runLifecycle["descendantCleanupBeforeAutoRestore"] as? Bool, true)
        XCTAssertEqual(runLifecycle["backgroundProcessesAllowed"] as? Bool, false)
        let directControlLifecycle = try XCTUnwrap(json["directControlLifecycle"] as? [String: Any])
        XCTAssertEqual(directControlLifecycle["prepareUsesIdempotencyKey"] as? Bool, true)
        XCTAssertEqual(directControlLifecycle["restoreAutoAcceptsIdempotencyKey"] as? Bool, false)
        XCTAssertEqual(directControlLifecycle["restoreAutoScopedByIdempotencyKey"] as? Bool, false)
        XCTAssertEqual(directControlLifecycle["preferRunForSingleChildWorkloads"] as? Bool, true)
        let metadataLimits = try XCTUnwrap(json["metadataLimits"] as? [String: Any])
        XCTAssertEqual(metadataLimits["maximumReasonLength"] as? Int, AgentControlRequest.maximumReasonLength)
        XCTAssertEqual(metadataLimits["maximumIdempotencyKeyLength"] as? Int, AgentControlRequest.maximumIdempotencyKeyLength)
        XCTAssertEqual(json["supportsForceRetry"] as? Bool, true)
        let policy = try XCTUnwrap(json["policy"] as? [String: Any])
        XCTAssertEqual(policy["maximumAllowedRPMPercent"] as? Int, 75)
        XCTAssertEqual(policy["maxDurationSeconds"] as? Int, 1_800)
        XCTAssertEqual(policy["prepareCooldownSeconds"] as? Int, 12)
    }

    func testCapabilitiesJSONMarksPolicyStatusUnavailableWhenDaemonStatusOmitsPolicy() async throws {
        let runner = ViftyCtlRunner(
            client: FakeAgentControlClient(status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: nil
            )),
            processRunner: FakeProcessRunner()
        )

        let result = try await runner.run(.capabilities(json: true))

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["daemonStatusAvailable"] as? Bool, true)
        XCTAssertEqual(json["policyStatusAvailable"] as? Bool, false)
        XCTAssertEqual(json["policySource"] as? String, ViftyCtlPolicySource.daemonStatus.rawValue)
        XCTAssertNil(json["agentControlStatusError"] as? String)
        let policy = try XCTUnwrap(json["policy"] as? [String: Any])
        XCTAssertEqual(policy["enabled"] as? Bool, true)
        XCTAssertEqual(policy["maxDurationSeconds"] as? Int, 1_800)
    }

    func testCapabilitiesJSONReturnsStaticContractWhenDaemonStatusUnavailable() async throws {
        let runner = ViftyCtlRunner(
            client: FakeAgentControlClient(
                statusError: ViftyError.helperRejected("Daemon request timed out.")
            ),
            processRunner: FakeProcessRunner()
        )

        let result = try await runner.run(.capabilities(json: true))

        XCTAssertEqual(result.exitCode, 69)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["daemonStatusAvailable"] as? Bool, false)
        XCTAssertEqual(json["policyStatusAvailable"] as? Bool, false)
        XCTAssertEqual(json["policySource"] as? String, ViftyCtlPolicySource.fallbackUnavailable.rawValue)
        XCTAssertTrue((json["agentControlStatusError"] as? String)?.contains("Daemon request timed out") == true)
        XCTAssertTrue((json["commands"] as? [String])?.contains("diagnose") == true)
        XCTAssertTrue((json["workloads"] as? [String])?.contains("test") == true)
        let schemas = try XCTUnwrap(json["schemas"] as? [String: Any])
        XCTAssertEqual(schemas["audit"] as? String, "docs/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(schemas["diagnose"] as? String, "docs/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(schemas["commandError"] as? String, "docs/schemas/viftyctl-command-error.schema.json")
        let schemaResources = try XCTUnwrap(json["schemaResources"] as? [String: Any])
        XCTAssertEqual(schemaResources["audit"] as? String, "Contents/Resources/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(schemaResources["diagnose"] as? String, "Contents/Resources/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(schemaResources["commandError"] as? String, "Contents/Resources/schemas/viftyctl-command-error.schema.json")
        let wrapperResources = try XCTUnwrap(json["wrapperResources"] as? [String: Any])
        XCTAssertEqual(wrapperResources["bundleDirectory"] as? String, "Contents/Resources/viftyctl-wrappers")
        XCTAssertEqual(wrapperResources["guardedRunScript"] as? String, "guarded-run.sh")
        let schemaIDs = try XCTUnwrap(json["schemaIDs"] as? [String: Any])
        XCTAssertEqual(schemaIDs["audit"] as? String, "https://vifty.local/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(schemaIDs["diagnose"] as? String, "https://vifty.local/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(schemaIDs["commandError"] as? String, "https://vifty.local/schemas/viftyctl-command-error.schema.json")
        let exitCodes = try XCTUnwrap(json["exitCodes"] as? [String: Any])
        XCTAssertEqual(exitCodes["unavailable"] as? Int, 69)
        let runLifecycle = try XCTUnwrap(json["runLifecycle"] as? [String: Any])
        XCTAssertEqual(runLifecycle["childCommandPreflightBeforeCooling"] as? Bool, true)
        XCTAssertEqual(runLifecycle["autoRestoreAfterChildExit"] as? Bool, true)
        XCTAssertEqual(runLifecycle["cleanupStateReportedOnLaunchFailure"] as? Bool, true)
        XCTAssertEqual(runLifecycle["resolvedChildExecutableReported"] as? Bool, true)
        XCTAssertEqual(runLifecycle["signalScope"] as? String, ViftyCtlSignalScope.processGroup.rawValue)
        XCTAssertEqual(runLifecycle["descendantCleanupBeforeAutoRestore"] as? Bool, true)
        XCTAssertEqual(runLifecycle["backgroundProcessesAllowed"] as? Bool, false)
        let directControlLifecycle = try XCTUnwrap(json["directControlLifecycle"] as? [String: Any])
        XCTAssertEqual(directControlLifecycle["prepareUsesIdempotencyKey"] as? Bool, true)
        XCTAssertEqual(directControlLifecycle["restoreAutoAcceptsIdempotencyKey"] as? Bool, false)
        XCTAssertEqual(directControlLifecycle["restoreAutoScopedByIdempotencyKey"] as? Bool, false)
        XCTAssertEqual(directControlLifecycle["preferRunForSingleChildWorkloads"] as? Bool, true)
        let metadataLimits = try XCTUnwrap(json["metadataLimits"] as? [String: Any])
        XCTAssertEqual(metadataLimits["maximumReasonLength"] as? Int, AgentControlRequest.maximumReasonLength)
        XCTAssertEqual(metadataLimits["maximumIdempotencyKeyLength"] as? Int, AgentControlRequest.maximumIdempotencyKeyLength)
        XCTAssertEqual(json["supportsForceRetry"] as? Bool, true)
        let policy = try XCTUnwrap(json["policy"] as? [String: Any])
        XCTAssertEqual(policy["enabled"] as? Bool, false)
        XCTAssertEqual(policy["maxDurationSeconds"] as? Int, 1_800)
    }

    func testCapabilitiesHumanReadableReturnsCommandsAndUnavailableExitWhenDaemonStatusUnavailable() async throws {
        let runner = ViftyCtlRunner(
            client: FakeAgentControlClient(
                statusError: ViftyError.helperRejected("Daemon request timed out.")
            ),
            processRunner: FakeProcessRunner()
        )

        let result = try await runner.run(.capabilities(json: false))

        XCTAssertEqual(result.exitCode, 69)
        XCTAssertTrue(result.stdout.contains("capabilities"))
        XCTAssertTrue(result.stdout.contains("run"))
        XCTAssertTrue(result.stderr.contains("daemon status unavailable"))
        XCTAssertTrue(result.stderr.contains("Daemon request timed out"))
    }

    func testDiagnoseJSONReturnsReadinessReportAndDoesNotMutateAgentControl() async throws {
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(),
            status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true, prepareCooldownSeconds: 12).snapshot
            )
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .nominal },
            manualControlActiveReader: { false },
            appPreferencesReader: {
                ViftyAppPreferencesDiagnostic(startupMode: .auto, startupModeSource: .persisted)
            },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.diagnose(json: true))

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["state"] as? String, "ready")
        XCTAssertEqual(json["recommendedAgentAction"] as? String, ViftyCtlRecommendedAgentAction.requestCooling.rawValue)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlReadinessRecoveryAction.none.rawValue)
        XCTAssertEqual(json["recoverySteps"] as? [String], [])
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(json["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(json["manualControlActive"] as? Bool, false)
        XCTAssertEqual(json["failedCheckIDs"] as? [String], [])
        XCTAssertEqual(json["coolingBlockerIDs"] as? [String], [])
        let appPreferences = try XCTUnwrap(json["appPreferences"] as? [String: Any])
        XCTAssertEqual(appPreferences["startupMode"] as? String, "Auto")
        XCTAssertEqual(appPreferences["startupModeSource"] as? String, "persisted")
        XCTAssertTrue(appPreferences["readError"] is NSNull)
        XCTAssertEqual(json["modelIdentifier"] as? String, "MacBookPro18,3")
        XCTAssertEqual(json["thermalPressure"] as? String, "nominal")
        XCTAssertEqual(json["fanCount"] as? Int, 2)
        XCTAssertEqual(json["controllableFanCount"] as? Int, 2)
        XCTAssertEqual(json["temperatureSensorCount"] as? Int, 1)
        let fans = try XCTUnwrap(json["fans"] as? [[String: Any]])
        XCTAssertEqual(fans.compactMap { $0["hardwareModeKey"] as? String }, ["F0Md", "F1md"])
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "daemonControlPathReady"
                && (check["passed"] as? Bool) == true
        })
        XCTAssertTrue(checks.contains { $0["id"] as? String == "supportedHardware" && $0["passed"] as? Bool == true })
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "manualControlClear"
                && (check["passed"] as? Bool) == true
                && (check["severity"] as? String) == "warning"
        })
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "replacementMaintenanceAttestation"
                && (check["passed"] as? Bool) == true
                && (check["severity"] as? String) == "error"
        })
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testDiagnoseReplacementMaintenanceAttestationDoesNotAssumeTwoFans() async throws {
        var snapshot = Self.readySnapshot()
        snapshot.fans = Array(snapshot.fans.prefix(1))
        let client = FakeAgentControlClient(snapshot: snapshot)
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .nominal },
            manualControlActiveReader: { false }
        )

        let result = try await runner.run(.diagnose(json: true))
        let json = try jsonObject(in: result.stdout)
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(json["fanCount"] as? Int, 1)
        XCTAssertTrue(checks.contains {
            $0["id"] as? String == "replacementMaintenanceAttestation"
                && $0["passed"] as? Bool == true
        })
    }

    func testDiagnoseOmitsReplacementAttestationForSelfConsistentUntrustedInventory() async throws {
        var snapshot = Self.readySnapshot()
        snapshot.fans = Array(snapshot.fans.prefix(1))
        snapshot.fans[0].controlEligibility = .legacyUnspecified
        let client = FakeAgentControlClient(snapshot: snapshot)
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .nominal },
            manualControlActiveReader: { false }
        )

        let result = try await runner.run(.diagnose(json: true))
        let json = try jsonObject(in: result.stdout)
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertEqual(json["fanCount"] as? Int, 1)
        XCTAssertFalse(checks.contains {
            $0["id"] as? String == "replacementMaintenanceAttestation"
        })
    }

    func testDiagnoseJSONBlocksCoolingWhenInstalledDaemonDiffersFromExpectedBuild() async throws {
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(),
            status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            )
        )
        let runtime = ViftyCtlDaemonRuntimeDiagnostic(
            installedDaemonPath: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
            installedDaemonPresent: true,
            installedDaemonSHA256: String(repeating: "a", count: 64),
            expectedDaemonPath: "/Applications/Vifty.app/Contents/MacOS/ViftyDaemon",
            expectedDaemonPresent: true,
            expectedDaemonSHA256: String(repeating: "b", count: 64),
            matchesExpectedDaemon: false,
            matchRequired: true
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .nominal },
            manualControlActiveReader: { false },
            daemonRuntimeReader: { runtime },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.diagnose(json: true))

        XCTAssertEqual(result.exitCode, 75)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["state"] as? String, "blocked")
        XCTAssertEqual(json["recommendedAgentAction"] as? String, ViftyCtlRecommendedAgentAction.doNotRequestCooling.rawValue)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlReadinessRecoveryAction.repairHelper.rawValue)
        XCTAssertEqual(json["recoverySteps"] as? [String], ViftyAgentRule.repairHelperRecoveryActions)
        let operatorRecoveryCommands = try XCTUnwrap(
            json["operatorRecoveryCommands"] as? [[String: Any]]
        )
        XCTAssertEqual(operatorRecoveryCommands.count, 1)
        let repairCommand = try XCTUnwrap(operatorRecoveryCommands.first)
        XCTAssertEqual(repairCommand["id"] as? String, "repair-helper-current-app")
        XCTAssertEqual(repairCommand["title"] as? String, "Repair helper from this Vifty app bundle")
        XCTAssertEqual(repairCommand["command"] as? String, "REPAIR_HELPER_APP='/Applications/Vifty.app' make repair-helper")
        XCTAssertEqual(repairCommand["workingDirectoryHint"] as? String, "Run from the Vifty source checkout.")
        XCTAssertEqual(repairCommand["requiresUserApproval"] as? Bool, true)
        XCTAssertEqual(repairCommand["safeForAgentsToRunAutomatically"] as? Bool, false)
        XCTAssertEqual(
            repairCommand["notes"] as? [String],
            [
                "Shows the same explicit administrator-approved LaunchDaemon repair path as the app UI.",
                "Does not request cooling or write fan state directly.",
                "After repair, rerun viftyctl diagnose --json and require safe readiness before requesting cooling."
            ]
        )
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(json["failedCheckIDs"] as? [String], ["daemonRuntimeMatchesExpected"])
        XCTAssertEqual(json["coolingBlockerIDs"] as? [String], ["daemonRuntimeMatchesExpected"])
        let daemonRuntime = try XCTUnwrap(json["daemonRuntime"] as? [String: Any])
        XCTAssertEqual(daemonRuntime["installedDaemonPath"] as? String, runtime.installedDaemonPath)
        XCTAssertEqual(daemonRuntime["installedDaemonPresent"] as? Bool, true)
        XCTAssertEqual(daemonRuntime["installedDaemonSHA256"] as? String, runtime.installedDaemonSHA256)
        XCTAssertEqual(daemonRuntime["expectedDaemonPath"] as? String, runtime.expectedDaemonPath)
        XCTAssertEqual(daemonRuntime["expectedDaemonPresent"] as? Bool, true)
        XCTAssertEqual(daemonRuntime["expectedDaemonSHA256"] as? String, runtime.expectedDaemonSHA256)
        XCTAssertEqual(daemonRuntime["matchesExpectedDaemon"] as? Bool, false)
        XCTAssertEqual(daemonRuntime["matchRequired"] as? Bool, true)
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "daemonRuntimeMatchesExpected"
                && (check["passed"] as? Bool) == false
                && (check["severity"] as? String) == "error"
                && ((check["message"] as? String)?.contains("Repair/Reinstall Helper") == true)
        })
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testDiagnoseJSONIncludesAllRecoveryStepsWhenHelperAndManualControlBothBlockCooling() async throws {
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(),
            status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            )
        )
        let runtime = ViftyCtlDaemonRuntimeDiagnostic(
            installedDaemonPath: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
            installedDaemonPresent: true,
            installedDaemonSHA256: String(repeating: "a", count: 64),
            expectedDaemonPath: "/Applications/Vifty.app/Contents/MacOS/ViftyDaemon",
            expectedDaemonPresent: true,
            expectedDaemonSHA256: String(repeating: "b", count: 64),
            matchesExpectedDaemon: false,
            matchRequired: true
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .nominal },
            manualControlActiveReader: { true },
            appPreferencesReader: {
                ViftyAppPreferencesDiagnostic(startupMode: .fixed, startupModeSource: .persisted)
            },
            daemonRuntimeReader: { runtime },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.diagnose(json: true))

        XCTAssertEqual(result.exitCode, 75)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["state"] as? String, "blocked")
        XCTAssertEqual(json["recommendedAgentAction"] as? String, ViftyCtlRecommendedAgentAction.doNotRequestCooling.rawValue)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlReadinessRecoveryAction.repairHelper.rawValue)
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(json["manualControlActive"] as? Bool, true)
        XCTAssertEqual(json["failedCheckIDs"] as? [String], ["daemonRuntimeMatchesExpected", "manualControlClear"])
        XCTAssertEqual(json["coolingBlockerIDs"] as? [String], ["daemonRuntimeMatchesExpected", "manualControlClear"])
        XCTAssertEqual(
            json["recoverySteps"] as? [String],
            ViftyAgentRule.repairHelperRecoveryActions + Self.restoreAutoRecoverySteps
        )
        let operatorRecoveryCommands = try XCTUnwrap(json["operatorRecoveryCommands"] as? [[String: Any]])
        XCTAssertEqual(operatorRecoveryCommands.count, 2)
        XCTAssertEqual(operatorRecoveryCommands[0]["id"] as? String, "repair-helper-current-app")
        XCTAssertEqual(
            operatorRecoveryCommands[0]["command"] as? String,
            "REPAIR_HELPER_APP='/Applications/Vifty.app' make repair-helper"
        )
        XCTAssertEqual(operatorRecoveryCommands[1]["id"] as? String, "restore-auto-current-app")
        XCTAssertEqual(
            operatorRecoveryCommands[1]["command"] as? String,
            "'/Applications/Vifty.app/Contents/MacOS/viftyctl' restore-auto --json --reason 'operator recovery before agent cooling'"
        )
        XCTAssertEqual(operatorRecoveryCommands[1]["requiresUserApproval"] as? Bool, true)
        XCTAssertEqual(operatorRecoveryCommands[1]["safeForAgentsToRunAutomatically"] as? Bool, false)
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "manualControlClear"
                && (check["passed"] as? Bool) == false
                && (check["severity"] as? String) == "warning"
                && ((check["message"] as? String)?.contains("default startup mode is Fixed") == true)
        })
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testDiagnoseJSONReturnsBlockedReportWhenDaemonSnapshotFails() async throws {
        let client = FakeAgentControlClient(
            status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            ),
            snapshotError: ViftyError.helperRejected("Daemon request timed out.")
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .nominal },
            manualControlActiveReader: { false },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.diagnose(json: true))

        XCTAssertEqual(result.exitCode, 75)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["state"] as? String, "blocked")
        XCTAssertEqual(json["recommendedAgentAction"] as? String, ViftyCtlRecommendedAgentAction.doNotRequestCooling.rawValue)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlReadinessRecoveryAction.repairHelper.rawValue)
        XCTAssertEqual(json["recoverySteps"] as? [String], ViftyAgentRule.repairHelperRecoveryActions)
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(json["daemonControlPathReady"] as? Bool, false)
        XCTAssertEqual(json["modelIdentifier"] as? String, "unknown")
        XCTAssertEqual(json["failedCheckIDs"] as? [String], [
            "daemonSnapshotAvailable",
            "daemonControlPathReady",
            "supportedHardware",
            "temperatureSensorsPresent",
            "controllableFansPresent"
        ])
        XCTAssertEqual(json["coolingBlockerIDs"] as? [String], [
            "daemonSnapshotAvailable",
            "daemonControlPathReady",
            "supportedHardware",
            "temperatureSensorsPresent",
            "controllableFansPresent"
        ])
        XCTAssertTrue((json["daemonSnapshotError"] as? String)?.contains("Daemon request timed out") == true)
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "daemonSnapshotAvailable"
                && (check["passed"] as? Bool) == false
                && (check["severity"] as? String) == "error"
        })
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "agentControlStatusAvailable"
                && (check["passed"] as? Bool) == true
        })
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "daemonControlPathReady"
                && (check["passed"] as? Bool) == false
                && (check["severity"] as? String) == "error"
        })
    }

    func testDiagnoseJSONReturnsBlockedReportWhenAgentControlStatusFails() async throws {
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(),
            statusError: ViftyError.helperRejected("Could not create daemon proxy.")
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .nominal },
            manualControlActiveReader: { false },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.diagnose(json: true))

        XCTAssertEqual(result.exitCode, 75)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["state"] as? String, "blocked")
        XCTAssertEqual(json["recommendedAgentAction"] as? String, ViftyCtlRecommendedAgentAction.doNotRequestCooling.rawValue)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlReadinessRecoveryAction.repairHelper.rawValue)
        XCTAssertEqual(json["recoverySteps"] as? [String], ViftyAgentRule.repairHelperRecoveryActions)
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(json["daemonControlPathReady"] as? Bool, false)
        XCTAssertEqual(json["modelIdentifier"] as? String, "MacBookPro18,3")
        XCTAssertEqual(json["failedCheckIDs"] as? [String], [
            "agentControlStatusAvailable",
            "daemonControlPathReady",
            "agentControlEnabled"
        ])
        XCTAssertEqual(json["coolingBlockerIDs"] as? [String], [
            "agentControlStatusAvailable",
            "daemonControlPathReady",
            "agentControlEnabled"
        ])
        XCTAssertTrue((json["agentControlStatusError"] as? String)?.contains("Could not create daemon proxy") == true)
        let agentControl = try XCTUnwrap(json["agentControl"] as? [String: Any])
        XCTAssertEqual(agentControl["enabled"] as? Bool, false)
        XCTAssertEqual(agentControl["lastErrorCode"] as? String, AgentControlErrorCode.helperUnreachable.rawValue)
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "agentControlStatusAvailable"
                && (check["passed"] as? Bool) == false
                && (check["severity"] as? String) == "error"
        })
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "daemonSnapshotAvailable"
                && (check["passed"] as? Bool) == true
        })
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "daemonControlPathReady"
                && (check["passed"] as? Bool) == false
                && (check["severity"] as? String) == "error"
        })
    }

    func testDiagnoseJSONReturnsDegradedUnsafeReportWhenActiveLeaseExists() async throws {
        let activeLease = AgentCoolingLease(
            id: "lease-example-test",
            request: AgentControlRequest(
                workload: .test,
                durationSeconds: 1_200,
                maxRPMPercent: 70,
                reason: "swift test",
                idempotencyKey: "example-test-001"
            ),
            createdAt: Date(timeIntervalSince1970: 700_000_000),
            expiresAt: Date(timeIntervalSince1970: 700_001_200),
            targetRPMByFanID: [0: 3_600, 1: 3_700]
        )
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(),
            status: AgentControlStatus(
                enabled: true,
                activeLease: activeLease,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            )
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .nominal },
            manualControlActiveReader: { false },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.diagnose(json: true))

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["state"] as? String, "degraded")
        XCTAssertEqual(
            json["recommendedAgentAction"] as? String,
            ViftyCtlRecommendedAgentAction.restoreAutoBeforeRequestingCooling.rawValue
        )
        XCTAssertEqual(
            json["recommendedRecoveryAction"] as? String,
            ViftyCtlReadinessRecoveryAction.restoreAutoBeforeRetry.rawValue
        )
        XCTAssertEqual(json["recoverySteps"] as? [String], Self.restoreAutoRecoverySteps)
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(json["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(json["failedCheckIDs"] as? [String], ["activeLeaseClear"])
        XCTAssertEqual(json["coolingBlockerIDs"] as? [String], ["activeLeaseClear"])
        let agentControl = try XCTUnwrap(json["agentControl"] as? [String: Any])
        let lease = try XCTUnwrap(agentControl["activeLease"] as? [String: Any])
        XCTAssertEqual(lease["id"] as? String, "lease-example-test")
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "activeLeaseClear"
                && (check["passed"] as? Bool) == false
                && (check["severity"] as? String) == "warning"
        })
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testDiagnoseJSONReturnsDegradedUnsafeReportWhenManualControlMarkerIsActive() async throws {
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(),
            status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            )
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .nominal },
            manualControlActiveReader: { true },
            appPreferencesReader: {
                ViftyAppPreferencesDiagnostic(startupMode: .curve, startupModeSource: .persisted)
            },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.diagnose(json: true))

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["state"] as? String, "degraded")
        XCTAssertEqual(
            json["recommendedAgentAction"] as? String,
            ViftyCtlRecommendedAgentAction.restoreAutoBeforeRequestingCooling.rawValue
        )
        XCTAssertEqual(
            json["recommendedRecoveryAction"] as? String,
            ViftyCtlReadinessRecoveryAction.restoreAutoBeforeRetry.rawValue
        )
        XCTAssertEqual(json["recoverySteps"] as? [String], Self.restoreAutoRecoverySteps)
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(json["daemonControlPathReady"] as? Bool, true)
        XCTAssertEqual(json["manualControlActive"] as? Bool, true)
        XCTAssertEqual(json["failedCheckIDs"] as? [String], ["manualControlClear"])
        XCTAssertEqual(json["coolingBlockerIDs"] as? [String], ["manualControlClear"])
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains { check in
            (check["id"] as? String) == "manualControlClear"
                && (check["passed"] as? Bool) == false
                && (check["severity"] as? String) == "warning"
                && (check["message"] as? String)?.contains("restore Auto") == true
                && (check["message"] as? String)?.contains("re-run diagnose") == true
                && (check["message"] as? String)?.contains("default startup mode is Curve") == true
                && (check["message"] as? String)?.contains("switch Vifty/default mode to Auto") == true
        })
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testDiagnoseRequireSafeExitsBlockedWhenManualControlBlocksCooling() async throws {
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(),
            status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            )
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .nominal },
            manualControlActiveReader: { true },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.diagnose(json: true, requireSafe: true))

        XCTAssertEqual(result.exitCode, 75)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["state"] as? String, "degraded")
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(json["manualControlActive"] as? Bool, true)
        XCTAssertEqual(json["coolingBlockerIDs"] as? [String], ["manualControlClear"])
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testDiagnoseRequireSafeAllowsWarningOnlyCautionReadiness() async throws {
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(),
            status: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            )
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .serious },
            manualControlActiveReader: { false },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.diagnose(json: true, requireSafe: true))

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["state"] as? String, "degraded")
        XCTAssertEqual(
            json["recommendedAgentAction"] as? String,
            ViftyCtlRecommendedAgentAction.requestCoolingWithCaution.rawValue
        )
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(json["manualControlActive"] as? Bool, false)
        XCTAssertEqual(json["coolingBlockerIDs"] as? [String], [])
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testDiagnoseHumanReadableShowsWarnings() async throws {
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(fanMode: .system),
            status: AgentControlStatus(
                enabled: true,
                activeLease: AgentCoolingLease(
                    id: "lease-1",
                    request: AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "Test", idempotencyKey: "key"),
                    createdAt: Date(timeIntervalSince1970: 1_000),
                    expiresAt: Date(timeIntervalSince1970: 1_600),
                    targetRPMByFanID: [0: 3200]
                ),
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            )
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            thermalReader: { .serious },
            manualControlActiveReader: { true }
        )

        let result = try await runner.run(.diagnose(json: false))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("state=degraded"))
        XCTAssertTrue(result.stdout.contains("agentAction=restoreAutoBeforeRequestingCooling safeToRequestCooling=false"))
        XCTAssertTrue(result.stdout.contains("recoveryAction=restoreAutoBeforeRetry"))
        XCTAssertTrue(result.stdout.contains("[warn] activeLeaseClear"))
        XCTAssertTrue(result.stdout.contains("[warn] manualControlClear"))
        XCTAssertTrue(result.stdout.contains("[warn] fanModeTelemetry"))
        XCTAssertTrue(result.stdout.contains("[warn] thermalPressureSafe"))
    }

    func testAuditJSONReturnsRecentEventsAndDoesNotMutateAgentControl() async throws {
        let events = [
            AgentControlAuditEvent(
                timestamp: Date(timeIntervalSince1970: 1_000),
                action: "prepare",
                leaseID: "lease-1",
                message: "Swift build"
            )
        ]
        let client = FakeAgentControlClient(auditEvents: events)
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.audit(limit: 5, json: true))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["readOnly"] as? Bool, true)
        XCTAssertEqual(json["coolingCommandsRun"] as? Bool, false)
        XCTAssertEqual(json["limit"] as? Int, 5)
        XCTAssertEqual(json["eventCount"] as? Int, 1)
        let decodedEvents = try XCTUnwrap(json["events"] as? [[String: Any]])
        XCTAssertEqual(decodedEvents.first?["action"] as? String, "prepare")
        XCTAssertEqual(decodedEvents.first?["leaseID"] as? String, "lease-1")
        XCTAssertEqual(decodedEvents.first?["message"] as? String, "Swift build")
        let auditLimits = await client.auditLimits
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(auditLimits, [5])
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
    }

    func testAuditHumanReadableShowsEvents() async throws {
        let events = [
            AgentControlAuditEvent(
                timestamp: Date(timeIntervalSince1970: 1_000),
                action: "restore-auto",
                leaseID: nil,
                message: "work complete"
            )
        ]
        let client = FakeAgentControlClient(auditEvents: events)
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            manualControlActiveReader: { false }
        )

        let result = try await runner.run(.audit(limit: 20, json: false))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("restore-auto"))
        XCTAssertTrue(result.stdout.contains("work complete"))
        XCTAssertFalse(result.stdout.contains("lease="))
    }

    func testAuditHumanReadableReportsEmptyAuditLog() async throws {
        let client = FakeAgentControlClient(auditEvents: [])
        let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner())

        let result = try await runner.run(.audit(limit: 20, json: false))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "No agent-control audit events.\n")
    }

    func testAuditJSONReturnsStructuredErrorWhenDaemonUnavailable() async throws {
        let client = FakeAgentControlClient(
            auditError: ViftyError.helperRejected("Daemon request timed out.")
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.audit(limit: 20, json: true))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "audit")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.helperUnreachable.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.repairHelper.rawValue)
        XCTAssertTrue((json["message"] as? String)?.contains("Daemon request timed out") == true)
    }

    func testReadinessReportRecommendsCautionForWarningOnlyDegradedState() {
        let report = ViftyCtlReadinessReport.make(
            snapshot: Self.readySnapshot(),
            agentControl: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            ),
            thermalPressure: .serious,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(report.state, .degraded)
        XCTAssertEqual(report.recommendedAgentAction, .requestCoolingWithCaution)
        XCTAssertEqual(report.recommendedRecoveryAction, .none)
        XCTAssertEqual(report.recoverySteps, [])
        XCTAssertEqual(report.safeToRequestCooling, true)
        XCTAssertTrue(report.daemonControlPathReady)
        XCTAssertEqual(report.failedCheckIDs, ["thermalPressureSafe"])
        XCTAssertEqual(report.coolingBlockerIDs, [])
    }

    func testReadinessReportRecommendsRestoreAutoBeforeNewCoolingWhenLeaseIsActive() {
        let activeLease = AgentCoolingLease(
            id: "lease-1",
            request: AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "Test", idempotencyKey: "key"),
            createdAt: Date(timeIntervalSince1970: 1_000),
            expiresAt: Date(timeIntervalSince1970: 1_600),
            targetRPMByFanID: [0: 3200]
        )
        let report = ViftyCtlReadinessReport.make(
            snapshot: Self.readySnapshot(),
            agentControl: AgentControlStatus(
                enabled: true,
                activeLease: activeLease,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            ),
            thermalPressure: .nominal,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(report.state, .degraded)
        XCTAssertEqual(report.recommendedAgentAction, .restoreAutoBeforeRequestingCooling)
        XCTAssertEqual(report.recommendedRecoveryAction, .restoreAutoBeforeRetry)
        XCTAssertEqual(report.recoverySteps, Self.restoreAutoRecoverySteps)
        XCTAssertEqual(report.safeToRequestCooling, false)
        XCTAssertTrue(report.daemonControlPathReady)
        XCTAssertEqual(report.failedCheckIDs, ["activeLeaseClear"])
        XCTAssertEqual(report.coolingBlockerIDs, ["activeLeaseClear"])
    }

    func testReadinessReportRecommendsRestoreAutoBeforeNewCoolingWhenManualControlMarkerIsActive() throws {
        let report = ViftyCtlReadinessReport.make(
            snapshot: Self.readySnapshot(),
            agentControl: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            ),
            thermalPressure: .nominal,
            generatedAt: Date(timeIntervalSince1970: 1_000),
            manualControlActive: true,
            daemonRuntime: ViftyCtlDaemonRuntimeDiagnostic(
                installedDaemonPath: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
                installedDaemonPresent: true,
                installedDaemonSHA256: String(repeating: "a", count: 64),
                expectedDaemonPath: "/Applications/Vifty.app/Contents/MacOS/ViftyDaemon",
                expectedDaemonPresent: true,
                expectedDaemonSHA256: String(repeating: "a", count: 64),
                matchesExpectedDaemon: true,
                matchRequired: true
            )
        )

        XCTAssertEqual(report.state, .degraded)
        XCTAssertEqual(report.recommendedAgentAction, .restoreAutoBeforeRequestingCooling)
        XCTAssertEqual(report.recommendedRecoveryAction, .restoreAutoBeforeRetry)
        XCTAssertEqual(report.recoverySteps, Self.restoreAutoRecoverySteps)
        XCTAssertEqual(report.safeToRequestCooling, false)
        XCTAssertTrue(report.daemonControlPathReady)
        XCTAssertTrue(report.manualControlActive)
        XCTAssertEqual(report.failedCheckIDs, ["manualControlClear"])
        XCTAssertEqual(report.coolingBlockerIDs, ["manualControlClear"])
        XCTAssertEqual(report.operatorRecoveryCommands?.map(\.id), ["restore-auto-current-app"])
        let command = try XCTUnwrap(report.operatorRecoveryCommands?.first)
        XCTAssertEqual(
            command.command,
            "'/Applications/Vifty.app/Contents/MacOS/viftyctl' restore-auto --json --reason 'operator recovery before agent cooling'"
        )
        XCTAssertTrue(command.requiresUserApproval)
        XCTAssertFalse(command.safeForAgentsToRunAutomatically)
        XCTAssertTrue(command.notes.contains("Requires an explicit human decision because restore-auto writes fan control state through the helper."))
        XCTAssertTrue(report.checks.contains { $0.id == "manualControlClear" && !$0.passed && $0.severity == .warning })
    }

    func testReadinessReportBlocksHelperRuntimeMismatchBeforeCooling() {
        let report = ViftyCtlReadinessReport.make(
            snapshot: Self.readySnapshot(),
            agentControl: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            ),
            thermalPressure: .nominal,
            generatedAt: Date(timeIntervalSince1970: 1_000),
            daemonRuntime: ViftyCtlDaemonRuntimeDiagnostic(
                installedDaemonPath: "/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon",
                installedDaemonPresent: true,
                installedDaemonSHA256: String(repeating: "a", count: 64),
                expectedDaemonPath: "/Applications/Vifty.app/Contents/MacOS/ViftyDaemon",
                expectedDaemonPresent: true,
                expectedDaemonSHA256: String(repeating: "b", count: 64),
                matchesExpectedDaemon: false,
                matchRequired: true
            )
        )

        XCTAssertEqual(report.state, .blocked)
        XCTAssertEqual(report.recommendedAgentAction, .doNotRequestCooling)
        XCTAssertEqual(report.recommendedRecoveryAction, .repairHelper)
        XCTAssertEqual(report.recoverySteps, ViftyAgentRule.repairHelperRecoveryActions)
        XCTAssertEqual(report.safeToRequestCooling, false)
        XCTAssertEqual(report.failedCheckIDs, ["daemonRuntimeMatchesExpected"])
        XCTAssertEqual(report.coolingBlockerIDs, ["daemonRuntimeMatchesExpected"])
        XCTAssertEqual(report.daemonRuntime.matchesExpectedDaemon, false)
        XCTAssertTrue(report.checks.contains {
            $0.id == "daemonRuntimeMatchesExpected" && !$0.passed && $0.severity == .error
        })
    }

    func testReadinessReportRecommendsPolicyInspectionWhenAgentCoolingIsDisabled() {
        let report = ViftyCtlReadinessReport.make(
            snapshot: Self.readySnapshot(),
            agentControl: AgentControlStatus(
                enabled: false,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: false).snapshot
            ),
            thermalPressure: .nominal,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(report.state, .blocked)
        XCTAssertEqual(report.recommendedAgentAction, .doNotRequestCooling)
        XCTAssertEqual(report.recommendedRecoveryAction, .inspectPolicy)
        XCTAssertEqual(report.safeToRequestCooling, false)
        XCTAssertTrue(report.daemonControlPathReady)
        XCTAssertEqual(report.failedCheckIDs, ["agentControlEnabled"])
        XCTAssertEqual(report.coolingBlockerIDs, ["agentControlEnabled"])
    }

    func testReadinessReportBlocksUnsupportedHardware() {
        let report = ViftyCtlReadinessReport.make(
            snapshot: HardwareSnapshot(
                fans: [],
                temperatureSensors: [],
                modelIdentifier: "Mac14,15",
                isAppleSilicon: true,
                isMacBookPro: false,
                capturedAt: Date(timeIntervalSince1970: 1_000)
            ),
            agentControl: AgentControlStatus(enabled: false, activeLease: nil, lastDecision: nil, lastErrorCode: nil),
            thermalPressure: .critical,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(report.state, .blocked)
        XCTAssertEqual(report.recommendedAgentAction, .doNotRequestCooling)
        XCTAssertEqual(report.recommendedRecoveryAction, .backOffWorkload)
        XCTAssertEqual(report.safeToRequestCooling, false)
        XCTAssertTrue(report.daemonControlPathReady)
        XCTAssertEqual(report.failedCheckIDs, [
            "supportedHardware",
            "agentControlEnabled",
            "temperatureSensorsPresent",
            "controllableFansPresent",
            "thermalPressureSafe"
        ])
        XCTAssertEqual(report.coolingBlockerIDs, report.failedCheckIDs)
        XCTAssertTrue(report.checks.contains { $0.id == "supportedHardware" && !$0.passed && $0.severity == .error })
        XCTAssertTrue(report.checks.contains { $0.id == "temperatureSensorsPresent" && !$0.passed && $0.severity == .error })
        XCTAssertTrue(report.checks.contains { $0.id == "thermalPressureSafe" && !$0.passed && $0.severity == .error })
    }

    func testReadinessReportBlocksInvalidAndDuplicateControllableFanIDs() throws {
        let report = ViftyCtlReadinessReport.make(
            snapshot: HardwareSnapshot(
                fans: [
                    Fan(
                        id: 0,
                        name: "Left Fan",
                        currentRPM: 2_100,
                        minimumRPM: 1_400,
                        maximumRPM: 6_000,
                        controllable: true,
                        hardwareMode: .automatic,
                        targetRPM: 2_000
                    ),
                    Fan(
                        id: 0,
                        name: "Duplicate Fan",
                        currentRPM: 2_200,
                        minimumRPM: 1_400,
                        maximumRPM: 6_000,
                        controllable: true,
                        hardwareMode: .automatic,
                        targetRPM: 2_000
                    ),
                    Fan(
                        id: 10,
                        name: "Invalid Fan",
                        currentRPM: 2_300,
                        minimumRPM: 1_400,
                        maximumRPM: 6_000,
                        controllable: true,
                        hardwareMode: .automatic,
                        targetRPM: 2_000
                    )
                ],
                temperatureSensors: [
                    TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 48.2, source: .smc)
                ],
                modelIdentifier: "MacBookPro18,3",
                isAppleSilicon: true,
                isMacBookPro: true,
                capturedAt: Date(timeIntervalSince1970: 1_000)
            ),
            agentControl: AgentControlStatus(
                enabled: true,
                activeLease: nil,
                lastDecision: nil,
                lastErrorCode: nil,
                policy: AgentControlPolicy(enabled: true).snapshot
            ),
            thermalPressure: .nominal,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(report.state, .blocked)
        XCTAssertEqual(report.recommendedRecoveryAction, .collectHardwareEvidence)
        let validIDsCheck = try XCTUnwrap(report.checks.first { $0.id == "fanIDsValid" })
        XCTAssertFalse(validIDsCheck.passed)
        XCTAssertEqual(validIDsCheck.severity, .error)
        XCTAssertTrue(validIDsCheck.message.contains("10"))
        let uniqueIDsCheck = try XCTUnwrap(report.checks.first { $0.id == "fanIDsUnique" })
        XCTAssertFalse(uniqueIDsCheck.passed)
        XCTAssertEqual(uniqueIDsCheck.severity, .error)
        XCTAssertTrue(uniqueIDsCheck.message.contains("0"))
        XCTAssertTrue(report.checks.contains { $0.id == "fanRangesValid" && $0.passed })
    }

    func testPrepareCallsAgentControlClient() async throws {
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)])
        let processRunner = FakeProcessRunner(exitCode: 0)
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        let result = try await runner.run(.prepare(request, json: true, force: false))

        XCTAssertEqual(result.exitCode, 0)
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, [])
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testPrepareReturnsNonzeroWithJSONWhenDenied() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let denied = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .denied(.unsupportedHardware, message: "Agent cooling is supported only on Apple Silicon MacBook Pro hardware."),
            lastErrorCode: .unsupportedHardware,
            policy: AgentControlPolicy(enabled: true).snapshot
        )
        let client = FakeAgentControlClient(prepareResponses: [denied])
        let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner())

        let result = try await runner.run(.prepare(request, json: true, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(json["lastErrorCode"] as? String, AgentControlErrorCode.unsupportedHardware.rawValue)
        let decision = try XCTUnwrap(json["lastDecision"] as? [String: Any])
        XCTAssertEqual(decision["message"] as? String, "Agent cooling is supported only on Apple Silicon MacBook Pro hardware.")
        let prepareRequests = await client.prepareRequests
        XCTAssertEqual(prepareRequests, [request])
    }

    func testPrepareJSONReturnsStructuredErrorWhenDaemonUnavailable() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let client = FakeAgentControlClient(
            prepareError: ViftyError.helperRejected("Could not create daemon proxy.")
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.prepare(request, json: true, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "prepare")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.helperUnreachable.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.repairHelper.rawValue)
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, false)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, false)
        XCTAssertTrue(json["autoRestoreSucceeded"] is NSNull)
        XCTAssertTrue((json["message"] as? String)?.contains("Could not create daemon proxy") == true)
        let prepareRequests = await client.prepareRequests
        XCTAssertEqual(prepareRequests, [request])
    }

    func testRestoreAutoCallsAgentControlRestore() async throws {
        let client = FakeAgentControlClient()
        let processRunner = FakeProcessRunner(exitCode: 0)
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            manualControlClearer: {}
        )

        let result = try await runner.run(.restoreAuto(reason: "done", json: true))

        XCTAssertEqual(result.exitCode, 0)
        let restoreReasons = await client.restoreReasons
        let restoreAuthorities = await client.restoreAuthorities
        XCTAssertEqual(restoreReasons, ["done"])
        XCTAssertEqual(restoreAuthorities, [.explicitOperator])
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testRestoreAutoClearsManualControlMarkerAfterSuccessfulDaemonRestore() async throws {
        let manualControl = ManualControlFlag(active: true)
        let client = FakeAgentControlClient(status: AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: nil,
            lastErrorCode: nil,
            policy: AgentControlPolicy(enabled: true).snapshot
        ))
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            manualControlActiveReader: { manualControl.isActive },
            manualControlClearer: { manualControl.clear() }
        )

        let beforeRestore = try await runner.run(.diagnose(json: true))
        XCTAssertEqual(beforeRestore.exitCode, 0)
        XCTAssertEqual(try boolValue("manualControlActive", in: beforeRestore.stdout), true)
        XCTAssertEqual(try boolValue("safeToRequestCooling", in: beforeRestore.stdout), false)
        XCTAssertEqual(
            try stringValue("recommendedAgentAction", in: beforeRestore.stdout),
            ViftyCtlRecommendedAgentAction.restoreAutoBeforeRequestingCooling.rawValue
        )

        let restore = try await runner.run(.restoreAuto(reason: "clear manual marker", json: true))
        XCTAssertEqual(restore.exitCode, 0)
        let restoreData = try XCTUnwrap(restore.stdout.data(using: .utf8))
        let restoreJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: restoreData) as? [String: Any])
        XCTAssertEqual(restoreJSON["schemaVersion"] as? Int, 1)
        XCTAssertEqual(restoreJSON["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-status.schema.json")
        XCTAssertFalse(manualControl.isActive)

        let afterRestore = try await runner.run(.diagnose(json: true))
        XCTAssertEqual(afterRestore.exitCode, 0)
        XCTAssertEqual(try boolValue("manualControlActive", in: afterRestore.stdout), false)
        XCTAssertEqual(try boolValue("safeToRequestCooling", in: afterRestore.stdout), true)
        XCTAssertEqual(
            try stringValue("recommendedAgentAction", in: afterRestore.stdout),
            ViftyCtlRecommendedAgentAction.requestCooling.rawValue
        )
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(restoreReasons, ["clear manual marker"])
    }

    func testRestoreAutoJSONReturnsStructuredErrorWhenDaemonUnavailable() async throws {
        let client = FakeAgentControlClient(
            restoreError: ViftyError.helperRejected("Daemon connection invalidated.")
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.restoreAuto(reason: "done", json: true))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "restore-auto")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.helperUnreachable.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.repairHelper.rawValue)
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, false)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, false)
        XCTAssertTrue(json["autoRestoreSucceeded"] is NSNull)
        XCTAssertTrue((json["message"] as? String)?.contains("Daemon connection invalidated") == true)
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(restoreReasons, ["done"])
    }

    func testRunPreparesRunsChildRestoresAndReturnsChildExitCode() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)])
        let processRunner = FakeProcessRunner(exitCode: 7, resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: false, force: false))

        XCTAssertEqual(result.exitCode, 7)
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        let restoreAuthorities = await client.restoreAuthorities
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, ["viftyctl run child exited with 7"])
        XCTAssertEqual(restoreAuthorities.count, 1)
        XCTAssertNil(restoreAuthorities[0])
        XCTAssertEqual(processRunner.runArguments, [["/usr/bin/swift", "test"]])
    }

    func testRunJSONReportsPreparedLeaseAutoRestoreAndChildExitCode() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)])
        let executableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("viftyctl-run-child-\(UUID().uuidString)")
        try Data("fake child executable".utf8).write(to: executableURL)
        defer { try? FileManager.default.removeItem(at: executableURL) }
        let processRunner = FakeProcessRunner(exitCode: 0, resolvedArguments: [executableURL.path, "test"])
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: true, force: false))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(json["command"] as? String, "run")
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, true)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, true)
        XCTAssertEqual(json["autoRestoreSucceeded"] as? Bool, true)
        XCTAssertEqual(json["childExitCode"] as? Int, 0)
        XCTAssertEqual(json["childTerminationReason"] as? String, "exited")
        XCTAssertNil(json["childSignal"] as? Int)
        XCTAssertNil(json["childSignalName"] as? String)
        XCTAssertTrue(json["autoRestoreError"] is NSNull)
        XCTAssertEqual(json["resolvedChildExecutable"] as? String, executableURL.path)
        let executableDigest = try XCTUnwrap(json["resolvedChildExecutableSHA256"] as? String)
        XCTAssertNotNil(executableDigest.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression))
        XCTAssertEqual(json["resolvedChildExecutableSHA256Status"] as? String, "computed")
        XCTAssertEqual(json["signalScope"] as? String, ViftyCtlSignalScope.processGroup.rawValue)
        XCTAssertEqual(json["descendantCleanupBeforeAutoRestore"] as? Bool, true)
        XCTAssertEqual(json["backgroundProcessesAllowed"] as? Bool, false)
        XCTAssertEqual(json["generatedAt"] as? Double, 721_692_800)
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, ["viftyctl run child exited with 0"])
        XCTAssertEqual(processRunner.runArguments, [[executableURL.path, "test"]])
    }

    func testRunJSONInfersSignalTerminationFromShellStyleExitCode() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)])
        let processRunner = FakeProcessRunner(exitCode: 143, resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: true, force: false))

        XCTAssertEqual(result.exitCode, 143)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(json["childExitCode"] as? Int, 143)
        XCTAssertEqual(json["childTerminationReason"] as? String, "signalInferred")
        XCTAssertEqual(json["childSignal"] as? Int, 15)
        XCTAssertEqual(json["childSignalName"] as? String, "TERM")
        XCTAssertEqual(json["autoRestoreSucceeded"] as? Bool, true)
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(restoreReasons, ["viftyctl run child exited with 143"])
    }

    func testRunJSONReportsUnavailableDigestStatusWhenResolvedExecutableCannotBeRead() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)])
        let missingExecutable = FileManager.default.temporaryDirectory
            .appendingPathComponent("viftyctl-missing-child-\(UUID().uuidString)")
            .path
        let processRunner = FakeProcessRunner(exitCode: 0, resolvedArguments: [missingExecutable, "test"])
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: true, force: false))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["resolvedChildExecutable"] as? String, missingExecutable)
        XCTAssertNil(json["resolvedChildExecutableSHA256"])
        XCTAssertEqual(json["resolvedChildExecutableSHA256Status"] as? String, "unavailable")
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, ["viftyctl run child exited with 0"])
        XCTAssertEqual(processRunner.runArguments, [[missingExecutable, "test"]])
    }

    func testRunJSONReportsAutoRestoreFailureAfterChildExit() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let restoreError = ViftyError.helperRejected("restore failed")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)], restoreError: restoreError)
        let processRunner = FakeProcessRunner(exitCode: 0, resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: true, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 1)
        XCTAssertEqual(json["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(json["command"] as? String, "run")
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, true)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, true)
        XCTAssertEqual(json["autoRestoreSucceeded"] as? Bool, false)
        XCTAssertEqual(json["childExitCode"] as? Int, 0)
        XCTAssertTrue((json["autoRestoreError"] as? String)?.contains("restore failed") == true)
        XCTAssertEqual(json["resolvedChildExecutable"] as? String, "/usr/bin/swift")
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(restoreReasons, ["viftyctl run child exited with 0"])
        XCTAssertEqual(processRunner.runArguments, [["/usr/bin/swift", "test"]])
    }

    func testRunKeepsSignalShieldActiveUntilAutoRestoreAttemptCompletes() async throws {
        let request = AgentControlRequest(
            workload: .test,
            durationSeconds: 600,
            maxRPMPercent: 70,
            reason: "swift test",
            idempotencyKey: "signal-shield"
        )
        let observation = SignalShieldObservation()
        let client = FakeAgentControlClient(
            prepareResponses: [Self.allowedStatus(for: request)],
            restoreObserver: { observation.recordRestoreAttempt() }
        )
        let processRunner = FakeProcessRunner(
            exitCode: 0,
            resolvedArguments: ["/usr/bin/swift", "test"],
            signalShieldObservation: observation
        )
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        let result = try await runner.run(
            .run(request, childArguments: ["swift", "test"], json: false, force: false)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(observation.wasActiveDuringRestore)
        XCTAssertFalse(observation.isActive)
        XCTAssertEqual(observation.finishCount, 1)
    }

    func testRunKeepsSignalShieldActiveThroughRestoreAfterChildLaunchFailure() async throws {
        let request = AgentControlRequest(
            workload: .test,
            durationSeconds: 600,
            maxRPMPercent: 70,
            reason: "swift test",
            idempotencyKey: "signal-shield-launch-error"
        )
        let observation = SignalShieldObservation()
        let launchError = ViftyError.helperRejected("launch failed")
        let client = FakeAgentControlClient(
            prepareResponses: [Self.allowedStatus(for: request)],
            restoreObserver: { observation.recordRestoreAttempt() }
        )
        let processRunner = FakeProcessRunner(
            error: launchError,
            signalShieldObservation: observation
        )
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        do {
            _ = try await runner.run(
                .run(request, childArguments: ["missing"], json: false, force: false)
            )
            XCTFail("Expected the launch failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, launchError.localizedDescription)
        }

        XCTAssertTrue(observation.wasActiveDuringRestore)
        XCTAssertFalse(observation.isActive)
        XCTAssertEqual(observation.finishCount, 1)
    }

    func testRunRestoresIfChildLaunchThrows() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)])
        let launchError = ViftyError.helperRejected("launch failed")
        let processRunner = FakeProcessRunner(error: launchError)
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        do {
            _ = try await runner.run(.run(request, childArguments: ["missing-command"], json: false, force: false))
            XCTFail("Expected child launch error")
        } catch {
            XCTAssertEqual(error.localizedDescription, launchError.localizedDescription)
            let prepareRequests = await client.prepareRequests
            let restoreReasons = await client.restoreReasons
            XCTAssertEqual(prepareRequests, [request])
            XCTAssertEqual(restoreReasons, ["viftyctl run failed to launch child: \(error.localizedDescription)"])
        }
    }

    func testRunReturnsFailureWhenRestoreFailsAfterSuccessfulChildExit() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let restoreError = ViftyError.helperRejected("restore failed")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)], restoreError: restoreError)
        let processRunner = FakeProcessRunner(exitCode: 0, resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: false, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("Auto restore failed"))
        XCTAssertTrue(result.stderr.contains("safety fallback"))
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(restoreReasons, ["viftyctl run child exited with 0"])
        XCTAssertEqual(processRunner.runArguments, [["/usr/bin/swift", "test"]])
    }

    func testRunPreservesFailingChildExitCodeWhenRestoreFails() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let restoreError = ViftyError.helperRejected("restore failed")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)], restoreError: restoreError)
        let processRunner = FakeProcessRunner(exitCode: 7, resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: false, force: false))

        XCTAssertEqual(result.exitCode, 7)
        XCTAssertTrue(result.stderr.contains("Auto restore failed"))
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(restoreReasons, ["viftyctl run child exited with 7"])
    }

    func testRunReportsRestoreFailureWhenChildLaunchThrows() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let launchError = ViftyError.helperRejected("launch failed")
        let restoreError = ViftyError.helperRejected("restore failed")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)], restoreError: restoreError)
        let processRunner = FakeProcessRunner(error: launchError)
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        do {
            _ = try await runner.run(.run(request, childArguments: ["missing-command"], json: false, force: false))
            XCTFail("Expected child launch and restore error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("launch failed"))
            XCTAssertTrue(error.localizedDescription.contains("Auto restore also failed"))
            XCTAssertTrue(error.localizedDescription.contains("restore failed"))
            let restoreReasons = await client.restoreReasons
            XCTAssertEqual(restoreReasons, ["viftyctl run failed to launch child: \(launchError.localizedDescription)"])
        }
    }

    func testRunJSONReportsRestoreSuccessWhenChildLaunchThrowsAfterPrepare() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let launchError = ViftyError.helperRejected("launch failed")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)])
        let processRunner = FakeProcessRunner(error: launchError)
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.run(request, childArguments: ["missing-command"], json: true, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "run")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.childCommandFailed.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.fixChildCommand.rawValue)
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, true)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, true)
        XCTAssertEqual(json["autoRestoreSucceeded"] as? Bool, true)
        XCTAssertTrue((json["message"] as? String)?.contains("launch failed") == true)
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, ["viftyctl run failed to launch child: \(launchError.localizedDescription)"])
        XCTAssertEqual(processRunner.runArguments, [["missing-command"]])
    }

    func testRunJSONReportsUnconfirmedDescendantCleanupAndStillRestoresAuto() async throws {
        let request = AgentControlRequest(
            workload: .test,
            durationSeconds: 600,
            maxRPMPercent: 70,
            reason: "swift test",
            idempotencyKey: "key"
        )
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)])
        let lifecycleError = ViftyCtlChildProcessLifecycleError(
            phase: .descendantCleanup,
            message: "process group survived bounded TERM/KILL escalation",
            childExitCode: 0,
            descendantCleanupCompleted: false,
            backgroundProcessesMayRemain: true
        )
        let processRunner = FakeProcessRunner(
            resolvedArguments: ["/usr/bin/swift", "test"],
            error: lifecycleError
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(
            .run(request, childArguments: ["swift", "test"], json: true, force: false)
        )

        XCTAssertEqual(result.exitCode, 1)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.childCommandFailed.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, true)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, true)
        XCTAssertEqual(json["autoRestoreSucceeded"] as? Bool, true)
        XCTAssertEqual(json["childProcessFailurePhase"] as? String, "descendantCleanup")
        XCTAssertEqual(json["childExitCode"] as? Int, 0)
        XCTAssertEqual(json["descendantCleanupCompleted"] as? Bool, false)
        XCTAssertEqual(json["backgroundProcessesMayRemain"] as? Bool, true)
        XCTAssertTrue((json["message"] as? String)?.contains("survived bounded") == true)
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(
            restoreReasons,
            ["viftyctl run child lifecycle failed during descendantCleanup: process group survived bounded TERM/KILL escalation"]
        )
    }

    func testRunJSONReportsRestoreFailureWhenChildLaunchThrowsAfterPrepare() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let launchError = ViftyError.helperRejected("launch failed")
        let restoreError = ViftyError.helperRejected("restore failed")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: request)], restoreError: restoreError)
        let processRunner = FakeProcessRunner(error: launchError)
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.run(request, childArguments: ["missing-command"], json: true, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "run")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.restoreFailed.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.runDiagnose.rawValue)
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, true)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, true)
        XCTAssertEqual(json["autoRestoreSucceeded"] as? Bool, false)
        XCTAssertTrue((json["message"] as? String)?.contains("launch failed") == true)
        XCTAssertTrue((json["message"] as? String)?.contains("Auto restore also failed") == true)
        XCTAssertTrue((json["message"] as? String)?.contains("restore failed") == true)
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, ["viftyctl run failed to launch child: \(launchError.localizedDescription)"])
        XCTAssertEqual(processRunner.runArguments, [["missing-command"]])
    }

    func testRunDoesNotLaunchChildWhenPrepareIsDenied() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let denied = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .denied(.unsupportedHardware, message: "Agent cooling is supported only on Apple Silicon MacBook Pro hardware."),
            lastErrorCode: .unsupportedHardware,
            policy: AgentControlPolicy(enabled: true).snapshot
        )
        let client = FakeAgentControlClient(prepareResponses: [denied])
        let processRunner = FakeProcessRunner(exitCode: 0, resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: false, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("prepare denied"))
        XCTAssertTrue(result.stderr.contains("Apple Silicon MacBook Pro"))
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, [])
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testRunJSONReturnsStructuredErrorWhenPrepareIsDenied() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let denied = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .denied(.unsupportedHardware, message: "Agent cooling is supported only on Apple Silicon MacBook Pro hardware."),
            lastErrorCode: .unsupportedHardware,
            policy: AgentControlPolicy(enabled: true).snapshot
        )
        let client = FakeAgentControlClient(prepareResponses: [denied])
        let processRunner = FakeProcessRunner(exitCode: 0, resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: true, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "run")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.unsupportedHardware.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.runDiagnose.rawValue)
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, false)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, false)
        XCTAssertTrue(json["autoRestoreSucceeded"] is NSNull)
        XCTAssertTrue((json["message"] as? String)?.contains("Apple Silicon MacBook Pro") == true)
        let prepareRequests = await client.prepareRequests
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testRunDoesNotLaunchChildWhenPrepareReturnsMismatchedLease() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let otherRequest = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "other", idempotencyKey: "key")
        let client = FakeAgentControlClient(prepareResponses: [Self.allowedStatus(for: otherRequest)])
        let processRunner = FakeProcessRunner(exitCode: 0, resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: false, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("does not match"))
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, [])
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testRunDoesNotLaunchChildWhenPrepareReturnsNoLease() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let malformedAllowed = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .allowed(targetRPMByFanID: [0: 3600]),
            lastErrorCode: nil,
            policy: AgentControlPolicy(enabled: true).snapshot
        )
        let client = FakeAgentControlClient(prepareResponses: [malformedAllowed])
        let processRunner = FakeProcessRunner(exitCode: 0, resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: false, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stderr.contains("active cooling lease"))
        let prepareRequests = await client.prepareRequests
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, [])
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testRunResolvesChildBeforePreparingLease() async throws {
        let client = FakeAgentControlClient()
        let resolveError = ViftyError.helperRejected("missing child")
        let processRunner = FakeProcessRunner(resolveError: resolveError)
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")

        do {
            _ = try await runner.run(.run(request, childArguments: ["missing-command"], json: false, force: false))
            XCTFail("Expected child resolve error")
        } catch {
            XCTAssertEqual(error.localizedDescription, resolveError.localizedDescription)
            let prepareRequestCount = await client.prepareRequestCount
            let restoreReasonCount = await client.restoreReasonCount
            XCTAssertEqual(prepareRequestCount, 0)
            XCTAssertEqual(restoreReasonCount, 0)
            XCTAssertEqual(processRunner.runCallCount, 0)
        }
    }

    func testRunJSONReturnsStructuredErrorWhenChildResolveFailsBeforePrepare() async throws {
        let client = FakeAgentControlClient()
        let resolveError = ViftyError.helperRejected("missing child")
        let processRunner = FakeProcessRunner(resolveError: resolveError)
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")

        let result = try await runner.run(.run(request, childArguments: ["missing-command"], json: true, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "run")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.childCommandFailed.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.fixChildCommand.rawValue)
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, false)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, false)
        XCTAssertTrue(json["autoRestoreSucceeded"] is NSNull)
        XCTAssertTrue((json["message"] as? String)?.contains("missing child") == true)
        let prepareRequestCount = await client.prepareRequestCount
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequestCount, 0)
        XCTAssertEqual(restoreReasonCount, 0)
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testPrepareForceUsesRetryAfterMetadataBeforeRetryingRateLimitedRequest() async throws {
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        let rateLimited = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .denied(.prepareRateLimited, message: "Wait", retryAfterSeconds: 2),
            lastErrorCode: .prepareRateLimited,
            policy: AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30).snapshot
        )
        let allowed = AgentControlStatus(
            enabled: true,
            activeLease: AgentCoolingLease(
                id: "lease-1",
                request: request,
                createdAt: Date(timeIntervalSince1970: 1_000),
                expiresAt: Date(timeIntervalSince1970: 1_600),
                targetRPMByFanID: [0: 3600]
            ),
            lastDecision: .allowed(targetRPMByFanID: [0: 3600]),
            lastErrorCode: nil,
            policy: AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30).snapshot
        )
        let client = FakeAgentControlClient(prepareResponses: [rateLimited, allowed])
        let sleepRecorder = SleepRecorder()
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            sleep: { nanoseconds in sleepRecorder.record(nanoseconds) }
        )

        let result = try await runner.run(.prepare(request, json: true, force: true))

        XCTAssertEqual(result.exitCode, 0)
        let prepareRequests = await client.prepareRequests
        XCTAssertEqual(prepareRequests, [request, request])
        XCTAssertEqual(sleepRecorder.values, [2_000_000_000])
        XCTAssertTrue(result.stdout.contains("\"activeLease\""))
    }

    func testPrepareForceReturnsNonzeroWhenRetryIsStillDenied() async throws {
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        let rateLimited = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .denied(.prepareRateLimited, message: "Wait", retryAfterSeconds: 2),
            lastErrorCode: .prepareRateLimited,
            policy: AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30).snapshot
        )
        let denied = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .denied(.noControllableFans, message: "No controllable fans were reported by the helper."),
            lastErrorCode: .noControllableFans,
            policy: AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30).snapshot
        )
        let client = FakeAgentControlClient(prepareResponses: [rateLimited, denied])
        let sleepRecorder = SleepRecorder()
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            sleep: { nanoseconds in sleepRecorder.record(nanoseconds) }
        )

        let result = try await runner.run(.prepare(request, json: true, force: true))

        XCTAssertEqual(result.exitCode, 1)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["lastErrorCode"] as? String, AgentControlErrorCode.noControllableFans.rawValue)
        let prepareRequests = await client.prepareRequests
        XCTAssertEqual(prepareRequests, [request, request])
        XCTAssertEqual(sleepRecorder.values, [2_000_000_000])
    }

    func testPrepareForceDoesNotRetryWhenCooldownWaitFails() async throws {
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        let rateLimited = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .denied(.prepareRateLimited, message: "Wait", retryAfterSeconds: 2),
            lastErrorCode: .prepareRateLimited,
            policy: AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30).snapshot
        )
        let client = FakeAgentControlClient(prepareResponses: [rateLimited, Self.allowedStatus(for: request)])
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            sleep: { _ in throw CancellationError() }
        )

        let result = try await runner.run(.prepare(request, json: true, force: true))

        XCTAssertEqual(result.exitCode, 1)
        let prepareRequests = await client.prepareRequests
        XCTAssertEqual(prepareRequests, [request])
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "prepare")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.prepareRateLimited.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.waitBeforeRetry.rawValue)
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, false)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, false)
        XCTAssertEqual(json["retryAfterSeconds"] as? Int, 2)
        XCTAssertTrue((json["message"] as? String)?.contains("Force retry wait was interrupted") == true)
    }

    func testRunForceDoesNotLaunchChildWhenCooldownWaitFails() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let rateLimited = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .denied(.prepareRateLimited, message: "Wait", retryAfterSeconds: 2),
            lastErrorCode: .prepareRateLimited,
            policy: AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30).snapshot
        )
        let client = FakeAgentControlClient(prepareResponses: [rateLimited, Self.allowedStatus(for: request)])
        let processRunner = FakeProcessRunner()
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            sleep: { _ in throw CancellationError() }
        )

        do {
            _ = try await runner.run(.run(request, childArguments: ["swift", "test"], json: false, force: true))
            XCTFail("Expected interrupted force retry wait to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Force retry wait was interrupted"))
            let prepareRequests = await client.prepareRequests
            let restoreReasonCount = await client.restoreReasonCount
            XCTAssertEqual(prepareRequests, [request])
            XCTAssertEqual(restoreReasonCount, 0)
            XCTAssertEqual(processRunner.runCallCount, 0)
        }
    }

    func testRunJSONForceReportsRateLimitWhenCooldownWaitFailsBeforeCooling() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let rateLimited = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .denied(.prepareRateLimited, message: "Wait", retryAfterSeconds: 2),
            lastErrorCode: .prepareRateLimited,
            policy: AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30).snapshot
        )
        let client = FakeAgentControlClient(prepareResponses: [rateLimited, Self.allowedStatus(for: request)])
        let processRunner = FakeProcessRunner(resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) },
            sleep: { _ in throw CancellationError() }
        )

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: true, force: true))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "run")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.prepareRateLimited.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.waitBeforeRetry.rawValue)
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, false)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, false)
        XCTAssertTrue(json["autoRestoreSucceeded"] is NSNull)
        XCTAssertEqual(json["retryAfterSeconds"] as? Int, 2)
        XCTAssertTrue((json["message"] as? String)?.contains("Force retry wait was interrupted") == true)
        let prepareRequests = await client.prepareRequests
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasonCount, 0)
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testRunJSONReportsRetryAfterWhenPrepareIsRateLimited() async throws {
        let request = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 70, reason: "swift test", idempotencyKey: "key")
        let rateLimited = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: .denied(.prepareRateLimited, message: "Wait", retryAfterSeconds: 12),
            lastErrorCode: .prepareRateLimited,
            policy: AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30).snapshot
        )
        let client = FakeAgentControlClient(prepareResponses: [rateLimited])
        let processRunner = FakeProcessRunner(resolvedArguments: ["/usr/bin/swift", "test"])
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: processRunner,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let result = try await runner.run(.run(request, childArguments: ["swift", "test"], json: true, force: false))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(result.stderr, "")
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "run")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.prepareRateLimited.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.waitBeforeRetry.rawValue)
        XCTAssertEqual(json["coolingLeasePrepared"] as? Bool, false)
        XCTAssertEqual(json["autoRestoreAttempted"] as? Bool, false)
        XCTAssertTrue(json["autoRestoreSucceeded"] is NSNull)
        XCTAssertEqual(json["retryAfterSeconds"] as? Int, 12)
        XCTAssertEqual(json["message"] as? String, "Wait")
        let prepareRequests = await client.prepareRequests
        let restoreReasonCount = await client.restoreReasonCount
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasonCount, 0)
        XCTAssertEqual(processRunner.runCallCount, 0)
    }

    func testDiagnoseBlocksWhenOwnershipStatusIsUnavailable() async throws {
        let client = FakeAgentControlClient(
            ownershipError: ViftyError.helperRejected("ownership status timed out")
        )
        let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner())

        let result = try await runner.run(.diagnose(json: true))
        let json = try jsonObject(in: result.stdout)

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(json["fanControlOwnershipStatusError"] as? String, "The fan helper rejected the command: ownership status timed out")
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])
        XCTAssertTrue(checks.contains {
            $0["id"] as? String == "fanControlOwnershipStatusAvailable"
                && $0["passed"] as? Bool == false
        })
        XCTAssertFalse(checks.contains {
            $0["id"] as? String == "replacementMaintenanceAttestation"
        })
    }

    func testDiagnoseBlocksProtocolMismatch() async throws {
        let legacyOwnership = FanControlOwnershipStatus(
            protocolVersion: FanControlProtocolVersion.legacy,
            owner: nil,
            phase: nil,
            transactionID: nil,
            expectedFanIDs: [],
            recoveryPending: false
        )
        let client = FakeAgentControlClient(ownership: legacyOwnership)
        let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner())

        let result = try await runner.run(.diagnose(json: true))
        let checks = try XCTUnwrap(try jsonObject(in: result.stdout)["checks"] as? [[String: Any]])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(checks.contains {
            $0["id"] as? String == "fanControlProtocolCurrent"
                && $0["passed"] as? Bool == false
        })
        XCTAssertFalse(checks.contains {
            $0["id"] as? String == "replacementMaintenanceAttestation"
        })
    }

    func testDiagnoseBlocksRecoveryPendingAndExposesStableRecoveryCode() async throws {
        let pending = FanControlOwnershipStatus(
            owner: .recovery,
            phase: .restorePending,
            transactionID: "tx-recovery",
            expectedFanIDs: [0, 1],
            confirmedOSManagedFanIDs: [0],
            recoveryPending: true,
            errorCode: "RESTORE_UNCONFIRMED",
            errorMessage: "fan 1 mode readback is unknown",
            recoveryAttemptCount: 2
        )
        let client = FakeAgentControlClient(ownership: pending)
        let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner())

        let result = try await runner.run(.diagnose(json: true))
        let json = try jsonObject(in: result.stdout)
        let ownership = try XCTUnwrap(json["fanControlOwnership"] as? [String: Any])
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertEqual(ownership["errorCode"] as? String, "RESTORE_UNCONFIRMED")
        XCTAssertEqual(ownership["errorMessage"] as? String, "fan 1 mode readback is unknown")
        XCTAssertEqual(ownership["recoveryAttemptCount"] as? Int, 2)
        XCTAssertTrue(checks.contains {
            $0["id"] as? String == "fanControlRecoveryClear"
                && $0["passed"] as? Bool == false
        })
    }

    func testDiagnoseBlocksForcedOrUnknownFanWithoutOwner() async throws {
        let forcedClient = FakeAgentControlClient(snapshot: Self.readySnapshot(fanMode: .forced))
        let forcedRunner = ViftyCtlRunner(client: forcedClient, processRunner: FakeProcessRunner())
        let unknownClient = FakeAgentControlClient(snapshot: Self.readySnapshot(fanMode: .unknown(2)))
        let unknownRunner = ViftyCtlRunner(client: unknownClient, processRunner: FakeProcessRunner())

        for result in [
            try await forcedRunner.run(.diagnose(json: true)),
            try await unknownRunner.run(.diagnose(json: true))
        ] {
            let checks = try XCTUnwrap(try jsonObject(in: result.stdout)["checks"] as? [[String: Any]])
            XCTAssertEqual(result.exitCode, 75)
            XCTAssertTrue(checks.contains {
                $0["id"] as? String == "fanControlHardwareConsistent"
                    && $0["passed"] as? Bool == false
            })
        }
    }

    func testDiagnoseBlocksOwnershipFanSetInconsistency() async throws {
        let ownership = FanControlOwnershipStatus(
            owner: .manual(sessionID: "manual-1"),
            phase: .active,
            transactionID: "tx-1",
            expectedFanIDs: [0, 2],
            recoveryPending: false
        )
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(fanMode: .forced),
            ownership: ownership
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            manualControlActiveReader: { false }
        )

        let result = try await runner.run(.diagnose(json: true))
        let checks = try XCTUnwrap(try jsonObject(in: result.stdout)["checks"] as? [[String: Any]])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(checks.contains {
            $0["id"] as? String == "fanControlHardwareConsistent"
                && $0["passed"] as? Bool == false
        })
    }

    func testDiagnoseBlocksActiveManualOwnershipEvenWhenLocalMarkerIsClear() async throws {
        let ownership = FanControlOwnershipStatus(
            owner: .manual(sessionID: "manual-1"),
            phase: .active,
            transactionID: "tx-1",
            expectedFanIDs: [0, 1],
            recoveryPending: false
        )
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(fanMode: .forced),
            ownership: ownership
        )
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            manualControlActiveReader: { false }
        )

        let result = try await runner.run(.diagnose(json: true))
        let json = try jsonObject(in: result.stdout)
        let checks = try XCTUnwrap(json["checks"] as? [[String: Any]])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertEqual(json["manualControlActive"] as? Bool, false)
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, false)
        XCTAssertEqual(
            json["recommendedRecoveryAction"] as? String,
            ViftyCtlReadinessRecoveryAction.restoreAutoBeforeRetry.rawValue
        )
        XCTAssertTrue(checks.contains {
            $0["id"] as? String == "fanControlOwnershipClear"
                && $0["passed"] as? Bool == false
        })
        XCTAssertTrue(checks.contains {
            $0["id"] as? String == "fanControlHardwareConsistent"
                && $0["passed"] as? Bool == true
        })
    }

    func testDiagnoseRejectsForcedOrUnknownFansOutsideManualExpectedDomain() async throws {
        let ownership = FanControlOwnershipStatus(
            owner: .manual(sessionID: "manual-1"),
            phase: .active,
            transactionID: "tx-1",
            expectedFanIDs: [0],
            recoveryPending: false
        )

        for modes in [[FanHardwareMode.forced, .forced], [.forced, .unknown(2)]] {
            let client = FakeAgentControlClient(
                snapshot: Self.readySnapshot(fanModes: modes),
                ownership: ownership
            )
            let result = try await ViftyCtlRunner(
                client: client,
                processRunner: FakeProcessRunner()
            ).run(.diagnose(json: true))
            let checks = try XCTUnwrap(try jsonObject(in: result.stdout)["checks"] as? [[String: Any]])

            XCTAssertEqual(result.exitCode, 75)
            XCTAssertTrue(checks.contains {
                $0["id"] as? String == "fanControlHardwareConsistent"
                    && $0["passed"] as? Bool == false
            })
        }
    }

    func testDiagnoseRejectsAgentOwnershipWhoseExpectedFansDifferFromLeaseTargets() async throws {
        let request = AgentControlRequest(
            workload: .test,
            durationSeconds: 300,
            maxRPMPercent: 60,
            reason: "test",
            idempotencyKey: "agent-1"
        )
        let status = AgentControlStatus(
            enabled: true,
            activeLease: AgentCoolingLease(
                id: "lease-1",
                request: request,
                createdAt: Date(timeIntervalSince1970: 1_000),
                expiresAt: Date(timeIntervalSince1970: 1_300),
                targetRPMByFanID: [0: 3_000]
            ),
            lastDecision: nil,
            lastErrorCode: nil
        )
        let ownership = FanControlOwnershipStatus(
            owner: .agent(leaseID: "lease-1"),
            phase: .active,
            transactionID: "lease-1",
            expectedFanIDs: [0, 1],
            recoveryPending: false
        )
        let client = FakeAgentControlClient(
            snapshot: Self.readySnapshot(fanMode: .forced),
            ownership: ownership,
            status: status
        )

        let result = try await ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner()
        ).run(.diagnose(json: true))
        let checks = try XCTUnwrap(try jsonObject(in: result.stdout)["checks"] as? [[String: Any]])

        XCTAssertEqual(result.exitCode, 75)
        XCTAssertTrue(checks.contains {
            $0["id"] as? String == "fanControlHardwareConsistent"
                && $0["passed"] as? Bool == false
        })
    }

    func testDiagnoseTreatsManualAndAgentTransientPhasesAsBlocked() async throws {
        let transientPhases: [FanControlPhase] = [.prepared, .applying, .restoring, .restorePending]
        let request = AgentControlRequest(
            workload: .test,
            durationSeconds: 300,
            maxRPMPercent: 60,
            reason: "test",
            idempotencyKey: "agent-1"
        )
        let agentStatus = AgentControlStatus(
            enabled: true,
            activeLease: AgentCoolingLease(
                id: "lease-1",
                request: request,
                createdAt: Date(timeIntervalSince1970: 1_000),
                expiresAt: Date(timeIntervalSince1970: 1_300),
                targetRPMByFanID: [0: 3_000, 1: 3_100]
            ),
            lastDecision: nil,
            lastErrorCode: nil
        )

        for owner in [FanControlOwner.manual(sessionID: "manual-1"), .agent(leaseID: "lease-1")] {
            for phase in transientPhases {
                let ownership = FanControlOwnershipStatus(
                    owner: owner,
                    phase: phase,
                    transactionID: "tx-1",
                    expectedFanIDs: [0, 1],
                    recoveryPending: phase == .restoring || phase == .restorePending
                )
                let client = FakeAgentControlClient(
                    snapshot: Self.readySnapshot(fanMode: .forced),
                    ownership: ownership,
                    status: agentStatus
                )
                let result = try await ViftyCtlRunner(
                    client: client,
                    processRunner: FakeProcessRunner()
                ).run(.diagnose(json: true))
                let checks = try XCTUnwrap(try jsonObject(in: result.stdout)["checks"] as? [[String: Any]])

                XCTAssertEqual(result.exitCode, 75, "\(owner.type) \(phase.rawValue)")
                XCTAssertTrue(checks.contains {
                    $0["id"] as? String == "fanControlOwnershipStateValid"
                        && $0["passed"] as? Bool == false
                }, "\(owner.type) \(phase.rawValue)")
            }
        }
    }

    func testDiagnoseRequiresRecoveryOwnerToUsePendingRecoveryShape() async throws {
        let invalidStatuses = [
            FanControlOwnershipStatus(
                owner: .recovery,
                phase: .active,
                transactionID: "tx-1",
                expectedFanIDs: [0, 1],
                recoveryPending: true
            ),
            FanControlOwnershipStatus(
                owner: .recovery,
                phase: .restorePending,
                transactionID: "tx-1",
                expectedFanIDs: [0, 1],
                recoveryPending: false
            )
        ]

        for ownership in invalidStatuses {
            let client = FakeAgentControlClient(ownership: ownership)
            let result = try await ViftyCtlRunner(
                client: client,
                processRunner: FakeProcessRunner()
            ).run(.diagnose(json: true))
            let checks = try XCTUnwrap(try jsonObject(in: result.stdout)["checks"] as? [[String: Any]])

            XCTAssertEqual(result.exitCode, 75)
            XCTAssertTrue(checks.contains {
                $0["id"] as? String == "fanControlOwnershipStateValid"
                    && $0["passed"] as? Bool == false
            })
        }
    }

    func testDiagnoseRejectsBlankManualSessionAndAgentLeaseIDs() async throws {
        for owner in [FanControlOwner.manual(sessionID: " \t"), .agent(leaseID: "\n")] {
            let ownership = FanControlOwnershipStatus(
                owner: owner,
                phase: .active,
                transactionID: "tx-1",
                expectedFanIDs: [0, 1],
                recoveryPending: false
            )
            let client = FakeAgentControlClient(
                snapshot: Self.readySnapshot(fanMode: .forced),
                ownership: ownership
            )
            let result = try await ViftyCtlRunner(
                client: client,
                processRunner: FakeProcessRunner(),
                manualControlActiveReader: { false }
            ).run(.diagnose(json: true))
            let checks = try XCTUnwrap(try jsonObject(in: result.stdout)["checks"] as? [[String: Any]])

            XCTAssertEqual(result.exitCode, 75)
            XCTAssertTrue(checks.contains {
                $0["id"] as? String == "fanControlOwnershipStateValid"
                    && $0["passed"] as? Bool == false
            })
        }
    }

    private func boolValue(
        _ key: String,
        in stdout: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Bool {
        let json = try jsonObject(in: stdout, file: file, line: line)
        return try XCTUnwrap(json[key] as? Bool, file: file, line: line)
    }

    private func stringValue(
        _ key: String,
        in stdout: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let json = try jsonObject(in: stdout, file: file, line: line)
        return try XCTUnwrap(json[key] as? String, file: file, line: line)
    }

    private func jsonObject(
        in stdout: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let data = try XCTUnwrap(stdout.data(using: .utf8), file: file, line: line)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any],
            file: file,
            line: line
        )
    }

    private static func allowedStatus(for request: AgentControlRequest) -> AgentControlStatus {
        AgentControlStatus(
            enabled: true,
            activeLease: AgentCoolingLease(
                id: "lease-\(request.idempotencyKey)",
                request: request,
                createdAt: Date(timeIntervalSince1970: 1_000),
                expiresAt: Date(timeIntervalSince1970: 1_000 + TimeInterval(request.durationSeconds)),
                targetRPMByFanID: [0: 3600]
            ),
            lastDecision: .allowed(targetRPMByFanID: [0: 3600]),
            lastErrorCode: nil,
            policy: AgentControlPolicy(enabled: true).snapshot
        )
    }

    fileprivate static func readySnapshot(fanMode: FanHardwareMode = .automatic) -> HardwareSnapshot {
        readySnapshot(fanModes: [fanMode, fanMode])
    }

    fileprivate static func readySnapshot(fanModes: [FanHardwareMode]) -> HardwareSnapshot {
        precondition(fanModes.count == 2)
        return HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left Fan",
                    currentRPM: 2_100,
                    minimumRPM: 1_400,
                    maximumRPM: 6_000,
                    controllable: true,
                    hardwareMode: fanModes[0],
                    hardwareModeKey: "F0Md",
                    targetRPM: 2_000
                ),
                Fan(
                    id: 1,
                    name: "Right Fan",
                    currentRPM: 2_200,
                    minimumRPM: 1_400,
                    maximumRPM: 6_000,
                    controllable: true,
                    hardwareMode: fanModes[1],
                    hardwareModeKey: "F1md",
                    targetRPM: 2_000
                )
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 48.2, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testHelperMaintenancePrepareEmitsOnlyDaemonReportAndUsesBlockedExitForUnsafeShape() async throws {
        let safeReport = Self.maintenanceReport(operation: .repair)
        let safeClient = FakeAgentControlClient(maintenancePrepareResponse: safeReport)
        let safe = try await ViftyCtlRunner(
            client: safeClient,
            processRunner: FakeProcessRunner()
        ).run(.helperMaintenancePrepare(operation: .repair))
        XCTAssertEqual(safe.exitCode, 0)
        let prepareOperations = await safeClient.maintenancePrepareOperations
        XCTAssertEqual(prepareOperations, [.repair])
        let safeData = try XCTUnwrap(safe.stdout.data(using: .utf8))
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(HelperMaintenanceReport.self, from: safeData), safeReport)

        var blockedReport = safeReport
        blockedReport.safeToStop = false
        blockedReport.token = nil
        blockedReport.blockers = [HelperMaintenanceBlocker(
            code: .ownershipUnresolved,
            message: "blocked",
            recommendedRecoveryAction: "restore"
        )]
        let blocked = try await ViftyCtlRunner(
            client: FakeAgentControlClient(maintenancePrepareResponse: blockedReport),
            processRunner: FakeProcessRunner()
        ).run(.helperMaintenancePrepare(operation: .repair))
        XCTAssertEqual(blocked.exitCode, 75)
    }

    func testHelperMaintenanceConsumeValidatesReportThenUsesDaemonOwnedToken() async throws {
        let report = Self.maintenanceReport(operation: .uninstall)
        let token = try XCTUnwrap(report.token)
        let authorization = HelperMaintenanceAuthorization(
            authorized: true,
            operation: .uninstall,
            tokenID: token.tokenID,
            consumedAt: Date(timeIntervalSince1970: 1_001),
            quiesced: true,
            tokenConsumed: true
        )
        let client = FakeAgentControlClient(maintenanceConsumeResponse: authorization)
        let runner = ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            maintenanceReportReader: { path in
                XCTAssertEqual(path, "/fixture/report.json")
                return report
            }
        )

        let result = try await runner.run(.helperMaintenanceConsume(
            operation: .uninstall,
            reportPath: "/fixture/report.json"
        ))

        XCTAssertEqual(result.exitCode, 0)
        let consumeRequests = await client.maintenanceConsumeRequests
        XCTAssertEqual(
            consumeRequests,
            [HelperMaintenanceAuthorizationRequest(operation: .uninstall, token: token)]
        )
    }

    func testHelperMaintenanceConsumeRejectsUserReportBeforeDaemonCall() async throws {
        var report = Self.maintenanceReport(operation: .repair)
        report.completeExpectedSetConfirmed = false
        let unsafeReport = report
        let client = FakeAgentControlClient(maintenanceConsumeResponse: HelperMaintenanceAuthorization(
            authorized: true,
            operation: .repair,
            tokenID: "must-not-run",
            consumedAt: Date(),
            quiesced: true,
            tokenConsumed: true
        ))
        let result = try await ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner(),
            maintenanceReportReader: { _ in unsafeReport }
        ).run(.helperMaintenanceConsume(operation: .repair, reportPath: "/fixture/report.json"))

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertTrue(result.stdout.contains("helper"))
        let consumeRequests = await client.maintenanceConsumeRequests
        XCTAssertTrue(consumeRequests.isEmpty)
    }

    func testHelperMaintenanceCancelUsesDaemonAndReturnsJSON() async throws {
        let client = FakeAgentControlClient()
        let result = try await ViftyCtlRunner(
            client: client,
            processRunner: FakeProcessRunner()
        ).run(.helperMaintenanceCancel)

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "{\"cancelled\":true}\n")
        let cancellationCount = await client.maintenanceCancellationCount
        XCTAssertEqual(cancellationCount, 1)
    }

    private static func maintenanceReport(
        operation: HelperMaintenanceOperation
    ) -> HelperMaintenanceReport {
        let issuedAt = Date(timeIntervalSince1970: 1_000)
        let token = HelperMaintenanceToken(
            tokenID: "maintenance-token",
            operation: operation,
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(30),
            bootSessionID: "boot",
            daemonSessionID: "daemon",
            journalGeneration: 4,
            expectedFanIDs: [0, 1],
            helperSHA256: String(repeating: "a", count: 64),
            quiesceGeneration: 2
        )
        return HelperMaintenanceReport(
            operation: operation,
            safeToStop: true,
            quiesced: true,
            restoreAttempted: true,
            restoreSucceeded: true,
            completeExpectedSetConfirmed: true,
            fanResults: [
                HelperMaintenanceFanResult(
                    fanID: 0,
                    observedMode: "automatic",
                    confirmedOSManaged: true,
                    freshConfirmationAt: issuedAt
                ),
                HelperMaintenanceFanResult(
                    fanID: 1,
                    observedMode: "system",
                    confirmedOSManaged: true,
                    freshConfirmationAt: issuedAt
                )
            ],
            blockers: [],
            token: token
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViftyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private final class ManualControlFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedActive: Bool

    init(active: Bool) {
        self.storedActive = active
    }

    var isActive: Bool {
        lock.withLock { storedActive }
    }

    func clear() {
        lock.withLock {
            storedActive = false
        }
    }
}

private actor FakeAgentControlClient: ViftyCtlAgentControlClient {
    private let snapshotResponse: HardwareSnapshot
    private let ownershipResponse: FanControlOwnershipStatus
    private let statusResponse: AgentControlStatus
    private let auditResponse: [AgentControlAuditEvent]
    private let snapshotError: (any Error)?
    private let ownershipError: (any Error)?
    private let statusError: (any Error)?
    private let auditError: (any Error)?
    private let prepareError: (any Error)?
    private let restoreError: (any Error)?
    private let restoreObserver: (@Sendable () -> Void)?
    private let maintenancePrepareResponse: HelperMaintenanceReport?
    private let maintenanceConsumeResponse: HelperMaintenanceAuthorization?
    private let maintenanceError: (any Error)?
    private var prepareResponses: [AgentControlStatus]
    private var storedPrepareRequests: [AgentControlRequest] = []
    private var storedRestoreReasons: [String] = []
    private var storedRestoreAuthorities: [UnreadableJournalRecoveryAuthority?] = []
    private var storedAuditLimits: [Int] = []
    private var storedMaintenancePrepareOperations: [HelperMaintenanceOperation] = []
    private var storedMaintenanceConsumeRequests: [HelperMaintenanceAuthorizationRequest] = []
    private var maintenanceCancelCount = 0

    init(
        snapshot: HardwareSnapshot = ViftyCtlRunnerTests.readySnapshot(),
        ownership: FanControlOwnershipStatus = .osManaged,
        status: AgentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: nil,
            lastErrorCode: nil
        ),
        auditEvents: [AgentControlAuditEvent] = [],
        prepareResponses: [AgentControlStatus] = [],
        snapshotError: (any Error)? = nil,
        ownershipError: (any Error)? = nil,
        statusError: (any Error)? = nil,
        auditError: (any Error)? = nil,
        prepareError: (any Error)? = nil,
        restoreError: (any Error)? = nil,
        restoreObserver: (@Sendable () -> Void)? = nil,
        maintenancePrepareResponse: HelperMaintenanceReport? = nil,
        maintenanceConsumeResponse: HelperMaintenanceAuthorization? = nil,
        maintenanceError: (any Error)? = nil
    ) {
        self.snapshotResponse = snapshot
        self.ownershipResponse = ownership
        self.statusResponse = status
        self.auditResponse = auditEvents
        self.snapshotError = snapshotError
        self.ownershipError = ownershipError
        self.statusError = statusError
        self.auditError = auditError
        self.prepareError = prepareError
        self.restoreError = restoreError
        self.restoreObserver = restoreObserver
        self.maintenancePrepareResponse = maintenancePrepareResponse
        self.maintenanceConsumeResponse = maintenanceConsumeResponse
        self.maintenanceError = maintenanceError
        self.prepareResponses = prepareResponses
    }

    var prepareRequestCount: Int {
        storedPrepareRequests.count
    }

    var restoreReasonCount: Int {
        storedRestoreReasons.count
    }

    var prepareRequests: [AgentControlRequest] {
        storedPrepareRequests
    }

    var restoreReasons: [String] {
        storedRestoreReasons
    }

    var restoreAuthorities: [UnreadableJournalRecoveryAuthority?] {
        storedRestoreAuthorities
    }

    var auditLimits: [Int] {
        storedAuditLimits
    }

    var maintenancePrepareOperations: [HelperMaintenanceOperation] {
        storedMaintenancePrepareOperations
    }

    var maintenanceConsumeRequests: [HelperMaintenanceAuthorizationRequest] {
        storedMaintenanceConsumeRequests
    }

    var maintenanceCancellationCount: Int { maintenanceCancelCount }

    func snapshot() async throws -> HardwareSnapshot {
        if let snapshotError {
            throw snapshotError
        }
        return snapshotResponse
    }

    func status() async throws -> AgentControlStatus {
        if let statusError {
            throw statusError
        }
        return statusResponse
    }

    func fanControlOwnershipStatus() async throws -> FanControlOwnershipStatus {
        if let ownershipError { throw ownershipError }
        return ownershipResponse
    }

    func auditEvents(limit: Int) async throws -> [AgentControlAuditEvent] {
        storedAuditLimits.append(limit)
        if let auditError {
            throw auditError
        }
        return auditResponse
    }

    func prepare(_ request: AgentControlRequest) async throws -> AgentControlStatus {
        storedPrepareRequests.append(request)
        if let prepareError {
            throw prepareError
        }
        if !prepareResponses.isEmpty {
            return prepareResponses.removeFirst()
        }
        return statusResponse
    }

    func restore(reason: String) async throws -> AgentControlStatus {
        storedRestoreReasons.append(reason)
        storedRestoreAuthorities.append(nil)
        restoreObserver?()
        if let restoreError {
            throw restoreError
        }
        return statusResponse
    }

    func restore(
        reason: String,
        unreadableJournalRecoveryAuthority: UnreadableJournalRecoveryAuthority?
    ) async throws -> AgentControlStatus {
        storedRestoreReasons.append(reason)
        storedRestoreAuthorities.append(unreadableJournalRecoveryAuthority)
        restoreObserver?()
        if let restoreError {
            throw restoreError
        }
        return statusResponse
    }

    func prepareHelperMaintenance(
        operation: HelperMaintenanceOperation
    ) async throws -> HelperMaintenanceReport {
        storedMaintenancePrepareOperations.append(operation)
        if let maintenanceError { throw maintenanceError }
        guard let maintenancePrepareResponse else {
            throw ViftyError.helperRejected("fixture maintenance report unavailable")
        }
        return maintenancePrepareResponse
    }

    func consumeHelperMaintenanceToken(
        _ request: HelperMaintenanceAuthorizationRequest
    ) async throws -> HelperMaintenanceAuthorization {
        storedMaintenanceConsumeRequests.append(request)
        if let maintenanceError { throw maintenanceError }
        guard let maintenanceConsumeResponse else {
            throw ViftyError.helperRejected("fixture maintenance authorization unavailable")
        }
        return maintenanceConsumeResponse
    }

    func cancelHelperMaintenance() async throws {
        maintenanceCancelCount += 1
        if let maintenanceError { throw maintenanceError }
    }
}

private final class FakeProcessRunner: ViftyCtlProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let exitCode: Int32
    private let resolvedArguments: [String]?
    private let resolveError: (any Error)?
    private let error: (any Error)?
    private let signalShieldObservation: SignalShieldObservation?
    private var storedRunArguments: [[String]] = []

    init(
        exitCode: Int32 = 0,
        resolvedArguments: [String]? = nil,
        resolveError: (any Error)? = nil,
        error: (any Error)? = nil,
        signalShieldObservation: SignalShieldObservation? = nil
    ) {
        self.exitCode = exitCode
        self.resolvedArguments = resolvedArguments
        self.resolveError = resolveError
        self.error = error
        self.signalShieldObservation = signalShieldObservation
    }

    var runCallCount: Int {
        withLock { storedRunArguments.count }
    }

    var runArguments: [[String]] {
        withLock { storedRunArguments }
    }

    func resolve(_ arguments: [String]) throws -> [String] {
        try withLock {
            if let resolveError {
                throw resolveError
            }
            return resolvedArguments ?? arguments
        }
    }

    func run(_ arguments: [String]) throws -> Int32 {
        try withLock {
            storedRunArguments.append(arguments)
            if let error {
                throw error
            }
            return exitCode
        }
    }

    func runMaintainingSignalShield(_ arguments: [String]) -> ViftyCtlProcessRunCompletion {
        signalShieldObservation?.activate()
        let finish: @Sendable () -> Void = { [signalShieldObservation] in
            signalShieldObservation?.finish()
        }
        do {
            return ViftyCtlProcessRunCompletion(
                exitCode: try run(arguments),
                finishSignalHandling: finish
            )
        } catch {
            return ViftyCtlProcessRunCompletion(
                error: error,
                finishSignalHandling: finish
            )
        }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

private final class SignalShieldObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var storedActive = false
    private var storedWasActiveDuringRestore = false
    private var storedFinishCount = 0

    var isActive: Bool { lock.withLock { storedActive } }
    var wasActiveDuringRestore: Bool { lock.withLock { storedWasActiveDuringRestore } }
    var finishCount: Int { lock.withLock { storedFinishCount } }

    func activate() {
        lock.withLock { storedActive = true }
    }

    func recordRestoreAttempt() {
        lock.withLock { storedWasActiveDuringRestore = storedActive }
    }

    func finish() {
        lock.withLock {
            storedActive = false
            storedFinishCount += 1
        }
    }
}

private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [UInt64] = []

    var values: [UInt64] {
        lock.withLock { storedValues }
    }

    func record(_ nanoseconds: UInt64) {
        lock.withLock {
            storedValues.append(nanoseconds)
        }
    }
}
