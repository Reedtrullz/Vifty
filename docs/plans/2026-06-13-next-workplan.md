# Vifty Next Workplan

**Date:** 2026-06-13

**Status:** Active next-work plan for post-`v1.1.1` development on `main`.

**Goal:** Move Vifty from source-first credible to day-to-day trusted by proving one real Apple Silicon MacBook Pro path, fixing the visible operational UX issues, and keeping future distribution/updater work tied to the trusted-binary lane.

## Executive Direction

Vifty should stay focused on the narrow wedge already documented in [competitive-analysis.md](../competitive-analysis.md): open-source, auditable thermal control for Apple Silicon MacBook Pro developer workloads. Do not turn the next cycle into a broad iStat Menus clone. The next release should feel safer, clearer, and more reliable for the user who opens Vifty before a build, test run, local model run, or coding-agent session.

The work should land in small, reviewable slices. Keep source-first and unsigned-dev language intact until Apple Developer Program credentials exist. Keep Homebrew parked. Keep Sparkle auto-update unavailable for source-first and unsigned-dev builds; [auto-update.md](../auto-update.md) is future trusted-binary work only.

## Constraints

- The available real hardware for immediate validation is the user's M1 Pro MacBook Pro.
- Other M1 Max, M2, M3, M4, and newer MacBook Pro rows must remain "needs report" until contributor evidence exists.
- Development-build evidence is useful for product confidence, but public release compatibility evidence should clearly record whether the installed app came from `v1.1.1` source, `Vifty-v1.1.1-unsigned-dev.zip`, a local ad-hoc build, or a future trusted binary.
- No fan-write smoke test should run until read-only readiness says the machine is `ready` or safely `degraded`, with `daemonControlPathReady=true` and `manualControlActive=false`.
- No updater, Homebrew, Developer ID, notarization, Gatekeeper, or trusted-binary claim is allowed for source-first or unsigned-dev artifacts.
- Telemetry stays local and in-memory unless a separate privacy plan approves persistence.

## Priority Order

1. Validate the available M1 Pro path and publish only evidence-backed compatibility status.
2. Fix the small-window layout and repeated-use UI problems that are visible in current screenshots.
3. Make helper install, approval, unreachable, repair, unsupported, and healthy states impossible to misread.
4. Finish the menu-bar display settings surface.
5. Add conservative local notifications and better in-memory history visualization.
6. Deepen the developer/agent workflow only after the app feels trustworthy to a human operator.
7. Prepare, but do not enable, future Sparkle auto-update until the trusted-binary lane exists.

## Workstream 1: M1 Pro Validation First

**Objective:** Turn the user's available M1 Pro MacBook Pro into the first reviewed compatibility report, without implying that untested model families are supported.

### 1.1 Decide The Install Source

Use one of these modes, and record it honestly in the evidence bundle:

- `source-build-tag` for a build from the immutable `v1.1.1` tag.
- `source-first-unsigned-dev-zip` for the published `Vifty-v1.1.1-unsigned-dev.zip` tester artifact.
- `local-ad-hoc-build` for current `main` development validation.

For public compatibility, prefer `v1.1.1` source or unsigned-dev evidence. For current development confidence, a local ad-hoc `main` report is still useful, but it should not be presented as the published release result.

### 1.2 Read-Only Evidence Collection

Run the read-only collector before any fan write. For current source-checkout validation, build the app and collect provenance-backed evidence in one step:

```sh
make validation-evidence-current-build
```

Requires a clean git worktree, builds `.build/Vifty.app` before collection, and records the current git ref/SHA as `local-ad-hoc-build`.

If the worktree is dirty, commit or stash first; otherwise keep exploratory evidence at the default `installSource=not-recorded`. If the app was already installed from the current checkout, record that exact source provenance:

