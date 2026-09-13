# Vifty One-Shot Recovery and Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to execute this plan task-by-task. Steps use checkbox syntax for tracking. Do not dispatch subagents: the work is serialized privileged state, and the global Vifty rules forbid treating parallel observations as one recovery transaction.

**Goal:** Convert the current blocked ad-hoc Vifty installation into the exact notarized v1.4.5 runtime, repair its helper and launchd registration, prove daemon-backed Auto ownership, and perform only supervised Fixed/Curve/Auto acceptance while preserving every inherited artifact and dirty source change.

**Architecture:** Run one sequential operator flow with a private evidence directory and fail-closed checkpoints. Request the 1Password desktop-app authorization immediately, then keep all long-running source checks non-mutating and hermetic; only after they pass enter the native administrator boundary for helper teardown, reversible old-app quarantine, public installation, and helper registration. Reuse install-vifty.sh, vifty-helper-lifecycle.sh, uninstall-vifty.sh, repair-vifty-helper.sh, the existing daemon receipts, and the app UI; do not add a second fan-control or replacement implementation.

**Tech Stack:** Swift Package Manager, Swift/XCTest, Bash, Ruby evidence/contract scripts, macOS launchd/SMAppService/BTM, codesign, Gatekeeper, notarized Developer ID archive, and 1Password CLI desktop integration.

**Spec:** docs/superpowers/plans/2026-09-10-vifty-recovery-lean-polish.md, docs/reviews/2026-09-10-vifty-recovery.md, docs/trust-model.md, docs/support-triage.md, docs/safe-agent-cooling.md, and the repository/global AGENTS.md files.

## Global Constraints

- Preserve branch codex/lean-polish, inherited dirty paths, existing recovery ledgers, manual-control markers, and prior evidence; never reset, clean, stash, overwrite, or delete them.
- Bind this run to current HEAD e79bcab20ad7c9eda302fe4594bfa547b15f929a unless a new plan is explicitly written for a different tree.
- Use the exact public archive /Users/reidar/Projectos/Vifty/.build/vifty-recovery/Vifty-v1.4.5.zip with SHA-256 13fa763cbfdca3e77fcf6f657df6d51b32e19a4d25dd17a79614635fe844b0d5.
- Keep /Applications/Vifty.app as the canonical destination. Do not install a second public copy, use a URL/SHA override, or fall back to ~/Applications.
- Ask 1Password before any long command by running op signin --account my.1password.com; use desktop integration, never print or persist a session token, and never read a password or secret into a shell variable.
- 1Password authorization is not Vifty fan/helper authorization. The native administrator prompt from the reviewed lifecycle script is a separate boundary; do not pipe a password into it and do not call sudo.
- Do not use `sudo -v`, an AppleScript password argument, a shell prompt, or any credential-cache workaround to pre-authorize macOS. Let the reviewed lifecycle call show the native prompt only after all non-mutating gates are green.
- Never background, multiplex, or bury a prompt-producing lifecycle/install command behind a long build. Run the prompt window in the foreground with the terminal visible and all evidence paths already prepared.
- Run source tests with GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null so host-wide Git SSH signing through 1Password cannot make temporary fixture commits nondeterministic. This does not modify the user's Git configuration.
- Do not call ViftyHelper setFixed, ViftyHelper auto, raw SMC tools, direct RPM writes, unguarded viftyctl prepare, sfltool resetbtm, or hand-written lifecycle replacement phases.
- Do not weaken the installer provenance gate. The existing ad-hoc release app must be safely unregistered and reversibly quarantined before the public installer is allowed to see an absent destination.
- Do not request cooling or perform manual fan writes while diagnose --json is blocked, safeToRequestCooling is false, daemonControlPathReady is false, manualControlActive is true, or blocker IDs are non-empty.
- Stop on unknown/active helper authority, malformed or expired receipts, protocol mismatch without the exact approved fallback, changed bundle identity, duplicate active BTM registration, or any installer exit that is not explicitly classified by its evidence.
- No release tag, merge, deployment, public release mutation, or commit is part of this repair.

## Why the first interactive boundary is different

The previous exact-archive install correctly stopped at exit 75 because /Applications/Vifty.app is an ad-hoc v1.4.5 build 13 with no Team ID. The installer will not treat that bundle as an authenticated predecessor merely because its version matches the public archive. Retrying the same command, signing the old bundle ad hoc again, editing the ledger, or resetting BTM would bypass the trust model.

