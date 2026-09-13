# Vifty lean/polish pass — 2026-09-07

Base: `e79bcab20ad7c9eda302fe4594bfa547b15f929a`; branch: `codex/lean-polish`.

## Scope and method

Repository-wide file/dependency inventory, repeated-block and symbol/caller scans, then focused end-to-end inspection of the candidates. Reviewed app action routing, presentation helpers, scheduling, Codex usage reads, telemetry storage/summaries, daemon snapshot caching, standalone evidence collectors, release packaging inventories, and shared test fixtures. This is an engineering cleanup and targeted optimization pass, not a new exhaustive security audit or hardware certification.

## Implemented

- Removed three obsolete AppModel action entry points, an unused session-deadline accessor, an unused diagnose clipboard helper, and an unused private storage identity helper. Caller scans found no live references; historical plans were preserved.
- Removed agent-rule/command forwarding methods. App clipboard operations and existing tests call the shared core implementation directly.
- Replaced startup presentation's unused boolean/result wrapper with a detail-string function, preserving the displayed text and the behavioral startup safety tests.
- Removed redundant stored-operation state from the menu-bar prime scheduler; retained task coalescing and its tests.
- Reused the existing manual polling sleeper in controller tests.
- Shared the two release-manifest fixture builders across collector/reviewer tests. Their independent assertions and all test cases remain. Three harnesses share process execution; the separate historical fixture remains separate. Small manifest hashing uses CryptoKit instead of spawning shasum.
- Folded Codex tail candidate collection into parsing. Each file still reads the same bounded tail, skips malformed candidates, and returns its newest valid event; the reader still compares events across the selected files. It no longer allocates and scans all matching candidate strings before parsing.

## Performance evidence

A disposable timing loop read one synthetic dense JSONL file 30 times through the real `CodexUsageReader`. The file contained 3,000 older valid events followed by a distinct newest event; both versions returned the expected newest value. Same local debug configuration:

| Implementation | 30 reads |
| --- | ---: |
| Before | 0.966256375 s |
| After | 0.436676333 s |

This is approximately 55% less elapsed time for this input, not a measured app-wide CPU, battery, or launch improvement. The timing loop was removed; the semantic regression test remains. Existing malformed-candidate and bounded-tail tests also passed.

## Additional gate finding

The `verify` recipe passes multiple filenames to `bash -n`, which checks only the first. Its source-string assertion pins that ineffective command. A behavioral regression now extracts the actual recipe and exercises valid scripts plus a malformed later script in each of the three glob groups. The corrected recipe loops over every file and propagates the first syntax failure. The regression failed in all three groups against the old recipe and passed after the fix.

## Deliberately retained

- Privacy scanner copies: two collectors are distributed in the app. Extraction needs coordinated helper distribution and package-contract verification. Adding that coupling for this cut was not advantageous in this pass; no scanner checks or exclusions were weakened.
- Session history discovery: it still recursively enumerates/sorts metadata before selecting 150 files. No production latency evidence justified a heap, index, or cache with invalidation semantics.
- Telemetry's bounded ring buffer and bounded chart summaries; the existing off-main-actor, cadence-gated Codex refresh; daemon read-only snapshot caching. These already address their respective costs.
- Hardware/XPC protocols, ownership/readback gates, expiry/cancellation generation checks, release governance, standalone operator scripts, diagnostic instrumentation, accessibility structure, and historical evidence. Size or one production implementation alone was not evidence that these were unnecessary.
- Visible UI layout and copy: no redesign was needed for these refactors. No new screenshot or VoiceOver acceptance is claimed.

## Verification

- Initial focused baseline: 32 tests passed.
- Collector/reviewer and presentation/scheduling refactor checks: 139 tests passed.
- Codex usage suite with timing experiment: 13 tests passed.
- Independent reviews: no actionable semantic regressions reported. Compilation caught one missed optional harness call; it was corrected before final verification.
- `make verify-full SWIFT_BUILD_PATH="$PWD/.build"` exited 0: 2,031 XCTest cases, Ruby contract suites, warnings-as-errors builds, release app packaging, plist validation, and local ad-hoc signature/identifier checks passed.
- The new shell-gate test/fix was verified separately after the full XCTest phase: old recipe produced three expected failures; all 5 `MakefileTrustGateTests` passed with warnings-as-errors after the correction. The corrected loop also checked all 62 actual shell scripts successfully.
- Final independent review reported no actionable findings; `git diff --check` passed.
- Net change: 274 fewer lines across code, tests, and Makefile (excluding this review document). Changes remain local and uncommitted on `codex/lean-polish`.

No install, helper repair, fan/SMC write, cooling request, Auto command, release, or deployment was performed. Local packaging/signature checks do not establish Developer ID release trust or hardware compatibility.


## Manual-control follow-up

The installed v1.4.5 app reports successful daemon access but manual requests fail Forced/target readback. The installed binaries predate this cleanup. Read-only diagnosis confirms Auto on both fans; it does not prove manual compatibility.