```sh
make validation-evidence \
  VALIDATION_EVIDENCE_INSTALL_SOURCE=local-ad-hoc-build \
  VALIDATION_EVIDENCE_SOURCE_REF=main \
  VALIDATION_EVIDENCE_SOURCE_SHA="$(git rev-parse HEAD)"
```

The target is read-only and defaults to `/Applications/Vifty.app` with `installSource=not-recorded`, so it does not pretend an older installed app came from the current checkout. Override `VALIDATION_EVIDENCE_APP`, `VALIDATION_EVIDENCE_OUTPUT`, `VALIDATION_EVIDENCE_INSTALL_SOURCE`, `VALIDATION_EVIDENCE_SOURCE_REF`, `VALIDATION_EVIDENCE_SOURCE_SHA`, or `VALIDATION_EVIDENCE_SOURCE_ARTIFACT` only when the installed app came from a known source.

If validating the published source-first release instead, use:

```sh
make validation-evidence \
  VALIDATION_EVIDENCE_INSTALL_SOURCE=source-build-tag \
  VALIDATION_EVIDENCE_SOURCE_REF=v1.1.1 \
  VALIDATION_EVIDENCE_SOURCE_SHA=a82f2237ff39c24a6b366dca8f95a17ee54fd972
```

If helper fan probe output is needed for the report, run the explicit probe path:

```sh
sudo make validation-evidence \
  VALIDATION_EVIDENCE_INSTALL_SOURCE=source-build-tag \
  VALIDATION_EVIDENCE_SOURCE_REF=v1.1.1 \
  VALIDATION_EVIDENCE_SOURCE_SHA=a82f2237ff39c24a6b366dca8f95a17ee54fd972 \
  VALIDATION_EVIDENCE_INCLUDE_PROBE_LOCAL=1
```

### 1.3 Review The Evidence Bundle

Review captured output without rerunning diagnostics:

```sh
make validation-evidence-review \
  VALIDATION_EVIDENCE_BUNDLE=.build/vifty-validation-<timestamp> \
  VALIDATION_EVIDENCE_REVIEW_MODE=supported-hardware \
  VALIDATION_EVIDENCE_REVIEW_SUMMARY=.build/vifty-validation-<timestamp>/review-result.json
```

Before sharing or indexing, check `privacy-review.tsv` and any file it flags.

### 1.4 Manual Smoke Only If Readiness Allows

Run the manual fan-write smoke only when:

- `viftyctl diagnose --json` is `ready` or safely `degraded`;
- `daemonControlPathReady` is true;
- `manualControlActive` is false;
- fans, sensors, fan IDs, and RPM ranges are valid;
- thermal pressure is not critical;
- helper state is healthy or repair guidance has been completed.

Then follow [hardware-validation.md](../hardware-validation.md): baseline probe, short `prepare`, follow-up diagnose/probe, `restore-auto`, and final diagnose/probe.

After manual smoke passes and Auto restore is confirmed, rerun review with:

```sh
make validation-evidence-review \
  VALIDATION_EVIDENCE_BUNDLE=.build/vifty-validation-<timestamp> \
  VALIDATION_EVIDENCE_REVIEW_MODE=supported-hardware \
  VALIDATION_EVIDENCE_MANUAL_SMOKE_RESULT=passed-auto-restored \
  VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE="local M1 Pro validation, 2026-06-13" \
  VALIDATION_EVIDENCE_REVIEW_SUMMARY=.build/vifty-validation-<timestamp>/review-result.json
```

### 1.5 Optional Agent-Run Smoke

After the manual smoke test, wait for `policy.prepareCooldownSeconds`, then collect one supervised developer-workload smoke from a clean source checkout:

```sh
make agent-run-smoke-evidence-current-build
```

