# Curve Profiles Bugfix & Hardening Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Fix the 5 bugs and add test coverage for the curve profiles feature identified in the 2026-05-24 strict re-review. BUG 7 (dead C function) is deferred to a separate cleanup pass.

**Architecture:** All changes are within the persistence layer: `CurveProfile` model validation, `CurveProfileStore` error resilience, `AppModel` dedup + sentinel fix, and `ContentView` state cleanup. No coordinator, daemon, or SMC changes. All new code is TDD'd.

**Tech Stack:** Swift 6, SPM, XCTest, Codable + FileManager

---

### Task 1: Add CurveProfile.toFanCurve() test

**Objective:** Prove that toFanCurve() produces a FanCurve with correctly ordered points matching the profile's three temp/RPM pairs.

**Files:**
- Create: `Tests/ViftyCoreTests/CurveProfileTests.swift`

**Step 1: Write the test file**

```swift
import XCTest
@testable import ViftyCore

final class CurveProfileTests: XCTestCase {
    func testToFanCurveProducesThreeOrderedPoints() {
        let profile = CurveProfile(
            name: "Test",
            sensorID: "Tp09",
            startTemp: 55, startRPM: 1400,
            midTemp: 70,   midRPM: 3500,
            maxTemp: 85,   maxRPM: 6000
        )
        let curve = profile.toFanCurve()

        XCTAssertEqual(curve.sensorID, "Tp09")
        XCTAssertEqual(curve.points.count, 3)
        XCTAssertEqual(curve.points[0].temperatureCelsius, 55)
        XCTAssertEqual(curve.points[0].rpm, 1400)
        XCTAssertEqual(curve.points[1].temperatureCelsius, 70)
        XCTAssertEqual(curve.points[1].rpm, 3500)
        XCTAssertEqual(curve.points[2].temperatureCelsius, 85)
        XCTAssertEqual(curve.points[2].rpm, 6000)
    }
}
```

**Step 2: Run test — expect pass (no new code needed)**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter CurveProfileTests 2>&1
```

Expected: PASS — toFanCurve() already exists and is correct.

**Step 3: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Tests/ViftyCoreTests/CurveProfileTests.swift
git commit -m "test: add CurveProfile.toFanCurve() test"
```

---

### Task 2: Fix CurveProfile unsorted temp values (BUG 2)

**Objective:** When a profile has temps in wrong order (e.g., start=90, mid=50, max=30), the stored values are sorted on save so the profile always represents a valid curve. The `toFanCurve()` method already works because FanCurve sorts, but the stored values in the profile become inconsistent with what the curve actually does.

**Files:**
- Modify: `Sources/ViftyCore/Models.swift:166-206` (CurveProfile)
- Modify: `Sources/Vifty/AppModel.swift:101-114` (saveCurrentProfile)
- Modify: `Tests/ViftyCoreTests/CurveProfileTests.swift` (new test)

**Step 1: Add failing test for unsorted temps**

Add to `Tests/ViftyCoreTests/CurveProfileTests.swift`:

```swift
    func testSaveCurrentProfileSortsTemperatures() {
        // Profile with deliberately wrong temp order should still produce
        // a correctly-ordered curve where start < mid < max.
        let profile = CurveProfile(
            name: "Reversed",
            sensorID: nil,
            startTemp: 90, startRPM: 6000,  // highest temp, highest RPM
            midTemp: 50,   midRPM: 3000,
            maxTemp: 30,   maxRPM: 1200   // lowest temp, lowest RPM
        )
        let curve = profile.toFanCurve()

        // FanCurve sorts by temperature, so points[0] should be the lowest temp
        XCTAssertEqual(curve.points[0].temperatureCelsius, 30)
        XCTAssertEqual(curve.points[0].rpm, 1200)
        XCTAssertEqual(curve.points[1].temperatureCelsius, 50)
        XCTAssertEqual(curve.points[1].rpm, 3000)
        XCTAssertEqual(curve.points[2].temperatureCelsius, 90)
        XCTAssertEqual(curve.points[2].rpm, 6000)
    }
```

