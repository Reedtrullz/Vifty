import Foundation
import SwiftUI
import ViftyCore

@MainActor
extension AppModel {
    func applyModeSelection() {
        if selectedMode == .auto {
            restoreAuto()
        } else {
            markFanControlDraftPending()
        }
    }

    func performModeSelectionAction() {
        Task { await performModeSelectionActionNow() }
    }

    func performModeSelectionActionNow() async {
        switch controlSessionPresentation.primaryAction {
        case .restoreAuto:
            await restoreAutoNow()
        case .apply:
            _ = await applyCurrentModeSelection()
        case .none, .repairHelper, .copyDiagnostics:
            break
        }
    }

    func restoreAuto() {
        let generation = beginAutoRestoreOperation()
        Task { await performAutoRestore(generation: generation) }
    }

    var canRequestRestoreAuto: Bool {
        FanControlOwnershipPresentation
            .resolve(fanControlOwnershipStatus)
            .canRequestRestoreAuto
    }

    func markFanControlDraftPending() {
        fanControlApplyState = fanControlSessionController.draftPendingApplyState(
            currentDraft: currentFanControlDraft,
            selectedMode: selectedMode,
            controlMode: controlState.mode,
            applyState: fanControlApplyState
        )
    }

    func applyPendingFanControl() {
        Task { _ = await applyCurrentModeSelection() }
    }

    @discardableResult
    func applyCurrentModeSelection() async -> FanControlApplyResult {
        if selectedMode == .auto {
            await restoreAutoNow()
            if case .failed(let message) = fanControlApplyState {
                return .failed(message: message)
            }
            return selectedMode == .auto && controlState.mode == .auto ? .applied : .superseded
        }

        if usePerFanFixedRPM, let fans = snapshot?.fans {
            ensureFixedFanTargets(for: fans)
        }
        let manualOperation = fanControlSessionController.beginManualOperation(
            currentSessionExpiresAt: manualSessionExpiresAt
        )
        let operation = manualOperation.operation
        let draft = currentFanControlDraft
        let mode = fanMode(for: draft)

        await refreshManualControlPreflight()
        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        if let blockedReason = manualFanControlBlockedReason {
            lastError = "Manual fan control blocked: \(blockedReason)"
            fanControlApplyState = .blocked(reason: blockedReason)
            await syncState()
            guard manualFanControlOperationIsCurrent(operation) else {
                return .superseded
            }
            return .blocked(reason: blockedReason)
        }

        fanControlApplyState = .applying
        lastError = nil
        let provisionalSessionExpiresAt = fanControlSessionController.registerManualApply(
            manualOperation,
            draft: draft,
            mode: mode
        )
        manualSessionExpiresAt = provisionalSessionExpiresAt

        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        await coordinator.setFixedFanTargets(fixedFanTargetMap(for: draft))
        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        await coordinator.setFanOverrides(draft.usePerFanOverrides ? draft.fanOverrides : [])
        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        await coordinator.setMode(mode)
        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        fanControlSessionController.markCoordinatorConfigured(operation)

        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        // A successful hardware poll is necessary but not sufficient to commit
        // the draft or its run limit. The fresh daemon ownership read below is
        // the final Apply boundary.
        await pollingController.freshPollOnce { [weak self] pollingOperation in
            await self?.performPollOnce(
                operation: pollingOperation,
                reconcileManualApply: false
            )
        }
        guard manualFanControlOperationIsCurrent(operation) else {
            return .superseded
        }
        if let lastError {
            restorePreviousManualDeadline(for: manualOperation)
            fanControlApplyState = .failed(message: lastError)
            return .failed(message: lastError)
        }
        do {
            let confirmedOwnership = try await coordinator.confirmCurrentManualOwnership()
            guard manualFanControlOperationIsCurrent(operation) else {
                return .superseded
            }
            fanControlOwnershipStatus = confirmedOwnership
            fanControlOwnershipStatusError = nil
        } catch {
            guard manualFanControlOperationIsCurrent(operation) else {
                return .superseded
            }
            let message = "Manual fan control could not be confirmed after Apply: \(error.localizedDescription)"
            rejectUnconfirmedManualApply(
                manualOperation,
                provisionalSessionExpiresAt: provisionalSessionExpiresAt
            )
            lastError = message
            fanControlOwnershipStatus = nil
            fanControlOwnershipStatusError = error.localizedDescription
            fanControlApplyState = .failed(message: message)
            return .failed(message: message)
        }
        guard controlState.mode == mode, controlState.manualControlActive else {
            let message = "Manual fan control could not be confirmed after Apply."
            rejectUnconfirmedManualApply(
                manualOperation,
                provisionalSessionExpiresAt: provisionalSessionExpiresAt
            )
            lastError = message
            fanControlApplyState = .failed(message: message)
            return .failed(message: message)
        }
        reconcileManualApplyAttemptAfterSuccessfulPoll()
        return .applied
    }

