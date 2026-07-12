import ViftyCore

struct FanCurveChartValue: Equatable {
    let temperature: Double
    let rpm: Double
}

enum FanCurveSeriesKind: Equatable {
    case base
    case fan(index: Int)
}

struct FanCurveSeriesPresentation: Equatable, Identifiable {
    let id: Int
    let fanID: Int
    let name: String
    let kind: FanCurveSeriesKind
    let points: [FanCurveChartValue]
    let colorIndex: Int
    let matchesBase: Bool
}

struct FanCurveChartPresentation: Equatable {
    let basePoints: [FanCurveChartValue]
    let series: [FanCurveSeriesPresentation]

    static func make(
        basePoints: [FanCurveChartValue],
        fans: [Fan],
        overrides: [FanCurveOverride],
        usePerFanOverrides: Bool
    ) -> FanCurveChartPresentation {
        guard usePerFanOverrides else {
            return FanCurveChartPresentation(
                basePoints: basePoints,
                series: []
            )
        }

        let series = fans.enumerated().map { index, fan in
            let override = overrides.first { $0.fanID == fan.id }
            let points = [
                FanCurveChartValue(temperature: pointTemperature(basePoints, at: 0), rpm: Double(FanCurve.clamp(override?.startRPM ?? Int(pointRPM(basePoints, at: 0).rounded()), fan.minimumRPM, fan.maximumRPM))),
                FanCurveChartValue(temperature: pointTemperature(basePoints, at: 1), rpm: Double(FanCurve.clamp(override?.midRPM ?? Int(pointRPM(basePoints, at: 1).rounded()), fan.minimumRPM, fan.maximumRPM))),
                FanCurveChartValue(temperature: pointTemperature(basePoints, at: 2), rpm: Double(FanCurve.clamp(override?.maxRPM ?? Int(pointRPM(basePoints, at: 2).rounded()), fan.minimumRPM, fan.maximumRPM)))
            ]
            return FanCurveSeriesPresentation(
                id: fan.id,
                fanID: fan.id,
                name: fan.name,
                kind: .fan(index: index),
                points: points,
                colorIndex: index,
                matchesBase: points == basePoints
            )
        }

        return FanCurveChartPresentation(
            basePoints: basePoints,
            series: series
        )
    }

    static func renderOrder(seriesCount: Int) -> [FanCurveSeriesKind] {
        [.base] + (0..<seriesCount).map { .fan(index: $0) }
    }

    private static func pointTemperature(_ points: [FanCurveChartValue], at index: Int) -> Double {
        points.indices.contains(index) ? points[index].temperature : 0
    }

    private static func pointRPM(_ points: [FanCurveChartValue], at index: Int) -> Double {
        points.indices.contains(index) ? points[index].rpm : 0
    }
}
