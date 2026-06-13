# Support Triage

Use this guide when reviewing bug reports, hardware-validation issues, release reports, or agent-cooling failures. Vifty should earn trust by sorting reports into the right bucket quickly and asking only for evidence that is safe to collect.

Do not ask reporters to run raw SMC writes, `sudo ViftyHelper setFixed`, or manual fan-write smoke tests when readiness is `blocked`. Use [unsupported-hardware.md](unsupported-hardware.md) when the report is outside the Apple Silicon MacBook Pro fan-control scope.

## First Response

Ask for the least invasive evidence that answers the triage question. For
agent/build/test cooling, helper-unreachable, rate-limit, expired-lease, and
restore-failure reports, prefer the read-only agent evidence bundle:

```sh
scripts/collect-agent-cooling-evidence.sh \
  --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl
```

It captures `capabilities --json`, `diagnose --json`, `status --json`, and
`audit --limit 20 --json` plus exit statuses, launchd/helper install evidence,
a manifest, `privacy-review.tsv`, and checksums. It does not request cooling,
restore Auto, invoke `ViftyHelper`, use `sudo`, or write SMC keys. Review the
bundle locally before triage:

```sh
scripts/review-agent-cooling-evidence.sh \
  --bundle <bundle-dir> \
  --summary <bundle-dir>/agent-cooling-evidence-review.json
```

The reviewer fails on `redaction-needed` privacy findings, schema drift,
manifest/status/checksum drift, or any evidence that cooling commands were run.
Its JSON summary declares
`schemaID: https://vifty.local/schemas/agent-cooling-evidence-review.schema.json`.
It accepts `viftyctl diagnose` exit `75` as blocked-readiness evidence and
summarizes the reviewed diagnose contract in `diagnoseDecision`: exit status,
readiness state, `recommendedAgentAction`, `recommendedRecoveryAction`,
`safeToRequestCooling`, and `daemonControlPathReady`. If those fields are
missing or contradict the diagnose exit code, the review fails, except legacy
`v1.1.x` reports that omit `daemonControlPathReady` may pass only when the same
boolean can be inferred from structured readiness/recovery fields. It also
writes `capabilitiesDecision` for advertised `viftyctl run` support,
force-retry discovery, safe `runLifecycle`, safe direct prepare/restore
lifecycle, metadata limits, daemon status, and unavailable-exit metadata;
missing or unsafe capabilities contract fields fail review, except absent
legacy `metadataLimits` is recorded as a warning for read-only triage evidence.
It also writes `appInfo` from the captured app plist: app plist command exit
status, bundle identifier, short version, and bundle version, so maintainers can
separate published `v1.1.0` helper-unreachable reports from `v1.1.1` or
current-source reports without trusting a manually typed version. In helper-unreachable cases,
the reviewer may also write `acceptedCommandErrors` for nonzero `status` or
`audit` only when blocked `diagnose` recommends `repairHelper` and the command
JSON is a structured `HELPER_UNREACHABLE` error with `safeToProceed: false`. If a reporter cannot run the
script, ask for the same read-only commands manually:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
/Applications/Vifty.app/Contents/MacOS/viftyctl capabilities --json
/Applications/Vifty.app/Contents/MacOS/viftyctl status --json
/Applications/Vifty.app/Contents/MacOS/viftyctl audit --limit 20 --json
```

For hardware/fan reports on supported Apple Silicon MacBook Pro machines, also ask for:

```sh
sudo /Applications/Vifty.app/Contents/MacOS/ViftyHelper probeLocal
```

For release-trust reports, use the dedicated **Release Trust Report** issue template and prefer the release-readiness preflight plus collector bundle:

```sh
git fetch origin main --tags
scripts/check-release-readiness.sh --mode source-first --version <version> --repo Reedtrullz/Vifty --json
scripts/collect-validation-evidence.sh --app /Applications/Vifty.app
scripts/review-validation-evidence.sh --bundle <evidence-dir> --mode release --summary <evidence-dir>/review-result.json
```

For `v1.1.1`, source-first release issues should focus on source tag/CI readiness, release-note warnings, unsigned-dev artifact naming/checksum, and the explicit source-first trust boundary. Do not ask users to verify Developer ID signing, notarization, stapling, or Homebrew trust for `v1.1.1`; those checks apply only to a future `--mode developer-id` release.

If a `v1.1.0` user reports "Fan helper unreachable" after updating, first collect the read-only agent evidence bundle, `diagnose --json`, `status --json`, and launchd/collector evidence. If the report matches the published helper issue, do not replace `v1.1.0` assets from `main`; direct the user to the `v1.1.1` source-first hotfix release.

The lightweight agent evidence bundle includes schema-backed `agent-cooling-evidence-summary.json` with `schemaID: https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json`; treat that summary as the machine-readable index for helper-unreachable and agent-cooling support bundles. The lightweight reviewer can write `agent-cooling-evidence-review.json` with `schemaID: https://vifty.local/schemas/agent-cooling-evidence-review.schema.json`, `diagnoseDecision`, `capabilitiesDecision`, `appInfo`, and `acceptedCommandErrors` summaries; use `scripts/review-agent-cooling-evidence.sh` before a report becomes evidence.

