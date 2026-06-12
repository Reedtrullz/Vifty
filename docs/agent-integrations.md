# Agent Integration Snippets

Use these snippets when a local coding agent can run shell commands on a supported Mac. They all point at the same safe path: read-only capabilities and readiness first, then `examples/viftyctl/guarded-run.sh`, which delegates to `viftyctl run --json` only when Vifty says cooling is safe to request.

For the short operational runbook and failure-handling table, see [safe-agent-cooling.md](safe-agent-cooling.md).

Do not give agents permission to call `ViftyHelper setFixed`, `ViftyHelper auto`, `sudo`, raw SMC tools, or `viftyctl prepare` unless a human is supervising a workflow that cannot be represented by `viftyctl run`.

## Shared Rule

Paste this into an agent instruction file such as `AGENTS.md`, `CLAUDE.md`, or a Cursor rule:

````md
For long local build/test/model workloads on this Mac, use Vifty only through the safe CLI contract.

Before requesting cooling, run:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
```

If `state` is `blocked` or `safeToRequestCooling` is false, do not request cooling. Show the JSON to the user and stop or run the workload without Vifty cooling, depending on the user's instruction.

Prefer the guarded wrapper:

```sh
examples/viftyctl/guarded-run.sh test 20m 70 "swift test" -- swift test
```

For common local workloads, the shortcut scripts in `examples/viftyctl/` are equivalent safe wrappers around `guarded-run.sh`:

```sh
examples/viftyctl/swift-test.sh
examples/viftyctl/swift-release-build.sh
examples/viftyctl/xcode-build.sh -scheme MyApp -destination 'platform=macOS'
examples/viftyctl/make-test.sh
examples/viftyctl/make-verify.sh
examples/viftyctl/npm-build.sh
examples/viftyctl/npm-test.sh
examples/viftyctl/cargo-build.sh --release
examples/viftyctl/cargo-test.sh
examples/viftyctl/pytest.sh
```

Use shorter durations and lower RPM percentages for degraded readiness. Never call raw SMC commands, `sudo ViftyHelper`, or arbitrary fan RPM writes. If Vifty reports `restoreAutoBeforeRequestingCooling`, ask the user before restoring Auto or retrying.

Leave `VIFTY_GUARDED_RUN_FORCE_RETRY` unset by default. Only set it to `1` for a supervised human workflow where the user has approved waiting for `retryAfterSeconds` and retrying a rate-limited prepare once. The wrapper still checks `supportsForceRetry` before passing `--force`.

The guarded wrapper rejects malformed duration/RPM/reason arguments before contacting Vifty, checks `viftyctl capabilities --json` before readiness, and refuses cooling if the CLI exits nonzero for anything other than the advertised unavailable exit code, if the CLI no longer advertises `run`, if the requested workload is not advertised, or if the advertised `runLifecycle` contract no longer guarantees child-command preflight, handled signal forwarding, Auto restore, structured pre-child failures, and launch-failure cleanup reporting.
````

## Codex

For a repository-level `AGENTS.md`, add the shared rule and then use workload-specific commands:

```sh
examples/viftyctl/swift-test.sh
examples/viftyctl/swift-release-build.sh
examples/viftyctl/xcode-build.sh -scheme MyApp -destination 'platform=macOS'
examples/viftyctl/make-verify.sh
```

If the repository is not Vifty itself, copy `examples/viftyctl/guarded-run.sh` into that project or call it from a known path. Set `VIFTYCTL` when testing a development bundle:

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

Do not request Vifty cooling when readiness is blocked, when `safeToRequestCooling` is false, or when the machine is not a supported Apple Silicon MacBook Pro.
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

Use this pattern for developer machines only. Remote CI machines, unsupported Macs, and non-macOS runners should run the workload normally without Vifty fan control. Do not add a fallback after `guarded-run.sh` that catches its nonzero exit and reruns the same child command, unless the user explicitly asked to continue without Vifty cooling after seeing the structured failure.

## Failure Handling

- `blocked` readiness: do not request cooling; show the JSON.
- `restoreAutoBeforeRequestingCooling`: ask the user whether to restore Auto before retrying.
- `requestCoolingWithCaution`: use a shorter duration and lower RPM percentage.
- `recommendedRecoveryAction: "repairHelper"`: ask the user to open Vifty and use Repair/Reinstall Helper or approve Login Items.
- `recommendedRecoveryAction: "fixChildCommand"`: fix the workload command/path or show the launch error; do not repair Vifty helper state.
- `recommendedRecoveryAction: "waitBeforeRetry"`: wait for `retryAfterSeconds`; do not busy-loop retries.
- `recommendedRecoveryAction: "restoreAutoBeforeRetry"`: ask the user whether to restore Auto before requesting another lease.
- `recommendedRecoveryAction: "fixArguments"`: fix the wrapper arguments before invoking Vifty again.
- `recommendedRecoveryAction: "runDiagnose"`: show `viftyctl diagnose --json`, and do not start cooling while readiness is unsafe.
- Guarded wrapper force retry: leave `VIFTY_GUARDED_RUN_FORCE_RETRY` unset unless a human explicitly approved one retry.
- Child exits nonzero: preserve the child failure. Vifty should still attempt Auto restore.
- Restore failure after a successful child: treat the wrapper exit as a Vifty safety failure and show stderr plus `viftyctl status --json` and `viftyctl audit --limit 20 --json`.
