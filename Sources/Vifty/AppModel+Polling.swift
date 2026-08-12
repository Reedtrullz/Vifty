import Foundation
import SwiftUI
import ViftyCore

@MainActor
extension AppModel {
    func pollOnce() async {
        await pollingController.pollOnce { [weak self] operation in
            await self?.performPollOnce(operation: operation)
        }
    }

    func performPollOnce(
        operation: AppPollingOperation,
        reconcileManualApply: Bool = true
    ) async {
        guard pollingController.isCurrent(operation) else { return }
        let pollingIntervalState = ViftyLog.pollingSignposter.beginInterval("Hardware poll")
        defer {
            ViftyLog.pollingSignposter.endInterval("Hardware poll", pollingIntervalState)
        }
        let pollStartedAt = now()
        let shouldRefreshPowerTelemetry = shouldRefresh(
            lastRefreshAt: lastPowerTelemetryRefreshAt,
            interval: powerTelemetryRefreshInterval,
            at: pollStartedAt
        )
        let currentPower: PowerSnapshot
        let currentThermalPressure: ThermalPressure
        if shouldRefreshPowerTelemetry {
            currentPower = powerReader()
            currentThermalPressure = thermalReader()
            lastPowerTelemetryRefreshAt = pollStartedAt
            assignIfChanged(\.powerSnapshot, currentPower)
            assignIfChanged(\.thermalPressure, currentThermalPressure)
        } else {
            currentPower = powerSnapshot ?? PowerSnapshot()
            currentThermalPressure = thermalPressure
        }

        defer {
            if pollingController.isCurrent(operation) {
                hasCompletedHardwarePoll = true
                refreshMenuBarStatusItemIfNeeded()
            }
        }
        refreshCodexUsageIfNeeded()
        let expiredAutoOperationGeneration = await restoreAutoIfManualSessionExpired()
        guard pollingController.isCurrent(operation) else { return }
        let stateBeforeTick = await coordinator.state
        guard pollingController.isCurrent(operation) else { return }
        do {
            let nextSnapshot = try await coordinator.tick()
            guard pollingController.isCurrent(operation) else { return }
            recordHardwareSnapshot(nextSnapshot, power: currentPower, thermalPressure: currentThermalPressure)
            assignIfChanged(\.lastError, nil)
            await refreshDaemonPingIfNeeded(at: pollStartedAt, force: false)
            guard pollingController.isCurrent(operation) else { return }
            assignIfChanged(\.daemonReachable, daemonResponding || !nextSnapshot.fans.isEmpty)
            await refreshAgentControlStatusIfNeeded(at: pollStartedAt)
            guard pollingController.isCurrent(operation) else { return }
            await refreshFanControlOwnershipStatus()
            guard pollingController.isCurrent(operation) else { return }
            assignIfChanged(\.fanAccessMessage, fanAccessMessage(for: nextSnapshot))
            await syncState()
            guard pollingController.isCurrent(operation) else { return }
            if let expiredAutoOperationGeneration,
               canCommitAutoRestoration(generation: expiredAutoOperationGeneration) {
                recordAutoRestorationApplied()
            } else if reconcileManualApply {
                reconcileManualApplyAttemptAfterSuccessfulPoll()
            }
            await evaluateLocalNotifications(power: currentPower, thermalPressure: currentThermalPressure)
            ViftyLog.polling.debug("Hardware poll completed")
        } catch {
            guard pollingController.isCurrent(operation) else { return }
            ViftyLog.polling.warning("Hardware poll failed")
            let preservesManualIntent = shouldPreserveManualIntent(
                afterTickFailure: error,
                attemptedMode: stateBeforeTick.mode
            )
            if preservesManualIntent, let observedSnapshot = await coordinator.lastObservedSnapshot {
                recordHardwareSnapshot(observedSnapshot, power: currentPower, thermalPressure: currentThermalPressure)
            }
            assignIfChanged(\.lastError, error.localizedDescription)
            await refreshDaemonPingIfNeeded(at: pollStartedAt, force: true)
            guard pollingController.isCurrent(operation) else { return }
            assignIfChanged(\.daemonReachable, daemonResponding || (preservesManualIntent && snapshot?.fans.isEmpty == false))
            await refreshAgentControlStatusIfNeeded(at: pollStartedAt, force: true)
            guard pollingController.isCurrent(operation) else { return }
            await refreshFanControlOwnershipStatus()
            guard pollingController.isCurrent(operation) else { return }
            if preservesManualIntent, let snapshot {
                assignIfChanged(\.fanAccessMessage, fanAccessMessage(for: snapshot))
            }
            if preservesManualIntent {
                if selectedMode != .auto {
                    let intendedMode: FanMode = stateBeforeTick.mode == .auto ? selectedFanMode() : stateBeforeTick.mode
                    await coordinator.setMode(intendedMode)
                    guard pollingController.isCurrent(operation) else { return }
                }
                assignIfChanged(\.controlState, await coordinator.state)
            } else if selectedMode == .auto,
                      expiredAutoOperationGeneration == nil {
                // The coordinator tick already attempted the current Auto
                // transaction. Do not double the retry rate with a second
                // forceAuto request in the same poll; later polls may make one
                // authority-free safety retry.
                await syncState()
            } else {
                let fallbackAutoRestoreResult = await coordinator.forceAuto()
                guard pollingController.isCurrent(operation) else { return }
                await syncState()
                guard pollingController.isCurrent(operation) else { return }

                if let expiredAutoOperationGeneration,
                   fanControlOperationIsCurrent(expiredAutoOperationGeneration) {
                    switch fallbackAutoRestoreResult {
                    case .restored:
                        if canCommitAutoRestoration(generation: expiredAutoOperationGeneration) {
                            recordAutoRestorationApplied()
                        } else {
                            let message = "\(error.localizedDescription)\nFallback Auto restore could not be confirmed."
                            assignIfChanged(\.lastError, message)
                            fanControlApplyState = .failed(message: message)
                        }
                    case .failed(let fallbackMessage):
                        let message = "\(error.localizedDescription)\nFallback Auto restore failed: \(fallbackMessage)"
                        assignIfChanged(\.lastError, message)
                        fanControlApplyState = .failed(message: message)
                    }
                }
            }
            await evaluateLocalNotifications(power: currentPower, thermalPressure: currentThermalPressure)
        }
    }

