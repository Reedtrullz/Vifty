# Vifty Stability and macOS Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans (recommended). Steps use checkbox syntax for tracking.

**Goal:** Bound Vifty's helper/XPC control-plane failure modes, harden its wire decoding, and replace the custom Settings navigation rail with native macOS settings interaction without changing fan-control safety, release trust, or hardware claims.

**Architecture:** Deliver three independently reviewable slices in this order: lifecycle liveness, XPC contract hardening, and Settings UI polish. The lifecycle slice may terminate a stuck command only after establishing a private process group and applying the existing lifecycle script's cleanup boundary; ambiguous results stay blocked and never auto-retry. XPC read-only requests become cancellation-aware, while every fan, agent, restore, and helper-maintenance mutation remains completion- and authoritative-readback-bound. The UI slice removes bespoke navigation code in favor of native SwiftUI settings semantics while preserving the existing panes, identifiers, scroll behavior, and chart accessibility contract.

**Tech Stack:** Swift 6, Swift Package Manager, SwiftUI, Foundation, Darwin, ServiceManagement, XCTest, Make verification gates, macOS Accessibility inspection, and the existing UI evidence harness.

**Spec:** docs/superpowers/specs/2026-09-06-vifty-audit-remediation-design.md, with the current findings recorded in /Users/reidar/Obsidian/Hermes/Hermes/Personal/Projects/Vifty/Vifty.md under “Second deep stability and macOS polish review — 14-09-2026 10:59”.

## Global Constraints

- Keep macOS 15 as the minimum deployment target and Swift Package Manager as the build system.
- Add no third-party dependency, snapshot framework, state-management framework, or new persistence framework.
- Preserve daemon-first, fail-closed fan writes, fresh daemon readback, transaction receipts, journal/lock recovery, SMC write allowlists, and Auto restoration.
- Never call ViftyHelper setFixed, ViftyHelper auto, raw SMC tools, sudo, direct fan writes, or unguarded viftyctl prepare during implementation or UI evidence capture.
- Keep mutation XPC requests authoritative: task cancellation must not abort or falsely report a fan/agent/helper mutation; the existing transaction timeout remains the outer client deadline.
- Diagnostics remain read-only and unsupported or unknown hardware remains read-only.
- Preserve the six canonical curve accessibility adjusters and the intentional hidden Exact point controls disclosure.
- Preserve ViftyAccessibilityIdentifier.settings, settingsTabs, all four settings-tab identifiers, and each settings-pane identifier; prove their runtime accessibility representation after the native navigation change.
- Keep at least 30 GiB free on /System/Volumes/Data before long builds, use the repository .build path for SwiftPM scratch output, and remove no unrelated artifacts.
- Do not change published release history, tags, cask metadata, signing identities, notarization policy, or Homebrew metadata in this slice.
- Do not claim a new helper install, fan-control success, Auto restoration, Fixed RPM, Temperature Curve compatibility, notarization, or release readiness from source tests alone.
- Keep existing script hashes and lifecycle protocol bindings unchanged unless a test proves that the implementation must change the script; if the lifecycle script changes, update its embedded digest and rerun every lifecycle trust test before continuing.

## Baseline findings and decisions

The reviewed baseline is clean commit bea54ad64df36cfb9e86335966dabbbd0c94693e. The current targeted run passed 35 FanControlArbiterTests, 20 ViftyDaemonClientTests, 5 XPCAgentControlCodingTests, 12 ViftyAccessibilitySemanticsTests, and 1 SettingsSceneSourceTests. The broader repository gates already passed 1,392/1,392 fast tests, 2,054/2,054 full tests, the warnings-as-errors build, release bundle checks, plist/codesign checks, and release/Ruby trust checks.

The following review leads are deliberately not implementation targets:

- Do not redesign FanControlArbiter, LocalFanHelperClient, SMCClient, journal locking, or daemon startup recovery. The authoritative AgentControlService durable-state recovery path is already used by DaemonService; the unused legacy convenience path is not evidence of a live defect.
- Do not change the fixed 35 °C–105 °C curve range, the curve chart accessibility representation, the main workbench information architecture, telemetry retention, or the release workflow.
- Do not add Liquid Glass, a new design system, TCA/MVVM, or a broad view refactor. Existing semantic colors, materials, SF Symbols, adaptive workbench layout, and six curve adjusters are already within scope.
- Do not make unknown AgentControlErrorCode values permissive in this slice. The current decoder fails closed, and the checked-in JSON schemas enumerate the known codes. Preserve that boundary and add a regression that makes the failure explicit rather than silently broadening the agent contract.

## File and interface map

