import XCTest
@testable import ViftyCore

final class TelemetryHistoryTests: XCTestCase {
    func testHistoryKeepsNewestSamplesWithinLimit() {
        var history = TelemetryHistory(limit: 3)
        for index in 0..<5 {
            history.append(sample(index: index))
        }

        XCTAssertEqual(history.samples.count, 3)
        XCTAssertEqual(history.sampleCount, 3)
        XCTAssertEqual(history.samples.first?.firstFanRPM, 2002)
        XCTAssertEqual(history.samples.last?.firstFanRPM, 2004)
        XCTAssertEqual(history.latestSample?.firstFanRPM, 2004)
        XCTAssertEqual(history.recentSamples(limit: 2).map(\.firstFanRPM), [2003, 2004])
    }

    func testRingHistoryPreservesOrderAfterWraparoundAndLimitGrowth() {
        var history = TelemetryHistory(limit: 3)
        for index in 0..<4 {
            history.append(sample(index: index))
        }

        XCTAssertEqual(history.samples.map(\.firstFanRPM), [2001, 2002, 2003])

        history.limit = 5
        history.append(sample(index: 4))
        history.append(sample(index: 5))

        XCTAssertEqual(history.samples.map(\.firstFanRPM), [2001, 2002, 2003, 2004, 2005])
        XCTAssertEqual(history.recentSamples(limit: 3).map(\.firstFanRPM), [2003, 2004, 2005])
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
        XCTAssertEqual(summary.plottedSeriesCountText, "2 plotted samples")
        XCTAssertEqual(summary.sampleWindowText, "1 s")
        XCTAssertEqual(summary.latestTemperatureLabel, "Latest temp")
        XCTAssertEqual(summary.latestTemperatureText, "72.6 °C")
        XCTAssertEqual(summary.latestFanRPMLabel, "Latest fan")
        XCTAssertEqual(summary.latestFanRPMText, "3450 RPM")
        XCTAssertEqual(summary.fanRPMTrendLabel, "Fan")
        XCTAssertEqual(summary.fanRPMSparklineTitle, "Fan")
        XCTAssertEqual(summary.latestBatteryPowerLabel, "Battery charge")
        XCTAssertEqual(summary.latestBatteryPowerText, "8.2 W")
        XCTAssertEqual(summary.latestBatteryPowerWatts, 8.25)
        XCTAssertEqual(summary.latestThermalPressureText, "Serious")
        XCTAssertEqual(summary.temperatureRangeText, "64.2 °C-72.6 °C")
        XCTAssertEqual(summary.temperatureChangeText, "+8.4 °C")
        XCTAssertEqual(summary.fanRPMRangeText, "2000 RPM-3450 RPM")
        XCTAssertEqual(summary.fanRPMChangeText, "+1450 RPM")
        XCTAssertEqual(summary.batteryPowerRangeText, "12.5 W drain to 8.2 W charge")
        XCTAssertEqual(summary.batteryPowerChangeText, "+20.8 W")
        XCTAssertEqual(summary.thermalPressureSamples, [.nominal, .serious])
        XCTAssertEqual(summary.thermalPressureSummaryText, "Peak Serious")
    }

    func testSummaryFormatsBoundedRecentSampleWindow() {
        var history = TelemetryHistory(limit: 10)
        history.append(sample(index: 0, capturedAt: 0))
        history.append(sample(index: 1, capturedAt: 30))
        history.append(sample(index: 2, capturedAt: 90))
        history.append(sample(index: 3, capturedAt: 150))

        let summary = TelemetryHistorySummary(history: history, sampleLimit: 3)

        XCTAssertEqual(summary.sampleCount, 4)
        XCTAssertEqual(summary.sampleWindowText, "2 min")
        XCTAssertEqual(summary.temperatureValues, [61, 62, 63])
    }

