# Vifty Open Issues Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Close all three open GitHub issues (#1, #2, #4) for Vifty.

**Architecture:** Issue #1 is likely already fixed by our recent viftyctl run implementation (Task 14) and needs verification only. Issue #4 (rate limiting) is a focused daemon-side change. Issue #2 (per-fan curves) is a larger feature requiring model/store/UI/XPC changes and should be implemented after #1 and #4.

**Tech Stack:** Swift 6, SPM, XCTest, macOS 15+

---

## Issue #1: viftyctl run should propagate child exit code (#1)

**Status:** Likely already fixed. Our Task 14 implementation correctly propagates exit codes.

**Evidence:**
- `ViftyCtlRunner.run()` at line 75: `let exitCode = try processRunner.run(childArguments)` captures the child exit code
- Line 77: `return ViftyCtlResult(exitCode: exitCode)` returns it
- `ViftyCtlMain.main()` at line 13: `exit(result.exitCode)` exits with the child's code
- Test `testRunPreparesRunsChildRestoresAndReturnsChildExitCode` verifies exit code 7 propagates correctly

### Task 1: Verify and close issue #1

**Objective:** Confirm viftyctl run propagates exit codes correctly, then close the issue.

**Files:**
- No source changes needed (verification only)

**Step 1: Run the existing test**

```bash
swift test --filter ViftyCtlRunnerTests/testRunPreparesRunsChildRestoresAndReturnsChildExitCode
```

Expected: PASS — exit code 7 propagates through the runner.

**Step 2: Build release and test manually**

```bash
make app CONFIGURATION=release
.build/Vifty.app/Contents/MacOS/viftyctl run --workload test --duration 1m --max-rpm-percent 70 --reason test -- /usr/bin/false
echo "exit=$?"
```

Expected: exit code reflects the child process (will fail because daemon isn't running locally, but proves the runner doesn't always exit 0).

**Step 3: Close the issue**

If the test passes and the code is correct, close issue #1 with a comment explaining that the current implementation correctly propagates exit codes via `ViftyCtlResult.exitCode`.

---

## Issue #4: Add lease rate-limiting for viftyctl prepare (#4)

**Goal:** Add a configurable cooldown (default 30s) between successive `prepare` calls. Repeated calls within the window return a structured error with retry-after metadata.

### Task 2: Add rate-limit model and AgentControlErrorCode

**Objective:** Add `prepareRateLimited` error code and rate-limit configuration to `AgentControlPolicy`.

**Files:**
- Modify: `Sources/ViftyCore/AgentControlModels.swift` — add `case prepareRateLimited` to `AgentControlErrorCode`
- Modify: `Sources/ViftyCore/AgentControlPolicy.swift` — add `prepareCooldownSeconds: Int` property (default 30)

**Step 1: Add error code**

In `AgentControlModels.swift`, find the `AgentControlErrorCode` enum and add:
```swift
case prepareRateLimited
```

**Step 2: Add policy configuration**

In `AgentControlPolicy.swift`, add to the struct:
```swift
public var prepareCooldownSeconds: Int
```

Update the `init` with default value 30.

**Step 3: Build**

```bash
swift build -Xswiftc -warnings-as-errors
```

Expected: clean build.

**Step 4: Commit**

```bash
git add Sources/ViftyCore/AgentControlModels.swift Sources/ViftyCore/AgentControlPolicy.swift
git commit -m "feat: add rate-limit configuration and error code for agent prepare"
```

---

### Task 3: Implement rate-limit enforcement in AgentControlService

**Objective:** Track last prepare timestamp per client; reject prepare calls within the cooldown window.

**Files:**
- Modify: `Sources/ViftyCore/AgentControlService.swift`
- Modify: `Tests/ViftyCoreTests/AgentControlServiceTests.swift`

**Step 1: Write RED tests**

Add two tests to `AgentControlServiceTests.swift`:

