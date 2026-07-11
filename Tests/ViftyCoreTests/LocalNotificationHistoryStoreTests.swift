import XCTest
@testable import Vifty

final class LocalNotificationHistoryStoreTests: XCTestCase {
    func testNotificationRequestIdentifierIsStablePerKind() {
        let first = LocalNotification(kind: .helperFailure, title: "A", body: "One")
        let second = LocalNotification(kind: .helperFailure, title: "B", body: "Two")
        let different = LocalNotification(kind: .autoRestoreFailure, title: "A", body: "One")

        XCTAssertEqual(first.requestIdentifier, second.requestIdentifier)
        XCTAssertNotEqual(first.requestIdentifier, different.requestIdentifier)
        XCTAssertEqual(first.requestIdentifier, "tech.reidar.vifty.helperFailure")
        XCTAssertTrue(first.matchesRequestIdentifier("tech.reidar.vifty.helperFailure.legacy-uuid"))
        XCTAssertFalse(first.matchesRequestIdentifier("tech.reidar.vifty.autoRestoreFailure.legacy-uuid"))
    }

    func testHistoryRoundTripsAcrossStoreInstances() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let deliveredAt = Date(timeIntervalSince1970: 1_000)
        let first = LocalNotificationHistoryStore(url: url)

        try first.recordDelivery(of: .helperFailure, at: deliveredAt)
        let reloaded = LocalNotificationHistoryStore(url: url)

        XCTAssertEqual(reloaded.lastDeliveredAt(for: .helperFailure), deliveredAt)
        XCTAssertTrue(reloaded.isCoolingDown(.helperFailure, at: Date(timeIntervalSince1970: 2_000), minimumInterval: 1_800))
        XCTAssertFalse(reloaded.isCoolingDown(.helperFailure, at: Date(timeIntervalSince1970: 2_801), minimumInterval: 1_800))
    }

    func testHistoryUsesPrivatePermissions() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = LocalNotificationHistoryStore(url: url)

        try store.recordDelivery(of: .pluggedInBatteryDrain, at: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(try permissions(at: url.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try permissions(at: url), 0o600)
    }

    func testFailedPersistenceStillKeepsInMemoryCooldown() throws {
        let blockingParent = FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-notification-history-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: blockingParent.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a directory".utf8).write(to: blockingParent)
        defer { try? FileManager.default.removeItem(at: blockingParent) }

        let deliveredAt = Date(timeIntervalSince1970: 1_000)
        let store = LocalNotificationHistoryStore(
            url: blockingParent.appendingPathComponent("notification-history.json")
        )

        XCTAssertThrowsError(try store.recordDelivery(of: .helperFailure, at: deliveredAt))
        XCTAssertEqual(store.lastDeliveredAt(for: .helperFailure), deliveredAt)
        XCTAssertTrue(store.isCoolingDown(
            .helperFailure,
            at: Date(timeIntervalSince1970: 1_100),
            minimumInterval: 1_800
        ))
    }

    func testTransitionStateSuppressesInitialAttentionAndNotifiesAfterRecovery() {
        var state = LocalNotificationTransitionState()

        XCTAssertFalse(state.shouldNotify(kind: .helperFailure, isAttention: true))
        XCTAssertFalse(state.shouldNotify(kind: .helperFailure, isAttention: false))
        XCTAssertTrue(state.shouldNotify(kind: .helperFailure, isAttention: true))
        XCTAssertFalse(state.shouldNotify(kind: .helperFailure, isAttention: true))
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vifty-notification-history-tests")
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("notification-history.json")
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
