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

If the report includes output from `examples/viftyctl/guarded-run.sh`, ask for
the stderr transcript to be copied into the bundle with
`AGENT_EVIDENCE_GUARDED_RUN_STDERR=/path/to/guarded-run.stderr make agent-cooling-evidence`
or `--guarded-run-stderr-file <path>` so the reviewer can summarize only the
schema-backed decision payload between the guarded-run markers, including the
stable `decisionReason` category, daemon-runtime mismatch evidence, and
privacy-conscious workload envelope when current wrappers provide them.

If the reporter has the exact guarded workload command but has not captured a
transcript yet, prefer the collector's read-only wrapper preflight:

```sh
scripts/collect-agent-cooling-evidence.sh \
  --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl \
  --guarded-run-preflight test 20m 70 "swift test" -- swift test
```

That path emits `guarded-run-stderr.txt` and
`guarded-run-preflight.status` without requesting cooling or launching the
child command.

Installed app bundles include the same read-only collector at
`/Applications/Vifty.app/Contents/Resources/collect-agent-cooling-evidence.sh`
for reporters who do not have a source checkout. For supervised
supported-hardware workload proof, use the bundled
`/Applications/Vifty.app/Contents/Resources/collect-agent-run-smoke-evidence.sh`
only after readiness is safe; it may request one bounded `viftyctl run` cooling
lease and is not the first-response path for helper failures.

It captures `capabilities --json`, `diagnose --json`, `status --json`, and
`audit --limit 20 --json` plus exit statuses, launchd/helper install evidence,
a manifest, optional `guarded-run-stderr.txt`, `privacy-review.tsv`, and
checksums. It does not request cooling, restore Auto, invoke `ViftyHelper`, use `sudo`, or write SMC keys. Review the
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
`safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`,
`failedCheckIDs`, `coolingBlockerIDs`, display-only `operatorRecoveryCommands`,
and `appPreferences.startupMode`. If those fields are missing or contradict the
diagnose exit code or each other, the review fails; malformed blocker-ID arrays
or agent-runnable operator recovery commands fail the same way. A non-empty
`coolingBlockerIDs` list must never be paired with `safeToRequestCooling: true`;
route those reports as hard blocked readiness instead of agent-safe evidence.
Legacy `v1.1.x` reports that omit
`daemonControlPathReady`, blocker-ID arrays, or `appPreferences` may pass only
with a warning;
`daemonControlPathReady` must still be inferred from structured
readiness/recovery fields. When `manualControlActive` is true and the saved
startup mode is `Curve` or `Fixed`, the reviewer warning should be routed as a
default-mode issue before another agent-cooling request. It also
writes `capabilitiesDecision` for advertised `viftyctl run` support,
force-retry discovery, safe `runLifecycle` including `resolvedChildExecutableReported=true`, safe direct prepare/restore
lifecycle, wrapper resource discovery, metadata limits, policy status availability, daemon status, and unavailable-exit metadata;
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
make validation-evidence-review VALIDATION_EVIDENCE_BUNDLE=<evidence-dir> VALIDATION_EVIDENCE_REVIEW_MODE=release VALIDATION_EVIDENCE_REVIEW_SUMMARY=<evidence-dir>/review-result.json
```

For `v1.1.1`, source-first release issues should focus on source tag/CI readiness, release-note warnings, unsigned-dev artifact naming/checksum, and the explicit source-first trust boundary. Do not ask users to verify Developer ID signing, notarization, stapling, or Homebrew trust for `v1.1.1`; those checks apply only to a future `--mode developer-id` release.

If a `v1.1.0` user reports "Fan helper unreachable" after updating, first collect the read-only agent evidence bundle, `diagnose --json`, `status --json`, and launchd/collector evidence. If the report matches the published helper issue, do not replace `v1.1.0` assets from `main`; direct the user to the `v1.1.1` source-first hotfix release. When `appInfo.shortVersion` is `1.1.0`, blocked `diagnose` recommends `repairHelper`, and accepted structured `HELPER_UNREACHABLE` command errors are present, the lightweight reviewer warns that this is the known v1.1.0 helper-unreachable issue; use the v1.1.1 source-first hotfix and do not retag v1.1.0 or replace its unsigned-dev assets.

The lightweight agent evidence bundle includes schema-backed `agent-cooling-evidence-summary.json` with `schemaID: https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json`; treat that summary as the machine-readable index for helper-unreachable and agent-cooling support bundles. It should record only the `viftyctl` basename, `viftyctlPathKind`, and `viftyctlPathPrivacy: basenameOnly`, not local executable directory paths. The lightweight reviewer can write `agent-cooling-evidence-review.json` with `schemaID: https://vifty.local/schemas/agent-cooling-evidence-review.schema.json`, `diagnoseDecision`, `capabilitiesDecision`, `appInfo`, and `acceptedCommandErrors` summaries; use `scripts/review-agent-cooling-evidence.sh` before a report becomes evidence. Accepted command errors must be structured `HELPER_UNREACHABLE` reports with `schemaVersion: 1`, `schemaID: https://vifty.local/schemas/viftyctl-command-error.schema.json`, and `safeToProceed: false`.

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
| Helper install or approval | `HELPER_UNREACHABLE`, helper unreachable UI, fallback fan telemetry with daemon not responding, Login Items approval, empty fan snapshot, or manual controls blocked by helper state | Read-only agent evidence bundle, `diagnose --json`, `status --json`, helper recovery text from the app, launchd status from collector | Ask user to open Vifty and use Repair/Reinstall Helper, or use `make repair-helper` from a source checkout for the same explicit administrator-approved repair so the daemon is copied, quarantine is stripped, and launchd is restarted. Approve Login Items if macOS asks, then rerun read-only diagnostics. |
| SMC key or fan telemetry drift | Fan count/range/mode missing, `hardwareMode` unknown, fan mode-key casing drift, no controllable fans on supported hardware | `probeLocal`, `diagnose --json`, model identifier, macOS version | Keep fan writes blocked until fan IDs, ranges, mode-key casing, and mode/target telemetry are understood. |
| Agent-cooling lifecycle | `prepare`, `run`, restore failure, expired lease, rate limit, guarded wrapper refusal, or child-command preflight issue | Agent Cooling Report issue, exact `viftyctl` or guarded-wrapper command, stdout/stderr, read-only agent evidence bundle with `--guarded-run-stderr-file <path>` when wrapper stderr exists or `--guarded-run-preflight ... -- <command>` when the exact workload should be checked without side effects, or manual `diagnose --json`, `capabilities --json`, `status --json`, `audit --limit 20 --json`; preflight bundles should include a `guarded-run-preflight` row in `manifest.tsv` and `agent-cooling-evidence-summary.json`; on supported hardware with safe readiness, optional `make agent-run-smoke-evidence-current-build` for current source checkouts or `make agent-run-smoke-evidence VIFTYCTL=/Applications/Vifty.app/Contents/MacOS/viftyctl` for installed-app smoke bundles | Follow [safe-agent-cooling.md](safe-agent-cooling.md); do not start another lease while restore is pending, and use the supervised smoke target only after readiness is safe. |
| UI or copy | Confusing owner/helper state, profile preset behavior, power/thermal display | screenshot, macOS version, `diagnose --json` if fan state is involved | Fix copy/state without changing SMC behavior unless evidence shows a control bug. |

