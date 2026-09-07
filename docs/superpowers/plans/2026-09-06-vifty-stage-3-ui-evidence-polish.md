# Vifty Stage 3 UI Evidence and Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore exact-source UI capture readiness, complete the declared evidence matrix, and apply only current-evidence-backed polish.

**Architecture:** Fix the existing SwiftUI/AppKit observation bridge at its root, retain the current 50-row provenance-bound harness, and keep visual changes downstream of accepted captures. Use native SwiftUI and existing tests; add no snapshot framework.

**Tech Stack:** SwiftUI, AppKit, XCTest, Ruby orchestration, macOS Accessibility APIs, existing UI evidence schemas and Make targets.

**Spec:** `docs/superpowers/specs/2026-09-06-vifty-audit-remediation-design.md`

## Global Constraints

- Stages 1 and 2 must be approved and green.
- Standard captures require at least 30 GiB free and a clean exact Git tree.
- Preserve `modelStartSkipped=true`, inert dependencies, and zero hardware/helper mutations.
- Historical checkpoint `6ac429cbacf7cc3358c74493ab7461a43fa40275` is not current evidence.
- Human visual and VoiceOver claims require actual current observations; automated AX is not VoiceOver evidence.

---

### Task 1: Make the observation bridge reliably schedule readiness

**Files:**
- Modify: `Sources/Vifty/ViftyReviewFixture.swift`
- Test: `Tests/ViftyCoreTests/ViftyReviewFixtureTests.swift`
- Test: `Tests/ViftyCoreTests/UIReviewEvidenceScriptTests.swift`

**Interfaces:**
- Produces: observation scheduling from both `makeNSView` and later updates, still requiring two stable samples.

- [ ] **Step 1: Add a hosted-window regression**

Create an `NSWindow` with an `NSHostingView` containing `ViftyReviewFixtureSceneHost`, order it front, and wait for `runtime.hasReadyObservation`. Do not call `recordObservation` directly. Assert the ready report appears before the test deadline and records no mutations.

- [ ] **Step 2: Run the regression against current source**

Run: `swift test --scratch-path "$PWD/.build" --filter ViftyReviewFixtureTests/testHostedSceneSchedulesObservationAfterPreparation`

Expected: timeout because a newly created observation representable is not guaranteed an update callback after insertion.

If this test reaches ready on unchanged source, do not apply Step 3. Preserve that evidence, rerun the exact product capture once in the same interactive WindowServer session, and compare lifecycle timing. A non-reproducing unit/hosted test means the current timeout is environmental or occurs outside this bridge; revise this task from observed evidence before editing production fixture code.

- [ ] **Step 3: Schedule from creation as well as update**

```swift
func makeNSView(context: Context) -> ViftyReviewFixtureWindowObserverView {
    let view = ViftyReviewFixtureWindowObserverView(frame: .zero)
    configure(view)
    view.scheduleObservationPair()
    return view
}
```

Keep `viewDidMoveToWindow`, `layout`, the update call, and `observationPairScheduled`; nil-window emissions remain harmless and later lifecycle callbacks reschedule.

- [ ] **Step 4: Run Swift and orchestrator regression tests**

Run: `swift test --scratch-path "$PWD/.build" --filter 'ViftyReviewFixtureTests|UIReviewEvidenceScriptTests'`

