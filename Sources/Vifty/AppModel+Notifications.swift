import Foundation
import SwiftUI
import ViftyCore

@MainActor
extension AppModel {
    func syncState() async {
        assignIfChanged(\.controlState, await coordinator.state)
        manualTargetSettlingFanIDs = await coordinator.recentManualWriteFanIDs(
            at: now(),
            within: Self.manualTargetWriteSettleInterval
        )
        updateManualTargetDriftStability()
    }

    func evaluateLocalNotifications(power: PowerSnapshot, thermalPressure: ThermalPressure) async {
        if let authorization = await localNotificationCoordinator.evaluate(
            settings: notificationSettings,
            input: LocalNotificationEvaluationInput(
                helperNeedsAttention: helperHealthState.notifiesAsHelperFailure,
                helperTitle: helperFailureNotificationTitle,
                helperBody: helperFailureNotificationBody,
                agentNeedsAttention: agentCoolingNeedsAttention,
                agentBody: agentCoolingRecoverySuggestion
                    ?? agentCoolingSummary
                    ?? "Check Vifty before starting another developer workload.",
                power: power,
                thermalPressure: thermalPressure
            )
        ) {
            notificationAuthorization = authorization
        }
    }

    func notifyAutoRestoreFailure(_ message: String) async {
        if let authorization = await localNotificationCoordinator.notifyAutoRestoreFailure(
            message,
            settings: notificationSettings
        ) {
            notificationAuthorization = authorization
        }
    }

    func setNotificationEnabled(_ kind: LocalNotificationKind, isEnabled: Bool) {
        notificationSettings.set(kind, enabled: isEnabled)
        guard isEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            let status = await localNotificationCoordinator.requestAuthorization()
            notificationAuthorization = status
        }
    }

    func refreshNotificationAuthorization() async {
        notificationAuthorization = await localNotificationCoordinator.authorizationStatus()
    }

    func sendTestNotification() async {
        let result = await localNotificationCoordinator.sendTestNotification()
        notificationAuthorization = result.authorization
        notificationTestMessage = result.delivered
            ? "Test notification sent."
            : "Test notification was not delivered."
    }

    func openNotificationSettings() async {
        notificationAuthorization = await localNotificationCoordinator.openSettings()
    }
}
