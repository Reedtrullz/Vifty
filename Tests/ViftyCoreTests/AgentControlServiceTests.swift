import Foundation
import XCTest
@testable import ViftyCore

final class AgentControlServiceTests: XCTestCase {
    func testStartupRecoveryIsReadOnlyWhenNoDurableOwnershipExists() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500)]))
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: temporaryDirectory()),
            thermalReader: { .nominal }
        )

        let status = try await service.recoverOnStartup()

        XCTAssertNil(status.activeLease)
        let snapshotCallCount = await hardware.snapshotCallCount
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertEqual(snapshotCallCount, 0)
        XCTAssertEqual(restoredFanIDs, [])
    }

    func testStartupRecoveryRestoresFullSetAndClearsPersistedLeaseBeforeUse() async throws {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let store = AgentControlStore(directory: temporaryDirectory())
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 75,
            reason: "Build",
            idempotencyKey: "key"
        )
        try store.saveActiveLease(AgentCoolingLease(
            id: "lease-1",
            request: request,
            createdAt: startedAt,
            expiresAt: startedAt.addingTimeInterval(600),
            targetRPMByFanID: [0: 3_750, 1: 4_500]
        ))
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
            Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500),
            Self.fan(id: 1, minimumRPM: 1_500, maximumRPM: 5_500)
        ]))
        let scheduler = AgentControlManualScheduler()
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { startedAt },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )

        let status = try await service.recoverOnStartup()

        XCTAssertNil(status.activeLease)
        XCTAssertNil(try store.loadActiveLease())
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertEqual(restoredFanIDs, [0, 1])
        let restoreRequests = await hardware.restoreAllAutoRequests
        XCTAssertEqual(
            restoreRequests.last?.unreadableJournalRecoveryAuthority,
            .durableState
        )
    }

    func testPrepareAppliesTargetsStoresLeaseAndReportsStatus() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        let status = try await service.prepare(request)

        XCTAssertEqual(status.activeLease?.id, "lease-1")
        XCTAssertEqual(status.activeLease?.expiresAt, Date(timeIntervalSince1970: 1_600))
        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(3750))])
        XCTAssertEqual(try store.loadActiveLease()?.id, "lease-1")
        let audit = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(audit.contains("\"message\":\"Build\""))
    }

    func testPrepareNormalizesMetadataBeforeSavingLeaseAndAudit() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 75,
            reason: "  Build  ",
            idempotencyKey: "  key  "
        )

        let status = try await service.prepare(request)

        XCTAssertEqual(status.activeLease?.request.reason, "Build")
        XCTAssertEqual(status.activeLease?.request.idempotencyKey, "key")
        let savedLease = try store.loadActiveLease()
        XCTAssertEqual(savedLease?.request.reason, "Build")
        XCTAssertEqual(savedLease?.request.idempotencyKey, "key")
        let audit = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(audit.contains("\"message\":\"Build\""))
        XCTAssertFalse(audit.contains("\"message\":\"  Build  \""))
    }

    func testPrepareRejectsBlankMetadataBeforeHardwareAccess() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 75,
            reason: "   ",
            idempotencyKey: "key"
        )

        let status = try await service.prepare(request)

        XCTAssertNil(status.activeLease)
        XCTAssertEqual(status.lastErrorCode, .invalidArguments)
        XCTAssertEqual(status.lastDecision?.message, "Agent cooling reason must not be blank.")
        let snapshotCallCount = await hardware.snapshotCallCount
        XCTAssertEqual(snapshotCallCount, 0)
        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [])
        XCTAssertNil(try store.loadActiveLease())
        let audit = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(audit.contains("\"action\":\"prepare-denied\""))
        XCTAssertTrue(audit.contains("Agent cooling reason must not be blank."))
    }

    func testPrepareRejectsOversizedMetadataBeforeHardwareAccess() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 75,
            reason: String(repeating: "r", count: AgentControlRequest.maximumReasonLength + 1),
            idempotencyKey: "key"
        )

        let status = try await service.prepare(request)

        XCTAssertNil(status.activeLease)
        XCTAssertEqual(status.lastErrorCode, .invalidArguments)
        XCTAssertEqual(status.lastDecision?.message, "Agent cooling reason must be 512 characters or fewer.")
        let snapshotCallCount = await hardware.snapshotCallCount
        XCTAssertEqual(snapshotCallCount, 0)
        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [])
        XCTAssertNil(try store.loadActiveLease())
        let audit = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(audit.contains("\"action\":\"prepare-denied\""))
        XCTAssertTrue(audit.contains("Agent cooling reason must be 512 characters or fewer."))
    }

    func testRestoreAutoRestoresFansAndClearsLease() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)

        let status = try await service.restoreAuto(reason: "done")

        XCTAssertNil(status.activeLease)
        XCTAssertNil(status.lastDecision)
        XCTAssertNil(status.lastErrorCode)
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        XCTAssertNil(try store.loadActiveLease())
    }

    func testRestoreAllAutoCannotNarrowAnActiveLeaseFanSet() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
            Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500),
            Self.fan(id: 1, minimumRPM: 1_500, maximumRPM: 5_500)
        ]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 75,
            reason: "Build",
            idempotencyKey: "key"
        )
        _ = try await service.prepare(request)

        _ = try await service.restoreAllAuto(
            AutoRestoreRequest(
                transactionID: "client-restore",
                expectedFanIDs: [0],
                reason: "done",
                allowRestoreAllTrustedFans: false
            )
        )

        let restoreRequests = await hardware.restoreAllAutoRequests
        XCTAssertEqual(restoreRequests.last?.expectedFanIDs, [0, 1])
        XCTAssertEqual(
            restoreRequests.last?.unreadableJournalRecoveryAuthority,
            .durableState
        )
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0, 1])
        XCTAssertNil(try store.loadActiveLease())
        let status = await service.status()
        XCTAssertNil(status.activeLease)
    }

    func testExplicitOperatorRestoreOverridesPartialLeaseSetWithTrustedGlobalRestore() async throws {
        let restoreOnlyFan = Fan(
            id: 1,
            name: "Restore-only fan",
            currentRPM: 1_500,
            minimumRPM: 0,
            maximumRPM: 0,
            controllable: false,
            hardwareMode: .automatic,
            hardwareModeKey: "F1Md",
            targetRPM: nil,
            controlEligibility: FanControlEligibility(
                canApplyFixedRPM: false,
                canRestoreOSManagedMode: true,
                reasons: [.missingTargetKey]
            )
        )
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
            Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500),
            restoreOnlyFan
        ]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        _ = try await service.prepare(AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 75,
            reason: "Build",
            idempotencyKey: "key"
        ))

        _ = try await service.restoreAllAuto(AutoRestoreRequest(
            transactionID: "explicit-recovery",
            reason: "Explicit operator Auto",
            allowRestoreAllTrustedFans: true,
            unreadableJournalRecoveryAuthority: .explicitOperator
        ))

        let restoreRequests = await hardware.restoreAllAutoRequests
        let request = try XCTUnwrap(restoreRequests.last)
        XCTAssertEqual(request.expectedFanIDs, [])
        XCTAssertTrue(request.allowRestoreAllTrustedFans)
        XCTAssertEqual(request.unreadableJournalRecoveryAuthority, .explicitOperator)
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertEqual(restoredFanIDs, [0, 1])
        XCTAssertNil(try store.loadActiveLease())
    }

    func testRestoreAutoNormalizesBlankAuditReasonWithoutBlockingRestore() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)

        let status = try await service.restoreAuto(reason: "   ")

        XCTAssertNil(status.activeLease)
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        let audit = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(audit.contains("\"action\":\"restore-auto\""))
        XCTAssertTrue(audit.contains("\"message\":\"manual restore\""))
    }

    func testRestoreAutoTruncatesOversizedAuditReasonWithoutBlockingRestore() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)
        let reason = String(repeating: "r", count: AgentControlRequest.maximumReasonLength + 100)

        let status = try await service.restoreAuto(reason: reason)

        XCTAssertNil(status.activeLease)
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        let restoreEvent = try store.loadRecentAuditEvents(limit: 10).first { $0.action == "restore-auto" }
        XCTAssertEqual(restoreEvent?.message.count, AgentControlRequest.maximumReasonLength)
        XCTAssertEqual(restoreEvent?.message, String(reason.prefix(AgentControlRequest.maximumReasonLength)))
    }

    func testClearActiveLeaseNormalizesAuditReason() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)

        let status = try await service.clearActiveLease(reason: "  user selected Auto  ")

        XCTAssertNil(status.activeLease)
        let audit = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(audit.contains("\"action\":\"clear-lease\""))
        XCTAssertTrue(audit.contains("\"message\":\"user selected Auto\""))
        XCTAssertFalse(audit.contains("\"message\":\"  user selected Auto  \""))
    }

    func testClearActiveLeaseTruncatesOversizedAuditReason() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)
        let reason = String(repeating: "c", count: AgentControlRequest.maximumReasonLength + 100)

        let status = try await service.clearActiveLease(reason: reason)

        XCTAssertNil(status.activeLease)
        let clearEvent = try store.loadRecentAuditEvents(limit: 10).first { $0.action == "clear-lease" }
        XCTAssertEqual(clearEvent?.message.count, AgentControlRequest.maximumReasonLength)
        XCTAssertEqual(clearEvent?.message, String(reason.prefix(AgentControlRequest.maximumReasonLength)))
    }

    func testRestoreAutoClearsStalePrepareDenialState() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: temporaryDirectory()),
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)
        let denied = try await service.prepare(AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 75, reason: "Test", idempotencyKey: "other-key"))
        XCTAssertEqual(denied.lastErrorCode, .policyDenied)

        let status = try await service.restoreAuto(reason: "done")

        XCTAssertNil(status.activeLease)
        XCTAssertNil(status.lastDecision)
        XCTAssertNil(status.lastErrorCode)
    }

    func testPrepareDoesNotIssueIndependentRestoreAfterTransactionalApplyFailure() async throws {
        let hardware = AgentServiceFakeHardware(
            snapshot: Self.snapshot(fans: [
                Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500),
                Self.fan(id: 1, minimumRPM: 1500, maximumRPM: 5500)
            ]),
            failingApplyFanID: 1
        )
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        do {
            _ = try await service.prepare(request)
            XCTFail("Expected prepare to throw")
        } catch AgentServiceFakeHardware.Failure.applyFailed {
            let restored = await hardware.restoredFanIDs
            XCTAssertEqual(restored, [])
            XCTAssertNil(try store.loadActiveLease())
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPrepareApplyFailureLeavesRollbackAuthorityWithArbiter() async throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let hardware = AgentServiceFakeHardware(
            snapshot: Self.snapshot(fans: [
                Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500),
                Self.fan(id: 1, minimumRPM: 1500, maximumRPM: 5500)
            ]),
            failingApplyFanID: 1
        )
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        do {
            _ = try await service.prepare(request)
            XCTFail("Expected prepare to throw")
        } catch AgentServiceFakeHardware.Failure.applyFailed {
            let restored = await hardware.restoredFanIDs
            XCTAssertEqual(restored, [])
            XCTAssertNil(try store.loadActiveLease())
            let audit = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
            XCTAssertTrue(audit.contains("prepare-apply-failed"))
            XCTAssertTrue(audit.contains("arbiter owns rollback"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLeaseSaveFailureRollsBackFullExpectedSetAndDurablyClearsLease() async throws {
        let directory = temporaryDirectory()
        let store = FailingActiveLeaseSaveStore(directory: directory)
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
            Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500),
            Self.fan(id: 1, minimumRPM: 1_500, maximumRPM: 5_500)
        ]))
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 600,
            maxRPMPercent: 75,
            reason: "Build",
            idempotencyKey: "key"
        )

        do {
            _ = try await service.prepare(request)
            XCTFail("Expected injected lease save failure")
        } catch FailingActiveLeaseSaveStore.Failure.saveFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertEqual(restoredFanIDs, [0, 1])
        XCTAssertEqual(store.saveAttempts, ["lease-1", nil])
        XCTAssertNil(try store.loadActiveLease())
        let finalStatus = await service.status()
        XCTAssertNil(finalStatus.activeLease)
    }

    func testPrepareRejectsForcedOrUnknownUnownedFansWithoutLeaseOrWrites() async throws {
        for mode in [FanHardwareMode.forced, .unknown(2)] {
            let directory = temporaryDirectory()
            let store = AgentControlStore(directory: directory)
            let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
                Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500, hardwareMode: mode)
            ]))
            let service = AgentControlService(
                hardware: hardware,
                policy: AgentControlPolicy(enabled: true),
                store: store,
                thermalReader: { .nominal },
                now: { Date(timeIntervalSince1970: 1_000) },
                leaseID: { "lease-1" }
            )

            let status = try await service.prepare(AgentControlRequest(
                workload: .build,
                durationSeconds: 300,
                maxRPMPercent: 60,
                reason: "Build",
                idempotencyKey: "key"
            ))

            XCTAssertNil(status.activeLease)
            XCTAssertEqual(status.lastErrorCode, .policyDenied)
            XCTAssertTrue(status.lastDecision?.message.contains("Forced/Unknown") == true)
            let appliedCommands = await hardware.appliedCommands
            let restoreRequests = await hardware.restoreAllAutoRequests
            XCTAssertTrue(appliedCommands.isEmpty)
            XCTAssertTrue(restoreRequests.isEmpty)
            XCTAssertNil(try store.loadActiveLease())
        }
    }

    func testPrepareRejectsUnsafePhysicalFanHiddenByLegacyControllableFlag() async throws {
        let unsafePhysicalFans = [
            Fan(
                id: 1,
                name: "Forced mode-only fan",
                currentRPM: 1_500,
                minimumRPM: 0,
                maximumRPM: 0,
                controllable: false,
                hardwareMode: .forced,
                hardwareModeKey: "F1Md",
                targetRPM: nil,
                controlEligibility: FanControlEligibility(
                    canApplyFixedRPM: false,
                    canRestoreOSManagedMode: true,
                    reasons: [.missingTargetKey]
                )
            ),
            Fan(
                id: 1,
                name: "Untrusted display-only fan",
                currentRPM: 1_500,
                minimumRPM: 0,
                maximumRPM: 0,
                controllable: false,
                hardwareMode: .automatic,
                controlEligibility: .legacyUnspecified
            )
        ]

        for unsafeFan in unsafePhysicalFans {
            let store = AgentControlStore(directory: temporaryDirectory())
            let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
                Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500),
                unsafeFan
            ]))
            let service = AgentControlService(
                hardware: hardware,
                policy: AgentControlPolicy(enabled: true),
                store: store,
                thermalReader: { .nominal },
                now: { Date(timeIntervalSince1970: 1_000) },
                leaseID: { "lease-1" }
            )

            let status = try await service.prepare(AgentControlRequest(
                workload: .build,
                durationSeconds: 300,
                maxRPMPercent: 60,
                reason: "Build",
                idempotencyKey: "key"
            ))

            XCTAssertNil(status.activeLease)
            XCTAssertEqual(status.lastErrorCode, .policyDenied)
            let appliedCommands = await hardware.appliedCommands
            let restoreRequests = await hardware.restoreAllAutoRequests
            XCTAssertTrue(appliedCommands.isEmpty)
            XCTAssertTrue(restoreRequests.isEmpty)
            XCTAssertNil(try store.loadActiveLease())
        }
    }

    func testCorruptLeaseWithoutJournalRequiresExplicitOperatorRestoreAndWritesNothing() async throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("active-lease.json")
        )
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
            Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500)
        ]))
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: directory),
            thermalReader: { .nominal },
            automaticallySchedulePersistedLeaseMonitor: false
        )

        do {
            _ = try await service.recoverOnStartup()
            XCTFail("Expected explicit operator recovery blocker")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("STARTUP_RECOVERY_REQUIRES_OPERATOR"))
        }
        let snapshotCallCount = await hardware.snapshotCallCount
        let appliedCommands = await hardware.appliedCommands
        let restoreRequests = await hardware.restoreAllAutoRequests
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertEqual(snapshotCallCount, 0)
        XCTAssertTrue(appliedCommands.isEmpty)
        XCTAssertTrue(restoreRequests.isEmpty)
        XCTAssertTrue(restoredFanIDs.isEmpty)
    }

    func testNoLeaseAutoUsesGlobalValidationAndRejectsPartialTelemetryBeforeClear() async throws {
        let partialFan = Fan(
            id: 1,
            name: "Partial Fan",
            currentRPM: 1_500,
            minimumRPM: 1_400,
            maximumRPM: 6_000,
            controllable: true,
            hardwareMode: nil,
            controlEligibility: FanControlEligibility(
                canApplyFixedRPM: false,
                canRestoreOSManagedMode: false,
                reasons: [.missingModeKey]
            )
        )
        let store = AgentControlStore(directory: temporaryDirectory())
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
            Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500),
            partialFan
        ]))
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            automaticallySchedulePersistedLeaseMonitor: false
        )

        do {
            _ = try await service.restoreAuto(reason: "Explicit user Auto")
            XCTFail("Expected partial global Auto refusal")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("complete trusted fan inventory"))
        }

        let requests = await hardware.restoreAllAutoRequests
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertEqual(requests.last?.expectedFanIDs, [])
        XCTAssertTrue(requests.last?.allowRestoreAllTrustedFans == true)
        XCTAssertTrue(restoredFanIDs.isEmpty)
    }

    func testNoLeaseRestoreAllCanonicalizesCallerSubsetToGlobalApproval() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
            Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500),
            Self.fan(id: 1, minimumRPM: 1_500, maximumRPM: 5_500)
        ]))
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: temporaryDirectory()),
            thermalReader: { .nominal },
            automaticallySchedulePersistedLeaseMonitor: false
        )

        _ = try await service.restoreAllAuto(AutoRestoreRequest(
            transactionID: "caller-subset",
            expectedFanIDs: [0],
            reason: "Explicit operator Auto",
            allowRestoreAllTrustedFans: true,
            unreadableJournalRecoveryAuthority: .explicitOperator
        ))

        let requests = await hardware.restoreAllAutoRequests
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.expectedFanIDs, [])
        XCTAssertTrue(request.allowRestoreAllTrustedFans)
        XCTAssertEqual(request.unreadableJournalRecoveryAuthority, .explicitOperator)
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertEqual(restoredFanIDs, [0, 1])
    }

    func testLeaseSaveFailureWithForeignOwnershipDoesNotClearOrRestoreForeignOwner() async throws {
        let directory = temporaryDirectory()
        let store = FailingActiveLeaseSaveStore(directory: directory)
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
            Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500)
        ]))
        await hardware.setOwnershipAfterApply(FanControlOwnershipStatus(
            owner: .manual(sessionID: "foreign-manual"),
            phase: .active,
            transactionID: "foreign-transaction",
            expectedFanIDs: [0],
            recoveryPending: false
        ))
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )

        do {
            _ = try await service.prepare(AgentControlRequest(
                workload: .build,
                durationSeconds: 300,
                maxRPMPercent: 60,
                reason: "Build",
                idempotencyKey: "key"
            ))
            XCTFail("Expected persistence failure")
        } catch FailingActiveLeaseSaveStore.Failure.saveFailed {
        }

        let restoreRequests = await hardware.restoreAllAutoRequests
        let restoredFanIDs = await hardware.restoredFanIDs
        XCTAssertTrue(restoreRequests.isEmpty)
        XCTAssertTrue(restoredFanIDs.isEmpty)
        XCTAssertEqual(store.saveAttempts, ["lease-1", nil])
        let rollbackRequests = await hardware.ownedRollbackRequests
        XCTAssertEqual(rollbackRequests.count, 1)
    }

    func testLeaseSaveFailureDoesNotProbeAgainAndAtomicallyRestoresOwnedTransaction() async throws {
        let directory = temporaryDirectory()
        let store = FailingActiveLeaseSaveStore(directory: directory)
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
            Self.fan(id: 0, minimumRPM: 1_500, maximumRPM: 4_500)
        ]))
        await hardware.enqueueOwnershipStatus(.osManaged)
        await hardware.enqueueOwnershipFailure()
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )

        do {
            _ = try await service.prepare(AgentControlRequest(
                workload: .build,
                durationSeconds: 300,
                maxRPMPercent: 60,
                reason: "Build",
                idempotencyKey: "key"
            ))
            XCTFail("Expected persistence failure")
        } catch FailingActiveLeaseSaveStore.Failure.saveFailed {
        }

        let restoreRequests = await hardware.restoreAllAutoRequests
        let restoredFanIDs = await hardware.restoredFanIDs
        let ownershipStatusCallCount = await hardware.fanControlOwnershipStatusCallCount
        let rollbackRequests = await hardware.ownedRollbackRequests
        XCTAssertEqual(ownershipStatusCallCount, 1)
        XCTAssertEqual(rollbackRequests.count, 1)
        XCTAssertEqual(restoreRequests.count, 1)
        XCTAssertEqual(restoredFanIDs, [0])
        XCTAssertEqual(store.saveAttempts, ["lease-1", nil])
    }

    func testRestoreAutoPreemptsPrepareSnapshotInProgress() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        await hardware.blockNextSnapshot()
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        let prepareTask = Task {
            try await service.prepare(request)
        }
        await hardware.waitForBlockedSnapshot()

        let restoreStatus = try await service.restoreAuto(reason: "done")
        XCTAssertNil(restoreStatus.activeLease)
        let restoredBeforePrepareCompletes = await hardware.restoredFanIDs
        XCTAssertEqual(restoredBeforePrepareCompletes, [0])

        await hardware.releaseBlockedSnapshot()
        let status = try await prepareTask.value

        XCTAssertNil(status.activeLease)
        XCTAssertEqual(status.lastErrorCode, .restoreRequested)
        XCTAssertEqual(status.lastDecision?.message, "Prepare cancelled because Auto restore was requested.")
        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [])
        let restoredAfterPrepareCompletes = await hardware.restoredFanIDs
        XCTAssertEqual(restoredAfterPrepareCompletes, [0])
        XCTAssertNil(try store.loadActiveLease())
    }

    func testClearActiveLeasePreemptsPrepareSnapshotInProgress() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        await hardware.blockNextSnapshot()
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        let prepareTask = Task {
            try await service.prepare(request)
        }
        await hardware.waitForBlockedSnapshot()

        let clearStatus = try await service.clearActiveLease(reason: "User/app restored Auto through daemon restoreAuto")
        XCTAssertNil(clearStatus.activeLease)

        await hardware.releaseBlockedSnapshot()
        let status = try await prepareTask.value

        XCTAssertNil(status.activeLease)
        XCTAssertEqual(status.lastErrorCode, .restoreRequested)
        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [])
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        XCTAssertNil(try store.loadActiveLease())
    }

    func testClearActiveLeaseClearsStalePrepareDenialState() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: temporaryDirectory()),
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)
        let denied = try await service.prepare(AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 75, reason: "Test", idempotencyKey: "other-key"))
        XCTAssertEqual(denied.lastErrorCode, .policyDenied)

        let status = try await service.clearActiveLease(reason: "User/app restored Auto through daemon restoreAuto")

        XCTAssertNil(status.activeLease)
        XCTAssertNil(status.lastDecision)
        XCTAssertNil(status.lastErrorCode)
    }

    func testPrepareRejectedWhileRestoreAutoInProgress() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        await hardware.blockNextSnapshot()
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: temporaryDirectory()),
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" }
        )
        let restoreTask = Task {
            try await service.restoreAuto(reason: "user auto")
        }
        await hardware.waitForBlockedSnapshot()
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        do {
            _ = try await service.prepare(request)
            XCTFail("Expected prepare to be rejected while Auto restore is in progress")
        } catch ViftyError.helperRejected(let message) {
            XCTAssertEqual(message, "Agent control operation already in progress.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await hardware.releaseBlockedSnapshot()
        let restoreStatus = try await restoreTask.value
        XCTAssertNil(restoreStatus.activeLease)
        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [])
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
    }

    func testDuplicateIdempotencyKeyReturnsExistingLeaseWithoutReapplying() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { UUID().uuidString }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")

        let firstStatus = try await service.prepare(request)
        let secondStatus = try await service.prepare(request)

        XCTAssertEqual(secondStatus.activeLease?.id, firstStatus.activeLease?.id)
        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(3750))])
    }

    func testDifferentIdempotencyKeyIsDeniedWhileLeaseActiveAndMonitorStillRestoresOriginalLease() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = AgentControlTestClock(now: start)
        let scheduler = AgentControlManualScheduler()
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { "lease-a" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let requestA = AgentControlRequest(workload: .build, durationSeconds: 60, maxRPMPercent: 75, reason: "Build A", idempotencyKey: "key-a")
        let requestB = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 80, reason: "Build B", idempotencyKey: "key-b")

        let statusA = try await service.prepare(requestA)
        XCTAssertEqual(statusA.activeLease?.id, "lease-a")
        var applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(3750))])
        var snapshotCallCount = await hardware.snapshotCallCount
        XCTAssertEqual(snapshotCallCount, 2)

        let statusB = try await service.prepare(requestB)

        XCTAssertEqual(statusB.activeLease?.id, "lease-a")
        XCTAssertEqual(statusB.lastErrorCode, .policyDenied)
        XCTAssertEqual(statusB.lastDecision?.errorCode, .policyDenied)
        XCTAssertEqual(statusB.lastDecision?.message, "Agent cooling lease already active. Restore Auto before starting a new lease.")
        applied = await hardware.appliedCommands
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(3750))])
        snapshotCallCount = await hardware.snapshotCallCount
        XCTAssertEqual(snapshotCallCount, 2)
        let restoredBeforeExpiry = await hardware.restoredFanIDs
        XCTAssertEqual(restoredBeforeExpiry, [])
        XCTAssertEqual(try store.loadActiveLease()?.id, "lease-a")
        let audit = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(audit.contains("\"action\":\"prepare-denied\""))
        XCTAssertTrue(audit.contains("Agent cooling lease already active. Restore Auto before starting a new lease."))

        clock.now = start.addingTimeInterval(61)
        await scheduler.fireLastScheduledOperation()

        let restoredAfterExpiry = await hardware.restoredFanIDs
        XCTAssertEqual(restoredAfterExpiry, [0])
        let finalStatus = await service.status()
        XCTAssertNil(finalStatus.activeLease)
        XCTAssertNil(try store.loadActiveLease())
    }

    func testMonitorTickRestoresExpiredLeaseWithoutStatusPoll() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = AgentControlTestClock(now: start)
        let scheduler = AgentControlManualScheduler()
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { "lease-1" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 60, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)

        clock.now = start.addingTimeInterval(61)
        await scheduler.fireLastScheduledOperation()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        let status = await service.status()
        XCTAssertNil(status.activeLease)
    }

    func testStatusKeepsExpiredUnrestoredLeaseVisibleUntilMonitorRestoresAuto() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = AgentControlTestClock(now: start)
        let scheduler = AgentControlManualScheduler()
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { "lease-1" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 60, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)

        clock.now = start.addingTimeInterval(61)
        let expiredButUnrestoredStatus = await service.status()

        XCTAssertEqual(expiredButUnrestoredStatus.activeLease?.id, "lease-1")
        XCTAssertFalse(try XCTUnwrap(expiredButUnrestoredStatus.activeLease).isActive(at: clock.now))
        let restoredBeforeMonitor = await hardware.restoredFanIDs
        XCTAssertEqual(restoredBeforeMonitor, [])

        await scheduler.fireLastScheduledOperation()

        let restoredAfterMonitor = await hardware.restoredFanIDs
        XCTAssertEqual(restoredAfterMonitor, [0])
        let restoredStatus = await service.status()
        XCTAssertNil(restoredStatus.activeLease)
    }

    func testPrepareDeniedWhenPreviousLeaseExpiredButMonitorHasNotRestoredAuto() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = AgentControlTestClock(now: start)
        let scheduler = AgentControlManualScheduler()
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { "lease-1" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 60, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)

        clock.now = start.addingTimeInterval(61)
        let nextRequest = AgentControlRequest(workload: .test, durationSeconds: 600, maxRPMPercent: 75, reason: "Test", idempotencyKey: "next-key")
        let denied = try await service.prepare(nextRequest)

        XCTAssertEqual(denied.activeLease?.id, "lease-1")
        XCTAssertEqual(denied.lastErrorCode, .policyDenied)
        XCTAssertEqual(denied.lastDecision?.message, "Agent cooling lease expired but Auto restore has not completed. Restore Auto before starting a new lease.")
        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(3750))])
        let snapshotCallCount = await hardware.snapshotCallCount
        XCTAssertEqual(snapshotCallCount, 2)
        let restoredBeforeMonitor = await hardware.restoredFanIDs
        XCTAssertEqual(restoredBeforeMonitor, [])

        await scheduler.fireLastScheduledOperation()

        let restoredAfterMonitor = await hardware.restoredFanIDs
        XCTAssertEqual(restoredAfterMonitor, [0])
        let restoredStatus = await service.status()
        XCTAssertNil(restoredStatus.activeLease)
    }

    func testExpiredUnrestoredLeaseWithSameIdempotencyKeyIsNotTreatedAsSuccessfulPrepare() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = AgentControlTestClock(now: start)
        let scheduler = AgentControlManualScheduler()
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: temporaryDirectory()),
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { "lease-1" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 60, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)

        clock.now = start.addingTimeInterval(61)
        let status = try await service.prepare(request)

        XCTAssertEqual(status.activeLease?.id, "lease-1")
        XCTAssertFalse(try XCTUnwrap(status.activeLease).isActive(at: clock.now))
        XCTAssertEqual(status.lastErrorCode, .policyDenied)
        XCTAssertEqual(status.lastDecision?.message, "Agent cooling lease expired but Auto restore has not completed. Restore Auto before starting a new lease.")
    }

    func testMonitorRestoresExpiredLeaseWithoutExplicitStatusPoll() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = AgentControlTestClock(now: start)
        let scheduler = AgentControlManualScheduler()
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { "lease-1" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 60, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)

        clock.now = start.addingTimeInterval(61)
        await scheduler.fireLastScheduledOperation()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        XCTAssertNil(try store.loadActiveLease())
    }

    func testStalePersistedLeaseSchedulingCannotCancelNewerLeaseMonitor() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = AgentControlTestClock(now: start)
        let scheduler = AgentControlManualScheduler()
        let fan = Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [fan]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let oldRequest = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Old", idempotencyKey: "old-key")
        let oldLease = AgentCoolingLease(
            id: "old-lease",
            request: oldRequest,
            createdAt: start.addingTimeInterval(-601),
            expiresAt: start.addingTimeInterval(-1),
            targetRPMByFanID: [0: 3750]
        )
        try store.saveActiveLease(oldLease)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { "new-lease" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 2, maxRPMPercent: 75, reason: "New", idempotencyKey: "new-key")

        _ = try await service.prepare(request)
        await scheduler.waitForScheduledOperationCount(atLeast: 1)
        await Task.yield()

        clock.now = start.addingTimeInterval(3)
        await scheduler.fireAllScheduledOperations()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        let status = await service.status()
        XCTAssertNil(status.activeLease)
    }

    func testMonitorRestoreRejectedByConcurrentUserRestoreSchedulesRetryAndThenNoOps() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = AgentControlTestClock(now: start)
        let scheduler = AgentControlManualScheduler()
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { "lease-1" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 60, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)
        clock.now = start.addingTimeInterval(61)
        await hardware.blockNextSnapshot()
        let restoreTask = Task {
            try await service.restoreAuto(reason: "user auto")
        }
        await hardware.waitForBlockedSnapshot()

        await scheduler.fireLastScheduledOperation()

        var restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [])
        let auditBeforeRestoreCompletes = try String(contentsOf: directory.appendingPathComponent("audit.jsonl"), encoding: .utf8)
        XCTAssertTrue(auditBeforeRestoreCompletes.contains("\"action\":\"restore-retry-scheduled\""))
        await hardware.releaseBlockedSnapshot()
        _ = try await restoreTask.value

        await scheduler.fireLastScheduledOperation()

        restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        let status = await service.status()
        XCTAssertNil(status.activeLease)
    }

    func testMonitorRestoreFailureRetriesAndRestoresOnNextFire() async throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = AgentControlTestClock(now: start)
        let scheduler = AgentControlManualScheduler()
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { "lease-1" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 60, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)
        await hardware.failNextRestoreAuto()
        clock.now = start.addingTimeInterval(61)

        await scheduler.fireLastScheduledOperation()

        var restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [])
        XCTAssertEqual(try store.loadActiveLease()?.id, "lease-1")

        await scheduler.fireLastScheduledOperation()

        restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        let status = await service.status()
        XCTAssertNil(status.activeLease)
    }

    func testMonitorTickRestoresWhenSensorsDisappearDuringLease() async throws {
        let scheduler = AgentControlManualScheduler()
        let fan = Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [fan]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)
        await hardware.setSnapshot(HardwareSnapshot(
            fans: [fan],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        ))

        await scheduler.fireLastScheduledOperation()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
    }

    func testMonitorSensorLossKeepsLeasePendingWhenFreshRestoreSnapshotFails() async throws {
        let scheduler = AgentControlManualScheduler()
        let fan = Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [fan]))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware,
            policy: AgentControlPolicy(enabled: true),
            store: store,
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1_000) },
            leaseID: { "lease-1" },
            expiryScheduler: { delay, operation in scheduler.schedule(after: delay, operation: operation) }
        )
        let request = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 75, reason: "Build", idempotencyKey: "key")
        _ = try await service.prepare(request)
        await hardware.enqueueSnapshot(HardwareSnapshot(
            fans: [fan],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        await hardware.failSnapshotsWhenQueuedResultsAreDrained()

        await scheduler.fireLastScheduledOperation()

        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [])
        let status = await service.status()
        XCTAssertEqual(status.activeLease?.id, "lease-1")
    }

    func testPrepareIsRateLimitedWithinCooldownWindow() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let policy = AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30)
        let clock = AgentControlTestClock(now: Date(timeIntervalSince1970: 1_000))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware, policy: policy, store: store,
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { UUID().uuidString }
        )

        let request1 = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "first", idempotencyKey: "key-1")
        _ = try await service.prepare(request1)
        _ = try await service.restoreAuto(reason: "done")

        clock.now = clock.now.addingTimeInterval(10) // only 10s, cooldown is 30s
        let request2 = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "second", idempotencyKey: "key-2")
        let status2 = try await service.prepare(request2)

        XCTAssertNil(status2.activeLease)
        XCTAssertEqual(status2.lastErrorCode, .prepareRateLimited)
        XCTAssertEqual(status2.lastDecision?.retryAfterSeconds, 20)
        XCTAssertEqual(status2.policy?.prepareCooldownSeconds, 30)
    }

    func testPrepareAllowedAfterCooldownExpires() async throws {
        let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500)]))
        let policy = AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30)
        let clock = AgentControlTestClock(now: Date(timeIntervalSince1970: 1_000))
        let store = AgentControlStore(directory: temporaryDirectory())
        let service = AgentControlService(
            hardware: hardware, policy: policy, store: store,
            thermalReader: { .nominal },
            now: { clock.now },
            leaseID: { UUID().uuidString }
        )

        let request1 = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "first", idempotencyKey: "key-1")
        _ = try await service.prepare(request1)
        _ = try await service.restoreAuto(reason: "done")

        clock.now = clock.now.addingTimeInterval(31) // past 30s cooldown
        let request2 = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "second", idempotencyKey: "key-2")
        let status2 = try await service.prepare(request2)

        XCTAssertNotNil(status2.activeLease)
        XCTAssertNil(status2.lastErrorCode)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vifty-agent-service-\(UUID().uuidString)", isDirectory: true)
    }

    private static func fan(
        id: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        hardwareMode: FanHardwareMode = .automatic
    ) -> Fan {
        Fan(
            id: id,
            name: "Fan \(id)",
            currentRPM: minimumRPM,
            minimumRPM: minimumRPM,
            maximumRPM: maximumRPM,
            controllable: true,
            hardwareMode: hardwareMode,
            hardwareModeKey: "F\(id)Md",
            targetRPM: minimumRPM,
            controlEligibility: .trusted
        )
    }

    private static func sensor(_ celsius: Double = 61) -> TemperatureSensor {
        TemperatureSensor(id: "Tp09", name: "CPU Performance Core 1", celsius: celsius, source: .synthetic)
    }

    private static func snapshot(fans: [Fan]) -> HardwareSnapshot {
        HardwareSnapshot(
            fans: fans,
            temperatureSensors: [sensor()],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
    }
}

