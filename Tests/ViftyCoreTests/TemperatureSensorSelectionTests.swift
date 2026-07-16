import XCTest
@testable import ViftyCore

final class TemperatureSensorSelectionTests: XCTestCase {
    func testSelectedCurveMetricStaysSeparateFromHighestSafetyMetric() {
        let selected = TemperatureSensor(
            id: "Tp01",
            name: "CPU Efficiency Core 1",
            celsius: 61,
            source: .smc
        )
        let hottest = TemperatureSensor(
            id: "TG0P",
            name: "GPU Proximity",
            celsius: 92,
            source: .smc
        )

        let result = TemperatureSensorSelection.resolve(
            sensors: [selected, hottest],
            selectedSensorID: selected.id
        )

        XCTAssertEqual(result.curveMetric, selected)
        XCTAssertEqual(result.curveMetricRole, .curveSensor)
        XCTAssertEqual(result.highestSafetyMetric, hottest)
        XCTAssertEqual(result.curveMetricLabel, "Curve sensor · CPU Efficiency Core 1")
    }

    func testAutomaticCPURoleDoesNotPretendToBeHighest() {
        let cpu = TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 70, source: .smc)
        let hottest = TemperatureSensor(id: "TG0P", name: "GPU Proximity", celsius: 84, source: .smc)

        let result = TemperatureSensorSelection.resolve(
            sensors: [cpu, hottest],
            selectedSensorID: nil
        )

        XCTAssertEqual(result.curveMetric, cpu)
        XCTAssertEqual(result.curveMetricRole, .automaticCPU)
        XCTAssertEqual(result.highestSafetyMetric, hottest)
        XCTAssertEqual(result.curveMetricLabel, "Automatic CPU · CPU Proximity")
    }

    func testNonCPUFallbackIsExplicitlyHighest() {
        let battery = TemperatureSensor(id: "TB0T", name: "Battery", celsius: 41, source: .smc)
        let memory = TemperatureSensor(id: "TM0P", name: "Memory Proximity", celsius: 76, source: .smc)

        let result = TemperatureSensorSelection.resolve(
            sensors: [battery, memory],
            selectedSensorID: nil
        )

        XCTAssertEqual(result.curveMetric, memory)
        XCTAssertEqual(result.curveMetricRole, .highestFallback)
        XCTAssertEqual(result.highestSafetyMetric, memory)
        XCTAssertEqual(result.curveMetricLabel, "Highest fallback · Memory Proximity")
    }

    func testTelemetrySummaryLabelsExactRoleAndSensor() {
        var history = TelemetryHistory(limit: 2)
        history.append(TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: 1),
            selectedTemperatureID: "Tp01",
            selectedTemperatureName: "CPU Efficiency Core 1",
            selectedTemperatureCelsius: 61,
            temperatureWasUserSelected: true,
            temperatureRole: .curveSensor,
            highestTemperatureCelsius: 92,
            firstFanRPM: 2_000,
            batteryPowerWatts: nil,
            thermalPressure: .nominal
        ))

        let summary = TelemetryHistorySummary(history: history)

        XCTAssertEqual(summary.latestTemperatureText, "61.0 °C")
        XCTAssertEqual(summary.latestTemperatureLabel, "Curve sensor · CPU Efficiency Core 1")
        XCTAssertEqual(history.latestSample?.highestTemperatureCelsius, 92)
    }
}
