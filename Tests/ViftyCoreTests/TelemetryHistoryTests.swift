import XCTest
@testable import ViftyCore

final class TelemetryHistoryTests: XCTestCase {
    func testHistoryKeepsNewestSamplesWithinLimit() {
        var history = TelemetryHistory(limit: 3)
        for index in 0..<5 {
            history.append(sample(index: index))
        }

        XCTAssertEqual(history.samples.count, 3)
        XCTAssertEqual(history.samples.first?.firstFanRPM, 2002)
        XCTAssertEqual(history.samples.last?.firstFanRPM, 2004)
    }

    func testInitialLimitClampsToOneAndKeepsNewestSample() {
        var history = TelemetryHistory(limit: 0)

        history.append(sample(index: 0))
        history.append(sample(index: 1))

        XCTAssertEqual(history.limit, 1)
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.first?.firstFanRPM, 2001)
    }

    func testMutatedLimitClampsTrimsAndAllowsFutureAppends() {
        var history = TelemetryHistory(limit: 3)
        for index in 0..<3 {
            history.append(sample(index: index))
        }

        history.limit = 0

        XCTAssertEqual(history.limit, 1)
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.first?.firstFanRPM, 2002)

        history.limit = -4
        history.append(sample(index: 3))

        XCTAssertEqual(history.limit, 1)
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.first?.firstFanRPM, 2003)
    }

    private func sample(index: Int) -> TelemetrySample {
        TelemetrySample(
            capturedAt: Date(timeIntervalSince1970: Double(index)),
            highestTemperatureCelsius: Double(60 + index),
            firstFanRPM: 2000 + index,
            batteryPowerWatts: -10,
            thermalPressure: .nominal
        )
    }
}
