# AGENTS.md — Vifty

AI coding instructions for working in this repository.

## Build System

- Swift Package Manager (`Package.swift`, tools-version 6.0).
- `swift build` / `swift test` / `make app` (see Makefile).
- macOS 15 minimum deployment target.
- `.build/` is gitignored.

## Target Layout

| Target | Type | Dependencies |
|--------|------|-------------|
| Vifty | executable | ViftyCore |
| ViftyCore | library | ViftyPrivateIOKit |
| ViftyDaemon | executable | ViftyCore |
| ViftyHelper | executable | ViftyCore |
| ViftyPrivateIOKit | C target | IOKit framework |
| ViftyCoreTests | test | ViftyCore |

ViftyCore links `IOKit.framework` and ViftyPrivateIOKit links it too (C target needs explicit linking).

## Key Files

- `Sources/ViftyCore/Models.swift` — All data types: Fan, TemperatureSensor, HardwareSnapshot, FanCurve, CurveProfile, FanMode, FanCommand, ControlState, ViftyError.
- `Sources/ViftyCore/HardwareService.swift` — `HardwareService` protocol + `FanControlCoordinator` actor + `ManualControlMarker`.
- `Sources/ViftyCore/RealMacHardwareService.swift` — `RealMacHardwareService` (daemon-first SMC reads/writes, local fallback).
- `Sources/ViftyCore/CurveProfileStore.swift` — JSON file persistence for saved curve profiles.
- `Sources/ViftyCore/SMCClient.swift` — IOKit SMC connection, read/write, SMCValue, SMCDecoding (float, FPE2, flt, uint en/decoding).
- `Sources/ViftyCore/ViftyDaemonClient.swift` — XPC client that talks to the privileged daemon.
- `Sources/ViftyCore/ViftyDaemonProtocol.swift` — `@objc` XPC protocol + `XPCSnapshotCoding` (NSDictionary ↔ HardwareSnapshot).
- `Sources/ViftyDaemon/main.swift` — XPC listener with `DaemonService` exporting the protocol.
- `Sources/ViftyHelper/main.swift` — CLI for `probe`, `readKey`, `setFixed`, `auto`, `smcDiagnostics`.
- `Sources/Vifty/ViftyApp.swift` — `@main` SwiftUI app entry (menu bar extra + window scene).
- `Sources/Vifty/AppModel.swift` — `@MainActor ObservableObject` driving the UI polling loop and profile management.

## Architecture Rules

1. **Curve resolution happens in `FanControlCoordinator`** — the daemon only receives resolved `fixedRPM` commands. Never pass `temperatureCurve` across XPC.
2. **RPM clamping** — `FanCurve.clamp()` is the single source. All callers (coordinator, helper, daemon) must clamp before writing.
3. **Daemon-first** — `RealMacHardwareService` tries `ViftyDaemonClient` first for all operations; falls back to `LocalFanHelperClient` (direct SMC) if the daemon is unreachable. This applies to both reads (`snapshot()`) and writes (`apply()`, `restoreAuto()`).
4. **Protocol abstraction** — Tests use a `FakeHardware` actor conforming to `HardwareService`. All fan logic lives in `FanControlCoordinator`, not in the hardware layer.
5. **Sendable safety** — `FanControlCoordinator` is an actor. `RealMacHardwareService` is `@unchecked Sendable` (owns non-Sendable IOKit connection). `CallbackState` uses NSLock for one-shot XPC callback delivery.
6. **Unclean exit recovery** — `ManualControlMarker` writes a file when manual control is active; `recoverIfNeeded()` checks it on next launch.

## Testing

- `swift test` runs `ViftyCoreTests`.
- `FanControlCoordinatorTests` uses `FakeHardware` (actor + `HardwareService`). Covers hardware validation, curve-to-fixed-RPM, missing-sensor recovery, auto-restore, and daemon-fallback regression.
- `FanCurveTests` tests interpolation, clamping, SMC float encode/decode, and SMC known-path coverage.
- `ManualControlMarkerTests` tests sentinel file lifecycle (create, detect, clear, idempotency).
- `RealMacHardwareServiceTests` tests SMC-unavailable fallback paths.
- Tests must pass before committing. Run from repo root.

## Conventions

- Use `@MainActor` for UI state, actors for mutable shared state.
- XPC callbacks are one-shot (guarded by `CallbackState` lock).
- SMC key names are 4-char strings (e.g. `F0Ac`, `Tp09`).
- Fan IDs are 0-indexed Ints matching SMC key suffixes.
- Temperature sensor IDs are SMC key strings or `hid-<index>`.
- Bundle identifier: `tech.reidar.vifty` (app), `tech.reidar.vifty.daemon` (Mach service).
- UI-facing persistence uses `Codable` + JSON file in `~/Library/Application Support/Vifty/` (see `CurveProfileStore`). No UserDefaults for structured data.

## New Feature Checklist

- [ ] Model types in `Models.swift` if needed
- [ ] `HardwareService` protocol update if daemon needs new capability
- [ ] `FanControlCoordinator` logic if it's control-flow
- [ ] `ViftyDaemonProtocol` + `XPCSnapshotCoding` if XPC shape changes
- [ ] `DaemonService` implementation on the daemon side
- [ ] `AppModel` + `ContentView` for UI
- [ ] Tests in `ViftyCoreTests`