    func testSampleWindowTextHandlesShortLongAndInvalidWindows() {
        XCTAssertNil(TelemetryHistorySummary.sampleWindowText(for: []))
        XCTAssertNil(TelemetryHistorySummary.sampleWindowText(for: [sample(index: 0, capturedAt: 10)]))
        XCTAssertNil(TelemetryHistorySummary.sampleWindowText(for: [
            sample(index: 0, capturedAt: 10),
            sample(index: 1, capturedAt: 10)
        ]))
        XCTAssertEqual(TelemetryHistorySummary.sampleWindowText(for: [
            sample(index: 0, capturedAt: 10),
            sample(index: 1, capturedAt: 55)
        ]), "45 s")
        XCTAssertEqual(TelemetryHistorySummary.sampleWindowText(for: [
            sample(index: 0, capturedAt: 0),
            sample(index: 1, capturedAt: 3_600)
        ]), "1 h")
        XCTAssertEqual(TelemetryHistorySummary.sampleWindowText(for: [
            sample(index: 0, capturedAt: 0),
            sample(index: 1, capturedAt: 5_400)
        ]), "1 h 30 min")
    }

    func testSingleRetainedPointIsNotClaimedAsPlottedHistory() {
        XCTAssertEqual(
            TelemetryHistorySummary.plottedSeriesCountText(
                temperatureCount: 1,
                fanCount: 1,
                batteryPowerCount: 1,
                thermalPressureCount: 1,
                retainedSampleCount: 1
            ),
            "1 retained sample"
        )
    }

    func testHistoryReadinessTextMatchesTwoPollChartThreshold() {
        XCTAssertEqual(
            TelemetryHistorySummary.historyReadinessText(sampleCount: 0),
            "History appears after two successful polls."
        )
        XCTAssertEqual(
            TelemetryHistorySummary.historyReadinessText(sampleCount: 1),
            "History appears after one more successful poll."
        )
        XCTAssertNil(TelemetryHistorySummary.historyReadinessText(sampleCount: 2))
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
        XCTAssertEqual(summary.plottedSeriesCountText, "2 temp · 2 fan · 2 power · 3 thermal points")
        XCTAssertEqual(summary.fanRPMValues, [2003, 2004])
        XCTAssertEqual(summary.batteryPowerValues, [-10, -10])
        XCTAssertEqual(summary.temperatureRangeText, "63.0 °C-64.0 °C")
        XCTAssertEqual(summary.temperatureChangeText, "+1.0 °C")
        XCTAssertEqual(summary.fanRPMRangeText, "2003 RPM-2004 RPM")
        XCTAssertEqual(summary.fanRPMChangeText, "+1 RPM")
        XCTAssertEqual(summary.batteryPowerRangeText, "10.0 W drain")
        XCTAssertEqual(summary.batteryPowerChangeText, "steady")
        XCTAssertEqual(summary.thermalPressureSamples, [.nominal, .nominal, .nominal])
        XCTAssertEqual(summary.thermalPressureSummaryText, "Stable Nominal")
    }

