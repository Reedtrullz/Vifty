# Vifty Stage 2 Operational Truth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make hardware readiness, audit persistence, CLI discovery, and compiler gates report exactly what is known.

**Architecture:** Reuse Stage 1's persistence-health object, pass snapshot availability into the existing readiness builder, add one pure help command, and put warnings-as-errors directly on the two existing test targets. Preserve JSON field names and exit codes unless the schema is explicitly advanced in the same commit.

**Tech Stack:** Swift 6, Foundation, XCTest, JSON Schema fixtures, Make, Swift Package Manager.

**Spec:** `docs/superpowers/specs/2026-09-06-vifty-audit-remediation-design.md`

## Global Constraints

- Stage 1 must be approved and green first.
- No third-party dependency or privileged/hardware operation.
- Preserve `policyStatusAvailable`, `safeToRequestCooling`, blocker IDs, recovery actions, and exit-code contracts.

---

### Task 1: Distinguish unavailable from unsupported hardware

**Files:**
- Modify: `Sources/ViftyCore/AgentDiagnostics.swift`
- Test: `Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift`
- Test: `Tests/ViftyCoreTests/ViftyCtlJSONExampleTests.swift`

**Interfaces:**
- Produces: `supportedHardwareCheck(_:snapshotError:)` with supported, unsupported, and unavailable copy.

- [ ] **Step 1: Add failing diagnostic cases**

For a snapshot error, assert the `supportedHardware` message contains “could not be determined” and does not contain “supported only”. For a successful Intel/non-MacBook snapshot, retain the unsupported message and blocker.

- [ ] **Step 2: Run the focused failure**

Run: `swift test --scratch-path "$PWD/.build" --filter 'ViftyCtlRunnerTests|ViftyCtlJSONExampleTests'`

Expected: unavailable case is mislabeled unsupported.

- [ ] **Step 3: Pass the existing error into the check**

```swift
private static func supportedHardwareCheck(
    _ snapshot: HardwareSnapshot,
    snapshotError: String?
) -> ViftyCtlReadinessCheck
```

If `snapshotError != nil`, return `passed: false` with unavailable copy. Otherwise evaluate the two hardware booleans exactly as today. Keep the stable check ID so existing agent blocker processing remains compatible.

- [ ] **Step 4: Run tests and commit**

Run: `swift test --scratch-path "$PWD/.build" --filter 'ViftyCtlRunnerTests|ViftyCtlJSONExampleTests'`

```bash
git add Sources/ViftyCore/AgentDiagnostics.swift Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift Tests/ViftyCoreTests/ViftyCtlJSONExampleTests.swift
git commit -m "fix: report unavailable hardware truthfully"
```

### Task 2: Surface audit persistence health

**Files:**
- Modify: `Sources/ViftyCore/AgentControlService.swift`
- Modify: `Sources/ViftyCore/ViftyCoreLog.swift`
- Modify: `Sources/ViftyCore/AgentDiagnostics.swift`
- Modify: `Sources/Vifty/AppModel+Control.swift`
- Modify: `Sources/Vifty/SettingsAgentWorkflowView.swift`
- Test: `Tests/ViftyCoreTests/AgentControlServiceTests.swift`
- Test: `Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift`
- Test: `Tests/ViftyCoreTests/AppModelFanControlTests.swift`
- Test: `Tests/ViftyCoreTests/AppSourceRegressionTests.swift`

**Interfaces:**
- Consumes: `AgentControlStatus.persistenceHealth` from Stage 1.
- Produces: last audit append failure and later recovery without changing fan transaction results.

- [ ] **Step 1: Extend the Stage 1 fault store and add red tests**

Make `appendAuditEvent` fail once, then succeed. Assert the first status has `auditStatusAvailable == false`, the next successful append restores it to true, and a successful mocked fan transaction still returns success.

- [ ] **Step 2: Run service tests and verify health remains falsely green**

Run: `swift test --scratch-path "$PWD/.build" --filter AgentControlServiceTests`

- [ ] **Step 3: Replace swallowed append with bounded health state**

```swift
private func appendAudit(...) {
    do {
        try store.appendAuditEvent(event)
        auditPersistenceErrorMessage = nil
    } catch {
        auditPersistenceErrorMessage = String(error.localizedDescription.prefix(512))
        ViftyCoreLog.agentControl.error("Agent audit persistence failed")
    }
}
```

Add `static let agentControl = Logger(subsystem: "tech.reidar.vifty", category: "AgentControl")` beside the existing core XPC logger. Build `status().persistenceHealth` from policy and audit health. Do not throw from `appendAudit` and do not replace a fan/restore `lastErrorCode`.

- [ ] **Step 4: Add diagnostic and UI presentation**

Keep the existing readiness-check ID set stable. Diagnose and status already embed `AgentControlStatus`, so expose audit health through its `persistenceHealth` object and surface concise attention copy in the existing agent settings/status area. Do not let audit availability change `safeToRequestCooling`, authorize cooling, reverse fan control, or overwrite a higher-priority fan/restore error.

- [ ] **Step 5: Run focused tests and commit**

Run: `swift test --scratch-path "$PWD/.build" --filter 'AgentControlServiceTests|ViftyCtlRunnerTests|AppModelFanControlTests|AppSourceRegressionTests'`