Use `--require-source-ref <candidate-ref-or-sha>` only when checking an unpublished release candidate or when you have an immutable release commit SHA. Do not require `origin/main` for an already-published source-first tag after `main` has moved on.

Before asking someone to attach a bundle publicly, check `privacy-review.tsv`.
A nonzero `privacy-review` row means the named files may contain a hostname,
`/Users/...` path, serial-number label, or hardware UUID label and should be
redacted or shared privately. This applies to both the lightweight agent
evidence bundle and the fuller validation evidence bundle.

## Triage Buckets

| Bucket | Typical signal | Evidence to request | Safe next action |
| --- | --- | --- | --- |
| Release trust | Source-first warning drift, unsigned-dev artifact naming/checksum, known source-first helper issue, Gatekeeper, notarization, cask SHA, TeamID, missing release assets, release-readiness blocker, stale release tag, or bundle-version mismatch | Release Trust Report issue, `scripts/check-release-readiness.sh --mode source-first --version <version> --repo Reedtrullz/Vifty --json`, optional `--require-source-ref <candidate-ref-or-sha>` for unpublished candidates, future Developer ID `--mode developer-id` readiness, `scripts/verify-release-artifact.sh --team-id <TEAMID>`, collector bundle, `review-result.json` | Do not promote the release or cask until the correct mode's readiness passes; do not treat unsigned-dev artifacts as trusted binaries, and cut a new source-first hotfix instead of retagging a flawed source release. |
| Hardware validation | New Apple Silicon MacBook Pro model, missing compatibility row, or smoke-test report | Hardware Validation Report issue, `diagnose --json`, `probeLocal`, collector bundle | Keep the model as needs validation until review passes and manual smoke records Auto restore. |
| Unsupported hardware safe block | Non-MacBook-Pro, Intel, or unsupported Apple Silicon reports `blocked` | `diagnose --json`, optional collector bundle, [unsupported-hardware.md](unsupported-hardware.md) | Treat safe blocking as expected behavior; do not suggest bypasses. |
| Helper install or approval | `HELPER_UNREACHABLE`, helper unreachable UI, fallback fan telemetry with daemon not responding, Login Items approval, empty fan snapshot, or manual controls blocked by helper state | Read-only agent evidence bundle, `diagnose --json`, `status --json`, helper recovery text from the app, launchd status from collector | Ask user to open Vifty, use Repair/Reinstall Helper so the app copies the daemon, strips quarantine, and restarts launchd, approve Login Items if macOS asks, then rerun read-only diagnostics. |
| SMC key or fan telemetry drift | Fan count/range/mode missing, `hardwareMode` unknown, fan mode-key casing drift, no controllable fans on supported hardware | `probeLocal`, `diagnose --json`, model identifier, macOS version | Keep fan writes blocked until fan IDs, ranges, mode-key casing, and mode/target telemetry are understood. |
| Agent-cooling lifecycle | `prepare`, `run`, restore failure, expired lease, rate limit, or child-command preflight issue | Agent Cooling Report issue, exact `viftyctl` command, stdout/stderr, read-only agent evidence bundle or manual `diagnose --json`, `capabilities --json`, `status --json`, `audit --limit 20 --json` | Follow [safe-agent-cooling.md](safe-agent-cooling.md); do not start another lease while restore is pending. |
| UI or copy | Confusing owner/helper state, profile preset behavior, power/thermal display | screenshot, macOS version, `diagnose --json` if fan state is involved | Fix copy/state without changing SMC behavior unless evidence shows a control bug. |

