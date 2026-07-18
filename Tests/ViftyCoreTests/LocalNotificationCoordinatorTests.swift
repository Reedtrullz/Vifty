import XCTest
import ViftyCore
@testable import Vifty

@MainActor
final class LocalNotificationCoordinatorTests: XCTestCase {
    func testHelperNotificationRequiresRecoveryThenNewAttention() async {
        let recorder = AppModelNotificationRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        var settings = LocalNotificationSettings.disabled
        settings.helperFailure = true

        _ = await coordinator.evaluate(settings: settings, input: input(helper: true))
        _ = await coordinator.evaluate(settings: settings, input: input(helper: false))
        _ = await coordinator.evaluate(settings: settings, input: input(helper: true))
        _ = await coordinator.evaluate(settings: settings, input: input(helper: true))

        XCTAssertEqual(recorder.delivered.map(\.kind), [.helperFailure])
        XCTAssertEqual(recorder.delivered.first?.title, "Helper title")
    }

    func testSustainedThermalPressureUsesInjectedClockAndCooldown() async {
        let recorder = AppModelNotificationRecorder()
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1_000))
        let coordinator = makeCoordinator(recorder: recorder, clock: clock)
        var settings = LocalNotificationSettings.disabled
        settings.elevatedThermalPressure = true

        _ = await coordinator.evaluate(settings: settings, input: input(thermal: .serious))
        clock.now = Date(timeIntervalSince1970: 1_059)
        _ = await coordinator.evaluate(settings: settings, input: input(thermal: .serious))
        XCTAssertTrue(recorder.delivered.isEmpty)

        clock.now = Date(timeIntervalSince1970: 1_060)
        _ = await coordinator.evaluate(settings: settings, input: input(thermal: .serious))
        clock.now = Date(timeIntervalSince1970: 2_859)
        _ = await coordinator.evaluate(settings: settings, input: input(thermal: .serious))
        XCTAssertEqual(recorder.delivered.map(\.kind), [.elevatedThermalPressure])

        clock.now = Date(timeIntervalSince1970: 2_861)
        _ = await coordinator.evaluate(settings: settings, input: input(thermal: .serious))
        XCTAssertEqual(
            recorder.delivered.map(\.kind),
            [.elevatedThermalPressure, .elevatedThermalPressure]
        )
    }

    func testFailedDeliveryDoesNotConsumeCooldown() async {
        let recorder = AppModelNotificationRecorder(deliveryResults: [false, true])
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1_000))
        let coordinator = makeCoordinator(recorder: recorder, clock: clock)
        var settings = LocalNotificationSettings.disabled
        settings.elevatedThermalPressure = true

        _ = await coordinator.evaluate(settings: settings, input: input(thermal: .critical))
        clock.now = Date(timeIntervalSince1970: 1_060)
        _ = await coordinator.evaluate(settings: settings, input: input(thermal: .critical))
        clock.now = Date(timeIntervalSince1970: 1_061)
        _ = await coordinator.evaluate(settings: settings, input: input(thermal: .critical))

        XCTAssertEqual(
            recorder.delivered.map(\.kind),
            [.elevatedThermalPressure, .elevatedThermalPressure]
        )
    }

    func testAutoRestoreFailureUsesPersistentCooldown() async {
        let url = temporaryPreferencesPath()
            .deletingLastPathComponent()
            .appendingPathComponent("coordinator-history.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var settings = LocalNotificationSettings.disabled
        settings.autoRestoreFailure = true

        let firstRecorder = AppModelNotificationRecorder()
        let first = LocalNotificationCoordinator(
            deliverer: firstRecorder,
            historyStore: LocalNotificationHistoryStore(url: url),
            now: { Date(timeIntervalSince1970: 1_000) }
        )
        _ = await first.notifyAutoRestoreFailure("first", settings: settings)

        let secondRecorder = AppModelNotificationRecorder()
        let second = LocalNotificationCoordinator(
            deliverer: secondRecorder,
            historyStore: LocalNotificationHistoryStore(url: url),
            now: { Date(timeIntervalSince1970: 1_100) }
        )
        _ = await second.notifyAutoRestoreFailure("second", settings: settings)

        XCTAssertEqual(firstRecorder.delivered.map(\.kind), [.autoRestoreFailure])
        XCTAssertTrue(secondRecorder.delivered.isEmpty)
    }

    private func makeCoordinator(
        recorder: AppModelNotificationRecorder,
        clock: AppModelTestClock = AppModelTestClock(now: Date(timeIntervalSince1970: 1_000))
    ) -> LocalNotificationCoordinator {
        LocalNotificationCoordinator(
            deliverer: recorder,
            historyStore: LocalNotificationHistoryStore(
                url: temporaryPreferencesPath()
                    .deletingLastPathComponent()
                    .appendingPathComponent("coordinator-history.json")
            ),
            now: { clock.now }
        )
    }

    private func input(
        helper: Bool = false,
        thermal: ThermalPressure = .nominal
    ) -> LocalNotificationEvaluationInput {
        LocalNotificationEvaluationInput(
            helperNeedsAttention: helper,
            helperTitle: "Helper title",
            helperBody: "Helper body",
            agentNeedsAttention: false,
            agentBody: "Agent body",
            power: PowerSnapshot(),
            thermalPressure: thermal
        )
    }
}