The safe one-shot has two owner boundaries:

1. 1Password desktop-app authorization is requested immediately, before disk/build work. It is idempotent and completes quickly if already authorized.
2. The Vifty lifecycle invokes a native macOS administrator prompt when it tears down or registers the privileged helper. That prompt cannot be safely pre-satisfied through 1Password or sudo; the operator must remain present until the prompt burst has completed. After that, the controller can run unattended.

The source gate runs before the administrator boundary unless an exact, fresh green gate is already bound to the same HEAD, dirty tree, and archive. This prevents a 30-minute test failure from occurring after helper teardown.

## Administrator-prompt timing contract

The execution controller must make the macOS password request a short, explicit handoff:

1. Complete 1Password authorization, the read-only baseline, the cheap binding checks, and—only if the prior green evidence is not reusable—the hermetic source/archive gate.
2. Create the evidence directory, open the log files, and verify the exact archive and expected destination state before invoking any lifecycle command.
3. Send one operator-facing notice: `Preflight is green. Stay at the Mac; the Vifty administrator prompt is next.` Do not ask for the password in chat or accept it in the terminal.
4. Run the helper transition and public install in the foreground. The first native prompt occurs when the reviewed lifecycle enters its root boundary; the public replacement transaction may show another prompt during its prepare/finish boundary. Type the administrator password directly into each native macOS dialog as soon as it appears. Do not authorize unrelated dialogs.
5. Do not start another build, test, network request, or UI smoke action while the prompt-producing command is active. If a prompt is cancelled, unexpected, or ambiguous, stop and preserve the transaction receipt; do not retry automatically.

This is the fastest safe timing because it removes the long wait after a password prompt without spending administrator authorization before the run is known to be ready. A successful public install owns the normal registration lifecycle; a routine extra `make repair-helper` call is intentionally avoided because it would create another privileged transition.

---

### Task 0: Start the one-shot session and request 1Password immediately

**Files:**
- Create: .build/vifty-recovery/one-shot-$STAMP/ (ignored evidence only)
- Read only: /Users/reidar/Projectos/Vifty/AGENTS.md, /Users/reidar/Projectos/AGENTS.md
- Do not read: vault item contents, passwords, session tokens, or SSH private keys

**Interfaces:**
- Consumes: the operator's current terminal and 1Password desktop integration.
- Produces: an authenticated 1Password CLI session check and an evidence directory that records only passed/failed, not account secrets.

- [ ] Step 1: Launch from the repository and set the non-secret account filter.

    cd /Users/reidar/Projectos/Vifty
    export OP_ACCOUNT="${OP_ACCOUNT:-my.1password.com}"

- [ ] Step 2: Ask for 1Password authorization before any long-running work.

    op signin --account "$OP_ACCOUNT"
    op whoami --account "$OP_ACCOUNT" >/dev/null

  op signin is idempotent and uses the 1Password desktop app when integration is enabled. If it reports that app integration is disabled, open 1Password, enable Settings → Developer → Integrate with 1Password CLI, then rerun exactly the same command. Do not use op account add, paste a secret key into the terminal, or store the returned session token.

- [ ] Step 3: Create the private evidence root only after the auth check passes.

    umask 077
    STAMP="$(date '+%Y%m%d-%H%M%S')"
    export EVIDENCE_DIR="$PWD/.build/vifty-recovery/one-shot-$STAMP"
    mkdir -p "$EVIDENCE_DIR"
    printf '%s\n' "onepassword=authorized" >"$EVIDENCE_DIR/authorization-status.txt"

  Keep `umask 077` for the evidence root, but do not leak it into Swift/Ruby fixture processes. The source-gate step below creates its log before entering a `umask 022` subshell, then restores mode `0600` after the command. This preserves private evidence without changing the fixture contract for simulated root-owned `0755` directories.

- [ ] Step 4: Set and record the run contract without recording secrets.

    export PUBLIC_ARCHIVE="$PWD/.build/vifty-recovery/Vifty-v1.4.5.zip"
    export PUBLIC_ARCHIVE_SHA256="13fa763cbfdca3e77fcf6f657df6d51b32e19a4d25dd17a79614635fe844b0d5"
    {
      date -u '+%Y-%m-%dT%H:%M:%SZ'
      git rev-parse HEAD
      printf '%s\n' "$PUBLIC_ARCHIVE_SHA256"
    } >"$EVIDENCE_DIR/run-contract.txt"

