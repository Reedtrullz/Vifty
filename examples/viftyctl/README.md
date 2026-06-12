# Vifty Workload Wrappers

These scripts are small convenience wrappers around `guarded-run.sh`. They keep
common developer workloads on Vifty's safe path:

1. preflight that the child command is a regular executable path or resolves to one on `PATH`;
2. read-only `viftyctl capabilities --json` and require the safe `runLifecycle` contract;
3. read-only `viftyctl diagnose --json`;
4. fail closed when readiness is blocked or `safeToRequestCooling` is false;
5. delegate to `viftyctl run --json` with one bounded lease;
6. let `viftyctl run` revalidate the child command and restore Auto afterward.

If a capabilities payload does not advertise `runLifecycle`, treat those
guarantees as unavailable and refuse cooling.

Set `VIFTYCTL` to test against a development app bundle:

```sh
VIFTYCTL=.build/Vifty.app/Contents/MacOS/viftyctl \
  examples/viftyctl/swift-test.sh --filter ViftyCoreTests
```

The wrappers do not pass `--force` by default. For a supervised human workflow
that should wait once for Vifty's `retryAfterSeconds` value and retry a
rate-limited prepare, set `VIFTY_GUARDED_RUN_FORCE_RETRY=1`. The guarded
wrapper still checks `supportsForceRetry` before passing `--force`. Leave it
unset for local agents unless the user explicitly approved retrying.

## Scripts

| Script | Delegates To |
| --- | --- |
| `swift-test.sh [swift-test-args...]` | `guarded-run.sh test 20m 70 "swift test" -- swift test ...` |
| `swift-release-build.sh [swift-build-args...]` | `guarded-run.sh build 25m 75 "swift release build" -- swift build -c release ...` |
| `xcode-build.sh [xcodebuild-args...]` | `guarded-run.sh build 30m 75 "xcodebuild build" -- xcodebuild build ...` |
| `xcode-test.sh [xcodebuild-args...]` | `guarded-run.sh test 30m 75 "xcodebuild test" -- xcodebuild test ...` |
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
