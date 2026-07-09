# Vifty Safety, Efficiency, and Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement confirmed Auto restoration on every quit path, durable notification coalescing, bounded Codex refresh, runtime observability, and native Settings/workbench behavior.

**Architecture:** Add small pure result/policy/store types around the existing `AppModel` and `FanControlCoordinator`, then wire AppKit termination and SwiftUI scenes through those contracts. Preserve existing hardware write boundaries and polling cadence while adding measurements and removing redundant work.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, AppKit, UserNotifications, OSLog, XCTest, shell/Makefile release tooling.

## Global Constraints

- Worktree: `/Users/reidar/Projectos/.codex-worktrees/vifty-safety-efficiency-workbench`.
- Use `swift test --scratch-path "$PWD/.build"` and `swift build --scratch-path "$PWD/.build"`.
- Before long test loops, require at least 50Gi free on `/System/Volumes/Data`.
- Do not run helper repair/install, fan writes, cooling leases, Auto restore, or live mode smoke.
- Preserve daemon-first fail-closed fan writes, the SMC allowlist, `FanCurve.clamp()`, and lease-based agent control.
- Preserve the source-first/Developer ID boundary and commit no certificate or secret material.
- Use TDD for behavior changes and `apply_patch` for manual edits.

---

### Task 1: Confirmed Auto Restore And Termination Coordination

**Files:**
- Modify: `Sources/ViftyCore/HardwareService.swift`
- Create: `Sources/Vifty/AppTerminationCoordinator.swift`
- Modify: `Sources/Vifty/AppModel.swift`
- Modify: `Sources/Vifty/ViftyApp.swift`
- Modify: `Sources/Vifty/MenuBarView.swift`
- Modify: `Tests/ViftyCoreTests/FanControlCoordinatorTests.swift`
- Create: `Tests/ViftyCoreTests/AppTerminationCoordinatorTests.swift`
- Modify: `Tests/ViftyCoreTests/AppModelTests.swift`

**Interfaces:**
- Produce: `public enum AutoRestoreResult: Sendable, Equatable`
- Produce: `enum AppTerminationRestoreResult: Equatable`
- Produce: `AppTerminationCoordinator.beginTermination(using:completion:) -> Bool`
- Change: `AppModel.stopAndRestore() async -> AppTerminationRestoreResult`

- [ ] Add failing coordinator tests for `.restored` and `.failed(message:)`.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter FanControlCoordinatorTests` and confirm RED.
- [ ] Implement `AutoRestoreResult` and make `forceAuto()` return it without weakening state cleanup.
- [ ] Add failing tests for one in-flight termination, success reply, and failure cancellation.
- [ ] Run `swift test --scratch-path "$PWD/.build" --filter AppTerminationCoordinatorTests` and confirm RED.
- [ ] Implement the pure coordinator and wire `applicationShouldTerminate` to `.terminateLater`.
- [ ] Make failed termination reopen the main window and preserve visible error state.
- [ ] Remove the custom menu Quit restore duplication; call `terminate(nil)` only.
- [ ] Run the three focused suites and warnings-as-errors build.
- [ ] Commit as `fix: confirm auto restore before quitting`.

### Task 2: Durable Notification Coalescing

**Files:**
- Modify: `Sources/Vifty/LocalNotifications.swift`
- Create: `Sources/Vifty/LocalNotificationHistoryStore.swift`
- Modify: `Sources/Vifty/AppModel.swift`
- Create: `Tests/ViftyCoreTests/LocalNotificationHistoryStoreTests.swift`
- Modify: `Tests/ViftyCoreTests/AppModelTests.swift`
- Modify: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Produce: `LocalNotification.requestIdentifier`
- Produce: `LocalNotificationHistoryStore.lastDeliveredAt(for:)`
- Produce: `LocalNotificationHistoryStore.recordDelivery(of:at:)`
- Produce: `LocalNotificationTransitionState` with baseline-aware transition methods.

- [ ] Write failing tests for stable kind identifiers, persisted cooldown, private permissions, and first-observation suppression.
- [ ] Run the new store and AppModel notification tests and confirm RED.
- [ ] Implement atomic private JSON persistence and stable request identifiers.
- [ ] Replace in-memory timestamp ownership with the store and baseline-aware transition state.
- [ ] Keep explicit Auto-restore failure notifications immediate and cooldown-aware.
- [ ] Run focused notification/preferences suites and warnings-as-errors build.
- [ ] Commit as `fix: coalesce local notifications across launches`.

### Task 3: Remove Runtime Faults And Add Safe Developer Launch

**Files:**
- Modify: `Sources/Vifty/ContentView.swift`
- Create: `scripts/build-and-run-vifty.sh`
- Modify: `Makefile`
- Modify: `README.md`
- Modify: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`
- Modify: `Tests/ViftyCoreTests/DocumentationTrustSurfaceTests.swift`

