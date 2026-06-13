import Foundation
@preconcurrency import UserNotifications
import ViftyCore

enum LocalNotificationKind: String, CaseIterable, Identifiable {
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

struct LocalNotificationSettings: Equatable {
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
}

@MainActor
protocol LocalNotificationDelivering: AnyObject {
    func deliver(_ notification: LocalNotification) async
}

@MainActor
final class UserNotificationDeliverer: LocalNotificationDelivering {
    private var requestedAuthorization = false

    init() {}

    func deliver(_ notification: LocalNotification) async {
        guard !Self.isRunningUnderXCTest else { return }
        let center = UNUserNotificationCenter.current()
        guard await ensureAuthorization(center: center) else { return }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "tech.reidar.vifty.\(notification.kind.rawValue).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
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
