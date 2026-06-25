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

Installed app bundles include the same wrappers under `Contents/Resources/viftyctl-wrappers/`. From an installed app, prefer:

```sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/guarded-run.sh test 20m 70 "swift test" -- swift test
```

The Vifty main window and menu-bar popover can copy both a short agent rule and
common guarded command templates. Use **Copy Safe Command** when you want an
audited wrapper command for Swift, Xcode, Make, npm, pnpm, Bun, Go, cargo, uv,
pytest, local-model, or custom workload templates; use the read-only preflight
entries when an agent only needs to check readiness without requesting cooling
or launching the child command.

Agents can also fetch the same short rule from the CLI with `viftyctl agent-rule
--json`. That payload declares `schemaID:
"https://vifty.local/schemas/viftyctl-agent-rule.schema.json"` and is read-only
guidance, not cooling authorization. Compare the value with
`capabilities.schemaIDs.agentRule`, use its `guardedRunDecisionSchemaID` to
validate guarded-run no-cooling/preflight decision payloads, and use
`guardedRunJSONMarkers` to extract wrapper capabilities/diagnose/decision JSON
without hardcoding marker strings. Still run `capabilities --json` and
`diagnose --json` before any guarded workload requests cooling. Since the rule
contains runnable command examples, live output is
location-aware: installed app runs use `/Applications/Vifty.app`, SwiftPM/source
checkout runs use `.build/.../ViftyCtl` plus `examples/viftyctl/...`, and
non-canonical/custom app bundles add `VIFTYCTL=...` so copied wrappers call the
same `viftyctl` binary.

## Contract

Agents should treat `viftyctl` as a local safety contract:

1. Run `viftyctl diagnose --json` before long workloads.
2. Treat `state: "blocked"` as a hard stop.
3. Treat `state: "degraded"` as proceed-with-caution; prefer shorter durations and lower RPM percent.
4. Use `viftyctl run` for child workloads whenever possible so Vifty prepares cooling, launches the resolved child command, and restores Auto afterward.
5. Use `prepare` and `restore-auto` directly only when a wrapper command cannot model the workload lifecycle.
6. Always include a non-blank human-readable `--reason` and a stable non-blank `--idempotency-key` when preparing directly.
7. Do not pass `--idempotency-key` to `restore-auto`; restore is intentionally tied to the supervised lifecycle, not a scoped key.
8. After a successful direct `restore-auto`, re-run `diagnose --json`; the CLI clears the same local `manualControlActive` marker that diagnose uses as the restore-first gate.

Vifty never exposes raw SMC writes through `viftyctl`. Agents request intent: workload type, maximum duration, maximum RPM percent, and reason. The daemon evaluates policy, writes bounded fan targets if allowed, records the lease, and owns expiry.

## Commands

