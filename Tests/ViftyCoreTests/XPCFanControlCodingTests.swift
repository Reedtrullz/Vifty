import XCTest
@testable import ViftyCore

final class XPCFanControlCodingTests: XCTestCase {
    func testManualRequestRoundTripKeepsExpectedDomainSeparateFromTargets() {
        let request = ManualFanControlRequest(
            transactionID: "manual-1",
            sessionID: "session-1",
            expectedFanIDs: [0, 1],
            targetRPMByFanID: [1: 3_200],
            reason: "Curve update"
        )

        XCTAssertEqual(
            XPCFanControlCoding.decodeManualRequest(XPCFanControlCoding.encode(request)),
            request
        )
    }

    func testAutoRestoreRequestRoundTripPreservesGlobalRestoreApproval() {
        let request = AutoRestoreRequest(
            transactionID: "restore-1",
            expectedFanIDs: [],
            reason: "Legacy global restore",
            allowRestoreAllTrustedFans: true,
            unreadableJournalRecoveryAuthority: .explicitOperator
        )

        XCTAssertEqual(
            XPCFanControlCoding.decodeAutoRestoreRequest(XPCFanControlCoding.encode(request)),
            request
        )
    }

    func testOlderAutoRestoreRequestDefaultsMissingUnreadableJournalAuthority() throws {
        let request = AutoRestoreRequest(
            transactionID: "restore-legacy",
            reason: "Older request",
            allowRestoreAllTrustedFans: true
        )
        let encoded = try XCTUnwrap(
            XPCFanControlCoding.encode(request).mutableCopy() as? NSMutableDictionary
        )
        encoded.removeObject(forKey: "unreadableJournalRecoveryAuthority")

        XCTAssertNil(
            XPCFanControlCoding.decodeAutoRestoreRequest(encoded)?
                .unreadableJournalRecoveryAuthority
        )
    }

    func testOwnershipStatusRoundTripsEveryOwnerShape() {
        let owners: [FanControlOwner] = [
            .manual(sessionID: "manual-1"),
            .agent(leaseID: "lease-1"),
            .recovery
        ]

        for owner in owners {
            let status = FanControlOwnershipStatus(
                owner: owner,
                phase: .restorePending,
                transactionID: "transaction-1",
                expectedFanIDs: [0, 1],
                confirmedOSManagedFanIDs: [0],
                recoveryPending: true,
                errorCode: "RESTORE_UNCONFIRMED",
                errorMessage: "Fan 1 still reports Forced mode.",
                recoveryAttemptCount: 3
            )
            XCTAssertEqual(
                XPCFanControlCoding.decodeOwnershipStatus(XPCFanControlCoding.encode(status)),
                status
            )
        }
    }

    func testOlderOwnershipStatusDefaultsMissingRecoveryAttemptMetadata() throws {
        let encoded = try XCTUnwrap(
            XPCFanControlCoding.encode(.osManaged).mutableCopy() as? NSMutableDictionary
        )
        encoded.removeObject(forKey: "errorMessage")
        encoded.removeObject(forKey: "recoveryAttemptCount")

        let decoded = try XCTUnwrap(XPCFanControlCoding.decodeOwnershipStatus(encoded))
        XCTAssertNil(decoded.errorMessage)
        XCTAssertEqual(decoded.recoveryAttemptCount, 0)
    }

    func testTransactionResultRoundTripPreservesConfirmedSetAndWarnings() {
        let result = FanControlTransactionResult(
            transactionID: "manual-1",
            owner: .manual(sessionID: "session-1"),
            phase: .active,
            expectedFanIDs: [0, 1],
            confirmedFanIDs: [0, 1],
            warnings: ["example"]
        )

        XCTAssertEqual(
            XPCFanControlCoding.decodeTransactionResult(XPCFanControlCoding.encode(result)),
            result
        )
    }

    func testManualRequestRejectsMalformedTargetFanID() {
        let malformed: NSDictionary = [
            "transactionID": "manual-1",
            "sessionID": "session-1",
            "expectedFanIDs": [0],
            "targetRPMByFanID": ["not-a-fan": 3_000],
            "reason": "Fixed"
        ]

        XCTAssertNil(XPCFanControlCoding.decodeManualRequest(malformed))
    }
}
