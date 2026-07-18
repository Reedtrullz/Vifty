# Changelog

All notable changes to Vifty will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.0] - 2026-07-18

### Added

- Added a daemon-owned protocol-v2 fan-control transaction engine with single-writer locking, durable recovery journals, complete-fan-set verification, transactional rollback, and confirmed Auto/System restoration.
- Added clearer draft, applying, daemon-confirmed, agent-owned, drift, and recovery states, including requested-versus-effective per-fan targets and curves.
- Added semantic text sizing, notification authorization guidance, contrast/transparency-aware presentation, and native scrollable Settings.
- Added advisory update checks for eligible Developer ID builds, with opt-out daily scheduling, strict stable-release metadata validation, and a locally constructed GitHub release-page handoff. Vifty never downloads or installs executable code.
- Added a no-network operator path for manually supplied, manifest-promoted v1.4.0-or-newer release archives, with SHA/tag binding, safe extraction, signing/notarization/Gatekeeper verification, and the existing fail-closed replacement transaction.
- Added source-bound fixture, Accessibility-tree, and visual-review tooling for deterministic automated UI evidence.

### Changed

- Helper repair, uninstall, app replacement, and termination now share an authenticated Auto-aware lifecycle that proves the service offline and the complete fan set OS-managed before destructive work.
- `viftyctl run` now resolves the child before cooling, supervises its process group, forwards handled signals, bounds descendant cleanup, restores Auto after cleanup, and reports lifecycle failures.
- Profile editing and recovery, selected-versus-hottest temperature semantics, telemetry smoothing labels, compact layouts, and effective per-fan summaries now describe the underlying state more accurately.
- Release automation now accepts only the first automatic push run for an exact signed `v*` tag and binds exact-main CI, pinned release tooling, administrator governance evidence, candidate inventory, signing, notarization, stapling, Gatekeeper, and canonical assets. Manual dispatch and reruns are rejected.

### Fixed

- Startup recovery now completes before polling or saved-mode application, and Auto preempts stale manual or agent work so suspended operations cannot reclaim control.
- Partial multi-fan writes, failed restoration, helper mismatch, and ambiguous app replacement now retain durable recovery ownership and block unsafe follow-on actions.
- Profile backup recovery, sorted curve points, private storage, and explicit dirty, overwrite, and failure states prevent silent loss or misleading profile state.
- App quit and replacement no longer fall through to forced process termination when Auto-aware shutdown cannot be confirmed.

### Security

- Display-only, synthesized, missing, or partial telemetry can no longer authorize fan writes; mutations require fresh eligibility, allowlisted and clamped commands, exclusive ownership, durable prewrite state, readback, and verified rollback.
- XPC clients, helper maintenance, and replacement transactions now bind authenticated component and caller identity, single-use authority, private no-follow storage, and crash-recoverable ledgers.
- Release tooling now verifies tag-only environment admission, an empty-bypass immutable `v*` tag ruleset, repository-secret scope, first-parent release tools, signed-tag provenance, and the one-shot retired-tag operator boundary.

### Scope

- These source capabilities do not by themselves prove publication, notarization, Homebrew promotion, installation, hardware compatibility, human visual review, or VoiceOver validation for the exact v1.4.0 build 8 artifact. Update checks remain advisory; automatic download and in-place updating are not implemented.

## [1.3.2] - 2026-07-13

### Fixed
- Preempt in-flight Fixed or Curve writes when Auto is selected so a suspended fan write cannot resume and reclaim hardware control after Auto appears active.
- Allow recent manual target writes a short telemetry-settling window before showing drift attention, while preserving alerts for sustained target mismatch.

## [1.3.1] - 2026-07-13

### Fixed
- Confirm fan hardware state after Fixed, Curve, and Auto writes so the UI no longer evaluates newly applied control state against stale pre-write telemetry or flashes between active, pending, and drift-attention states.

## [1.3.0] - 2026-07-12

