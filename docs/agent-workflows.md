# Vifty Agent Workflows

Vifty's agent surface is the bundled `viftyctl` CLI. It is designed for local coding agents, build scripts, and shell automation that need temporary cooling for a bounded workload without gaining arbitrary SMC write access.

For the short operational runbook, see [safe-agent-cooling.md](safe-agent-cooling.md).

Installed path:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl
```

Development bundle path:

```sh
.build/Vifty.app/Contents/MacOS/viftyctl
```

## Contract

Agents should treat `viftyctl` as a local safety contract:

1. Run `viftyctl diagnose --json` before long workloads.
2. Treat `state: "blocked"` as a hard stop.
3. Treat `state: "degraded"` as proceed-with-caution; prefer shorter durations and lower RPM percent.
4. Use `viftyctl run` for child workloads whenever possible so Vifty prepares cooling, launches the resolved child command, and restores Auto afterward.
5. Use `prepare` and `restore-auto` directly only when a wrapper command cannot model the workload lifecycle.
6. Always include a human-readable `--reason` and a stable `--idempotency-key` when preparing directly.

Vifty never exposes raw SMC writes through `viftyctl`. Agents request intent: workload type, maximum duration, maximum RPM percent, and reason. The daemon evaluates policy, writes bounded fan targets if allowed, records the lease, and owns expiry.

## Commands

```sh
viftyctl status --json
viftyctl capabilities --json
viftyctl diagnose --json
viftyctl prepare --workload build --duration 25m --max-rpm-percent 75 --reason "Swift release build" --idempotency-key "$(uuidgen)" --json
viftyctl restore-auto --reason "workload complete" --json
viftyctl run --workload test --duration 20m --max-rpm-percent 70 --reason "swift test" -- swift test
```

Supported workloads are currently:

- `build`
- `test`
- `render`
- `localModel`
- `custom`

Durations accept seconds, `m`, or `h`, for example `600`, `20m`, or `1h`. The default daemon policy caps leases at 30 minutes unless policy is changed in code.

## JSON Decision Rules

### `diagnose --json`

The readiness report has `schemaVersion: 1` and a top-level `state`:

- `ready` - all required checks passed.
- `degraded` - no hard blocker, but one or more warning checks failed.
- `blocked` - at least one error check failed; do not request cooling.

It also includes `recommendedAgentAction` and `safeToRequestCooling` so agents do not need to infer the next step from prose:

- `requestCooling` / `safeToRequestCooling: true` - safe to request a normal bounded lease.
- `requestCoolingWithCaution` / `safeToRequestCooling: true` - a warning exists; reduce duration/RPM or be ready to back off.
- `restoreAutoBeforeRequestingCooling` / `safeToRequestCooling: false` - another lease is active; restore Auto or wait before requesting new cooling.
- `doNotRequestCooling` / `safeToRequestCooling: false` - a hard blocker exists.

`diagnose` exits `0` for `ready` and `degraded`. It exits with `capabilities.exitCodes.blockedReadiness` for `blocked` after printing the same structured readiness report, so shell automation can fail closed without losing machine-readable evidence.

Important fields:

- `modelIdentifier`
- `isAppleSilicon`
- `isMacBookPro`
- `thermalPressure`
- `recommendedAgentAction`
- `safeToRequestCooling`
- `fanCount`
- `controllableFanCount`
- `temperatureSensorCount`
- `highestTemperatureCelsius`
- `fans`
- `temperatureSensors`
- `agentControl`
- `daemonSnapshotError`
- `agentControlStatusError`
- `checks`

Important readiness check IDs:

- `daemonSnapshotAvailable`
- `agentControlStatusAvailable`
- `supportedHardware`
- `agentControlEnabled`
- `temperatureSensorsPresent`
- `controllableFansPresent`
- `fanIDsValid`
- `fanIDsUnique`
- `fanRangesValid`
- `thermalPressureSafe`
- `activeLeaseClear`
- `fanModeTelemetry`

### `capabilities --json`

The capabilities report has `schemaVersion: 1` and includes:

- `commands`
- `workloads`
- `schemas.capabilities`
- `schemas.audit`
- `schemas.diagnose`
- `schemas.status`
- `schemas.commandError`
- `schemaResources.capabilities`
- `schemaResources.audit`
- `schemaResources.diagnose`
- `schemaResources.status`
- `schemaResources.commandError`
- `schemaIDs.capabilities`
- `schemaIDs.audit`
- `schemaIDs.diagnose`
- `schemaIDs.status`
- `schemaIDs.commandError`
- `policy.enabled`
- `policy.minimumAgentRPMPercent`
- `policy.maximumAllowedRPMPercent`
- `policy.maxDurationSeconds`
- `policy.prepareCooldownSeconds`
- `policySource`
- `daemonStatusAvailable`
- `agentControlStatusError`
- `supportsForceRetry` (treat a missing value in legacy payloads as `false`)
- `runLifecycle.childCommandPreflightBeforeCooling`
- `runLifecycle.signalsForwardedToChild`
- `runLifecycle.autoRestoreAfterChildExit`
- `runLifecycle.structuredPreChildFailures`
- `runLifecycle.cleanupStateReportedOnLaunchFailure`
- `exitCodes.success`
- `exitCodes.commandFailure`
- `exitCodes.usage`
- `exitCodes.unavailable`
- `exitCodes.blockedReadiness`

Use this output rather than hardcoding policy limits, schema paths/resource paths/IDs, shell exit-code meanings, or `viftyctl run` wrapper guarantees in an agent. `schemas` points at source-tree documentation paths, `schemaResources` points at the installed app bundle paths under `Vifty.app/Contents/Resources/schemas`, and `schemaIDs` gives stable IDs for validators. `runLifecycle` tells agents whether the wrapper validates the child command before cooling, forwards handled signals, restores Auto after child exit, uses structured pre-child JSON failures, and reports cleanup state after launch failures. `supportsForceRetry` tells supervised wrappers whether they may pass `--force`; if the field is absent in a legacy payload, treat it as unsupported. If daemon status is unavailable, `capabilities --json` still prints the static command contract, but returns `exitCodes.unavailable`, sets `daemonStatusAvailable: false`, sets `policySource: "fallbackUnavailable"`, and reports a disabled fallback policy. Treat that as discovery-only; run `diagnose --json` or ask the user to repair the helper before requesting cooling.

Canonical examples live in [docs/examples/viftyctl](examples/viftyctl/README.md). The XCTest suite decodes those fixtures against the current Swift models so agent-facing examples stay aligned with implementation.

Agent-facing schemas live in [docs/schemas](schemas) and are bundled into release app artifacts at `Vifty.app/Contents/Resources/schemas`. Agents should pin readiness behavior to [viftyctl-diagnose.schema.json](schemas/viftyctl-diagnose.schema.json)'s required safety fields: `state`, `recommendedAgentAction`, `safeToRequestCooling`, hardware support flags, fan/sensor counts, `agentControl`, and `checks`. The same folder also documents capabilities, audit, status/prepare/restore-auto, and structured command-error payloads.

For copy/paste instructions tailored to Codex, Claude Code, Cursor, and shell runners, see [agent-integrations.md](agent-integrations.md).

### `prepare --json` and `status --json`

The status response includes:

- `enabled`
- `activeLease`
- `lastDecision`
- `lastErrorCode`
- `policy`

`prepare` exits with code `0` only when the daemon returns an active lease matching the request. It exits nonzero when cooling is denied or the returned status is not safe to rely on. With `--json`, the structured status is still printed so agents can inspect `lastDecision.errorCode`, `lastDecision.message`, and `lastDecision.retryAfterSeconds`.

Known `lastDecision.errorCode` values include:

- `AGENT_CONTROL_DISABLED`
- `UNSUPPORTED_HARDWARE`
- `HELPER_UNREACHABLE`
- `TEMP_SENSOR_UNAVAILABLE`
- `NO_CONTROLLABLE_FANS`
- `POLICY_DENIED`
- `DURATION_TOO_LONG`
- `RPM_OUT_OF_RANGE`
- `THERMAL_CRITICAL`
- `LEASE_NOT_FOUND`
- `RESTORE_FAILED`
- `INVALID_ARGUMENTS`
- `PREPARE_RATE_LIMITED`
- `RESTORE_REQUESTED`

For JSON command/parse/transport failures, Vifty emits:

- `schemaVersion`
- `command`
- `errorCode`
- `message`
- `safeToProceed: false`
- `coolingLeasePrepared`
- `autoRestoreAttempted`
- `autoRestoreSucceeded`
- `retryAfterSeconds` when the error is `PREPARE_RATE_LIMITED` and Vifty can report a retry wait

### `audit --json`

`viftyctl audit --json` is read-only and returns the most recent bounded agent-control audit events through the daemon:

- `schemaVersion`
- `generatedAt`
- `readOnly: true`
- `coolingCommandsRun: false`
- `limit`
- `eventCount`
- `events[]`

Each event includes `timestamp`, `action`, optional `leaseID`, and `message`. Use `--limit <count>` to request a smaller or larger recent window; the daemon-backed store remains capped to the most recent 2,000 events by default. Agents can use this after a failed restore, blocked readiness, or user report to show what Vifty actually did without requesting cooling or reading raw SMC state.

For `viftyctl run --json`, wrapper failures before the child process starts use this same structured error shape. That includes child-command resolution failures, daemon prepare denial, and child launch failures after a cooling lease was prepared. When a lease was prepared before launch failed, `coolingLeasePrepared`, `autoRestoreAttempted`, and `autoRestoreSucceeded` tell agents whether Vifty reached the cleanup path and whether Auto restore succeeded. Canonical examples for both cleanup-success and cleanup-failure launch errors live in [docs/examples/viftyctl](examples/viftyctl). Once the child has started, Vifty preserves normal child output and wrapper exit/stderr behavior so agents do not confuse child stdout with a clean Vifty JSON document.

If `--force` is waiting for a `PREPARE_RATE_LIMITED` cooldown retry and the wait is interrupted before a lease is prepared, JSON callers receive `errorCode: PREPARE_RATE_LIMITED`, `coolingLeasePrepared: false`, `autoRestoreAttempted: false`, and `retryAfterSeconds` from the rate-limit decision or policy fallback.

Unknown wrapper options and unexpected positional arguments fail with `INVALID_ARGUMENTS` instead of being ignored. For `viftyctl run`, only arguments before `--` are parsed as Vifty wrapper options; child arguments after `--` are passed through to the child command.

## Preferred Wrapper

Use the generic wrapper in [examples/viftyctl/guarded-run.sh](../examples/viftyctl/guarded-run.sh) when you want a shell-friendly preflight and lifecycle wrapper:

```sh
examples/viftyctl/guarded-run.sh test 20m 70 "swift test" -- swift test
```

The wrapper:

- runs `capabilities --json` and requires the safe `runLifecycle` contract,
- runs `diagnose --json`,
- treats nonzero blocked diagnose reports as readiness blocks,
- fails closed and prints any structured diagnose failure before requesting cooling,
- refuses to continue on `blocked`,
- requires `recommendedAgentAction` and `safeToRequestCooling` to be present,
- treats `safeToRequestCooling: false` as a hard stop, including the restore-first active-lease case,
- proceeds only for `requestCooling` or `requestCoolingWithCaution`,
- prints a warning for `requestCoolingWithCaution`,
- then delegates to `viftyctl run --json`,
- and lets `viftyctl run` handle prepare, child launch, signal forwarding, and Auto restore.

The wrapper does not pass `--force` by default. If a supervised human workflow wants the CLI to wait once for `retryAfterSeconds` and retry a rate-limited prepare, set `VIFTY_GUARDED_RUN_FORCE_RETRY=1`; the wrapper still checks `supportsForceRetry` before passing `--force`. Local agents should leave that off unless the user explicitly asks them to retry after a rate limit.

Set `VIFTYCTL` to point at a development bundle:

```sh
VIFTYCTL=.build/Vifty.app/Contents/MacOS/viftyctl \
  examples/viftyctl/guarded-run.sh test 20m 70 "swift test" -- swift test
