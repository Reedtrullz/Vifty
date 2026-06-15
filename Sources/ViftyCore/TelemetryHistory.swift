import Foundation

public struct TelemetrySample: Equatable, Identifiable, Sendable {
    public var id: Date { capturedAt }
    public var capturedAt: Date
    public var selectedTemperatureID: String?
    public var selectedTemperatureName: String?
    public var selectedTemperatureCelsius: Double?
    public var highestTemperatureCelsius: Double?
    public var firstFanRPM: Int?
    public var averageFanRPM: Double?
    public var batteryPowerWatts: Double?
    public var thermalPressure: ThermalPressure

    public init(
        capturedAt: Date,
        selectedTemperatureID: String? = nil,
        selectedTemperatureName: String? = nil,
        selectedTemperatureCelsius: Double? = nil,
        highestTemperatureCelsius: Double?,
        firstFanRPM: Int?,
        averageFanRPM: Double? = nil,
        batteryPowerWatts: Double?,
        thermalPressure: ThermalPressure
    ) {
        self.capturedAt = capturedAt
        self.selectedTemperatureID = selectedTemperatureID
        self.selectedTemperatureName = selectedTemperatureName
        self.selectedTemperatureCelsius = selectedTemperatureCelsius
        self.highestTemperatureCelsius = highestTemperatureCelsius
        self.firstFanRPM = firstFanRPM
        self.averageFanRPM = averageFanRPM
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
    public var latestTemperatureLabel: String
    public var latestTemperatureText: String?
    public var latestFanRPMLabel: String
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
        latestTemperatureLabel = latest?.selectedTemperatureCelsius == nil ? "Latest temp" : "Selected temp"
        latestTemperatureText = latest.flatMap(Self.sampleTemperature).map(Self.temperatureText)
        latestFanRPMLabel = (latest?.averageFanRPM == nil) ? "Latest fan" : "Average fan"
        latestFanRPMText = latest.flatMap(Self.sampleFanRPM).map(Self.fanRPMText)
        if let batteryPowerWatts = latest?.batteryPowerWatts {
            latestBatteryPowerLabel = batteryPowerWatts < 0 ? "Battery drain" : "Battery charge"
            latestBatteryPowerText = PowerDisplayFormatter.watts(abs(batteryPowerWatts))
        } else {
            latestBatteryPowerLabel = nil
            latestBatteryPowerText = nil
        }
        latestThermalPressureText = latest?.thermalPressure.displayName ?? "--"
        temperatureValues = Self.temperatureValues(from: recentSamples, latest: latest)
        fanRPMValues = recentSamples.compactMap(Self.sampleFanRPM)
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

    public static func fanRPMText(_ value: Double) -> String {
        "\(Int(value.rounded())) RPM"
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

    private static func sampleTemperature(_ sample: TelemetrySample) -> Double? {
        sample.selectedTemperatureCelsius ?? sample.highestTemperatureCelsius
    }

    private static func temperatureValues(from samples: [TelemetrySample], latest: TelemetrySample?) -> [Double] {
        if let selectedTemperatureID = latest?.selectedTemperatureID,
           latest?.selectedTemperatureCelsius != nil {
            let matchingSelectedValues = samples.compactMap { sample -> Double? in
                guard sample.selectedTemperatureID == selectedTemperatureID else { return nil }
                return sample.selectedTemperatureCelsius
            }
            if !matchingSelectedValues.isEmpty {
                return matchingSelectedValues
            }
        }
        return samples.compactMap(Self.sampleTemperature)
    }

    private static func sampleFanRPM(_ sample: TelemetrySample) -> Double? {
        sample.averageFanRPM ?? sample.firstFanRPM.map(Double.init)
    }
}