### Changed
- Reframed the main window around explicit readiness, fan-control ownership, and one safe next action.
- Made manual fan edits draft-first with explicit Apply semantics and immediate Auto restoration.
- Improved per-fan curve visibility, profile discoverability, fan target/drift rows, menu-bar status, native Settings categories, compact layouts, and accessibility output.
- Centralized app polling ownership, made manual startup defaults draft-only, improved 1280-class pane allocation, and added native Open Vifty and safely gated Restore Auto commands.
- Made copied support feedback temporary and completed source-level command, layout, startup-safety, and accessibility contracts for the release candidate.

## [1.2.0] - 2026-07-11

### Added
- A responsive three-column workbench now separates safety and mode controls, fan control, and telemetry, while compact windows stack the same operational sections without clipping the curve editor.
- The fan-curve editor now supports direct point dragging, stable chart geometry, clearer axes and value readouts, compact point summaries, developer workload presets, and per-fan curve overrides.
- Menu-bar summaries can combine AI quota, selected temperature, average or primary fan RPM, fan-control owner, adapter wattage, and other user-selected fields; curve profiles can also be selected from the menu.
- Native Settings now owns menu-bar, startup, notification, profile, and agent-workflow tools instead of extending the main control surface indefinitely.
- Optional local notification history, in-memory telemetry trends, launch-at-login control, per-fan fixed RPM targets, and copyable guarded workload commands are now available.
- A Release Trust Report issue template now collects release-readiness JSON, GitHub Release asset listings, verifier/reviewer evidence, Gatekeeper/signing/notarization/cask output, and no-bypass safety confirmations for public binary trust failures.
- GitHub repository topics and triage labels are now captured in `.github/repo-metadata.json`, checked by `scripts/check-github-metadata.sh`, and covered by fixture-backed tests so the contributor/reporting surface stays reproducible.
- `examples/viftyctl/guarded-run.sh` now leaves force retry off by default and requires explicit `VIFTY_GUARDED_RUN_FORCE_RETRY=1` opt-in before passing `--force` to `viftyctl run`.
- Canonical `viftyctl run --json` command-error examples now cover child-launch failures after a prepared cooling lease, including both Auto-restore-success and Auto-restore-failure cleanup states.
- `viftyctl capabilities --json` now includes `runLifecycle` metadata so agents can discover child-command preflight, forwarded signals, Auto restore, structured pre-child failures, and cleanup-state reporting without scraping docs.
- `examples/viftyctl/guarded-run.sh` now checks the advertised `runLifecycle` contract before readiness and refuses cooling if child-command preflight, handled signal forwarding, Auto restore, structured pre-child failures, or launch-failure cleanup reporting are missing.
- `examples/viftyctl/guarded-run.sh` now checks `supportsForceRetry` before passing `--force` so supervised retry opt-in stays tied to advertised CLI capabilities.
- `ViftyCtlCapabilities` now decodes legacy payloads without `supportsForceRetry` as force-retry unsupported, matching the guarded wrapper's fail-closed behavior for missing capability fields.
- `scripts/collect-validation-evidence.sh` now writes `capabilities-contract.tsv` and review summaries flag it when the installed `viftyctl capabilities --json` payload no longer advertises the safe `runLifecycle` and `supportsForceRetry` contract expected by guarded workload wrappers.
- `scripts/collect-validation-evidence.sh` now documents `manifest.tsv` command rows and matching `.status` files inside generated evidence bundles, with tests requiring every manifest output/status file to be checksummed.
- `scripts/review-validation-evidence.sh` now accepts `viftyctl-capabilities` status `69` when the static schema-resource and capabilities-contract evidence still pass, matching the collector's daemon-unavailable but machine-readable capabilities mode.
- `scripts/review-validation-evidence.sh` now directly verifies `schema-resources.tsv`, `capabilities-schema-resources.tsv`, and `capabilities-contract.tsv` contents instead of relying only on `review-summary.json` status rows for the agent-facing contract evidence.
- `scripts/review-validation-evidence.sh` now rejects validation bundles when human-facing `review-summary.tsv` check statuses drift from automation-facing `review-summary.json`.
- `scripts/review-validation-evidence.sh` now validates `manifest.tsv` command rows, output files, and per-command `.status` files against captured summary evidence.
- `scripts/review-validation-evidence.sh` now requires `checksums.tsv` coverage for captured evidence files and recomputes SHA-256 digests and byte counts so files cannot be edited or omitted after collection without reviewer detection.

