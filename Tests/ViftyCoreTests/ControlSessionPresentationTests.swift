import XCTest
@testable import Vifty

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

    func testActiveAgentCoolingPrioritizesRestoreAuto() {
        let presentation = ControlSessionPresentation.resolve(input(
            agentCoolingSummary: "Agent Build cooling until 14:30",
            hasAgentCoolingLease: true,
            selectedMode: .curve,
            applyState: .pending
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
            selectedMode: .auto
        ))

        XCTAssertEqual(presentation.state, .agentCooling)
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

        XCTAssertEqual(presentation.state, .manual)
        XCTAssertEqual(presentation.primaryAction, .apply)
        XCTAssertEqual(presentation.primaryActionTitle, "Apply Changes")
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
        manualSessionExpiresAt: Date? = nil
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
            manualSessionExpiresAt: manualSessionExpiresAt
        )
    }
}
