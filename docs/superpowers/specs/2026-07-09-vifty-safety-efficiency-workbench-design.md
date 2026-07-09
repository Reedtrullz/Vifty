# Vifty Safety, Efficiency, and Workbench Design

## Goal

Make Vifty safer to quit, quieter across relaunches, easier to diagnose, and more native on wide macOS displays without weakening daemon-first fan control or the source-first release boundary.

## Approved Direction

The implementation follows the 09-07-2026 deep-review sequence:

1. Make every application termination path await a confirmed Auto-restore attempt.
2. Coalesce local notifications across relaunches.
3. remove known UI/runtime faults and make bundled launch the obvious developer path.
4. Bound Codex child-process shutdown and fallback work.
5. Add privacy-safe runtime instrumentation before changing control cadence.
6. Keep Settings & Tools visible in the left rail, but open a native Settings scene.
7. Reflow telemetry content at wide sizes instead of only stretching its container.
8. Preserve external Developer ID and live hardware validation as explicit later gates.

## Safety Contract

`FanControlCoordinator.forceAuto()` returns `AutoRestoreResult`, either `.restored` or `.failed(message:)`. It still updates coordinator state and the unclean marker exactly as today, but callers can no longer confuse an attempted restore with a confirmed restore.

`AppModel.stopAndRestore()` returns `AppTerminationRestoreResult`. The result combines hardware Auto restoration and agent-lease clearing. Polling and Codex refresh stop before restoration begins. The model reports failures through existing UI/notification state and never hides them from the application delegate.

`ViftyAppDelegate.applicationShouldTerminate(_:)` uses `.terminateLater` for the first request, starts one termination task, and calls `reply(toApplicationShouldTerminate:)` only after `stopAndRestore()` completes. Successful restoration terminates. Failed restoration cancels termination and opens the main window so the error remains visible. Repeated quit requests reuse the in-flight task.

The custom menu-bar Quit delegates to `NSApplication.terminate(nil)` and does not run a second independent restore sequence.

## Notification Contract

Local notification request identifiers are stable per kind, allowing Notification Center to replace pending same-kind requests. A small private JSON store persists the most recent delivery timestamp per kind with `0o700` directory and `0o600` file permissions. Initial helper, drain, and agent-attention observations establish a baseline without notifying; only a later transition to attention posts an alert. Explicit Auto-restore failures remain immediately eligible because they are action outcomes, not baseline telemetry.

## Efficiency and Observability

Add `ViftyLog` categories for lifecycle, polling, XPC, notifications, fan control, and Codex usage. Log only duration, outcome class, mode, and fallback source; do not log hostnames, sensor identifiers, command arguments, profile names, or user content.

Polling keeps the current 5-second active and 10-second idle safety cadence. The launch sequence removes the redundant immediate second poll. XPC requests retain their fail-closed per-request connection model in this slice; signposts provide evidence for a later combined-state or persistent-channel change.

Codex app-server execution gains a bounded termination grace period. After the response timeout, the client terminates the process, waits only for the grace interval, and returns without an unbounded `waitUntilExit()`. The local JSONL fallback remains tail-bounded.

## Workbench and Settings

The left workbench rail keeps readiness and mode controls plus a visible Settings & Tools button. The button opens a SwiftUI `Settings` scene. Settings content moves to a dedicated scrollable view; it is no longer expanded inline below a large spacer.

The telemetry pane uses a width-sensitive adaptive metric grid. Wide workbench windows show more telemetry columns and make the history/sensor content consume available width while preserving the existing three-pane identity. Minimum window behavior remains stacked.

The unavailable `thermometer.slash` symbol is replaced with a supported symbol. The repository adds `scripts/build-and-run-vifty.sh`, which builds the app bundle and opens it; documentation warns against launching `.build/debug/Vifty` directly.

## Testing

- Pure tests cover Auto-restore results and termination reply policy.
- AppModel tests cover successful and failed stop-and-restore outcomes.
- Notification policy/store tests cover stable identifiers, restart cooldown, private permissions, and baseline suppression.
- Codex tests cover bounded timeout return.
- Layout tests cover telemetry column policy at minimum, workbench, and ultrawide widths.
- Source checks remain only for scene wiring, supported SF Symbol, bundled launcher, and forbidden direct termination/restore duplication.
- Final verification uses focused suites, warnings-as-errors, `make verify`, and `make verify-full` if disk remains above 50Gi.

## External Gates And Non-Goals

- No helper repair/install, fan write, cooling lease, Auto restore, or live mode smoke is part of automated verification.
- No Developer ID certificate import, notarization submission, Homebrew promotion, or trusted-binary claim occurs while the personal team is pending.
- No change is made to the SMC write allowlist, `FanCurve.clamp()`, daemon-first write routing, agent lease policy, or source-first release naming.
- Persistent XPC and a full AppModel decomposition remain follow-up work unless instrumentation proves they are needed now.