    func testSummaryPrefersSelectedTemperatureAndAverageFanRPMWhenAvailable() {
        var history = TelemetryHistory(limit: 10)
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            selectedTemperatureID: "Tp01",
            selectedTemperatureName: "CPU Efficiency Core 1",
            selectedTemperatureCelsius: 67.4,
            temperatureWasUserSelected: true,
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
            temperatureWasUserSelected: true,
            highestTemperatureCelsius: 78.0,
            firstFanRPM: 2_400,
            averageFanRPM: 2_550.5,
            batteryPowerWatts: -7.2,
            thermalPressure: .serious
        ))

        let summary = TelemetryHistorySummary(history: history)

        XCTAssertEqual(summary.latestTemperatureLabel, "Selected temp")
        XCTAssertEqual(summary.latestTemperatureText, "69.2 °C")
        XCTAssertEqual(summary.latestFanRPMLabel, "Average fan")
        XCTAssertEqual(summary.latestFanRPMText, "2551 RPM")
        XCTAssertEqual(summary.fanRPMTrendLabel, "Avg fan")
        XCTAssertEqual(summary.fanRPMSparklineTitle, "Avg fan")
        XCTAssertEqual(summary.temperatureValues, [67.4, 69.2])
        XCTAssertEqual(summary.fanRPMValues, [2_250.5, 2_550.5])
        XCTAssertEqual(summary.temperatureRangeText, "67.4 °C-69.2 °C")
        XCTAssertEqual(summary.temperatureChangeText, "+1.8 °C")
        XCTAssertEqual(summary.fanRPMRangeText, "2251 RPM-2551 RPM")
        XCTAssertEqual(summary.fanRPMChangeText, "+300 RPM")
        XCTAssertEqual(summary.batteryPowerChangeText, "-1.0 W")
        XCTAssertEqual(summary.thermalPressureSummaryText, "Peak Serious")
    }

    func testSummaryDoesNotMixAverageFanTrendWithFirstFanFallbacks() {
        var history = TelemetryHistory(limit: 10)
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            highestTemperatureCelsius: 64.0,
            firstFanRPM: 2_100,
            batteryPowerWatts: -6.2,
            thermalPressure: .fair
        ))
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 2),
            highestTemperatureCelsius: 65.0,
            firstFanRPM: 2_400,
            averageFanRPM: 2_550.5,
            batteryPowerWatts: -7.2,
            thermalPressure: .serious
        ))

        let summary = TelemetryHistorySummary(history: history)

        XCTAssertEqual(summary.latestFanRPMLabel, "Average fan")
        XCTAssertEqual(summary.latestFanRPMText, "2551 RPM")
        XCTAssertEqual(summary.fanRPMTrendLabel, "Avg fan")
        XCTAssertEqual(summary.fanRPMValues, [2_550.5])
        XCTAssertEqual(summary.fanRPMRangeText, "2551 RPM")
        XCTAssertNil(summary.fanRPMChangeText)
    }

    func testSummaryDoesNotMixFirstFanTrendWithOlderAverageSamples() {
        var history = TelemetryHistory(limit: 10)
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            highestTemperatureCelsius: 64.0,
            firstFanRPM: 2_100,
            averageFanRPM: 2_700.0,
            batteryPowerWatts: -6.2,
            thermalPressure: .fair
        ))
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 2),
            highestTemperatureCelsius: 65.0,
            firstFanRPM: 2_400,
            batteryPowerWatts: -7.2,
            thermalPressure: .serious
        ))

        let summary = TelemetryHistorySummary(history: history)

        XCTAssertEqual(summary.latestFanRPMLabel, "Latest fan")
        XCTAssertEqual(summary.latestFanRPMText, "2400 RPM")
        XCTAssertEqual(summary.fanRPMTrendLabel, "Fan")
        XCTAssertEqual(summary.fanRPMValues, [2_100, 2_400])
        XCTAssertEqual(summary.fanRPMRangeText, "2100 RPM-2400 RPM")
        XCTAssertEqual(summary.fanRPMChangeText, "+300 RPM")
    }

    func testSummaryDoesNotMixSelectedTemperatureSensorsInRecentRange() {
        var history = TelemetryHistory(limit: 10)
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            selectedTemperatureID: "Tp01",
            selectedTemperatureName: "CPU Efficiency Core 1",
            selectedTemperatureCelsius: 67.4,
            temperatureWasUserSelected: true,
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
            temperatureWasUserSelected: true,
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
            temperatureWasUserSelected: true,
            highestTemperatureCelsius: 79.1,
            firstFanRPM: 2_900,
            batteryPowerWatts: -11.0,
            thermalPressure: .serious
        ))

        let summary = TelemetryHistorySummary(history: history)

        XCTAssertEqual(summary.latestTemperatureText, "69.2 °C")
        XCTAssertEqual(summary.temperatureValues, [67.4, 69.2])
        XCTAssertEqual(summary.plottedSeriesCountText, "2 temp · 3 fan · 3 power · 3 thermal points")
        XCTAssertEqual(summary.temperatureRangeText, "67.4 °C-69.2 °C")
        XCTAssertEqual(summary.temperatureChangeText, "+1.8 °C")
    }

    func testChangeTextRequiresTwoSamplesAndMarksFlatLinesSteady() {
        XCTAssertNil(TelemetryHistorySummary.changeText([], unit: "C", decimals: 1))
        XCTAssertNil(TelemetryHistorySummary.changeText([72.0], unit: "C", decimals: 1))
        XCTAssertEqual(TelemetryHistorySummary.changeText([72.0, 72.02], unit: "C", decimals: 1), "steady")
        XCTAssertEqual(
            TelemetryHistorySummary.changeText([50.0, 50.0, 100.0, 50.0], unit: "°C", decimals: 1),
            "returned to start"
        )
        XCTAssertEqual(TelemetryHistorySummary.changeText([72.0, 70.5], unit: "C", decimals: 1), "-1.5 C")
        XCTAssertEqual(TelemetryHistorySummary.changeText([2200.0, 2400.0], unit: "RPM", decimals: 0), "+200 RPM")
    }

    func testSummaryDistinguishesAutomaticTemperatureSourceFromUserSelectedSensor() {
        var automaticHistory = TelemetryHistory(limit: 10)
        automaticHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            selectedTemperatureID: "Tp09",
            selectedTemperatureName: "CPU Proximity",
            selectedTemperatureCelsius: 71.0,
            temperatureWasUserSelected: false,
            highestTemperatureCelsius: 71.0,
            firstFanRPM: 2_100,
            batteryPowerWatts: -6.0,
            thermalPressure: .nominal
        ))

        XCTAssertEqual(TelemetryHistorySummary(history: automaticHistory).latestTemperatureLabel, "CPU temp")

        for name in ["Package Proximity", "SoC Die"] {
            var automaticPackageHistory = TelemetryHistory(limit: 10)
            automaticPackageHistory.append(TelemetrySample(
                capturedAt: Date(timeIntervalSince1970: 2),
                selectedTemperatureID: name,
                selectedTemperatureName: name,
                selectedTemperatureCelsius: 71.0,
                temperatureWasUserSelected: false,
                highestTemperatureCelsius: 71.0,
                firstFanRPM: 2_100,
                batteryPowerWatts: -6.0,
                thermalPressure: .nominal
            ))

            XCTAssertEqual(TelemetryHistorySummary(history: automaticPackageHistory).latestTemperatureLabel, "CPU temp")
        }

        var automaticNonCPUHistory = TelemetryHistory(limit: 10)
        automaticNonCPUHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 2),
            selectedTemperatureID: "TB0T",
            selectedTemperatureName: "Battery",
            selectedTemperatureCelsius: 42.0,
            temperatureWasUserSelected: false,
            highestTemperatureCelsius: 42.0,
            firstFanRPM: 2_100,
            batteryPowerWatts: -6.0,
            thermalPressure: .nominal
        ))

        XCTAssertEqual(TelemetryHistorySummary(history: automaticNonCPUHistory).latestTemperatureLabel, "Highest temp")

        var selectedHistory = TelemetryHistory(limit: 10)
        selectedHistory.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            selectedTemperatureID: "Tp01",
            selectedTemperatureName: "CPU Efficiency Core 1",
            selectedTemperatureCelsius: 66.0,
            temperatureWasUserSelected: true,
            highestTemperatureCelsius: 71.0,
            firstFanRPM: 2_100,
            batteryPowerWatts: -6.0,
            thermalPressure: .nominal
        ))

        XCTAssertEqual(TelemetryHistorySummary(history: selectedHistory).latestTemperatureLabel, "Selected temp")
    }

    func testSignedWattRangeTextUsesDrainAndChargeLanguage() {
        XCTAssertEqual(TelemetryHistorySummary.signedWattRangeText([-12.0, -5.0]), "5.0 W-12.0 W drain")
        XCTAssertEqual(TelemetryHistorySummary.signedWattRangeText([3.0, 8.0]), "3.0 W-8.0 W charge")
        XCTAssertEqual(TelemetryHistorySummary.signedWattRangeText([-12.0, 8.0]), "12.0 W drain to 8.0 W charge")
        XCTAssertEqual(TelemetryHistorySummary.signedWattRangeText([0.0, 0.0]), "0.0 W")
    }

    func testZeroBatteryPowerUsesNeutralLabel() {
        var history = TelemetryHistory(limit: 10)
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            highestTemperatureCelsius: 64.2,
            firstFanRPM: 2_000,
            batteryPowerWatts: 0.0,
            thermalPressure: .nominal
        ))

        let summary = TelemetryHistorySummary(history: history)

        XCTAssertEqual(summary.latestBatteryPowerLabel, "Battery power")
        XCTAssertEqual(summary.latestBatteryPowerText, "0.0 W")
    }

    private func sample(index: Int, capturedAt: TimeInterval? = nil) -> TelemetrySample {
        TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: capturedAt ?? Double(index)),
            highestTemperatureCelsius: Double(60 + index),
            firstFanRPM: 2000 + index,
            batteryPowerWatts: -10,
            thermalPressure: .nominal
        )
    }
}
