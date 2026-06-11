# Support Triage

Use this guide when reviewing bug reports, hardware-validation issues, release reports, or agent-cooling failures. Vifty should earn trust by sorting reports into the right bucket quickly and asking only for evidence that is safe to collect.

Do not ask reporters to run raw SMC writes, `sudo ViftyHelper setFixed`, or manual fan-write smoke tests when readiness is `blocked`. Use [unsupported-hardware.md](unsupported-hardware.md) when the report is outside the Apple Silicon MacBook Pro fan-control scope.

## First Response

Ask for the least invasive evidence that answers the triage question:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
/Applications/Vifty.app/Contents/MacOS/viftyctl status --json
/Applications/Vifty.app/Contents/MacOS/viftyctl audit --limit 20 --json
```

For hardware/fan reports on supported Apple Silicon MacBook Pro machines, also ask for:

```sh
sudo /Applications/Vifty.app/Contents/MacOS/ViftyHelper probeLocal
```

For release-trust reports, prefer the collector bundle:

```sh
scripts/collect-validation-evidence.sh --app /Applications/Vifty.app
scripts/review-validation-evidence.sh --bundle <evidence-dir> --mode release --summary <evidence-dir>/review-result.json
```

## Triage Buckets

| Bucket | Typical signal | Evidence to request | Safe next action |
| --- | --- | --- | --- |
| Release trust | Gatekeeper, notarization, cask SHA, TeamID, or bundle-version mismatch | `scripts/verify-release-artifact.sh --team-id <TEAMID>`, collector bundle, `review-result.json` | Do not promote the release or cask until verifier and reviewer pass. |
| Hardware validation | New Apple Silicon MacBook Pro model, missing compatibility row, or smoke-test report | Hardware Validation Report issue, `diagnose --json`, `probeLocal`, collector bundle | Keep the model as needs validation until review passes and manual smoke records Auto restore. |
| Unsupported hardware safe block | Non-MacBook-Pro, Intel, or unsupported Apple Silicon reports `blocked` | `diagnose --json`, optional collector bundle, [unsupported-hardware.md](unsupported-hardware.md) | Treat safe blocking as expected behavior; do not suggest bypasses. |
| Helper install or approval | `HELPER_UNREACHABLE`, helper unreachable UI, Login Items approval, empty fan snapshot | `diagnose --json`, `status --json`, helper recovery text from the app, launchd status from collector | Ask user to open Vifty, use Repair/Reinstall Helper, approve Login Items, then rerun read-only diagnostics. |
| SMC key or fan telemetry drift | Fan count/range/mode missing, `hardwareMode` unknown, no controllable fans on supported hardware | `probeLocal`, `diagnose --json`, model identifier, macOS version | Keep fan writes blocked until fan IDs, ranges, and mode/target telemetry are understood. |
| Agent-cooling lifecycle | `prepare`, `run`, restore failure, expired lease, rate limit, or child-command preflight issue | Agent Cooling Report issue, exact `viftyctl` command, stdout/stderr, `status --json`, `audit --limit 20 --json`, `diagnose --json` | Follow [safe-agent-cooling.md](safe-agent-cooling.md); do not start another lease while restore is pending. |
| UI or copy | Confusing owner/helper state, profile preset behavior, power/thermal display | screenshot, macOS version, `diagnose --json` if fan state is involved | Fix copy/state without changing SMC behavior unless evidence shows a control bug. |

## Labels

Suggested labels:

- `release-trust`
- `hardware-validation`
- `unsupported-hardware`
- `helper-install`
- `smc-telemetry`
- `agent-cooling`
- `ui`

Use `security` only for public non-sensitive tracking. For vulnerabilities involving unprivileged fan writes, daemon client spoofing, arbitrary SMC writes, or local permission leaks, direct the reporter to GitHub Security Advisories.

Use the dedicated **Agent Cooling Report** issue template for `viftyctl run`, `prepare`, `restore-auto`, guarded wrapper, rate-limit, expired-lease, and restore-failure reports.

## Escalation Rules

Escalate a report before suggesting any fan-write test when:

- `diagnose --json` reports `state: "blocked"`;
- thermal pressure is critical;
- temperature sensors are missing;
- no controllable fans are present on a claimed supported MacBook Pro;
- fan IDs are invalid or duplicated;
- fan RPM ranges are invalid;
- the helper or daemon state is uncertain;
- an agent lease is expired but Auto restore is still pending.

## Compatibility Claims

Only update [compatibility.md](compatibility.md) from reviewed `review-result.json` files. Use [hardware-validation.md](hardware-validation.md) for collection and `scripts/summarize-validation-reports.sh` for indexes. A supported-hardware report becomes validated hardware evidence only when the review result includes:

```json
"manualSmokeTestResult": "passed-auto-restored"
```

Until then, keep the report as candidate evidence that still needs manual smoke confirmation.
