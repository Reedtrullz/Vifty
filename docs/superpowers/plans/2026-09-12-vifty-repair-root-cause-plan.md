# Vifty runtime recovery and Fixed/Curve acceptance plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task-by-task with review checkpoints.

**Goal:** Repair the Vifty installation path and validate the current dirty source on live hardware so Fixed RPM and Temperature Curve either work with confirmed SMC readback or stop with a precise, preserved blocker.

**Architecture:** Keep the existing fail-closed lifecycle and fan-control transaction. Make the smallest orchestration correction needed to separate the canonical replacement target from the signed control bundle used to recover an unreachable helper. Then build the current source as a local Developer ID app, register its matching daemon through the existing macOS service flow, and perform bounded UI-driven Fixed/Curve smoke tests with Auto restoration and evidence.

**Tech Stack:** Swift 6 / Swift Package Manager, XCTest, Bash, Ruby contract fixtures, macOS `SMAppService`, launchd, IOKit/SMC, Developer ID signing.

**Spec / handoff:** `/Users/reidar/.codex/attachments/52d8f77d-cf59-4c09-b083-ad135b6a23ce/pasted-text.txt`

**Current review:** `/Users/reidar/Projectos/Vifty/docs/reviews/2026-09-12-vifty-root-cause-review.md`

## Current execution override — 12-09-2026

The original recovery-source separation work in this plan is complete and the daemon lifetime root cause is now fixed. Do not repeat those phases or install the historical public archive.

### Verified now

- `Sources/ViftyDaemon/main.swift` uses `dispatchMain()` after Mach-listener registration; `Tests/ViftyCoreTests/DaemonTerminationSignalGateTests.swift` guards against regression.
- Hermetic `make verify-full SWIFT_BUILD_PATH="$PWD/.build"` passed 2,041 XCTest cases and all release/Ruby trust suites. The current dirty source was then rebuilt as a local Developer ID candidate and deep-strict signature verification passed.
- The candidate daemon SHA is `1202d284d60e930e871fe5df1fc6ef133a3eed6106f9811883a6e39f0bf2bd2e`. The installed `/Applications/Vifty.app` is Developer ID signed but still contains the older daemon SHA `6802e5b1966fac2c006244ade309526dbf3dabe538cdca1344513ce46fdef751`.
- Read-only launchd/BTM evidence points at the canonical `/Applications` bundle, while that old daemon exits 0 before serving XPC. Installed `viftyctl diagnose --json` therefore exits 75 with `HELPER_UNREACHABLE`; direct local telemetry confirms both physical fans are in Auto/System mode. No fan/SMC write has been attempted.

### The only remaining critical path

1. Capture fresh read-only state and keep the signed candidate immutable.
2. Obtain one explicit owner-present authorization for termination of the currently running old Vifty app. The reviewed installer will try normal AppleScript quit first; it must not force-terminate or overwrite a live bundle. If normal quit still cannot prove safe termination, the owner must perform the one-time native Force Quit/Activity Monitor action; Codex must not do that silently.
3. Run the reviewed same-path installer against `/Applications/Vifty.app`. Do not set `QUIT_RUNNING_APP=0` as a bypass; that mode intentionally exits 75. Do not reset BTM, mutate launchd directly, or reboot as a first-line fix.
4. Re-read installed app/daemon byte identity, `launchctl print`, BTM, and `viftyctl diagnose --json`. Continue only when the new daemon remains alive and diagnose exits 0 with daemon and policy status available.
5. If the new bundle is installed but `SMAppService` still reports `enabled` while launchd resolves the old daemon bytes, stop. Add a minimal identity-aware stale-registration check/rebind path through the existing native service-management flow; never solve that branch with raw launchctl/BTM edits.
6. Only after readiness passes, perform supervised UI Fixed and Curve tests with fresh daemon readback and explicit Auto restoration. Keep all live hardware claims separate from source/build evidence.

This override supersedes the earlier “ad-hoc app/public archive” starting-state text and the already-completed recovery-source implementation tasks below; the architectural safety requirements and later readiness/acceptance gates remain applicable.

## Non-negotiable boundaries

