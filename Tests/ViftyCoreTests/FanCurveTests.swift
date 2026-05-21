import XCTest
@testable import ViftyCore

final class FanCurveTests: XCTestCase {
    func testInterpolatesBetweenCurvePoints() {
        let curve = FanCurve(points: [
            CurvePoint(temperatureCelsius: 50, rpm: 2000),
            CurvePoint(temperatureCelsius: 70, rpm: 4000)
        ])

        XCTAssertEqual(curve.targetRPM(for: 60, minimumRPM: 1000, maximumRPM: 6000), 3000)
    }

    func testClampsCurveOutputToFanRange() {
        let curve = FanCurve(points: [
            CurvePoint(temperatureCelsius: 50, rpm: 500),
            CurvePoint(temperatureCelsius: 70, rpm: 8000)
        ])

        XCTAssertEqual(curve.targetRPM(for: 45, minimumRPM: 1200, maximumRPM: 6200), 1200)
        XCTAssertEqual(curve.targetRPM(for: 90, minimumRPM: 1200, maximumRPM: 6200), 6200)
    }

    func testDefaultCurveUsesPlanTemperatures() {
        let curve = FanCurve.defaultCurve(minimumRPM: 1400, maximumRPM: 6000)

        XCTAssertEqual(curve.points.map(\.temperatureCelsius), [55, 70, 85])
        XCTAssertEqual(curve.targetRPM(for: 55, minimumRPM: 1400, maximumRPM: 6000), 1400)
        XCTAssertEqual(curve.targetRPM(for: 85, minimumRPM: 1400, maximumRPM: 6000), 6000)
    }

    func testDecodesNativeEndianSMCFloat() {
        let rpm = Float(2432.5)
        let bytes = withUnsafeBytes(of: rpm) { Array($0) }
        let value = SMCValue(key: "F0Ac", dataType: "flt ", bytes: bytes)

        XCTAssertEqual(try XCTUnwrap(SMCDecoding.decodeFloat(value)), 2432.5, accuracy: 0.01)
    }

    func testEncodesNativeEndianSMCRPMFloat() {
        let bytes = SMCDecoding.encodeRPM(2500, dataType: "flt ", size: 4)
        let decoded = bytes.withUnsafeBytes { rawBuffer in
            rawBuffer.loadUnaligned(as: Float.self)
        }

        XCTAssertEqual(decoded, 2500, accuracy: 0.01)
    }
}
