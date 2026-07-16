# Trust Model

<!-- BEGIN GENERATED RELEASE FACTS -->
> Release facts authority: `.github/release-manifest.json` (schema `docs/schemas/release-manifest.schema.json`).
> Published: `v1.3.2` (version `1.3.2`, build `7`), `arm64` only, minimum macOS `15.0`.
> Runtime identities: app `tech.reidar.vifty`, daemon `tech.reidar.vifty.daemon`, helper `tech.reidar.vifty.helper`, CLI `tech.reidar.vifty.ctl`.
> Canonical artifact: `Vifty-v1.3.2.zip` with checksum asset `Vifty-v1.3.2.zip.sha256` and SHA-256 `8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0`.
> Public artifact trust: `passed` / `developer-id-notarized` for TeamID `X88J3853S2`; source `6a771c2ea10386bf7a0a8369a759930f01d56062`, CI run `29284751837`, Release run `29285576026`.
> Tag policy: `v1.3.2` remains recorded as `historical-unsigned` evidence; signed tags are mandatory from version `1.3.3` onward.
> Separate exact-build claims: installed release review `passed`; manual Fixed/Curve/Auto compatibility `passed-auto-restored` on `MacBookPro18,1` only (review `docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/review-result.json`; attestation `docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/manual-smoke-attestation.md`).
<!-- END GENERATED RELEASE FACTS -->

Vifty controls fans through private macOS SMC interfaces, so trust has to be explicit. This document describes what runs with privilege, what can write fan state, what agents can request, and what Vifty refuses to do.

## Summary

- The SwiftUI app and `viftyctl` run unprivileged.
- The LaunchDaemon runs as root and owns normal SMC fan writes.
- Direct helper fan writes require a privileged/root caller and are for probing or emergency recovery.
- Fan writes are narrow: fan mode keys, fan target keys, and the guarded force-test key only.
- Agents request bounded cooling intent. They do not get raw SMC write access.
- Power, thermal, profile, telemetry, and agent state stay local to the Mac.
- Public releases should be Developer ID signed, notarized, stapled, and TeamID-gated over XPC.

## Private Interface Risk

Apple does not document or guarantee the SMC/HID interfaces Vifty uses. A macOS update or new MacBook Pro revision can change service names, sensor keys, fan mode keys, mode values, or write behavior.

When private telemetry is absent, contradictory, or outside known fan ranges, Vifty must fail closed instead of guessing. That means staying in macOS Auto, blocking manual or agent-requested cooling, and collecting read-only diagnostics before any supported-hardware claim expands.

## Privileged Components

| Component | Privilege | Purpose |
| --- | --- | --- |
| `Vifty.app` | User | SwiftUI menu bar app, polling, profile selection, power telemetry, and user controls |
| `viftyctl` | User | Agent/build/test CLI for status, diagnostics, bounded cooling leases, and restore requests |
| `ViftyDaemon` | Root LaunchDaemon | XPC endpoint that reads snapshots, may briefly cache read-only snapshots, and applies validated fan commands |
| `ViftyHelper` | User or root depending on caller | Local SMC probe and emergency fan restore tool; fan writes require a privileged/root path |

The normal app path is daemon-first. If the daemon is unavailable, the unprivileged app fails closed for fan writes instead of attempting direct AppleSMC writes.

The daemon may reuse a read-only hardware snapshot for a very short TTL to reduce polling overhead. That cache is cleared after manual fan writes and agent prepare/restore operations, and cached telemetry must never authorize a privileged write: write paths resolve the target fan from fresh local daemon telemetry before touching SMC state.

## XPC Boundary

The daemon accepts XPC clients by signing identity:

- `tech.reidar.vifty` for the app.
- `tech.reidar.vifty.ctl` for `viftyctl`.

`ViftyHelper` uses its local privileged SMC path rather than daemon XPC, so it is not an allowed XPC client.

When a local ad-hoc build leaves `VIFTY_XPC_ALLOWED_TEAM_ID` empty, the daemon trusts no XPC write clients and fan writes fail closed; read-only app telemetry can still use unprivileged fallbacks. Teamless development access is explicit only: a development LaunchDaemon must set `VIFTY_XPC_ADHOC_DEVELOPMENT=1`, bind `VIFTY_XPC_ADHOC_ALLOWED_UID`, and provide exact absolute app and `viftyctl` paths through `VIFTY_XPC_ADHOC_APP_PATH` and `VIFTY_XPC_ADHOC_CTL_PATH`. The daemon then requires matching audit-token EUID, signing identifier, and canonical executable path. `ViftyHelper` does not call daemon XPC and is not an allowed client. Missing, partial, invalid-enable, legacy-helper, or mixed TeamID/development metadata fails closed. Public releases set `VIFTY_XPC_ALLOWED_TEAM_ID` to the Developer ID TeamID and must contain no `VIFTY_XPC_ADHOC_*` metadata.

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

