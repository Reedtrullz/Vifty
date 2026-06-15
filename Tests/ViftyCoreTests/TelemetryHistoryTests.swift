import XCTest
@testable import ViftyCore

final class TelemetryHistoryTests: XCTestCase {
    func testHistoryKeepsNewestSamplesWithinLimit() {
        var history = TelemetryHistory(limit: 3)
        for index in 0..<5 {
            history.append(sample(index: index))
        }

        XCTAssertEqual(history.samples.count, 3)
        XCTAssertEqual(history.samples.first?.firstFanRPM, 2002)
        XCTAssertEqual(history.samples.last?.firstFanRPM, 2004)
    }

    func testInitialLimitClampsToOneAndKeepsNewestSample() {
        var history = TelemetryHistory(limit: 0)

        history.append(sample(index: 0))
        history.append(sample(index: 1))

        XCTAssertEqual(history.limit, 1)
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.first?.firstFanRPM, 2001)
    }

    func testMutatedLimitClampsTrimsAndAllowsFutureAppends() {
        var history = TelemetryHistory(limit: 3)
        for index in 0..<3 {
            history.append(sample(index: index))
        }

        history.limit = 0

        XCTAssertEqual(history.limit, 1)
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.first?.firstFanRPM, 2002)

        history.limit = -4
        history.append(sample(index: 3))

        XCTAssertEqual(history.limit, 1)
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.first?.firstFanRPM, 2003)
    }

    func testSummaryFormatsLatestValuesAndRanges() {
        var history = TelemetryHistory(limit: 10)
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            highestTemperatureCelsius: 64.2,
            firstFanRPM: 2_000,
            batteryPowerWatts: -12.5,
            thermalPressure: .nominal
        ))
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 2),
            highestTemperatureCelsius: 72.6,
            firstFanRPM: 3_450,
            batteryPowerWatts: 8.25,
            thermalPressure: .serious
        ))

        let summary = TelemetryHistorySummary(history: history)

        XCTAssertEqual(summary.sampleCount, 2)
        XCTAssertEqual(summary.sampleCountText, "2 samples")
        XCTAssertEqual(summary.latestTemperatureLabel, "Latest temp")
        XCTAssertEqual(summary.latestTemperatureText, "72.6 C")
        XCTAssertEqual(summary.latestFanRPMLabel, "Latest fan")
        XCTAssertEqual(summary.latestFanRPMText, "3450 RPM")
        XCTAssertEqual(summary.latestBatteryPowerLabel, "Battery charge")
        XCTAssertEqual(summary.latestBatteryPowerText, "8.2 W")
        XCTAssertEqual(summary.latestThermalPressureText, "Serious")
        XCTAssertEqual(summary.temperatureRangeText, "64.2 C-72.6 C")
        XCTAssertEqual(summary.fanRPMRangeText, "2000 RPM-3450 RPM")
        XCTAssertEqual(summary.batteryPowerRangeText, "-12.5 W-+8.2 W")
        XCTAssertEqual(summary.thermalPressureSamples, [.nominal, .serious])
    }

    func testSummaryAppliesIndependentSampleAndThermalWindows() {
        var history = TelemetryHistory(limit: 10)
        for index in 0..<5 {
            history.append(sample(index: index))
        }

        let summary = TelemetryHistorySummary(
            history: history,
            sampleLimit: 2,
            thermalPressureLimit: 3
        )

        XCTAssertEqual(summary.sampleCount, 5)
        XCTAssertEqual(summary.temperatureValues, [63, 64])
        XCTAssertEqual(summary.fanRPMValues, [2003, 2004])
        XCTAssertEqual(summary.batteryPowerValues, [-10, -10])
        XCTAssertEqual(summary.temperatureRangeText, "63.0 C-64.0 C")
        XCTAssertEqual(summary.fanRPMRangeText, "2003 RPM-2004 RPM")
        XCTAssertEqual(summary.batteryPowerRangeText, "-10.0 W")
        XCTAssertEqual(summary.thermalPressureSamples, [.nominal, .nominal, .nominal])
    }

    func testSummaryPrefersSelectedTemperatureAndAverageFanRPMWhenAvailable() {
        var history = TelemetryHistory(limit: 10)
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            selectedTemperatureID: "Tp01",
            selectedTemperatureName: "CPU Efficiency Core 1",
            selectedTemperatureCelsius: 67.4,
            highestTemperatureCelsius: 72.1,
            firstFanRPM: 2_100,
            averageFanRPM: 2_250.5,
            batteryPowerWatts: -6.2,
            thermalPressure: .fair
        ))
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 2),
            selectedTemperatureID: "Tp01",
            selectedTemperatureName: "CPU Efficiency Core 1",
            selectedTemperatureCelsius: 69.2,
            highestTemperatureCelsius: 78.0,
            firstFanRPM: 2_400,
            averageFanRPM: 2_550.5,
            batteryPowerWatts: -7.2,
            thermalPressure: .serious
        ))

        let summary = TelemetryHistorySummary(history: history)

        XCTAssertEqual(summary.latestTemperatureLabel, "Selected temp")
        XCTAssertEqual(summary.latestTemperatureText, "69.2 C")
        XCTAssertEqual(summary.latestFanRPMLabel, "Average fan")
        XCTAssertEqual(summary.latestFanRPMText, "2551 RPM")
        XCTAssertEqual(summary.temperatureValues, [67.4, 69.2])
        XCTAssertEqual(summary.fanRPMValues, [2_250.5, 2_550.5])
        XCTAssertEqual(summary.temperatureRangeText, "67.4 C-69.2 C")
        XCTAssertEqual(summary.fanRPMRangeText, "2251 RPM-2551 RPM")
    }

    func testSummaryDoesNotMixSelectedTemperatureSensorsInRecentRange() {
        var history = TelemetryHistory(limit: 10)
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            selectedTemperatureID: "Tp01",
            selectedTemperatureName: "CPU Efficiency Core 1",
            selectedTemperatureCelsius: 67.4,
            highestTemperatureCelsius: 72.1,
            firstFanRPM: 2_100,
            batteryPowerWatts: -6.2,
            thermalPressure: .fair
        ))
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 2),
            selectedTemperatureID: "Tp09",
            selectedTemperatureName: "CPU Performance Core 1",
            selectedTemperatureCelsius: 78.8,
            highestTemperatureCelsius: 78.8,
            firstFanRPM: 2_600,
            batteryPowerWatts: -9.2,
            thermalPressure: .fair
        ))
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 3),
            selectedTemperatureID: "Tp01",
            selectedTemperatureName: "CPU Efficiency Core 1",
            selectedTemperatureCelsius: 69.2,
            highestTemperatureCelsius: 79.1,
            firstFanRPM: 2_900,
            batteryPowerWatts: -11.0,
            thermalPressure: .serious
        ))

        let summary = TelemetryHistorySummary(history: history)

        XCTAssertEqual(summary.latestTemperatureText, "69.2 C")
        XCTAssertEqual(summary.temperatureValues, [67.4, 69.2])
        XCTAssertEqual(summary.temperatureRangeText, "67.4 C-69.2 C")
    }

    private func sample(index: Int) -> TelemetrySample {
        TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: Double(index)),
            highestTemperatureCelsius: Double(60 + index),
            firstFanRPM: 2000 + index,
            batteryPowerWatts: -10,
            thermalPressure: .nominal
        )
    }
}
