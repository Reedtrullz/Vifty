# Vifty Whole-App Review Remediation Implementation Plan

> **For agentic workers:** Execute this plan PR-by-PR with test-first implementation and two-stage review. Do not combine the safety-critical phases into one unreviewed change wave. Checkbox state is the execution record.

**Status:** The remediation is committed and pushed on `codex/vifty-whole-app-remediation` in PR #17 from baseline `21c2f9175dccb9226d6972574070bc21dbede2f0`. All code-changing work through `7e24e245ec202edaa01db283308bc5c3b38168c3` passed the exact local and GitHub full gates, and the later portable UI checkpoint passed exact-head CI. The owner skipped VoiceOver, so no VoiceOver behavior claim is made. On 17 July, the mistakenly team-shaped release-review policy was replaced with an explicit solo-maintainer contract. Protected `main` and the immutable `v*` tag ruleset are live; the `release` environment has no reviewer gate and disables administrator bypass, but its old protected-branch-only admission is now a declared blocker until this hardening merges and the environment is migrated to one custom `tag: v*` policy with no branch policy. The release-manifest candidate remains `null` until the separate v1.4.0 release-prep handoff. The exact public v1.3.2 hardware smoke is recorded separately and does not transfer to the remediation build.

**Goal:** Resolve every confirmed finding from the 14 July 2026 whole-app review while preserving Vifty's fail-closed fan-control boundary, exact-release evidence discipline, native macOS interaction model, and explicit separation between automated proof and supervised hardware proof.

**Starting point:** clean `main` at `21c2f9175dccb9226d6972574070bc21dbede2f0`; current public trusted artifact `v1.3.2` / build `7`; exact signed-artifact trust is proven, but exact-build installed-helper parity, explicit Auto restoration, and Fixed/Curve compatibility remain separate claims.

**Target architecture:** Curve resolution remains in `FanControlCoordinator`, but all physical mutations become resolved command batches sent to one daemon-owned `FanControlArbiter`. The arbiter reserves ownership before suspension, writes a durable journal before the first SMC mutation, uses only trusted native telemetry, applies through a transactional helper, and clears recovery state only after a fresh read confirms every expected fan is OS-managed. Manual control, agent leases, startup recovery, repair, termination, and uninstall all use that same transaction authority.

**Tech stack:** Swift 6, Swift Package Manager, SwiftUI, narrow AppKit interop, XCTest, NSXPC, launchd, shell release/evidence tooling, GitHub Actions, Developer ID signing/notarization, Homebrew Cask, and the existing `make verify` / `make verify-full` gates.

---

## Non-Negotiable Safety Invariants

1. While the daemon is live, every privileged fan write passes through one daemon-owned arbiter. Offline Auto-only maintenance may use the same journal/transaction layer only while holding the cross-process exclusive lock; `ViftyHelper`, app fallback, agent control, repair, and legacy XPC may not create parallel ownership lanes.
2. A durable expected-fan record exists before the first physical mutation.
3. Expected fan IDs may expand, never shrink, until fresh telemetry confirms the complete set is OS-managed.
4. The currently failing fan is included in rollback even when the helper throws before returning success.
5. Manual markers, leases, and journals are not cleared until the same restore transaction confirms the expected set.
6. Empty, partial, legacy, corrupt, missing, or synthesized telemetry cannot authorize writes or prove restoration.
7. Manual, agent, and recovery ownership are mutually exclusive. Restore preempts apply and blocks new control until recovery is resolved.
8. A new app facing an old control protocol fails closed and requests the Auto-aware helper repair flow. It does not silently fall back to legacy per-fan writes.
9. Diagnostics, fixture UI, tests, builds, review, repair preflight, and release verification remain hardware-read-only unless a later step is explicitly marked **human-supervised hardware evidence**.
10. `FanCurve.clamp()`, the SMC key allowlist, private `0700`/`0600` persistence, release TeamID enforcement, and the 30-minute default lease maximum remain authoritative.

## Global Execution Constraints

- Before long build/test loops, run `df -h /System/Volumes/Data`; stop below `30Gi` free.
- Use `swift test --scratch-path "$PWD/.build"`, `swift build --scratch-path "$PWD/.build"`, and `.derivedData` for any Xcode work.
- Never invoke helper install/repair, `ViftyHelper setFixed`, Fixed/Curve Apply, `restore-auto`, cooling leases, or real AppleSMC writes during automated implementation.
- Do not launch a locally built app while the installed app or manual marker reports active control; startup recovery can request Auto.
- Use deterministic fake SMC, fake stores, fake XPC, fake notification clients, and manual clocks for every failure/concurrency test.
- Use `apply_patch` for manual edits, preserve unrelated worktree state, and run `git diff --check` before every commit.
- Keep `v1.3.2` immutable. Choose the next version only after the safety cutover is merged and fully verified; do not retag an existing release.
- Keep exact artifact trust, installed app/helper parity, explicit Auto restoration, manual compatibility, and agent smoke as separate evidence rows.
- Log each merged PR and final evidence to the Vifty Obsidian project note and the current daily note.

## Completion Definition

The program is complete only when:

- no production path can mutate fan state outside the arbiter and journal;
- empty/partial snapshots and all injected partial-write failures retain recovery ownership;
- repair, termination, and uninstall refuse destructive teardown when Auto cannot be confirmed;
- UI previews and ownership text match the transaction that will run and the ownership the daemon confirms;
- release architecture, identities, permissions, provenance, version facts, and documentation are machine-checked;
- source-string tests have been reduced to true architecture/security boundaries;
- focused tests, `make test-fast`, warnings-as-errors build, `make verify`, and `make verify-full` pass;
- an exact signed candidate passes artifact, installed-helper, read-only review, and separately supervised hardware gates;
- no compatibility or support claim exceeds the evidence for that exact binary.

---

## Finding Coverage Matrix

| Review finding | Planned resolution |
| --- | --- |
| Empty/partial restore clears ownership | Tasks 1, 3, 4 |
| Non-transactional mode/target/`Ftst` writes | Task 2 |
| Manual/agent daemon race and per-fan global lease clear | Tasks 3-4 |
| Fail-open marker/lease persistence | Tasks 1, 3-4 |
| Synthesized SMC bounds authorize writes | Task 1 |
| Forced/Unknown readiness and direct-prepare ownership gaps | Task 4 |
| Ad-hoc daemon identity too weak | Task 4 |
| Unsafe repair, installer, shutdown, cask uninstall | Task 5 |
| Main-actor-blocking administrator prompt | Task 5 |
| Installer force-kill and unbounded `/tmp` fallback | Task 5 |
| Per-fan curve preview differs from applied command | Task 6 |
| Menu ownership headline inferred from editor state | Task 6 |
| Notification preferences hide authorization state | Task 6 |
| Profile dirty/overwrite ambiguity | Task 7 |
| Profile backup unused and decoded points unsorted | Task 7 |
| Selected temperature conflated with hottest | Task 7 |
| Smoothed plot presented as raw evidence | Task 7 |
| Curve handles not directly AX-adjustable | Task 7 |
| Settings vertical dead space and weak hierarchy | Task 7 |
| Stale README screenshot and incomplete appearance/AX QA | Task 8 |
| Thin arm64 artifact lacks cask/public constraint | Task 9 |
| Release credentials imported too early/write token too broad | Task 9 |
| Unsigned/unproven tag provenance | Task 9 |
| Artifact verifier omits app/daemon identity and architecture | Task 9 |
| Contradictory release/security/docs versions | Task 10 |
| Hardware issue form lacks truthful not-run option | Task 10 |
| Text-oriented workflow/community gates | Tasks 9-10 |
| Daemon/helper executable logic not behavior-testable | Tasks 3, 5, 11 |
| `AppModel`, `FanControlPanel`, and tests oversized | Task 11 |
| Real sleeps and polling flake risk | Task 11 |
| CLI signal forwarding ignores process groups | Task 12 |
| Path-casing and monotonic build-number gaps | Tasks 9-10 |

---

## Dependency And PR Map

```text
PR 1  Trusted telemetry + transaction models
  └─ PR 2  Transactional LocalFanHelperClient
       └─ PR 3  Durable journal + daemon FanControlArbiter
            └─ PR 4  Agent/app/XPC/readiness cutover
                 └─ PR 5  Safe repair/termination/uninstall

PR 6  Operator truth + notifications  ─┐
PR 7  Profiles/telemetry/AX/Settings  ├─ PR 8  Fixture-backed visual/AX evidence
PR 9  Release-manifest foundation + distribution hardening  ┤
PR 10 Manifest-driven docs and forms                         ┘

PR 11 AppModel/test/panel decomposition (after behavior is locked)
PR 12 CLI lifecycle hardening
PR 13 Exact candidate, installed proof, supervised hardware proof, release
```

PRs 6, 7, and the non-teardown portions of PRs 9-10 may run beside the critical safety lane after Task 0. Ownership copy in PR 6 must not merge before PR 4 exposes authoritative daemon ownership. Task 7D follows Task 6C because both change the Notifications Settings tab. Cask uninstall in PR 9 must not merge before PR 5 provides the safe lifecycle script. PR 4 disables the old repair/install actions and shows blocking protocol-mismatch guidance until PR 5 lands; it may not route users into the bootout-first repair flow.

---

## Task 0: Freeze The Baseline And Add The Safety Contract

**Files:**

- Create: `docs/superpowers/specs/2026-07-14-fan-control-transaction-safety.md`
- Create: `Tests/ViftyCoreTests/WholeAppReviewFindingInventoryTests.swift`
- Modify: `docs/release-status.md` only if a non-claim needs clarification; do not change release status otherwise.

**Steps:**

