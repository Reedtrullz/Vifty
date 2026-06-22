# Vifty Workload Wrappers

These scripts are small convenience wrappers around `guarded-run.sh`. They keep
common developer workloads on Vifty's safe path:

1. preflight that the child command is a regular executable path or resolves to one on `PATH`;
2. reject malformed wrapper arguments before contacting Vifty, including empty or blank reasons, non-positive durations, unsupported duration suffixes, and RPM percentages outside `1...100`;
3. read-only `viftyctl capabilities --json`, require schema version `1`, the stable capabilities, diagnose, command-error, and run schema IDs, require any nonzero exit to match the advertised unavailable exit code, require advertised `run` command support, require the requested workload name, require the safe `runLifecycle` contract used by `viftyctl run`, including `resolvedChildExecutableReported=true` so completed run reports identify the cooled executable, include `childTerminationReason` plus inferred signal fields for shell-style signal exit codes, and include `resolvedChildExecutableSHA256Status` plus `resolvedChildExecutableSHA256` when the executable bytes are readable, require `wrapperResources` for machine-readable source/app-bundle wrapper discovery, require audited `workloadTemplates` for every advertised shortcut wrapper, require `policyStatusAvailable: true` before trusting policy duration/RPM limits, require `policy.enabled: true` before requesting cooling, and require `metadataLimits`, then reject durations or RPM percentages outside the advertised policy range and reasons longer than the advertised maximum before readiness or cooling;
4. read-only `viftyctl diagnose --json`, require diagnose readiness schema version `1`, and require recognized command-error schema identity when diagnose exits nonzero with a command-error payload;
5. require `recommendedAgentAction`, `recommendedRecoveryAction`, `safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`, `failedCheckIDs`, and `coolingBlockerIDs` so wrappers do not infer safety from prose or fallback telemetry;
6. fail closed when readiness is blocked, `safeToRequestCooling` is false, `daemonControlPathReady` is false, `manualControlActive` is true, or `coolingBlockerIDs` is non-empty, and print recovery guidance for helper repair, Auto restore, workload backoff, policy inspection, or hardware-evidence follow-up. Do not loop `restore-auto`; if `manualControlActive` stays true after one restore, inspect `appPreferences.startupMode`, then stop and ask the user to switch Vifty/default startup mode to Auto. When diagnose reports a persisted `Curve` or `Fixed` default, the wrapper also prints that saved default in plain stderr before the JSON;
7. in `--preflight-only` / `VIFTY_GUARDED_RUN_PREFLIGHT_ONLY=1` mode, exit after the read-only gates with decision JSON and without requesting cooling or launching the child;
8. delegate to `viftyctl run --json` with one bounded lease;
9. let `viftyctl run` revalidate the child command and restore Auto afterward.

When the wrapper prints captured JSON on a failure or preflight-only path, it
wraps capabilities evidence with `guarded-run: BEGIN_VIFTY_CAPABILITIES_JSON` /
`guarded-run: END_VIFTY_CAPABILITIES_JSON` and diagnose evidence with
`guarded-run: BEGIN_VIFTY_DIAGNOSE_JSON` /
`guarded-run: END_VIFTY_DIAGNOSE_JSON`. It also wraps wrapper-level no-cooling
or preflight-only decisions with `guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON` /
`guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON`; those payloads use
`schemaID: https://vifty.local/schemas/guarded-run-decision.schema.json` and
summarize `coolingRequested`, `uncooledFallbackRequested`,
`uncooledFallbackAllowed`, `decisionReason`, `recommendedAgentAction`,
`recommendedRecoveryAction`, `safeToRequestCooling`, `daemonControlPathReady`,
`manualControlActive`, `failedCheckIDs`, and `coolingBlockerIDs`. Extract the
exact JSON between those markers instead of scraping human recovery text.

If a capabilities payload does not advertise schema version `1`, the stable
capabilities, diagnose, command-error, and run schema IDs, `runLifecycle`,
`wrapperResources`, audited `workloadTemplates`, `policyStatusAvailable: true`,
`policy.enabled: true`, policy duration/RPM limits, or `metadataLimits`, treat
those guarantees as unavailable and refuse cooling.

`wrapperResources` intentionally uses app-bundle/source-checkout relative paths
and script names. Agents can combine those values with a known installed app or
checkout location without copying user-specific absolute paths into support
evidence.

`workloadTemplates` must also advertise every shortcut wrapper by
`shortcutScript`, so guarded runs cannot proceed against older or drifted
capabilities payloads that list scripts without their audited workload defaults.

Agents should also read `metadataLimits` from capabilities before generating
custom direct-prepare reasons or idempotency keys; legacy payloads without those
limits should be treated as missing an agent-safety guarantee.

The app bundle installs this directory to `Contents/Resources/viftyctl-wrappers/`.
Installed users can run the same audited shortcuts directly, for example:

```sh
/Applications/Vifty.app/Contents/Resources/viftyctl-wrappers/swift-test.sh
```

For exceptional supervised multi-step workflows that use direct `prepare` and
`restore-auto` instead of these wrappers, inspect `directControlLifecycle` first.
It should advertise that prepare uses idempotency keys, `restore-auto` rejects
`--idempotency-key`, restore is not key-scoped, and `viftyctl run` remains the
preferred path for single child workloads.

Set `VIFTYCTL` to test against a development app bundle:

