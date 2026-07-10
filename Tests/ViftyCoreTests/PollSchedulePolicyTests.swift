import XCTest
import ViftyCore
@testable import Vifty

final class PollSchedulePolicyTests: XCTestCase {
    func testFullyAutoStateUsesIdleInterval() {
        let policy = PollSchedulePolicy.standard

        XCTAssertEqual(
            policy.interval(selectedMode: .auto, controlMode: .auto, hasAgentLease: false),
            .seconds(10)
        )
    }

    func testAnyManualIntentUsesActiveInterval() {
        let policy = PollSchedulePolicy.standard
        let curve = FanCurve(sensorID: nil, points: [])

        XCTAssertEqual(
            policy.interval(selectedMode: .fixed, controlMode: .auto, hasAgentLease: false),
            .seconds(5)
        )
        XCTAssertEqual(
            policy.interval(selectedMode: .auto, controlMode: .fixedRPM(3200), hasAgentLease: false),
            .seconds(5)
        )
        XCTAssertEqual(
            policy.interval(selectedMode: .auto, controlMode: .temperatureCurve(curve), hasAgentLease: false),
            .seconds(5)
        )
    }

    func testAgentLeaseUsesActiveInterval() {
        XCTAssertEqual(
            PollSchedulePolicy.standard.interval(
                selectedMode: .auto,
                controlMode: .auto,
                hasAgentLease: true
            ),
            .seconds(5)
        )
    }
}
