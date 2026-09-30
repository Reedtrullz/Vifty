# Installed-app replacement: confirmed App Management denial

On September 15 at 08:57:48 and 19:02:14, TCC attributed the failed
file-write-flags operations on /Applications/Vifty.app to
com.apple.authtrampoline (root, audit UID 0), service
kTCCServiceSystemPolicyAppBundles. The platform process could not prompt,
and the authorization response lacked an auth_value.

Normal-boot root probes successfully set and cleared schg on empty temporary
files and nested directories with SIP enabled and securelevel 0. Both
child-first and parent-first clearing worked. Probe trees were removed.
Therefore neither Recovery nor traversal order was established as the remedy.

An idempotent no-payload Installer probe succeeded, but it only reapplied the
existing schg flag. The subsequent guarded replacement through PackageKit
failed at actual flag clearing; TCC still attributed that operation to
authtrampoline. The no-op result was not evidence of mutation permission.
The PackageKit workaround was removed after this failed experiment.

The incorrect Recovery-only preflight and speculative uchg policy were also
removed. The maintenance code and compiled hash now match the previously
verified 4a318b1 implementation. The replacement still needs an execution
context legitimately authorized for App Management; root authentication alone
does not supply that permission. Do not edit TCC databases, strip provenance,
disable SIP, or retry identical unauthorized workers as a workaround.

No replacement bytes were copied. The installed app's supported registration
action restored its helper; fresh diagnose returned ready,
safeToRequestCooling=true, and no cooling blockers. This proves restored
readiness, not completion of the requested replacement.

Focused checks for the restored source: installer contract tests, shell
syntax, and lifecycle hash parity. The unsuccessful experimental version had
passed 18 replacement fixture tests and 11 DaemonInstallService tests; those
tests did not establish live App Management authorization.

Next work: use a supported interactive installation context with App Management
authorization, or implement and review a native Vifty maintenance host that can
obtain appropriate consent. Do not send the operator into Recovery based on
the earlier incorrect immutable-flag diagnosis.

## Interactive sudo route

The owner authorized a one-time sudo exception for the guarded installation.
`VIFTY_TERMINAL_AUTHORIZATION=1 scripts/install-vifty.sh` opts into an interactive
terminal route; the default remains native AppleScript authorization. The
installer authenticates before quitting Vifty or quiescing its daemon, and
forwards `--terminal-authorization` through prepare, finish, and rollback.
Only the existing digest-bound root stager is elevated. Signature checks,
caller-bound receipts, immutable locks, and Auto-restoration checks are unchanged.

The route requires terminal stdin/stdout and does not handle password bytes.
Run it in a visible terminal; a hidden tool PTY cannot be opened by passing its
numeric session ID to the Codex app terminal panel. The attempted hidden prompt
was cancelled without authentication. Successful sudo authentication alone is
not proof of App Management authorization or successful replacement.

## Verified outcome

The owner subsequently ran the guarded installer from visible Terminal using
this opt-in route. Prepare, replacement, finish, and final identity checks
completed with exit 0. Independent installed executable hashes matched the
candidate, deep/strict code-sign verification passed, and daemon-backed
diagnostics confirmed helper parity and OS-managed fan ownership. A follow-up
installation also eliminated the diagnostic-only CandidateSnapshot permission
warnings and false legacy-helper-missing message. See
[installed runtime validation](2026-09-15-installed-runtime-smoke.md) for exact
build identity and hardware/UI checks. No reboot, Recovery operation, SIP
change, or persistent permission expansion was required.
