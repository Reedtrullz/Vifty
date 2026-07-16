import Foundation

public struct TelemetrySample: Equatable, Identifiable, Sendable {
    public var id: Date { capturedAt }
    public var capturedAt: Date
    public var selectedTemperatureID: String?
    public var selectedTemperatureName: String?
    public var selectedTemperatureCelsius: Double?
    public var temperatureWasUserSelected: Bool
    public var temperatureRole: TemperatureSensorRole?
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
        temperatureWasUserSelected: Bool = false,
        temperatureRole: TemperatureSensorRole? = nil,
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
        self.temperatureWasUserSelected = temperatureWasUserSelected
        self.temperatureRole = temperatureRole
        self.highestTemperatureCelsius = highestTemperatureCelsius
        self.firstFanRPM = firstFanRPM
        self.averageFanRPM = averageFanRPM
        self.batteryPowerWatts = batteryPowerWatts
        self.thermalPressure = thermalPressure
    }
}

public struct TelemetryHistory: Equatable, Sendable {
    private var storage: [TelemetrySample] = []
    private var startIndex = 0
    public private(set) var sampleCount = 0
    public var limit: Int {
        didSet {
            limit = max(1, limit)
            trimToLimit()
        }
    }

    public init(limit: Int = 900) {
        self.limit = max(1, limit)
    }

    public var samples: [TelemetrySample] {
        recentSamples(limit: sampleCount)
    }

    public var latestSample: TelemetrySample? {
        guard sampleCount > 0, !storage.isEmpty else { return nil }
        return storage[logicalIndex(sampleCount - 1)]
    }

    public mutating func append(_ sample: TelemetrySample) {
        if sampleCount < limit {
            if storage.count < limit {
                normalizeStorageIfNeeded()
                storage.append(sample)
            } else {
                storage[logicalIndex(sampleCount)] = sample
            }
            sampleCount += 1
            return
        }

        if storage.count < limit {
            trimToLimit()
        }
        storage[startIndex] = sample
        startIndex = (startIndex + 1) % storage.count
        sampleCount = limit
    }

    public func recentSamples(limit requestedLimit: Int) -> [TelemetrySample] {
        guard sampleCount > 0 else { return [] }
        let boundedLimit = max(0, min(requestedLimit, sampleCount))
        guard boundedLimit > 0 else { return [] }
        let start = sampleCount - boundedLimit
        return (start..<sampleCount).map { storage[logicalIndex($0)] }
    }

    private mutating func trimToLimit() {
        guard sampleCount > limit else { return }
        let retained = recentSamples(limit: limit)
        storage = retained
        startIndex = 0
        sampleCount = retained.count
    }

    private mutating func normalizeStorageIfNeeded() {
        guard startIndex != 0 else { return }
        storage = samples
        startIndex = 0
    }

    private func logicalIndex(_ offset: Int) -> Int {
        (startIndex + offset) % storage.count
    }

    public static func == (lhs: TelemetryHistory, rhs: TelemetryHistory) -> Bool {
        lhs.limit == rhs.limit && lhs.samples == rhs.samples
    }
}

public struct TelemetryHistorySummary: Equatable, Sendable {
    public var sampleCount: Int
    public var sampleCountText: String
    public var plottedSeriesCountText: String
    public var sampleWindowText: String?
    public var latestTemperatureLabel: String
    public var latestTemperatureText: String?
    public var latestFanRPMLabel: String
    public var latestFanRPMText: String?
    public var fanRPMTrendLabel: String
    public var fanRPMSparklineTitle: String
    public var latestBatteryPowerLabel: String?
    public var latestBatteryPowerText: String?
    public var latestBatteryPowerWatts: Double?
    public var latestThermalPressureText: String
    public var temperatureValues: [Double]
    public var fanRPMValues: [Double]
    public var batteryPowerValues: [Double]
    public var temperatureRangeText: String
    public var temperatureChangeText: String?
    public var fanRPMRangeText: String
    public var fanRPMChangeText: String?
    public var batteryPowerRangeText: String
    public var batteryPowerChangeText: String?
    public var thermalPressureSamples: [ThermalPressure]
    public var thermalPressureSummaryText: String