- [ ] Record branch, full SHA, installed version/build, public artifact SHA, helper parity status, manual-control status, and current free space. Record values only; do not restore or repair.
- [ ] Write the ten invariants above as the control-transaction specification, including state transitions and crash points.
- [ ] Add an inventory test or machine-readable fixture mapping every finding in the coverage matrix to its owning task/test suite, preventing silent scope loss during the multi-PR program.
- [ ] Run the existing focused baseline and capture exact counts:

```bash
swift test --scratch-path "$PWD/.build" --filter FanControlCoordinatorTests
swift test --scratch-path "$PWD/.build" --filter LocalFanHelperClientTests
swift test --scratch-path "$PWD/.build" --filter AgentControlServiceTests
swift test --scratch-path "$PWD/.build" --filter ViftyDaemonClientTests
make verify SWIFT_BUILD_PATH="$PWD/.build"
```

- [ ] Confirm the spec/inventory commit contains no production behavior change.

**Commit:** `docs: define fan control transaction safety`

## Task 1: Separate Display Telemetry From Privileged Write Eligibility

**Files:**

- Modify: `Sources/ViftyCore/Models.swift`
- Modify: `Sources/ViftyCore/FanInfoReader.swift`
- Modify: `Sources/ViftyCore/AgentControlPolicy.swift`
- Modify: `Sources/ViftyCore/ViftyDaemonProtocol.swift`
- Modify: `Sources/ViftyCore/ViftyCtlReadinessReport.swift`
- Modify: `Sources/ViftyDaemon/main.swift`
- Modify: `Sources/ViftyHelper/main.swift`
- Test: `FanInfoReaderTests`, `XPCSnapshotCodingTests`, `AgentControlPolicyTests`, `ViftyCtlRunnerTests`

**Interfaces:**

```swift
public enum FanControlIneligibilityReason: String, Codable, Sendable {
    case legacyUnspecified, missingFanCount, missingMinimumRPM, missingMaximumRPM
    case missingModeKey, missingTargetKey, invalidRPMRange, invalidFanID
}

public struct FanControlEligibility: Equatable, Codable, Sendable {
    public let canApplyFixedRPM: Bool
    public let canRestoreOSManagedMode: Bool
    public let reasons: [FanControlIneligibilityReason]
}
```

- [ ] RED: prove missing min/max, fan count, invalid ID, and invalid range remain displayable but cannot authorize Fixed RPM.
- [ ] RED: prove a trusted fan ID/mode key can still perform mode-only Auto recovery when the target key is missing; target reset is best-effort hygiene after confirmed OS ownership. Missing/invalid mode telemetry blocks recovery.
- [ ] RED: prove legacy XPC snapshots without eligibility decode as `.legacyUnspecified`, never eligible.
- [ ] Add eligibility/provenance to `Fan` and XPC coding. Preserve synthesized values only for display continuity.
- [ ] Make daemon resolution, policy, and readiness require `canApplyFixedRPM`; make recovery require the separate `canRestoreOSManagedMode`. Ignore caller-provided bounds for authorization.
- [ ] Remove `ViftyHelper setFixed/auto` from normal use, or make them explicit refusals that point to daemon-owned supervised tooling. They may not construct write-eligible fans from CLI bounds.
- [ ] Add protocol/capability version `2`. New clients facing `<2` keep read-only telemetry but fail closed for control.

**Focused gate:**

```bash
swift test --scratch-path "$PWD/.build" --filter FanInfoReaderTests
swift test --scratch-path "$PWD/.build" --filter XPCSnapshotCodingTests
swift test --scratch-path "$PWD/.build" --filter AgentControlPolicyTests
```

**Commit:** `fix: separate fan telemetry from write eligibility`

## Task 2: Make Every Low-Level Fan Mutation Transactional

**Files:**

- Move: `Sources/ViftyCore/LocalFanHelperClient.swift` to internal target `Sources/ViftyFanControlSafety/LocalFanHelperClient.swift`.
- Modify: `Sources/ViftyCore/SMCClient.swift` only for typed preflight/readback helpers; do not broaden the allowlist.
- Create: `Sources/ViftyCore/FanMutationReceipt.swift` for immutable cross-target result values only.
- Modify: `Tests/ViftyCoreTests/LocalFanHelperClientTests.swift`

**Interface:**

```swift
public struct FanMutationReceipt: Equatable, Sendable {
    public let fanID: Int
    public let requestedMode: FanHardwareMode
    public let observedMode: FanHardwareMode?
    public let observedTargetRPM: Int?
    public let forceTestDisabled: Bool
    public let recoveryConfirmed: Bool
    public let warnings: [String]
}
```

- [ ] RED: preflight failure occurs before the first write.
- [ ] RED: target failure after Forced attempts Auto, target hygiene, and `Ftst=0`, including the failing fan.
- [ ] RED: unlock timeout and cleanup failure return `recoveryUnconfirmed` with both primary and cleanup errors.
- [ ] RED: readback mismatch fails the operation; System-managed mode counts as safe OS ownership but not literal mode-0 evidence.
- [ ] Inject clock/sleeper so retry tests use no `Thread.sleep` or wall time.
- [ ] Pre-read mode, target, optional `Ftst`, types, sizes, and encoded bytes before mutation. After any first write, cleanup attempts continue independently even when one cleanup step fails.
- [ ] Return receipts from Fixed and restore operations; never equate a successful write syscall with confirmed state.

**Focused gate:**

```bash
swift test --scratch-path "$PWD/.build" --filter LocalFanHelperClientTests
swift test --scratch-path "$PWD/.build" --filter SMCClientWritePolicyTests
```

**Commit:** `fix: make fan mutations transactional`

## Task 3: Add A Durable Journal And One Daemon FanControlArbiter

**Files:**

- Create: `Sources/ViftyCore/FanControlTransactionModels.swift` for immutable request/status/result values only.
- Create internal target: `Sources/ViftyFanControlSafety/FanControlJournalStore.swift`
- Create internal target: `Sources/ViftyFanControlSafety/FanControlArbiter.swift`
- Create internal target: `Sources/ViftyFanControlSafety/PrivilegedFanControlHardware.swift`
- Create internal target: `Sources/ViftyFanControlSafety/FanControlExclusiveLock.swift`
- Move the transactional `LocalFanHelperClient` implementation into `ViftyFanControlSafety`.
- Create: `Sources/ViftyDaemonSupport/DaemonService.swift`
- Modify: `Package.swift` so daemon/offline-maintenance code imports internal `ViftyFanControlSafety`; `ViftyDaemon` also depends on importable `ViftyDaemonSupport`; tests import both without exposing privileged implementations through public `ViftyCore`.
- Reduce: `Sources/ViftyDaemon/main.swift` to listener, identity extraction, startup recovery, and signal adapter.
- Create tests: `FanControlJournalStoreTests`, `FanControlArbiterTests`, `DaemonServiceTests`

**Journal model:**

```swift
public enum FanControlOwner: Codable, Sendable {
    case manual(sessionID: String)
    case agent(leaseID: String)
    case recovery
}

public enum FanControlPhase: String, Codable, Sendable {
    case prepared, applying, active, restoring, restorePending
}

public struct FanControlJournalRecord: Codable, Sendable {
    public let schemaVersion: Int
    public let transactionID: String
    public var owner: FanControlOwner
    public var phase: FanControlPhase
    public var expectedFanIDs: [Int]
    public var targetRPMByFanID: [Int: Int]
    public var appliedFanIDs: [Int]
    public let createdAt: Date
    public var updatedAt: Date
    public var lastErrorCode: String?
}
```

The shown journal model is conceptual. Define a stable tagged JSON wire format with explicit owner `type` plus fields, custom decoding, golden fixtures, unknown-version refusal, and a rule that older code never overwrites a newer schema. Do not persist synthesized `Codable` output for associated-value enums.

**Arbiter surface:**

```swift
actor FanControlArbiter {
    func status() -> FanControlOwnershipStatus
    func applyManual(_ request: ManualFanControlRequest) throws -> FanControlTransactionResult
    func applyAgent(_ request: AgentFanControlRequest) throws -> FanControlTransactionResult
    func restoreAuto(_ request: AutoRestoreRequest) throws -> FanControlTransactionResult
    func recoverOnStartup() -> FanControlTransactionResult
}
```

These methods and privileged protocols are internal implementation seams, not frozen public API.

- [ ] Journal RED tests: atomic round-trip, `0700`/`0600`, fsync failure, corrupt data, monotonic expected set, clear failure, old lease migration, and no `try?` suppression.
- [ ] Harden storage against filesystem substitution: require root ownership, regular files/directories, `O_NOFOLLOW`/`lstat`, safe link counts, same-directory temporary replacement, and file plus directory synchronization. RED-test symlink, hard-link, wrong-owner, wrong-mode, and unsafe pre-existing path cases.
- [ ] Arbiter RED tests: manual/agent mutual exclusion, operation reservation before suspension, Auto preemption between fans, failing-fan rollback, empty/partial snapshot refusal, Forced/Unknown readback refusal, System-managed acceptance, idempotent transaction IDs, and recovery persistence.
- [ ] Use a root-owned `fcntl` single-writer lock held for the daemon lifetime and acquired by offline maintenance before any SMC access. RED-test simultaneous acquisition, process-exit/stale-lock recovery, launchd restart while maintenance owns the lock, unsafe lock-file paths, and zero writes without ownership.
- [ ] Persist `.prepared` with the complete expected set before the first mutation. Union attempted IDs before each fan and never shrink the record.
- [ ] Keep the privileged hardware transaction synchronous inside the arbiter to avoid actor reentrancy during physical writes. Reserve an operation token before any await and revalidate its generation after all external suspension points.
- [ ] Add a thread-safe restore signal checked between fans so Auto can preempt a bounded apply without allowing another owner. The XPC adapter raises it synchronously before enqueueing the actor restore call, so actor serialization cannot hide the preemption request.
- [ ] On apply failure, restore every expected fan, take a fresh snapshot, and clear only after the complete expected set is present and OS-managed.
- [ ] Corrupt/unknown journal state serves read-only status and may retry only reload/status publication. It must not mutate hardware unless expected IDs are reconstructed from a valid durable v2 lease/record or a human explicitly approves `restore all trusted fans` recovery.
- [ ] Store the journal under `/Library/Application Support/Vifty/FanControl/` with private ownership/permissions and atomic file plus directory synchronization.

