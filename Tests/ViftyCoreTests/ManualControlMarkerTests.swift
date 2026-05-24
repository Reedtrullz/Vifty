import XCTest
@testable import ViftyCore

final class ManualControlMarkerTests: XCTestCase {
    func testMarkerNotPresentInitially() {
        let url = tempURL()
        let marker = ManualControlMarker(url: url)
        XCTAssertFalse(marker.wasManualControlActive)
    }

    func testMarkActiveCreatesFile() {
        let url = tempURL()
        let marker = ManualControlMarker(url: url)
        marker.markActive()
        XCTAssertTrue(marker.wasManualControlActive)
    }

    func testClearRemovesFile() {
        let url = tempURL()
        let marker = ManualControlMarker(url: url)
        marker.markActive()
        XCTAssertTrue(marker.wasManualControlActive)
        marker.clear()
        XCTAssertFalse(marker.wasManualControlActive)
    }

    func testDoubleMarkDoesNotCrash() {
        let url = tempURL()
        let marker = ManualControlMarker(url: url)
        marker.markActive()
        marker.markActive()
        XCTAssertTrue(marker.wasManualControlActive)
    }

    func testDoubleClearDoesNotCrash() {
        let url = tempURL()
        let marker = ManualControlMarker(url: url)
        marker.clear()
        marker.clear()
        XCTAssertFalse(marker.wasManualControlActive)
    }

    private func tempURL() -> URL {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("manual-control-active")
    }
}
