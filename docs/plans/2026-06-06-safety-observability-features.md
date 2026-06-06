# Vifty Safety & Observability Features Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add the highest-value Vifty feature tranche: explicit hardware fan-mode visibility, helper health, thermal pressure, battery/charger insights, timed manual modes, and short rolling telemetry history.

**Architecture:** Keep fan-control behavior in `FanControlCoordinator`, hardware reads in `RealMacHardwareService`/small pure readers, and UI state in `AppModel`. New hardware/IOKit parsing must be isolated behind pure testable helpers so tests do not depend on this Mac's charger, fan state, or SMC availability. XPC snapshot encoding must remain the single daemon/app boundary for fan snapshot fields.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest, SwiftUI, Foundation `ProcessInfo.thermalState`, IOKit/SMC dictionaries, GitHub Actions CI.

---

## Architecture audit before implementation

Read these first:

- `AGENTS.md` — repo architecture, target layout, SMC/XPC rules, testing rules.
- `README.md` — current user-facing behavior and safety claims.
- `Package.swift` — confirms `ViftyCoreTests` already depends on both `ViftyCore` and executable target `Vifty`, so `@testable import Vifty` in AppModel tests is valid. No Package.swift change is needed for the AppModel tests in this plan unless new tests import another executable target.
- `Sources/ViftyCore/HardwareService.swift` — fan-control heartbeat and Auto restore safety.
- `Sources/ViftyCore/RealMacHardwareService.swift` — daemon-first snapshot/apply/restore layer.
- `Sources/ViftyCore/ViftyDaemonProtocol.swift` and `Sources/ViftyDaemon/main.swift` — XPC snapshot shape and daemon implementation.
- `Sources/Vifty/AppModel.swift`, `Sources/Vifty/ContentView.swift`, `Sources/Vifty/MenuBarView.swift` — UI state and presentation.

Runtime heartbeat dependency chain:

```text
ViftyApp/MenuBarView/ContentView
  -> AppModel.start()/pollOnce()/applyModeSelection()/restoreAuto()
  -> FanControlCoordinator.tick()/setMode()/forceAuto()
  -> RealMacHardwareService.snapshot()/apply()/restoreAuto()
  -> ViftyDaemonClient XPC or local SMC fallback
  -> ViftyDaemon/DaemonService
  -> LocalFanHelperClient/SMCClient
```

Risk notes:

- Any change to `Fan`, `HardwareSnapshot`, or `XPCSnapshotCoding` can silently drop daemon fields if encode/decode tests are missing. Add XPC round-trip tests immediately when model fields change.
- Any change to Auto/manual state must preserve the existing invariant: selecting **Auto** is an explicit hardware restore command, not just UI cleanup.
- Any test that `@testable import Vifty` is safe because `Package.swift` already lists `"Vifty"` in `ViftyCoreTests` dependencies.
- SwiftUI view snippets below must compile against private nested views in `ContentView.swift`; prefer extracting pure display formatters into `ViftyCore` or `AppModel` and testing those directly, because there is no ViewInspector dependency.

---

### Task 1: Add fan hardware-mode fields to the Fan model

**Objective:** Represent the SMC fan mode (`Auto` vs `Forced`) and hardware target RPM directly on each `Fan` snapshot.

**Files:**
- Modify: `Sources/ViftyCore/Models.swift`
- Test: `Tests/ViftyCoreTests/FanStatusTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/FanStatusTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class FanStatusTests: XCTestCase {
    func testFanHardwareModeDecodesKnownSMCValues() {
        XCTAssertEqual(FanHardwareMode(rawValue: 0), .automatic)
        XCTAssertEqual(FanHardwareMode(rawValue: 1), .forced)
        XCTAssertEqual(FanHardwareMode(rawValue: 7), .unknown(7))
        XCTAssertNil(FanHardwareMode(rawValue: nil))
    }

    func testFanStoresHardwareModeAndTargetRPM() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 3200,
            minimumRPM: 1400,
            maximumRPM: 6000,
            controllable: true,
            hardwareMode: .forced,
            targetRPM: 5000
        )

        XCTAssertEqual(fan.hardwareMode, .forced)
        XCTAssertEqual(fan.targetRPM, 5000)
    }
}
```

**Step 2: Run tests to verify failure**

Run:

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter FanStatusTests 2>&1
```

Expected: FAIL — `FanHardwareMode` and the new `Fan` initializer parameters do not exist.

**Step 3: Add minimal model code**

In `Sources/ViftyCore/Models.swift`, insert before `public struct Fan`:

```swift
public enum FanHardwareMode: Equatable, Sendable {
    case automatic
    case forced
    case unknown(Int)