**Focused gate:**

```bash
swift test --scratch-path "$PWD/.build" --filter FanControlJournalStoreTests
swift test --scratch-path "$PWD/.build" --filter FanControlArbiterTests
swift test --scratch-path "$PWD/.build" --filter DaemonServiceTests
```

**Commits:**

1. `feat: add durable fan control journal`
2. `feat: add daemon fan control arbiter`
3. `refactor: extract testable daemon service`

These commits are not release candidates until Task 4 cuts every write route over atomically.

## Task 4: Cut App, Agent, XPC, Recovery, And Readiness Over To The Arbiter

**Files:**

- Modify: `Sources/ViftyCore/AgentControlService.swift`
- Modify: `Sources/ViftyCore/AgentControlModels.swift`
- Modify: `Sources/ViftyCore/AgentControlStore.swift`
- Modify: `Sources/ViftyCore/ViftyDaemonProtocol.swift`
- Modify: `Sources/ViftyCore/ViftyDaemonClient.swift`
- Modify: `Sources/ViftyCore/RealMacHardwareService.swift`
- Modify: `Sources/ViftyCore/HardwareService.swift`
- Modify: `Sources/ViftyCore/ViftyCtlReadinessReport.swift`
- Modify: `Sources/ViftyCore/ViftyCtlRunner.swift`
- Modify: `Sources/Vifty/AppModel.swift`
- Modify: XPC coding, agent JSON schemas, and canonical examples.
- Test: agent, coordinator, daemon-client, XPC, readiness, runner, and AppModel suites.

**New XPC operations:**

```swift
func fanControlCapabilities(reply: ...)
func fanControlStatus(reply: ...)
func applyManual(_ request: NSDictionary, reply: ...)
func restoreAllAuto(_ request: NSDictionary, reply: ...)
```

Curve resolution remains app/core-side; `applyManual` carries only resolved fixed-RPM commands, the session ID, and reason.

- [ ] RED: agent prepare failure attempts restore for all expected IDs, including the currently failing fan, and retains `restorePending` after any rollback failure.
- [ ] RED: lease-save failure after physical application restores the whole set; empty/partial restoration cannot clear the lease.
- [ ] RED: concurrent manual and agent requests produce one owner and no interleaved writes.
- [ ] RED: legacy per-fan Auto restores the entire journal set and cannot clear a global lease after one fan.
- [ ] RED: selecting a draft does not claim manual ownership; only a confirmed transaction does.
- [ ] RED: old/missing ownership status is `.unknownLegacy`, blocks control, and preserves telemetry.
- [ ] Create the lease ID before mutation, let the arbiter journal/apply/confirm it, save the lease, then mark the journal active. Remove public lease-clearing paths that do not restore hardware.
- [ ] Replace app per-fan writes with one resolved batch. Make app Auto one daemon transaction, not fan restore followed by independent lease clearing.
- [ ] Carry `expectedFanIDs` separately from the resolved mutation batch. Coordinator optimization may omit unchanged fans, but ownership and the journal always cover the complete session domain; a partial/no-op batch cannot claim ownership without confirming that full set.
- [ ] Remove the root local-write fallback from `RealMacHardwareService` for app/ctl paths. Daemon failure must never construct `LocalFanHelperClient`, even at EUID 0. Only the daemon arbiter or Task 5's exclusively locked offline maintenance path may do so. Add a regression proving the fallback closure is never called.
- [ ] Make daemon ownership authoritative. The user-home marker becomes legacy recovery evidence and is cleared only after daemon-confirmed OS ownership.
- [ ] Add ownership status fields: owner, phase, transaction ID, expected IDs, confirmed OS-managed IDs, recovery pending, and bounded error code.
- [ ] Make readiness block Unknown/Forced-without-owner, corrupt recovery, protocol mismatch, untrusted telemetry, and ownership inconsistency.
- [ ] Harden ad-hoc daemon authorization with a persisted root-owned installation UID plus audit-token EUID and exact signing/executable identity, or disable ad-hoc writes unless an explicit development allowlist exists. Never dynamically trust the current console user under fast user switching.
- [ ] Startup loads journal/lease before write-capable requests, attempts bounded recovery, serves read-only status on failure, and retries without a launchd crash loop.
- [ ] RED: startup recovery, a legacy marker, protocol mismatch, or unknown ownership blocks `applyStartupModePreferenceIfNeeded()`; non-Auto startup preference remains a pending draft until authoritative macOS ownership is confirmed.
- [ ] Specify and test restore persistence order: journal `.restoring` → hardware confirmation → durable lease clear → durable journal clear → legacy marker clear. Lease-clear failure retains `restorePending` and blocks new control.
- [ ] Add crash-reconciliation tests between every transition, including lease-without-journal, journal-active-without-lease, hardware-confirmed/lease-not-cleared, and journal-cleared/legacy-marker-present.
- [ ] New client + old daemon fails closed with protocol-mismatch guidance and disables repair/install until Task 5's lifecycle contract is present. No silent legacy write fallback.

**Focused gate:**

```bash
swift test --scratch-path "$PWD/.build" --filter AgentControlServiceTests
swift test --scratch-path "$PWD/.build" --filter FanControlCoordinatorTests
swift test --scratch-path "$PWD/.build" --filter ViftyDaemonClientTests
swift test --scratch-path "$PWD/.build" --filter ViftyCtlRunnerTests
swift test --scratch-path "$PWD/.build" --filter AppModelTests
make test-fast SWIFT_BUILD_PATH="$PWD/.build"
```

**Commits:**

1. `fix: route agent leases through fan control arbiter`
2. `feat: add transactional fan control XPC`
3. `fix: make daemon ownership authoritative`
4. `fix: block unsafe ownership in readiness`

Do not merge a subset that leaves both old and new write authorities active.

## Task 5: Make Repair, Termination, Installation, And Uninstall Auto-Aware

**Files:**

- Create: `Sources/ViftyDaemonSupport/DaemonLifecycleCoordinator.swift`
- Create: `Sources/ViftyHelperSupport/HelperCommandRunner.swift`
- Create: `Sources/Vifty/DaemonInstallService.swift`
- Create: `scripts/vifty-helper-lifecycle.sh`
- Create: `scripts/uninstall-vifty.sh`
- Modify: `Sources/ViftyDaemon/main.swift`
- Modify: `Sources/Vifty/DaemonInstaller.swift`
- Modify: `Sources/Vifty/ControlSessionPresentation.swift`
- Modify: `Sources/Vifty/ContentView.swift`
- Modify: `scripts/repair-vifty-helper.sh`
- Modify: `scripts/install-vifty.sh`
- Modify: `Casks/vifty.rb`
- Modify: `Sources/ViftyHelper/main.swift` into a wiring-only entrypoint.
- Modify: `Package.swift`, `Makefile`, and app bundling resources so daemon/helper support targets are importable by tests without changing signed executable names or identifiers.
- Test: `DaemonInstallerTests`, new `DaemonLifecycleCoordinatorTests`, `HelperCommandRunnerTests`, lifecycle shell fixture tests, cask/release metadata tests.

**Lifecycle contract:**

```text
inspect ownership → quiesce new writes → restore complete expected set
→ fresh mode confirmation → bootout/replace/delete → bootstrap if repairing
```

```swift
public struct HelperMaintenanceReport: Codable, Equatable, Sendable {
    public let safeToStop: Bool
    public let quiesced: Bool
    public let restoreAttempted: Bool
    public let restoreSucceeded: Bool
    public let fanResults: [HelperMaintenanceFanResult]
    public let blockers: [HelperMaintenanceBlocker]
}
```

- [ ] RED: repair/uninstall with manual or agent ownership cannot boot out until complete OS ownership is confirmed.
- [ ] RED: daemon unreachable, partial telemetry, restore failure, and unknown ownership block destructive teardown and emit recovery/reboot guidance.
- [ ] RED: successful repair orders quiesce/restore/confirm before `launchctl bootout` and preserves root ownership/modes.
- [ ] RED: app termination blocked by failed Auto makes `scripts/install-vifty.sh` abort; it never falls through to `pkill`.
- [ ] Add a daemon quiesce operation that rejects new control, completes or restores the journaled set, and returns a machine-readable teardown token only after confirmation.
- [ ] Bind that token to boot/session ID, journal generation, expected fan IDs, helper hash, and quiesced state; make it short-lived and single-use. Any new control or generation change invalidates it.
- [ ] Add `ViftyHelper prepareMaintenance --json` as an Auto-only recovery tool using fresh telemetry and the same journal/transaction primitives. It may run only when the daemon service is absent or already stopped; it may never become a parallel writer beside a live legacy daemon and may never accept target RPMs.
- [ ] For a live protocol-v1 daemon, the actual legacy gate is: no active agent lease, complete fresh trusted fan telemetry, and every fan physically Auto/System-managed. Protocol v1 cannot authoritatively prove “no manual owner”; the user marker is caution evidence only. Anything less blocks repair and directs the user to the installed version's Restore Auto or reboot/recovery.
- [ ] Handle SIGTERM through a dispatch signal source: quiesce and request bounded verified restore. Voluntary termination exits only when `safeToStop=true`; otherwise remain quiesced, persist/expose recovery, and allow further restore attempts. Document SIGKILL and system shutdown as outside this voluntary guarantee.
- [ ] Make UI recovery ordering ownership-first: when manual/recovery state exists, Restore Auto remains the primary action; Repair is enabled only after safe teardown preconditions or as an explicit blocked recovery path.
- [ ] Move `Process.run`/authorization waiting off `@MainActor` into `DaemonInstallService`; publish only small state changes on the main actor. Polling and session-expiry timers must continue while the prompt is open.
- [ ] Replace duplicated UI/shell repair implementations with the shared lifecycle script/contract. Bundle it into the app and test its exact resource path.
- [ ] Wire Homebrew uninstall to the safe script, unregister `SMAppService`, verify launchd/Login Items registration is gone, and remove daemon plist, privileged executable, and logs only after the preflight token. Preserve `AgentControl`, `FanControl` journal/lock, and other recovery state whenever Auto or durable cleanup is unconfirmed; document cleanup versus preservation rules. Keep `zap` for user preferences separately.
- [ ] Replace `/tmp/vifty-install-swiftpm-$$` and README persistent scratch instructions with repository `.build` or one `mktemp -d` cleaned by `trap`. Add behavior tests for success, retry failure, and signal cleanup; never remove a caller-provided `SWIFT_BUILD_PATH`.
- [ ] Refuse downgrade/bootstrap of a protocol-v1 helper while any v2 journal/lease exists. Allow downgrade only after verified full Auto and durable journal clearance; test both outcomes.
- [ ] Add dry-run fixture modes that record commands and never invoke `sudo`, `launchctl`, helper binaries, or AppleSMC in tests.

