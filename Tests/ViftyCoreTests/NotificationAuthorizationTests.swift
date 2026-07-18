import XCTest
@testable import Vifty

final class NotificationAuthorizationTests: XCTestCase {
    func testConcurrentExplicitOptInsShareOneSystemRequest() async {
        let client = NotificationCenterClientFake(
            status: .notDetermined,
            requestResult: .authorized,
            holdsAuthorizationRequest: true
        )
        let controller = LocalNotificationAuthorizationController(client: client)
        _ = await controller.refresh()

        async let first = controller.requestForExplicitOptIn()
        async let second = controller.requestForExplicitOptIn()
        await client.waitForAuthorizationRequest()
        await client.resolveAuthorizationRequest()

        let firstValue = await first
        let secondValue = await second
        let requestCount = await client.requestCount
        XCTAssertEqual([firstValue, secondValue], [.authorized, .authorized])
        XCTAssertEqual(requestCount, 1)
    }

    func testDenialDoesNotRewriteSelectedEventPreferences() async {
        let client = NotificationCenterClientFake(status: .notDetermined, requestResult: .denied)
        let controller = LocalNotificationAuthorizationController(client: client)
        var preferences = LocalNotificationSettings(
            helperFailure: true,
            elevatedThermalPressure: false,
            autoRestoreFailure: true,
            pluggedInBatteryDrain: false,
            agentCoolingAttention: false
        )
        let expected = preferences

        _ = await controller.refresh()
        let authorization = await controller.requestForExplicitOptIn()

        XCTAssertEqual(authorization, .denied)
        XCTAssertEqual(preferences, expected)
        preferences.helperFailure = false
        XCTAssertFalse(preferences.helperFailure)
    }

    func testAuthorizedTestDeliveryDoesNotConsumeEventCooldown() async throws {
        let client = NotificationCenterClientFake(status: .authorized, requestResult: .authorized)
        let controller = LocalNotificationAuthorizationController(client: client)
        let historyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("notification-history.json")
        defer { try? FileManager.default.removeItem(at: historyURL.deletingLastPathComponent()) }
        let history = LocalNotificationHistoryStore(url: historyURL)

        _ = await controller.refresh()
        let testDelivered = await controller.deliverTestNotification()
        let deliveredNotifications = await client.delivered

        XCTAssertTrue(testDelivered)
        XCTAssertFalse(history.isCoolingDown(
            .helperFailure,
            at: Date(timeIntervalSince1970: 10),
            minimumInterval: 1_800
        ))
        XCTAssertEqual(deliveredNotifications.count, 1)
        XCTAssertEqual(deliveredNotifications.first?.title, "Vifty test notification")
    }

    func testDeniedDeliveryStaysVisibleAndDoesNotDeliver() async {
        let client = NotificationCenterClientFake(status: .denied, requestResult: .denied)
        let controller = LocalNotificationAuthorizationController(client: client)
        _ = await controller.refresh()

        let delivered = await controller.deliver(
            LocalNotification(kind: .helperFailure, title: "Blocked", body: "Blocked"),
            allowUpgradeFallbackRequest: true
        )

        let status = await controller.status
        let deliveredNotifications = await client.delivered
        XCTAssertFalse(delivered)
        XCTAssertEqual(status, .denied)
        XCTAssertTrue(deliveredNotifications.isEmpty)
    }

    func testUpgradeFallbackRequestsOnceThenDelivers() async {
        let client = NotificationCenterClientFake(status: .notDetermined, requestResult: .authorized)
        let controller = LocalNotificationAuthorizationController(client: client)

        let delivered = await controller.deliver(
            LocalNotification(kind: .helperFailure, title: "Allowed", body: "Allowed"),
            allowUpgradeFallbackRequest: true
        )

        let requestCount = await client.requestCount
        let status = await controller.status
        XCTAssertTrue(delivered)
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(status, .authorized)
    }
}

private actor NotificationCenterClientFake: LocalNotificationCenterClient {
    private(set) var status: LocalNotificationAuthorization
    private let requestResult: LocalNotificationAuthorization
    private let holdsAuthorizationRequest: Bool
    private(set) var requestCount = 0
    private(set) var delivered: [LocalNotification] = []
    private var requestContinuation: CheckedContinuation<Void, Never>?

    init(
        status: LocalNotificationAuthorization,
        requestResult: LocalNotificationAuthorization,
        holdsAuthorizationRequest: Bool = false
    ) {
        self.status = status
        self.requestResult = requestResult
        self.holdsAuthorizationRequest = holdsAuthorizationRequest
    }

    func authorizationStatus() -> LocalNotificationAuthorization {
        status
    }

    func requestAuthorization() async -> LocalNotificationAuthorization {
        requestCount += 1
        if holdsAuthorizationRequest {
            await withCheckedContinuation { continuation in
                requestContinuation = continuation
            }
        }
        status = requestResult
        return requestResult
    }

    func deliver(_ notification: LocalNotification) -> Bool {
        delivered.append(notification)
        return true
    }

    func openNotificationSettings() -> Bool {
        true
    }

    func waitForAuthorizationRequest() async {
        while requestCount == 0 {
            await Task.yield()
        }
    }

    func resolveAuthorizationRequest() {
        requestContinuation?.resume()
        requestContinuation = nil
    }
}
