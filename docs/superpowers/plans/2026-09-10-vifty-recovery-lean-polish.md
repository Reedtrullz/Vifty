# Vifty Recovery and Lean-Polish Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore one canonical trusted Vifty runtime, prove safe Auto restoration, and then prove Fixed RPM and Temperature Curve through fresh daemon readback on the supported MacBookPro18,1 without weakening fan, helper, release, or recovery safety gates.

**Architecture:** Treat this as runtime recovery first and source work second. Start with read-only evidence and the current dirty-tree verification gate, install only the exact verified public v1.4.5 archive through the reviewed replacement transaction, reconcile native registration/launchd state, and block all manual fan acceptance until `viftyctl diagnose --json` is healthy. Only a receipt-backed source failure may open a minimal test-first code fix.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI/AppKit, IOKit/SMC, privileged XPC daemon, macOS `SMAppService`/launchd/BTM, Bash, Ruby contract tests, `codesign`, `stapler`, and Gatekeeper.

**Spec:** `/Users/reidar/.codex/attachments/52d8f77d-cf59-4c09-b083-ad135b6a23ce/pasted-text.txt`, with current source context in `docs/reviews/2026-09-07-lean-polish.md`.

## Global Constraints

- Work only from branch `codex/lean-polish` at the inherited dirty head `e79bcab20ad7c9eda302fe4594bfa547b15f929a`; never reset, clean, stash, discard, or overwrite existing worktree changes.
- Keep at least 30 GiB free on `/System/Volumes/Data`; stop before any long build or installer run if the guardrail is crossed.
- Preserve `/Applications/Vifty.app`, `/Users/reidar/Applications/Vifty.app`, the root replacement ledger, the public evidence mirror, the stale manual marker, and `.build/vifty-recovery/` until their replacement or removal is proven by the reviewed workflow.
- Use only `/Users/reidar/Projectos/Vifty/.build/vifty-recovery/Vifty-v1.4.5.zip` with SHA-256 `13fa763cbfdca3e77fcf6f657df6d51b32e19a4d25dd17a79614635fe844b0d5` for trusted-runtime recovery.
- Do not copy bundles into protected locations, invoke `cp -p`, edit the root ledger, replay a completed transaction, or invent a rollback path.
- Do not call `ViftyHelper setFixed`, `ViftyHelper auto`, raw SMC tools, `sudo`, direct fan writes, or unguarded `viftyctl prepare` from an agent. Hardware acceptance uses the Vifty UI and normal daemon path.
- Do not run `sfltool resetbtm`, weaken signing/TeamID/launch-constraint gates, or change owner-controlled Login Items/accessibility settings automatically.
- A local test/build success is not installed-release, daemon-reachability, hardware-compatibility, Fixed/Curve, notarization, public-release, or deployment proof.
- No release tag, merge, deployment, or public-release mutation is part of this plan.

## File and Evidence Map

- Existing source under test: `Sources/Vifty/AppModel+Control.swift`, `Sources/ViftyCore/HardwareService.swift`, `Sources/ViftyCore/DaemonWriteGate.swift`, `Sources/ViftyFanControlSafety/LocalFanHelperClient.swift`.
- Existing source tests: `Tests/ViftyCoreTests/AppModelFanControlTests.swift`, `Tests/ViftyCoreTests/FanControlCoordinatorTests.swift`, `Tests/ViftyCoreTests/FanControlArbiterTests.swift`, and `Tests/ViftyCoreTests/LocalFanHelperClientTests.swift`.
- Reviewed operator paths: `scripts/install-vifty.sh`, `scripts/vifty-helper-lifecycle.sh`, `scripts/repair-vifty-helper.sh`, `scripts/uninstall-vifty.sh`, and the `install-public-release`/`repair-helper` Make targets.
- Preserve historical evidence: `.build/lean-polish-20260907/`, `.build/vifty-recovery/`, and `docs/reviews/2026-09-07-lean-polish.md`.
- New continuation evidence: `.build/vifty-recovery/continuation-$STAMP/`, created by the first execution task and retained.
- New final review: `docs/reviews/2026-09-10-vifty-recovery.md`, created only after the recovery attempt has a result to record; it must contain verified claims and explicit non-claims.

