import Foundation

public enum ViftyError: Error, LocalizedError, Equatable {
    case unsupportedHardware(String)
    case noTemperatureSensors
    case noControllableFans
    case helperRejected(String)
    case smcUnavailable
    case smcOpenFailed(Int32)
    case smcCallFailed(Int32)
    case smcKeyUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedHardware(let reason):
            "Unsupported hardware: \(reason)"
        case .noTemperatureSensors:
            "No temperature sensors are available."
        case .noControllableFans:
            "No controllable fans are available."
        case .helperRejected(let reason):
            "The fan helper rejected the command: \(reason)"
        case .smcUnavailable:
            "AppleSMC is unavailable."
        case .smcOpenFailed(let code):
            "AppleSMC open failed with IOKit code \(code)."
        case .smcCallFailed(let code):
            "AppleSMC call failed with IOKit code \(code)."
        case .smcKeyUnavailable(let key):
            "SMC key \(key) is unavailable."
        }
    }
}

public struct Fan: Identifiable, Equatable, Sendable {
    public let id: Int
    public var name: String
    public var currentRPM: Int
    public var minimumRPM: Int
    public var maximumRPM: Int
    public var controllable: Bool

    public init(id: Int, name: String, currentRPM: Int, minimumRPM: Int, maximumRPM: Int, controllable: Bool) {
        self.id = id
        self.name = name
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.controllable = controllable
    }

    public var percentage: Int {
        guard maximumRPM > minimumRPM else { return 0 }
        let ratio = Double(currentRPM - minimumRPM) / Double(maximumRPM - minimumRPM)
        return max(0, min(100, Int((ratio * 100).rounded())))
    }
}

public struct TemperatureSensor: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var celsius: Double
    public var source: SensorSource

    public init(id: String, name: String, celsius: Double, source: SensorSource) {
        self.id = id
        self.name = name
        self.celsius = celsius
        self.source = source
    }
}

public enum SensorSource: String, Equatable, Sendable {
    case smc = "SMC"
    case hid = "HID"
    case synthetic = "Synthetic"
}

public struct HardwareSnapshot: Equatable, Sendable {
    public var fans: [Fan]
    public var temperatureSensors: [TemperatureSensor]
    public var modelIdentifier: String
    public var isAppleSilicon: Bool
    public var isMacBookPro: Bool
    public var capturedAt: Date

    public init(
        fans: [Fan],
        temperatureSensors: [TemperatureSensor],
        modelIdentifier: String,
        isAppleSilicon: Bool,
        isMacBookPro: Bool,
        capturedAt: Date = Date()
    ) {
        self.fans = fans
        self.temperatureSensors = temperatureSensors
        self.modelIdentifier = modelIdentifier
        self.isAppleSilicon = isAppleSilicon
        self.isMacBookPro = isMacBookPro
        self.capturedAt = capturedAt
    }

    public var highestTemperature: TemperatureSensor? {
        temperatureSensors.max { $0.celsius < $1.celsius }
    }
}

public struct CurvePoint: Equatable, Sendable {
    public var temperatureCelsius: Double
    public var rpm: Int

    public init(temperatureCelsius: Double, rpm: Int) {
        self.temperatureCelsius = temperatureCelsius
        self.rpm = rpm
    }
}

public struct FanCurve: Equatable, Sendable {
    public var sensorID: String?
    public var points: [CurvePoint]

    public init(sensorID: String? = nil, points: [CurvePoint]) {
        self.sensorID = sensorID
        self.points = points.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
    }

    public static func defaultCurve(sensorID: String? = nil, minimumRPM: Int = 1400, maximumRPM: Int = 6000) -> FanCurve {
        FanCurve(sensorID: sensorID, points: [
            CurvePoint(temperatureCelsius: 55, rpm: minimumRPM),
            CurvePoint(temperatureCelsius: 70, rpm: Int(Double(minimumRPM) + Double(maximumRPM - minimumRPM) * 0.45)),
            CurvePoint(temperatureCelsius: 85, rpm: maximumRPM)
        ])
    }

    public func targetRPM(for temperature: Double, minimumRPM: Int, maximumRPM: Int) -> Int {
        let safePoints = points
            .sorted { $0.temperatureCelsius < $1.temperatureCelsius }
            .map { CurvePoint(temperatureCelsius: $0.temperatureCelsius, rpm: Self.clamp($0.rpm, minimumRPM, maximumRPM)) }

        guard let first = safePoints.first else { return minimumRPM }
        guard temperature > first.temperatureCelsius else { return first.rpm }
        guard let last = safePoints.last else { return first.rpm }
        guard temperature < last.temperatureCelsius else { return last.rpm }

        for index in 1..<safePoints.count {
            let previous = safePoints[index - 1]
            let next = safePoints[index]
            guard temperature <= next.temperatureCelsius else { continue }

            let span = next.temperatureCelsius - previous.temperatureCelsius
            guard span > 0 else { return next.rpm }

            let progress = (temperature - previous.temperatureCelsius) / span
            let rpm = Double(previous.rpm) + Double(next.rpm - previous.rpm) * progress
            return Self.clamp(Int(rpm.rounded()), minimumRPM, maximumRPM)
        }

        return Self.clamp(last.rpm, minimumRPM, maximumRPM)
    }

    public static func clamp(_ rpm: Int, _ minimumRPM: Int, _ maximumRPM: Int) -> Int {
        min(max(rpm, minimumRPM), maximumRPM)
    }
}

public struct CurveProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sensorID: String?
    public var startTemp: Double
    public var startRPM: Int
    public var midTemp: Double
    public var midRPM: Int
    public var maxTemp: Double
    public var maxRPM: Int

    public init(
        id: UUID = UUID(),
        name: String,
        sensorID: String? = nil,
        startTemp: Double,
        startRPM: Int,
        midTemp: Double,
        midRPM: Int,
        maxTemp: Double,
        maxRPM: Int
    ) {
        self.id = id
        self.name = name
        self.sensorID = sensorID
        self.startTemp = startTemp
        self.startRPM = startRPM
        self.midTemp = midTemp
        self.midRPM = midRPM
        self.maxTemp = maxTemp
        self.maxRPM = maxRPM
    }

    public func toFanCurve() -> FanCurve {
        FanCurve(sensorID: sensorID, points: [
            CurvePoint(temperatureCelsius: startTemp, rpm: startRPM),
            CurvePoint(temperatureCelsius: midTemp, rpm: midRPM),
            CurvePoint(temperatureCelsius: maxTemp, rpm: maxRPM)
        ])
    }
}

public enum FanMode: Equatable, Sendable {
    case auto
    case fixedRPM(Int)
    case temperatureCurve(FanCurve)
}

public struct FanCommand: Equatable, Sendable {
    public var fanID: Int
    public var mode: FanMode

    public init(fanID: Int, mode: FanMode) {
        self.fanID = fanID
        self.mode = mode
    }
}

public struct ControlState: Equatable, Sendable {
    public var mode: FanMode
    public var selectedSensorID: String?
    public var lastAppliedRPM: [Int: Int]
    public var statusMessage: String
    public var manualControlActive: Bool

    public init(
        mode: FanMode = .auto,
        selectedSensorID: String? = nil,
        lastAppliedRPM: [Int: Int] = [:],
        statusMessage: String = "Auto",
        manualControlActive: Bool = false
    ) {
        self.mode = mode
        self.selectedSensorID = selectedSensorID
        self.lastAppliedRPM = lastAppliedRPM
        self.statusMessage = statusMessage
        self.manualControlActive = manualControlActive
    }
}
