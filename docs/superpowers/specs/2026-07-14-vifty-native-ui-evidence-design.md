# Native UI, Accessibility, and VoiceOver Evidence Design

**Status:** Implementation complete. A committed portable checkpoint records 50 automated rows passing for exact historical source `6ac429cbacf7cc3358c74493ab7461a43fa40275`; current `HEAD` differs, so current-source recapture remains required. Human visual review remains pending, and VoiceOver was skipped by the owner with no VoiceOver behavior claimed.

## Goal

Produce hardware-free evidence that Vifty's deterministic review states render in their real macOS containers, expose the intended macOS Accessibility hierarchy, and remain safe from fan/helper/system mutations. Keep the final human visual and VoiceOver sessions as explicit attestations rather than inferring them from screenshots or AX data.

## Claim boundary

The evidence may prove:

- A specific debug executable rendered a specific deterministic state in Vifty's real main `Window`, real SwiftUI `Settings` scene, or a real `NSPopover` anchored to a disposable `NSStatusItem`.
- The captured PNG is nonempty, nontransparent, nonsolid, unique, dimensionally consistent with the observed native container, and bound to the exact capture.
- The target process exposed a complete, bounded Accessibility hierarchy with the required roles, identifiers, labels, values, selection states, actions, hierarchy order, and structural scroll reachability.
- No fixture fan command, helper lifecycle action, external settings mutation, real XPC/SMC client construction, or production polling lifecycle occurred.

The evidence must not claim:

- Hardware compatibility, fan-write correctness, helper repair, agent cooling, or Auto restoration.
- What VoiceOver spoke, how it pronounced text, VoiceOver navigation order, rotor behavior, or post-action announcements without a human VoiceOver attestation.
- A human visual-quality pass without a human visual attestation.
- Increase Contrast or Reduce Transparency coverage unless the corresponding macOS setting was observed as enabled during that capture.

## Selected architecture

### 1. Preserve the inert fixture runtime

`ViftyReviewFixtureRuntime` remains the only model-construction path for fixture sessions. It injects fake hardware, power, notifications, Login Item, helper, profile, preference, and daemon dependencies before `AppModel` is created. `model.start()` remains skipped. Fixture termination never calls production restore logic.

The runtime accepts a caller-supplied capture ID and records:

- process identifier;
- debug executable path and SHA-256;
- canonical semantic request and request SHA-256;
- native window identifier, window number, class, role provenance, visibility, content geometry, and backing scale;
- screenshot method, dimensions, path, and SHA-256 when a screenshot was requested;
- the existing safety recorder;
- lifecycle phase `prepared`, `ready`, or `final`.

The runtime writes `ready` only after the requested native container has produced the same visible, nonzero geometry on two consecutive main-run-loop turns. It writes `final` on ordinary fixture termination so late attempted actions remain visible.

### 2. Route through real native containers

Fixture content is no longer switched inside one main-window root.

- **Main:** the real `Window("Vifty", id: "main")` hosts `ContentView(daemonInstaller: runtime.daemonInstaller)` inside a DEBUG-only observation/capture wrapper.
- **Settings:** a DEBUG-only launcher in the main scene calls `openSettings()` once. The real `Settings` scene hosts `ViftySettingsView(model:initialTab:)` inside the observation/capture wrapper. The launcher window is hidden after the Settings window is visible.
- **Menu popover:** a DEBUG-only presenter creates a disposable `NSStatusItem`, attaches an inert `MenuBarView` to a real `NSPopover`, and shows it through the same AppKit anchoring geometry as production. It does not reuse `ViftyStatusItemController`, because production telemetry priming, quit, and restore callbacks are outside the fixture trust boundary.

Every fixture-named type, flag, state string, and router remains inside `#if DEBUG`. Fixture sessions omit production commands and continue to suppress production status-item construction and activation polling.

The container wrapper supplies explicit provenance (`swiftui-main-window`, `swiftui-settings-scene`, or `ns-popover-status-item`) and independently records AppKit facts. It assigns both an `NSWindow.identifier` and an Accessibility identifier derived from the capture ID.

Accessibility-text evidence uses the same app-owned, persisted Vifty text-size preference and environment as production: Standard (`1.0`), Large (`1.2`), and Accessibility (`1.5`). Semantic fonts retain their native AppKit descriptors while their sizes scale. The fixture selects this production environment directly; it does not synthesize or claim a macOS Dynamic Type setting.

### 3. Capture compositor-backed PNGs in the DEBUG fixture