This requires a clean git worktree, builds `.build/Vifty.app`, and runs the smoke through `.build/Vifty.app/Contents/MacOS/viftyctl` so current development evidence does not accidentally exercise an older installed app. Because the privileged XPC service is launchd-installed, the current-build smoke target should also require the installed helper daemon hash to match the freshly built `.build/Vifty.app/Contents/MacOS/ViftyDaemon` before it requests cooling, with the result preserved in `daemon-runtime.tsv` and `agent-run-smoke-evidence-summary.json`. If you are intentionally testing an already installed app from a source checkout, pass the installed CLI explicitly:

```sh
make agent-run-smoke-evidence \
  VIFTYCTL=/Applications/Vifty.app/Contents/MacOS/viftyctl
```

Installed testers can run the bundled collector directly when they do not have a source checkout:

```sh
/Applications/Vifty.app/Contents/Resources/collect-agent-run-smoke-evidence.sh \
  --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl
```

The raw `scripts/collect-agent-run-smoke-evidence.sh` path remains available for advanced local review, but public report instructions should prefer the Make target or installed app resource so the bounded defaults are obvious.

Review it by adding:

```sh
VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY=.build/vifty-agent-run-smoke-<timestamp>/agent-run-smoke-evidence-summary.json
```

The agent-run smoke proves the bounded `viftyctl run` lifecycle, but it does not replace `manualSmokeTestResult: "passed-auto-restored"` for hardware support.

### 1.6 Publish The Result Conservatively

If the M1 Pro report passes:

- generate a local compatibility index from reviewed reports;
- update [compatibility.md](../compatibility.md) only with the generated/report-backed status;
- label M1 Pro/Max according to the report's actual `modelFamily`, `modelIdentifier`, install source, manual smoke result, helper health, fan count, min/max RPM, Auto restore, Fixed/Curve smoke, and `viftyctl diagnose --json` evidence;
- keep M1 Max, M2, M3, M4, and newer rows as "Needs report" until they have their own evidence.

**Exit criteria:**

- One reviewed M1 Pro evidence bundle exists.
- `review-result.json` passes in supported-hardware mode.
- Manual smoke result is either honestly `passed-auto-restored` or explicitly not recorded with the reason.
- Compatibility docs do not broaden the claim beyond the reviewed evidence.

## Workstream 2: Small-Window And Operational UI

**Objective:** Make the main app usable at minimum window sizes and pleasant for repeated use.

### 2.1 Layout Stability

Tasks:

- Ensure both left and right panes scroll predictably at minimum supported window sizes.
- Keep the right-side operational panel full-height so it does not visually cut off while blank space remains below it.
- Preserve stable dimensions for cards, sliders, fan rows, and toolbar controls so dynamic labels do not shift the layout.
- Verify the bottom of each pane is reachable by scrolling, including fan cards and temperature rows.
- Avoid nesting cards inside cards or making page sections look like floating cards.

Implementation notes:

- Inspect `Sources/Vifty/ContentView.swift` for split view, scroll, and frame interactions.
- Prefer one outer split layout with independent `ScrollView`s per pane.
- Add minimum-height and flexible-frame constraints around the right pane rather than relying on content height.

Tests:

- Add focused UI/layout tests where practical, or pure view-model/layout-state tests if SwiftUI inspection remains awkward.
- Use screenshot/manual verification at compact and default window sizes.

**Exit criteria:**

- No useful data is clipped outside the reachable area at minimum window size.
- Right pane spans the full available height.
- The main window still feels like an operational tool, not a marketing dashboard.

### 2.2 Dense Panel States

Tasks:

- Add compact/dense states for Power, History, and Temperatures when the window is constrained.
- Avoid duplicate power information such as separate "140 W adapter" rows when the detailed negotiated power line already makes the adapter state clear.
- Keep high-signal telemetry visible first: selected sensor temperature, fan RPM, control owner/helper state, thermal pressure, and power source.

Tests:

- Add AppModel or formatter tests for compact power summaries.
- Add view-level assertions or screenshot checks when feasible.

**Exit criteria:**

