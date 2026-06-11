# Vifty Comprehensive Audit — 2026-06-07

**Repo**: `/Users/reidar/Projectos/Vifty` | **HEAD**: `0ac319e2047ce6e2d7cefb985b9c2fe3574e0ccb`
**Audit date**: 2026-06-07 | **CI**: ✅ `27097640371` completed success
**Tests**: 127 passing, 0 failures | **Build**: clean with `-warnings-as-errors`

Three parallel specialist tracks: (A) Swift code quality + concurrency, (B) Security + architecture, (C) Infrastructure + GitHub Community Standards.

---

## Summary

Vifty is a well-engineered Swift 6 macOS app with strong fundamentals: clean actor-based concurrency, comprehensive XPC protocol design, lease-based agent control safety, and excellent documentation (README, AGENTS.md, CONTRIBUTING.md, SECURITY.md). The 127-test suite is thorough for a hardware-touching project.

The audit found **2 critical issues**, **9 high issues**, **9 medium issues**, and **17 low observations**. The most important gaps are in XPC identity validation security (pid-based TOCTOU, ad-hoc signing spoofability) and missing GitHub Community Standards files.

---

## Critical Issues

### [SEC-C1] `XPCConnectionIdentityExtractor` uses PID-based identity — TOCTOU race
- **File**: `Sources/ViftyDaemon/XPCConnectionIdentityExtractor.swift:11`
- **Severity**: Critical
- **Detail**: Uses `SecCodeCopyGuestWithAttributes(kSecGuestAttributePid, pid)` — vulnerable to time-of-check-time-of-use: a connecting process can `execve()` after connection but before validation, keeping the same PID while changing code identity. Apple recommends `kSecGuestAttributeAuditToken` (the audit token includes an exec-generation counter). Vifty targets macOS 15, so `connection.auditToken` is fully available.
- **Fix**: Switch to `SecCodeCopyGuestWithAttributes(kSecGuestAttributeAuditToken, auditToken)` or use `SecCodeCheckValidity` with the audit token.

### [SEC-C2] XPC validator rejects validly-signed clients when TeamID is nil
- **File**: `Sources/ViftyCore/XPCClientValidator.swift:50`
- **Severity**: Critical (latent DoS)
- **Detail**: When `allowedClient.teamIdentifier == nil`, the validator requires `identity.teamIdentifier == nil`. For ad-hoc builds this works. But if Vifty is ever signed with an Apple Developer ID (TeamID becomes non-nil), the daemon will reject ALL connections because both allowedClients use `teamIdentifier: nil`. The intended "don't care about team" behavior should return `true` for the team check, not require nil.
- **Fix**: When `allowedClient.teamIdentifier == nil`, skip the team check entirely (return `true`), matching the documented intent of "signing-identifier-only matching."

---

## High Issues

### [SEC-H1] XPC signing-identifier-only validation provides zero security against local attacker
- **File**: `Sources/ViftyDaemon/main.swift:124-127`
- **Severity**: High
- **Detail**: The allowedClients list accepts `signingIdentifier: "tech.reidar.vifty"` and `"tech.reidar.vifty.ctl"` with no TeamID. Since the app is ad-hoc signed, ANY process can ad-hoc sign itself with `codesign --force --sign - --identifier tech.reidar.vifty.ctl /path/to/malicious` and connect. Without a TeamID anchor or provisioning profile check, the signing-identifier check provides no real security.
- **Fix**: Add a TeamID requirement (even for development, use a personal team). Hard-code the expected TeamID(s) or read them from a build-configuration file. For distribution, use provisioning profile validation.

### [SEC-H2] No entitlements files — App Sandbox and Hardened Runtime missing
- **Files**: No `.entitlements` files exist in the repo
- **Severity**: High
- **Detail**: `Package.swift` has no entitlements settings. Missing: App Sandbox (limits blast radius of app compromise), Hardened Runtime (prevents dylib injection), and explicit XPC entitlements. The daemon runs as root with zero sandbox constraints.
- **Fix**: Create `Resources/Vifty.entitlements` with App Sandbox + Hardened Runtime, `Resources/ViftyDaemon.entitlements` with minimal daemon entitlements, and reference them in `Package.swift`.

