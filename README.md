# Vifty

Native macOS menu-bar fan control and charger-power monitoring for Apple Silicon MacBook Pros. Vifty combines live thermals, fan RPM control, reusable temperature curves, and USB-C/MagSafe power telemetry in one local-first SwiftUI utility.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
[![CI](https://github.com/Reedtrullz/Vifty/actions/workflows/ci.yml/badge.svg)](https://github.com/Reedtrullz/Vifty/actions/workflows/ci.yml)
![Architecture](https://img.shields.io/badge/architecture-Apple%20Silicon-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

Vifty is built for local signed distribution, not the App Store. It uses private macOS SMC/HID interfaces for fan and sensor access, keeps data on-device, and refuses manual control on unsupported hardware.

![Vifty screenshot showing menu bar, fan controls, power telemetry, temperature sensors, and thermal history](docs/images/vifty-screenshot.png)

## Highlights

- **Menu bar cockpit** — temperature, fan RPM, and power state at a glance.
- **Three fan modes** — Auto, Fixed RPM, and a 3-point Temperature Curve.
- **Curve profiles** — save, name, switch, overwrite, and delete fan curves, including per-fan RPM overrides; profiles persist across restarts.
- **Developer presets** — conservative curve presets for tests, builds, and local model runs.
- **Hardware fan state** — shows actual SMC Auto/Forced/System mode and target RPM when available.
- **Live temperature panel** — all SMC and HID sensors with source labels and highest-temperature tracking.
- **Live power tracking** — battery percentage, charge/drain watts, signed battery current, adapter wattage, negotiated USB-C voltage/current, health, cycle count, battery temperature, and USB-C PD profiles from local IOKit data.
- **Thermal pressure** — surfaces macOS thermal-pressure state alongside raw temperatures.
- **Timed manual modes** — Fixed RPM and Temperature Curve modes can automatically restore Auto after a selected duration.
- **Power insights** — estimates battery runtime from live drain and warns when plugged in but still draining.
- **Telemetry history** — keeps a local in-memory rolling history for recent temperature, fan, power, and thermal-pressure state.
- **Privileged helper architecture** — a LaunchDaemon/XPC helper owns root SMC writes so the app does not need repeated permission prompts.
- **Helper health summary** — distinguishes healthy helper fan data from helper errors, unreachable daemon state, and empty snapshots, with recovery guidance when fan control is not safe to start.
- **Agent-friendly cooling leases** — local agents can use bundled `viftyctl` JSON commands to inspect readiness, request bounded temporary cooling for builds/tests, and restore Auto with visible state and daemon-owned expiry.
- **Installer workflow** — double-click `Install Vifty.command`, run `make install`, or build a reusable `.pkg`.
- **Safety defaults** — RPM clamping, unsupported-hardware refusal, auto-restore on sensor loss, and unclean-exit recovery.
- **Debug helper CLI** — `ViftyHelper` can probe SMC state and restore Auto from Terminal.

## Why Vifty matters

Mac fan control has been dominated by proprietary closed-source tools for years. Vifty is different:

- **Open-source and auditable** — every SMC write path, RPM clamp, and safety check is visible. You can verify that fan control does exactly what it claims.
- **Agent-safe by design** — the `viftyctl` agent CLI is a purpose-built open-source thermal management interface for AI coding agents. Leases carry bounded durations, reasons, idempotency keys, policy metadata, and retry-after signals; the daemon enforces expiry independently.
- **Combined fan + power + telemetry** — instead of running separate tools for fan control, battery monitoring, and thermal pressure, Vifty gives you a single local-first utility with zero cloud dependencies.
- **Privileged helper architecture** — the root daemon owns SMC writes so the app never needs repeated permission prompts, and unprivileged direct AppleSMC writes are refused (fail-closed).

If you use Apple Silicon for builds, tests, or AI workloads, Vifty keeps your machine cool and your fan control auditable.

## Supported scope

V1 targets Apple Silicon MacBook Pro models on macOS 15+. Compatibility claims are evidence-based; see [docs/compatibility.md](docs/compatibility.md) for the current validation status and [docs/hardware-validation.md](docs/hardware-validation.md) for the report procedure.

Vifty intentionally excludes HDD/SSD S.M.A.R.T., Boot Camp, Windows support, analytics, cloud sync, and non-MacBook-Pro fan control. Unsupported Macs should remain under macOS automatic fan control; see [docs/unsupported-hardware.md](docs/unsupported-hardware.md) for the safe-block policy.

For help or reports, start with [SUPPORT.md](SUPPORT.md). Maintainers should triage reports with [docs/support-triage.md](docs/support-triage.md) so release, hardware, helper, SMC telemetry, agent-cooling, and UI issues stay evidence-based.

## Install and launch

### Current release trust status

Vifty `v1.1.0` is a source-first release because the project does not currently have Apple Developer Program credentials. The recommended path is to build from source. There is no Developer ID signed or notarized public binary for `v1.1.0`, and the canonical notarized artifact name `Vifty-v1.1.0.zip` is reserved for a future Developer ID release.

An optional `Vifty-v1.1.0-unsigned-dev.zip` convenience app may be attached to the GitHub Release for testers. It is ad-hoc signed, not notarized, not the official trusted binary, and macOS may show Gatekeeper warnings. See [docs/release-status.md](docs/release-status.md) before treating any binary path as trusted.

### From source

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

### Unsigned tester zip

For v1.1.0 tester convenience only:

```sh
make source-first-release-notes
make unsigned-dev-artifact
make source-first-readiness
```

This writes `.build/Vifty-v1.1.0-source-first-release-notes.md`, creates `.build/Vifty-v1.1.0-unsigned-dev.zip` plus `.build/Vifty-v1.1.0-unsigned-dev.zip.sha256`, and checks the published source-first GitHub Release state. Do not rename the unsigned artifact to `Vifty-v1.1.0.zip`; that name is reserved for a future signed and notarized release.

### Homebrew

```sh
brew tap Reedtrullz/vifty https://github.com/Reedtrullz/Vifty
brew install --cask vifty
```

Do not use Homebrew as the recommended or trusted `v1.1.0` install path. The Homebrew cask is for the future Developer ID/notarized release lane and should not be updated to point at the unsigned-dev artifact. For public binary trust, a future cask artifact must pass `scripts/verify-release-artifact.sh --team-id <TEAMID>` after a signed/notarized release checksum is published.

## Build and verify

Requires macOS 15, Xcode 16, and Swift 6.

```sh
# Run local trust gates: community/support surface, release metadata, tests,
# warnings-as-errors, release bundle, plist lint, codesign verification,
# and viftyctl identifier check
make verify

# Run the XCTest suite
swift test

# Build an ad-hoc-signed app bundle at .build/Vifty.app
make app CONFIGURATION=release

# Build the optional source-first unsigned tester zip and checksum
make unsigned-dev-artifact

# Write source-first release notes and check the published release lane
make source-first-release-notes
make source-first-readiness

# Install the release app bundle
make install

# Optional: build an unsigned local installer package in .build/
make pkg
```

GitHub Actions runs the same verification on every push to `main`, every pull request targeting `main`, and manual `workflow_dispatch`: Swift tests, release app bundle build, plist validation, ad-hoc code-signature verification, temporary install-script verification, and a zipped `Vifty.app` artifact upload.

The app bundle is signed ad-hoc with `codesign --sign -`. The local `.pkg` is unsigned and intended for local development/test installs; the app inside remains ad-hoc signed.

Source-first releases use `make source-first-release-notes`, `make unsigned-dev-artifact`, and `make source-first-readiness`; the readiness target calls `scripts/check-release-readiness.sh --mode source-first` and allows only clearly named `Vifty-v<version>-unsigned-dev.zip` convenience builds. Tagged public Developer ID releases use the separate [release workflow](docs/release.md), which requires Developer ID signing, TeamID XPC allowlisting, Apple notarization, stapling, and SHA-256 checksum publication.

After a public release artifact and cask checksum are published, `scripts/verify-release-artifact.sh --team-id <TEAMID>` verifies the cask SHA, bundle version, bundled release and agent JSON Schemas and stable IDs, signing TeamID, LaunchDaemon TeamID allowlist, stapled notarization ticket, and Gatekeeper assessment. The release workflow publishes a JSON artifact summary and release checklist for reviewer evidence, and `scripts/collect-validation-evidence.sh --release-summary <path> --release-checklist <path>` can copy those files into hardware-validation bundles while marking the release-summary row nonzero for skipped or failed verifier checks, checksum mismatches, artifact-name drift, schema drift, or version mismatch, and marking the release-checklist row nonzero for version drift or missing follow-up sections.

## Power tracking

The power panel is inspired by projects like [`MacBook-Charger-Power-Indicator`](https://github.com/unrelatedlabs/MacBook-Charger-Power-Indicator), but Vifty keeps the implementation inside its existing Swift/IOKit model layer. `PowerInfoReader` gathers:

- `IOPSCopyPowerSourcesInfo` battery status and time estimates.
- `AppleSmartBattery` registry values for voltage, signed amperage, capacity, cycles, condition, and temperature.
- `IOPSCopyExternalPowerAdapterDetails` adapter wattage, USB-C PD negotiation, manufacturer/model metadata, and advertised PD profiles.

The UI displays a compact menu-bar summary (`96 W adapter`, `16.9 W drain`, etc.) plus a detailed Power panel next to the temperature sensors. Power telemetry is read locally and does not require the privileged fan helper. When live drain and capacity data are available, Vifty estimates time remaining and warns if the Mac is plugged in but the battery is still draining.

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
| `ViftyCtl` | executable | Agent-friendly JSON CLI for bounded cooling leases |
| `ViftyPrivateIOKit` | library | C/IOKit bridge for HID temperature sensors |

**Data flow:** the app polls every 2 seconds. Fan control resolves the selected mode into per-fan RPM targets, then writes through the daemon when available. Power telemetry is read directly from local macOS IOKit dictionaries. Curve profiles are persisted as JSON in `~/Library/Application Support/Vifty/`.

## Safety and privacy

For the detailed privileged-helper and agent-control boundaries, see [docs/trust-model.md](docs/trust-model.md).

- Fan RPM targets are clamped to `[minRPM, maxRPM]` per fan.
- Low-level SMC writes are allowlisted to Vifty's fan mode, fan target, and guarded force-test keys.
- Hardware must be Apple Silicon + MacBookPro before manual fan control is enabled.
- Manual fan modes can be time-limited so Vifty restores Auto automatically.
- The UI distinguishes Vifty's selected mode from the hardware-reported SMC mode when that SMC key is available.
- If temperature sensors disappear mid-curve, Vifty restores Auto.
- An unclean-exit marker (`~/Library/Application Support/Vifty/manual-control-active`) is written while manual control is active; the next launch restores Auto before continuing.
- Curve profiles are stored in `~/Library/Application Support/Vifty/curve-profiles.json` with a `.bak` backup before each save.
- Power, thermal, and telemetry-history data stay on the Mac. The telemetry history is in-memory only; there are no analytics, accounts, network uploads, or cloud dependencies.

### Optional: Harden XPC with your TeamID

By default Vifty accepts any ad-hoc-signed binary with the correct signing identifier over XPC — this keeps the project buildable by anyone who clones it. If you have an Apple Developer account, you can lock the daemon to only accept binaries signed by your team:

1. Find your TeamID: `make app CONFIGURATION=release SIGNING_IDENTITY="Apple Development"` then `codesign -dvvv .build/Vifty.app 2>&1 | grep TeamIdentifier`
2. Build with your identity and TeamID: `make app CONFIGURATION=release SIGNING_IDENTITY="Apple Development" VIFTY_XPC_ALLOWED_TEAM_ID="<TEAMID>"`
3. Verify the daemon plist contains `VIFTY_XPC_ALLOWED_TEAM_ID`: `plutil -p .build/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist`

When `VIFTY_XPC_ALLOWED_TEAM_ID` is set, the root daemon only accepts XPC clients with Vifty's signing identifiers and that TeamID. Leave it empty for local ad-hoc development builds.

## Fail-safe recovery

If manual fan control misbehaves, restore Auto before trying anything else:

> `AppleSMC call failed with kIOReturnNotPrivileged (-536870207)` means macOS rejected a direct fan write because it was not running through the privileged helper/root path. In the app, use **Reinstall Helper** and approve the helper if System Settings asks. From Terminal, direct `ViftyHelper setFixed` / `auto` writes require `sudo`.

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

Do not run manual fan control on unsupported hardware. Follow [docs/unsupported-hardware.md](docs/unsupported-hardware.md) instead.

## ViftyHelper CLI

```sh
ViftyHelper probe              # Full hardware snapshot via daemon
ViftyHelper probeLocal         # Direct SMC read (no daemon)
ViftyHelper readKey <key>      # Read raw SMC key, e.g. F0Ac
ViftyHelper setFixed <id> <rpm> <min> <max>
ViftyHelper auto <id> <min> <max>
ViftyHelper smcDiagnostics     # IOKit service discovery dump
```

## viftyctl agent CLI

`viftyctl` is bundled at:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl
```

It is designed for local AI/coding agents and shell automation. It exposes structured JSON and bounded workload leases rather than arbitrary raw SMC writes:

```sh
viftyctl status --json
viftyctl capabilities --json
viftyctl diagnose --json
viftyctl audit --limit 20 --json
viftyctl prepare --workload build --duration 25m --max-rpm-percent 75 --reason "Swift release build" --idempotency-key "$(uuidgen)" --json
viftyctl restore-auto --reason "workload complete" --json
viftyctl run --workload test --duration 20m --max-rpm-percent 70 --reason "swift test" -- swift test
```

`--idempotency-key` belongs to `prepare` / `run` lease requests only. `restore-auto` is intentionally not key-scoped; keep it in the same supervised lifecycle that prepared cooling.

`capabilities --json` returns the supported commands, supported workload names, source schema paths, installed bundle schema resource paths, stable schema IDs, shell exit-code meanings, `runLifecycle` guarantees for `viftyctl run`, `supportsForceRetry`, and daemon policy limits such as max lease duration, allowed RPM percent range, and prepare cooldown. If the daemon status cannot be read, it still prints the static command contract with `daemonStatusAvailable: false`, `policySource: "fallbackUnavailable"`, a disabled fallback policy, and exits with `exitCodes.unavailable`. Rate-limited decisions include `retryAfterSeconds` so supervised agents can wait without parsing human text only when `supportsForceRetry` is true.

`diagnose --json` is a read-only readiness report for agents, release testers, and hardware validation. It combines daemon snapshot telemetry, thermal pressure, fan hardware mode/target data, agent policy/status, explicit `ready` / `degraded` / `blocked` checks, and machine-readable `recommendedAgentAction` / `safeToRequestCooling` fields, including invalid or duplicate controllable fan IDs. If the daemon snapshot or agent-control status cannot be read, the command still emits a structured `blocked` report with `daemonSnapshotAvailable` / `agentControlStatusAvailable` failure checks and exits 75 after printing JSON. See [docs/hardware-validation.md](docs/hardware-validation.md) for the release-test matrix, [docs/unsupported-hardware.md](docs/unsupported-hardware.md) for blocked unsupported Macs, and use the GitHub Hardware Validation Report issue template when contributing compatibility evidence.

`audit --json` is a read-only local audit export for recent agent lease events. It returns `readOnly: true`, `coolingCommandsRun: false`, the requested `limit`, `eventCount`, and timestamped events with action, optional lease ID, and message. Use it after blocked readiness or restore failures to show what Vifty actually did without requesting cooling.

For the short runbook, see [docs/safe-agent-cooling.md](docs/safe-agent-cooling.md). For a fuller contract, decision rules, canonical JSON examples, and ready-to-run wrappers for Swift, Xcode, Make, npm, cargo, pytest, and local model workloads, see [docs/agent-workflows.md](docs/agent-workflows.md) and [examples/viftyctl](examples/viftyctl/README.md). For Codex, Claude Code, Cursor, and shell-runner snippets, see [docs/agent-integrations.md](docs/agent-integrations.md).

For commands with `--json`, daemon/transport failures return a structured error object with `command`, `errorCode`, `message`, and `safeToProceed: false` instead of plain stderr text. Unknown, duplicate, or unexpected wrapper arguments fail with `INVALID_ARGUMENTS` instead of being ignored or silently choosing one value. `PREPARE_RATE_LIMITED` command errors include `retryAfterSeconds` when Vifty can report a retry wait. For `viftyctl run --json`, wrapper failures before the child starts, such as child-command resolution, prepare denial, or launch failure after a prepared lease, use the same structured error shape. Child command resolution/launch failures use `CHILD_COMMAND_FAILED` so agents do not confuse workload command problems with Vifty helper failures. If launch fails after cooling was prepared, the JSON also reports `coolingLeasePrepared`, `autoRestoreAttempted`, and `autoRestoreSucceeded` so agents can tell whether cleanup ran. Child output and post-child restore errors keep the normal wrapper exit/stderr behavior. Human-readable invocations keep the normal stderr failure path.

Safety rules:

- Agent control is local-only through the signed CLI and privileged daemon.
- Every prepare request carries a bounded duration and reason; the default daemon policy caps leases at 30 minutes, and the CLI supplies a default reason when one is omitted.
- `viftyctl prepare` exits nonzero when the daemon denies cooling or fails to return a matching active lease; `--json` still prints the structured status for automation.
- Expired leases stay visible in agent status and block new prepares until the daemon actually restores Auto, so automation can detect delayed or retried restores.
- RPM targets are computed from each fan's min/max range and clamped by policy.
- Invalid or duplicate controllable fan IDs block agent cooling before Vifty reaches the SMC write path.
- User Auto restore wins over active and in-flight agent cooling; a preempted prepare reports `RESTORE_REQUESTED`.
- `viftyctl run` resolves the child executable before preparing a lease, refuses to launch if prepare does not return a matching active lease, launches the resolved path, forwards common terminal/session signals to the child, and restores Auto on child launch failure, normal exit, or handled signal exit. Restore failures are surfaced on stderr and make an otherwise-successful wrapper exit nonzero; if the wrapper is force-killed or crashes, the daemon-owned lease monitor is the safety fallback.
- Sensor loss, unsupported hardware, helper uncertainty, or critical thermal pressure refuses or restores control.
- Agents should run `viftyctl diagnose --json` before long build/test workloads, use `safeToRequestCooling` as the hard machine-readable gate, and follow `recommendedAgentAction` for normal, caution, restore-first, or stop behavior.

### Rate limiting

A 30-second cooldown (configurable via `prepareCooldownSeconds` in `AgentControlPolicy`) prevents rapid prepare/restore cycles from thrashing fan RPM. Repeated calls within the window return `prepareRateLimited` error with retry-after metadata.

For human use, `--force` retries once after the cooldown expires:

```sh
viftyctl prepare --workload build --duration 25m --max-rpm-percent 75 --force --reason "build" --json
viftyctl run --workload test --duration 20m --max-rpm-percent 70 --force -- swift test
```

## Daemon installation

The app bundles a LaunchDaemon plist. On first launch:

1. `SMAppService.register()` attempts Login Items approval on macOS 13+.
2. Fallback: administrator-prompted install via `osascript` to `/Library/PrivilegedHelperTools/` plus `launchctl bootstrap`.

The **Reinstall Helper** button retries this flow. The bundled LaunchDaemon plist uses `BundleProgram`, which the installer patches with `PlistBuddy` so launchd points at the daemon inside the installed app bundle. The fallback installer sets the helper and LaunchDaemon plist to `root:wheel` ownership, with the executable at `0755` and plist at `0644`, and pre-creates the daemon log files as `0600 root:wheel` before bootstrapping launchd.

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
│   ├── ViftyCtl/               # Agent-friendly JSON CLI
│   ├── ViftyDaemon/            # Privileged XPC daemon
│   ├── ViftyHelper/            # CLI helper
│   └── ViftyPrivateIOKit/      # C IOKit bridge
└── Tests/
    └── ViftyCoreTests/         # XCTest suite
```

## License

MIT. See [LICENSE](LICENSE).
