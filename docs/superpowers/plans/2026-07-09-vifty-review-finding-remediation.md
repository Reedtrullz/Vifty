# Vifty Review Finding Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Vifty more efficient and more desktop-native by removing menu-bar telemetry polling bursts, using wide workbench windows better, replacing brittle source-string UI assertions with behavioral seams, and preserving the Developer ID/source-first trust boundary.

**Architecture:** Keep hardware control untouched and move UI/runtime policy into small pure Swift types that can be tested without launching the app, repairing helpers, or writing fan state. Use macOS SwiftUI desktop patterns by separating the root layout from focused panels, layout policy, status-item policy, and chart geometry. Release readiness remains evidence-based: source-first and Developer ID notarized lanes stay separate until the intended TeamID is active and verifier output passes.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI, AppKit `NSStatusItem`, XCTest, existing Makefile release and verification scripts.

## Global Constraints

- Repository root: `/Users/reidar/Projectos/Vifty`.
- Swift Package Manager is the build system; use `swift test --scratch-path "$PWD/.build"` and `swift build --scratch-path "$PWD/.build"`.
- Before long build/test loops, run `df -h /System/Volumes/Data` and stop if free space is below 50Gi.
- Do not run helper repair, helper install, fan writes, cooling leases, or Auto restore as part of this plan unless the user explicitly asks for live hardware validation.
- Preserve daemon-first fail-closed write behavior and the SMC write allowlist.
- Preserve `FanCurve.clamp()` as the single source of RPM clamping.
- Preserve source-first versus Developer ID release separation: no Homebrew cask promotion, no Sparkle enablement, no notarization claims, and no certificate material in git until the intended Developer ID team is active and release evidence passes.
- Use `apply_patch` for manual source edits; do not revert unrelated dirty worktree changes.
- Keep commits scoped by task.
- Keep generated scratch output bounded under `.build` or `.derivedData`.
- At the end of meaningful execution work, log concise evidence to Obsidian daily and project notes.

---

## Findings This Plan Fixes

1. `ViftyStatusItemController` can run up to 120 launch telemetry prime attempts with a fixed 750 ms delay, while `ViftyApp` also launches two 5-attempt prime loops. That is too aggressive for an app whose first complaint was resource usage and noisy notifications.
2. The workbench layout caps the editor at 760 px and telemetry at 1000 px, leaving ultrawide windows underused even though the UI has three logical panels.
3. Important layout behavior is pinned through source-string tests in `AppSourceRegressionTests`, which makes refactors risky and hides whether the actual layout policy is correct.
4. The curve chart is visually improved, but its geometry and label decisions are still embedded in a large SwiftUI view instead of testable pure policy.
5. `ContentView.swift` is about 2294 lines and `AppModel.swift` is about 2558 lines, which makes small UI work expensive and error-prone.
6. Developer ID release readiness is intentionally blocked until the intended Apple Developer team is active; implementation must not weaken this trust boundary while cleaning up the UI.

## File Structure

Create:

- `Sources/Vifty/MenuBarTelemetryPrimePolicy.swift` - pure policy for status-item launch and popover telemetry priming.
- `Tests/ViftyCoreTests/MenuBarTelemetryPrimePolicyTests.swift` - focused tests for attempt caps, completed-poll stopping, and retry backoff.
- `Sources/Vifty/MainWindowSectionPlacement.swift` - pure mapping of sections to panes for stacked, split, and workbench layouts.
- `Tests/ViftyCoreTests/MainWindowSectionPlacementTests.swift` - behavioral tests that replace source-substring layout assertions.
- `Sources/Vifty/FanCurveChartGeometry.swift` - pure chart coordinate, drag, and live-target calculations.
- `Tests/ViftyCoreTests/FanCurveChartGeometryTests.swift` - deterministic tests for chart math and labels.
- `Sources/Vifty/FanCurveChartEditor.swift` - extracted chart view declarations currently living at the bottom of `ContentView.swift`.
- `Sources/Vifty/SettingsToolsPanel.swift` - extracted Settings & Tools panel view with explicit bindings and action closures.
- `Sources/Vifty/MenuBarStatusPresentation.swift` - extracted menu-bar display enums and status-item presentation types.

Modify:

- `Sources/Vifty/ViftyStatusItemController.swift` - use the new telemetry prime policy and remove fixed launch constants.
- `Sources/Vifty/ViftyApp.swift` - remove duplicate launch prime tasks; let the model start and the status-item controller own priming.
- `Sources/Vifty/AppModel.swift` - expose only the already-internal telemetry state needed by policy, then move menu-bar presentation types out.
- `Sources/Vifty/MainWindowLayout.swift` - add telemetry minimum/ideal widths and stop capping workbench telemetry to a narrow column.
- `Sources/Vifty/ContentView.swift` - consume new layout placement, chart geometry, chart view file, and Settings & Tools panel.
- `Tests/ViftyCoreTests/MainWindowLayoutTests.swift` - cover ultrawide workbench allocation.
- `Tests/ViftyCoreTests/AppSourceRegressionTests.swift` - delete or narrow source-substring assertions that are replaced by behavioral tests.
- `Tests/ViftyCoreTests/AppModelTests.swift` - keep menu-bar behavior coverage and update expectations for bounded priming.
- `Tests/ViftyCoreTests/DocumentationTrustSurfaceTests.swift` - keep Developer ID/source-first trust assertions current if release copy changes.

Do not modify for this plan unless a verification failure proves drift:

- `Sources/ViftyCore/SMCClient.swift`
- `Sources/ViftyCore/RealMacHardwareService.swift`
- `Sources/ViftyCore/FanControlService.swift`
- `Sources/ViftyDaemon/main.swift`
- `.github/workflows/release.yml`
- `Casks/vifty.rb`

## Task 1: Bound Menu-Bar Telemetry Priming

**Files:**
- Create: `Sources/Vifty/MenuBarTelemetryPrimePolicy.swift`
- Create: `Tests/ViftyCoreTests/MenuBarTelemetryPrimePolicyTests.swift`
- Modify: `Sources/Vifty/ViftyStatusItemController.swift`
- Modify: `Sources/Vifty/ViftyApp.swift`
- Modify: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Produces: `MenuBarTelemetryPrimePolicy.launch`
- Produces: `MenuBarTelemetryPrimePolicy.popover`
- Produces: `func shouldAttempt(_ attempt: Int, needsTelemetryPrime: Bool, hasCompletedHardwarePoll: Bool) -> Bool`
- Produces: `func retryDelaySeconds(after attempt: Int) -> Double`
- Produces: `func retryDelay(after attempt: Int) -> Duration`
- Consumes: `AppModel.menuBarLabelNeedsTelemetryPrime`
- Consumes: `AppModel.hasCompletedHardwarePoll`
- Consumes: `AppModel.primeMenuBarStatusItemTelemetry(maxAttempts:retryDelay:)`

