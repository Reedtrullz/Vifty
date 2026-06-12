# Safe Local Agent Cooling

Use this guide when a local coding agent, build script, or shell runner wants temporary cooling for a long developer workload. Vifty's safe path is intentionally narrow: read-only readiness first, one bounded workload lease, validated child command, then Auto restore.

This guide is for supported Apple Silicon MacBook Pro hardware only. Unsupported Macs should run workloads normally under macOS automatic fan control.

## Rules

Agents and scripts may:

- run `viftyctl diagnose --json`, `status --json`, `capabilities --json`, and `audit --json`;
- run workloads through `examples/viftyctl/guarded-run.sh` or the convenience wrappers in `examples/viftyctl/`;
- use direct `prepare` / `restore-auto` only when a human is supervising a lifecycle that cannot be represented by `viftyctl run`.

Agents and scripts must not:

- call `sudo`, `ViftyHelper setFixed`, `ViftyHelper auto`, raw SMC tools, or arbitrary fan RPM writes;
- request cooling when `diagnose --json` reports `state: "blocked"`;
- request cooling when `safeToRequestCooling` is `false`;
- request cooling when `daemonControlPathReady` is `false`;
- prepare cooling before the child command has been resolved and validated;
- ignore `restoreAutoBeforeRequestingCooling`, `doNotRequestCooling`, `THERMAL_CRITICAL`, `HELPER_UNREACHABLE`, `CHILD_COMMAND_FAILED`, `PREPARE_RATE_LIMITED`, or `UNSUPPORTED_HARDWARE`;
- use empty or blank cooling reasons; audit entries should explain the supervised workload.

## Preferred Command

Prefer the guarded wrapper. It checks that the child command is a regular executable path or resolves to one on `PATH`, rejects malformed wrapper arguments before contacting Vifty, including blank reasons, checks the read-only `capabilities --json` output for advertised `run` command support, requested workload support, the advertised unavailable exit code, the `runLifecycle` contract, policy duration/RPM limits, and `metadataLimits`, rejects durations and RPM percentages outside the advertised policy range and reasons longer than the advertised maximum before readiness or cooling, runs read-only readiness, and delegates to `viftyctl run --json` only when Vifty says cooling is safe:

```sh
examples/viftyctl/guarded-run.sh test 20m 70 "swift test" -- swift test
```

Use the installed CLI explicitly when running outside the Vifty repository:

```sh
VIFTYCTL=/Applications/Vifty.app/Contents/MacOS/viftyctl \
  /path/to/guarded-run.sh build 25m 75 "release build" -- swift build -c release
```

The guarded wrapper does not force-retry rate-limited prepares by default. For a supervised human workflow, set `VIFTY_GUARDED_RUN_FORCE_RETRY=1` to let `viftyctl run --force` wait once for the daemon's retry window and try again. The wrapper checks `supportsForceRetry` before passing `--force`. Agents should normally leave that unset and show the rate-limit JSON instead. `viftyctl run` still revalidates the child command before preparing cooling, so direct CLI use keeps the same safety boundary.

The guarded wrapper also does not fall back to an uncooled workload by default.
When the user explicitly wants the child command to run without Vifty after a
structured readiness block, set `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1`. The
wrapper still performs read-only capabilities/readiness checks, prints the
diagnose JSON, refuses to request cooling, and only then execs the child directly.
It still refuses uncooled execution when Vifty recommends `backOffWorkload` or
`restoreAutoBeforeRetry`.

For common workloads, use the audited shortcuts:

```sh
examples/viftyctl/swift-test.sh
examples/viftyctl/swift-release-build.sh
examples/viftyctl/xcode-build.sh -scheme MyApp -destination 'platform=macOS'
examples/viftyctl/xcode-test.sh -scheme MyApp -destination 'platform=macOS'
examples/viftyctl/make-test.sh
examples/viftyctl/make-verify.sh
examples/viftyctl/npm-build.sh
examples/viftyctl/npm-test.sh
examples/viftyctl/cargo-build.sh --release
examples/viftyctl/cargo-test.sh
examples/viftyctl/pytest.sh
examples/viftyctl/local-model.sh -- ./run-local-model.sh
```

## Readiness Decisions