| Slice | Files to modify | Files to test |
|---|---|---|
| Lifecycle liveness | Sources/Vifty/DaemonInstallService.swift; Sources/Vifty/DaemonInstaller.swift; Sources/Vifty/HelperServiceManagementBridge.swift | Tests/ViftyCoreTests/DaemonInstallServiceTests.swift; Tests/ViftyCoreTests/DaemonInstallerTests.swift; Tests/ViftyCoreTests/HelperServiceManagementBridgeTests.swift |
| XPC lifecycle and wire hardening | Sources/ViftyCore/ViftyDaemonClient.swift; Sources/ViftyCore/ViftyDaemonProtocol.swift | Tests/ViftyCoreTests/ViftyDaemonClientTests.swift; Tests/ViftyCoreTests/XPCAgentControlCodingTests.swift; Tests/ViftyCoreTests/XPCFanControlCodingTests.swift |
| UI navigation | Sources/Vifty/ViftySettingsView.swift; only the settings source contracts that fail after the change | Tests/ViftyCoreTests/SettingsSceneSourceTests.swift; Tests/ViftyCoreTests/SettingsPresentationTests.swift; Tests/ViftyCoreTests/ViftyAccessibilitySemanticsTests.swift |
| Final evidence | docs/reviews/2026-09-14-vifty-stability-and-macos-polish.md | Existing full verification, UI evidence, and read-only AX checks |

No new production file is needed. Reuse the existing process runner, callback state, settings panes, accessibility identifier catalog, and UI evidence harness.

## Gate order

| Gate | Required result | If it fails |
|---|---|---|
| Baseline | Clean intended tree, disk guardrail, existing targeted tests green | Stop and reconcile state before editing |
| Lifecycle runner | High-output, timeout, process-group cleanup, stdin-failure, and service-state tests green | Do not touch helper installation or fan state |
| XPC contract | Immediate invalidation, read-only cancellation, mutation cancellation, timer cleanup, duplicate-map, and strict-number tests green | Keep the existing fail-closed behavior and stop the slice |
| Settings | Native tab semantics, flexible window sizing, identifiers, scroll panes, and keyboard navigation verified in source and live AX | Revert only the UI slice; keep stability fixes |
| Repository | make test-fast, make verify, make test-full, make verify-full, diff check, and UI evidence gates green | No release or push |

---

### Task 0: Capture the implementation baseline

**Files:**
- Read: git status, Makefile, the source/test files in the file map, and the current Obsidian review entry
- Create: ignored evidence under .build/stability-polish-baseline-<timestamp>/

**Interfaces:**
- Consumes: the clean reviewed commit and existing verification contract.
- Produces: a timestamped baseline record; no production mutation, helper action, fan command, or source edit.

- [ ] **Step 1: Confirm the source and disk state.**

Run:

~~~sh
git status --short --branch
git rev-parse HEAD
git diff --check
df -h /System/Volumes/Data
~~~

Expected: the only intentional worktree change is this plan document, HEAD is bea54ad64df36cfb9e86335966dabbbd0c94693e, diff check exits 0, and free space is at least 30 GiB.

- [ ] **Step 2: Run the focused baseline after the plan file is present.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter 'ViftyCoreTests\.(FanControlArbiterTests|ViftyDaemonClientTests|XPCAgentControlCodingTests|ViftyAccessibilitySemanticsTests|SettingsSceneSourceTests)'
~~~

Expected: the baseline remains green. If a test name is not accepted by the active SwiftPM toolchain, run the five suite filters separately and retain each command/output.

- [ ] **Step 3: Record the baseline without exposing sensitive data.**

Store only branch, commit, test counts, disk space, and command exit statuses under .build/stability-polish-baseline-<timestamp>/. Do not copy credentials, personal account rows, helper tokens, maintenance reports, or private logs into the repository.

### Task 1: Bound the lifecycle subprocess without weakening transaction safety

**Files:**
- Modify: Sources/Vifty/DaemonInstallService.swift, symbols DaemonInstallProcessRunner.system and DaemonInstallService.perform
- Modify: Sources/Vifty/DaemonInstaller.swift, symbol runSafeLifecycle
- Test: Tests/ViftyCoreTests/DaemonInstallServiceTests.swift
- Test: Tests/ViftyCoreTests/DaemonInstallerTests.swift

**Interfaces:**
- Produces: DaemonInstallProcessError.timedOut and DaemonInstallProcessRunner.system(timeout:) for deterministic lifecycle deadlines.
- Preserves: DaemonInstallProcessOutput, exit-status mapping 0/75/other, bounded 64 KiB output streams, bundled lifecycle script bytes, and the existing fail-closed UI outcome.

- [ ] **Step 1: Write the real-process timeout regression before changing the runner.**

Add a test using the existing temporary-script pattern:

~~~swift
func testSystemRunnerTimesOutAndCleansThePrivateProcessGroup() async throws {
    let script = FileManager.default.temporaryDirectory
        .appendingPathComponent("vifty-timeout-\(UUID().uuidString).sh")
    let childPIDFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("vifty-timeout-child-\(UUID().uuidString).pid")
    defer { try? FileManager.default.removeItem(at: script) }
    defer { try? FileManager.default.removeItem(at: childPIDFile) }
    try Data("""
    #!/bin/bash
    trap '' TERM
    (while :; do sleep 1; done) &
    echo $! > "\(childPIDFile.path)"
    while :; do sleep 1; done
    """.utf8).write(to: script)
    XCTAssertEqual(chmod(script.path, 0o755), 0)

    let startedAt = Date()
    do {
        _ = try await DaemonInstallProcessRunner.system(timeout: 0.2)
            .run(script, [], Data())
        XCTFail("Expected a bounded timeout")
    } catch let error as DaemonInstallProcessError {
        XCTAssertEqual(error, .timedOut)
    }
    XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    let childPID = try Int32(String(contentsOf: childPIDFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
    XCTAssertEqual(kill(childPID, 0), -1)
}
~~~

The test must also assert that the emitted child PID is gone before returning. Use kill(pid, 0) with a short bounded polling loop; do not leave a background fixture running after the assertion.
Write the shell PID and process-group ID to separate temporary files from the fixture and assert that the group ID differs from the test process group before cleanup; this proves the timeout cannot signal the host test process.

- [ ] **Step 2: Run only the new test against the current source.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter DaemonInstallServiceTests/testSystemRunnerTimesOutAndCleansThePrivateProcessGroup
~~~

Expected: the test does not compile because the timeout factory/error is absent, or it fails because the current runner waits indefinitely. That failure is the required red state.

- [ ] **Step 3: Add the smallest deadline and process-group contract.**

Implement these exact internal interfaces:

~~~swift
enum DaemonInstallProcessError: Error, Equatable, Sendable {
    case timedOut
    case processGroupUnavailable
}

extension DaemonInstallProcessRunner {
    static let defaultLifecycleTimeout: TimeInterval = 180

    static func system(
        timeout: TimeInterval = defaultLifecycleTimeout
    ) -> DaemonInstallProcessRunner
}
~~~

The system runner must:

1. Launch the existing /bin/bash invocation in a private process group and verify the child group identity before the lifecycle script can create descendants. Use Darwin posix_spawn attributes with POSIX_SPAWN_SETPGROUP and a zero process-group value if Foundation Process cannot guarantee pre-exec group creation; a setpgid call after process.run is not sufficient by itself. If the private group cannot be established, terminate the launched process and throw processGroupUnavailable.
2. Start both bounded readers before writing standard input. Close standard input exactly once after the complete script snapshot is written.
3. Poll process liveness using a monotonic deadline while the readers continue draining. Do not call unbounded waitUntilExit().
4. At the deadline, send SIGTERM to the private group, allow a 250 ms cleanup grace period so the lifecycle script's existing trap and cleanup run, then send SIGKILL to the same private group if any member remains. Wait only for that bounded cleanup and await both reader tasks before returning.
5. Throw timedOut after cleanup. Never convert a timeout into success, never retry the lifecycle script, and never expose captured stderr in the operator-facing message.
6. Keep the existing 64 KiB per-stream cap and the existing stdin-write cleanup path; the cleanup path must use the same private-group termination routine and must await readers.

Do not modify scripts/vifty-helper-lifecycle.sh in this task. Its embedded digest must remain unchanged.

- [ ] **Step 4: Map timeout to a blocked, fail-closed application result.**

In DaemonInstallService.perform, map timedOut to:

~~~swift
DaemonInstallResult(
    outcome: .blocked,
    operatorMessage: "Helper lifecycle timed out; fan writes stay blocked until helper state is verified."
)
~~~

Keep every other thrown error on the existing failed path. In DaemonInstaller.runSafeLifecycle, move the isWorking/canInstall reset into defer:

~~~swift
isWorking = true
canInstall = false
defer {
    isWorking = false
    canInstall = true
}
~~~

The defer must execute before awaiting installService.perform so a timeout or unexpected actor error cannot leave the button permanently disabled.

- [ ] **Step 5: Add the service and UI-state regressions.**

Add one injected-runner test proving a thrown timedOut error returns .blocked with the exact safe message, and one DaemonInstaller test proving isWorking == false and canInstall == true after a blocked result. Retain the existing tests proving raw launchctl output is not shown.

- [ ] **Step 6: Run the focused lifecycle suite.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter 'ViftyCoreTests\.(DaemonInstallServiceTests|DaemonInstallerTests)'
~~~

Expected: all lifecycle runner, output-drain, stdin-failure, hash, UI-state, and timeout tests pass. A failure that leaves a child process alive blocks the commit.

- [ ] **Step 7: Commit the independently reviewable lifecycle slice.**

~~~sh
git add Sources/Vifty/DaemonInstallService.swift Sources/Vifty/DaemonInstaller.swift Tests/ViftyCoreTests/DaemonInstallServiceTests.swift Tests/ViftyCoreTests/DaemonInstallerTests.swift
git commit -m "fix: bound helper lifecycle execution"
~~~

### Task 2: Bound SMAppService unregister completion and preserve fail-closed state

**Files:**
- Modify: Sources/Vifty/HelperServiceManagementBridge.swift, SystemHelperServiceManagementBackend.unregister
- Test: Tests/ViftyCoreTests/HelperServiceManagementBridgeTests.swift

**Interfaces:**
- Produces: a bounded unregister completion gate using the existing HelperServiceManagementBridgeError.transitionFailed error surface.
- Preserves: authorization/token checks, root evidence checks, native ServiceManagement usage, and final .notRegistered readback.

- [ ] **Step 1: Add a direct callback-gate timeout regression.**

Keep the existing HelperServiceBackendFixture for the bridge's authorization and final-state tests. Test the new internal callback gate directly with a start closure that never invokes its completion:

~~~swift
func testUnregisterCompletionTimeoutFailsClosedWithoutHanging() async throws {
    do {
        try await performServiceManagementUnregister(timeout: 0.05) { _ in }
        XCTFail("Expected unregister timeout")
    } catch let error as HelperServiceManagementBridgeError {
        guard case .transitionFailed(let message) = error else {
            return XCTFail("Unexpected bridge error: \(error)")
        }
        XCTAssertTrue(message.contains("timed out"))
    }
}
~~~

Add a second test whose start closure invokes success after the timeout and assert that the late callback does not crash or resume twice. This tests the actual continuation gate without requiring a live ServiceManagement registration.

Use this shape for the late-callback test:

~~~swift
func testUnregisterLateCallbackAfterTimeoutIsIgnored() async throws {
    do {
        try await performServiceManagementUnregister(timeout: 0.01) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
                completion(nil)
            }
        }
        XCTFail("Expected timeout")
    } catch {}
    try await Task.sleep(for: .milliseconds(100))
}
~~~