### [SEC-H3] LaunchDaemon plist lacks security hardening
- **File**: `Resources/tech.reidar.vifty.daemon.plist`
- **Severity**: High
- **Detail**: Missing: `LowPriorityIO`, `ProcessType`, `Nice`, sandbox profile reference, `UserName` documentation, `Umask`, `LaunchOnlyOnce`, `ThrottleInterval`.
- **Fix**: Add `LowPriorityIO=true`, `ProcessType=Background`, `Umask=077`, and document root requirement. Consider a sandbox profile.

### [SEC-H4] Agent control store uses world-readable permissions
- **File**: `Sources/ViftyCore/AgentControlStore.swift:20-22,66-68`
- **Severity**: High
- **Detail**: Directory created with default `0o755`, files with `0o644`. On multi-user Macs, other users can read active lease details (workload types, RPM targets, timing patterns, audit history).
- **Fix**: Set `0o700` on directory, `0o600` on files using `FileManager.default.setAttributes`.

### [SEC-H5] `viftyctl run` inherits user PATH — potential injection
- **File**: `Sources/ViftyCtl/main.swift:48-49`
- **Severity**: High
- **Detail**: `ViftyCtlProcessRunner.run()` uses `/usr/bin/env` to resolve commands via PATH. Since `run` prepares a cooling lease BEFORE launching the child, a compromised PATH could cause a malicious binary to receive the cooling boost intended for the actual workload.
- **Fix**: Resolve the executable to a full path before execution, or require an explicit `--exec-path` for `run` mode.

### [CODE-H1] Force-unwrap of Optional in ViftyHelper async-to-sync bridge
- **File**: `Sources/ViftyHelper/main.swift:95`
- **Severity**: High
- **Detail**: `box.result!.get()` force-unwraps. Safe under current thread flow (semaphore ensures result is set), but fragile — any refactoring could introduce a crash.
- **Fix**: Replace with `guard let result = box.result else { fatalError("...") }` or a throwing pattern.

### [CODE-H2] Silent `try?` error swallowing in rollback path
- **File**: `Sources/ViftyCore/AgentControlService.swift:142`
- **Severity**: High
- **Detail**: During prepare rollback, `try? await hardware.restoreAuto(fan: fan)` silently swallows errors. If rollback fails, the fan stays at agent-controlled speed with no lease tracking. Audit log captures attempt, but fan state is not guaranteed restored.
- **Fix**: Log rollback failures specifically and consider a retry mechanism or alert path.

### [CODE-H3] Silent `try?` in LocalFanHelperClient.restoreAuto
- **File**: `Sources/ViftyCore/LocalFanHelperClient.swift:25`
- **Severity**: High
- **Detail**: `try? smc.write(...)` for target RPM during restoreAuto silently fails. Mode write at line 23 throws correctly, but the target write does not.
- **Fix**: Either throw the error or log it explicitly.

### [INFRA-H1] Missing GitHub Community Standards files
- **Files**: Not present
- **Severity**: High
- **Detail**: GitHub flags repositories missing these. Vifty is missing: CODE_OF_CONDUCT.md, `.github/ISSUE_TEMPLATE/` (bug report + feature request templates), and `.github/PULL_REQUEST_TEMPLATE.md`. These are the three that GitHub explicitly surfaces in the Community profile health check and would block an "all standards met" badge.
- **Fix**: Add all three. For CODE_OF_CONDUCT, adopt Contributor Covenant. For issue templates, create bug-report and feature-request forms. For PR template, reference CONTRIBUTING.md requirements.

---

## Medium Issues

### [CODE-M1] AppModel.stop() Task captures self strongly
- **File**: `Sources/Vifty/AppModel.swift:68,83-86`
- **Detail**: `Task { await coordinator.forceAuto(); await syncState() }` without `[weak self]`. Acceptable under `@MainActor` but defensive `[weak self]` would be cleaner.

### [CODE-M2] CurveProfileStore silently swallows all I/O errors
- **File**: `Sources/ViftyCore/CurveProfileStore.swift:13-37`
- **Detail**: All file operations use `try?`, suppressing disk-full, permission, and encoding errors. Users won't know if profiles failed to save.

### [CODE-M3] @preconcurrency import Foundation is file-wide
- **File**: `Sources/ViftyCore/ViftyDaemonClient.swift:1`
- **Detail**: Suppresses concurrency warnings for `NSXPCConnection`. Justified by NSLock in CallbackState, but file-wide suppression could mask future issues.

