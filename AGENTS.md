# AGENTS.md — Vifty

AI coding instructions for working in this repository.

## Build System

- Swift Package Manager (`Package.swift`, tools-version 6.0).
- `swift build` / `swift test` / `make verify` / `make app` (see Makefile).
- macOS 15 minimum deployment target.
- `.build/` is gitignored.

## Target Layout

| Target | Type | Dependencies |
|--------|------|-------------|
| Vifty | executable | ViftyCore |
| ViftyCore | library | ViftyPrivateIOKit |
| ViftyDaemon | executable | ViftyCore |
| ViftyHelper | executable | ViftyCore |
| ViftyCtl | executable | ViftyCore |
| ViftyPrivateIOKit | C target | IOKit framework |
| ViftyCoreTests | test | ViftyCore, Vifty |

ViftyCore links `IOKit.framework` and ViftyPrivateIOKit links it too (C target needs explicit linking).

## Key Files

- `Sources/ViftyCore/Models.swift` — All data types: Fan, TemperatureSensor, HardwareSnapshot, FanCurve, CurveProfile, FanMode, FanCommand, ControlState, ViftyError.
- `Sources/ViftyCore/AgentControlModels.swift` — Codable agent-control requests, leases, policy snapshots, decisions, retry metadata, and status.
- `Sources/ViftyCore/AgentControlPolicy.swift` — conservative policy for bounded workload leases.
- `Sources/ViftyCore/AgentControlService.swift` — daemon-owned service that applies agent cooling targets and restores Auto.
- `Sources/ViftyCore/HardwareService.swift` — `HardwareService` protocol + `FanControlCoordinator` actor + `ManualControlMarker`.
- `Sources/ViftyCore/RealMacHardwareService.swift` — `RealMacHardwareService` (daemon-first SMC reads/writes, local fallback).
- `Sources/ViftyCore/CurveProfileStore.swift` — JSON file persistence for saved curve profiles.
- `Sources/ViftyCore/SMCClient.swift` — IOKit SMC connection, read/write allowlist, SMCValue, SMCDecoding (float, FPE2, flt, uint en/decoding).
- `Sources/ViftyCore/FanInfoReader.swift` — Pure SMC fan snapshot parser for hardware Auto/Forced/System mode, mode-key casing probes, and target RPM.
- `Sources/ViftyCore/FanDisplayFormatter.swift` — Pure fan-state display strings for UI rows.
- `Sources/ViftyCore/HardwareSnapshotProbeFormatter.swift` — Pure helper-probe text formatter for hardware validation evidence.
- `Sources/ViftyCore/LocalFanHelperClient.swift` — Privileged/root local SMC fan writer with mode-key probing and guarded `Ftst` unlock support.
- `Sources/ViftyCore/PowerInfo.swift` — Local IOKit power telemetry parser (`IOPS`, `AppleSmartBattery`, adapter details) + UI formatters.
- `Sources/ViftyCore/ThermalPressure.swift` — macOS thermal-pressure state model and display helpers.
- `Sources/ViftyCore/TelemetryHistory.swift` — In-memory rolling telemetry sample buffer.
- `Sources/ViftyCore/ViftyCtlArguments.swift` — pure parser for the bundled agent CLI, including read-only audit export options.
- `Sources/ViftyCore/ViftyCtlReadinessReport.swift` — machine-readable `viftyctl diagnose` report for hardware/agent readiness.
- `Sources/ViftyCore/ViftyCtlRunner.swift` — testable command runner used by `viftyctl`, including structured capabilities, read-only audit export, and retry handling.
- `Sources/ViftyCore/XPCAuditTokenCoding.swift` — audit-token byte bridge used by the daemon XPC identity extractor.
- `Sources/ViftyCore/ViftyDaemonClient.swift` — XPC client that talks to the privileged daemon.
- `Sources/ViftyCore/ViftyDaemonProtocol.swift` — `@objc` XPC protocol + `XPCSnapshotCoding` / `XPCAgentControlCoding` bridges for snapshots, agent status, leases, and audit events.
- `Sources/ViftyDaemon/main.swift` — XPC listener with `DaemonService` exporting the protocol.
- `Sources/ViftyHelper/main.swift` — CLI for `probe`, `readKey`, `setFixed`, `auto`, `smcDiagnostics`.
- `Sources/ViftyCtl/main.swift` — thin `viftyctl` command entrypoint.
- `Sources/Vifty/ViftyApp.swift` — `@main` SwiftUI app entry (menu bar extra + window scene).
- `Sources/Vifty/AppModel.swift` — `@MainActor ObservableObject` driving UI polling, fan/profile state, and power snapshot refresh.
- `.github/workflows/ci.yml` — GitHub Actions CI: Swift tests, release app build, plist/code-sign checks, temp install verification, and app artifact upload.
- `.github/workflows/release.yml` — tagged release workflow for Developer ID signing, notarization, stapling, checksums, and GitHub Release publishing.
- `.github/repo-metadata.json` — expected GitHub topics and issue labels for contributor discovery, release trust, hardware validation, and agent-cooling triage.
- `.github/ISSUE_TEMPLATE/release-trust.yml` — structured release-trust reports for missing assets, cask checksum drift, Gatekeeper/notarization/signing/TeamID failures, and release-readiness/verifier/reviewer blockers.
- `.github/ISSUE_TEMPLATE/hardware-validation.yml` — structured compatibility reports for release validation evidence.
- `.github/ISSUE_TEMPLATE/agent-cooling.yml` — structured `viftyctl`/guarded-run agent cooling reports with diagnose/status/audit evidence and safety confirmations.
- `scripts/validate-release-metadata.sh` — verifies release tag/version wiring, bundle version, cask version, cask URL/SHA, release artifact naming, release TeamID build wiring, notarization/stapling workflow steps, pre-publish artifact verification summary publication, public verifier skip flags, and Gatekeeper assessment stay aligned.
- `scripts/check-release-secrets.sh` — verifies required GitHub Actions release secret names are configured before pushing/rerunning release tags; reads names only, never values.
- `scripts/check-release-readiness.sh` — read-only public-release preflight with `developer-id` and `source-first` modes. Developer ID mode validates release metadata, optional required source-ref alignment, source CI, Release workflow status, required secret names, and canonical trusted GitHub Release assets. Source-first mode validates source/ref/CI readiness and honest GitHub Release notes/assets without requiring Apple Developer Program secrets.
- `scripts/check-github-metadata.sh` — verifies GitHub topics and triage labels against `.github/repo-metadata.json`; supports fixture files for tests and live `gh` checks for maintainers.
- `scripts/write-release-checklist.sh` — writes either the Developer ID release checklist prepended to notarized GitHub Release notes or source-first release notes for releases without Apple Developer Program credentials.
- `scripts/build-unsigned-dev-artifact.sh` — builds the source-first tester convenience artifact `Vifty-v<version>-unsigned-dev.zip` and checksum without using the canonical notarized artifact name.
- `scripts/update-cask-checksum.sh` — applies the release workflow's checksum file to `Casks/vifty.rb` only when the artifact name matches the cask version, with release metadata validation before and after the edit.
- `scripts/verify-release-artifact.sh` — public-release audit that verifies the cask artifact SHA or generated workflow checksum, bundle version, required executables, bundled release/agent schema JSON/IDs, plist validity, Developer ID TeamID, LaunchDaemon TeamID allowlist, stapled notarization ticket, and Gatekeeper assessment.
- `scripts/collect-validation-evidence.sh` — read-only evidence collector for release/hardware validation reports, including `review-summary.tsv`, `review-summary.json`, `bundle-executables.tsv`, `privacy-review.tsv`, `schema-resources.tsv`, `capabilities-schema-resources.tsv`, optional `release-artifact-summary.json` / `release-artifact-summary.tsv` and `release-checklist.md` / `release-checklist.tsv` with installed-app version matching, bundle plist, LaunchDaemon TeamID, per-binary signing, notarization, and Gatekeeper outputs.
- `scripts/review-validation-evidence.sh` — read-only evidence-bundle reviewer for installed release, supported Apple Silicon MacBook Pro, and unsupported-hardware safe-block claims, including release-summary and release-checklist consistency in release mode, with optional `review-result.json` output.
- `scripts/summarize-validation-reports.sh` — read-only report-index builder that summarizes `review-result.json` files, keeps candidate supported-hardware rows manual-smoke-required, and promotes only explicit `passed-auto-restored` smoke-test reports to validated hardware evidence.
- `docs/agent-workflows.md` — stable `viftyctl` agent contract, JSON decision rules, and common workload examples.
- `docs/agent-integrations.md` — copy/paste guarded-run instructions for Codex, Claude Code, Cursor, and shell runners.
- `docs/safe-agent-cooling.md` — short operational runbook for local agents/scripts: readiness gate, guarded-run preference, conservative workload limits, and blocked/restore-failure handling.
- `docs/trust-model.md` — plain-language trust model for privileged helper, SMC write, agent-control, local-data, and release-signing boundaries.
- `docs/release-status.md` — point-in-time public release trust status, including source-first, unsigned-dev tester artifact, future Developer ID, Homebrew trust, and operator checks.
- `docs/unsupported-hardware.md` — canonical policy for unsupported-machine safe blocks, read-only evidence, and forbidden fan-write bypasses.
- `docs/support-triage.md` — maintainer triage guide for release trust, hardware validation, unsupported hardware, helper install, SMC telemetry, agent-cooling, and UI reports.
- `docs/schemas/` — release and agent-facing JSON Schemas for release readiness plus `viftyctl` capabilities, audit, diagnose, status/prepare/restore-auto, and command-error reports.
- `docs/examples/viftyctl/` — canonical `viftyctl` JSON fixtures decoded by tests to keep agent examples current.
- `examples/viftyctl/` — guarded-run shell wrapper and tested convenience wrappers for Swift, Xcode, npm, cargo, pytest, local-model, and custom workloads.
- `scripts/install-vifty.sh` and `Install Vifty.command` — local install path into `/Applications` or `~/Applications`.
- `scripts/build-installer-pkg.sh` — unsigned local `.pkg` builder for reusable installs.
- `docs/release.md` — Developer ID/notarized release checklist and required GitHub secrets.