- [ ] **Step 2: Run the new test against the current source.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter HelperServiceManagementBridgeTests/testUnregisterCompletionTimeoutFailsClosedWithoutHanging
~~~

Expected: the test does not compile because performServiceManagementUnregister is absent, or it fails because the current checked continuation has no deadline. The bounded fixture must return within one second after implementation.

- [ ] **Step 3: Add a one-shot completion gate with a 30-second production deadline.**

Add this file-local helper and call it from SystemHelperServiceManagementBackend.unregister:

~~~swift
@MainActor
func performServiceManagementUnregister(
    timeout: TimeInterval = 30,
    start: (@escaping (Error?) -> Void) -> Void
) async throws
~~~

Before calling start, create a private NSLock-protected gate containing the checked continuation and a DispatchSourceTimer. The gate's single finish method must:

~~~swift
lock.lock()
guard !finished else {
    lock.unlock()
    return false
}
finished = true
let timer = retainedTimer
retainedTimer = nil
lock.unlock()
timer?.cancel()
continuationResult.resume()
return true
~~~

Schedule the timer for 30 seconds on a global queue. The timer finishes with HelperServiceManagementBridgeError.transitionFailed("SMAppService unregister timed out; registration state is not trusted."). The native completion finishes with the native error or success. A late native completion is ignored by the gate and cannot resume the continuation twice. On success, the existing bridge still performs the authoritative .notRegistered readback.

- [ ] **Step 4: Run the bridge suite and source contract.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter HelperServiceManagementBridgeTests
~~~

Expected: registration, approval, successful unregister, stuck readback, unknown state, legacy evidence, replay protection, and timeout tests pass.

- [ ] **Step 5: Commit the independently reviewable ServiceManagement slice.**

~~~sh
git add Sources/Vifty/HelperServiceManagementBridge.swift Tests/ViftyCoreTests/HelperServiceManagementBridgeTests.swift
git commit -m "fix: bound helper unregister completion"
~~~

### Task 3: Make XPC request cancellation and timer setup race-safe

**Files:**
- Modify: Sources/ViftyCore/ViftyDaemonClient.swift, private withProxy and CallbackState
- Test: Tests/ViftyCoreTests/ViftyDaemonClientTests.swift, FakeDaemonConnection

**Interfaces:**
- Produces: private DaemonRequestPolicy with .readOnly and .mutation cases; a cancellation-aware withProxy policy.
- Preserves: the existing 3-second read timeout, 125-second fan-control transaction timeout, one connection per request, error redaction, and connection invalidation after completion.

- [ ] **Step 1: Add the immediate-invalidation regression.**

Extend FakeDaemonConnection with an optional onResume closure and add:

~~~swift
func testImmediateInvalidationDuringResumeCompletesExactlyOnce() async {
    let connection = FakeDaemonConnection(proxy: FakeDaemonProxy())
    connection.onResume = {
        connection.fireInvalidation()
    }
    let client = ViftyDaemonClient(connectionFactory: { connection })

    do {
        _ = try await client.snapshot()
        XCTFail("Expected invalidation failure")
    } catch {
        XCTAssertTrue(error is ViftyError)
    }
    XCTAssertEqual(connection.resumeCount, 1)
    XCTAssertEqual(connection.invalidateCount, 1)
}
~~~

The fixture's fireInvalidation() must invoke the installed handler without incrementing invalidateCount; invalidate() remains the explicit client call. This distinguishes a synchronous remote invalidation from a client-initiated cleanup.

Add a source-order assertion beside the runtime test so the timer-retention race is observable without waiting for the three-second timer:

~~~swift
let source = try String(contentsOf: repositoryRoot.appendingPathComponent("Sources/ViftyCore/ViftyDaemonClient.swift"), encoding: .utf8)
let retainIndex = try XCTUnwrap(source.range(of: "state.retain(timer:"))
let resumeIndex = try XCTUnwrap(source.range(of: "connection.resume()"))
XCTAssertLessThan(retainIndex.lowerBound, resumeIndex.lowerBound)
~~~

Define repositoryRoot in this test from #filePath by deleting the three test/source parent directories, matching the repository-root helper used by the other source-contract tests.

- [ ] **Step 2: Run the race test against the current source.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter ViftyDaemonClientTests/testImmediateInvalidationDuringResumeCompletesExactlyOnce
~~~

Expected: the current setup has a timer-retention window because the connection is resumed before the timer is retained. The test must fail or expose the setup ordering before the implementation step.

