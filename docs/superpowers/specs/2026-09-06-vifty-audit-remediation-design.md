# Vifty Audit Remediation Design

**Date:** 2026-09-06
**Status:** Approved design
**Repository baseline:** `93fa955d6cea4b90c5d5d64090cccd3677efbe44`

## Purpose

Resolve the confirmed correctness, safety, operational-truth, and UI-evidence findings from the 2026-09-06 comprehensive audit without weakening Vifty's existing fan-control, XPC, helper-maintenance, local-data, or release-trust boundaries.

The work is split into three independently shippable stages. Each stage must leave the repository green and may be reviewed or reverted without depending on unfinished work in a later stage.

## Global constraints

- macOS 15 remains the minimum deployment target and Swift Package Manager remains the build system.
- Add no third-party dependency.
- Preserve daemon-first, fail-closed fan writes and all existing fresh-snapshot, transaction, readback, ownership, restore, lock, and journal requirements.
- Do not expose raw SMC writes or relax the agent cooling lease policy.
- Do not change published release history, release tags, cask metadata, signing identities, or notarization policy.
- Implementation verification is read-only with respect to hardware: no fan command, cooling lease, helper maintenance, `sudo`, install, Auto restoration, or release mutation.
- Reuse existing persistence and error-presentation patterns where they satisfy the requirement; do not create a general storage framework.
- Every behavioral change starts with a failing focused test and ends with an independently reviewable commit.
- Current screenshots and accessibility evidence are required before claiming visual polish. Historical evidence is context only.

## Selected architecture

Use a safety-first staged program:

1. Correct durable policy, preference, and helper-process behavior.
2. Make diagnostics, audit health, CLI help, and compiler gates truthful.
3. Repair exact-source UI evidence, review current captures, and apply only evidence-backed polish.

This order prevents presentation work from hiding unresolved safety or data-integrity defects. It also keeps the UI stage grounded in current screenshots instead of source inspection or historical captures.

## Stage 1: Safety and persistence

### 1. Agent-control policy loading

`AgentControlService` must distinguish active-lease persistence from policy persistence.

- A successful stored policy value remains authoritative.
- Absence of a stored policy retains the bootstrap default for first-run compatibility.
- Any error reading the policy file forces the in-memory policy to disabled for that daemon session.
- The failure must remain observable in daemon status or diagnostics using a typed persistence-health signal; it must not be represented as unsupported hardware or helper unreachability.
- A policy-read failure by itself must not trigger an SMC write or unnecessary Auto restoration. Existing active-lease or ownership recovery requirements remain unchanged.
- No agent prepare request may succeed while policy persistence health is unresolved.

### 2. Transactional policy mutation

Policy changes must not leave memory and durable state disagreeing.

- Enabling persists `true` before the in-memory policy becomes enabled.
- If enabling persistence fails, the policy remains disabled and the caller receives a typed failure.
- Disabling an active lease first completes the existing Auto restoration path. Durable `false` is then written before the successful disabled status is returned.
- If the durable disable write fails after Auto restoration, the active lease stays cleared, the prior persisted policy remains authoritative, and the caller receives an explicit persistence failure. The service must not report a successfully committed toggle.
- A successful save clears the policy-persistence health error.
- Restart tests must prove success and failure behavior from stored `true`, stored `false`, absent, corrupt, and unreadable policy states.

### 3. Application preference durability and recovery

`AppPreferencesStore` must adopt the small, proven recovery behavior used by `CurveProfileStore`, without introducing a shared abstraction.

- Before replacing a valid primary file, preserve it as `.bak` using same-directory atomic operations.
- On load, try the primary first and then a valid backup.
- A corrupt primary must never overwrite or delete a valid backup.
- Preserve corrupt bytes under a distinct quarantine suffix only when that can be done without endangering the primary or backup; quarantine failure must not block recovery from a valid backup.
- A recovered backup becomes the returned preference state. Rewriting the primary may be attempted, but failure must remain visible rather than destroying the recovered in-memory value.
- Directory permissions remain `0700`; primary, backup, temporary, and quarantine files remain `0600`.
- The nonthrowing `save` path is removed from production use. `AppModel` catches the throwing save, retains the user's in-memory selection, and exposes a clear “settings were not saved” state with a retry path. The state clears on the next successful save.
- Preference write failures must not affect fan-control ownership or invoke hardware operations.

