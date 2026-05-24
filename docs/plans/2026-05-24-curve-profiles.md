# Curve Profile Persistence — Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Let users save, name, and switch between multiple fan curve profiles. Profiles persist as JSON in `~/Library/Application Support/Vifty/`.

**Architecture:** A `CurveProfile` Codable struct holds the 3-point curve + sensor + name. `AppModel` loads/saves profiles from a JSON file via a thin `CurveProfileStore`. The curve editor in `ContentView` gains a profile picker + Save/Load/Delete buttons. No coordinator changes needed — loading a profile just fills the slider values and applies the mode.

**Tech Stack:** Swift 6, SwiftUI, Codable + FileManager for persistence

---

### Task 1: Add CurveProfile model

**Objective:** Add a Codable, Identifiable, Sendable struct that captures a named curve configuration.

**Files:**
- Modify: `Sources/ViftyCore/Models.swift` (add after FanCurve, before FanMode)

**Step 1: Add the struct**

In `Sources/ViftyCore/Models.swift`, insert after line 164 (after `FanCurve.clamp`):

```swift
public struct CurveProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sensorID: String?
    public var startTemp: Double
    public var startRPM: Int
    public var midTemp: Double
    public var midRPM: Int
    public var maxTemp: Double
    public var maxRPM: Int

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
        self.startTemp = startTemp
        self.startRPM = startRPM
        self.midTemp = midTemp
        self.midRPM = midRPM
        self.maxTemp = maxTemp
        self.maxRPM = maxRPM
    }

    public func toFanCurve() -> FanCurve {
        FanCurve(sensorID: sensorID, points: [
            CurvePoint(temperatureCelsius: startTemp, rpm: startRPM),
            CurvePoint(temperatureCelsius: midTemp, rpm: midRPM),
            CurvePoint(temperatureCelsius: maxTemp, rpm: maxRPM)
        ])
    }
}
```

**Step 2: Build**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: Build complete.

**Step 3: Run tests — no regressions**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all 18 tests pass.

**Step 4: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/Models.swift
git commit -m "feat: add CurveProfile model for saved curve configurations"
```

---

### Task 2: Add CurveProfileStore for JSON persistence

**Objective:** A thin store that reads/writes `[CurveProfile]` to a JSON file in the Vifty Application Support directory.

**Files:**
- Create: `Sources/ViftyCore/CurveProfileStore.swift`

**Step 1: Create the file**

```swift
import Foundation