- [ ] **Step 3: Install timer state before resuming the connection.**

Use this request setup order in withProxy:

1. Create the connection, state, handlers, and timer.
2. Schedule the timer and retain it in CallbackState before resume.
3. Obtain the remote proxy and install the operation callback.
4. Resume the connection.
5. Invoke the operation only if the one-shot state has not already finished.

Make CallbackState.finish the only place that marks completion and cancels/releases the timer. The invalidation handler, interruption handler, timeout handler, proxy error handler, and operation callback must all call that same one-shot method. A synchronous invalidation therefore cannot leave a live timer or double-resume the continuation.

- [ ] **Step 4: Add read-only task cancellation.**

Add:

~~~swift
private enum DaemonRequestPolicy: Sendable {
    case readOnly
    case mutation
}
~~~

Wrap only .readOnly requests in withTaskCancellationHandler. The cancellation box must invalidate the connection and finish with CancellationError(); the callback state prevents later XPC replies from resuming the continuation. Classify ping, snapshot, agentControlStatus, agentControlAudit, and fanControlOwnershipStatus as read-only. Classify setAgentControlEnabled, prepareAgentControl, restoreAgentControl, applyManualFanControl, restoreAllAuto, prepareHelperMaintenance, consumeHelperMaintenanceToken, cancelHelperMaintenance, and all restore paths as mutation. Give cancelHelperMaintenance the existing fanControlTransactionTimeout.

Mutation cancellation must not invalidate the connection or resume with a local cancellation error. The caller continues waiting for the remote completion or existing transaction timeout so authoritative daemon/readback semantics remain intact.

- [ ] **Step 5: Add cancellation behavior tests.**

Use a delayed FakeDaemonProxy callback and these assertions:

~~~swift
func testReadOnlyCancellationInvalidatesTheConnection() async {
    let replyGate = DispatchSemaphore(value: 0)
    let proxy = FakeDaemonProxy()
    proxy.snapshotHandler = { reply in
        DispatchQueue.global().async {
            replyGate.wait()
            reply(nil, "late snapshot")
        }
    }
    let connection = FakeDaemonConnection(proxy: proxy)
    let client = ViftyDaemonClient(connectionFactory: { connection })
    let task = Task { try await client.snapshot() }

    await Task.yield()
    task.cancel()
    do {
        _ = try await task.value
        XCTFail("Expected cancellation")
    } catch is CancellationError {}
    XCTAssertEqual(connection.invalidateCount, 1)
    replyGate.signal()
}

func testMutationCancellationWaitsForAuthoritativeReply() async throws {
    let replyGate = DispatchSemaphore(value: 0)
    let request = ManualFanControlRequest(
        transactionID: "cancellation-test",
        sessionID: "cancellation-test",
        expectedFanIDs: [0],
        targetRPMByFanID: [0: 3000],
        reason: "cancellation test"
    )
    let expected = FanControlTransactionResult(
        transactionID: request.transactionID,
        owner: .manual(sessionID: request.sessionID),
        phase: .active,
        expectedFanIDs: request.expectedFanIDs,
        confirmedFanIDs: request.expectedFanIDs
    )
    let proxy = FakeDaemonProxy()
    proxy.applyManualFanControlHandler = { _, reply in
        DispatchQueue.global().async {
            replyGate.wait()
            reply(XPCFanControlCoding.encode(expected), nil)
        }
    }
    let connection = FakeDaemonConnection(proxy: proxy)
    let client = ViftyDaemonClient(connectionFactory: { connection })
    let task = Task {
        try await client.applyManualFanControl(request)
    }

    await Task.yield()
    task.cancel()
    replyGate.signal()
    _ = try await task.value
    XCTAssertEqual(connection.invalidateCount, 1)
}
~~~

The mutation assertion counts only the normal completion invalidation; cancellation itself must not increment it before the daemon reply. Keep the existing slow mutation timeout test.

- [ ] **Step 6: Run the full daemon-client suite.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter ViftyDaemonClientTests
~~~

Expected: all existing protocol-v2 selector, timeout, maintenance, snapshot, ownership, and restore tests pass with the new race and cancellation tests.

- [ ] **Step 7: Commit the XPC lifecycle slice.**

~~~sh
git add Sources/ViftyCore/ViftyDaemonClient.swift Tests/ViftyCoreTests/ViftyDaemonClientTests.swift
git commit -m "fix: make daemon request lifecycle cancellation-safe"
~~~

### Task 4: Harden agent/fan wire decoding without changing safety policy

**Files:**
- Modify: Sources/ViftyCore/ViftyDaemonProtocol.swift, XPCFanControlCoding and XPCAgentControlCoding private decoders
- Test: Tests/ViftyCoreTests/XPCAgentControlCodingTests.swift
- Test: Tests/ViftyCoreTests/XPCFanControlCodingTests.swift

**Interfaces:**
- Produces: bounded, duplicate-rejecting RPM-map decoding and exact integer/boolean wire coercion.
- Preserves: fail-closed invalid-response behavior, existing JSON/XPC field names, known error-code schema, RPM policy limits, and agent cooling decisions.

- [ ] **Step 1: Add decoder regressions before changing the decoder.**

Add these tests:

