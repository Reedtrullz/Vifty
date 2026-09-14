# Vifty Stability and macOS Polish — Verification Report

**Plan:** docs/superpowers/plans/2026-09-14-vifty-stability-and-macos-polish.md
**Branch:** codex/vifty-stability-polish-sdd
**Baseline:** 6294fef (1,392 fast tests, 0 failures, 64 GiB free)
**Final commit:** c7f574e (post-review unregister gate fix)
**Date:** 2026-09-14

## Source / Unit Tests

### Implementation slice commits

| Slice | Commit | Description |
|-------|--------|-------------|
| Baseline | 6294fef | Plan document committed; 1,392 fast tests green |
| Lifecycle | ac3bbc4 | Bounded helper lifecycle execution with private process group cleanup |
| Lifecycle fix | b521d6c | SIGKILL escalation preserved in catch path |
| Unregister gate | 7519d48 | SMAppService unregister completion bounded with one-shot timeout |
| XPC lifecycle | c5135e0 | Read-only cancellation invalidation; mutation requests remain transaction-bound |
| Wire hardening | ad908fe | RPM map duplicate rejection, strict NSNumber coercion, unknown-error fail-closed |
| Settings UI | c1fac50 | Native macOS TabView settings navigation |
| Test fix | 7f52943 | Frame expectation updated from .frame(width:height:) to .frame(minWidth:minHeight:) |
| Review fix | c7f574e | Start native unregister before awaiting completion; close the continuation race |

### Focused test results

Pre-fix make test-fast ran 1,399 tests with exactly two stale frame-string failures in AppArchitectureBoundaryTests and ViftyReviewFixtureTests. Both failures matched the intentional Task 5 change from .frame(width: 600, height: 420) to .frame(minWidth: 600, minHeight: 420).

Post-fix focused boundary tests: 70/70 passed (0 failures) across AppArchitectureBoundaryTests, ViftyReviewFixtureTests, SettingsSceneSourceTests, SettingsPresentationTests, and ViftyAccessibilitySemanticsTests.

Final-review remediation: HelperServiceManagementBridgeTests passed 11/11 after adding the immediate native-completion regression test. The fix starts the native unregister operation before awaiting the completion gate and resumes a continuation immediately if the gate already finished synchronously or by timeout.

Post-fix whole-branch re-review: no Critical or Important issues remained. The reviewer confirmed synchronous completion, timeout-before-continuation, late callback, and native-error propagation behavior.

Per-slice focused suites (all green):

- DaemonInstallServiceTests + DaemonInstallerTests: lifecycle timeout, process-group cleanup, output drain, blocked-state mapping
- HelperServiceManagementBridgeTests: unregister completion gate, late-callback safety
- ViftyDaemonClientTests: protocol-v2 selectors, timeout, cancellation, maintenance
- XPCAgentControlCodingTests + XPCFanControlCodingTests: duplicate-map rejection, strict-number coercion, unknown-error fail-closed, JSON fixture round-trip
- SettingsSceneSourceTests + SettingsPresentationTests + ViftyAccessibilitySemanticsTests: native TabView contracts, pane ordering, scroll behavior, identifier catalog

### make verify (fast trust gate)

make verify was run before the test fix and passed. It covers shell syntax checks, community/support surface, release metadata validation, fast XCTest suite (1,399 tests at that point, minus the two stale failures), warnings-as-errors build, release app bundle including schema resources, plist lint, codesign verification, and viftyctl identifier checks.

The post-review helper-gate fix was validated with its focused 11-test suite; the full make verify gate was not rerun after that focused remediation.

### make verify-full (CI-facing gate)

make verify-full was interrupted with SIGTERM during InstallReplacementPreflightScriptTests. It is incomplete and must not be treated as a pass. The interruption was external to the implementation; no test failure was observed before termination.

## Live UI Evidence

The native Settings UI evidence step (Task 6 Step 4) was not re-run in this bookkeeping pass because the earlier Task 5 live UI/AX evidence is already recorded in the progress ledger and task-5 report.

Known limitation from Task 5 Ruling: macOS 15 live AX exposed native toolbar buttons rather than the custom tab identifiers/selected state. Keyboard navigation and resize/text-scale evidence was incomplete. The stability commits are preserved; the native settings navigation may need a later AppKit/accessibility bridge before full keyboard/AX acceptance.

## Hardware / Runtime Evidence

No hardware or runtime claims are made. The implementation is source, test, and read-only UI evidence work. The following remain unproven from this plan:

- No new helper install or 1Password/macOS administrator authorization flow
- No SMC fan write or Auto restoration
- No Fixed RPM or Temperature Curve hardware acceptance
- No supervised supported-hardware daemon readback

## Release Evidence

No release evidence is claimed. The following remain unchanged:

- No release tag, public artifact, or cask update
- No notarization or signing changes
- No Homebrew metadata changes
- No cross-Mac compatibility claim

## Non-Claims Summary

- No new helper install
- No SMC write
- No Auto restoration
- No Fixed/Curve hardware acceptance
- No notarization
- No release publication
- No cross-Mac compatibility
- make verify-full is incomplete (SIGTERM interruption)
- Live UI/AX acceptance is pending a follow-up (Task 5 Ruling)

## Verification Commands

    git diff --check                          # clean
    df -h /System/Volumes/Data                # 62 GiB free
    swift test --scratch-path "$PWD/.build" --filter 'ViftyCoreTests.(AppArchitectureBoundaryTests|ViftyReviewFixtureTests|SettingsSceneSourceTests|SettingsPresentationTests|ViftyAccessibilitySemanticsTests)'  # 70/70 passed
    swift test --scratch-path "$PWD/.build" --filter 'ViftyCoreTests.HelperServiceManagementBridgeTests'  # 11/11 passed after c7f574e
    make verify                                # passed (pre-test-fix)
