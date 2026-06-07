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
        let restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [0])
        XCTAssertNil(try store.loadActiveLease())
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

    func testRestoreAutoRejectedWhilePrepareSnapshotInProgress() async throws {
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

        do {
            _ = try await service.restoreAuto(reason: "done")
            XCTFail("Expected restore to be rejected while prepare is in progress")
        } catch ViftyError.helperRejected(let message) {
            XCTAssertEqual(message, "Agent control operation already in progress.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let restoredBeforePrepareCompletes = await hardware.restoredFanIDs
        XCTAssertEqual(restoredBeforePrepareCompletes, [])

        await hardware.releaseBlockedSnapshot()
        let status = try await prepareTask.value

        XCTAssertEqual(status.activeLease?.id, "lease-1")
        let applied = await hardware.appliedCommands
        XCTAssertEqual(applied, [FanCommand(fanID: 0, mode: .fixedRPM(3750))])
        let restoredAfterPrepareCompletes = await hardware.restoredFanIDs
        XCTAssertEqual(restoredAfterPrepareCompletes, [])
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

    func testMonitorRestoreRejectedByConcurrentMutationRetriesAndRestoresOnNextFire() async throws {
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
        await hardware.blockNextSnapshot()
        let deniedRequest = AgentControlRequest(workload: .test, durationSeconds: 99_999, maxRPMPercent: 75, reason: "Denied", idempotencyKey: "denied-key")
        let prepareTask = Task {
            try await service.prepare(deniedRequest)
        }
        await hardware.waitForBlockedSnapshot()

        await scheduler.fireLastScheduledOperation()

        var restored = await hardware.restoredFanIDs
        XCTAssertEqual(restored, [])
        await hardware.releaseBlockedSnapshot()
        _ = try await prepareTask.value

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