```bash
git add Sources/ViftyCore/AgentControlService.swift Sources/ViftyCore/ViftyCoreLog.swift Sources/ViftyCore/AgentDiagnostics.swift Sources/Vifty/AppModel+Control.swift Sources/Vifty/SettingsAgentWorkflowView.swift Tests/ViftyCoreTests/AgentControlServiceTests.swift Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift Tests/ViftyCoreTests/AppModelFanControlTests.swift Tests/ViftyCoreTests/AppSourceRegressionTests.swift
git commit -m "fix: expose agent audit persistence failures"
```

### Task 3: Add deterministic CLI help

**Files:**
- Modify: `Sources/ViftyCore/ViftyCtlArguments.swift`
- Modify: `Sources/ViftyCore/ViftyCtlRunner.swift`
- Modify: `docs/agent-workflows.md`
- Test: `Tests/ViftyCoreTests/ViftyCtlArgumentsTests.swift`
- Test: `Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift`

**Interfaces:**
- Produces: `ViftyCtlCommand.help` and `ViftyCtlArguments.usage`.

- [ ] **Step 1: Add parser and output tests**

Assert `help`, `--help`, and `-h` parse to `.help`; running `.help` returns exit 0 and identical text ending in a newline. Assert `frobnicate` still throws `.unknownCommand`.

- [ ] **Step 2: Run the red tests**

Run: `swift test --scratch-path "$PWD/.build" --filter 'ViftyCtlArgumentsTests|ViftyCtlRunnerTests'`

- [ ] **Step 3: Add the command and one usage string**

```swift
public static let usage = """
Usage: viftyctl <command> [options]
Commands: status, capabilities, agent-rule, diagnose, audit, prepare, restore-auto, run
Run 'viftyctl agent-rule' for the guarded agent workflow.
"""
```

Handle aliases in `parse`, return the usage from `ViftyCtlRunner`, add `.help` to command-name/JSON switches, and keep helper-maintenance commands out of public help.

- [ ] **Step 4: Verify the built executable**

Run: `bin_dir="$(swift build --scratch-path "$PWD/.build" --show-bin-path)" && for arg in help --help -h; do "$bin_dir/viftyctl" "$arg"; done`

Expected: three identical outputs and three zero exits.

- [ ] **Step 5: Commit**

```bash
git add Sources/ViftyCore/ViftyCtlArguments.swift Sources/ViftyCore/ViftyCtlRunner.swift docs/agent-workflows.md Tests/ViftyCoreTests/ViftyCtlArgumentsTests.swift Tests/ViftyCoreTests/ViftyCtlRunnerTests.swift
git commit -m "feat: add viftyctl help"
```

### Task 4: Enforce warning-free test compilation

**Files:**
- Modify: `Tests/ViftyCoreTests/AgentControlServiceTests.swift`
- Modify: `Makefile`
- Modify: `Tests/ViftyCoreTests/MakefileTrustGateTests.swift`

**Interfaces:**
- Produces: `SWIFT_TEST_WARNING_ARGS = -Xswiftc -warnings-as-errors` used by both test targets.

- [ ] **Step 1: Pin the intended Makefile contract in a failing test**

Assert both `swift test` invocations include `$(SWIFT_TEST_WARNING_ARGS)` and the variable equals `-Xswiftc -warnings-as-errors`.

- [ ] **Step 2: Run the trust-gate test**

Run: `swift test --scratch-path "$PWD/.build" --filter MakefileTrustGateTests`

Expected: FAIL because the argument is absent.

- [ ] **Step 3: Remove the known warning and wire the flag once**

Change `let status = try await service.status()` to `let status = await service.status()`. Add the named Make variable and use it in `test-fast` and `test-full`; do not duplicate a second test target.

- [ ] **Step 4: Run the warning gate**

Run: `make test-fast`

Expected: exit 0 with test sources compiled under warnings-as-errors.

- [ ] **Step 5: Commit**

```bash
git add Tests/ViftyCoreTests/AgentControlServiceTests.swift Makefile Tests/ViftyCoreTests/MakefileTrustGateTests.swift
git commit -m "test: reject Swift test warnings"
```

### Task 5: Stage 2 verification checkpoint

**Files:**
- Verify schemas, fixtures, docs, and bundles.

- [ ] **Step 1: Run diff and JSON checks**

Run: `git diff --check && plutil -lint Resources/Info.plist`

- [ ] **Step 2: Run the fast trust gate**

Run: `make verify`

Expected: tests, warnings-as-errors build, bundle, plist, codesign, schema resources, and identifiers pass.

- [ ] **Step 3: Inspect CLI compatibility**

Run: `stage2_tmp="$(mktemp -d)"; trap 'rm -rf "$stage2_tmp"' EXIT; .build/Vifty.app/Contents/MacOS/viftyctl --help && .build/Vifty.app/Contents/MacOS/viftyctl diagnose --json >"$stage2_tmp/diagnose.json"; status=$?; /usr/bin/python3 -m json.tool "$stage2_tmp/diagnose.json" >/dev/null; test "$status" -eq 0 -o "$status" -eq 75`

Expected: help exits 0; diagnose is parseable and either ready or safely blocked. Do not run recovery commands.

- [ ] **Step 4: Review Stage 2 before UI work**

Review the Stage 2 commit range and confirm stable existing JSON keys and exit codes. Record any schema addition explicitly; do not begin Stage 3 with a failing gate.
