import Foundation
import XCTest
@testable import ViftyCore

final class ViftyCtlJSONExampleTests: XCTestCase {
    private static let repairHelperRecoverySteps = ViftyAgentRule.repairHelperRecoveryActions
    private static let restoreAutoRecoverySteps = [
        "Restore Auto once with Vifty or viftyctl restore-auto --json, then rerun diagnose --json.",
        "If manualControlActive remains true, switch Vifty/default startup mode to Auto before requesting cooling."
    ]
    private static let fixChildCommandRecoverySteps = [
        "Fix the workload command/path or show the launch error; do not treat this as a helper failure."
    ]
    private static let runDiagnoseRecoverySteps = [
        "Run viftyctl diagnose --json and follow its readiness fields before requesting cooling."
    ]
    private static let waitBeforeRetryRecoverySteps = [
        "Wait for retryAfterSeconds before retrying, or show the JSON to the user if no retryAfterSeconds is present."
    ]

    func testCapabilitiesExampleDecodesAgainstCurrentModel() throws {
        let capabilities = try decode(ViftyCtlCapabilities.self, from: "capabilities.json")

        XCTAssertEqual(capabilities.schemaVersion, 1)
        XCTAssertTrue(capabilities.commands.contains("diagnose"))
        XCTAssertTrue(capabilities.commands.contains("audit"))
        XCTAssertTrue(capabilities.commands.contains("run"))
        XCTAssertTrue(capabilities.commands.contains("agent-rule"))
        XCTAssertTrue(capabilities.workloads.contains("localModel"))
        XCTAssertEqual(capabilities.policySource, .daemonStatus)
        XCTAssertTrue(capabilities.daemonStatusAvailable)
        XCTAssertTrue(capabilities.policyStatusAvailable)
        XCTAssertNil(capabilities.agentControlStatusError)
        XCTAssertEqual(capabilities.policy.prepareCooldownSeconds, 30)
        XCTAssertTrue(capabilities.supportsForceRetry)
        XCTAssertEqual(capabilities.runLifecycle.childCommandPreflightBeforeCooling, true)
        XCTAssertEqual(capabilities.runLifecycle.signalsForwardedToChild, ["INT", "TERM", "HUP"])
        XCTAssertEqual(capabilities.runLifecycle.autoRestoreAfterChildExit, true)
        XCTAssertEqual(capabilities.runLifecycle.structuredPreChildFailures, true)
        XCTAssertEqual(capabilities.runLifecycle.cleanupStateReportedOnLaunchFailure, true)
        XCTAssertEqual(capabilities.runLifecycle.resolvedChildExecutableReported, true)
        XCTAssertEqual(capabilities.directControlLifecycle.prepareUsesIdempotencyKey, true)
        XCTAssertEqual(capabilities.directControlLifecycle.restoreAutoAcceptsIdempotencyKey, false)
        XCTAssertEqual(capabilities.directControlLifecycle.restoreAutoScopedByIdempotencyKey, false)
        XCTAssertEqual(capabilities.directControlLifecycle.preferRunForSingleChildWorkloads, true)
        XCTAssertEqual(capabilities.metadataLimits.maximumReasonLength, AgentControlRequest.maximumReasonLength)
        XCTAssertEqual(capabilities.metadataLimits.maximumIdempotencyKeyLength, AgentControlRequest.maximumIdempotencyKeyLength)
        XCTAssertEqual(capabilities.exitCodes.blockedReadiness, 75)
        XCTAssertEqual(capabilities.schemas.capabilities, "docs/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(capabilities.schemas.audit, "docs/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(capabilities.schemas.diagnose, "docs/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(capabilities.schemas.status, "docs/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(capabilities.schemas.commandError, "docs/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(capabilities.schemas.run, "docs/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(capabilities.schemas.agentRule, "docs/schemas/viftyctl-agent-rule.schema.json")
        XCTAssertEqual(capabilities.schemaResources.capabilities, "Contents/Resources/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(capabilities.schemaResources.audit, "Contents/Resources/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(capabilities.schemaResources.diagnose, "Contents/Resources/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(capabilities.schemaResources.status, "Contents/Resources/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(capabilities.schemaResources.commandError, "Contents/Resources/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(capabilities.schemaResources.run, "Contents/Resources/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(capabilities.schemaResources.agentRule, "Contents/Resources/schemas/viftyctl-agent-rule.schema.json")
        XCTAssertEqual(capabilities.wrapperResources.sourceDirectory, "examples/viftyctl")
        XCTAssertEqual(capabilities.wrapperResources.bundleDirectory, "Contents/Resources/viftyctl-wrappers")
        XCTAssertEqual(capabilities.wrapperResources.guardedRunScript, "guarded-run.sh")
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("swift-test.sh"))
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("make-build.sh"))
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("pnpm-build.sh"))
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("pnpm-test.sh"))
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("bun-build.sh"))
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("bun-test.sh"))
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("go-build.sh"))
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("go-test.sh"))
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("uv-build.sh"))
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("uv-test.sh"))
        XCTAssertTrue(capabilities.wrapperResources.workloadScripts.contains("custom-workload.sh"))
        XCTAssertEqual(capabilities.workloadTemplates, ViftyCtlWorkloadTemplate.auditedTemplates)
        XCTAssertEqual(
            Set(capabilities.workloadTemplates.map(\.shortcutScript)),
            Set(capabilities.wrapperResources.workloadScripts)
        )
        XCTAssertTrue(capabilities.workloadTemplates.contains { template in
            template.id == "make-verify"
                && template.workload == "test"
                && template.childArguments == ["make", "verify"]
        })
        XCTAssertTrue(capabilities.workloadTemplates.contains { template in
            template.id == "custom-workload-template"
                && template.shortcutArguments == ["15m", "65", "custom workload", "--", "./scripts/smoke-test.sh"]
        })
        XCTAssertEqual(capabilities.schemaIDs.capabilities, "https://vifty.local/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.audit, "https://vifty.local/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.diagnose, "https://vifty.local/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.status, "https://vifty.local/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.commandError, "https://vifty.local/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.run, "https://vifty.local/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(capabilities.schemaIDs.agentRule, "https://vifty.local/schemas/viftyctl-agent-rule.schema.json")
    }

    func testAgentRuleExampleMatchesGeneratedReport() throws {
        let fixture = try decode(ViftyCtlAgentRuleReport.self, from: "agent-rule.json")
        let expected = ViftyAgentRule.report(generatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(fixture, expected)
    }

    func testWorkloadWrapperContractMatchesSourceScriptsAndSchema() throws {
        let sourceScripts = try sourceWorkloadWrapperScripts()
        let capabilities = try decode(ViftyCtlCapabilities.self, from: "capabilities.json")
        let schemaScripts = try capabilitiesSchemaWorkloadScripts()
        let templateScripts = ViftyCtlWorkloadTemplate.auditedTemplates.map(\.shortcutScript).sorted()

        XCTAssertEqual(ViftyCtlWrapperResources.workloadScriptNames.sorted(), sourceScripts)
        XCTAssertEqual(templateScripts, sourceScripts)
        XCTAssertEqual(capabilities.wrapperResources.workloadScripts.sorted(), sourceScripts)
        XCTAssertEqual(capabilities.workloadTemplates.map(\.shortcutScript).sorted(), sourceScripts)
        XCTAssertEqual(schemaScripts.sorted(), sourceScripts)
    }

    func testLegacyCapabilitiesPayloadDecodesWithConservativeDefaults() throws {
        var payload = try readJSON(fixtureURL("capabilities.json"))
        payload.removeValue(forKey: "supportsForceRetry")
        payload.removeValue(forKey: "runLifecycle")
        payload.removeValue(forKey: "directControlLifecycle")
        payload.removeValue(forKey: "metadataLimits")
        payload.removeValue(forKey: "policyStatusAvailable")
        payload.removeValue(forKey: "wrapperResources")
        payload.removeValue(forKey: "workloadTemplates")
        let data = try JSONSerialization.data(withJSONObject: payload)

        let capabilities = try JSONDecoder().decode(ViftyCtlCapabilities.self, from: data)

        XCTAssertFalse(capabilities.supportsForceRetry)
        XCTAssertEqual(capabilities.runLifecycle, .unsupported)
        XCTAssertEqual(capabilities.directControlLifecycle, .unsupported)
        XCTAssertEqual(capabilities.metadataLimits, .unsupported)
        XCTAssertFalse(capabilities.policyStatusAvailable)
        XCTAssertEqual(capabilities.wrapperResources, .unsupported)
        XCTAssertEqual(capabilities.workloadTemplates, [])
    }

    func testLegacyRunLifecycleDecodesWithoutResolvedExecutableReporting() throws {
        var payload = try readJSON(fixtureURL("capabilities.json"))
        var runLifecycle = try XCTUnwrap(payload["runLifecycle"] as? [String: Any])
        runLifecycle.removeValue(forKey: "resolvedChildExecutableReported")
        payload["runLifecycle"] = runLifecycle
        let data = try JSONSerialization.data(withJSONObject: payload)

        let capabilities = try JSONDecoder().decode(ViftyCtlCapabilities.self, from: data)

        XCTAssertTrue(capabilities.runLifecycle.childCommandPreflightBeforeCooling)
        XCTAssertFalse(capabilities.runLifecycle.resolvedChildExecutableReported)
    }

    func testDiagnoseReadyExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlReadinessReport.self, from: "diagnose-ready.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.state, .ready)
        XCTAssertEqual(report.recommendedAgentAction, .requestCooling)
        XCTAssertEqual(report.recommendedRecoveryAction, .none)
        XCTAssertEqual(report.recoverySteps, [])
        XCTAssertEqual(report.safeToRequestCooling, true)
        XCTAssertTrue(report.daemonControlPathReady)
        XCTAssertFalse(report.manualControlActive)
        XCTAssertEqual(report.failedCheckIDs, [])
        XCTAssertEqual(report.coolingBlockerIDs, [])
        XCTAssertEqual(report.appPreferences.startupMode, .auto)
        XCTAssertEqual(report.appPreferences.startupModeSource, .persisted)
        XCTAssertEqual(report.modelIdentifier, "MacBookPro18,3")
        XCTAssertEqual(report.thermalPressure, .nominal)
        XCTAssertEqual(report.controllableFanCount, 2)
        XCTAssertEqual(report.fans.map(\.id), [0, 1])
        XCTAssertEqual(report.fans.map(\.hardwareModeKey), ["F0Md", "F1md"])
        XCTAssertTrue(report.checks.contains { $0.id == "supportedHardware" && $0.passed })
        XCTAssertNil(report.daemonSnapshotError)
        XCTAssertNil(report.agentControlStatusError)
    }

    func testDiagnoseBlockedHelperUnreachableExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlReadinessReport.self, from: "diagnose-blocked-helper-unreachable.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.state, .blocked)
        XCTAssertEqual(report.recommendedAgentAction, .doNotRequestCooling)
        XCTAssertEqual(report.recommendedRecoveryAction, .repairHelper)
        XCTAssertEqual(report.recoverySteps, Self.repairHelperRecoverySteps)
        XCTAssertEqual(report.safeToRequestCooling, false)
        XCTAssertFalse(report.daemonControlPathReady)
        XCTAssertFalse(report.manualControlActive)
        XCTAssertEqual(report.failedCheckIDs, [
            "agentControlStatusAvailable",
            "daemonControlPathReady",
            "agentControlEnabled"
        ])
        XCTAssertEqual(report.coolingBlockerIDs, [
            "agentControlStatusAvailable",
            "daemonControlPathReady",
            "agentControlEnabled"
        ])
        XCTAssertEqual(report.modelIdentifier, "MacBookPro18,3")
        XCTAssertEqual(report.thermalPressure, .nominal)
        XCTAssertNil(report.daemonSnapshotError)
        XCTAssertNotNil(report.agentControlStatusError)
        XCTAssertFalse(report.agentControl.enabled)
        XCTAssertNil(report.agentControl.activeLease)
        XCTAssertEqual(report.agentControl.lastDecision?.errorCode, .helperUnreachable)
        XCTAssertEqual(report.agentControl.lastErrorCode, .helperUnreachable)
        try assertCheck("daemonSnapshotAvailable", in: report.checks, passed: true, severity: .info)
        try assertCheck("agentControlStatusAvailable", in: report.checks, passed: false, severity: .error)
        try assertCheck("daemonControlPathReady", in: report.checks, passed: false, severity: .error)
        try assertCheck("agentControlEnabled", in: report.checks, passed: false, severity: .error)
        try assertCheck("fanModeTelemetry", in: report.checks, passed: true, severity: .info)
    }

    func testDiagnoseDegradedActiveLeaseExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlReadinessReport.self, from: "diagnose-degraded-active-lease.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.state, .degraded)
        XCTAssertEqual(report.recommendedAgentAction, .restoreAutoBeforeRequestingCooling)
        XCTAssertEqual(report.recommendedRecoveryAction, .restoreAutoBeforeRetry)
        XCTAssertEqual(report.recoverySteps, Self.restoreAutoRecoverySteps)
        XCTAssertEqual(report.safeToRequestCooling, false)
        XCTAssertTrue(report.daemonControlPathReady)
        XCTAssertFalse(report.manualControlActive)
        XCTAssertEqual(report.failedCheckIDs, ["activeLeaseClear"])
        XCTAssertEqual(report.coolingBlockerIDs, ["activeLeaseClear"])
        XCTAssertEqual(report.thermalPressure, .nominal)
        XCTAssertTrue(report.agentControl.enabled)
        XCTAssertEqual(report.agentControl.activeLease?.id, "lease-example-test")
        XCTAssertEqual(report.agentControl.activeLease?.request.workload, .test)
        XCTAssertEqual(report.agentControl.activeLease?.targetRPMByFanID[0], 3600)
        XCTAssertNil(report.agentControl.lastErrorCode)
        try assertCheck("daemonControlPathReady", in: report.checks, passed: true, severity: .error)
        try assertCheck("agentControlEnabled", in: report.checks, passed: true, severity: .error)
        try assertCheck("activeLeaseClear", in: report.checks, passed: false, severity: .warning)
        try assertCheck("thermalPressureSafe", in: report.checks, passed: true, severity: .info)
    }

    func testDiagnoseDegradedManualControlExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlReadinessReport.self, from: "diagnose-degraded-manual-control.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.state, .degraded)
        XCTAssertEqual(report.recommendedAgentAction, .restoreAutoBeforeRequestingCooling)
        XCTAssertEqual(report.recommendedRecoveryAction, .restoreAutoBeforeRetry)
        XCTAssertEqual(report.recoverySteps, Self.restoreAutoRecoverySteps)
        XCTAssertEqual(report.safeToRequestCooling, false)
        XCTAssertTrue(report.daemonControlPathReady)
        XCTAssertTrue(report.manualControlActive)
        XCTAssertEqual(report.failedCheckIDs, ["manualControlClear"])
        XCTAssertEqual(report.coolingBlockerIDs, ["manualControlClear"])
        XCTAssertEqual(report.appPreferences.startupMode, .curve)
        XCTAssertEqual(report.appPreferences.startupModeSource, .persisted)
        XCTAssertEqual(report.thermalPressure, .nominal)
        XCTAssertEqual(report.controllableFanCount, 2)
        XCTAssertEqual(report.fans.map(\.hardwareMode), ["Forced", "Forced"])
        XCTAssertEqual(report.fans.map(\.hardwareModeRawValue), [1, 1])
        XCTAssertTrue(report.agentControl.enabled)
        XCTAssertNil(report.agentControl.activeLease)
        XCTAssertNil(report.agentControl.lastErrorCode)
        try assertCheck("daemonControlPathReady", in: report.checks, passed: true, severity: .error)
        try assertCheck("activeLeaseClear", in: report.checks, passed: true, severity: .warning)
        try assertCheck("manualControlClear", in: report.checks, passed: false, severity: .warning)
        XCTAssertTrue(report.checks.contains { check in
            check.id == "manualControlClear"
                && check.message.contains("re-run diagnose")
                && check.message.contains("switch Vifty/default mode to Auto")
        })
        try assertCheck("fanModeTelemetry", in: report.checks, passed: true, severity: .info)
    }

    func testDiagnoseDegradedCautionExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlReadinessReport.self, from: "diagnose-degraded-caution.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.state, .degraded)
        XCTAssertEqual(report.recommendedAgentAction, .requestCoolingWithCaution)
        XCTAssertEqual(report.recommendedRecoveryAction, .none)
        XCTAssertEqual(report.recoverySteps, [])
        XCTAssertEqual(report.safeToRequestCooling, true)
        XCTAssertTrue(report.daemonControlPathReady)
        XCTAssertFalse(report.manualControlActive)
        XCTAssertEqual(report.failedCheckIDs, ["thermalPressureSafe"])
        XCTAssertEqual(report.coolingBlockerIDs, [])
        XCTAssertEqual(report.thermalPressure, .serious)
        XCTAssertTrue(report.agentControl.enabled)
        XCTAssertNil(report.agentControl.activeLease)
        XCTAssertNil(report.agentControl.lastErrorCode)
        try assertCheck("daemonControlPathReady", in: report.checks, passed: true, severity: .error)
        try assertCheck("activeLeaseClear", in: report.checks, passed: true, severity: .warning)
        try assertCheck("thermalPressureSafe", in: report.checks, passed: false, severity: .warning)
        try assertCheck("fanModeTelemetry", in: report.checks, passed: true, severity: .info)
    }

    func testDiagnoseLegacyPayloadDecodesWithRecoveryDefault() throws {
        var payload = try readJSON(fixtureURL("diagnose-ready.json"))
        payload.removeValue(forKey: "recommendedRecoveryAction")
        payload.removeValue(forKey: "recoverySteps")
        payload.removeValue(forKey: "daemonControlPathReady")
        payload.removeValue(forKey: "manualControlActive")
        payload.removeValue(forKey: "appPreferences")
        payload.removeValue(forKey: "failedCheckIDs")
        payload.removeValue(forKey: "coolingBlockerIDs")
        let data = try JSONSerialization.data(withJSONObject: payload)

        let report = try JSONDecoder().decode(ViftyCtlReadinessReport.self, from: data)

        XCTAssertEqual(report.state, .ready)
        XCTAssertEqual(report.recommendedAgentAction, .requestCooling)
        XCTAssertEqual(report.recommendedRecoveryAction, .none)
        XCTAssertEqual(report.recoverySteps, [])
        XCTAssertEqual(report.safeToRequestCooling, true)
        XCTAssertTrue(report.daemonControlPathReady)
        XCTAssertFalse(report.manualControlActive)
        XCTAssertEqual(report.appPreferences, .unavailable)
        XCTAssertEqual(report.failedCheckIDs, [])
        XCTAssertEqual(report.coolingBlockerIDs, [])
    }

    func testStatusActiveLeaseExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlStatusReport.self, from: "status-active-lease.json")
        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.schemaID, "https://vifty.local/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(report.generatedAt, Date(timeIntervalSinceReferenceDate: 700_000_900))
        XCTAssertEqual(report.activeLease?.id, "lease-example-test")

        let status = try decode(AgentControlStatus.self, from: "status-active-lease.json")

        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.activeLease?.id, "lease-example-test")
        XCTAssertEqual(status.activeLease?.request.workload, .test)
        XCTAssertEqual(status.activeLease?.targetRPMByFanID[0], 3600)
        XCTAssertEqual(status.lastDecision?.allowed, true)
        XCTAssertEqual(status.lastDecision?.targetRPMByFanID[1], 3700)
        XCTAssertNil(status.lastErrorCode)
    }

    func testCommandErrorExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlCommandErrorReport.self, from: "command-error.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.schemaID, "https://vifty.local/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(report.command, "prepare")
        XCTAssertEqual(report.errorCode, .prepareRateLimited)
        XCTAssertFalse(report.safeToProceed)
        XCTAssertEqual(report.recommendedRecoveryAction, .waitBeforeRetry)
        XCTAssertEqual(report.recoverySteps, Self.waitBeforeRetryRecoverySteps)
        XCTAssertFalse(report.coolingLeasePrepared)
        XCTAssertFalse(report.autoRestoreAttempted)
        XCTAssertNil(report.autoRestoreSucceeded)
        XCTAssertEqual(report.retryAfterSeconds, 20)
        XCTAssertTrue(report.message.contains("Wait 20s"))
    }

    func testCommandErrorLegacyPayloadDecodesWithLifecycleDefaults() throws {
        let data = Data("""
        {
          "command": "prepare",
          "errorCode": "HELPER_UNREACHABLE",
          "generatedAt": 700000000,
          "message": "daemon unavailable",
          "safeToProceed": false,
          "schemaVersion": 1
        }
        """.utf8)

        let report = try JSONDecoder().decode(ViftyCtlCommandErrorReport.self, from: data)

        XCTAssertEqual(report.command, "prepare")
        XCTAssertEqual(report.schemaID, "https://vifty.local/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(report.errorCode, .helperUnreachable)
        XCTAssertFalse(report.safeToProceed)
        XCTAssertEqual(report.recommendedRecoveryAction, .repairHelper)
        XCTAssertEqual(report.recoverySteps, Self.repairHelperRecoverySteps)
        XCTAssertFalse(report.coolingLeasePrepared)
        XCTAssertFalse(report.autoRestoreAttempted)
        XCTAssertNil(report.autoRestoreSucceeded)
        XCTAssertNil(report.retryAfterSeconds)
    }

    func testRunCommandErrorExamplesDecodeAgainstCurrentModel() throws {
        let preflight = try decode(ViftyCtlCommandErrorReport.self, from: "command-error-run-child-command-failed.json")
        XCTAssertEqual(preflight.schemaID, "https://vifty.local/schemas/viftyctl-command-error.schema.json")
        XCTAssertEqual(preflight.command, "run")
        XCTAssertEqual(preflight.errorCode, .childCommandFailed)
        XCTAssertFalse(preflight.safeToProceed)
        XCTAssertEqual(preflight.recommendedRecoveryAction, .fixChildCommand)
        XCTAssertEqual(preflight.recoverySteps, Self.fixChildCommandRecoverySteps)
        XCTAssertFalse(preflight.coolingLeasePrepared)
        XCTAssertFalse(preflight.autoRestoreAttempted)
        XCTAssertNil(preflight.autoRestoreSucceeded)

        let restored = try decode(ViftyCtlCommandErrorReport.self, from: "command-error-run-cleanup-restored.json")
        XCTAssertEqual(restored.command, "run")
        XCTAssertEqual(restored.errorCode, .childCommandFailed)
        XCTAssertFalse(restored.safeToProceed)
        XCTAssertEqual(restored.recommendedRecoveryAction, .fixChildCommand)
        XCTAssertEqual(restored.recoverySteps, Self.fixChildCommandRecoverySteps)
        XCTAssertTrue(restored.coolingLeasePrepared)
        XCTAssertTrue(restored.autoRestoreAttempted)
        XCTAssertEqual(restored.autoRestoreSucceeded, true)

        let failed = try decode(ViftyCtlCommandErrorReport.self, from: "command-error-run-cleanup-failed.json")
        XCTAssertEqual(failed.command, "run")
        XCTAssertEqual(failed.errorCode, .restoreFailed)
        XCTAssertFalse(failed.safeToProceed)
        XCTAssertEqual(failed.recommendedRecoveryAction, .runDiagnose)
        XCTAssertEqual(failed.recoverySteps, Self.runDiagnoseRecoverySteps)
        XCTAssertTrue(failed.coolingLeasePrepared)
        XCTAssertTrue(failed.autoRestoreAttempted)
        XCTAssertEqual(failed.autoRestoreSucceeded, false)
    }

    func testRunSuccessExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlRunReport.self, from: "run-success.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertEqual(report.schemaID, "https://vifty.local/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(report.command, "run")
        XCTAssertTrue(report.coolingLeasePrepared)
        XCTAssertTrue(report.autoRestoreAttempted)
        XCTAssertEqual(report.autoRestoreSucceeded, true)
        XCTAssertEqual(report.childExitCode, 0)
        XCTAssertNil(report.autoRestoreError)
        XCTAssertEqual(report.resolvedChildExecutable, "/usr/bin/true")
        XCTAssertNil(report.resolvedChildExecutableSHA256)
        XCTAssertEqual(report.resolvedChildExecutableSHA256Status, .unavailable)
    }

    func testAuditExampleDecodesAgainstCurrentModel() throws {
        let report = try decode(ViftyCtlAuditReport.self, from: "audit.json")

        XCTAssertEqual(report.schemaVersion, 1)
        XCTAssertTrue(report.readOnly)
        XCTAssertFalse(report.coolingCommandsRun)
        XCTAssertEqual(report.limit, 20)
        XCTAssertEqual(report.eventCount, 2)
        XCTAssertEqual(report.events.map(\.action), ["prepare", "restore-auto"])
        XCTAssertEqual(report.events.first?.leaseID, "lease-example-test")
    }

    func testDiagnoseSchemaDocumentsRequiredSafetyContract() throws {
        let schema = try readJSON(schemaURL("viftyctl-diagnose.schema.json"))
        XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")

        let required = try XCTUnwrap(schema["required"] as? [String])
        for field in [
            "schemaVersion",
            "state",
            "recommendedAgentAction",
            "recommendedRecoveryAction",
            "safeToRequestCooling",
            "daemonControlPathReady",
            "manualControlActive",
            "daemonRuntime",
            "isAppleSilicon",
            "isMacBookPro",
            "thermalPressure",
            "fanCount",
            "controllableFanCount",
            "temperatureSensorCount",
            "fans",
            "temperatureSensors",
            "agentControl",
            "checks"
        ] {
            XCTAssertTrue(required.contains(field), "schema should require \(field)")
        }

        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let appPreferencesProperty = try XCTUnwrap(properties["appPreferences"] as? [String: Any])
        XCTAssertEqual(appPreferencesProperty["$ref"] as? String, "#/$defs/appPreferencesDiagnostic")
        let daemonRuntimeProperty = try XCTUnwrap(properties["daemonRuntime"] as? [String: Any])
        XCTAssertEqual(daemonRuntimeProperty["$ref"] as? String, "#/$defs/daemonRuntimeDiagnostic")
        XCTAssertNotNil(properties["failedCheckIDs"])
        XCTAssertNotNil(properties["coolingBlockerIDs"])
        let recoverySteps = try XCTUnwrap(properties["recoverySteps"] as? [String: Any])
        XCTAssertEqual(recoverySteps["type"] as? String, "array")
        let recoveryStepItems = try XCTUnwrap(recoverySteps["items"] as? [String: Any])
        XCTAssertEqual(recoveryStepItems["type"] as? String, "string")
        let operatorRecoveryCommands = try XCTUnwrap(properties["operatorRecoveryCommands"] as? [String: Any])
        XCTAssertEqual(operatorRecoveryCommands["type"] as? String, "array")
        let operatorRecoveryCommandItems = try XCTUnwrap(operatorRecoveryCommands["items"] as? [String: Any])
        XCTAssertEqual(operatorRecoveryCommandItems["$ref"] as? String, "#/$defs/operatorRecoveryCommand")
        XCTAssertFalse(required.contains("recoverySteps"))
        XCTAssertFalse(required.contains("operatorRecoveryCommands"))
        XCTAssertEqual(enumValues(named: "state", in: properties), ["ready", "degraded", "blocked"])
        XCTAssertEqual(enumValues(named: "recommendedAgentAction", in: properties), [
            "requestCooling",
            "requestCoolingWithCaution",
            "restoreAutoBeforeRequestingCooling",
            "doNotRequestCooling"
        ])
        XCTAssertEqual(enumValues(named: "recommendedRecoveryAction", in: properties), [
            "none",
            "repairHelper",
            "restoreAutoBeforeRetry",
            "backOffWorkload",
            "inspectPolicy",
            "collectHardwareEvidence"
        ])
        XCTAssertEqual(enumValues(named: "thermalPressure", in: properties), [
            "nominal",
            "fair",
            "serious",
            "critical",
            "unknown"
        ])

        let definitions = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let appPreferences = try XCTUnwrap(definitions["appPreferencesDiagnostic"] as? [String: Any])
        let appPreferencesRequired = try XCTUnwrap(appPreferences["required"] as? [String])
        XCTAssertEqual(appPreferencesRequired, ["startupMode", "startupModeSource", "readError"])
        let appPreferencesProperties = try XCTUnwrap(appPreferences["properties"] as? [String: Any])
        let startupModeProperty = try XCTUnwrap(appPreferencesProperties["startupMode"] as? [String: Any])
        let startupModeEnum = try XCTUnwrap(startupModeProperty["enum"] as? [Any])
        XCTAssertEqual(startupModeEnum.compactMap { $0 as? String }, ["Auto", "Curve", "Fixed"])
        XCTAssertTrue(startupModeEnum.contains { $0 is NSNull })
        XCTAssertEqual(enumValues(named: "startupModeSource", in: appPreferencesProperties), [
            "persisted",
            "defaultMissingFile",
            "defaultMissingKey",
            "unreadable",
            "unavailable"
        ])
        let daemonRuntime = try XCTUnwrap(definitions["daemonRuntimeDiagnostic"] as? [String: Any])
        let daemonRuntimeRequired = try XCTUnwrap(daemonRuntime["required"] as? [String])
        XCTAssertEqual(daemonRuntimeRequired, [
            "installedDaemonPath",
            "installedDaemonPresent",
            "installedDaemonSHA256",
            "expectedDaemonPath",
            "expectedDaemonPresent",
            "expectedDaemonSHA256",
            "matchesExpectedDaemon",
            "matchRequired"
        ])
        let daemonRuntimeProperties = try XCTUnwrap(daemonRuntime["properties"] as? [String: Any])
        XCTAssertEqual((daemonRuntimeProperties["installedDaemonSHA256"] as? [String: Any])?["pattern"] as? String, "^[a-f0-9]{64}$")
        XCTAssertEqual((daemonRuntimeProperties["expectedDaemonSHA256"] as? [String: Any])?["pattern"] as? String, "^[a-f0-9]{64}$")
        let operatorRecoveryCommand = try XCTUnwrap(definitions["operatorRecoveryCommand"] as? [String: Any])
        let operatorRecoveryCommandRequired = try XCTUnwrap(operatorRecoveryCommand["required"] as? [String])
        XCTAssertEqual(operatorRecoveryCommandRequired, [
            "id",
            "title",
            "command",
            "workingDirectoryHint",
            "requiresUserApproval",
            "safeForAgentsToRunAutomatically",
            "notes"
        ])
        let operatorRecoveryCommandProperties = try XCTUnwrap(operatorRecoveryCommand["properties"] as? [String: Any])
        XCTAssertEqual(enumValues(named: "id", in: operatorRecoveryCommandProperties), ["repair-helper-current-app"])
        XCTAssertEqual(
            (operatorRecoveryCommandProperties["safeForAgentsToRunAutomatically"] as? [String: Any])?["const"] as? Bool,
            false
        )
        let readinessCheck = try XCTUnwrap(definitions["readinessCheck"] as? [String: Any])
        let checkProperties = try XCTUnwrap(readinessCheck["properties"] as? [String: Any])
        XCTAssertEqual(enumValues(named: "severity", in: checkProperties), ["info", "warning", "error"])
        let checkIDProperty = try XCTUnwrap(checkProperties["id"] as? [String: Any])
        XCTAssertEqual(checkIDProperty["$ref"] as? String, "#/$defs/readinessCheckID")
        let readinessCheckID = try XCTUnwrap(definitions["readinessCheckID"] as? [String: Any])
        XCTAssertEqual(readinessCheckID["enum"] as? [String], [
            "daemonSnapshotAvailable",
            "agentControlStatusAvailable",
            "daemonControlPathReady",
            "daemonRuntimeMatchesExpected",
            "supportedHardware",
            "agentControlEnabled",
            "temperatureSensorsPresent",
            "controllableFansPresent",
            "fanIDsValid",
            "fanIDsUnique",
            "fanRangesValid",
            "thermalPressureSafe",
            "activeLeaseClear",
            "manualControlClear",
            "fanModeTelemetry"
        ])

        let fanRequired = try requiredFields(for: "fanReport", in: definitions)
        let checkRequired = try XCTUnwrap(readinessCheck["required"] as? [String])
        for exampleFilename in try diagnoseExampleFilenames() {
            let example = try readJSON(fixtureURL(exampleFilename))
            for field in required {
                XCTAssertNotNil(example[field], "\(exampleFilename) should include required schema field \(field)")
            }
            let fans = try XCTUnwrap(example["fans"] as? [[String: Any]])
            for field in fanRequired {
                XCTAssertNotNil(fans.first?[field], "\(exampleFilename) fan should include \(field)")
            }
            let checks = try XCTUnwrap(example["checks"] as? [[String: Any]])
            for field in checkRequired {
                XCTAssertNotNil(checks.first?[field], "\(exampleFilename) check should include \(field)")
            }
        }
    }

    func testDiagnoseExamplesIncludeDerivedCheckIDLists() throws {
        for exampleFilename in try diagnoseExampleFilenames() {
            let example = try readJSON(fixtureURL(exampleFilename))
            let checks = try XCTUnwrap(example["checks"] as? [[String: Any]])
            let failedIDs = checks
                .filter { ($0["passed"] as? Bool) == false }
                .compactMap { $0["id"] as? String }
            let blockerIDs = checks
                .filter { check in
                    guard (check["passed"] as? Bool) == false,
                          let id = check["id"] as? String,
                          let severity = check["severity"] as? String else {
                        return false
                    }
                    return severity == "error" || ["activeLeaseClear", "manualControlClear"].contains(id)
                }
                .compactMap { $0["id"] as? String }

            XCTAssertEqual(example["failedCheckIDs"] as? [String], failedIDs, exampleFilename)
            XCTAssertEqual(example["coolingBlockerIDs"] as? [String], blockerIDs, exampleFilename)
            XCTAssertNotNil(example["recoverySteps"] as? [String], "\(exampleFilename) should include recoverySteps")
        }
    }

    func testAgentSchemasDocumentCanonicalPayloads() throws {
        let examplesReadme = try String(contentsOf: fixtureURL("README.md"), encoding: .utf8)
        let schemaExamples = [
            ("viftyctl-audit.schema.json", "audit.json"),
            ("viftyctl-agent-rule.schema.json", "agent-rule.json"),
            ("viftyctl-capabilities.schema.json", "capabilities.json"),
            ("viftyctl-command-error.schema.json", "command-error.json"),
            ("viftyctl-command-error.schema.json", "command-error-run-child-command-failed.json"),
            ("viftyctl-command-error.schema.json", "command-error-run-cleanup-restored.json"),
            ("viftyctl-command-error.schema.json", "command-error-run-cleanup-failed.json"),
            ("viftyctl-diagnose.schema.json", "diagnose-ready.json"),
            ("viftyctl-diagnose.schema.json", "diagnose-blocked-helper-unreachable.json"),
            ("viftyctl-diagnose.schema.json", "diagnose-degraded-active-lease.json"),
            ("viftyctl-diagnose.schema.json", "diagnose-degraded-manual-control.json"),
            ("viftyctl-diagnose.schema.json", "diagnose-degraded-caution.json"),
            ("viftyctl-status.schema.json", "status-active-lease.json")
        ]

        for (schemaFilename, exampleFilename) in schemaExamples {
            XCTAssertTrue(examplesReadme.contains(schemaFilename))
            let schema = try readJSON(schemaURL(schemaFilename))
            XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")

            let required = try XCTUnwrap(schema["required"] as? [String])
            let example = try readJSON(fixtureURL(exampleFilename))
            for field in required {
                XCTAssertNotNil(
                    example[field],
                    "\(exampleFilename) should include required schema field \(field)"
                )
            }
        }

        let capabilitiesSchema = try readJSON(schemaURL("viftyctl-capabilities.schema.json"))
        let capabilitiesExample = try readJSON(fixtureURL("capabilities.json"))
        let capabilitiesRequired = try XCTUnwrap(capabilitiesSchema["required"] as? [String])
        XCTAssertTrue(capabilitiesRequired.contains("policyStatusAvailable"))
        XCTAssertTrue(capabilitiesRequired.contains("wrapperResources"))
        XCTAssertEqual(capabilitiesExample["policyStatusAvailable"] as? Bool, true)
        let capabilitiesProperties = try XCTUnwrap(capabilitiesSchema["properties"] as? [String: Any])
        let policyStatusAvailable = try XCTUnwrap(capabilitiesProperties["policyStatusAvailable"] as? [String: Any])
        XCTAssertEqual(policyStatusAvailable["type"] as? String, "boolean")
        let commandItems = try XCTUnwrap((capabilitiesProperties["commands"] as? [String: Any])?["items"] as? [String: Any])
        XCTAssertEqual(commandItems["enum"] as? [String], ["status", "capabilities", "agent-rule", "diagnose", "audit", "prepare", "restore-auto", "run"])
        XCTAssertEqual(enumValues(named: "policySource", in: capabilitiesProperties), ["daemonStatus", "fallbackUnavailable"])
        let capabilitiesDefinitions = try XCTUnwrap(capabilitiesSchema["$defs"] as? [String: Any])
        XCTAssertEqual(definitionEnumValues(named: "workload", in: capabilitiesDefinitions), ["build", "test", "render", "localModel", "custom"])
        let wrapperResourcesDefinition = try XCTUnwrap(capabilitiesDefinitions["wrapperResources"] as? [String: Any])
        let wrapperResourceProperties = try XCTUnwrap(wrapperResourcesDefinition["properties"] as? [String: Any])
        let workloadScriptsSchema = try XCTUnwrap(wrapperResourceProperties["workloadScripts"] as? [String: Any])
        let workloadScriptConstraints = try XCTUnwrap(workloadScriptsSchema["allOf"] as? [[String: Any]])
        for script in ViftyCtlWrapperResources.workloadScriptNames {
            XCTAssertTrue(workloadScriptConstraints.containsRequiredString(script), "Missing required capabilities wrapper script \(script)")
        }
        try assertRequiredFields(
            definition: "policy",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["policy"] as? [String: Any],
            context: "capabilities policy"
        )
        try assertRequiredFields(
            definition: "exitCodes",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["exitCodes"] as? [String: Any],
            context: "capabilities exitCodes"
        )
        try assertRequiredFields(
            definition: "runLifecycle",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["runLifecycle"] as? [String: Any],
            context: "capabilities runLifecycle"
        )
        try assertRequiredFields(
            definition: "directControlLifecycle",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["directControlLifecycle"] as? [String: Any],
            context: "capabilities directControlLifecycle"
        )
        try assertRequiredFields(
            definition: "metadataLimits",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["metadataLimits"] as? [String: Any],
            context: "capabilities metadataLimits"
        )
        try assertRequiredFields(
            definition: "wrapperResources",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["wrapperResources"] as? [String: Any],
            context: "capabilities wrapperResources"
        )
        let workloadTemplates = try XCTUnwrap(capabilitiesExample["workloadTemplates"] as? [[String: Any]])
        for template in workloadTemplates {
            try assertRequiredFields(
                definition: "workloadTemplate",
                in: capabilitiesDefinitions,
                arePresentIn: template,
                context: "capabilities workloadTemplate"
            )
        }
        let workloadTemplateDefinition = try XCTUnwrap(capabilitiesDefinitions["workloadTemplate"] as? [String: Any])
        let workloadTemplateProperties = try XCTUnwrap(workloadTemplateDefinition["properties"] as? [String: Any])
        let shortcutScript = try XCTUnwrap(workloadTemplateProperties["shortcutScript"] as? [String: Any])
        XCTAssertEqual((shortcutScript["enum"] as? [String])?.sorted(), try sourceWorkloadWrapperScripts())
        try assertRequiredFields(
            definition: "schemaPathReferences",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["schemas"] as? [String: Any],
            context: "capabilities schemas"
        )
        try assertRequiredFields(
            definition: "schemaResourceReferences",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["schemaResources"] as? [String: Any],
            context: "capabilities schemaResources"
        )
        try assertRequiredFields(
            definition: "schemaIDReferences",
            in: capabilitiesDefinitions,
            arePresentIn: capabilitiesExample["schemaIDs"] as? [String: Any],
            context: "capabilities schemaIDs"
        )

        let runSchema = try readJSON(schemaURL("viftyctl-run.schema.json"))
        let runProperties = try XCTUnwrap(runSchema["properties"] as? [String: Any])
        XCTAssertEqual((runProperties["schemaID"] as? [String: Any])?["const"] as? String, "https://vifty.local/schemas/viftyctl-run.schema.json")
        XCTAssertEqual((runProperties["command"] as? [String: Any])?["const"] as? String, "run")
        XCTAssertNotNil(runProperties["coolingLeasePrepared"] as? [String: Any])
        XCTAssertNotNil(runProperties["autoRestoreAttempted"] as? [String: Any])
        XCTAssertNotNil(runProperties["autoRestoreSucceeded"] as? [String: Any])
        XCTAssertNotNil(runProperties["childExitCode"] as? [String: Any])
        let childTerminationReason = try XCTUnwrap(runProperties["childTerminationReason"] as? [String: Any])
        XCTAssertEqual(childTerminationReason["enum"] as? [String], ["exited", "signalInferred"])
        XCTAssertNotNil(runProperties["childSignal"] as? [String: Any])
        XCTAssertNotNil(runProperties["childSignalName"] as? [String: Any])
        XCTAssertNotNil(runProperties["resolvedChildExecutable"] as? [String: Any])
        let executableDigest = try XCTUnwrap(runProperties["resolvedChildExecutableSHA256"] as? [String: Any])
        XCTAssertEqual(executableDigest["pattern"] as? String, "^[a-f0-9]{64}$")
        let executableDigestStatus = try XCTUnwrap(runProperties["resolvedChildExecutableSHA256Status"] as? [String: Any])
        XCTAssertEqual(executableDigestStatus["enum"] as? [String], ["computed", "unavailable"])
        let runExample = try readJSON(fixtureURL("run-success.json"))
        XCTAssertEqual(runExample["schemaVersion"] as? Int, 1)
        XCTAssertEqual(runExample["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-run.schema.json")
        XCTAssertEqual(runExample["command"] as? String, "run")
        XCTAssertEqual(runExample["coolingLeasePrepared"] as? Bool, true)
        XCTAssertEqual(runExample["autoRestoreAttempted"] as? Bool, true)
        XCTAssertEqual(runExample["autoRestoreSucceeded"] as? Bool, true)
        XCTAssertEqual(runExample["childExitCode"] as? Int, 0)
        XCTAssertEqual(runExample["childTerminationReason"] as? String, "exited")
        XCTAssertEqual(runExample["resolvedChildExecutableSHA256Status"] as? String, "unavailable")
        XCTAssertEqual(runExample["resolvedChildExecutable"] as? String, "/usr/bin/true")

        let agentRuleSchema = try readJSON(schemaURL("viftyctl-agent-rule.schema.json"))
        let agentRuleProperties = try XCTUnwrap(agentRuleSchema["properties"] as? [String: Any])
        XCTAssertEqual((agentRuleProperties["schemaID"] as? [String: Any])?["const"] as? String, "https://vifty.local/schemas/viftyctl-agent-rule.schema.json")
        XCTAssertEqual((agentRuleProperties["command"] as? [String: Any])?["const"] as? String, "agent-rule")
        XCTAssertEqual((agentRuleProperties["guardedRunDecisionSchemaID"] as? [String: Any])?["const"] as? String, "https://vifty.local/schemas/guarded-run-decision.schema.json")
        let strictDiagnoseCommandSchema = try XCTUnwrap(agentRuleProperties["strictDiagnoseCommand"] as? [String: Any])
        XCTAssertEqual(strictDiagnoseCommandSchema["type"] as? String, "string")
        let repairHelperRecoveryActionsSchema = try XCTUnwrap(agentRuleProperties["repairHelperRecoveryActions"] as? [String: Any])
        let repairHelperRecoveryConstraints = try XCTUnwrap(repairHelperRecoveryActionsSchema["allOf"] as? [[String: Any]])
        for action in ViftyAgentRule.repairHelperRecoveryActions {
            XCTAssertTrue(repairHelperRecoveryConstraints.containsRequiredString(action))
        }
        let markerProperties = try XCTUnwrap(agentRuleProperties["guardedRunJSONMarkers"] as? [String: Any])
        XCTAssertEqual(markerProperties["additionalProperties"] as? Bool, false)
        let schemaRequirementsSchema = try XCTUnwrap(agentRuleProperties["schemaRequirements"] as? [String: Any])
        let schemaRequirementConstraints = try XCTUnwrap(schemaRequirementsSchema["allOf"] as? [[String: Any]])
        XCTAssertTrue(schemaRequirementConstraints.containsRequiredString("schemaIDs.agentRule"))
        XCTAssertTrue(schemaRequirementConstraints.containsRequiredString("guardedRunDecisionSchemaID"))
        XCTAssertTrue(schemaRequirementConstraints.containsRequiredString("guardedRunJSONMarkers"))
        let safetyRequirementsSchema = try XCTUnwrap(agentRuleProperties["safetyRequirements"] as? [String: Any])
        let safetyRequirementConstraints = try XCTUnwrap(safetyRequirementsSchema["allOf"] as? [[String: Any]])
        XCTAssertTrue(safetyRequirementConstraints.containsRequiredString("policyStatusAvailable == true"))
        XCTAssertTrue(safetyRequirementConstraints.containsRequiredString("policy.enabled == true"))
        XCTAssertTrue(safetyRequirementConstraints.containsRequiredString("safeToRequestCooling == true"))
        XCTAssertTrue(safetyRequirementConstraints.containsRequiredString("daemonControlPathReady == true"))
        XCTAssertTrue(safetyRequirementConstraints.containsRequiredString("manualControlActive == false"))
        XCTAssertTrue(safetyRequirementConstraints.containsRequiredString("daemonRuntime.matchRequired != true || daemonRuntime.matchesExpectedDaemon == true"))
        XCTAssertTrue(safetyRequirementConstraints.containsRequiredString("coolingBlockerIDs is empty"))
        let forbiddenActionsSchema = try XCTUnwrap(agentRuleProperties["forbiddenActions"] as? [String: Any])
        let forbiddenActionConstraints = try XCTUnwrap(forbiddenActionsSchema["allOf"] as? [[String: Any]])
        XCTAssertTrue(forbiddenActionConstraints.containsRequiredString("ViftyHelper setFixed"))
        XCTAssertTrue(forbiddenActionConstraints.containsRequiredString("ViftyHelper auto"))
        XCTAssertTrue(forbiddenActionConstraints.containsRequiredString("sudo"))
        XCTAssertTrue(forbiddenActionConstraints.containsRequiredString("raw SMC tools"))
        XCTAssertTrue(forbiddenActionConstraints.containsRequiredString("direct fan RPM writes"))
        XCTAssertTrue(forbiddenActionConstraints.containsRequiredString("unguarded viftyctl prepare"))
        let workloadTemplateIDsSchema = try XCTUnwrap(agentRuleProperties["workloadTemplateIDs"] as? [String: Any])
        let workloadTemplateIDConstraints = try XCTUnwrap(workloadTemplateIDsSchema["allOf"] as? [[String: Any]])
        let auditedWorkloadTemplateIDs = ViftyCtlWorkloadTemplate.auditedTemplates.map(\.id)
        for templateID in auditedWorkloadTemplateIDs {
            XCTAssertTrue(workloadTemplateIDConstraints.containsRequiredString(templateID), "Missing required agent-rule workload template ID \(templateID)")
        }
        let agentRuleExample = try readJSON(fixtureURL("agent-rule.json"))
        XCTAssertEqual(agentRuleExample["schemaVersion"] as? Int, 1)
        XCTAssertEqual(agentRuleExample["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-agent-rule.schema.json")
        XCTAssertEqual(agentRuleExample["command"] as? String, "agent-rule")
        XCTAssertEqual(agentRuleExample["guardedRunDecisionSchemaID"] as? String, "https://vifty.local/schemas/guarded-run-decision.schema.json")
        XCTAssertEqual(
            agentRuleExample["strictDiagnoseCommand"] as? String,
            "'/Applications/Vifty.app/Contents/MacOS/viftyctl' diagnose --json --require-safe"
        )
        XCTAssertEqual(agentRuleExample["repairHelperRecoveryActions"] as? [String], ViftyAgentRule.repairHelperRecoveryActions)
        let markerExample = try XCTUnwrap(agentRuleExample["guardedRunJSONMarkers"] as? [String: Any])
        let capabilitiesMarker = try XCTUnwrap(markerExample["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilitiesMarker["begin"] as? String, "guarded-run: BEGIN_VIFTY_CAPABILITIES_JSON")
        XCTAssertEqual(capabilitiesMarker["end"] as? String, "guarded-run: END_VIFTY_CAPABILITIES_JSON")
        let diagnoseMarker = try XCTUnwrap(markerExample["diagnose"] as? [String: Any])
        XCTAssertEqual(diagnoseMarker["begin"] as? String, "guarded-run: BEGIN_VIFTY_DIAGNOSE_JSON")
        XCTAssertEqual(diagnoseMarker["end"] as? String, "guarded-run: END_VIFTY_DIAGNOSE_JSON")
        let decisionMarker = try XCTUnwrap(markerExample["decision"] as? [String: Any])
        XCTAssertEqual(decisionMarker["begin"] as? String, "guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON")
        XCTAssertEqual(decisionMarker["end"] as? String, "guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON")
        XCTAssertTrue((agentRuleExample["rule"] as? String)?.contains("safeToRequestCooling") == true)
        XCTAssertTrue((agentRuleExample["rule"] as? String)?.contains("daemonRuntime.matchRequired") == true)
        XCTAssertTrue((agentRuleExample["rule"] as? String)?.contains("diagnose --json --require-safe") == true)
        XCTAssertTrue((agentRuleExample["rule"] as? String)?.contains("exits with blocked-readiness code `75`") == true)
        XCTAssertTrue((agentRuleExample["safetyRequirements"] as? [String])?.contains("daemonRuntime.matchRequired != true || daemonRuntime.matchesExpectedDaemon == true") == true)
        XCTAssertTrue((agentRuleExample["rule"] as? String)?.contains("include `decisionReason` and `recoverySteps`") == true)
        XCTAssertTrue((agentRuleExample["schemaRequirements"] as? [String])?.contains("schemaIDs.agentRule") == true)
        XCTAssertTrue((agentRuleExample["schemaRequirements"] as? [String])?.contains("guardedRunDecisionSchemaID") == true)
        XCTAssertTrue((agentRuleExample["schemaRequirements"] as? [String])?.contains("guardedRunJSONMarkers") == true)
        XCTAssertTrue((agentRuleExample["safetyRequirements"] as? [String])?.contains("daemonControlPathReady == true") == true)
        XCTAssertTrue((agentRuleExample["forbiddenActions"] as? [String])?.contains("ViftyHelper setFixed") == true)
        XCTAssertEqual(agentRuleExample["workloadTemplateIDs"] as? [String], auditedWorkloadTemplateIDs)

        let statusSchema = try readJSON(schemaURL("viftyctl-status.schema.json"))
        let statusDefinitions = try XCTUnwrap(statusSchema["$defs"] as? [String: Any])
        XCTAssertEqual(definitionEnumValues(named: "workload", in: statusDefinitions), ["build", "test", "render", "localModel", "custom"])
        XCTAssertEqual(definitionEnumValues(named: "errorCode", in: statusDefinitions), agentErrorCodeStrings)
        let statusExample = try readJSON(fixtureURL("status-active-lease.json"))
        XCTAssertEqual(statusExample["schemaVersion"] as? Int, 1)
        XCTAssertEqual(statusExample["schemaID"] as? String, "https://vifty.local/schemas/viftyctl-status.schema.json")
        XCTAssertNotNil(statusExample["generatedAt"])
        let activeLease = try XCTUnwrap(statusExample["activeLease"] as? [String: Any])
        try assertRequiredFields(definition: "lease", in: statusDefinitions, arePresentIn: activeLease, context: "active lease")
        try assertRequiredFields(definition: "request", in: statusDefinitions, arePresentIn: activeLease["request"] as? [String: Any], context: "lease request")
        try assertRequiredFields(definition: "decision", in: statusDefinitions, arePresentIn: statusExample["lastDecision"] as? [String: Any], context: "last decision")
        try assertRequiredFields(definition: "policy", in: statusDefinitions, arePresentIn: statusExample["policy"] as? [String: Any], context: "status policy")

        let commandErrorSchema = try readJSON(schemaURL("viftyctl-command-error.schema.json"))
        let commandErrorProperties = try XCTUnwrap(commandErrorSchema["properties"] as? [String: Any])
        let safeToProceed = try XCTUnwrap(commandErrorProperties["safeToProceed"] as? [String: Any])
        XCTAssertEqual(safeToProceed["const"] as? Bool, false)
        XCTAssertNotNil(commandErrorProperties["coolingLeasePrepared"] as? [String: Any])
        XCTAssertNotNil(commandErrorProperties["autoRestoreAttempted"] as? [String: Any])
        XCTAssertNotNil(commandErrorProperties["autoRestoreSucceeded"] as? [String: Any])
        let commandErrorRecoverySteps = try XCTUnwrap(commandErrorProperties["recoverySteps"] as? [String: Any])
        XCTAssertEqual(commandErrorRecoverySteps["type"] as? String, "array")
        XCTAssertEqual(
            (commandErrorProperties["recommendedRecoveryAction"] as? [String: Any])?["enum"] as? [String],
            [
                "runDiagnose",
                "repairHelper",
                "fixArguments",
                "fixChildCommand",
                "restoreAutoBeforeRetry",
                "waitBeforeRetry"
            ]
        )
        XCTAssertNotNil(commandErrorProperties["retryAfterSeconds"] as? [String: Any])
        XCTAssertEqual(oneOfEnumValues(named: "errorCode", in: commandErrorProperties), agentErrorCodeStrings)
        let commandErrorExample = try readJSON(fixtureURL("command-error.json"))
        XCTAssertEqual(commandErrorExample["safeToProceed"] as? Bool, false)
        XCTAssertEqual(commandErrorExample["recommendedRecoveryAction"] as? String, "waitBeforeRetry")
        XCTAssertEqual(commandErrorExample["recoverySteps"] as? [String], Self.waitBeforeRetryRecoverySteps)
        XCTAssertEqual(commandErrorExample["coolingLeasePrepared"] as? Bool, false)
        XCTAssertEqual(commandErrorExample["autoRestoreAttempted"] as? Bool, false)
        XCTAssertTrue(commandErrorExample["autoRestoreSucceeded"] is NSNull)
        XCTAssertEqual(commandErrorExample["retryAfterSeconds"] as? Int, 20)

        let auditSchema = try readJSON(schemaURL("viftyctl-audit.schema.json"))
        let auditProperties = try XCTUnwrap(auditSchema["properties"] as? [String: Any])
        XCTAssertEqual((auditProperties["readOnly"] as? [String: Any])?["const"] as? Bool, true)
        XCTAssertEqual((auditProperties["coolingCommandsRun"] as? [String: Any])?["const"] as? Bool, false)
        let auditDefinitions = try XCTUnwrap(auditSchema["$defs"] as? [String: Any])
        let auditExample = try readJSON(fixtureURL("audit.json"))
        let auditEvents = try XCTUnwrap(auditExample["events"] as? [[String: Any]])
        try assertRequiredFields(
            definition: "auditEvent",
            in: auditDefinitions,
            arePresentIn: auditEvents.first,
            context: "audit event"
        )
    }

    func testCapabilitiesSchemaReferencesPointToExistingSchemas() throws {
        let capabilities = try decode(ViftyCtlCapabilities.self, from: "capabilities.json")

        let references = [
            (capabilities.schemas.capabilities, capabilities.schemaIDs.capabilities),
            (capabilities.schemas.audit, capabilities.schemaIDs.audit),
            (capabilities.schemas.diagnose, capabilities.schemaIDs.diagnose),
            (capabilities.schemas.status, capabilities.schemaIDs.status),
            (capabilities.schemas.commandError, capabilities.schemaIDs.commandError),
            (capabilities.schemas.run, capabilities.schemaIDs.run),
            (capabilities.schemas.agentRule, capabilities.schemaIDs.agentRule)
        ]
        for (schemaPath, schemaID) in references {
            let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(schemaPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing schema at \(schemaPath)")
            let schema = try readJSON(url)
            XCTAssertEqual(schema["$schema"] as? String, "https://json-schema.org/draft/2020-12/schema")
            XCTAssertEqual(schema["$id"] as? String, schemaID)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from filename: String) throws -> T {
        let data = try Data(contentsOf: fixtureURL(filename))
        return try JSONDecoder().decode(type, from: data)
    }

    private func readJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func sourceWorkloadWrapperScripts() throws -> [String] {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(ViftyCtlWrapperResources().sourceDirectory)
        let filenames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return filenames
            .filter { $0.hasSuffix(".sh") && $0 != ViftyCtlWrapperResources().guardedRunScript }
            .sorted()
    }

    private func capabilitiesSchemaWorkloadScripts() throws -> [String] {
        let schema = try readJSON(schemaURL("viftyctl-capabilities.schema.json"))
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let definitions = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let wrapperReference = try XCTUnwrap(properties["wrapperResources"] as? [String: Any])
        let wrapperDefinitionName = try XCTUnwrap((wrapperReference["$ref"] as? String)?.split(separator: "/").last)
        let wrapperResources = try XCTUnwrap(definitions[String(wrapperDefinitionName)] as? [String: Any])
        let wrapperProperties = try XCTUnwrap(wrapperResources["properties"] as? [String: Any])
        let workloadScripts = try XCTUnwrap(wrapperProperties["workloadScripts"] as? [String: Any])
        let items = try XCTUnwrap(workloadScripts["items"] as? [String: Any])
        return try XCTUnwrap(items["enum"] as? [String])
    }

    private func enumValues(named propertyName: String, in properties: [String: Any]) -> [String] {
        guard
            let property = properties[propertyName] as? [String: Any],
            let values = property["enum"] as? [String]
        else {
            return []
        }
        return values
    }

    private func definitionEnumValues(named definitionName: String, in definitions: [String: Any]) -> [String] {
        guard
            let definition = definitions[definitionName] as? [String: Any],
            let values = definition["enum"] as? [String]
        else {
            return []
        }
        return values
    }

    private func oneOfEnumValues(named propertyName: String, in properties: [String: Any]) -> [String] {
        guard
            let property = properties[propertyName] as? [String: Any],
            let oneOf = property["oneOf"] as? [[String: Any]]
        else {
            return []
        }
        return oneOf.compactMap { $0["enum"] as? [String] }.flatMap { $0 }
    }

    private func requiredFields(for definitionName: String, in definitions: [String: Any]) throws -> [String] {
        let definition = try XCTUnwrap(definitions[definitionName] as? [String: Any])
        return try XCTUnwrap(definition["required"] as? [String])
    }

    private func assertRequiredFields(
        definition: String,
        in definitions: [String: Any],
        arePresentIn object: [String: Any]?,
        context: String
    ) throws {
        let object = try XCTUnwrap(object)
        for field in try requiredFields(for: definition, in: definitions) {
            XCTAssertNotNil(object[field], "\(context) should include required schema field \(field)")
        }
    }

    private func assertCheck(
        _ id: String,
        in checks: [ViftyCtlReadinessCheck],
        passed: Bool,
        severity: ViftyCtlReadinessSeverity
    ) throws {
        let check = try XCTUnwrap(checks.first { $0.id == id }, "missing readiness check \(id)")
        XCTAssertEqual(check.passed, passed, "readiness check \(id) passed mismatch")
        XCTAssertEqual(check.severity, severity, "readiness check \(id) severity mismatch")
    }

    private func diagnoseExampleFilenames() throws -> [String] {
        let directory = fixtureURL("")
        let filenames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return filenames
            .filter { $0.hasPrefix("diagnose-") && $0.hasSuffix(".json") }
            .sorted()
    }

    private var agentErrorCodeStrings: [String] {
        [
            "AGENT_CONTROL_DISABLED",
            "UNSUPPORTED_HARDWARE",
            "HELPER_UNREACHABLE",
            "TEMP_SENSOR_UNAVAILABLE",
            "NO_CONTROLLABLE_FANS",
            "POLICY_DENIED",
            "DURATION_TOO_LONG",
            "RPM_OUT_OF_RANGE",
            "THERMAL_CRITICAL",
            "LEASE_NOT_FOUND",
            "RESTORE_FAILED",
            "INVALID_ARGUMENTS",
            "CHILD_COMMAND_FAILED",
            "PREPARE_RATE_LIMITED",
            "RESTORE_REQUESTED"
        ]
    }

    private func fixtureURL(_ filename: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/examples/viftyctl")
            .appendingPathComponent(filename)
    }

    private func schemaURL(_ filename: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs/schemas")
            .appendingPathComponent(filename)
    }
}

private extension Array where Element == [String: Any] {
    func containsRequiredString(_ value: String) -> Bool {
        contains { constraint in
            guard
                let contains = constraint["contains"] as? [String: Any],
                let const = contains["const"] as? String
            else {
                return false
            }
            return const == value
        }
    }
}
