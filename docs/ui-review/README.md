# Hardware-free native UI review

Vifty's review fixture exists only in debug builds. It injects inert hardware, daemon, power, notification, Login Item, profile, preference, and helper dependencies before `AppModel` is created. It skips `model.start()`, production commands, the production status item, activation polling, and termination restore. Any attempted fan command, external mutation, or real control-path construction makes the final report fail.

The fixture renders the real app views in their real containers:

- main rows use the production SwiftUI `Window` at an exact requested point size;
- Settings rows use the production `Settings` scene at exactly `600x420` content points;
- the menu row uses a debug-owned real `NSPopover` anchored to a disposable status item at exactly 320 points wide and a positive native height.

Accessibility-text requests use Vifty's production text-size preference and environment, not a synthetic macOS Dynamic Type override. The persisted choices are Standard (`1.0`), Large (`1.2`), and Accessibility (`1.5`). Vifty scales semantic text while preserving the native AppKit font descriptors, and the fixture injects the same production environment that the app uses.

The DEBUG-only PNG path invokes the fixed, root-owned `/usr/sbin/screencapture` tool for the exact observed `NSWindow.windowNumber`, excludes shadows, and crops the compositor result to `contentLayoutRect` before hashing it. This preserves native SwiftUI materials that AppKit view-cache rendering cannot reproduce. The app removes the transient full-window file on normal and thrown paths; after a forced outer timeout, the orchestrator terminates and reaps the fixture process group, then removes only exact regular non-symlink `window-capture-<UUID>.png` files inside that fixture directory. The invoking terminal or Codex host needs macOS Screen Recording permission; the workflow never prompts for or changes that permission, and it cannot choose a different window or an interactive region. The separate `ViftyAXCollector` uses public read-only macOS Accessibility APIs, never prompts for permission, never performs Accessibility actions, and is not bundled in `Vifty.app`.

## Build without launching

```bash
df -h /System/Volumes/Data
make ui-review-build-products
```

Stop if `/System/Volumes/Data` has less than 30 GiB free. The transaction refuses a dirty repository before creating output, archives one exact `HEAD` commit/tree into a bounded read-only source snapshot, and builds all three products from that snapshot. Each Mach-O carries one canonical `__TEXT,__vifty_src` identity with the same source commit, source tree, and build-transaction ID plus its exact role/configuration. Products are published together only after the embedded identities validate:

- `.build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty` — `debug-fixture-app` / `debug`
- `.build/ui-review-products/release/Vifty` — `release-exclusion` / `release`
- `.build/ui-review-products/debug/ViftyAXCollector` — `ax-collector` / `debug`

Do not substitute ordinary `.build` products or a mutable sidecar. Capture reports, raw/sealed AX artifacts, the verifier, and the portable checkpoint all bind these embedded identities.

## Local capture ledger and portable checkpoint

The committed [evidence-manifest.json](evidence-manifest.json) is an empty, pending request template. It deliberately contains no capture IDs, executable paths, process IDs, window numbers, host paths, or completed human attestations. Never seal runtime evidence into that tracked template.

Initialize the ignored machine-local ledger once, then use it for every capture, seal, and verification command:

```bash
test -e "$PWD/docs/ui-review/evidence-manifest.local.json" || \
  cp "$PWD/docs/ui-review/evidence-manifest.json" \
     "$PWD/docs/ui-review/evidence-manifest.local.json"
```

The full capture tree remains below ignored `.build/ui-review-evidence/`. After a fresh exact-binary local ledger passes `--verify-automated`, write the small tracked checkpoint with:

```bash
UI_REVIEW_SOURCE_COMMIT="$(git rev-parse HEAD)" make ui-review-write-checkpoint
```

The writer requires the exact Git repository root, binds the supplied source commit to `HEAD`, and rejects every source-affecting worktree change. Only the canonical checkpoint output and tracked `docs/images/vifty-screenshot.png` may be locally changed; ignored local evidence remains outside Git status. It reruns the existing automated verifier with the exact AX collector, snapshots every manifest/product/report/PNG/raw/sealed input before verification, and refuses publication if any identity or hash changes afterward. Its strict schema requires exactly 50 canonically ordered, path-free rows (9 fixture, 28 visual, and 13 Accessibility), SHA-256 capture-ID projections, manifest and product hashes, final zero-mutation aggregates, and a byte-exact `main-1180x820-light` canonical hero binding. It never copies a raw capture ID, reviewer identity, or human attestation from the local ledger. Visual review remains pending with prior evidence marked superseded; VoiceOver remains pending with the owner's `skipped-by-owner` decision and no speech, focus, rotor, grouping, traversal, pronunciation, or announcement claim.

