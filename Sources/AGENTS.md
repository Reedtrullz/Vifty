# Vifty source boundaries

Read the root safety rules and [current state](../CURRENT_STATE.md). `Package.swift` is the target graph; source directory names are not independent products.

- `Vifty`: SwiftUI model/scenes, preferences, helper installation UI, advisory updates.
- `ViftyCore`: shared data, policy, XPC protocol/client, read-only telemetry and CLI contracts.
- `ViftyDaemon` + `ViftyDaemonSupport`: authenticated privileged service, lifecycle and maintenance coordination.
- `ViftyFanControlSafety`: exclusive ownership, durable journal, transactional write/readback/restore.
- `ViftyHelper` + `ViftyHelperSupport`: helper command boundary; not an alternate unrestricted agent write path.
- `ViftyCtl`: structured CLI; `ViftyAXCollector`/`ViftyAXEvidenceCore`: UI evidence. `ViftyBuildProvenance` binds build identity; `ViftyPrivateIOKit` is the native bridge.

Mocked tests are under `../Tests/ViftyCoreTests`. Keep read-only diagnostics distinct from hardware writes. Working files already contain installer changes beyond HEAD; preserve them.