```

The [examples/viftyctl](../examples/viftyctl/README.md) directory also includes small workload wrappers for common developer commands. They all delegate through `guarded-run.sh` and keep the same read-only capabilities/readiness gates:

```sh
examples/viftyctl/swift-test.sh --filter ViftyCoreTests
examples/viftyctl/swift-release-build.sh --product Vifty
examples/viftyctl/xcode-test.sh -scheme MyApp -destination 'platform=macOS'
examples/viftyctl/npm-test.sh -- --watch=false
examples/viftyctl/cargo-test.sh --locked
examples/viftyctl/pytest.sh Tests
examples/viftyctl/local-model.sh -- ./run-local-model.sh
examples/viftyctl/custom-workload.sh 15m 65 "project smoke test" -- ./scripts/smoke-test.sh
```

## Common Workloads

Swift package tests:

```sh
examples/viftyctl/swift-test.sh
```

Swift release build:

```sh
examples/viftyctl/swift-release-build.sh
```

Xcode test:

```sh
examples/viftyctl/xcode-test.sh -scheme MyApp -destination 'platform=macOS'
```

npm test:

```sh
examples/viftyctl/npm-test.sh
```

Cargo test:

```sh
examples/viftyctl/cargo-test.sh
```

pytest:

```sh
examples/viftyctl/pytest.sh
```

Local model run:

```sh
examples/viftyctl/local-model.sh -- ./run-local-model.sh
```

## Direct Prepare/Restore

Prefer `run`. Use direct prepare/restore only when the workload lifecycle is managed by another process:

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
      --reason "external build coordinator complete" \
      --json || status=70
  fi

  exit "$status"
}

trap cleanup EXIT INT TERM HUP

"$VIFTYCTL" prepare \
  --workload build \
  --duration 20m \
  --max-rpm-percent 70 \
  --reason "external build coordinator" \
  --idempotency-key "$LEASE_KEY" \
  --json
PREPARED=1

# Run external coordinated work here.
```

