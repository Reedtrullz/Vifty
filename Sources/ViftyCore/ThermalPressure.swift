import Foundation

public enum ThermalPressure: String, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    public init(processInfoState: ProcessInfo.ThermalState) {
        switch processInfoState {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        case .unknown: "Unknown"
        }
    }

    public var menuSummary: String? {
        switch self {
        case .nominal, .unknown:
            nil
        case .fair, .serious, .critical:
            "Thermal: \(displayName)"
        }
    }
}

public enum ThermalPressureReader {
    public static func read() -> ThermalPressure {
        ThermalPressure(processInfoState: ProcessInfo.processInfo.thermalState)
    }
}
