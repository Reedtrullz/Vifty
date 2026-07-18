import Foundation

enum LocalNotificationAuthorization: String, Equatable, Sendable {
    case checking
    case notDetermined
    case authorized
    case denied
    case unavailable

    var displayName: String {
        switch self {
        case .checking: "Checking"
        case .notDetermined: "Not requested"
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .unavailable: "Unavailable"
        }
    }
}

protocol LocalNotificationCenterClient: Sendable {
    func authorizationStatus() async -> LocalNotificationAuthorization
    func requestAuthorization() async -> LocalNotificationAuthorization
    func deliver(_ notification: LocalNotification) async -> Bool
    func openNotificationSettings() async -> Bool
}

actor LocalNotificationAuthorizationController {
    private let client: any LocalNotificationCenterClient
    private var authorizationRequest: Task<LocalNotificationAuthorization, Never>?
    private(set) var status: LocalNotificationAuthorization = .checking

    init(client: any LocalNotificationCenterClient) {
        self.client = client
    }

    @discardableResult
    func refresh() async -> LocalNotificationAuthorization {
        let refreshed = await client.authorizationStatus()
        status = refreshed
        return refreshed
    }

    /// Called only for a user's explicit opt-in. Concurrent toggles share the
    /// same request task, so macOS is never prompted twice for one decision.
    @discardableResult
    func requestForExplicitOptIn() async -> LocalNotificationAuthorization {
        if status == .authorized || status == .denied || status == .unavailable {
            return status
        }
        if let authorizationRequest {
            return await authorizationRequest.value
        }

        let client = self.client
        let request = Task { await client.requestAuthorization() }
        authorizationRequest = request
        let result = await request.value
        status = result
        authorizationRequest = nil
        return result
    }

    /// Existing installations may already have enabled events. Their first
    /// delivery keeps the old lazy-request behavior, but the resulting denial
    /// remains visible through `status` instead of being silently swallowed.
    func deliver(
        _ notification: LocalNotification,
        allowUpgradeFallbackRequest: Bool
    ) async -> Bool {
        let current = status == .checking ? await refresh() : status
        let authorized: Bool
        switch current {
        case .authorized:
            authorized = true
        case .notDetermined where allowUpgradeFallbackRequest:
            authorized = await requestForExplicitOptIn() == .authorized
        case .checking, .notDetermined, .denied, .unavailable:
            authorized = false
        }
        guard authorized else { return false }
        return await client.deliver(notification)
    }

    func deliverTestNotification() async -> Bool {
        let current = status == .checking ? await refresh() : status
        guard current == .authorized else { return false }
        return await client.deliver(LocalNotification(
            kind: .helperFailure,
            title: "Vifty test notification",
            body: "Notifications are allowed. Event cooldown history was not changed."
        ))
    }

    func openSettings() async -> Bool {
        await client.openNotificationSettings()
    }
}