- [ ] **Step 1: Write the failing policy tests**

Create `Tests/ViftyCoreTests/MenuBarTelemetryPrimePolicyTests.swift`:

```swift
import XCTest
@testable import Vifty

final class MenuBarTelemetryPrimePolicyTests: XCTestCase {
    func testLaunchPolicyCapsAttemptsBeforeFirstCompletedPoll() {
        let policy = MenuBarTelemetryPrimePolicy.launch

        XCTAssertTrue(policy.shouldAttempt(1, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertTrue(policy.shouldAttempt(8, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertFalse(policy.shouldAttempt(9, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertFalse(policy.shouldAttempt(1, needsTelemetryPrime: false, hasCompletedHardwarePoll: false))
    }

    func testLaunchPolicyStopsQuicklyAfterCompletedPollStillHasNoTelemetry() {
        let policy = MenuBarTelemetryPrimePolicy.launch

        XCTAssertTrue(policy.shouldAttempt(1, needsTelemetryPrime: true, hasCompletedHardwarePoll: true))
        XCTAssertTrue(policy.shouldAttempt(2, needsTelemetryPrime: true, hasCompletedHardwarePoll: true))
        XCTAssertFalse(policy.shouldAttempt(3, needsTelemetryPrime: true, hasCompletedHardwarePoll: true))
    }

    func testLaunchPolicyUsesBoundedExponentialBackoff() {
        let policy = MenuBarTelemetryPrimePolicy.launch

        XCTAssertEqual(policy.retryDelaySeconds(after: 1), 0.75, accuracy: 0.001)
        XCTAssertEqual(policy.retryDelaySeconds(after: 2), 1.5, accuracy: 0.001)
        XCTAssertEqual(policy.retryDelaySeconds(after: 3), 3.0, accuracy: 0.001)
        XCTAssertEqual(policy.retryDelaySeconds(after: 4), 6.0, accuracy: 0.001)
        XCTAssertEqual(policy.retryDelaySeconds(after: 5), 10.0, accuracy: 0.001)
    }

    func testPopoverPolicyStaysShortAndResponsive() {
        let policy = MenuBarTelemetryPrimePolicy.popover

        XCTAssertTrue(policy.shouldAttempt(1, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertTrue(policy.shouldAttempt(3, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertFalse(policy.shouldAttempt(4, needsTelemetryPrime: true, hasCompletedHardwarePoll: false))
        XCTAssertEqual(policy.retryDelaySeconds(after: 1), 0.25, accuracy: 0.001)
        XCTAssertEqual(policy.retryDelaySeconds(after: 3), 1.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the new tests and confirm they fail before implementation**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MenuBarTelemetryPrimePolicyTests
```

Expected:

```text
error: cannot find 'MenuBarTelemetryPrimePolicy' in scope
```

- [ ] **Step 3: Add the pure policy implementation**

Create `Sources/Vifty/MenuBarTelemetryPrimePolicy.swift`:

```swift
import Foundation

struct MenuBarTelemetryPrimePolicy: Equatable {
    let maxAttempts: Int
    let completedPollGraceAttempts: Int
    let initialRetryDelaySeconds: Double
    let maxRetryDelaySeconds: Double

    static let launch = MenuBarTelemetryPrimePolicy(
        maxAttempts: 8,
        completedPollGraceAttempts: 2,
        initialRetryDelaySeconds: 0.75,
        maxRetryDelaySeconds: 10.0
    )

    static let popover = MenuBarTelemetryPrimePolicy(
        maxAttempts: 3,
        completedPollGraceAttempts: 1,
        initialRetryDelaySeconds: 0.25,
        maxRetryDelaySeconds: 1.0
    )

    func shouldAttempt(
        _ attempt: Int,
        needsTelemetryPrime: Bool,
        hasCompletedHardwarePoll: Bool
    ) -> Bool {
        guard needsTelemetryPrime else { return false }
        guard attempt >= 1, attempt <= maxAttempts else { return false }
        guard hasCompletedHardwarePoll else { return true }
        return attempt <= completedPollGraceAttempts
    }

    func retryDelaySeconds(after attempt: Int) -> Double {
        let exponent = max(0, attempt - 1)
        let delay = initialRetryDelaySeconds * pow(2.0, Double(exponent))
        return min(delay, maxRetryDelaySeconds)
    }

    func retryDelay(after attempt: Int) -> Duration {
        .milliseconds(Int((retryDelaySeconds(after: attempt) * 1000).rounded()))
    }
}
```

- [ ] **Step 4: Wire the policy into the status item controller**

In `Sources/Vifty/ViftyStatusItemController.swift`, replace the two fixed constants:

```swift
private static let launchPrimeAttempts = 120
private static let launchPrimeRetryDelay: Duration = .milliseconds(750)
```

with:

```swift
private static let launchPrimePolicy = MenuBarTelemetryPrimePolicy.launch
private static let popoverPrimePolicy = MenuBarTelemetryPrimePolicy.popover
```

Replace the launch call in `scheduleTelemetryPrimeIfNeeded()`:

```swift
await self.primeStatusItemUntilTelemetryResolved(
    maxAttempts: Self.launchPrimeAttempts,
    retryDelay: Self.launchPrimeRetryDelay
)
```

with:

```swift
await self.primeStatusItemUntilTelemetryResolved(policy: Self.launchPrimePolicy)
```

Replace the popover call in `showPopover()`:

```swift
await primeStatusItemUntilTelemetryResolved(maxAttempts: 3, retryDelay: .milliseconds(250))
```

with:

```swift
await primeStatusItemUntilTelemetryResolved(policy: Self.popoverPrimePolicy)
```

Replace the existing `primeStatusItemUntilTelemetryResolved(maxAttempts:retryDelay:)` method with:

```swift
private func primeStatusItemUntilTelemetryResolved(
    policy: MenuBarTelemetryPrimePolicy
) async {
    model.start()
    for attempt in 1...policy.maxAttempts {
        guard policy.shouldAttempt(
            attempt,
            needsTelemetryPrime: model.menuBarLabelNeedsTelemetryPrime,
            hasCompletedHardwarePoll: model.hasCompletedHardwarePoll
        ) else { return }

        await model.primeMenuBarStatusItemTelemetry(maxAttempts: 1)
        updateStatusItem()

        guard policy.shouldAttempt(
            attempt + 1,
            needsTelemetryPrime: model.menuBarLabelNeedsTelemetryPrime,
            hasCompletedHardwarePoll: model.hasCompletedHardwarePoll
        ) else { return }

        try? await Task.sleep(for: policy.retryDelay(after: attempt))
    }
}
```

