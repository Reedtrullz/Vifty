# Changelog

All notable changes to Vifty will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Apple Silicon fan mode probing now checks both `F{n}Md` and `F{n}md` so newer hardware key casing can be detected.
- Helper fan writes can retry manual mode after a guarded `Ftst` unlock path when direct mode writes are rejected.
- Low-level SMC writes are now allowlisted to fan mode, fan target, and guarded force-test keys.
- `viftyctl capabilities --json` now exposes structured command, workload, shell exit-code, and agent policy metadata.
- `viftyctl capabilities --json` includes an `exitCodes` object so agents can discover success, command-failure, usage, unavailable, and blocked-readiness exit semantics without scraping documentation.
- `viftyctl capabilities --json` now advertises local schema paths, bundled schema resource paths, and stable schema IDs for capabilities, diagnose, status, and command-error payloads.
- `viftyctl capabilities --json` now remains machine-readable when daemon status is unavailable, returning static command metadata, a disabled fallback policy, `policySource: "fallbackUnavailable"`, and the `unavailable` exit code so agents can discover the contract but fail closed.
- `viftyctl --json` command and argument-parse failures now return a structured error report with `safeToProceed: false` for automation; `viftyctl run --json` now also uses that shape for pre-child wrapper failures.
- `viftyctl diagnose --json` reports read-only hardware/agent readiness with `ready`, `degraded`, and `blocked` checks for release validation and local agents, including `recommendedAgentAction` and `safeToRequestCooling` so agents can distinguish normal, caution, restore-first, and stop decisions without parsing warning text. Blocked readiness now exits 75 after printing the JSON report so shell automation fails closed without losing evidence.
- Rate-limited agent-control decisions now carry `retryAfterSeconds` for automation-friendly retries.
- Agent workflow documentation now defines the `viftyctl` JSON contract, readiness decision rules, and a reusable guarded workload wrapper.
- Agent integration snippets now document the safe guarded-run pattern for Codex, Claude Code, Cursor, and shell runners.
- `viftyctl` JSON Schemas now document capabilities, readiness diagnostics, status/prepare/restore-auto reports, and structured command errors for local agents.
- Canonical `viftyctl` JSON examples now decode in XCTest so agent-facing payload documentation stays aligned with the Swift models.
- The reusable `guarded-run.sh` example now handles nonzero blocked diagnose reports as readiness blocks, requires `recommendedAgentAction` / `safeToRequestCooling`, refuses restore-first or unsafe decisions before launching the child workload, preserves structured diagnose failures, and delegates through `viftyctl run --json` so wrapper-level failures stay machine-readable for agents.
- The daemon XPC audit-token byte bridge is now isolated in core code with focused tests.
- Release builds can set `VIFTY_XPC_ALLOWED_TEAM_ID` to require a Developer TeamID on daemon XPC clients.
- Tagged releases now have a GitHub Actions workflow for Developer ID signing, TeamID verification, notarization, stapling, checksum generation, and GitHub Release publication.
- A GitHub Hardware Validation Report issue template now collects release compatibility evidence for Apple Silicon MacBook Pro model families.
- A compatibility status page now keeps Apple Silicon MacBook Pro support claims evidence-based and report-backed before broad marketing claims are made.
- A read-only validation evidence collector now gathers system metadata, bundle plist, bundled executable hashes, bundled agent and release-evidence JSON Schema hashes, advertised schema resource paths, optional release-artifact verifier summaries with schema identity and installed-app version matching, LaunchDaemon TeamID, app/CLI/helper/daemon signing checks, notarization/Gatekeeper checks, and `viftyctl` capabilities/status/diagnose JSON for release and hardware reports, including blocked diagnose output, with reviewer-friendly `review-summary.tsv`, automation-friendly `review-summary.json`, `bundle-executables.tsv`, `schema-resources.tsv`, `capabilities-schema-resources.tsv`, `release-artifact-summary.tsv` / `.json` when supplied, nonzero release-summary rows for skipped/failed verifier checks, checksum mismatches, or artifact-name drift, and SHA-256 digests for captured evidence files.
- A validation evidence reviewer now checks captured bundles in `release`, `supported-hardware`, or `unsupported-hardware` modes so maintainers can reject weak compatibility or release-trust claims without rerunning fan-control commands, including release-artifact summaries with missing or drifted schema identity, skipped/failed verifier checks, checksum mismatches, or artifact-name drift, and can write pass/fail `review-result.json` summaries for automation and report attachments.
- A validation report summarizer now builds TSV/JSON indexes from reviewed `review-result.json` files while keeping supported-hardware evidence labeled as manual-smoke-required until the issue template confirms the fan-write smoke test.
- A release artifact verifier now checks the Homebrew cask artifact SHA or generated workflow checksum, bundle version, required executables, bundled agent/release-evidence JSON Schema syntax and stable IDs, plist validity, Developer ID TeamID, LaunchDaemon TeamID allowlist, stapled notarization ticket, and Gatekeeper assessment before publish and after the cask checksum follow-up, with passed or failed machine-readable summaries that declare the stable release-artifact summary schema ID.
- A cask checksum updater now applies the release workflow's `Vifty-v<version>.zip.sha256` output to `Casks/vifty.rb` only when the checksum and artifact version match, with release metadata validation before and after the edit.
- A trust model document now explains the privileged helper boundary, SMC write allowlist, agent lease limits, local data handling, and release-signing expectations.
- Bug report forms now ask for read-only `viftyctl diagnose --json` and `ViftyHelper probeLocal` output for fan, helper, and agent-cooling issues.
- `ViftyHelper probe` / `probeLocal` fan rows now include `hardwareMode`, `hardwareModeRawValue`, and `targetRPM` so validation reports can compare SMC state before and after smoke tests.
- Release metadata validation now checks that release tag/version wiring, bundle version, Homebrew cask version/URL/SHA, cask signing metadata, privileged-helper cleanup path, workflow artifact naming, release TeamID build wiring, bundled LaunchDaemon TeamID verification, notarization/stapling workflow steps, pre-publish artifact verification/summary publication, release verifier signature/notarization checks, published zip/checksum/summary assets, and Gatekeeper assessment agree before CI or release publication.
- `make verify` now runs the local trust gate bundle: shell syntax checks for project scripts, release metadata validation, Swift tests, warnings-as-errors build, release app bundling, plist lint, strict codesign verification, and `viftyctl` identifier verification.

