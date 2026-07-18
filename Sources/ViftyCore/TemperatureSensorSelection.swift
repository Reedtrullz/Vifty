import Foundation

public enum TemperatureSensorRole: String, Codable, Equatable, Sendable {
    case curveSensor
    case automaticCPU
    case highestFallback

    public var displayName: String {
        switch self {
        case .curveSensor: "Curve sensor"
        case .automaticCPU: "Automatic CPU"
        case .highestFallback: "Highest fallback"
        }
    }
}

public struct TemperatureSensorSelection: Equatable, Sendable {
    public var curveMetric: TemperatureSensor?
    public var curveMetricRole: TemperatureSensorRole?
    public var highestSafetyMetric: TemperatureSensor?

    public init(
        curveMetric: TemperatureSensor?,
        curveMetricRole: TemperatureSensorRole?,
        highestSafetyMetric: TemperatureSensor?
    ) {
        self.curveMetric = curveMetric
        self.curveMetricRole = curveMetricRole
        self.highestSafetyMetric = highestSafetyMetric
    }

    public static func resolve(
        sensors: [TemperatureSensor],
        selectedSensorID: String?
    ) -> TemperatureSensorSelection {
        let highest = sensors.max { $0.celsius < $1.celsius }
        if let selectedSensorID,
           let selected = sensors.first(where: { $0.id == selectedSensorID }) {
            return TemperatureSensorSelection(
                curveMetric: selected,
                curveMetricRole: .curveSensor,
                highestSafetyMetric: highest
            )
        }

        if let automaticCPU = sensors.first(where: { isCPUSensorName($0.name) }) {
            return TemperatureSensorSelection(
                curveMetric: automaticCPU,
                curveMetricRole: .automaticCPU,
                highestSafetyMetric: highest
            )
        }

        return TemperatureSensorSelection(
            curveMetric: highest,
            curveMetricRole: highest == nil ? nil : .highestFallback,
            highestSafetyMetric: highest
        )
    }

    public var curveMetricLabel: String {
        guard let role = curveMetricRole else { return "Curve temperature" }
        guard let sensorName = curveMetric?.name, !sensorName.isEmpty else {
            return role.displayName
        }
        return "\(role.displayName) · \(sensorName)"
    }

    private static func isCPUSensorName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("cpu")
            || lower.contains("processor")
            || lower.contains("package")
            || lower.contains("die")
    }
}