## Architecture Rules

1. **Curve resolution happens in `FanControlCoordinator`** — the daemon only receives resolved `fixedRPM` commands. Never pass `temperatureCurve` across XPC.
2. **RPM clamping** — `FanCurve.clamp()` is the single source. All callers (coordinator, helper, daemon) must clamp before writing.
3. **SMC writes are allowlisted** — `SMCClient.write()` may only write Vifty's fan mode keys (`F{n}Md` / `F{n}md`), fan target keys (`F{n}Tg`), and guarded force-test key (`Ftst`). Keep arbitrary SMC access read-only.
4. **Daemon-first with fail-closed writes** — `RealMacHardwareService` tries `ViftyDaemonClient` first for all operations. Reads may fall back to local SMC so the UI can still show sensors; fan writes only fall back to `LocalFanHelperClient` for privileged/root callers. The unprivileged app must fail closed and ask for helper reinstall instead of attempting direct AppleSMC writes.
5. **Protocol abstraction** — Tests use a `FakeHardware` actor conforming to `HardwareService`. All fan logic lives in `FanControlCoordinator`, not in the hardware layer.
6. **Sendable safety** — `FanControlCoordinator` is an actor. `RealMacHardwareService` is `@unchecked Sendable` (owns non-Sendable IOKit connection). `CallbackState` uses NSLock for one-shot XPC callback delivery.
7. **Unclean exit recovery** — `ManualControlMarker` writes a file when manual control is active; `recoverIfNeeded()` checks it on next launch.
8. **Profile temp sorting** — `CurveProfile.init()` sorts the three temperature/RPM pairs into ascending order so stored values always match actual curve behavior. The UI sliders can be set in any order; the init normalizes them.
9. **Profile backup** — `CurveProfileStore.save()` copies the existing file to a `.bak` backup before overwriting, protecting against disk-full or interrupted-write corruption.
10. **Power telemetry stays app-local** — `PowerInfoReader` reads IOKit power/battery dictionaries directly; it does not require the privileged fan daemon and should keep parser helpers testable with dictionary fixtures.
11. **Fan hardware state is read-only telemetry** — SMC mode/target fields are surfaced on snapshots and round-tripped through XPC, but fan commands still go through `FanControlCoordinator` and daemon/helper paths.
12. **Telemetry history is in-memory only** — do not persist rolling samples unless a future plan explicitly covers privacy and retention.
13. **Agent control is lease-based** — agents request bounded workload cooling through `viftyctl`; never expose raw SMC writes or arbitrary fixed-low RPM to agent tools. The daemon/core service owns lease monitoring, expiry, and restore; UI state is visibility and user override. The default maximum lease duration is 30 minutes.
14. **Apple Silicon fan mode keys vary** — fan mode may be `F{n}Md` or `F{n}md`; probe both at runtime and keep tests fixture-backed.
15. **Protected/system fan mode is explicit** — SMC mode value `3` represents macOS/System-managed control. If direct manual mode writes are rejected and `Ftst` exists, helper writes may use a guarded unlock/retry path; restoring Auto should return `Ftst` to `0` when available.
16. **Agent JSON is a contract** — capabilities, read-only audit export, readiness diagnostics, command errors, and rate-limit responses must stay machine-readable. Preserve policy fields, source schema paths, bundled schema resource paths, schema ID references, `policySource`, `daemonStatusAvailable`, `runLifecycle`, readiness check IDs, state strings, `recommendedAgentAction`, `safeToRequestCooling`, `safeToProceed`, `readOnly`, `coolingCommandsRun`, and `retryAfterSeconds` across Codable and XPC dictionary coding. `capabilities --json` must remain parseable when daemon status is unavailable, but it must fail closed with `exitCodes.unavailable` and a disabled fallback policy.
17. **Release XPC hardening is build-configured** — local builds leave `VIFTY_XPC_ALLOWED_TEAM_ID` empty for ad-hoc signing; release builds should set it so the daemon requires matching signing identifiers and the configured TeamID.
18. **Separate source-first from trusted binaries** — `v1.1.0` is source-first because Apple Developer Program credentials are unavailable. Do not claim source-first or unsigned-dev artifacts are Developer ID signed, notarized, stapled, Gatekeeper-approved, Homebrew-trusted, or official trusted binaries. Future trusted binary releases should use `.github/workflows/release.yml`.
19. **Diagnostics are read-only** — `viftyctl diagnose` must not prepare leases, restore Auto, or perform SMC writes. It may read daemon snapshots, thermal pressure, and agent-control status only.
20. **Run command preflight comes before cooling** — `viftyctl run` must resolve/validate the child command before preparing a lease, then execute the resolved path directly only if prepare returns a matching active lease. While the child is active, handled terminal/session signals should be forwarded to the child so the wrapper can still restore Auto before exiting. Auto-restore failures after child exit must be visible to agents through stderr and a nonzero wrapper exit when the child itself succeeded.
21. **Local persistence is private by default** — agent-control stores, curve profiles/backups, and manual-control markers must keep directories at `0o700` and files at `0o600`, including when tightening permissions on legacy files from older builds.
22. **Release metadata must stay aligned** — for future Developer ID releases, `Resources/Info.plist`, `Casks/vifty.rb`, and `.github/workflows/release.yml` must agree on the version, `Vifty-v<version>.zip` artifact name, cask SHA shape, notarization/stapling workflow gates, release verifier signature/notarization checks, and Gatekeeper assessment. Run `scripts/validate-release-metadata.sh` when touching release files, use `scripts/update-cask-checksum.sh --checksum-file <path> --version <version>` for the post-release cask SHA handoff, and use `scripts/verify-release-artifact.sh --team-id <TEAMID>` after the notarized release artifact and cask SHA are published. Source-first unsigned builds must use `Vifty-v<version>-unsigned-dev.zip` and must not update or repoint the Homebrew cask.