### Task 1: Capture a fresh read-only baseline and bind the dirty tree

**Files:**
- Create: $EVIDENCE_DIR/git-status.txt, $EVIDENCE_DIR/launchctl-before.txt, $EVIDENCE_DIR/btm-before.txt, $EVIDENCE_DIR/diagnose-before.json, $EVIDENCE_DIR/diagnose-before.exit, $EVIDENCE_DIR/app-before-codesign.txt, $EVIDENCE_DIR/disk-before.txt, $EVIDENCE_DIR/processes-before.txt
- Read only: /Applications/Vifty.app, /Applications/Vifty Recovery 14/Vifty.app, /Library/Application Support/ViftyMaintenanceEvidence/, /Users/reidar/Library/Application Support/Vifty/

**Interfaces:**
- Consumes: the run contract from Task 0.
- Produces: a timestamped pre-mutation snapshot and an explicit decision that the current state is still the known blocked state.

- [ ] Step 1: Enforce the expected source identity and free-space guardrail.

    test "$(git rev-parse HEAD)" = "e79bcab20ad7c9eda302fe4594bfa547b15f929a"
    git status --short -b >"$EVIDENCE_DIR/git-status.txt"
    git diff --stat >"$EVIDENCE_DIR/git-diff-stat.txt"
    git diff --check
    df -h /System/Volumes/Data | tee "$EVIDENCE_DIR/disk-before.txt"

  Stop if free space is below 30 GiB or if HEAD differs. Do not silently retarget the operation to a newer or different dirty tree.

- [ ] Step 2: Capture the selected app, duplicate app paths, daemon, BTM, and preserved evidence.

    find /Applications "$HOME/Applications" -maxdepth 3 -type d -name Vifty.app -print 2>/dev/null | sort >"$EVIDENCE_DIR/app-paths-before.txt"
    codesign -dvvv /Applications/Vifty.app >"$EVIDENCE_DIR/app-before-codesign.txt" 2>&1 || true
    launchctl print system/tech.reidar.vifty.daemon >"$EVIDENCE_DIR/launchctl-before.txt" 2>&1 || true
    sfltool dumpbtm >"$EVIDENCE_DIR/btm-before.txt" 2>&1 || true
    pgrep -alf '(^|/)(Vifty|ViftyDaemon|ViftyHelper|viftyctl)( |$)' >"$EVIDENCE_DIR/processes-before.txt" 2>&1 || true
    ls -lO \
      '/Library/Application Support/ViftyMaintenanceEvidence/replacement-state-v1.json' \
      '/Library/Application Support/ViftyMaintenanceEvidence/last-execution-v1.json' \
      '/Users/reidar/Library/Application Support/Vifty/manual-control-active' \
      >"$EVIDENCE_DIR/preserved-artifacts-before.txt" 2>&1 || true

- [ ] Step 3: Run read-only diagnosis and preserve its exit code.

    set +e
    /Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json \
      >"$EVIDENCE_DIR/diagnose-before.json" \
      2>"$EVIDENCE_DIR/diagnose-before.stderr"
    printf '%s\n' "$?" >"$EVIDENCE_DIR/diagnose-before.exit"
    set -e

  An exit 75 with state: blocked, recommendedRecoveryAction: repairHelper, or daemonControlPathReady: false is expected at this stage. It is a stop-before-cooling signal, not permission to invoke a fan command.

### Task 2: Prove the current source and exact public archive before any system mutation

**Files:**
- Read only: all inherited dirty source/test/script files and the exact archive.
- Create: $EVIDENCE_DIR/verify-full-hermetic.log, $EVIDENCE_DIR/public-release-summary.json, $EVIDENCE_DIR/public-release-verifier.log, $EVIDENCE_DIR/archive-sha256.txt

**Interfaces:**
- Consumes: current HEAD and the Task 1 evidence binding.
- Produces: a source gate and archive gate that authorize the later administrator boundary.

