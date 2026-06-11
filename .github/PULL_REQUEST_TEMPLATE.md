## Summary

<!-- Brief description of the change -->

## Safety Impact

<!-- Mark every area this PR touches and explain the risk briefly. Use "N/A" when it does not apply. -->

- Fan/SMC writes:
- Privileged daemon, helper, installer, signing, or XPC identity:
- `viftyctl`, agent leases, JSON contracts, or workload wrappers:
- Hardware validation, release trust, compatibility, or unsupported-hardware policy:
- UI state for Auto restore, helper health, fan ownership, or active agent cooling:
- Local persistence, permissions, telemetry, or audit history:

## Verification

<!-- Paste exact commands and results. If a gate was skipped, explain why and what evidence covers the risk instead. -->

```sh
make verify
```

## Safety Checklist

- [ ] `make verify` passes locally, or each skipped gate is explained
- [ ] New tests added for new functionality or bug fixes
- [ ] SMC write paths still reject arbitrary keys, invalid fan IDs, invalid RPM ranges, and mismatched fan commands before IOKit access
- [ ] Agent cooling remains lease-based, bounded, child-command-preflighted, and Auto-restoring; agents still use `safeToRequestCooling` / `recommendedAgentAction`
- [ ] Unprivileged app paths still fail closed when daemon/helper, hardware, sensor, fan, or thermal-pressure state is uncertain
- [ ] Release, signing, notarization, TeamID, cask, or schema-resource changes were checked with the release metadata/verifier scripts
- [ ] Hardware-validation or compatibility changes stay evidence-based and do not ask for manual fan-write smoke tests when readiness is blocked
- [ ] New local persistence keeps private permissions and does not add persistent telemetry beyond documented agent-control audit state
- [ ] Public docs, `AGENTS.md`, examples, JSON Schemas, and issue templates were updated when behavior or contracts changed

## Related Issues

<!-- Link to issues this PR closes or relates to -->
