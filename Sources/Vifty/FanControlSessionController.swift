import Foundation
import ViftyCore

struct FanControlSessionOperation: Equatable {
    fileprivate let generation: UInt64
}

struct FanControlManualOperation: Equatable {
    var operation: FanControlSessionOperation
    var previousSessionExpiresAt: Date?
}

struct FanControlSessionReconciliation: Equatable {
    var manualSessionExpiresAt: Date?
    var applyState: FanControlApplyState
}

struct FanControlSessionController {
    private struct ManualApplyAttempt {
        var operation: FanControlSessionOperation
        var draft: FanControlDraft
        var mode: FanMode
        var previousSessionExpiresAt: Date?
        var coordinatorConfigured: Bool
    }

    private let now: () -> Date
    private var operationGeneration: UInt64 = 0
    private var lastAppliedDraft: FanControlDraft?
    private var manualApplyAttempt: ManualApplyAttempt?

    init(now: @escaping () -> Date = { Date() }) {
        self.now = now
    }

    var hasManualApplyAttempt: Bool {
        manualApplyAttempt != nil
    }

    func hasPendingChanges(
        currentDraft: FanControlDraft,
        selectedMode: ModeSelection
    ) -> Bool {
        guard let lastAppliedDraft else { return selectedMode != .auto }
        return currentDraft.isDirty(comparedTo: lastAppliedDraft)
    }

    func presentationApplyState(
        currentDraft: FanControlDraft,
        selectedMode: ModeSelection,
        applyState: FanControlApplyState
    ) -> FanControlApplyState {
        let hasPendingChanges = hasPendingChanges(
            currentDraft: currentDraft,
            selectedMode: selectedMode
        )
        if hasPendingChanges, applyState == .applied {
            return .pending
        }
        if !hasPendingChanges,
           applyState == .pending,
           manualApplyAttempt == nil {
            return .applied
        }
        return applyState
    }

    func draftPendingApplyState(
        currentDraft: FanControlDraft,
        selectedMode: ModeSelection,
        controlMode: FanMode,
        applyState: FanControlApplyState
    ) -> FanControlApplyState {
        guard selectedMode != .auto else { return applyState }
        if !hasPendingChanges(currentDraft: currentDraft, selectedMode: selectedMode),
           manualApplyAttempt == nil,
           let lastAppliedDraft,
           controlMode == fanMode(for: lastAppliedDraft) {
            return .applied
        }
        return applyState == .applying ? applyState : .pending
    }

    mutating func beginManualOperation(
        currentSessionExpiresAt: Date?
    ) -> FanControlManualOperation {
        let previousSessionExpiresAt = manualApplyAttempt?.previousSessionExpiresAt
            ?? currentSessionExpiresAt
        let operation = beginOperation()
        return FanControlManualOperation(
            operation: operation,
            previousSessionExpiresAt: previousSessionExpiresAt
        )
    }

    mutating func registerManualApply(
        _ manualOperation: FanControlManualOperation,
        draft: FanControlDraft,
        mode: FanMode
    ) -> Date? {
        guard isCurrent(manualOperation.operation) else {
            return manualOperation.previousSessionExpiresAt
        }
        manualApplyAttempt = ManualApplyAttempt(
            operation: manualOperation.operation,
            draft: draft,
            mode: mode,
            previousSessionExpiresAt: manualOperation.previousSessionExpiresAt,
            coordinatorConfigured: false
        )
        return deadline(for: mode, runLimit: draft.manualRunLimit)
    }

    mutating func markCoordinatorConfigured(_ operation: FanControlSessionOperation) {
        guard manualApplyAttempt?.operation == operation else { return }
        manualApplyAttempt?.coordinatorConfigured = true
    }

    mutating func rejectManualApply(_ operation: FanControlSessionOperation) {
        guard manualApplyAttempt?.operation == operation else { return }
        manualApplyAttempt = nil
    }

    mutating func beginAutoOperation() -> FanControlSessionOperation {
        beginOperation()
    }

    func isCurrent(_ operation: FanControlSessionOperation) -> Bool {
        operation.generation == operationGeneration
    }

    func isCurrentManual(
        _ operation: FanControlSessionOperation,
        selectedMode: ModeSelection
    ) -> Bool {
        isCurrent(operation) && selectedMode != .auto
    }

    func canCommitAutoRestoration(
        operation: FanControlSessionOperation,
        selectedMode: ModeSelection,
        controlState: ControlState
    ) -> Bool {
        isCurrent(operation)
            && selectedMode == .auto
            && controlState.mode == .auto
            && !controlState.manualControlActive
    }

    func shouldRestoreExpiredManualSession(
        selectedMode: ModeSelection,
        manualSessionExpiresAt: Date?
    ) -> Bool {
        guard selectedMode != .auto,
              let manualSessionExpiresAt else {
            return false
        }
        return now() >= manualSessionExpiresAt
    }

    mutating func recordAutoRestorationApplied(currentDraft: FanControlDraft) {
        manualApplyAttempt = nil
        lastAppliedDraft = currentDraft
    }

    mutating func reconcileManualApplyAfterSuccessfulPoll(
        operationSelectedMode: ModeSelection,
        controlState: ControlState,
        currentDraft: FanControlDraft
    ) -> FanControlSessionReconciliation? {
        guard let attempt = manualApplyAttempt,
              attempt.coordinatorConfigured,
              isCurrentManual(attempt.operation, selectedMode: operationSelectedMode),
              controlState.mode == attempt.mode,
              controlState.manualControlActive else {
            return nil
        }

        let deadline = deadline(for: attempt.mode, runLimit: attempt.draft.manualRunLimit)
        lastAppliedDraft = attempt.draft
        manualApplyAttempt = nil
        return FanControlSessionReconciliation(
            manualSessionExpiresAt: deadline,
            applyState: currentDraft == attempt.draft ? .applied : .pending
        )
    }

    func previousSessionDeadline(for operation: FanControlSessionOperation) -> Date? {
        guard let attempt = manualApplyAttempt,
              attempt.operation == operation else {
            return nil
        }
        return attempt.previousSessionExpiresAt
    }

    func fanMode(for draft: FanControlDraft) -> FanMode {
        switch draft.mode {
        case .auto:
            .auto
        case .fixed:
            .fixedRPM(Int(draft.fixedRPM.rounded()))
        case .curve:
            .temperatureCurve(FanCurve(sensorID: draft.selectedSensorID, points: [
                CurvePoint(
                    temperatureCelsius: draft.curve.startTemperature,
                    rpm: Int(draft.curve.startRPM.rounded())
                ),
                CurvePoint(
                    temperatureCelsius: draft.curve.rampTemperature,
                    rpm: Int(draft.curve.rampRPM.rounded())
                ),
                CurvePoint(
                    temperatureCelsius: draft.curve.highTemperature,
                    rpm: Int(draft.curve.highRPM.rounded())
                )
            ]))
        }
    }

    private mutating func beginOperation() -> FanControlSessionOperation {
        operationGeneration &+= 1
        manualApplyAttempt = nil
        return FanControlSessionOperation(generation: operationGeneration)
    }

    private func deadline(for mode: FanMode, runLimit: ManualRunLimit) -> Date? {
        guard mode != .auto else { return nil }
        switch runLimit {
        case .indefinitely:
            return nil
        case .minutes(let minutes):
            return now().addingTimeInterval(TimeInterval(minutes * 60))
        }
    }
}
