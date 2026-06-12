import Foundation
import XCTest
@testable import ViftyCore

final class ViftyCtlRunnerTests: XCTestCase {
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
        let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner())

        let result = try await runner.run(.status(json: true))

        XCTAssertEqual(result.exitCode, 0)
        let data = try XCTUnwrap(result.stdout.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
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
        XCTAssertEqual(json["command"] as? String, "status")
        XCTAssertEqual(json["errorCode"] as? String, AgentControlErrorCode.helperUnreachable.rawValue)
        XCTAssertEqual(json["safeToProceed"] as? Bool, false)
        XCTAssertEqual(json["recommendedRecoveryAction"] as? String, ViftyCtlCommandErrorRecoveryAction.repairHelper.rawValue)
        XCTAssertTrue((json["message"] as? String)?.contains("Daemon request timed out") == true)
    }

    func testStatusHumanReadableStillThrowsWhenDaemonUnavailable() async throws {
        let expected = ViftyError.helperRejected("Daemon request timed out.")
        let client = FakeAgentControlClient(statusError: expected)
        let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner())

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
        let schemaResources = try XCTUnwrap(json["schemaResources"] as? [String: Any])
        XCTAssertEqual(schemaResources["capabilities"] as? String, "Contents/Resources/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(schemaResources["audit"] as? String, "Contents/Resources/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(schemaResources["diagnose"] as? String, "Contents/Resources/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(schemaResources["status"] as? String, "Contents/Resources/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(schemaResources["commandError"] as? String, "Contents/Resources/schemas/viftyctl-command-error.schema.json")
        let schemaIDs = try XCTUnwrap(json["schemaIDs"] as? [String: Any])
        XCTAssertEqual(schemaIDs["capabilities"] as? String, "https://vifty.local/schemas/viftyctl-capabilities.schema.json")
        XCTAssertEqual(schemaIDs["audit"] as? String, "https://vifty.local/schemas/viftyctl-audit.schema.json")
        XCTAssertEqual(schemaIDs["diagnose"] as? String, "https://vifty.local/schemas/viftyctl-diagnose.schema.json")
        XCTAssertEqual(schemaIDs["status"] as? String, "https://vifty.local/schemas/viftyctl-status.schema.json")
        XCTAssertEqual(schemaIDs["commandError"] as? String, "https://vifty.local/schemas/viftyctl-command-error.schema.json")
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
        let directControlLifecycle = try XCTUnwrap(json["directControlLifecycle"] as? [String: Any])
        XCTAssertEqual(directControlLifecycle["prepareUsesIdempotencyKey"] as? Bool, true)
        XCTAssertEqual(directControlLifecycle["restoreAutoAcceptsIdempotencyKey"] as? Bool, false)
        XCTAssertEqual(directControlLifecycle["restoreAutoScopedByIdempotencyKey"] as? Bool, false)
        XCTAssertEqual(directControlLifecycle["preferRunForSingleChildWorkloads"] as? Bool, true)
        XCTAssertEqual(json["supportsForceRetry"] as? Bool, true)
        let policy = try XCTUnwrap(json["policy"] as? [String: Any])
        XCTAssertEqual(policy["maximumAllowedRPMPercent"] as? Int, 75)
        XCTAssertEqual(policy["maxDurationSeconds"] as? Int, 1_800)
        XCTAssertEqual(policy["prepareCooldownSeconds"] as? Int, 12)
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
        let directControlLifecycle = try XCTUnwrap(json["directControlLifecycle"] as? [String: Any])
        XCTAssertEqual(directControlLifecycle["prepareUsesIdempotencyKey"] as? Bool, true)
        XCTAssertEqual(directControlLifecycle["restoreAutoAcceptsIdempotencyKey"] as? Bool, false)
        XCTAssertEqual(directControlLifecycle["restoreAutoScopedByIdempotencyKey"] as? Bool, false)
        XCTAssertEqual(directControlLifecycle["preferRunForSingleChildWorkloads"] as? Bool, true)
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
        XCTAssertEqual(json["safeToRequestCooling"] as? Bool, true)
        XCTAssertEqual(json["daemonControlPathReady"] as? Bool, true)
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
        XCTAssertEqual(json["daemonControlPathReady"] as? Bool, false)
        XCTAssertEqual(json["modelIdentifier"] as? String, "unknown")
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
        XCTAssertEqual(json["daemonControlPathReady"] as? Bool, false)
        XCTAssertEqual(json["modelIdentifier"] as? String, "MacBookPro18,3")
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
            thermalReader: { .serious }
        )

        let result = try await runner.run(.diagnose(json: false))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("state=degraded"))
        XCTAssertTrue(result.stdout.contains("agentAction=restoreAutoBeforeRequestingCooling safeToRequestCooling=false"))
        XCTAssertTrue(result.stdout.contains("recoveryAction=restoreAutoBeforeRetry"))
        XCTAssertTrue(result.stdout.contains("[warn] activeLeaseClear"))
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
        let runner = ViftyCtlRunner(client: client, processRunner: FakeProcessRunner())

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
        XCTAssertEqual(report.safeToRequestCooling, true)
        XCTAssertTrue(report.daemonControlPathReady)
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
        XCTAssertEqual(report.safeToRequestCooling, false)
        XCTAssertTrue(report.daemonControlPathReady)
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
        let runner = ViftyCtlRunner(client: client, processRunner: processRunner)

        let result = try await runner.run(.restoreAuto(reason: "done", json: true))

        XCTAssertEqual(result.exitCode, 0)
        let restoreReasons = await client.restoreReasons
        XCTAssertEqual(restoreReasons, ["done"])
        XCTAssertEqual(processRunner.runCallCount, 0)
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
        XCTAssertEqual(prepareRequests, [request])
        XCTAssertEqual(restoreReasons, ["viftyctl run child exited with 7"])
        XCTAssertEqual(processRunner.runArguments, [["/usr/bin/swift", "test"]])
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
        HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left Fan",
                    currentRPM: 2_100,
                    minimumRPM: 1_400,
                    maximumRPM: 6_000,
                    controllable: true,
                    hardwareMode: fanMode,
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
                    hardwareMode: fanMode,
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
}

