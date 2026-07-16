import XCTest
@testable import Vifty

final class CurvePointAdjustmentTests: XCTestCase {
    func testTemperatureAdjustsByOneDegreeAndClamps() {
        XCTAssertEqual(
            CurvePointAdjustment.temperature(61, direction: .increment, range: 35...105),
            62
        )
        XCTAssertEqual(
            CurvePointAdjustment.temperature(35, direction: .decrement, range: 35...105),
            35
        )
        XCTAssertEqual(
            CurvePointAdjustment.temperature(105, direction: .increment, range: 35...105),
            105
        )
    }

    func testRPMAdjustsByFiftyAndUsesFanCurveClamp() {
        XCTAssertEqual(
            CurvePointAdjustment.rpm(2_000, direction: .increment, range: 1_500...4_500),
            2_050
        )
        XCTAssertEqual(
            CurvePointAdjustment.rpm(1_500, direction: .decrement, range: 1_500...4_500),
            1_500
        )
        XCTAssertEqual(
            CurvePointAdjustment.rpm(4_490, direction: .increment, range: 1_500...4_500),
            4_500
        )
    }
}
