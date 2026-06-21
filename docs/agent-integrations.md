# Agent Integration Snippets

Use these snippets when a local coding agent can run shell commands on a supported Mac. They all point at the same safe path: read-only capabilities and readiness first, then `examples/viftyctl/guarded-run.sh` or the installed app's bundled wrapper, which delegates to `viftyctl run --json` only when Vifty says cooling is safe to request.

For the short operational runbook and failure-handling table, see [safe-agent-cooling.md](safe-agent-cooling.md).

Do not give agents permission to call `ViftyHelper setFixed`, `ViftyHelper auto`, `sudo`, raw SMC tools, or `viftyctl prepare` unless a human is supervising a workflow that cannot be represented by `viftyctl run`.

If the Vifty app is installed, prefer the bundled wrappers at
`/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/`. Source
checkouts can use the same scripts from `examples/viftyctl/`.

Agents that want machine-readable discovery should read
`viftyctl capabilities --json` first and use `wrapperResources.bundleDirectory`,
`wrapperResources.sourceDirectory`, `wrapperResources.guardedRunScript`, and
`wrapperResources.workloadScripts` instead of hardcoding wrapper script names.
Those paths are intentionally relative to the app bundle or source checkout so
support evidence does not expose user-specific absolute paths.

## Shared Rule

Paste this into an agent instruction file such as `AGENTS.md`, `CLAUDE.md`, or a Cursor rule:

````md
For long local build/test/model workloads on this Mac, use Vifty only through the safe CLI contract.

Before requesting cooling, run:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
```

If `state` is `blocked`, `safeToRequestCooling` is false, `daemonControlPathReady` is false, `manualControlActive` is true, or `coolingBlockerIDs` is non-empty, do not request cooling. Show the JSON to the user and stop. If the user explicitly approves running the child command without Vifty cooling after seeing that JSON, use `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1` with the guarded wrapper so Vifty can still enforce recovery-action, daemon-control, manual-ownership, blocker-ID, and force-retry blocks; do not catch a guarded-run failure and rerun the child yourself.

Prefer the guarded wrapper:

```sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/guarded-run.sh test 20m 70 "swift test" -- swift test
```

For common local workloads, the shortcut scripts in the installed
`viftyctl-wrappers/` directory or source-tree `examples/viftyctl/` directory are
equivalent safe wrappers around `guarded-run.sh`:

```sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/swift-test.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/swift-release-build.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/xcode-build.sh -scheme MyApp -destination 'platform=macOS'
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/xcode-test.sh -scheme MyApp -destination 'platform=macOS'
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/make-build.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/make-test.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/make-verify.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/npm-build.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/npm-test.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/cargo-build.sh --release
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/cargo-test.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/pytest.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/local-model.sh -- ./run-local-model.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/custom-workload.sh 10m 65 "project smoke test" -- ./scripts/smoke-test.sh
```

In a source checkout, the equivalent wrapper paths are:

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
examples/viftyctl/cargo-build.sh --release
examples/viftyctl/cargo-test.sh
examples/viftyctl/pytest.sh
examples/viftyctl/local-model.sh -- ./run-local-model.sh
examples/viftyctl/custom-workload.sh 10m 65 "project smoke test" -- ./scripts/smoke-test.sh
```

Use shorter durations and lower RPM percentages for degraded readiness. Never call raw SMC commands, `sudo ViftyHelper`, or arbitrary fan RPM writes. If Vifty reports `restoreAutoBeforeRequestingCooling`, ask the user before restoring Auto or retrying.

Leave `VIFTY_GUARDED_RUN_FORCE_RETRY` unset by default. Only set it to `1` for a supervised human workflow where the user has approved waiting for `retryAfterSeconds` and retrying a rate-limited prepare once. The wrapper still checks `supportsForceRetry` before passing `--force`, and refuses to combine force retry with `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED`.

Leave `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED` unset by default. Only set it to `1`
after the user explicitly approved running the child command without Vifty
cooling after seeing the structured readiness block. The wrapper will still run
read-only checks, print the diagnose JSON, refuse to request cooling, avoid the uncooled fallback when Vifty recommends helper repair, backing off, restoring Auto first, policy inspection, hardware evidence collection, or when the daemon control path is unavailable, and reject attempts to combine uncooled fallback with force retry.

The guarded wrapper rejects malformed duration/RPM/reason arguments before contacting Vifty, checks `viftyctl capabilities --json` before readiness, and refuses cooling if the CLI exits nonzero for anything other than the advertised unavailable exit code, if the capabilities payload does not declare schema version `1` and the stable capabilities, diagnose, command-error, and run schema IDs, if the CLI no longer advertises `run`, if the requested workload is not advertised, if `wrapperResources` discovery metadata is missing or stale, if `policyStatusAvailable` is missing or not true, if `policy.enabled` is absent or false, if advertised policy duration/RPM limits or `metadataLimits` are missing, if the requested duration/RPM/reason exceeds those advertised limits, if `diagnose --json` readiness does not declare schema version `1`, if a nonzero diagnose command-error payload does not match the advertised command-error schema identity, or if the advertised `runLifecycle` contract no longer guarantees child-command preflight, handled signal forwarding, Auto restore, structured pre-child failures, launch-failure cleanup reporting, and `resolvedChildExecutableReported=true`. Completed `viftyctl run --json` payloads identify the absolute child executable that was resolved before cooling.

On guarded-run failure paths, extract captured JSON from stderr only between
the stable markers `guarded-run: BEGIN_VIFTY_CAPABILITIES_JSON` /
`guarded-run: END_VIFTY_CAPABILITIES_JSON` or
`guarded-run: BEGIN_VIFTY_DIAGNOSE_JSON` /
`guarded-run: END_VIFTY_DIAGNOSE_JSON` or
`guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON` /
`guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON`; do not parse surrounding
human recovery text. The wrapper decision payload declares `schemaID:
https://vifty.local/schemas/guarded-run-decision.schema.json` and tells agents
whether cooling was requested, whether an uncooled fallback was requested or
allowed, which stable `decisionReason` category applies, and which readiness fields blocked the safe path.

