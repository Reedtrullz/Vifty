import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class AppModelNotificationTests: XCTestCase {
    func testAppReactivationRefreshesNotificationAndLoginItemState() async {
        let notifications = AppModelNotificationRecorder(authorization: .denied)
        let loginItem = AppModelLaunchAtLoginRecorder(status: .requiresApproval)
        let model = AppModel(
            notificationDeliverer: notifications,
            launchAtLoginManager: loginItem
        )
        await model.refreshSystemSettingsStateOnActivation()
        XCTAssertEqual(model.notificationAuthorization, .denied)
        XCTAssertEqual(model.launchAtLoginStatus, .requiresApproval)

        notifications.setAuthorization(.authorized)
        loginItem.status = .enabled
        await model.refreshSystemSettingsStateOnActivation()

        XCTAssertEqual(model.notificationAuthorization, .authorized)
        XCTAssertEqual(model.launchAtLoginStatus, .enabled)
    }

    func testHelperFailureNotificationFiresOnAttentionTransitionWhenEnabled() async throws {
        let recorder = AppModelNotificationRecorder()
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFailingHardware(error: ViftyError.helperRejected("Snapshot failed")),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1000) },
            notificationDeliverer: recorder,
            daemonPing: { false },
            agentStatusReader: { nil }
        )
        model.notificationSettings.helperFailure = true

        await model.pollOnce()
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.helperFailure])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertEqual(notification.title, "Vifty fan helper needs attention")
        XCTAssertEqual(model.helperFailureNotificationTitle, "Vifty fan helper needs attention")
        XCTAssertEqual(
            notification.body,
            "Use Repair Helper, approve Login Items if prompted, then wait for healthy fan status. Fan writes stay blocked until the daemon responds; restore Auto first if fans appear stuck."
        )
    }

    func testExplicitNotificationOptInKeepsPreferenceSelectedWhenDenied() async {
        let recorder = AppModelNotificationRecorder(
            authorization: .notDetermined,
            authorizationRequestResult: .denied
        )
        let model = AppModel(notificationDeliverer: recorder)

        model.setNotificationEnabled(.helperFailure, isEnabled: true)
        await recorder.waitForAuthorizationRequestCount(1)

        XCTAssertTrue(model.notificationSettings.helperFailure)
        XCTAssertEqual(model.notificationAuthorization, .denied)
        XCTAssertEqual(recorder.authorizationRequestCount, 1)
    }

    func testAuthorizedNotificationTestDoesNotWriteCooldownHistory() async {
        let historyURL = temporaryPreferencesPath()
            .deletingLastPathComponent()
            .appendingPathComponent("notification-history.json")
        defer { try? FileManager.default.removeItem(at: historyURL.deletingLastPathComponent()) }
        let recorder = AppModelNotificationRecorder(authorization: .authorized)
        let history = LocalNotificationHistoryStore(url: historyURL)
        let model = AppModel(
            notificationDeliverer: recorder,
            notificationHistoryStore: history
        )

        await model.refreshNotificationAuthorization()
        await model.sendTestNotification()

        XCTAssertEqual(model.notificationAuthorization, .authorized)
        XCTAssertEqual(model.notificationTestMessage, "Test notification sent.")
        XCTAssertEqual(recorder.testDeliveryCount, 1)
        XCTAssertFalse(history.isCoolingDown(
            .helperFailure,
            at: Date(timeIntervalSince1970: 100),
            minimumInterval: 1_800
        ))
    }

    func testHelperFailureNotificationUsesHotBlockedFanWritesRecoveryWhenAvailable() async throws {
        let recorder = AppModelNotificationRecorder()
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let pingSequence = AppModelPingSequence(values: [true, false])
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: HardwareSnapshot(
                    fans: [Fan(id: 0, name: "Left", currentRPM: 1780, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
                    temperatureSensors: [
                        TemperatureSensor(id: "Tp09", name: "CPU Efficiency Core 1", celsius: 91.2, source: .smc)
                    ],
                    modelIdentifier: "MacBookPro18,3",
                    isAppleSilicon: true,
                    isMacBookPro: true
                )),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            notificationDeliverer: recorder,
            daemonPing: { pingSequence.next() },
            agentStatusReader: { nil }
        )
        model.notificationSettings.helperFailure = true

        await model.pollOnce()
        XCTAssertTrue(recorder.delivered.isEmpty)
        clock.now = Date(timeIntervalSince1970: 1031)
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.helperFailure])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertEqual(notification.title, "Vifty fan writes are blocked while hot")
        XCTAssertEqual(model.helperFailureNotificationTitle, "Vifty fan writes are blocked while hot")
        XCTAssertEqual(
            notification.body,
            "Reduce heavy work now. Keep Auto selected, then Repair/Reinstall Helper; writes stay blocked until the daemon responds."
        )
    }

    func testSustainedThermalPressureNotificationWaitsBeforeFiring() async throws {
        let recorder = AppModelNotificationRecorder()
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: agentHardwareSnapshot()),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .serious },
            now: { clock.now },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.notificationSettings.elevatedThermalPressure = true

        await model.pollOnce()
        XCTAssertTrue(recorder.delivered.isEmpty)

        clock.now = Date(timeIntervalSince1970: 1061)
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.elevatedThermalPressure])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertTrue(notification.body.contains("sustained serious thermal pressure"))
    }

    func testSustainedThermalPressureNotificationRespectsCooldown() async {
        let recorder = AppModelNotificationRecorder()
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: agentHardwareSnapshot()),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .serious },
            now: { clock.now },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.notificationSettings.elevatedThermalPressure = true

        await model.pollOnce()
        clock.now = Date(timeIntervalSince1970: 1061)
        await model.pollOnce()
        clock.now = Date(timeIntervalSince1970: 1065)
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.elevatedThermalPressure])

        clock.now = Date(timeIntervalSince1970: 2860)
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.elevatedThermalPressure])

        clock.now = Date(timeIntervalSince1970: 2862)
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.elevatedThermalPressure, .elevatedThermalPressure])
    }

    func testPluggedInBatteryDrainNotificationFiresOnDrainTransition() async throws {
        let recorder = AppModelNotificationRecorder()
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let powerSequence = AppModelPowerSequence(values: [
            PowerSnapshot(percent: 50, isPluggedIn: true, batteryPowerWatts: 0),
            PowerSnapshot(percent: 50, isPluggedIn: true, batteryPowerWatts: -11.25)
        ])
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: agentHardwareSnapshot()),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { powerSequence.next() },
            thermalReader: { .nominal },
            now: { clock.now },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.notificationSettings.pluggedInBatteryDrain = true

        await model.pollOnce()
        XCTAssertTrue(recorder.delivered.isEmpty)
        clock.now = Date(timeIntervalSince1970: 1016)
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.pluggedInBatteryDrain])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertTrue(notification.body.contains("11.2 W"))
    }

    func testAutoRestoreFailureNotificationFiresWhenAuthoritativeRestoreFails() async throws {
        let recorder = AppModelNotificationRecorder()
        let lease = agentLease()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        await hardware.failNextRestore(ViftyError.helperRejected("Daemon connection invalidated."))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1000) },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: {
                AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)
            }
        )
        model.notificationSettings.autoRestoreFailure = true
        model.agentControlStatus = AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)

        await model.restoreAutoNow()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.autoRestoreFailure])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertTrue(notification.body.contains("Daemon connection invalidated"))
    }

    func testAgentCoolingAttentionNotificationFiresWhenLeaseNeedsRestore() async throws {
        let recorder = AppModelNotificationRecorder()
        let hardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        let lease = agentLease(expiresAt: Date(timeIntervalSince1970: 1005))
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1000))
        let statusSequence = AgentStatusSequence(results: [
            .success(AgentControlStatus(enabled: true, activeLease: nil, lastDecision: nil, lastErrorCode: nil)),
            .success(AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil))
        ])
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { clock.now },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: {
                try await statusSequence.next()
            }
        )
        model.notificationSettings.agentCoolingAttention = true

        await model.pollOnce()
        XCTAssertTrue(recorder.delivered.isEmpty)
        clock.now = Date(timeIntervalSince1970: 1016)
        await model.pollOnce()

        XCTAssertEqual(recorder.delivered.map(\.kind), [.agentCoolingAttention])
        let notification = try XCTUnwrap(recorder.delivered.first)
        XCTAssertEqual(notification.title, "Vifty agent cooling needs attention")
        XCTAssertTrue(notification.body.contains("Use Auto to restore daemon control"))
    }

    func testNotificationCooldownPersistsAcrossModelInstances() async {
        let historyURL = temporaryPreferencesPath()
            .deletingLastPathComponent()
            .appendingPathComponent("notification-history.json")
        defer { try? FileManager.default.removeItem(at: historyURL.deletingLastPathComponent()) }
        let firstRecorder = AppModelNotificationRecorder()
        let lease = agentLease()
        let firstHardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        await firstHardware.failNextRestore(ViftyError.helperRejected("restore refused"))
        let firstModel = AppModel(
            coordinator: FanControlCoordinator(
                hardware: firstHardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1000) },
            notificationDeliverer: firstRecorder,
            notificationHistoryStore: LocalNotificationHistoryStore(url: historyURL),
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        firstModel.notificationSettings.autoRestoreFailure = true
        firstModel.agentControlStatus = AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)

        await firstModel.restoreAutoNow()
        XCTAssertEqual(firstRecorder.delivered.map(\.kind), [.autoRestoreFailure])

        let secondRecorder = AppModelNotificationRecorder()
        let secondHardware = AppModelFakeHardware(snapshot: agentHardwareSnapshot())
        await secondHardware.failNextRestore(ViftyError.helperRejected("restore refused"))
        let secondModel = AppModel(
            coordinator: FanControlCoordinator(
                hardware: secondHardware,
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .nominal },
            now: { Date(timeIntervalSince1970: 1100) },
            notificationDeliverer: secondRecorder,
            notificationHistoryStore: LocalNotificationHistoryStore(url: historyURL),
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        secondModel.notificationSettings.autoRestoreFailure = true
        secondModel.agentControlStatus = AgentControlStatus(enabled: true, activeLease: lease, lastDecision: nil, lastErrorCode: nil)

        await secondModel.restoreAutoNow()
        XCTAssertTrue(secondRecorder.delivered.isEmpty)
    }

    func testFailedNotificationDeliveryDoesNotConsumeCooldown() async {
        let recorder = AppModelNotificationRecorder(deliveryResults: [false, true])
        let clock = AppModelTestClock(now: Date(timeIntervalSince1970: 1_000))
        let model = AppModel(
            coordinator: FanControlCoordinator(
                hardware: AppModelFakeHardware(snapshot: agentHardwareSnapshot()),
                uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())
            ),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .serious },
            now: { clock.now },
            notificationDeliverer: recorder,
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.notificationSettings.elevatedThermalPressure = true

        await model.pollOnce()
        clock.now = Date(timeIntervalSince1970: 1_060)
        await model.pollOnce()
        clock.now = Date(timeIntervalSince1970: 1_061)
        await model.pollOnce()

        XCTAssertEqual(
            recorder.delivered.map(\.kind),
            [.elevatedThermalPressure, .elevatedThermalPressure]
        )
    }

}