## Gate Order

| Gate | Required result | If it fails |
|---|---|---|
| Baseline | Fresh read-only state captured and worktree preserved | Reconcile facts; do not assume the handoff is still current |
| Source | Current dirty head passes `make verify-full` | Debug the failing gate; no runtime mutation or cleanup |
| Trusted runtime | Exact public archive installed through reviewed transaction | Preserve receipts/logs; no direct copy or retry after an unsafe failure |
| Daemon | Canonical path runs, XPC responds, no LWCR/EX_CONFIG failure | Stop at launchd/BTM evidence and owner restart/approval gates |
| Auto | `diagnose --json` exits 0 with clean ownership and Auto readback | Do not clear marker or test manual modes |
| Fixed/Curve | Fresh receipt and daemon snapshot prove the requested mode/target | Preserve receipt; classify root cause before any source edit |
| Closure | Full verification, evidence review, diff review | Leave branch uncommitted and report the exact blocker |

---

### Task 1: Capture a fresh read-only recovery baseline

**Files:**
- Create: `.build/vifty-recovery/continuation-$STAMP/` (ignored evidence directory)
- Read only: `/Library/Application Support/ViftyMaintenanceEvidence/replacement-state-v1.json`
- Read only: `/Library/Application Support/ViftyMaintenanceEvidence/last-execution-v1.json`
- Read only: `/Users/reidar/Library/Application Support/Vifty/manual-control-active`
- Read only: `/Applications/Vifty.app` and `/Users/reidar/Applications/Vifty Recovery 14/Vifty.app`

**Interfaces:**
- Produces: one timestamped evidence directory and a baseline that binds branch, SHA, selected app paths, daemon state, BTM state, hardware probe, marker metadata, disk space, and process state.
- Consumes: the handoff’s preservation boundaries and the root ledger as authoritative recovery state.

- [ ] **Step 1: Confirm the inherited source state without modifying it.**

Run:

```sh
git status --short -b
git rev-parse HEAD
git diff --stat
df -h /System/Volumes/Data
```

Expected: branch `codex/lean-polish`, HEAD `e79bcab20ad7c9eda302fe4594bfa547b15f929a`, the intentional dirty paths remain present, and free space is at least 30 GiB.

- [ ] **Step 2: Create one bounded evidence directory and export its path.**

```sh
STAMP="$(date '+%Y%m%d-%H%M%S')"
export EVIDENCE_DIR="$PWD/.build/vifty-recovery/continuation-$STAMP"
mkdir -p "$EVIDENCE_DIR"
```

- [ ] **Step 3: Capture the daemon, BTM, signing, logs, diagnosis, probe, marker, disk, and process outputs independently.**

Run each command independently and retain nonzero output as evidence:

```sh
git status --short -b >"$EVIDENCE_DIR/git-status.txt"
git rev-parse HEAD >"$EVIDENCE_DIR/git-head.txt"
launchctl print system/tech.reidar.vifty.daemon >"$EVIDENCE_DIR/launchctl-daemon.txt" 2>&1
sfltool dumpbtm >"$EVIDENCE_DIR/btm.txt" 2>&1
codesign -dvvv /Applications/Vifty.app >"$EVIDENCE_DIR/app-codesign.txt" 2>&1
codesign -dvvv /Applications/Vifty.app/Contents/MacOS/ViftyDaemon >"$EVIDENCE_DIR/daemon-codesign.txt" 2>&1
/usr/bin/log show --style compact --last 30m --predicate 'process == "xpcproxy" OR process == "launchd" OR eventMessage CONTAINS[c] "tech.reidar.vifty.daemon"' >"$EVIDENCE_DIR/launchd-log.txt" 2>&1
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json >"$EVIDENCE_DIR/diagnose.json" 2>"$EVIDENCE_DIR/diagnose.stderr"
/Applications/Vifty.app/Contents/MacOS/ViftyHelper probe >"$EVIDENCE_DIR/hardware-probe.txt" 2>&1
/usr/bin/stat -f '%N %Sp %Su %Sg %Sf %m' '/Users/reidar/Library/Application Support/Vifty/manual-control-active' >"$EVIDENCE_DIR/manual-marker-stat.txt" 2>&1
df -h /System/Volumes/Data >"$EVIDENCE_DIR/disk-space.txt"
pgrep -alf 'Vifty|ViftyDaemon' >"$EVIDENCE_DIR/vifty-processes.txt" 2>&1
```