private final class AgentControlTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(now: Date) {
        self.value = now
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

private final class AgentControlManualScheduler: @unchecked Sendable {
    private struct ScheduledOperation {
        var operation: @Sendable () async -> Void
        var isCancelled: Bool
    }

    private let lock = NSLock()
    private var scheduledOperations: [Int: ScheduledOperation] = [:]
    private var scheduledOrder: [Int] = []
    private var nextID = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func schedule(after delay: TimeInterval, operation: @escaping @Sendable () async -> Void) -> AgentControlScheduledExpiry {
        lock.lock()
        let id = nextID
        nextID += 1
        scheduledOperations[id] = ScheduledOperation(operation: operation, isCancelled: false)
        scheduledOrder.append(id)
        let readyWaiters = waiters.filter { scheduledOrder.count >= $0.0 }
        waiters.removeAll { scheduledOrder.count >= $0.0 }
        lock.unlock()
        readyWaiters.forEach { $0.1.resume() }
        return AgentControlScheduledExpiry { [weak self] in
            self?.cancel(id: id)
        }
    }

    func fireLastScheduledOperation() async {
        let operation = lastScheduledOperation()
        await operation?()
    }

    func fireAllScheduledOperations() async {
        let operations = allScheduledOperations()
        for operation in operations {
            await operation()
        }
    }

