# viftyctl JSON Examples

These examples are canonical sample payloads for local agents and shell automation. They are not captured from a live machine; they are stable fixtures that document the JSON shape emitted by `viftyctl`.

The XCTest suite decodes these files against the current Swift models so the examples stay aligned with the implementation.

`capabilities.json` includes source-tree `schemas`, installed app-bundle `schemaResources`, and stable `schemaIDs` so agents can validate payloads from either a checkout or an installed `Vifty.app`.

Files:

- [capabilities.json](capabilities.json) - `viftyctl capabilities --json`
- [audit.json](audit.json) - `viftyctl audit --json`
- [diagnose-ready.json](diagnose-ready.json) - `viftyctl diagnose --json` on ready hardware
- [status-active-lease.json](status-active-lease.json) - `viftyctl status --json` with an active lease
- [command-error.json](command-error.json) - structured `--json` command failure

Schema:

- [../../schemas/viftyctl-capabilities.schema.json](../../schemas/viftyctl-capabilities.schema.json) - agent-facing schema for the capabilities report
- [../../schemas/viftyctl-audit.schema.json](../../schemas/viftyctl-audit.schema.json) - agent-facing schema for the read-only audit report
- [../../schemas/viftyctl-command-error.schema.json](../../schemas/viftyctl-command-error.schema.json) - agent-facing schema for structured command failures
- [../../schemas/viftyctl-diagnose.schema.json](../../schemas/viftyctl-diagnose.schema.json) - agent-facing schema for the readiness report
- [../../schemas/viftyctl-status.schema.json](../../schemas/viftyctl-status.schema.json) - agent-facing schema for status, prepare, and restore-auto reports

Dates use Swift's current `JSONEncoder` default date representation, matching the CLI output.