~~~swift
func testAgentRPMMapRejectsNormalizedDuplicateFanIDsAndOversizedMaps() {
    let duplicate: NSDictionary = [
        "enabled": true,
        "lastDecision": [
            "allowed": true,
            "message": "Allowed",
            "targetRPMByFanID": ["01": 3000, "1": 3200],
            "warnings": []
        ]
    ]
    XCTAssertNil(XPCAgentControlCoding.decodeStatus(duplicate))

    let oversized = Dictionary(uniqueKeysWithValues: (0..<11).map { (String($0), 3000) })
    let decision: NSDictionary = [
        "allowed": true,
        "message": "Allowed",
        "targetRPMByFanID": oversized,
        "warnings": []
    ]
    XCTAssertNil(XPCAgentControlCoding.decodeStatus([
        "enabled": true,
        "lastDecision": decision
    ]))
}

func testWireDecodersRejectFractionalNumbersAndNumericBooleans() {
    XCTAssertNil(XPCAgentControlCoding.decodeStatus([
        "enabled": NSNumber(value: 2)
    ]))
    XCTAssertNil(XPCAgentControlCoding.decodeStatus([
        "enabled": NSNumber(value: 1.5)
    ]))
}
~~~

Expose no production test-only API. If the private decision decoder cannot be reached through decodeStatus, build the status fixture with lastDecision and assert the same nil result through the public decoder.

- [ ] **Step 2: Run the new tests against the current source.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter 'ViftyCoreTests\.(XPCAgentControlCodingTests|XPCFanControlCodingTests)'
~~~

Expected: the duplicate-normalization case currently decodes last-write-wins, and permissive NSNumber coercion currently accepts at least one invalid value. These failures establish the regression.

- [ ] **Step 3: Make RPM maps bounded and duplicate-safe.**

In XPCAgentControlCoding.decodeRPMMap, reject dictionaries over the existing maximum fan count of 10, reject a fan ID that already exists after Int(key) normalization, and reject non-integer or non-finite RPM values. Keep the current dictionary key format and do not add a new protocol version.

The loop must have the following logical guard:

~~~swift
guard let key = key as? String,
      let fanID = Int(key),
      let rpm = StrictXPCValue.integer(value),
      decoded[fanID] == nil else {
    return nil
}
~~~

- [ ] **Step 4: Centralize exact NSNumber conversion inside the existing protocol file.**

Add one private file-local helper with these exact entry points:

~~~swift
private enum StrictXPCValue {
    static func integer(_ value: Any?) -> Int?
    static func boolean(_ value: Any?) -> Bool?
}
~~~

Use StrictXPCValue.integer and StrictXPCValue.boolean from XPCFanControlCoding and XPCAgentControlCoding. The helper accepts Swift Int and Bool values, accepts NSNumber values only when their CoreFoundation type is the matching boolean or an integral numeric type, rejects NSNumber booleans for integer fields, rejects fractions, rejects non-finite values, and returns nil on Int range overflow. Replace the permissive intValue/boolValue calls in these two coding enums. Keep snapshot decoding behavior unchanged unless the new helper is directly required by a shared call site.

- [ ] **Step 5: Pin the unknown-error-code boundary.**

Add a test that places a future string in a decision errorCode and asserts decodeStatus returns nil. Do not add an unknown enum case or broaden the checked-in agent schemas in this slice; the existing behavior is intentionally fail-closed until a protocol/schema version can carry unknown-code semantics end-to-end.

Use:

~~~swift
func testUnknownAgentErrorCodeFailsClosed() {
    let dictionary: NSDictionary = [
        "enabled": true,
        "lastDecision": [
            "allowed": false,
            "errorCode": "FUTURE_SAFETY_STATE",
            "message": "Unknown",
            "targetRPMByFanID": [:],
            "warnings": []
        ]
    ]
    XCTAssertNil(XPCAgentControlCoding.decodeStatus(dictionary))
}
~~~

- [ ] **Step 6: Run the coding suites and agent JSON examples.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter 'ViftyCoreTests\.(XPCAgentControlCodingTests|XPCFanControlCodingTests|ViftyCtlJSONExampleTests)'
~~~

Expected: known status/decision examples round-trip byte-compatible fields, invalid wire values fail closed, and all existing JSON fixtures still decode.

- [ ] **Step 7: Commit the wire-contract slice.**

~~~sh
git add Sources/ViftyCore/ViftyDaemonProtocol.swift Tests/ViftyCoreTests/XPCAgentControlCodingTests.swift Tests/ViftyCoreTests/XPCFanControlCodingTests.swift
git commit -m "fix: reject ambiguous agent control wire values"
~~~

### Task 5: Replace the custom Settings rail with native macOS tabs

**Files:**
- Modify: Sources/Vifty/ViftySettingsView.swift
- Modify: Tests/ViftyCoreTests/SettingsSceneSourceTests.swift
- Modify: Tests/ViftyCoreTests/SettingsPresentationTests.swift
- Modify: Tests/ViftyCoreTests/ViftyAccessibilitySemanticsTests.swift only where the source contract names the removed rail

**Interfaces:**
- Produces: a native TabView(selection:) settings surface using ViftySettingsTab metadata, flexible minimum sizing, native tab roles, and the existing settings panes.
- Preserves: initialTab selection, pane order, pane scroll views, all settings controls, all accessibility identifiers, SettingsLink behavior, and no fan command from settings panes.

