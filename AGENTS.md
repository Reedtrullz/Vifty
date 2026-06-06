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
| ViftyCoreTests | test | ViftyCore, Vifty |

ViftyCore links `IOKit.framework` and ViftyPrivateIOKit links it too (C target needs explicit linking).

## Key Files

- `Sources/ViftyCore/Models.swift` — All data types: Fan, TemperatureSensor, HardwareSnapshot, FanCurve, CurveProfile, FanMode, FanCommand, ControlState, ViftyError.
- `Sources/ViftyCore/HardwareService.swift` — `HardwareService` protocol + `FanControlCoordinator` actor + `ManualControlMarker`.
- `Sources/ViftyCore/RealMacHardwareService.swift` — `RealMacHardwareService` (daemon-first SMC reads/writes, local fallback).
- `Sources/ViftyCore/CurveProfileStore.swift` — JSON file persistence for saved curve profiles.
- `Sources/ViftyCore/SMCClient.swift` — IOKit SMC connection, read/write, SMCValue, SMCDecoding (float, FPE2, flt, uint en/decoding).
- `Sources/ViftyCore/FanInfoReader.swift` — Pure SMC fan snapshot parser for hardware Auto/Forced mode and target RPM.
- `Sources/ViftyCore/FanDisplayFormatter.swift` — Pure fan-state display strings for UI rows.
- `Sources/ViftyCore/PowerInfo.swift` — Local IOKit power telemetry parser (`IOPS`, `AppleSmartBattery`, adapter details) + UI formatters.
- `Sources/ViftyCore/ThermalPressure.swift` — macOS thermal-pressure state model and display helpers.
- `Sources/ViftyCore/TelemetryHistory.swift` — In-memory rolling telemetry sample buffer.
- `Sources/ViftyCore/ViftyDaemonClient.swift` — XPC client that talks to the privileged daemon.
- `Sources/ViftyCore/ViftyDaemonProtocol.swift` — `@objc` XPC protocol + `XPCSnapshotCoding` (NSDictionary ↔ HardwareSnapshot).
- `Sources/ViftyDaemon/main.swift` — XPC listener with `DaemonService` exporting the protocol.
- `Sources/ViftyHelper/main.swift` — CLI for `probe`, `readKey`, `setFixed`, `auto`, `smcDiagnostics`.
- `Sources/Vifty/ViftyApp.swift` — `@main` SwiftUI app entry (menu bar extra + window scene).
- `Sources/Vifty/AppModel.swift` — `@MainActor ObservableObject` driving UI polling, fan/profile state, and power snapshot refresh.
- `.github/workflows/ci.yml` — GitHub Actions CI: Swift tests, release app build, plist/code-sign checks, temp install verification, and app artifact upload.
- `scripts/install-vifty.sh` and `Install Vifty.command` — local install path into `/Applications` or `~/Applications`.
- `scripts/build-installer-pkg.sh` — unsigned local `.pkg` builder for reusable installs.

## Architecture Rules

1. **Curve resolution happens in `FanControlCoordinator`** — the daemon only receives resolved `fixedRPM` commands. Never pass `temperatureCurve` across XPC.
2. **RPM clamping** — `FanCurve.clamp()` is the single source. All callers (coordinator, helper, daemon) must clamp before writing.
3. **Daemon-first with fail-closed writes** — `RealMacHardwareService` tries `ViftyDaemonClient` first for all operations. Reads may fall back to local SMC so the UI can still show sensors; fan writes only fall back to `LocalFanHelperClient` for privileged/root callers. The unprivileged app must fail closed and ask for helper reinstall instead of attempting direct AppleSMC writes.
4. **Protocol abstraction** — Tests use a `FakeHardware` actor conforming to `HardwareService`. All fan logic lives in `FanControlCoordinator`, not in the hardware layer.
5. **Sendable safety** — `FanControlCoordinator` is an actor. `RealMacHardwareService` is `@unchecked Sendable` (owns non-Sendable IOKit connection). `CallbackState` uses NSLock for one-shot XPC callback delivery.
6. **Unclean exit recovery** — `ManualControlMarker` writes a file when manual control is active; `recoverIfNeeded()` checks it on next launch.
7. **Profile temp sorting** — `CurveProfile.init()` sorts the three temperature/RPM pairs into ascending order so stored values always match actual curve behavior. The UI sliders can be set in any order; the init normalizes them.
8. **Profile backup** — `CurveProfileStore.save()` copies the existing file to a `.bak` backup before overwriting, protecting against disk-full or interrupted-write corruption.
9. **Power telemetry stays app-local** — `PowerInfoReader` reads IOKit power/battery dictionaries directly; it does not require the privileged fan daemon and should keep parser helpers testable with dictionary fixtures.
10. **Fan hardware state is read-only telemetry** — SMC mode/target fields are surfaced on snapshots and round-tripped through XPC, but fan commands still go through `FanControlCoordinator` and daemon/helper paths.
11. **Telemetry history is in-memory only** — do not persist rolling samples unless a future plan explicitly covers privacy and retention.

