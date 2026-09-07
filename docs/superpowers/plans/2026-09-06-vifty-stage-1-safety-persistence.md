# Vifty Stage 1 Safety and Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make agent policy, application preferences, and helper lifecycle execution fail closed, durable, recoverable, and truthful.

**Architecture:** Add one small status value for daemon persistence health, keep policy mutations inside `AgentControlService`, copy the proven `CurveProfileStore` recovery sequence into the app-preference store, and drain lifecycle process output concurrently with fixed byte limits. Do not create a general persistence framework or alter fan mutation paths.

**Tech Stack:** Swift 6, Foundation, Swift Concurrency, XCTest, Swift Package Manager, macOS `Process` and `Pipe`.

**Spec:** `docs/superpowers/specs/2026-09-06-vifty-audit-remediation-design.md`

## Global Constraints

- macOS 15 minimum; no third-party dependency.
- No fan command, cooling lease, helper maintenance, `sudo`, install, Auto restoration, or release mutation during verification.
- Preserve all daemon/XPC/SMC/ownership/journal/readback gates.
- Use `.build` as the Swift scratch path and stop if `/System/Volumes/Data` has less than 30 GiB free.

---

### Task 1: Define the persistence-health contract

**Files:**
- Modify: `Sources/ViftyCore/AgentControlModels.swift`
- Modify: `Sources/ViftyCore/ViftyDaemonProtocol.swift`
- Modify: `Sources/ViftyCore/ViftyCtlRunner.swift`
- Modify: `docs/schemas/viftyctl-status.schema.json`
- Modify: `docs/schemas/viftyctl-command-error.schema.json`
- Modify: `docs/examples/viftyctl/status-active-lease.json`
- Test: `Tests/ViftyCoreTests/XPCAgentControlCodingTests.swift`
- Test: `Tests/ViftyCoreTests/ViftyCtlJSONExampleTests.swift`

**Interfaces:**
- Produces: `AgentControlPersistenceHealth(policyStatusAvailable:policyError:auditStatusAvailable:auditError:)`.
- Produces: non-optional `AgentControlStatus.persistenceHealth`, defaulting to `.healthy` for source call-site compatibility.
- XPC decode treats a missing persistence dictionary as unavailable rather than healthy.

- [ ] **Step 1: Add failing model and XPC round-trip tests**

```swift
let health = AgentControlPersistenceHealth(
    policyStatusAvailable: false,
    policyError: "policy unreadable",
    auditStatusAvailable: true,
    auditError: nil
)
let status = AgentControlStatus(
    enabled: false,
    activeLease: nil,
    lastDecision: nil,
    lastErrorCode: .persistenceFailure,
    persistenceHealth: health
)
XCTAssertEqual(XPCAgentControlCoding.decodeStatus(XPCAgentControlCoding.encode(status)), status)
```

- [ ] **Step 2: Run the focused tests and verify the missing-type failure**

Run: `swift test --scratch-path "$PWD/.build" --filter XPCAgentControlCodingTests`

Expected: compilation fails because `AgentControlPersistenceHealth` and `.persistenceFailure` do not exist.

- [ ] **Step 3: Add the minimal model**

```swift
public struct AgentControlPersistenceHealth: Codable, Equatable, Sendable {
    public var policyStatusAvailable: Bool
    public var policyError: String?
    public var auditStatusAvailable: Bool
    public var auditError: String?

    public static let healthy = Self(
        policyStatusAvailable: true,
        policyError: nil,
        auditStatusAvailable: true,
        auditError: nil
    )
}
```

Add `case persistenceFailure = "PERSISTENCE_FAILURE"` to `AgentControlErrorCode` and map it to the existing `.runDiagnose` command-error recovery action. Encode all four persistence fields through JSON and XPC; decode absent XPC persistence data as both statuses unavailable with a bounded compatibility message. In `capabilitiesReport()`, require both `status.policy != nil` and `status.persistenceHealth.policyStatusAvailable` before setting `policyStatusAvailable: true`; otherwise return the disabled fallback policy and the bounded policy persistence message without claiming the daemon itself is unreachable.

- [ ] **Step 4: Update the strict status schema and schema tests**

Require `persistenceHealth`; require both Boolean availability fields; allow both error fields to be string or null. Add `PERSISTENCE_FAILURE` to every schema/test enum for `AgentControlErrorCode`, including the command-error schema. Update canonical status fixture builders to emit `.healthy` without changing unrelated fields.

- [ ] **Step 5: Run contract tests**

