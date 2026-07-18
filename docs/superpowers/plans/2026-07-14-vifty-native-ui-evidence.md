# Native UI Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Vifty's spoofable schema-v2 UI matrix with native-container screenshots, PID/window/executable-bound capture ledgers, semantically verified read-only AX evidence, and explicit human visual/VoiceOver handoffs.

**Architecture:** Keep the existing inert debug fixture model, route its real views through the production main and Settings scenes plus a debug-owned `NSPopover`, use the same persisted Vifty semantic text-scale environment as production, capture PNGs in-process, and inspect the live process with a separate non-bundled read-only AX collector. Seal every artifact into a schema-v3 capture ledger whose expected requests and predicates are owned by the verifier.

**Tech Stack:** Swift 6, SwiftUI, AppKit, ApplicationServices AX APIs, CryptoKit, Swift Package Manager, XCTest, Bash, Ruby, JSON Schema.

**Worktree rule:** Work in the existing `codex/vifty-whole-app-remediation` checkout because the feature depends on its uncommitted aggregate changes. Do not create a detached worktree, stage files, commit, push, launch the production helper, invoke `viftyctl`, or issue fan commands.

---

### Task 1: Lock schema-v3 request, ledger, and PNG contracts

**Files:**

- Modify: `Tests/ViftyCoreTests/UIReviewEvidenceScriptTests.swift`
- Modify: `scripts/run-ui-review-fixture.sh`
- Create: `scripts/lib/ui_review_contract.rb`
- Create: `docs/schemas/ui-review-evidence-manifest-v3.schema.json`
- Modify: `docs/ui-review/evidence-manifest.json`

- [x] **Step 1: Write failing ledger and request-map tests**

Add XCTest cases named:

```swift
func testVerifierRejectsLegacyV2AndMissingOrOrphanedCaptureLedgerEntries() throws
func testVerifierPinsEveryFixtureVisualAndAXIDToItsCanonicalRequest() throws
func testVerifierRejectsDebugExecutablePIDWindowAndContainerDrift() throws
func testVerifierRequiresMainScreenshotCoverageForAllNineStates() throws
func testVerifierRequiresNativeSettingsAnd320PointPopoverGeometry() throws
```

The populated fixture must use schema version 3, a top-level `captureLedger` dictionary, `captureID` references from requirement rows, canonical request hashes, final fixture-report hashes, debug executable SHA, PID, window identifier/number/class/container/geometry, and no unused capture.

- [x] **Step 2: Verify the new tests fail for the intended v2 behavior**

Run:

```bash
swift test --scratch-path "$PWD/.build" --filter UIReviewEvidenceScriptTests
```

Expected: failures state that schema v2 is still accepted, capture-ledger/request maps are absent, or runtime identity is not checked.

- [x] **Step 3: Extract the verifier contract and implement canonical binding**

Create `scripts/lib/ui_review_contract.rb` with these public entry points:

```ruby
module ViftyUIReview
  SCHEMA_VERSION = 3
  REQUEST_KEYS = %w[appearance contrast interaction state surface textSize transparency window].freeze

  def self.canonical_json(value)
    normalized = case value
                 when Hash then value.keys.sort.to_h { |key| [key, JSON.parse(canonical_json(value.fetch(key)))] }
                 when Array then value.map { |item| JSON.parse(canonical_json(item)) }
                 else value
                 end
    JSON.generate(normalized)
  end

  def self.sha256_json(value)
    Digest::SHA256.hexdigest(canonical_json(value))
  end

  def self.expected_fixture_requests = EXPECTED_FIXTURE_REQUESTS
  def self.expected_visual_requests = EXPECTED_VISUAL_REQUESTS
  def self.expected_ax_requests = EXPECTED_AX_REQUESTS
end
```

Populate the constants explicitly. `EXPECTED_FIXTURE_REQUESTS` contains each of the nine states at main/1180x820/light/standard/standard/standard/none. `EXPECTED_VISUAL_REQUESTS` contains the eight healthy main size/appearance combinations, seven other-state main/1180x820/light rows, a native Settings Notifications row for `notification-denied`, four healthy native Settings rows, one 320xauto popover row, a main Increase Contrast row with the macOS-implied reduced transparency, a separate standard-contrast Reduce Transparency row, and main plus four Settings accessibility-text rows. The healthy Settings Notifications row reports `Allowed`; the denied-state row exposes the denial on the surface where it is visible. `EXPECTED_AX_REQUESTS` contains the eight semantic checks at their state/surface plus five accessibility-text structural-scroll rows; no request is derived from manifest content.

