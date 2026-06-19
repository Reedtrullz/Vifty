# Vifty Workload Wrappers

These scripts are small convenience wrappers around `guarded-run.sh`. They keep
common developer workloads on Vifty's safe path:

1. preflight that the child command is a regular executable path or resolves to one on `PATH`;
2. reject malformed wrapper arguments before contacting Vifty, including empty or blank reasons, non-positive durations, unsupported duration suffixes, and RPM percentages outside `1...100`;
3. read-only `viftyctl capabilities --json`, require schema version `1`, the stable capabilities, diagnose, command-error, and run schema IDs, require any nonzero exit to match the advertised unavailable exit code, require advertised `run` command support, require the requested workload name, require the safe `runLifecycle` contract used by `viftyctl run`, discover whether completed run reports include `resolvedChildExecutable`, require `wrapperResources` for machine-readable source/app-bundle wrapper discovery, require `policyStatusAvailable: true` before trusting policy duration/RPM limits, require `policy.enabled: true` before requesting cooling, and require `metadataLimits`, then reject durations or RPM percentages outside the advertised policy range and reasons longer than the advertised maximum before readiness or cooling;
4. read-only `viftyctl diagnose --json`, require diagnose readiness schema version `1`, and require recognized command-error schema identity when diagnose exits nonzero with a command-error payload;
5. require `recommendedAgentAction`, `recommendedRecoveryAction`, `safeToRequestCooling`, `daemonControlPathReady`, and `manualControlActive` so wrappers do not infer safety from prose or fallback telemetry;
6. fail closed when readiness is blocked, `safeToRequestCooling` is false, `daemonControlPathReady` is false, or `manualControlActive` is true, and print recovery guidance for helper repair, Auto restore, workload backoff, policy inspection, or hardware-evidence follow-up. Do not loop `restore-auto`; if `manualControlActive` stays true after one restore, inspect `appPreferences.startupMode`, then stop and ask the user to switch Vifty/default startup mode to Auto. When diagnose reports a persisted `Curve` or `Fixed` default, the wrapper also prints that saved default in plain stderr before the JSON;
7. delegate to `viftyctl run --json` with one bounded lease;
8. let `viftyctl run` revalidate the child command and restore Auto afterward.

When the wrapper prints captured JSON on a failure path, it wraps capabilities
evidence with `guarded-run: BEGIN_VIFTY_CAPABILITIES_JSON` /
`guarded-run: END_VIFTY_CAPABILITIES_JSON` and diagnose evidence with
`guarded-run: BEGIN_VIFTY_DIAGNOSE_JSON` /
`guarded-run: END_VIFTY_DIAGNOSE_JSON`. Extract the exact JSON between those
markers instead of scraping human recovery text.

If a capabilities payload does not advertise schema version `1`, the stable
capabilities, diagnose, command-error, and run schema IDs, `runLifecycle`,
`wrapperResources`, `policyStatusAvailable: true`, `policy.enabled: true`,
policy duration/RPM limits, or `metadataLimits`, treat those guarantees as
unavailable and refuse cooling.

`wrapperResources` intentionally uses app-bundle/source-checkout relative paths
and script names. Agents can combine those values with a known installed app or
checkout location without copying user-specific absolute paths into support
evidence.

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

The wrappers do not pass `--force` by default. For a supervised human workflow
that should wait once for Vifty's `retryAfterSeconds` value and retry a
rate-limited prepare, set `VIFTY_GUARDED_RUN_FORCE_RETRY=1`. The guarded
wrapper still checks `supportsForceRetry` before passing `--force`. Leave it
unset for local agents unless the user explicitly approved retrying. Do not
combine this with `VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1`; the wrapper refuses
that ambiguous mix.

When the user explicitly approves running the workload without Vifty cooling
after seeing the structured readiness block, set
`VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=1`. The wrapper still runs read-only
capabilities and diagnose checks, still refuses to request cooling, prints the
diagnose JSON, and then execs the child directly. It will not use this fallback
when Vifty recommends `repairHelper`, `backOffWorkload`, or
`restoreAutoBeforeRetry`, `inspectPolicy`, or `collectHardwareEvidence`, when
`manualControlActive` is true, when `daemonControlPathReady` is false, or when
`VIFTY_GUARDED_RUN_FORCE_RETRY=1` is also set.
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
| `cargo-build.sh [cargo-build-args...]` | `guarded-run.sh build 25m 75 "cargo build" -- cargo build ...` |
| `cargo-test.sh [cargo-test-args...]` | `guarded-run.sh test 20m 70 "cargo test" -- cargo test ...` |
| `pytest.sh [pytest-args...]` | `guarded-run.sh test 20m 70 "pytest" -- python3 -m pytest ...` |
| `local-model.sh -- <command> [args...]` | `guarded-run.sh localModel 30m 75 "local model run" -- ...` |
| `custom-workload.sh <duration> <max-rpm-percent> <reason> -- <command> [args...]` | `guarded-run.sh custom ...` |

Do not edit these wrappers to call `sudo`, `ViftyHelper`, raw SMC tools, or
fixed RPM commands. For unusual workflows, prefer `custom-workload.sh` or call
`guarded-run.sh` directly with conservative limits.