## Testing

- `swift test` runs `ViftyCoreTests` (73 tests).
- `FanControlCoordinatorTests` uses `FakeHardware` (actor + `HardwareService`). Covers hardware validation, curve-to-fixed-RPM, missing-sensor recovery, auto-restore, and daemon-fallback regression.
- `FanCurveTests` tests interpolation, clamping, SMC float encode/decode, and SMC known-path coverage.
- `FanInfoReaderTests` tests pure fan hardware-mode/target parsing from synthetic SMC dictionaries.
- `FanDisplayFormatterTests` tests fan hardware-state display strings without SwiftUI inspection.
- `ManualControlMarkerTests` tests sentinel file lifecycle (create, detect, clear, idempotency).
- `RealMacHardwareServiceTests` tests SMC-unavailable snapshot fallback paths and verifies the app does not fall back to unprivileged direct AppleSMC fan writes when the daemon is unavailable.
- `CurveProfileTests` tests toFanCurve() output and init-time temperature sorting.
- `CurveProfileStoreTests` tests JSON round-trip, missing/corrupt file handling, and backup file creation.
- `PowerInfoTests` tests IOKit dictionary parsing for adapter watts, negotiated USB-C voltage/current, PD profiles, signed charge/drain watts, fallback formatting, battery runtime estimates, and plugged-in-but-draining warnings.
- `ThermalPressureTests` tests thermal-pressure labels and elevated menu summaries.
- `TelemetryHistoryTests` tests rolling-buffer trimming and limit clamping.
- `XPCSnapshotCodingTests` tests fan hardware mode/target round trips and older snapshot compatibility.
- `AppModelTests` tests duplicate-profile overwrite, append behavior, curve-defaults sync flag, menu power summaries, injected power-reader polling, timed manual-mode expiry/restores, telemetry-history append, and helper-health summaries.
- Tests must pass before committing. Run from repo root.

## Conventions

- Use `@MainActor` for UI state, actors for mutable shared state.
- XPC callbacks are one-shot (guarded by `CallbackState` lock).
- SMC key names are 4-char strings (e.g. `F0Ac`, `Tp09`).
- Fan IDs are 0-indexed Ints matching SMC key suffixes.
- Temperature sensor IDs are SMC key strings or `hid-<index>`.
- Bundle identifier: `tech.reidar.vifty` (app), `tech.reidar.vifty.daemon` (Mach service).
- UI-facing persistence uses `Codable` + JSON file in `~/Library/Application Support/Vifty/` (see `CurveProfileStore`). No UserDefaults for structured data. Saving a profile with an existing name overwrites it; no duplicate names are permitted.

## New Feature Checklist

- [ ] Model types in `Models.swift` or `PowerInfo.swift` if needed
- [ ] `HardwareService` protocol update if daemon/fan control needs new capability
- [ ] `FanControlCoordinator` logic if it's fan-control flow
- [ ] `ViftyDaemonProtocol` + `XPCSnapshotCoding` if XPC shape changes
- [ ] `DaemonService` implementation on the daemon side
- [ ] `AppModel` + `ContentView`/`MenuBarView` for UI
- [ ] Tests in `ViftyCoreTests`
- [ ] README/AGENTS updates for user-visible features, install changes, or safety behavior