- [ ] **Step 1: Change the source contract first so it fails against the custom rail.**

Replace the custom-rail assertions with these source requirements:

~~~swift
XCTAssertTrue(settingsView.contains("TabView(selection:"))
XCTAssertTrue(settingsView.contains(".frame(minWidth: 600, minHeight: 420)"))
XCTAssertFalse(settingsView.contains("ViftySettingsTabStripLayout"))
XCTAssertFalse(settingsView.contains(".buttonStyle(.plain)"))
XCTAssertFalse(settingsView.contains(".frame(width: 600, height: 420)"))
for tab in ViftySettingsTab.allCases {
    XCTAssertTrue(settingsView.contains("ViftySettingsTab.\(tab.rawValue)"))
}
~~~

Replace the removed tab-width tests with metadata tests that assert the four cases preserve title, SF Symbol, and accessibility identifier values.

Use:

~~~swift
XCTAssertEqual(ViftySettingsTab.allCases.map(\.title), [
    "General", "Menu Bar", "Notifications", "Agent Workflows"
])
XCTAssertEqual(ViftySettingsTab.allCases.map(\.systemImage), [
    "gearshape", "menubar.rectangle", "bell", "terminal"
])
XCTAssertEqual(
    ViftySettingsTab.allCases.map(\.accessibilityIdentifier),
    [
        ViftyAccessibilityIdentifier.settingsTabGeneral,
        ViftyAccessibilityIdentifier.settingsTabMenuBar,
        ViftyAccessibilityIdentifier.settingsTabNotifications,
        ViftyAccessibilityIdentifier.settingsTabAgentWorkflows
    ]
)
~~~

- [ ] **Step 2: Run the Settings tests to establish the red state.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter 'ViftyCoreTests\.(SettingsSceneSourceTests|SettingsPresentationTests|ViftyAccessibilitySemanticsTests)'
~~~

Expected: the new native-navigation assertions fail while the current custom-rail behavior remains unchanged.

- [ ] **Step 3: Delete the bespoke layout and render native tabs.**

Remove ViftySettingsTabLayout, ViftySettingsTabWidthAllocation, ViftySettingsTabStripLayout, settingsSectionPicker, and the text-scale dependency that exists only for the rail. Render the four existing panes in a native TabView:

~~~swift
TabView(selection: $selectedTab) {
    SettingsGeneralView(model: model, softwareUpdates: softwareUpdates)
        .tabItem {
            Label(ViftySettingsTab.general.title, systemImage: ViftySettingsTab.general.systemImage)
                .accessibilityIdentifier(ViftySettingsTab.general.accessibilityIdentifier)
        }
        .tag(ViftySettingsTab.general)
    SettingsMenuBarView(model: model)
        .tabItem {
            Label(ViftySettingsTab.menuBar.title, systemImage: ViftySettingsTab.menuBar.systemImage)
                .accessibilityIdentifier(ViftySettingsTab.menuBar.accessibilityIdentifier)
        }
        .tag(ViftySettingsTab.menuBar)
    SettingsNotificationsView(model: model)
        .tabItem {
            Label(ViftySettingsTab.notifications.title, systemImage: ViftySettingsTab.notifications.systemImage)
                .accessibilityIdentifier(ViftySettingsTab.notifications.accessibilityIdentifier)
        }
        .tag(ViftySettingsTab.notifications)
    SettingsAgentWorkflowView(model: model)
        .tabItem {
            Label(ViftySettingsTab.agentWorkflows.title, systemImage: ViftySettingsTab.agentWorkflows.systemImage)
                .accessibilityIdentifier(ViftySettingsTab.agentWorkflows.accessibilityIdentifier)
        }
        .tag(ViftySettingsTab.agentWorkflows)
}
.accessibilityIdentifier(ViftyAccessibilityIdentifier.settingsTabs)
~~~

Keep the outer settings identifier and use:

~~~swift
.scenePadding()
.frame(minWidth: 600, minHeight: 420)
~~~

Apply each existing per-tab accessibility identifier to the native tab item or its stable native accessibility wrapper, whichever the live AX tree exposes on macOS 15. Do not reintroduce custom buttons to force an identifier. If the native tab item does not expose an identifier, attach the identifier to the corresponding pane root and update the AX predicate catalog only after a live readback proves the new element stable.

- [ ] **Step 4: Run the focused Settings tests.**

Run:

~~~sh
swift test --scratch-path "$PWD/.build" --filter 'ViftyCoreTests\.(SettingsSceneSourceTests|SettingsPresentationTests|ViftyAccessibilitySemanticsTests)'
~~~

Expected: source contracts pass, pane ordering remains General, Menu Bar, Notifications, Agent Workflows, all pane-level scroll contracts remain present, and settings sources still contain no FanCommand, setFixedFanRPM, or restoreAuto calls.

- [ ] **Step 5: Verify native keyboard and accessibility behavior in the live app.**

Build and open the local app:

~~~sh
make run-app
~~~

Inspect the Settings scene with the existing Accessibility collector/CUA workflow. Verify:

