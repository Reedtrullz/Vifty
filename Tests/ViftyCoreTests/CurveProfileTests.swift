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

    func testSaveCurrentProfileSortsTemperatures() {
        // Profile with deliberately wrong temp order should still produce
        // a correctly-ordered curve where start < mid < max.
        let profile = CurveProfile(
            name: "Reversed",
            sensorID: nil,
            startTemp: 90, startRPM: 6000,  // highest temp, highest RPM
            midTemp: 50,   midRPM: 3000,
            maxTemp: 30,   maxRPM: 1200   // lowest temp, lowest RPM
        )
        let curve = profile.toFanCurve()

        // FanCurve sorts by temperature, so points[0] should be the lowest temp
        XCTAssertEqual(curve.points[0].temperatureCelsius, 30)
        XCTAssertEqual(curve.points[0].rpm, 1200)
        XCTAssertEqual(curve.points[1].temperatureCelsius, 50)
        XCTAssertEqual(curve.points[1].rpm, 3000)
        XCTAssertEqual(curve.points[2].temperatureCelsius, 90)
        XCTAssertEqual(curve.points[2].rpm, 6000)
    }

    func testInitSortsTemperaturesAscending() {
        // Creating a profile with out-of-order temps should store them sorted.
        let profile = CurveProfile(
            name: "Unsorted",
            startTemp: 85, startRPM: 6000,
            midTemp: 55,   midRPM: 3000,
            maxTemp: 70,   maxRPM: 4500
        )
        // Stored values should now be ascending by temperature.
        XCTAssertTrue(profile.startTemp < profile.midTemp)
        XCTAssertTrue(profile.midTemp < profile.maxTemp)
        // RPMs should follow the temps they were paired with.
        XCTAssertEqual(profile.startTemp, 55)
        XCTAssertEqual(profile.startRPM, 3000)
        XCTAssertEqual(profile.midTemp, 70)
        XCTAssertEqual(profile.midRPM, 4500)
        XCTAssertEqual(profile.maxTemp, 85)
        XCTAssertEqual(profile.maxRPM, 6000)
    }
}
