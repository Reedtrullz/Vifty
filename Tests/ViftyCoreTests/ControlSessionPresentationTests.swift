import XCTest
@testable import Vifty
import ViftyCore

final class ControlSessionPresentationTests: XCTestCase {
    func testHealthyAutoHasNoPrimaryAction() {
        let presentation = ControlSessionPresentation.resolve(input(
            helperHealth: .healthy(fanCount: 2),
            selectedMode: .auto
        ))

        XCTAssertEqual(presentation.state, .ready)
        XCTAssertEqual(presentation.primaryAction, .none)
        XCTAssertTrue(presentation.primaryActionDisabled)
    }

    func testTelemetryOnlyHelperOffersRepair() {
        let presentation = ControlSessionPresentation.resolve(input(
            helperHealth: .telemetryOnly,
            helperHealthNeedsAttention: true,
            helperRepairActionAvailable: true,
            manualFanControlAvailable: false,
            selectedMode: .fixed
        ))

        XCTAssertEqual(presentation.state, .blocked)
        XCTAssertEqual(presentation.primaryAction, .repairHelper)
        XCTAssertEqual(presentation.primaryActionTitle, "Repair Helper")
    }

    func testBlockedHelperPresentationUsesTheInstallerActionEverywhere() {
        let blocked = ControlSessionPresentation.resolve(input(
            helperHealth: .telemetryOnly,
            helperHealthNeedsAttention: true,
            helperRepairActionAvailable: true,
            manualFanControlAvailable: false,
            selectedMode: .fixed
        ))
        let install = HelperActionPresentation.resolve(
            backendStatus: .notRegistered,
            canInstall: true,
            isWorking: false,
            unavailableMessage: "unavailable"
        )

        let resolved = blocked.resolvingHelperAction(install)

        XCTAssertEqual(resolved.primaryAction, .repairHelper)
        XCTAssertEqual(resolved.primaryActionTitle, "Install Helper")
        XCTAssertEqual(resolved.primaryActionHelp, install.help)
        XCTAssertEqual(resolved.detail, install.description)
    }

    func testUnavailableInstallerActionFallsBackToReadOnlyDiagnostics() {
        let blocked = ControlSessionPresentation.resolve(input(
            helperHealth: .telemetryOnly,
            helperHealthNeedsAttention: true,
            helperRepairActionAvailable: true,
            manualFanControlAvailable: false,
            selectedMode: .fixed
        ))
        let unavailable = HelperActionPresentation.resolve(
            backendStatus: .unknown,
            canInstall: true,
            isWorking: false,
            unavailableMessage: "Fan helper status unknown"
        )

        let resolved = blocked.resolvingHelperAction(unavailable)

        XCTAssertEqual(resolved.primaryAction, .copyDiagnostics)
        XCTAssertEqual(resolved.primaryActionTitle, "Copy Support Evidence")
        XCTAssertFalse(resolved.primaryActionDisabled)
        XCTAssertEqual(resolved.detail, unavailable.description)
    }


    func testActiveAgentCoolingPrioritizesRestoreAuto() {
        let presentation = ControlSessionPresentation.resolve(input(
            agentCoolingSummary: "Agent Build cooling until 14:30",
            hasAgentCoolingLease: true,
            selectedMode: .curve,
            applyState: .pending,
            ownershipStatus: activeStatus(owner: .agent(leaseID: "lease-1"))
        ))

        XCTAssertEqual(presentation.state, .agentCooling)
        XCTAssertEqual(presentation.primaryAction, .restoreAuto)
        XCTAssertEqual(presentation.primaryActionTitle, "Restore Auto")
    }

    func testExpiredAgentCoolingStillPrioritizesRestoreAuto() {
        let presentation = ControlSessionPresentation.resolve(input(
            agentCoolingSummary: "Agent Build cooling expired; waiting for Auto restore",
            hasAgentCoolingLease: true,
            agentCoolingNeedsAttention: true,
            selectedMode: .auto,
            ownershipStatus: FanControlOwnershipStatus(
                owner: .recovery,
                phase: .restorePending,
                transactionID: "lease-1",
                expectedFanIDs: [0, 1],
                recoveryPending: true
            )
        ))

        XCTAssertEqual(presentation.state, .attention)
        XCTAssertEqual(presentation.title, "Fan recovery pending")
        XCTAssertEqual(presentation.primaryAction, .restoreAuto)
        XCTAssertFalse(presentation.primaryActionDisabled)
    }

    func testAgentStatusUnavailableWithoutLeaseDoesNotShowAgentCooling() {
        let presentation = ControlSessionPresentation.resolve(input(
            helperHealth: .healthy(fanCount: 2),
            controlOwnershipNeedsAttention: true,
            agentCoolingSummary: "Agent cooling status unavailable; repair helper before requesting cooling.",
            selectedMode: .auto
        ))

        XCTAssertEqual(presentation.state, .attention)
        XCTAssertEqual(presentation.primaryAction, .copyDiagnostics)
    }

    func testDirtyCurveOffersApplyChanges() {
        let presentation = ControlSessionPresentation.resolve(input(
            helperHealth: .healthy(fanCount: 2),
            selectedMode: .curve,
            applyState: .pending
        ))

        XCTAssertEqual(presentation.state, .draft)
        XCTAssertEqual(presentation.primaryAction, .apply)
        XCTAssertEqual(presentation.primaryActionTitle, "Apply Changes")
        XCTAssertEqual(presentation.summary, "Owner: macOS")
    }