```swift
func testPrepareIsRateLimitedWithinCooldownWindow() async throws {
    let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
        Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 6000)
    ]))
    let policy = AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30)
    var currentTime = Date(timeIntervalSince1970: 1000)
    let store = AgentControlStore(directory: temporaryDirectory())
    let service = AgentControlService(
        hardware: hardware, policy: policy, store: store,
        thermalReader: { .nominal },
        now: { currentTime },
        leaseID: { UUID().uuidString }
    )

    let request1 = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "first", idempotencyKey: "key-1")
    _ = try await service.prepare(request1)

    // Restore to clear the active lease
    _ = try await service.restoreAuto(reason: "done")

    // Try another prepare within cooldown window
    currentTime = currentTime.addingTimeInterval(10) // only 10s later, cooldown is 30s
    let request2 = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "second", idempotencyKey: "key-2")
    let status2 = try await service.prepare(request2)

    XCTAssertNil(status2.activeLease)
    XCTAssertEqual(status2.lastErrorCode, .prepareRateLimited)
}

func testPrepareAllowedAfterCooldownExpires() async throws {
    let hardware = AgentServiceFakeHardware(snapshot: Self.snapshot(fans: [
        Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 6000)
    ]))
    let policy = AgentControlPolicy(enabled: true, prepareCooldownSeconds: 30)
    var currentTime = Date(timeIntervalSince1970: 1000)
    let store = AgentControlStore(directory: temporaryDirectory())
    let service = AgentControlService(
        hardware: hardware, policy: policy, store: store,
        thermalReader: { .nominal },
        now: { currentTime },
        leaseID: { UUID().uuidString }
    )

    let request1 = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "first", idempotencyKey: "key-1")
    _ = try await service.prepare(request1)
    _ = try await service.restoreAuto(reason: "done")

    // Advance past cooldown
    currentTime = currentTime.addingTimeInterval(31)
    let request2 = AgentControlRequest(workload: .build, durationSeconds: 600, maxRPMPercent: 70, reason: "second", idempotencyKey: "key-2")
    let status2 = try await service.prepare(request2)

    XCTAssertNotNil(status2.activeLease)
    XCTAssertNil(status2.lastErrorCode)
}
```

**Step 2: Run tests to verify failure**

```bash
swift test --filter AgentControlServiceTests/testPrepareIsRateLimitedWithinCooldownWindow
```

Expected: FAIL — no rate limiting logic exists yet.

**Step 3: Implement rate limiting**

In `AgentControlService`, add a private property:
```swift
private var lastPrepareCompletedAt: Date?
```

In `prepare()`, after the existing checks but before applying targets, add:
```swift
if let lastPrepare = lastPrepareCompletedAt,
   now().timeIntervalSince(lastPrepare) < Double(policy.prepareCooldownSeconds) {
    let remaining = policy.prepareCooldownSeconds - Int(now().timeIntervalSince(lastPrepare))
    let decision = AgentControlDecision.denied(
        .prepareRateLimited,
        message: "Prepare rate-limited. Wait \(remaining)s between prepare calls."
    )
    lastDecision = decision
    lastErrorCode = decision.errorCode
    appendAudit(action: "prepare-rate-limited", leaseID: nil, message: decision.message)
    return status()
}
```

After a successful prepare (after the `scheduleMonitor(for: lease)` call), update:
```swift
lastPrepareCompletedAt = now()
```

Also update in `restoreAuto(reason:snapshot:)` — no change needed there, the cooldown starts from the prepare time.

**Step 4: Run tests**

```bash
swift test --filter AgentControlServiceTests
```

Expected: all tests pass (13 existing + 2 new = 15).

**Step 5: Commit**

```bash
git add Sources/ViftyCore/AgentControlService.swift Tests/ViftyCoreTests/AgentControlServiceTests.swift
git commit -m "feat: enforce configurable prepare cooldown in agent control service"
```

---

### Task 4: Advertise cooldown in capabilities and add --force flag

**Objective:** `viftyctl capabilities --json` includes the cooldown. `viftyctl prepare` accepts `--force` to bypass rate limiting (for human use).

