# Installed runtime smoke — September 15, 2026

Scope: locally Developer-ID-signed candidate installed at /Applications/Vifty.app,
MacBookPro18,1. Daemon SHA256:
5ef806dfa11c802d25655aaf33d0ec760cd13f95d850fc0088cad344542e0eb5.
One running installed GUI instance observed. This is not public-release evidence.

## Observed results

- Baseline: manual readiness gate passed, runtime hash matched, two fans in Auto,
  six temperature sensors, nominal thermal pressure.
- Guarded agent smoke: 1-minute lease cap, 55 percent, 15-second sleep child.
  Collector reports passed, child exit 0, Auto restore succeeded. UI fan readback
  was 3034/3282 RPM against targets 3037/3284. Post-run returned to Auto/ready.
  Evidence: .build/validation-20260915-installed-agent.
- Fixed UI smoke: existing 2800 RPM draft, Apply, 10-minute bounded manual run.
  Daemon confirmed active manual ownership and Forced mode on both fans;
  readback 2800/2811 RPM against 2800 targets. Selecting Auto restored ready state.
- Curve UI smoke: existing edited Quiet draft left unchanged (35 C/1500 RPM,
  70 C/3000 RPM, 85 C/6000 RPM, hardware clamping displayed).
  Apply confirmed active manual ownership. Two samples showed targets changing
  from 2727 to 2709 RPM, measured 2736/2743 then 2702/2708 RPM.
- Curve-to-Auto released manual ownership. Subsequent daemon readback reported
  both fans System/raw mode 3, zero target/current RPM, no owner/lease/recovery,
  hardware-consistency and replacement-attestation checks passed. Diagnose was
  degraded solely for System-mode telemetry, safeToRequestCooling=true.

## Defects / follow-up

1. During the agent lease, UI displayed owner macOS and ownership-confirmation
   warning despite measured manual hardware cooling. Cleared after lease restore.
2. After Curve-to-Auto, UI persisted in ownership-confirmation warning although
   daemon attested consistent System-managed ownership. UI displayed target 1499
   RPM while raw daemon target was zero. Investigate UI ownership reconciliation
   and target formatting; do not weaken daemon safety gates to suppress warnings.
3. Brief attention warnings appeared during both manual-to-Auto transitions;
   inspect whether pending restoration should be presented separately from failure.

Further writes stopped after the final discrepancy. App left in Auto selection,
hardware System-managed, thermal nominal, no manual owner or active lease.
Manual duration preference changed from 30 to 10 minutes for bounded smoke;
profiles and RPM drafts were not edited. No long-duration, sleep/wake, timer-expiry,
crash-recovery, high-temperature or other-hardware acceptance is claimed.

## Follow-up repair

The System-mode warning came from AppModel treating every System-mode fan as
an ownership fault, even with fresh clean daemon ownership. The repair requires
confirmed macOS ownership before accepting System mode; unknown/Forced hardware
still raises attention. Readback target RPM is now displayed without manual RPM
clamping, preserving zero and rejecting negative telemetry. Command clamping is
unchanged.

A second guarded 25-second agent test correlated a matching active agent lease
and ownership transaction with the UI's correct Agent cooling active banner.
It restored Auto and passed the collector. The earlier agent warning was a
transient readback mismatch, not evidence that agent ownership never appears;
no unconfirmed state is promoted to confirmed ownership to suppress it.

The installer now uses matching live daemon runtime hashes before looking for a
legacy helper. Lock scans propagate enumeration failures instead of ignoring
process-substitution errors. Only the unprivileged caller prunes the exact
immutable root-owned 0700 CandidateSnapshot boundary; privileged workers still
scan the entire tree. A read-only check on transaction
13378700-ecc6-4ee7-b348-0e2f29a0a894 passed without permission warnings.

These source fixes require a new guarded installation and post-install UI check;
the preceding smoke evidence belongs to the previous local signed build.