**Focused gate:**

```bash
swift test --scratch-path "$PWD/.build" --filter DaemonLifecycleCoordinatorTests
swift test --scratch-path "$PWD/.build" --filter HelperCommandRunnerTests
swift test --scratch-path "$PWD/.build" --filter DaemonInstallerTests
/bin/bash -n scripts/*.sh
swift test --scratch-path "$PWD/.build" --filter ReleaseMetadataScriptTests
```

**Commits:**

1. `feat: add safe helper lifecycle contract`
2. `fix: keep helper authorization off main actor`
3. `fix: make install and uninstall restore-aware`

## Task 6: Make Operator Preview, Ownership, And Notifications Truthful

### 6A. Share One Per-Fan Curve Target Resolver

**Files:**

- Create: `Sources/ViftyCore/FanCurveTargetResolver.swift`
- Create: `Tests/ViftyCoreTests/FanCurveTargetResolverTests.swift`
- Modify: `Sources/ViftyCore/HardwareService.swift`
- Modify: `Sources/Vifty/AppModel.swift`
- Modify: coordinator and AppModel tests.

```swift
public enum FanCurveTargetResolver {
    public static func effectiveCurve(
        baseCurve: FanCurve,
        fanID: Int,
        overrides: [FanCurveOverride]
    ) -> FanCurve

    public static func targetRPM(
        baseCurve: FanCurve,
        fan: Fan,
        temperature: Double,
        overrides: [FanCurveOverride]
    ) -> Int
}
```

- [ ] RED: divergent right-fan override produces the same preview and fake-hardware command.
- [ ] RED: disabled/missing/malformed override follows the same base fallback as apply.
- [ ] Preserve `FanCurve.clamp()` as the only clamp authority.
- [ ] Replace both coordinator-private and AppModel preview calculations with this resolver.

**Commit:** `fix: unify per-fan curve target resolution`

### 6B. Separate Editor Phase From Confirmed Ownership

**Files:**

- Modify: `Sources/Vifty/ControlSessionPresentation.swift`
- Modify: `Sources/Vifty/MenuBarPanelPresentation.swift`
- Modify: `Sources/Vifty/AppModel.swift`
- Modify focused presentation tests.

- [ ] Consume Task 4's `FanControlOwnershipStatus`; do not create a second UI-only ownership authority.
- [ ] Keep draft states (`pending`, `applying`, `failed`, `applied`) separate from confirmed owner (`macOS`, `viftyManual`, `agent`, `recovery`, `mixedOrUnknown`).
- [ ] RED matrix: pending/failed draft while Auto says macOS; pending edits during confirmed manual says Vifty; agent says agent; mixed/unknown says confirmation required; Restore Auto appears only for confirmed non-macOS/recovery ownership.
- [ ] Derive menu headline, owner row, attention state, and Restore Auto visibility from confirmed ownership.

**Commit:** `fix: present confirmed fan ownership`

### 6C. Expose Notification Authorization

**Files:**

- Create: `Sources/Vifty/NotificationAuthorization.swift`
- Create: `Tests/ViftyCoreTests/NotificationAuthorizationTests.swift`
- Modify: `Sources/Vifty/LocalNotifications.swift`
- Modify: `Sources/Vifty/AppModel.swift`
- Modify: `Sources/Vifty/SettingsNotificationsView.swift`

```swift
enum LocalNotificationAuthorization: Equatable {
    case checking, notDetermined, authorized, denied, unavailable
}
```

- [ ] Inject a `LocalNotificationCenterClient` for status, request, delivery, test notification, and settings opening.
- [ ] RED: first explicit opt-in requests once; denial preserves the selected event preferences while visibly blocking delivery; authorized test delivery does not mutate event cooldown history; racing toggles do not duplicate prompts.
- [ ] Show authorization state, Open Notification Settings when denied, and Test Notification only when authorized.
- [ ] Keep delivery-time fallback for upgraded installations without hiding denial.

**Commit:** `feat: expose notification authorization`

**Task gate:**

```bash
swift test --scratch-path "$PWD/.build" --filter FanCurveTargetResolverTests
swift test --scratch-path "$PWD/.build" --filter MenuBarPanelPresentationTests
swift test --scratch-path "$PWD/.build" --filter NotificationAuthorizationTests
swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors
```

## Task 7: Resolve Profiles, Temperature Semantics, Evidence Charts, Accessibility, And Settings

### 7A. Add A Saved/Edited/Unsaved Profile Lifecycle And Real Backup Recovery

**Files:**

- Create: `Sources/Vifty/CurveProfilePresentation.swift`
- Create: `Tests/ViftyCoreTests/CurveProfilePresentationTests.swift`
- Modify: `Sources/Vifty/CurveProfileToolbar.swift`
- Modify: `Sources/Vifty/AppModel.swift`
- Modify: `Sources/ViftyCore/CurveProfileStore.swift`
- Modify: `Sources/ViftyCore/Models.swift`
- Modify: profile/store tests.

- [ ] Define normalized `CurveProfileDraftSnapshot`, `CurveProfileEditState`, and `CurveProfileSaveResult`.
- [ ] RED: point/sensor/override edits mark Edited; reverting returns Saved; override order does not create false edits; Update preserves UUID; colliding Save As requires confirmation.
- [ ] RED: corrupt or missing primary loads a valid `.bak`, reports recovery, and does not silently return an empty profile list.
- [ ] RED: corrupt primary cannot overwrite a valid backup; sibling-temp backup replacement preserves the old backup on copy, permission, rename, or sync failure.
- [ ] Make custom decoding call the same normalization/sorting initializer used by new profiles.
- [ ] Surface recovery through AppModel without immediately persisting an empty or recovered state; rewriting requires explicit user save/recovery confirmation.
- [ ] Show `Name — Edited`, separate Update from Save As, and require overwrite confirmation.

**Commits:**

1. `fix: recover and normalize curve profiles`
2. `feat: make curve profile edits explicit`

### 7B. Distinguish Curve Temperature From Highest Temperature

**Files:**

- Create: `Sources/Vifty/TemperatureSensorSelection.swift`
- Create: `Tests/ViftyCoreTests/TemperatureSensorSelectionTests.swift`
- Modify: `AppModel`, `TelemetryHistory`, `TelemetryEvidencePanel`, `FanControlPanel`, and menu presentation.

- [ ] Define explicit roles: `curveSensor`, `automaticCPU`, and `highestFallback`.
- [ ] RED: selected sensor at 61 C plus another at 92 C displays 61 C as the curve metric while highest-temperature safety still evaluates 92 C.
- [ ] Label menu/history/control values with exact role or sensor name; retain explicitly named Highest telemetry.
- [ ] Preserve machine-readable evidence strings unless their schema is intentionally versioned.

**Commit:** `fix: distinguish curve and highest temperatures`

### 7C. Plot Raw Evidence And Make Curve Points Adjustable

**Files:**

- Create: `Sources/Vifty/SparklineGeometry.swift`
- Create: `Sources/Vifty/CurvePointAdjustment.swift`
- Create tests for both.
- Modify: `TelemetryEvidencePanel`, `FanCurveChartEditor`, and `FanControlPanel`.

- [ ] RED: `[0, 0, 100, 0, 0]` retains its spike; plotted first/latest/range match raw labels.
- [ ] Remove disguised moving-average geometry. If smoothing remains as an option, label it explicitly and keep the raw endpoint visible.
- [ ] Add pure 1 C / 50 RPM adjustment policy with clamping.
- [ ] Give each visible point an accessibility representation with independent adjustable temperature and RPM controls; retain exact controls and name them `Exact point controls`.
- [ ] RED: accessibility increments only mark the draft pending and issue zero fake hardware commands.

**Commits:**

1. `fix: render raw telemetry evidence`
2. `fix: make curve points accessibility adjustable`

### 7D. Rebuild Settings As Top-Aligned Native Forms

**Files:**

- Create: `Sources/Vifty/SettingsPane.swift`
- Modify: `ViftySettingsView` and all `Settings*View.swift` files.
- Modify: `SettingsSceneSourceTests` only for scene/security boundaries.

