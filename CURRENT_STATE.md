# Vifty — source review, 2026-09-25

An implemented macOS thermal-control application with a substantial privileged-service, recovery and release-evidence system. Local source branch: `codex/update-hardware-template`; HEAD `6294feff5dbeadd456d88f447088b76033f66fb0`. Five tracked source/test files were already modified, primarily `DaemonInstallService`, `DaemonInstaller`, `HelperServiceManagementBridge` and their tests. This review describes the working files; it does not certify the commit alone or the installed application.

## Architecture

`Package.swift` specifies Swift tools 6.0, macOS 15+, no third-party package dependencies. The products are `ViftyCore`, `Vifty`, `ViftyHelper`, `ViftyDaemon`, `ViftyCtl` and `ViftyAXCollector`. Internal targets split build provenance, fan-control safety, daemon/helper support and AX evidence; `ViftyPrivateIOKit` bridges C/IOKit, and `ViftyLockTestHelper` is test-only.

`Sources/Vifty/ViftyApp.swift` creates the UI model, menu/window/settings scenes, optional advisory update controller and a special service-management launch path. `AppModel` coordinates UI polling; `RealMacHardwareService` delegates mutations to XPC while allowing read-only telemetry fallback. `ViftyCore` contains domain types, coordinator, daemon-client/protocol, policy and JSON CLI contracts.

`Sources/ViftyDaemon/main.swift` validates incoming XPC identities before exposing `DaemonService`. `ViftyDaemonSupport` owns service/lifecycle/maintenance orchestration. `ViftyFanControlSafety/FanControlArbiter.swift` serializes ownership transitions over an exclusive lock and durable journal; `LocalFanHelperClient` is the SMC writer. Restore requires fresh native telemetry and a complete expected fan set. A successful call is not itself proof of restoration.

`AgentControlPolicy.swift` defaults disabled and evaluates hardware, sensor, topology, duration and RPM constraints. `ViftyCtl` exposes structured diagnostic and bounded workload commands; diagnostics and cooling requests have different effects. `scripts/` handles signing, installation, maintenance, provenance, UI evidence and release verification. Never run those mutation paths just to inspect documentation.

## Local source versus release

The committed `.github/release-manifest.json` records published `v1.4.8`, source `65cc3862beee62dd7abf7a31847988bbec7e37e8`, artifact trust `passed`, and **installed release review/manual compatibility both `pending`**. Those are stored assertions read from a manifest, not new GitHub, Gatekeeper, hardware, or installed-helper checks. The local HEAD and dirty files differ from that release source.

Three linked worktrees were retained under `.worktrees/` at review time; `resolve-review-issues` already had 67 tracked changes. The other two were separate commits for install/maintenance and stability work. Use `git worktree list` for the current identities; do not treat them as interchangeable clean backups.

## Commands and findings

`make test-fast`, `make test-full`, `make verify`, and `make verify-full` are defined in `Makefile`. `verify` bundles/signs local build products as well as checking source; `make install` and repair/uninstall targets affect the machine. Swift scratch output belongs in `.build`. **None of these were executed in this review.**

| Priority | Finding / unresolved boundary |
|---|---|
| High operational | Local source, recorded public release, dirty installer work and linked worktrees have different identities. Picking a directory or trusting a README badge does not establish what is installed or owns fan control. |
| High acceptance | The manifest explicitly keeps exact-release installation/hardware claims pending. Preserve that boundary; older machine evidence cannot close the current release's acceptance rows. |
| Medium maintainability | The existing root target table omitted several safety/support/evidence targets and understated daemon/helper dependencies. It has been refreshed from `Package.swift`; detailed safety rules remain intact. |
| Medium coverage | The most consequential pre-existing edits are in installer/service lifecycle code. They were inspected for purpose and boundaries, not validated as a working repair. Do not infer they are ready to ship. |

Coverage: package target graph, app and daemon entrypoints, hardware service, agent policy/diagnostic models, arbiter/journal code, dirty installer/service-management paths, Makefile, release manifest, test inventory and worktree state. This is not an independent full concurrency/security audit, an execution of release gates, or physical fan validation. See the established `docs/trust-model.md`, `docs/safe-agent-cooling.md`, and `docs/release-status.md` for operational detail.
