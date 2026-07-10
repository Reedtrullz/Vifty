import Foundation
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
}

@MainActor
final class UserNotificationDeliverer: LocalNotificationDelivering {
    private var requestedAuthorization = false

    init() {}

    func deliver(_ notification: LocalNotification) async -> Bool {
        guard !Self.isRunningUnderXCTest else { return false }
        let center = UNUserNotificationCenter.current()
        guard await ensureAuthorization(center: center) else {
            ViftyLog.notifications.debug("Notification suppressed because authorization is unavailable")
            return false
        }

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

    private func ensureAuthorization(center: UNUserNotificationCenter) async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            guard !requestedAuthorization else { return false }
            requestedAuthorization = true
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        @unknown default:
            return false
        }
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName == "xctest"
            || NSClassFromString("XCTestCase") != nil
    }
}
