# Vifty Strategy Workplan

**Goal:** Make Vifty the trusted open-source thermal control layer for Apple Silicon developer workloads, with a special focus on safe local agent/build/test cooling.

**Date:** 2026-06-11

**Status:** Active. Local hardening is on `main` for the `v1.1.0` source-first release, and the current local trust gate verifies 432 XCTest cases plus the release app bundle checks. Public binary trust still depends on a future Developer ID signed/notarized release, Homebrew release metadata, and real Apple Silicon MacBook Pro validation reports.

**Current public-release audit:** On 2026-06-11, the published `v1.0.0` GitHub asset existed and its asset digest matched the then-current `Casks/vifty.rb`, but `scripts/verify-release-artifact.sh` failed because the extracted app bundle reported `CFBundleShortVersionString` `0.1.0` while the cask version was `1.0.0`. Treat the `v1.0.0` public artifact as not trust-complete. The `v1.1.0` GitHub Release is source-first and attaches only `Vifty-v1.1.0-unsigned-dev.zip` plus `Vifty-v1.1.0-unsigned-dev.zip.sha256` as tester convenience assets. Do not promote Homebrew or a trusted binary install until Apple Developer Program credentials exist and the Developer ID release lane passes. [release-status.md](../release-status.md) is the current public status page for that distinction.

## Executive Thesis

Vifty should not try to beat every Mac utility at general monitoring. That space is already crowded by mature, polished products. The credible opening is narrower and sharper:

1. Be the auditable fan-control app for Apple Silicon MacBook Pro users who care what privileged software is doing.
2. Own the developer workload use case: builds, tests, local AI coding agents, and long-running automation.
3. Treat fan control as a safety-critical local capability, not as a cosmetic menu-bar toggle.
4. Make compatibility evidence public, repeatable, and machine-readable.

The honest path forward is to position Vifty as "open-source, local-first, agent-safe fan and power control for Apple Silicon MacBook Pros" rather than a broad consumer replacement for every fan/sensor app.

## Competitive Snapshot

Sources checked on 2026-06-11:

- [Macs Fan Control](https://crystalidea.com/macs-fan-control) markets real-time fan and temperature monitoring, custom RPM/temperature-sensor control, and Intel plus Apple Silicon support. Its supported-models page was recently updated and explicitly claims broad Intel/Apple Silicon coverage.
- [TG Pro](https://www.tunabellysoftware.com/tgpro/) is a mature commercial Mac temperature and fan-control app with broad model support, notifications, logging, and polished consumer UX.
- [iStat Menus](https://bjango.com/mac/istatmenus/) is the premium general-purpose menu-bar monitor. Its fan docs say it can raise fan speeds and supports automatic, custom-curve, and manual fan modes.
- [Stats](https://github.com/exelban/stats) is a major free/open-source system monitor, but its README currently labels fan control as "not maintained". That matters: Vifty can be the open-source project that takes fan-control safety seriously.
- [Hot](https://github.com/macmade/Hot) is useful thermal-pressure/throttling visibility, especially on Apple Silicon, but it is observability rather than fan-control workflow ownership.
- [smcFanControl](https://github.com/hholtmann/smcFanControl) is historically important, but its own README frames it around Intel Macs and minimum fan speed control.

## Honest Assessment

### Vifty Strengths

- Open-source implementation with visible SMC write paths, RPM clamping, and daemon/client boundaries.
- Focused Apple Silicon MacBook Pro scope, which is easier to validate deeply than broad Mac coverage.
- Privileged helper architecture, so normal app use does not need repeated root prompts.
- Agent lease model through `viftyctl`, which competitors do not appear to productize.
- Local power telemetry, thermal pressure, fan hardware state, and in-memory history in one app.
- Strong test posture: current local suite is 432 XCTest cases after the audit remediation, release/readiness evidence schemas, cask trust-metadata, cask checksum handoff, release secret/readiness/source-ref/source-CI/release-workflow/source-first preflights, GitHub Actions Node.js 24 runtime opt-in and cache-action versioning, release status trust documentation, release checklist/source-first note publication, release asset-publication checks, release TeamID build wiring checks, release tag/version identity checks, release verifier skip-flag checks, release-summary consistency review checks, release-summary capture-time consistency checks, release-checklist evidence collection/review checks, validation privacy-review checks including generated summaries, validation capabilities-contract checks, direct validation TSV content checks, review-summary TSV/JSON consistency checks, collector manifest output/status checksum coverage checks, manifest status/output consistency checks, evidence-bundle checksum coverage/recomputation checks, daemon-unavailable capabilities review checks, malformed review-result indexer rejection checks, capabilities run-lifecycle metadata, guarded-run lifecycle contract checks, guarded-run force-retry capability checks, guarded-run null-field normalization, capability legacy-field fail-closed decoding, force-retry opt-in, interrupted force-retry JSON error reporting, command-error retry metadata, child-command failure classification, guarded-run child executable preflight checks for PATH and direct paths, workload shortcut checks, real-process child-command resolution/signal-exit checks, non-directory executable validation checks, Auto-restore fan-shape/range preflight checks before SMC/XPC access, helper install/approve/repair action-copy checks, signal-handler restoration checks, fan-control ownership UI summary checks, developer workload preset checks, validation-report hardening, safe-agent-cooling guidance, support-triage, unsupported-hardware policy, GitHub topic/label metadata checks, PR safety review, and CODEOWNERS safety-surface checks.

### Vifty Weaknesses

- Trusted binary distribution is not yet complete until a future release is Developer ID signed, notarized, stapled, and distributed with verified checksums. `v1.1.0` is source-first, with an optional unsigned-dev tester artifact only.
- Hardware support is still claim-limited until real MacBook Pro model reports are collected.
- Competitors have years of UX polish, model compatibility, brand recognition, and support surface.
- Private SMC/HID interfaces are inherently fragile across macOS and hardware generations.
- The project needs crisp public docs explaining why it is safe to install a privileged helper.

### Best Differentiator

The winning differentiator is not "free fan control." It is:

> A safe, auditable local control plane for developer thermal workloads.

That means agent-readable diagnostics, bounded leases, restore guarantees, transparent policy, public validation evidence, and conservative defaults.

## Positioning

### Primary Audience

- Developers using Apple Silicon MacBook Pros for Swift builds, tests, local AI coding agents, video/export tasks, and other bursty workloads.
- Security-conscious users who want open-source fan control and can read the safety model.
- Open-source contributors willing to submit hardware validation reports.

### Secondary Audience

- Power users who want fan curves plus charger/power telemetry in one app.
- Mac utility enthusiasts who prefer transparent local tools.

### Non-Audience

- Casual users who only want a polished all-in-one menu-bar monitor.
- Intel Mac users, Boot Camp users, Hackintosh users, and unsupported hardware owners.
- Anyone expecting App Store distribution.

## Product Principles

1. **Fail closed on writes.** If daemon trust, hardware shape, fan ranges, or sensor state is uncertain, do not write SMC fan state.
2. **Expose intent, not raw power.** Agents request bounded workload cooling, never arbitrary SMC writes.
3. **Make Auto restoration boring.** Every manual/agent path must have clear restore behavior, test coverage, and user-visible failure reporting.
4. **Prefer proof over claims.** Public compatibility should be backed by `viftyctl diagnose --json`, helper probe output, screenshots, and model metadata.
5. **Stay local-first.** No analytics, accounts, cloud sync, or background network dependencies.
6. **Own Apple Silicon MacBook Pros before expanding.** Depth beats breadth for a privileged tool.

## Workstreams

### 0. Maintain Current Local Hardening

**Objective:** Keep the landed hardening trustworthy while product and validation work continues.

Current local state:

- XPC audit-token byte bridging is isolated and tested.
- XPC validator supports TeamID-gated release hardening while preserving local ad-hoc builds.
- Low-level SMC writes are allowlisted.
- Agent-control store/profile/marker persistence is private by default.
- `viftyctl` JSON errors, readiness diagnostics, capabilities run-lifecycle metadata, guarded-run lifecycle/force-retry capability checks, missing capability field fail-closed decoding, force retry behavior, run preflight, and Auto-restore reporting are tested.
- App user Auto now reports daemon agent-lease clear failures instead of swallowing them during follow-up polling.
- Agent-cooling, bug, hardware-validation, and release-trust issue templates now keep blocked readiness and source-first provenance on read-only evidence paths.
- Local gates pass: `make verify` runs 432 XCTest cases with 0 failures after the release/readiness evidence schemas, cask trust-metadata, cask checksum handoff, release secret/readiness/source-ref/source-CI/release-workflow/source-first preflights, GitHub Actions Node.js 24 runtime opt-in and cache-action versioning, release status trust documentation, release checklist/source-first note publication, release asset-publication, release TeamID build-wiring, release tag/version identity, release verifier skip-flag, release-summary consistency review, release-summary capture-time consistency, release-checklist evidence collection/review, validation privacy-review checks including generated summaries, validation capabilities-contract checks, direct validation TSV content checks, review-summary TSV/JSON consistency checks, collector manifest output/status checksum coverage checks, manifest status/output consistency checks, evidence-bundle checksum coverage/recomputation checks, daemon-unavailable capabilities review checks, malformed review-result indexer, capabilities run-lifecycle coverage, guarded-run lifecycle contract checks, guarded-run force-retry capability checks, guarded-run null-field normalization, capability legacy-field fail-closed decoding, force-retry opt-in, interrupted force-retry JSON error reporting, command-error retry metadata, child-command failure classification, guarded-run child executable preflight coverage for PATH and direct paths, workload shortcut coverage, real-process child-command resolution/signal-exit coverage, non-directory executable validation coverage, Auto-restore fan-shape/range preflight coverage before SMC/XPC access, helper install/approve/repair action-copy coverage, signal-handler restoration coverage, fan-control ownership UI summary, developer workload preset, validation-report hardening, safe-agent-cooling guidance, support-triage, unsupported-hardware policy, GitHub topic/label metadata checks, PR safety review, and CODEOWNERS safety-surface increments, plus warnings-as-errors build, release app bundle, plist lint, and strict codesign verification without installing the app.

Remaining local action:

- Use `make verify` as the standard local pre-PR trust gate.
- Keep the source-first `v1.1.0` release honest: do not retag it, do not rename unsigned-dev assets to the canonical notarized artifact name, and do not promote Homebrew until the future Developer ID lane passes.
- Keep old historical plans untouched unless they block contributor understanding.

### 1. Public Trust and Release Hardening

**Objective:** Make the first public release feel safe to install.

Tasks:

- For the future trusted-binary lane, configure Apple Developer TeamID and Developer ID Application signing.
- Build release app with `VIFTY_XPC_ALLOWED_TEAM_ID`.
- Verify daemon accepts only Vifty signing identifiers plus the configured TeamID.
- Notarize, staple, and verify the final zip artifact.
- Publish SHA-256 checksum and update the Homebrew cask SHA with `scripts/update-cask-checksum.sh`.
- Run `scripts/verify-release-artifact.sh --team-id <TEAMID>` against the published artifact after the cask SHA is updated.
- Document exactly what the privileged daemon can write and what it refuses.
- Keep `docs/trust-model.md` linked from README and SECURITY so the privileged-helper boundary is visible before install.
- Keep ad-hoc local build instructions separate from public release instructions.

Exit criteria:

- `spctl --assess`, `codesign --verify --deep --strict`, notarization, stapling, and Homebrew cask install all pass on a clean machine.
- README and `docs/release.md` explain the trust model without hand-waving.

### 2. Hardware Validation Program

**Objective:** Replace "should work" with visible Apple Silicon evidence.

Tasks:

- Use `docs/hardware-validation.md` and the hardware-validation issue template as the canonical report path.
- Use `scripts/collect-validation-evidence.sh --release-summary ./Vifty-v<version>-artifact-summary.json --release-checklist ./Vifty-v<version>-release-checklist.md` to gather the standard read-only evidence bundle from installed release builds and tie hardware reports to the verified release artifact and release checklist.
- Collect reports for at least:
  - M1 Pro MacBook Pro
  - M1 Max MacBook Pro
  - M2 Pro MacBook Pro
  - M2 Max MacBook Pro
  - M3 Pro MacBook Pro
  - M3 Max MacBook Pro
  - M4 Pro MacBook Pro
  - M4 Max MacBook Pro
- Capture `viftyctl diagnose --json`, `ViftyHelper probeLocal`, macOS version, exact model identifier, fan count, fan min/max RPM, fan hardware mode/raw mode/target RPM telemetry, mode-key casing, and whether Auto/Fixed/Curve restore works.
- Add a compatibility table to README only after evidence exists.

Exit criteria:

- At least 5 validated reports before calling the release "Apple Silicon MBP ready".
- At least 2 reports from M3/M4 generation machines before leaning into agent-cooling marketing.

### 3. Developer and Agent Workflow

**Objective:** Make Vifty the default safe preflight for local agent/build/test workloads.

Tasks:

- Publish concise `viftyctl` examples for Swift, Xcode, npm, cargo, pytest, and generic long-running commands.
- Add an "agent contract" section describing `status`, `capabilities`, `diagnose`, `prepare`, `restore-auto`, and `run`.
- Keep JSON schemas or example outputs stable enough for local automation.
- Add copy/paste snippets for Codex, Claude Code, Cursor, shell scripts, and CI-like local runners.
- Add a small `examples/` directory with wrapper scripts.
- Consider a future MCP or Shortcuts bridge only after the CLI contract survives real use.

Current progress:

- `docs/agent-workflows.md` defines the `viftyctl` JSON contract, readiness decision rules, common workload invocations, tested workload shortcut wrappers, and direct prepare/restore guidance.
- `docs/agent-integrations.md` provides copy/paste guarded-run instructions for Codex, Claude Code, Cursor, and shell runners, including explicit "do not call raw SMC or sudo helper" guardrails.
- `docs/safe-agent-cooling.md` provides a short operational runbook for local agents and scripts: read-only capabilities/readiness first, guarded-run preference, conservative duration/RPM starting points, blocked/restore-failure handling, and direct-prepare guardrails.
- `docs/schemas/` gives release tooling and local agents stable schemas for release readiness, capabilities discovery, required readiness safety fields, read-only audit export, status/lease state, structured command errors, actions, fan telemetry, agent-control status, and check IDs; `viftyctl capabilities --json` now advertises source schema paths, installed bundle schema resource paths, schema IDs, and `runLifecycle` guarantees at runtime, and release artifacts are checked for bundled schema resources, valid JSON, and expected schema IDs.
- `examples/viftyctl/guarded-run.sh` provides a shell-friendly preflight plus `viftyctl run --json` wrapper, and `examples/viftyctl/*` now includes tested shortcut scripts for Swift, Xcode, npm, cargo, pytest, local model, and custom workloads, with XCTest coverage proving capabilities `runLifecycle` contract checks, `supportsForceRetry` checks before passing `--force`, missing capability-field fail-closed behavior, ready/degraded/blocked behavior, restore-first decision blocking, missing-decision fail-closed behavior, diagnose failure preservation, opt-in `VIFTY_GUARDED_RUN_FORCE_RETRY` handling, missing and non-executable child-command preflight, structured pre-child failures, executable shortcut scripts, and no raw fan-control commands in those wrappers.
- `viftyctl` rejects unknown wrapper options and unexpected positional arguments so agent typos fail closed instead of silently changing the intended command.
- `viftyctl diagnose` exits 75 for blocked readiness after printing structured JSON, while validation evidence collection and the guarded-run wrapper both preserve blocked reports correctly. Diagnose JSON also includes `recommendedAgentAction` and `safeToRequestCooling` so agents can distinguish normal, caution, restore-first, and stop decisions without parsing warning text.
- `viftyctl audit --json` exposes recent local agent-control audit events through the daemon with `readOnly: true` and `coolingCommandsRun: false`, so users and agents can inspect prepare/restore history after blocked readiness or restore failures without requesting cooling.
- `docs/examples/viftyctl/` provides canonical JSON examples for capabilities, readiness, read-only audit export, active lease status, and structured command errors, with XCTest decoding coverage.
- `scripts/collect-validation-evidence.sh` makes release and hardware reports repeatable without requesting cooling or writing fan state, and now captures bundle plist, installed executable hashes, privacy-review output for likely hostnames, `/Users/...` paths, serial-number labels, or hardware UUID labels, installed release/agent schema resource hashes, advertised schema resource paths from capabilities output, the safe capabilities contract used by guarded workload wrappers, optional release-artifact verifier summaries with schema identity, pass/fail, installed-app version matching, skipped/failed check detection, SHA consistency, and artifact-name consistency, optional release checklists with installed-app version matching and required follow-up coverage, LaunchDaemon TeamID, per-binary signing, notarization, and Gatekeeper evidence alongside `viftyctl` JSON plus manifest rows, per-command status files, reviewer-oriented `review-summary.tsv`, and automation-oriented `review-summary.json`; collector tests require each manifest row's stdout, stderr, and status file to exist and appear in `checksums.tsv`, and the reviewer now requires those summary status rows to agree, requires `manifest.tsv` statuses and output files to match captured evidence, requires captured files to be covered by `checksums.tsv`, and recomputes checksum entries against the captured files.
- `scripts/review-validation-evidence.sh` reviews captured evidence bundles in `release`, `supported-hardware`, or `unsupported-hardware` modes and can write `review-result.json`, so maintainers can mechanically reject privacy-review findings, missing helper probes, skipped notarization, release summaries with a missing/drifted schema contract, release summaries with skipped/failed checks, checksum mismatches, artifact-name drift, missing or version-drifted release checklists, release checklists without required post-publication follow-up coverage, unsupported-hardware reports that only prove daemon failure rather than a safe hardware block, or failed supported-hardware smoke tests.
- `scripts/summarize-validation-reports.sh` builds JSON/TSV indexes from valid reviewed `review-result.json` files, rejects malformed or non-read-only review outputs before they become claims, keeps candidate supported-hardware rows labeled as manual-smoke-required until the review result records `manualSmokeTestResult: "passed-auto-restored"`, then promotes them to `validated-hardware-evidence`.
- `scripts/verify-release-artifact.sh` audits a generated release zip before publication and the public cask artifact after publication, verifying checksum, bundle version, required executables, bundled release/agent schema JSON/IDs, plist validity, Developer ID TeamID, LaunchDaemon TeamID allowlist, stapled notarization, and Gatekeeper assessment, with passed or failed JSON summary evidence that declares `https://vifty.local/schemas/release-artifact-summary.schema.json` for release reviewers.
- `scripts/validate-release-metadata.sh` now rejects casks that regress to ad-hoc `signing_identity identity: "-"`, reference the old `/Library/PrivilegedHelperTools/ViftyDaemon` cleanup path, omit the real `/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon` cleanup path, release workflows that fail to publish the notarized zip, checksum, and verification summary assets, release workflows that fail to build and verify the bundled LaunchDaemon with `VIFTY_XPC_ALLOWED_TEAM_ID`, release workflows that disable public release verifier signature/notarization checks, or release workflows that fail to derive and verify the release version from a `v<version>` tag before publishing.
- CI and Release workflows now opt GitHub JavaScript actions into Node.js 24, CI uses `actions/cache@v5`, and release metadata validation rejects either workflow if that runtime opt-in is removed or the cache action drifts back to Node.js 20.
- `scripts/check-release-secrets.sh` checks the required GitHub Actions release secret names before a release tag is pushed or a failed Release workflow is rerun, so missing Developer ID/notary configuration is visible before another no-artifact run.
- `scripts/check-release-readiness.sh` now gives maintainers a single read-only human/schema-backed JSON preflight for release metadata, optional required source-ref alignment, release-commit CI status, Release workflow status for the tag, required secret names, and GitHub Release asset presence, so `v1.1.0` can be reported as source-ready but public-release blocked without ambiguity, failed Release runs are distinct from missing assets, and stale release tags can be rejected before promotion.
- `docs/release-status.md` now separates the `v1.1.0` source-first release, optional unsigned-dev tester artifact, future trust-complete Developer ID binary release, and Homebrew lane, and tells maintainers not to promote Homebrew until a signed/notarized artifact, checksum, verifier summary, and cask SHA are aligned.
- `scripts/write-release-checklist.sh` now generates either the Developer ID checklist prepended to notarized GitHub Release notes and uploaded as `Vifty-v<version>-release-checklist.md`, or source-first release notes for releases without Apple Developer Program credentials.
- `scripts/update-cask-checksum.sh` now applies the release workflow checksum to `Casks/vifty.rb` only when the checksum is well-formed, the checksum artifact matches the cask version, and release metadata validates before and after the edit.
- `ViftyHelper probe` / `probeLocal` now share a tested formatter that includes fan `hardwareMode`, `hardwareModeRawValue`, and `targetRPM`, making before/after smoke-test evidence easier to audit.
- The app/menu UI now summarizes the current fan-control owner for macOS Auto, Vifty Fixed/Curve, active agent cooling, expired agent leases, and unexpected Forced/System hardware modes, plus active agent workload and target RPMs so humans can see what local agents are doing.
- Agent audit history is now local, private by default, capped to the most recent 2,000 events, and available through a bounded read-only `viftyctl audit` export so lease observability does not become unbounded local retention.
- `docs/support-triage.md` routes release trust, hardware validation, unsupported hardware, helper install, SMC telemetry drift, agent-cooling, and UI reports to read-only evidence and escalation rules before maintainers ask for any fan-write tests.
- `.github/ISSUE_TEMPLATE/agent-cooling.yml` collects exact `viftyctl` commands, diagnose/status/audit JSON, stdout/stderr, Auto-restore state, and no-raw-SMC safety confirmations for agent/build/test cooling failures; blocked readiness is explicitly evidence-only and tells reporters: do not retry `viftyctl prepare` or `viftyctl run` while diagnose says cooling is unsafe.

Exit criteria:

- A local agent can run `viftyctl diagnose --json`, decide whether to proceed, run a workload through `viftyctl run`, and restore Auto without parsing human text.
- Failure states are structured and conservative.

### 4. UX and Product Polish

**Objective:** Make the app trustworthy for humans, not only correct for tests.

Tasks:

- Clarify menu-bar state when hardware mode differs from selected Vifty mode.
- Make active agent leases unmistakable in the UI.
- Provide one-click Auto restore and clear error reporting for failed lease cleanup.
- Improve first-run helper install messaging and recovery instructions.
- Add a screenshot or short demo GIF showing fan/power/agent state.

Current progress:

- The curve editor includes safe developer presets for tests, builds, and local model runs; preset RPM percentages stay under the default agent policy ceiling and loading a preset clears stale per-fan overrides.
- Helper health surfaces now include recovery guidance for helper errors, unreachable daemon state, and reachable helpers with no fan data, so users see when to repair/reinstall and when not to start manual or agent cooling.
- Helper action labels now distinguish first install, Login Items approval, reinstall, repair, and unavailable states instead of always saying reinstall.

Exit criteria:

- A new user can understand whether Vifty, macOS, or an agent currently controls the fans.
- A failed helper/daemon path tells the user the next safe action.

### 5. Safety, Observability, and Auditability

**Objective:** Keep privileged fan control defensible under scrutiny.

Tasks:

- Keep all SMC write paths behind allowlists and tests.
- Keep agent lease audit history private and bounded.
- Keep `viftyctl audit` read-only, bounded, and local; avoid persistent telemetry creep beyond agent-control audit events.
- Add fault-injection tests for daemon unavailable, XPC timeout, interrupted child process, helper permission failures, and restore failures.
- Document private API risk honestly.

Exit criteria:

- Every write path has a test that proves invalid fan IDs/ranges/key names are rejected before SMC access.
- Every restore failure has a visible user or agent-facing signal.

### 6. Distribution and Community

**Objective:** Make the repo easy to trust, install, and contribute to.

Tasks:

- Finish GitHub community files and issue templates.
- Add a release checklist to every tagged release.
- Add GitHub topics: `macos`, `swift`, `apple-silicon`, `fan-control`, `thermal`, `menubar`, `smc`, `developer-tools`.
- Keep the "unsupported hardware" policy clear and linked from compatibility, validation, triage, and trust docs.
- Invite validation reports before asking for broad adoption.
- Keep Homebrew tap/cask metadata aligned with release artifacts.
- Use [support-triage.md](../support-triage.md) to sort incoming reports into release trust, hardware validation, unsupported hardware, helper install, SMC telemetry, agent-cooling, and UI buckets.

Current progress:

- `docs/unsupported-hardware.md` defines unsupported-machine safe-block behavior for Intel Macs, Apple Silicon non-MacBook-Pro machines, unknown fan topology, and untrustworthy telemetry, with read-only evidence commands, reviewer mode, and explicit no-bypass rules.
- `.github/PULL_REQUEST_TEMPLATE.md` now requires contributors to identify safety impact across fan/SMC writes, daemon/helper/XPC boundaries, agent leases, release trust, hardware validation, UI restore/ownership state, and local persistence before review.
- `.github/CODEOWNERS` now explicitly calls out agent-facing contracts, JSON Schemas, release workflows, cask metadata, validation docs, issue templates, and repo safety process files as safety-sensitive review surfaces.
- `.github/ISSUE_TEMPLATE/release-trust.yml` now gives reporters a structured path for GitHub Release asset, Homebrew cask checksum, Gatekeeper, notarization, stapling, Developer ID TeamID, LaunchDaemon TeamID, release-readiness, verifier, and reviewer failures without asking them to bypass trust gates or run fan-write tests.
- The GitHub repository now has the planned discovery topics plus triage labels for release trust, hardware validation, unsupported hardware, helper install, SMC telemetry, agent cooling, UI, and non-sensitive security tracking. `.github/repo-metadata.json` and `scripts/check-github-metadata.sh` make that metadata reproducible and testable.

Exit criteria:

- Fresh users can install via Homebrew from a notarized artifact.
- Contributors know what evidence is needed for hardware support claims.

## 30/60/90 Day Plan

### First 30 Days: Trust Floor

- Finish review of the current audit remediation branch.
- Get Developer ID signing and notarization working.
- Ship a future corrected notarized release with checksum, Homebrew cask update, and passing release-artifact verification after Apple Developer Program credentials exist. Do not retag `v1.1.0`; it is the source-first release.
- Validate at least 3 Apple Silicon MacBook Pro models.
- Publish the compatibility-report workflow.

### Days 31-60: Developer Workflow Proof

- Add practical `viftyctl run` examples and agent integration snippets.
- Collect reports from M3/M4 Pro/Max users.
- Tighten UI copy around active leases, failed restores, and helper state.
- Keep the short "safe local agent cooling" guide current as the CLI contract evolves.

### Days 61-90: Adoption Loop

- Publish a small demo video or GIF.
- Keep example scripts for common workloads aligned with the guarded-run contract as the CLI evolves.
- Decide whether an MCP/Shortcuts bridge is justified by actual users.
- Build a public compatibility matrix from validated reports.
- Triage support issues into hardware, helper install, SMC key drift, and UX categories.

## Risk Register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Apple changes SMC/HID behavior | Fan writes or sensors break on new hardware | Narrow hardware claims, collect diagnostics, fail closed |
| Privileged helper trust concern | Users refuse install | Developer ID, notarization, clear daemon write policy, open-source auditability |
| Competitors out-polish UI | Casual users choose mature apps | Compete on developer workflow, safety, and auditability |
| Agent misuse | Fans left forced or workloads keep running hot | Bounded leases, daemon expiry, preflight diagnostics, visible Auto restore failures |
| Hardware reports are sparse | Public claims remain weak | Make report template easy, ask early adopters directly |
| Private APIs create maintenance drag | Repeated breakage across macOS versions | Keep tests fixture-backed, isolate SMC write policy, publish support matrix |

## Success Metrics

- 100% trusted binary public releases notarized and checksum-published. Source-first releases must instead be clearly labeled, checksum their unsigned-dev tester artifacts if present, and recommend building from source.
- 5+ validated Apple Silicon MacBook Pro model reports.
- 0 known paths where unprivileged app writes SMC directly.
- 0 known agent paths that prepare cooling before child-command validation.
- `viftyctl diagnose --json` used in bug reports and hardware reports.
- Homebrew cask installs cleanly on a fresh Mac.
- README explains why Vifty exists in under 30 seconds.

## Decisions Needed

1. Apple Developer TeamID and signing identity for public release hardening.
2. Whether the corrected public release should be `1.0.1` or a later patch version. Decision: use `v1.1.0` for the expanded agent-safety and release-trust surface.
3. Minimum hardware evidence required before public announcement.
4. Whether the primary public headline is "open-source Apple Silicon fan control" or the sharper "agent-safe fan control for developer workloads".
5. Whether to prioritize MCP/Shortcuts after the CLI stabilizes, or keep integrations script-first for now.

## Recommendation

Lead with the sharper wedge:

> Vifty is the open-source, local-first fan and power control app for Apple Silicon MacBook Pro developers, with bounded cooling leases for builds, tests, and local coding agents.

That is specific enough to beat mature competitors somewhere they are not focused, while still leaving room to become a general trusted thermal utility over time.