private actor FakeAgentControlClient: ViftyCtlAgentControlClient {
    private let snapshotResponse: HardwareSnapshot
    private let statusResponse: AgentControlStatus
    private let auditResponse: [AgentControlAuditEvent]
    private let snapshotError: (any Error)?
    private let statusError: (any Error)?
    private let auditError: (any Error)?
    private let prepareError: (any Error)?
    private let restoreError: (any Error)?
    private var prepareResponses: [AgentControlStatus]
    private var storedPrepareRequests: [AgentControlRequest] = []
    private var storedRestoreReasons: [String] = []
    private var storedAuditLimits: [Int] = []

    init(
        snapshot: HardwareSnapshot = ViftyCtlRunnerTests.readySnapshot(),
        status: AgentControlStatus = AgentControlStatus(
            enabled: true,
            activeLease: nil,
            lastDecision: nil,
            lastErrorCode: nil
        ),
        auditEvents: [AgentControlAuditEvent] = [],
        prepareResponses: [AgentControlStatus] = [],
        snapshotError: (any Error)? = nil,
        statusError: (any Error)? = nil,
        auditError: (any Error)? = nil,
        prepareError: (any Error)? = nil,
        restoreError: (any Error)? = nil
    ) {
        self.snapshotResponse = snapshot
        self.statusResponse = status
        self.auditResponse = auditEvents
        self.snapshotError = snapshotError
        self.statusError = statusError
        self.auditError = auditError
        self.prepareError = prepareError
        self.restoreError = restoreError
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

    var auditLimits: [Int] {
        storedAuditLimits
    }

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
        if let restoreError {
            throw restoreError
        }
        return statusResponse
    }
}

private final class FakeProcessRunner: ViftyCtlProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private let exitCode: Int32
    private let resolvedArguments: [String]?
    private let resolveError: (any Error)?
    private let error: (any Error)?
    private var storedRunArguments: [[String]] = []

    init(
        exitCode: Int32 = 0,
        resolvedArguments: [String]? = nil,
        resolveError: (any Error)? = nil,
        error: (any Error)? = nil
    ) {
        self.exitCode = exitCode
        self.resolvedArguments = resolvedArguments
        self.resolveError = resolveError
        self.error = error
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

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
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