- [ ] Add failing source/docs tests that reject `thermometer.slash`, require the bundled launcher, and forbid direct raw GUI launch guidance.
- [ ] Run both focused suites and confirm RED.
- [ ] Replace the SF Symbol with `thermometer.medium`.
- [ ] Add a bounded launcher that runs `make app`, then `open .build/Vifty.app`, without helper or fan actions.
- [ ] Add `make run-app` and document the bundled path.
- [ ] Run shell syntax, focused tests, and warnings-as-errors build.
- [ ] Commit as `fix: make local app launch bundle-safe`.

### Task 4: Bound Codex Usage Child Processes

**Files:**
- Modify: `Sources/Vifty/CodexUsage.swift`
- Modify: `Tests/ViftyCoreTests/CodexUsageTests.swift`

**Interfaces:**
- Add: `terminationGracePeriod: TimeInterval` to `CodexUsageAppServerClient.init`.
- Add: bounded process-exit wait helper returning whether the child exited.

- [ ] Add a failing test with a script that ignores `TERM`; assert `read()` returns within response timeout plus grace.
- [ ] Run `CodexUsageTests` and confirm RED because `waitUntilExit()` blocks.
- [ ] Replace unbounded exit waiting with a semaphore-backed bounded grace wait.
- [ ] Close pipes and return `nil` without blocking when the child survives the grace period.
- [ ] Run `CodexUsageTests` and warnings-as-errors build.
- [ ] Commit as `fix: bound Codex usage process shutdown`.

### Task 5: Runtime Logging And Poll Scheduling

**Files:**
- Create: `Sources/Vifty/ViftyLog.swift`
- Create: `Sources/Vifty/PollSchedulePolicy.swift`
- Modify: `Sources/Vifty/AppModel.swift`
- Modify: `Sources/ViftyCore/ViftyDaemonClient.swift`
- Create: `Tests/ViftyCoreTests/PollSchedulePolicyTests.swift`
- Modify: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Produce privacy-safe `ViftyLog.lifecycle`, `.polling`, `.xpc`, `.notifications`, `.fanControl`, `.codexUsage`.
- Produce `PollSchedulePolicy.delay(afterInitialPollFor:)` and preserve 5s/10s values.

- [ ] Add failing tests proving the first loop sleeps after the initial poll and preserves active/idle intervals.
- [ ] Run the policy suite and confirm RED.
- [ ] Implement the policy and remove the immediate duplicate poll after `start()`.
- [ ] Add begin/end/outcome logs around polling, XPC requests, notification delivery, termination, and Codex refresh without private values.
- [ ] Keep per-request XPC connections and current cadence unchanged.
- [ ] Run focused suites and warnings-as-errors build.
- [ ] Commit as `perf: instrument and de-duplicate polling`.

### Task 6: Native Settings Scene And Wide Telemetry Reflow

**Files:**
- Create: `Sources/Vifty/ViftySettingsView.swift`
- Create: `Sources/Vifty/TelemetryLayoutPolicy.swift`
- Modify: `Sources/Vifty/ViftyApp.swift`
- Modify: `Sources/Vifty/ContentView.swift`
- Modify: `Sources/Vifty/SettingsToolsPanel.swift`
- Create: `Tests/ViftyCoreTests/TelemetryLayoutPolicyTests.swift`
- Modify: `Tests/ViftyCoreTests/MainWindowSectionPlacementTests.swift`
- Modify: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Produce `TelemetryLayoutPolicy.metricColumnCount(for:)`.
- Produce a `Settings` scene sharing the existing `AppModel`.
- Change the left-rail Settings & Tools section into a command button that opens Settings.

- [ ] Add failing policy tests for 2, 3, and 4 metric columns at compact, workbench, and ultrawide widths.
- [ ] Add failing source tests for the Settings scene and left-rail `SettingsLink`.
- [ ] Implement the adaptive telemetry metric grid.
- [ ] Move settings content into `ViftySettingsView` and add the native scene.
- [ ] Remove the large spacer/inline disclosure from the workbench rail.
- [ ] Run layout/source/AppModel focused suites and warnings-as-errors build.
- [ ] Commit as `feat: move tools into native settings`.

### Task 7: Release Boundary, Full Verification, And Evidence

**Files:**
- Modify only if needed: `docs/release-status.md`, `docs/release.md`, `docs/competitive-analysis.md`
- Update: Obsidian daily and project notes outside the repository.

- [ ] Run `git diff --check` and shell syntax checks.
- [ ] Run `make verify SWIFT_BUILD_PATH="$PWD/.build"`.
- [ ] Recheck disk space, then run `make verify-full SWIFT_BUILD_PATH="$PWD/.build"`.
- [ ] Confirm ad-hoc hardened-runtime signing remains source-first and no TeamID/notarization claim was introduced.
- [ ] Review the complete branch diff for safety, notification, privacy, and UI regressions.
- [ ] Record exact evidence and non-claims in Obsidian.
- [ ] Commit any final docs/test alignment as `docs: record Vifty safety readiness`.