Implement fail-closed validation for exact IDs and requests, canonical request hashes, unique capture IDs, no orphan/unused captures, final fixture phase, matching debug executable SHA, positive PID/window number, exact Accessibility window identifier, correct container geometry, fixture safety recorder, and release marker exclusion.

- [x] **Step 4: Add content-aware PNG tests before the decoder**

Add:

```swift
func testVerifierRejectsFullyTransparentAndSolidPNGs() throws
func testVerifierRejectsCanonicalPixelDuplicatesAcrossCells() throws
func testVerifierAcceptsUniqueOpaquePatternedPNGsAcrossSupportedColorTypes() throws
```

Replace the zero-filled `validPNG` helper with a seeded opaque pattern. Add helpers for transparent, solid, and recompressed-equivalent images.

- [x] **Step 5: Verify PNG tests fail for the intended reason**

Run the same focused suite and confirm the current structure-only verifier accepts at least one forbidden image.

- [x] **Step 6: Implement PNG filters and canonical pixels**

In `ui_review_contract.rb`, decode PNG filters 0–4 for 8-bit grayscale, RGB, gray-alpha, and RGBA. Normalize every pixel to RGBA bytes, compute a canonical pixel SHA, and return:

```ruby
{
  width: width,
  height: height,
  canonical_pixel_sha256: Digest::SHA256.hexdigest(rgba),
  visible_pixels: visible_pixels,
  unique_visible_colors: unique_visible_colors
}
```

Reject zero visible pixels, fewer than two visible colors, malformed/CRC-invalid/truncated/interlaced data, dimension drift, and duplicate canonical pixel hashes.

- [x] **Step 7: Update the committed manifest shape while keeping it pending**

Convert `docs/ui-review/evidence-manifest.json` to schema v3 with an empty `captureLedger`, exact fixture/visual/AX rows, human-attestation slots, and `status: "pending"`. Use `window: "native"` for Settings and `window: "320xauto"` for the popover. Remove the five duplicate compact-scroll screenshot rows, add seven nonhealthy main-state screenshot rows, and bind `state-notification-denied` to native Settings Notifications.

- [x] **Step 8: Verify Task 1 green**

Run:

```bash
/bin/bash -n scripts/run-ui-review-fixture.sh
ruby -c scripts/lib/ui_review_contract.rb
swift test --scratch-path "$PWD/.build" --filter UIReviewEvidenceScriptTests
git diff --check -- scripts/run-ui-review-fixture.sh scripts/lib/ui_review_contract.rb docs/ui-review/evidence-manifest.json docs/schemas/ui-review-evidence-manifest-v3.schema.json Tests/ViftyCoreTests/UIReviewEvidenceScriptTests.swift
```

Expected: syntax checks pass and every UI evidence script test passes.

### Task 2: Add runtime identity, stable geometry, and in-process PNG capture

**Files:**

- Modify: `Sources/Vifty/ViftyReviewFixture.swift`
- Create: `Sources/Vifty/ViftyReviewCapture.swift`
- Modify: `Tests/ViftyCoreTests/ViftyReviewFixtureTests.swift`

- [x] **Step 1: Write failing runtime-identity and capture tests**

Add:

```swift
func testSchemaV3ReportBindsCanonicalRequestProcessExecutableAndWindow() async throws
func testRuntimeRequiresTwoMatchingVisibleGeometrySamplesBeforeReady() async throws
func testRuntimeRejectsWrongContainerNativeGeometryAndExecutableHash() async throws
func testCaptureWritesOpaquePNGMatchingObservedScaleAndFinalizesLateSafetyState() async throws
```

Tests construct a deterministic request with explicit capture ID, executable fixture URL/data, and output paths. Geometry samples cover hidden, zero-sized, unstable, stable main, native Settings, and 320-point popover cases.

- [x] **Step 2: Run red fixture tests**

```bash
swift test --scratch-path "$PWD/.build" --filter ViftyReviewFixtureTests
```