    func refreshCodexUsageIfNeeded() {
        guard menuBarDisplaysCodexUsage else {
            if codexUsageRefreshTask != nil || codexUsageSnapshot != nil {
                cancelCodexUsageRefresh(clearSnapshot: true)
            }
            return
        }
        guard codexUsageRefreshTask == nil else { return }

        let currentTime = now()
        if let lastCodexUsageRefreshAt,
           currentTime.timeIntervalSince(lastCodexUsageRefreshAt) < codexUsageRefreshCadence.seconds {
            return
        }

        lastCodexUsageRefreshAt = currentTime
        let reader = codexUsageReader
        codexUsageRefreshGeneration &+= 1
        let generation = codexUsageRefreshGeneration
        codexUsageRefreshTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                reader()
            }.value
            let wasCancelled = Task.isCancelled

            guard let self else { return }
            guard self.codexUsageRefreshGeneration == generation else { return }
            self.codexUsageRefreshTask = nil
            guard !wasCancelled else { return }
            guard self.menuBarDisplaysCodexUsage else {
                self.cancelCodexUsageRefresh(clearSnapshot: true)
                return
            }

            self.assignIfChanged(\.codexUsageSnapshot, snapshot)
            self.refreshMenuBarStatusItemIfNeeded()
        }
    }

    func cancelCodexUsageRefresh(clearSnapshot: Bool) {
        codexUsageRefreshGeneration &+= 1
        codexUsageRefreshTask?.cancel()
        codexUsageRefreshTask = nil
        lastCodexUsageRefreshAt = nil
        if clearSnapshot {
            assignIfChanged(\.codexUsageSnapshot, nil)
        }
        refreshMenuBarStatusItemIfNeeded()
    }

    func waitForCodexUsageRefresh() async {
        await codexUsageRefreshTask?.value
    }

    @discardableResult
    func refreshMenuBarStatusItemIfNeeded() -> Bool {
        let nextPresentation = currentMenuBarStatusItemPresentation
        guard nextPresentation != menuBarStatusItemPresentation else { return false }
        menuBarStatusItemPresentation = nextPresentation
        menuBarStatusItemRevision &+= 1
        return true
    }

    var currentMenuBarStatusItemPresentation: MenuBarStatusItemPresentation {
        resolvedMenuBarPresentation.statusItemPresentation
    }

    func shouldRefresh(lastRefreshAt: Date?, interval: TimeInterval, at date: Date) -> Bool {
        guard let lastRefreshAt else { return true }
        return date.timeIntervalSince(lastRefreshAt) >= interval
    }

    func backgroundPollInterval() -> Duration {
        pollSchedulePolicy.interval(
            selectedMode: selectedMode,
            controlMode: controlState.mode,
            hasAgentLease: agentControlStatus?.activeLease?.isActive(at: now()) == true
        )
    }

    func refreshDaemonPingIfNeeded(at date: Date, force: Bool) async {
        guard force || !daemonResponding || shouldRefresh(
            lastRefreshAt: lastDaemonPingAt,
            interval: daemonPingRefreshInterval,
            at: date
        ) else {
            return
        }
        let responding = await daemonPing()
        lastDaemonPingAt = date
        assignIfChanged(\.daemonResponding, responding)
    }

    func refreshAgentControlStatusIfNeeded(at date: Date, force: Bool = false) async {
        let activeLease = agentControlStatus?.activeLease
        let activeAgentWork = activeLease?.isActive(at: date) == true || agentControlStatusError != nil
        guard force || activeAgentWork || shouldRefresh(
            lastRefreshAt: lastAgentStatusRefreshAt,
            interval: agentStatusRefreshInterval,
            at: date
        ) else {
            return
        }
        await refreshAgentControlStatus()
        lastAgentStatusRefreshAt = date
    }

    @discardableResult
    func assignIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<AppModel, Value>,
        _ value: Value
    ) -> Bool {
        guard self[keyPath: keyPath] != value else { return false }
        self[keyPath: keyPath] = value
        return true
    }

    func recordHardwareSnapshot(
        _ nextSnapshot: HardwareSnapshot,
        power: PowerSnapshot,
        thermalPressure: ThermalPressure
    ) {
        assignIfChanged(\.snapshot, nextSnapshot)
        telemetrySession.record(
            snapshot: nextSnapshot,
            power: power,
            thermalPressure: thermalPressure,
            userSelectedSensorID: userSelectedSensorID,
            capturedAt: now(),
        )
        publishTelemetrySession()
        syncCurveDefaultsIfNeeded(from: nextSnapshot)
        if usePerFanFixedRPM {
            ensureFixedFanTargets(for: nextSnapshot.fans)
        }
    }

    func fanAccessMessage(for snapshot: HardwareSnapshot) -> String? {
        snapshot.fans.isEmpty
            ? (daemonResponding ? "The fan helper is running but did not return fan data." : "Install and approve the fan helper to enable fan reads and control.")
            : nil
    }

}
