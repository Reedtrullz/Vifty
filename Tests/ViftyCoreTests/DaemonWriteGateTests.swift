import XCTest
@testable import ViftyCore

final class DaemonWriteGateTests: XCTestCase {
    func testCleanStartupAllowsWrites() async throws {
        let gate = DaemonWriteGate(ownershipStatus: .osManaged)

        try await gate.requireWriteAllowed()
        let writesAllowed = await gate.writesAllowed
        let blockReason = await gate.blockReason
        XCTAssertTrue(writesAllowed)
        XCTAssertNil(blockReason)
    }

    func testStartupRecoveryFailureKeepsStableMachineCodeAndSeparateHumanDetail() async {
        let gate = DaemonWriteGate(
            startupRecoveryError: "fan 1 restore readback was unknown",
            ownershipStatus: .osManaged
        )

        do {
            try await gate.requireWriteAllowed()
            XCTFail("Expected read-only startup gate")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("fan 1 restore readback was unknown"))
        }
        let status = await gate.statusOverlay(.osManaged)
        XCTAssertEqual(status.owner, .recovery)
        XCTAssertEqual(status.phase, .restorePending)
        XCTAssertTrue(status.recoveryPending)
        XCTAssertEqual(status.errorCode, "STARTUP_RECOVERY_BLOCKED")
        XCTAssertEqual(status.errorMessage, "fan 1 restore readback was unknown")
        XCTAssertEqual(status.recoveryAttemptCount, 1)
    }

    func testPendingJournalBlocksEvenWhenRecoveryCallDidNotThrow() async {
        let pending = FanControlOwnershipStatus(
            owner: .recovery,
            phase: .restorePending,
            transactionID: "tx-1",
            expectedFanIDs: [0, 1],
            recoveryPending: true,
            errorCode: "RESTORE_UNCONFIRMED"
        )
        let gate = DaemonWriteGate(ownershipStatus: pending)

        let writesAllowed = await gate.writesAllowed
        XCTAssertFalse(writesAllowed)
        let overlaid = await gate.statusOverlay(pending)
        XCTAssertEqual(overlaid.errorCode, "RESTORE_UNCONFIRMED")
        XCTAssertNotNil(overlaid.errorMessage)
    }

    func testOnlyConfirmedCleanRecoveryUnblocksWrites() async throws {
        let gate = DaemonWriteGate(
            startupRecoveryError: "startup failed",
            ownershipStatus: .osManaged
        )
        let stillPending = FanControlOwnershipStatus(
            owner: .recovery,
            phase: .restorePending,
            transactionID: "tx-1",
            expectedFanIDs: [0],
            recoveryPending: true,
            errorCode: "RESTORE_UNCONFIRMED"
        )

        await gate.recordRecoveryResult(ownershipStatus: stillPending)
        let pendingWritesAllowed = await gate.writesAllowed
        let pendingStatus = await gate.statusOverlay(stillPending)
        XCTAssertFalse(pendingWritesAllowed)
        XCTAssertEqual(pendingStatus.recoveryAttemptCount, 2)

        await gate.recordRecoveryResult(ownershipStatus: .osManaged)
        try await gate.requireWriteAllowed()
        let recoveredWritesAllowed = await gate.writesAllowed
        XCTAssertTrue(recoveredWritesAllowed)
    }
}