Expected: missing schema-v3 process/runtime fields, capture ID parsing, stability gate, or screenshot writer.

- [x] **Step 3: Implement pure canonical request and geometry helpers**

Add types with these responsibilities:

```swift
struct ViftyReviewRuntimeIdentity: Codable, Equatable, Sendable {
    let processIdentifier: Int32
    let executablePath: String
    let executableSHA256: String
}

struct ViftyReviewWindowSample: Codable, Equatable, Sendable {
    let provenance: String
    let identifier: String
    let accessibilityIdentifier: String
    let windowNumber: Int
    let windowClass: String
    let isVisible: Bool
    let contentWidth: Int
    let contentHeight: Int
    let backingScaleFactor: Double
}

struct ViftyReviewGeometryStabilizer {
    mutating func consume(_ sample: ViftyReviewWindowSample, request: ViftyReviewFixtureRequest) -> ViftyReviewWindowSample?
}
```

The stabilizer returns a sample only after two identical valid samples. Main geometry is exact, Settings requires provenance `swiftui-settings-scene` with positive native geometry, and popover requires provenance `ns-popover-status-item`, width 320, and positive height.

- [x] **Step 4: Implement the AppKit screenshot writer**

`ViftyReviewCapture.swift` exposes:

```swift
@MainActor
enum ViftyReviewPNGWriter {
    static func capture(contentView: NSView, window: NSWindow, to url: URL) throws -> ViftyReviewScreenshotObservation
}
```

It lays out the view, invokes the fixed root-owned `/usr/sbin/screencapture` executable for the exact observed `NSWindow.windowNumber`, validates the full compositor-frame geometry, crops to `contentLayoutRect`, writes an atomic PNG, and records point/pixel dimensions, `native-window-screencapture-crop`, and SHA-256. It refuses empty bounds, untrusted or failed capture tooling, missing/invalid PNG data, and dimensions inconsistent with scale. The app removes the transient full-window file on every in-process success or failure path, and a timed-out capture subprocess is terminated, force-killed if necessary, and reaped before the fixture returns. The outer orchestrator also performs a post-reap cleanup limited to exact regular non-symlink transient filenames when its ready deadline terminates the fixture first.

- [x] **Step 5: Upgrade runtime lifecycle and arguments**

Parse explicit DEBUG-only flags for capture ID, screenshot path, AX hold/completion file, and bounded timeout. Record `prepared`, `ready`, and `final` phases. Keep finalization idempotent, but rewrite the final report from the latest recorder snapshot so late attempted actions fail.

- [x] **Step 6: Verify Task 2 green**

Run the fixture tests, `AppArchitectureBoundaryTests`, and `git diff --check` for the touched files.

### Task 3: Route fixtures through real main, Settings, and popover containers

**Files:**

- Modify: `Sources/Vifty/ViftyApp.swift`
- Modify: `Sources/Vifty/ViftyReviewFixture.swift`
- Create: `Sources/Vifty/ViftyReviewPopoverPresenter.swift`
- Modify: `Tests/ViftyCoreTests/ViftyReviewFixtureTests.swift`
- Modify: `Tests/ViftyCoreTests/AppArchitectureBoundaryTests.swift`

- [x] **Step 1: Write failing route and presenter tests**

Add pure route tests asserting:

```swift
XCTAssertEqual(ViftyReviewFixtureRoute(surface: .main), .main)
XCTAssertEqual(ViftyReviewFixtureRoute(surface: .settingsNotifications), .settings(.notifications))
XCTAssertEqual(ViftyReviewFixtureRoute(surface: .menuPopover), .popover)
```

Add an idempotent launch coordinator test proving repeated appearances call exactly one of `openSettings` or `showPopover`. Add source-boundary assertions that Settings content lives in the `Settings` scene and menu fixture content is no longer returned from the main fixture root.

- [x] **Step 2: Verify route tests fail**

Run `ViftyReviewFixtureTests` and `AppArchitectureBoundaryTests`; confirm the old embedded switch is the failure.

- [x] **Step 3: Implement container-specific scene hosts**

Create a DEBUG-only `ViftyReviewFixtureSceneHost` that applies color/text overrides, installs the observer/root AX marker, and passes explicit provenance. Add `ViftyReviewFixtureLaunchBridge` with `@Environment(\.openSettings)` and one-shot routing.