### [CODE-M4] FanCurve re-sorts points on every targetRPM call
- **File**: `Sources/ViftyCore/FanCurve.swift:204-205`
- **Detail**: `points` is `var` on a struct and re-sorted on every call even though `init` already sorts. Minor performance concern.

### [SEC-M1] SMCClient.write() has no key allowlist at the IOKit layer
- **File**: `Sources/ViftyCore/SMCClient.swift:143-162`
- **Detail**: Accepts arbitrary SMC key strings. If daemon code execution is achieved, arbitrary SMC writes could damage hardware. The daemon's setFixedRPM restricts keys, but defense-in-depth should add an allowlist at the IOKit layer.

### [SEC-M2] Daemon logs to world-readable /tmp
- **File**: `Resources/tech.reidar.vifty.daemon.plist:16-18`
- **Detail**: `StandardOutPath` and `StandardErrorPath` point to `/tmp/tech.reidar.vifty.daemon.{out,err}.log` — world-readable.

### [SEC-M3] Daemon creates two independent RealMacHardwareService instances
- **File**: `Sources/ViftyDaemon/main.swift:5-9`
- **Detail**: Two separate SMC connections. Wastes resources and creates race potential.

### [SEC-M4] Task.sleep-based lease expiry under cooperative concurrency
- **File**: `Sources/ViftyCore/AgentControlService.swift:189-197`
- **Detail**: Under extreme CPU load, Swift concurrency may delay Task wakeups beyond intended expiry, allowing leases to persist past expiration.

### [INFRA-M1] No `make clean`, `make test`, or `make help` targets
- **File**: `Makefile`
- **Detail**: Only `clean-app` and `clean-pkg` exist. No universal `clean`. No `test` target. No `help` for contributor onboarding.

### [INFRA-M2] No SPM dependency/cache warm-up in CI
- **File**: `.github/workflows/ci.yml`
- **Detail**: CI runs from scratch each time. Adding `actions/cache` for `.build/` would cut CI time significantly.

### [INFRA-M3] No CD / release workflow for tagged releases
- **File**: `.github/workflows/` (missing)
- **Detail**: Tag `v1.0.0` exists but has no release assets. A `workflow_dispatch` or `on: push: tags: v*` workflow would automate GitHub Release creation with the app bundle attached.

---

## Low / Observations

- **[CODE]** `@unchecked Sendable` annotations well-justified for SMCClient, RealMacHardwareService, XPCConnectionHandle, CallbackState. One unnecessary `@unchecked Sendable` on CurveProfileStore (URL is Sendable).
- **[CODE]** ContentView.swift is 611 lines — the largest file. Consider extracting sub-views into a `Views/` directory.
- **[CODE]** CurveProfileStore post-save backup-ensure (lines 35-38) is partially redundant with pre-save backup (lines 25-29).
- **[CODE]** `AppModel.fanAccessMessage` ternary is dense; a helper function would improve readability.
- **[CODE]** `awaitSnapshot()` name in DaemonService is misleading (synchronous call, not async).
- **[CODE]** `XPCClientIdentity.isPlatformBinary` is populated but unused in validation logic.
- **[SEC]** Curve profile store and ManualControlMarker sentinel file also use default (world-readable) permissions.
- **[SEC]** AgentControlService `beginOperation()` rejects concurrent calls rather than queueing — could cause spurious "operation in progress" errors under load.
- **[SEC]** Policy default `maxDurationSeconds` of 3600 (1 hour) is generous; 15-30 minutes would reduce blast radius.
- **[SEC]** ViftyHelper uses `DispatchSemaphore` to bridge async/sync — known anti-pattern that can cause priority inversions.
- **[SEC]** SECURITY.md is excellent: identifies trust boundaries, in-scope/out-of-scope, private reporting via GitHub Advisories.
- **[SEC]** `Fan.percentage` division-by-zero guard present — good.
- **[SEC]** AgentControlPolicy denies non-Apple-Silicon MacBook Pro — good.
- **[SEC]** ViftyPrivateIOKit C code uses bounds-checked string operations — no buffer overflow vectors.
- **[INFRA]** `install-vifty.sh` is well-written: `set -euo pipefail`, trap cleanup, idempotent, ditto-safe copies, signature verification.
- **[INFRA]** CI has concurrency group with `cancel-in-progress: true` — good.
- **[INFRA]** No `FUNDING.yml` or `SUPPORT.md` (optional/low priority).