- [ ] Step 1: Verify the archive identity and release trust.

    stat -f '%N %z bytes' "$PUBLIC_ARCHIVE" >"$EVIDENCE_DIR/archive-stat.txt"
    shasum -a 256 "$PUBLIC_ARCHIVE" | tee "$EVIDENCE_DIR/archive-sha256.txt"
    test "$(awk '{print $1}' "$EVIDENCE_DIR/archive-sha256.txt")" = "$PUBLIC_ARCHIVE_SHA256"
    scripts/verify-release-artifact.sh \
      --artifact "$PUBLIC_ARCHIVE" \
      --release-version 1.4.5 \
      --team-id X88J3853S2 \
      --summary "$EVIDENCE_DIR/public-release-summary.json" \
      2>&1 | tee "$EVIDENCE_DIR/public-release-verifier.log"

  Expected: notarized Developer ID, Team ID X88J3853S2, stapling, Gatekeeper acceptance, exact content binding, and the pinned SHA all pass.

- [ ] Step 2: Run the full source gate with host Git signing isolated.

    : >"$EVIDENCE_DIR/verify-full-hermetic.log"
    chmod 600 "$EVIDENCE_DIR/verify-full-hermetic.log"
    (
      umask 022
      set -o pipefail
      GIT_CONFIG_GLOBAL=/dev/null \
      GIT_CONFIG_SYSTEM=/dev/null \
        make verify-full SWIFT_BUILD_PATH="$PWD/.build" \
        2>&1 | tee "$EVIDENCE_DIR/verify-full-hermetic.log"
    )
    chmod 600 "$EVIDENCE_DIR/verify-full-hermetic.log"

  Expected: exit 0, 2,037 XCTest cases passing, release bundle/codesign/plist/schema checks passing, and all Ruby trust, installer, helper-lifecycle, governance, and UI evidence suites passing. The empty Git config is a test-isolation boundary only; do not alter ~/.gitconfig.

- [ ] Step 3: Bind the green gate to the exact dirty tree.

    git rev-parse HEAD >"$EVIDENCE_DIR/verified-head.txt"
    git status --short >"$EVIDENCE_DIR/verified-status.txt"
    git diff --check

  If any source, script, test, or plan file changes after the gate, invalidate the gate and rerun it before the administrator boundary.

### Task 3: Safely transition the existing ad-hoc installation

**Files:**
- Use only: scripts/uninstall-vifty.sh, scripts/vifty-helper-lifecycle.sh, Makefile target uninstall-helper
- Preserve: /Applications/Vifty.app and its exact tree under $EVIDENCE_DIR/previous-install/
- Create: $EVIDENCE_DIR/uninstall-helper.log, $EVIDENCE_DIR/launchctl-after-uninstall.txt, $EVIDENCE_DIR/btm-after-uninstall.txt, $EVIDENCE_DIR/previous-app-content-manifest.txt

**Interfaces:**
- Consumes: the green source/archive gates.
- Produces: a verified helper-unregistered state and a reversible quarantine precondition for the strict public installer.

- [ ] Step 1: Capture the old app's content binding before moving it.

    mkdir -p "$EVIDENCE_DIR/previous-install"
    ruby scripts/release-candidate-inventory.rb public-tree-sha256 \
      --app /Applications/Vifty.app \
      >"$EVIDENCE_DIR/previous-app-content-manifest.txt"

  This is an inventory only; it does not establish trusted public-release provenance.

- [ ] Step 2: Use the reviewed helper-uninstall path and approve the native administrator prompt.

    set -o pipefail
    UNINSTALL_HELPER_APP=/Applications/Vifty.app \
      make uninstall-helper 2>&1 | tee "$EVIDENCE_DIR/uninstall-helper.log"

  Run this in the foreground only after Task 2 is green. The lifecycle script must produce its own fresh receipt/offline Auto proof, disable and verify the exact daemon label offline, and finish SMAppService unregistration. Type the password in the native macOS dialog immediately when it appears. Do not replace this with sudo, `sudo -v`, direct launchctl, raw lifecycle phase arguments, or an edited maintenance report.

  If the predecessor is an ad-hoc bundle and the reviewed lifecycle classifies it as unreachable before authorization, preserve that failed record and do not move the predecessor. Use the exact signed public recovery bundle at `/Users/reidar/Applications/Vifty Recovery 14/Vifty.app` only after independently confirming its Developer ID Team ID and the pinned public recovery-helper SHA (`4c467d99f7e59c2727f0e1a9b13de81772741d269b560ce6ca9fb605782f0d0f`), but invoke the current reviewed lifecycle so its explicit public-helper fallback is present: `UNINSTALL_HELPER_APP=/Users/reidar/Applications/Vifty Recovery 14/Vifty.app make uninstall-helper`. This is the reviewed offline recovery-helper path for the active public registration; it is not a raw phase invocation and must still reach the same native administrator boundary. Do not use an ad-hoc recovery bundle, a different Vifty app path, or a second retry after a 75/76 result.

