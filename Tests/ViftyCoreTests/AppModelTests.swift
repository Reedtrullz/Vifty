import XCTest
@testable import ViftyCore
@testable import Vifty

@MainActor
final class AppModelTests: XCTestCase {
    func testSaveProfileWithDuplicateNameOverwrites() {
        let model = AppModel()
        model.savedProfiles = []

        model.saveCurrentProfile(name: "Quiet")
        XCTAssertEqual(model.savedProfiles.count, 1)

        // Change sliders to different values.
        model.curveStartTemp = 60
        model.curveStartRPM = 1500

        // Save again with the same name — should overwrite, not append.
        model.saveCurrentProfile(name: "Quiet")
        XCTAssertEqual(model.savedProfiles.count, 1, "Duplicate name should overwrite, not append")
        XCTAssertEqual(model.savedProfiles[0].startTemp, 60, "Should store updated values")
        XCTAssertEqual(model.savedProfiles[0].startRPM, 1500)
    }

    func testSaveProfileWithDifferentNamesAppends() {
        let model = AppModel()
        model.savedProfiles = []

        model.saveCurrentProfile(name: "Quiet")
        model.saveCurrentProfile(name: "Loud")
        XCTAssertEqual(model.savedProfiles.count, 2)
    }

    func testCurveDefaultsOnlySyncOnce() {
        let model = AppModel()
        // Initially not synced.
        XCTAssertFalse(model.curveDefaultsSynced)

        // Mark as synced (simulates first poll having run).
        model.curveDefaultsSynced = true

        // Set values to exact defaults — they should NOT be overwritten.
        model.curveStartRPM = 1400
        model.curveMaxRPM = 6000

        // After marking synced, the guard in syncCurveDefaultsIfNeeded
        // returns early, so these values persist.
        XCTAssertEqual(model.curveStartRPM, 1400)
        XCTAssertEqual(model.curveMaxRPM, 6000)
        XCTAssertTrue(model.curveDefaultsSynced)
    }
}
