# viftyctl JSON Examples

These examples are canonical sample payloads for local agents and shell automation. They are not captured from a live machine; they are stable fixtures that document the JSON shape emitted by `viftyctl`.

The XCTest suite decodes these files against the current Swift models so the examples stay aligned with the implementation.

`capabilities.json` includes source-tree `schemas`, installed app-bundle `schemaResources`, and stable `schemaIDs` so agents can validate payloads from either a checkout or an installed `Vifty.app`.

Files:

- [capabilities.json](capabilities.json) - `viftyctl capabilities --json`
- [audit.json](audit.json) - `viftyctl audit --json`
- [diagnose-ready.json](diagnose-ready.json) - `viftyctl diagnose --json` on ready hardware with `recommendedRecoveryAction`
- [diagnose-blocked-helper-unreachable.json](diagnose-blocked-helper-unreachable.json) - `viftyctl diagnose --json` when helper telemetry exists but the daemon agent-control path is unreachable
- [diagnose-degraded-active-lease.json](diagnose-degraded-active-lease.json) - `viftyctl diagnose --json` when another bounded cooling lease is active and new cooling is unsafe
- [diagnose-degraded-caution.json](diagnose-degraded-caution.json) - `viftyctl diagnose --json` when warning-only thermal pressure makes cooling safe only with caution
- [status-active-lease.json](status-active-lease.json) - `viftyctl status --json` with an active lease
- [command-error.json](command-error.json) - structured `--json` command failure with `recommendedRecoveryAction`
- [command-error-run-child-command-failed.json](command-error-run-child-command-failed.json) - `viftyctl run --json` child-command failure before any cooling lease is prepared
- [command-error-run-cleanup-restored.json](command-error-run-cleanup-restored.json) - `viftyctl run --json` launch failure after a prepared lease with Auto restore confirmed
- [command-error-run-cleanup-failed.json](command-error-run-cleanup-failed.json) - `viftyctl run --json` launch failure after a prepared lease where Auto restore failed

Schema:

- [../../schemas/viftyctl-capabilities.schema.json](../../schemas/viftyctl-capabilities.schema.json) - agent-facing schema for the capabilities report
- [../../schemas/viftyctl-audit.schema.json](../../schemas/viftyctl-audit.schema.json) - agent-facing schema for the read-only audit report
- [../../schemas/viftyctl-command-error.schema.json](../../schemas/viftyctl-command-error.schema.json) - agent-facing schema for structured command failures
- [../../schemas/viftyctl-diagnose.schema.json](../../schemas/viftyctl-diagnose.schema.json) - agent-facing schema for the readiness report
- [../../schemas/viftyctl-status.schema.json](../../schemas/viftyctl-status.schema.json) - agent-facing schema for status, prepare, and restore-auto reports

Blocked diagnose examples may exit `75` while still printing machine-readable JSON. `degraded` can be safe or unsafe, so agents must read `safeToRequestCooling`; `daemonControlPathReady: false` is always a helper-repair stop before requesting cooling.

Dates use Swift's current `JSONEncoder` default date representation, matching the CLI output.