```sh
viftyctl status --json
viftyctl capabilities --json
viftyctl agent-rule --json
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

Durations accept seconds, `m`, or `h`, for example `600`, `20m`, or `1h`. Explicit `--reason` and `--idempotency-key` values are trimmed and rejected if blank or oversized; reasons are capped at 512 characters and idempotency keys at 256 characters so daemon status, lease persistence, and audit entries stay bounded and meaningful. The daemon applies the same metadata check to programmatic agent requests before hardware access, so clients that bypass the CLI parser still fail closed with `INVALID_ARGUMENTS`. Restore and lease-clear audit reasons are trimmed too; blank programmatic restore reasons fall back to a safe default and oversized reasons are truncated instead of blocking Auto restore. The default daemon policy caps leases at 30 minutes unless policy is changed in code.

## JSON Decision Rules

### `diagnose --json`

The readiness report has `schemaVersion: 1` and a top-level `state`:

- `ready` - all required checks passed.
- `degraded` - no hard blocker, but one or more warning checks failed.
- `blocked` - at least one error check failed; do not request cooling.

It also includes `recommendedAgentAction`, `safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`, `failedCheckIDs`, `coolingBlockerIDs`, and `appPreferences.startupMode` so agents do not need to infer the next step from prose, fallback telemetry, or Vifty UI state:

- `requestCooling` / `safeToRequestCooling: true` - safe to request a normal bounded lease.
- `requestCoolingWithCaution` / `safeToRequestCooling: true` - a warning exists; reduce duration/RPM or be ready to back off.
- `restoreAutoBeforeRequestingCooling` / `safeToRequestCooling: false` - another lease or manual-control marker is active; restore Auto once or wait before requesting new cooling. A successful CLI `restore-auto` clears the local manual-control marker, but agents should re-run `diagnose --json` and require `manualControlActive: false` before cooling. Do not loop `restore-auto`; if `manualControlActive` stays true after one restore, inspect `appPreferences.startupMode`, then stop and ask the user to switch Vifty/default startup mode to Auto before requesting cooling.
- `doNotRequestCooling` / `safeToRequestCooling: false` - a hard blocker exists.
- `daemonControlPathReady: false` - the daemon-backed snapshot or agent-control path is unavailable; repair the helper before requesting cooling, even if other telemetry exists.

Canonical diagnose fixtures live in [docs/examples/viftyctl](examples/viftyctl). Use them to test agent behavior against the four non-happy-path decisions:

- [diagnose-degraded-caution.json](examples/viftyctl/diagnose-degraded-caution.json) - degraded + `requestCoolingWithCaution` + `safeToRequestCooling: true`.
- [diagnose-degraded-active-lease.json](examples/viftyctl/diagnose-degraded-active-lease.json) - degraded + `restoreAutoBeforeRequestingCooling` + `safeToRequestCooling: false`.
- [diagnose-degraded-manual-control.json](examples/viftyctl/diagnose-degraded-manual-control.json) - degraded + `restoreAutoBeforeRequestingCooling` + `manualControlActive: true`.
- [diagnose-blocked-helper-unreachable.json](examples/viftyctl/diagnose-blocked-helper-unreachable.json) - blocked + `doNotRequestCooling` + `daemonControlPathReady: false`.

Do not treat `state: degraded` as automatically safe or unsafe. `safeToRequestCooling` is the gate. Do treat `daemonControlPathReady: false` as a hard helper-repair stop, and `manualControlActive: true` as a restore-Auto stop before an agent takes ownership. If an agent runs the supervised CLI restore path, the next diagnose must show `manualControlActive: false` before the agent requests cooling. Do not loop `restore-auto`; if `manualControlActive` stays true after one restore, inspect `appPreferences.startupMode`, then stop and ask the user to switch Vifty/default startup mode to Auto.

`failedCheckIDs` mirrors every failed readiness check ID in order. `coolingBlockerIDs` is the hard-stop subset: failed error checks plus restore-first ownership checks such as `activeLeaseClear` and `manualControlClear`. Warning-only caution states can have `failedCheckIDs` such as `thermalPressureSafe` while `coolingBlockerIDs` remains empty, so agents should still use `safeToRequestCooling` and `recommendedAgentAction` as the final gate.

`recommendedRecoveryAction` gives the next safe follow-up without parsing `checks[].message`. Current payloads also include ordered `recoverySteps` that agents may show directly after applying the safety gates:

- `none` - no recovery is needed before following `recommendedAgentAction`.
- `repairHelper` - open Vifty and use Repair/Reinstall Helper; do not attempt direct SMC writes.
- `restoreAutoBeforeRetry` - restore Auto once, re-run diagnose, or wait for the active lease to clear before retrying. If `manualControlActive` stays true, inspect `appPreferences.startupMode`, then switch Vifty/default startup mode to Auto before another cooling request.
- `backOffWorkload` - thermal pressure is critical; pause or reduce the workload instead of fighting system thermals.
- `inspectPolicy` - agent cooling policy is disabled; inspect local policy/status before retrying.
- `collectHardwareEvidence` - hardware/fan/sensor evidence is missing or inconsistent; collect read-only validation evidence before considering support.

`diagnose` exits `0` for `ready` and `degraded`. It exits with `capabilities.exitCodes.blockedReadiness` for `blocked` after printing the same structured readiness report, so shell automation can fail closed without losing machine-readable evidence.

Important fields:

- `modelIdentifier`
- `isAppleSilicon`
- `isMacBookPro`
- `thermalPressure`
- `recommendedAgentAction`
- `recommendedRecoveryAction`
- `recoverySteps`
- `safeToRequestCooling`
- `daemonControlPathReady`
- `manualControlActive`
- `failedCheckIDs`
- `coolingBlockerIDs`
- `appPreferences`
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
- `daemonControlPathReady`
- `supportedHardware`
- `agentControlEnabled`
- `temperatureSensorsPresent`
- `controllableFansPresent`
- `fanIDsValid`
- `fanIDsUnique`
- `fanRangesValid`
- `thermalPressureSafe`
- `activeLeaseClear`
- `manualControlClear`
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
- `schemas.agentRule`
- `schemaResources.capabilities`
- `schemaResources.audit`
- `schemaResources.diagnose`
- `schemaResources.status`
- `schemaResources.commandError`
- `schemaResources.run`
- `schemaResources.agentRule`
- `schemaIDs.capabilities`
- `schemaIDs.audit`
- `schemaIDs.diagnose`
- `schemaIDs.status`
- `schemaIDs.commandError`
- `schemaIDs.run`
- `schemaIDs.agentRule`
- `policy.enabled`
- `policy.minimumAgentRPMPercent`
- `policy.maximumAllowedRPMPercent`
- `policy.maxDurationSeconds`
- `policy.prepareCooldownSeconds`
- `policySource`
- `daemonStatusAvailable`
- `policyStatusAvailable`
- `agentControlStatusError`
- `supportsForceRetry` (treat a missing value in legacy payloads as `false`)
- `runLifecycle.childCommandPreflightBeforeCooling`
- `runLifecycle.signalsForwardedToChild`
- `runLifecycle.autoRestoreAfterChildExit`
- `runLifecycle.structuredPreChildFailures`
- `runLifecycle.cleanupStateReportedOnLaunchFailure`
- `runLifecycle.resolvedChildExecutableReported`
- `directControlLifecycle.prepareUsesIdempotencyKey`
- `directControlLifecycle.restoreAutoAcceptsIdempotencyKey`
- `directControlLifecycle.restoreAutoScopedByIdempotencyKey`
- `directControlLifecycle.preferRunForSingleChildWorkloads`
- `metadataLimits.maximumReasonLength`
- `metadataLimits.maximumIdempotencyKeyLength`
- `wrapperResources.sourceDirectory`
- `wrapperResources.bundleDirectory`
- `wrapperResources.guardedRunScript`
- `wrapperResources.workloadScripts`
- `workloadTemplates`
- `exitCodes.success`
- `exitCodes.commandFailure`
- `exitCodes.usage`
- `exitCodes.unavailable`
- `exitCodes.blockedReadiness`

Use this output rather than hardcoding policy limits, metadata limits, wrapper paths/script names, workload command templates, schema paths/resource paths/IDs, shell exit-code meanings, or `viftyctl run` wrapper guarantees in an agent. `schemas` points at source-tree documentation paths, `schemaResources` points at the installed app bundle paths under `Vifty.app/Contents/Resources/schemas`, `wrapperResources` points at source-tree and app-bundle-relative guarded workload wrapper locations, `workloadTemplates` lists the audited title/workload/duration/RPM cap/reason/child-command defaults used by the app's copy menu, and `schemaIDs` gives stable IDs for validators. The wrapper paths are relative on purpose: combine `wrapperResources.bundleDirectory` with a known app-bundle root, or combine `wrapperResources.sourceDirectory` with a known source checkout, instead of expecting Vifty to publish user-specific absolute paths in evidence bundles. Guarded wrappers must require `schemaVersion: 1`, `schemaIDs.capabilities: "https://vifty.local/schemas/viftyctl-capabilities.schema.json"`, `schemaIDs.diagnose: "https://vifty.local/schemas/viftyctl-diagnose.schema.json"`, `schemaIDs.commandError: "https://vifty.local/schemas/viftyctl-command-error.schema.json"`, `schemaIDs.run: "https://vifty.local/schemas/viftyctl-run.schema.json"`, and `schemaIDs.agentRule: "https://vifty.local/schemas/viftyctl-agent-rule.schema.json"` before trusting lifecycle, readiness, policy, wrapper discovery, workload templates, command-error fields, completed-run fields, or a fetched agent-rule payload. Structured command-error payloads also declare `schemaVersion: 1` and `schemaID: "https://vifty.local/schemas/viftyctl-command-error.schema.json"`; agents should compare that value with `capabilities.schemaIDs.commandError` before trusting `errorCode`, `safeToProceed`, `recommendedRecoveryAction`, cleanup fields, or retry metadata. Completed `viftyctl run --json` payloads after a launched child command declare `schemaVersion: 1` and `schemaID: "https://vifty.local/schemas/viftyctl-run.schema.json"`; agents should compare that value with `capabilities.schemaIDs.run` before trusting `childExitCode`, optional `childTerminationReason`, optional `childSignal`, optional `childSignalName`, `autoRestoreSucceeded`, `autoRestoreError`, `resolvedChildExecutable`, optional `resolvedChildExecutableSHA256`, or optional `resolvedChildExecutableSHA256Status`. `viftyctl agent-rule --json` payloads declare `schemaVersion: 1` and `schemaID: "https://vifty.local/schemas/viftyctl-agent-rule.schema.json"`; agents should compare that value with `capabilities.schemaIDs.agentRule` before using the emitted rule text, command examples, safety requirements, forbidden actions, or workload template IDs. The agent-rule payload is read-only guidance, not cooling authorization. `runLifecycle` tells agents whether the wrapper validates the child command before cooling, forwards handled signals, restores Auto after child exit, uses structured pre-child JSON failures, reports cleanup state after launch failures, and includes the resolved absolute child executable in completed run JSON. `directControlLifecycle` tells agents whether direct prepare/restore has the expected supervised lifecycle: prepare uses idempotency keys, `restore-auto` rejects `--idempotency-key`, restore is not key-scoped, and `viftyctl run` remains preferred for single child workloads. `metadataLimits` tells agents how long generated reason and idempotency-key values may be after trimming. If `wrapperResources` is absent in a legacy payload, do not guess installed wrapper paths from the capabilities payload; fall back to documented defaults or ask the user for the installed app/source checkout location. If `workloadTemplates` is absent in a legacy payload, agents may use documented examples but must not infer that unlisted commands are audited templates. `policyStatusAvailable` tells agents whether `policy.*` was read from daemon agent-control status and is safe to use for local preflight limits. If `policyStatusAvailable` is absent or false, do not trust `policy.*` duration/RPM limits, do not request cooling, and treat the capabilities payload as discovery-only. If `policy.enabled` is absent or false, treat agent cooling as locally disabled and refuse to request cooling even if a stale readiness payload looks safe. If `runLifecycle`, `directControlLifecycle`, or `metadataLimits` is absent in a legacy payload, treat those lifecycle or metadata guarantees as unsupported and refuse agent cooling instead of assuming defaults; if `runLifecycle.resolvedChildExecutableReported` is absent or false, guarded wrappers should refuse cooling because completed-run executable provenance is unsupported. `supportsForceRetry` tells supervised wrappers whether they may pass `--force`; if the field is absent in a legacy payload, treat it as unsupported. If daemon status is unavailable, `capabilities --json` still prints the static command contract, but returns `exitCodes.unavailable`, sets `daemonStatusAvailable: false`, sets `policyStatusAvailable: false`, sets `policySource: "fallbackUnavailable"`, and reports a disabled fallback policy. Treat that as discovery-only; run `diagnose --json` or ask the user to repair the helper before requesting cooling.

Canonical examples live in [docs/examples/viftyctl](examples/viftyctl/README.md). The XCTest suite decodes those fixtures against the current Swift models so agent-facing examples stay aligned with implementation.

Agent-facing schemas live in [docs/schemas](schemas) and are bundled into release app artifacts at `Vifty.app/Contents/Resources/schemas`. Agents should pin readiness behavior to [viftyctl-diagnose.schema.json](schemas/viftyctl-diagnose.schema.json)'s safety fields: `state`, `recommendedAgentAction`, `recommendedRecoveryAction`, `recoverySteps`, `safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`, `failedCheckIDs`, `coolingBlockerIDs`, hardware support flags, fan/sensor counts, `agentControl`, and `checks`. The additive `appPreferences.startupMode` field helps diagnose persistent manual-control markers, but it is not a cooling authorization. The same folder also documents capabilities, audit, status/prepare/restore-auto, completed run reports, and structured command-error payloads.

For copy/paste instructions tailored to Codex, Claude Code, Cursor, and shell runners, see [agent-integrations.md](agent-integrations.md).

### `prepare --json` and `status --json`

The status response includes:

- `schemaVersion`
- `schemaID`
- `generatedAt`
- `enabled`
- `activeLease`
- `lastDecision`
- `lastErrorCode`
- `policy`

Successful `status --json`, `prepare --json`, and `restore-auto --json` payloads identify this shape with `schemaVersion: 1` and `schemaID: "https://vifty.local/schemas/viftyctl-status.schema.json"` while keeping the operational fields at the top level. `prepare` exits with code `0` only when the daemon returns an active lease matching the request. It exits nonzero when cooling is denied or the returned status is not safe to rely on. With `--json`, the structured status is still printed so agents can inspect `lastDecision.errorCode`, `lastDecision.message`, and `lastDecision.retryAfterSeconds`.

Successful completed `run --json` payloads identify their shape with `schemaVersion: 1` and `schemaID: "https://vifty.local/schemas/viftyctl-run.schema.json"`. They are emitted only after the child command has launched and exited; pre-child failures, prepare denials, launch failures, and cleanup failures before a child exit continue to use the structured command-error schema. Use `childExitCode` for the wrapped workload result and `autoRestoreSucceeded` / `autoRestoreError` for cleanup status after the workload. Current builds also include `childTerminationReason`; `signalInferred` means the exit code looked like `128 + signal`, with `childSignal` and `childSignalName` included when Vifty can infer them. Treat that as a machine-readable interruption hint, not a guarantee that the child could not have returned the same numeric code itself. When `capabilities.runLifecycle.resolvedChildExecutableReported` is true, `resolvedChildExecutable` gives the absolute executable path Vifty selected before requesting cooling. Current builds also include `resolvedChildExecutableSHA256Status`; `computed` means `resolvedChildExecutableSHA256` contains the lowercase SHA-256 digest, while `unavailable` means Vifty could not read or hash the executable bytes. The digest gives reviewers byte-level provenance without turning hashing into a safety precondition.

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
- `CHILD_COMMAND_FAILED`
- `PREPARE_RATE_LIMITED`
- `RESTORE_REQUESTED`

For JSON command/parse/transport failures, Vifty emits:

- `schemaVersion`
- `command`
- `errorCode`
- `message`
- `safeToProceed: false`
- `recommendedRecoveryAction`
- `recoverySteps`
- `coolingLeasePrepared`
- `autoRestoreAttempted`
- `autoRestoreSucceeded`
- `retryAfterSeconds` when the error is `PREPARE_RATE_LIMITED` and Vifty can report a retry wait

`recommendedRecoveryAction` is the stable machine-readable next step for command failures. Current values are `runDiagnose`, `repairHelper`, `fixArguments`, `fixChildCommand`, `restoreAutoBeforeRetry`, and `waitBeforeRetry`. Current payloads also include ordered `recoverySteps`; agents should prefer these fields over parsing `message` text.

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

For `viftyctl run --json`, wrapper failures before the child process starts use this same structured error shape. That includes child-command resolution failures, daemon prepare denial, and child launch failures after a cooling lease was prepared. Child-command failures report `CHILD_COMMAND_FAILED` so agents can fix the workload command instead of treating the Vifty helper as unavailable. When a lease was prepared before launch failed, `coolingLeasePrepared`, `autoRestoreAttempted`, and `autoRestoreSucceeded` tell agents whether Vifty reached the cleanup path and whether Auto restore succeeded. Canonical examples for pre-cooling child-command failure, cleanup-success launch failure, and cleanup-failure launch error live in [docs/examples/viftyctl](examples/viftyctl). Once the child has started, Vifty preserves normal child output and wrapper exit/stderr behavior so agents do not confuse child stdout with a clean Vifty JSON document.

If `--force` is waiting for a `PREPARE_RATE_LIMITED` cooldown retry and the wait is interrupted before a lease is prepared, JSON callers receive `errorCode: PREPARE_RATE_LIMITED`, `coolingLeasePrepared: false`, `autoRestoreAttempted: false`, and `retryAfterSeconds` from the rate-limit decision or policy fallback.

Unknown wrapper options, duplicate wrapper options, missing option values, and unexpected positional arguments fail with `INVALID_ARGUMENTS` instead of being ignored, silently choosing one value, or generating a default value. For `viftyctl run`, only arguments before `--` are parsed as Vifty wrapper options; child arguments after `--` are passed through to the child command.

## Preferred Wrapper

Use the generic wrapper in [examples/viftyctl/guarded-run.sh](../examples/viftyctl/guarded-run.sh) when you want a shell-friendly preflight and lifecycle wrapper:

```sh
examples/viftyctl/guarded-run.sh test 20m 70 "swift test" -- swift test
```

For read-only planning, use the same wrapper with `--preflight-only` or
`VIFTY_GUARDED_RUN_PREFLIGHT_ONLY=1`:

```sh
examples/viftyctl/guarded-run.sh --preflight-only test 20m 70 "swift test" -- swift test
```

Preflight-only validates the child command, capabilities, policy, metadata
limits, and diagnose readiness, then exits before `viftyctl run` and before the
child command starts. A passing preflight-only decision emits
`schemaID: https://vifty.local/schemas/guarded-run-decision.schema.json`,
`decisionReason: "preflightReady"`, `coolingRequested: false`, and `exitCode:
0`; it proves the guarded path is currently available, not that cooling has
already been requested.

