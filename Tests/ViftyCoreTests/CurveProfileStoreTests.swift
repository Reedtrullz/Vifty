import XCTest
@testable import ViftyCore

final class CurveProfileStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() {
        let url = tempURL()
        let store = CurveProfileStore(url: url)
        let profiles = [
            CurveProfile(name: "Quiet", startTemp: 50, startRPM: 1200, midTemp: 65, midRPM: 2500, maxTemp: 80, maxRPM: 4000),
            CurveProfile(name: "Loud",  startTemp: 40, startRPM: 2000, midTemp: 60, midRPM: 4000, maxTemp: 75, maxRPM: 6500)
        ]

        store.save(profiles)
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "Quiet")
        XCTAssertEqual(loaded[1].name, "Loud")
    }

    func testLoadFromMissingFileReturnsEmpty() {
        let url = tempURL()
        let store = CurveProfileStore(url: url)
        let loaded = store.load()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testLoadFromCorruptFileReturnsEmpty() {
        let url = tempURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! "not json".write(to: url, atomically: true, encoding: .utf8)
        let store = CurveProfileStore(url: url)
        let loaded = store.load()
        XCTAssertTrue(loaded.isEmpty, "Corrupt file should return empty, not crash")
    }

    func testSaveCreatesBackupFile() {
        let url = tempURL()
        let backupURL = url.appendingPathExtension("bak")
        let store = CurveProfileStore(url: url)
        let profiles = [CurveProfile(name: "A", startTemp: 50, startRPM: 1200, midTemp: 65, midRPM: 2500, maxTemp: 80, maxRPM: 4000)]

        store.save(profiles)
        // After save, a .bak file should exist.
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path), "Backup file should exist after save")
    }

    private func tempURL() -> URL {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("curve-profiles.json")
    }
}