No [automated-checkpoint.json](automated-checkpoint.json) is valid or committed until a new exact-binary 50-row recapture passes. The checkpoint is a portable integrity summary, not the full evidence bundle, hardware compatibility proof, or release-readiness proof.

## Explicit capture modes

Every mode requires explicit trusted paths. `--capture` chooses a verifier-owned row, creates the capture ID before launch, launches the bundle executable directly, retains its exact PID, and waits with bounded deadlines for `ready` and `final` reports. `--timeout-seconds` is the per-operation timeout and, for AX collection, the collector's per-message AX timeout (maximum 10 seconds). `--fixture-hold-seconds` is the separate inert fixture lifetime (30–300 seconds). `--collector-wall-timeout-seconds` bounds the complete traversal subprocess; the orchestrator refuses collection unless the retained fixture deadline has enough time for that wall bound plus finalization.

Capture and seal a visual row:

```bash
capture_json="$(scripts/run-ui-review-fixture.sh \
  --capture \
  --row-kind visual \
  --row-id main-1180x820-light \
  --manifest "$PWD/docs/ui-review/evidence-manifest.local.json" \
  --evidence-dir "$PWD/.build/ui-review-evidence" \
  --debug-executable "$PWD/.build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty" \
  --timeout-seconds 5 \
  --fixture-hold-seconds 120)"

capture_id="$(printf '%s' "$capture_json" | /usr/bin/ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("captureID")')"

scripts/run-ui-review-fixture.sh \
  --seal \
  --capture-id "$capture_id" \
  --manifest "$PWD/docs/ui-review/evidence-manifest.local.json" \
  --evidence-dir "$PWD/.build/ui-review-evidence" \
  --debug-executable "$PWD/.build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty"
```

Visual review remains post-seal: inspect and attest only the immutable PNG and hashes produced by the completed visual capture, never the transient live fixture.

Accessibility rows remain alive at `ready` only until collection completes. Perform the human VoiceOver observation while that exact fixture remains at `ready`; `collect-ax` sends the completion signal and ends the live fixture, so observations made after collection do not belong to that capture. Use the maximum 300-second hold, begin the row-specific human observation immediately, and repeat this live sequence for every exact AX capture. After the observation and immediately before `collect-ax`, verify that more than 40 seconds remain before the fixture deadline. If not, abandon that unsealed capture and start a fresh one; never promote or attest a timed-out or different fixture.

Collect and seal each observed row with the exact non-bundled collector:

```bash
capture_json="$(scripts/run-ui-review-fixture.sh \
  --capture \
  --row-kind accessibility \
  --row-id confirmed-owner-headline \
  --manifest "$PWD/docs/ui-review/evidence-manifest.local.json" \
  --evidence-dir "$PWD/.build/ui-review-evidence" \
  --debug-executable "$PWD/.build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty" \
  --timeout-seconds 5 \
  --fixture-hold-seconds 300)"

capture_id="$(printf '%s' "$capture_json" | /usr/bin/ruby -rjson -e 'print JSON.parse(STDIN.read).fetch("captureID")')"

# HUMAN STEP: with this exact capture still at ready, perform only the
# VoiceOver steps whose authoritative row subsets contain this row ID.

remaining_seconds="$(printf '%s' "$capture_json" | /usr/bin/ruby -rjson -e 'print((JSON.parse(STDIN.read).fetch("fixtureDeadlineEpochSeconds") - Time.now.to_f).floor)')"
if (( remaining_seconds <= 40 )); then
  echo "VoiceOver capture has insufficient hold time; start a fresh capture." >&2
  exit 1
fi

scripts/run-ui-review-fixture.sh \
  --collect-ax \
  --capture-id "$capture_id" \
  --manifest "$PWD/docs/ui-review/evidence-manifest.local.json" \
  --evidence-dir "$PWD/.build/ui-review-evidence" \
  --debug-executable "$PWD/.build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty" \
  --collector-executable "$PWD/.build/ui-review-products/debug/ViftyAXCollector" \
  --timeout-seconds 5 \
  --collector-wall-timeout-seconds 30 \
  --maximum-nodes 2048 \
  --maximum-depth 32

scripts/run-ui-review-fixture.sh \
  --seal \
  --capture-id "$capture_id" \
  --manifest "$PWD/docs/ui-review/evidence-manifest.local.json" \
  --evidence-dir "$PWD/.build/ui-review-evidence" \
  --debug-executable "$PWD/.build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty" \
  --collector-executable "$PWD/.build/ui-review-products/debug/ViftyAXCollector"
```