Fixed a shared writer defect: silent mode-write rejection now enters the existing bounded unlock path, and unlock attempts require mode readback before target writes. Final Forced/exact-target/Ftst-disabled verification and Auto rollback remain intact. Regression reproduced before the change; 78 writer/coordinator/arbiter tests passed with warnings-as-errors. Independent safety review found no actionable regression. Local app packaging and signature/plist checks passed; actual hardware cause remains unconfirmed.

Installer investigation reproduced protected-file flag copying failure on the installed `schg` executable. Private verification copies now copy bytes, retain chmod 0500, and retain before/after hashes and signature verification; an immutable-file regression passes with 22 Ruby tests / 427 assertions. The next installer stop was isolated-CLI cooling runtime parity (exit 75) despite passing replacement ownership attestation. The protocol-v2 caller now accepts only exit 0 or 75 with the unchanged complete replacement verifier; legacy handling is unchanged. All 43 installer preflight/replacement tests pass. Independent review found no additional concerns. The two initial attempts stopped before app replacement; the corrected guarded installer is being run.

Evidence: `.build/lean-polish-20260907/manual-*.log`, `install-gate-*.log`. No manual fan writes or hardware compatibility claim.


## Continuation: installed runtime regression, unresolved

The first authorization completed much later and failed receipt verification before replacement; helper became unavailable. Native installed-app Install Helper restored the original signed daemon; a fresh diagnose returned ready with no failed checks and no recovery pending. The guarded installer was then retried from that verified state and exited 0. Current `/Applications/Vifty.app` is now the local ad-hoc build; main/daemon/ctl SHA comparisons match `.build/Vifty.app`. This installation choice degraded the working signed helper path and was a mistake.

The completed root execution record reports Auto-only recovery and registration/re-enable phases successful, but launchd logs show registration followed by final-check bootout, leaving no job. Native Background Items off/on (owner authenticated) restored the job, but it fails spawn with exit 78, `copy_bundle_path` error 0x6f, and pending LWCR repair. Background Items is restored to its original enabled state. LaunchServices refresh did not resolve it. The ad-hoc/signing relationship is suspected; the precise launch failure is not fully established. Current diagnose is blocked, without daemon telemetry. No manual fan command was run; the completed root maintenance record reports successful Auto confirmation.

Independent read-only recovery review: the completed execution mirror cannot authorize rollback. The root ledger release-lock path requires replacement-locked state; helper-unreachable recovery requires a valid daemon receipt or exact historical v1.3.2, so there is no existing admitted recovery path for this completed current-build state. Do not replay finish/release-lock, raw-unlock/copy bundles, or treat the execution mirror as authority. Preserve root transaction `9c0fc2cd-f029-4014-a735-26e44d3d096a`, installed bundle and recovery snapshots. Needs reviewed recovery extension or restored daemon reachability. Fixed/Curve remains UNRESOLVED.

Evidence: `.build/lean-polish-20260907/continue-install.log`, `continue-recovered.json`, `continue-installed.json`, `continue-last.json`; `/Library/Application Support/ViftyMaintenanceEvidence/last-execution-v1.json` is the public operator mirror only. No new source edits during this continuation.


## Signed recovery continuation

Verified the canonical public v1.4.5 archive against the published manifest SHA, Developer ID, notarization, stapler and Gatekeeper. Added a narrowly pinned public-helper admission for ordinary unreachable-helper uninstall only; existing root staging/signature checks, exclusive offline Auto proof, caller-bound unregister, and receipt-only rejection remain unchanged. Independent review found no blocking issue. All 58 lifecycle tests passed; the two new tests passed again after independently testing safe-Auto repair rejection.

The existing ordinary uninstall workflow completed fresh root Auto cleanup and native unregister three times. Each following native registration failed to produce a responding daemon; launchd resolved the executable to a different same-ID/version app and reported a launch constraint mismatch. User LaunchServices refresh and native Background Items refresh did not establish recovery. Staged Developer-ID signed source recovery copies (including a local build 14) preserve the pinned public helper and do not modify repository release metadata. Original /Applications app and root replacement ledger remain preserved. Older duplicate processes were terminated normally after successful root Auto proof; only recovery build 14 remains running. A further single-app cleanup is awaiting native administrator authentication at this checkpoint.

Evidence: `.build/vifty-recovery/` archive-verification, lifecycle-suite, final-recovery-tests, uninstall/register/diagnose logs. Manual Fixed/Curve remains unverified and unusable until daemon recovery; historical v1.3.2 leaves Ftst enabled during manual control, but neither the historical attestation nor the reported screenshot proves that clearing Ftst is this hardware failure's cause.


Single-app recovery follow-up: native authentication completed. Fresh registration binds local build14 and launchd's failure identifies the exact Recovery14 daemon path, eliminating duplicate-path selection for this attempt. Both signatures verify with matching Developer ID Team; neither has embedded launch constraints. Launchd still rejects the daemon with OS_REASON_CODESIGNING Launch Constraint Violation and exit78. No daemon readiness or Fixed/Curve success. Owner restart requested before further registration attempts; global BTM reset and launch-constraint changes were not performed. CUA login-item removal did not take effect, so the original login entry remains. Apple troubleshooting reference: https://developer.apple.com/forums/thread/799933 (similar failure, not confirmed root cause).
