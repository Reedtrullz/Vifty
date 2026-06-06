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
