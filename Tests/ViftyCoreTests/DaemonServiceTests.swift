import Darwin
import Foundation
import XCTest
@testable import ViftyCore
@testable import ViftyDaemonSupport
@testable import ViftyFanControlSafety

final class DaemonServiceTests: XCTestCase {
    func testNewDaemonBootstrapRevokesSameBootPreviousSessionAuthorityBeforeWriterBoundary() throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HelperMaintenanceAuthorityStore(
            directoryURL: root.appendingPathComponent("maintenance", isDirectory: true),
            requiredOwnerID: geteuid()
        )
        let issuedAt = Date(timeIntervalSince1970: 1_000)
        try store.save(HelperMaintenanceAuthorityReceipt(
            operation: .repair,
            tokenID: "session-a-token",
            tokenIssuedAt: issuedAt,
            authorizedAt: issuedAt.addingTimeInterval(1),
            expiresAt: issuedAt.addingTimeInterval(301),
            bootSessionID: "same-boot",
            daemonSessionID: "daemon-session-A",
            journalGeneration: 4,
            expectedFanIDs: [0],
            helperSHA256: String(repeating: "a", count: 64),
            quiesceGeneration: 2
        ))
        XCTAssertEqual(try store.load()?.daemonSessionID, "daemon-session-A")

        try DaemonService.revokeMaintenanceAuthorityBeforeBootstrap {
            try store.clear()
        }

