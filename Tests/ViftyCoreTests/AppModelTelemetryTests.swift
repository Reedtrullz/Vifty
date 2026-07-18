import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class AppModelTelemetryTests: XCTestCase {
    func testMissingSavedSensorUsesVisibleFallbackAndMarksProfileEdited() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [
                TemperatureSensor(id: "gpu", name: "GPU Proximity", celsius: 79, source: .smc),
                TemperatureSensor(id: "cpu", name: "CPU Package", celsius: 72, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        let profile = CurveProfile(
            name: "Legacy sensor",
            sensorID: "stale-sensor",
            startTemp: 50,
            startRPM: 1_500,
            midTemp: 65,
            midRPM: 3_000,
            maxTemp: 80,
            maxRPM: 4_500
        )
        model.savedProfiles = [profile]
        XCTAssertTrue(model.selectCurveProfile(id: profile.id))

        XCTAssertEqual(model.selectedSensorID, "stale-sensor")
        XCTAssertEqual(model.effectiveSelectedSensorID, "cpu")
        XCTAssertEqual(model.selectedSensor?.id, "cpu")
        XCTAssertEqual(model.currentFanControlDraft.selectedSensorID, "cpu")
        XCTAssertEqual(model.curveProfileEditState, .edited(profileID: profile.id))
        XCTAssertEqual(model.curveTemperatureSelection.curveMetricRole, .automaticCPU)
    }

    func testSelectedCurveTemperatureDoesNotHideHotterSafetyTemperature() {
        let model = AppModel()
        model.snapshot = HardwareSnapshot(
            fans: [],
            temperatureSensors: [
                TemperatureSensor(id: "selected", name: "CPU Proximity", celsius: 61, source: .smc),
                TemperatureSensor(id: "hotspot", name: "SoC Hotspot", celsius: 92, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )
        model.selectedSensorID = "selected"

        XCTAssertEqual(model.selectedSensor?.celsius, 61)
        XCTAssertEqual(model.snapshot?.highestTemperature?.celsius, 92)
        XCTAssertEqual(model.temperatureAttentionSummary, "High temp")
    }

    func testPollOnceAppendsTelemetryHistorySample() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let now = Date(timeIntervalSince1970: 1234)
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50, batteryPowerWatts: -12.5) },
            thermalReader: { .fair },
            now: { now },
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        await model.pollOnce()

        XCTAssertEqual(model.telemetryHistory.samples.count, 1)
        XCTAssertEqual(model.telemetryHistory.samples[0].capturedAt, now)
        XCTAssertEqual(model.telemetryHistory.samples[0].selectedTemperatureID, "Tp09")
        XCTAssertEqual(model.telemetryHistory.samples[0].selectedTemperatureName, "CPU Proximity")
        XCTAssertEqual(model.telemetryHistory.samples[0].selectedTemperatureCelsius, 64)
        XCTAssertFalse(model.telemetryHistory.samples[0].temperatureWasUserSelected)
        XCTAssertEqual(model.telemetryHistory.samples[0].highestTemperatureCelsius, 64)
        XCTAssertEqual(model.telemetryHistory.samples[0].firstFanRPM, 2500)
        XCTAssertEqual(model.telemetryHistory.samples[0].averageFanRPM, 2500)
        XCTAssertEqual(model.telemetryHistory.samples[0].batteryPowerWatts, -12.5)
        XCTAssertEqual(model.telemetryHistory.samples[0].thermalPressure, .fair)
    }

    func testProgrammaticDefaultSensorDoesNotMarkTelemetryAsUserSelected() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50, batteryPowerWatts: -12.5) },
            thermalReader: { .fair },
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        await model.pollOnce()
        await model.pollOnce()

        XCTAssertEqual(model.selectedSensorID, "Tp09")
        XCTAssertEqual(model.telemetryHistory.samples.count, 2)
        XCTAssertFalse(model.telemetryHistory.samples[0].temperatureWasUserSelected)
        XCTAssertFalse(model.telemetryHistory.samples[1].temperatureWasUserSelected)
        XCTAssertEqual(
            TelemetryHistorySummary(history: model.telemetryHistory).latestTemperatureLabel,
            "Automatic CPU · CPU Proximity"
        )
    }

    func testPollOnceAppendsSelectedSensorAndAverageFanTelemetryHistorySample() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2200, minimumRPM: 1400, maximumRPM: 6000, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 2800, minimumRPM: 1400, maximumRPM: 6000, controllable: true)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "Tp09", name: "CPU Performance Core 1", celsius: 73, source: .smc),
                TemperatureSensor(id: "Tp01", name: "CPU Efficiency Core 1", celsius: 66, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50, batteryPowerWatts: -8.0) },
            thermalReader: { .nominal },
            daemonPing: { true },
            agentStatusReader: { nil }
        )
        model.selectedSensorID = "Tp01"

        await model.pollOnce()

        let sample = model.telemetryHistory.samples[0]
        XCTAssertEqual(sample.selectedTemperatureID, "Tp01")
        XCTAssertEqual(sample.selectedTemperatureName, "CPU Efficiency Core 1")
        XCTAssertEqual(sample.selectedTemperatureCelsius, 66)
        XCTAssertTrue(sample.temperatureWasUserSelected)
        XCTAssertEqual(sample.highestTemperatureCelsius, 73)
        XCTAssertEqual(sample.firstFanRPM, 2200)
        XCTAssertEqual(sample.averageFanRPM, 2500)
    }

    func testRecentTelemetryTrendSummaryRequiresAtLeastTwoSamples() {
        let model = AppModel()

        XCTAssertNil(model.recentTelemetryTrendSummary)

        model.telemetryHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            highestTemperatureCelsius: 70.0,
            firstFanRPM: 2_000,
            batteryPowerWatts: -4.0,
            thermalPressure: .nominal
        ))

        XCTAssertNil(model.recentTelemetryTrendSummary)
    }

    func testRecentTelemetryTrendSummaryFormatsCompactDeltasAndPeakThermalPressure() {
        let model = AppModel()
        model.telemetryHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            highestTemperatureCelsius: 70.0,
            firstFanRPM: 2_000,
            averageFanRPM: 2_100,
            batteryPowerWatts: -4.0,
            thermalPressure: .nominal
        ))
        model.telemetryHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 2),
            highestTemperatureCelsius: 74.2,
            firstFanRPM: 2_250,
            averageFanRPM: 2_350,
            batteryPowerWatts: -7.1,
            thermalPressure: .serious
        ))

        XCTAssertEqual(
            model.recentTelemetryTrendSummary,
            "Temp +4.2 °C · Avg fan +250 RPM · Power -3.1 W · Peak Serious"
        )
    }

    func testRecentTelemetryTrendSummaryOmitsMissingMetricsAndStableNominalThermalPressure() {
        let model = AppModel()
        model.telemetryHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            highestTemperatureCelsius: nil,
            firstFanRPM: nil,
            batteryPowerWatts: nil,
            thermalPressure: .nominal
        ))
        model.telemetryHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 2),
            highestTemperatureCelsius: nil,
            firstFanRPM: nil,
            batteryPowerWatts: nil,
            thermalPressure: .nominal
        ))

        XCTAssertNil(model.recentTelemetryTrendSummary)
    }

    func testMenuTitleIncludesElevatedThermalPressure() async {
        let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
            fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
            temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 74, source: .smc)],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        ))
        let model = AppModel(
            coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
            powerReader: { PowerSnapshot(percent: 50) },
            thermalReader: { .serious },
            daemonPing: { true },
            agentStatusReader: { nil }
        )

        await model.pollOnce()

        XCTAssertEqual(model.thermalPressure, .serious)
        XCTAssertTrue(model.menuTitle.contains("Thermal: Serious"))
    }

}