- [ ] **Step 5: Remove duplicate launch prime tasks from the app entrypoint**

In `Sources/Vifty/ViftyApp.swift`, keep `model.start()` in `init()` and remove this block:

```swift
Task { @MainActor in
    await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)
}
```

In `applicationDidFinishLaunching(_:)`, keep status item creation and remove this block:

```swift
Task { @MainActor in
    await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)
}
```

The method should still call:

```swift
model.start()
```

- [ ] **Step 6: Update source regression coverage so it protects the new policy instead of the old burst**

In `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`, replace assertions that require:

```swift
private static let launchPrimeAttempts = 120
private static let launchPrimeRetryDelay: Duration = .milliseconds(750)
await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)
```

with assertions that require:

```swift
XCTAssertTrue(statusItemController.contains("MenuBarTelemetryPrimePolicy.launch"))
XCTAssertTrue(statusItemController.contains("MenuBarTelemetryPrimePolicy.popover"))
XCTAssertTrue(statusItemController.contains("policy.shouldAttempt("))
XCTAssertFalse(statusItemController.contains("private static let launchPrimeAttempts = 120"))
XCTAssertFalse(viftyApp.contains("await model.primeMenuBarStatusItemTelemetry(maxAttempts: 5)"))
```

- [ ] **Step 7: Verify the task**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MenuBarTelemetryPrimePolicyTests
swift test --scratch-path "$PWD/.build" --filter AppSourceRegressionTests
```

Expected:

```text
Test Suite 'MenuBarTelemetryPrimePolicyTests' passed
Test Suite 'AppSourceRegressionTests' passed
```

- [ ] **Step 8: Commit**

```bash
git add Sources/Vifty/MenuBarTelemetryPrimePolicy.swift \
        Sources/Vifty/ViftyStatusItemController.swift \
        Sources/Vifty/ViftyApp.swift \
        Tests/ViftyCoreTests/MenuBarTelemetryPrimePolicyTests.swift \
        Tests/ViftyCoreTests/AppSourceRegressionTests.swift
git commit -m "fix: bound menu bar telemetry priming"
```

## Task 2: Make Workbench Layout Use Wide Displays

**Files:**
- Modify: `Sources/Vifty/MainWindowLayout.swift`
- Modify: `Sources/Vifty/ContentView.swift`
- Modify: `Tests/ViftyCoreTests/MainWindowLayoutTests.swift`
- Modify: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Produces: `MainWindowLayout.telemetryPaneMinWidth: CGFloat`
- Produces: `MainWindowLayout.telemetryPaneIdealWidth: CGFloat`
- Produces: existing `MainWindowLayout.telemetryPaneMaxWidth: CGFloat`, now `.infinity` for workbench
- Consumes: existing `MainWindowLayout.resolve(width:height:)`

- [ ] **Step 1: Write failing layout tests**

Append these tests to `Tests/ViftyCoreTests/MainWindowLayoutTests.swift`:

```swift
func testUltraWideWorkbenchDoesNotCapTelemetryToNarrowColumn() {
    let layout = MainWindowLayout.resolve(width: 3024, height: 1600)

    XCTAssertEqual(layout.mode, .workbench)
    XCTAssertEqual(layout.controlPaneWidth, 320)
    XCTAssertGreaterThanOrEqual(layout.editorPaneIdealWidth, 760)
    XCTAssertGreaterThanOrEqual(layout.telemetryPaneIdealWidth, 1600)
    XCTAssertEqual(layout.telemetryPaneMaxWidth, .infinity)
}

func testWorkbenchKeepsTelemetryUsableAtEntryWidth() {
    let layout = MainWindowLayout.resolve(width: 1280, height: 720)

    XCTAssertEqual(layout.mode, .workbench)
    XCTAssertEqual(layout.controlPaneWidth, 320)
    XCTAssertGreaterThanOrEqual(layout.editorPaneMinWidth, 460)
    XCTAssertGreaterThanOrEqual(layout.telemetryPaneMinWidth, 420)
}
```

- [ ] **Step 2: Run the tests and confirm they fail before implementation**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MainWindowLayoutTests
```

Expected:

```text
error: value of type 'MainWindowLayout' has no member 'telemetryPaneIdealWidth'
```

- [ ] **Step 3: Extend the layout model**

In `Sources/Vifty/MainWindowLayout.swift`, add two stored properties after `editorPaneMaxWidth`:

```swift
let telemetryPaneMinWidth: CGFloat
let telemetryPaneIdealWidth: CGFloat
```

Change the workbench branch to:

```swift
if width >= 1280, height >= 640 {
    let editorIdealWidth = min(max((width * 0.30).rounded(), 620), 860)
    let telemetryIdealWidth = max(520, (width - 320 - editorIdealWidth).rounded(.down))
    return MainWindowLayout(
        mode: .workbench,
        compactTelemetry: false,
        controlPaneWidth: 320,
        editorPaneMinWidth: 460,
        editorPaneIdealWidth: editorIdealWidth,
        editorPaneMaxWidth: 900,
        telemetryPaneMinWidth: 420,
        telemetryPaneIdealWidth: telemetryIdealWidth,
        telemetryPaneMaxWidth: .infinity
    )
}
```

Add values to the stacked branch:

```swift
telemetryPaneMinWidth: 360,
telemetryPaneIdealWidth: min(max(width, 360), 560),
telemetryPaneMaxWidth: .infinity
```

Add values to the split branch:

```swift
telemetryPaneMinWidth: 420,
telemetryPaneIdealWidth: max(520, (width * 0.52).rounded()),
telemetryPaneMaxWidth: .infinity
```

- [ ] **Step 4: Apply the new widths in the workbench telemetry pane**

In the workbench case of `Sources/Vifty/ContentView.swift`, replace:

```swift
.frame(maxWidth: layout.telemetryPaneMaxWidth, minHeight: proxy.size.height, maxHeight: proxy.size.height)
```

with:

```swift
.frame(
    minWidth: layout.telemetryPaneMinWidth,
    idealWidth: layout.telemetryPaneIdealWidth,
    maxWidth: layout.telemetryPaneMaxWidth,
    minHeight: proxy.size.height,
    maxHeight: proxy.size.height
)
```

- [ ] **Step 5: Update existing layout expectations**

In `Tests/ViftyCoreTests/MainWindowLayoutTests.swift`, update `testWideWindowUsesWorkbenchLayout()` to expect the new adaptive workbench values:

```swift
XCTAssertEqual(layout.controlPaneWidth, 320)
XCTAssertEqual(layout.editorPaneMinWidth, 460)
XCTAssertGreaterThanOrEqual(layout.editorPaneIdealWidth, 620)
XCTAssertEqual(layout.editorPaneMaxWidth, 900)
XCTAssertEqual(layout.telemetryPaneMinWidth, 420)
XCTAssertGreaterThanOrEqual(layout.telemetryPaneIdealWidth, 520)
XCTAssertEqual(layout.telemetryPaneMaxWidth, .infinity)
```

In `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`, update the frame assertion to look for the multi-line telemetry frame from Step 4 instead of the old one-line `maxWidth` call.

- [ ] **Step 6: Verify the task**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MainWindowLayoutTests
swift test --scratch-path "$PWD/.build" --filter AppSourceRegressionTests
```

Expected:

```text
Test Suite 'MainWindowLayoutTests' passed
Test Suite 'AppSourceRegressionTests' passed
```

- [ ] **Step 7: Commit**

```bash
git add Sources/Vifty/MainWindowLayout.swift \
        Sources/Vifty/ContentView.swift \
        Tests/ViftyCoreTests/MainWindowLayoutTests.swift \
        Tests/ViftyCoreTests/AppSourceRegressionTests.swift
git commit -m "fix: let workbench layout use wide windows"
```

## Task 3: Replace Brittle Workbench Placement Assertions With Behavioral Placement Tests

**Files:**
- Create: `Sources/Vifty/MainWindowSectionPlacement.swift`
- Create: `Tests/ViftyCoreTests/MainWindowSectionPlacementTests.swift`
- Modify: `Sources/Vifty/ContentView.swift`
- Modify: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Produces: `enum MainWindowPaneRole: String, Equatable`
- Produces: `struct MainWindowSectionPlacement: Equatable`
- Produces: `static func resolve(layout: MainWindowLayout) -> MainWindowSectionPlacement`
- Consumes: `MainWindowLayout.Mode`

- [ ] **Step 1: Write failing behavioral placement tests**

Create `Tests/ViftyCoreTests/MainWindowSectionPlacementTests.swift`:

```swift
import XCTest
@testable import Vifty

final class MainWindowSectionPlacementTests: XCTestCase {
    func testWorkbenchPlacesSettingsInControlRailAndFanControlInEditor() {
        let layout = MainWindowLayout.resolve(width: 1500, height: 820)
        let placement = MainWindowSectionPlacement.resolve(layout: layout)

        XCTAssertEqual(placement.safetyMode, .workbenchControlRail)
        XCTAssertEqual(placement.settingsAndTools, .workbenchControlRail)
        XCTAssertEqual(placement.fanControl, .workbenchEditor)
        XCTAssertEqual(placement.telemetryEvidence, .workbenchTelemetry)
    }

    func testSplitLayoutKeepsTelemetrySeparateFromControlAndEditor() {
        let layout = MainWindowLayout.resolve(width: 1180, height: 820)
        let placement = MainWindowSectionPlacement.resolve(layout: layout)

        XCTAssertEqual(placement.safetyMode, .splitControl)
        XCTAssertEqual(placement.settingsAndTools, .splitControl)
        XCTAssertEqual(placement.fanControl, .splitControl)
        XCTAssertEqual(placement.telemetryEvidence, .splitTelemetry)
    }