- [ ] Use native `Form`/`Section` layouts with top-leading alignment and scrolling for taller tabs.
- [ ] Organize General (Startup/Login), Menu Bar (Display/Custom Fields/Codex Usage), Notifications (Authorization/Events), and Agent Workflows (Commands/Agent Rule).
- [ ] Use a tighter common window baseline and verify long text, keyboard traversal, light/dark, Increase Contrast, Reduce Transparency, and larger accessibility text.
- [ ] Remove nested material where it obscures hierarchy; use material for primary chrome/session surfaces only.
- [ ] Give Apply, Restore, Repair, and Copy distinct semantic symbols. Disable the toggle for the last enabled custom menu field with help text explaining that at least one field is required; never accept the click and silently re-enable it. Add a focused presentation test for the last-field state.

**Commit:** `polish: align settings with macOS forms`

**Task gate:**

```bash
swift test --scratch-path "$PWD/.build" --filter CurveProfile
swift test --scratch-path "$PWD/.build" --filter TemperatureSensorSelectionTests
swift test --scratch-path "$PWD/.build" --filter SparklineGeometryTests
swift test --scratch-path "$PWD/.build" --filter CurvePointAdjustmentTests
swift test --scratch-path "$PWD/.build" --filter SettingsSceneSourceTests
make test-fast SWIFT_BUILD_PATH="$PWD/.build"
```

## Task 8: Add Hardware-Free Visual And Accessibility Evidence

**Files:**

- Create: `Sources/Vifty/ViftyReviewFixture.swift` under `#if DEBUG`.
- Create: `Tests/ViftyCoreTests/ViftyReviewFixtureTests.swift`.
- Create: `scripts/run-ui-review-fixture.sh`.
- Create: `docs/ui-review/README.md` and a concise evidence manifest.
- Modify: `Sources/Vifty/ViftyApp.swift`, `README.md`, and `docs/images/vifty-screenshot.png`.

- [ ] Add `--ui-review-fixture <state>` that skips `model.start()`, injects fake hardware/daemon/power/notification clients, records attempted commands, and fails the fixture if any real XPC/helper/SMC path is constructed.
- [ ] Prove the fixture switch and strings are absent from the release binary.
- [ ] Fixtures: healthy Auto, divergent per-fan Curve draft, active manual, recovery/mixed ownership, helper blocked, notification denied, edited profile, selected-vs-highest temperature, and raw spike telemetry.
- [ ] Visual matrix: 780x480, 1180x820, 1280x720, wide workbench; light/dark; every Settings tab; menu popover; compact scrolling; Reduce Transparency; Increase Contrast.
- [ ] AX matrix: confirmed-owner headline, correct per-fan target, six adjustable point controls, sensor selected trait/value, explicit temperature role, notification actions, logical Settings traversal, and no duplicate chart elements.
- [ ] Include larger accessibility text and vertical-scroll reachability for every Settings tab plus compact main-window layouts.
- [ ] Make `scripts/run-ui-review-fixture.sh --verify-matrix` exit nonzero unless every required fixture/window/appearance/AX cell passes, attempted hardware commands are zero, no real XPC/helper/SMC client was constructed, and the release binary contains no fixture flag/string. Record matrix results and checksums in the evidence manifest.
- [ ] Refresh the README hero from a deterministic healthy fixture. Commit the public screenshot and evidence manifest, not an unbounded screenshot dump.

**Commits:**

1. `test: add hardware-free UI review fixtures`
2. `docs: refresh Vifty interface evidence`

## Task 9: Harden Distribution, Signing Identities, Workflow Permissions, And Provenance

### 9.0. Land The Release-Manifest Foundation First

Before 9A, create `.github/release-manifest.json`, `docs/schemas/release-manifest.schema.json`, and `scripts/check-release-manifest.sh` using Task 10's schema/shape. Set the next candidate's non-null `signedTagsRequiredFromVersion` before any publication workflow is enabled; publication fails while it is unset. Task 10 then consumes this foundation for prose/templates rather than creating it later.

### 9A. Make The Architecture Contract Explicit

**Files:**

- Modify: `Casks/vifty.rb`
- Modify: `scripts/verify-release-artifact.sh`
- Modify: release-summary schema/tests and compatibility docs.

- [ ] Decision gate: default to declaring the existing product arm64-only now. Add the cask architecture constraint and update Intel compatibility from “diagnose can safe-block” to “binary cannot execute.”
- [ ] Treat a future universal binary as a separate feature requiring an Intel build runner, launch/read-only diagnostic proof, and unsupported-hardware safe-block evidence; do not imply Rosetta proves native Intel support.
- [ ] Add `lipo -archs` checks for app, helper, daemon, and ctl. All binaries must match the manifest's exact architecture set.
- [ ] Include architectures in the release summary JSON/schema and cask verifier fixtures.
- [ ] Add a manifest-driven arm64 target/triple to the Makefile and release build. `lipo` verification remains the fail-closed assertion, not the mechanism that discovers an accidental runner-native build.

**Commit:** `fix: declare the release architecture contract`

### 9B. Verify Every Runtime Identity And Bundle Contract

**Files:**

- Modify: `scripts/verify-release-artifact.sh`
- Modify: `Tests/ViftyCoreTests/ReleaseArtifactScriptTests.swift`
- Modify: release-summary schema.

- [ ] RED: reject wrong main app identifier, daemon identifier, `CFBundleIdentifier`, LaunchDaemon `Label`, Mach service, TeamID, build number, or architecture even when deep codesign passes.
- [ ] Verify exact identities: `tech.reidar.vifty`, `.daemon`, `.helper`, and `.ctl`.
- [ ] Enforce a monotonically increasing `CFBundleVersion` against the published manifest/release history.
- [ ] Preserve required notarization, staple, Gatekeeper, checksum, schema, wrapper, and LaunchDaemon TeamID checks without skip flags in public release mode.
- [ ] Emit a version-2 release-summary schema for identity/build/architecture fields while retaining explicit version-1 historical decoding fixtures for `v1.3.2` evidence.

**Commit:** `fix: verify complete release identity`

### 9C. Split Read-Only Build/Test From Privileged Publication

**Files:**

- Modify: `.github/workflows/ci.yml`
- Modify: `.github/workflows/release.yml`
- Create: `scripts/check-release-provenance.sh`
- Create: `scripts/check-workflow-contract.rb` or equivalent parsed-YAML validator.
- Modify: release metadata tests.

- [ ] Pin every action to an immutable commit SHA with a comment naming its release.
- [ ] Set workflow/default permissions to `contents: read`; use `persist-credentials: false` for checkout.
- [ ] Run static gates, full tests, warnings-as-errors build, unsigned bundle assembly, and artifact inventory before any signing material is imported.
- [ ] Upload the unsigned, hash-inventoried candidate from the read-only job. A separate protected `release` environment downloads exactly that artifact, imports signing credentials, signs/notarizes/verifies, and receives `contents: write` only for publication.
- [ ] Make GitHub's `environment: release` an authoritative protected deployment boundary without pretending it supplies unavailable peer approval. Validate the declaration semantically, require no reviewer gate, disable administrator bypass, disable protected-branch admission, require exactly one custom `tag: v*` deployment policy with no branch policy, and bind administrator-visible branch/environment/ruleset/secret facts into the signed tag immediately before creation. The provenance script must decode and validate that signed evidence in addition to signature, exact remote tag identity, exact-main CI, and version facts.
- [ ] Inventory and hash the minimal signing/notarization/package/verifier scripts before certificate import, then revalidate hashes before their allowlisted execution. No SwiftPM, package plugin, test, general `make` target, or arbitrary child command runs afterward.
- [ ] Delete the temporary keychain/certificate in an `always()` cleanup step.
- [ ] Parse workflow YAML semantically and run a pinned, checksummed or vendored hermetic `actionlint`; do not accept commented/unreachable strings or an unspecified local tool version as proof.

**Commit:** `ci: isolate signed release publication`

### 9D. Require Signed, Ancestry-Proven Tags With Exact-Commit CI

- [ ] Add the hardware-backed release signing public key to a public allowed-signers file; never store private key material.
- [ ] Change release instructions to create an annotated signed tag and push only after exact merged-main CI passes.
- [ ] `check-release-provenance.sh` must verify: tag signature, immutable remote tag, tag commit equals the exact signed-tag workflow revision and exact-main CI commit, exact source CI success, version/build/manifest agreement, and the fresh administrator governance evidence embedded in the signed tag. The environment is a deployment/provenance boundary, not a peer-approval claim.
- [ ] Correct all wording that implies `gh release create --verify-tag` verifies a cryptographic signature; it only confirms the remote tag exists.
- [ ] Block release publication when any provenance check is unknown, skipped, or stale.

**Commit:** `ci: require signed release provenance`

**Task gate:**

```bash
swift test --scratch-path "$PWD/.build" --filter ReleaseArtifactScriptTests
swift test --scratch-path "$PWD/.build" --filter ReleaseMetadataScriptTests
ruby scripts/check-workflow-contract.rb
actionlint .github/workflows/*.yml
scripts/validate-release-metadata.sh --mode developer-id
brew style Casks/vifty.rb
brew audit --cask --strict Casks/vifty.rb
```

## Task 10: Create One Release-Facts Authority And Remove Documentation Drift

**Files:**

- Consume/extend: `.github/release-manifest.json`
- Consume/extend: `docs/schemas/release-manifest.schema.json`
- Consume/extend: `scripts/check-release-manifest.sh`
- Create: `scripts/render-release-facts.sh --check`
- Modify: `SECURITY.md`, `README.md`, `SUPPORT.md`, `docs/release-status.md`, `docs/trust-model.md`, `docs/competitive-analysis.md`, `docs/compatibility.md`, `docs/release.md`, `docs/auto-update.md`.
- Modify: release/hardware issue templates, CODEOWNERS path casing, community/metadata gates, and documentation tests.

**Starting manifest shape before Task 9 selects the next candidate/version:**