### 4. Helper lifecycle subprocess reliability

`DaemonInstallProcessRunner.system` must not wait for process exit while bounded pipes are undrained.

- Drain stdout and stderr concurrently from process launch through termination.
- Bound captured bytes per stream. Additional bytes may be discarded after the bound; helper lifecycle correctness cannot depend on unbounded diagnostic output.
- Preserve the current exit-status mapping in `DaemonInstallService`.
- On stdin write failure, terminate the process, close all handles, wait for bounded cleanup, and return an error.
- Add a real-process regression whose child writes more than the platform pipe capacity to both stdout and stderr before exiting. The test must complete within a bounded timeout and prove both streams are handled without deadlock.

### Stage 1 acceptance

- Injected policy load/save failures prove fail-closed and transactional behavior.
- Preference tests cover valid primary, valid backup, corrupt primary plus valid backup, corrupt primary and backup, permission failure, and successful retry.
- The high-output lifecycle regression passes repeatedly.
- Focused suites and `make test-fast` pass.
- No privileged or hardware mutation command is executed.

## Stage 2: Diagnostics and operational truth

### 1. Unknown hardware reporting

Do not encode snapshot unavailability as a known negative hardware identity.

- Preserve the existing fallback snapshot only as an internal container where required for report construction.
- The readiness builder must consider `daemonSnapshotError` before interpreting `isAppleSilicon` or `isMacBookPro`.
- When snapshot acquisition fails, the supported-hardware check reports `unknown/unavailable` copy and recommends repairing the daemon path; it must not claim that the machine is unsupported.
- A successful snapshot from genuinely unsupported hardware retains the existing unsupported-hardware blocker and read-only guidance.
- JSON output remains machine-readable and keeps stable existing fields. If a new state field is necessary, update Codable, XPC bridges, JSON schemas, canonical examples, documentation, and compatibility tests together.

### 2. Audit persistence health

Audit logging remains observability, not an authorization prerequisite, but failures must be visible.

- `appendAudit` records the latest persistence error in bounded in-memory state and logs it through the existing Vifty logging surface.
- A later successful append clears the in-memory failure.
- Status and diagnose expose audit availability without overwriting a more important fan-control or restore error.
- An audit append failure must not falsely report that a fan mutation failed if the authoritative transaction and readback succeeded.
- Audit content, paths, permissions, maximum event count, and privacy boundaries remain unchanged.

### 3. CLI help

Add discoverable help without changing agent JSON command semantics.

- `viftyctl help`, `viftyctl --help`, and `viftyctl -h` print the same deterministic usage text and exit zero.
- The usage lists public agent commands and directs helper-maintenance operations to documented supervised flows; it must not advertise raw helper or SMC commands.
- Invalid commands continue returning usage exit code `64` and the structured error behavior already selected by `--json`.
- Help output is version-stable enough for snapshot testing but does not duplicate full integration documentation.

### 4. Warning-free test gate

- Remove the unnecessary `try` in `AgentControlServiceTests`.
- Compile test sources with warnings-as-errors in both fast and full verification paths.
- Keep the production warnings-as-errors build.
- CI continues to invoke `make verify-full`; no parallel compiler policy is introduced.

### Stage 2 acceptance

- Fixture tests distinguish supported, unsupported, and unavailable hardware.
- Audit failure and recovery are observable without changing fan mutation results.
- All three help forms exit zero; invalid commands retain exit `64`.
- A deliberately introduced test warning would fail the gate.
- `make verify` passes with schemas, examples, documentation contracts, bundle checks, and codesign structure intact.

## Stage 3: UI evidence and polish

### 1. Repair fixture readiness

Treat the 10-second and 60-second `READY_TIMEOUT` reports as the starting failure.