Record the `viftyctl diagnose` exit status beside `diagnose.json`; an exit 75 is expected for the inherited blocked state and is evidence, not a reason to bypass the gate.

- [ ] **Step 4: Verify preserved recovery artifacts are still present and unchanged.**

```sh
ls -lO '/Library/Application Support/ViftyMaintenanceEvidence/replacement-state-v1.json' \
  '/Library/Application Support/ViftyMaintenanceEvidence/last-execution-v1.json' \
  '/Users/reidar/Library/Application Support/Vifty/manual-control-active'
find '/Library/Application Support/ViftyMaintenanceEvidence/ReplacementTransactions/9c0fc2cd-f029-4014-a735-26e44d3d096a' -maxdepth 1 -print
```

Expected: the root ledger and transaction remain available; the public mirror is not treated as rollback authority; the marker is not removed.

### Task 2: Verify the current dirty source tree before runtime mutation

**Files:**
- Read only: `Makefile`, all inherited modified source/test/script paths, and `docs/reviews/2026-09-07-lean-polish.md`
- Create: `$EVIDENCE_DIR/verify-full.log`

**Interfaces:**
- Consumes: current dirty HEAD and the existing SwiftPM/Make verification contract.
- Produces: current-tree verification evidence; no source changes.

- [ ] **Step 1: Ensure no competing SwiftPM or Xcode verification job is running.**

```sh
pgrep -alf 'swift-build|swiftc|xctest|xcodebuild' || true
```

Stop only an owned stale verification process after checking its PID and open files; do not interrupt an unrelated user build.

- [ ] **Step 2: Run the cheap diff gate.**

```sh
git diff --check
```

Expected: exit 0. Any whitespace error is fixed only in the inherited intended diff and rechecked; unrelated changes are not reformatted.

- [ ] **Step 3: Run the full current-tree gate once.**

```sh
set -o pipefail
make verify-full SWIFT_BUILD_PATH="$PWD/.build" 2>&1 | tee "$EVIDENCE_DIR/verify-full.log"
```

Expected: exit 0 with the current helper-lifecycle extension included. Retain the existing historical logs; do not overwrite them.

- [ ] **Step 4: If the gate fails, enter systematic debugging instead of installing or cleaning.**

Classify the first failing command, reproduce only that command, inspect the relevant current diff and caller chain, and record the failure in the continuation evidence. Do not proceed to helper recovery until the current source gate is green or the user explicitly chooses to continue with a named source blocker.

### Task 3: Select and install the canonical signed runtime

**Files:**
- Consume: `.build/vifty-recovery/Vifty-v1.4.5.zip`
- Use without editing: `scripts/install-vifty.sh`, `scripts/vifty-helper-lifecycle.sh`, `scripts/repair-vifty-helper.sh`, `Makefile`
- Preserve: `/Applications/Vifty.app`, `/Users/reidar/Applications/Vifty.app`, and root replacement evidence
- Create: `$EVIDENCE_DIR/public-release-summary.json`, `$EVIDENCE_DIR/public-install.log`

**Interfaces:**
- Input: exact archive SHA `13fa763cbfdca3e77fcf6f657df6d51b32e19a4d25dd17a79614635fe844b0d5`.
- Output: `/Applications/Vifty.app` is the selected canonical public-release path only if the reviewed installer completes and its post-swap evidence passes.

- [ ] **Step 1: Recheck the archive identity and public artifact trust.**

```sh
PUBLIC_ARCHIVE="$PWD/.build/vifty-recovery/Vifty-v1.4.5.zip"
export PUBLIC_ARCHIVE
shasum -a 256 "$PUBLIC_ARCHIVE" | tee "$EVIDENCE_DIR/public-archive-sha256.txt"
scripts/verify-release-artifact.sh \
  --artifact "$PUBLIC_ARCHIVE" \
  --release-version 1.4.5 \
  --team-id X88J3853S2 \
  --summary "$EVIDENCE_DIR/public-release-summary.json"
```