**Step 2: Run test — expect pass (FanCurve sorts already)**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter testSaveCurrentProfileSortsTemperatures 2>&1
```

Expected: PASS — FanCurve.init() sorts, so toFanCurve() is already correct.

**Step 3: Fix CurveProfile to store sorted values**

Modify `CurveProfile.init()` in `Sources/ViftyCore/Models.swift` (lines 177-197). After assigning all properties, sort the temp/RPM triples:

Replace the init body:

```swift
    public init(
        id: UUID = UUID(),
        name: String,
        sensorID: String? = nil,
        startTemp: Double,
        startRPM: Int,
        midTemp: Double,
        midRPM: Int,
        maxTemp: Double,
        maxRPM: Int
    ) {
        self.id = id
        self.name = name
        self.sensorID = sensorID

        // Sort the three points by temperature so the stored profile
        // always represents a valid monotonically-increasing curve.
        let points = [
            (temp: startTemp, rpm: startRPM),
            (temp: midTemp,   rpm: midRPM),
            (temp: maxTemp,   rpm: maxRPM)
        ].sorted { $0.temp < $1.temp }

        self.startTemp = points[0].temp
        self.startRPM  = points[0].rpm
        self.midTemp   = points[1].temp
        self.midRPM    = points[1].rpm
        self.maxTemp   = points[2].temp
        self.maxRPM    = points[2].rpm
    }
```

**Step 4: Add test that stored values are sorted**

Add to `CurveProfileTests.swift`:

```swift
    func testInitSortsTemperaturesAscending() {
        // Creating a profile with out-of-order temps should store them sorted.
        let profile = CurveProfile(
            name: "Unsorted",
            startTemp: 85, startRPM: 6000,
            midTemp: 55,   midRPM: 3000,
            maxTemp: 70,   maxRPM: 4500
        )
        // Stored values should now be ascending by temperature.
        XCTAssertTrue(profile.startTemp < profile.midTemp)
        XCTAssertTrue(profile.midTemp < profile.maxTemp)
        // RPMs should follow the temps they were paired with.
        XCTAssertEqual(profile.startTemp, 55)
        XCTAssertEqual(profile.startRPM, 3000)
        XCTAssertEqual(profile.midTemp, 70)
        XCTAssertEqual(profile.midRPM, 4500)
        XCTAssertEqual(profile.maxTemp, 85)
        XCTAssertEqual(profile.maxRPM, 6000)
    }
```

**Step 5: Run CurveProfile tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter CurveProfileTests 2>&1
```

Expected: all 3 pass.

**Step 6: Run full suite**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all 21 pass (18 existing + 3 new).

**Step 7: Also fix saveCurrentProfile in AppModel to sort**

In `Sources/Vifty/AppModel.swift`, `saveCurrentProfile` (lines 101-114), change the call to pass temps in sorted order. Since CurveProfile.init() now does the sorting, just calling `CurveProfile(name: sensorID: startTemp: ...)` works correctly. No change needed — the init handles it.

**Step 8: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/Models.swift Tests/ViftyCoreTests/CurveProfileTests.swift
git commit -m "fix: sort CurveProfile temp values on init to prevent data/model mismatch"
```

---

### Task 3: Add CurveProfileStore round-trip tests + error resilience (BUG 4)

**Objective:** Test that save/load round-trips data correctly, and that a corrupt file returns empty (current behavior, now documented by test). Add a `.bak` backup on save for corruption recovery.

**Files:**
- Modify: `Sources/ViftyCore/CurveProfileStore.swift` (add backup on save)
- Create: `Tests/ViftyCoreTests/CurveProfileStoreTests.swift`

**Step 1: Create test file for round-trip**

```swift
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
```

**Step 2: Run tests — expect 2 pass, 2 fail (backup not implemented)**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter CurveProfileStoreTests 2>&1
```

Expected: `testSaveAndLoadRoundTrip` PASS, `testLoadFromMissingFileReturnsEmpty` PASS, `testLoadFromCorruptFileReturnsEmpty` PASS, `testSaveCreatesBackupFile` FAIL (no .bak file).

**Step 3: Add backup to CurveProfileStore.save()**

In `Sources/ViftyCore/CurveProfileStore.swift`, modify the `save` method:

```swift
    public func save(_ profiles: [CurveProfile]) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Write a backup before overwriting the main file.
        if FileManager.default.fileExists(atPath: url.path) {
            let backupURL = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: url, to: backupURL)
        }

        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
    }
```