public final class CurveProfileStore: @unchecked Sendable {
    private let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Vifty/curve-profiles.json")
    }

    public func load() -> [CurveProfile] {
        guard let data = try? Data(contentsOf: url),
              let profiles = try? JSONDecoder().decode([CurveProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    public func save(_ profiles: [CurveProfile]) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
```

**Step 2: Build**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: Build complete — no compilation errors.

**Step 3: Run tests — no regressions**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all 18 tests pass.

**Step 4: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/CurveProfileStore.swift
git commit -m "feat: add CurveProfileStore for JSON persistence of curve profiles"
```

---

### Task 3: Add profile management to AppModel

**Objective:** Add `@Published var savedProfiles`, `saveCurrentProfile(name:)`, `loadProfile(_:)`, and `deleteProfile(_:)` to AppModel. Load profiles on init.

**Files:**
- Modify: `Sources/Vifty/AppModel.swift`

**Step 1: Add store and published property**

In AppModel, add:

```swift
// After the existing @Published properties (after line 21):
@Published var savedProfiles: [CurveProfile] = []

// After the coordinator property (after line 23):
private let profileStore = CurveProfileStore()
```

**Step 2: Load profiles in init**

After `self.coordinator = coordinator` in init (line 27), add:

```swift
self.savedProfiles = profileStore.load()
```

**Step 3: Add saveCurrentProfile method**

Add after `restoreAuto()` (after line 96):

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
    savedProfiles.append(profile)
    profileStore.save(savedProfiles)
}

func loadProfile(_ profile: CurveProfile) {
    curveStartTemp = profile.startTemp
    curveStartRPM = Double(profile.startRPM)
    curveMidTemp = profile.midTemp
    curveMidRPM = Double(profile.midRPM)
    curveMaxTemp = profile.maxTemp
    curveMaxRPM = Double(profile.maxRPM)
    selectedSensorID = profile.sensorID
    applyModeSelection()
}

func deleteProfile(_ profile: CurveProfile) {
    savedProfiles.removeAll { $0.id == profile.id }
    profileStore.save(savedProfiles)
}
```

**Step 4: Build**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: Build complete.

**Step 5: Run tests — no regressions**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all 18 tests pass.

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/AppModel.swift
git commit -m "feat: add profile save/load/delete to AppModel"
```

---

### Task 4: Add profile UI to ContentView curve editor

**Objective:** Add a profile picker, "Save" button with name input, and "Delete" button to the curve editor section. The picker shows saved profiles; selecting one loads it.

**Files:**
- Modify: `Sources/Vifty/ContentView.swift` (the `curveEditor` var, lines ~138-164)

**Note:** `read_file` on ContentView.swift first to get current line numbers, then patch.

**Step 1: Add imports and state**

In ContentView.swift, add at the top of the struct (after `@StateObject private var daemonInstaller`):

```swift
@State private var newProfileName = ""
@State private var showSaveDialog = false
```

**Step 2: Add profile section to curveEditor**

Replace the curveEditor var (the entire VStack at lines ~138-164) with:

```swift
private var curveEditor: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Temperature Curve")
            .font(.headline)

        if !model.savedProfiles.isEmpty {
            HStack {
                Picker("Profile", selection: $selectedProfileID) {
                    Text("Unsaved").tag(Optional<UUID>.none)
                    ForEach(model.savedProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .onChange(of: selectedProfileID) { _, newID in
                    guard let id = newID,
                          let profile = model.savedProfiles.first(where: { $0.id == id }) else { return }
                    model.loadProfile(profile)
                }

                if selectedProfileID != nil {
                    Button {
                        if let id = selectedProfileID,
                           let profile = model.savedProfiles.first(where: { $0.id == id }) {
                            model.deleteProfile(profile)
                            selectedProfileID = nil
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            }
        }

        if let sensors = model.snapshot?.temperatureSensors, !sensors.isEmpty {
            Picker("Sensor", selection: $model.selectedSensorID) {
                ForEach(sensors) { sensor in
                    Text(sensor.name).tag(Optional(sensor.id))
                }
            }
            .onChange(of: model.selectedSensorID) {
                model.applyModeSelection()
            }
        }

        CurvePointEditor(title: "Start", temp: $model.curveStartTemp, rpm: $model.curveStartRPM, rpmRange: model.fanRange)
        CurvePointEditor(title: "Ramp", temp: $model.curveMidTemp, rpm: $model.curveMidRPM, rpmRange: model.fanRange)
        CurvePointEditor(title: "High", temp: $model.curveMaxTemp, rpm: $model.curveMaxRPM, rpmRange: model.fanRange)

        if let sensor = model.selectedSensor {
            Text("Live: \(sensor.celsius, specifier: "%.1f") C from \(sensor.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack {
            if showSaveDialog {
                TextField("Profile name", text: $newProfileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Button("Save") {
                    let name = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    model.saveCurrentProfile(name: name)
                    selectedProfileID = model.savedProfiles.last?.id
                    newProfileName = ""
                    showSaveDialog = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Cancel") {
                    newProfileName = ""
                    showSaveDialog = false
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            } else {
                Button {
                    showSaveDialog = true
                } label: {
                    Label("Save Profile", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
```

Also add the state variable for selected profile:

```swift
@State private var selectedProfileID: UUID?
```

**Step 3: Build**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: Build complete. Fix any compilation errors.

**Step 4: Run tests — no regressions**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all 18 tests pass.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/ContentView.swift
git commit -m "feat: add profile picker, save, and delete UI to curve editor"
```

---

### Task 5: Final integration test

**Objective:** Build and test the full app.

**Step 1: Full build**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: Build complete, no errors, no warnings.

**Step 2: Full test suite**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: all 18 tests pass.

---

## Summary

| Task | What | Files | Tests |
|------|------|-------|-------|
| 1 | CurveProfile model (Codable, Identifiable) | Models.swift | — |
| 2 | CurveProfileStore (JSON file persistence) | CurveProfileStore.swift (new) | — |
| 3 | AppModel save/load/delete methods | AppModel.swift | — |
| 4 | Profile picker + Save/Delete UI | ContentView.swift | — |
| 5 | Integration build + test | — | 18 existing |

**Total: 5 tasks, 2 new files, 2 modified files, 18 tests maintained**