Run: `swift test --scratch-path "$PWD/.build" --filter 'XPCAgentControlCodingTests|ViftyCtlJSONExampleTests'`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ViftyCore/AgentControlModels.swift Sources/ViftyCore/ViftyDaemonProtocol.swift Sources/ViftyCore/ViftyCtlRunner.swift docs/schemas/viftyctl-status.schema.json docs/schemas/viftyctl-command-error.schema.json docs/examples/viftyctl/status-active-lease.json Tests/ViftyCoreTests/XPCAgentControlCodingTests.swift Tests/ViftyCoreTests/ViftyCtlJSONExampleTests.swift
git commit -m "feat: expose agent persistence health"
```

### Task 2: Fail closed and make policy toggles transactional

**Files:**
- Modify: `Sources/ViftyCore/AgentControlService.swift`
- Test: `Tests/ViftyCoreTests/AgentControlServiceTests.swift`

**Interfaces:**
- Consumes: `AgentControlPersistenceHealth` and `.persistenceFailure` from Task 1.
- Produces: policy prepare gate and transactional `setPolicyEnabled(_:)` behavior.

- [ ] **Step 1: Add one fault-injecting store to the existing test support**

```swift
private enum AgentControlFault: Error { case loadPolicy, savePolicy }

private final class AgentControlFaultStore: AgentControlPersisting, @unchecked Sendable {
    let base: AgentControlStore
    var loadedPolicy: Result<Bool?, AgentControlFault> = .success(nil)
    var savePolicyError: AgentControlFault?
    var savedPolicies: [Bool] = []