    func waitForScheduledOperationCount(atLeast count: Int) async {
        if scheduledOperationCountAtLeast(count) { return }
        await withCheckedContinuation { continuation in
            if appendWaiterIfNeeded(count: count, continuation: continuation) {
                continuation.resume()
            }
        }
    }

    private func scheduledOperationCountAtLeast(_ count: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return scheduledOrder.count >= count
    }

    private func appendWaiterIfNeeded(count: Int, continuation: CheckedContinuation<Void, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if scheduledOrder.count >= count {
            return true
        } else {
            waiters.append((count, continuation))
            return false
        }
    }

    private func lastScheduledOperation() -> (@Sendable () async -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        for id in scheduledOrder.reversed() {
            guard var scheduled = scheduledOperations[id], !scheduled.isCancelled else { continue }
            scheduled.isCancelled = true
            scheduledOperations[id] = scheduled
            return scheduled.operation
        }
        return nil
    }

    private func allScheduledOperations() -> [@Sendable () async -> Void] {
        lock.lock()
        defer { lock.unlock() }
        var operations: [@Sendable () async -> Void] = []
        for id in scheduledOrder {
            guard var scheduled = scheduledOperations[id], !scheduled.isCancelled else { continue }
            scheduled.isCancelled = true
            scheduledOperations[id] = scheduled
            operations.append(scheduled.operation)
        }
        return operations
    }