The wrapper:

- runs `capabilities --json` and requires schema version `1`, the stable capabilities, diagnose, command-error, and run schema IDs, current `wrapperResources` discovery metadata, and the safe `runLifecycle` contract,
- requires `policyStatusAvailable: true`, `policy.enabled: true`, and advertised policy duration/RPM limits, then rejects durations or RPM percentages outside the daemon's advertised policy range before readiness or cooling,
- requires `metadataLimits` and rejects reasons longer than the advertised maximum before readiness or cooling,
- runs `diagnose --json` and requires diagnose readiness schema version `1`,
- treats nonzero blocked diagnose reports as readiness blocks,
- fails closed and prints any structured diagnose failure before requesting cooling only when a nonzero diagnose command-error payload matches the advertised command-error schema identity,
- refuses to continue on `blocked`,
- requires `recommendedAgentAction`, `recommendedRecoveryAction`, `recoverySteps`, `safeToRequestCooling`, `daemonControlPathReady`, and `manualControlActive` to be present,
- treats `safeToRequestCooling: false` as a hard stop, including the restore-first active-lease or manual-control case,
- treats `daemonControlPathReady: false` as a hard stop before cooling,
- treats `manualControlActive: true` as a restore-Auto stop before cooling,
- prints `recommendedRecoveryAction` and `recoverySteps` guidance for blocked or restore-first readiness; for older `repairHelper` payloads without `recoverySteps`, agents should fall back to the optional `repairHelperRecoveryActions` array from `viftyctl agent-rule --json`, including the source-checkout `make repair-helper` path,
- proceeds only for `requestCooling` or `requestCoolingWithCaution`,
- prints a warning for `requestCoolingWithCaution`,
- exits after decision JSON when preflight-only is requested,
- then delegates to `viftyctl run --json`,
- and lets `viftyctl run` handle prepare, child launch, signal forwarding, and Auto restore.

