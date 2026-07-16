import CoreGraphics
import XCTest
import ViftyCore
@testable import Vifty

final class FanCurveChartGeometryTests: XCTestCase {
    func testPortableEditingEnvelopeDoesNotCollapseToCurrentHardwareRange() {
        let fans = [
            Fan(id: 0, name: "Left", currentRPM: 1_500, minimumRPM: 1_499, maximumRPM: 4_296, controllable: true),
            Fan(id: 1, name: "Right", currentRPM: 1_500, minimumRPM: 1_499, maximumRPM: 4_744, controllable: true)
        ]

        let range = CurveRPMEditingEnvelope.resolve(
            fans: fans,
            selectedProfile: nil
        )

        XCTAssertEqual(range, 1_000...7_000)
    }

    func testPortableEditingEnvelopeAlreadyContainsKnownSixThousandEightHundredRPMHardware() {
        let fans = [
            Fan(id: 0, name: "Left", currentRPM: 1_400, minimumRPM: 1_400, maximumRPM: 6_800, controllable: true)
        ]

        XCTAssertEqual(
            CurveRPMEditingEnvelope.resolve(fans: fans, selectedProfile: nil),
            1_000...7_000
        )
    }

    func testPortableEditingEnvelopeExpandsFutureHardwareBoundsToFiftyRPMGrid() {
        let fans = [
            Fan(id: 0, name: "Future", currentRPM: 900, minimumRPM: 875, maximumRPM: 7_201, controllable: true)
        ]

        XCTAssertEqual(
            CurveRPMEditingEnvelope.resolve(fans: fans, selectedProfile: nil),
            850...7_250
        )
    }

    func testPortableEditingEnvelopeAnchorsSelectedLegacyProfileWithoutClamping() {
        let profile = CurveProfile(
            name: "Legacy",
            startTemp: 55,
            startRPM: 975,
            midTemp: 70,
            midRPM: 3_500,
            maxTemp: 85,
            maxRPM: 7_601
        )

        XCTAssertEqual(
            CurveRPMEditingEnvelope.resolve(fans: [], selectedProfile: profile),
            950...7_650
        )
    }

    func testResolvedRPMRangeIncludesEveryFanWhenPerFanSeriesIsShown() {
        let fans = [
            Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
            Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
        ]

        let range = FanCurveChartGeometry.resolvedRPMRange(
            base: 1499...4296,
            fans: fans,
            includeFanRanges: true
        )

        XCTAssertEqual(range.lowerBound, 1499)
        XCTAssertEqual(range.upperBound, 4744)
    }

    func testResolvedRPMRangeKeepsBaseEditingBoundsWhenFanSeriesIsHidden() {
        let fans = [
            Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
            Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
        ]

        let range = FanCurveChartGeometry.resolvedRPMRange(
            base: 1499...4296,
            fans: fans,
            includeFanRanges: false
        )

        XCTAssertEqual(range, 1499...4296)
    }

    func testResolvedRPMRangeIncludesRenderedRequestedValuesBeyondHardwareBounds() {
        let fans = [
            Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
            Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
        ]

        let range = FanCurveChartGeometry.resolvedRPMRange(
            base: 1499...4296,
            fans: fans,
            includeFanRanges: true,
            renderedRPMs: [1499, 3500, 6000]
        )

        XCTAssertEqual(range, 1499...6000)
    }

    func testResolvedRPMRangeIncludesRenderedRequestedValueBelowHardwareBounds() {
        let range = FanCurveChartGeometry.resolvedRPMRange(
            base: 1499...4296,
            fans: [],
            includeFanRanges: false,
            renderedRPMs: [1400, 3500, 6000]
        )

        XCTAssertEqual(range, 1400...6000)
    }

    func testExpandedPlotRangeKeepsHardwareCapAndRequestAtDistinctPositions() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...6000
        )
        let size = CGSize(width: 700, height: 272)

        let hardwareCap = geometry.position(
            for: FanCurveChartValue(temperature: 85, rpm: 4296),
            in: size
        )
        let request = geometry.position(
            for: FanCurveChartValue(temperature: 85, rpm: 6000),
            in: size
        )

        XCTAssertGreaterThan(hardwareCap.y, request.y)
        XCTAssertEqual(request.y, geometry.plotRect(in: size).minY, accuracy: 0.1)
    }

    func testExpandedRequestSurvivesRoundTripThroughLargerFanPlotRange() {
        let requestRange = FanCurveChartGeometry.resolvedRPMRange(
            base: 1499...4296,
            fans: [],
            includeFanRanges: false,
            renderedRPMs: [1499, 3500, 6000]
        )
        let plotRange = FanCurveChartGeometry.resolvedRPMRange(
            base: requestRange,
            fans: [
                Fan(id: 0, name: "Left", currentRPM: 1500, minimumRPM: 1200, maximumRPM: 6200, controllable: true),
                Fan(id: 1, name: "Right", currentRPM: 1500, minimumRPM: 1300, maximumRPM: 6600, controllable: true)
            ],
            includeFanRanges: true,
            renderedRPMs: [1499, 3500, 6000]
        )
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: plotRange
        )
        let size = CGSize(width: 700, height: 272)
        let authored = FanCurveChartValue(temperature: 85, rpm: 6000)

        let roundTripped = geometry.value(
            from: geometry.position(for: authored, in: size),
            in: size
        )

        XCTAssertEqual(requestRange, 1499...6000)
        XCTAssertEqual(plotRange, 1200...6600)
        XCTAssertEqual(roundTripped.temperature, authored.temperature, accuracy: 0.1)
        XCTAssertEqual(roundTripped.rpm, authored.rpm, accuracy: 0.1)
    }

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