    func testStackedLayoutUsesSingleFlowForAllSections() {
        let layout = MainWindowLayout.resolve(width: 780, height: 480)
        let placement = MainWindowSectionPlacement.resolve(layout: layout)

        XCTAssertEqual(placement.safetyMode, .stackedFlow)
        XCTAssertEqual(placement.settingsAndTools, .stackedFlow)
        XCTAssertEqual(placement.fanControl, .stackedFlow)
        XCTAssertEqual(placement.telemetryEvidence, .stackedFlow)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail before implementation**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MainWindowSectionPlacementTests
```

Expected:

```text
error: cannot find 'MainWindowSectionPlacement' in scope
```

- [ ] **Step 3: Add the pure placement model**

Create `Sources/Vifty/MainWindowSectionPlacement.swift`:

```swift
import Foundation

enum MainWindowPaneRole: String, Equatable {
    case stackedFlow
    case splitControl
    case splitTelemetry
    case workbenchControlRail
    case workbenchEditor
    case workbenchTelemetry
}

struct MainWindowSectionPlacement: Equatable {
    let safetyMode: MainWindowPaneRole
    let fanControl: MainWindowPaneRole
    let telemetryEvidence: MainWindowPaneRole
    let settingsAndTools: MainWindowPaneRole

    static func resolve(layout: MainWindowLayout) -> MainWindowSectionPlacement {
        switch layout.mode {
        case .stacked:
            MainWindowSectionPlacement(
                safetyMode: .stackedFlow,
                fanControl: .stackedFlow,
                telemetryEvidence: .stackedFlow,
                settingsAndTools: .stackedFlow
            )
        case .split:
            MainWindowSectionPlacement(
                safetyMode: .splitControl,
                fanControl: .splitControl,
                telemetryEvidence: .splitTelemetry,
                settingsAndTools: .splitControl
            )
        case .workbench:
            MainWindowSectionPlacement(
                safetyMode: .workbenchControlRail,
                fanControl: .workbenchEditor,
                telemetryEvidence: .workbenchTelemetry,
                settingsAndTools: .workbenchControlRail
            )
        }
    }
}
```

- [ ] **Step 4: Use the placement model in the root layout**

In `Sources/Vifty/ContentView.swift`, inside `GeometryReader`, directly after:

```swift
let layout = MainWindowLayout.resolve(width: proxy.size.width, height: proxy.size.height)
```

add:

```swift
let placement = MainWindowSectionPlacement.resolve(layout: layout)
```

Add an explicit local use near the same scope so `-warnings-as-errors` does not reject the new placement seam before later tasks use it directly:

```swift
let _ = placement
```

Keep the visible pane structure unchanged in this task. The purpose here is to make placement a testable contract before extracting view files.

- [ ] **Step 5: Remove brittle placement source-string expectations**

In `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`, delete `testWorkbenchSeparatesLiveControlFromSettingsAndTools()` or reduce it to only assert that the placement seam is wired:

```swift
func testMainWindowUsesBehavioralSectionPlacementModel() throws {
    let contentView = try read("Sources/Vifty/ContentView.swift")

    XCTAssertTrue(contentView.contains("MainWindowSectionPlacement.resolve(layout: layout)"))
    XCTAssertFalse(contentView.contains("private var controlRailPane: some View {\\n        VStack(alignment: .leading, spacing: 18) {\\n            readinessStatusGroup"))
}
```

The detailed pane-role expectations now live in `MainWindowSectionPlacementTests`.

- [ ] **Step 6: Verify the task**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MainWindowSectionPlacementTests
swift test --scratch-path "$PWD/.build" --filter AppSourceRegressionTests
```

Expected:

```text
Test Suite 'MainWindowSectionPlacementTests' passed
Test Suite 'AppSourceRegressionTests' passed
```

- [ ] **Step 7: Commit**

```bash
git add Sources/Vifty/MainWindowSectionPlacement.swift \
        Sources/Vifty/ContentView.swift \
        Tests/ViftyCoreTests/MainWindowSectionPlacementTests.swift \
        Tests/ViftyCoreTests/AppSourceRegressionTests.swift
git commit -m "test: model main window section placement"
```

## Task 4: Extract Testable Fan Curve Chart Geometry

**Files:**
- Create: `Sources/Vifty/FanCurveChartGeometry.swift`
- Create: `Tests/ViftyCoreTests/FanCurveChartGeometryTests.swift`
- Modify: `Sources/Vifty/ContentView.swift`
- Modify: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Produces: `struct FanCurveChartGeometry: Equatable`
- Produces: `struct FanCurveChartValue: Equatable`
- Produces: `func position(for value: FanCurveChartValue, in size: CGSize) -> CGPoint`
- Produces: `func value(from location: CGPoint, in size: CGSize) -> FanCurveChartValue`
- Produces: `func targetRPM(at temperature: Double, points: [FanCurveChartValue]) -> Int`
- Consumes: `FanCurve`
- Consumes: existing chart bindings in `FanCurveChartEditor`

- [ ] **Step 1: Write failing chart geometry tests**

Create `Tests/ViftyCoreTests/FanCurveChartGeometryTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import Vifty

final class FanCurveChartGeometryTests: XCTestCase {
    func testPositionMapsLowTemperatureAndLowRPMToPlotBottomLeft() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...4296
        )

        let point = geometry.position(
            for: FanCurveChartValue(temperature: 35, rpm: 1499),
            in: CGSize(width: 700, height: 272)
        )

        XCTAssertEqual(point.x, 44, accuracy: 0.1)
        XCTAssertEqual(point.y, 232, accuracy: 0.1)
    }

    func testValueFromDragClampsInsidePlotRange() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...4296
        )

        let value = geometry.value(
            from: CGPoint(x: -100, y: 999),
            in: CGSize(width: 700, height: 272)
        )

        XCTAssertEqual(value.temperature, 35, accuracy: 0.1)
        XCTAssertEqual(value.rpm, 1499, accuracy: 0.1)
    }

    func testTargetRPMInterpolatesThroughCurvePoints() {
        let geometry = FanCurveChartGeometry(
            temperatureRange: 35...105,
            rpmRange: 1499...4296
        )
        let points = [
            FanCurveChartValue(temperature: 55, rpm: 1499),
            FanCurveChartValue(temperature: 70, rpm: 3500),
            FanCurveChartValue(temperature: 85, rpm: 4296)
        ]

        XCTAssertEqual(geometry.targetRPM(at: 55, points: points), 1499)
        XCTAssertEqual(geometry.targetRPM(at: 70, points: points), 3500)
        XCTAssertEqual(geometry.targetRPM(at: 85, points: points), 4296)
        XCTAssertEqual(geometry.targetRPM(at: 62.5, points: points), 2500)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail before implementation**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter FanCurveChartGeometryTests
```

Expected:

```text
error: cannot find 'FanCurveChartGeometry' in scope
```

- [ ] **Step 3: Add the chart geometry model**

Create `Sources/Vifty/FanCurveChartGeometry.swift`:

```swift
import CoreGraphics
import Foundation
import ViftyCore

struct FanCurveChartValue: Equatable {
    let temperature: Double
    let rpm: Double
}

struct FanCurveChartGeometry: Equatable {
    let temperatureRange: ClosedRange<Double>
    let rpmRange: ClosedRange<Double>

    private let leftInset: CGFloat = 44
    private let rightInset: CGFloat = 18
    private let topInset: CGFloat = 20
    private let bottomInset: CGFloat = 40

    func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: leftInset,
            y: topInset,
            width: max(1, size.width - leftInset - rightInset),
            height: max(1, size.height - topInset - bottomInset)
        )
    }

    func position(for value: FanCurveChartValue, in size: CGSize) -> CGPoint {
        let rect = plotRect(in: size)
        let clampedTemperature = min(max(value.temperature, temperatureRange.lowerBound), temperatureRange.upperBound)
        let clampedRPM = min(max(value.rpm, rpmRange.lowerBound), rpmRange.upperBound)
        let xRatio = (clampedTemperature - temperatureRange.lowerBound) / (temperatureRange.upperBound - temperatureRange.lowerBound)
        let yRatio = (clampedRPM - rpmRange.lowerBound) / (rpmRange.upperBound - rpmRange.lowerBound)
        return CGPoint(
            x: rect.minX + rect.width * CGFloat(xRatio),
            y: rect.maxY - rect.height * CGFloat(yRatio)
        )
    }

    func value(from location: CGPoint, in size: CGSize) -> FanCurveChartValue {
        let rect = plotRect(in: size)
        let x = min(max(location.x, rect.minX), rect.maxX)
        let y = min(max(location.y, rect.minY), rect.maxY)
        let xRatio = Double((x - rect.minX) / rect.width)
        let yRatio = Double((rect.maxY - y) / rect.height)
        return FanCurveChartValue(
            temperature: temperatureRange.lowerBound + xRatio * (temperatureRange.upperBound - temperatureRange.lowerBound),
            rpm: rpmRange.lowerBound + yRatio * (rpmRange.upperBound - rpmRange.lowerBound)
        )
    }

    func targetRPM(at temperature: Double, points: [FanCurveChartValue]) -> Int {
        let fanCurvePoints = points.map { value in
            CurvePoint(
                temperatureCelsius: value.temperature,
                rpm: Int(value.rpm.rounded())
            )
        }
        let curve = FanCurve(sensorID: "chart-preview", points: fanCurvePoints)
        return curve.targetRPM(
            for: temperature,
            minimumRPM: Int(rpmRange.lowerBound.rounded()),
            maximumRPM: Int(rpmRange.upperBound.rounded())
        )
    }
}
```

- [ ] **Step 4: Replace duplicated geometry logic in the chart view**

In `Sources/Vifty/ContentView.swift`, inside `FanCurveChartEditor`, add:

```swift
private var chartGeometry: FanCurveChartGeometry {
    FanCurveChartGeometry(
        temperatureRange: tempRange,
        rpmRange: rpmLower...rpmUpper
    )
}
```

Replace the body of the existing private `plotRect(in:)` with:

```swift
chartGeometry.plotRect(in: size)
```

Replace the body of the existing private `position(for:in:)` with:

```swift
chartGeometry.position(
    for: FanCurveChartValue(temperature: point.temperature, rpm: point.rpm),
    in: size
)
```

Replace the location-to-value math in `setCurvePoint(_:from:in:)` with:

```swift
let value = chartGeometry.value(from: location, in: size)
switch point {
case .start:
    startTemp = value.temperature
    startRPM = value.rpm
case .ramp:
    midTemp = value.temperature
    midRPM = value.rpm
case .high:
    maxTemp = value.temperature
    maxRPM = value.rpm
}
```

Replace `targetRPM(at:points:)` with:

```swift
private func targetRPM(at temperature: Double, points: [FanCurveChartPoint]) -> Int {
    chartGeometry.targetRPM(
        at: temperature,
        points: points.map { FanCurveChartValue(temperature: $0.temperature, rpm: $0.rpm) }
    )
}
```

- [ ] **Step 5: Keep source regression tests pointed at behavior, not duplicated math**

In `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`, replace assertions that require the chart math functions to live in `ContentView.swift` with:

```swift
let chartGeometry = try read("Sources/Vifty/FanCurveChartGeometry.swift")
XCTAssertTrue(chartGeometry.contains("struct FanCurveChartGeometry"))
XCTAssertTrue(chartGeometry.contains("func targetRPM(at temperature: Double, points: [FanCurveChartValue]) -> Int"))
XCTAssertTrue(contentView.contains("private var chartGeometry: FanCurveChartGeometry"))
```

- [ ] **Step 6: Verify the task**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter FanCurveChartGeometryTests
swift test --scratch-path "$PWD/.build" --filter AppSourceRegressionTests
```

Expected:

```text
Test Suite 'FanCurveChartGeometryTests' passed
Test Suite 'AppSourceRegressionTests' passed
```

- [ ] **Step 7: Commit**

```bash
git add Sources/Vifty/FanCurveChartGeometry.swift \
        Sources/Vifty/ContentView.swift \
        Tests/ViftyCoreTests/FanCurveChartGeometryTests.swift \
        Tests/ViftyCoreTests/AppSourceRegressionTests.swift
git commit -m "refactor: test fan curve chart geometry"
```

## Task 5: Split Large SwiftUI Views Into Focused Files

**Files:**
- Create: `Sources/Vifty/FanCurveChartEditor.swift`
- Create: `Sources/Vifty/SettingsToolsPanel.swift`
- Modify: `Sources/Vifty/ContentView.swift`
- Modify: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Produces: `struct FanCurveChartEditor: View`
- Produces: `struct SettingsToolsPanel: View`
- Consumes: `FanCurveChartGeometry`
- Consumes: existing `AppModel` published settings and action methods
- Consumes: closures for agent workflow copy actions

- [ ] **Step 1: Move chart declarations into a dedicated chart file**

Move these declarations exactly as currently implemented from `Sources/Vifty/ContentView.swift` to `Sources/Vifty/FanCurveChartEditor.swift`:

```text
FanCurveChartEditor
CurveChartAxisValue
CurveChartAxisTitle
CurveChartAxisReadout
CurveChartPointKind
FanCurveChartPoint
FanCurveChartSeries
CurveChartPointSummaryChip
ChartHandle
CurveChartHandleValueLabel
```

The new file must start with:

```swift
import SwiftUI
import ViftyCore
```

Keep these declarations `private` where possible. Make only the root `FanCurveChartEditor` internal by removing `private` from its declaration, because `ContentView.swift` consumes it from another file in the same module:

```swift
struct FanCurveChartEditor: View {
```

- [ ] **Step 2: Verify the chart move compiles**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter FanCurveChartGeometryTests
```

Expected:

```text
Test Suite 'FanCurveChartGeometryTests' passed
```

- [ ] **Step 3: Extract Settings & Tools into an explicit panel**

Create `Sources/Vifty/SettingsToolsPanel.swift` with this public surface:

```swift
import SwiftUI
import ViftyCore

struct SettingsToolsPanel: View {
    @ObservedObject var model: AppModel
    @Binding var selectedProfileID: UUID?
    @Binding var agentRuleCopied: Bool
    @Binding var agentCommandCopied: Bool

    let menuBarCustomFieldBinding: (MenuBarField) -> Binding<Bool>
    let copyAgentWorkflowCommand: (AgentWorkflowSupport.WorkloadCommandTemplate, AgentWorkflowSupport.WorkloadCommandMode) -> Void
    let copyAgentWorkflowRule: () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                quickSettingsStrip
                menuBarDisplaySettings
                notificationSettings
                agentWorkflowSettings
            }
            .padding(.top, 6)
        } label: {
            Label("Settings & Tools", systemImage: "gearshape")
                .font(.headline)
        }
    }
}
```

Move these existing computed views and helpers from `ContentView.swift` into `SettingsToolsPanel.swift`, adapting every `model` access to the stored `model` property and every `selectedProfileID` access to the binding:

```text
quickSettingsStrip
curveProfileSettings
startupModeSettings
launchAtLoginSettings
launchAtLoginStatusMessage
menuBarDisplaySettings
menuBarCustomFieldControls
codexUsageDisplayControls
notificationSettings
agentWorkflowSettings
```

Do not move `copyAgentWorkflowCommand`, `copyAgentWorkflowRule`, or clipboard-writing helpers in this task. They remain in `ContentView.swift` and are passed to the new panel as closures.

- [ ] **Step 4: Replace the old settings panel in ContentView**

In `Sources/Vifty/ContentView.swift`, replace the body of `settingsAndToolsPanel` with:

```swift
private var settingsAndToolsPanel: some View {
    SettingsToolsPanel(
        model: model,
        selectedProfileID: $selectedProfileID,
        agentRuleCopied: $agentRuleCopied,
        agentCommandCopied: $agentCommandCopied,
        menuBarCustomFieldBinding: menuBarCustomFieldBinding(_:),
        copyAgentWorkflowCommand: copyAgentWorkflowCommand(_:mode:),
        copyAgentWorkflowRule: copyAgentWorkflowRule
    )
}
```

Keep `menuBarCustomFieldBinding(_:)` in `ContentView.swift` for this task so the binding shape stays unchanged.

- [ ] **Step 5: Update source regression tests to follow the new files**

In `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`, for chart-specific assertions, read `Sources/Vifty/FanCurveChartEditor.swift`:

```swift
let chartView = try read("Sources/Vifty/FanCurveChartEditor.swift")
XCTAssertTrue(chartView.contains("struct FanCurveChartEditor: View"))
XCTAssertTrue(chartView.contains("ChartHandle("))
XCTAssertFalse(contentView.contains("private struct FanCurveChartEditor: View"))
```

For settings-specific assertions, read `Sources/Vifty/SettingsToolsPanel.swift`:

```swift
let settingsTools = try read("Sources/Vifty/SettingsToolsPanel.swift")
XCTAssertTrue(settingsTools.contains("Label(\"Settings & Tools\", systemImage: \"gearshape\")"))
XCTAssertTrue(settingsTools.contains("Toggle(\"Helper failure\", isOn: $model.notificationSettings.helperFailure)"))
XCTAssertTrue(contentView.contains("SettingsToolsPanel("))
```

- [ ] **Step 6: Verify the task**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter FanCurveChartGeometryTests
swift test --scratch-path "$PWD/.build" --filter AppSourceRegressionTests
swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors
```

Expected:

```text
Test Suite 'FanCurveChartGeometryTests' passed
Test Suite 'AppSourceRegressionTests' passed
Build complete!
```

- [ ] **Step 7: Commit**

```bash
git add Sources/Vifty/FanCurveChartEditor.swift \
        Sources/Vifty/SettingsToolsPanel.swift \
        Sources/Vifty/ContentView.swift \
        Tests/ViftyCoreTests/AppSourceRegressionTests.swift
git commit -m "refactor: split chart and settings panels"
```

## Task 6: Move Menu-Bar Presentation Types Out Of AppModel

**Files:**
- Create: `Sources/Vifty/MenuBarStatusPresentation.swift`
- Modify: `Sources/Vifty/AppModel.swift`
- Modify: `Sources/Vifty/ViftyStatusItemController.swift`
- Modify: `Tests/ViftyCoreTests/AppModelTests.swift`
- Modify: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Produces: `enum MenuBarDisplayMode`
- Produces: `enum MenuBarField`
- Produces: `struct MenuBarStatusItemPresentation`
- Produces: `enum ViftyStatusItemPresentation`
- Consumes: `AppPreferencesStore`
- Consumes: `CodexUsageDisplayStyle`
- Consumes: `ViftyStatusItemController.updateStatusItem()`

- [ ] **Step 1: Create the new presentation file by moving top-level types**

Create `Sources/Vifty/MenuBarStatusPresentation.swift` and move these declarations from `Sources/Vifty/AppModel.swift` and `Sources/Vifty/ViftyStatusItemController.swift` without behavior changes:

```text
MenuBarDisplayMode
MenuBarField
MenuBarStatusItemPresentation
ViftyStatusItemPresentation
```

The new file must start with:

```swift
import Foundation
```

The moved `ViftyStatusItemPresentation` declaration must remain:

```swift
enum ViftyStatusItemPresentation {
    static func resolvedText(
        statusItemText: String?,
        fallbackStatusItemText: String? = nil,
        labelNeedsTelemetryPrime: Bool,
        allowsPlaceholderText: Bool
    ) -> String? {
        guard !labelNeedsTelemetryPrime else {
            return fallbackStatusItemText
        }
        guard let statusItemText else {
            return fallbackStatusItemText
        }
        guard allowsPlaceholderText || !statusItemText.contains("--") else { return fallbackStatusItemText }
        return statusItemText
    }
}
```

- [ ] **Step 2: Remove moved declarations from old files**

Delete the moved menu-bar type declarations from:

```text
Sources/Vifty/AppModel.swift
Sources/Vifty/ViftyStatusItemController.swift
```

Keep all `AppModel` computed properties and methods that read live hardware, Codex usage, and preferences in `AppModel.swift` during this task.

- [ ] **Step 3: Update source regression expectations**

In `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`, replace assertions that expect `enum ViftyStatusItemPresentation` in `ViftyStatusItemController.swift` or menu-bar enums in `AppModel.swift` with:

```swift
let menuBarPresentation = try read("Sources/Vifty/MenuBarStatusPresentation.swift")
XCTAssertTrue(menuBarPresentation.contains("enum MenuBarDisplayMode"))
XCTAssertTrue(menuBarPresentation.contains("enum MenuBarField"))
XCTAssertTrue(menuBarPresentation.contains("struct MenuBarStatusItemPresentation"))
XCTAssertTrue(menuBarPresentation.contains("enum ViftyStatusItemPresentation"))
XCTAssertFalse(statusItemController.contains("enum ViftyStatusItemPresentation"))
```

- [ ] **Step 4: Verify the task**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter AppModelTests
swift test --scratch-path "$PWD/.build" --filter AppSourceRegressionTests
swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors
```

Expected:

```text
Test Suite 'AppModelTests' passed
Test Suite 'AppSourceRegressionTests' passed
Build complete!
```

- [ ] **Step 5: Commit**

```bash
git add Sources/Vifty/MenuBarStatusPresentation.swift \
        Sources/Vifty/AppModel.swift \
        Sources/Vifty/ViftyStatusItemController.swift \
        Tests/ViftyCoreTests/AppModelTests.swift \
        Tests/ViftyCoreTests/AppSourceRegressionTests.swift
git commit -m "refactor: separate menu bar presentation types"
```

## Task 7: Preserve Developer ID And Source-First Trust Boundaries

**Files:**
- Modify only if wording drift is found: `docs/release.md`
- Modify only if wording drift is found: `docs/release-status.md`
- Modify only if wording drift is found: `Tests/ViftyCoreTests/DocumentationTrustSurfaceTests.swift`
- Do not modify: `.github/workflows/release.yml`
- Do not modify: `Casks/vifty.rb`

**Interfaces:**
- Consumes: existing source-first release metadata checks.
- Consumes: existing Developer ID release verifier checks.
- Produces: no new release path until the intended TeamID is active.

- [ ] **Step 1: Run the source-first metadata check**

Run:

```bash
scripts/validate-release-metadata.sh --mode source-first
```

Expected:

```text
Source-first release metadata OK
```

- [ ] **Step 2: Run the community/support surface check**

Run:

```bash
scripts/check-community-standards.sh
```

Expected:

```text
Community standards OK
```

- [ ] **Step 3: Run the release-trust documentation tests**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter DocumentationTrustSurfaceTests
```

Expected:

```text
Test Suite 'DocumentationTrustSurfaceTests' passed
```

- [ ] **Step 4: If the tests fail because trust wording drifted, make the minimal copy-and-test update**

Keep these exact concepts present in both docs and tests:

```text
Pending Apple Developer Program access is not release evidence.
Do not use another organization's Developer ID certificate unless that organization is intentionally meant to own Vifty's public signing identity.
Keep Casks/vifty.rb disabled for source-first releases.
Do not claim source-first or unsigned-dev artifacts are Developer ID signed, notarized, stapled, Gatekeeper-approved, Homebrew-trusted, or official trusted binaries.
```

After any copy change, run:

```bash
swift test --scratch-path "$PWD/.build" --filter DocumentationTrustSurfaceTests
scripts/validate-release-metadata.sh --mode source-first
```

Expected:

```text
Test Suite 'DocumentationTrustSurfaceTests' passed
Source-first release metadata OK
```

- [ ] **Step 5: Commit only if files changed**

If Step 4 made changes:

```bash
git add docs/release.md docs/release-status.md Tests/ViftyCoreTests/DocumentationTrustSurfaceTests.swift
git commit -m "docs: preserve release trust boundary"
```

If Step 4 made no changes, do not create an empty commit.

## Task 8: Full Verification, Local App Smoke, And Evidence Log

**Files:**
- Modify: Obsidian daily note through the `$obsidian` skill.
- Modify: Obsidian Vifty project note through the `$obsidian` skill.
- Do not modify repo source unless a verification failure identifies a concrete regression.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: final local evidence for pre-push review.

- [ ] **Step 1: Check disk space before long gates**

Run:

```bash
df -h /System/Volumes/Data
```

Expected:

```text
Avail is 50Gi or higher
```

- [ ] **Step 2: Check whitespace and patch cleanliness**

Run:

```bash
git diff --check
```

Expected:

```text
no output
```

- [ ] **Step 3: Run the focused test set introduced by this plan**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter MenuBarTelemetryPrimePolicyTests
swift test --scratch-path "$PWD/.build" --filter MainWindowLayoutTests
swift test --scratch-path "$PWD/.build" --filter MainWindowSectionPlacementTests
swift test --scratch-path "$PWD/.build" --filter FanCurveChartGeometryTests
swift test --scratch-path "$PWD/.build" --filter AppModelTests
swift test --scratch-path "$PWD/.build" --filter AppSourceRegressionTests
swift test --scratch-path "$PWD/.build" --filter DocumentationTrustSurfaceTests
```

Expected:

```text
each selected test suite passed
```

- [ ] **Step 4: Run the fast local trust gate**

Run:

```bash
make test-fast SWIFT_BUILD_PATH="$PWD/.build"
```

Expected:

```text
all ViftyCoreTests selected by make test-fast passed
```

- [ ] **Step 5: Build with warnings as errors**

Run:

```bash
swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors
```

Expected:

```text
Build complete!
```

- [ ] **Step 6: Build the local ad-hoc app bundle without claiming trusted distribution**

Run:

```bash
make app CONFIGURATION=release SIGNING_IDENTITY=- VIFTY_XPC_ALLOWED_TEAM_ID="" SWIFT_BUILD_PATH="$PWD/.build"
```

Expected:

```text
.build/release/Vifty.app exists
codesign verification passes for the ad-hoc local app
```

- [ ] **Step 7: Run release metadata checks**

Run:

```bash
scripts/validate-release-metadata.sh --mode source-first
scripts/check-community-standards.sh
```

Expected:

```text
Source-first release metadata OK
Community standards OK
```

- [ ] **Step 8: Local visual smoke without helper or fan actions**

Run:

```bash
open .build/release/Vifty.app
```

Manual checks:

```text
Menu bar label resolves within the bounded launch policy and does not sit in a rapid polling loop.
At around 1280 px width the workbench has three usable panels.
At ultrawide width the telemetry/evidence pane expands instead of leaving a large unused right side.
Settings & Tools remains in the left/control rail in workbench mode.
The curve chart remains readable, draggable, and non-overlapping.
No helper repair, helper install, fan write, cooling lease, or Auto restore action is triggered during this visual smoke.
```

- [ ] **Step 9: Check temp leftovers**

Run:

```bash
du -sh /private/tmp/[Vv]ifty* 2>/dev/null || true
```

Expected:

```text
no unexpected large Vifty temp directories
```

- [ ] **Step 10: Log evidence to Obsidian**

Use the `$obsidian` skill to update:

```text
Daily note: Hermes/Daily/09-07-2026.md
Project note: Hermes/Personal/Projects/Vifty.md
```

Record:

```text
branch or commit range
tasks completed
focused tests run
make test-fast result
build result
release metadata result
local visual smoke result
explicit note that no helper/fan write actions were run
remaining blockers, especially Developer ID account activation if still pending
```

- [ ] **Step 11: Commit any final evidence/doc changes**

If Obsidian notes are outside the repo, do not stage them here. If repo docs changed during verification:

```bash
git add docs/release.md docs/release-status.md Tests/ViftyCoreTests/DocumentationTrustSurfaceTests.swift
git commit -m "docs: update verification evidence"
```

If no repo docs changed during verification, do not create an empty commit.

## Execution Order

Use this order:

1. Task 1 - resource efficiency first, because it directly addresses the resource-hogging complaint.
2. Task 2 - responsive layout width allocation.
3. Task 3 - behavioral layout seam before more view movement.
4. Task 4 - chart geometry seam before moving the chart view file.
5. Task 5 - view extraction after seams exist.
6. Task 6 - AppModel/menu-bar presentation file split.
7. Task 7 - release trust boundary verification.
8. Task 8 - full gates and evidence log.

## Self-Review

**Spec coverage:** The plan covers the earlier findings: menu-bar resource burst, wide-workbench dead space, brittle UI tests, oversized view/model files, chart maintainability, and Developer ID/source-first trust boundaries. It also covers the user's request for better responsive panel usage and a more customizable menu bar by preserving the menu-bar field settings while making the status-item runtime cheaper.

**Placeholder scan:** Red-flag placeholder phrases were scanned and removed. Steps include concrete files, commands, expected outputs, and code snippets for new interfaces.

**Type consistency:** New names are consistent across tasks: `MenuBarTelemetryPrimePolicy`, `MainWindowSectionPlacement`, `MainWindowPaneRole`, `FanCurveChartGeometry`, `FanCurveChartValue`, `SettingsToolsPanel`, and `MenuBarStatusPresentation`.

**Risk check:** The plan intentionally does not alter SMC write policy, daemon write authorization, helper install behavior, release workflow notarization gates, or Homebrew cask state. Live visual smoke is read-only unless the user explicitly asks for helper or fan-control actions.