In `ViftyApp.body`:

- host main fixture content only for `.main`;
- host fixture Settings content inside the real `Settings` scene;
- omit production commands during any fixture run;
- preserve all fixture guards around `model.start`, status-item creation, activation refresh, and termination restore.

- [x] **Step 4: Implement the debug-owned popover presenter**

`ViftyReviewPopoverPresenter` owns a disposable `NSStatusItem` and `NSPopover`, embeds the real `MenuBarView` with inert recording closures, waits for `popoverDidShow`, assigns capture-derived identifiers, supplies popover provenance, and removes the status item on disposal. It does not instantiate or call `ViftyStatusItemController`.

- [x] **Step 5: Verify Task 3 green**

Run fixture, architecture-boundary, Settings scene, and menu presentation tests. Run a debug build only; do not launch the app yet.

### Task 4: Add the pure AX evidence model and semantic predicate engine

**Files:**

- Create: `Sources/ViftyAXEvidenceCore/AXEvidenceModels.swift`
- Create: `Sources/ViftyAXEvidenceCore/AXPredicateCatalog.swift`
- Create: `Tests/ViftyCoreTests/AXEvidencePredicateTests.swift`
- Modify: `Package.swift`

- [x] **Step 1: Add the target and write one red valid/invalid test per predicate**

Add `ViftyAXEvidenceCore` as a library dependency of `ViftyCoreTests`. Synthetic observations use stable paths and identifiers. For each of the 13 IDs, provide one valid tree and then mutate every required fact: missing/duplicate node, wrong label/value/action/selection/order, swapped target, missing explicit role, missing overflow, or zero scrollbar range.

- [x] **Step 2: Run red predicate tests**

```bash
swift test --scratch-path "$PWD/.build" --filter AXEvidencePredicateTests
```

Expected: the predicate catalog is unavailable.

- [x] **Step 3: Implement deterministic models and predicates**

Define Codable `AXEvidenceRequest`, `AXObservation`, `AXTraversal`, `AXScrollEvidence`, `AXRawCapture`, `AXAssertion`, and `AXSealedReport`. Implement:

```swift
public enum AXPredicateCatalog {
    public static func evaluate(id: String, capture: AXRawCapture) throws -> AXAssertion
}
```

The evaluator ignores any self-declared status and derives facts/paths from observations. Unknown IDs and incomplete traversal fail closed.

- [x] **Step 4: Add deterministic JSON and generic-stub rejection tests**

Prove dictionary/action input order cannot change sorted JSON bytes and that the previous one-node `AXGroup` stub fails all 13 checks.

- [x] **Step 5: Verify Task 4 green**

Run the predicate suite and a warnings-as-errors build of `ViftyAXEvidenceCore`.

### Task 5: Add the non-bundled read-only AX collector

**Files:**

- Create: `Sources/ViftyAXCollector/main.swift`
- Create: `Sources/ViftyAXCollector/AXReader.swift`
- Create: `Sources/ViftyAXCollector/AXTraversal.swift`
- Create: `Tests/ViftyCoreTests/AXCollectorAdapterTests.swift`
- Modify: `Package.swift`
- Modify: `Tests/ViftyCoreTests/MakefileTrustGateTests.swift`
- Modify: `Tests/ViftyCoreTests/AppArchitectureBoundaryTests.swift`

- [x] **Step 1: Write failing adapter, permission, and packaging tests**

Cover permission denied without prompt, invalid PID, PID mismatch, zero/multiple window matches, missing/duplicate root marker, timeout, disappearing process, cycle, depth/node truncation, deterministic traversal, and action-name sorting. Static tests reject mutating AX/event/process symbols and prove the collector/core are absent from all Vifty app bundle locations.

- [x] **Step 2: Run the red collector tests**

Expected: target/reader/CLI are missing.

- [x] **Step 3: Implement the reader abstraction and public-API adapter**

Create an injectable protocol for tests and a production adapter using only the read APIs listed in the design. `AXIsProcessTrusted() == false` emits `AX_PERMISSION_MISSING`, `promptRequested: false`, and exit 77. Set a bounded messaging timeout and page children.

- [x] **Step 4: Implement bound deterministic traversal**

