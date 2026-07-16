import Foundation
import ViftyCore

enum CurvePointAdjustmentDirection: Equatable, Sendable {
    case increment
    case decrement
}

struct CurvePointAdjustment: Equatable, Sendable {
    static let temperatureStep = 1.0
    static let rpmStep = 50

    static func temperature(
        _ current: Double,
        direction: CurvePointAdjustmentDirection,
        range: ClosedRange<Double>
    ) -> Double {
        let delta = direction == .increment ? temperatureStep : -temperatureStep
        return min(max(current + delta, range.lowerBound), range.upperBound)
    }

    static func rpm(
        _ current: Double,
        direction: CurvePointAdjustmentDirection,
        range: ClosedRange<Double>
    ) -> Double {
        let delta = direction == .increment ? rpmStep : -rpmStep
        return Double(FanCurve.clamp(
            Int(current.rounded()) + delta,
            Int(range.lowerBound.rounded()),
            Int(range.upperBound.rounded())
        ))
    }
}
