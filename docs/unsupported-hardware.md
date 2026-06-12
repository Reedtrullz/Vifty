# Unsupported Hardware Policy

Vifty's fan-control support scope is intentionally narrow: Apple Silicon MacBook Pro models on macOS 15+, validated by real reports. Other Macs should remain under macOS automatic fan control.

Unsupported hardware safe block is expected behavior, not a bug to bypass. When a machine is outside the write-control scope, `viftyctl diagnose --json` should report `state: "blocked"`, `safeToRequestCooling: false`, and a recovery action such as `collectHardwareEvidence` or `backOffWorkload`; the app, helper, daemon, and local agent paths should refuse manual or agent cooling.

## Unsupported Scope

Vifty does not claim fan-control support for:

- Intel Macs, including Intel MacBook Pro models;
- Apple Silicon non-MacBook-Pro machines, including MacBook Air, Mac mini, Mac Studio, iMac, and Mac Pro;
- Hackintosh, virtualized, modified, or externally controlled Mac environments;
- unknown fan topologies, invalid fan IDs, invalid RPM ranges, or missing controllable fans;
- machines where temperature sensors, fan telemetry, helper state, or daemon state are not trustworthy.

Some read-only telemetry may still appear on unsupported machines. That does not make the machine supported for manual, curve, or agent-requested cooling.

## Expected Behavior

On unsupported hardware, Vifty should:

- keep fan control in macOS Auto;
- fail closed for manual, curve, and agent-cooling requests;
- return a blocked readiness report from `viftyctl diagnose --json`;
- set `safeToRequestCooling: false`;
- set a machine-readable `recommendedRecoveryAction` for the follow-up path;
- avoid raw SMC writes and helper fan-write fallback paths;
- preserve read-only evidence for triage and compatibility reporting.

Local agents must treat `safeToRequestCooling: false`, `recommendedAgentAction: "doNotRequestCooling"`, and `state: "blocked"` as hard stops, then follow `recommendedRecoveryAction` without parsing check prose. They may continue the workload without Vifty cooling only when the user explicitly wants that.

## Safe Evidence To Collect

For unsupported-hardware reports, collect read-only evidence only:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
/Applications/Vifty.app/Contents/MacOS/viftyctl status --json
/Applications/Vifty.app/Contents/MacOS/viftyctl audit --limit 20 --json
```

If the reporter is validating an installed app or public release, they can also run:

```sh
scripts/collect-validation-evidence.sh --app /Applications/Vifty.app
scripts/review-validation-evidence.sh --bundle <evidence-dir> --mode unsupported-hardware --summary <evidence-dir>/review-result.json
```

The resulting `review-result.json` can be indexed as unsupported-hardware safe-block evidence. It must not be used as proof that fan control is supported on that machine.

## Do Not Do This

Do not run manual fan-write smoke tests on unsupported hardware.

Do not run:

- `sudo ViftyHelper setFixed`;
- `ViftyHelper auto` as a way to experiment with unsupported manual writes;
- raw SMC tools or arbitrary key writes;
- `viftyctl prepare` or `viftyctl run` after readiness is blocked;
- repeated retries intended to force a machine into supported compatibility.

Do not treat a blocked unsupported-hardware report as a compatibility failure unless the report proves Vifty attempted cooling or exposed a raw write path.

## Maintainer Policy

Maintainers should route these reports through the `unsupported-hardware` triage bucket in [support-triage.md](support-triage.md). A passing unsupported-hardware review means Vifty blocked safely. It should not expand the supported matrix, enable manual smoke tests, or justify README support claims.

Support expansion requires a deliberate future design: hardware model research, fan topology evidence, write-key validation, safe restore behavior, tests, and reviewed real-machine reports. Until then, unsupported hardware remains read-only or blocked.