## Codex

For a repository-level `AGENTS.md`, add the shared rule and then use workload-specific commands:

```sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/swift-test.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/swift-release-build.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/xcode-build.sh -scheme MyApp -destination 'platform=macOS'
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/make-build.sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/make-verify.sh
```

If the repository is not Vifty itself, call the installed wrapper path above,
copy `examples/viftyctl/guarded-run.sh` into that project, or call the source
wrapper from a known checkout. Set `VIFTYCTL` when testing a development bundle:

```sh
VIFTYCTL=.build/Vifty.app/Contents/MacOS/viftyctl \
  examples/viftyctl/swift-test.sh
```

## Claude Code

For `CLAUDE.md`, use the shared rule and prefer explicit one-shot commands:

```sh
examples/viftyctl/pytest.sh
examples/viftyctl/xcode-test.sh -scheme MyApp -destination 'platform=macOS'
```

If Claude Code is running outside an interactive terminal, avoid direct `prepare` / `restore-auto`. The guarded wrapper keeps lifecycle and Auto restore tied to one child process.

## Cursor

For a Cursor project rule, use the shared rule and keep the command examples narrow:

````md
When running long local tests or builds, prefer:

```sh
examples/viftyctl/npm-test.sh
examples/viftyctl/npm-build.sh
examples/viftyctl/cargo-test.sh
examples/viftyctl/cargo-build.sh --release
examples/viftyctl/make-test.sh
```

Do not request Vifty cooling when readiness is blocked, when `safeToRequestCooling` is false, when `daemonControlPathReady` is false, when `manualControlActive` is true, when `coolingBlockerIDs` is non-empty, or when the machine is not a supported Apple Silicon MacBook Pro.
````

## Shell Runners

For a local script, keep Vifty optional without masking Vifty failures. The fallback below is only for projects or machines where the guarded wrapper is intentionally absent. If the guarded wrapper exists and Vifty blocks, errors, or fails to restore Auto, the script exits with that failure instead of rerunning the workload without cooling:

```sh
#!/bin/sh
set -eu

if [ -x ./examples/viftyctl/guarded-run.sh ]; then
  exec ./examples/viftyctl/guarded-run.sh test 20m 70 "project test" -- "$@"
fi

exec "$@"
```

Use this pattern for developer machines only. Remote CI machines, unsupported Macs, and non-macOS runners should run the workload normally without Vifty fan control. Do not add a fallback after `guarded-run.sh` that catches its nonzero exit and reruns the same child command; use `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1` only when the user explicitly asked to continue without Vifty cooling after seeing the structured failure.

## Failure Handling

- `blocked` readiness: do not request cooling; show the JSON.
- `restoreAutoBeforeRequestingCooling`: ask the user whether to restore Auto once before retrying, then re-run diagnose.
- `requestCoolingWithCaution`: use a shorter duration and lower RPM percentage.
- Diagnose `recommendedRecoveryAction: "repairHelper"`: ask the user to open Vifty and use Repair/Reinstall Helper or approve Login Items.
- Diagnose `recommendedRecoveryAction: "backOffWorkload"`: pause or reduce the workload; do not fight critical system thermals.
- Diagnose `recommendedRecoveryAction: "inspectPolicy"`: inspect local policy/status before retrying; do not use the guarded uncooled fallback.
- Diagnose `recommendedRecoveryAction: "collectHardwareEvidence"`: collect read-only validation evidence before considering hardware support; do not use the guarded uncooled fallback.
- Command-error `recommendedRecoveryAction: "repairHelper"`: recover daemon/transport failures through the Vifty helper repair path; do not attempt direct SMC writes.
- `recommendedRecoveryAction: "fixChildCommand"`: fix the workload command/path or show the launch error; do not repair Vifty helper state.
- `recommendedRecoveryAction: "waitBeforeRetry"`: wait for `retryAfterSeconds`; do not busy-loop retries.
- `recommendedRecoveryAction: "restoreAutoBeforeRetry"`: ask the user whether to restore Auto once before requesting another lease, then re-run diagnose. Do not loop `restore-auto`; if `manualControlActive` stays true after one restore, inspect `appPreferences.startupMode`, then stop and ask the user to switch Vifty/default startup mode to Auto.
- `recommendedRecoveryAction: "fixArguments"`: fix the wrapper arguments before invoking Vifty again.
- `recommendedRecoveryAction: "runDiagnose"`: show `viftyctl diagnose --json`, and do not start cooling while readiness is unsafe.
- Guarded wrapper force retry: leave `VIFTY_GUARDED_RUN_FORCE_RETRY` unset unless a human explicitly approved one retry, and do not combine it with uncooled fallback.
- Guarded wrapper uncooled fallback: leave `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED` unset unless the user explicitly approved running the child without Vifty cooling after seeing the structured readiness block; avoid the uncooled fallback when Vifty recommends helper repair, backing off, restoring Auto first, policy inspection, or hardware evidence collection; when the daemon control path is unavailable; or when manual control is active. The wrapper still refuses helper-repair, restore-first, manual-control-active, backoff, policy-inspection, hardware-evidence, daemon-control-unavailable states, and force-retry combinations.
- Child exits nonzero: preserve the child failure. Vifty should still attempt Auto restore.
- Restore failure after a successful child: treat the wrapper exit as a Vifty safety failure and show stderr plus `viftyctl status --json` and `viftyctl audit --limit 20 --json`.