- The app remains scannable at small sizes.
- Power information is not redundant.
- Temperature and fan rows remain readable without overflow.

## Workstream 3: Helper Repair And First-Run Clarity

**Objective:** Remove ambiguity around fan-write availability while preserving fail-closed behavior.

Helper states should be distinct:

- not installed;
- installed but waiting for approval;
- reachable and healthy;
- unreachable but repairable;
- telemetry-only/read fallback available;
- unsupported hardware;
- repair failed;
- healthy after repair.

Tasks:

- Audit `AppModel` helper-health summaries and `ContentView` helper cards.
- Replace dead-end copy like "Fan helper unreachable" with state plus next action: approve, repair, reinstall, open docs, or keep Auto.
- Explain exactly when fan writes are blocked and why.
- Keep reads allowed where safe, but never let the unprivileged app attempt direct fan writes.
- Add repair-flow copy to support triage if users still see the v1.1.0-style helper issue.

Tests:

- Extend AppModel tests for helper state summary/copy.
- Add documentation guard tests if trust/support docs change.
- Keep fail-closed tests intact.

**Exit criteria:**

- A user can tell whether the helper needs approval, repair, reinstall, or unsupported-hardware handling.
- The UI always shows a next safe action.
- Fan writes remain blocked until the daemon/helper path is trustworthy.

## Workstream 4: Menu-Bar Display Settings

**Objective:** Give users control over the menu-bar signal without turning it into a noisy monitor.

Modes:

- icon only;
- selected sensor temperature;
- primary or average fan RPM;
- adapter wattage;
- compact combined summary.

Tasks:

- Add a settings surface in the app for menu-bar display mode.
- Persist the chosen mode with the existing local persistence pattern, not ad-hoc unstructured state.
- Keep formatting stable and compact enough for the macOS menu bar.
- Ensure "current sensor temperature" uses the same selected sensor as the curve/profile UI unless the user explicitly chooses another display sensor later.

Tests:

- Add AppModel tests for selection, formatting, fallback when data is missing, and mode persistence.
- Add MenuBarView tests where practical.

**Exit criteria:**

- User can switch menu-bar display mode without editing code.
- Missing telemetry degrades to icon-only or a safe compact fallback.
- No existing `viftyctl` JSON contracts change.

## Workstream 5: Local Observability

**Objective:** Add practical alerting and history that competitors train users to expect, while keeping Vifty local and conservative.

### 5.1 Notifications

Default off or conservative:

- helper failure or daemon unreachable;
- sustained high or critical thermal pressure;
- Auto restore failure;
- plugged-in battery drain;
- agent lease stuck or restore retry exhausted.

Tasks:

- Add notification settings.
- Use local UserNotifications only.
- Avoid analytics, network calls, or persistent telemetry export.
- Rate-limit alerts to avoid noise.

Tests:

- AppModel tests for trigger conditions and suppression windows.
- Notification scheduler wrapper tests with fakes.

### 5.2 In-Memory History Visualization

Tasks:

- Improve charts for selected sensor temperature, fan RPM, power draw, and thermal pressure.
- Keep history in memory unless a future privacy plan approves persistence.
- Add small hover/readout affordances only if they do not make the operational UI busy.

Tests:

- Extend `TelemetryHistoryTests` for any aggregation/window changes.
- Add formatter tests for chart labels and units.

**Exit criteria:**

- Users can see whether Vifty helped during a workload.
- No persistent telemetry is added.
- Notifications are useful but quiet by default.

## Workstream 6: Developer And Agent Workflow Polish

**Objective:** Make `viftyctl` the safe preflight path that developer tools and local agents can trust.

Tasks:

- Move examples for Swift, Xcode, Make, npm, pnpm, Bun, Go, cargo, pytest, local-model, and custom workloads higher in README.
- Add an "agent readiness checklist" near the CLI docs.
- Keep `diagnose`, `capabilities`, `status`, `audit`, command-error, and run lifecycle JSON contracts stable.
- Add report links or sample transcripts after the M1 Pro validation produces real evidence.
- Defer MCP and Shortcuts until CLI reports show repeated real use.