```sh
VIFTYCTL=.build/Vifty.app/Contents/MacOS/viftyctl \
  examples/viftyctl/swift-test.sh --filter ViftyCoreTests
```

Use `--preflight-only` or `VIFTY_GUARDED_RUN_PREFLIGHT_ONLY=1` when a local
agent only needs to know whether a workload can safely request Vifty cooling.
The wrapper validates the same child command, capabilities, policy, metadata,
and diagnose gates, then exits before `viftyctl run` and before launching the
child:

```sh
examples/viftyctl/guarded-run.sh --preflight-only test 20m 70 "swift test" -- swift test
```

Successful preflight-only decision JSON uses
`decisionReason: "preflightReady"`, `coolingRequested: false`, and
`exitCode: 0`.

The wrappers do not pass `--force` by default. For a supervised human workflow
that should wait once for Vifty's `retryAfterSeconds` value and retry a
rate-limited prepare, set `VIFTY_GUARDED_RUN_FORCE_RETRY=1`. The guarded
wrapper still checks `supportsForceRetry` before passing `--force`. Leave it
unset for local agents unless the user explicitly approved retrying. Do not
combine this with `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1`; the wrapper refuses
that ambiguous mix, and it also refuses force retry with
`VIFTY_GUARDED_RUN_PREFLIGHT_ONLY=1`.

When the user explicitly approves running the workload without Vifty cooling
after seeing the structured readiness block, set
`VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1`. The wrapper still runs read-only
capabilities and diagnose checks, still refuses to request cooling, prints the
diagnose JSON, and then execs the child directly. It will not use this fallback
when Vifty recommends `repairHelper`, `backOffWorkload`, or
`restoreAutoBeforeRetry`, `inspectPolicy`, or `collectHardwareEvidence`, when
`manualControlActive` is true, when `daemonControlPathReady` is false, or when
`VIFTY_GUARDED_RUN_FORCE_RETRY=1` is also set.
It also refuses to combine uncooled fallback with
`VIFTY_GUARDED_RUN_PREFLIGHT_ONLY=1`.
Do not catch guarded-run failures and rerun the child command yourself.

## Scripts

| Script | Delegates To |
| --- | --- |
| `swift-test.sh [swift-test-args...]` | `guarded-run.sh test 20m 70 "swift test" -- swift test ...` |
| `swift-release-build.sh [swift-build-args...]` | `guarded-run.sh build 25m 75 "swift release build" -- swift build -c release ...` |
| `xcode-build.sh [xcodebuild-args...]` | `guarded-run.sh build 30m 75 "xcodebuild build" -- xcodebuild build ...` |
| `xcode-test.sh [xcodebuild-args...]` | `guarded-run.sh test 30m 75 "xcodebuild test" -- xcodebuild test ...` |
| `make-build.sh [make-args...]` | `guarded-run.sh build 25m 75 "make build" -- make build ...` |
| `make-test.sh [make-args...]` | `guarded-run.sh test 20m 70 "make test" -- make test ...` |
| `make-verify.sh [make-args...]` | `guarded-run.sh test 30m 75 "make verify" -- make verify ...` |
| `npm-build.sh [npm-build-args...]` | `guarded-run.sh build 25m 75 "npm run build" -- npm run build ...` |
| `npm-test.sh [npm-test-args...]` | `guarded-run.sh test 20m 70 "npm test" -- npm test ...` |
| `pnpm-build.sh [pnpm-build-args...]` | `guarded-run.sh build 25m 75 "pnpm build" -- pnpm build ...` |
| `pnpm-test.sh [pnpm-test-args...]` | `guarded-run.sh test 20m 70 "pnpm test" -- pnpm test ...` |
| `bun-build.sh [bun-build-args...]` | `guarded-run.sh build 25m 75 "bun run build" -- bun run build ...` |
| `bun-test.sh [bun-test-args...]` | `guarded-run.sh test 20m 70 "bun test" -- bun test ...` |
| `go-build.sh [go-build-args...]` | `guarded-run.sh build 25m 75 "go build" -- go build ...` |
| `go-test.sh [go-test-args...]` | `guarded-run.sh test 20m 70 "go test" -- go test ...` |
| `cargo-build.sh [cargo-build-args...]` | `guarded-run.sh build 25m 75 "cargo build" -- cargo build ...` |
| `cargo-test.sh [cargo-test-args...]` | `guarded-run.sh test 20m 70 "cargo test" -- cargo test ...` |
| `uv-build.sh [uv-build-args...]` | `guarded-run.sh build 25m 75 "uv build" -- uv build ...` |
| `uv-test.sh [pytest-args...]` | `guarded-run.sh test 20m 70 "uv pytest" -- uv run pytest ...` |
| `pytest.sh [pytest-args...]` | `guarded-run.sh test 20m 70 "pytest" -- python3 -m pytest ...` |
| `local-model.sh -- <command> [args...]` | `guarded-run.sh localModel 30m 75 "local model run" -- ...` |
| `custom-workload.sh <duration> <max-rpm-percent> <reason> -- <command> [args...]` | `guarded-run.sh custom ...` |

Do not edit these wrappers to call `sudo`, `ViftyHelper`, raw SMC tools, or
fixed RPM commands. For unusual workflows, prefer `custom-workload.sh` or call
`guarded-run.sh` directly with conservative limits.
