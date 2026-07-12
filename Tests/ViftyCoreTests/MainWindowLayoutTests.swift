import XCTest
@testable import Vifty

final class MainWindowLayoutTests: XCTestCase {
    func testMinimumSupportedWindowUsesStackedCompactLayout() {
        let layout = MainWindowLayout.resolve(width: 780, height: 480)

        XCTAssertEqual(layout.mode, .stacked)
        XCTAssertTrue(layout.compactTelemetry)
        XCTAssertEqual(layout.editorPaneMinWidth, 360)
        XCTAssertEqual(layout.telemetryPaneMinWidth, 360)
        XCTAssertEqual(layout.telemetryPaneMaxWidth, .infinity)
    }

    func testDefaultOperatorWindowUsesSplitRegularLayout() {
        let layout = MainWindowLayout.resolve(width: 1180, height: 820)

        XCTAssertEqual(layout.mode, .split)
        XCTAssertFalse(layout.compactTelemetry)
        XCTAssertEqual(layout.controlPaneWidth, 496, accuracy: 0.1)
        XCTAssertEqual(layout.editorPaneMinWidth, 420)
        XCTAssertEqual(layout.editorPaneIdealWidth, 560)
        XCTAssertEqual(layout.telemetryPaneMinWidth, 420)
        XCTAssertEqual(layout.telemetryPaneMaxWidth, .infinity)
    }

    func testWideWindowUsesWorkbenchLayout() {
        let layout = MainWindowLayout.resolve(width: 1500, height: 820)

        XCTAssertEqual(layout.mode, .workbench)
        XCTAssertFalse(layout.compactTelemetry)
        XCTAssertEqual(layout.controlPaneWidth, 320)
        XCTAssertEqual(layout.editorPaneMinWidth, 460)
        XCTAssertGreaterThanOrEqual(layout.editorPaneIdealWidth, 620)
        XCTAssertEqual(layout.editorPaneMaxWidth, 900)
        XCTAssertEqual(layout.telemetryPaneMinWidth, 420)
        XCTAssertGreaterThanOrEqual(layout.telemetryPaneIdealWidth, 520)
        XCTAssertEqual(layout.telemetryPaneMaxWidth, .infinity)
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

    func testUltraWideWorkbenchDoesNotCapTelemetryToNarrowColumn() {
        let layout = MainWindowLayout.resolve(width: 3024, height: 1600)

        XCTAssertEqual(layout.mode, .workbench)
        XCTAssertEqual(layout.controlPaneWidth, 320)
        XCTAssertGreaterThanOrEqual(layout.editorPaneIdealWidth, 760)
        XCTAssertGreaterThanOrEqual(layout.telemetryPaneIdealWidth, 1600)
        XCTAssertEqual(layout.telemetryPaneMaxWidth, .infinity)
    }

    func test1280ClassDisplayUsesSplitLayoutInsteadOfSparseWorkbench() {
        let layout = MainWindowLayout.resolve(width: 1280, height: 720)

        XCTAssertEqual(layout.mode, .split)
        XCTAssertFalse(layout.compactTelemetry)
        XCTAssertGreaterThanOrEqual(layout.controlPaneWidth, 480)
        XCTAssertGreaterThanOrEqual(layout.telemetryPaneMinWidth, 420)
    }

    func testWorkbenchBeginsAt1440Points() {
        XCTAssertEqual(MainWindowLayout.resolve(width: 1439, height: 820).mode, .split)
        XCTAssertEqual(MainWindowLayout.resolve(width: 1440, height: 820).mode, .workbench)
    }
}