For hardware-validation or maintainer triage where you need to know whether the supervised smoke collector may cross the cooling boundary, run `make agent-run-smoke-readiness` first. `AGENT_RUN_SMOKE_READINESS_JSON=1 make agent-run-smoke-readiness` emits `schemaID: https://vifty.local/schemas/agent-run-smoke-readiness.schema.json`, `readOnly: true`, and `coolingCommandsRun: false`; `AGENT_RUN_SMOKE_READINESS_SUMMARY=.build/agent-run-smoke-readiness.json` saves the same JSON for review. The preflight validates daemon-backed capabilities, policy limits, wrapper lifecycle, `safeToRequestCooling`, helper readiness, manual-control state, and optional daemon hash matching without calling `viftyctl run`. Saved summaries omit the full reason text, carry `reasonCharacterCount`, and mark daemon path display values as `system`, `relative`, `basenameOnly`, or `notProvided` so reviewer evidence can stay share-safe. Blocked summaries also copy diagnose `recoverySteps` so agents and maintainers can show the next safe action without scraping human output.

The wrapper does not pass `--force` by default. If a supervised human workflow wants the CLI to wait once for `retryAfterSeconds` and retry a rate-limited prepare, set `VIFTY_GUARDED_RUN_FORCE_RETRY=1`; the wrapper still checks `supportsForceRetry` before passing `--force`. Local agents should leave that off unless the user explicitly asks them to retry after a rate limit. Do not combine it with `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1` or `VIFTY_GUARDED_RUN_PREFLIGHT_ONLY=1`; the wrapper refuses that ambiguous mix.

