# Contributing to Vifty

Thanks for considering contributing! Vifty is a native macOS utility for Apple Silicon fan control, thermal monitoring, and charger/battery power tracking — with a safety-bounded agent CLI for AI coding workloads.

## Getting Started

### Prerequisites

- macOS 15+ on Apple Silicon
- Xcode 16+ with Swift 6
- Command Line Tools (`xcode-select --install`)

### Build and Test

```sh
# Clone
git clone https://github.com/Reedtrullz/Vifty.git
cd Vifty

# Run tests
swift test

# Build release app bundle
make app CONFIGURATION=release

# Install locally
make install
```

## Project Structure

See [README.md](README.md) for the full layout. Key areas:

| Area | What it does |
|---|---|
| `Sources/ViftyCore/` | Shared models, fan coordinator, SMC client, power telemetry, agent control |
| `Sources/Vifty/` | SwiftUI menu bar app + AppModel |
| `Sources/ViftyDaemon/` | Privileged XPC daemon (runs as root) |
| `Sources/ViftyCtl/` | Agent CLI with bounded workload leases |
| `Sources/ViftyPrivateIOKit/` | C IOKit bridge for HID sensors |
| `Tests/ViftyCoreTests/` | XCTest suite |

## Architecture Rules

1. **Curve resolution happens in `FanControlCoordinator`** — the daemon only receives resolved `fixedRPM` commands. Never pass `temperatureCurve` across XPC.
2. **RPM clamping** — `FanCurve.clamp()` is the single source. All callers must clamp before writing.
3. **Daemon-first, fail-closed writes** — the app tries the daemon first for fan writes. Unprivileged direct SMC writes are refused.
4. **Protocol abstraction** — tests use `FakeHardware` conforming to `HardwareService`. Fan logic lives in the coordinator, not the hardware layer.
5. **Agent control is lease-based** — agents request bounded workload cooling. Never expose raw SMC writes or arbitrary fixed RPM to agent tools.
6. **User Auto-restore wins** — user selecting Auto overrides any active agent lease.

For full conventions, see [AGENTS.md](AGENTS.md).

## Pull Request Process

1. **Open an issue first** for significant changes — discuss the approach before writing code.
2. **Run `swift test`** — all tests must pass.
3. **Add tests** for new functionality or bug fixes.
4. **Keep changes focused** — one concern per PR.
5. **Update documentation** if you change public APIs, CLI flags, or architecture rules.
6. **Sign your commits** — we prefer signed commits.

Tagged public releases follow [docs/release.md](docs/release.md) and require Developer ID signing plus notarization.

## Code Conventions

- `@MainActor` for UI state, actors for mutable shared state
- XPC callbacks are one-shot (guarded by `CallbackState` lock)
- SMC key names are 4-char strings (e.g. `F0Ac`, `Tp09`)
- Fan IDs are 0-indexed Ints matching SMC key suffixes
- Bundle identifier: `tech.reidar.vifty` (app), `tech.reidar.vifty.daemon` (Mach service)

## Questions?

Open a [GitHub Discussion](https://github.com/Reedtrullz/Vifty/discussions) for questions, or open an issue for bugs and feature requests.
