# Trust Model

Vifty controls fans through private macOS SMC interfaces, so trust has to be explicit. This document describes what runs with privilege, what can write fan state, what agents can request, and what Vifty refuses to do.

## Summary

- The SwiftUI app and `viftyctl` run unprivileged.
- The LaunchDaemon runs as root and owns normal SMC fan writes.
- Direct helper fan writes require a privileged/root caller and are for probing or emergency recovery.
- Fan writes are narrow: fan mode keys, fan target keys, and the guarded force-test key only.
- Agents request bounded cooling intent. They do not get raw SMC write access.
- Power, thermal, profile, telemetry, and agent state stay local to the Mac.
- Public releases should be Developer ID signed, notarized, stapled, and TeamID-gated over XPC.

## Privileged Components

| Component | Privilege | Purpose |
| --- | --- | --- |
| `Vifty.app` | User | SwiftUI menu bar app, polling, profile selection, power telemetry, and user controls |
| `viftyctl` | User | Agent/build/test CLI for status, diagnostics, bounded cooling leases, and restore requests |
| `ViftyDaemon` | Root LaunchDaemon | XPC endpoint that reads snapshots and applies validated fan commands |
| `ViftyHelper` | User or root depending on caller | Local SMC probe and emergency fan restore tool; fan writes require a privileged/root path |

The normal app path is daemon-first. If the daemon is unavailable, the unprivileged app fails closed for fan writes instead of attempting direct AppleSMC writes.

## XPC Boundary

The daemon accepts XPC clients by signing identity:

- `tech.reidar.vifty` for the app.
- `tech.reidar.vifty.ctl` for `viftyctl`.

Local ad-hoc builds leave `VIFTY_XPC_ALLOWED_TEAM_ID` empty so contributors can build the project. Public release builds should set `VIFTY_XPC_ALLOWED_TEAM_ID` so the daemon also requires the configured Apple Developer TeamID.

Platform-binary status does not bypass Vifty's signing identifier checks.

## SMC Write Boundary

Low-level SMC writes are allowlisted. `SMCClient.write()` rejects arbitrary keys before it reaches IOKit.

Allowed write keys:

- `F{n}Md` - fan mode key candidate.
- `F{n}md` - lowercase fan mode key candidate seen on some Apple Silicon hardware.
- `F{n}Tg` - fan target RPM key.
- `Ftst` - guarded force-test key used only by helper retry/recovery paths.

Fan IDs must be single decimal digits `0` through `9`. RPM targets are clamped to each fan's reported `[minimumRPM, maximumRPM]` range before writing.

Vifty does not expose arbitrary SMC writes through the app, daemon, helper policy path, or `viftyctl`.

## User Fan Control Flow

The UI can request Auto, Fixed RPM, or Temperature Curve mode. Curves are resolved inside `FanControlCoordinator` before the daemon sees a command. The daemon receives resolved fixed-RPM commands or Auto restore commands, not raw temperature curves.

Vifty refuses or restores control when safety inputs are not trustworthy, including:

- unsupported hardware;
- missing temperature sensors;
- missing controllable fans;
- invalid or duplicate fan IDs;
- invalid fan RPM ranges;
- critical thermal pressure;
- sensor loss during curve or lease control;
- helper or daemon uncertainty on fan writes.

Unsupported-hardware behavior is defined in [unsupported-hardware.md](unsupported-hardware.md). A safe block keeps the Mac under macOS Auto, reports `safeToRequestCooling: false`, and must not be bypassed with helper or raw SMC fan writes.

Manual control uses an unclean-exit marker so the next launch can restore Auto if Vifty exited while manual fan control was active.

## Agent Cooling Flow

`viftyctl` is an intent interface for local agents and build scripts. Agents can inspect status, capabilities, and readiness, then request a bounded lease for a known workload type.

The short operational guide for agent and script authors is [safe-agent-cooling.md](safe-agent-cooling.md).

Agent control rules:

- leases have a bounded duration, reason, and idempotency key;
- the default maximum duration is 30 minutes;
- the default RPM percent range is policy-bounded;
- the daemon records active leases and owns expiry;
- expired-but-unrestored leases remain visible and block new prepares until Auto is restored;
- user Auto restore preempts active and in-flight agent cooling;
- `viftyctl run` resolves the child executable before preparing cooling and restores Auto after normal exit, handled signal exit, or launch failure.

Agents should run `viftyctl diagnose --json` before long build/test workloads, use `safeToRequestCooling` as the machine-readable gate, and treat `recommendedAgentAction: "doNotRequestCooling"` or `"restoreAutoBeforeRequestingCooling"` as stop-before-cooling decisions.

## Local Data and Privacy

Vifty has no analytics, accounts, cloud sync, or background network dependency.

Local files:

- curve profiles and backups live under `~/Library/Application Support/Vifty/`;
- manual-control markers live under the same app support directory;
- agent lease/audit state is local, permission-restricted, and bounded to the most recent 2,000 audit events by default;
- telemetry history is in-memory only.

`viftyctl audit [--limit N] --json` reads recent agent-control audit events through the daemon and declares `readOnly: true` / `coolingCommandsRun: false`. It is intended for local troubleshooting after blocked readiness, failed restores, or user reports; it does not request cooling, restore Auto, or perform SMC reads/writes.

Power telemetry is read directly from local IOKit power/battery dictionaries and does not require the privileged fan daemon.

## Release Trust

Public releases should be:

1. built with a Developer ID Application identity;
2. built with `VIFTY_XPC_ALLOWED_TEAM_ID` set;
3. verified with `codesign --verify --deep --strict`;
4. notarized with Apple notary service;
5. stapled and validated;
6. published as `Vifty-v<version>.zip` with a SHA-256 checksum;
7. validated on real hardware through `scripts/collect-validation-evidence.sh`, including `review-summary.tsv`, `review-summary.json`, `bundle-executables.tsv`, `schema-resources.tsv`, `capabilities-schema-resources.tsv`, `viftyctl-audit.json`, optional `release-artifact-summary.json` / `release-artifact-summary.tsv` with installed-app version matching, optional `release-checklist.md` / `release-checklist.tsv` with checklist version/follow-up checks, app/CLI/helper/daemon signing evidence, bundled LaunchDaemon TeamID evidence, and the release verifier result when available.

Ad-hoc CI artifacts, local builds, and source-first unsigned-dev convenience zips are useful for development and tester convenience, but they are not a substitute for signed, notarized public releases.

Vifty `v1.1.0` is source-first because the project does not currently have Apple Developer Program credentials. Its recommended trust path is building from source. Any `Vifty-v<version>-unsigned-dev.zip` attachment is not Developer ID signed, not notarized, not Homebrew-trusted, and should not use the canonical `Vifty-v<version>.zip` release artifact name.

The current release trust state is tracked in [release-status.md](release-status.md). Do not promote Homebrew or a GitHub asset as trust-complete unless that status page points to a signed, notarized, stapled artifact whose checksum and verifier summary match the cask.

## What To Report Privately

Please use GitHub Security Advisories for any path that would allow:

- unprivileged SMC writes;
- daemon XPC access by an unexpected client;
- arbitrary SMC key writes;
- agent cooling without bounded lease expiry;
- RPM targets outside validated fan ranges;
- local permission leaks for profile, lease, marker, or audit files.