    func saveActiveLease(_ lease: AgentCoolingLease?) throws { try base.saveActiveLease(lease) }
    func loadActiveLease() throws -> AgentCoolingLease? { try base.loadActiveLease() }
    func appendAuditEvent(_ event: AgentControlAuditEvent) throws { try base.appendAuditEvent(event) }
    func loadRecentAuditEvents(limit: Int) throws -> [AgentControlAuditEvent] {
        try base.loadRecentAuditEvents(limit: limit)
    }
    func loadAgentControlEnabled() throws -> Bool? { try loadedPolicy.get() }
    func saveAgentControlEnabled(_ enabled: Bool) throws {
        if let savePolicyError { throw savePolicyError }
        savedPolicies.append(enabled)
        try base.saveAgentControlEnabled(enabled)
    }
}
```

Add tests for stored true, stored false, absent, load failure, failed enable save, failed disable save, and successful retry. For load failure assert `enabled == false`, `policyStatusAvailable == false`, error code `.persistenceFailure`, and prepare denial before `hardware.apply`.

- [ ] **Step 2: Run tests and verify failure on current behavior**

Run: `swift test --scratch-path "$PWD/.build" --filter AgentControlServiceTests`

Expected: new load-failure test observes enabled policy or missing health; mutation tests observe memory/disk disagreement.

- [ ] **Step 3: Separate lease and policy load errors in initialization**

Use an explicit `do/catch` for `loadAgentControlEnabled()`. On catch set `policy.enabled = false`, set `policyStatusAvailable = false`, and retain a bounded localized message. Do not add the policy error to `persistenceLoadErrorMessage`, because that lease error intentionally triggers Auto recovery.

- [ ] **Step 4: Gate prepare and reorder durable mutation**

At the top of `prepare`, deny with `.persistenceFailure` while policy status is unavailable. In `setPolicyEnabled`, perform active-lease Auto restoration first when disabling, then call `saveAgentControlEnabled(enabled)`, and only then assign `policy.enabled = enabled`. On failure retain the pre-call policy value, publish the typed health error, and rethrow.

- [ ] **Step 5: Run service and store tests**

Run: `swift test --scratch-path "$PWD/.build" --filter 'AgentControlServiceTests|AgentControlStoreTests'`

Expected: PASS with no hardware apply in persistence-failure cases.

- [ ] **Step 6: Commit**

```bash
git add Sources/ViftyCore/AgentControlService.swift Tests/ViftyCoreTests/AgentControlServiceTests.swift
git commit -m "fix: fail closed on agent policy persistence errors"
```

### Task 3: Recover app preferences and surface failed saves

**Files:**
- Modify: `Sources/Vifty/AppPreferencesStore.swift`
- Modify: `Sources/Vifty/AppModel.swift`
- Modify: `Sources/Vifty/AppModel+MenuBar.swift`
- Modify: `Sources/Vifty/SettingsGeneralView.swift`
- Test: `Tests/ViftyCoreTests/AppModelPreferencesTests.swift`
- Test: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Produces: `AppPreferencesLoadResult(preferences:recoveryMessage:)`.
- Produces: `AppModel.appPreferencesPersistenceMessage` and `retryAppPreferencesSave()`.

- [ ] **Step 1: Add failing backup and write-error tests**

Create private `0700` test directories and `0600` files. Assert that a corrupt primary plus valid backup returns the backup, does not mutate the backup, and reports recovery. Assert that an unwritable/invalid destination sets `appPreferencesPersistenceMessage`, while a later valid retry clears it.

- [ ] **Step 2: Run the focused tests and capture the failures**

Run: `swift test --scratch-path "$PWD/.build" --filter AppModelPreferencesTests`

Expected: backup is replaced by corrupt bytes and save failure remains invisible.

- [ ] **Step 3: Implement the store recovery sequence**

```swift
struct AppPreferencesLoadResult: Equatable {
    var preferences: AppPreferences
    var recoveryMessage: String?
}
```

Add `loadResult() throws -> AppPreferencesLoadResult`. Decode primary, then backup. Preserve a valid primary to `.bak` before replacement. Never delete `.bak` during corrupt-primary handling. Use same-directory atomic writes and reapply `0700`/`0600` permissions. Keep `load()` as a test/compatibility convenience returning `(try? loadResult().preferences) ?? migratedPreferences()`; production initialization uses `loadResult()`.

- [ ] **Step 4: Route throwing saves through AppModel**

Replace `preferencesStore.save(...)` with `do { try saveThrowing; message = nil } catch { message = "Settings were not saved: …" }`. Add `retryAppPreferencesSave()` that calls the same single persistence function. Avoid rollback and recursive `didSet` writes.

- [ ] **Step 5: Present the error and retry in General settings**

Use a compact native `Label` plus `Button("Retry Save")` in `SettingsGeneralView`; give both stable accessibility text. Do not mix this message into fan-control `lastError`.

- [ ] **Step 6: Run focused UI/model tests**

Run: `swift test --scratch-path "$PWD/.build" --filter 'AppModelPreferencesTests|AppSourceRegressionTests'`

Expected: PASS; no test hardware command recorded.

- [ ] **Step 7: Commit**

```bash
git add Sources/Vifty/AppPreferencesStore.swift Sources/Vifty/AppModel.swift Sources/Vifty/AppModel+MenuBar.swift Sources/Vifty/SettingsGeneralView.swift Tests/ViftyCoreTests/AppModelPreferencesTests.swift Tests/ViftyCoreTests/AppSourceRegressionTests.swift
git commit -m "fix: make app preferences recoverable and truthful"
```

### Task 4: Drain helper lifecycle output without deadlock

**Files:**
- Modify: `Sources/Vifty/DaemonInstallService.swift`
- Test: `Tests/ViftyCoreTests/DaemonInstallServiceTests.swift`

**Interfaces:**
- Produces: bounded concurrent stdout/stderr capture inside `DaemonInstallProcessRunner.system`.

- [ ] **Step 1: Add the real high-output regression**

Create a temporary executable shell script that reads stdin, writes 256 KiB to stdout and 256 KiB to stderr, and exits 0. Invoke `DaemonInstallProcessRunner.system.run` under a two-second XCTest timeout and assert exit 0 plus captured lengths no greater than a named per-stream limit.

- [ ] **Step 2: Run the test against current code**

Run: `swift test --scratch-path "$PWD/.build" --filter DaemonInstallServiceTests/testSystemRunnerDrainsLargeOutputWithoutDeadlock`

Expected: timeout/failure because the child fills a pipe before `waitUntilExit` returns.

- [ ] **Step 3: Add a bounded collector and drain both handles concurrently**

```swift
private actor BoundedProcessOutput {
    static let maximumBytesPerStream = 64 * 1_024
    private var data = Data()
    func append(_ chunk: Data) {
        guard data.count < Self.maximumBytesPerStream else { return }
        data.append(chunk.prefix(Self.maximumBytesPerStream - data.count))
    }
}
```

Start one task per read handle before writing stdin; read until EOF, retaining only the bound. Wait for process termination and both reader tasks. Close handles on every error path. Keep environment and exit mapping unchanged.

- [ ] **Step 4: Run lifecycle tests repeatedly**

Run: `for i in 1 2 3; do swift test --scratch-path "$PWD/.build" --filter DaemonInstallServiceTests || exit 1; done`

Expected: all three runs PASS without a hang.

- [ ] **Step 5: Commit**

```bash
git add Sources/Vifty/DaemonInstallService.swift Tests/ViftyCoreTests/DaemonInstallServiceTests.swift
git commit -m "fix: drain helper lifecycle output concurrently"
```

### Task 5: Stage 1 verification checkpoint

**Files:**
- Verify only; modify a file only to fix a Stage 1 regression.

- [ ] **Step 1: Check disk and diff hygiene**

Run: `df -h /System/Volumes/Data && git diff --check`

Expected: at least 30 GiB free and exit 0.

- [ ] **Step 2: Run the fast gate**

Run: `make test-fast`

Expected: all fast XCTest cases pass.

- [ ] **Step 3: Run the production build gate**

Run: `swift build --scratch-path "$PWD/.build" -Xswiftc -warnings-as-errors`

Expected: exit 0.

- [ ] **Step 4: Review Stage 1 before Stage 2**

Inspect `git log --oneline` and `git diff 94ae958..HEAD`. Confirm no SMC, XPC authorization, release, or helper-maintenance script weakening. Record `94ae958` and the exact Stage 1 head SHA in the review message; do not create a review-only commit.
