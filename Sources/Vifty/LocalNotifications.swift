import Foundation
import AppKit
@preconcurrency import UserNotifications
import ViftyCore

enum LocalNotificationKind: String, Codable, CaseIterable, Identifiable {
    case helperFailure
    case elevatedThermalPressure
    case autoRestoreFailure
    case pluggedInBatteryDrain
    case agentCoolingAttention

    var id: String { rawValue }

    var label: String {
        switch self {
        case .helperFailure:
            "Helper failure"
        case .elevatedThermalPressure:
            "High thermal pressure"
        case .autoRestoreFailure:
            "Auto restore failure"
        case .pluggedInBatteryDrain:
            "Plugged-in battery drain"
        case .agentCoolingAttention:
            "Agent cooling attention"
        }
    }
}

struct LocalNotificationSettings: Codable, Equatable {
    var helperFailure = false
    var elevatedThermalPressure = false
    var autoRestoreFailure = false
    var pluggedInBatteryDrain = false
    var agentCoolingAttention = false

    static let disabled = LocalNotificationSettings()

    func isEnabled(_ kind: LocalNotificationKind) -> Bool {
        switch kind {
        case .helperFailure:
            helperFailure
        case .elevatedThermalPressure:
            elevatedThermalPressure
        case .autoRestoreFailure:
            autoRestoreFailure
        case .pluggedInBatteryDrain:
            pluggedInBatteryDrain
        case .agentCoolingAttention:
            agentCoolingAttention
        }
    }

    mutating func set(_ kind: LocalNotificationKind, enabled: Bool) {
        switch kind {
        case .helperFailure:
            helperFailure = enabled
        case .elevatedThermalPressure:
            elevatedThermalPressure = enabled
        case .autoRestoreFailure:
            autoRestoreFailure = enabled
        case .pluggedInBatteryDrain:
            pluggedInBatteryDrain = enabled
        case .agentCoolingAttention:
            agentCoolingAttention = enabled
        }
    }
}

struct LocalNotification: Equatable {
    let kind: LocalNotificationKind
    let title: String
    let body: String

    var requestIdentifier: String {
        "tech.reidar.vifty.\(kind.rawValue)"
    }

    func matchesRequestIdentifier(_ identifier: String) -> Bool {
        identifier == requestIdentifier || identifier.hasPrefix("\(requestIdentifier).")
    }
}

struct LocalNotificationTransitionState {
    private var previousAttentionByKind: [LocalNotificationKind: Bool] = [:]

    mutating func shouldNotify(kind: LocalNotificationKind, isAttention: Bool) -> Bool {
        guard let previous = previousAttentionByKind[kind] else {
            previousAttentionByKind[kind] = isAttention
            return false
        }

        previousAttentionByKind[kind] = isAttention
        return isAttention && !previous
    }
}

@MainActor
protocol LocalNotificationDelivering: AnyObject {
    func deliver(_ notification: LocalNotification) async -> Bool
    func authorizationStatus() async -> LocalNotificationAuthorization
    func requestAuthorization() async -> LocalNotificationAuthorization
    func deliverTestNotification() async -> Bool
    func openNotificationSettings() async -> Bool
}

extension LocalNotificationDelivering {
    func authorizationStatus() async -> LocalNotificationAuthorization { .unavailable }
    func requestAuthorization() async -> LocalNotificationAuthorization { .unavailable }
    func deliverTestNotification() async -> Bool { false }
    func openNotificationSettings() async -> Bool { false }
}

@MainActor
final class UserNotificationDeliverer: LocalNotificationDelivering {
    private let controller: LocalNotificationAuthorizationController

    init(client: any LocalNotificationCenterClient = UserNotificationCenterClient()) {
        self.controller = LocalNotificationAuthorizationController(client: client)
    }

    func deliver(_ notification: LocalNotification) async -> Bool {
        guard !UserNotificationCenterClient.isRunningUnderXCTest else { return false }
        return await controller.deliver(notification, allowUpgradeFallbackRequest: true)
    }

    func authorizationStatus() async -> LocalNotificationAuthorization {
        await controller.refresh()
    }

    func requestAuthorization() async -> LocalNotificationAuthorization {
        await controller.requestForExplicitOptIn()
    }

    func deliverTestNotification() async -> Bool {
        await controller.deliverTestNotification()
    }

    func openNotificationSettings() async -> Bool {
        await controller.openSettings()
    }
}

final class UserNotificationCenterClient: LocalNotificationCenterClient, @unchecked Sendable {
    init() {}

    func authorizationStatus() async -> LocalNotificationAuthorization {
        guard !Self.isRunningUnderXCTest else { return .unavailable }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
    }

    func requestAuthorization() async -> LocalNotificationAuthorization {
        guard !Self.isRunningUnderXCTest else { return .unavailable }
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .authorized : .denied
        } catch {
            ViftyLog.notifications.error("Notification authorization request failed")
            return .unavailable
        }
    }

    func deliver(_ notification: LocalNotification) async -> Bool {
        guard !Self.isRunningUnderXCTest else { return false }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body

        let deliveredIdentifiers = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter(notification.matchesRequestIdentifier)
        center.removeDeliveredNotifications(withIdentifiers: deliveredIdentifiers)
        center.removePendingNotificationRequests(withIdentifiers: [notification.requestIdentifier])

        let request = UNNotificationRequest(
            identifier: notification.requestIdentifier,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
            ViftyLog.notifications.info("Notification delivered kind=\(notification.kind.rawValue, privacy: .public)")
            return true
        } catch {
            ViftyLog.notifications.error("Notification delivery failed kind=\(notification.kind.rawValue, privacy: .public)")
            return false
        }
    }

    func openNotificationSettings() async -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return false
        }
        return await MainActor.run { NSWorkspace.shared.open(url) }
    }

    static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName == "xctest"
            || NSClassFromString("XCTestCase") != nil
    }
}
