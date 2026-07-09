import CoreGraphics
import XCTest
@testable import Vifty

final class FanCurveChartGeometryTests: XCTestCase {
    func testPositionMapsLowTemperatureAndLowRPMToPlotBottomLeft() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...4296
        )

        let point = geometry.position(
            for: FanCurveChartValue(temperature: 35, rpm: 1499),
            in: CGSize(width: 700, height: 272)
        )

        XCTAssertEqual(point.x, 44, accuracy: 0.1)
        XCTAssertEqual(point.y, 232, accuracy: 0.1)
    }

    func testValueFromDragClampsInsidePlotRange() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...4296
        )

        let value = geometry.value(
            from: CGPoint(x: -100, y: 999),
            in: CGSize(width: 700, height: 272)
        )

        XCTAssertEqual(value.temperature, 35, accuracy: 0.1)
        XCTAssertEqual(value.rpm, 1499, accuracy: 0.1)
    }

    func testTargetRPMInterpolatesThroughCurvePoints() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...4296
        )
        let points = [
            FanCurveChartValue(temperature: 55, rpm: 1499),
            FanCurveChartValue(temperature: 70, rpm: 3500),
            FanCurveChartValue(temperature: 85, rpm: 4296)
        ]

        XCTAssertEqual(geometry.targetRPM(at: 55, points: points), 1499)
        XCTAssertEqual(geometry.targetRPM(at: 70, points: points), 3500)
        XCTAssertEqual(geometry.targetRPM(at: 85, points: points), 4296)
        XCTAssertEqual(geometry.targetRPM(at: 62.5, points: points), 2500)
    }
}