- Preserve all existing dirty worktree changes and recovery artifacts. Never use `git reset`, `git checkout`, `git clean`, `git stash`, broad deletion, or an unreviewed overwrite.
- Do not run `sudo`, `sfltool resetbtm`, raw SMC tools, `ViftyHelper setFixed`, `ViftyHelper auto`, direct fan RPM writes, unguarded `viftyctl prepare`, or hand-written replacement lifecycle phases.
- Do not ask for or place an administrator password, 1Password secret, or fingerprint in chat. The native macOS prompt is the only credential boundary.
- Do not attempt another privileged operation while the owner is AFK. Pause before the first `osascript ... with administrator privileges` call, Login Items approval, or reboot.
- Do not treat a passing source gate, catalog advertisement, bundle signature, `diagnose` exit alone, or mode registration as hardware acceptance.
- Keep the public v1.4.5 archive as recovery evidence only. Do not install it as the final current-source repair because its helper predates the dirty-tree SMC hardening.
- Use no subagents for the privileged path. The state is serialized across one root ledger, one launchd label, one BTM registration, and one physical fan transaction; parallel work would increase risk without reducing the critical path.

## Verified starting point

The current worktree is `codex/lean-polish` at `e79bcab20ad7c9eda302fe4594bfa547b15f929a`, with pre-existing dirty changes plus the daemon lifetime repair. The fresh hermetic gate passed under `umask 022`, including 2,041 XCTest cases, but that only proves the current source tree and fixtures. The existing `/Applications/Vifty.app` is Developer ID signed, but its installed daemon is the older pre-`dispatchMain()` binary and exits 0; the helper is unreachable, `diagnose` is blocked, the signed Recovery 14 app remains a separate usable control source, and the recovery evidence is preserved.

The current source already contains the relevant writer hardening:

- `LocalFanHelperClient` confirms the mode key reads back as Forced after every manual-mode write.
- A silently ignored/protected mode write may enter the existing guarded `Ftst` unlock/retry path.
- Fixed target, final Forced mode, exact target RPM, and `Ftst=0` remain receipt requirements.
- Failure cleanup still attempts Auto and reports unconfirmed recovery instead of claiming success.

No further SMC code should be changed until the current source is running through a matching daemon and the live readback failure is reproduced or cleared.

## Implementation tasks

### 1. Add the smallest safe recovery-source/target separation

**Modify:**

- `scripts/vifty-helper-lifecycle.sh`
- `Sources/Vifty/DaemonInstallService.swift`
- `Tests/ViftyCoreTests/HelperLifecycleScriptTests.swift`
- `Tests/Ruby/InstallerLifecycleTrustContractTests.rb`
- `Tests/Ruby/HelperLifecycleReplacementFixtureTests.rb`

The current script uses `APP_PATH` for both the executable source (`Vifty`, `viftyctl`, `ViftyHelper`, `ViftyDaemon`) and the bundle whose replacement ledger may need unlocking. That is the root cause of the failed recovery attempt. Keep `--app` as the target and add one explicit `--control-app` argument for the exceptional uninstall-only recovery path.

Required behavior:

1. Default `CONTROL_APP_PATH` to `APP_PATH`, so every existing normal repair/uninstall/replacement invocation is byte-for-byte equivalent in behavior.
2. Accept `--control-app` only when `--operation uninstall` is selected and no replacement phase is selected. Reject it for repair and for `prepare`, `finish`, or `release-lock` with a usage/configuration error before invoking any helper, `launchctl`, or root worker.
3. Canonicalize both paths without following a symlink for the final bundle. Require both to be real `Vifty.app` directories, require the control path to differ from the target, and record the target in the existing `app` field. Add an explicit control-source field to the operator record so the recovery provenance is not ambiguous.
4. Resolve `VIFTY_CTL`, `VIFTY_MAIN`, `VIFTY_HELPER`, and `VIFTY_DAEMON` from `CONTROL_APP_PATH`. Keep all replacement-ledger lookup, `capture_bundle_binding`, `release_prior_replacement_lock_after_quiesce`, and target identity checks bound to `APP_PATH`.
5. Validate the control app before any maintenance command: complete bundle, exact component identifiers, deep strict code signature, Developer ID signatures for all four executables, one matching TeamID `X88J3853S2`, and the pinned recovery helper SHA `4c467d99f7e59c2727f0e1a9b13de81772741d269b560ce6ca9fb605782f0d0f`. Reuse the existing bundle-binding/signature checks where possible; do not add a new signing verifier.
6. Snapshot the control app’s helper as the trusted offline helper. Continue to use the existing root verification, Auto-only authorization, launchd disable/offline proof, caller binding, and root-owned ledger removal. The root worker must never execute the control app’s `Vifty` or `viftyctl`; those remain user-side control calls, while the root worker uses only its staged helper snapshot.
7. Keep the ordinary public fallback restricted to uninstall. Do not make `--control-app` a general repair bypass or allow it to authorize a raw fan write.
8. Update the lifecycle hash embedded in `DaemonLifecycleScriptLoader.bundled` after the script change. Compute it with `/usr/bin/shasum -a 256 scripts/vifty-helper-lifecycle.sh` and replace the compiled literal with that exact digest; add/retain a test that the bundled loader accepts only those bytes.