This pattern still has more moving parts than `viftyctl run`, so use it only when a single child command cannot model the workload. Keep the trap installed for `EXIT`, `INT`, `TERM`, and `HUP`; do not put more fan-control commands inside the work section.

If prepare returns `PREPARE_RATE_LIMITED`, use `lastDecision.retryAfterSeconds` or call again with `--force` for human-driven workflows. Agents should prefer the explicit retry value so they do not hide repeated thermal thrashing.

## Agent Policy

Recommended agent behavior:

- Refuse to call `prepare` when `diagnose.state` is `blocked`.
- For `degraded`, reduce duration to 10-15 minutes and cap RPM at 55-65% unless the user explicitly requested more.
- Stop or back off the workload on `THERMAL_CRITICAL`.
- On `RESTORE_REQUESTED`, assume the user intentionally chose Auto and do not retry automatically.
- On `HELPER_UNREACHABLE`, ask the user to open Vifty and reinstall the helper rather than attempting direct SMC writes.
- On `PREPARE_RATE_LIMITED`, wait for `retryAfterSeconds` before retrying.
- Leave `VIFTY_GUARDED_RUN_FORCE_RETRY` unset unless a supervised human workflow explicitly wants the guarded wrapper to wait once and retry a rate-limited prepare.
- If `viftyctl run --json` reports `coolingLeasePrepared: true` and `autoRestoreSucceeded: false`, show the user the restore failure and run `viftyctl status --json` before starting more work.
- After any unexpected wrapper failure, run `viftyctl status --json` and show the user whether an active lease remains.

## Safety Notes

- `viftyctl run` resolves the child executable before requesting cooling.
- `viftyctl` rejects unknown wrapper options instead of silently ignoring them.
- `viftyctl run` refuses to launch the child if prepare is denied or does not return a matching active lease.
- `viftyctl run` restores Auto after normal child exit, handled signal exit, or child launch failure.
- If Auto restore fails after a successful child exit, `viftyctl run` exits nonzero and prints the restore failure.
- If the wrapper is force-killed or crashes, the daemon-owned lease monitor remains the safety fallback until lease expiry.
- The unprivileged app path must fail closed; do not replace `viftyctl` with direct `ViftyHelper` or AppleSMC writes in automation.