### Changed
- App polling now coalesces shared hardware refreshes, avoids duplicate power and agent-status work, instruments slow refreshes, and bounds Codex subprocess output and shutdown so background telemetry uses fewer resources and cannot leave inherited pipes hanging.
- Local notifications now coalesce across launches, notification and quit edge cases close cleanly, and quitting waits for confirmed Auto restoration before allowing manual-control ownership to end.
- Codex usage tracking now prefers the current local app-server transport, performs refresh work off the main poll path, and keeps session-log parsing as a bounded fallback.
- Helper repair, daemon provenance, fan-control ownership, blocked-write, and recovery states are now explicit in the main window, menu bar, diagnostics, and evidence bundles.
- Manual and agent cooling paths now fail closed on stale helpers, unsafe readiness, ownership conflicts, malformed metadata, unresolved child commands, or incomplete restore evidence.
- The Hardware Validation Report template now keeps `ViftyHelper probeLocal` optional for unsupported safe-block reports while still asking supported Apple Silicon MacBook Pro validators for helper fan telemetry.
- Hardware validation docs and the issue template now distinguish source builds, source-first unsigned-dev zips, future notarized releases, and Homebrew installs so `v1.1.0` compatibility reports do not imply trusted binary distribution.
- The Bug Report template now steers unsupported or blocked fan reports to `viftyctl diagnose --json` first and keeps helper probe output optional unless supported hardware or maintainer follow-up needs it.
- The Agent Cooling Report template now treats blocked readiness as evidence-only, adds a blocked-before-cooling command path, and warns reporters not to retry `viftyctl prepare` or `viftyctl run` while diagnose says cooling is unsafe.
- The strategy workplan now reflects the landed `main` hardening state, 427-test trust gate, source-first `v1.1.0` assets, and no-retag/no-Homebrew boundaries.

