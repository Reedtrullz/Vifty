import Darwin
import XCTest
@testable import ViftyCore

final class CurveProfileStoreTests: XCTestCase {
    func testDefaultStoreIsIsolatedFromProductionProfilesUnderXCTest() {
        var store: CurveProfileStore? = CurveProfileStore()
        let productionURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vifty/curve-profiles.json")
        let storageURL = store!.storageURL
        let cleanupDirectory = storageURL.deletingLastPathComponent()

        XCTAssertNotEqual(storageURL.standardizedFileURL, productionURL.standardizedFileURL)
        XCTAssertTrue(
            storageURL.standardizedFileURL.path.hasPrefix(
                FileManager.default.temporaryDirectory.standardizedFileURL.path
            )
        )
        store!.save([profile(named: "Isolated")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
        store = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: cleanupDirectory.path))
    }

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

    func testCorruptPrimaryRecoversValidBackupAndReportsIt() throws {
        let url = tempURL()
        let backupURL = url.appendingPathExtension("bak")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let expected = [profile(named: "Recovered")]
        try JSONEncoder().encode(expected).write(to: backupURL)

        let result = try CurveProfileStore(url: url).loadResult()

        XCTAssertEqual(result.profiles, expected)
        XCTAssertEqual(result.source, .recoveredBackup)
        XCTAssertNotNil(result.recoveryMessage)
    }

    func testMissingPrimaryRecoversValidBackup() throws {
        let url = tempURL()
        let backupURL = url.appendingPathExtension("bak")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let expected = [profile(named: "Backup only")]
        try JSONEncoder().encode(expected).write(to: backupURL)

        let result = try CurveProfileStore(url: url).loadResult()

        XCTAssertEqual(result.profiles, expected)
        XCTAssertEqual(result.source, .recoveredBackup)
    }

    func testUnreadablePrimaryAndBackupThrowsInsteadOfClaimingEmpty() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("primary corrupt".utf8).write(to: url)
        try Data("backup corrupt".utf8).write(to: url.appendingPathExtension("bak"))

        XCTAssertThrowsError(try CurveProfileStore(url: url).loadResult()) { error in
            XCTAssertTrue(error is CurveProfileStoreError)
        }
    }

    func testSavingOverCorruptPrimaryPreservesValidBackup() throws {
        let url = tempURL()
        let backupURL = url.appendingPathExtension("bak")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("primary corrupt".utf8).write(to: url)
        let backupProfiles = [profile(named: "Last known good")]
        let backupData = try JSONEncoder().encode(backupProfiles)
        try backupData.write(to: backupURL)

        try CurveProfileStore(url: url).saveThrowing([profile(named: "New")])

        XCTAssertEqual(try Data(contentsOf: backupURL), backupData)
        XCTAssertEqual(try JSONDecoder().decode([CurveProfile].self, from: backupData), backupProfiles)
    }

    func testBackupReplacementPreservesKnownGoodBytesAtEveryPreRenameFailure() throws {
        for stage in CurveProfileBackupStage.allCases {
            let url = tempURL()
            let backupURL = url.appendingPathExtension("bak")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode([profile(named: "Primary")]).write(to: url)
            let knownGoodBackup = try JSONEncoder().encode([profile(named: "Known good backup")])
            try knownGoodBackup.write(to: backupURL)
            let hooks = CurveProfileBackupHooks(
                beforeStage: { currentStage in
                    if currentStage == stage { throw InjectedBackupFailure() }
                },
                synchronize: { descriptor in
                    guard fsync(descriptor) == 0 else { throw InjectedBackupFailure() }
                }
            )

            try CurveProfileStore(url: url, backupHooks: hooks).saveThrowing([
                profile(named: "New primary")
            ])

            XCTAssertEqual(
                try Data(contentsOf: backupURL),
                knownGoodBackup,
                "The existing backup changed after an injected \(stage) failure."
            )
        }
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

    func testSaveRestrictsDirectoryProfileAndBackupPermissions() throws {
        let url = tempURL()
        let store = CurveProfileStore(url: url)
        let profiles = [CurveProfile(name: "A", startTemp: 50, startRPM: 1200, midTemp: 65, midRPM: 2500, maxTemp: 80, maxRPM: 4000)]

        store.save(profiles)

        XCTAssertEqual(try posixPermissions(at: url.deletingLastPathComponent()), 0o700)
        XCTAssertEqual(try posixPermissions(at: url), 0o600)
        XCTAssertEqual(try posixPermissions(at: url.appendingPathExtension("bak")), 0o600)
    }

    func testSaveRestrictsLegacyBackupPermissions() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: url.path)

        let store = CurveProfileStore(url: url)
        let profiles = [CurveProfile(name: "A", startTemp: 50, startRPM: 1200, midTemp: 65, midRPM: 2500, maxTemp: 80, maxRPM: 4000)]

        store.save(profiles)

        XCTAssertEqual(try posixPermissions(at: url.appendingPathExtension("bak")), 0o600)
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

    func testSaveThrowingReportsDirectoryCreationFailure() throws {
        let parentFile = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: parentFile)
        let url = parentFile.appendingPathComponent("curve-profiles.json")
        let store = CurveProfileStore(url: url)
        let profiles = [CurveProfile(name: "A", startTemp: 50, startRPM: 1200, midTemp: 65, midRPM: 2500, maxTemp: 80, maxRPM: 4000)]

        XCTAssertThrowsError(try store.saveThrowing(profiles))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func tempURL() -> URL {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("curve-profiles.json")
    }

    private func profile(named name: String) -> CurveProfile {
        CurveProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: name,
            startTemp: 50,
            startRPM: 1_200,
            midTemp: 65,
            midRPM: 2_500,
            maxTemp: 80,
            maxRPM: 4_000
        )
    }

    private func posixPermissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

private struct InjectedBackupFailure: Error {}