Require exact PID, capture ID, and window/root identifiers before and after traversal. Use bounded pre-order paths based on child indices, `CFEqual` cycle detection, finite normalized geometry, sorted action names, string limits, and `traversal.complete = false` at any bound.

- [x] **Step 5: Implement `collect` and `seal` CLI modes**

`collect` writes canonical raw JSON only. `seal` accepts the final fixture report and hashes, verifies matching request/runtime identity and safe final phase, evaluates the requested predicate through `ViftyAXEvidenceCore`, and writes the sealed report.

- [x] **Step 6: Verify forbidden symbols and non-bundling**

Build the collector explicitly, inspect undefined symbols with `nm -u`, build the debug and release app bundles, and confirm no AX target binary/source/schema appears inside either app.

### Task 6: Expose stable Accessibility semantics required by the predicates

**Files:**

- Modify: `Sources/Vifty/ControlSessionCard.swift`
- Modify: `Sources/Vifty/FanStatusList.swift`
- Modify: `Sources/Vifty/FanCurveChartEditor.swift`
- Modify: `Sources/Vifty/TemperatureCurveEditor.swift`
- Modify: `Sources/Vifty/TelemetryEvidencePanel.swift`
- Modify: `Sources/Vifty/SettingsGeneralView.swift`
- Modify: `Sources/Vifty/SettingsMenuBarView.swift`
- Modify: `Sources/Vifty/SettingsNotificationsView.swift`
- Modify: `Sources/Vifty/SettingsAgentWorkflowView.swift`
- Modify: focused presentation/accessibility tests for each surface.

- [x] **Step 1: Write failing source/presentation tests for every required identifier and value**

Define stable identifiers under `vifty.ax.*` for owner card/title/summary, left/right fan draft targets, six exact curve controls, sensor rows, curve/highest temperature metrics, notification actions/events, Settings tabs/anchors, chart scope, and five scroll areas/anchors.

Add a failing test that requires the explicit metric value `Curve sensor · CPU Efficiency` and a separate `Highest 83.0 °C` value.

- [x] **Step 2: Run red focused tests**

Confirm the explicit-temperature-role test fails because the metric is currently absent.

- [x] **Step 3: Add minimal SwiftUI accessibility semantics**

Add identifiers, labels, values, selection traits, adjustable actions, and accessibility representations without altering fan-control behavior. Preserve the existing six independent temperature/RPM adjustable controls and remove duplicate chart elements from the AX tree.

- [x] **Step 4: Verify predicates against synthetic and fixture-derived presentation data**

Run all touched UI/presentation suites plus AX predicates. Ensure no test invokes an Accessibility action, helper, XPC, or hardware path.

### Task 7: Add capture orchestration, sealing, and human handoff templates

**Files:**

- Modify: `scripts/run-ui-review-fixture.sh`
- Modify: `Makefile`
- Modify: `Tests/ViftyCoreTests/UIReviewEvidenceScriptTests.swift`
- Modify: `Tests/ViftyCoreTests/MakefileTrustGateTests.swift`
- Modify: `docs/ui-review/README.md`
- Create: `docs/ui-review/visual-attestation-template.json`
- Create: `docs/ui-review/voiceover-attestation-template.json`
- Create: `docs/schemas/ui-review-attestation-v1.schema.json`

- [x] **Step 1: Write failing orchestration and attestation tests**

Test direct executable PID retention, bounded ready/final waits, completion-file termination, permission-block preservation, safe timeout cleanup, ledger sealing, `--verify-automated`, missing/tampered/wrong-method visual attestation, missing/tampered/wrong-method VoiceOver attestation, and `--verify-matrix` remaining blocked until both human attestations pass.

- [x] **Step 2: Implement explicit modes**

Support:

```text
--capture
--collect-ax
--seal
--verify-automated
--verify-matrix
```

Always require explicit app/debug executable, manifest, evidence directory, and release binary where applicable. Generate capture IDs before launch, launch the bundle executable directly, retain `$!`, poll with bounded deadlines, and preserve structured failure artifacts.

- [x] **Step 3: Add human templates and verifier rules**

Visual method is exactly `visual-inspection`; VoiceOver method is exactly `voiceover-session`. Require nonempty reviewer, ISO-8601 time, exact capture/request/executable/report/PNG/AX hashes, covered row IDs, scripted per-step results, and overall passed status. Do not accept AX evidence as a VoiceOver attestation.