Expected: the checksum matches exactly and the verifier proves the archive’s Developer ID identity, Team ID, notarization, stapling, Gatekeeper result, bundle contents, and manifest binding.

- [ ] **Step 2: Run the reviewed public-release installer.**

```sh
set -o pipefail
make install-public-release PUBLIC_RELEASE_ARCHIVE="$PUBLIC_ARCHIVE" 2>&1 | tee "$EVIDENCE_DIR/public-install.log"
```

Do not copy the bundle manually, use `cp -p`, pass a direct app/URL/SHA override, or edit the root ledger.

- [ ] **Step 3: Classify installer failure before any retry.**

If the installer reports a protocol mismatch, receipt failure, unknown active authority, or any result other than the reviewed `HELPER_UNREACHABLE` admission, stop and preserve the transaction evidence. Do not replay finish/release-lock, invoke a raw unlock, or retry the helper script. The exact public-helper recovery extension is admitted only for ordinary uninstall on the exact `HELPER_UNREACHABLE` path and must remain inside the reviewed lifecycle.

- [ ] **Step 4: Verify the selected app identity after a successful install.**

```sh
codesign -dvvv /Applications/Vifty.app >"$EVIDENCE_DIR/selected-app-codesign.txt" 2>&1
codesign -dvvv /Applications/Vifty.app/Contents/MacOS/ViftyDaemon >"$EVIDENCE_DIR/selected-daemon-codesign.txt" 2>&1
shasum -a 256 /Applications/Vifty.app/Contents/MacOS/ViftyDaemon >"$EVIDENCE_DIR/selected-daemon-sha256.txt"
```

Expected: the selected app and daemon are the verified signed bundle, with Team ID `X88J3853S2`; the ad-hoc `/Applications` build is no longer the trusted runtime.

### Task 4: Reconcile native registration and launchd without weakening trust

**Files:**
- Use: `/Applications/Vifty.app`, `SMAppService` through the app’s helper-maintenance UI, `scripts/repair-vifty-helper.sh`
- Read only: `launchctl print`, `sfltool dumpbtm`, unified logs, installed plist/helper metadata
- Do not modify: `sfltool` state directly, launch constraints, TeamID allowlists, or root evidence ledgers

**Interfaces:**
- Consumes: the canonical signed app selected in Task 3.
- Produces: one daemon registration bound to `/Applications/Vifty.app/Contents/MacOS/ViftyDaemon`, with a responding XPC service and no duplicate-path ambiguity.

- [ ] **Step 1: Open the canonical app and use its native Install Helper/Repair Helper action.**

```sh
open -a /Applications/Vifty.app
```

Complete only the owner-authenticated native action presented by Vifty. If the reviewed operator wrapper is required by that flow, use only:

```sh
make repair-helper REPAIR_HELPER_APP=/Applications/Vifty.app
```

Do not invoke `vifty-helper-lifecycle.sh` with hand-written replacement-phase arguments.

- [ ] **Step 2: Preserve the user’s background-login intent.**

Do not automatically toggle Login Items. If native UI requires an owner-authenticated disable/re-enable refresh, record the original disposition first and restore that same disposition; do not use `sfltool resetbtm`.

- [ ] **Step 3: Honor one owner restart gate if launchd requests it.**

Before the restart, capture `launchctl print`, `sfltool dumpbtm`, and the latest unified log output into `$EVIDENCE_DIR`. Restart once through the normal macOS UI, then repeat the read-only captures. Do not attempt another registration cycle before checking the new state.

- [ ] **Step 4: Verify daemon identity and reachability.**

```sh
launchctl print system/tech.reidar.vifty.daemon >"$EVIDENCE_DIR/launchctl-after-registration.txt" 2>&1
sfltool dumpbtm >"$EVIDENCE_DIR/btm-after-registration.txt" 2>&1
/usr/bin/log show --style compact --last 15m --predicate 'process == "xpcproxy" OR process == "launchd" OR eventMessage CONTAINS[c] "tech.reidar.vifty.daemon"' >"$EVIDENCE_DIR/launchd-after-registration.log" 2>&1
/Applications/Vifty.app/Contents/MacOS/viftyctl status --json >"$EVIDENCE_DIR/status-after-registration.json" 2>&1
```