First run:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
```

Decision table:

| Diagnose result | Agent action |
| --- | --- |
| `state: "ready"`, `safeToRequestCooling: true`, and `daemonControlPathReady: true` | Use `guarded-run.sh` with normal conservative limits. |
| `state: "degraded"`, `safeToRequestCooling: true`, and `daemonControlPathReady: true` | Use a shorter duration, lower RPM percent, and surface the warning to the user. |
| `recommendedAgentAction: "restoreAutoBeforeRequestingCooling"` | Stop before cooling. Ask the user whether to restore Auto or wait. |
| `state: "blocked"` or `safeToRequestCooling: false` | Do not request cooling. Show the JSON and run without Vifty only if the user explicitly wants that; use `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1` rather than catching wrapper failures yourself. |
| `daemonControlPathReady: false` | Do not request cooling. Ask the user to repair or reinstall the helper before retrying. |
| Diagnose `recommendedRecoveryAction: "repairHelper"` | Ask the user to open Vifty and use Repair/Reinstall Helper. Do not attempt direct SMC writes. |
| Diagnose `recommendedRecoveryAction: "restoreAutoBeforeRetry"` | Restore Auto or wait for the active lease to clear before retrying. |
| Diagnose `recommendedRecoveryAction: "backOffWorkload"` | Pause or reduce the workload; do not fight critical system thermals. |
| Diagnose `recommendedRecoveryAction: "inspectPolicy"` | Inspect policy/status before retrying; do not assume cooling is available. |
| Diagnose `recommendedRecoveryAction: "collectHardwareEvidence"` | Collect read-only validation evidence before considering hardware support. |
| Command-error `recommendedRecoveryAction: "repairHelper"` | Recover daemon/transport failures through the Vifty helper repair path. Do not attempt direct SMC writes. |
| `recommendedRecoveryAction: "waitBeforeRetry"` | Do not busy-loop. Show the JSON or wait for `retryAfterSeconds` only when the user approved retrying. |
| `recommendedRecoveryAction: "fixChildCommand"` | Fix the workload command/path or show the launch error. Do not treat this as a helper failure. |

Do not parse human-readable warning text when the JSON fields exist. Pin automation to `state`, `recommendedAgentAction`, `recommendedRecoveryAction`, `safeToRequestCooling`, `daemonControlPathReady`, `checks`, and `agentControl`.

## Conservative Workload Limits

These are starting points, not rights to exceed daemon policy:

| Workload | Duration | Max RPM percent | Example |
| --- | ---: | ---: | --- |
| Swift/package tests | `20m` | `70` | `swift test` |
| Release build | `25m` | `75` | `swift build -c release` |
| Xcode build/test | `30m` | `75` | `xcodebuild build ...`, `xcodebuild test ...` |
| Make test/verify | `20m`/`30m` | `70`/`75` | `make test`, `make verify` |
| npm/cargo builds | `25m` | `75` | `npm run build`, `cargo build --release` |
| npm/cargo/pytest tests | `20m` | `70` | `npm test`, `cargo test`, `python3 -m pytest` |
| Local model run | `20m` | `75` | local inference or eval command |
| Unknown/custom workload | `10m` | `65` | only with a clear human-readable reason |

When readiness is degraded, reduce one or both numbers. A good degraded default is `10m` and `60`.

## Failure Handling

If readiness is blocked:

```sh
scripts/collect-agent-cooling-evidence.sh \
  --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl
```

This read-only support bundle captures capabilities, diagnose, status, audit,
command exit statuses, launchd/helper install evidence, a manifest,
schema-backed `agent-cooling-evidence-summary.json` with
`schemaID: https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json`,
`privacy-review.tsv`, and checksums without requesting cooling, restoring Auto,
calling `ViftyHelper`, using `sudo`, or writing SMC keys. Check
`privacy-review.tsv` before posting the bundle publicly; redact or share
privately if it reports `redaction-needed`. Maintainers can review a collected
bundle with:

```sh
scripts/review-agent-cooling-evidence.sh \
  --bundle <bundle-dir> \
  --summary <bundle-dir>/agent-cooling-evidence-review.json
```

The reviewer accepts blocked diagnose exit `75` as evidence and rejects privacy
findings, schema drift, manifest/status drift, checksum drift, missing or
contradictory diagnose decision fields, or any record that cooling commands
were run. Its JSON summary declares
`schemaID: https://vifty.local/schemas/agent-cooling-evidence-review.schema.json`.
The `diagnoseDecision` summary records the diagnose exit status, readiness
state, `recommendedAgentAction`, `recommendedRecoveryAction`,
`safeToRequestCooling`, and `daemonControlPathReady` so maintainers can route
blocked readiness without parsing human text. The `capabilitiesDecision`
summary records whether the bundle advertised `viftyctl run`, force-retry
discovery, safe `runLifecycle`, safe direct prepare/restore lifecycle,
metadata limits, daemon status, and the unavailable-exit contract before the
report is treated as agent-safe evidence. In helper-unreachable reports, the
reviewer may also list `viftyctl-status` or `viftyctl-audit` under
`acceptedCommandErrors`, but only when blocked `diagnose` recommends
`repairHelper` and those commands emitted structured `HELPER_UNREACHABLE`
command errors with `safeToProceed: false`.
If the repository scripts are not available, collect the same core evidence manually:

```sh
viftyctl capabilities --json
viftyctl diagnose --json
viftyctl status --json
viftyctl audit --limit 20 --json
```

Show the bundle or manual outputs to the user. `audit --json` is read-only and
declares `coolingCommandsRun: false`.

If `viftyctl run` reports an Auto-restore failure after the child exits, treat it as a Vifty safety failure even when the child succeeded. Show stderr plus:

```sh
viftyctl status --json
viftyctl audit --limit 20 --json
```

The app's menu and main window also show the current fan-control owner. If the UI says an agent lease is expired or restore is pending, do not start another cooling request until Auto is restored.

## Direct Prepare Is Exceptional

Use direct `prepare` only for a supervised workflow that cannot fit inside one child process:

```sh
#!/bin/sh
set -eu

VIFTYCTL=${VIFTYCTL:-/Applications/Vifty.app/Contents/MacOS/viftyctl}
LEASE_KEY="$(uuidgen)"
PREPARED=0

cleanup() {
  status=$?
  trap - EXIT INT TERM HUP

  if [ "$PREPARED" = "1" ]; then
    "$VIFTYCTL" restore-auto \
      --reason "supervised multi-step build complete" \
      --json || status=70
  fi

  exit "$status"
}

trap cleanup EXIT INT TERM HUP

"$VIFTYCTL" prepare \
  --workload build \
  --duration 20m \
  --max-rpm-percent 70 \
  --reason "supervised multi-step build" \
  --idempotency-key "$LEASE_KEY" \
  --json
PREPARED=1

# Run supervised multi-step work here.
```

For normal build/test/model commands, prefer `viftyctl run` or `guarded-run.sh` so child validation, cooling lease creation, signal forwarding, and Auto restore remain one lifecycle. Direct prepare is the exception because the shell now owns cleanup; keep the restore trap in the same script as the prepare call.

`restore-auto` is intentionally not scoped by idempotency key. Use a stable `--idempotency-key` when preparing directly, then keep the unkeyed restore call in the same supervised script.