    public init?(rawValue: Int?) {
        guard let rawValue else { return nil }
        switch rawValue {
        case 0:
            self = .automatic
        case 1:
            self = .forced
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: Int {
        switch self {
        case .automatic: 0
        case .forced: 1
        case .unknown(let value): value
        }
    }

    public var displayName: String {
        switch self {
        case .automatic: "Auto"
        case .forced: "Forced"
        case .unknown(let value): "Unknown (\(value))"
        }
    }
}
```

Then extend `Fan` with optional fields at the end of the stored properties and initializer. Keep defaults so all existing call sites compile:

```swift
public struct Fan: Identifiable, Equatable, Sendable {
    public let id: Int
    public var name: String
    public var currentRPM: Int
    public var minimumRPM: Int
    public var maximumRPM: Int
    public var controllable: Bool
    public var hardwareMode: FanHardwareMode?
    public var targetRPM: Int?

    public init(
        id: Int,
        name: String,
        currentRPM: Int,
        minimumRPM: Int,
        maximumRPM: Int,
        controllable: Bool,
        hardwareMode: FanHardwareMode? = nil,
        targetRPM: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.currentRPM = currentRPM
        self.minimumRPM = minimumRPM
        self.maximumRPM = maximumRPM
        self.controllable = controllable
        self.hardwareMode = hardwareMode
        self.targetRPM = targetRPM
    }

    public var percentage: Int {
        guard maximumRPM > minimumRPM else { return 0 }
        let ratio = Double(currentRPM - minimumRPM) / Double(maximumRPM - minimumRPM)
        return max(0, min(100, Int((ratio * 100).rounded())))
    }
}
```

**Step 4: Run tests to verify pass**

Run:

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter FanStatusTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/Models.swift Tests/ViftyCoreTests/FanStatusTests.swift
git commit -m "feat: add fan hardware mode model"
```

---

### Task 2: Extract pure SMC fan snapshot parsing

**Objective:** Read `F{n}Md` and `F{n}Tg` through a pure parser seam so hardware fan mode and target RPM are tested with fixtures, not live SMC state.

**Files:**
- Create: `Sources/ViftyCore/FanInfoReader.swift`
- Modify: `Sources/ViftyCore/RealMacHardwareService.swift`
- Test: `Tests/ViftyCoreTests/FanInfoReaderTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/FanInfoReaderTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class FanInfoReaderTests: XCTestCase {
    func testReadsHardwareModeAndTargetRPM() {
        let values: [String: SMCValue] = [
            "FNum": SMCValue(key: "FNum", dataType: "ui8 ", bytes: [1]),
            "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", bytes: [0x0c, 0x80]), // 800 RPM? fixture only proves parser path
            "F0Mn": SMCValue(key: "F0Mn", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1400)),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(6000)),
            "F0Md": SMCValue(key: "F0Md", dataType: "ui8 ", bytes: [1]),
            "F0Tg": SMCValue(key: "F0Tg", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(5000))
        ]

        let fans = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }

        XCTAssertEqual(fans.count, 1)
        XCTAssertEqual(fans[0].hardwareMode, .forced)
        XCTAssertEqual(fans[0].targetRPM, 5000)
        XCTAssertEqual(fans[0].minimumRPM, 1400)
        XCTAssertEqual(fans[0].maximumRPM, 6000)
    }

    func testMissingModeAndTargetStayNil() {
        let values: [String: SMCValue] = [
            "FNum": SMCValue(key: "FNum", dataType: "ui8 ", bytes: [1]),
            "F0Ac": SMCValue(key: "F0Ac", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(2400)),
            "F0Mn": SMCValue(key: "F0Mn", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(1400)),
            "F0Mx": SMCValue(key: "F0Mx", dataType: "fpe2", bytes: SMCDecoding.encodeFPE2(6000))
        ]

        let fans = SMCFanInfoReader.readFans { key in
            guard let value = values[key] else { throw ViftyError.smcKeyUnavailable(key) }
            return value
        }

        XCTAssertEqual(fans[0].hardwareMode, nil)
        XCTAssertEqual(fans[0].targetRPM, nil)
    }
}
```

**Step 2: Run tests to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter FanInfoReaderTests 2>&1
```

Expected: FAIL — `SMCFanInfoReader` does not exist.

**Step 3: Add pure reader**

Create `Sources/ViftyCore/FanInfoReader.swift`:

```swift
import Foundation

public enum SMCFanInfoReader {
    public typealias ReadValue = (String) throws -> SMCValue

    public static func readFans(read: ReadValue) -> [Fan] {
        let fanCount = (try? read("FNum")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 0
        guard fanCount > 0 else { return [] }

        return (0..<fanCount).map { index in
            let actual = (try? read("F\(index)Ac")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 0
            let minimum = (try? read("F\(index)Mn")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? 1200
            let maximum = (try? read("F\(index)Mx")).flatMap(SMCDecoding.decodeFloat).map(Int.init) ?? max(actual, 6000)
            let modeRaw = (try? read("F\(index)Md")).flatMap(SMCDecoding.decodeFloat).map(Int.init)
            let target = (try? read("F\(index)Tg")).flatMap(SMCDecoding.decodeFloat).map(Int.init)

            return Fan(
                id: index,
                name: fanName(index),
                currentRPM: actual,
                minimumRPM: minimum,
                maximumRPM: maximum,
                controllable: maximum > minimum,
                hardwareMode: FanHardwareMode(rawValue: modeRaw),
                targetRPM: target
            )
        }
    }

    private static func fanName(_ index: Int) -> String {
        switch index {
        case 0: "Left Fan"
        case 1: "Right Fan"
        default: "Fan \(index + 1)"
        }
    }
}
```

Then simplify `RealMacHardwareService.readFans(_:)` to:

```swift
private static func readFans(_ smc: SMCClient) -> [Fan] {
    SMCFanInfoReader.readFans { key in
        try smc.read(key)
    }
}
```

Remove the now-duplicated private `fanName(_:)` from `RealMacHardwareService.swift`.

**Step 4: Run tests to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter FanInfoReaderTests 2>&1
```

Expected: PASS.

**Step 5: Run nearby regression tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter RealMacHardwareServiceTests 2>&1
```

Expected: PASS.

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/FanInfoReader.swift Sources/ViftyCore/RealMacHardwareService.swift Tests/ViftyCoreTests/FanInfoReaderTests.swift
git commit -m "feat: read fan hardware mode from SMC"
```

---

### Task 3: Round-trip new fan fields through XPC snapshots

**Objective:** Ensure daemon snapshots preserve `hardwareMode` and `targetRPM` across `XPCSnapshotCoding.encode/decode`.

**Files:**
- Modify: `Sources/ViftyCore/ViftyDaemonProtocol.swift`
- Test: `Tests/ViftyCoreTests/XPCSnapshotCodingTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/XPCSnapshotCodingTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class XPCSnapshotCodingTests: XCTestCase {
    func testFanHardwareModeAndTargetRoundTrip() {
        let snapshot = HardwareSnapshot(
            fans: [
                Fan(
                    id: 0,
                    name: "Left Fan",
                    currentRPM: 3200,
                    minimumRPM: 1400,
                    maximumRPM: 6000,
                    controllable: true,
                    hardwareMode: .forced,
                    targetRPM: 5000
                )
            ],
            temperatureSensors: [],
            modelIdentifier: "MacBookPro18,1",
            isAppleSilicon: true,
            isMacBookPro: true
        )

        let encoded = XPCSnapshotCoding.encode(snapshot)
        let decoded = XPCSnapshotCoding.decode(encoded)

        XCTAssertEqual(decoded?.fans.first?.hardwareMode, .forced)
        XCTAssertEqual(decoded?.fans.first?.targetRPM, 5000)
    }

    func testOlderSnapshotsWithoutFanHardwareFieldsStillDecode() {
        let dictionary: NSDictionary = [
            "modelIdentifier": "MacBookPro18,1",
            "isAppleSilicon": true,
            "isMacBookPro": true,
            "fans": [
                [
                    "id": 0,
                    "name": "Left Fan",
                    "currentRPM": 2400,
                    "minimumRPM": 1400,
                    "maximumRPM": 6000,
                    "controllable": true
                ] as NSDictionary
            ],
            "temperatureSensors": []
        ]

        let decoded = XPCSnapshotCoding.decode(dictionary)

        XCTAssertEqual(decoded?.fans.first?.hardwareMode, nil)
        XCTAssertEqual(decoded?.fans.first?.targetRPM, nil)
    }
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter XPCSnapshotCodingTests 2>&1
```

Expected: FAIL — fields are not encoded/decoded.

**Step 3: Encode/decode the fields**

In `XPCSnapshotCoding.encode`, use optional-friendly dictionary construction so `nil` values do not produce invalid `Any?` payloads. Complete fan dictionary block:

```swift
var encodedFan: [String: Any] = [
    "id": fan.id,
    "name": fan.name,
    "currentRPM": fan.currentRPM,
    "minimumRPM": fan.minimumRPM,
    "maximumRPM": fan.maximumRPM,
    "controllable": fan.controllable
]
if let hardwareMode = fan.hardwareMode {
    encodedFan["hardwareMode"] = hardwareMode.rawValue
}
if let targetRPM = fan.targetRPM {
    encodedFan["targetRPM"] = targetRPM
}
return encodedFan as NSDictionary
```

In `XPCSnapshotCoding.decode`, read the optional fields:

```swift
let hardwareModeRaw = item["hardwareMode"] as? Int
let targetRPM = item["targetRPM"] as? Int
return Fan(
    id: id,
    name: name,
    currentRPM: currentRPM,
    minimumRPM: minimumRPM,
    maximumRPM: maximumRPM,
    controllable: controllable,
    hardwareMode: FanHardwareMode(rawValue: hardwareModeRaw),
    targetRPM: targetRPM
)
```

**Step 4: Run tests to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter XPCSnapshotCodingTests 2>&1
```

Expected: PASS.

**Step 5: Run daemon/client-adjacent tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter XPCClientValidatorTests 2>&1
```

Expected: PASS.

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/ViftyDaemonProtocol.swift Tests/ViftyCoreTests/XPCSnapshotCodingTests.swift
git commit -m "feat: preserve fan hardware state over XPC"
```

---

### Task 4: Add pure display formatting for fan state

**Objective:** Make fan rows show user-facing state like `Forced · Target 5000 RPM` without putting formatting logic directly in SwiftUI views.

**Files:**
- Create: `Sources/ViftyCore/FanDisplayFormatter.swift`
- Test: `Tests/ViftyCoreTests/FanDisplayFormatterTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/FanDisplayFormatterTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class FanDisplayFormatterTests: XCTestCase {
    func testForcedFanSubtitleIncludesTarget() {
        let fan = Fan(
            id: 0,
            name: "Left Fan",
            currentRPM: 3200,
            minimumRPM: 1400,
            maximumRPM: 6000,
            controllable: true,
            hardwareMode: .forced,
            targetRPM: 5000
        )

        XCTAssertEqual(FanDisplayFormatter.subtitle(for: fan), "Forced · Target 5000 RPM")
    }

    func testAutoFanSubtitleOmitsMissingTarget() {
        let fan = Fan(id: 0, name: "Left Fan", currentRPM: 1800, minimumRPM: 1400, maximumRPM: 6000, controllable: true, hardwareMode: .automatic)

        XCTAssertEqual(FanDisplayFormatter.subtitle(for: fan), "Auto")
    }
}
```

**Step 2: Run tests to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter FanDisplayFormatterTests 2>&1
```

Expected: FAIL — formatter does not exist.

**Step 3: Add formatter**

Create `Sources/ViftyCore/FanDisplayFormatter.swift`:

```swift
import Foundation

public enum FanDisplayFormatter {
    public static func subtitle(for fan: Fan) -> String {
        var parts: [String] = []
        if let hardwareMode = fan.hardwareMode {
            parts.append(hardwareMode.displayName)
        }
        if let targetRPM = fan.targetRPM, fan.hardwareMode == .forced {
            parts.append("Target \(targetRPM) RPM")
        }
        return parts.isEmpty ? "Hardware mode unknown" : parts.joined(separator: " · ")
    }
}
```

**Step 4: Run tests to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter FanDisplayFormatterTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/FanDisplayFormatter.swift Tests/ViftyCoreTests/FanDisplayFormatterTests.swift
git commit -m "feat: format fan hardware state"
```

---

### Task 5: Show fan hardware state in the main fan rows

**Objective:** Surface actual hardware mode/target in the existing `FanRow` UI.

**Files:**
- Modify: `Sources/Vifty/ContentView.swift` (`FanRow`)
- Test: no ViewInspector available; verify via build and formatter tests from Task 4.

**Step 1: Modify FanRow**

In `Sources/Vifty/ContentView.swift`, inside `private struct FanRow`, add a subtitle line after the current RPM row and before `ProgressView`:

```swift
Text(FanDisplayFormatter.subtitle(for: fan))
    .font(.caption)
    .foregroundStyle(fan.hardwareMode == .forced ? .orange : .secondary)
```

The resulting body should be:

```swift
var body: some View {
    VStack(alignment: .leading, spacing: 6) {
        HStack {
            Text(fan.name)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(fan.currentRPM) RPM")
                .monospacedDigit()
        }
        Text(FanDisplayFormatter.subtitle(for: fan))
            .font(.caption)
            .foregroundStyle(fan.hardwareMode == .forced ? .orange : .secondary)
        ProgressView(value: Double(fan.percentage), total: 100)
        HStack {
            Text("\(fan.minimumRPM) min")
            Spacer()
            if let targetRPM {
                Text("Target \(targetRPM) RPM")
            }
            Spacer()
            Text("\(fan.maximumRPM) max")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding(10)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
}
```

Do not remove the existing curve target preview; hardware target and curve preview answer different questions.

**Step 2: Build to verify SwiftUI compiles**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: PASS.

**Step 3: Run full tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: PASS.

**Step 4: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/ContentView.swift
git commit -m "feat: show fan hardware state in UI"
```

---

### Task 6: Add thermal pressure model and formatter

**Objective:** Expose macOS thermal pressure (`Nominal`, `Fair`, `Serious`, `Critical`) as a typed snapshot independent from fan temperature sensors.

**Files:**
- Create: `Sources/ViftyCore/ThermalPressure.swift`
- Test: `Tests/ViftyCoreTests/ThermalPressureTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/ThermalPressureTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class ThermalPressureTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(ThermalPressure.nominal.displayName, "Nominal")
        XCTAssertEqual(ThermalPressure.fair.displayName, "Fair")
        XCTAssertEqual(ThermalPressure.serious.displayName, "Serious")
        XCTAssertEqual(ThermalPressure.critical.displayName, "Critical")
    }

    func testMenuSummaryOnlyShowsElevatedStates() {
        XCTAssertNil(ThermalPressure.nominal.menuSummary)
        XCTAssertEqual(ThermalPressure.serious.menuSummary, "Thermal: Serious")
    }
}
```

**Step 2: Run tests to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter ThermalPressureTests 2>&1
```

Expected: FAIL — type does not exist.

**Step 3: Add model**

Create `Sources/ViftyCore/ThermalPressure.swift`:

```swift
import Foundation

public enum ThermalPressure: String, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    public init(processInfoState: ProcessInfo.ThermalState) {
        switch processInfoState {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        case .unknown: "Unknown"
        }
    }

    public var menuSummary: String? {
        switch self {
        case .nominal, .unknown:
            nil
        case .fair, .serious, .critical:
            "Thermal: \(displayName)"
        }
    }
}

public enum ThermalPressureReader {
    public static func read() -> ThermalPressure {
        ThermalPressure(processInfoState: ProcessInfo.processInfo.thermalState)
    }
}
```

**Step 4: Run tests to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter ThermalPressureTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/ThermalPressure.swift Tests/ViftyCoreTests/ThermalPressureTests.swift
git commit -m "feat: add thermal pressure model"
```

---

### Task 7: Poll thermal pressure in AppModel and menu title

**Objective:** Refresh thermal pressure on every poll and include elevated thermal pressure in the menu bar summary.

**Files:**
- Modify: `Sources/Vifty/AppModel.swift`
- Test: `Tests/ViftyCoreTests/AppModelTests.swift`

**Step 1: Write failing AppModel test**

Add to `AppModelTests`:

```swift
func testMenuTitleIncludesElevatedThermalPressure() async {
    let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
        fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
        temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 74, source: .smc)],
        modelIdentifier: "MacBookPro18,3",
        isAppleSilicon: true,
        isMacBookPro: true
    ))
    let model = AppModel(
        coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
        powerReader: { PowerSnapshot(percent: 50) },
        thermalReader: { .serious },
        daemonPing: { true }
    )

    await model.pollOnce()

    XCTAssertEqual(model.thermalPressure, .serious)
    XCTAssertTrue(model.menuTitle.contains("Thermal: Serious"))
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests/testMenuTitleIncludesElevatedThermalPressure 2>&1
```

Expected: FAIL — `thermalReader` initializer argument and `thermalPressure` property do not exist.

**Step 3: Modify AppModel**

In `AppModel`, add published property and injected reader:

```swift
@Published var thermalPressure: ThermalPressure = .nominal

private let thermalReader: @Sendable () -> ThermalPressure
```

Change the initializer signature to:

```swift
init(
    coordinator: FanControlCoordinator = FanControlCoordinator(hardware: RealMacHardwareService()),
    powerReader: @escaping @Sendable () -> PowerSnapshot = { PowerInfoReader.read() },
    thermalReader: @escaping @Sendable () -> ThermalPressure = { ThermalPressureReader.read() },
    daemonPing: @escaping @Sendable () async -> Bool = { await ViftyDaemonClient().ping() }
) {
    self.coordinator = coordinator
    self.powerReader = powerReader
    self.thermalReader = thermalReader
    self.daemonPing = daemonPing
    savedProfiles = profileStore.load()
}
```

At the top of `pollOnce()` after `powerSnapshot = powerReader()`:

```swift
thermalPressure = thermalReader()
```

In `menuTitle`, append elevated state after power summary:

```swift
if let thermal = thermalPressure.menuSummary {
    parts.append(thermal)
}
```

**Step 4: Run test to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests/testMenuTitleIncludesElevatedThermalPressure 2>&1
```

Expected: PASS.

**Step 5: Run AppModel tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests 2>&1
```

Expected: PASS.

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/AppModel.swift Tests/ViftyCoreTests/AppModelTests.swift
git commit -m "feat: poll thermal pressure"
```

---

### Task 8: Display thermal pressure in main and menu views

**Objective:** Add visible thermal pressure rows to `MenuBarView` and `ContentView` without changing fan-control behavior.

**Files:**
- Modify: `Sources/Vifty/MenuBarView.swift`
- Modify: `Sources/Vifty/ContentView.swift`

**Step 1: Add MenuBar row**

In `MenuBarView`, after the highest-temperature label, add:

```swift
Label("Thermal pressure: \(model.thermalPressure.displayName)", systemImage: "speedometer")
    .foregroundStyle(model.thermalPressure == .serious || model.thermalPressure == .critical ? .orange : .secondary)
```

**Step 2: Add ContentView header/status label**

In `ContentView.header`, near the power label, add:

```swift
Label("Thermal \(model.thermalPressure.displayName)", systemImage: "speedometer")
    .font(.caption)
    .foregroundStyle(model.thermalPressure == .serious || model.thermalPressure == .critical ? .orange : .secondary)
```

Keep the label compact; do not crowd the fan control pane.

**Step 3: Build to verify SwiftUI compiles**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: PASS.

**Step 4: Run tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/MenuBarView.swift Sources/Vifty/ContentView.swift
git commit -m "feat: show thermal pressure in UI"
```

---

### Task 9: Add power insights for battery ETA and charger insufficiency

**Objective:** Turn existing power snapshot fields into user-facing insights: remaining battery estimate and plugged-in-but-draining warning.

**Files:**
- Modify: `Sources/ViftyCore/PowerInfo.swift`
- Test: `Tests/ViftyCoreTests/PowerInfoTests.swift`

**Step 1: Write failing tests**

Add to `PowerInfoTests`:

```swift
func testPowerInsightsEstimateBatteryRuntimeFromLiveDrain() {
    let snapshot = PowerSnapshot(
        percent: 50,
        isPluggedIn: false,
        batteryVoltageVolts: 12.0,
        batteryCurrentAmps: -2.0,
        batteryPowerWatts: -24.0,
        currentCapacityMah: 4000
    )

    let insights = PowerInsights(snapshot: snapshot)

    XCTAssertEqual(insights.estimatedBatteryMinutes, 120)
    XCTAssertEqual(insights.estimatedBatteryText, "2h 0m remaining at current drain")
}

func testPowerInsightsWarnWhenPluggedInButBatteryDraining() {
    let snapshot = PowerSnapshot(
        isPluggedIn: true,
        batteryPowerWatts: -8.4,
        adapter: PowerAdapter(ratedWatts: 30)
    )

    let insights = PowerInsights(snapshot: snapshot)

    XCTAssertEqual(insights.chargerWarning, "Plugged in, but battery is draining at 8.4 W")
}
```

**Step 2: Run tests to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter PowerInfoTests 2>&1
```

Expected: FAIL — `PowerInsights` does not exist.

**Step 3: Add pure insights type**

Add to `PowerInfo.swift` after `PowerDisplayFormatter`:

```swift
public struct PowerInsights: Equatable, Sendable {
    public var estimatedBatteryMinutes: Int?
    public var chargerWarning: String?

    public init(snapshot: PowerSnapshot) {
        self.estimatedBatteryMinutes = Self.estimateBatteryMinutes(snapshot)
        self.chargerWarning = Self.makeChargerWarning(snapshot)
    }

    public var estimatedBatteryText: String? {
        estimatedBatteryMinutes.map { "\(PowerDisplayFormatter.duration(minutes: $0)) remaining at current drain" }
    }

    private static func estimateBatteryMinutes(_ snapshot: PowerSnapshot) -> Int? {
        guard let watts = snapshot.batteryPowerWatts, watts < -0.5,
              let voltage = snapshot.batteryVoltageVolts, voltage > 0,
              let currentCapacityMah = snapshot.currentCapacityMah, currentCapacityMah > 0
        else { return nil }

        let remainingWh = Double(currentCapacityMah) / 1000.0 * voltage
        return Int((remainingWh / abs(watts) * 60.0).rounded())
    }

    private static func makeChargerWarning(_ snapshot: PowerSnapshot) -> String? {
        guard snapshot.isPluggedIn,
              let watts = snapshot.batteryPowerWatts,
              watts < -1.0
        else { return nil }
        return "Plugged in, but battery is draining at \(PowerDisplayFormatter.watts(abs(watts)))"
    }
}
```

**Step 4: Run tests to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter PowerInfoTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/PowerInfo.swift Tests/ViftyCoreTests/PowerInfoTests.swift
git commit -m "feat: add power insights"
```

---

### Task 10: Show power insights in the Power panel and menu

**Objective:** Surface battery ETA and charger insufficiency warning in existing power UI.

**Files:**
- Modify: `Sources/Vifty/ContentView.swift`
- Modify: `Sources/Vifty/MenuBarView.swift`
- Test: build + existing `PowerInfoTests`.

**Step 1: Add menu warning**

In `MenuBarView`, inside `if let power = model.powerSnapshot`, add after `batteryFlow`:

```swift
let insights = PowerInsights(snapshot: power)
if let warning = insights.chargerWarning {
    Label(warning, systemImage: "exclamationmark.triangle")
        .font(.caption)
        .foregroundStyle(.orange)
}
```

**Step 2: Add PowerPanel lines**

In `PowerPanel.body`, inside the `VStack(alignment: .leading, spacing: 6)` that shows `batteryLine`, `adapterLine`, and `profilesLine`, add:

```swift
let insights = PowerInsights(snapshot: snapshot)
if let eta = insights.estimatedBatteryText {
    Text("Estimate: \(eta)")
}
if let warning = insights.chargerWarning {
    Text(warning)
        .foregroundStyle(.orange)
}
```

If Swift complains about declaring `let insights` inside the `ViewBuilder`, move it to a computed property:

```swift
private var insights: PowerInsights { PowerInsights(snapshot: snapshot) }
```

and reference `insights` in the body.

**Step 3: Build to verify SwiftUI compiles**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: PASS.

**Step 4: Run tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/ContentView.swift Sources/Vifty/MenuBarView.swift
git commit -m "feat: show power insights"
```

---

### Task 11: Add timed manual-mode session state to AppModel

**Objective:** Allow fixed/curve modes to automatically restore Auto after a selected duration.

**Files:**
- Modify: `Sources/Vifty/AppModel.swift`
- Test: `Tests/ViftyCoreTests/AppModelTests.swift`

**Step 1: Write failing tests**

Add to `AppModelTests`:

```swift
func testTimedManualModeRestoresAutoAfterDeadline() async {
    let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
        fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
        temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
        modelIdentifier: "MacBookPro18,3",
        isAppleSilicon: true,
        isMacBookPro: true
    ))
    var now = Date(timeIntervalSince1970: 1000)
    let model = AppModel(
        coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
        powerReader: { PowerSnapshot(percent: 50) },
        thermalReader: { .nominal },
        now: { now },
        daemonPing: { true }
    )

    model.selectedMode = .fixed
    model.fixedRPM = 5000
    model.manualRunLimit = .minutes(10)
    await model.applyCurrentModeSelection()

    now = Date(timeIntervalSince1970: 1000 + 601)
    await model.pollOnce()

    XCTAssertEqual(model.selectedMode, .auto)
    XCTAssertNil(model.manualSessionExpiresAt)
    let restored = await hardware.restoredFanIDs
    XCTAssertEqual(restored, [0], "Timed expiry must issue a real Auto restore, not only update UI state")
}

func testExplicitRestoreAutoClearsTimedManualDeadline() async {
    let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
        fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
        temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
        modelIdentifier: "MacBookPro18,3",
        isAppleSilicon: true,
        isMacBookPro: true
    ))
    let now = Date(timeIntervalSince1970: 1000)
    let model = AppModel(
        coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
        powerReader: { PowerSnapshot(percent: 50) },
        thermalReader: { .nominal },
        now: { now },
        daemonPing: { true }
    )

    model.selectedMode = .fixed
    model.fixedRPM = 5000
    model.manualRunLimit = .minutes(10)
    await model.applyCurrentModeSelection()
    XCTAssertNotNil(model.manualSessionExpiresAt)

    await model.restoreAutoNow()

    XCTAssertEqual(model.selectedMode, .auto)
    XCTAssertNil(model.manualSessionExpiresAt)
    let restored = await hardware.restoredFanIDs
    XCTAssertEqual(restored, [0], "Explicit Auto must also issue a hardware restore")
}
```

Also update the `AppModelFakeHardware` actor at the bottom of `AppModelTests` so the test can prove hardware restore happened:

```swift
private actor AppModelFakeHardware: HardwareService {
    var snapshotValue: HardwareSnapshot
    var restoredFanIDs: [Int] = []

    init(snapshot: HardwareSnapshot) {
        self.snapshotValue = snapshot
    }

    func snapshot() async throws -> HardwareSnapshot {
        snapshotValue
    }

    func apply(_ command: FanCommand, fan: Fan) async throws {}

    func restoreAuto(fan: Fan) async throws {
        restoredFanIDs.append(fan.id)
    }
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests/testTimedManualModeRestoresAutoAfterDeadline 2>&1
```

Expected: FAIL — `manualRunLimit`, `manualSessionExpiresAt`, `applyCurrentModeSelection()`, `restoreAutoNow()`, and `now` injection do not exist.

**Step 3: Add run-limit enum and state**

In `AppModel.swift`, near `ModeSelection`, add:

```swift
enum ManualRunLimit: Equatable, Hashable, Identifiable {
    case indefinitely
    case minutes(Int)

    var id: String {
        switch self {
        case .indefinitely: "indefinitely"
        case .minutes(let minutes): "\(minutes)m"
        }
    }

    var label: String {
        switch self {
        case .indefinitely: "Until changed"
        case .minutes(let minutes): "\(minutes) min"
        }
    }

    static let presets: [ManualRunLimit] = [.indefinitely, .minutes(10), .minutes(30), .minutes(60)]
}
```

Add properties to `AppModel`:

```swift
@Published var manualRunLimit: ManualRunLimit = .indefinitely
@Published var manualSessionExpiresAt: Date?

private let now: @Sendable () -> Date
```

Extend `AppModel.init`:

```swift
now: @escaping @Sendable () -> Date = { Date() },
```

and assign:

```swift
self.now = now
```

Add helper methods inside `AppModel`:

```swift
private func selectedFanMode() -> FanMode {
    switch selectedMode {
    case .auto:
        .auto
    case .fixed:
        .fixedRPM(Int(fixedRPM.rounded()))
    case .curve:
        .temperatureCurve(currentCurve())
    }
}

private func updateManualDeadline(for mode: FanMode) {
    guard mode != .auto else {
        manualSessionExpiresAt = nil
        return
    }
    switch manualRunLimit {
    case .indefinitely:
        manualSessionExpiresAt = nil
    case .minutes(let minutes):
        manualSessionExpiresAt = now().addingTimeInterval(TimeInterval(minutes * 60))
    }
}

func applyCurrentModeSelection() async {
    let mode = selectedFanMode()
    updateManualDeadline(for: mode)
    await coordinator.setMode(mode)
    await pollOnce()
}

func restoreAutoNow() async {
    selectedMode = .auto
    manualSessionExpiresAt = nil
    await coordinator.setMode(.auto)
    await pollOnce()
}

private func restoreAutoIfManualSessionExpired() async -> Bool {
    guard selectedMode != .auto,
          let manualSessionExpiresAt,
          now() >= manualSessionExpiresAt
    else { return false }

    selectedMode = .auto
    self.manualSessionExpiresAt = nil
    await coordinator.setMode(.auto)
    return true
}
```

Then replace the body of `applyModeSelection()` with a wrapper around the awaitable helper. This avoids flaky tests that race an unstructured `Task` while preserving the existing synchronous SwiftUI button/onChange API:

```swift
func applyModeSelection() {
    Task {
        await applyCurrentModeSelection()
    }
}
```

Also replace the body of `restoreAuto()` with a wrapper around `restoreAutoNow()` so explicit menu/UI Auto clears any timed deadline and performs the same hardware restore path:

```swift
func restoreAuto() {
    Task {
        await restoreAutoNow()
    }
}
```

At the start of `pollOnce()` after power/thermal refresh and before `coordinator.tick()`:

```swift
_ = await restoreAutoIfManualSessionExpired()
```

**Step 4: Run test to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests/testTimedManualModeRestoresAutoAfterDeadline 2>&1
```

Expected: PASS.

**Step 5: Run AppModel tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests 2>&1
```

Expected: PASS.

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/AppModel.swift Tests/ViftyCoreTests/AppModelTests.swift
git commit -m "feat: add timed manual fan sessions"
```

---

### Task 12: Add timed manual-mode controls to the UI

**Objective:** Let the user pick a manual-mode duration before selecting Fixed or Curve.

**Files:**
- Modify: `Sources/Vifty/ContentView.swift`
- Modify: `Sources/Vifty/MenuBarView.swift`

**Step 1: Add duration picker to ContentView**

In `modePicker`, after the segmented mode picker and before the Apply button, add a duration picker that remains visible and usable while Auto is selected. This lets the user choose `10 min` or `30 min` before switching to Fixed/Curve; the existing mode `.onChange` then applies the intended limit immediately.

```swift
Picker("Manual run", selection: $model.manualRunLimit) {
    ForEach(ManualRunLimit.presets) { limit in
        Text(limit.label).tag(limit)
    }
}
.pickerStyle(.menu)

if let expiresAt = model.manualSessionExpiresAt {
    Text("Auto restore scheduled at \(expiresAt.formatted(date: .omitted, time: .shortened))")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**Step 2: Add menu countdown/status**

In `MenuBarView`, before the `Divider()`, add:

```swift
if let expiresAt = model.manualSessionExpiresAt {
    Label("Auto restore at \(expiresAt.formatted(date: .omitted, time: .shortened))", systemImage: "timer")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**Step 3: Build**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: PASS.

**Step 4: Run tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/ContentView.swift Sources/Vifty/MenuBarView.swift
git commit -m "feat: add timed fan mode controls"
```

---

### Task 13: Add a rolling telemetry history ring buffer

**Objective:** Keep a short in-memory history of temperature, fan RPM, battery watts, and thermal pressure for mini graphs and debugging.

**Files:**
- Create: `Sources/ViftyCore/TelemetryHistory.swift`
- Test: `Tests/ViftyCoreTests/TelemetryHistoryTests.swift`

**Step 1: Write failing tests**

Create `Tests/ViftyCoreTests/TelemetryHistoryTests.swift`:

```swift
import XCTest
@testable import ViftyCore

final class TelemetryHistoryTests: XCTestCase {
    func testHistoryKeepsNewestSamplesWithinLimit() {
        var history = TelemetryHistory(limit: 3)
        for index in 0..<5 {
            history.append(TelemetrySample(
                capturedAt: Date(timeIntervalSince1970: Double(index)),
                highestTemperatureCelsius: Double(60 + index),
                firstFanRPM: 2000 + index,
                batteryPowerWatts: -10,
                thermalPressure: .nominal
            ))
        }

        XCTAssertEqual(history.samples.count, 3)
        XCTAssertEqual(history.samples.first?.firstFanRPM, 2002)
        XCTAssertEqual(history.samples.last?.firstFanRPM, 2004)
    }
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter TelemetryHistoryTests 2>&1
```

Expected: FAIL — types do not exist.

**Step 3: Add history types**

Create `Sources/ViftyCore/TelemetryHistory.swift`:

```swift
import Foundation

public struct TelemetrySample: Equatable, Identifiable, Sendable {
    public var id: Date { capturedAt }
    public var capturedAt: Date
    public var highestTemperatureCelsius: Double?
    public var firstFanRPM: Int?
    public var batteryPowerWatts: Double?
    public var thermalPressure: ThermalPressure

    public init(
        capturedAt: Date,
        highestTemperatureCelsius: Double?,
        firstFanRPM: Int?,
        batteryPowerWatts: Double?,
        thermalPressure: ThermalPressure
    ) {
        self.capturedAt = capturedAt
        self.highestTemperatureCelsius = highestTemperatureCelsius
        self.firstFanRPM = firstFanRPM
        self.batteryPowerWatts = batteryPowerWatts
        self.thermalPressure = thermalPressure
    }
}

public struct TelemetryHistory: Equatable, Sendable {
    public private(set) var samples: [TelemetrySample] = []
    public var limit: Int

    public init(limit: Int = 900) {
        self.limit = max(1, limit)
    }

    public mutating func append(_ sample: TelemetrySample) {
        samples.append(sample)
        if samples.count > limit {
            samples.removeFirst(samples.count - limit)
        }
    }
}
```

Default `limit = 900` equals 30 minutes at the current 2-second polling cadence.

**Step 4: Run tests to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter TelemetryHistoryTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/ViftyCore/TelemetryHistory.swift Tests/ViftyCoreTests/TelemetryHistoryTests.swift
git commit -m "feat: add telemetry history buffer"
```

---

### Task 14: Append telemetry history from AppModel polling

**Objective:** Populate the history buffer from the actual snapshot/power/thermal data on every successful poll.

**Files:**
- Modify: `Sources/Vifty/AppModel.swift`
- Test: `Tests/ViftyCoreTests/AppModelTests.swift`

**Step 1: Write failing test**

Add to `AppModelTests`:

```swift
func testPollOnceAppendsTelemetryHistorySample() async {
    let hardware = AppModelFakeHardware(snapshot: HardwareSnapshot(
        fans: [Fan(id: 0, name: "Left", currentRPM: 2500, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
        temperatureSensors: [TemperatureSensor(id: "Tp09", name: "CPU Proximity", celsius: 64, source: .smc)],
        modelIdentifier: "MacBookPro18,3",
        isAppleSilicon: true,
        isMacBookPro: true
    ))
    let now = Date(timeIntervalSince1970: 1234)
    let model = AppModel(
        coordinator: FanControlCoordinator(hardware: hardware, uncleanMarker: ManualControlMarker(url: temporaryMarkerPath())),
        powerReader: { PowerSnapshot(percent: 50, batteryPowerWatts: -12.5) },
        thermalReader: { .fair },
        now: { now },
        daemonPing: { true }
    )

    await model.pollOnce()

    XCTAssertEqual(model.telemetryHistory.samples.count, 1)
    XCTAssertEqual(model.telemetryHistory.samples[0].capturedAt, now)
    XCTAssertEqual(model.telemetryHistory.samples[0].highestTemperatureCelsius, 64)
    XCTAssertEqual(model.telemetryHistory.samples[0].firstFanRPM, 2500)
    XCTAssertEqual(model.telemetryHistory.samples[0].batteryPowerWatts, -12.5)
    XCTAssertEqual(model.telemetryHistory.samples[0].thermalPressure, .fair)
}
```

**Step 2: Run test to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests/testPollOnceAppendsTelemetryHistorySample 2>&1
```

Expected: FAIL — `telemetryHistory` does not exist.

**Step 3: Add AppModel history property and append logic**

In `AppModel`, add:

```swift
@Published var telemetryHistory = TelemetryHistory()
```

After `snapshot = nextSnapshot` and before `lastError = nil` in `pollOnce()`, append:

```swift
telemetryHistory.append(TelemetrySample(
    capturedAt: now(),
    highestTemperatureCelsius: nextSnapshot.highestTemperature?.celsius,
    firstFanRPM: nextSnapshot.fans.first?.currentRPM,
    batteryPowerWatts: powerSnapshot?.batteryPowerWatts,
    thermalPressure: thermalPressure
))
```

**Step 4: Run test to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests/testPollOnceAppendsTelemetryHistorySample 2>&1
```

Expected: PASS.

**Step 5: Run AppModel tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests 2>&1
```

Expected: PASS.

**Step 6: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/AppModel.swift Tests/ViftyCoreTests/AppModelTests.swift
git commit -m "feat: collect telemetry history"
```

---

### Task 15: Add a compact latest-telemetry panel

**Objective:** Display the latest telemetry values from the history buffer without adding chart dependencies.

**Files:**
- Modify: `Sources/Vifty/ContentView.swift`
- Test: build + existing model tests.

**Step 1: Add helper view**

In `ContentView.swift`, add this private view near `PowerPanel`:

```swift
private struct HistoryPanel: View {
    let history: TelemetryHistory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("History", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Text("\(history.samples.count) samples")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let latest = history.samples.last {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    if let temp = latest.highestTemperatureCelsius {
                        PowerMetric(label: "Latest temp", value: String(format: "%.1f C", temp), systemImage: "thermometer.medium")
                    }
                    if let rpm = latest.firstFanRPM {
                        PowerMetric(label: "Latest fan", value: "\(rpm) RPM", systemImage: "fan")
                    }
                    if let watts = latest.batteryPowerWatts {
                        PowerMetric(label: "Battery flow", value: PowerDisplayFormatter.watts(abs(watts)), systemImage: watts < 0 ? "arrow.up.circle" : "arrow.down.circle")
                    }
                    PowerMetric(label: "Thermal", value: latest.thermalPressure.displayName, systemImage: "speedometer")
                }
            } else {
                Text("History appears after the first successful poll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
```

YAGNI: this task intentionally avoids `Charts` or custom `Canvas`; the history model is the durable foundation, and the panel only shows latest telemetry values for now.

**Step 2: Render panel in sensors pane**

In `sensorsPane`, after the power panel:

```swift
HistoryPanel(history: model.telemetryHistory)
```

**Step 3: Build**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: PASS.

**Step 4: Run tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/ContentView.swift
git commit -m "feat: show telemetry history panel"
```

---

### Task 16: Add helper health summary in AppModel

**Objective:** Provide a concise helper health summary derived from daemon reachability, fan data, and current errors. The existing `DaemonInstaller.statusText` remains the source for install/approval state in the UI.

**Files:**
- Modify: `Sources/Vifty/AppModel.swift`
- Test: `Tests/ViftyCoreTests/AppModelTests.swift`

**Step 1: Write failing tests**

Add to `AppModelTests`:

```swift
func testHelperHealthSummaryReportsHealthyWhenDaemonAndFansAvailable() {
    let model = AppModel()
    model.daemonReachable = true
    model.snapshot = HardwareSnapshot(
        fans: [Fan(id: 0, name: "Left", currentRPM: 2400, minimumRPM: 1400, maximumRPM: 6000, controllable: true)],
        temperatureSensors: [],
        modelIdentifier: "MacBookPro18,3",
        isAppleSilicon: true,
        isMacBookPro: true
    )

    XCTAssertEqual(model.helperHealthSummary, "Fan helper healthy · 1 fan")
}

func testHelperHealthSummaryReportsUnreachableDaemon() {
    let model = AppModel()
    model.daemonReachable = false
    model.snapshot = HardwareSnapshot(fans: [], temperatureSensors: [], modelIdentifier: "MacBookPro18,3", isAppleSilicon: true, isMacBookPro: true)

    XCTAssertEqual(model.helperHealthSummary, "Fan helper unreachable")
}
```

**Step 2: Run tests to verify failure**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests/testHelperHealthSummary 2>&1
```

Expected: FAIL — property does not exist.

**Step 3: Add computed summary**

Add to `AppModel`:

```swift
var helperHealthSummary: String {
    if let lastError, lastError.contains("Fan helper") {
        return "Fan helper error"
    }
    guard daemonReachable else {
        return "Fan helper unreachable"
    }
    let fanCount = snapshot?.fans.count ?? 0
    guard fanCount > 0 else {
        return "Fan helper reachable · no fan data"
    }
    return "Fan helper healthy · \(fanCount) fan\(fanCount == 1 ? "" : "s")"
}
```

**Step 4: Run tests to verify pass**

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests/testHelperHealthSummary 2>&1
```

If XCTest filtering by partial name does not match both tests, run:

```bash
cd /Users/reidar/Projectos/Vifty && swift test --filter AppModelTests 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/AppModel.swift Tests/ViftyCoreTests/AppModelTests.swift
git commit -m "feat: add fan helper health summary"
```

---

### Task 17: Add helper health panel to the UI

**Objective:** Make helper/XPC health visible and actionable from the main window and menu.

**Files:**
- Modify: `Sources/Vifty/ContentView.swift`
- Modify: `Sources/Vifty/MenuBarView.swift`

**Step 1: Add menu helper status**

In `MenuBarView`, before the `Divider()`, add:

```swift
Label(model.helperHealthSummary, systemImage: model.daemonReachable ? "checkmark.shield" : "xmark.shield")
    .font(.caption)
    .foregroundStyle(model.daemonReachable ? .secondary : .orange)
```

**Step 2: Add main helper panel**

In `ContentView.fanControlPane`, after `modePicker`, add:

```swift
HStack(spacing: 8) {
    Image(systemName: model.daemonReachable ? "checkmark.shield" : "xmark.shield")
        .foregroundStyle(model.daemonReachable ? .green : .orange)
    VStack(alignment: .leading, spacing: 2) {
        Text("Fan Helper")
            .font(.caption.weight(.semibold))
        Text(model.helperHealthSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    Spacer()
    Button("Repair") {
        daemonInstaller.installOrOpenApproval()
    }
    .controlSize(.small)
}
.padding(10)
.background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
```

**Step 3: Build**

```bash
cd /Users/reidar/Projectos/Vifty && swift build 2>&1
```

Expected: PASS.

**Step 4: Run tests**

```bash
cd /Users/reidar/Projectos/Vifty && swift test 2>&1
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add Sources/Vifty/ContentView.swift Sources/Vifty/MenuBarView.swift
git commit -m "feat: show fan helper health"
```

---

### Task 18: Update docs for safety and observability features

**Objective:** Document the new user-facing behavior and keep repo agent instructions current.

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`

**Step 1: Update README highlights**

In `README.md`, update the Highlights list with bullets for:

```markdown
- **Hardware fan state** — shows actual SMC Auto/Forced mode and target RPM when available.
- **Thermal pressure** — surfaces macOS thermal-pressure state alongside raw temperatures.
- **Timed manual modes** — Fixed and Curve modes can automatically restore Auto after a selected duration.
- **Power insights** — estimates battery runtime from live drain and warns when plugged in but still draining.
- **Telemetry history** — keeps a local rolling history for recent temperature, fan, power, and thermal-pressure state.
```

**Step 2: Update README safety section**

Add:

```markdown
- Manual fan modes can be time-limited so Vifty restores Auto automatically.
- The UI distinguishes Vifty's selected mode from the hardware-reported SMC mode when that SMC key is available.
```

**Step 3: Update AGENTS.md**

Update:

- test count after final `swift test`
- key file list with `FanInfoReader.swift`, `ThermalPressure.swift`, `TelemetryHistory.swift`, and `FanDisplayFormatter.swift`
- architecture rule that fan hardware state is read-only telemetry; fan commands still go through `FanControlCoordinator` and daemon/helper paths

**Step 4: Run markdown/file sanity check**

```bash
cd /Users/reidar/Projectos/Vifty && git diff -- README.md AGENTS.md
```

Expected: docs mention only features actually implemented in prior tasks.

**Step 5: Commit**

```bash
cd /Users/reidar/Projectos/Vifty
git add README.md AGENTS.md
git commit -m "docs: document safety observability features"
```

---

### Task 19: Final post-implementation audit and release gate

**Objective:** Verify the full feature tranche across model, parser, XPC, app state, UI, app bundle, installer, and CI.

**Files:**
- Inspect all files modified in Tasks 1-18.
- No code changes unless audit finds blockers.

**Step 1: Audit every modified file**

Run:

```bash
cd /Users/reidar/Projectos/Vifty
git diff --name-only origin/main...HEAD
```

For every changed Swift file, read the file and check:

- Optional SMC values stay optional and never fabricate `Auto`/`0 RPM` when keys are absent.
- `FanHardwareMode.rawValue` and XPC `hardwareMode` use the same raw integer contract.
- XPC encode/decode preserves nils and does not reject older daemon snapshots missing the new keys.
- Timed manual-mode expiry calls `coordinator.setMode(.auto)` and does not only change `selectedMode`.
- Any `manualSessionExpiresAt` is cleared after restore Auto.
- `PowerInsights` uses signed watts correctly: negative = drain, positive = charge.
- Thermal pressure is independent from raw temperature sensors.
- History is in-memory only; no new persistence or privacy surface was introduced.
- UI labels do not claim a helper is healthy when daemon is reachable but fan data is empty.

**Step 2: Run full local gate**

```bash
cd /Users/reidar/Projectos/Vifty
swift test
make app CONFIGURATION=release
codesign --verify --deep --strict .build/Vifty.app
rm -rf .build/ci-install
VIFTY_INSTALL_DIR="$PWD/.build/ci-install" make install
codesign --verify --deep --strict .build/ci-install/Vifty.app
cmp .build/Vifty.app/Contents/MacOS/Vifty .build/ci-install/Vifty.app/Contents/MacOS/Vifty
```

Expected:

- `swift test`: all tests pass.
- release app builds.
- both app bundles verify with `codesign`.
- installed temp bundle binary matches `.build/Vifty.app`.

**Step 3: Launch installed local app for smoke verification**

Only if user wants local install updated immediately:

```bash
open /Applications/Vifty.app
pgrep -fl '/Applications/Vifty.app/Contents/MacOS/Vifty' || true
```

Expected: Vifty process is running if launched. Do not force-quit an existing Vifty process without explicit user approval.

**Step 4: Push and verify GitHub Actions for exact SHA**

```bash
cd /Users/reidar/Projectos/Vifty
git status --short
git push
SHA=$(git rev-parse HEAD)
git fetch origin main --quiet
test "$(git rev-parse origin/main)" = "$SHA"
RUN_ID=$(gh run list --commit "$SHA" --json databaseId,workflowName,status,conclusion,headSha --limit 10 --jq '.[] | select(.workflowName == "CI" and .headSha == "'"$SHA"'") | .databaseId' | head -1)
test -n "$RUN_ID"
gh run watch "$RUN_ID" --exit-status
gh run view "$RUN_ID" --json databaseId,workflowName,status,conclusion,headSha,url,jobs
```

Expected: exact pushed SHA has `workflowName=CI`, `status=completed`, `conclusion=success`, `headSha=$SHA`.

**Step 5: Commit audit fixes if needed**

If audit finds blockers, do not fold silent fixes into previous commits. Add a focused RED test for each blocker, fix it, rerun targeted test + full gate, and commit:

```bash
cd /Users/reidar/Projectos/Vifty
git add <fixed files>
git commit -m "fix: address safety observability audit findings"
```

Then repeat Steps 1-4 for the new SHA.

---

## Plan review history

- Initial planner review: read `AGENTS.md`, `README.md`, `Package.swift`, current `Models.swift`, `HardwareService.swift`, `RealMacHardwareService.swift`, `ViftyDaemonProtocol.swift`, `ViftyDaemon/main.swift`, `AppModel.swift`, `ContentView.swift`, `MenuBarView.swift`, `SMCClient.swift`, `PowerInfo.swift`, `DaemonInstaller.swift`, current CI workflow, and existing tests.
- SPM cross-target check: `Package.swift` already lists `"Vifty"` in `ViftyCoreTests` dependencies; no Package.swift dependency task is required for AppModel/UI tests that import `Vifty`.
- Runtime heartbeat audit: tasks touching fan model/XPC/Auto state include targeted encode/decode tests, coordinator/AppModel tests, and final audit checks.
- Independent review 1 verdict: `REQUEST_CHANGES`. Blockers found: `ManualRunLimit` missing `Hashable`, timed manual test racing unstructured `Task`, timed expiry not proving hardware restore, Task 16 objective overpromising installer state, hazardous XPC optional payload snippet, missing old-snapshot XPC decode test, and latest-values panel described as a trend.
- Patch after review 1: added `Hashable`, introduced awaitable `applyCurrentModeSelection()`, added fake-hardware restore assertions, narrowed helper-health scope, replaced XPC payload snippet with optional-friendly dictionary construction, added backward-compatible XPC decode test, and renamed latest telemetry wording.
- Focused review 2 verdict: `REQUEST_CHANGES`. Remaining issue: explicit menu/UI Auto path could leave a timed manual deadline visible because only expiry cleared it; minor UX note that users should be able to choose duration before switching manual mode.
- Patch after review 2: added `restoreAutoNow()` and explicit Auto deadline-clearing test, changed `restoreAuto()` to wrap the awaitable helper, removed remaining trend wording, and made the manual-run picker visible while Auto is selected so the desired duration can be chosen before selecting Fixed/Curve.
- Focused review 3 verdict: `REQUEST_CHANGES`. Remaining issue: the manual-run picker was visible under Auto but disabled, contradicting the pre-selection UX goal.
- Patch after review 3: removed `.disabled(model.selectedMode == .auto)` so the picker is visible and usable while Auto is selected.
- Focused review 4 verdict: `APPROVED`; no remaining critical blockers, important issues, or minor nits in the reviewed blocker classes.
- Scope decision: this plan intentionally avoids persistent telemetry history, Charts dependency, Sparkle auto-update, signed/notarized release distribution, battery charge limiting, and real helper log streaming. Those are follow-up projects.

## Execution handoff

Use `subagent-driven-development` if executing this plan. Dispatch tasks sequentially for model/XPC/AppModel tasks because they touch shared files and can create git commit races. UI-only tasks can be direct parent execution if the diff is small. Run the two-stage review after each non-trivial task: spec compliance first, then code quality. After every subagent, the controller must verify `git status --short`, `git log --oneline -3`, and the exact files changed before marking a task complete.
