public enum FanCurveTargetResolver {
    public static func effectiveCurve(
        baseCurve: FanCurve,
        fanID: Int,
        overrides: [FanCurveOverride]
    ) -> FanCurve {
        guard let override = overrides.last(where: { $0.fanID == fanID }) else {
            return baseCurve
        }

        let sortedPoints = baseCurve.points.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
        guard sortedPoints.count >= 3,
              let first = sortedPoints.first,
              let last = sortedPoints.last else {
            return baseCurve
        }

        let middle = sortedPoints[sortedPoints.count / 2]
        return FanCurve(sensorID: baseCurve.sensorID, points: [
            CurvePoint(temperatureCelsius: first.temperatureCelsius, rpm: override.startRPM),
            CurvePoint(temperatureCelsius: middle.temperatureCelsius, rpm: override.midRPM),
            CurvePoint(temperatureCelsius: last.temperatureCelsius, rpm: override.maxRPM)
        ])
    }

    public static func targetRPM(
        baseCurve: FanCurve,
        fan: Fan,
        temperature: Double,
        overrides: [FanCurveOverride]
    ) -> Int {
        effectiveCurve(
            baseCurve: baseCurve,
            fanID: fan.id,
            overrides: overrides
        ).targetRPM(
            for: temperature,
            minimumRPM: fan.minimumRPM,
            maximumRPM: fan.maximumRPM
        )
    }
}