- [ ] Step 3: Verify that helper authority is absent before moving the old app.

    launchctl print system/tech.reidar.vifty.daemon \
      >"$EVIDENCE_DIR/launchctl-after-uninstall.txt" 2>&1 || true
    sfltool dumpbtm >"$EVIDENCE_DIR/btm-after-uninstall.txt" 2>&1 || true
    test ! -e /Library/PrivilegedHelperTools/tech.reidar.vifty.helper
    test ! -e /Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
    ! launchctl print system/tech.reidar.vifty.daemon >/dev/null 2>&1

  If any authority is active or unknown, stop. Do not move the app, retry the lifecycle, or reset BTM. If the lifecycle reports HELPER_UNREACHABLE, continue only when the exact reviewed public v1.4.5 offline recovery path and fresh Auto evidence are present in its record.

- [ ] Step 4: Quarantine the old app reversibly, without deleting or copying it.

    QUARANTINE_APP="$EVIDENCE_DIR/previous-install/Vifty.app"
    test ! -e "$QUARANTINE_APP"
    mv /Applications/Vifty.app "$QUARANTINE_APP"
    test ! -e /Applications/Vifty.app
    test -d "$QUARANTINE_APP"
    ruby scripts/release-candidate-inventory.rb public-tree-sha256 \
      --app "$QUARANTINE_APP" \
      >"$EVIDENCE_DIR/quarantined-app-content-manifest.txt"
    cmp -s \
      "$EVIDENCE_DIR/previous-app-content-manifest.txt" \
      "$EVIDENCE_DIR/quarantined-app-content-manifest.txt"

  The mv is a same-volume, reversible quarantine of the exact prior bundle, not deletion or a second install. If permissions prevent this move, stop and ask the owner to perform the same exact-path move in Finder; never use sudo mv from the agent. Preserve the quarantine until final review.

- [ ] Step 5: Check duplicate BTM registrations without resetting them.

    sfltool dumpbtm >"$EVIDENCE_DIR/btm-after-quarantine.txt" 2>&1
    find /Applications "$HOME/Applications" -maxdepth 3 -type d -name Vifty.app -print 2>/dev/null | sort >"$EVIDENCE_DIR/app-paths-after-quarantine.txt"

  Preserve /Applications/Vifty Recovery 14/Vifty.app and any historical evidence bundle. If a duplicate registration is active rather than disabled/stale, use that exact app's native unregister/quit path and capture a new readback; never call sfltool resetbtm and never delete an unfamiliar bundle.

### Task 4: Install the exact public runtime through the reviewed transaction

**Files:**
- Use: Makefile target install-public-release, scripts/install-vifty.sh
- Preserve: $EVIDENCE_DIR/previous-install/Vifty.app and all installer receipts
- Create: $EVIDENCE_DIR/public-install.log, $EVIDENCE_DIR/selected-app-codesign.txt, $EVIDENCE_DIR/selected-daemon-codesign.txt

**Interfaces:**
- Consumes: absent canonical destination, no active helper authority, exact archive verification, and quarantined previous app.
- Produces: /Applications/Vifty.app containing the exact verified Developer ID archive, or a preserved stop state.

- [ ] Step 1: Recheck the destination precondition immediately before install.

    test ! -e /Applications/Vifty.app
    test ! -e /Library/PrivilegedHelperTools/tech.reidar.vifty.helper
    test ! -e /Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
    ! launchctl print system/tech.reidar.vifty.daemon >/dev/null 2>&1

- [ ] Step 2: Run the exact public installer once.

    set -o pipefail
    make install-public-release \
      PUBLIC_RELEASE_ARCHIVE="$PUBLIC_ARCHIVE" \
      2>&1 | tee "$EVIDENCE_DIR/public-install.log"

  Run this immediately after the successful Task 3 quarantine in the same foreground terminal session. No build is needed here: the archive is already pinned and verified. The reviewed public transaction owns its own replacement prepare/finish lifecycle and may show one or more native administrator dialogs; type the password directly into each Vifty dialog as soon as it appears. Do not use `sudo -v`, retry after exit 75/76, replay a root phase, manually edit a ledger, copy the app into place, or invoke a workflow/tag/release action. If the installer fails, preserve the quarantined app and transaction files and stop for owner recovery.