## [1.1.0] — 2026-06-11

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
- Agent workflow documentation now defines the `viftyctl` JSON contract, readiness decision rules, a reusable guarded workload wrapper, and tested shortcut wrappers for Swift, Xcode, npm, cargo, pytest, local-model, and custom workloads.
- Agent integration snippets now document the safe guarded-run pattern for Codex, Claude Code, Cursor, and shell runners.
- `viftyctl` JSON Schemas now document capabilities, readiness diagnostics, status/prepare/restore-auto reports, and structured command errors for local agents.
- Canonical `viftyctl` JSON examples now decode in XCTest so agent-facing payload documentation stays aligned with the Swift models.
- The reusable `guarded-run.sh` example now handles nonzero blocked diagnose reports as readiness blocks, requires `recommendedAgentAction` / `safeToRequestCooling`, refuses restore-first or unsafe decisions before launching the child workload, preserves structured diagnose failures, and delegates through `viftyctl run --json` so wrapper-level failures stay machine-readable for agents.
- The reusable `guarded-run.sh` example now normalizes `null` readiness decision fields as missing so agents fail closed consistently across macOS runner versions.
- The daemon XPC audit-token byte bridge is now isolated in core code with focused tests.
- Release builds can set `VIFTY_XPC_ALLOWED_TEAM_ID` to require a Developer TeamID on daemon XPC clients.
- Tagged releases now have a GitHub Actions workflow for Developer ID signing, TeamID verification, notarization, stapling, checksum generation, and GitHub Release publication.
- A GitHub Hardware Validation Report issue template now collects release compatibility evidence for Apple Silicon MacBook Pro model families.
- A compatibility status page now keeps Apple Silicon MacBook Pro support claims evidence-based and report-backed before broad marketing claims are made.
- A read-only validation evidence collector now gathers system metadata without local hostnames, bundle plist, bundled executable hashes, bundled agent and release-evidence JSON Schema hashes, advertised schema resource paths, agent capabilities contract checks, privacy-review output for likely hostnames, `/Users/...` paths, serial-number labels, or hardware UUID labels, optional release-artifact verifier summaries with schema identity and installed-app version matching, optional release checklists with version/follow-up coverage, LaunchDaemon TeamID, app/CLI/helper/daemon signing checks, notarization/Gatekeeper checks, and `viftyctl` capabilities/status/diagnose JSON for release and hardware reports, including blocked diagnose output, with reviewer-friendly `review-summary.tsv`, automation-friendly `review-summary.json`, `bundle-executables.tsv`, `privacy-review.tsv`, `schema-resources.tsv`, `capabilities-schema-resources.tsv`, `capabilities-contract.tsv`, `release-artifact-summary.tsv` / `.json` and `release-checklist.md` / `.tsv` when supplied, nonzero privacy rows for likely private identifiers, nonzero release-summary rows for skipped/failed verifier checks, checksum mismatches, or artifact-name drift, nonzero release-checklist rows for version drift or missing follow-up sections, and SHA-256 digests for captured evidence files.
- A validation evidence reviewer now checks captured bundles in `release`, `supported-hardware`, or `unsupported-hardware` modes so maintainers can reject weak compatibility or release-trust claims without rerunning fan-control commands, including privacy-review findings, release-artifact summaries with missing or drifted schema identity, skipped/failed verifier checks, checksum mismatches, or artifact-name drift, and release checklists with missing files, version drift, or missing post-publication follow-up coverage, and can write pass/fail `review-result.json` summaries for automation and report attachments.
- A validation report summarizer now builds TSV/JSON indexes from reviewed `review-result.json` files while keeping supported-hardware evidence labeled as manual-smoke-required until the issue template confirms the fan-write smoke test, and rejects malformed, non-read-only, cooling-mutating, unsupported-mode, or contradictory passed review results before they become compatibility claims.
- A release artifact verifier now checks the Homebrew cask artifact SHA or generated workflow checksum, bundle version, required executables, bundled agent/release-evidence JSON Schema syntax and stable IDs, plist validity, Developer ID TeamID, LaunchDaemon TeamID allowlist, stapled notarization ticket, and Gatekeeper assessment before publish and after the cask checksum follow-up, with passed or failed machine-readable summaries that declare the stable release-artifact summary schema ID.
- A cask checksum updater now applies the release workflow's `Vifty-v<version>.zip.sha256` output to `Casks/vifty.rb` only when the checksum and artifact version match, with release metadata validation before and after the edit.
- GitHub workflows now opt JavaScript actions into Node.js 24, use `actions/cache@v5`, and release metadata validation rejects CI or Release workflow drift back to the deprecated Node.js 20 runtime or `actions/cache@v4`.
- A trust model document now explains the privileged helper boundary, SMC write allowlist, agent lease limits, local data handling, and release-signing expectations.
- A safe local agent-cooling guide now gives agent and script authors a short runbook for readiness gating, guarded-run usage, conservative workload limits, blocked-state handling, restore-failure evidence, and forbidden raw fan-write paths.
- A support triage guide now routes release trust, hardware validation, unsupported hardware, helper install, SMC telemetry drift, agent-cooling, and UI reports to the right read-only evidence before maintainers ask for riskier checks.
- An unsupported-hardware policy now defines safe-block behavior for machines outside the Apple Silicon MacBook Pro fan-control scope, including read-only evidence collection and forbidden helper/raw-SMC bypasses.
- The pull request template now requires a safety-impact review for fan/SMC writes, daemon/helper/XPC changes, agent leases, release trust, hardware validation, UI restore/ownership state, and local persistence changes.
- CODEOWNERS now explicitly names agent-facing contracts, JSON Schemas, release workflows, cask metadata, validation policy, issue templates, and repo safety process files as safety-sensitive review surfaces.
- An Agent Cooling Report issue template now collects exact `viftyctl` commands, diagnose/status/audit JSON, stdout/stderr, Auto-restore state, and no-raw-SMC safety confirmations for build/test/agent lifecycle failures.
- Bug report forms now ask for read-only `viftyctl diagnose --json` and `ViftyHelper probeLocal` output for fan, helper, and agent-cooling issues.
- `ViftyHelper probe` / `probeLocal` fan rows now include `hardwareMode`, `hardwareModeRawValue`, and `targetRPM` so validation reports can compare SMC state before and after smoke tests.
- Release metadata validation now checks that release tag/version wiring, bundle version, Homebrew cask version/URL/SHA, cask signing metadata, privileged-helper cleanup path, workflow artifact naming, release TeamID build wiring, bundled LaunchDaemon TeamID verification, notarization/stapling workflow steps, pre-publish artifact verification/summary publication, release verifier signature/notarization checks, published zip/checksum/summary assets, and Gatekeeper assessment agree before CI or release publication.
- A release secret preflight script now checks required GitHub Actions secret names before release tags are pushed or failed release workflows are rerun.
- A release readiness preflight script now validates local release metadata, optional required source-ref alignment, source CI for the release commit, Release workflow status for the tag, required secret names, and GitHub Release asset presence with human and schema-backed JSON output so maintainers can distinguish source/tag readiness from a trust-complete public binary release, reject stale release tags, and surface failed Release workflow runs separately from missing assets.
- The release readiness preflight now supports explicit `developer-id` and `source-first` modes. Developer ID mode keeps the strict Apple secret, Release workflow, canonical asset, verifier, and Homebrew-trust checks; source-first mode supports v1.1.0 without Apple Developer Program credentials while rejecting canonical trusted binary asset names and requiring honest source-first release notes.
- A source-first release-note writer mode and `scripts/build-unsigned-dev-artifact.sh` now prepare optional `Vifty-v<version>-unsigned-dev.zip` tester convenience artifacts plus checksums without using the canonical notarized `Vifty-v<version>.zip` name.
- The release readiness preflight JSON now declares a stable schema ID, and the release artifact/evidence checks verify the bundled `release-readiness.schema.json` resource alongside the release-artifact and `viftyctl` schemas.
- A release status page now distinguishes the `v1.1.0` source-first release, optional unsigned-dev tester artifact, unavailable Developer ID/notarized binary lane, Homebrew trust requirements, and operator checks.
- Tagged releases now publish a generated release checklist as both GitHub Release notes preface and a release asset, separating workflow-verified checks from post-publication cask, verifier, evidence, and compatibility follow-up.
- `make verify` now runs the local trust gate bundle: shell syntax checks for project scripts and agent-facing workload wrappers, release metadata validation, Swift tests, warnings-as-errors build, release app bundling, plist lint, strict codesign verification, and `viftyctl` identifier verification.

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
- The app and menu now show an explicit fan-control owner summary for macOS Auto, Vifty Fixed/Curve, active agent cooling, expired agent leases, and unexpected Forced/System hardware modes.
- The app and menu now show helper recovery guidance for helper errors, unreachable daemon state, and reachable helpers that return no fan data, so users see the next safe action before starting manual or agent cooling.
- The curve editor now includes conservative developer presets for tests, builds, and local model runs, with preset RPM percentages kept under the default agent policy ceiling and stale per-fan overrides cleared when a preset is loaded.
- User Auto now preempts active and in-flight agent cooling; prepares cancelled by Auto report the structured `RESTORE_REQUESTED` code instead of applying a lease after the user restores Auto.
- Agent policy and readiness diagnostics now block invalid or duplicate controllable fan IDs before Vifty reaches the SMC write path.
- Per-fan curve override profiles now stay matched by fan ID in the UI, clamp edited override RPMs to each fan's own range, and avoid traps from duplicate override IDs or malformed short curves.
- Local fan helper and daemon-client writes now reject invalid fan IDs, malformed RPM ranges, and mismatched `FanCommand`/hardware fan IDs before touching SMC keys or opening XPC.
- Hardened runtime exception entitlements were removed from the app and daemon entitlement templates.
- The app bundle version now matches the release-facing cask/repo version.
- The Homebrew cask no longer declares ad-hoc signing and now removes the correct privileged helper path in uninstall caveats.
- Agent-control stores, curve profiles/backups, and manual-control markers now enforce private local permissions, including permission tightening for legacy audit/profile files.
- Profile persistence now has a throwing save path, and the app surfaces profile save/delete failures in `lastError` instead of silently losing them.
- Daemon-client XPC requests now use the same one-shot callback guard for missing-proxy failures and only invalidate the connection from the callback path that wins the response race.
- The administrator fallback installer now explicitly sets root ownership and restrictive permissions on the LaunchDaemon plist and daemon log files before bootstrapping the helper.
- `ViftyHelper probe` now awaits daemon-backed snapshots directly instead of bridging through a semaphore.
- Release artifacts are named `Vifty-v<version>.zip` to match the Homebrew cask download URL.
- XCTest coverage expanded to 389 tests for fan mode probing, helper-probe formatter evidence, per-fan curve override safety, developer workload presets, SMC write allowlisting, helper/daemon-client write behavior and fan-ID/range validation, local persistence permissions and profile-save failure surfacing, bounded agent audit retention and read-only audit export, daemon-client callback handling, installer script hardening, XPC policy/retry metadata and audit-token byte bridging, expired-lease visibility/prepare blocking, post-Auto agent status cleanup, app agent-lease UI summaries, fan-control ownership summaries, helper recovery summaries, app agent-lease clear failure surfacing, and default lease duration, release TeamID allowlisting, release metadata validation including cask SHA, cask checksum updating, cask signing/cleanup metadata, release secret/readiness preflights, release-readiness schema identity and mode field, release source-ref alignment, release source-CI readiness checks, release-workflow readiness checks, source-first readiness and unsigned-dev asset checks, GitHub Actions Node.js 24 runtime opt-in and cache-action versioning, release status trust documentation, release checklist/source-first note publication, release tag/version identity, release verifier skip-flag rejection, release TeamID build/LaunchDaemon verification, notarization workflow gates, Gatekeeper assessment, pre-publish public release artifact verification/summary publication, published release zip/checksum asset checks, release-summary schema identity, release-summary checksum/artifact/check-status review, release-checklist version/follow-up review, GitHub topic/label metadata checks, and Makefile trust-gate wiring, CLI capabilities fallback discovery for daemon read failures, CLI retry behavior including interrupted force-retry waits, readiness diagnostics including agent action/safe-to-request fields, invalid/duplicate fan IDs, and blocked diagnose exit codes, structured JSON command/parse errors, wrapper-vs-child flag parsing, unknown wrapper-option rejection, child-command preflight, guarded-run wrapper decision-field gating, guarded-run force-retry opt-in, tested workload shortcut wrappers, preflight/diagnose-failure behavior including null-field normalization, validation evidence collection, review, and indexing including reviewer TSV/JSON summaries, executable hashes, privacy-review leak detection including generated summaries, schema resource hashes, advertised schema resources, release-artifact summary copy/pass-fail/version-match/schema-ID evidence, release-summary capture-time check/SHA/artifact drift rejection, release-checklist capture/version/follow-up drift rejection, malformed review-result rejection before compatibility indexing, plist/signing evidence, richer helper-probe fan telemetry, unsupported-hardware safe-block reports and policy docs, machine-readable evidence review results, manual-smoke-required and validated-hardware compatibility report rows, skipped-notarization rejection, failed supported-hardware smoke tests, and nonzero blocked diagnose reports, decoded agent JSON examples and schema alignment, runtime schema discovery, bundled schema resource JSON/ID verification, documentation trust-surface links, CODEOWNERS safety-surface coverage, PR safety review, support-triage, trust-model, safe-agent-cooling, and unsupported-hardware guardrails, run `--json` pre-child failure reporting, Auto preemption of in-flight prepare, prepare/run denial fail-closed behavior, restore-failure reporting, signal-style process exit handling, agent integration snippet guardrails, and failed release-artifact summary evidence.

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
