# Support

Vifty controls fans through a privileged local daemon, so support starts with
read-only evidence and conservative safety gates.

## Where To Ask

- **Security vulnerabilities:** do not open a public issue. Use GitHub
  Security Advisories and follow [SECURITY.md](SECURITY.md).
- **Release trust:** use the **Release Trust Report** issue template for
  source-first release warnings, unsigned-dev asset naming or checksum issues,
  Gatekeeper, Developer ID, notarization, Homebrew, TeamID, release-readiness,
  verifier, or reviewer problems. For source-first releases, remember that the
  optional unsigned `.app` zip is tester convenience only. The `v1.1.1`
  source-first hotfix supersedes the known `v1.1.0` helper-unreachable issue;
  keep both reports in the release-trust evidence lane, not as proof of trusted
  binary distribution.
- **Hardware validation:** use the **Hardware Validation Report** issue
  template and follow [docs/hardware-validation.md](docs/hardware-validation.md).
- **Agent/build/test cooling:** use the **Agent Cooling Report** issue template
  for `viftyctl prepare`, `viftyctl run`, `restore-auto`, guarded wrappers,
  rate limits, expired leases, restore failures, or child-command preflight
  issues.
- **General bugs or UI issues:** use the bug report template. Include screenshots
  only after collecting the safe diagnostics below when fan state is involved.
- **Questions and design discussion:** use GitHub Discussions when no bug,
  safety issue, or validation report is involved.

Maintainers triage reports with [docs/support-triage.md](docs/support-triage.md).

## Safe First Evidence

For agent/build/test cooling, helper-unreachable, and restore-failure reports,
the quickest read-only bundle is:

```sh
scripts/collect-agent-cooling-evidence.sh \
  --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl
```

If the report is about a guarded wrapper refusal and you already captured the
wrapper stderr, add it without rerunning the workload:

```sh
scripts/collect-agent-cooling-evidence.sh \
  --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl \
  --guarded-run-stderr-file /path/to/guarded-run.stderr
```

The script writes `viftyctl-diagnose.json`, `viftyctl-capabilities.json`,
`viftyctl-status.json`, `viftyctl-audit.json`, command status files, a manifest,
read-only launchd/helper install files, schema-backed
`agent-cooling-evidence-summary.json` with
`schemaID: https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json`,
optional `guarded-run-stderr.txt`, `privacy-review.tsv`, and a checksum list. It does not request cooling, restore Auto, call `ViftyHelper`, use `sudo`, or write SMC keys. Check
`privacy-review.tsv` before posting the bundle publicly; redact or share
privately if it reports `redaction-needed`.

Maintainers can review the bundle before triage with:

```sh
scripts/review-agent-cooling-evidence.sh \
  --bundle <bundle-dir> \
  --summary <bundle-dir>/agent-cooling-evidence-review.json
```

The reviewer rejects schema drift, manifest/status/checksum drift,
`redaction-needed` privacy findings, and any evidence that says cooling commands
were run. Its JSON summary declares
`schemaID: https://vifty.local/schemas/agent-cooling-evidence-review.schema.json`.
It accepts `viftyctl diagnose` exit `75` as blocked-readiness evidence and
records a `diagnoseDecision` object with the diagnose exit status, readiness
state, `recommendedAgentAction`, `recommendedRecoveryAction`,
`safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`, and
`appPreferences.startupMode`. Missing or contradictory diagnose decision fields
fail review, except legacy `v1.1.x` bundles that omit `daemonControlPathReady`
or `appPreferences` may pass only with a warning; `daemonControlPathReady` must
still be inferred from structured readiness and recovery fields. Manual-control
reports with a persisted `Curve` or `Fixed` default are called out so triage can
tell the user to switch Vifty's default startup mode to `Auto` before retrying
agent cooling. The summary also records
`guardedRunDecision` when `guarded-run-stderr.txt` contains a bracketed
`https://vifty.local/schemas/guarded-run-decision.schema.json` payload; that
summary is accepted only when the wrapper decision agrees with the captured
diagnose evidence. It records `capabilitiesDecision` for the advertised `viftyctl run` support, force-retry
discovery, safe run/direct-control lifecycle, metadata limits, policy status
availability, daemon status, and unavailable exit-code contract; missing or unsafe capabilities contract
fields fail review, except absent legacy `metadataLimits` is a warning rather
than a blocker for read-only triage evidence. The summary also records
`appInfo` from the captured app plist: app plist command exit status, bundle
identifier, short version, and bundle version, so helper-unreachable reports can
be routed against the installed app version instead of a manually typed value.
If `diagnoseDecision` proves blocked readiness with `repairHelper`, the reviewer
may list `viftyctl-status` or `viftyctl-audit` in `acceptedCommandErrors`, but
only when their JSON is a structured `HELPER_UNREACHABLE` command error with
`schemaVersion: 1`,
`schemaID: https://vifty.local/schemas/viftyctl-command-error.schema.json`, and
`safeToProceed: false`.
When `appInfo.shortVersion` is `1.1.0` and that same repair-helper evidence is
present, the reviewer emits this stable warning text: known v1.1.0 helper-unreachable issue; use the v1.1.1 source-first hotfix and do not retag v1.1.0 or replace its unsigned-dev assets.

If you prefer to paste commands manually, start with these read-only commands
when Vifty is installed:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
/Applications/Vifty.app/Contents/MacOS/viftyctl capabilities --json
/Applications/Vifty.app/Contents/MacOS/viftyctl status --json
/Applications/Vifty.app/Contents/MacOS/viftyctl audit --limit 20 --json
```

If the report is about fan telemetry on a supported Apple Silicon MacBook Pro,
maintainers may also ask for:

```sh
sudo /Applications/Vifty.app/Contents/MacOS/ViftyHelper probeLocal
```

Do not attach evidence publicly until you have checked for private data. The
agent evidence collector and validation collector both write `privacy-review.tsv`;
a nonzero privacy row means the bundle may contain a hostname, `/Users/...`
path, serial-number label, or hardware UUID label that should be redacted or
shared privately.

## Safety Rules

- Do not run `sudo ViftyHelper setFixed`, raw SMC tools, or manual fan-write
  smoke tests when `diagnose --json` reports `state: "blocked"` or
  `safeToRequestCooling: false` or `daemonControlPathReady: false`.
- Do not retry `viftyctl prepare` or `viftyctl run` while readiness is blocked,
  thermal pressure is critical, sensors are missing, no controllable fans are
  present, fan IDs or RPM ranges are invalid, or Auto restore is pending.
- Unsupported Macs should remain under macOS automatic fan control. Follow
  [docs/unsupported-hardware.md](docs/unsupported-hardware.md) and collect
  read-only evidence only.
- Prefer [docs/safe-agent-cooling.md](docs/safe-agent-cooling.md) and the
  guarded wrappers in [examples/viftyctl](examples/viftyctl/README.md) for local
  build/test/agent workloads.

When in doubt, stop at read-only diagnostics and ask before running any command
that changes fan state.