The app treats fallback fan telemetry as diagnostic evidence only. If fans can be read locally while the daemon is not responding, the UI reports that telemetry is available but keeps manual Fixed/Curve controls blocked until the daemon-backed write path responds again.

Vifty refuses or restores control when safety inputs are not trustworthy, including:

- unsupported hardware;
- missing temperature sensors;
- missing controllable fans;
- invalid or duplicate fan IDs;
- invalid fan RPM ranges;
- critical thermal pressure;
- sensor loss during curve or lease control;
- helper or daemon uncertainty on fan writes.

Unsupported-hardware behavior is defined in [unsupported-hardware.md](unsupported-hardware.md). A safe block keeps the Mac under macOS Auto, reports `safeToRequestCooling: false` with `daemonControlPathReady: true` when daemon paths are available, and must not be bypassed with helper or raw SMC fan writes.

Manual control uses an unclean-exit marker so the next launch can restore Auto if Vifty exited while manual fan control was active.

## App Replacement Boundary

The source installer replaces only the unprivileged app bundle. It does not stop, remove, repair, or overwrite the installed LaunchDaemon helper, and its replacement preflights are read-only.

For a current protocol-v2 install, replacement requires a fresh, exit-zero `viftyctl diagnose --json` attestation from the authenticated installed CLI, with a complete trusted physical fan set in Auto/System, valid mode keys, clear transaction/recovery ownership, no active agent lease, and no manual-control marker. Developer ID installs are Apple-anchor/TeamID/identifier/deep-seal checked before a private CLI copy runs; explicit debug ad-hoc installs must match the configured UID and exact installed app/CLI paths. A failed or incomplete protocol-v2 report cannot downgrade into a legacy path.

Before changing helper authority, the privileged replacement bootstrap copies the complete candidate into a root-owned `ReplacementTransactions/<UUID>/CandidateSnapshot/Vifty.app`, independently re-verifies its signature/identifiers, proves the caller source was stable across the copy, and derives both the lifecycle executable and candidate binding only from that snapshot. The binding contains the bundle-root row and every descendant's relative path, type, UID, GID, permission mode, link count, and type-appropriate size plus file SHA-256 or symbolic-link target. The manifest hash does not claim to bind ACLs or extended attributes: `ditto` preserves them in the snapshot, Developer ID validation separately enforces the signed code seal, and local ad-hoc development trust remains an explicit exact-path/operator boundary rather than an ACL/xattr authenticity claim.

Replacement recovery state is kept in the root-private mode-`0600` `/Library/Application Support/ViftyMaintenanceEvidence/replacement-state-v1.json` ledger, separate from the replaceable mode-`0644` `last-execution-v1.json` operator-evidence record. Ordinary repair failures and ordinary successful repairs therefore cannot erase a prepared, locked, or completed replacement obligation. A later prepare or uninstall may remove that ledger only after another quiesce plus complete Auto/System proof, validated unlock, transaction removal, and directory durability barriers. Recursive immutable-flag changes first journal `locking` or `unlocking`; partial flag operations, process/power loss between a flag change and its next ledger state, transaction-retirement interruption, and record-rename/fsync ambiguity are resolved on the same or a later authorized invocation by rereading the actual tree flags and root-private ledger, reauthenticating the destination against its recorded candidate/previous identity, and converging to a validated all-locked or all-unlocked state. Exit `75` claims frozen authority only when the exact launchd label is currently proven disabled and offline; otherwise prepare/root uncertainty is exit `76`.

The only legacy compatibility path is the published Developer ID `v1.3.2` build `7`. Before executing legacy code, the installer verifies that exact version/build, app/CLI/daemon/helper canonical byte and CDHash identities, explicit Apple Developer ID requirements, bundled LaunchDaemon TeamID, and the deep app seal. It runs a private reverified copy of the canonical CLI beside a private canonical daemon copy, then runs a private stable copy of the new bundle's `probeLocal` command. The hardened local reader must report one FNum-backed inventory of 1 to 10 fans with contiguous IDs `0..<fanCount`, whose per-fan mode key, restore eligibility, and Auto/System raw mode exactly match the fresh `v1.3.2` daemon report and its installed/bundled daemon hash parity. Mode-only fans may pass when they are eligible for OS-managed restore even if Fixed RPM is unavailable. Forced, partial, unreachable, leased, manual-marker, mismatched, other-version, noncanonical, and generic legacy states fail before copy. The old schema is evidence only for that allowlisted migration; it is never interpreted as protocol-v2 ownership authority. These checks are point-in-time snapshots, not a daemon quiescence lease; the existing daemon remains authoritative for concurrent bounded lease expiry and Auto restoration during the app-only swap.

## Privileged Helper Maintenance Boundary

