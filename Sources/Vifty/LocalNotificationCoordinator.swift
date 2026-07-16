import Foundation
import ViftyCore

struct LocalNotificationEvaluationInput {
    var helperNeedsAttention: Bool
    var helperTitle: String
    var helperBody: String
    var agentNeedsAttention: Bool
    var agentBody: String
    var power: PowerSnapshot
    var thermalPressure: ThermalPressure
}

@MainActor
final class LocalNotificationCoordinator {
    private let deliverer: LocalNotificationDelivering
    private let historyStore: LocalNotificationHistoryStore
    private let now: @Sendable () -> Date
    private let minimumInterval: TimeInterval
    private let sustainedThermalPressureInterval: TimeInterval
    private var transitionState = LocalNotificationTransitionState()
    private var elevatedThermalPressureStartedAt: Date?

    init(
        deliverer: LocalNotificationDelivering,
        historyStore: LocalNotificationHistoryStore,
        now: @escaping @Sendable () -> Date,
        minimumInterval: TimeInterval = 30 * 60,
        sustainedThermalPressureInterval: TimeInterval = 60
    ) {
        self.deliverer = deliverer
        self.historyStore = historyStore
        self.now = now
        self.minimumInterval = minimumInterval
        self.sustainedThermalPressureInterval = sustainedThermalPressureInterval
    }

    func evaluate(
        settings: LocalNotificationSettings,
        input: LocalNotificationEvaluationInput
    ) async -> LocalNotificationAuthorization? {
        var authorization: LocalNotificationAuthorization?

        if transitionState.shouldNotify(
            kind: .helperFailure,
            isAttention: input.helperNeedsAttention
        ) {
            authorization = await post(
                settings: settings,
                notification: LocalNotification(
                    kind: .helperFailure,
                    title: input.helperTitle,
                    body: input.helperBody
                )
            ) ?? authorization
        }

        if transitionState.shouldNotify(
            kind: .agentCoolingAttention,
            isAttention: input.agentNeedsAttention
        ) {
            authorization = await post(
                settings: settings,
                notification: LocalNotification(
                    kind: .agentCoolingAttention,
                    title: "Vifty agent cooling needs attention",
                    body: input.agentBody
                )
            ) ?? authorization
        }

        authorization = await evaluateThermalPressure(
            input.thermalPressure,
            settings: settings
        ) ?? authorization
        authorization = await evaluatePluggedInDrain(
            input.power,
            settings: settings
        ) ?? authorization
        return authorization
    }

    func notifyAutoRestoreFailure(
        _ message: String,
        settings: LocalNotificationSettings
    ) async -> LocalNotificationAuthorization? {
        await post(
            settings: settings,
            notification: LocalNotification(
                kind: .autoRestoreFailure,
                title: "Vifty could not confirm Auto restore",
                body: message
            )
        )
    }

    func authorizationStatus() async -> LocalNotificationAuthorization {
        await deliverer.authorizationStatus()
    }

    func requestAuthorization() async -> LocalNotificationAuthorization {
        await deliverer.requestAuthorization()
    }

    func sendTestNotification() async -> (
        delivered: Bool,
        authorization: LocalNotificationAuthorization
    ) {
        let delivered = await deliverer.deliverTestNotification()
        return (delivered, await deliverer.authorizationStatus())
    }

    func openSettings() async -> LocalNotificationAuthorization {
        _ = await deliverer.openNotificationSettings()
        return await deliverer.authorizationStatus()
    }

    private func evaluateThermalPressure(
        _ thermalPressure: ThermalPressure,
        settings: LocalNotificationSettings
    ) async -> LocalNotificationAuthorization? {
        let isElevated = thermalPressure == .serious || thermalPressure == .critical
        guard isElevated else {
            elevatedThermalPressureStartedAt = nil
            return nil
        }

        let currentDate = now()
        if elevatedThermalPressureStartedAt == nil {
            elevatedThermalPressureStartedAt = currentDate
        }

        guard let startedAt = elevatedThermalPressureStartedAt,
              currentDate.timeIntervalSince(startedAt) >= sustainedThermalPressureInterval
        else {
            return nil
        }

        return await post(
            settings: settings,
            notification: LocalNotification(
                kind: .elevatedThermalPressure,
                title: "Vifty thermal pressure is \(thermalPressure.displayName)",
                body: "macOS reports sustained \(thermalPressure.displayName.lowercased()) thermal pressure. Consider reducing workload or restoring Auto."
            )
        )
    }

    private func evaluatePluggedInDrain(
        _ power: PowerSnapshot,
        settings: LocalNotificationSettings
    ) async -> LocalNotificationAuthorization? {
        let needsAttention = power.isPluggedIn && power.batteryIsActivelyDraining
        guard transitionState.shouldNotify(
            kind: .pluggedInBatteryDrain,
            isAttention: needsAttention
        ) else {
            return nil
        }

        let watts = power.batteryPowerWatts
            .map { PowerDisplayFormatter.watts(abs($0)) }
            ?? "battery power"
        return await post(
            settings: settings,
            notification: LocalNotification(
                kind: .pluggedInBatteryDrain,
                title: "Vifty sees battery drain while plugged in",
                body: "Battery is draining at \(watts) even though external power is connected."
            )
        )
    }

    private func post(
        settings: LocalNotificationSettings,
        notification: LocalNotification
    ) async -> LocalNotificationAuthorization? {
        guard settings.isEnabled(notification.kind) else { return nil }

        let currentDate = now()
        guard !historyStore.isCoolingDown(
            notification.kind,
            at: currentDate,
            minimumInterval: minimumInterval
        ) else {
            return nil
        }

        let delivered = await deliverer.deliver(notification)
        let authorization = await deliverer.authorizationStatus()
        if delivered {
            do {
                try historyStore.recordDelivery(of: notification.kind, at: currentDate)
            } catch {
                ViftyLog.notifications.error(
                    "Notification cooldown persistence failed kind=\(notification.kind.rawValue, privacy: .public)"
                )
            }
        }
        return authorization
    }
}