Tests to add or extend:

- A fixture uninstall with a locked replacement ledger bound to target app A and signed/control fixture app B. Assert that control calls use B, the root record/ledger uses A, A is unlocked only after Auto proof, the transaction evidence is removed only after identity validation, and the service is left absent.
- A negative test that passes `--control-app` to repair or a replacement phase and proves no helper or registrar is invoked.
- A negative test for an ad-hoc, wrong-TeamID, wrong-identifier, symlinked, or wrong-helper-digest control bundle; assert a fail-closed result and an unchanged target ledger/tree.
- A regression assertion that using the Recovery 14 bundle as the control source no longer causes the `/Applications` replacement ledger to be treated as unrelated.
- Contract assertions for the new argument, target/control fields, the pinned helper digest, and the absence of direct `chflags`, `sudo`, raw replacement-phase replay, or unguarded SMC commands in the operator path.

Do not add a second recovery script, a new root protocol, or a `--force-unlock` flag. The existing lifecycle already owns the hard part.

### 2. Run focused verification before touching the machine again

Run from `/Users/reidar/Projectos/Vifty`:

```sh
df -h /System/Volumes/Data
git diff --check
/bin/bash -n scripts/*.sh scripts/lib/*.sh examples/viftyctl/*.sh
swift test --filter ViftyCoreTests.HelperLifecycleScriptTests
swift test --filter ViftyCoreTests.DaemonInstallServiceTests
swift test --filter ViftyCoreTests.LocalFanHelperClientTests
/usr/bin/ruby Tests/Ruby/InstallerLifecycleTrustContractTests.rb
/usr/bin/ruby Tests/Ruby/HelperLifecycleReplacementFixtureTests.rb
```

The long gate must use a permissive fixture umask and isolated Git configuration so a restrictive shell umask cannot create false fixture failures:

```sh
(
  umask 022
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    make verify-full SWIFT_BUILD_PATH="$PWD/.build"
)
```

Capture every result under the bounded evidence directory `/Users/reidar/Projectos/Vifty/.build/vifty-recovery/root-cause-20260912/`. Do not create unbounded `/private/tmp` scratch trees. If free disk falls below 30 GiB, stop before another build. Preserve the existing evidence directory and prior logs.

### 3. Build a current, locally signed candidate without calling it a release

A Developer ID identity is currently available for TeamID `X88J3853S2`. After the focused/full source gates pass, build the dirty source with that identity and the release XPC TeamID:

```sh
SIGNING_IDENTITY='Developer ID Application: REIDAR OVERREIN JOESSUND (X88J3853S2)' \
VIFTY_XPC_ALLOWED_TEAM_ID='X88J3853S2' \
make app CONFIGURATION=release SWIFT_BUILD_PATH="$PWD/.build"
```

Verify the candidate before installation:

- `codesign --verify --deep --strict .build/Vifty.app` succeeds.
- All four bundled executables have the expected identifiers and TeamID.
- The bundled LaunchDaemon plist points at the current candidate and has `VIFTY_XPC_ALLOWED_TEAM_ID=X88J3853S2`.
- The embedded lifecycle digest equals the current script digest.
- The candidate’s source provenance is recorded as the dirty `codex/lean-polish` worktree at HEAD `e79bcab...`, not as a public release.

