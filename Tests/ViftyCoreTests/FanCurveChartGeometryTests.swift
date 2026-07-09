import CoreGraphics
import XCTest
@testable import Vifty

final class FanCurveChartGeometryTests: XCTestCase {
    func testPlotRectUsesWideInsetsAtDesktopWidth() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...4296
        )

        let rect = geometry.plotRect(
            in: CGSize(width: 700, height: 272)
        )

        XCTAssertEqual(rect.minX, 56, accuracy: 0.1)
        XCTAssertEqual(rect.minY, 18, accuracy: 0.1)
        XCTAssertEqual(rect.width, 632, accuracy: 0.1)
        XCTAssertEqual(rect.height, 224, accuracy: 0.1)
    }

    func testPlotRectUsesCompactInsetsBelowWidthThreshold() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...4296
        )

        let rect = geometry.plotRect(
            in: CGSize(width: 400, height: 272)
        )

        XCTAssertEqual(rect.minX, 48, accuracy: 0.1)
        XCTAssertEqual(rect.minY, 18, accuracy: 0.1)
        XCTAssertEqual(rect.width, 340, accuracy: 0.1)
        XCTAssertEqual(rect.height, 224, accuracy: 0.1)
    }

    func testPositionMapsLowTemperatureAndLowRPMToPlotBottomLeft() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...4296
        )

        let point = geometry.position(
            for: FanCurveChartValue(temperature: 35, rpm: 1499),
            in: CGSize(width: 700, height: 272)
        )

        XCTAssertEqual(point.x, 56, accuracy: 0.1)
        XCTAssertEqual(point.y, 242, accuracy: 0.1)
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
        XCTAssertEqual(value.rpm, 1500, accuracy: 0.1)
    }

    func testValueFromDragRoundsToWholeDegreesAndFiftyRPM() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...4296
        )

        let value = geometry.value(
            from: CGPoint(x: 191.4286, y: 121.8012),
            in: CGSize(width: 700, height: 272)
        )

        XCTAssertEqual(value.temperature, 50, accuracy: 0.1)
        XCTAssertEqual(value.rpm, 3000, accuracy: 0.1)
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