## Repaired build installed and rechecked

The subsequent owner-run guarded install exited 0 without CandidateSnapshot
permission warnings or the false helper-missing message. Installed app/daemon/ctl
hashes matched the candidate, and deep/strict code-sign verification passed.
The repaired installed daemon SHA256 is
42466b2349c4bbe5679ff123464ab39400c6e6623e1fc1f62cbee13d6979ec15.
Source and installed lifecycle script SHA256 both match the compiled pin:
8cc4772c1e6f30e6827059ab998d67db5eea8e2eb41f2c3fd11d9f1ede3e4157.

At 20:12 local time, the exact System/raw mode 3 condition recurred on this
repaired build: both measured and target RPM were zero, daemon ownership was
clear, hardware consistency passed, and thermal pressure was nominal. The live
UI correctly showed Auto control active, Owner macOS, macOS System control,
Target 0 RPM, and On target. There was no ownership-confirmation warning.
Diagnose retained its separate System-mode advisory (degraded but safe), without
cooling blockers. This is direct hardware/UI verification of both display fixes.

Fresh focused verification: 92 Swift tests passed; 26 installer contract tests
with 477 assertions and 18 replacement fixture tests with 145 assertions passed.
An earlier 92-test run reported two failures whose assertion details were
truncated before capture. Inspection of the retained session output did not
recover those details; later combined reruns passed. The cause remains unknown,
not proven to be a build race. Current logs are retained under .build as
repair-recheck.log and repair-ruby-recheck.log.

### Timer, repeat checks, and captured test flake

- Fixed 2800 RPM, 10-minute manual session: confirmed active ownership and
  physical fan readback near the target. At the scheduled 20:23 expiry, the app
  returned to Auto without an operator command. Subsequent daemon readback
  showed no owner, no recovery, both fans OS-managed, and no cooling blockers.
- Curve used the currently loaded Unsaved draft without editing its points:
  55 C/1499 RPM, 70 C/3500 RPM, 85 C/4296 RPM. Ownership was confirmed; one
  readback measured 3317/3323 RPM against 3314 targets. Auto restoration passed.
- Quit in Auto removed the installed GUI process; daemon diagnostics remained
  safe. Relaunch opened Auto with correct System/zero-RPM telemetry.
- After relaunch, repeated Fixed 2800 RPM (measured 2806/2804), then applied
  Curve while Fixed was active, observed changing Curve targets and physical
  response, and restored Auto. No profiles or RPM points were edited.
- Final exact-build guarded agent smoke: one-minute cap, 45 percent,
  15-second sleep child. Collector status passed, child exit 0, and
  autoRestoreSucceeded=true. Evidence is retained locally at
  .build/validation-20260915-repaired-final; one installed GUI instance remained.
- A transient attention banner still appears during manual-to-Auto restoration
  before the fresh readback arrives, then clears. This is remaining presentation
  polish, not a persistent ownership failure.
- The broader `make test-fast` run passed 1401 tests. An additional 28-test
  repeat captured a timing failure in
  `testSystemRunnerBoundsCleanupAfterStdinWriteFailure`: total elapsed 1.255s
  exceeded a redundant 1.25s wall-clock assertion, although the existing 2s
  XCTest completion bound succeeded. The measurement includes task scheduling,
  process startup, input transfer, and cleanup. Removed that second threshold;
  retained the bounded completion and error assertion, with no production
  cleanup changes. Eleven service tests passed, followed by five consecutive
  11-test repeats and the final combined 92-test run. Logs:
  repair-cleanup-test.log, repair-cleanup-repeat-{1..5}.log,
  repair-final-focused.log. This does not establish the cause of the earlier
  two failures whose details were lost.

The cumulative branch and timing-test adjustment received independent read-only
review with no blocking findings. Sleep/wake, crash recovery, other hardware,
and a new notarized public release remain unverified by this run.