    func restoreAutoNow() async {
        let generation = beginAutoRestoreOperation()
        await performAutoRestore(generation: generation)
    }

    func performAutoRestore(generation: FanControlSessionOperation) async {
        guard fanControlOperationIsCurrent(generation) else { return }
        await coordinator.setMode(
            .auto,
            unreadableJournalRecoveryAuthority: .explicitOperator
        )
        guard fanControlOperationIsCurrent(generation) else { return }

        // Auto is a safety-priority operation. Do not coalesce it behind an
        // in-flight manual poll: invalidate that poll's publication token and
        // start a concurrent Auto tick so the daemon can preempt at the next
        // physical fan boundary.
        pollingController.supersedeActivePoll()
        await pollOnce()
        guard fanControlOperationIsCurrent(generation) else { return }
        // The coordinator's protocol-v2 full-Auto transaction routes through
        // AgentControlService in the daemon and clears the lease atomically.
        // Refresh visibility only; never issue a second lease-clear restore.
        await refreshAgentControlStatus()
        guard fanControlOperationIsCurrent(generation) else { return }
        if let lastError {
            fanControlApplyState = .failed(message: lastError)
            await notifyAutoRestoreFailure(lastError)
        } else if controlState.mode != .auto || controlState.manualControlActive {
            let message = "Auto restore could not be confirmed."
            lastError = message
            fanControlApplyState = .failed(message: message)
            await notifyAutoRestoreFailure(message)
        } else {
            recordAutoRestorationApplied()
        }
    }

    func updateManualTargetDriftStability() {
        let driftedIDs = Set(currentManualTargetDriftFans.map(\.id))
        guard !driftedIDs.isEmpty else {
            manualTargetDriftSampleCounts = [:]
            return
        }

        manualTargetDriftSampleCounts = driftedIDs.reduce(into: [:]) { countsByFanID, fanID in
            let count = (manualTargetDriftSampleCounts[fanID] ?? 0) + 1
            countsByFanID[fanID] = min(count, Self.manualTargetDriftAttentionSampleCount)
        }
    }

    var manualResponseAttentionIsWarranted: Bool {
        if thermalPressure == .serious || thermalPressure == .critical {
            return true
        }
        guard let sensor = snapshot?.highestTemperature else { return false }
        return sensor.celsius >= Self.highTemperatureAttentionThreshold
    }

    func fixedModeTargetSummary(fallbackRPM: Int) -> String {
        guard perFanFixedRPMApplies else { return "\(fallbackRPM) RPM" }

        let controllableFans = snapshot?.fans.filter(\.controllable) ?? []
        if !controllableFans.isEmpty {
            return controllableFans.map { fan in
                let rpm = expectedManualTargetRPM(for: fan)
                    ?? FanCurve.clamp(fallbackRPM, fan.minimumRPM, fan.maximumRPM)
                return "\(fan.name) \(rpm) RPM"
            }
            .joined(separator: ", ")
        }

        let targets = fixedFanTargets.sorted { $0.fanID < $1.fanID }
        guard !targets.isEmpty else { return "per-fan RPM" }
        return targets
            .map { target in "F\(target.fanID) \(target.rpm) RPM" }
            .joined(separator: ", ")
    }

    func expectedManualTargetRPM(for fan: Fan) -> Int? {
        if let lastAppliedRPM = controlState.lastAppliedRPM[fan.id] {
            return lastAppliedRPM
        }

        switch controlState.mode {
        case .auto:
            return nil
        case .fixedRPM(let rpm):
            if perFanFixedRPMApplies, let target = fixedFanTarget(for: fan.id)?.rpm {
                return FanCurve.clamp(target, fan.minimumRPM, fan.maximumRPM)
            }
            return FanCurve.clamp(rpm, fan.minimumRPM, fan.maximumRPM)
        case .temperatureCurve(let curve):
            guard let snapshot,
                  let sensor = snapshot.temperatureSensors.first(where: { $0.id == (curve.sensorID ?? controlState.selectedSensorID) })
                    ?? selectedSensor else {
                return nil
            }
            return curve.targetRPM(
                for: sensor.celsius,
                minimumRPM: fan.minimumRPM,
                maximumRPM: fan.maximumRPM
            )
        }
    }