Pass only when launchd has no `needs LWCR update`, no repeated `78: EX_CONFIG` spawn failure, the daemon process is running, `status --json` can obtain daemon state, and the executable path resolves to the selected canonical bundle. A duplicate same-ID path or another launch-constraint rejection is a blocker; do not reset BTM automatically.

### Task 5: Prove clean Auto state and remove the stale marker only through the owner path

**Files:**
- Use: `/Applications/Vifty.app` UI and daemon-backed `viftyctl` read-only commands
- Preserve until proof: `/Users/reidar/Library/Application Support/Vifty/manual-control-active`
- Create: `$EVIDENCE_DIR/auto-recovery-*`

**Interfaces:**
- Consumes: a responding canonical daemon.
- Produces: diagnosis exit 0, explicit Auto/System readback, no active manual owner, and no stale marker left by an unverified operation.

- [ ] **Step 1: Run the readiness gate before touching manual controls.**

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json >"$EVIDENCE_DIR/diagnose-before-auto.json" 2>"$EVIDENCE_DIR/diagnose-before-auto.stderr"
AUTO_DIAGNOSE_EXIT=$?
printf '%s\n' "$AUTO_DIAGNOSE_EXIT" >"$EVIDENCE_DIR/diagnose-before-auto.exit"
```

Continue only when the exit is 0 and the JSON contains `daemonControlPathReady=true`, `daemonStatusAvailable=true`, `manualControlActive=false`, `safeToRequestCooling=true`, an empty `coolingBlockerIDs` array, and a fresh daemon snapshot. If it remains blocked, do not test Fixed/Curve and do not remove the marker.

- [ ] **Step 2: Apply Auto through the Vifty UI and wait for a fresh poll.**

Select Auto and use the normal Apply/Restore Auto action. Let the app complete its fresh snapshot and ownership confirmation. Do not invoke `ViftyHelper auto` or a raw SMC command.

- [ ] **Step 3: Confirm Auto from independent read-only evidence.**

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl status --json >"$EVIDENCE_DIR/status-after-auto.json"
/Applications/Vifty.app/Contents/MacOS/ViftyHelper probe >"$EVIDENCE_DIR/probe-after-auto.txt" 2>&1
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json >"$EVIDENCE_DIR/diagnose-after-auto.json" 2>"$EVIDENCE_DIR/diagnose-after-auto.stderr"
```

Expected: both controllable fans are freshly confirmed Auto/System-managed, ownership is clear, `manualControlActive=false`, and the daemon reports no recovery blocker.

- [ ] **Step 4: Verify marker retirement through the application path.**

The marker may disappear only as a consequence of the verified daemon-owned Auto restoration. If it remains, keep it and record its metadata; do not `rm` it manually.

### Task 6: Supervised Fixed RPM and Temperature Curve acceptance

**Files:**
- Use: `/Applications/Vifty.app` UI and the responding daemon
- Read only: `viftyctl status --json`, `viftyctl audit --limit 20 --json`, `ViftyHelper probe`, app/daemon logs
- Create: `$EVIDENCE_DIR/fixed-*`, `$EVIDENCE_DIR/curve-*`

**Interfaces:**
- Fixed path: `AppModel.applyCurrentModeSelection()` → coordinator manual batch → daemon/XPC → `FanControlArbiter` → `LocalFanHelperClient.apply(_:fan:)`.
- Curve path: the same transaction path after `FanControlCoordinator` resolves the selected sensor/curve to bounded fixed-RPM targets.
- Acceptance output: fresh `FanMutationReceipt`/audit evidence plus fresh daemon snapshot; a successful write call without readback is not acceptance.

- [ ] **Step 1: Capture the starting Auto state and fan bounds.**

Record the current fan IDs, minimum/maximum RPM, hardware mode, target RPM, selected sensor, and snapshot timestamp from the UI/daemon evidence. Choose a Fixed target inside every controllable fan’s trusted range; do not invent a raw RPM outside the reported bounds.

- [ ] **Step 2: Apply Fixed RPM through the UI.**