    private func cancel(id: Int) {
        lock.lock()
        if var scheduled = scheduledOperations[id] {
            scheduled.isCancelled = true
            scheduledOperations[id] = scheduled
        }
        lock.unlock()
    }
}

private final class FailingActiveLeaseSaveStore: AgentControlPersisting, @unchecked Sendable {
    enum Failure: Error {
        case saveFailed
    }

    private let lock = NSLock()
    private let base: AgentControlStore
    private var shouldFailNextNonNilSave = true
    private var attempts: [String?] = []

    init(directory: URL) {
        self.base = AgentControlStore(directory: directory)
    }

    var saveAttempts: [String?] {
        lock.withLock { attempts }
    }

    func saveActiveLease(_ lease: AgentCoolingLease?) throws {
        let shouldFail = lock.withLock { () -> Bool in
            attempts.append(lease?.id)
            guard lease != nil, shouldFailNextNonNilSave else { return false }
            shouldFailNextNonNilSave = false
            return true
        }
        if shouldFail { throw Failure.saveFailed }
        try base.saveActiveLease(lease)
    }

    func loadActiveLease() throws -> AgentCoolingLease? {
        try base.loadActiveLease()
    }

    func appendAuditEvent(_ event: AgentControlAuditEvent) throws {
        try base.appendAuditEvent(event)
    }