Destructive helper repair and uninstall use one lifecycle boundary. Under protocol v2, the daemon blocks new fan-control ownership, restores the complete trusted physical fan set to Auto/System, requires fresh confirmation, and consumes one short-lived operation token only after revalidating the boot session, daemon session, journal generation, quiesce generation, fan inventory, and exact canonical bundled `ViftyHelper` SHA-256. The requesting CLI hashes its sibling helper, while the daemon independently hashes its own canonical app sibling and requires equality; client report data cannot choose the receipt identity. It persists authorization at the fixed `/Library/Application Support/Vifty/Maintenance/authorized-v1.json` path. The directory is root-owned mode `0700`; authorized and claimed receipts are root-owned mode `0600`, singly linked, bounded, and opened without following symlinks. Every daemon bootstrap synchronously revokes prior authorized and claimed receipts before constructing the writer boundary or exposing XPC, and startup fails closed if revocation fails.

After administrator authorization, an immutable digest-checked root worker atomically claims a valid receipt, parses the full disabled-service key literally, disables the launchd label, boots the service out, and confirms it remains disabled and offline. It then independently restores and freshly confirms the complete Auto/System fan set using a root-staged copy of the helper bytes snapshotted before authorization. Production accepts that helper only when its SHA-256 is unchanged and its signature satisfies Vifty's exact helper identifier, TeamID, Developer ID intermediate/leaf OIDs and authority chain, and hardened runtime. Only after that mandatory post-freeze proof does it consume the claim and delete legacy files; repair alone may re-enable the label afterward. The outer process requires recent caller-UID/parent-PID-bound completed root evidence before any registration or final unregister transition. Signal or incomplete-root paths persist blocked evidence and cannot register repair.

Authority selection is explicit. A successful protocol-v2 prepare is receipt-only: missing, expired, cross-boot, operation-mismatched, or changed-helper authority fails without offline downgrade. A structurally exact current-schema `PROTOCOL_MISMATCH` report may select offline recovery. A fresh structured `HELPER_UNREACHABLE` report first reuses a still-valid receipt; without one, root must snapshot and verify the exact published v1.3.2 daemon SHA-256 and CDHash plus its daemon identifier, TeamID, Developer ID OIDs/authority chain, and hardened runtime before service freeze. Generic unavailable, stale, malformed, safety-blocked, or lookalike-v1.3.2 states cannot enter teardown. Protocol-v1 uninstall asks the signed main app to finish SMAppService unregistration only after root cleanup. That bridge accepts only a recent completed root phase record from `/Library/Application Support/ViftyMaintenanceEvidence/last-execution-v1.json`, whose root-owned non-writable directory is separately traversable for read-only verification, and requires the same requesting user and lifecycle parent process recorded by the root worker; the private receipt directory remains inaccessible to the user process. Direct invocation, replay from another process, repair requests, incomplete phases, stale evidence, or caller-chosen paths cannot unregister the service. App and shell-wrapper entrypoints use clean `env -i` execution with Bash profiles disabled before lifecycle parsing; the signed app also pins the reviewed script digest, while direct source execution retains the explicit operator-trusted-checkout boundary.

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

Agents should run `viftyctl diagnose --json` before long build/test workloads, use `safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`, `daemonRuntime`, and `coolingBlockerIDs` as machine-readable gates, treat `recommendedAgentAction: "doNotRequestCooling"` or `"restoreAutoBeforeRequestingCooling"` as stop-before-cooling decisions, and use `recommendedRecoveryAction` plus `recoverySteps` for helper repair, Auto restore, workload backoff, policy inspection, or read-only hardware evidence follow-up. If `daemonRuntime.matchRequired` is true and `daemonRuntime.matchesExpectedDaemon` is not true, agents should stop and repair/reinstall the helper before trusting current-build cooling. If a restore leaves `manualControlActive` true, agents should inspect `appPreferences.startupMode`, then stop instead of looping and ask the user to switch Vifty/default startup mode to Auto before another cooling request.

## Local Data and Privacy

Vifty has no analytics, Vifty-owned accounts, cloud sync, or background network dependency. The optional **Codex usage** menu-bar field is separate: when selected alone or inside a custom menu-bar summary, it asks the local Codex CLI/app-server for account rate-limit data if available, then falls back to local Codex session logs. Vifty can show percent left or used as text or a compact battery-style gauge, reset countdown or reset time, and a 30 second to 5 minute refresh cadence without storing Codex credentials or API keys.

Local files:

- curve profiles and backups live under `~/Library/Application Support/Vifty/`;
- manual-control markers live under the same app support directory;
- agent lease/audit state is local, permission-restricted, and bounded to the most recent 2,000 audit events by default;
- telemetry history and trend visualizations are derived from an in-memory rolling sample buffer only; Vifty does not persist or export those samples.

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
7. validated on real hardware through `scripts/collect-validation-evidence.sh`, including `review-summary.tsv`, `review-summary.json`, `install-provenance.tsv`, `bundle-executables.tsv`, `schema-resources.tsv`, `capabilities-schema-resources.tsv`, `capabilities-contract.tsv`, `viftyctl-audit.json`, optional `release-artifact-summary.json` / `release-artifact-summary.tsv` with installed-app version matching, optional `release-checklist.md` / `release-checklist.tsv` with checklist version/follow-up checks, app/CLI/helper/daemon signing evidence, bundled LaunchDaemon TeamID evidence, the release verifier result when available, and a reviewed `review-result.json` declaring `schemaID: https://vifty.local/schemas/validation-review-result.schema.json`.

Ad-hoc CI artifacts, local builds, and source-first unsigned-dev convenience zips are useful for development and tester convenience, but they are not a substitute for signed, notarized public releases.

### Canonical v1.3.2 migration identity

The installer’s one legacy replacement exception is bound to the canonical public archive, not merely to matching version text or TeamID. The source is `https://github.com/Reedtrullz/Vifty/releases/download/v1.3.2/Vifty-v1.3.2.zip`; its SHA-256 is `8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0`, matching `Casks/vifty.rb`.

The archive was downloaded to fresh scratch storage, hashed before extraction, extracted once, and inspected without executing any component. Reproduce the identities with `shasum -a 256 Vifty-v1.3.2.zip`, `ditto -x -k Vifty-v1.3.2.zip extracted`, `shasum -a 256 extracted/Vifty.app/Contents/MacOS/{Vifty,viftyctl,ViftyDaemon,ViftyHelper}`, and `codesign -dvvv` on each executable for its CDHash. The pinned results are:

| Component | SHA-256 | CDHash |
|---|---|---|
| Vifty | `10e6ca95faa8167bf81df49bfa7407ad5f8ab3e55cf7720085ec61334897c55e` | `666e4972fcb31fa3fcb3134c956daae0bdf62189` |
| viftyctl | `63d2837795f22a34f1833c9c38a49b2c95d87339262347cca89b0245f7068f3e` | `95a55844ba7b4983712c69693ec4c4b80a7e1205` |
| ViftyDaemon | `7543c573528a57bb096b045b9a7476b1d4da4aef88b7cd8b54d4cd2ca5bf7dac` | `c5613e3020d94de1d141917d7b950fc367a6e61a` |
| ViftyHelper | `f081eb5f0f3097d0baf8b96b8655cb038d6b5e8abb406e53192305af31a98cf0` | `c5802ef35c7cbeabad37db5657dd20fa95f727ba` |

Before any legacy code runs, the installer also requires `anchor apple generic`, the Developer ID Application leaf/intermediate certificate OIDs, leaf OU `X88J3853S2`, exact signing identifiers, and a valid deep app seal. It copies the pinned CLI and sibling daemon into a private `0700` run directory, rechecks their signatures and byte identities there, and executes only that private CLI copy. Its Auto/System evidence is a fresh point-in-time snapshot rather than a daemon-held quiescence lease; the existing daemon continues to own any concurrent bounded lease, expiry, and Auto restoration during the app-only rename swap.

The generated fact block above is authoritative for the current public version, build, architecture, identities, checksum, TeamID, and trust state. The exact `v1.3.2` public artifact passes release-level signing/notarization checks, installed release-mode review, and human-supervised Fixed → Auto → Curve → Auto validation on `MacBookPro18,1`. The [release review](validation-reports/2026-07-14-v1.3.2-macbookpro18-release/review-result.json) and [manual-smoke attestation](validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/manual-smoke-attestation.md) scope those claims to that exact binary and model; they do not validate the current branch or broad Apple Silicon compatibility. `v1.1.1` remains the source-first fallback and supersedes `v1.1.0` for users who hit the helper-unreachable update issue. Any `Vifty-v<version>-unsigned-dev.zip` attachment is not Developer ID signed, not notarized, not Homebrew-trusted, and must not use the canonical `Vifty-v<version>.zip` release artifact name.

The current release trust state is tracked in [release-status.md](release-status.md). Do not promote Homebrew or a GitHub asset as trust-complete unless that status page points to a signed, notarized, stapled artifact whose checksum and verifier summary match the cask.

Auto-update installs executable code and therefore belongs only to the future trusted binary lane. See [auto-update.md](auto-update.md) for the Sparkle appcast, EdDSA signing, Developer ID, notarization, and source-first exclusion rules.

## What To Report Privately

Please use GitHub Security Advisories for any path that would allow:

- unprivileged SMC writes;
- daemon XPC access by an unexpected client;
- arbitrary SMC key writes;
- agent cooling without bounded lease expiry;
- RPM targets outside validated fan ranges;
- local permission leaks for profile, lease, marker, or audit files.
