import XCTest
@testable import Vifty

final class FanControlDraftTests: XCTestCase {
    func testEqualDraftsAreNotDirty() {
        let curve = FanCurveDraft(
            startTemperature: 35,
            startRPM: 1500,
            rampTemperature: 70,
            rampRPM: 3000,
            highTemperature: 85,
            highRPM: 4296
        )
        let draft = FanControlDraft(
            mode: .curve,
            manualRunLimit: .minutes(30),
            fixedRPM: 2800,
            fixedFanTargets: [],
            usePerFanFixedRPM: false,
            curve: curve,
            selectedSensorID: "cpu-efficiency-1",
            usePerFanOverrides: false,
            fanOverrides: []
        )

        XCTAssertFalse(draft.isDirty(comparedTo: draft))
    }

    func testCurveEditMakesDraftDirtyWithoutChangingAppliedDraft() {
        let applied = FanControlDraft(
            mode: .curve,
            manualRunLimit: .minutes(30),
            fixedRPM: 2800,
            fixedFanTargets: [],
            usePerFanFixedRPM: false,
            curve: FanCurveDraft(startTemperature: 35, startRPM: 1500, rampTemperature: 70, rampRPM: 3000, highTemperature: 85, highRPM: 4296),
            selectedSensorID: "cpu",
            usePerFanOverrides: false,
            fanOverrides: []
        )
        var pending = applied
        pending.curve.highRPM = 4000

        XCTAssertTrue(pending.isDirty(comparedTo: applied))
        XCTAssertEqual(applied.curve.highRPM, 4296)
    }

    func testManualRunLimitDefaultsToThirtyMinutes() {
        XCTAssertEqual(ManualRunLimit.defaultForManualControl, .minutes(30))
    }

    func testApplyStatesRemainDistinct() {
        XCTAssertNotEqual(FanControlApplyState.applied, .pending)
        XCTAssertNotEqual(FanControlApplyState.applying, .blocked(reason: "Helper unavailable"))
        XCTAssertNotEqual(FanControlApplyState.failed(message: "Write failed"), .applied)
    }
}
