# Vifty

Native macOS menu-bar fan control and charger-power monitoring for Apple Silicon MacBook Pros. Vifty combines live thermals, fan RPM control, reusable temperature curves, and USB-C/MagSafe power telemetry in one local-first SwiftUI utility.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

Vifty is built for local signed distribution, not the App Store. It uses private macOS SMC/HID interfaces for fan and sensor access, keeps data on-device, and refuses manual control on unsupported hardware.

## Highlights

- **Menu bar cockpit** — temperature, fan RPM, and power state at a glance.
- **Three fan modes** — Auto, Fixed RPM, and a 3-point Temperature Curve.
- **Curve profiles** — save, name, switch, overwrite, and delete fan curves; profiles persist across restarts.
- **Live temperature panel** — all SMC and HID sensors with source labels and highest-temperature tracking.
- **Live power tracking** — battery percentage, charge/drain watts, signed battery current, adapter wattage, negotiated USB-C voltage/current, health, cycle count, battery temperature, and USB-C PD profiles from local IOKit data.
- **Privileged helper architecture** — a LaunchDaemon/XPC helper owns root SMC writes so the app does not need repeated permission prompts.
- **Installer workflow** — double-click `Install Vifty.command`, run `make install`, or build a reusable `.pkg`.
- **Safety defaults** — RPM clamping, unsupported-hardware refusal, auto-restore on sensor loss, and unclean-exit recovery.
- **Debug helper CLI** — `ViftyHelper` can probe SMC state and restore Auto from Terminal.

## Supported scope

V1 targets Apple Silicon MacBook Pro models on macOS 15+. It intentionally excludes HDD/SSD S.M.A.R.T., Boot Camp, Windows support, analytics, cloud sync, and non-MacBook-Pro fan control. Unsupported Macs should remain under macOS automatic fan control.

## Install and launch

For normal local use:

1. Double-click **`Install Vifty.command`** in this repository. It builds a release app, installs it, registers it with Launch Services, and launches Vifty.
2. Or run:

   ```sh
   make install
   ```

After installation, start Vifty from Spotlight, Launchpad, Finder, or Terminal:

```sh
open /Applications/Vifty.app
```

`make install` installs to `/Applications/Vifty.app` when writable and falls back to `~/Applications/Vifty.app` otherwise. If you want a reusable installer file, run `make pkg` and open the generated `.build/Vifty-<version>.pkg`.

## Build and verify

Requires macOS 15, Xcode 16, and Swift 6.

```sh
# Run the XCTest suite
swift test

# Build an ad-hoc-signed app bundle at .build/Vifty.app
make app CONFIGURATION=release

# Install the release app bundle
make install

# Optional: build an unsigned local installer package in .build/
make pkg
```

The app bundle is signed ad-hoc with `codesign --sign -`. The local `.pkg` is unsigned and intended for local development/test installs; the app inside remains ad-hoc signed.

## Power tracking