```json
{
  "schemaVersion": 1,
  "product": {
    "bundleID": "tech.reidar.vifty",
    "daemonID": "tech.reidar.vifty.daemon",
    "helperID": "tech.reidar.vifty.helper",
    "ctlID": "tech.reidar.vifty.ctl",
    "architectures": ["arm64"],
    "minimumMacOS": "15.0"
  },
  "releasePolicy": {
    "signedTagsRequiredFromVersion": null
  },
  "publishedRelease": {
    "version": "1.3.2",
    "build": 7,
    "tag": "v1.3.2",
    "artifact": "Vifty-v1.3.2.zip",
    "sha256": "8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0",
    "artifactTrust": "passed",
    "manualCompatibility": "pending",
    "manualCompatibilityScope": null
  },
  "candidate": null
}
```

- [ ] Validate the manifest with its schema and make release scripts consume it instead of duplicating identities/architecture/current-version facts.
- [ ] Support a separate candidate object during release preparation; never rewrite `publishedRelease` until the exact public artifact and checksum pass.
- [ ] Preserve the non-null `signedTagsRequiredFromVersion` established in Task 9 so historical unsigned `v1.3.x` evidence remains readable without allowing a new unsigned publication.
- [ ] Generate or verify bounded fact blocks in Markdown and template defaults. Human prose may explain evidence, but it cannot redefine current version, architecture, or trust state.
- [ ] Update `SECURITY.md` to support the current release and accurately describe both daemon and guarded privileged-helper write boundaries.
- [ ] Replace every stale `v1.2.0`/future-notarization claim and align polling copy with the actual 5-second active / 10-second idle policy.
- [ ] Add `Not run — read-only evidence only` to the hardware issue form and map it to `manualSmokeTestResult: not-recorded`.
- [ ] Add a casing regression that requires the existing `.github/PULL_REQUEST_TEMPLATE.md` and rejects a duplicate lowercase variant; add a monotonic build-number check.
- [ ] Replace documentation tests that pin prose/version literals with manifest/schema/evidence relationships. Keep explicit non-claim tests.
- [ ] Make community/release gates parse JSON/YAML and check reachable structured fields rather than generic greps.

**Focused gate:**

```bash
scripts/check-release-manifest.sh
scripts/render-release-facts.sh --check
scripts/check-community-standards.sh
swift test --scratch-path "$PWD/.build" --filter DocumentationTrustSurfaceTests
swift test --scratch-path "$PWD/.build" --filter GitHubMetadataScriptTests
```

**Commits:**

1. `build: centralize release facts`
2. `docs: align trust and compatibility claims`
3. `test: validate structured release documentation`

## Task 11: Decompose AppModel, FanControlPanel, And Brittle Tests

This task begins only after Tasks 4-8 have locked the new safety, recovery UI, notification, visual, and accessibility behavior. It supersedes, rather than duplicates, Task 8 of `2026-07-12-vifty-v1.3-completion-and-hardening.md`.

### 11A. Split Tests Mechanically Before Moving Behavior

- [ ] Move existing tests without semantic rewrites into `AppModelLifecycleTests`, `AppModelPollingTests`, `AppModelFanControlTests`, `AppModelMenuBarTests`, `AppModelHelperHealthTests`, `AppModelNotificationTests`, `AppModelPreferencesTests`, and `AppModelTelemetryTests`.
- [ ] Create `Tests/ViftyCoreTests/Support/AppModelTestSupport.swift` for fakes/builders.
- [ ] Prove the same test count and assertions pass before any extraction.

**Commit:** `test: split app model suites`

### 11B. Extract Deterministic Collaborators

**Create:**

- `Sources/Vifty/FanControlSessionController.swift`
- `Sources/Vifty/MenuBarPresentationProvider.swift`
- `Sources/Vifty/HelperHealthPresentation.swift`
- `Sources/Vifty/LocalNotificationCoordinator.swift`
- `Sources/Vifty/AppPollingController.swift`
- `Sources/Vifty/TelemetrySession.swift`
- focused tests for each.

- [ ] Keep `AppModel` as the sole `@MainActor ObservableObject` integration facade and the only UI owner of coordinator/hardware calls.
- [ ] Move only deterministic transitions, scheduling policy, and presentation calculations.
- [ ] Inject a manual clock/sleeper into polling, copy feedback, notification cooldown, retry, and session-expiry behavior. Remove real sleeps/poll loops from unit tests.
- [ ] RED: idempotent start, poll coalescing, cancellation, cadence change, no post-stop publish, stale operation rejection, Auto preemption, and helper/notification state transitions.
- [ ] Run the whole AppModel family after every extraction commit.

**Commits:** one per collaborator, using `refactor: extract ...` subjects.

### 11C. Replace FanControlPanel's Argument Surface

**Create:**

- `Sources/Vifty/FanControlPanelPresentation.swift`
- `Sources/Vifty/FixedRPMEditor.swift`
- `Sources/Vifty/TemperatureCurveEditor.swift`
- `Sources/Vifty/PerFanCurveOverrideEditor.swift`
- `Sources/Vifty/FanStatusList.swift`
- focused presentation/action tests.

```swift
struct FanControlPanelPresentation: Equatable {
    let draft: FanControlDraft
    let sensors: [TemperatureSensor]
    let fans: [FanControlFanRowPresentation]
    let profile: CurveProfilePresentation
    let manualControlAvailable: Bool
    let emptyState: FanControlEmptyState?
}

enum FanControlPanelAction: Equatable {
    case setFixedRPM(Double)
    case setPerFanFixedEnabled(Bool)
    case setFanFixedRPM(fanID: Int, rpm: Int, committed: Bool)
    case setCurvePoint(CurvePointKind, temperature: Double, rpm: Int)
    case selectSensor(String)
    case setPerFanOverridesEnabled(Bool)
    case setOverride(fanID: Int, point: CurvePointKind, rpm: Int)
    case loadDeveloperPreset(DeveloperFanPreset)
    case selectProfile(UUID?)
    case updateProfile
    case saveProfile(String)
    case deleteProfile(UUID)
}
```

- [ ] Make `FanControlPanel` a composition root accepting `presentation`, `send`, helper action, and copy-diagnostics action.
- [ ] RED: every editor action, including per-fan Fixed enablement, per-fan Curve override enablement, and developer presets, changes draft/session state and produces zero fake hardware commands until Apply.
- [ ] No subview receives the entire `AppModel`.

**Commit:** `refactor: split fan control editor surfaces`

### 11D. Retire Source-Shape Assertions

- [ ] Rename/reduce `AppSourceRegressionTests.swift` to `AppArchitectureBoundaryTests.swift`.
- [ ] Keep source checks only for boundaries not expressible behaviorally: native Settings scene, no UI construction of SMC/XPC/coordinator clients, no raw fan-write commands, required fixture exclusion/resources, and required accessibility representation.
- [ ] Replace view-string/layout assertions with resolver, presentation, state, fixture, rendered AX, and geometry tests.
- [ ] Target a small architecture boundary suite; do not set an arbitrary production line-count gate.

**Commit:** `test: replace source-shape UI assertions`

**Task gate:**

```bash
make test-fast SWIFT_BUILD_PATH="$PWD/.build"
swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors
make verify SWIFT_BUILD_PATH="$PWD/.build"
```

## Task 12: Harden viftyctl Child Process And Signal Lifecycle

**Files:**

- Create: `Sources/ViftyCtl/ChildProcessSupervisor.swift`
- Modify: `Sources/ViftyCtl/main.swift`
- Modify: `Sources/ViftyCore/ViftyCtlRunner.swift` only where the injected process boundary requires it.
- Modify: `ViftyCtlProcessRunnerTests` and `ViftyCtlRunnerTests`.

- [ ] Install/activate signal forwarding before the child can run, closing the current launch-before-handler window.
- [ ] Start the child in a distinct process group and forward handled signals to the group, not just the immediate PID.
- [ ] Wait for group termination with a bounded escalation policy while always preserving the wrapper's Auto-restore attempt and exit-code rules.
- [ ] RED: signal immediately after launch reaches child; child/grandchild both terminate; handlers restore after run; child signal exit maps correctly; restore failure remains visible when the child succeeded.
- [ ] Add backward-compatible capability/run fields: `signalScope: processGroup`, `descendantCleanupBeforeAutoRestore: true`, and `backgroundProcessesAllowed: false`; update schemas, canonical examples, evidence collector, and reviewer fixtures.
- [ ] Process tests may launch local fixture processes but must use a fake control client and never request a real lease or Auto restore.

**Commit:** `fix: supervise guarded workload process groups`

## Task 13: Full Gates, Exact Candidate, Installed Proof, And Supervised Hardware Evidence

### 13A. Automated Merge Gate

- [ ] Re-run the finding inventory and prove every row points to a passing behavioral/contract test.
- [ ] Run:

```bash
df -h /System/Volumes/Data
/bin/bash -n scripts/*.sh examples/viftyctl/*.sh
make test-fast SWIFT_BUILD_PATH="$PWD/.build"
swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors
make verify SWIFT_BUILD_PATH="$PWD/.build"
make verify-full SWIFT_BUILD_PATH="$PWD/.build"
git diff --check
```

- [ ] Run fixture visual/AX matrices and review failures rather than regenerating expected evidence blindly.
- [ ] Require two reviews for the safety cutover: correctness/concurrency and hardware/recovery. Require separate release/security and macOS UI/AX reviews.
- [ ] Merge each PR only with exact-head CI; do not batch-merge unreviewed safety layers.

### 13B. Release Candidate Gate

- [ ] Choose the next version after merged-main gates; a control-protocol/behavior release should normally be a new minor version, not a silent `v1.3.2` rebuild.
- [ ] Populate manifest candidate facts, run exact merged-main CI, create a signed tag, and prove signature/ancestry/exact-commit CI before publication.
- [ ] Build/sign/notarize/staple through the protected release environment.
- [ ] Verify checksum, all four identities, architecture, build/version, TeamID, LaunchDaemon contract, schemas/wrappers, notarization, staple, and Gatekeeper with no public-mode skips.
- [ ] Publish, apply the verified cask checksum in a follow-up PR, and rerun public release readiness.
- [ ] After the cask follow-up is public, redownload through the final public cask URL and rerun the artifact verifier against those exact bytes and the final cask SHA. Metadata readiness alone is not binary verification.

