# Agent Integration Snippets

Use these snippets when a local coding agent can run shell commands on a supported Mac. They all point at the same safe path: read-only readiness first, then `examples/viftyctl/guarded-run.sh`, which delegates to `viftyctl run --json` only when Vifty says cooling is safe to request.

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

Use shorter durations and lower RPM percentages for degraded readiness. Never call raw SMC commands, `sudo ViftyHelper`, or arbitrary fan RPM writes. If Vifty reports `restoreAutoBeforeRequestingCooling`, ask the user before restoring Auto or retrying.
````

## Codex

For a repository-level `AGENTS.md`, add the shared rule and then use workload-specific commands:

```sh
examples/viftyctl/guarded-run.sh test 20m 70 "swift test" -- swift test
examples/viftyctl/guarded-run.sh build 25m 75 "release build" -- swift build -c release
```

If the repository is not Vifty itself, copy `examples/viftyctl/guarded-run.sh` into that project or call it from a known path. Set `VIFTYCTL` when testing a development bundle:

```sh
VIFTYCTL=.build/Vifty.app/Contents/MacOS/viftyctl \
  examples/viftyctl/guarded-run.sh test 20m 70 "swift test" -- swift test
```

## Claude Code

For `CLAUDE.md`, use the shared rule and prefer explicit one-shot commands:

```sh
examples/viftyctl/guarded-run.sh test 20m 70 "pytest" -- python3 -m pytest
examples/viftyctl/guarded-run.sh build 25m 75 "xcodebuild" -- \
  xcodebuild test -scheme MyApp -destination 'platform=macOS'
```

If Claude Code is running outside an interactive terminal, avoid direct `prepare` / `restore-auto`. The guarded wrapper keeps lifecycle and Auto restore tied to one child process.

## Cursor

For a Cursor project rule, use the shared rule and keep the command examples narrow:

````md
When running long local tests or builds, prefer:

```sh
examples/viftyctl/guarded-run.sh test 20m 70 "npm test" -- npm test
examples/viftyctl/guarded-run.sh test 20m 70 "cargo test" -- cargo test
```

Do not request Vifty cooling when readiness is blocked, when `safeToRequestCooling` is false, or when the machine is not a supported Apple Silicon MacBook Pro.
````

## Shell Runners

For a local script, keep Vifty optional and fail closed on Vifty problems:

```sh
#!/bin/sh
set -eu

if [ -x ./examples/viftyctl/guarded-run.sh ]; then
  exec ./examples/viftyctl/guarded-run.sh test 20m 70 "project test" -- "$@"
fi

exec "$@"
```

Use this pattern for developer machines only. Remote CI machines, unsupported Macs, and non-macOS runners should run the workload normally without Vifty fan control.

## Failure Handling

- `blocked` readiness: do not request cooling; show the JSON.
- `restoreAutoBeforeRequestingCooling`: ask the user whether to restore Auto before retrying.
- `requestCoolingWithCaution`: use a shorter duration and lower RPM percentage.
- `HELPER_UNREACHABLE`: ask the user to open Vifty and reinstall or approve the helper.
- `PREPARE_RATE_LIMITED`: wait for `retryAfterSeconds`; do not busy-loop retries.
- Child exits nonzero: preserve the child failure. Vifty should still attempt Auto restore.
- Restore failure after a successful child: treat the wrapper exit as a Vifty safety failure and show stderr plus `viftyctl status --json` and `viftyctl audit --limit 20 --json`.
