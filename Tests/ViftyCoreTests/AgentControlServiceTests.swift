import Foundation
import XCTest
@testable import ViftyCore

final class AgentControlServiceTests: XCTestCase {
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

    func testPrepareRestoresAlreadyAppliedFansWhenLaterApplyFails() async throws {
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
            XCTAssertEqual(restored, [0])
            XCTAssertNil(try store.loadActiveLease())
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPrepareRollbackAuditsIndividualFanRestoreFailures() async throws {
        let directory = temporaryDirectory()
        let store = AgentControlStore(directory: directory)
        let hardware = AgentServiceFakeHardware(
            snapshot: Self.snapshot(fans: [
                Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 4500),
                Self.fan(id: 1, minimumRPM: 1500, maximumRPM: 5500)
            ]),
            failingApplyFanID: 1
        )
        // Make restoreAuto fail during rollback for fan 0
        await hardware.failNextRestoreAuto()
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
            XCTAssertTrue(audit.contains("prepare-rollback-failure"))
            XCTAssertTrue(audit.contains("Failed to restore fan 0"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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
        XCTAssertEqual(restored, [])
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
        XCTAssertEqual(snapshotCallCount, 1)

        let statusB = try await service.prepare(requestB)

        XCTAssertEqual(statusB.activeLease?.id, "lease-a")
        XCTAssertEqual(statusB.lastErrorCode, .policyDenied)
        XCTAssertEqual(statusB.lastDecision?.errorCode, .policyDenied)
        XCTAssertEqual(statusB.lastDecision?.message, "Agent cooling lease already active. Restore Auto before starting a new lease.")
        applied = await hardware.appliedCommands
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(3750))])
        snapshotCallCount = await hardware.snapshotCallCount
        XCTAssertEqual(snapshotCallCount, 1)
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
        XCTAssertEqual(snapshotCallCount, 1)
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

    func testMonitorSensorLossRestoreUsesObservedSnapshotWhenLaterSnapshotsFail() async throws {
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
        XCTAssertEqual(restored, [0])
        let status = await service.status()
        XCTAssertNil(status.activeLease)
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

    private static func fan(id: Int, minimumRPM: Int, maximumRPM: Int) -> Fan {
        Fan(id: id, name: "Fan \(id)", currentRPM: minimumRPM, minimumRPM: minimumRPM, maximumRPM: maximumRPM, controllable: true)
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

private actor AgentServiceFakeHardware: HardwareService {
    enum Failure: Error, Equatable {
        case applyFailed
        case snapshotFailed
        case restoreFailed
    }

    private enum SnapshotResult {
        case success(HardwareSnapshot)
        case failure(Failure)
    }

    var snapshotValue: HardwareSnapshot
    var snapshotCallCount = 0
    var appliedCommands: [FanCommand] = []
    var restoredFanIDs: [Int] = []
    var failingApplyFanID: Int?
    private var queuedSnapshotResults: [SnapshotResult] = []
    private var shouldFailSnapshotsWhenQueueDrained = false
    private var restoreAutoFailuresRemaining = 0
    private var shouldBlockNextSnapshot = false
    private var blockedSnapshotContinuation: CheckedContinuation<Void, Never>?
    private var blockedSnapshotEnteredContinuation: CheckedContinuation<Void, Never>?

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

    func restoreAuto(fan: Fan) async throws {
        if restoreAutoFailuresRemaining > 0 {
            restoreAutoFailuresRemaining -= 1
            throw Failure.restoreFailed
        }
        restoredFanIDs.append(fan.id)
    }
}