## Labels

Suggested labels:

- `release-trust`
- `hardware-validation`
- `unsupported-hardware`
- `helper-install`
- `smc-telemetry`
- `agent-cooling`
- `ui`

The expected GitHub topics and labels are tracked in `.github/repo-metadata.json`. Maintainers can verify live repository metadata with:

```sh
scripts/check-github-metadata.sh --repo Reedtrullz/Vifty --json
```

Use `security` only for public non-sensitive tracking. For vulnerabilities involving unprivileged fan writes, daemon client spoofing, arbitrary SMC writes, or local permission leaks, direct the reporter to GitHub Security Advisories.

Use the dedicated **Agent Cooling Report** issue template for `viftyctl run`, `prepare`, `restore-auto`, guarded wrapper, rate-limit, expired-lease, and restore-failure reports.

Use the dedicated **Release Trust Report** issue template for source-first release-note warnings, unsigned-dev asset naming/checksum, GitHub Release asset, Homebrew cask SHA, Gatekeeper, notarization, stapling, Developer ID TeamID, LaunchDaemon TeamID allowlist, bundle-version, release-readiness, and release verifier/reviewer failures. Do not treat a source tag, CI artifact, unsigned-dev convenience zip, or local ad-hoc build as a trusted public binary release.

## Escalation Rules

Escalate a report before suggesting any fan-write test when:

- `diagnose --json` reports `state: "blocked"`;
- thermal pressure is critical;
- temperature sensors are missing;
- no controllable fans are present on a claimed supported MacBook Pro;
- fan IDs are invalid or duplicated;
- fan RPM ranges are invalid;
- the helper or daemon state is uncertain;
- an agent lease is expired but Auto restore is still pending.

## Compatibility Claims

Only update [compatibility.md](compatibility.md) from reviewed `review-result.json` files. Use [hardware-validation.md](hardware-validation.md) for collection and `scripts/summarize-validation-reports.sh` for indexes. Keep `installSource`, `sourceRef`, `sourceSHA`, `sourceArtifactSHA256`, `modelFamily`, `recommendedAgentAction`, `recommendedRecoveryAction`, `daemonControlPathReady`, `agentRunSmokeResult`, and `agentRunSmokeSource` visible when moving reports into compatibility indexes, especially for source-first `v1.1.1` reports. Use `countsByModelFamily`, `validatedHardwareReportsByModelFamily`, and the optional generated `compatibility-matrix.md` draft to group reports by stable model identifier prefix before changing any public support claim. A supported-hardware report becomes validated hardware evidence only when the review result includes:

```json
"manualSmokeTestResult": "passed-auto-restored"
```

Until then, keep the report as candidate evidence that still needs manual smoke confirmation. `agentRunSmokeResult: "passed-auto-restored"` is useful developer-workload proof for guarded `viftyctl run`, but it does not promote a row to validated hardware evidence without the manual smoke result above. When reviewing many reports, use the index `countsByRecommendedAgentAction`, `countsByRecommendedRecoveryAction`, `countsBySafeToRequestCooling`, and `countsByDaemonControlPathReady` fields to find stop-before-cooling, helper-repair, and unsafe-readiness clusters before updating compatibility claims.
