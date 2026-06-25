# Safe Local Agent Cooling

Use this guide when a local coding agent, build script, or shell runner wants temporary cooling for a long developer workload. Vifty's safe path is intentionally narrow: read-only readiness first, one bounded workload lease, validated child command, then Auto restore.

This guide is for supported Apple Silicon MacBook Pro hardware only. Unsupported Macs should run workloads normally under macOS automatic fan control.

## Rules

Agents and scripts may:

- run `viftyctl agent-rule --json`, `diagnose --json`, `status --json`, `capabilities --json`, and `audit --json`;
- run workloads through `/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/guarded-run.sh`, `examples/viftyctl/guarded-run.sh`, or their convenience wrappers;
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

Prefer the guarded wrapper. It checks that the child command is a regular executable path or resolves to one on `PATH`, rejects malformed wrapper arguments before contacting Vifty, including blank reasons, checks the read-only `capabilities --json` output for schema version `1`, the stable capabilities, diagnose, command-error, and run schema IDs, advertised `run` command support, requested workload support, the advertised unavailable exit code, the `runLifecycle` contract including `resolvedChildExecutableReported=true`, `wrapperResources` discovery metadata, `policyStatusAvailable: true`, `policy.enabled: true`, policy duration/RPM limits, and `metadataLimits`, rejects durations and RPM percentages outside the advertised policy range and reasons longer than the advertised maximum before readiness or cooling, requires diagnose readiness schema version `1` or a recognized command-error schema identity when diagnose fails, runs read-only readiness, and delegates to `viftyctl run --json` only when Vifty says cooling is safe. Current completed run JSON includes `resolvedChildExecutable`, `childTerminationReason`, `resolvedChildExecutableSHA256Status`, and, when readable, `resolvedChildExecutableSHA256`, so agents can audit which executable Vifty cooled, whether the child appears to have been interrupted by a signal, and whether byte-level provenance was computed:

```sh
examples/viftyctl/guarded-run.sh test 20m 70 "swift test" -- swift test
```

For read-only planning, add `--preflight-only` or set
`VIFTY_GUARDED_RUN_PREFLIGHT_ONLY=1`. The wrapper still validates the child
command path, capabilities, policy, metadata limits, and diagnose readiness, but
it exits before `viftyctl run` and before launching the child:

```sh
examples/viftyctl/guarded-run.sh --preflight-only test 20m 70 "swift test" -- swift test
```

Successful preflight-only output includes guarded-run decision JSON with
`decisionReason: "preflightReady"`, `coolingRequested: false`, and `exitCode:
0`; agents can use that as permission to ask the user or continue into the real
guarded wrapper command without pretending cooling already ran. This means no cooling command or child command was run.

Installed app bundles include the same wrapper directory, so installed users can
prefer:

```sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/guarded-run.sh test 20m 70 "swift test" -- swift test
```

For machine-readable discovery, `viftyctl capabilities --json` advertises
`wrapperResources.bundleDirectory`, `wrapperResources.sourceDirectory`,
`wrapperResources.guardedRunScript`, and `wrapperResources.workloadScripts`.
Those paths are app-bundle/source-checkout relative rather than absolute, so
agents can combine them with a known installed app or checkout location without
recording user-specific paths in support evidence.

For a pasteable starter rule, `viftyctl agent-rule --json` emits
`schemaID: "https://vifty.local/schemas/viftyctl-agent-rule.schema.json"`,
`guardedRunDecisionSchemaID:
"https://vifty.local/schemas/guarded-run-decision.schema.json"`, the safe-rule
text, default guarded commands, safety requirements, forbidden actions, and
audited workload template IDs. It also includes `guardedRunJSONMarkers` for the
capabilities, diagnose, and decision marker pairs printed by guarded wrappers.
Treat it as read-only guidance, not cooling
authorization: compare the schema ID with `capabilities.schemaIDs.agentRule`,
then still require safe `capabilities --json` and `diagnose --json` output before
requesting cooling. Use `guardedRunDecisionSchemaID` when validating
preflight-only or no-cooling decision payloads from the guarded wrapper, and use
`guardedRunJSONMarkers` instead of hardcoding marker strings when extracting
wrapper JSON.

Use the installed CLI explicitly when running outside the Vifty repository:

```sh
VIFTYCTL=/Applications/Vifty.app/Contents/MacOS/viftyctl \
  /path/to/guarded-run.sh build 25m 75 "release build" -- swift build -c release
```