The wrapper also does not silently rerun workloads without cooling. If the user
explicitly wants the child command to run without Vifty after a structured
readiness block, set `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1`. The wrapper still
prints the diagnose JSON plus a guarded-run decision payload between
`guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON` and
`guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON`, refuses to request cooling,
and only then execs the child directly; it refuses that fallback for
`repairHelper`, `backOffWorkload`, `restoreAutoBeforeRetry`, `inspectPolicy`,
`collectHardwareEvidence`, `manualControlActive: true`,
`daemonControlPathReady: false`, force-retry combinations, and preflight-only
combinations. The decision
payload uses `schemaID:
https://vifty.local/schemas/guarded-run-decision.schema.json` and includes
`decisionReason` so agents can classify the wrapper-level no-cooling decision
without parsing `message`.

Set `VIFTYCTL` to point at a development bundle:

```sh
VIFTYCTL=.build/Vifty.app/Contents/MacOS/viftyctl \
  examples/viftyctl/guarded-run.sh test 20m 70 "swift test" -- swift test
```

The [examples/viftyctl](../examples/viftyctl/README.md) directory also includes small workload wrappers for common developer commands. They all delegate through `guarded-run.sh` and keep the same read-only capabilities/readiness gates:

```sh
examples/viftyctl/swift-test.sh --filter ViftyCoreTests
examples/viftyctl/swift-release-build.sh --product Vifty
examples/viftyctl/xcode-build.sh -scheme MyApp -destination 'platform=macOS'
examples/viftyctl/xcode-test.sh -scheme MyApp -destination 'platform=macOS'
examples/viftyctl/make-build.sh
examples/viftyctl/make-test.sh
examples/viftyctl/make-verify.sh
examples/viftyctl/npm-build.sh -- --mode=production
examples/viftyctl/npm-test.sh -- --watch=false
examples/viftyctl/pnpm-build.sh -- --mode=production
examples/viftyctl/pnpm-test.sh -- --runInBand=false
examples/viftyctl/bun-build.sh
examples/viftyctl/bun-test.sh
examples/viftyctl/go-build.sh ./...
examples/viftyctl/go-test.sh ./...
examples/viftyctl/cargo-build.sh --release
examples/viftyctl/cargo-test.sh --locked
examples/viftyctl/uv-build.sh
examples/viftyctl/uv-test.sh Tests
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

Xcode build:

```sh
examples/viftyctl/xcode-build.sh -scheme MyApp -destination 'platform=macOS'
```

Xcode test:

```sh
examples/viftyctl/xcode-test.sh -scheme MyApp -destination 'platform=macOS'
```

Make test:

```sh
examples/viftyctl/make-test.sh
```

Make build:

```sh
examples/viftyctl/make-build.sh
```

Make verify:

```sh
examples/viftyctl/make-verify.sh
```

npm test:

```sh
examples/viftyctl/npm-test.sh
```

npm build:

```sh
examples/viftyctl/npm-build.sh
```

pnpm test:

```sh
examples/viftyctl/pnpm-test.sh
```

pnpm build:

```sh
examples/viftyctl/pnpm-build.sh
```

Bun test:

```sh
examples/viftyctl/bun-test.sh
```

Bun build:

```sh
examples/viftyctl/bun-build.sh
```

Go build:

```sh
examples/viftyctl/go-build.sh ./...
```

Go test:

```sh
examples/viftyctl/go-test.sh ./...
```

Cargo build:

```sh
examples/viftyctl/cargo-build.sh --release
```

Cargo test:

```sh
examples/viftyctl/cargo-test.sh
```

uv build:

```sh
examples/viftyctl/uv-build.sh
```

uv pytest:

```sh
examples/viftyctl/uv-test.sh
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