When the UI says `Fixed request pending` or `Curve request pending`, Vifty has preserved the user's manual intent but the helper write path is blocked. Treat **Copy Support Evidence** as the safest next evidence path: the bundled collector can write `ui-context.txt` next to the read-only `viftyctl` evidence so reviewers can see selected mode, manual-run choice, helper state, hot fan-write warning, current temperature/fan summary, and last app error without requesting cooling or writing SMC keys. Do not ask the user to run a fan-write smoke test until `diagnose --json` reports `daemonControlPathReady: true`, `manualControlActive: false`, and the normal hardware-validation gates pass.

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

For supported Apple Silicon MacBook Pro reports that are close to manual validation, ask for `make manual-smoke-readiness` first. For clean current-source reports, prefer `make manual-smoke-readiness-current-build`; it blocks if the installed LaunchDaemon helper does not match the freshly built daemon. Use `MANUAL_SMOKE_READINESS_SUMMARY=.build/manual-smoke-readiness.json MANUAL_SMOKE_READINESS_JSON=1 make manual-smoke-readiness-current-build` when you want the reviewer-ready JSON saved without copy/paste. For installed-app testers without a source checkout, use `/Applications/Vifty.app/Contents/Resources/check-manual-smoke-readiness.sh --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl --json --summary manual-smoke-readiness.json`. In JSON mode (`MANUAL_SMOKE_READINESS_JSON=1 make manual-smoke-readiness`) the result is read-only evidence with `schemaID: https://vifty.local/schemas/manual-smoke-readiness.schema.json`, `daemonRuntime`, `recoverySteps`, display-only `operatorRecoveryCommands`, and `coolingCommandsRun: false`; if it exits `75`, use the listed blockers, ordered recovery steps, and human-only commands as guidance and do not suggest Fixed/Curve smoke, `prepare`, or agent-run smoke yet. For passed `local-ad-hoc-build` manual smoke, require the ready JSON through `VALIDATION_EVIDENCE_MANUAL_SMOKE_READINESS_SUMMARY=<path>` so `review-result.json` records `manualSmokeReadinessSource`.