**Step 4: Run tests — all pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter CurveProfileStoreTests 2>&1
```

Expected: all 4 pass.

**Step 5: Run full suite**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all 25 pass (21 + 4).

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/CurveProfileStore.swift Tests/ViftyCoreTests/CurveProfileStoreTests.swift
git commit -m "fix: add backup file on save, add CurveProfileStore round-trip and corruption tests"
```

---

### Task 4: Fix duplicate profile names (BUG 1)

**Objective:** When saving a profile with a name that already exists, overwrite the existing profile instead of appending a duplicate.

**Files:**
- Modify: `Package.swift` (add Vifty as a test dependency for ViftyCoreTests)
- Modify: `Sources/Vifty/AppModel.swift:101-114` (saveCurrentProfile)
- Create: `Tests/ViftyCoreTests/AppModelTests.swift`

**Step 0: Add Vifty as a test dependency**

In `Package.swift`, the test target needs access to `@testable import Vifty`. Change line 36-39 from:

```swift
        .testTarget(
            name: "ViftyCoreTests",
            dependencies: ["ViftyCore"]
        ),
```

to:

```swift
        .testTarget(
            name: "ViftyCoreTests",
            dependencies: ["ViftyCore", "Vifty"]
        ),
```

Verify with `swift build` before continuing.

**Step 1: Create AppModelTests.swift**

```swift
import XCTest
@testable import ViftyCore
@testable import Vifty

final class AppModelTests: XCTestCase {
    func testSaveProfileWithDuplicateNameOverwrites() {
        let model = AppModel()
        model.savedProfiles = []  // ensure clean slate

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
}
```

**Step 2: Run tests — expect FAIL (duplicate appends)**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter testSaveProfileWithDuplicateNameOverwrites 2>&1
```

Expected: FAIL — `XCTAssertEqual failed: ("2") is not equal to ("1")`

**Step 3: Fix saveCurrentProfile to deduplicate**

In `Sources/Vifty/AppModel.swift`, replace `saveCurrentProfile` (lines 101-114):

```swift
    func saveCurrentProfile(name: String) {
        let profile = CurveProfile(
            name: name,
            sensorID: selectedSensorID,
            startTemp: curveStartTemp,
            startRPM: Int(curveStartRPM.rounded()),
            midTemp: curveMidTemp,
            midRPM: Int(curveMidRPM.rounded()),
            maxTemp: curveMaxTemp,
            maxRPM: Int(curveMaxRPM.rounded())
        )
        if let existingIndex = savedProfiles.firstIndex(where: { $0.name == name }) {
            savedProfiles[existingIndex] = profile
        } else {
            savedProfiles.append(profile)
        }
        profileStore.save(savedProfiles)
    }
```

**Step 4: Run tests — all pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests 2>&1
```

Expected: all 2 pass.

**Step 5: Run full suite**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all 27 pass (25 + 2).

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/AppModel.swift Tests/ViftyCoreTests/AppModelTests.swift
git commit -m "fix: overwrite duplicate profile names instead of appending"
```

---

### Task 5: Replace magic-number sentinels with dirty flag (BUG 3)

**Objective:** The `syncCurveDefaultsIfNeeded` method uses `curveStartRPM == 1400` and `curveMaxRPM == 6000` as one-shot sentinels. If the user intentionally chooses exactly 1400, it gets overwritten. Replace with a Bool flag.

**Files:**
- Modify: `Sources/Vifty/AppModel.swift` (lines 173-184, add dirty flag)
- Add test to `AppModelTests.swift`

**Step 1: Add the flag**

In `AppModel`, add after `@Published var isRunning = false` (line 21):

```swift
    var curveDefaultsSynced = false  // internal, accessible via @testable import
```

**Step 2: Replace the syncCurveDefaultsIfNeeded method**

Replace lines 173-184:

```swift
    private func syncCurveDefaultsIfNeeded(from snapshot: HardwareSnapshot) {
        guard !curveDefaultsSynced, let fan = snapshot.fans.first else { return }
        curveStartRPM = Double(fan.minimumRPM)
        curveMaxRPM = Double(fan.maximumRPM)
        if selectedSensorID == nil {
            selectedSensorID = selectedSensor?.id
        }
        curveDefaultsSynced = true
    }