    public init(
        history: TelemetryHistory,
        sampleLimit: Int = 180,
        thermalPressureLimit: Int = 36
    ) {
        let boundedSampleLimit = max(1, sampleLimit)
        let boundedThermalLimit = max(1, thermalPressureLimit)
        let recentSamples = history.recentSamples(limit: boundedSampleLimit)
        let latest = history.latestSample

        sampleCount = history.sampleCount
        sampleCountText = history.sampleCount == 1 ? "1 sample" : "\(history.sampleCount) samples"
        sampleWindowText = Self.sampleWindowText(for: recentSamples)
        latestTemperatureLabel = Self.temperatureLabel(for: latest)
        latestTemperatureText = latest.flatMap(Self.sampleTemperature).map(Self.temperatureText)
        let usesAverageFanRPM = latest?.averageFanRPM != nil
        latestFanRPMLabel = usesAverageFanRPM ? "Average fan" : "Latest fan"
        fanRPMTrendLabel = usesAverageFanRPM ? "Avg fan" : "Fan"
        fanRPMSparklineTitle = usesAverageFanRPM ? "Avg fan" : "Fan"
        latestFanRPMText = latest.flatMap(Self.sampleFanRPM).map(Self.fanRPMText)
        latestBatteryPowerWatts = latest?.batteryPowerWatts
        if let batteryPowerWatts = latestBatteryPowerWatts {
            if abs(batteryPowerWatts) < 0.1 {
                latestBatteryPowerLabel = "Battery power"
            } else {
                latestBatteryPowerLabel = batteryPowerWatts < 0 ? "Battery drain" : "Battery charge"
            }
            latestBatteryPowerText = PowerDisplayFormatter.watts(abs(batteryPowerWatts))
        } else {
            latestBatteryPowerLabel = nil
            latestBatteryPowerText = nil
        }
        latestThermalPressureText = latest?.thermalPressure.displayName ?? "--"
        temperatureValues = Self.temperatureValues(from: recentSamples, latest: latest)
        fanRPMValues = Self.fanRPMValues(from: recentSamples, usesAverageFanRPM: usesAverageFanRPM)
        batteryPowerValues = recentSamples.compactMap(\.batteryPowerWatts)
        plottedSeriesCountText = Self.plottedSeriesCountText(
            temperatureCount: temperatureValues.count,
            fanCount: fanRPMValues.count,
            batteryPowerCount: batteryPowerValues.count,
            thermalPressureCount: min(history.sampleCount, boundedThermalLimit),
            retainedSampleCount: history.sampleCount
        )
        temperatureRangeText = Self.unsignedRangeText(temperatureValues, unit: "°C", decimals: 1)
        temperatureChangeText = Self.changeText(temperatureValues, unit: "°C", decimals: 1)
        fanRPMRangeText = Self.unsignedRangeText(fanRPMValues, unit: "RPM", decimals: 0)
        fanRPMChangeText = Self.changeText(fanRPMValues, unit: "RPM", decimals: 0)
        batteryPowerRangeText = Self.signedWattRangeText(batteryPowerValues)
        batteryPowerChangeText = Self.changeText(batteryPowerValues, unit: "W", decimals: 1)
        thermalPressureSamples = history.recentSamples(limit: boundedThermalLimit).map(\.thermalPressure)
        thermalPressureSummaryText = Self.thermalPressureSummaryText(thermalPressureSamples)
    }

    public static func temperatureText(_ value: Double) -> String {
        String(format: "%.1f °C", value)
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
        if abs(max - min) < 0.0001 {
            return batteryPowerFlowText(min)
        }
        if max <= 0 {
            let lowerDrain = PowerDisplayFormatter.watts(abs(max))
            let upperDrain = PowerDisplayFormatter.watts(abs(min))
            return lowerDrain == upperDrain ? "\(lowerDrain) drain" : "\(lowerDrain)-\(upperDrain) drain"
        }
        if min >= 0 {
            let lowerCharge = PowerDisplayFormatter.watts(min)
            let upperCharge = PowerDisplayFormatter.watts(max)
            return lowerCharge == upperCharge ? "\(lowerCharge) charge" : "\(lowerCharge)-\(upperCharge) charge"
        }
        return "\(batteryPowerFlowText(min)) to \(batteryPowerFlowText(max))"
    }

    public static func sampleWindowText(for samples: [TelemetrySample]) -> String? {
        guard samples.count > 1,
              let first = samples.first?.capturedAt,
              let last = samples.last?.capturedAt
        else { return nil }

        let seconds = Int(last.timeIntervalSince(first).rounded())
        guard seconds > 0 else { return nil }
        if seconds < 60 { return "\(seconds) s" }

        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        if minutes < 60 { return "\(minutes) min" }

        let hours = minutes / 60
        let remainderMinutes = minutes % 60
        if remainderMinutes == 0 { return "\(hours) h" }
        return "\(hours) h \(remainderMinutes) min"
    }

