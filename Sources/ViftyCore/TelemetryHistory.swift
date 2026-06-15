import Foundation

public struct TelemetrySample: Equatable, Identifiable, Sendable {
    public var id: Date { capturedAt }
    public var capturedAt: Date
    public var highestTemperatureCelsius: Double?
    public var firstFanRPM: Int?
    public var batteryPowerWatts: Double?
    public var thermalPressure: ThermalPressure

    public init(
        capturedAt: Date,
        highestTemperatureCelsius: Double?,
        firstFanRPM: Int?,
        batteryPowerWatts: Double?,
        thermalPressure: ThermalPressure
    ) {
        self.capturedAt = capturedAt
        self.highestTemperatureCelsius = highestTemperatureCelsius
        self.firstFanRPM = firstFanRPM
        self.batteryPowerWatts = batteryPowerWatts
        self.thermalPressure = thermalPressure
    }
}

public struct TelemetryHistory: Equatable, Sendable {
    public private(set) var samples: [TelemetrySample] = []
    public var limit: Int {
        didSet {
            limit = max(1, limit)
            trimToLimit()
        }
    }

    public init(limit: Int = 900) {
        self.limit = max(1, limit)
    }

    public mutating func append(_ sample: TelemetrySample) {
        samples.append(sample)
        trimToLimit()
    }

    private mutating func trimToLimit() {
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }
}

public struct TelemetryHistorySummary: Equatable, Sendable {
    public var sampleCount: Int
    public var sampleCountText: String
    public var latestTemperatureText: String?
    public var latestFanRPMText: String?
    public var latestBatteryPowerLabel: String?
    public var latestBatteryPowerText: String?
    public var latestThermalPressureText: String
    public var temperatureValues: [Double]
    public var fanRPMValues: [Double]
    public var batteryPowerValues: [Double]
    public var temperatureRangeText: String
    public var fanRPMRangeText: String
    public var batteryPowerRangeText: String
    public var thermalPressureSamples: [ThermalPressure]

    public init(
        history: TelemetryHistory,
        sampleLimit: Int = 180,
        thermalPressureLimit: Int = 36
    ) {
        let boundedSampleLimit = max(1, sampleLimit)
        let boundedThermalLimit = max(1, thermalPressureLimit)
        let recentSamples = Array(history.samples.suffix(boundedSampleLimit))
        let latest = history.samples.last

        sampleCount = history.samples.count
        sampleCountText = history.samples.count == 1 ? "1 sample" : "\(history.samples.count) samples"
        latestTemperatureText = latest?.highestTemperatureCelsius.map(Self.temperatureText)
        latestFanRPMText = latest?.firstFanRPM.map(Self.fanRPMText)
        if let batteryPowerWatts = latest?.batteryPowerWatts {
            latestBatteryPowerLabel = batteryPowerWatts < 0 ? "Battery drain" : "Battery charge"
            latestBatteryPowerText = PowerDisplayFormatter.watts(abs(batteryPowerWatts))
        } else {
            latestBatteryPowerLabel = nil
            latestBatteryPowerText = nil
        }
        latestThermalPressureText = latest?.thermalPressure.displayName ?? "--"
        temperatureValues = recentSamples.compactMap(\.highestTemperatureCelsius)
        fanRPMValues = recentSamples.compactMap { $0.firstFanRPM.map(Double.init) }
        batteryPowerValues = recentSamples.compactMap(\.batteryPowerWatts)
        temperatureRangeText = Self.unsignedRangeText(temperatureValues, unit: "C", decimals: 1)
        fanRPMRangeText = Self.unsignedRangeText(fanRPMValues, unit: "RPM", decimals: 0)
        batteryPowerRangeText = Self.signedWattRangeText(batteryPowerValues)
        thermalPressureSamples = history.samples.suffix(boundedThermalLimit).map(\.thermalPressure)
    }

    public static func temperatureText(_ value: Double) -> String {
        String(format: "%.1f C", value)
    }

    public static func fanRPMText(_ value: Int) -> String {
        "\(value) RPM"
    }

    public static func unsignedRangeText(_ values: [Double], unit: String, decimals: Int) -> String {
        guard let min = values.min(), let max = values.max() else { return "--" }
        let lower = formatUnsigned(min, unit: unit, decimals: decimals)
        let upper = formatUnsigned(max, unit: unit, decimals: decimals)
        return lower == upper ? lower : "\(lower)-\(upper)"
    }

    public static func signedWattRangeText(_ values: [Double]) -> String {
        guard let min = values.min(), let max = values.max() else { return "--" }
        let lower = signedWatts(min)
        let upper = signedWatts(max)
        return lower == upper ? lower : "\(lower)-\(upper)"
    }

    private static func formatUnsigned(_ value: Double, unit: String, decimals: Int) -> String {
        if decimals == 0 {
            return "\(Int(value.rounded())) \(unit)"
        }
        return String(format: "%.1f %@", value, unit)
    }

    private static func signedWatts(_ value: Double) -> String {
        let formatted = PowerDisplayFormatter.watts(abs(value))
        if value < 0 { return "-\(formatted)" }
        if value > 0 { return "+\(formatted)" }
        return formatted
    }
}