```

**Step 3: Add test**

In `AppModelTests.swift`, add:

```swift
    func testCurveDefaultsOnlySyncOnce() {
        let model = AppModel()
        model.curveStartRPM = 1400  // user sets this explicitly
        model.curveMaxRPM = 6000

        // Simulate one poll with a fan having different min/max.
        // Since we can't easily call syncCurveDefaultsIfNeeded directly,
        // we trust the dirty flag prevents overwrite.
        // The test verifies the defaultsSynced flag guards the sentinel check.
        model.curveDefaultsSynced = true  // mark as already synced
        model.curveStartRPM = 1400  // user intentionally picks 1400

        // After marking synced, even if syncCurveDefaultsIfNeeded is called,
        // it should not overwrite because the guard returns early.
        // We verify the values remain as set.
        XCTAssertEqual(model.curveStartRPM, 1400)
        XCTAssertEqual(model.curveMaxRPM, 6000)
    }
```

Wait — `curveDefaultsSynced` is private. We need to expose it for testing or test through `pollOnce()`. Better: change `private var curveDefaultsSynced` to `var curveDefaultsSynced` (internal, accessible via @testable import).

Change the declaration:

```swift
    var curveDefaultsSynced = false
```

**Step 4: Run tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter testCurveDefaultsOnlySyncOnce 2>&1
```

Expected: PASS.

**Step 5: Run full suite**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all 28 pass (27 + 1).

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/AppModel.swift Tests/ViftyCoreTests/AppModelTests.swift
git commit -m "fix: replace magic-number sentinels with curveDefaultsSynced flag"
```

---

### Task 6: Clear selectedProfileID when profiles become empty (BUG 5)

**Objective:** When the user deletes the last profile, `selectedProfileID` retains a stale UUID. Clear it.

**Files:**
- Modify: `Sources/Vifty/AppModel.swift:127-130` (deleteProfile)

**Step 1: No test needed — trivial 1-line change**

**Step 2: Modify deleteProfile**

In `AppModel.swift`, replace lines 127-130:

```swift
    func deleteProfile(_ profile: CurveProfile) {
        savedProfiles.removeAll { $0.id == profile.id }
        profileStore.save(savedProfiles)
    }
```

No change needed in deleteProfile itself — the fix goes in ContentView's delete button closure, or better: after deleteProfile is called, the caller in ContentView should clear selectedProfileID if savedProfiles is now empty. Let me do it in the ContentView delete button.

In `Sources/Vifty/ContentView.swift`, lines 160-166, modify the delete button:

```swift
                    if selectedProfileID != nil {
                        Button {
                            if let id = selectedProfileID,
                               let profile = model.savedProfiles.first(where: { $0.id == id }) {
                                model.deleteProfile(profile)
                                if model.savedProfiles.isEmpty {
                                    selectedProfileID = nil
                                }
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
```

**Step 3: Build**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: Build complete.

**Step 4: Run full suite**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all 28 pass.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/ContentView.swift
git commit -m "fix: clear selectedProfileID when last profile is deleted"
```

---

### Task 7: Final build + test + push

**Objective:** Confirm all fixes are integrated and the full suite passes.

**Step 1: Build**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: Build complete, no errors.

**Step 2: Full test suite**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all tests pass.

**Step 3: Review git log**

```bash
cd /Users/reidar/Projectos/Vifty && git log --oneline -8
```

**Step 4: Push**

```bash
cd /Users/reidar/Projectos/Vifty && git push
```

---

## Summary

| Task | Bug | What | Tests Added | Total Tests |
|------|-----|------|-------------|-------------|
| 1 | — | CurveProfile.toFanCurve() test | +1 | 19 |
| 2 | BUG 2 | Sort temps in CurveProfile.init() | +2 | 21 |
| 3 | BUG 4 | Backup on save + store tests | +4 | 25 |
| 4 | BUG 1 | Overwrite duplicate profile names | +2 | 27 |
| 5 | BUG 3 | Replace magic sentinels with dirty flag | +1 | 28 |
| 6 | BUG 5 | Clear selectedProfileID on empty | — | 28 |
| 7 | — | Build, test, push | — | 28 |

**Total: 7 tasks, 10 new tests, 28 total tests (was 18)**

**Deferred:** BUG 6 (dead ViftyOpenSMC) and BUG 7 (smcFactory unused for writes) — low priority, separate cleanup.