When the guarded wrapper refuses before `viftyctl run` or completes a
preflight-only check, it keeps the captured machine-readable payload extractable
from stderr: capabilities payloads are
bracketed by `guarded-run: BEGIN_VIFTY_CAPABILITIES_JSON` and
`guarded-run: END_VIFTY_CAPABILITIES_JSON`, while diagnose payloads are bracketed
by `guarded-run: BEGIN_VIFTY_DIAGNOSE_JSON` and
`guarded-run: END_VIFTY_DIAGNOSE_JSON`. Wrapper no-cooling or preflight-only decisions are
bracketed by `guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON` and
`guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON`, with `schemaID:
https://vifty.local/schemas/guarded-run-decision.schema.json`. Agents and
support tooling should extract the exact JSON between those markers instead of
parsing surrounding prose. Current wrapper decision payloads include
`decisionReason` so agents can classify readiness-blocked, manual-control,
daemon-control, hard-blocker, preflight-ready, and uncooled-fallback decisions
without scraping the human `message`. They also include a privacy-conscious
workload envelope: `requestedWorkload`, `requestedDuration`,
`requestedMaxRPMPercent`, `reasonCharacterCount`, `childCommandName`,
`childCommandKind`, and `childArgumentCount`. The reason text, full local
command path, and child argument values are intentionally omitted.

The guarded wrapper does not force-retry rate-limited prepares by default. For a supervised human workflow, set `VIFTY_GUARDED_RUN_FORCE_RETRY=1` to let `viftyctl run --force` wait once for the daemon's retry window and try again. The wrapper checks `supportsForceRetry` before passing `--force`. Agents should normally leave that unset and show the rate-limit JSON instead. Do not combine force retry with `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1` or `VIFTY_GUARDED_RUN_PREFLIGHT_ONLY=1`; the wrapper treats those as mutually exclusive operator choices. `viftyctl run` still revalidates the child command before preparing cooling, so direct CLI use keeps the same safety boundary.

The guarded wrapper also does not fall back to an uncooled workload by default.
When the user explicitly wants the child command to run without Vifty after a
structured readiness block, set `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1`. The
wrapper still performs read-only capabilities/readiness checks, prints the
diagnose JSON and wrapper decision JSON, refuses to request cooling, and only
then execs the child directly. The decision JSON sets `coolingRequested: false`,
`uncooledFallbackRequested: true`, and `uncooledFallbackAllowed: true` only for
that explicit no-cooling exec path. It still refuses uncooled execution when
Vifty recommends `repairHelper`,
`backOffWorkload`, `restoreAutoBeforeRetry`, `inspectPolicy`, or
`collectHardwareEvidence`; when `daemonControlPathReady` is false; or when
`manualControlActive` is true. The
uncooled fallback is mutually exclusive with `VIFTY_GUARDED_RUN_FORCE_RETRY=1`
and `VIFTY_GUARDED_RUN_PREFLIGHT_ONLY=1`.
Do not catch guarded-run failures and rerun workloads without cooling.

For common workloads, use the audited shortcuts:

```sh
examples/viftyctl/swift-test.sh
examples/viftyctl/swift-release-build.sh
examples/viftyctl/xcode-build.sh -scheme MyApp -destination 'platform=macOS'
examples/viftyctl/xcode-test.sh -scheme MyApp -destination 'platform=macOS'
examples/viftyctl/make-build.sh
examples/viftyctl/make-test.sh
examples/viftyctl/make-verify.sh
examples/viftyctl/npm-build.sh
examples/viftyctl/npm-test.sh
examples/viftyctl/pnpm-build.sh
examples/viftyctl/pnpm-test.sh
examples/viftyctl/bun-build.sh
examples/viftyctl/bun-test.sh
examples/viftyctl/go-build.sh ./...
examples/viftyctl/go-test.sh ./...
examples/viftyctl/cargo-build.sh --release
examples/viftyctl/cargo-test.sh
examples/viftyctl/uv-build.sh
examples/viftyctl/uv-test.sh
examples/viftyctl/pytest.sh
examples/viftyctl/local-model.sh -- ./run-local-model.sh
```