- [x] **Step 4: Update docs and Makefile**

Document autonomous capture, AX permission exit 77, native container geometry, system-setting captures, automated versus full matrix status, and the exact human scripts. Keep the pending matrix out of `make verify`; keep its contract tests in the fast suite.

- [x] **Step 5: Verify Task 7 green**

Run shell/Ruby syntax, UI evidence tests, Makefile trust tests, community/docs tests, and `git diff --check`.

### Task 8: Capture autonomous evidence and run final review

**Files:**

- Generated only: `.build/ui-review-evidence/**`
- Modify only after successful sealing: ignored `docs/ui-review/evidence-manifest.local.json`
- Write only after a fresh 50-row automated pass: `docs/ui-review/automated-checkpoint.json`
- Modify after evidence is stable: `README.md` screenshot reference if the deterministic healthy capture is approved.

- [x] **Step 1: Recheck disk and build bounded products**

```bash
df -h /System/Volumes/Data
make ui-review-build-products
```

Stop below 30 GiB. This clean-tree transaction builds the debug fixture app, release-exclusion Vifty binary, and AX collector from one exact archived commit/tree and embeds one shared transaction identity in each Mach-O.

- [x] **Step 2: Capture every standard, light/dark, size, state, Settings, popover, and accessibility-text row after the required temporary macOS setting changes are authorized**

Standard rows require both Reduce Transparency and Increase Contrast off. The dedicated Increase Contrast row requires Increase Contrast on, which also implies reduced transparency; the dedicated Reduce Transparency row uses standard contrast with Reduce Transparency on. Use the orchestrator only. Do not click fixture controls. After each run, require final safe recorder, exact executable/PID/window binding, valid PNG, and sealed AX report where required. After the telemetry-history copy fix superseded the prior ledger, the replacement `main-reduce-transparency` row, all 48 standard rows, and `main-increase-contrast` were sealed. At that historical checkpoint, Increase Contrast was off and Reduce Transparency was on; the later current-state correction appears below.

- [ ] **Step 3: Run automated verification and inspect every PNG**

```bash
scripts/run-ui-review-fixture.sh --verify-automated \
  --manifest docs/ui-review/evidence-manifest.local.json \
  --evidence-dir "$PWD/.build/ui-review-evidence" \
  --debug-executable "$PWD/.build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty" \
  --release-binary "$PWD/.build/ui-review-products/release/Vifty" \
  --collector-executable "$PWD/.build/ui-review-products/debug/ViftyAXCollector"
```

Inspect all screenshots for clipping, overlap, empty panes, illegible hierarchy, unexpected controls, and incorrect transient states. Record observations without creating a human attestation.

- [ ] **Step 4: Run fresh automated gates**

Run focused fixture/AX/verifier suites, `make verify`, release marker/bundle checks, `git diff --check`, and temp/disk hygiene checks.

- [x] **Step 5: Request independent spec and code-quality review**

Review the bounded UI-evidence diff against the design. Fix every Critical and Important finding, rerun focused tests, then rerun `make verify`.

- [ ] **Step 6: Hand off only genuine human gates**

Ask the user for:

1. the bounded visual-inspection checklist;
2. the scripted human VoiceOver session.

At that historical checkpoint, the display-setting captures were complete and the original Reduce Transparency on / Increase Contrast off state was restored. The then-proposed non-owner release-reviewer gate was later removed after forensic review showed it was remediation-added team-shaped policy rather than a live GitHub requirement. Current release governance is documented separately and does not upgrade this historical UI evidence.

Do not claim full matrix completion until the resulting attestations verify.

### Continuation record — 2026-07-15