- [ ] Step 3: Verify the selected public bundle before helper repair.

    codesign -dvvv /Applications/Vifty.app >"$EVIDENCE_DIR/selected-app-codesign.txt" 2>&1
    codesign -dvvv /Applications/Vifty.app/Contents/MacOS/ViftyDaemon >"$EVIDENCE_DIR/selected-daemon-codesign.txt" 2>&1
    grep -Fqx 'TeamIdentifier=X88J3853S2' "$EVIDENCE_DIR/selected-app-codesign.txt"
    grep -Fqx 'TeamIdentifier=X88J3853S2' "$EVIDENCE_DIR/selected-daemon-codesign.txt"

### Task 5: Validate installer-managed helper registration; repair only on an explicit narrow exception

**Files:**
- Use: /Applications/Vifty.app and the public install transaction's lifecycle receipts
- Conditional use only: scripts/repair-vifty-helper.sh, Makefile target repair-helper
- Read only: launchd, BTM, unified logs, helper/daemon hashes
- Create: $EVIDENCE_DIR/repair-helper.log, $EVIDENCE_DIR/launchctl-after-repair.txt, $EVIDENCE_DIR/btm-after-repair.txt, $EVIDENCE_DIR/daemon-log-after-repair.txt

**Interfaces:**
- Consumes: the verified public bundle and the public install transaction's `finish` readback.
- Produces: proof that the installer registered one canonical daemon bound to the installed bundle. A separate repair is not part of the happy path.

- [ ] Step 1: Capture the installer-owned registration and process readback.

    launchctl print system/tech.reidar.vifty.daemon >"$EVIDENCE_DIR/launchctl-after-repair.txt" 2>&1
    sfltool dumpbtm >"$EVIDENCE_DIR/btm-after-repair.txt" 2>&1
    /usr/bin/log show --style compact --last 15m \
      --predicate 'process == "xpcproxy" OR process == "launchd" OR eventMessage CONTAINS[c] "tech.reidar.vifty.daemon"' \
      >"$EVIDENCE_DIR/daemon-log-after-repair.txt" 2>&1
    shasum -a 256 /Applications/Vifty.app/Contents/MacOS/ViftyDaemon >"$EVIDENCE_DIR/installed-daemon-sha256.txt"

  Pass only when the daemon is not spawn failed, has no last exit code = 78: EX_CONFIG, has no needs LWCR update, and the registered executable path resolves to /Applications/Vifty.app/Contents/MacOS/ViftyDaemon. The public install's successful finish receipt and these readbacks are the normal helper-repair proof.

- [ ] Step 2: Use the repair target only for the narrow post-install exception.

  Invoke the following exactly once only if the public installer exited `0`, helper authority is inactive rather than active/unknown, and the installer/readback evidence specifically says SMAppService registration did not reach enabled state:

    set -o pipefail
    REPAIR_HELPER_APP=/Applications/Vifty.app \
      make repair-helper 2>&1 | tee "$EVIDENCE_DIR/repair-helper.log"

  Approve the native administrator prompt immediately if it appears. If the installer exited 75/76, if authority is active/unknown, or if the failure is a duplicate/stale BTM registration, do not run this exception; preserve evidence and stop.

- [ ] Step 3: Stop on any registration ambiguity.

  If launchd shows a duplicate path, stale BTM authority, unknown active state, Team ID mismatch, or repeated crash, stop. Capture the readback and ask for one owner-authorized restart only if the app/lifecycle explicitly requires it; do not reset BTM or retry registration in a loop.

### Task 6: Prove daemon-backed Auto and readiness before any manual mode

**Files:**
- Use: /Applications/Vifty.app/Contents/MacOS/viftyctl diagnose, status, capabilities
- Use UI only for one Auto restoration if the app reports an active manual session
- Create: $EVIDENCE_DIR/diagnose-after-repair.json, $EVIDENCE_DIR/status-after-repair.json, $EVIDENCE_DIR/capabilities-after-repair.json, $EVIDENCE_DIR/auto-proof.json