    func loadRecentAuditEvents(limit: Int) throws -> [AgentControlAuditEvent] {
        try base.loadRecentAuditEvents(limit: limit)
    }
}

private actor AgentServiceFakeHardware: HardwareService {
    enum Failure: Error, Equatable {
        case applyFailed
        case snapshotFailed
        case restoreFailed
        case ownershipFailed
    }

    private enum SnapshotResult {
        case success(HardwareSnapshot)
        case failure(Failure)
    }

    var snapshotValue: HardwareSnapshot
    var snapshotCallCount = 0
    var appliedCommands: [FanCommand] = []
    var restoredFanIDs: [Int] = []
    var restoreAllAutoRequests: [AutoRestoreRequest] = []
    var ownedRollbackRequests: [(transactionID: String, owner: FanControlOwner, reason: String)] = []
    var fanControlOwnershipStatusCallCount = 0
    var failingApplyFanID: Int?
    private var queuedSnapshotResults: [SnapshotResult] = []
    private var shouldFailSnapshotsWhenQueueDrained = false
    private var restoreAutoFailuresRemaining = 0
    private var shouldBlockNextSnapshot = false
    private var blockedSnapshotContinuation: CheckedContinuation<Void, Never>?
    private var blockedSnapshotEnteredContinuation: CheckedContinuation<Void, Never>?
    private enum OwnershipResult {
        case success(FanControlOwnershipStatus)
        case failure
    }
    private var ownershipStatusValue: FanControlOwnershipStatus = .osManaged
    private var queuedOwnershipResults: [OwnershipResult] = []
    private var ownershipAfterApplyOverride: FanControlOwnershipStatus?

    init(snapshot: HardwareSnapshot, failingApplyFanID: Int? = nil) {
        self.snapshotValue = snapshot
        self.failingApplyFanID = failingApplyFanID
    }

    func setSnapshot(_ snapshot: HardwareSnapshot) {
        snapshotValue = snapshot
    }

    func enqueueSnapshot(_ snapshot: HardwareSnapshot) {
        queuedSnapshotResults.append(.success(snapshot))
    }

    func failSnapshotsWhenQueuedResultsAreDrained() {
        shouldFailSnapshotsWhenQueueDrained = true
    }

    func failNextRestoreAuto() {
        restoreAutoFailuresRemaining += 1
    }

    func enqueueOwnershipStatus(_ status: FanControlOwnershipStatus) {
        queuedOwnershipResults.append(.success(status))
    }

    func enqueueOwnershipFailure() {
        queuedOwnershipResults.append(.failure)
    }

    func setOwnershipAfterApply(_ status: FanControlOwnershipStatus) {
        ownershipAfterApplyOverride = status
    }

    func blockNextSnapshot() {
        shouldBlockNextSnapshot = true
    }

    func waitForBlockedSnapshot() async {
        if blockedSnapshotContinuation != nil { return }
        await withCheckedContinuation { continuation in
            blockedSnapshotEnteredContinuation = continuation
        }
    }

    func releaseBlockedSnapshot() {
        let continuation = blockedSnapshotContinuation
        blockedSnapshotContinuation = nil
        continuation?.resume()
    }

    func snapshot() async throws -> HardwareSnapshot {
        snapshotCallCount += 1
        if shouldBlockNextSnapshot {
            shouldBlockNextSnapshot = false
            let enteredContinuation = blockedSnapshotEnteredContinuation
            blockedSnapshotEnteredContinuation = nil
            await withCheckedContinuation { continuation in
                blockedSnapshotContinuation = continuation
                enteredContinuation?.resume()
            }
        }
        if !queuedSnapshotResults.isEmpty {
            let result = queuedSnapshotResults.removeFirst()
            switch result {
            case .success(let snapshot):
                return snapshot
            case .failure(let failure):
                throw failure
            }
        }
        if shouldFailSnapshotsWhenQueueDrained {
            throw Failure.snapshotFailed
        }
        return snapshotValue
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {
        if command.fanID == failingApplyFanID {
            throw Failure.applyFailed
        }
        appliedCommands.append(command)
    }

    func fanControlOwnershipStatus() async throws -> FanControlOwnershipStatus {
        fanControlOwnershipStatusCallCount += 1
        if !queuedOwnershipResults.isEmpty {
            switch queuedOwnershipResults.removeFirst() {
            case .success(let status): return status
            case .failure: throw Failure.ownershipFailed
            }
        }
        return ownershipStatusValue
    }

    func applyAgentFanControl(
        _ request: AgentFanControlRequest
    ) async throws -> FanControlTransactionResult {
        let currentSnapshot = try await snapshot()
        let fansByID = Dictionary(uniqueKeysWithValues: currentSnapshot.fans.map { ($0.id, $0) })
        for fanID in request.targetRPMByFanID.keys.sorted() {
            guard let fan = fansByID[fanID], let rpm = request.targetRPMByFanID[fanID] else {
                throw ViftyError.helperRejected("Missing fake fan \(fanID).")
            }
            try await apply(FanCommand(fanID: fanID, mode: .fixedRPM(rpm)), fan: fan)
        }
        ownershipStatusValue = FanControlOwnershipStatus(
            owner: .agent(leaseID: request.leaseID),
            phase: .active,
            transactionID: request.transactionID,
            expectedFanIDs: request.expectedFanIDs,
            recoveryPending: false
        )
        if let ownershipAfterApplyOverride {
            ownershipStatusValue = ownershipAfterApplyOverride
            self.ownershipAfterApplyOverride = nil
        }
        return FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: .agent(leaseID: request.leaseID),
            phase: .active,
            expectedFanIDs: request.expectedFanIDs,
            confirmedFanIDs: request.expectedFanIDs
        )
    }

    func restoreAuto(fan: Fan) async throws {
        if restoreAutoFailuresRemaining > 0 {
            restoreAutoFailuresRemaining -= 1
            throw Failure.restoreFailed
        }
        restoredFanIDs.append(fan.id)
    }

    func restoreFanControlIfOwned(
        transactionID: String,
        owner: FanControlOwner,
        reason: String,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult? {
        ownedRollbackRequests.append((transactionID, owner, reason))
        guard ownershipStatusValue.transactionID == transactionID,
              ownershipStatusValue.owner == owner,
              ownershipStatusValue.phase == .active,
              !ownershipStatusValue.recoveryPending else {
            return nil
        }
        return try await restoreAllAuto(
            AutoRestoreRequest(
                transactionID: transactionID,
                expectedFanIDs: ownershipStatusValue.expectedFanIDs,
                reason: reason,
                allowRestoreAllTrustedFans: false
            ),
            beforeOwnershipClear: beforeOwnershipClear
        )
    }

    func restoreAllAuto(
        _ request: AutoRestoreRequest,
        beforeOwnershipClear: @escaping @Sendable () throws -> Void
    ) async throws -> FanControlTransactionResult {
        restoreAllAutoRequests.append(request)
        let currentSnapshot = try await snapshot()
        let expectedFanIDs: [Int]
        if request.expectedFanIDs.isEmpty && request.allowRestoreAllTrustedFans {
            guard !currentSnapshot.fans.isEmpty,
                  currentSnapshot.fans.map(\.id).count == Set(currentSnapshot.fans.map(\.id)).count,
                  currentSnapshot.fans.allSatisfy({
                      SMCFanControlKeys.isValidFanID($0.id)
                          && $0.controlEligibility.canRestoreOSManagedMode
                  }) else {
                throw ViftyError.helperRejected(
                    "Global Auto restore requires one complete trusted fan inventory."
                )
            }
            expectedFanIDs = currentSnapshot.fans.map(\.id).sorted()
        } else {
            expectedFanIDs = request.expectedFanIDs
        }
        let fansByID = Dictionary(uniqueKeysWithValues: currentSnapshot.fans.map { ($0.id, $0) })
        for fanID in expectedFanIDs {
            guard let fan = fansByID[fanID] else {
                throw ViftyError.helperRejected("Expected fan \(fanID) is missing from fake restore telemetry.")
            }
            try await restoreAuto(fan: fan)
        }
        try beforeOwnershipClear()
        ownershipStatusValue = .osManaged
        return FanControlTransactionResult(
            transactionID: request.transactionID,
            owner: nil,
            phase: nil,
            expectedFanIDs: expectedFanIDs,
            confirmedFanIDs: expectedFanIDs
        )
    }
}