The installed equivalents live under
`/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/`.

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
| `manualControlActive: true`, `coolingBlockerIDs` includes `manualControlClear`, or check `manualControlClear` failed | Stop before cooling. Restore Auto once, re-run diagnose, inspect `appPreferences.startupMode`, and ask the user to switch Vifty/default startup mode to Auto if manual ownership persists. |
| `coolingBlockerIDs` is non-empty | Stop before cooling and show the blocker IDs plus `recommendedRecoveryAction` and `recoverySteps`. |
| `recommendedAgentAction: "restoreAutoBeforeRequestingCooling"` | Stop before cooling. Ask the user whether to restore Auto once or wait; do not loop restore attempts. |
| `state: "blocked"` or `safeToRequestCooling: false` | Do not request cooling. Show the JSON and run without Vifty only if the user explicitly wants that and the guarded wrapper allows it; use `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1` rather than catching wrapper failures yourself. |
| `daemonControlPathReady: false` | Do not request cooling. Ask the user to repair or reinstall the helper before retrying; source checkouts can use `make repair-helper` for the same explicit administrator-approved LaunchDaemon repair. |
| Diagnose `recommendedRecoveryAction: "repairHelper"` | Show payload-local `recoverySteps` when available, falling back to `repairHelperRecoveryActions` from `viftyctl agent-rule --json`: open Vifty and use Repair/Reinstall Helper, or in a source checkout run `make repair-helper`, then rerun `diagnose --json`. Do not attempt direct SMC writes or uncooled guarded fallback. |
| Diagnose `recommendedRecoveryAction: "restoreAutoBeforeRetry"` | Restore Auto once, re-run diagnose, clear manual/user ownership, or wait for the active lease to clear before retrying. |
| Diagnose `recommendedRecoveryAction: "backOffWorkload"` | Pause or reduce the workload; do not fight critical system thermals. |
| Diagnose `recommendedRecoveryAction: "inspectPolicy"` | Inspect policy/status before retrying; do not assume cooling is available and do not use the guarded uncooled fallback. |
| Diagnose `recommendedRecoveryAction: "collectHardwareEvidence"` | Collect read-only validation evidence before considering hardware support; do not use the guarded uncooled fallback. |
| Command-error `recommendedRecoveryAction: "repairHelper"` | Recover daemon/transport failures through the Vifty helper repair path or explicit `make repair-helper` source-checkout path. Do not attempt direct SMC writes. |
| `recommendedRecoveryAction: "waitBeforeRetry"` | Do not busy-loop. Show the JSON or wait for `retryAfterSeconds` only when the user approved retrying. |
| `recommendedRecoveryAction: "fixChildCommand"` | Fix the workload command/path or show the launch error. Do not treat this as a helper failure. |

Do not parse human-readable warning text when the JSON fields exist. Pin automation to `state`, `recommendedAgentAction`, `recommendedRecoveryAction`, `recoverySteps`, `safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`, `failedCheckIDs`, `coolingBlockerIDs`, `appPreferences.startupMode`, `checks`, and `agentControl`.
The guarded wrapper may echo the saved `Curve` or `Fixed` startup mode in plain stderr when manual control blocks cooling; treat that as recovery guidance for humans, not as a replacement for the JSON gate.

If a supervised script runs `/Applications/Vifty.app/Contents/MacOS/viftyctl restore-auto --json`, a successful command clears the same local `manualControlActive` marker that `diagnose --json` uses for the restore-first gate. Always re-run `diagnose --json` after restore and require `manualControlActive: false`, `safeToRequestCooling: true`, and `daemonControlPathReady: true` before requesting cooling. Do not loop `restore-auto`; if `manualControlActive` stays true after one restore, inspect `appPreferences.startupMode`, then stop and ask the user to switch Vifty/default startup mode to Auto before another cooling request.

## Conservative Workload Limits

These are starting points, not rights to exceed daemon policy:

| Workload | Duration | Max RPM percent | Example |
| --- | ---: | ---: | --- |
| Swift/package tests | `20m` | `70` | `swift test` |
| Release build | `25m` | `75` | `swift build -c release` |
| Xcode build/test | `30m` | `75` | `xcodebuild build ...`, `xcodebuild test ...` |
| Make build/test/verify | `25m`/`20m`/`30m` | `75`/`70`/`75` | `make build`, `make test`, `make verify` |
| npm/cargo/uv builds | `25m` | `75` | `npm run build`, `cargo build --release`, `uv build` |
| npm/cargo/uv/pytest tests | `20m` | `70` | `npm test`, `cargo test`, `uv run pytest`, `python3 -m pytest` |
| Local model run | `20m` | `75` | local inference or eval command |
| Unknown/custom workload | `10m` | `65` | only with a clear human-readable reason |