**Interfaces:**
- Consumes: a responding public daemon and matching helper.
- Produces: diagnose --json exit 0, safeToRequestCooling=true, daemonControlPathReady=true, manualControlActive=false, empty cooling blockers, and fresh Auto/System ownership evidence.

- [ ] Step 1: Run the read-only readiness commands.

    /Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json \
      >"$EVIDENCE_DIR/diagnose-after-repair.json" \
      2>"$EVIDENCE_DIR/diagnose-after-repair.stderr"
    printf '%s\n' "$?" >"$EVIDENCE_DIR/diagnose-after-repair.exit"
    /Applications/Vifty.app/Contents/MacOS/viftyctl status --json >"$EVIDENCE_DIR/status-after-repair.json"
    /Applications/Vifty.app/Contents/MacOS/viftyctl capabilities --json >"$EVIDENCE_DIR/capabilities-after-repair.json"

  Require exit 0 and the structured fields above. Do not infer readiness from a successful process launch or a catalog listing.

- [ ] Step 2: Clear a manual marker only through the normal owner path.

  If manualControlActive is true, use the Vifty UI's Restore Auto action once, wait for a fresh daemon snapshot, and rerun diagnose --json. Do not call ViftyHelper auto or loop the restore command. If the marker persists, inspect the saved startup mode and ask the owner to select Auto; stop before manual smoke.

- [ ] Step 3: Save the Auto proof.

  Record the exact daemon snapshot/audit event, observed fan hardware modes, target telemetry, marker status, and timestamp in $EVIDENCE_DIR/auto-proof.json. The proof must show fresh OS/System ownership for every expected fan, not merely a local preference value.

### Task 7: Perform supervised Fixed/Curve/Auto acceptance only when readiness is green

**Files:**
- Use: /Applications/Vifty.app UI only
- Read only: daemon snapshots, receipts, audit events, thermal pressure, process state
- Create: $EVIDENCE_DIR/manual-smoke/ with one record per mode and a final Auto record

**Interfaces:**
- Consumes: Task 6 readiness and fresh fan IDs/ranges from the daemon.
- Produces: receipt-backed Fixed and Curve acceptance, followed by explicit Auto restoration, or a precise hardware non-claim.

- [ ] Step 1: Freeze the valid test inputs from fresh telemetry.

  Read fan IDs and ranges from the current daemon snapshot. Select conservative in-range values through the UI; do not invent IDs, write raw RPMs, or use a stale snapshot. Record the selected profile and values before applying.

- [ ] Step 2: Apply Fixed through the UI and validate the receipt.

  Use the UI's Fixed mode. Require a fresh transaction receipt, daemon readback for every selected fan, matching ownership, accepted/clamped target, and a corresponding audit event. A successful button return without readback is not acceptance.

- [ ] Step 3: Restore Auto through the UI and validate fresh OS/System readback.

  Use the UI's Auto action once. Require all fans to report automatic/system ownership, a fresh readback timestamp, no manual marker, and a successful audit entry. If Auto restoration fails, stop and preserve the receipt; do not proceed to Curve.

- [ ] Step 4: Apply Curve through the UI and validate the receipt.

  Use one bounded Curve profile whose points are already in the saved profile or selected through the UI. Require the same fresh receipt/readback/audit conditions as Fixed. Do not claim learner/profile quality from source tests alone.

- [ ] Step 5: Restore Auto a final time and close the smoke session.

  Require a final Auto proof and rerun diagnose --json. If any hardware write is rejected, classify the exact receipt-backed cause and stop; do not patch around it or repeat the same workload.

  This task is inherently supervised because it exercises real fan control. The operator may go AFK only after this task is either completed with final Auto proof or explicitly skipped and recorded as unverified.

### Task 8: Close the transaction and leave an auditable handoff

**Files:**
- Create/update: docs/reviews/2026-09-12-vifty-one-shot-recovery.md
- Create: $EVIDENCE_DIR/final-preservation-check.txt, $EVIDENCE_DIR/manifest.tsv, $EVIDENCE_DIR/review-summary.json
- Preserve: quarantined previous app and all root replacement receipts

**Interfaces:**
- Consumes: all phase evidence and final runtime state.
- Produces: a truthful completion report with verified claims and explicit non-claims.

