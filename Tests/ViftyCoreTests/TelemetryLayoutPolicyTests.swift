import XCTest
@testable import Vifty

final class TelemetryLayoutPolicyTests: XCTestCase {
    func testNarrowTelemetryUsesTwoColumns() {
        XCTAssertEqual(TelemetryLayoutPolicy.metricColumnCount(for: 420), 2)
        XCTAssertEqual(TelemetryLayoutPolicy.metricColumnCount(for: 519), 2)
    }

    func testRegularTelemetryUsesThreeColumns() {
        XCTAssertEqual(TelemetryLayoutPolicy.metricColumnCount(for: 520), 3)
        XCTAssertEqual(TelemetryLayoutPolicy.metricColumnCount(for: 859), 3)
    }

    func testWideTelemetryUsesFourColumns() {
        XCTAssertEqual(TelemetryLayoutPolicy.metricColumnCount(for: 860), 4)
        XCTAssertEqual(TelemetryLayoutPolicy.metricColumnCount(for: 1_600), 4)
    }
}