When readiness is degraded, reduce one or both numbers. A good degraded default is `10m` and `60`.

## Supervised Run Smoke Evidence

After supported hardware has safe readiness and a human is supervising the
machine, maintainers can capture a standard developer-workload proof from a
clean source checkout with the freshly built app:

```sh
make agent-run-smoke-evidence-current-build
```

This target refuses dirty worktrees, builds `.build/Vifty.app`, records `installSource=local-ad-hoc-build`, the current git ref, and the current 40-character source SHA, and then runs the smoke through
`.build/Vifty.app/Contents/MacOS/viftyctl`. If you are testing an already
installed app instead, point the generic Make target at that installed CLI and
set source provenance when you know it:

```sh
make agent-run-smoke-evidence \
  VIFTYCTL=/Applications/Vifty.app/Contents/MacOS/viftyctl \
  AGENT_RUN_SMOKE_INSTALL_SOURCE=local-ad-hoc-build \
  AGENT_RUN_SMOKE_SOURCE_REF=<ref> \
  AGENT_RUN_SMOKE_SOURCE_SHA=<40-char-sha>
```

This is intentionally different from the read-only support bundle below. It
should be preceded by `make agent-run-smoke-readiness`, which emits
`schemaID: https://vifty.local/schemas/agent-run-smoke-readiness.schema.json`
with `readOnly: true` and `coolingCommandsRun: false` after checking only
`capabilities --json`, `diagnose --json`, and optional daemon hash evidence. The
readiness summary can be saved with
`AGENT_RUN_SMOKE_READINESS_SUMMARY=.build/agent-run-smoke-readiness.json`, and it
copies diagnose `recoverySteps` so blocked supervised-smoke preflights carry the
next safe actions without asking agents to parse prose. Saved readiness
summaries omit the full reason text, record `reasonCharacterCount`, and reduce
private daemon paths to basename-only display values with path privacy labels. The
collector itself first performs read-only capabilities/diagnose checks, but when readiness is
safe it may request one bounded `viftyctl run --json` lease for `/bin/sleep 5`.
The supervised smoke summary uses the same privacy envelope: it omits the full
reason text, records `reasonCharacterCount`, labels daemon path display
values, and records only the child command basename, command kind, argument
count, resolved executable basename, `childArgumentsPrivacy=omitted`, and
`resolvedChildExecutablePathPrivacy=basenameOnly` while preserving daemon identity
through SHA-256 fields. The smoke bundle also writes `privacy-review.tsv`; review
and redact any `redaction-needed` rows before public sharing. The collector supports
exactly one structured cooldown retry if the daemon returns
`PREPARE_RATE_LIMITED`. The collector stops before cooling unless
`capabilities --json` reports schema version `1`, the stable capabilities,
diagnose, command-error, and run schema IDs, daemon-backed policy status,
`policy.enabled: true`, advertised `run` support, wrapper resource discovery, and the safe run lifecycle used by guarded wrappers, including `resolvedChildExecutableReported=true`. Use it for
supported-hardware validation and developer-workload proof, not as the first response to helper-unreachable or blocked readiness states.
If Vifty/manual ownership is still active, the blocked summary's `run.skippedReason` is `manual control active before smoke run`; restore Auto before collecting supervised run evidence.

Checked-in M1 Pro evidence: `docs/validation-reports/2026-06-18-macbookpro18-main-agent-run-smoke/review-result.json` records MacBookPro18,1 local-ad-hoc `agentRunSmokeResult: "passed-auto-restored"` from `2026-06-18-macbookpro18-main-agent-run-smoke/agent-run-smoke-evidence-summary.json`. Treat that as reviewed developer-workload proof for the guarded `viftyctl run` lifecycle only; it does not promote MacBookPro18 to validated hardware support until a reviewed manual smoke report records `manualSmokeTestResult: "passed-auto-restored"`.

## Failure Handling

If readiness is blocked:

```sh
scripts/collect-agent-cooling-evidence.sh \
  --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl
```

If you already captured stderr from a blocked guarded wrapper run, attach it to
the same read-only bundle:

```sh
AGENT_EVIDENCE_GUARDED_RUN_STDERR=/path/to/guarded-run.stderr make agent-cooling-evidence
```

Or call the collector directly:

```sh
scripts/collect-agent-cooling-evidence.sh \
  --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl \
  --guarded-run-stderr-file /path/to/guarded-run.stderr
```

To capture the exact guarded workload path without requesting cooling or
launching the child command, let the collector run the wrapper in
preflight-only mode:

```sh
scripts/collect-agent-cooling-evidence.sh \
  --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl \
  --guarded-run-preflight test 20m 70 "swift test" -- swift test
```

Source checkouts can use the same path through Make:

```sh
AGENT_EVIDENCE_GUARDED_RUN_PREFLIGHT='test 20m 70 "swift test" -- swift test' make agent-cooling-evidence
```

Installed app bundles include this read-only collector at
`/Applications/Vifty.app/Contents/Resources/collect-agent-cooling-evidence.sh`
for users who do not have a source checkout.

This read-only support bundle captures capabilities, diagnose, status, audit,
command exit statuses, launchd/helper install evidence, a manifest,
schema-backed `agent-cooling-evidence-summary.json` with
`schemaID: https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json`,
optional `guarded-run-stderr.txt`, `guarded-run-preflight.status`,
`privacy-review.tsv`, and checksums without requesting cooling, restoring Auto,
calling `ViftyHelper`, using `sudo`, launching the guarded workload, or writing
SMC keys. The summary stores the `viftyctl` basename, `viftyctlPathKind`, and
`viftyctlPathPrivacy: basenameOnly` instead of local executable directory paths.
Check
`privacy-review.tsv` before posting the bundle publicly; redact or share
privately if it reports `redaction-needed`. Maintainers can review a collected
bundle with:

```sh
scripts/review-agent-cooling-evidence.sh \
  --bundle <bundle-dir> \
  --summary <bundle-dir>/agent-cooling-evidence-review.json
```

The reviewer accepts blocked diagnose exit `75` as evidence and rejects privacy
findings, schema drift, manifest/status drift, checksum drift, malformed guarded
wrapper decision markers, guarded-run/diagnose decision drift, missing or
contradictory diagnose decision fields, or any record that cooling commands were
run. Its JSON summary declares
`schemaID: https://vifty.local/schemas/agent-cooling-evidence-review.schema.json`.
The `diagnoseDecision` summary records the diagnose exit status, readiness
state, `recommendedAgentAction`, `recommendedRecoveryAction`, `recoverySteps`,
`safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`,
`failedCheckIDs`, `coolingBlockerIDs`, and `appPreferences.startupMode` so
maintainers can route blocked readiness without parsing human text. A non-empty
`coolingBlockerIDs` list is a hard stop and must not be paired with
`safeToRequestCooling: true` in reviewed evidence. If `manualControlActive` is true and the summary shows a
persisted `Curve` or `Fixed` default, switch Vifty's default startup mode to
`Auto` before another agent-cooling request. Legacy `v1.1.x` bundles that omit
`daemonControlPathReady`, blocker-ID arrays, or `appPreferences` may pass only with a warning;
`daemonControlPathReady` still has to be inferred from structured
readiness/recovery fields. If `guarded-run-stderr.txt` is present, the
`guardedRunDecision` summary records the bracketed wrapper decision, preserves
`decisionReason` and the privacy-conscious workload envelope when current
wrappers provide them, and fails review if that decision drifts from the
captured diagnose evidence. The
`capabilitiesDecision` summary
records the captured capabilities schema version plus stable
`schemaIDs.capabilities`, `schemaIDs.diagnose`, `schemaIDs.commandError`, and
`schemaIDs.run`,
then records whether the bundle advertised `viftyctl run`, force-retry discovery,
safe `runLifecycle`, safe direct prepare/restore lifecycle, wrapper resource discovery, metadata limits,
policy enabled status, policy status availability, daemon status, and the unavailable-exit contract before the report is treated
as agent-safe evidence; absent legacy `metadataLimits` is a warning, not proof
that automation should skip local argument limits. The `appInfo` summary records
the captured app plist command exit status, bundle identifier, short version,
and bundle version, so helper-unreachable reports can be tied to the installed
app version. In helper-unreachable reports, the
reviewer may also list `viftyctl-status` or `viftyctl-audit` under
`acceptedCommandErrors`, but only when blocked `diagnose` recommends
`repairHelper` and those commands emitted structured `HELPER_UNREACHABLE`
command errors with `schemaVersion: 1`,
`schemaID: https://vifty.local/schemas/viftyctl-command-error.schema.json`,
and `safeToProceed: false`.
If the captured `appInfo.shortVersion` is `1.1.0`, that evidence also produces
this stable warning text: known v1.1.0 helper-unreachable issue; use the v1.1.1 source-first hotfix.
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