- [ ] Step 1: Recheck source and workspace preservation.

    git diff --check
    git status --short -b
    df -h /System/Volumes/Data
    find /private/tmp -maxdepth 1 -type d \( -name 'Vifty*' -o -name 'vifty*' \) -print -exec du -sh {} \; 2>/dev/null || true

  Do not clean .build, prior evidence, the quarantined app, credentials, wallets, or unrelated temporary paths.

- [ ] Step 2: Verify final runtime identity read-only.

    codesign -dvvv /Applications/Vifty.app >"$EVIDENCE_DIR/final-app-codesign.txt" 2>&1
    launchctl print system/tech.reidar.vifty.daemon >"$EVIDENCE_DIR/final-launchctl.txt" 2>&1
    sfltool dumpbtm >"$EVIDENCE_DIR/final-btm.txt" 2>&1
    /Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json >"$EVIDENCE_DIR/final-diagnose.json" 2>"$EVIDENCE_DIR/final-diagnose.stderr"
    printf '%s\n' "$?" >"$EVIDENCE_DIR/final-diagnose.exit"

- [ ] Step 3: Write the final review and Obsidian log.

  The review must distinguish source verification, public archive verification, installation, helper/daemon registration, Auto proof, Fixed/Curve receipts, and hardware acceptance. It must not transfer proof from the ad-hoc predecessor, prior releases, source tests, or catalog metadata into the installed public-runtime claim.

## Stop-condition matrix

| Failure | Immediate action | Forbidden response |
|---|---|---|
| op signin fails | Stop before source/system work; ask the owner to enable desktop integration or authorize the prompt | Read vault secrets, paste a secret key, log a session token |
| Free space below 30 GiB | Stop and report | Start builds or cleanup unrelated data |
| HEAD/tree differs from the bound run | Stop and bind a new plan/run | Silently continue on a new dirty tree |
| Source gate fails | Preserve test log and debug source-only | Install, repair helper, or modify hardware state |
| Archive SHA/signing/Gatekeeper fails | Stop before installation | Accept a different archive or skip checks |
| Existing helper authority active/unknown | Stop before quarantine | Reset BTM, raw launchctl, replay lifecycle phases |
| Helper uninstall cancellation | Preserve receipt and exact state | Retry blindly or remove files manually |
| Duplicate active BTM registration | Stop and use the native exact-app unregister path | sfltool resetbtm |
| Public installer exits 75/76 | Preserve transaction and quarantine | Retry, edit ledger, copy bundle manually |
| Diagnose remains blocked | Stop before fan writes | prepare, ViftyHelper, or uncooled fallback |
| Fixed/Curve receipt/readback fails | Restore Auto once if safe, preserve evidence, stop | Repeat the same write or patch speculatively |
| Auto restoration fails | Keep hardware claim unverified and stop | Proceed to the next mode |

## AFK choreography

1. The first command is op signin; the only expected immediate user action is the 1Password desktop authorization.
2. The long source/archive gate then runs without system mutation and without 1Password-backed Git signing.
3. Before the helper transition, the operator must be present for the native administrator prompt. The lifecycle receipt is short-lived, so it cannot be authorized and left waiting for a long build.
4. Helper teardown and public install run as one prepared foreground transition. macOS may show multiple administrator/Login Items prompts across the reviewed lifecycle's prepare/finish boundaries; approve only the Vifty prompt and remain until the prompt burst ends. The happy path does not run a redundant post-install repair.
5. After Task 5/6 has produced healthy Auto proof, the non-hardware portion can run AFK. Fixed/Curve acceptance remains supervised by design.

## Definition of done

- Exact v1.4.5 archive SHA, Developer ID, Team ID, notarization, stapling, Gatekeeper, and content binding pass.
- /Applications/Vifty.app is the selected canonical signed bundle; the quarantined ad-hoc predecessor remains preserved and recorded.
- The helper and daemon are registered once, launchd has no LWCR/EX_CONFIG failure, the installed daemon hash matches the selected bundle, and BTM has no active duplicate ambiguity.
- diagnose --json exits 0 with safeToRequestCooling=true, daemonControlPathReady=true, manualControlActive=false, and no blockers.
- Auto proof is fresh and receipt-backed. Fixed/Curve are claimed only if their supervised receipts, daemon readbacks, audit entries, and final Auto restoration pass.
- Evidence, review, and Obsidian logging are complete; the dirty branch is preserved and no release/merge/deploy occurred.