### 13C. Installed Read-Only Gate

- [ ] Install the already-verified public zip, not a locally rebuilt substitute.
- [ ] Verify installed app/helper hash parity and control protocol version without repairing while manual ownership is unresolved.
- [ ] Collect/review release-mode validation evidence with `coolingCommandsRun: false` and exact source/tag/artifact identity.
- [ ] Test cask installation and safe Auto-state uninstall on a clean dedicated Mac. Confirm no privileged plist/helper/log leftovers.

### 13D. Human-Supervised Hardware Gates — Separate Claims

These steps require explicit user presence and confirmation. They are never automatic continuations of tests, install, or release.

1. Confirm nominal thermal state, trusted fan telemetry, journal clear, daemon owner macOS, helper parity, and safe manual-smoke readiness.
2. Run a short Fixed RPM transaction; inspect journal/ownership; request Auto; verify both expected fans report OS-managed; archive evidence.
3. After a fresh baseline, run a short Temperature Curve transaction with divergent per-fan override; verify preview equals applied targets; request Auto; verify both fans; archive separately.
4. Exercise a safe repair while already confirmed Auto. Failure-in-Forced repair behavior remains fixture/fault-injection proof unless the user explicitly authorizes a dedicated recovery test.
5. After cooldown and a separate readiness pass, run the bounded agent workload smoke and confirm expiry/child completion restores the complete expected set.
6. Promote compatibility only for the exact model and exact signed binary represented by reviewed evidence.

### 13E. Final Evidence And Logging

- [ ] Record merge SHAs, CI runs, signed tag, Release run, artifact/checksum, verifier summary, cask commit, installed review result, helper parity, each supervised smoke result, and explicit non-claims.
- [ ] Update the release manifest's `publishedRelease` only after the exact public artifact passes; clear the candidate in a reviewed follow-up commit.
- [ ] Log evidence in Obsidian daily and Vifty project notes.
- [ ] Run final disk hygiene: inspect `/private/tmp/[Vv]ifty*`, check candidate leftovers with `lsof`, and remove only stale owned directories with no active handles.

---

## Rollback And Recovery Strategy

- Before merge, revert only whole focused commits/PRs; never leave both legacy and arbiter write authorities enabled.
- Once a v2 journal exists, an older daemon must not overwrite or clear it. Downgrade shows protocol mismatch and remains read-only until a compatible helper is installed.
- Never roll back app and helper independently. First confirm OS ownership and journal clear, then install the known-compatible app/helper pair.
- A failed new release is superseded by a new signed version; published tags/assets are immutable.
- A failed docs/cask follow-up does not change binary trust. Keep the release unpromoted until manifest, cask, and public readiness agree.
- If restore is unconfirmed, preserve journal/lease/marker evidence, block new control and teardown, show recovery guidance, and prefer reboot/system recovery over destructive cleanup.

## Final Plan Self-Review

### Safety coverage

- Physical write authorization, mutation, ownership, persistence, recovery, and teardown each have one named authority and fault-injection suite.
- Empty/partial/legacy/synthesized/corrupt states are fail-closed.
- No automated command in this plan authorizes real fan writes.

### Product coverage

- Preview, ownership, notifications, profiles, temperature semantics, chart truth, curve accessibility, Settings layout, menu hierarchy, and screenshots are included.
- Broad Liquid Glass adoption, new telemetry persistence, generic system-monitor expansion, and Sparkle remain out of scope.

### Trust coverage

- Architecture, identity, TeamID, version/build, checksum, notarization, provenance, permissions, secrets, docs, cask, installed parity, and hardware compatibility remain distinct verified facts.

### Maintainability coverage

- Daemon/helper logic becomes importable and behavior-tested.
- AppModel/panel decomposition follows locked behavior rather than preceding it.
- Deterministic clocks and process supervision address the observed flake/lifecycle gaps.

## Execution Handoff

Start with Task 0 in a `codex/` branch or isolated worktree. Execute Tasks 1-5 serially with a fresh implementation agent and independent review for each PR. UI and release-facts work may proceed in parallel only where the dependency map permits. Stop after every PR gate; do not treat the existence of this plan as authorization for helper actions, fan writes, Auto restoration, publishing, or hardware smoke.

## Execution Record — 2026-07-14

Implementation was completed on `codex/vifty-whole-app-remediation` from unchanged baseline `21c2f9175dccb9226d6972574070bc21dbede2f0`. The worktree remains intentionally uncommitted and unstaged for review.

### Completed implementation

- Replaced split fan-write authority with the protocol-v2 transactional arbiter, complete physical-fan inventory, durable ownership/journal envelopes, fail-closed recovery, full-set Auto restoration, and process-group-aware guarded workload lifecycle.
- Reworked app polling, fan-control session reconciliation, curve/profile presentation, per-fan target preview, telemetry semantics, notifications, menu-bar state, Settings layout, compact-window behavior, and deterministic hardware-free review fixtures. Added persisted Vifty-owned Standard (`1.0`), Large (`1.2`), and Accessibility (`1.5`) semantic text scaling that preserves native AppKit font descriptors; the fixture exercises the same production environment rather than synthetic macOS Dynamic Type.
- Hardened helper repair/uninstall around exact helper identity, daemon-owned single-use maintenance receipts, atomic root claims, exact-label launchd freeze, mandatory post-freeze staged-helper Auto/readback, caller-bound root evidence, clean environments, and deterministic interruption handling. The reviewed lifecycle script SHA-256 and compiled loader constant both equal `f438be985aad1660a0a59b878bb7e5263bcbd4aabebe4fcf5d8d367d4e31e001`.
- Added a narrow selector-missing migration route for the exact published v1.3.2 daemon only. Root independently verifies the installed daemon's canonical SHA-256, CDHash, identifier, TeamID, Developer ID chain/OIDs, and hardened runtime before any service disable or bootout. Lookalikes and normal protocol-v2 missing receipts block.
- Made app replacement transactional and fail closed: private authenticated preflight tools, canonical v1.3.2 executable identity pins, safe fixture scoping, symlink rejection, same-filesystem staging, post-swap verification, and explicit rollback-recovery preservation.
- Added manifest-driven release facts, immutable tag-object and commit binding, exact protected-tag ruleset checks, cryptographic draft containment, immutable numeric release-ID addressing, least-privilege jobs, and schema-backed release/environment checks.

### Historical proof snapshot — superseded by later edits

The following results were valid for the source snapshot tested at that point in the execution record. Later edits mean they are not current-source completion evidence.

- `make verify-full SWIFT_BUILD_PATH="$PWD/.build"`: passed, including **1,470/1,470 tests**, warnings-as-errors production build, release app bundling, plist lint, and deep code-sign verification.
- Integrated safety/release/installer lane: **388/388 tests passed**.
- UI fixture/evidence contracts: **9/9 fixture tests** and **7/7 evidence-verifier tests passed**; no hardware/control backend was constructed.
- Shell syntax, Ruby syntax, JSON schema parsing, `git diff --check`, workflow contract, actionlint, release manifest, generated release facts, Developer ID metadata validation, community standards, and lifecycle digest parity all passed.
- Live read-only GitHub metadata check passed for required topics and labels.
- Independent adversarial reviews found no remaining P0/P1 in release containment, exact v1.3.2 replacement, or privileged-helper lifecycle. No live installer, sudo, launchctl, cooling lease, fan-write, or Auto-restoration request was issued. A later hermeticity audit found that some pre-fix unit tests could still perform live read-only daemon/SMC/HID probes or clear the production marker; the continuation record documents their isolation.

### Explicit pending gates and non-claims

- The tracked UI request manifest remains honestly `pending`. A committed portable checkpoint records all 50 automated rows passing for exact historical source `6ac429cbacf7cc3358c74493ab7461a43fa40275`, with a byte-bound canonical hero. Current `HEAD` differs, so the checkpoint is not current-source UI evidence. Human visual review remains pending; VoiceOver is `skipped-by-owner` and no VoiceOver behavior is claimed.
- Immutable tag governance is live: active ruleset `18940029`, `Immutable Vifty release tags`, covers `refs/tags/v*`, blocks update and deletion, and has no bypass actors. The protected `release` environment exists with no reviewer gate and administrator bypass disabled, but its old protected-branch-only deployment policy cannot admit the hardened signed-tag workflow. After this code merges it must be migrated to one custom `tag: v*` policy with no branch policy, and the full readback must pass before tag creation. The earlier non-owner reviewer requirement was remediation-added team-shaped policy, not a live GitHub rule, and is superseded by the explicit solo-maintainer governance contract. The release manifest candidate remains `null` until the separate release-prep change; no tag, draft, asset, release, or cask mutation has yet occurred.
- The exact public `v1.3.2` build 7 passed supervised Fixed → Auto → Curve → Auto smoke on `MacBookPro18,1`, with final `passed-auto-restored`, no failures, and no warnings. This validates only that exact public binary on that exact model; it does not validate the remediation branch, another build/model, agent cooling, or broad compatibility.
- The user-authorized profile restore is complete. The primary and backup contain the single `Quiet` profile, are mode `600`, and share SHA-256 `4a8ddf17e11e9fccd17f8ccb5ef2ba8ac7cf760e3eafc12f7f8eddf8844c9ec8`; the incident snapshot remains preserved at SHA-256 `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945`. Post-smoke verification confirms the restored files remained byte-identical.
- The installed `/Applications/Vifty.app` process remained untouched throughout final autonomous UI work. Codex did not launch or signal the installed app, helper, daemon, or `viftyctl`, and did not request a hardware command. This is an actor-scoped automation claim, not proof that an already-running installed app stayed in Auto.
- Live helper repair, agent workload, install/uninstall, notarized-candidate, and future public-release evidence remain separately supervised gates.