Select Fixed RPM, apply the bounded target, wait for a fresh daemon snapshot, and record the full mutation receipt or audit event. Pass only when every expected controllable fan reports `Forced`, every target equals the requested/clamped value, and the final receipt confirms `Ftst` disabled. A UI label or successful button press is insufficient.

- [ ] **Step 3: Restore Auto immediately after Fixed acceptance.**

Use the UI’s Restore Auto action, wait for a fresh snapshot, and record explicit Auto/System mode and `Ftst=0` confirmation. If restoration fails or is not freshly confirmed, stop all further testing.

- [ ] **Step 4: Apply Temperature Curve through the UI.**

Start from the verified Auto state, choose one valid reported temperature sensor, apply the existing valid curve profile, and record the current temperature plus the expected interpolated/clamped RPM. Confirm the daemon snapshot and UI state agree for every controllable fan. Exercise the edited-profile path once only if the acceptance target includes profile editing; do not add a new profile feature.

- [ ] **Step 5: Restore Auto after Curve acceptance and capture final evidence.**

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl status --json >"$EVIDENCE_DIR/curve-status.json"
/Applications/Vifty.app/Contents/MacOS/viftyctl audit --limit 20 --json >"$EVIDENCE_DIR/curve-audit.json"
/Applications/Vifty.app/Contents/MacOS/ViftyHelper probe >"$EVIDENCE_DIR/curve-probe.txt" 2>&1
```

Expected: explicit Auto readback after restoration, no active manual owner, and no stale marker without an owner-approved reason.

### Task 7: Conditional receipt-backed source fix

**Files:**
- Inspect first: `Sources/Vifty/AppModel+Control.swift`, `Sources/ViftyCore/HardwareService.swift`, `Sources/ViftyCore/DaemonWriteGate.swift`, `Sources/ViftyFanControlSafety/LocalFanHelperClient.swift`
- Test first in the owner of the invariant: `Tests/ViftyCoreTests/LocalFanHelperClientTests.swift`, `Tests/ViftyCoreTests/FanControlCoordinatorTests.swift`, `Tests/ViftyCoreTests/FanControlArbiterTests.swift`, or `Tests/ViftyCoreTests/AppModelFanControlTests.swift`
- Do not modify: release metadata or trusted installed bundles as part of this task

**Interfaces:**
- Input: one fresh failure with `FanMutationError.code`, `primaryError`, `cleanupErrors`, and `FanMutationReceipt` fields captured.
- Candidate shared invariants: `LocalFanHelperClient.apply(_:fan:)` must end Fixed with `observedMode == .forced`, exact `observedTargetRPM`, and `forceTestDisabled == true`; Auto cleanup must have `recoveryConfirmed == true`; coordinator ownership must be confirmed by fresh daemon readback.
- Output: one minimal source change only if the evidence identifies a source defect, plus a regression test that fails before the change and passes after it.

- [ ] **Step 1: Classify the failed acceptance without retrying blindly.**

Use the receipt to distinguish mode reclaim/registration, target encoding or clamping, Ftst cleanup, daemon/XPC stale-state, and UI/coordinator publication errors. Trace from `AppModel.applyCurrentModeSelection()` through `FanControlCoordinator.applyManualBatch` and the daemon/arbiter boundary before editing.

- [ ] **Step 2: Add one deterministic failing fixture for the identified invariant.**

Place the fixture in the existing test owner. For a low-level mismatch, extend `LocalFanHelperClientTests` with the exact mode/target/Ftst readback sequence. For coordinator or ownership publication, extend `FanControlCoordinatorTests`, `FanControlArbiterTests`, or `AppModelFanControlTests` with the exact observed state. Do not add a new abstraction or dependency.

- [ ] **Step 3: Run the focused failure before implementing the fix.**

```sh
swift test --scratch-path "$PWD/.build" \
  --filter 'LocalFanHelperClientTests|FanControlCoordinatorTests|FanControlArbiterTests|AppModelFanControlTests'
