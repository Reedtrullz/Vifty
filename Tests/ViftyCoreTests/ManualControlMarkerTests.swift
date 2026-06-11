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

    func testMarkActiveRestrictsDirectoryAndFilePermissions() throws {
        let url = tempURL()
        let marker = ManualControlMarker(url: url)

        marker.markActive()

        XCTAssertEqual(try posixPermissions(at: url.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try posixPermissions(at: url), 0o600)
    }

    private func tempURL() -> URL {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("manual-control-active")
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