### Changed
- Hardware fan mode value `3` is displayed as macOS/System-managed instead of unknown.
- `viftyctl prepare` now exits nonzero when cooling is denied or no matching active lease is returned, while preserving JSON status output for agents.
- `viftyctl` now rejects unknown wrapper options and unexpected positional arguments instead of silently ignoring them; child arguments after `run --` still pass through untouched.
- `viftyctl run` now resolves the child executable before preparing a lease, refuses to launch if prepare is denied or returns a mismatched lease, launches the resolved path directly, separates Vifty wrapper flags from child-command flags, forwards common terminal/session signals so handled interrupts still restore Auto, and surfaces Auto-restore failures after child exit.
- `viftyctl --force` retries now fail closed if the rate-limit wait is interrupted instead of immediately retrying prepare without waiting.
- The default agent-control maximum lease duration is now 30 minutes, reducing the unattended blast radius while keeping longer caps configurable by policy.
- Agent status now keeps expired-but-unrestored leases visible and blocks new prepares until the daemon actually restores Auto, making delayed monitor restores observable to agents and the UI.
- Successful Auto restore and user/app lease clearing now reset stale agent-control decision/error metadata so post-Auto status is clean for agents.
- The app now surfaces daemon agent-lease clear failures after user Auto restore instead of losing the error during the follow-up poll.
- Active agent cooling UI now shows the workload, target fan RPMs, and an explicit restore-pending warning for expired-but-unrestored leases.
- User Auto now preempts active and in-flight agent cooling; prepares cancelled by Auto report the structured `RESTORE_REQUESTED` code instead of applying a lease after the user restores Auto.
- Agent policy and readiness diagnostics now block invalid or duplicate controllable fan IDs before Vifty reaches the SMC write path.
- Per-fan curve override profiles now stay matched by fan ID in the UI, clamp edited override RPMs to each fan's own range, and avoid traps from duplicate override IDs or malformed short curves.
- Local fan helper and daemon-client writes now reject invalid fan IDs, malformed RPM ranges, and mismatched `FanCommand`/hardware fan IDs before touching SMC keys or opening XPC.
- Hardened runtime exception entitlements were removed from the app and daemon entitlement templates.
- The app bundle version now matches the release-facing `1.0.0` cask/repo version.
- The Homebrew cask no longer declares ad-hoc signing and now removes the correct privileged helper path in uninstall caveats.
- Agent-control stores, curve profiles/backups, and manual-control markers now enforce private local permissions, including permission tightening for legacy audit/profile files.
- Profile persistence now has a throwing save path, and the app surfaces profile save/delete failures in `lastError` instead of silently losing them.
- Daemon-client XPC requests now use the same one-shot callback guard for missing-proxy failures and only invalidate the connection from the callback path that wins the response race.
- The administrator fallback installer now explicitly sets root ownership and restrictive permissions on the LaunchDaemon plist and daemon log files before bootstrapping the helper.
- `ViftyHelper probe` now awaits daemon-backed snapshots directly instead of bridging through a semaphore.
- Release artifacts are named `Vifty-v<version>.zip` to match the Homebrew cask download URL.
- XCTest coverage expanded to 339 tests for fan mode probing, helper-probe formatter evidence, per-fan curve override safety, SMC write allowlisting, helper/daemon-client write behavior and fan-ID/range validation, local persistence permissions and profile-save failure surfacing, bounded agent audit retention and read-only audit export, daemon-client callback handling, installer script hardening, XPC policy/retry metadata and audit-token byte bridging, expired-lease visibility/prepare blocking, post-Auto agent status cleanup, app agent-lease UI summaries, app agent-lease clear failure surfacing, and default lease duration, release TeamID allowlisting, release metadata validation including cask SHA, cask checksum updating, cask signing/cleanup metadata, release tag/version identity, release verifier skip-flag rejection, release TeamID build/LaunchDaemon verification, notarization workflow gates, Gatekeeper assessment, pre-publish public release artifact verification/summary publication, published release zip/checksum asset checks, release-summary schema identity, release-summary checksum/artifact/check-status review, and Makefile trust-gate wiring, CLI capabilities fallback discovery for daemon read failures, CLI retry behavior including interrupted force-retry waits, readiness diagnostics including agent action/safe-to-request fields, invalid/duplicate fan IDs, and blocked diagnose exit codes, structured JSON command/parse errors, wrapper-vs-child flag parsing, unknown wrapper-option rejection, child-command preflight, guarded-run wrapper decision-field gating, preflight/diagnose-failure behavior, validation evidence collection, review, and indexing including reviewer TSV/JSON summaries, executable hashes, schema resource hashes, advertised schema resources, release-artifact summary copy/pass-fail/version-match/schema-ID evidence, release-summary capture-time check/SHA/artifact drift rejection, plist/signing evidence, richer helper-probe fan telemetry, unsupported-hardware safe-block reports, machine-readable evidence review results, manual-smoke-required and validated-hardware compatibility report rows, skipped-notarization rejection, failed supported-hardware smoke tests, and nonzero blocked diagnose reports, decoded agent JSON examples and schema alignment, runtime schema discovery, bundled schema resource JSON/ID verification, documentation trust-surface links, trust-model guardrails, run `--json` pre-child failure reporting, Auto preemption of in-flight prepare, prepare/run denial fail-closed behavior, restore-failure reporting, signal-style process exit handling, agent integration snippet guardrails, and failed release-artifact summary evidence.