## Testing

- `swift test` runs `ViftyCoreTests` (414 tests).
- `FanControlCoordinatorTests` uses `FakeHardware` (actor + `HardwareService`). Covers hardware validation, curve-to-fixed-RPM, per-fan override resolution/malformed-profile safety, missing-sensor recovery, auto-restore, and daemon-fallback regression.
- `FanCurveTests` tests interpolation, clamping, SMC float encode/decode, and SMC known-path coverage.
- `SMCClientWritePolicyTests` tests low-level SMC write allowlisting, valid fan-ID key scope, and rejected-key messaging.
- `AgentControlStoreTests` tests active lease/audit JSON persistence, private directory/file permissions, legacy audit-file tightening, bounded audit retention, and recent audit-event loading.
- `FanInfoReaderTests` tests pure fan hardware-mode/target parsing and uppercase/lowercase mode-key fallback from synthetic SMC dictionaries.
- `FanDisplayFormatterTests` tests fan hardware-state display strings without SwiftUI inspection.
- `HardwareSnapshotProbeFormatterTests` tests helper-probe validation evidence includes fan mode, raw mode, target RPM, and explicit missing-telemetry markers.
- `LocalFanHelperClientTests` tests mode-key write selection, invalid fan-ID/range/controllability refusal before SMC access, mismatched fan-command refusal, guarded `Ftst` unlock retry, and Auto restore cleanup without live SMC writes.
- `ManualControlMarkerTests` tests sentinel file lifecycle (create, detect, clear, idempotency) and private marker directory/file permissions.
- `RealMacHardwareServiceTests` tests SMC-unavailable snapshot fallback paths and verifies the app does not fall back to unprivileged direct AppleSMC fan writes when the daemon is unavailable.
- `CurveProfileTests` tests toFanCurve() output and init-time temperature sorting.
- `CurveProfileStoreTests` tests JSON round-trip, missing/corrupt file handling, backup file creation, throwing save failures, and private profile/backup permissions.
- `PowerInfoTests` tests IOKit dictionary parsing for adapter watts, negotiated USB-C voltage/current, PD profiles, signed charge/drain watts, fallback formatting, battery runtime estimates, and plugged-in-but-draining warnings.
- `ThermalPressureTests` tests thermal-pressure labels and elevated menu summaries.
- `TelemetryHistoryTests` tests rolling-buffer trimming and limit clamping.
- `XPCSnapshotCodingTests` tests fan hardware mode/target round trips and older snapshot compatibility.
- `XPCAgentControlCodingTests` tests agent lease, policy, decision, retry metadata, and audit event round trips plus older status compatibility.
- `XPCAuditTokenCodingTests` tests the daemon XPC audit-token byte bridge without requiring a live connection.
- `ViftyDaemonClientTests` tests XPC proxy response decoding for snapshots and audit events, proxy creation failures, timeout invalidation, late callback one-shot behavior, and invalid fan-input rejection before XPC for fixed-RPM and Auto restore paths without a live daemon.
- `DaemonInstallerTests` tests helper install/approve/repair action copy and the administrator fallback install script quotes paths and sets root-owned LaunchDaemon/helper/log permissions before bootstrap.
- `ViftyCtlArgumentsTests` tests agent CLI parsing, audit limit parsing, parse-error helpers, JSON flag detection, unknown wrapper-option rejection, wrapper-vs-child flag separation for `run`, and wrapper `run --json` parsing.
- `ViftyCtlJSONExampleTests` decodes canonical `docs/examples/viftyctl/` JSON examples against current Swift models, verifies capabilities compatibility defaults, and keeps the audit/diagnose JSON Schemas aligned with implementation enums/check IDs.
- `AgentControlServiceTests` tests lease prepare/restore, rollback, monitor restore/retry, expired-lease status visibility/prepare blocking, post-Auto error-state cleanup, cooldown, and user Auto preemption of in-flight prepare.
- `AgentControlPolicyTests` tests hardware, sensor, thermal-pressure, fan-shape/fan-ID validity, RPM-percent, default-duration, and cooldown policy decisions.
- `ViftyCtlRunnerTests` tests status/capabilities/diagnose/audit JSON, capabilities run-lifecycle metadata, capabilities fallback discovery and unavailable exit codes for daemon read failures, blocked diagnose reports and exit codes for daemon read failures, readiness state/action/safe-to-request evaluation including active leases and invalid/duplicate fan IDs, structured JSON command errors, prepare/restore/run flows, child-command preflight, run `--json` pre-child failures, prepare/run denial fail-closed behavior, restore-failure reporting, exit-code propagation, retry-after driven force retries, and interrupted force-retry waits.
- `ViftyCtlProcessRunnerTests` tests child executable resolution, non-directory executable validation for direct paths and PATH lookup, non-executable/missing command rejection before run, shell-style exit-code mapping for real child signal exits, and signal-handler restoration after handled child runs.
- `GuardedRunScriptTests` tests the reusable `examples/viftyctl/guarded-run.sh` wrapper preflights capabilities `runLifecycle` metadata and readiness, gates on `recommendedAgentAction` / `safeToRequestCooling`, treats nonzero blocked diagnose reports as readiness blocks, preserves diagnose failures, keeps force retry opt-in through `VIFTY_GUARDED_RUN_FORCE_RETRY`, delegates to `viftyctl run --json` only after safety gates pass, and keeps the workload shortcut scripts on that guarded path without raw fan-control commands.
- `DocumentationTrustSurfaceTests` keeps README/release/security/hardware-validation/agent/support docs linked to the evidence-backed compatibility status, trust model, support triage guide, and safe agent-cooling runbook.
- `ValidationEvidenceScriptTests` tests `scripts/collect-validation-evidence.sh` gathers read-only system metadata without local hostnames, plist, bundled executable hashes, privacy-review output covering generated summaries, bundled release/agent schema resource hashes, advertised schema resource paths, optional release-artifact verifier summaries, optional release checklist evidence, signing, daemon, and viftyctl evidence, writes reviewer TSV/JSON summary and checksum files, preserves blocked diagnose output even when `diagnose` exits nonzero, records likely private identifier leaks, missing bundled executables, missing bundled schemas, advertised path drift, failed release summaries, release-summary/app-version mismatches, skipped/failed release-summary checks, checksum mismatches, artifact-name drift, release-checklist/app-version mismatches, or missing release-checklist follow-up sections without invoking cooling, and never invokes cooling commands.
- `ValidationEvidenceReviewScriptTests` tests `scripts/review-validation-evidence.sh` accepts supported-hardware, unsupported-hardware safe-block, and installed-release evidence bundles only when the captured files support those claims, writes pass/fail `review-result.json` summaries with explicit manual smoke-test evidence, and rejects privacy-review findings, missing helper probes, skipped notarization evidence, release-summary schema drift, release-summary checksum/artifact/check-status drift, missing or version-drifted release checklists, or failed supported-hardware smoke tests.
- `ValidationReportSummaryScriptTests` tests `scripts/summarize-validation-reports.sh` builds TSV/JSON indexes from valid read-only `review-result.json` files, separates validated supported-hardware evidence from reports still requiring manual smoke-test confirmation, and rejects missing inputs, unsupported modes, non-read-only reports, reports that ran cooling commands, or contradictory passed reports with failures.
- `ReleaseMetadataScriptTests` tests `scripts/validate-release-metadata.sh` accepts aligned release metadata and rejects invalid cask checksums, ad-hoc cask signing metadata, stale privileged-helper cleanup paths, missing release tag/version validation, missing release TeamID build wiring, missing LaunchDaemon TeamID verification, missing GitHub Actions Node.js 24 runtime opt-in, stale `actions/cache@v4` usage, missing notarization workflow steps, release verifier signature/notarization skip flags, missing pre-publish artifact verification/summary publication, missing published release zip/checksum assets, missing `--verify-tag`, or missing Gatekeeper assessment. It also tests `scripts/update-cask-checksum.sh` applies release workflow checksums only when the checksum, artifact version, and release metadata are safe, `scripts/write-release-checklist.sh` writes Developer ID checklists and source-first release notes, and `scripts/check-release-readiness.sh` reports passed metadata/source-ref/source-CI/release-workflow/secrets/release assets or schema-backed machine-readable blockers for stale required source refs, failed source CI, failed Release workflows, missing secrets, missing release trust assets, source-first unsigned-dev checksum drift, and source-first canonical trusted asset misuse.
- `ReleaseArtifactScriptTests` tests `scripts/verify-release-artifact.sh` validates cask SHA/version alignment on a local artifact fixture, supports generated-checksum verification before the cask checksum follow-up commit exists, writes passed and failed machine-readable verification summaries with a stable release-summary schema ID, documents the release-readiness schema contract including source-ref and source-CI checks, rejects checksum, bundle-version, bundled-schema JSON, and bundled-schema ID drift, and keeps signing/notarization checks required by default.
- `GitHubMetadataScriptTests` tests `.github/repo-metadata.json` covers planned discovery topics, issue-template labels, and support-triage labels, and that `scripts/check-github-metadata.sh` accepts matching GitHub fixtures while blocking missing topics, missing labels, and label color/description drift.
- `MakefileTrustGateTests` tests `make verify` remains wired to shell syntax checks for project scripts and agent-facing workload wrappers, release metadata validation, Swift tests, warnings-as-errors build, release app bundling including schema resources, plist lint, codesign verification, and the `viftyctl` identifier check.
- `AppModelTests` tests duplicate-profile overwrite, append behavior, per-fan override fan-ID normalization and clamping, developer workload presets, profile persistence failure surfacing, curve-defaults sync flag, menu power summaries, injected power-reader polling, timed manual-mode expiry/restores, fan-control ownership summaries, agent-lease summary/warning text, agent-lease clear failure surfacing, telemetry-history append, and helper-health/recovery summaries.
- Tests must pass before committing. Run from repo root.

## Conventions

- Use `@MainActor` for UI state, actors for mutable shared state.
- XPC callbacks are one-shot (guarded by `CallbackState` lock).
- SMC key names are 4-char strings (e.g. `F0Ac`, `Tp09`).
- Fan IDs are 0-indexed Ints matching SMC key suffixes.
- Temperature sensor IDs are SMC key strings or `hid-<index>`.
- Bundle identifier: `tech.reidar.vifty` (app), `tech.reidar.vifty.daemon` (Mach service).
- Release hardening knob: `make app CONFIGURATION=release SIGNING_IDENTITY="<identity>" VIFTY_XPC_ALLOWED_TEAM_ID="<TEAMID>"`.
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