Before asking for supervised developer-workload proof, ask for `make agent-run-smoke-readiness`. In JSON mode (`AGENT_RUN_SMOKE_READINESS_JSON=1 make agent-run-smoke-readiness`) it emits `schemaID: https://vifty.local/schemas/agent-run-smoke-readiness.schema.json`, keeps `readOnly: true` and `coolingCommandsRun: false`, and validates daemon-backed capabilities, policy limits, wrapper lifecycle, `safeToRequestCooling`, helper readiness, and manual-control state without calling `viftyctl run`. Use `AGENT_RUN_SMOKE_READINESS_SUMMARY=.build/agent-run-smoke-readiness.json` when you want the reviewer-ready JSON saved without copy/paste, then pass it as `VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_READINESS_SUMMARY=<path>` during validation review so `review-result.json` records `agentRunSmokeReadinessSource`. The readiness summary omits the full reason text, keeps `reasonCharacterCount`, labels daemon path display privacy, and carries diagnose `recoverySteps` plus display-only `operatorRecoveryCommands` for blocked states; the supervised smoke summary uses the same reason/privacy-label envelope, the share-safe child command envelope, basename-only resolved executable display with `resolvedChildExecutablePathPrivacy=basenameOnly`, and daemon identity in SHA-256 fields. The reviewer rejects obvious `/Users/...` leaks in legacy or hand-edited readiness and smoke summaries, and rejects readiness summaries whose `operatorRecoveryCommands` are missing, malformed, or marked agent-runnable. If readiness exits `75`, do not ask the reporter to run `make agent-run-smoke-evidence`; triage the blockers first.

## Compatibility Claims

Only update [compatibility.md](compatibility.md) from reviewed `review-result.json` files. Use [hardware-validation.md](hardware-validation.md) for collection and `scripts/summarize-validation-reports.sh` for indexes. Keep `installSource`, `sourceRef`, `sourceSHA`, `sourceArtifactSHA256`, `modelFamily`, `recommendedAgentAction`, `recommendedRecoveryAction`, `failedCheckIDs`, `coolingBlockerIDs`, `daemonControlPathReady`, `manualControlActive`, `manualSmokeReadinessSource`, `agentRunSmokeResult`, `agentRunSmokeSource`, `agentRunSmokeReadinessSource`, `agentRunSmokePrivacyReviewSource`, `agentRunSmokePrivacyReviewStatus`, `agentRunSmokeStartupMode`, `agentRunSmokeStartupModeSource`, and `agentRunSmokeStartupModeReadError` visible when moving reports into compatibility indexes, especially for source-first `v1.1.1` reports. `coolingBlockerIDs` must be empty for cooling-safe evidence; non-empty blocker lists are triage and recovery context, not support proof. The startup-mode fields are startup-mode recovery context, not cooling authorization; use them to explain why manual ownership or a saved Curve/Fixed default may need user action before another agent/build/test cooling request. Captured agent-run privacy-review fields prove the reviewer checked the smoke bundle privacy gate; they are evidence provenance, not cooling authorization. Use `countsByModelFamily`, `validatedHardwareReportsByModelFamily`, and the optional generated `compatibility-matrix.md` draft to group reports by stable model identifier prefix before changing any public support claim. A supported-hardware report becomes validated hardware evidence only when the review result includes:

```json
"manualSmokeTestResult": "passed-auto-restored"
```

Until then, keep the report as candidate evidence that still needs manual smoke confirmation. Prefer `VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY=<smoke-dir>/agent-run-smoke-evidence-summary.json` when the supervised smoke bundle is available; the reporter should run `make agent-run-smoke-readiness` first, and the reviewer validates `schemaID: https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json`, the omitted reason/count fields, daemon path privacy labels, the child command basename/kind/argument-count envelope, the resolved executable basename/privacy envelope, `privacy-review.tsv` status with no `redaction-needed` rows, and adjacent command/checksum evidence before deriving `agentRunSmokeResult`. If only issue-template text records the supervised smoke result for a `local-ad-hoc-build`, require `VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_READINESS_SUMMARY=<path>` so the reviewer can record `agentRunSmokeReadinessSource` and prove the read-only preflight was safe and daemon-matched before accepting the claim. For `local-ad-hoc-build` smoke, require the `daemonRuntime` fields to show that the installed LaunchDaemon helper matched the expected build daemon before the lease was requested. `agentRunSmokeResult: "passed-auto-restored"` is useful developer-workload proof for guarded `viftyctl run`, but it does not promote a row to validated hardware evidence without the manual smoke result above. When reviewing many reports, use the index `countsByRecommendedAgentAction`, `countsByRecommendedRecoveryAction`, `countsBySafeToRequestCooling`, `countsByDaemonControlPathReady`, and `countsByManualControlActive` fields to find stop-before-cooling, helper-repair, active/manual-control, and unsafe-readiness clusters before updating compatibility claims.