`restore-auto` is intentionally not scoped by idempotency key. Keep the restore call in the same supervised script that prepared cooling instead of trying to restore by key from a later agent step.

If prepare returns `PREPARE_RATE_LIMITED`, use `lastDecision.retryAfterSeconds` or call again with `--force` for human-driven workflows. Agents should prefer the explicit retry value so they do not hide repeated thermal thrashing.

## Agent Policy

Recommended agent behavior:

- Refuse to call `prepare` when `diagnose.state` is `blocked`.
- For `degraded`, reduce duration to 10-15 minutes and cap RPM at 55-65% unless the user explicitly requested more.
- Stop or back off the workload on `THERMAL_CRITICAL`.
- On `RESTORE_REQUESTED`, assume the user intentionally chose Auto and do not retry automatically.
- On `HELPER_UNREACHABLE`, ask the user to open Vifty and reinstall the helper rather than attempting direct SMC writes.
- On `CHILD_COMMAND_FAILED`, fix the workload command/path or show the launch error; do not repair Vifty helper state or retry cooling.
- On `PREPARE_RATE_LIMITED`, wait for `retryAfterSeconds` before retrying.
- Leave `VIFTY_GUARDED_RUN_FORCE_RETRY` unset unless a supervised human workflow explicitly wants the guarded wrapper to wait once and retry a rate-limited prepare.
- If `viftyctl run --json` reports `coolingLeasePrepared: true` and `autoRestoreSucceeded: false`, show the user the restore failure and run `viftyctl status --json` before starting more work.
- After any unexpected wrapper failure, run `viftyctl status --json` and show the user whether an active lease remains.

## Safety Notes

- `viftyctl run` resolves the child executable before requesting cooling.
- Current `viftyctl run --json` reports include `resolvedChildExecutable` after the child exits, `childTerminationReason` plus inferred signal fields when the exit code looks like `128 + signal`, and `resolvedChildExecutableSHA256Status` plus `resolvedChildExecutableSHA256` when the executable bytes are readable, so agents can audit which executable received cooling, whether the workload appears interrupted, and whether byte-level provenance was computed.
- `viftyctl` rejects unknown, duplicate, or missing-value wrapper options instead of silently ignoring them, choosing one value, or generating a default value.
- `viftyctl run` refuses to launch the child if prepare is denied or does not return a matching active lease.
- `viftyctl run` restores Auto after normal child exit, handled signal exit, or child launch failure.
- If Auto restore fails after a successful child exit, `viftyctl run` exits nonzero and prints the restore failure.
- If the wrapper is force-killed or crashes, the daemon-owned lease monitor remains the safety fallback until lease expiry.
- The unprivileged app path must fail closed; do not replace `viftyctl` with direct `ViftyHelper` or AppleSMC writes in automation.