### Continuation record — 2026-07-15

- The pre-curve-fix 50-entry UI ledger and the user's first two visual-review batches were superseded after the app added truthful cyan Left/purple Right effective curves, a stable 1,000-7,000+ RPM authoring envelope, and exact per-fan AX summaries. The current evidence manifest is pending a complete recapture; no old visual or AX pass is carried forward.
- The current binary's standard recapture is now complete: 9 fixture + 26 standard visual + 13 AX rows, 48 ledger entries, and `--verify-automated` passed. Only the dedicated Reduce Transparency and Increase Contrast rows remain before fresh human visual and VoiceOver review can begin.
- The dedicated Reduce Transparency row is now sealed, bringing the current ledger to 49 entries with automated verification still passing. Only Increase Contrast remains.
- The dedicated Increase Contrast row is also sealed. The current binary now has a complete 50-entry automated UI matrix, and the only full-matrix blockers are the fresh human visual and VoiceOver attestations.
- The original display state was restored and read back as Reduce Transparency on / Increase Contrast off. Fresh human visual review restarted at 0/28 with Batch 1 bound to the then-current 50-entry manifest.
- Engineering QA stopped that Batch 1 before human approval after finding that the header called one retained point plotted while the placeholder promised history after the already-completed first poll. The test-first fix now labels it `1 retained sample` and asks for one more successful poll. `TelemetryHistoryTests` passed 18/18; a second exact `make test-fast` passed 1,268/1,268 after the earlier two suite failures did not reproduce. The failing test names were not preserved and are not inferred from older logs. The exact-source change requires a full new ledger: debug `411ba2e2c40aa717affc2ef24a60594cfa2810a333ed532930581a3ea2c1f233`, collector `3cc2c943361f8a2148f88eb36095ac797f50a7d589e00ceea4a1628d74e64fd2`, release `ce9cffdcd3e3f5784c8d915559ffc3e7e048fe3b443ed87be1582fd8309b19fc`. `main-reduce-transparency` is sealed as `visual-main-reduce-transparency-20260715T172355Z-5b1bc08cd94c`; current progress is 1/50 with Reduce Transparency on and Increase Contrast off. No installed app, helper, daemon, `viftyctl`, or hardware control path was touched.

- At that checkpoint, isolated `make verify` passed with 1,201 tests, a warnings-as-errors build, release app bundling, plist checks, deep code-sign verification, and release exclusion of all review-only AX components.
- Focused UI fixture/evidence/release-environment testing passed 74/74. Independent frozen-diff reviews found no remaining Critical or Important findings.
- The UI seal tests now reset their copied target row to a private pending fixture before sealing, so they remain independent of the repository's final sealed evidence state; the focused `UIReviewEvidenceScriptTests` suite passed 51/51 after that correction.
- The then-frozen UI products were release SHA-256 `3ca9a5d6d8cdd09656ca76c06056ed0c066fbb4b945416be54cd464959d2db5a`, debug SHA-256 `139d440226a00d739d76beb74bc6d0ae60401c3696a8f176158367c4231c7afc`, and collector SHA-256 `e54135c739c1174a38d93c3cbd5317583f6585d3b85ab02d3cf1e71c51dc0e0c`.
- The dedicated Increase Contrast and Reduce Transparency cells are sealed. After capture, the display state was restored to Reduce Transparency on / Increase Contrast off.
- At this 15 July checkpoint, the single `Quiet` profile remained restored, the protected release environment was still absent, and the then-manual release design was blocked on the proposed non-owner reviewer gate. The 17 July governance correction below supersedes that reviewer policy, and the later push-only trigger correction supersedes the manual-dispatch design; the candidate remains `null`.
- A passive final-state check found the already-running installed v1.3.2 app repeatedly refreshing `manual-control-active` while its persisted startup preference remained `Curve`, including after the isolated test process exited. Codex stopped the full gate, issued no control request, and did not delete the marker. At that checkpoint, current live Auto remained unproven until the user selected Auto in the installed app and a passive check confirmed the marker stayed absent.
- The user subsequently confirmed **Auto applied** and changed Settings → General → Default mode to **Auto**. With the same installed process `19096` still running, passive checks at `2026-07-15T08:25:33Z` and `2026-07-15T08:25:46Z` found `manual-control-active` absent and persisted `startupMode` equal to `Auto` on both observations. The preferences file remained private (`0600`, `reidar:staff`) at SHA-256 `ffc783aea49bce3bd0f16a103ce5a9ae9919976fb0143724579939576f72ae18`. This closes the current installed marker/default-state gate using operator confirmation plus a passive greater-than-one-poll absence check. It is not a new daemon fan-mode readback, hardware smoke, remediation-build compatibility result, or release-candidate claim.
- The follow-up test-hermeticity audit removed every identified host dependency from exercised control/read paths: direct AppModel control-path tests inject fake coordinators and private markers; the fake-client `viftyctl restore-auto` test injects a no-op marker clearer; `ManualControlMarker()` resolves to process-session-private storage under XCTest; the architecture boundary rejects AppModel control tests without explicit coordinator injection, including startup-preference polling; and local-snapshot fallback tests inject an empty HID reader.
- App startup now prioritizes unclean-exit recovery before polling, startup preferences, or notification authorization. A persisted marker itself forces a daemon-confirmed Auto transaction, failed recovery remains pending across later polls, and a captured generation prevents stale recovery from overriding a newer mode request. Repeated `markActive()` calls reassert private permissions without replacing the marker inode or content in the remediation build. Exact ordered-call, double-failure, and paused-snapshot supersession regressions are included; the final focused architecture/lifecycle/coordinator run passed **58/58 tests**.
- At that checkpoint, isolated `make verify-full SWIFT_BUILD_PATH="$PWD/.build-verify" APP_DIR="$PWD/.build-verify/Vifty.app"` passed **1,621/1,621 tests** in 566.623 seconds, the warnings-as-errors production build, release app bundling, plist and executable-identity checks, review-only AX exclusion, and deep code-sign verification. The separate disk guard and `git diff --check` preflights also passed. Later source edits superseded this as current-source proof.

### Claims correction — 2026-07-16

- Every verification count, product hash, capture ledger, and visual result above is a historical snapshot unless a later exact-source checkpoint explicitly binds it. The compiled/full gate is now current through the final code-changing commit, but a fresh 50-row UI recapture remains pending; no current visual or VoiceOver pass is claimed.
- The owner reports the current host settings as Reduce Transparency off and Increase Contrast off. This state does not revive any superseded evidence.

### Integration closeout — 2026-07-17

- PR #17 contains the remediation on `codex/vifty-whole-app-remediation`. All code-changing work is present through `7e24e245ec202edaa01db283308bc5c3b38168c3`; the worktree and remote branch matched exactly at that checkpoint.
- Exact local `make verify-full` passed **1,810/1,810 XCTest cases** with zero failures, then passed every Ruby release, installer-lifecycle, and UI-review contract suite, warnings-as-errors build, app assembly, plist, identifier, and deep code-sign gate.
- Exact-head GitHub run `29551623379` passed the synthetic merge of base `515dd7cbc1698bac1ca44ed3bfa77f8a04a31f1a` and code head `7e24e245ec202edaa01db283308bc5c3b38168c3`, including full verification, temporary install parity, archive creation, and artifact upload. The locale-sensitive release-inventory failure was closed by pinning all C-sorted `comm` comparisons to `LC_ALL=C`; the macOS-runner regression passed inside the 41-case release-artifact suite.
- This plan reconciliation must pass the normal exact-head PR check. PR-ready is not public-release-ready: skipped VoiceOver, remediation-build hardware compatibility, candidate, signed tag, notarized asset, cask handoff, and installed exact-release proof remain separate and unclaimed.

### Governance correction — 2026-07-17

- The earlier non-owner-reviewer entries above are retained as dated execution history, not current policy. Forensic readback showed that GitHub never had an active release reviewer environment and that a dormant REST subresource count had been misreported as an active `main` approval rule. Full REST, GraphQL, and PR #17 merge state showed no active PR-review requirement.
- The accepted solo-maintainer contract keeps the real controls: a protected `release` environment with no required-reviewer rule, administrator bypass disabled, and exactly one custom `tag: v*` deployment policy with no branch policy; six intentionally repository-scoped release secret names with same-name environment shadows forbidden and all references confined to the protected signing job; a required PR with zero approvals and no bypass actors; strict Actions-owned `SwiftPM checks` enforced for administrators; conversation resolution; no force push/deletion; an immutable signed-tag push that automatically triggers exactly one first-attempt Release run with no manual dispatch or rerun path; exact-main CI provenance; signed immutable tags; manifest binding; Developer ID signing; notarization; and isolated publication.
- Protected-main, tag-ruleset, and secret-name placement match that boundary; the environment remains the explicit transitional blocker until its old protected-branch policy is migrated after this code merges. Only after that migration, release prep merge, and exact-main CI pass may `scripts/create-signed-release-tag.sh` bind fresh administrator-pretag evidence into the signed tag. Despite its retained filename, `scripts/push-and-dispatch-signed-release-tag.sh` then revalidates the signed and live facts, creates only the exact annotated remote tag with an absent-ref lease, reads it back, and observes the first-attempt `push` run that GitHub automatically starts. A checkout-independent retired-tag marker is created immediately before the push boundary; after that point the operator inspects the original marker, receipt, tag, run, and release rather than rerunning or redispatching, and uses a new patch only after non-publication is conclusive. The workflow persists initial current-fresh admission in the hashed candidate handoff and later validates that record plus narrower current public evidence without claiming administrator-only visibility.