**Files:**
- Modify: `Sources/ViftyCore/ViftyCtlRunner.swift` — add cooldown to capabilities output
- Modify: `Sources/ViftyCore/ViftyCtlArguments.swift` — add `--force` flag to prepare
- Modify: `Tests/ViftyCoreTests/ViftyCtlArgumentsTests.swift` — test --force parsing

**Step 1: Add --force to ViftyCtlCommand**

In `ViftyCtlArguments.swift`, add `force: Bool` to the `.prepare` command case:
```swift
case prepare(AgentControlRequest, json: Bool, force: Bool)
```

Parse `--force` as a flag in the prepare parser.

**Step 2: Pass force through the runner**

In `ViftyCtlRunner.run()`, when handling `.prepare`, pass the force flag. If force is true, the client can send a special request that bypasses cooldown (the daemon handles this).

Actually, the simplest approach: if `--force` is set, the runner makes the prepare call regardless — the daemon's rate limiter checks the force flag. But the XPC protocol would need to carry the force flag.

Alternative simpler approach: `--force` just makes the CLI re-attempt once if rate-limited, by sleeping for the remaining cooldown and retrying. This avoids protocol changes.

**Step 3: Add cooldown to capabilities**

In `ViftyCtlRunner.run()` for `.capabilities`, add "prepareCooldownSeconds" from the policy. But the runner doesn't have direct access to the policy — it gets it from the daemon's status. Add a field to `AgentControlStatus` or return it via capabilities.

Simplest: hardcode a reasonable default in capabilities until the daemon returns it. Or read from `client.status().enabled` + add a cooldown field.

For now, add cooldown to capabilities as a hardcoded 30 (matching the policy default) with a TODO to read from daemon.

**Step 4: Run tests**

```bash
swift test --filter ViftyCtlArgumentsTests
swift test --filter ViftyCtlRunnerTests
```

Expected: all pass.

**Step 5: Commit**

```bash
git add Sources/ViftyCore/ViftyCtlArguments.swift Sources/ViftyCore/ViftyCtlRunner.swift Tests/ViftyCoreTests/ViftyCtlArgumentsTests.swift
git commit -m "feat: add --force flag and cooldown to capabilities output"
```

---

### Task 5: Add policy test for cooldown configuration

**Objective:** Verify the policy cooldown defaults and custom values.

**Files:**
- Modify: `Tests/ViftyCoreTests/AgentControlPolicyTests.swift`

**Step 1: Add test**

```swift
func testPolicyCooldownDefaultAndCustom() {
    let defaultPolicy = AgentControlPolicy(enabled: true)
    XCTAssertEqual(defaultPolicy.prepareCooldownSeconds, 30)

    let customPolicy = AgentControlPolicy(enabled: true, prepareCooldownSeconds: 10)
    XCTAssertEqual(customPolicy.prepareCooldownSeconds, 10)
}
```

**Step 2: Run tests**

```bash
swift test --filter AgentControlPolicyTests
```

Expected: all pass.

**Step 3: Commit**

```bash
git add Tests/ViftyCoreTests/AgentControlPolicyTests.swift
git commit -m "test: verify agent control policy cooldown defaults"
```

---

### Task 6: Close issue #4

After all rate-limiting tasks are committed and pushed, close issue #4 with a summary of the implementation.

---

## Issue #2: Support per-fan independent curve profiles (#2)

**Goal:** Allow users to define separate temperature curves for each fan, instead of applying the same curve to all fans.

### Task 7: Add optional per-fan overrides to CurveProfile model

**Objective:** Extend `CurveProfile` with optional per-fan curve overrides. Existing profiles with a single curve continue to work (backward compatible).

**Files:**
- Modify: `Sources/ViftyCore/Models.swift:234-283`
- Modify: `Tests/ViftyCoreTests/CurveProfileTests.swift`

**Step 1: Add per-fan override type**

In `Models.swift`, add before `CurveProfile`:

