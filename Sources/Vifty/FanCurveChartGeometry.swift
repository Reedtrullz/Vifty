import CoreGraphics
import Foundation
import ViftyCore

struct FanCurveChartValue: Equatable {
    let temperature: Double
    let rpm: Double
}

struct FanCurveChartGeometry: Equatable {
    let temperatureRange: ClosedRange<Double>
    let rpmRange: ClosedRange<Double>

    private let leftInset: CGFloat = 44
    private let rightInset: CGFloat = 18
    private let topInset: CGFloat = 20
    private let bottomInset: CGFloat = 40

    func plotRect(in size: CGSize) -> CGRect {
        CGRect(
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
        return FanCurveChartValue(
            temperature: temperatureRange.lowerBound + xRatio * (temperatureRange.upperBound - temperatureRange.lowerBound),
            rpm: rpmRange.lowerBound + yRatio * (rpmRange.upperBound - rpmRange.lowerBound)
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
}
