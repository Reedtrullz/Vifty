import XCTest
@testable import ViftyCore

final class FanCurveTargetResolverTests: XCTestCase {
    func testDivergentFanOverrideProducesResolvedTarget() {
        let fan = Self.fan(id: 1, maximumRPM: 4_500)
        let target = FanCurveTargetResolver.targetRPM(
            baseCurve: Self.baseCurve,
            fan: fan,
            temperature: 60,
            overrides: [
                FanCurveOverride(fanID: fan.id, startRPM: 2_200, midRPM: 4_200, maxRPM: 4_500)
            ]
        )

        XCTAssertEqual(target, 4_200)
    }

    func testMissingOrDisabledOverrideUsesBaseCurve() {
        let fan = Self.fan(id: 0, maximumRPM: 6_000)
        let unrelatedOverride = FanCurveOverride(
            fanID: 1,
            startRPM: 2_200,
            midRPM: 4_200,
            maxRPM: 4_500
        )

        XCTAssertEqual(
            FanCurveTargetResolver.targetRPM(
                baseCurve: Self.baseCurve,
                fan: fan,
                temperature: 60,
                overrides: [unrelatedOverride]
            ),
            4_000
        )
        XCTAssertEqual(
            FanCurveTargetResolver.targetRPM(
                baseCurve: Self.baseCurve,
                fan: fan,
                temperature: 60,
                overrides: []
            ),
            4_000
        )
    }

    func testDuplicateOverridesUseLastMatchingOverride() {
        let fan = Self.fan(id: 1, maximumRPM: 4_500)

        let target = FanCurveTargetResolver.targetRPM(
            baseCurve: Self.baseCurve,
            fan: fan,
            temperature: 60,
            overrides: [
                FanCurveOverride(fanID: fan.id, startRPM: 2_200, midRPM: 4_200, maxRPM: 4_500),
                FanCurveOverride(fanID: fan.id, startRPM: 2_300, midRPM: 4_300, maxRPM: 4_500)
            ]
        )

        XCTAssertEqual(target, 4_300)
    }

    func testMalformedBaseCurveFallsBackToBaseTarget() {
        let fan = Self.fan(id: 1, maximumRPM: 4_500)
        let malformedCurve = FanCurve(points: [
            CurvePoint(temperatureCelsius: 60, rpm: 4_000)
        ])

        let target = FanCurveTargetResolver.targetRPM(
            baseCurve: malformedCurve,
            fan: fan,
            temperature: 60,
            overrides: [
                FanCurveOverride(fanID: fan.id, startRPM: 2_200, midRPM: 4_200, maxRPM: 4_500)
            ]
        )

        XCTAssertEqual(target, 4_000)
    }

    func testResolvedTargetUsesFanCurveClamp() {
        let fan = Self.fan(id: 1, maximumRPM: 4_500)

        let target = FanCurveTargetResolver.targetRPM(
            baseCurve: Self.baseCurve,
            fan: fan,
            temperature: 85,
            overrides: [
                FanCurveOverride(fanID: fan.id, startRPM: 500, midRPM: 8_000, maxRPM: 9_000)
            ]
        )

        XCTAssertEqual(target, 4_500)
    }

    private static let baseCurve = FanCurve(points: [
        CurvePoint(temperatureCelsius: 40, rpm: 2_000),
        CurvePoint(temperatureCelsius: 60, rpm: 4_000),
        CurvePoint(temperatureCelsius: 85, rpm: 5_500)
    ])

    private static func fan(id: Int, maximumRPM: Int) -> Fan {
        Fan(
            id: id,
            name: id == 0 ? "Left" : "Right",
            currentRPM: 1_500,
            minimumRPM: 1_500,
            maximumRPM: maximumRPM,
            controllable: true
        )
    }
}
