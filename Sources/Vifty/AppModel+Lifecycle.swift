import Foundation
import SwiftUI
import ViftyCore

@MainActor
extension AppModel {
    var launchAtLoginEnabled: Bool {
        launchAtLoginStatus.isToggleOn
    }

    var launchAtLoginStatusMessage: String? {
        launchAtLoginError ?? launchAtLoginStatus.message
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginManager.status
        if launchAtLoginStatus == .enabled || launchAtLoginStatus == .disabled {
            launchAtLoginError = nil
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            launchAtLoginStatus = launchAtLoginManager.status
            launchAtLoginError = nil
            if launchAtLoginStatus == .requiresApproval {
                launchAtLoginManager.openLoginItemsSettings()
            }
        } catch {
            launchAtLoginStatus = launchAtLoginManager.status
            launchAtLoginError = "Could not update startup item: \(error.localizedDescription)"
        }
    }

    func openLaunchAtLoginSettings() {
        launchAtLoginManager.openLoginItemsSettings()
    }

    func refreshSystemSettingsStateOnActivation() async {
        refreshLaunchAtLoginStatus()
        await refreshNotificationAuthorization()
    }

    func applyStartupModePreferenceIfNeeded() async {
        guard !startupModeApplied else { return }
        startupModeApplied = true
        selectedMode = startupMode
        guard startupMode != .auto else { return }
        if snapshot == nil {
            await pollOnce()
            selectedMode = startupMode
        }
        guard FanControlOwnershipPresentation.resolve(fanControlOwnershipStatus).owner == .macOS else {
            lastError = "Startup manual mode remains a draft until daemon-confirmed macOS fan ownership is available."
            markFanControlDraftPending()
            return
        }
        markFanControlDraftPending()
    }

    func stop() {
        Task { _ = await stopAndRestore() }
    }

    func stopAndRestore() async -> AppTerminationRestoreResult {
        ViftyLog.fanControl.notice("Termination restore started")
        let wasRunning = isRunning
        let stateBeforeStop = await coordinator.state
        let hasAgentLeaseRequiringRestore = agentControlStatus?.activeLease != nil
        pollingController.stop()
        codexUsageRefreshGeneration &+= 1
        codexUsageRefreshTask?.cancel()
        codexUsageRefreshTask = nil
        isRunning = false
        selectedMode = .auto
        manualSessionExpiresAt = nil

        var failures: [String] = []
        let ownershipBeforeRestore: FanControlOwnershipStatus?
        do {
            let status = try await coordinator.fanControlOwnershipStatus()
            fanControlOwnershipStatus = status
            fanControlOwnershipStatusError = nil
            ownershipBeforeRestore = status
        } catch {
            let message = "Could not confirm daemon fan-control ownership before termination: \(error.localizedDescription)"
            fanControlOwnershipStatus = nil
            fanControlOwnershipStatusError = error.localizedDescription
            ownershipBeforeRestore = nil
            failures.append(message)
        }

        let requiresHardwareRestore = stateBeforeStop.manualControlActive
            || stateBeforeStop.mode != .auto
            || hasAgentLeaseRequiringRestore
            || ownershipBeforeRestore.map {
                !FanControlCoordinator.confirmsCleanOSOwnership($0)
            } == true

        // A failed ownership read must not suppress a restore already required
        // by local manual state or an agent lease. We still fail termination
        // closed on that unreadable precondition, but make the best available
        // safety move back to Auto and then re-read authoritative ownership.
        if requiresHardwareRestore {
            let hardwareRestoreResult = await coordinator.forceAuto()
            if case .failed(let message) = hardwareRestoreResult {
                failures.append(message)
            }

            do {
                let status = try await coordinator.fanControlOwnershipStatus()
                fanControlOwnershipStatus = status
                fanControlOwnershipStatusError = nil
                if !FanControlCoordinator.confirmsCleanOSOwnership(status) {
                    failures.append(
                        "Auto restore did not reach clean daemon-confirmed macOS fan ownership."
                    )
                }
            } catch {
                fanControlOwnershipStatus = nil
                fanControlOwnershipStatusError = error.localizedDescription
                failures.append(
                    "Could not confirm daemon fan-control ownership after Auto restore: \(error.localizedDescription)"
                )
            }
        }
        await refreshAgentControlStatus()
        await syncState()

        guard !failures.isEmpty else {
            recordAutoRestorationApplied()
            ViftyLog.fanControl.notice("Termination restore confirmed")
            return .restored
        }

        let message = failures.joined(separator: "\n")
        lastError = message
        await notifyAutoRestoreFailure(message)
        selectedMode = modeSelection(for: controlState.mode)
        resumePollingAfterTerminationFailure(wasRunning: wasRunning)
        ViftyLog.fanControl.error("Termination restore failed")
        return .failed(message: message)
    }

    func modeSelection(for mode: FanMode) -> ModeSelection {
        switch mode {
        case .auto:
            .auto
        case .fixedRPM:
            .fixed
        case .temperatureCurve:
            .curve
        }
    }

    func resumePollingAfterTerminationFailure(wasRunning: Bool) {
        guard wasRunning, !pollingController.isRunning else { return }
        let started = pollingController.start(
            interval: { [weak self] in
                self?.backgroundPollInterval() ?? .seconds(10)
            },
            poll: { [weak self] operation in
                await self?.performPollOnce(operation: operation)
            }
        )
        isRunning = started
    }

}