---

## Test Coverage Gaps (Track A)

| Gap | Severity |
|-----|----------|
| SMCClient — no direct tests (hardware-dependent) | Medium |
| LocalFanHelperClient — no tests for apply/restoreAuto dispatch logic | Medium |
| ViftyDaemonClient — no tests for callback/timeout/invalidation/interruption | Medium |
| AgentControlService expiry monitor loop — scheduleMonitor, monitorLease, restoreFromMonitor, retry untested | High |
| CurveProfileStore.save() backup-error paths untested | Low |
| AppModel manual session expiry untested with mocked now provider | Medium |
| XPCConnectionIdentityExtractor — no tests (requires real code-signing context) | Low |
| HIDTemperatureReader — no tests (C-bridged, hardware-dependent) | Low |
| DaemonInstaller — no tests (SMAppService, admin prompts, AppleScript) | Low |
| ViftyCtlArguments suffix parsing (`5m`, `1h`) not tested | Low |

---

## GitHub Community Standards Checklist

| Standard | Status | Notes |
|----------|--------|-------|
| **Code of Conduct** | ❌ Missing | No CODE_OF_CONDUCT.md |
| **Contributing** | ✅ Present | Comprehensive: prerequisites, build/test, architecture rules, PR process |
| **Security** | ✅ Present | Excellent: trust boundaries, in-scope/out-of-scope, advisory reporting |
| **Issue Templates** | ❌ Missing | No `.github/ISSUE_TEMPLATE/` directory |
| **Pull Request Template** | ❌ Missing | No `.github/PULL_REQUEST_TEMPLATE.md` |
| **README** | ✅ Present | Outstanding: badges, screenshots, architecture, safety, CLI reference |
| **License** | ✅ Present | MIT |
| **FUNDING** | ❌ Missing | Optional, low priority |
| **SUPPORT** | ❌ Missing | Optional, low priority |

**Score: 4/9 present (44%).** The three high-priority gaps are Code of Conduct, Issue Templates, and Pull Request Template.

---

## Prioritized Remediation Queue

### Batch 1 — Security (should implement before distribution)
1. [SEC-C1] Switch to audit-token-based XPC identity validation
2. [SEC-C2] Fix XPC validator team-identifier logic
3. [SEC-H1] Add TeamID requirement to XPC allowlist
4. [SEC-H2] Create entitlements files with App Sandbox + Hardened Runtime

### Batch 2 — Community Standards (quick wins, no code risk)
5. [INFRA-H1] Add CODE_OF_CONDUCT.md (Contributor Covenant)
6. [INFRA-H1] Create `.github/ISSUE_TEMPLATE/bug-report.yml`
7. [INFRA-H1] Create `.github/ISSUE_TEMPLATE/feature-request.yml`
8. [INFRA-H1] Create `.github/PULL_REQUEST_TEMPLATE.md`

### Batch 3 — Hardening
9. [SEC-H4] Set strict permissions on AgentControlStore directory/files
10. [SEC-H3] Harden LaunchDaemon plist
11. [SEC-H5] Resolve child process executable to absolute path in viftyctl run
12. [SEC-M2] Move daemon logs from /tmp to /var/log with restricted permissions

### Batch 4 — Code quality
13. [CODE-H1] Replace force-unwrap in ViftyHelper with guard-let
14. [CODE-H2] Log rollback failures specifically in AgentControlService
15. [CODE-H3] Throw or log target RPM write failures in LocalFanHelperClient

### Batch 5 — Infrastructure
16. [INFRA-H1] Add `make clean`, `make test`, `make help` targets
17. [INFRA-M2] Add SPM cache to CI workflow
18. [INFRA-M3] Add GitHub Release workflow for tagged releases

### Batch 6 — Test coverage
19. Add tests for AgentControlService monitor loop (expiry, retry, sensor-loss restore)
20. Add tests for ViftyDaemonClient XPC callback/timeout/invalidation
21. Add tests for LocalFanHelperClient apply/restoreAuto dispatch
22. Add tests for ViftyCtlArguments suffix duration parsing

---

## Non-Claims

- No live `/Applications/Vifty.app` install or privileged fan-write smoke was performed.
- No physical SMC writes were tested on actual hardware.
- No penetration testing against a running daemon was performed.
- This is a read-only static analysis audit. Runtime dynamic testing is a separate scope.