```

Expected: the new fixture fails for the receipt-backed reason, not because of an unrelated build or environment failure.

- [ ] **Step 4: Implement the smallest root-cause fix in the shared path.**

Preserve mode readback, exact target readback, `Ftst` cleanup, Auto rollback, ownership confirmation, daemon write gates, and all existing error codes. Do not make the UI hide a mismatch, weaken a final check, add retry loops outside the existing bounded unlock path, or install a local ad-hoc build over the trusted public runtime.

- [ ] **Step 5: Run focused tests, then repeat Tasks 2, 5, and 6.**

The source fix must pass the focused suite and the full current-tree gate before any new hardware claim. A local/ad-hoc source build is separate evidence and must not be described as the public v1.4.5 artifact.

### Task 8: Evidence review, lean-polish scope closure, and integration decision

**Files:**
- Create: `docs/reviews/2026-09-10-vifty-recovery.md`
- Preserve: `docs/reviews/2026-09-07-lean-polish.md` and all `.build/vifty-recovery/` evidence
- Read only until all gates pass: complete `git diff`, source/test/script inventories, release metadata, and safety contracts

**Interfaces:**
- Consumes: the continuation evidence directory and all source/runtime/hardware gate results.
- Produces: an evidence-backed review with verified claims, non-claims, blocker IDs, exact app/archive identity, and the final integration recommendation.

- [ ] **Step 1: Re-run the full verification after any source edit or lifecycle change.**

```sh
git diff --check
set -o pipefail
make verify-full SWIFT_BUILD_PATH="$PWD/.build" 2>&1 | tee "$EVIDENCE_DIR/verify-full-final.log"
```

Expected: exit 0 on the final current tree. Do not claim the earlier 2,031-case result as current proof if the final run is missing.

- [ ] **Step 2: Review the complete dirty diff for safety and scope.**

```sh
git status --short -b
git diff --stat
git diff -- Makefile Sources Tests scripts docs/reviews
```

Confirm no raw fan-write path, release gate, TeamID check, launch-constraint check, Auto restoration, readback invariant, accessibility rule, or evidence-provenance boundary was weakened.

- [ ] **Step 3: Keep optional cleanup deferred unless measured and independent.**

Do not add shared privacy scanners, more subprocess abstractions, or further Codex session optimization during recovery. Add one only after the runtime and hardware gates pass, a bounded measurement demonstrates a real cost, and the change has its own focused test and reviewable diff.

- [ ] **Step 4: Write the dated review with explicit claims and non-claims.**

The review must state the final branch/SHA, full verification result, selected app/archive identity, launchd/BTM outcome, diagnosis exit/fields, Auto evidence, Fixed evidence, Curve evidence, Ftst result, marker outcome, and every unproven item. It must explicitly state whether any raw SMC write, unsafe rollback, global BTM reset, release tag, deployment, or public release mutation occurred.

- [ ] **Step 5: Decide integration only after the review.**

If all done criteria pass, review the complete diff and prepare the branch for user-approved commit and code review. If any runtime or hardware gate remains blocked, leave the inherited worktree intact, do not create a release tag or deploy, and hand off the exact blocker and evidence path.

## Done Criteria

- [ ] The current dirty head passes `make verify-full SWIFT_BUILD_PATH="$PWD/.build"`.
- [ ] Exactly one canonical signed app path is selected, and the public archive identity is recorded.
- [ ] The launchd daemon runs without LWCR/launch-constraint/EX_CONFIG failure and responds over XPC.
- [ ] `viftyctl diagnose --json` exits 0 with `daemonControlPathReady=true`, `daemonStatusAvailable=true`, `manualControlActive=false`, `safeToRequestCooling=true`, and no cooling blockers.
- [ ] Explicit Auto restoration is freshly confirmed for every controllable fan, with `Ftst=0` and no unexplained marker.
- [ ] Fixed RPM succeeds through the UI/daemon path with Forced mode, exact bounded targets, fresh readback, and final `Ftst=0`.
- [ ] Temperature Curve succeeds through the UI/daemon path with correct sensor/curve resolution, fresh readback, and explicit Auto restoration.
- [ ] The final review records evidence and non-claims; prior-version or local-test evidence is not promoted into current public-release or hardware claims.
- [ ] No raw SMC write, unsafe rollback, global BTM reset, release tag, merge, deployment, or public-release mutation occurred without the required explicit approval.