- the navigation reports native tab roles and selected state;
- Left/Right or Control-Tab navigation moves between settings sections without pointer input;
- VoiceOver/AX sees the section labels, selected state, and pane content once each;
- the window can grow beyond 600x420 and pane content remains scrollable;
- increased text scale does not clip the tab labels or pane controls;
- the four existing tab identifiers and the active pane identifier are present in the observed AX tree;
- opening Settings from the main window still targets the native Settings scene.

No fan-control action, helper repair, agent lease, or SMC operation is part of this check.

- [ ] **Step 6: Commit the UI slice only after live AX passes.**

~~~sh
git add Sources/Vifty/ViftySettingsView.swift Tests/ViftyCoreTests/SettingsSceneSourceTests.swift Tests/ViftyCoreTests/SettingsPresentationTests.swift Tests/ViftyCoreTests/ViftyAccessibilitySemanticsTests.swift
git commit -m "polish: use native macOS settings navigation"
~~~

If native tab semantics fail the live AX acceptance, do not weaken the accessibility contract. Leave the stability commits intact, record the exact observed failure, and make a separate UI-only follow-up decision.

### Task 6: Run the repository gates and publish an evidence-backed review note

**Files:**
- Create after implementation: docs/reviews/2026-09-14-vifty-stability-and-macos-polish.md
- Read only: release metadata, workflow, signing, schema, and validation files unless a gate identifies a real contract mismatch

**Interfaces:**
- Consumes: the three committed implementation slices and current installed/local UI observations.
- Produces: reproducible verification evidence and an explicit claim/non-claim record; no release or hardware mutation.

- [ ] **Step 1: Run the cheap repository checks.**

Run:

~~~sh
git diff --check
df -h /System/Volumes/Data
swift test --scratch-path "$PWD/.build" --filter 'ViftyCoreTests\.(DaemonInstallServiceTests|DaemonInstallerTests|HelperServiceManagementBridgeTests|ViftyDaemonClientTests|XPCAgentControlCodingTests|XPCFanControlCodingTests|SettingsSceneSourceTests|SettingsPresentationTests|ViftyAccessibilitySemanticsTests)'
~~~

Expected: all focused suites pass and the disk guardrail remains satisfied.

- [ ] **Step 2: Run the fast trust gate.**

Run:

~~~sh
make verify SWIFT_BUILD_PATH="$PWD/.build"
~~~

Expected: fast tests, warnings-as-errors build, bundle, schema resources, plist, codesign structure, release metadata, community files, and identifier gates pass.

- [ ] **Step 3: Run the full CI-facing gate.**

Run:

~~~sh
make verify-full SWIFT_BUILD_PATH="$PWD/.build"
~~~

Expected: the full XCTest suite, Ruby release/lifecycle/UI contract suites, bundle checks, and verification gates pass. Do not create a release tag when this gate fails.

- [ ] **Step 4: Re-run the existing automated UI evidence checks.**

Run:

~~~sh
make ui-review-start-session
make ui-review-verify-automated
~~~

Capture at least the main workbench, Settings General, Settings Agent Workflows, dark mode, increased text scale, and the existing main-window accessibility rows. Bind every accepted row to the exact source commit. Keep any missing human VoiceOver or system-setting row pending rather than promoting it.

- [ ] **Step 5: Write the review note with exact evidence boundaries.**

The review note must include:

- source commits for each slice;
- focused test commands and counts;
- make verify and make verify-full exit status;
- UI evidence session/build provenance and current AX observations;
- the specific native Settings interaction result;
- explicit non-claims: no new helper install, no SMC write, no Auto restoration, no Fixed/Curve hardware acceptance, no new notarization, no release publication, and no cross-Mac compatibility claim.

- [ ] **Step 6: Commit only the evidence note.**

~~~sh
git add docs/reviews/2026-09-14-vifty-stability-and-macos-polish.md
git commit -m "docs: record stability and settings validation"
~~~

## Completion criteria

The work is complete only when all of these are true:

1. Helper lifecycle processes no longer wait indefinitely, drain bounded output, clean up only their private process group, map timeout to a blocked state, and never retry a timed-out privileged operation.
2. SMAppService unregister cannot leave a checked continuation pending forever; late callbacks are ignored after the one-shot timeout gate, and final registration state is still required.
3. Read-only XPC requests respond to task cancellation; mutation requests remain transaction-bound and are not locally aborted; immediate invalidation cannot leak a timer or double-resume.
4. Agent RPM maps reject normalized duplicates and oversized payloads; numeric wire coercion is exact; unknown error codes still fail closed and remain schema-consistent.
5. Settings use native macOS tab semantics, flexible minimum sizing, stable pane scroll behavior, and live-verified accessibility identifiers without reintroducing custom navigation buttons.
6. Focused tests, make verify, make verify-full, diff checks, and the relevant UI evidence checks pass.
7. The final review note distinguishes repository proof, live UI proof, and hardware/release non-claims.

## Intentionally deferred

- No direct physical Fixed RPM or Temperature Curve acceptance; that requires a supervised supported-hardware run and fresh daemon readback.
- No helper install or 1Password/macOS administrator authorization flow; this plan is source, test, and read-only UI evidence work.
- No release tag, public artifact, cask update, notarization, or merge.
- No broader visual redesign, Figma asset import, Liquid Glass adoption, telemetry expansion, or settings content rewrite.
