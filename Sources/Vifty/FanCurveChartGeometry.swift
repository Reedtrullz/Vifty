import CoreGraphics
import Foundation
import ViftyCore

enum CurveRPMEditingEnvelope {
    static let portableRange: ClosedRange<Double> = 1_000...7_000
    static let step: Double = 50

    static func resolve(
        fans: [Fan],
        selectedProfile: CurveProfile?
    ) -> ClosedRange<Double> {
        var anchors = [portableRange.lowerBound, portableRange.upperBound]

        for fan in fans where fan.controllable {
            anchors.append(Double(fan.minimumRPM))
            anchors.append(Double(fan.maximumRPM))
        }

        if let selectedProfile {
            anchors.append(contentsOf: [
                Double(selectedProfile.startRPM),
                Double(selectedProfile.midRPM),
                Double(selectedProfile.maxRPM)
            ])
        }

        let minimum = anchors.min() ?? portableRange.lowerBound
        let maximum = anchors.max() ?? portableRange.upperBound
        let lower = floor(minimum / step) * step
        let upper = ceil(maximum / step) * step
        return lower...max(upper, lower + step)
    }
}

struct FanCurveChartGeometry: Equatable {
    let temperatureRange: ClosedRange<Double>
    let rpmRange: ClosedRange<Double>

    static func resolvedRPMRange(
        base: ClosedRange<Double>,
        fans: [Fan],
        includeFanRanges: Bool,
        renderedRPMs: [Double] = []
    ) -> ClosedRange<Double> {
        var lower = base.lowerBound
        var upper = max(base.upperBound, base.lowerBound + 100)

        for rpm in renderedRPMs where rpm.isFinite {
            lower = min(lower, rpm)
            upper = max(upper, rpm)
        }

        if includeFanRanges {
            lower = min(lower, fans.map { Double($0.minimumRPM) }.min() ?? lower)
            upper = max(upper, fans.map { Double($0.maximumRPM) }.max() ?? upper)
        }

        return lower...max(upper, lower + 100)
    }

    func plotRect(in size: CGSize) -> CGRect {
        let leftInset: CGFloat = size.width < 420 ? 48 : 56
        let topInset: CGFloat = 18
        let rightInset: CGFloat = 12
        let bottomInset: CGFloat = 30
        return CGRect(
            x: leftInset,
            y: topInset,
            width: max(1, size.width - leftInset - rightInset),
            height: max(1, size.height - topInset - bottomInset)
        )
    }

    func position(for value: FanCurveChartValue, in size: CGSize) -> CGPoint {
        let rect = plotRect(in: size)
        let clampedTemperature = min(max(value.temperature, temperatureRange.lowerBound), temperatureRange.upperBound)
        let clampedRPM = min(max(value.rpm, rpmRange.lowerBound), rpmRange.upperBound)
        let xRatio = (clampedTemperature - temperatureRange.lowerBound) / (temperatureRange.upperBound - temperatureRange.lowerBound)
        let yRatio = (clampedRPM - rpmRange.lowerBound) / (rpmRange.upperBound - rpmRange.lowerBound)
        return CGPoint(
            x: rect.minX + rect.width * CGFloat(xRatio),
            y: rect.maxY - rect.height * CGFloat(yRatio)
        )
    }

    func value(from location: CGPoint, in size: CGSize) -> FanCurveChartValue {
        let rect = plotRect(in: size)
        let x = min(max(location.x, rect.minX), rect.maxX)
        let y = min(max(location.y, rect.minY), rect.maxY)
        let xRatio = Double((x - rect.minX) / rect.width)
        let yRatio = Double((rect.maxY - y) / rect.height)
        let temperature = temperatureRange.lowerBound + xRatio * (temperatureRange.upperBound - temperatureRange.lowerBound)
        let rpm = rpmRange.lowerBound + yRatio * (rpmRange.upperBound - rpmRange.lowerBound)
        return FanCurveChartValue(
            temperature: quantizedTemperature(temperature),
            rpm: quantizedRPM(rpm)
        )
    }

    func targetRPM(at temperature: Double, points: [FanCurveChartValue]) -> Int {
        let fanCurvePoints = points.map { value in
            CurvePoint(
                temperatureCelsius: value.temperature,
                rpm: Int(value.rpm.rounded())
            )
        }
        let curve = FanCurve(sensorID: "chart-preview", points: fanCurvePoints)
        return curve.targetRPM(
            for: temperature,
            minimumRPM: Int(rpmRange.lowerBound.rounded()),
            maximumRPM: Int(rpmRange.upperBound.rounded())
        )
    }

    private func quantizedTemperature(_ temperature: Double) -> Double {
        min(max(temperature.rounded(), temperatureRange.lowerBound), temperatureRange.upperBound)
    }

    private func quantizedRPM(_ rpm: Double) -> Double {
        min(max((rpm / 50).rounded() * 50, rpmRange.lowerBound), rpmRange.upperBound)
    }
}