Tests:

- Keep `ViftyCtlJSONExampleTests`, guarded-run tests, and schema tests stable.
- Add docs guard tests for the readiness checklist if README changes.

**Exit criteria:**

- A local agent can decide whether to request cooling without parsing UI text.
- The README makes guarded-run usage easy to copy.
- Real validation evidence exists for at least one developer-workload smoke.

## Workstream 7: Release Trust And Future Auto-Update

**Objective:** Prepare for trusted distribution without weakening the current source-first boundary.

Tasks for now:

- Keep `v1.1.1` source-first and unsigned-dev wording intact.
- Do not update Homebrew for source-first releases.
- Keep `Resources/Info.plist` free of `SUFeedURL`, `SUPublicEDKey`, and signed-feed keys while source-first mode is current.
- Keep [auto-update.md](../auto-update.md) as the future Sparkle plan.

Future Developer ID tasks:

- Obtain Apple Developer Program credentials.
- Configure Developer ID signing and `VIFTY_XPC_ALLOWED_TEAM_ID`.
- Build, notarize, staple, verify, and publish canonical `Vifty-v<version>.zip`.
- Add Sparkle 2 only after HTTPS appcast hosting, EdDSA appcast signing, `SUPublicEDKey`, `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction`, `generate_appcast`, and artifact verification exist.
- Update Homebrew only after the same canonical artifact passes release verification.

**Exit criteria now:**

- No current build self-updates.
- No docs imply unsigned-dev or source-first artifacts are trusted binaries.
- Future updater work is blocked on trusted release prerequisites.

## Suggested Implementation Sequence

1. Create the M1 Pro evidence bundle and review it.
2. If readiness is safe, run manual smoke and optional agent-run smoke.
3. Index the M1 Pro result and update compatibility conservatively.
4. Fix main-window scroll/full-height layout.
5. Add compact panel states and remove redundant adapter display.
6. Improve helper repair state/copy.
7. Add menu-bar display settings.
8. Add conservative local notifications.
9. Improve in-memory history visualization.
10. Promote developer/agent examples and checklist.
11. Revisit trusted binary and Sparkle only after Apple credentials exist.

## Test Plan

Every implementation slice should run the narrowest meaningful tests first, then `make verify` before commit/push.

Expected additions by workstream:

- Documentation guard tests for this plan, compatibility status, trust boundaries, and future auto-update separation.
- AppModel tests for menu-bar display mode, helper state copy, notification triggers, and compact summary formatting.
- Formatter tests for power and telemetry text.
- Layout/manual screenshot verification for small-window behavior.
- Validation evidence review/index tests only if scripts or schema contracts change.
- Full `make verify` before any release-facing or safety-sensitive commit.

## Non-Goals For This Cycle

- Competing with iStat Menus as a full sensor dashboard.
- Battery charge limiting or battery health policy.
- Cloud sync, accounts, analytics, or network telemetry.
- Persistent telemetry history.
- Raw SMC scripting for agents.
- Sparkle auto-update in source-first or unsigned-dev builds.
- Homebrew cask updates before a verified Developer ID/notarized artifact exists.

## Public Messaging

Use language like:

> Vifty is source-first today. The first real compatibility target is a reviewed M1 Pro MacBook Pro report, with other Apple Silicon MacBook Pro rows staying "needs report" until contributors provide evidence. Auto-update and Homebrew remain future trusted-binary work.

Avoid language like:

- "Apple Silicon MacBook Pros are supported" without report counts.
- "Trusted binary" for source-first or unsigned-dev artifacts.
- "Auto-update coming next" before Developer ID, notarization, and signed appcast prerequisites exist.
- "General monitor" positioning that pulls the product away from auditable fan control.