- Supersession: the frozen products and 50-entry ledger described below are historical after the curve chart gained distinct effective Left/Right fan series, stable authoring bounds, and exact per-fan Accessibility summaries. The manifest was reset to pending, and both human visual batches were marked superseded. Current-build recapture and both human reviews must restart against new hashes.
- Post-fix recapture checkpoint: 9/9 fixture, 26/26 standard visual, and 13/13 AX rows are sealed in a 48-entry ledger; `--verify-automated` passes with only `main-increase-contrast` and `main-reduce-transparency` pending. The canonical divergent screenshot visibly contains blue Requested plus dashed cyan/purple effective curves, and the sealed six-control AX row contains exact Left/Right summaries after the chart. Human visual review remains 0/28.
- The owner then enabled Reduce Transparency with Increase Contrast off. `main-reduce-transparency` sealed as `visual-main-reduce-transparency-20260715T165043Z-12df14f9fa4c`; the 49-entry manifest re-passed `--verify-automated`. Only `main-increase-contrast` remains before human review can restart.
- The owner enabled Increase Contrast; readback observed both Increase Contrast and Reduce Transparency on. `main-increase-contrast` sealed as `visual-main-increase-contrast-20260715T165530Z-f774d04ea05f`. The complete 50-entry matrix passed `--verify-automated`; `--verify-matrix` now blocks only on the absent current visual and VoiceOver attestations. Restore Increase Contrast off while retaining Reduce Transparency on before human review.
- The owner restored and Codex read back Reduce Transparency on / Increase Contrast off. Current human visual Batch 1 is now bound to four current-manifest captures and awaits review; historical Batch 1/2 responses remain superseded.
- Engineering QA caught a two-poll telemetry-history contradiction in that Batch 1 before human approval. The fix labels one point as retained and requests one more successful poll. Its red/green tests and 18-test telemetry suite passed; a second exact `make test-fast` passed 1,268/1,268 after an earlier non-reproducing suite-level failure. Because all rows bind the exact executable, the 50-entry ledger and awaiting Batch 1 were superseded again. New hashes are debug `411ba2e2c40aa717affc2ef24a60594cfa2810a333ed532930581a3ea2c1f233`, collector `3cc2c943361f8a2148f88eb36095ac797f50a7d589e00ceea4a1628d74e64fd2`, and release `ce9cffdcd3e3f5784c8d915559ffc3e7e048fe3b443ed87be1582fd8309b19fc`. The new Reduce Transparency row is sealed as `visual-main-reduce-transparency-20260715T172355Z-5b1bc08cd94c`; the ledger is 1/50 and human review remains 0/28.
- With both display accommodations off, the fail-closed resumable batch sealed all 48 standard rows against those frozen hashes. One ready timeout and one native WindowServer screenshot failure remained unbound; identical clean retries produced new sealed captures. The 49-entry manifest is SHA-256 `eec9ee74a364dbf6adbac3019e7919e18bf2f985cf24975a680f870863d7cbce`, and `--verify-automated` passes with 9/9 fixture, 27/28 visual, and 13/13 AX rows. Only `main-increase-contrast` remains; human visual review is still 0/28 and VoiceOver has not started.
- The owner enabled Increase Contrast; readback was Reduce Transparency `1` / Increase Contrast `1`. `main-increase-contrast` sealed as `visual-main-increase-contrast-20260715T181336Z-1c58e0fe738c`. The 50-entry manifest SHA-256 is `3ad360d06748c27fec1014db8da036651cbdc68c9abbbaa5db153bfdee73c648`; `--verify-automated` passes with 9/9 fixture, 28/28 visual, and 13/13 AX rows. `--verify-matrix` now blocks only on pending manifest status and the absent current visual and VoiceOver attestations. Restore Increase Contrast off while retaining Reduce Transparency on before human review.
- The owner restored the display and readback confirmed Reduce Transparency `1` / Increase Contrast `0`. Engineering QA found no clipping, overlap, legibility, hierarchy, or transient-state blocker in the first four current-build screenshots. Current Batch 1 is presented with exact capture and pixel-hash bindings; human review remains 0/28 until the owner responds.
- The owner responded `Great. Anything left to do?`; this is recorded as passing current Batch 1's four exact bindings. Human visual progress is 4/28. Current Batch 2 contains the 1280x720 and 1500x900 light/dark rows; engineering QA found no blocker and the owner response is pending.
- A complete engineering sweep then found blockers outside Batch 1: the light-request native popover artifact was dark with illegible black content; the edited-profile toolbar clipped its identity and actions; raw-spike fixture telemetry contradicted its current snapshot; and narrower contrast, selected-tab layout, curve-legend, helper-action wording, and VoiceOver-script gaps remained. Apparent black tiles and missing Settings-tab fragments were inconsistent conversation-renderer artifacts; independent decoding and pixel statistics did not reproduce them in the immutable PNG bytes, so no app/capture race is claimed. Batch 2 and VoiceOver handoff are paused. The 50-entry ledger still proves exact provenance and automated predicates, but it is not visual approval. Source fixes will supersede the ledger and the four-row Batch 1 result; collect a complete replacement exact-binary matrix before asking for renewed human review.

