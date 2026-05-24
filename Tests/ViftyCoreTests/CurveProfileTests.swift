import XCTest
@testable import ViftyCore

final class CurveProfileTests: XCTestCase {
    func testToFanCurveProducesThreeOrderedPoints() {
        let profile = CurveProfile(
            name: "Test",
            sensorID: "Tp09",
            startTemp: 55, startRPM: 1400,
            midTemp: 70,   midRPM: 3500,
            maxTemp: 85,   maxRPM: 6000
        )
        let curve = profile.toFanCurve()

        XCTAssertEqual(curve.sensorID, "Tp09")
        XCTAssertEqual(curve.points.count, 3)
        XCTAssertEqual(curve.points[0].temperatureCelsius, 55)
        XCTAssertEqual(curve.points[0].rpm, 1400)
        XCTAssertEqual(curve.points[1].temperatureCelsius, 70)
        XCTAssertEqual(curve.points[1].rpm, 3500)
        XCTAssertEqual(curve.points[2].temperatureCelsius, 85)
        XCTAssertEqual(curve.points[2].rpm, 6000)
    }
}
