import Foundation
import ViftyCore

struct TelemetrySession: Equatable {
    private(set) var history: TelemetryHistory
    private(set) var overviewSummary: TelemetryHistorySummary
    private(set) var compactSummary: TelemetryHistorySummary
    private(set) var recentTrendSummary: String?

    init(history: TelemetryHistory = TelemetryHistory()) {
        self.history = history
        overviewSummary = TelemetryHistorySummary(
            history: history,
            sampleLimit: 180,
            thermalPressureLimit: 36
        )
        compactSummary = TelemetryHistorySummary(
            history: history,
            sampleLimit: 90,
            thermalPressureLimit: 24
        )
        recentTrendSummary = Self.trendSummary(from: compactSummary)
    }

    mutating func replaceHistory(_ history: TelemetryHistory) {
        self = TelemetrySession(history: history)
    }

    mutating func append(_ sample: TelemetrySample) {
        history.append(sample)
        refreshSummaries()
    }

    mutating func record(
        snapshot: HardwareSnapshot,
        power: PowerSnapshot,
        thermalPressure: ThermalPressure,
        userSelectedSensorID: String?,
        capturedAt: Date
    ) {
        let selection = TemperatureSensorSelection.resolve(
            sensors: snapshot.temperatureSensors,
            selectedSensorID: userSelectedSensorID
        )
        let selectedSensor = selection.curveMetric
        append(TelemetrySample(
            capturedAt: capturedAt,
            selectedTemperatureID: selectedSensor?.id,
            selectedTemperatureName: selectedSensor?.name,
            selectedTemperatureCelsius: selectedSensor?.celsius,
            temperatureWasUserSelected: userSelectedSensorID != nil
                && selectedSensor?.id == userSelectedSensorID,
            temperatureRole: selection.curveMetricRole,
            highestTemperatureCelsius: snapshot.highestTemperature?.celsius,
            firstFanRPM: snapshot.fans.first?.currentRPM,
            averageFanRPM: Self.averageFanRPM(in: snapshot.fans),
            batteryPowerWatts: power.batteryPowerWatts,
            thermalPressure: thermalPressure
        ))
    }

    private mutating func refreshSummaries() {
        overviewSummary = TelemetryHistorySummary(
            history: history,
            sampleLimit: 180,
            thermalPressureLimit: 36
        )
        compactSummary = TelemetryHistorySummary(
            history: history,
            sampleLimit: 90,
            thermalPressureLimit: 24
        )
        recentTrendSummary = Self.trendSummary(from: compactSummary)
    }

    private static func averageFanRPM(in fans: [Fan]) -> Double? {
        guard !fans.isEmpty else { return nil }
        return Double(fans.reduce(0) { $0 + $1.currentRPM }) / Double(fans.count)
    }

    private static func trendSummary(from summary: TelemetryHistorySummary) -> String? {
        guard summary.sampleCount >= 2 else { return nil }

        var parts: [String] = []
        if let temperatureChangeText = summary.temperatureChangeText {
            parts.append("Temp \(temperatureChangeText)")
        }
        if let fanRPMChangeText = summary.fanRPMChangeText {
            parts.append("\(summary.fanRPMTrendLabel) \(fanRPMChangeText)")
        }
        if let batteryPowerChangeText = summary.batteryPowerChangeText {
            parts.append("Power \(batteryPowerChangeText)")
        }
        if summary.thermalPressureSamples.count >= 2,
           summary.thermalPressureSummaryText != "Stable Nominal" {
            parts.append(summary.thermalPressureSummaryText)
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