Do not update `Casks/vifty.rb`, the release manifest, GitHub, or public release notes. This is a local runtime validation build.

### 4. Wait for the owner-authorized recovery boundary

Do not execute this phase now while the owner is AFK. When the owner is present, explain that one native administrator prompt is about to appear and that the password/fingerprint must be entered only into macOS’s prompt. Do not collect it in chat.

Before the prompt, capture read-only state:

- current `/Applications/Vifty.app` path, bundle version/build, flags, component hashes, and signature summary;
- root ledger and transaction metadata hashes/ownership without reading protected secret material;
- `launchctl print`/`print-disabled` for `tech.reidar.vifty.daemon`;
- BTM records for both `/Applications/Vifty.app` and the Recovery 14 source;
- process and `lsof` checks proving no Vifty app/daemon/helper is actively mutating the target;
- `viftyctl diagnose --json` exit/status, expected to remain blocked at this point.

1Password is not a gate here: the earlier `op signin`/`op whoami` check already completed and no secret was accessed.

### 5. Execute the corrected single recovery operation

Use the reviewed lifecycle once, with the canonical target and signed control source separated:

```sh
./scripts/uninstall-vifty.sh \
  --app /Applications/Vifty.app \
  --control-app "$HOME/Applications/Vifty Recovery 14/Vifty.app" \
  --record "/Users/reidar/Projectos/Vifty/.build/vifty-recovery/root-cause-20260912/uninstall-control-target.json"
```

Expected lifecycle properties:

- the control app’s `viftyctl` classifies the unreachable helper and the control app’s `Vifty` performs the verified post-root legacy unregister;
- the root worker disables and proves the exact daemon label offline;
- the pinned public Auto-only helper is staged only after root verification;
- the helper proves complete current fan inventory, fresh Auto/System readback, and `Ftst=0` before cleanup;
- the root worker validates the existing `/Applications` replacement ledger against `/Applications/Vifty.app`, unlocks only that exact target and its transaction child, and removes the ledger only through the existing durable identity checks;
- legacy helper/daemon/plist/log artifacts are removed only after the same proof;
- no fan-write operation is issued and no direct `chflags`/`sudo` path is used.

Accept exit 0 only with the lifecycle record and root evidence showing all required phases. Exit 75/76 is a stop, not a reason to retry. Preserve the evidence and report the exact failed phase.

Immediately verify, read-only:

```sh
stat -f '%N %Su:%Sg %Sf' /Applications/Vifty.app
launchctl print system/tech.reidar.vifty.daemon
launchctl print-disabled system
```

The target bundle may still exist, but it must no longer carry the replacement `schg` lock, and the helper label must be absent/disabled according to the lifecycle record.

### 6. Reversibly quarantine the obsolete ad-hoc app

Only after the corrected lifecycle proves the target is unlocked, the label is offline, and no process has an open handle:

1. Create a unique, private evidence/quarantine directory inside the repository’s bounded recovery evidence tree.
2. Move `/Applications/Vifty.app` there with one reversible filesystem move.
3. Verify the move by path, content manifest, ownership, and absence of `/Applications/Vifty.app`.
4. Record the quarantine path; do not delete it.

If the move is denied after the lifecycle’s unlock proof, stop and report the exact flag/ownership/handle evidence. Do not run `chflags`, `sudo mv`, Finder workarounds, or repeated attempts.

The Recovery 14 source app remains preserved in `~/Applications` unless the BTM cleanup requires an owner-approved normal uninstall/reboot. Do not delete it as part of this step.

### 7. Clear the BTM/LWCR conflict through native state only

Re-read Login Items/BTM and launchd after the lifecycle. The desired state is one canonical future registration source: `/Applications/Vifty.app`; no active Recovery 14 duplicate; no stale root `/Applications` registration; no `LWCR update`/exit 78 launch failure.

- If exact lifecycle unregister removed the duplicate, continue.
- If macOS still reports an enabled duplicate or stale `LWCR`, stop and request one owner-present reboot. Do not reset BTM with `sfltool`, edit its database, or repeatedly register/unregister from competing bundles.
- After reboot, re-check BTM, launchd, and the preserved evidence before installation. A reboot is an explicit owner action and cannot be completed unattended.