After layout stabilizes, the fixture invokes the fixed, root-owned `/usr/sbin/screencapture` executable for only the exact observed `NSWindow.windowNumber`, with interaction and shadows disabled. It validates the full native-window pixel geometry, crops the compositor image to the window's `contentLayoutRect`, removes the transient full-window file on every in-process success or failure path, and records only the bounded content PNG. A timed-out capture subprocess is terminated, force-killed if needed, and reaped before the request returns. If the outer ready deadline instead terminates the whole fixture first, the orchestrator reaps that process group and then removes only an exact regular non-symlink `window-capture-<UUID>.png` child of the verified fixture directory. This is required because AppKit view-cache rendering turns SwiftUI compositor materials into transparent or black regions and is therefore not admissible visual evidence. The invoking terminal or Codex host needs Screen Recording permission; the fixture never prompts for or changes that permission and fails closed when capture is unavailable.

Main-window requests retain exact point sizes (`780x480`, `1180x820`, `1280x720`, and `1500x900`). Settings use native `600x420` content geometry. The popover uses native `320xauto`: its observed width must be exactly 320 points and its observed height must be positive and stable. PNG pixel dimensions must equal observed content points multiplied by backing scale.

The app remains alive after the screenshot when AX collection is requested. The orchestrator supplies a bounded completion-file path. After the external collector returns, the orchestrator creates that file; the app terminates normally and writes the final safety report. A timeout fails closed.

### 4. Add a non-bundled read-only AX collector

Add a Foundation-only `ViftyAXEvidenceCore` target and an ApplicationServices-linked `ViftyAXCollector` executable. The app build never copies either target into `Vifty.app`.

The collector requires an explicit positive PID, exact window Accessibility identifier, capture ID, check ID, and canonical request. It uses public read-only APIs only:

- `AXIsProcessTrusted()` without prompting;
- `AXUIElementCreateApplication` and `AXUIElementGetPid`;
- attribute reads, paged child reads, action-name reads, and `AXValue` decoding;
- a client-local messaging timeout.

The collector must not link or call AX action setters, keyboard/event posting, process activation/termination, System Settings opening, or trust-modification APIs. Missing permission emits a structured `AX_PERMISSION_MISSING` result with `promptRequested: false` and exit 77.

The collector finds exactly one `AXWindow` with the supplied identifier and exactly one descendant root marker containing the capture ID. It verifies PID and identifiers before and after traversal. Zero, duplicate, replaced, truncated, cyclic, timed-out, or incomplete targets fail closed.

Traversal is bounded deterministic depth-first pre-order. The raw report records stable paths, parent/child order, roles, subroles, identifiers, titles, descriptions, help, typed values, enabled/focused/selected state, positions, sizes, advertised actions, read errors, structural scroll data, and focus observations. It records actions as capabilities only; `actionsPerformed` must remain empty.

Structural scroll evidence binds the exact `AXVerticalScrollBar`, its finite current value, page-up/page-down capabilities, viewport/content geometry, and an offscreen end anchor. `AXMinValue` and `AXMaxValue` are recorded only when macOS exposes both; when both attributes are unavailable the report records explicit `null` values and never synthesizes `0`/`1` bounds. Settings scroll checks may use the unique exact capture-root `AXScrollArea` only when the pane's canonical scroll identifier is absent; the compact-main check still requires its canonical scroll identifier.

### 5. Recompute semantic AX predicates offline

The verifier never trusts a report's `status`, prose, or self-declared assertion. `ViftyAXEvidenceCore` and the Ruby matrix verifier share a versioned check catalog and recompute these contracts:

- manual-control owner headline and summary;
- distinct left/right Curve draft targets;
- exactly six unique Start/Ramp/High temperature/RPM adjustable controls with increment/decrement actions;
- the selected `CPU Efficiency` sensor and unselected peers;
- separate `Curve sensor · CPU Efficiency` and highest-temperature semantics;
- denied-notification settings actions and absence of an invalid test action;
- Settings hierarchy order;
- absence of duplicate chart accessibility elements;
- compact-main and four Settings structural scroll-reachability checks at accessibility text size.

Stable accessibility identifiers locate scopes and anchors, but every predicate also validates role, label, value, selection, actions, hierarchy, cardinality, and request state. The UI now exposes the explicit temperature metric required by `explicit-temperature-role`; the predicate passes without weakening its contract.

### 6. Seal every capture in schema v3

The manifest uses a top-level capture ledger keyed by unique capture ID. Requirement rows reference captures instead of repeating mutable paths and hashes.

Each ledger entry binds:

- canonical request plus its SHA-256;
- final fixture report path/SHA;
- debug executable path/SHA;
- PID and exact native-window identity;
- screenshot path, binary SHA, and canonical decoded-pixel SHA when present;
- AX raw/sealed report paths and hashes when present;
- optional human visual and VoiceOver attestation paths/hashes.

The verifier owns the exact ID-to-request mapping. Rewriting the manifest, reports, and hashes together cannot change what an ID means. It rejects missing, duplicate, unused, or orphaned captures.

PNG verification decodes filters 0–4 and canonicalizes supported 8-bit grayscale, RGB, gray-alpha, and RGBA pixels. It rejects transparent, solid, malformed, truncated, interlaced, dimension-mismatched, or canonically duplicate screenshots.

The automated visual matrix contains unique screenshots only:

- eight main-window size/appearance cells for healthy Auto;
- main-window screenshots for seven nonhealthy fixture states;
- a native Settings Notifications screenshot for `notification-denied`, where the denied state is visible; the baseline Settings Notifications cell remains healthy and `Allowed`;
- all four Settings tabs;
- one native 320-point popover;
- an Increase Contrast cell observed with the macOS-implied reduced transparency, plus a separate standard-contrast Reduce Transparency cell;
- main and four Settings accessibility-text cells.

Scroll reachability is AX evidence, not a duplicate screenshot request. This surface allocation gives every one of the nine fixture states meaningful visual coverage without asking a screenshot of the main window to prove a notification state that it does not display.

### 7. Keep human attestations distinct

A visual attestation references the exact capture-ledger hashes and records reviewer, time, method `visual-inspection`, covered cells, clipping/overlap/legibility/hierarchy/transient-state checks, and per-cell pass/fail.

A VoiceOver attestation references the same immutable capture set and records a scripted human session covering spoken labels/values, focus movement, rotor/grouping, adjustable controls, buttons, scroll reachability, and announcements after safe UI-only actions. AX hierarchy order must not be described as VoiceOver traversal order.

Overall manifest status remains pending until required automated rows and both human attestations pass. A separate automated verifier mode may report that autonomous evidence is complete while human gates remain pending.

An early historical autonomous result contained 9 of 9 fixture rows, 28 of 28 visual rows, and 13 of 13 AX rows in a 50-entry ledger. `--verify-automated` passed against release SHA-256 `3ca9a5d6d8cdd09656ca76c06056ed0c066fbb4b945416be54cd464959d2db5a`, debug SHA-256 `139d440226a00d739d76beb74bc6d0ae60401c3696a8f176158367c4231c7afc`, and collector SHA-256 `e54135c739c1174a38d93c3cbd5317583f6585d3b85ab02d3cf1e71c51dc0e0c`. That snapshot was superseded after the curve chart and its Accessibility contract changed. A later committed portable checkpoint records a separate 50-row automated pass for exact source `6ac429cbacf7cc3358c74493ab7461a43fa40275` and byte-binds the canonical hero, but it also does not transfer to current `HEAD`. The tracked request manifest remains pending a fresh current-source seal; prior agent and human image reviews remain historical and cannot satisfy the current visual gate.

## Orchestration and failure handling

The shell entrypoint gains explicit `capture`, `collect-ax`, `seal`, `verify-automated`, and `verify-matrix` modes. It launches the bundle executable directly to retain the exact PID, supplies the capture ID, waits with bounded polling for `ready`, invokes the collector only when requested, asks the fixture to terminate through its completion file, waits for `final`, and then writes the ledger.

Every mode uses one bounded `.build/ui-review-evidence` tree. It never edits macOS Accessibility, Increase Contrast, or Reduce Transparency settings. It never launches the production helper, daemon, or `viftyctl`.

Failures preserve structured evidence and exit nonzero. A prepared/ready-only report, unsafe recorder, permission block, process replacement, container mismatch, missing final report, invalid PNG, semantic AX failure, or attestation drift cannot be promoted.

## Verification

Implementation follows red-green-refactor cycles for:

- schema-v3 ledger/provenance/request tamper resistance;
- transparent, solid, malformed, and pixel-duplicate PNG rejection;
- exact matrix request maps and all-nine-state screenshot coverage;
- all 13 semantic AX predicates and structural scroll evidence;
- permission, PID, window, root-marker, timeout, cycle, and traversal-limit failures;
- real main/Settings/popover routing and stable geometry;
- fixture late-mutation detection and release-marker exclusion;
- collector non-bundling and forbidden-symbol checks.

The final automated gate includes focused fixture/AX/verifier tests, `make verify`, release-binary marker inspection, `git diff --check`, fresh capture verification for all autonomously available cells, and independent spec/code-quality review. Hardware and helper state remain untouched.
