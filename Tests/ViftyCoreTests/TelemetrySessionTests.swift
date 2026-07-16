import XCTest
import ViftyCore
@testable import Vifty

final class TelemetrySessionTests: XCTestCase {
    func testRecordUsesSelectedCurveSensorAndAverageFanRPM() {
        var session = TelemetrySession()
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 2_000, minimumRPM: 1_400, maximumRPM: 6_000, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 3_000, minimumRPM: 1_400, maximumRPM: 6_000, controllable: true)
            ],
            temperatureSensors: [
                TemperatureSensor(id: "cpu", name: "CPU Package", celsius: 66, source: .smc),
                TemperatureSensor(id: "hot", name: "SoC Hotspot", celsius: 78, source: .smc)
            ],
            modelIdentifier: "MacBookPro18,3",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        session.record(
            snapshot: snapshot,
            power: PowerSnapshot(batteryPowerWatts: -8),
            thermalPressure: .fair,
            userSelectedSensorID: "cpu",
            capturedAt: Date(timeIntervalSince1970: 10)
        )

        let sample = session.history.latestSample
        XCTAssertEqual(sample?.selectedTemperatureID, "cpu")
        XCTAssertEqual(sample?.temperatureRole, .curveSensor)
        XCTAssertTrue(sample?.temperatureWasUserSelected == true)
        XCTAssertEqual(sample?.highestTemperatureCelsius, 78)
        XCTAssertEqual(sample?.averageFanRPM, 2_500)
        XCTAssertEqual(sample?.batteryPowerWatts, -8)
        XCTAssertEqual(sample?.thermalPressure, .fair)
    }

    func testAppendRefreshesOverviewCompactAndTrendTogether() {
        var session = TelemetrySession()
        session.append(sample(at: 1, temperature: 70, fanRPM: 2_000, watts: -4, pressure: .nominal))
        XCTAssertNil(session.recentTrendSummary)

        session.append(sample(at: 2, temperature: 74.2, fanRPM: 2_250, watts: -7.1, pressure: .serious))

        XCTAssertEqual(session.overviewSummary.sampleCount, 2)
        XCTAssertEqual(session.compactSummary.sampleCount, 2)
        XCTAssertEqual(
            session.recentTrendSummary,
            "Temp +4.2 °C · Avg fan +250 RPM · Power -3.1 W · Peak Serious"
        )
    }

    func testReplaceHistoryRecomputesEveryDerivedValue() {
        var history = TelemetryHistory()
        history.append(sample(at: 1, temperature: 60, fanRPM: 2_000, watts: nil, pressure: .nominal))
        history.append(sample(at: 2, temperature: 60, fanRPM: 2_000, watts: nil, pressure: .nominal))

        var session = TelemetrySession()
        session.replaceHistory(history)

        XCTAssertEqual(session.history, history)
        XCTAssertEqual(session.overviewSummary.sampleCount, 2)
        XCTAssertEqual(session.compactSummary.sampleCount, 2)
        XCTAssertEqual(session.recentTrendSummary, "Temp steady · Avg fan steady")
    }

    private func sample(
        at time: TimeInterval,
        temperature: Double,
        fanRPM: Double,
        watts: Double?,
        pressure: ThermalPressure
    ) -> TelemetrySample {
        TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: time),
            selectedTemperatureCelsius: temperature,
            temperatureRole: .automaticCPU,
            highestTemperatureCelsius: temperature,
            firstFanRPM: Int(fanRPM),
            averageFanRPM: fanRPM,
            batteryPowerWatts: watts,
            thermalPressure: pressure
        )
    }
}