### 8. Install the current dirty source to the canonical path

Once `/Applications` is absent and BTM is not actively owning a conflicting Vifty service, install the candidate built from the current source:

```sh
SIGNING_IDENTITY='Developer ID Application: REIDAR OVERREIN JOESSUND (X88J3853S2)' \
VIFTY_XPC_ALLOWED_TEAM_ID='X88J3853S2' \
OPEN_AFTER_INSTALL=0 \
make install SWIFT_BUILD_PATH="$PWD/.build"
```

The installer’s existing preflight and replacement transaction must remain enabled. It should see an absent destination, build/copy the current candidate, and verify source/staged/installed byte identity and Developer ID signatures. If it instead sees a conflicting app or helper state, stop; do not weaken the preflight or fall back to the old public archive.

Record the installed app’s current dirty-tree provenance, version/build, component hashes, plist TeamID, and `codesign` output. This is a local Developer ID build, not a published release and not evidence transferable to `v1.4.5` public-release claims.

### 9. Register the matching daemon and resolve approval once

Open the exact installed app:

```sh
open /Applications/Vifty.app
```

Use the existing app UI’s Install/Reinstall Helper action. If macOS opens Login Items approval, the owner must approve it while present. Do not automate or bypass that UI. Do not run raw launchctl registration.

If the app reports `requiresApproval`, approve once and wait for the app to refresh. If it reports `notRegistered`, register from the app. If it reports `unknown`, stop and reboot rather than guessing. If a registered but mismatched daemon remains, use the app’s Repair/Reinstall Helper action, which invokes the reviewed lifecycle and its native administrator prompt.

Verify that the installed daemon path and SHA match `/Applications/Vifty.app/Contents/MacOS/ViftyDaemon`, that the label is loaded from the canonical bundle, that TeamID/signing constraints are satisfied, and that no `OS_REASON_CODESIGNING`, `LWCR`, or exit 78 remains.

### 10. Prove readiness before any fan command

Run only read-only checks first:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json \
  > "/Users/reidar/Projectos/Vifty/.build/vifty-recovery/root-cause-20260912/diagnose-ready.json"
diagnose_status=$?
printf '%s\n' "$diagnose_status" > "/Users/reidar/Projectos/Vifty/.build/vifty-recovery/root-cause-20260912/diagnose-ready.exit"

