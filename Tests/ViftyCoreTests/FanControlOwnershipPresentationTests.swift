import XCTest
@testable import Vifty
import ViftyCore

final class FanControlOwnershipPresentationTests: XCTestCase {
    func testOSManagedStatusIsTheOnlyStatusThatClaimsMacOSOwnership() {
        let presentation = FanControlOwnershipPresentation.resolve(.osManaged)

        XCTAssertEqual(presentation.owner, .macOS)
        XCTAssertEqual(presentation.ownerText, "Owner: macOS")
        XCTAssertFalse(presentation.canRequestRestoreAuto)
    }

    func testConfirmedManualAndAgentTransactionsOfferRestore() {
        let manual = FanControlOwnershipPresentation.resolve(active(owner: .manual(sessionID: "manual")))
        let agent = FanControlOwnershipPresentation.resolve(active(owner: .agent(leaseID: "lease")))

        XCTAssertEqual(manual.owner, .viftyManual)
        XCTAssertEqual(agent.owner, .agent)
        XCTAssertTrue(manual.canRequestRestoreAuto)
        XCTAssertTrue(agent.canRequestRestoreAuto)
    }

    func testRecoveryPendingTakesPrecedenceOverStaleOwnerFields() {
        let status = FanControlOwnershipStatus(
            owner: .manual(sessionID: "manual"),
            phase: .restorePending,
            transactionID: "transaction",
            expectedFanIDs: [0, 1],
            recoveryPending: true
        )

        let presentation = FanControlOwnershipPresentation.resolve(status)

        XCTAssertEqual(presentation.owner, .recovery)
        XCTAssertTrue(presentation.canRequestRestoreAuto)
    }

    func testMissingLegacyOrInconsistentStatusNeverClaimsAnOwner() {
        let legacy = FanControlOwnershipStatus(
            protocolVersion: FanControlProtocolVersion.current - 1,
            owner: nil,
            phase: nil,
            transactionID: nil,
            expectedFanIDs: [],
            recoveryPending: false
        )
        let partial = FanControlOwnershipStatus(
            owner: .manual(sessionID: "manual"),
            phase: .active,
            transactionID: nil,
            expectedFanIDs: [0],
            recoveryPending: false
        )

        for status in [nil, legacy, partial] {
            let presentation = FanControlOwnershipPresentation.resolve(status)
            XCTAssertEqual(presentation.owner, .mixedOrUnknown)
            XCTAssertEqual(presentation.ownerText, "Owner: Confirmation required")
            XCTAssertFalse(presentation.canRequestRestoreAuto)
        }
    }

    private func active(owner: FanControlOwner) -> FanControlOwnershipStatus {
        FanControlOwnershipStatus(
            owner: owner,
            phase: .active,
            transactionID: "transaction",
            expectedFanIDs: [0, 1],
            recoveryPending: false
        )
    }
}
