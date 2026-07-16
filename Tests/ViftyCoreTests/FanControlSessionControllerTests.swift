import XCTest
@testable import ViftyCore
@testable import Vifty

final class FanControlSessionControllerTests: XCTestCase {
    func testAutoOperationPreemptsManualOperationAndRejectsStaleCompletion() {
        var controller = FanControlSessionController(now: { Date(timeIntervalSince1970: 1_000) })
        let draft = makeDraft(mode: .fixed)
        let manual = controller.beginManualOperation(currentSessionExpiresAt: nil)
        _ = controller.registerManualApply(
            manual,
            draft: draft,
            mode: .fixedRPM(2_800)
        )
        controller.markCoordinatorConfigured(manual.operation)

        let auto = controller.beginAutoOperation()

        XCTAssertFalse(controller.isCurrent(manual.operation))
        XCTAssertFalse(controller.isCurrentManual(manual.operation, selectedMode: .fixed))
        XCTAssertTrue(controller.isCurrent(auto))
        XCTAssertFalse(controller.hasManualApplyAttempt)
    }

    func testManualDeadlineAndExpiryUseInjectedClock() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        var controller = FanControlSessionController(now: { currentDate })
        let draft = makeDraft(mode: .fixed, runLimit: .minutes(10))
        let manual = controller.beginManualOperation(currentSessionExpiresAt: nil)

        let deadline = controller.registerManualApply(
            manual,
            draft: draft,
            mode: .fixedRPM(2_800)
        )

        XCTAssertEqual(deadline, Date(timeIntervalSince1970: 1_600))
        XCTAssertFalse(controller.shouldRestoreExpiredManualSession(
            selectedMode: .fixed,
            manualSessionExpiresAt: deadline
        ))
        currentDate = Date(timeIntervalSince1970: 1_600)
        XCTAssertTrue(controller.shouldRestoreExpiredManualSession(
            selectedMode: .fixed,
            manualSessionExpiresAt: deadline
        ))
        XCTAssertFalse(controller.shouldRestoreExpiredManualSession(
            selectedMode: .auto,
            manualSessionExpiresAt: deadline
        ))
    }

    func testSuccessfulManualReconciliationCommitsDraftAndDeadline() {
        var controller = FanControlSessionController(now: { Date(timeIntervalSince1970: 2_000) })
        let appliedDraft = makeDraft(mode: .curve, runLimit: .minutes(30))
        let manual = controller.beginManualOperation(currentSessionExpiresAt: nil)
        _ = controller.registerManualApply(
            manual,
            draft: appliedDraft,
            mode: controller.fanMode(for: appliedDraft)
        )
        controller.markCoordinatorConfigured(manual.operation)

        let reconciliation = controller.reconcileManualApplyAfterSuccessfulPoll(
            operationSelectedMode: .curve,
            controlState: ControlState(
                mode: controller.fanMode(for: appliedDraft),
                manualControlActive: true
            ),
            currentDraft: appliedDraft
        )

        XCTAssertEqual(reconciliation, FanControlSessionReconciliation(
            manualSessionExpiresAt: Date(timeIntervalSince1970: 3_800),
            applyState: .applied
        ))
        XCTAssertFalse(controller.hasManualApplyAttempt)
        XCTAssertFalse(controller.hasPendingChanges(
            currentDraft: appliedDraft,
            selectedMode: .curve
        ))
    }

    func testSuccessfulPollDoesNotCommitUnconfiguredOrMismatchedAttempt() {
        var controller = FanControlSessionController(now: { Date(timeIntervalSince1970: 1_000) })
        let draft = makeDraft(mode: .fixed)
        let manual = controller.beginManualOperation(currentSessionExpiresAt: nil)
        _ = controller.registerManualApply(
            manual,
            draft: draft,
            mode: .fixedRPM(2_800)
        )

        XCTAssertNil(controller.reconcileManualApplyAfterSuccessfulPoll(
            operationSelectedMode: .fixed,
            controlState: ControlState(mode: .fixedRPM(2_800), manualControlActive: true),
            currentDraft: draft
        ))

        controller.markCoordinatorConfigured(manual.operation)
        XCTAssertNil(controller.reconcileManualApplyAfterSuccessfulPoll(
            operationSelectedMode: .fixed,
            controlState: ControlState(mode: .fixedRPM(3_000), manualControlActive: true),
            currentDraft: draft
        ))
    }

    func testPresentationStateReflectsDirtyAndRevertedDrafts() {
        var controller = FanControlSessionController()
        let appliedDraft = makeDraft(mode: .fixed)
        controller.recordAutoRestorationApplied(currentDraft: appliedDraft)
        var editedDraft = appliedDraft
        editedDraft.fixedRPM = 3_200

        XCTAssertEqual(controller.presentationApplyState(
            currentDraft: editedDraft,
            selectedMode: .fixed,
            applyState: .applied
        ), .pending)
        XCTAssertEqual(controller.presentationApplyState(
            currentDraft: appliedDraft,
            selectedMode: .fixed,
            applyState: .pending
        ), .applied)
    }

    private func makeDraft(
        mode: ModeSelection,
        runLimit: ManualRunLimit = .minutes(30)
    ) -> FanControlDraft {
        FanControlDraft(
            mode: mode,
            manualRunLimit: runLimit,
            fixedRPM: 2_800,
            fixedFanTargets: [],
            usePerFanFixedRPM: false,
            curve: FanCurveDraft(
                startTemperature: 55,
                startRPM: 1_400,
                rampTemperature: 70,
                rampRPM: 3_500,
                highTemperature: 85,
                highRPM: 6_000
            ),
            selectedSensorID: "Tp09",
            usePerFanOverrides: false,
            fanOverrides: []
        )
    }
}