Expected: PASS, including structured timeout behavior for intentionally non-ready fixtures.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vifty/ViftyReviewFixture.swift Tests/ViftyCoreTests/ViftyReviewFixtureTests.swift Tests/ViftyCoreTests/UIReviewEvidenceScriptTests.swift
git commit -m "fix: schedule UI fixture observation on creation"
```

### Task 2: Prove one real exact-source capture before matrix work

**Files:**
- Generated ignored evidence only under `.build/ui-review-evidence/`.
- Do not modify the committed manifest in this task.

- [ ] **Step 1: Verify disk, clean tree, and host settings**

Run: `df -h /System/Volumes/Data && test -z "$(git status --porcelain --untracked-files=all)"`

Expected: at least 30 GiB free and clean tree. Standard rows require Increase Contrast and Reduce Transparency off; inspect them manually/read-only per `docs/ui-review/README.md`.

- [ ] **Step 2: Build exact products and initialize the local ledger**

Run: `make ui-review-start-session`

Expected: one provenance-bound debug app, release exclusion binary, AX collector, and ignored local ledger for current `HEAD`.

- [ ] **Step 3: Capture the previously failing row**

Run the documented `--capture --row-kind visual --row-id main-1180x820-light` command with five-second readiness and 120-second hold, then seal its returned capture ID.

Expected: capture and seal exit 0; final fixture report has `phase: final`, `passed: true`, `modelStartSkipped: true`, and empty mutation arrays.

- [ ] **Step 4: Inspect the immutable PNG**

Open the sealed screenshot, confirm it is the requested Vifty window rather than transparent/solid/launcher content, and record any visual defect separately. Do not patch UI in this task.

- [ ] **Step 5: Commit only a checkpoint note if source documentation requires it**

Normally make no commit: ignored evidence is the deliverable. If a source change was required after Task 1, return to Task 1 and repeat its red/green cycle instead of committing an unreviewed capture workaround.

### Task 3: Recapture and verify the automated 50-row matrix

**Files:**
- Generated: ignored `.build/ui-review-evidence/**`
- Generated: ignored `docs/ui-review/evidence-manifest.local.json`
- Modify after automated pass only: `docs/ui-review/automated-checkpoint.json`
- Modify after automated pass only: `docs/images/vifty-screenshot.png`

**Interfaces:**
- Consumes: nine fixture, 28 visual, and 13 AX requests from `scripts/lib/ui_review_contract.rb`.
- Produces: exact-current-source automated checkpoint and canonical hero.

- [ ] **Step 1: Capture the nine fixture rows**

Use the documented capture and seal commands for every exact state emitted by:

```bash
jq -r '.fixtureReports[].state' docs/ui-review/evidence-manifest.json
```

For each emitted value, pass it unchanged to `--row-id`, extract `captureID` from the returned JSON with `/usr/bin/ruby -rjson`, and pass that exact ID to `--seal`. Stop on the first nonzero capture or seal result.

- [ ] **Step 2: Capture the standard visual rows**

Capture and seal every standard light/dark, size, state, Settings, popover, and accessibility-text row listed by `jq -r '.visualCells[].id'`. Keep the two system-setting rows pending until their settings are explicitly arranged.

- [ ] **Step 3: Capture and collect automated AX rows**

For each `jq -r '.accessibilityChecks[].id'` row, launch with a 300-second hold, run `--collect-ax` with the exact collector, and seal. Do not activate inspect-only controls.

- [ ] **Step 4: Capture the two explicit system-setting rows**

With owner-controlled settings, capture Reduce Transparency under standard contrast, then Increase Contrast with macOS-implied reduced transparency. Restore the owner's preferred settings afterward and record only observed readback.

- [ ] **Step 5: Verify automated evidence**

Run: `make ui-review-verify-automated`

Expected: 9/9 fixture, 28/28 visual, and 13/13 AX rows pass with zero mutation aggregates.

- [ ] **Step 6: Publish the portable checkpoint**

Run: `UI_REVIEW_SOURCE_COMMIT="$(git rev-parse HEAD)" make ui-review-write-checkpoint`

Expected: path-free checkpoint bound to current source/products and canonical hero.

- [ ] **Step 7: Commit checkpoint artifacts**

```bash
git add docs/ui-review/automated-checkpoint.json docs/images/vifty-screenshot.png
git commit -m "docs: refresh current Vifty UI evidence checkpoint"
```

### Task 4: Conduct human review and create file-specific fix plans

**Files:**
- Update: `/Users/reidar/Obsidian/Hermes/Hermes/Personal/Projects/Vifty/Vifty.md`
- Create when findings exist: one dated design/implementation-plan pair per coherent validated UI problem.
- Generated: visual and VoiceOver attestations when actually completed.

**Interfaces:**
- Produces: a ranked finding ledger containing row ID, capture ID, observed defect, expected behavior, owning file, and acceptance check.
- Produces: concrete file-specific plans before any UI production edit.

- [ ] **Step 1: Review every sealed visual row**

Check clipping, overlap, truncation, contrast, hierarchy, spacing, state truth, and compact-scroll reachability. Record “no issue” or one concrete finding per row; do not infer defects from source alone.

- [ ] **Step 2: Perform the VoiceOver session if the owner authorizes it**

Use the exact seven scripted steps and row subsets in `docs/ui-review/README.md`. If not authorized, preserve `skipped-by-owner` and make no VoiceOver claim.

- [ ] **Step 3: Write the durable current-review ledger**

In the Vifty Obsidian project note, record all 28 visual rows and 13 AX rows with exact row ID, capture ID, disposition (`no-issue` or `validated-finding`), observation, and evidence hash. For every validated finding also record severity, owning source path, focused test path, and affected recapture row IDs. Do not write production code or tracked repository documentation in this step, because either would invalidate the exact-source capture set.

- [ ] **Step 4: Verify the review did not invalidate source provenance**

```bash
test -z "$(git status --porcelain --untracked-files=all)"
make ui-review-verify-automated
```

- [ ] **Step 5: Create concrete follow-on plans for validated findings**

If the ledger contains no validated finding, record that Stage 3 needs no UI production edit. Otherwise, group only findings that share one owning presentation/layout path, run the brainstorming approval gate, and create dated file-specific plans under `docs/superpowers/plans/`. Each follow-on plan names exact Swift files, exact focused tests, exact failing assertion, exact affected capture rows, and its commit message before implementation begins.

- [ ] **Step 6: Execute approved follow-on plans and recapture affected rows**

Each approved fix must pass its red/green test and replace every stale affected capture. Re-run `make ui-review-verify-automated`; update human visual bindings only after inspecting the new immutable PNG. Do not proceed on an unapproved or non-file-specific fix plan.

### Task 5: Reduce harness duplication only after stability

**Files:**
- Modify if duplication is proven: `Tests/ViftyCoreTests/UIReviewEvidenceScriptTests.swift`
- Modify if duplication is proven: `scripts/lib/ui_review_contract.rb`
- Do not modify: verifier safety, provenance, sealing, schemas, or path-containment code.

- [ ] **Step 1: Count repeated request/expectation blocks**

Run: `rg -n 'main-1180x820|settings-general|accessibility-text' Tests/ViftyCoreTests/UIReviewEvidenceScriptTests.swift scripts/lib/ui_review_contract.rb`

Identify only byte-structurally repeated cases already represented by the canonical request table.

- [ ] **Step 2: Add one parameterized test loop alongside existing cases**

Keep the old cases temporarily, run the new loop, and prove identical row IDs and expected request dictionaries.

- [ ] **Step 3: Delete only superseded duplicated cases**

Run `git diff --stat` and require net line deletion. Keep explicit adversarial security/path/provenance tests separate.

- [ ] **Step 4: Run all UI evidence suites**

Run: `swift test --scratch-path "$PWD/.build" --filter UIReviewEvidenceScriptTests && make ui-review-ruby-tests`

Expected: identical required matrix coverage and all tests pass.

- [ ] **Step 5: Commit only if the result is smaller**

```bash
git add Tests/ViftyCoreTests/UIReviewEvidenceScriptTests.swift scripts/lib/ui_review_contract.rb
git commit -m "test: deduplicate UI evidence matrix cases"
```

Skip this commit entirely if the change is not a net deletion or weakens explicit adversarial coverage.

If this task creates a commit, its new source tree invalidates the existing products and capture ledger. Repeat Tasks 2 through 4 against the new exact `HEAD` before entering Task 6. If no net-deletion commit is justified, retain the already verified matrix and continue directly to Task 6.

### Task 6: Final program verification and proof report

**Files:**
- Modify: `docs/ui-review/README.md` only for commands or state that actually changed.
- Log: Obsidian Vifty project note and current daily note.

- [ ] **Step 1: Run full repository verification**

Run: `df -h /System/Volumes/Data && git diff --check && make verify-full`

Expected: at least 30 GiB free and every Swift/Ruby/build/bundle/schema/plist/codesign gate passes.

- [ ] **Step 2: Run current automated UI verification**

Run: `make ui-review-verify-automated`

Expected: complete automated matrix pass for exact current products.

- [ ] **Step 3: Run full matrix verification only when both human attestations exist**

Run: `make ui-review-verify`

Expected: pass only if visual and VoiceOver attestations are genuinely complete. Otherwise report the exact pending human gate and do not relabel it as failure or success.

- [ ] **Step 4: Record a read-only runtime diagnostic**

Run: `.build/Vifty.app/Contents/MacOS/viftyctl diagnose --json`

Accept exit 0 or safely blocked exit 75. Do not follow repair or cooling recommendations automatically.

- [ ] **Step 5: Check owned temporary leftovers**

Run: `du -sh /private/tmp/[Vv]ifty* 2>/dev/null || true`

Remove only stale Vifty-owned temporary directories after confirming no active `lsof` handles.

- [ ] **Step 6: Write the evidence-backed closeout**

Report exact test counts, commit range, automated matrix counts, human-review status, runtime status, and explicit non-claims for hardware compatibility, helper replacement, notarization, and release publication.
