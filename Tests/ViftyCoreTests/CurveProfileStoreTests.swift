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

    func testSaveHandlesBackupCopyItemFailure() {
        let url = tempURL()
        let store = CurveProfileStore(url: url)
        let bakURL = url.appendingPathExtension("bak")

        // 1. First save so the main file exists and a .bak is created.
        let initial = [CurveProfile(name: "Initial", startTemp: 50, startRPM: 1200, midTemp: 65, midRPM: 2500, maxTemp: 80, maxRPM: 4000)]
        store.save(initial)

        // 2. Pre-create a read-only file where .bak would be written.
        //    Make it immutable so removeItem + copyItem both fail.
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "stale".write(to: bakURL, atomically: true, encoding: .utf8)
        chflags(bakURL.path, UInt32(UF_IMMUTABLE))

        // 3. Save again — backup copyItem should fail gracefully, main save must succeed.
        let updated = [CurveProfile(name: "Updated", startTemp: 40, startRPM: 1000, midTemp: 55, midRPM: 2000, maxTemp: 70, maxRPM: 5000)]
        store.save(updated)

        // 4. Assert the main profiles file was still saved successfully.
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1, "Save should succeed even when backup copyItem fails")
        XCTAssertEqual(loaded[0].name, "Updated", "Profile name should reflect the saved data")

        // Clean up: remove the immutable flag so temp dir can be reclaimed.
        chflags(bakURL.path, 0)
        try? FileManager.default.removeItem(at: bakURL)
    }

    private func tempURL() -> URL {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("curve-profiles.json")
    }
}