## [1.0.0] — 2026-06-07

### Added
- Menu bar cockpit with live fan RPM, temperatures, and power state
- Three fan control modes: Auto, Fixed RPM, and Temperature Curve
- Saveable, nameable curve profiles with backup and overwrite protection
- Live power tracking: adapter wattage, USB-C PD profiles, battery health, charge/drain watts
- `viftyctl` agent CLI with `status`, `capabilities`, `prepare`, `restore-auto`, and `run` commands
- Agent control: bounded-duration workload cooling leases with idempotency keys
- Daemon-owned lease monitoring and expiry (safety fallback)
- Privileged XPC helper (LaunchDaemon) for fail-closed SMC fan writes
- ViftyHelper debug CLI for direct SMC probing and emergency fan restoration
- Thermal-pressure state monitoring alongside raw temperatures
- In-memory rolling telemetry history
- Unclean-exit recovery (manual-control marker + Auto-restore on next launch)
- Timed manual modes (auto-restore after selected duration)
- Double-click installer (`Install Vifty.command`) and `make install` workflow
- Unsigned `.pkg` builder for reusable local installs
- Homebrew cask distribution
- 127 XCTest cases covering fan control, curves, XPC, power, and agent control
- GitHub Actions CI: Swift tests, release build, plist/code-sign checks
- SECURITY.md with vulnerability reporting and trust boundaries
- CONTRIBUTING.md with setup, architecture rules, and PR process
- CODEOWNERS for security-sensitive paths

### Security
- RPM clamping on all fan write paths
- Daemon-first architecture: unprivileged direct SMC writes refused (fail-closed)
- Sensor loss triggers Auto-restore
- Unsupported hardware refuses manual fan control
- Critical thermal pressure refuses or restores control
- User Auto always wins over active agent lease