```swift
public struct FanCurveOverride: Codable, Equatable, Sendable {
    public var fanID: Int
    public var startRPM: Int
    public var midRPM: Int
    public var maxRPM: Int

    public init(fanID: Int, startRPM: Int, midRPM: Int, maxRPM: Int) {
        self.fanID = fanID
        self.startRPM = startRPM
        self.midRPM = midRPM
        self.maxRPM = maxRPM
    }
}
```

**Step 2: Add to CurveProfile**

Add to `CurveProfile`:
```swift
public var fanOverrides: [FanCurveOverride]
```

Update `init` with default `fanOverrides: [FanCurveOverride] = []`.

**Step 3: Add RED test**

```swift
func testCurveProfileEncodesPerFanOverrides() throws {
    let profile = CurveProfile(
        name: "Custom",
        startTemp: 40, startRPM: 2000,
        midTemp: 60, midRPM: 4000,
        maxTemp: 85, maxRPM: 5500,
        fanOverrides: [FanCurveOverride(fanID: 1, startRPM: 2200, midRPM: 4200, maxRPM: 5800)]
    )
    XCTAssertEqual(profile.fanOverrides.count, 1)
    XCTAssertEqual(profile.fanOverrides[0].fanID, 1)
    XCTAssertEqual(profile.fanOverrides[0].maxRPM, 5800)

    // Round-trip through JSON
    let data = try JSONEncoder().encode(profile)
    let decoded = try JSONDecoder().decode(CurveProfile.self, from: data)
    XCTAssertEqual(decoded.fanOverrides.count, 1)
}
```

**Step 4: Ensure backward compatibility**

A profile loaded from JSON without `fanOverrides` should decode with an empty array. Add test:
```swift
func testCurveProfileDecodesWithoutFanOverrides() throws {
    let json = """
    {"id":"00000000-0000-0000-0000-000000000001","name":"Legacy","startTemp":40,"startRPM":2000,"midTemp":60,"midRPM":4000,"maxTemp":85,"maxRPM":5500}
    """
    let profile = try JSONDecoder().decode(CurveProfile.self, from: Data(json.utf8))
    XCTAssertEqual(profile.fanOverrides, [])
}
```

**Step 5: Run tests**

```bash
swift test --filter CurveProfileTests
```

Expected: all pass (3 existing + 2 new = 5).

**Step 6: Commit**

```bash
git add Sources/ViftyCore/Models.swift Tests/ViftyCoreTests/CurveProfileTests.swift
git commit -m "feat: add optional per-fan curve overrides to curve profile model"
```

---

### Task 8: Resolve per-fan curves in FanControlCoordinator

**Objective:** When a curve profile has per-fan overrides, the coordinator uses the override RPM values for that fan instead of the shared curve.

**Files:**
- Modify: `Sources/ViftyCore/HardwareService.swift` (FanControlCoordinator)
- Modify: `Tests/ViftyCoreTests/FanControlCoordinatorTests.swift`

**Step 1: Write RED test**

Add a test where the coordinator resolves a curve with a per-fan override for fan 1:
```swift
func testCurveWithPerFanOverrideAppliesDifferentRPMs() async throws {
    let hardware = FakeHardware(snapshot: Self.snapshot(fans: [
        Self.fan(id: 0, minimumRPM: 1500, maximumRPM: 6000),
        Self.fan(id: 1, minimumRPM: 1500, maximumRPM: 4500)
    ]))
    let coordinator = FanControlCoordinator(hardware: hardware)
    let curve = FanCurve(sensorID: nil, points: [
        CurvePoint(temperatureCelsius: 40, rpm: 2000),
        CurvePoint(temperatureCelsius: 60, rpm: 4000),
        CurvePoint(temperatureCelsius: 85, rpm: 5500)
    ])
    let overrides = [FanCurveOverride(fanID: 1, startRPM: 2200, midRPM: 4200, maxRPM: 4500)]

    try await coordinator.applyCurveWithOverrides(curve, fanOverrides: overrides, temperature: 60)

    let commands = await hardware.appliedCommands
    // Fan 0 uses the shared curve: 4000 RPM at 60°C
    // Fan 1 uses the override: 4200 RPM at 60°C
    XCTAssertEqual(commands.count, 2)
    XCTAssertTrue(commands.contains(FanCommand(fanID: 0, mode: .fixedRPM(4000))))
    XCTAssertTrue(commands.contains(FanCommand(fanID: 1, mode: .fixedRPM(4200))))
}
```

