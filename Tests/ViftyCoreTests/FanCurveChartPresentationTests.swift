import XCTest
import ViftyCore
@testable import Vifty

final class FanCurveChartPresentationTests: XCTestCase {
    func testPerFanPresentationShowsDivergentRangeAndSeries() {
        let basePoints = basePoints()
        let fans = [
            Fan(id: 0, name: "Left Fan", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
            Fan(id: 1, name: "Right Fan", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
        ]

        let presentation = FanCurveChartPresentation.make(
            basePoints: basePoints,
            fans: fans,
            overrides: [FanCurveOverride(fanID: 1, startRPM: 1499, midRPM: 3500, maxRPM: 4744)],
            usePerFanOverrides: true
        )

        XCTAssertEqual(presentation.series.map(\.kind), [.fan(index: 0), .fan(index: 1)])
        XCTAssertTrue(presentation.series[0].matchesBase)
        XCTAssertFalse(presentation.series[1].matchesBase)
        XCTAssertEqual(presentation.series[1].points.map(\.rpm), [1499, 3500, 4744])
        XCTAssertEqual(FanCurveChartPresentation.renderOrder(seriesCount: presentation.series.count), [.base, .fan(index: 0), .fan(index: 1)])
    }

    func testPerFanPresentationClampsOverridesToEachFanRange() {
        let fan = Fan(id: 1, name: "Right Fan", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)

        let presentation = FanCurveChartPresentation.make(
            basePoints: basePoints(),
            fans: [fan],
            overrides: [FanCurveOverride(fanID: fan.id, startRPM: 1000, midRPM: 3500, maxRPM: 6000)],
            usePerFanOverrides: true
        )

        XCTAssertEqual(presentation.series[0].points.map(\.rpm), [1499, 3500, 4744])
        XCTAssertFalse(presentation.series[0].matchesBase)
    }

    func testPerFanPresentationOmitsFanSeriesWhenDisabled() {
        let presentation = FanCurveChartPresentation.make(
            basePoints: basePoints(),
            fans: [Fan(id: 0, name: "Left Fan", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true)],
            overrides: [],
            usePerFanOverrides: false
        )

        XCTAssertTrue(presentation.series.isEmpty)
        XCTAssertEqual(FanCurveChartPresentation.renderOrder(seriesCount: 2), [.base, .fan(index: 0), .fan(index: 1)])
    }

    private func basePoints() -> [FanCurveChartValue] {
        [
            FanCurveChartValue(temperature: 55, rpm: 1499),
            FanCurveChartValue(temperature: 70, rpm: 3500),
            FanCurveChartValue(temperature: 85, rpm: 4296)
        ]
    }
}