    public static func historyReadinessText(sampleCount: Int) -> String? {
        switch sampleCount {
        case ..<1:
            return "History appears after two successful polls."
        case 1:
            return "History appears after one more successful poll."
        default:
            return nil
        }
    }

    public static func plottedSeriesCountText(
        temperatureCount: Int,
        fanCount: Int,
        batteryPowerCount: Int,
        thermalPressureCount: Int,
        retainedSampleCount: Int
    ) -> String {
        let availableSeries = [
            (label: "temp", count: temperatureCount),
            (label: "fan", count: fanCount),
            (label: "power", count: batteryPowerCount),
            (label: "thermal", count: thermalPressureCount)
        ].filter { $0.count > 0 }

        guard !availableSeries.isEmpty else {
            return retainedSampleCount == 1 ? "1 retained sample" : "\(retainedSampleCount) retained samples"
        }

        let uniqueCounts = Set(availableSeries.map { $0.count })
        if uniqueCounts.count == 1, let count = uniqueCounts.first {
            return count == 1 ? "1 retained sample" : "\(count) plotted samples"
        }

        return availableSeries
            .map { "\($0.count) \($0.label)" }
            .joined(separator: " · ") + " points"
    }

    public static func changeText(_ values: [Double], unit: String, decimals: Int) -> String? {
        guard let first = values.first, let last = values.last, values.count > 1 else { return nil }
        let delta = last - first
        let epsilon = decimals == 0 ? 0.5 : 0.05
        guard abs(delta) >= epsilon else {
            let observedRange = (values.max() ?? first) - (values.min() ?? first)
            return observedRange >= epsilon ? "returned to start" : "steady"
        }
        let sign = delta > 0 ? "+" : "-"
        let formatted = formatUnsigned(abs(delta), unit: unit, decimals: decimals)
        return "\(sign)\(formatted)"
    }

    private static func formatUnsigned(_ value: Double, unit: String, decimals: Int) -> String {
        if decimals == 0 {
            return "\(Int(value.rounded())) \(unit)"
        }
        return String(format: "%.1f %@", value, unit)
    }

    private static func batteryPowerFlowText(_ value: Double) -> String {
        let formatted = PowerDisplayFormatter.watts(abs(value))
        if value < 0 { return "\(formatted) drain" }
        if value > 0 { return "\(formatted) charge" }
        return formatted
    }

    private static func temperatureLabel(for sample: TelemetrySample?) -> String {
        guard let sample, sample.selectedTemperatureCelsius != nil else { return "Latest temp" }
        if let role = sample.temperatureRole {
            guard let name = sample.selectedTemperatureName, !name.isEmpty else {
                return role.displayName
            }
            return "\(role.displayName) · \(name)"
        }
        if sample.temperatureWasUserSelected { return "Selected temp" }
        guard let name = sample.selectedTemperatureName else { return "Highest temp" }
        return isCPUTemperatureName(name) ? "CPU temp" : "Highest temp"
    }

    private static func isCPUTemperatureName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("cpu")
            || lower.contains("processor")
            || lower.contains("package")
            || lower.contains("die")
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

    private static func fanRPMValues(from samples: [TelemetrySample], usesAverageFanRPM: Bool) -> [Double] {
        if usesAverageFanRPM {
            return samples.compactMap(\.averageFanRPM)
        }
        return samples.compactMap { $0.firstFanRPM.map(Double.init) }
    }

    private static func sampleFanRPM(_ sample: TelemetrySample) -> Double? {
        sample.averageFanRPM ?? sample.firstFanRPM.map(Double.init)
    }

    private static func thermalPressureSummaryText(_ pressures: [ThermalPressure]) -> String {
        guard !pressures.isEmpty else { return "--" }
        let peak = pressures.max { severity($0) < severity($1) } ?? .unknown
        if pressures.allSatisfy({ $0 == peak }) {
            return "Stable \(peak.displayName)"
        }
        return "Peak \(peak.displayName)"
    }

    private static func severity(_ pressure: ThermalPressure) -> Int {
        switch pressure {
        case .unknown: 0
        case .nominal: 1
        case .fair: 2
        case .serious: 3
        case .critical: 4
        }
    }
}