The power panel is inspired by projects like [`MacBook-Charger-Power-Indicator`](https://github.com/unrelatedlabs/MacBook-Charger-Power-Indicator), but Vifty keeps the implementation inside its existing Swift/IOKit model layer. `PowerInfoReader` gathers:

- `IOPSCopyPowerSourcesInfo` battery status and time estimates.
- `AppleSmartBattery` registry values for voltage, signed amperage, capacity, cycles, condition, and temperature.
- `IOPSCopyExternalPowerAdapterDetails` adapter wattage, USB-C PD negotiation, manufacturer/model metadata, and advertised PD profiles.

The UI displays a compact menu-bar summary (`96 W adapter`, `16.9 W drain`, etc.) plus a detailed Power panel next to the temperature sensors. Power telemetry is read locally and does not require the privileged fan helper.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│ Vifty.app (SwiftUI menu bar + window)                      │
│  AppModel                                                  │
│   ├─ PowerInfoReader ── local IOKit power/battery data     │
│   └─ FanControlCoordinator                                 │
│        ├─ ViftyDaemonClient ── XPC ── root LaunchDaemon    │
│        └─ RealMacHardwareService ── local SMC fallback     │
│                                                            │
│ ViftyDaemon                                                │
│  tech.reidar.vifty.daemon ── AppleSMC IOKit                │
└────────────────────────────────────────────────────────────┘
```

| Package | Type | Role |
|---------|------|------|
| `Vifty` | executable | SwiftUI menu bar app and main window |
| `ViftyCore` | library | Models, SMC client, fan coordinator, power snapshots, daemon protocol |
| `ViftyDaemon` | executable | Privileged XPC daemon that reads/writes fan SMC keys as root |
| `ViftyHelper` | executable | CLI for direct SMC probing and emergency fan restoration |
| `ViftyPrivateIOKit` | library | C/IOKit bridge for HID temperature sensors |

**Data flow:** the app polls every 2 seconds. Fan control resolves the selected mode into per-fan RPM targets, then writes through the daemon when available. Power telemetry is read directly from local macOS IOKit dictionaries. Curve profiles are persisted as JSON in `~/Library/Application Support/Vifty/`.

## Safety and privacy

- Fan RPM targets are clamped to `[minRPM, maxRPM]` per fan.
- Hardware must be Apple Silicon + MacBookPro before manual fan control is enabled.
- If temperature sensors disappear mid-curve, Vifty restores Auto.
- An unclean-exit marker (`~/Library/Application Support/Vifty/manual-control-active`) is written while manual control is active; the next launch restores Auto before continuing.
- Curve profiles are stored in `~/Library/Application Support/Vifty/curve-profiles.json` with a `.bak` backup before each save.
- Power and thermal telemetry stays on the Mac. There are no analytics, accounts, network uploads, or cloud dependencies.

## Fail-safe recovery

If manual fan control misbehaves, restore Auto before trying anything else:

1. In the Vifty UI, select **Auto** in the Mode picker and click **Apply**.
2. If the UI is unavailable, use the helper CLI from the repo root after building release binaries. First inspect supported fans and their limits:

   ```sh
   sudo .build/release/ViftyHelper probeLocal
   ```

   Then restore Auto for each fan ID using its reported minimum and maximum RPM:

   ```sh
   sudo .build/release/ViftyHelper auto 0 <minRPM> <maxRPM>
   sudo .build/release/ViftyHelper auto 1 <minRPM> <maxRPM>
   ```

3. To stop the privileged daemon while troubleshooting, unload it from launchd:

   ```sh
   sudo launchctl bootout system /Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
   ```

4. If fan state is still unclear, reboot macOS so the firmware/system controller and launchd return to normal startup state.

Do not run manual fan control on unsupported hardware.

## ViftyHelper CLI

```sh
ViftyHelper probe              # Full hardware snapshot via daemon
ViftyHelper probeLocal         # Direct SMC read (no daemon)
ViftyHelper readKey <key>      # Read raw SMC key, e.g. F0Ac
ViftyHelper setFixed <id> <rpm> <min> <max>
ViftyHelper auto <id> <min> <max>
ViftyHelper smcDiagnostics     # IOKit service discovery dump
```

## Daemon installation

The app bundles a LaunchDaemon plist. On first launch:

1. `SMAppService.register()` attempts Login Items approval on macOS 13+.
2. Fallback: administrator-prompted install via `osascript` to `/Library/PrivilegedHelperTools/` plus `launchctl bootstrap`.

The **Reinstall Helper** button retries this flow. The bundled LaunchDaemon plist uses `BundleProgram`, which the installer patches with `PlistBuddy` so launchd points at the daemon inside the installed app bundle.

## Project structure

```
Vifty/
├── Install Vifty.command       # Double-click installer launcher
├── Makefile                    # app/install/pkg targets
├── Package.swift
├── Resources/
│   ├── Info.plist
│   └── tech.reidar.vifty.daemon.plist
├── scripts/
│   ├── build-installer-pkg.sh
│   └── install-vifty.sh
├── Sources/
│   ├── Vifty/                  # Main app target
│   ├── ViftyCore/              # Shared models, fan control, SMC, power telemetry
│   ├── ViftyDaemon/            # Privileged XPC daemon
│   ├── ViftyHelper/            # CLI helper
│   └── ViftyPrivateIOKit/      # C IOKit bridge
└── Tests/
    └── ViftyCoreTests/         # XCTest suite
```

## License

MIT. See [LICENSE](LICENSE).