**Step 2: Implement**

Add a new method to `FanControlCoordinator`:
```swift
func applyCurveWithOverrides(_ curve: FanCurve, fanOverrides: [FanCurveOverride], temperature: Double) async throws {
    let snapshot = try await hardware.snapshot()
    let overridesByID = Dictionary(uniqueKeysWithValues: fanOverrides.map { ($0.fanID, $0) })

    for fan in snapshot.fans where fan.controllable {
        let rpm: Int
        if let override = overridesByID[fan.id] {
            // Use per-fan override with the same temperature interpolation
            let overrideCurve = FanCurve(sensorID: curve.sensorID, points: [
                CurvePoint(temperatureCelsius: curve.points[0].temperatureCelsius, rpm: override.startRPM),
                CurvePoint(temperatureCelsius: curve.points[1].temperatureCelsius, rpm: override.midRPM),
                CurvePoint(temperatureCelsius: curve.points[2].temperatureCelsius, rpm: override.maxRPM)
            ])
            rpm = FanCurve.clamp(overrideCurve.interpolatedRPM(at: temperature), fan.minimumRPM, fan.maximumRPM)
        } else {
            rpm = FanCurve.clamp(curve.interpolatedRPM(at: temperature), fan.minimumRPM, fan.maximumRPM)
        }
        try await hardware.apply(FanCommand(fanID: fan.id, mode: .fixedRPM(rpm)), fan: fan)
    }
}
```

**Step 3: Run tests**

```bash
swift test --filter FanControlCoordinatorTests
```

Expected: all pass (7 existing + 1 new = 8).

**Step 4: Commit**

```bash
git add Sources/ViftyCore/HardwareService.swift Tests/ViftyCoreTests/FanControlCoordinatorTests.swift
git commit -m "feat: resolve per-fan curve overrides in fan control coordinator"
```

---

### Task 9: Add per-fan override UI in curve profile editor

**Objective:** Add a toggle and per-fan RPM sliders in the curve profile editor (`ContentView.swift`).

**Files:**
- Modify: `Sources/Vifty/ContentView.swift`

**Step 1: Read the current curve editor UI**

Find the `CurvePointEditor` or equivalent view in ContentView.swift.

**Step 2: Add per-fan toggle**

After the existing curve sliders, add a section:
```swift
if fans.count > 1 {
    Toggle("Per-fan overrides", isOn: $profile.hasPerFanOverrides)
    if profile.hasPerFanOverrides {
        ForEach(fans) { fan in
            Section("Fan \(fan.id): \(fan.name)") {
                // RPM sliders for this fan using override values
            }
        }
    }
}
```

**Step 3: Build and test**

```bash
swift build
swift test
```

Expected: build clean, all tests pass.

**Step 4: Commit**

```bash
git add Sources/Vifty/ContentView.swift
git commit -m "feat: add per-fan curve override toggle in profile editor"
```

---

### Task 10: Close issue #2

After all per-fan curve tasks are committed and pushed, close issue #2 with a summary.

---

## Execution order

1. **Task 1** — Verify and close #1 (quick, likely no code changes)
2. **Tasks 2–6** — Rate limiting for #4 (self-contained, 5 tasks)
3. **Tasks 7–10** — Per-fan curves for #2 (larger feature, 4 tasks)

## Closeout verification

```bash
cd /Users/reidar/Projectos/Vifty
swift test
swift build -Xswiftc -warnings-as-errors
make app CONFIGURATION=release
codesign --verify --deep --strict .build/Vifty.app
git status --short
```

Expected: 0 failures, clean build, clean tree.