### Portability continuation — 2026-07-16

- Every ledger and human result above is historical after later remediation source changes. The committed `docs/ui-review/evidence-manifest.json` is now a host-free pending request template; the last host-bound ledger is retained only in ignored `docs/ui-review/evidence-manifest.local.json`.
- The full `.build/ui-review-evidence/` tree remains local and untracked. A strict portable checkpoint may be generated only after the current exact binary has a new 50-row automated pass. It records source/manifest/product hashes, per-row checksums, zero-mutation aggregates, and the canonical hero binding without paths, PIDs, window numbers, reviewer identity, or human attestation carry-forward.
- The checkpoint writer now binds the declared commit to an exact clean repository `HEAD`, permits only the canonical tracked hero and checkpoint output as local Git changes, hashes rather than exports capture IDs, emits rows in the authoritative contract order, validates the result against the tracked strict schema, and snapshots every manifest/product/report/PNG/raw/sealed input before verification and again before atomic publication. AX collection and sealing record one exact collector path and SHA-256; the verifier requires all 13 AX rows to match the explicitly supplied collector.
- A committed portable `docs/ui-review/automated-checkpoint.json` now records an automated pass for all 50 rows at exact historical source `6ac429cbacf7cc3358c74493ab7461a43fa40275`, and its hero hash matches `docs/images/vifty-screenshot.png`. Current `HEAD` differs, so that checkpoint is not current-source UI evidence. Human visual review remains pending with prior results superseded. VoiceOver remains pending with the owner's decision recorded as `skipped-by-owner`; no VoiceOver behavior is claimed.

- Vifty now owns a persisted semantic text-size preference with Standard (`1.0`), Large (`1.2`), and Accessibility (`1.5`) choices. The fonts preserve native AppKit descriptors, and the fixture uses the same production environment rather than synthetic macOS Dynamic Type.
- Superseded snapshot: the then-frozen products were release SHA-256 `3ca9a5d6d8cdd09656ca76c06056ed0c066fbb4b945416be54cd464959d2db5a`, debug SHA-256 `139d440226a00d739d76beb74bc6d0ae60401c3696a8f176158367c4231c7afc`, and collector SHA-256 `e54135c739c1174a38d93c3cbd5317583f6585d3b85ab02d3cf1e71c51dc0e0c`.
- In that now-historical ledger, the manifest contained 9 of 9 fixture rows, 28 of 28 visual rows, and 13 of 13 AX rows, and `--verify-automated` passed. Those rows do not bind the current source.
- At that checkpoint, agent inspection of all 28 PNGs found no blocking clipping, overlap, unreadability, or state mismatch. This was not a human visual attestation and is now superseded along with the ledger.
- At that checkpoint, the dedicated display-accommodation captures were sealed and the user display state was Reduce Transparency on / Increase Contrast off.
- The owner subsequently restored the current host settings to Reduce Transparency off / Increase Contrast off. This setting state does not revive any superseded evidence.
- Historical governance note: this checkpoint predated the 17 July forensic correction. The absent non-owner reviewer was later recognized as a team-shaped policy introduced by the remediation rather than a live GitHub requirement. The corrected solo-maintainer contract uses a real protected `release` environment with no reviewer gate, administrator bypass disabled, and exactly one custom `tag: v*` deployment policy with no branch policy. The live environment still had the older protected-branch-only setting at the latest readback, so migration after the hardening merge is an explicit pre-tag blocker. After separate release prep and exact-main CI, the tag creator embeds fresh administrator-pretag evidence in the signed annotated tag and the hardened helper pushes that exact signed tag; the push automatically starts the only permitted first-attempt Release run. There is no manual dispatch or rerun path. The helper creates a checkout-independent retired-tag marker immediately before the push boundary, so an inconclusive outcome is inspected in place and a new patch is used only after non-publication is conclusive. The release-manifest candidate remains `null` until that separate release-prep change.
