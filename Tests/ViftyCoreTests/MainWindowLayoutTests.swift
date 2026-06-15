import XCTest
@testable import Vifty

final class MainWindowLayoutTests: XCTestCase {
    func testMinimumSupportedWindowUsesStackedCompactLayout() {
        let layout = MainWindowLayout.resolve(width: 780, height: 480)

        XCTAssertEqual(layout.mode, .stacked)
        XCTAssertTrue(layout.compactTelemetry)
    }

    func testDefaultOperatorWindowUsesSplitRegularLayout() {
        let layout = MainWindowLayout.resolve(width: 1180, height: 820)

        XCTAssertEqual(layout.mode, .split)
        XCTAssertFalse(layout.compactTelemetry)
    }

    func testNarrowWindowStacksBeforePanesCompeteForWidth() {
        let layout = MainWindowLayout.resolve(width: 919, height: 700)

        XCTAssertEqual(layout.mode, .stacked)
        XCTAssertTrue(layout.compactTelemetry)
    }

    func testShortWindowStacksAndKeepsTelemetryCompact() {
        let layout = MainWindowLayout.resolve(width: 1180, height: 520)

        XCTAssertEqual(layout.mode, .stacked)
        XCTAssertTrue(layout.compactTelemetry)
    }
}