        XCTAssertNil(try store.load(), "Session B must revoke session A's receipt even on the same boot")

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ViftyDaemonSupport/DaemonService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let revocation = try XCTUnwrap(source.range(
            of: "try revokeMaintenanceAuthorityBeforeBootstrap"
        ))
        let writerBoundary = try XCTUnwrap(source.range(
            of: "let exclusiveLock = try FanControlExclusiveLock()"
        ))
        XCTAssertLessThan(revocation.lowerBound, writerBoundary.lowerBound)
    }

    func testBootstrapAuthorityRevocationFailureFailsClosed() {
        XCTAssertThrowsError(
            try DaemonService.revokeMaintenanceAuthorityBeforeBootstrap {
                throw ViftyError.helperRejected("fixture receipt could not be revoked")
            }
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("could not be revoked"))
        }
    }

    func testLegacyAgentMutationSelectorsRejectWithoutHardwareWrites() throws {
        let fixture = try makeFixture(startupRecoveryError: nil)
        defer { fixture.cleanup() }
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 60,
            maxRPMPercent: 60,
            reason: "Legacy selector test",
            idempotencyKey: "legacy-selector"
        )
        let prepareError = DaemonServiceTestStringBox()
        let restoreError = DaemonServiceTestStringBox()

        fixture.service.prepareAgentControl(XPCAgentControlCoding.encode(request)) { _, error in
            prepareError.set(error)
        }
        fixture.service.restoreAgentControl("legacy restore") { _, error in
            restoreError.set(error)
        }

        XCTAssertTrue(prepareError.value?.contains("Legacy agent-control mutation selector is disabled") == true)
        XCTAssertTrue(restoreError.value?.contains("Legacy agent-control restore selector is disabled") == true)
        XCTAssertTrue(fixture.hardware.appliedFanIDs.isEmpty)
        XCTAssertTrue(fixture.hardware.restoredFanIDs.isEmpty)
    }

    func testProtocolV2AgentSelectorsApplyAndRestoreThroughTransactionalArbiter() async throws {
        let fixture = try makeFixture(startupRecoveryError: nil)
        defer { fixture.cleanup() }
        let request = AgentControlRequest(
            workload: .build,
            durationSeconds: 60,
            maxRPMPercent: 60,
            reason: "Protocol v2 selector test",
            idempotencyKey: "protocol-v2-selector"
        )

        let prepared = await prepareAgentControlV2(fixture.service, request: request)
        XCTAssertNil(prepared.error)
        XCTAssertEqual(prepared.value?.activeLease?.id.isEmpty, false)
        XCTAssertEqual(fixture.hardware.appliedFanIDs, [0, 1])

        let restored = await restoreAgentControlV2(fixture.service, reason: "Protocol v2 test complete")
        XCTAssertNil(restored.error)
        XCTAssertNil(restored.value?.activeLease)
        XCTAssertEqual(fixture.hardware.restoredFanIDs, [0, 1])
    }

    func testRecoveryPendingServiceStaysReachableAndRejectsNewWrites() async throws {
        let fixture = try makeFixture(startupRecoveryError: "startup restore was not confirmed")
        defer { fixture.cleanup() }

        var pinged = false
        fixture.service.ping { pinged = $0 }
        XCTAssertTrue(pinged)

        let status = await ownershipStatus(fixture.service)
        XCTAssertEqual(status.value?.owner, .recovery)
        XCTAssertTrue(status.value?.recoveryPending == true)
        XCTAssertEqual(status.value?.errorCode, "STARTUP_RECOVERY_BLOCKED")
        XCTAssertEqual(status.value?.recoveryAttemptCount, 1)

        let apply = await applyManual(fixture.service, request: Self.manualRequest())
        XCTAssertNil(apply.value)
        XCTAssertTrue(apply.error?.contains("read-only") == true)
        XCTAssertTrue(fixture.hardware.appliedFanIDs.isEmpty)
    }

    func testExplicitFullAutoRetriesRecoveryThenUnblocksExactlyOneManualBatch() async throws {
        let fixture = try makeFixture(startupRecoveryError: "startup restore was not confirmed")
        defer { fixture.cleanup() }

        let restore = await restoreAllAuto(fixture.service, request: AutoRestoreRequest(
            transactionID: "operator-retry",
            expectedFanIDs: [],
            reason: "Operator explicitly retried Auto",
            allowRestoreAllTrustedFans: true
        ))
        XCTAssertNil(restore.error)
        XCTAssertEqual(restore.value?.confirmedFanIDs, [0, 1])
        XCTAssertEqual(fixture.hardware.restoredFanIDs, [0, 1])

        let recoveredStatus = await ownershipStatus(fixture.service)
        XCTAssertNil(recoveredStatus.value?.owner)
        XCTAssertFalse(recoveredStatus.value?.recoveryPending == true)

        let apply = await applyManual(fixture.service, request: Self.manualRequest())
        XCTAssertNil(apply.error)
        XCTAssertEqual(apply.value?.confirmedFanIDs, [0, 1])
        XCTAssertEqual(fixture.hardware.appliedFanIDs, [0, 1])
    }

    func testCorruptLeaseWithoutJournalKeepsDaemonReachableReadOnlyWithZeroWrites() async throws {
        let root = try Self.makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let lock = try FanControlExclusiveLock(
            url: root.appendingPathComponent("fan-control/writer.lock"),
            requiredOwnerID: geteuid()
        )
        let hardware = DaemonServiceFakeHardware(fans: [Self.fan(id: 0), Self.fan(id: 1)])
        let snapshotProvider: @Sendable () throws -> HardwareSnapshot = { try hardware.freshSnapshot() }
        let arbiter = FanControlArbiter(
            hardware: hardware,
            journalStore: FanControlJournalStore(
                directoryURL: root.appendingPathComponent("fan-control/journal", isDirectory: true),
                requiredOwnerID: geteuid()
            ),
            exclusiveLock: lock
        )
        let agentDirectory = root.appendingPathComponent("agent-control", isDirectory: true)
        try FileManager.default.createDirectory(at: agentDirectory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(
            to: agentDirectory.appendingPathComponent("active-lease.json")
        )
        let agentControl = AgentControlService(
            hardware: DaemonTransactionalHardwareService(
                snapshotProvider: snapshotProvider,
                arbiter: arbiter
            ),
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(directory: agentDirectory),
            thermalReader: { .nominal },
            automaticallySchedulePersistedLeaseMonitor: false
        )

        let startupError: String
        do {
            _ = try await agentControl.recoverOnStartup()
            XCTFail("Expected startup recovery blocker")
            startupError = "missing blocker"
        } catch {
            startupError = error.localizedDescription
        }
        XCTAssertTrue(startupError.contains("STARTUP_RECOVERY_REQUIRES_OPERATOR"))
        XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
        XCTAssertTrue(hardware.restoredFanIDs.isEmpty)

        let service = DaemonService(
            exclusiveLock: lock,
            snapshotProvider: snapshotProvider,
            arbiter: arbiter,
            agentControl: agentControl,
            writeGate: DaemonWriteGate(
                startupRecoveryError: startupError,
                ownershipStatus: await arbiter.status()
            ),
            snapshotCacheTTL: 0
        )
        var pinged = false
        service.ping { pinged = $0 }
        XCTAssertTrue(pinged)
        let status = await ownershipStatus(service)
        XCTAssertEqual(status.value?.errorCode, "STARTUP_RECOVERY_BLOCKED")
        XCTAssertTrue(status.value?.recoveryPending == true)

        let apply = await applyManual(service, request: Self.manualRequest())
        XCTAssertNil(apply.value)
        XCTAssertTrue(apply.error?.contains("read-only") == true)
        XCTAssertTrue(hardware.appliedFanIDs.isEmpty)
        XCTAssertTrue(hardware.restoredFanIDs.isEmpty)
    }

    private func makeFixture(startupRecoveryError: String?) throws -> DaemonServiceFixture {
        let root = try Self.makeScratchDirectory()
        let lock = try FanControlExclusiveLock(
            url: root.appendingPathComponent("fan-control/writer.lock"),
            requiredOwnerID: geteuid()
        )
        let hardware = DaemonServiceFakeHardware(fans: [Self.fan(id: 0), Self.fan(id: 1)])
        let snapshotProvider: @Sendable () throws -> HardwareSnapshot = { try hardware.freshSnapshot() }
        let arbiter = FanControlArbiter(
            hardware: hardware,
            journalStore: FanControlJournalStore(
                directoryURL: root.appendingPathComponent("fan-control/journal", isDirectory: true),
                requiredOwnerID: geteuid()
            ),
            exclusiveLock: lock
        )
        let transactionalHardware = DaemonTransactionalHardwareService(
            snapshotProvider: snapshotProvider,
            arbiter: arbiter
        )
        let agentControl = AgentControlService(
            hardware: transactionalHardware,
            policy: AgentControlPolicy(enabled: true),
            store: AgentControlStore(
                directory: root.appendingPathComponent("agent-control", isDirectory: true)
            ),
            thermalReader: { .nominal },
            automaticallySchedulePersistedLeaseMonitor: false
        )
        let gate = DaemonWriteGate(
            startupRecoveryError: startupRecoveryError,
            ownershipStatus: .osManaged
        )
        let service = DaemonService(
            exclusiveLock: lock,
            snapshotProvider: snapshotProvider,
            arbiter: arbiter,
            agentControl: agentControl,
            writeGate: gate,
            snapshotCacheTTL: 0
        )
        return DaemonServiceFixture(
            root: root,
            lock: lock,
            service: service,
            hardware: hardware
        )
    }

    private func ownershipStatus(_ service: DaemonService) async -> CallbackValue<FanControlOwnershipStatus> {
        await withCheckedContinuation { continuation in
            service.fanControlOwnershipStatus { dictionary, error in
                continuation.resume(returning: CallbackValue(
                    value: dictionary.flatMap(XPCFanControlCoding.decodeOwnershipStatus),
                    error: error
                ))
            }
        }
    }

    private func applyManual(
        _ service: DaemonService,
        request: ManualFanControlRequest
    ) async -> CallbackValue<FanControlTransactionResult> {
        await withCheckedContinuation { continuation in
            service.applyManualFanControl(XPCFanControlCoding.encode(request)) { dictionary, error in
                continuation.resume(returning: CallbackValue(
                    value: dictionary.flatMap(XPCFanControlCoding.decodeTransactionResult),
                    error: error
                ))
            }
        }
    }

    private func restoreAllAuto(
        _ service: DaemonService,
        request: AutoRestoreRequest
    ) async -> CallbackValue<FanControlTransactionResult> {
        await withCheckedContinuation { continuation in
            service.restoreAllAuto(XPCFanControlCoding.encode(request)) { dictionary, error in
                continuation.resume(returning: CallbackValue(
                    value: dictionary.flatMap(XPCFanControlCoding.decodeTransactionResult),
                    error: error
                ))
            }
        }
    }

    private func prepareAgentControlV2(
        _ service: DaemonService,
        request: AgentControlRequest
    ) async -> CallbackValue<AgentControlStatus> {
        await withCheckedContinuation { continuation in
            service.prepareAgentControlV2(XPCAgentControlCoding.encode(request)) { dictionary, error in
                continuation.resume(returning: CallbackValue(
                    value: dictionary.flatMap(XPCAgentControlCoding.decodeStatus),
                    error: error
                ))
            }
        }
    }

    private func restoreAgentControlV2(
        _ service: DaemonService,
        reason: String
    ) async -> CallbackValue<AgentControlStatus> {
        await withCheckedContinuation { continuation in
            service.restoreAgentControlV2(reason) { dictionary, error in
                continuation.resume(returning: CallbackValue(
                    value: dictionary.flatMap(XPCAgentControlCoding.decodeStatus),
                    error: error
                ))
            }
        }
    }

    private static func manualRequest() -> ManualFanControlRequest {
        ManualFanControlRequest(
            transactionID: "manual-after-recovery",
            sessionID: "session-after-recovery",
            expectedFanIDs: [0, 1],
            targetRPMByFanID: [0: 3_200, 1: 3_300],
            reason: "Manual test batch"
        )
    }

    private static func fan(id: Int) -> Fan {
        Fan(
            id: id,
            name: "Fan \(id)",
            currentRPM: 1_400,
            minimumRPM: 1_400,
            maximumRPM: 6_000,
            controllable: true,
            hardwareMode: .automatic,
            hardwareModeKey: "F\(id)Md",
            targetRPM: 1_400,
            controlEligibility: .trusted
        )
    }

    private static func makeScratchDirectory() throws -> URL {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = repositoryRoot
            .appendingPathComponent(".build/test-scratch", isDirectory: true)
            .appendingPathComponent("daemon-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private struct CallbackValue<Value: Sendable>: Sendable {
    var value: Value?
    var error: String?
}

private final class DaemonServiceTestStringBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: String?

    var value: String? { lock.withLock { storage } }

    func set(_ value: String?) {
        lock.withLock { storage = value }
    }
}

private struct DaemonServiceFixture {
    var root: URL
    var lock: FanControlExclusiveLock
    var service: DaemonService
    var hardware: DaemonServiceFakeHardware

    func cleanup() {
        lock.release()
        try? FileManager.default.removeItem(at: root)
    }
}

private final class DaemonServiceFakeHardware: PrivilegedFanControlHardware, @unchecked Sendable {
    private let lock = NSLock()
    private var fansByID: [Int: Fan]
    private var applyLog: [Int] = []
    private var restoreLog: [Int] = []

    init(fans: [Fan]) {
        fansByID = Dictionary(uniqueKeysWithValues: fans.map { ($0.id, $0) })
    }

    var appliedFanIDs: [Int] { lock.withLock { applyLog } }
    var restoredFanIDs: [Int] { lock.withLock { restoreLog } }

    func freshSnapshot() throws -> HardwareSnapshot {
        HardwareSnapshot(
            fans: lock.withLock { fansByID.values.sorted { $0.id < $1.id } },
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU", celsius: 60, source: .synthetic)
            ],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )
    }

    func applyFixedRPM(_ rpm: Int, to fan: Fan) throws -> FanMutationReceipt {
        lock.withLock {
            applyLog.append(fan.id)
            var updated = fansByID[fan.id] ?? fan
            updated.hardwareMode = .forced
            updated.targetRPM = rpm
            updated.currentRPM = rpm
            fansByID[fan.id] = updated
        }
        return FanMutationReceipt(
            fanID: fan.id,
            requestedMode: .forced,
            observedMode: .forced,
            observedTargetRPM: rpm,
            forceTestDisabled: true,
            recoveryConfirmed: false,
            warnings: []
        )
    }

    func restoreOSManagedMode(for fan: Fan) throws -> FanMutationReceipt {
        lock.withLock {
            restoreLog.append(fan.id)
            var updated = fansByID[fan.id] ?? fan
            updated.hardwareMode = .automatic
            updated.targetRPM = updated.minimumRPM
            fansByID[fan.id] = updated
        }
        return FanMutationReceipt(
            fanID: fan.id,
            requestedMode: .automatic,
            observedMode: .automatic,
            observedTargetRPM: fan.minimumRPM,
            forceTestDisabled: true,
            recoveryConfirmed: true,
            warnings: []
        )
    }
}