- Trace the exact-source fixture from preparation through window creation, observation bridge delivery, stability checks, capture, and final report publication.
- Determine whether the failure is deterministic application logic or a WindowServer/session precondition before changing production UI code.
- Add the smallest behavioral seam that makes readiness observable and testable.
- Add a regression that launches the inert fixture, receives a stable observation, and reaches capture-ready state within the documented bound.
- Preserve `modelStartSkipped=true`, inert hardware dependencies, and zero external fan/helper mutations.

### 2. Capture current evidence

Run the repository's declared matrix rather than inventing a new parallel harness.

- Capture required main-window widths, menu-bar popover, settings views, helper/error states, agent-control states, light mode, dark mode, and increased text scale.
- Collect accessibility evidence for labels, roles, values, actions, focus order, adjustable curve controls, keyboard operation, and meaningful status text.
- Each accepted row must bind to the exact source revision and build provenance.
- Failed or missing rows stay pending; do not promote a partial matrix as complete.

### 3. Evidence-backed polish pass

Only current evidence may create polish work.

- Fix clipping, truncation, low contrast, excessive dead space, inconsistent spacing, unclear hierarchy, misleading status copy, inaccessible controls, or broken focus behavior found in the accepted matrix.
- Prefer native SwiftUI layout, accessibility, and control behavior.
- Preserve the existing application information architecture unless evidence shows a concrete workflow failure.
- Each visual change receives a focused behavioral/layout test and before/after capture at affected matrix rows.

### 4. Simplify evidence maintenance

After the capture path is stable, convert repeated matrix cases to data-driven declarations where this reduces duplication without weakening provenance or acceptance rules.

- Do not simplify fan safety, release verification, evidence signing, provenance binding, or fail-closed review semantics.
- Do not introduce a new snapshot-testing dependency.
- Deletion is accepted only when the replacement tests prove equivalent required matrix coverage.

### Stage 3 acceptance

- Every required evidence-manifest row is accepted or explicitly documented as pending with a concrete blocker.
- No accepted capture shows clipping, unreadable contrast, inaccessible primary controls, misleading ownership state, or broken focus behavior.
- Accessibility evidence covers the complete supported interaction surface.
- `make verify-full` passes.
- A final read-only `viftyctl diagnose --json` is recorded; if the installed helper is unavailable, that limitation is reported rather than repaired automatically.

## Commit and review boundaries

Use small commits aligned with independently testable behavior:

1. Fail-closed policy loading.
2. Transactional policy mutation.
3. Recoverable app preferences and visible save failure.
4. Nonblocking lifecycle output handling.
5. Truthful unknown-hardware diagnostics.
6. Observable audit persistence health.
7. CLI help and warning-free test gates.
8. UI fixture readiness repair.
9. Current evidence capture.
10. Evidence-backed UI fixes.
11. Data-driven evidence-harness reduction, only if equivalence is proven.

Review Stage 1 before starting Stage 2, and Stage 2 before starting Stage 3. A failed gate stops the program without folding unrelated fixes into the failing commit.

## Verification and proof boundaries

Repository tests and inert fixtures can prove deterministic source behavior, schemas, packaging, and read-only diagnostics. They cannot prove physical fan compatibility, successful privileged helper replacement, notarization of new bytes, or subjective visual quality on every display.

Those claims require separate, explicitly authorized evidence:

- Supported-hardware Fixed/Curve/Auto compatibility requires supervised hardware validation and fresh full-set readback.
- Helper repair or install behavior requires an explicit privileged maintenance session.
- Release trust requires the existing Developer ID, notarization, stapling, checksum, Gatekeeper, governance, and public artifact workflow.
- Visual polish requires current accepted screenshots and human review after the fixture is repaired.

## Non-goals

- No new fan-control mode, agent policy feature, updater, telemetry persistence, analytics, network service, or third-party dependency.
- No rewrite of `AgentControlService`, `AppModel`, the release pipeline, or the UI evidence system.
- No weakening of output schemas for convenience.
- No automatic repair, install, fan control, cooling request, Auto restoration, release, or deployment during implementation.