VIFTYCTL=/Applications/Vifty.app/Contents/MacOS/viftyctl \
MANUAL_SMOKE_READINESS_JSON=1 \
MANUAL_SMOKE_EXPECTED_DAEMON=/Applications/Vifty.app/Contents/MacOS/ViftyDaemon \
MANUAL_SMOKE_REQUIRE_DAEMON_MATCH=1 \
make manual-smoke-readiness
```

Proceed to hardware smoke only when all of the following are true:

- `diagnose` exits 0;
- daemon status and policy status are available;
- `safeToRequestCooling` and the manual control readiness gate are true;
- `manualControlActive` is false and ownership/recovery state is clear;
- the complete fan inventory is present with valid mode keys, ranges, and current Auto/System readback;
- the installed daemon hash matches the current installed app;
- no BTM/LWCR or helper-registration blocker remains.

If any item fails, preserve JSON/stderr and stop. Do not test Fixed/Curve against a blocked daemon.

### 11. Perform bounded live Fixed RPM acceptance

Use the installed Vifty UI only. Select a safe target derived from each fan’s live minimum/maximum range; do not hard-code a low RPM and do not use `ViftyHelper` or raw SMC tools.

1. Capture the pre-test snapshot: fan IDs, mode keys, current Auto/System mode, target/min/max RPM, thermal pressure, and helper/daemon identity.
2. Select Fixed RPM in the UI and apply one bounded target for the shortest meaningful observation window.
3. Capture the UI/daemon receipt and a fresh snapshot for every selected fan.
4. Accept only if each fan has confirmed Forced mode, exact requested target RPM, `Ftst=0`, no mutation/recovery errors, and a matching daemon transaction receipt.
5. Select Auto in the UI and wait for a fresh receipt proving Auto/System-managed mode for the complete fan set and `Ftst=0`.

A mode label alone is not acceptance. A write return alone is not acceptance. If readback stays Auto or target drift persists, stop with the receipt and restore result; do not retry the same workload or bypass the daemon.

### 12. Perform bounded Temperature Curve acceptance

Only after Fixed passes and Auto restoration is proven:

1. Capture the curve/profile and the selected temperature sensor identity.
2. Select Temperature Curve in the UI with the existing normalized three-point profile.
3. Use a short, bounded workload or natural thermal change sufficient to produce a fresh sensor sample; avoid an unbounded stress process.
4. Verify the coordinator’s resolved RPM is within the fan’s live bounds and that the daemon receipt/readback reports Forced mode and the expected target for the curve sample. Capture at least one second sample if the temperature changes.
5. Select Auto and require complete Auto/System plus `Ftst=0` readback before ending.

If the sensor is missing, curve resolution is malformed, the target is outside bounds, or the daemon receipt does not match the displayed curve decision, stop and preserve the exact state. Do not classify a UI selection as a working curve.

### 13. Optional agent-cooling smoke only after manual acceptance

This is not required to prove Fixed/Curve. If the user later wants it, run the existing read-only readiness gate and supervised guarded-run collector only after manual acceptance, with a short duration and conservative maximum RPM. Never call `viftyctl prepare` directly. Keep the agent result separate from manual hardware acceptance.

### 14. Final verification and handoff

Run the final read-only inventory:

- `git status --short --branch`, `git diff --check`, and exact current source SHA/dirty state;
- installed app version/build, code signatures, TeamID, daemon plist, installed daemon SHA, and launchd path;
- BTM/Login Items records with one canonical enabled registration;
- `viftyctl diagnose --json`, status, audit, and readiness output;
- Fixed receipt/readback and Auto receipt/readback;
- Curve receipt/readback and Auto receipt/readback;
- preserved quarantine path and all recovery evidence paths;
- disk free space and owned temporary-directory check.

Only then may the final report say “Fixed and Curve passed on this runtime.” If the live gates did not run or any gate failed, report “source repaired / runtime not accepted” with the exact blocker and no stronger claim.

## Definition of done

The repair is complete only when all rows are true:

| Gate | Required proof |
| --- | --- |
| Source integrity | Focused tests and hermetic `make verify-full` pass on the preserved dirty tree. |
| Recovery correctness | The new target/control lifecycle test passes and the current run unlocks only the exact `/Applications` ledger-bound tree. |
| Old-state preservation | The old ad-hoc app is reversibly quarantined with a content manifest; no recovery evidence is deleted. |
| macOS registration | One canonical Developer ID app owns the daemon; no duplicate BTM/LWCR failure remains. |
| Runtime parity | Installed daemon bytes and app-bundled daemon bytes match exactly. |
| Readiness | `diagnose` exit 0, complete fan inventory, policy/daemon availability, no blockers, manual control inactive. |
| Fixed | Every selected fan confirms Forced and exact target readback, with `Ftst=0`, followed by confirmed Auto. |
| Curve | Curve decision/resolved RPM and daemon receipt/readback agree, followed by confirmed Auto. |
| Evidence | Logs/JSON/receipts are bounded, privacy-safe, and tied to the installed dirty-source provenance. |

## Stop conditions

Stop immediately and preserve the evidence on any of these conditions:

- lifecycle exit 75 or 76;
- replacement ledger, transaction path, bundle identity, code signature, or control-source digest mismatch;
- helper label active/unknown after a supposed freeze;
- BTM duplicate, `LWCR`, or exit 78 registration failure after exact unregister;
- any administrator/Login Items/reboot prompt while the owner is unavailable;
- `diagnose` blocked, incomplete, or missing daemon/policy status;
- Fixed/Curve readback mismatch, target drift, missing Auto confirmation, or `Ftst` not zero;
- free disk below 30 GiB or unexplained large temporary directories;
- any temptation to bypass a gate with raw `sudo`, `chflags`, SMC/helper commands, `sfltool`, or a second retry.

The next action after a stop is a small evidence review, not another blind attempt.