    var autoSystemModeFans: [Fan] {
        guard controlState.mode == .auto else { return [] }
        return snapshot?.fans.filter { $0.hardwareMode == .system } ?? []
    }

    var autoForcedModeFans: [Fan] {
        guard controlState.mode == .auto else { return [] }
        return snapshot?.fans.filter { $0.hardwareMode == .forced } ?? []
    }

    var autoUnknownModeFans: [Fan] {
        guard controlState.mode == .auto else { return [] }
        return snapshot?.fans.filter { fan in
            if case .unknown = fan.hardwareMode {
                return true
            }
            return false
        } ?? []
    }

    var autoMissingModeFans: [Fan] {
        guard controlState.mode == .auto else { return [] }
        return snapshot?.fans.filter { $0.hardwareMode == nil } ?? []
    }

    func fanIDList(_ fans: [Fan]) -> String {
        fans.map { "F\($0.id)" }.joined(separator: ", ")
    }

    var fanRange: ClosedRange<Double> {
        let bounds = fixedRPMBaseBounds
        return Double(bounds.minimumRPM)...Double(bounds.maximumRPM)
    }

    func rpm(forPercent percent: Int) -> Int {
        let bounds = fixedRPMBaseBounds
        let span = bounds.maximumRPM - bounds.minimumRPM
        let rpm = bounds.minimumRPM + Int((Double(span) * Double(percent) / 100.0).rounded())
        return FanCurve.clamp(rpm, bounds.minimumRPM, bounds.maximumRPM)
    }

    func currentCurve() -> FanCurve {
        FanCurve(sensorID: resolvedCurveSensorID, points: [
            CurvePoint(temperatureCelsius: curveStartTemp, rpm: Int(curveStartRPM.rounded())),
            CurvePoint(temperatureCelsius: curveMidTemp, rpm: Int(curveMidRPM.rounded())),
            CurvePoint(temperatureCelsius: curveMaxTemp, rpm: Int(curveMaxRPM.rounded()))
        ])
    }

    func fixedFanTargetMap(for draft: FanControlDraft) -> [Int: Int] {
        guard draft.mode == .fixed, draft.usePerFanFixedRPM else { return [:] }
        if let fans = snapshot?.fans {
            guard fans.filter(\.controllable).count > 1 else { return [:] }
        } else {
            guard draft.fixedFanTargets.count > 1 else { return [:] }
        }
        return draft.fixedFanTargets.reduce(into: [Int: Int]()) { targetsByID, target in
            targetsByID[target.fanID] = target.rpm
        }
    }

    var perFanFixedRPMApplies: Bool {
        guard usePerFanFixedRPM else { return false }
        if let fans = snapshot?.fans {
            return fans.filter(\.controllable).count > 1
        }
        return fixedFanTargets.count > 1
    }

    func selectedFanMode() -> FanMode {
        fanMode(for: currentFanControlDraft)
    }

    func fanMode(for draft: FanControlDraft) -> FanMode {
        fanControlSessionController.fanMode(for: draft)
    }

    func applyCurveOverrides() {
        markFanControlDraftPending()
    }

    func restoreAutoIfManualSessionExpired() async -> FanControlSessionOperation? {
        guard fanControlSessionController.shouldRestoreExpiredManualSession(
            selectedMode: selectedMode,
            manualSessionExpiresAt: manualSessionExpiresAt
        ) else {
            return nil
        }

        let generation = beginAutoRestoreOperation()
        guard fanControlOperationIsCurrent(generation) else { return nil }
        await coordinator.setMode(.auto)
        guard fanControlOperationIsCurrent(generation) else { return nil }
        return generation
    }

    func recordAutoRestorationApplied() {
        fanControlSessionController.recordAutoRestorationApplied(currentDraft: currentFanControlDraft)
        fanControlApplyState = .applied
    }

#if DEBUG
    func configureReviewFixtureAppliedFanControlDraft() {
        fanControlSessionController.recordAutoRestorationApplied(currentDraft: currentFanControlDraft)
        fanControlApplyState = .applied
    }
#endif

    func beginAutoRestoreOperation() -> FanControlSessionOperation {
        let operation = fanControlSessionController.beginAutoOperation()
        fanControlApplyState = .applying
        lastError = nil
        selectedMode = .auto
        manualSessionExpiresAt = nil
        return operation
    }

    func fanControlOperationIsCurrent(_ operation: FanControlSessionOperation) -> Bool {
        fanControlSessionController.isCurrent(operation)
    }

    func manualFanControlOperationIsCurrent(_ operation: FanControlSessionOperation) -> Bool {
        fanControlSessionController.isCurrentManual(operation, selectedMode: selectedMode)
    }