    func testPendingAndFailedDraftsDoNotClaimViftyOwnershipWhileMacOSOwnsFans() {
        let pending = ControlSessionPresentation.resolve(input(
            helperHealth: .healthy(fanCount: 2),
            selectedMode: .curve,
            applyState: .pending,
            ownershipStatus: .osManaged
        ))
        let failed = ControlSessionPresentation.resolve(input(
            helperHealth: .healthy(fanCount: 2),
            selectedMode: .curve,
            applyState: .failed(message: "Daemon refused the transaction"),
            ownershipStatus: .osManaged
        ))

        XCTAssertEqual(pending.state, .draft)
        XCTAssertEqual(pending.title, "Manual draft pending")
        XCTAssertEqual(failed.state, .draft)
        XCTAssertEqual(failed.title, "Manual draft needs attention")
        XCTAssertFalse([pending, failed].contains { $0.title.contains("Vifty controls") })
    }

    func testPendingEditsDuringConfirmedManualOwnershipStillSayViftyControlsFans() {
        let presentation = ControlSessionPresentation.resolve(input(
            helperHealth: .healthy(fanCount: 2),
            selectedMode: .curve,
            applyState: .pending,
            ownershipStatus: activeStatus(owner: .manual(sessionID: "session-1"))
        ))

        XCTAssertEqual(presentation.state, .manual)
        XCTAssertEqual(presentation.title, "Vifty controls fans · changes pending")
        XCTAssertEqual(presentation.summary, "Owner: Vifty manual control")
    }

    func testConfirmedManualOwnershipKeepsRestorePrimaryWhenHelperNeedsRepair() {
        let presentation = ControlSessionPresentation.resolve(input(
            helperHealth: .telemetryOnly,
            helperHealthNeedsAttention: true,
            helperRepairActionAvailable: true,
            manualFanControlAvailable: false,
            selectedMode: .fixed,
            ownershipStatus: activeStatus(owner: .manual(sessionID: "session-1"))
        ))

        XCTAssertEqual(presentation.state, .attention)
        XCTAssertEqual(presentation.primaryAction, .restoreAuto)
        XCTAssertEqual(presentation.primaryActionTitle, "Restore Auto")
    }

    func testMissingOwnershipRequiresConfirmationAndDoesNotOfferRestore() {
        let presentation = ControlSessionPresentation.resolve(input(
            helperHealth: .healthy(fanCount: 2),
            selectedMode: .auto,
            ownershipStatus: nil
        ))

        XCTAssertEqual(presentation.state, .attention)
        XCTAssertEqual(presentation.title, "Fan ownership requires confirmation")
        XCTAssertEqual(presentation.primaryAction, .copyDiagnostics)
    }

    func testUnavailableManualControlOffersReadOnlyDiagnostics() {
        let presentation = ControlSessionPresentation.resolve(input(
            helperHealth: .noFanData,
            helperHealthNeedsAttention: true,
            manualFanControlAvailable: false,
            selectedMode: .fixed
        ))

        XCTAssertEqual(presentation.state, .blocked)
        XCTAssertEqual(presentation.primaryAction, .copyDiagnostics)
        XCTAssertEqual(presentation.primaryActionTitle, "Copy Support Evidence")
    }

    private func input(
        helperHealth: HelperHealthState = .checking,
        helperHealthNeedsAttention: Bool = false,
        helperRepairActionAvailable: Bool = false,
        manualFanControlAvailable: Bool = true,
        controlOwnershipNeedsAttention: Bool = false,
        controlOwnershipSummary: String = "Auto",
        agentCoolingSummary: String? = nil,
        hasAgentCoolingLease: Bool = false,
        agentCoolingNeedsAttention: Bool = false,
        manualControlAttentionSummary: String? = nil,
        selectedMode: ModeSelection = .auto,
        applyState: FanControlApplyState = .applied,
        manualSessionExpiresAt: Date? = nil,
        ownershipStatus: FanControlOwnershipStatus? = .osManaged
    ) -> ControlSessionInput {
        ControlSessionInput(
            helperHealth: helperHealth,
            helperHealthNeedsAttention: helperHealthNeedsAttention,
            helperRepairActionAvailable: helperRepairActionAvailable,
            manualFanControlAvailable: manualFanControlAvailable,
            controlOwnershipNeedsAttention: controlOwnershipNeedsAttention,
            controlOwnershipSummary: controlOwnershipSummary,
            agentCoolingSummary: agentCoolingSummary,
            hasAgentCoolingLease: hasAgentCoolingLease,
            agentCoolingNeedsAttention: agentCoolingNeedsAttention,
            manualControlAttentionSummary: manualControlAttentionSummary,
            selectedMode: selectedMode,
            applyState: applyState,
            manualSessionExpiresAt: manualSessionExpiresAt,
            ownershipStatus: ownershipStatus
        )
    }

    private func activeStatus(owner: FanControlOwner) -> FanControlOwnershipStatus {
        FanControlOwnershipStatus(
            owner: owner,
            phase: .active,
            transactionID: "transaction-1",
            expectedFanIDs: [0, 1],
            recoveryPending: false
        )
    }
}
