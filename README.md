# Vifty

Native macOS fan control for Apple Silicon MacBook Pros. Reads temperature sensors via SMC and HID, displays them in a menu bar utility, and steers fan speeds through a privileged daemon that survives app restarts.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

V1 intentionally excludes HDD/SSD S.M.A.R.T., Boot Camp, Windows support, analytics, and non-MacBook-Pro hardware. Unsupported hardware is detected and refuses manual control.

## Features

- **Menu bar** — temperature and fan RPM at a glance. Click for details and quick actions.
- **Three fan modes** — Auto (restore system control), Fixed RPM, Temperature Curve (3-point).
- **Curve profiles** — save, name, and switch between multiple fan curve configurations. Profiles persist across restarts.
- **Live temperature panel** — all SMC and HID sensors with source labels.
- **Daemon architecture** — privileged XPC daemon writes SMC keys without repeated permission prompts. Falls back to local SMC if the daemon is unreachable.
- **Safety defaults** — RPM clamping, auto-restore on sensor loss, unclean-exit recovery marker, hardware validation.
- **Helper CLI** — standalone `ViftyHelper` for debugging SMC keys and direct fan writes from the terminal.

## Build

Requires macOS 15, Xcode 16, Swift 6.

```sh
# Run tests
swift test

# Build binaries
swift build -c release

# Build signed .app bundle
make app
```

The app bundle is written to `.build/Vifty.app` and signed ad-hoc (`codesign --sign -`).

## Architecture

```
┌─────────────────────────────────────────────────┐
│ Vifty.app (menu bar + window)                   │
│  SwiftUI ── AppModel ── FanControlCoordinator   │
│                              │                  │
│                    ┌─────────┴─────────┐         │
│                    ▼                   ▼         │
│           ViftyDaemonClient    RealMacHardware  │
│           (XPC, no-auth)      Service (SMC)     │
│                    │                             │
│                    ▼                             │
│           tech.reidar.vifty.daemon              │
│           (root, Mach service)                   │
│                    │                             │
│                    ▼                             │
│               AppleSMC IOKit                     │
└─────────────────────────────────────────────────┘
```

| Package | Type | Role |
|---------|------|------|
| `Vifty` | executable | SwiftUI app — menu bar + window |
| `ViftyCore` | library | Models, SMC client, fan coordinator, daemon protocol |
| `ViftyDaemon` | executable | Privileged XPC daemon — reads SMC, writes fan keys as root |
| `ViftyHelper` | executable | CLI for direct SMC fan control without the daemon |
| `ViftyPrivateIOKit` | library | C/IOKit bridge for HID temperature sensors |

**Data flow:** The app polls every 2 seconds → `FanControlCoordinator` resolves the active mode to per-fan RPM targets → writes go through the daemon (`ViftyDaemon`) which owns the SMC connection as root. If the daemon is unreachable, the app falls back to direct SMC writes via `LocalFanHelperClient`. Curve profiles are persisted as JSON in `~/Library/Application Support/Vifty/`.

## Safety

- Fan RPM targets are clamped to `[minRPM, maxRPM]` per fan.
- Hardware must be Apple Silicon + MacBookPro — anything else gets an empty snapshot and no manual control.
- If temperature sensors disappear mid-curve, fans are restored to Auto.
- An unclean-exit marker file (`~/Library/Application Support/Vifty/manual-control-active`) is written when manual control is active and cleared on clean exit. On next launch, if the marker exists, Vifty restores Auto before starting.

## ViftyHelper CLI

```sh
ViftyHelper probe              # Full hardware snapshot via daemon
ViftyHelper probeLocal         # Direct SMC read (no daemon)
ViftyHelper readKey <key>      # Read raw SMC key (e.g. F0Ac)
ViftyHelper setFixed <id> <rpm> <min> <max>
ViftyHelper auto <id> <min> <max>
ViftyHelper smcDiagnostics     # IOKit service discovery dump
```

## Daemon Installation

The app bundles a LaunchDaemon plist. On first launch:
1. `SMAppService.register()` attempts `Login Items` approval (macOS 13+).
2. Fallback: administrator-prompted install via `osascript` to `/Library/PrivilegedHelperTools/` and `launchctl bootstrap`.

The Reinstall Helper button in the UI retries this flow.

## Project Structure

```
Vifty/
├── Package.swift
├── Makefile
├── Resources/
│   ├── Info.plist
│   └── tech.reidar.vifty.daemon.plist
├── Sources/
│   ├── Vifty/            # Main app target
│   ├── ViftyCore/        # Shared library
│   ├── ViftyDaemon/      # Privileged XPC daemon
│   ├── ViftyHelper/      # CLI helper
│   └── ViftyPrivateIOKit/ # C IOKit bridge
└── Tests/
    └── ViftyCoreTests/   # XCTest suite
```

## Notes

Fan and thermal control uses private macOS SMC/HID interfaces. This app is designed for local signed distribution and is not suitable for the App Store. The daemon uses the `BundleProgram` key which requires manual `PlistBuddy` patching by the installer script — this is a `launchd` quirk for bundled daemon paths.