    func canCommitAutoRestoration(generation: FanControlSessionOperation) -> Bool {
        fanControlSessionController.canCommitAutoRestoration(
            operation: generation,
            selectedMode: selectedMode,
            controlState: controlState
        )
    }

    func reconcileManualApplyAttemptAfterSuccessfulPoll() {
        guard let reconciliation = fanControlSessionController.reconcileManualApplyAfterSuccessfulPoll(
            operationSelectedMode: selectedMode,
            controlState: controlState,
            currentDraft: currentFanControlDraft
        ) else { return }
        manualSessionExpiresAt = reconciliation.manualSessionExpiresAt
        fanControlApplyState = reconciliation.applyState
    }

    func restorePreviousManualDeadline(for operation: FanControlManualOperation) {
        // Use the operation's immutable capture: the polling path may have
        // advanced controller reconciliation state before a later check fails.
        manualSessionExpiresAt = operation.previousSessionExpiresAt
    }

    func rejectUnconfirmedManualApply(
        _ operation: FanControlManualOperation,
        provisionalSessionExpiresAt: Date?
    ) {
        fanControlSessionController.rejectManualApply(operation.operation)
        // If this was the first finite Apply there is no previous deadline to
        // restore. Keep the provisional bound because the hardware transaction
        // completed before its final ownership read failed; never turn that
        // bounded user request into an indefinite manual session.
        manualSessionExpiresAt = operation.previousSessionExpiresAt
            ?? provisionalSessionExpiresAt
    }

    func shouldPreserveManualIntent(afterTickFailure error: Error, attemptedMode: FanMode) -> Bool {
        guard attemptedMode != .auto else { return false }
        guard let viftyError = error as? ViftyError else { return true }

        switch viftyError {
        case .helperRejected, .smcUnavailable, .smcOpenFailed, .smcCallFailed, .smcKeyUnavailable, .smcWriteRejected:
            return true
        case .unsupportedHardware:
            return false
        case .noTemperatureSensors:
            return true
        case .noControllableFans:
            return true
        }
    }

    func refreshAgentControlStatus() async {
        do {
            agentControlStatus = try await agentStatusReader()
            agentCoolingEnabled = agentControlStatus?.policy?.enabled
            agentControlStatusError = nil
        } catch {
            agentControlStatusError = error.localizedDescription
        }
    }

    func setAgentCoolingEnabled(_ enabled: Bool) async {
        do {
            guard let status = try await agentPolicySetter(enabled) else { return }
            agentControlStatus = status
            agentCoolingEnabled = status.policy?.enabled
            agentControlStatusError = nil
        } catch {
            agentControlStatusError = error.localizedDescription
        }
    }

    func refreshFanControlOwnershipStatus() async {
        do {
            fanControlOwnershipStatus = try await coordinator.fanControlOwnershipStatus()
            fanControlOwnershipStatusError = nil
        } catch {
            fanControlOwnershipStatus = nil
            fanControlOwnershipStatusError = error.localizedDescription
        }
    }

    func refreshManualControlPreflight() async {
        daemonResponding = await daemonPing()
        if let snapshot {
            daemonReachable = daemonResponding || !snapshot.fans.isEmpty
        } else {
            daemonReachable = daemonResponding
        }

        // A draft must never infer ownership from its selected mode or from
        // stale fan telemetry. Refresh the daemon's transaction status as part
        // of the same preflight that authorizes every manual Apply attempt.
        await refreshFanControlOwnershipStatus()

        guard agentControlStatus?.activeLease == nil || agentControlStatusError != nil else {
            return
        }

        do {
            guard let status = try await agentStatusReader() else { return }
            agentControlStatus = status
            agentCoolingEnabled = status.policy?.enabled
            agentControlStatusError = nil
        } catch {
            agentControlStatusError = error.localizedDescription
        }
    }

    func syncCurveDefaultsIfNeeded(from snapshot: HardwareSnapshot) {
        guard !curveDefaultsSynced,
              let fan = snapshot.fans.first(where: \.controllable) else { return }
        curveStartRPM = Double(fan.minimumRPM)
        curveMaxRPM = Double(fan.maximumRPM)
        if selectedSensorID == nil {
            setProgrammaticSelectedSensorID(selectedSensor?.id)
        }
        curveDefaultsSynced = true
    }

    func setProgrammaticSelectedSensorID(_ sensorID: String?) {
        isSettingSelectedSensorProgrammatically = true
        selectedSensorID = sensorID
        isSettingSelectedSensorProgrammatically = false
    }

}
