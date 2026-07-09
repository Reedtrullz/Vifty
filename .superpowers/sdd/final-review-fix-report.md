# Final Review Fix Report

## What you changed for each finding

### Important 1 — popover telemetry priming is now controller-bounded

- Added [`Sources/Vifty/MenuBarTelemetryPrimeScheduler.swift`](/Users/reidar/Projectos/Vifty/Sources/Vifty/MenuBarTelemetryPrimeScheduler.swift) as a small `@MainActor` scheduler that tracks one in-flight priming task at a time and clears itself when the task finishes.
- Updated [`Sources/Vifty/ViftyStatusItemController.swift`](/Users/reidar/Projectos/Vifty/Sources/Vifty/ViftyStatusItemController.swift) so both launch priming and popover priming go through the same tracked scheduler via `scheduleTelemetryPrimeIfNeeded(policy:)`.
- Removed the controller-local untracked popover `Task` pattern and the old `primeTask` field, so repeated popover opens no longer start overlapping prime loops while one is already running.
- Added focused coverage in [`Tests/ViftyCoreTests/MenuBarTelemetryPrimePolicyTests.swift`](/Users/reidar/Projectos/Vifty/Tests/ViftyCoreTests/MenuBarTelemetryPrimePolicyTests.swift):
  - a running launch-prime request suppresses a popover-prime request
  - after the first prime finishes, a new popover-prime request can start
- Updated source regression coverage in [`Tests/ViftyCoreTests/AppSourceRegressionTests.swift`](/Users/reidar/Projectos/Vifty/Tests/ViftyCoreTests/AppSourceRegressionTests.swift) so the controller must keep using the shared scheduler seam.

### Important 2 — `ContentView` now renders from `MainWindowSectionPlacement`

- Extended [`Sources/Vifty/MainWindowSectionPlacement.swift`](/Users/reidar/Projectos/Vifty/Sources/Vifty/MainWindowSectionPlacement.swift) with:
  - `MainWindowSection`
  - `paneRole(for:)`
  - `sections(in:)`
- Reworked [`Sources/Vifty/ContentView.swift`](/Users/reidar/Projectos/Vifty/Sources/Vifty/ContentView.swift) so pane composition is driven by `placement.sections(in:)` instead of computing placement and discarding it.
- Preserved the requested layout behavior:
  - stacked: safety/mode + fan control + settings in the main flow, telemetry appended in the stacked flow
  - split: safety/mode + fan control + settings on the control side, telemetry on the telemetry side
  - workbench: safety/mode + settings in the left rail, fan control in the editor, telemetry in the right pane
- Kept the workbench control-rail spacer behavior by routing that pane through a dedicated sections-based renderer.
- Added meaningful placement tests in [`Tests/ViftyCoreTests/MainWindowSectionPlacementTests.swift`](/Users/reidar/Projectos/Vifty/Tests/ViftyCoreTests/MainWindowSectionPlacementTests.swift) for ordered per-pane section lists, and updated [`Tests/ViftyCoreTests/AppSourceRegressionTests.swift`](/Users/reidar/Projectos/Vifty/Tests/ViftyCoreTests/AppSourceRegressionTests.swift) to pin the new placement-driven rendering shape instead of the removed pane helpers.

### Minor — release doc heading cleanup

- Fixed the heading structure in [`docs/release.md`](/Users/reidar/Projectos/Vifty/docs/release.md) by adding a short Developer ID mode intro and making pending account setup a clean subsection.
- Updated the matching assertion in [`Tests/ViftyCoreTests/DocumentationTrustSurfaceTests.swift`](/Users/reidar/Projectos/Vifty/Tests/ViftyCoreTests/DocumentationTrustSurfaceTests.swift).

## Commands run and pass/fail summaries

- `df -h /System/Volumes/Data` — passed; ~68 GiB free, above the 50 GiB floor.
- `swift test --scratch-path "$PWD/.build" --filter MenuBarTelemetryPrimePolicyTests` — initial red run failed before implementation because `MenuBarTelemetryPrimeScheduler` did not exist; final run passed (6 tests).
- `swift test --scratch-path "$PWD/.build" --filter MainWindowSectionPlacementTests` — initial red run failed before implementation because `sections(in:)` did not exist; final run passed (6 tests).
- `swift test --scratch-path "$PWD/.build" --filter AppSourceRegressionTests` — first post-change run failed on one outdated assertion in `testMainWindowPanesAreIndependentlyScrollableAndFillAvailableHeight`; after updating the regression expectation, final run passed (27 tests).
- `swift test --scratch-path "$PWD/.build" --filter DocumentationTrustSurfaceTests` — passed (32 tests).
- `swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors` — passed.

## Files changed

- [`Sources/Vifty/MenuBarTelemetryPrimeScheduler.swift`](/Users/reidar/Projectos/Vifty/Sources/Vifty/MenuBarTelemetryPrimeScheduler.swift)
- [`Sources/Vifty/ViftyStatusItemController.swift`](/Users/reidar/Projectos/Vifty/Sources/Vifty/ViftyStatusItemController.swift)
- [`Sources/Vifty/MainWindowSectionPlacement.swift`](/Users/reidar/Projectos/Vifty/Sources/Vifty/MainWindowSectionPlacement.swift)
- [`Sources/Vifty/ContentView.swift`](/Users/reidar/Projectos/Vifty/Sources/Vifty/ContentView.swift)
- [`Tests/ViftyCoreTests/MenuBarTelemetryPrimePolicyTests.swift`](/Users/reidar/Projectos/Vifty/Tests/ViftyCoreTests/MenuBarTelemetryPrimePolicyTests.swift)
- [`Tests/ViftyCoreTests/MainWindowSectionPlacementTests.swift`](/Users/reidar/Projectos/Vifty/Tests/ViftyCoreTests/MainWindowSectionPlacementTests.swift)
- [`Tests/ViftyCoreTests/AppSourceRegressionTests.swift`](/Users/reidar/Projectos/Vifty/Tests/ViftyCoreTests/AppSourceRegressionTests.swift)
- [`Tests/ViftyCoreTests/DocumentationTrustSurfaceTests.swift`](/Users/reidar/Projectos/Vifty/Tests/ViftyCoreTests/DocumentationTrustSurfaceTests.swift)
- [`docs/release.md`](/Users/reidar/Projectos/Vifty/docs/release.md)

## Self-review findings

- The priming fix is scoped to task scheduling only; it does not change telemetry retry policy or any hardware-control behavior.
- The new placement seam is used by `ContentView` itself, and the tests now validate ordered pane membership rather than only checking that `resolve` was called.
- No helper repair, helper install, fan writes, cooling leases, or other live hardware-control operations were run.

## Any issues/concerns

- No blocking issues found after the required verification.
