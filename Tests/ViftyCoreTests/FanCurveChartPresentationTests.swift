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
        XCTAssertNil(presentation.statusText)
        XCTAssertEqual(FanCurveChartPresentation.renderOrder(seriesCount: 2), [.base, .fan(index: 0), .fan(index: 1)])
    }

    func testDisabledOverridesShowsEffectiveFanSeriesWhenHardwareLimitsChangeRequest() {
        let requestedPoints = [
            FanCurveChartValue(temperature: 55, rpm: 1499),
            FanCurveChartValue(temperature: 70, rpm: 3500),
            FanCurveChartValue(temperature: 85, rpm: 6000)
        ]
        let fans = [
            Fan(id: 0, name: "Left Fan", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4296, controllable: true),
            Fan(id: 1, name: "Right Fan", currentRPM: 1500, minimumRPM: 1499, maximumRPM: 4744, controllable: true)
        ]

        let presentation = FanCurveChartPresentation.make(
            basePoints: requestedPoints,
            fans: fans,
            overrides: [],
            usePerFanOverrides: false
        )

        XCTAssertEqual(presentation.basePoints, requestedPoints)
        XCTAssertEqual(presentation.series.map(\.name), ["Left Fan", "Right Fan"])
        XCTAssertEqual(presentation.series[0].points.map(\.rpm), [1499, 3500, 4296])
        XCTAssertEqual(presentation.series[1].points.map(\.rpm), [1499, 3500, 4744])
        XCTAssertTrue(presentation.series.allSatisfy { !$0.matchesBase })
        XCTAssertEqual(
            presentation.statusText,
            "Fan limits change the requested curve. Dashed lines show effective curves that differ from requested."
        )
        XCTAssertEqual(presentation.requestedLegendLabel, "Requested")
        XCTAssertEqual(presentation.legendLabel(for: presentation.series[0]), "Left Fan · Effective")
    }

    func testDisabledOverridesKeepsMatchingFanBesideHardwareLimitedFan() {
        let requestedPoints = [
            FanCurveChartValue(temperature: 55, rpm: 1500),
            FanCurveChartValue(temperature: 70, rpm: 3500),
            FanCurveChartValue(temperature: 85, rpm: 5000)
        ]
        let fans = [
            Fan(id: 0, name: "Left Fan", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 4296, controllable: true),
            Fan(id: 1, name: "Right Fan", currentRPM: 1500, minimumRPM: 1500, maximumRPM: 5200, controllable: true)
        ]

        let presentation = FanCurveChartPresentation.make(
            basePoints: requestedPoints,
            fans: fans,
            overrides: [],
            usePerFanOverrides: false
        )

        XCTAssertEqual(presentation.series.count, 2)
        XCTAssertFalse(presentation.series[0].matchesBase)
        XCTAssertTrue(presentation.series[1].matchesBase)
        XCTAssertEqual(presentation.differingSeries.map(\.name), ["Left Fan"])
        XCTAssertEqual(presentation.legendLabel(for: presentation.series[0]), "Left Fan · Effective")
        XCTAssertEqual(presentation.legendLabel(for: presentation.series[1]), "Right Fan · Matches requested")
    }

    func testDisabledOverridesIgnoresStaleOverrideRecords() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 1500,
            minimumRPM: 1499,
            maximumRPM: 4296,
            controllable: true
        )

        let presentation = FanCurveChartPresentation.make(
            basePoints: basePoints(),
            fans: [fan],
            overrides: [FanCurveOverride(fanID: fan.id, startRPM: 2000, midRPM: 4000, maxRPM: 4200)],
            usePerFanOverrides: false
        )

        XCTAssertTrue(presentation.series.isEmpty)
        XCTAssertNil(presentation.statusText)
    }

    func testPresentationUsesLastDuplicateOverrideLikeCommandResolver() {
        let fan = Fan(
            id: 1,
            name: "Right Fan",
            currentRPM: 1500,
            minimumRPM: 1499,
            maximumRPM: 4744,
            controllable: true
        )

        let presentation = FanCurveChartPresentation.make(
            basePoints: basePoints(),
            fans: [fan],
            overrides: [
                FanCurveOverride(fanID: fan.id, startRPM: 1600, midRPM: 3200, maxRPM: 4300),
                FanCurveOverride(fanID: fan.id, startRPM: 1800, midRPM: 3800, maxRPM: 4600)
            ],
            usePerFanOverrides: true
        )

        XCTAssertEqual(presentation.series[0].points.map(\.rpm), [1800, 3800, 4600])
    }

    func testPresentationSortsTemperaturesLikeCommandResolver() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 1500,
            minimumRPM: 1499,
            maximumRPM: 4296,
            controllable: true
        )
        let outOfOrder = [
            FanCurveChartValue(temperature: 85, rpm: 4200),
            FanCurveChartValue(temperature: 55, rpm: 1600),
            FanCurveChartValue(temperature: 70, rpm: 3300)
        ]
        let override = FanCurveOverride(
            fanID: fan.id,
            startRPM: 1700,
            midRPM: 3600,
            maxRPM: 4500
        )

        let presentation = FanCurveChartPresentation.make(
            basePoints: outOfOrder,
            fans: [fan],
            overrides: [override],
            usePerFanOverrides: true
        )

        XCTAssertEqual(presentation.basePoints.map(\.temperature), [55, 70, 85])
        XCTAssertEqual(presentation.basePoints.map(\.rpm), [1600, 3300, 4200])
        XCTAssertEqual(presentation.series[0].points.map(\.temperature), [55, 70, 85])
        XCTAssertEqual(presentation.series[0].points.map(\.rpm), [1700, 3600, 4296])

        let baseCurve = FanCurve(points: outOfOrder.map {
            CurvePoint(temperatureCelsius: $0.temperature, rpm: Int($0.rpm.rounded()))
        })
        let chartGeometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: Double(fan.minimumRPM)...Double(fan.maximumRPM)
        )
        for temperature in [55.0, 62.0, 70.0, 78.0, 85.0] {
            XCTAssertEqual(
                chartGeometry.targetRPM(at: temperature, points: presentation.series[0].points),
                FanCurveTargetResolver.targetRPM(
                    baseCurve: baseCurve,
                    fan: fan,
                    temperature: temperature,
                    overrides: [override]
                )
            )
        }
    }

    func testEnabledPerFanStatusExplainsMatchingAndDivergentCurves() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 1500,
            minimumRPM: 1499,
            maximumRPM: 4296,
            controllable: true
        )
        let matching = FanCurveChartPresentation.make(
            basePoints: basePoints(),
            fans: [fan],
            overrides: [],
            usePerFanOverrides: true
        )
        XCTAssertEqual(
            matching.statusText,
            "Separate fan curves are on. All effective curves match the requested curve."
        )
        XCTAssertEqual(matching.legendLabel(for: matching.series[0]), "Left Fan · Matches requested")

        let divergent = FanCurveChartPresentation.make(
            basePoints: basePoints(),
            fans: [fan],
            overrides: [FanCurveOverride(fanID: fan.id, startRPM: 1700, midRPM: 3600, maxRPM: 4200)],
            usePerFanOverrides: true
        )
        XCTAssertEqual(
            divergent.statusText,
            "Separate fan curves are on. Dashed lines show effective curves that differ from requested."
        )
    }

    func testEffectiveSummariesExposeExactResolvedPerFanPoints() {
        let fans = [
            Fan(id: 0, name: "Left Fan", currentRPM: 1500, minimumRPM: 1200, maximumRPM: 6200, controllable: true),
            Fan(id: 1, name: "Right Fan", currentRPM: 1500, minimumRPM: 1300, maximumRPM: 6600, controllable: true)
        ]
        let presentation = FanCurveChartPresentation.make(
            basePoints: [
                FanCurveChartValue(temperature: 55, rpm: 1200),
                FanCurveChartValue(temperature: 70, rpm: 3500),
                FanCurveChartValue(temperature: 85, rpm: 6200)
            ],
            fans: fans,
            overrides: [
                FanCurveOverride(fanID: 0, startRPM: 1700, midRPM: 3400, maxRPM: 5700),
                FanCurveOverride(fanID: 1, startRPM: 2100, midRPM: 4200, maxRPM: 6400)
            ],
            usePerFanOverrides: true
        )

        XCTAssertEqual(presentation.effectiveSummaries.map(\.accessibilityLabel), [
            "Left Fan effective curve",
            "Right Fan effective curve"
        ])
        XCTAssertEqual(presentation.effectiveSummaries.map(\.accessibilityValue), [
            "Start 55 °C, 1700 RPM; Ramp 70 °C, 3400 RPM; High 85 °C, 5700 RPM",
            "Start 55 °C, 2100 RPM; Ramp 70 °C, 4200 RPM; High 85 °C, 6400 RPM"
        ])
    }

    func testEffectiveSummariesUseClampedValuesAndRejectNoncanonicalPointCounts() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 1500,
            minimumRPM: 1499,
            maximumRPM: 4296,
            controllable: true
        )
        let clamped = FanCurveChartPresentation.make(
            basePoints: [
                FanCurveChartValue(temperature: 55, rpm: 1400),
                FanCurveChartValue(temperature: 70, rpm: 3500),
                FanCurveChartValue(temperature: 85, rpm: 6000)
            ],
            fans: [fan],
            overrides: [],
            usePerFanOverrides: false
        )
        XCTAssertEqual(
            clamped.effectiveSummaries.first?.accessibilityValue,
            "Start 55 °C, 1499 RPM; Ramp 70 °C, 3500 RPM; High 85 °C, 4296 RPM"
        )

        let malformed = FanCurveChartPresentation.make(
            basePoints: [
                FanCurveChartValue(temperature: 55, rpm: 1800),
                FanCurveChartValue(temperature: 85, rpm: 4200)
            ],
            fans: [fan],
            overrides: [],
            usePerFanOverrides: true
        )
        XCTAssertTrue(malformed.effectiveSummaries.isEmpty)
    }

    func testMalformedShortCurveDoesNotFabricateChartPoints() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 1500,
            minimumRPM: 1499,
            maximumRPM: 4296,
            controllable: true
        )
        let requestedPoints = [
            FanCurveChartValue(temperature: 55, rpm: 1800),
            FanCurveChartValue(temperature: 85, rpm: 4200)
        ]

        let presentation = FanCurveChartPresentation.make(
            basePoints: requestedPoints,
            fans: [fan],
            overrides: [FanCurveOverride(fanID: fan.id, startRPM: 2000, midRPM: 3500, maxRPM: 4296)],
            usePerFanOverrides: true
        )

        XCTAssertEqual(presentation.basePoints, requestedPoints)
        XCTAssertEqual(presentation.series[0].points, requestedPoints)
        XCTAssertFalse(presentation.series[0].points.contains { $0.temperature == 0 || $0.rpm == 0 })
    }

    private func basePoints() -> [FanCurveChartValue] {
        [
            FanCurveChartValue(temperature: 55, rpm: 1499),
            FanCurveChartValue(temperature: 70, rpm: 3500),
            FanCurveChartValue(temperature: 85, rpm: 4296)
        ]
    }
}
