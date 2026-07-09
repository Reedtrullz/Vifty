import XCTest
@testable import Vifty

final class MainWindowSectionPlacementTests: XCTestCase {
    func testWorkbenchPlacesSettingsInControlRailAndFanControlInEditor() {
        let layout = MainWindowLayout.resolve(width: 1500, height: 820)
        let placement = MainWindowSectionPlacement.resolve(layout: layout)

        XCTAssertEqual(placement.safetyMode, .workbenchControlRail)
        XCTAssertEqual(placement.settingsAndTools, .workbenchControlRail)
        XCTAssertEqual(placement.fanControl, .workbenchEditor)
        XCTAssertEqual(placement.telemetryEvidence, .workbenchTelemetry)
    }

    func testSplitLayoutKeepsTelemetrySeparateFromControlAndEditor() {
        let layout = MainWindowLayout.resolve(width: 1180, height: 820)
        let placement = MainWindowSectionPlacement.resolve(layout: layout)

        XCTAssertEqual(placement.safetyMode, .splitControl)
        XCTAssertEqual(placement.settingsAndTools, .splitControl)
        XCTAssertEqual(placement.fanControl, .splitControl)
        XCTAssertEqual(placement.telemetryEvidence, .splitTelemetry)
    }

    func testStackedLayoutUsesSingleFlowForAllSections() {
        let layout = MainWindowLayout.resolve(width: 780, height: 480)
        let placement = MainWindowSectionPlacement.resolve(layout: layout)

        XCTAssertEqual(placement.safetyMode, .stackedFlow)
        XCTAssertEqual(placement.settingsAndTools, .stackedFlow)
        XCTAssertEqual(placement.fanControl, .stackedFlow)
        XCTAssertEqual(placement.telemetryEvidence, .stackedFlow)
    }
}
