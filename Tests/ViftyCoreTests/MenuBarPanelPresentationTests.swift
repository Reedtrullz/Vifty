import XCTest
@testable import Vifty
import ViftyCore

final class MenuBarPanelPresentationTests: XCTestCase {
    func testHealthyAutoHidesRestoreAuto() {
        let presentation = MenuBarPanelPresentation.resolve(input: input())

        XCTAssertEqual(presentation.primaryAction, .openMainWindow)
        XCTAssertFalse(presentation.showsRestoreAuto)
        XCTAssertEqual(presentation.stateTitle, "Auto control active")
    }

    func testActiveManualSessionShowsRestoreAuto() {
        let controlSession = ControlSessionPresentation.resolve(ControlSessionInput(
            helperHealth: .healthy(fanCount: 2),
            helperHealthNeedsAttention: false,
            helperRepairActionAvailable: false,
            manualFanControlAvailable: true,
            controlOwnershipNeedsAttention: false,
            controlOwnershipSummary: "Vifty Fixed owns fan targets",
            agentCoolingSummary: nil,
            hasAgentCoolingLease: false,
            agentCoolingNeedsAttention: false,
            manualControlAttentionSummary: nil,
            selectedMode: .fixed,
            applyState: .applied,
            manualSessionExpiresAt: nil
        ))
        let presentation = MenuBarPanelPresentation.resolve(input: input(
            controlSession: controlSession,
            isManualControlActive: true
        ))

        XCTAssertEqual(controlSession.state, .manual)
        XCTAssertEqual(controlSession.primaryAction, .apply)
        XCTAssertTrue(presentation.showsRestoreAuto)
    }

    func testHelperBlockedActiveManualSessionOffersOnlyRecoveryPath() {
        let presentation = MenuBarPanelPresentation.resolve(input: input(
            controlSession: ControlSessionPresentation(
                state: .blocked,
                title: "Manual fan control blocked",
                summary: "Helper needs repair",
                detail: "Repair the helper from the main Vifty window.",
                expiryText: nil,
                primaryAction: .repairHelper,
                primaryActionTitle: "Repair Helper",
                primaryActionHelp: "Repair the helper before fan writes.",
                primaryActionDisabled: false
            ),
            isManualControlActive: true
        ))

        XCTAssertEqual(presentation.primaryAction, .openMainWindow)
        XCTAssertEqual(presentation.primaryActionTitle, "Open Vifty")
        XCTAssertFalse(presentation.showsRestoreAuto)
    }

    func testAgentSessionDoesNotSurfaceTargetOrRecoveryDetailVerbatim() {
        let targetSummary = "Agent build cooling until 14:20 · F0 4,200 RPM, F1 4,100 RPM"
        let recoveryDetail = "Restore Auto before starting another workload."
        let expiryText = "Auto restore scheduled at 14:20"
        let presentation = MenuBarPanelPresentation.resolve(input: input(
            controlSession: ControlSessionPresentation(
                state: .agentCooling,
                title: "Agent cooling active",
                summary: targetSummary,
                detail: recoveryDetail,
                expiryText: expiryText,
                primaryAction: .restoreAuto,
                primaryActionTitle: "Restore Auto",
                primaryActionHelp: "Restore automatic macOS fan control.",
                primaryActionDisabled: false
            )
        ))

        XCTAssertEqual(presentation.headline, "Bounded workload cooling")
        let visibleText = [
            presentation.stateTitle,
            presentation.headline,
            presentation.ownerText,
            presentation.attentionText
        ].compactMap { $0 }
        XCTAssertFalse(visibleText.contains(targetSummary))
        XCTAssertFalse(visibleText.contains(recoveryDetail))
        XCTAssertFalse(visibleText.contains(expiryText))
        XCTAssertFalse(visibleText.joined(separator: " ").contains("4,200 RPM"))
    }

    func testAgentRestorePendingUsesResolvedAttentionTitle() {
        let controlSession = ControlSessionPresentation.resolve(ControlSessionInput(
            helperHealth: .healthy(fanCount: 2),
            helperHealthNeedsAttention: false,
            helperRepairActionAvailable: false,
            manualFanControlAvailable: true,
            controlOwnershipNeedsAttention: false,
            controlOwnershipSummary: "Vifty owns fan targets",
            agentCoolingSummary: "Agent build cooling expired; waiting for Auto restore",
            hasAgentCoolingLease: true,
            agentCoolingNeedsAttention: true,
            manualControlAttentionSummary: nil,
            selectedMode: .auto,
            applyState: .applied,
            manualSessionExpiresAt: nil
        ))
        let presentation = MenuBarPanelPresentation.resolve(input: input(
            controlSession: controlSession
        ))

        XCTAssertEqual(controlSession.title, "Agent cooling needs attention")
        XCTAssertEqual(presentation.stateTitle, controlSession.title)
        XCTAssertNotEqual(presentation.headline, presentation.stateTitle)
        XCTAssertNotEqual(presentation.attentionText, presentation.stateTitle)
        XCTAssertNotEqual(presentation.attentionText, presentation.headline)
        XCTAssertNotEqual(presentation.headline, "Agent cooling active")
    }

    func testVisibleActionLabelsAreConcise() {
        let presentations = [
            MenuBarPanelPresentation.resolve(input: input()),
            MenuBarPanelPresentation.resolve(input: input(
                controlSession: ControlSessionPresentation(
                    state: .blocked,
                    title: "Manual fan control blocked",
                    summary: "Helper needs repair",
                    detail: nil,
                    expiryText: nil,
                    primaryAction: .repairHelper,
                    primaryActionTitle: "Repair Helper",
                    primaryActionHelp: "Repair the helper before fan writes.",
                    primaryActionDisabled: false
                )
            ))
        ]

        XCTAssertTrue(presentations.allSatisfy { $0.visibleActionTitles.allSatisfy { $0.count <= 30 } })
    }

    private func input(
        controlSession: ControlSessionPresentation = ControlSessionPresentation(
            state: .ready,
            title: "Auto control active",
            summary: "macOS owns fan control",
            detail: nil,
            expiryText: nil,
            primaryAction: .none,
            primaryActionTitle: "",
            primaryActionHelp: "",
            primaryActionDisabled: true
        ),
        isManualControlActive: Bool = false
    ) -> MenuBarPanelPresentation.Input {
        MenuBarPanelPresentation.Input(
            controlSession: controlSession,
            ownerText: "Owner: macOS",
            attentionText: nil,
            fans: [
                Fan(
                    id: 0,
                    name: "Left fan",
                    currentRPM: 2200,
                    minimumRPM: 1700,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .automatic
                )
            ],
            isManualControlActive: isManualControlActive
        )
    }
}
