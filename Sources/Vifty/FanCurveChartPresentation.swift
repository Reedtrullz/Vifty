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

struct FanCurveEffectiveSummaryPresentation: Equatable, Identifiable {
    let fanID: Int
    let fanName: String
    let start: FanCurveChartValue
    let ramp: FanCurveChartValue
    let high: FanCurveChartValue

    var id: Int { fanID }
    var accessibilityLabel: String { "\(fanName) effective curve" }
    var accessibilityValue: String {
        [
            pointText("Start", start),
            pointText("Ramp", ramp),
            pointText("High", high)
        ].joined(separator: "; ")
    }

    private func pointText(_ label: String, _ point: FanCurveChartValue) -> String {
        "\(label) \(Int(point.temperature.rounded())) °C, \(Int(point.rpm.rounded())) RPM"
    }
}

struct FanCurveChartPresentation: Equatable {
    let basePoints: [FanCurveChartValue]
    let series: [FanCurveSeriesPresentation]
    let usesPerFanOverrides: Bool

    var requestedLegendLabel: String { "Requested" }
    var differingSeries: [FanCurveSeriesPresentation] {
        series.filter { !$0.matchesBase }
    }
    var effectiveSummaries: [FanCurveEffectiveSummaryPresentation] {
        series.compactMap { series in
            guard series.points.count == 3 else { return nil }
            return FanCurveEffectiveSummaryPresentation(
                fanID: series.fanID,
                fanName: series.name,
                start: series.points[0],
                ramp: series.points[1],
                high: series.points[2]
            )
        }
    }

    var statusText: String? {
        let hasEffectiveDifference = !differingSeries.isEmpty
        if usesPerFanOverrides {
            return hasEffectiveDifference
                ? "Separate fan curves are on. Dashed lines show effective curves that differ from requested."
                : "Separate fan curves are on. All effective curves match the requested curve."
        }
        return hasEffectiveDifference
            ? "Fan limits change the requested curve. Dashed lines show effective curves that differ from requested."
            : nil
    }

    func legendLabel(for series: FanCurveSeriesPresentation) -> String {
        series.matchesBase
            ? "\(series.name) · Matches requested"
            : "\(series.name) · Effective"
    }

    static func make(
        basePoints: [FanCurveChartValue],
        fans: [Fan],
        overrides: [FanCurveOverride],
        usePerFanOverrides: Bool
    ) -> FanCurveChartPresentation {
        let baseCurve = FanCurve(points: basePoints.map {
            CurvePoint(
                temperatureCelsius: $0.temperature,
                rpm: Int($0.rpm.rounded())
            )
        })
        let requestedPoints = chartValues(from: baseCurve)
        let effectiveOverrides = usePerFanOverrides ? overrides : []

        let resolvedSeries = fans.enumerated().map { index, fan in
            let effectiveCurve = FanCurveTargetResolver.effectiveCurve(
                baseCurve: baseCurve,
                fanID: fan.id,
                overrides: effectiveOverrides
            )
            let points = chartValues(from: effectiveCurve).map { point in
                FanCurveChartValue(
                    temperature: point.temperature,
                    rpm: Double(FanCurve.clamp(
                        Int(point.rpm.rounded()),
                        fan.minimumRPM,
                        fan.maximumRPM
                    ))
                )
            }
            return FanCurveSeriesPresentation(
                id: fan.id,
                fanID: fan.id,
                name: fan.name,
                kind: .fan(index: index),
                points: points,
                colorIndex: index,
                matchesBase: points == requestedPoints
            )
        }
        let series = usePerFanOverrides || resolvedSeries.contains { !$0.matchesBase }
            ? resolvedSeries
            : []

        return FanCurveChartPresentation(
            basePoints: requestedPoints,
            series: series,
            usesPerFanOverrides: usePerFanOverrides
        )
    }

    static func renderOrder(seriesCount: Int) -> [FanCurveSeriesKind] {
        [.base] + (0..<seriesCount).map { .fan(index: $0) }
    }

    private static func chartValues(from curve: FanCurve) -> [FanCurveChartValue] {
        curve.points.map {
            FanCurveChartValue(
                temperature: $0.temperatureCelsius,
                rpm: Double($0.rpm)
            )
        }
    }
}