If Accessibility permission is absent, collection returns `exit 77` and preserves the structured `AX_PERMISSION_MISSING` result with `promptRequested: false`, the process log, the ready report, raw failure artifact, completion signal, and final fixture report. Grant permission manually in System Settings, then start a fresh capture; the workflow never changes trust settings itself.

Missing Screen Recording access, timeout, early exit, PID/executable replacement, unsafe final reports, invalid PNGs, collector failures, and seal failures also preserve their structured capture directory and exit nonzero. Never promote a prepared- or ready-only report.

## System settings and autonomous status

Increase Contrast and Reduce Transparency are observed read-only from the SwiftUI environment. The orchestrator never changes either setting. All standard fixture, visual, and AX rows require both settings to be off; they fail closed on an environment mismatch instead of silently producing mislabeled evidence. Capture those standard rows while both settings are off. The dedicated Reduce Transparency row requires standard contrast plus reduced transparency. The dedicated Increase Contrast row requires increased contrast plus reduced transparency because macOS automatically reduces transparency when Increase Contrast is enabled. `--verify-automated` permits only `main-increase-contrast` and `main-reduce-transparency` to remain pending and unbound after every standard automated row has passed. The top-level manifest remains `pending`, and the command reports autonomous-subset success out-of-band:

```bash
scripts/run-ui-review-fixture.sh \
  --verify-automated \
  --manifest "$PWD/docs/ui-review/evidence-manifest.local.json" \
  --evidence-dir "$PWD/.build/ui-review-evidence" \
  --debug-executable "$PWD/.build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty" \
  --release-binary "$PWD/.build/ui-review-products/release/Vifty" \
  --collector-executable "$PWD/.build/ui-review-products/debug/ViftyAXCollector"
```

The verifier binds canonical requests, direct executable SHA/PID/window identity, final safety reports, native geometry, decoded canonical PNG pixels, raw and sealed AX hashes, the read-only action record, and release-marker exclusion. Duplicate, transparent, solid, malformed, escaped, symlinked, orphaned, or tampered evidence fails closed.

### Current evidence state — recapture required

The remediation source changed after the last 50-row capture and seven-batch visual review. Those executable-bound rows and every prior visual result are historical and superseded; none transfers to the current source. The committed manifest is therefore reset to the empty pending template, and no portable automated checkpoint exists yet.

The next valid checkpoint requires a new build, a fresh local 50-row ledger, an automated-verifier pass, and a path-free `automated-checkpoint.json` bound to that source commit and product hashes. Until that happens, do not describe the current source as having passed automated UI evidence, visual review, or VoiceOver review. The owner chose to skip VoiceOver, so that gate remains pending with no human VoiceOver claims.

The ignored `evidence-manifest.local.json` may retain the last ledger for local forensic reference. Its absolute paths, PIDs, window numbers, capture artifacts, and human bindings are deliberately excluded from version control and must not be presented as current evidence.

The owner has restored both Reduce Transparency and Increase Contrast to off. That is only the current host setting state and the precondition for standard rows; it does not validate or revive any superseded capture.

## Human visual and VoiceOver handoff

No current exact-binary human visual handoff is complete. The prior seven visual batches are superseded by source changes. The owner deliberately skipped VoiceOver, so that binding and the top-level manifest status remain pending. Do not fabricate or infer either human attestation from screenshots or automated AX evidence. If a future owner reopens VoiceOver review, use only fresh exact capture bindings: observe each AX row during its live 300-second `ready` hold, require more than 40 seconds before collection, then run `collect-ax` and seal that same capture. Never reuse superseded capture IDs or transfer an earlier human result to a changed executable.

Automated AX hierarchy evidence is not a VoiceOver session. It cannot prove speech, pronunciation, focus navigation, rotor behavior, grouping, or announcements. Likewise, screenshots do not constitute human visual approval.

Use [visual-attestation-template.json](visual-attestation-template.json) only for a human method exactly named `visual-inspection`. Review every visual row for clipping, overlap, legibility, hierarchy, and transient-state correctness. Use [voiceover-attestation-template.json](voiceover-attestation-template.json) only for a human method exactly named `voiceover-session`; follow all seven scripted steps and record what VoiceOver actually does. Do not describe raw AX hierarchy order as VoiceOver traversal order.

For the VoiceOver session, keep the seven steps in template order and use their prefilled row subsets exactly:

