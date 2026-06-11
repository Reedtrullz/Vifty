# Vifty Workload Wrappers

These scripts are small convenience wrappers around `guarded-run.sh`. They keep
common developer workloads on Vifty's safe path:

1. read-only `viftyctl diagnose --json`;
2. fail closed when readiness is blocked or `safeToRequestCooling` is false;
3. delegate to `viftyctl run --json` with one bounded lease;
4. let `viftyctl run` validate the child command and restore Auto afterward.

Set `VIFTYCTL` to test against a development app bundle:

```sh
VIFTYCTL=.build/Vifty.app/Contents/MacOS/viftyctl \
  examples/viftyctl/swift-test.sh --filter ViftyCoreTests
```

## Scripts

| Script | Delegates To |
| --- | --- |
| `swift-test.sh [swift-test-args...]` | `guarded-run.sh test 20m 70 "swift test" -- swift test ...` |
| `swift-release-build.sh [swift-build-args...]` | `guarded-run.sh build 25m 75 "swift release build" -- swift build -c release ...` |
| `xcode-test.sh [xcodebuild-args...]` | `guarded-run.sh test 30m 75 "xcodebuild test" -- xcodebuild test ...` |
| `npm-test.sh [npm-test-args...]` | `guarded-run.sh test 20m 70 "npm test" -- npm test ...` |
| `cargo-test.sh [cargo-test-args...]` | `guarded-run.sh test 20m 70 "cargo test" -- cargo test ...` |
| `pytest.sh [pytest-args...]` | `guarded-run.sh test 20m 70 "pytest" -- python3 -m pytest ...` |
| `local-model.sh -- <command> [args...]` | `guarded-run.sh localModel 30m 75 "local model run" -- ...` |
| `custom-workload.sh <duration> <max-rpm-percent> <reason> -- <command> [args...]` | `guarded-run.sh custom ...` |

Do not edit these wrappers to call `sudo`, `ViftyHelper`, raw SMC tools, or
fixed RPM commands. For unusual workflows, prefer `custom-workload.sh` or call
`guarded-run.sh` directly with conservative limits.
