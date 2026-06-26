# viftyctl JSON Examples

These examples are canonical sample payloads for local agents and shell automation. They are not captured from a live machine; they are stable fixtures that document the JSON shape emitted by `viftyctl`.

The XCTest suite decodes these files against the current Swift models so the examples stay aligned with the implementation.

`capabilities.json` includes source-tree `schemas`, installed app-bundle `schemaResources`, stable `schemaIDs`, wrapper resource discovery, and audited `workloadTemplates` so agents can validate payloads from either a checkout or an installed `Vifty.app` without scraping docs for safe build/test/model command defaults.

Agent-rule examples include the stable agent-rule schema ID,
`https://vifty.local/schemas/viftyctl-agent-rule.schema.json`, matching
`capabilities.schemaIDs.agentRule` before agents trust the pasteable safe-cooling
instructions, default guarded-run commands, safety requirements, or forbidden
actions. They also expose `guardedRunDecisionSchemaID:
https://vifty.local/schemas/guarded-run-decision.schema.json` so agents can
validate guarded-run no-cooling/preflight decision JSON without scraping rule
text, plus `guardedRunJSONMarkers` so agents can extract wrapper capabilities,
diagnose, and decision JSON blocks without hardcoding marker strings.

Command-error examples include the stable command-error schema ID,
`https://vifty.local/schemas/viftyctl-command-error.schema.json`, matching
`capabilities.schemaIDs.commandError` before agents trust recovery, retry, or
cleanup fields. Current command-error examples include ordered `recoverySteps`
so agents can show the next safe action without parsing human messages.

Status examples include the stable status schema ID,
`https://vifty.local/schemas/viftyctl-status.schema.json`, matching
`capabilities.schemaIDs.status` before agents trust lease, policy, or decision
fields.

Run success examples include the stable run schema ID,
`https://vifty.local/schemas/viftyctl-run.schema.json`, matching
`capabilities.schemaIDs.run` before agents trust child-exit or Auto-restore
status from a completed `viftyctl run --json` workload. Current examples also
show `resolvedChildExecutableSHA256Status` so agents can distinguish computed,
unavailable, and legacy digest provenance.

Files:

- [capabilities.json](capabilities.json) - `viftyctl capabilities --json`
- [agent-rule.json](agent-rule.json) - `viftyctl agent-rule --json`
- [audit.json](audit.json) - `viftyctl audit --json`
- [diagnose-ready.json](diagnose-ready.json) - `viftyctl diagnose --json` on ready hardware with `recommendedRecoveryAction`
- [diagnose-blocked-helper-unreachable.json](diagnose-blocked-helper-unreachable.json) - `viftyctl diagnose --json` when helper telemetry exists but the daemon agent-control path is unreachable
- [diagnose-degraded-active-lease.json](diagnose-degraded-active-lease.json) - `viftyctl diagnose --json` when another bounded cooling lease is active and new cooling is unsafe
- [diagnose-degraded-manual-control.json](diagnose-degraded-manual-control.json) - `viftyctl diagnose --json` when Vifty/manual fan control is active and an agent must wait for Auto restore before taking ownership
- [diagnose-degraded-caution.json](diagnose-degraded-caution.json) - `viftyctl diagnose --json` when warning-only thermal pressure makes cooling safe only with caution
- [status-active-lease.json](status-active-lease.json) - `viftyctl status --json` with an active lease
- [run-success.json](run-success.json) - `viftyctl run --json` after the child command exits and Auto restore succeeds
- [command-error.json](command-error.json) - structured `--json` command failure with `recommendedRecoveryAction`
- [command-error-run-child-command-failed.json](command-error-run-child-command-failed.json) - `viftyctl run --json` child-command failure before any cooling lease is prepared
- [command-error-run-cleanup-restored.json](command-error-run-cleanup-restored.json) - `viftyctl run --json` launch failure after a prepared lease with Auto restore confirmed
- [command-error-run-cleanup-failed.json](command-error-run-cleanup-failed.json) - `viftyctl run --json` launch failure after a prepared lease where Auto restore failed

Schema:

- [../../schemas/viftyctl-capabilities.schema.json](../../schemas/viftyctl-capabilities.schema.json) - agent-facing schema for the capabilities report
- [../../schemas/viftyctl-agent-rule.schema.json](../../schemas/viftyctl-agent-rule.schema.json) - agent-facing schema for the safe local agent-cooling rule
- [../../schemas/viftyctl-audit.schema.json](../../schemas/viftyctl-audit.schema.json) - agent-facing schema for the read-only audit report
- [../../schemas/viftyctl-command-error.schema.json](../../schemas/viftyctl-command-error.schema.json) - agent-facing schema for structured command failures
- [../../schemas/viftyctl-diagnose.schema.json](../../schemas/viftyctl-diagnose.schema.json) - agent-facing schema for the readiness report
- [../../schemas/viftyctl-run.schema.json](../../schemas/viftyctl-run.schema.json) - agent-facing schema for completed `viftyctl run --json` reports
- [../../schemas/viftyctl-status.schema.json](../../schemas/viftyctl-status.schema.json) - agent-facing schema for status, prepare, and restore-auto reports

Blocked diagnose examples may exit `75` while still printing machine-readable JSON. `degraded` can be safe or unsafe, so agents must read `safeToRequestCooling`; shell-only gates can use `diagnose --json --require-safe` to get exit `75` whenever a new cooling request is unsafe. `daemonControlPathReady: false` is always a helper-repair stop, `manualControlActive: true` is always a restore-Auto stop, and `daemonRuntime.matchRequired: true` with `daemonRuntime.matchesExpectedDaemon` not `true` is always a helper-runtime mismatch stop before requesting cooling. Current diagnose examples include `failedCheckIDs` for all failed readiness checks, `coolingBlockerIDs` for the hard-stop subset, ordered `recoverySteps`, and `appPreferences.startupMode` so integrations can distinguish a one-off manual marker from a saved Curve/Fixed default that may reassert control after launch. Current diagnose payloads may also include display-only `operatorRecoveryCommands` for a human to run from a source checkout; agents must honor `safeForAgentsToRunAutomatically: false`.

Dates use Swift's current `JSONEncoder` default date representation, matching the CLI output.