| Step | Exact AX rows | Required human observation |
|---|---|---|
| `spoken-labels-values` | `confirmed-owner-headline`, `correct-per-fan-target`, `explicit-temperature-role`, `no-duplicate-chart-elements`, `notification-actions`, `sensor-selected-trait-value`, `settings-logical-traversal`, `six-adjustable-point-controls` | Record the labels, roles, states, and values VoiceOver actually speaks. |
| `focus-movement` | `no-duplicate-chart-elements`, `notification-actions`, `sensor-selected-trait-value`, `settings-logical-traversal`, `six-adjustable-point-controls` | Record the observed focus sequence; do not substitute AX-tree order. |
| `rotor-grouping` | `confirmed-owner-headline`, `no-duplicate-chart-elements`, `settings-logical-traversal` | Record the rotor and group boundaries exposed by VoiceOver. |
| `adjustable-controls` | `six-adjustable-point-controls` | Treat all six curve points as inspect and announce only. Do not invoke the six curve-point adjustables. |
| `buttons` | `notification-actions`, `sensor-selected-trait-value`, `settings-logical-traversal` | Confirm names, roles, states, and help without activating a button. Do not activate notification actions or sensor buttons in this step. |
| `scroll-reachability` | `compact-main-scroll-reachable`, `settings-agent-workflows-scroll-reachable`, `settings-general-scroll-reachable`, `settings-menu-bar-scroll-reachable`, `settings-notifications-scroll-reachable` | Record the exact end anchor reached on every bound surface at Accessibility text size. |
| `safe-action-announcements` | `settings-logical-traversal` | The complete allowlist is `General -> Menu Bar -> Notifications -> Agent Workflows -> General`. Activate only those in-app Settings section buttons and record every resulting announcement. |

No other activation is authorized by this evidence session. In particular, do not invoke Apply, Restore Auto, helper install/approve/repair/reinstall, notification actions, sensor buttons, curve-point adjustables, fan controls, clipboard actions, or external Settings links. Scrolling and VoiceOver navigation are permitted; they are not evidence of a control activation.

The VoiceOver attestation records this policy structurally. `actionSequence` must equal `settings-general`, `settings-menu-bar`, `settings-notifications`, `settings-agent-workflows`, `settings-general` in that order. `inspectOnlyControlGroups` must equal `curve-point-adjustables`, `notification-actions`, `sensor-buttons`; none may be activated. `disallowedActionsPerformed` must remain an empty array. Missing, reordered, additional, or contradictory action records fail matrix verification.

For each template:

1. Copy it to the manifest-declared path below the evidence directory. Copy the VoiceOver template before the first live AX capture so observations are recorded during each exact `ready` hold; copy or complete the visual template only against already sealed PNGs.
2. Replace `REPLACE_WITH_REVIEWER_NAME` and the `1970-01-01T00:00:00Z` sentinel with the actual reviewer and ISO-8601 session time. The verifier rejects both untouched sentinels.
3. Bind the exact covered row IDs and capture IDs plus request, executable, and final-report hashes; bind both the PNG binary and canonical-pixel hashes for visual rows, and both the raw-capture and sealed-report hashes for AX rows.
4. Replace every `REPLACE_WITH_OBSERVED_RESULT:` instruction with a specific human-observed result. Generic completion copy is not evidence. Mark every required scripted step and the overall result `passed` only after the human session succeeds.
5. Compute the attestation file SHA-256, set its manifest binding to `passed`, and keep the artifact immutable.

Only after both attestations pass, the two system-setting captures are sealed, every automated row passes, and the manifest status is explicitly changed to `passed`, run:

```bash
scripts/run-ui-review-fixture.sh \
  --verify-matrix \
  --manifest "$PWD/docs/ui-review/evidence-manifest.local.json" \
  --evidence-dir "$PWD/.build/ui-review-evidence" \
  --debug-executable "$PWD/.build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty" \
  --release-binary "$PWD/.build/ui-review-products/release/Vifty" \
  --collector-executable "$PWD/.build/ui-review-products/debug/ViftyAXCollector"
```

The attestation structure is defined by [ui-review-attestation-v1.schema.json](../schemas/ui-review-attestation-v1.schema.json). Wrong methods, missing or placeholder reviewers, malformed or placeholder times, generic/template observations, incomplete or over-broad step rows, stale hashes, AX substituted for VoiceOver, and missing/tampered files fail full-matrix verification.

This is UI evidence only. It never proves hardware compatibility, helper repair or installation, manual fan writes, agent cooling, or successful Auto restoration.
