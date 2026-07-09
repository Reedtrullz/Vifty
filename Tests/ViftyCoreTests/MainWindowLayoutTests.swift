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
        XCTAssertEqual(layout.controlPaneWidth, 496, accuracy: 0.1)
        XCTAssertEqual(layout.editorPaneIdealWidth, 560)
    }

    func testWideWindowUsesWorkbenchLayout() {
        let layout = MainWindowLayout.resolve(width: 1500, height: 820)

        XCTAssertEqual(layout.mode, .workbench)
        XCTAssertFalse(layout.compactTelemetry)
        XCTAssertEqual(layout.controlPaneWidth, 320)
        XCTAssertEqual(layout.editorPaneMinWidth, 460)
        XCTAssertEqual(layout.editorPaneIdealWidth, 600)
        XCTAssertEqual(layout.editorPaneMaxWidth, 760)
        XCTAssertEqual(layout.telemetryPaneMaxWidth, 1000)
    }

    func testNarrowWindowStacksBeforePanesCompeteForWidth() {
        let layout = MainWindowLayout.resolve(width: 979, height: 700)

        XCTAssertEqual(layout.mode, .stacked)
        XCTAssertTrue(layout.compactTelemetry)
    }

    func testShortWindowStacksAndKeepsTelemetryCompact() {
        let layout = MainWindowLayout.resolve(width: 1180, height: 520)

        XCTAssertEqual(layout.mode, .stacked)
        XCTAssertTrue(layout.compactTelemetry)
    }
}
