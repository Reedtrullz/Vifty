# Hardware Validation

Vifty should earn trust with repeatable hardware evidence, not guesses. Use this checklist when validating a release on Apple Silicon MacBook Pro hardware or when collecting compatibility reports from contributors.

Contributor reports should use the GitHub **Hardware Validation Report** issue template. The template asks for the exact readiness JSON, local helper fan probe output, model identifier, install source, and manual smoke-test result so compatibility claims remain auditable.

The public compatibility status is tracked in [compatibility.md](compatibility.md). Do not treat the intended support scope as broad validation until the compatibility page links to real reports. Unsupported machines should follow [unsupported-hardware.md](unsupported-hardware.md): collect read-only evidence, expect a blocked report, and do not run manual fan-write smoke tests.

For `v1.1.1`, record whether the app came from a source build from the tag or the optional `Vifty-v1.1.1-unsigned-dev.zip` tester artifact. Those reports can still prove hardware behavior, but they do not prove Developer ID signing, notarization, Homebrew trust, or trusted binary distribution. Future Developer ID or Homebrew reports should choose the corresponding install source only after that trusted-binary lane exists.

## Evidence Collector

For release candidates and contributor reports, the easiest read-only collection path is:

```sh
make validation-evidence
```

This defaults to `/Applications/Vifty.app` with `installSource=not-recorded` so a local report never pretends the installed app came from the current checkout. Use `VALIDATION_EVIDENCE_APP=<path>`, `VALIDATION_EVIDENCE_OUTPUT=<dir>`, `VALIDATION_EVIDENCE_INSTALL_SOURCE=<source>`, `VALIDATION_EVIDENCE_SOURCE_REF=<ref>`, `VALIDATION_EVIDENCE_SOURCE_SHA=<sha>`, `VALIDATION_EVIDENCE_SOURCE_ARTIFACT=<path>`, `VALIDATION_EVIDENCE_RELEASE_SUMMARY=<path>`, or `VALIDATION_EVIDENCE_RELEASE_CHECKLIST=<path>` when the installed app came from a known source or release artifact.

For a current `main` or other local ad-hoc source checkout, prefer the current-build target. It requires a clean git worktree, builds `.build/Vifty.app` first, and records `local-ad-hoc-build` with the current git ref and full SHA:

```sh
make validation-evidence-current-build
```

If the worktree is dirty, commit or stash first; otherwise use `make validation-evidence` with the default `installSource=not-recorded` for exploratory local evidence. If you already installed a local ad-hoc build elsewhere, set source provenance only after the installed app was actually built from that exact ref/SHA:

```sh
make validation-evidence \
  VALIDATION_EVIDENCE_INSTALL_SOURCE=local-ad-hoc-build \
  VALIDATION_EVIDENCE_SOURCE_REF=main \
  VALIDATION_EVIDENCE_SOURCE_SHA="$(git rev-parse HEAD)"
```

For a `v1.1.1` source-first report, record the install source explicitly:

```sh
# Source build from the immutable release tag.
make validation-evidence \
  VALIDATION_EVIDENCE_INSTALL_SOURCE=source-build-tag \
  VALIDATION_EVIDENCE_SOURCE_REF=v1.1.1 \
  VALIDATION_EVIDENCE_SOURCE_SHA=a82f2237ff39c24a6b366dca8f95a17ee54fd972

# Optional unsigned tester zip. Include the artifact path when it is available
# so install-provenance.tsv records the zip SHA-256 alongside the source tag.
make validation-evidence \
  VALIDATION_EVIDENCE_INSTALL_SOURCE=source-first-unsigned-dev-zip \
  VALIDATION_EVIDENCE_SOURCE_REF=v1.1.1 \
  VALIDATION_EVIDENCE_SOURCE_SHA=a82f2237ff39c24a6b366dca8f95a17ee54fd972 \
  VALIDATION_EVIDENCE_SOURCE_ARTIFACT=./Vifty-v1.1.1-unsigned-dev.zip
```

For `source-build-tag`, `source-first-unsigned-dev-zip`, and `local-ad-hoc-build` reports, `--source-sha` is required and must be the immutable 40-character source commit SHA. `source-build-tag` and `source-first-unsigned-dev-zip` also require `--source-ref` to be the version tag used for the source build. A mutable ref such as `main` is valid only with `local-ad-hoc-build`; it is not tag evidence.

When validating a published release, include the verifier summary too:

```sh
make validation-evidence \
  VALIDATION_EVIDENCE_RELEASE_SUMMARY=./Vifty-v<version>-artifact-summary.json \
  VALIDATION_EVIDENCE_RELEASE_CHECKLIST=./Vifty-v<version>-release-checklist.md
```

The script writes a local evidence bundle under `.build/vifty-validation-<timestamp>/` by default. It captures system metadata without the local hostname, bundle Info.plist, install/source provenance, bundled executable hashes, bundled JSON Schema resource hashes, bundled LaunchDaemon plist and TeamID setting, launchctl daemon status, app/CLI/helper/daemon signing checks, notarization/Gatekeeper checks, `viftyctl capabilities --json`, `viftyctl status --json`, `viftyctl diagnose --json`, and `viftyctl audit --limit 20 --json`, then writes `manifest.tsv` with each command's exit status, `install-provenance.tsv` with the declared install source, source ref/SHA, and optional source artifact SHA-256, `bundle-executables.tsv` with installed app/helper/daemon/CLI SHA-256 digests and bundle paths, `schema-resources.tsv` with installed schema SHA-256 digests and bundle paths, `capabilities-schema-resources.tsv` recording whether the CLI advertises those installed schema resource paths, `capabilities-contract.tsv` recording whether the CLI advertises the safe `runLifecycle`, direct prepare/restore lifecycle, `policyStatusAvailable: true`, metadata limits, and `supportsForceRetry` contract used by guarded workload wrappers, `privacy-review.tsv` to flag likely hostnames, `/Users/...` paths, serial-number labels, or hardware UUID labels before sharing, `review-summary.tsv` for reviewers, `review-summary.json` for automation, and `checksums.tsv` with SHA-256 digests and byte counts for the captured files. If `--release-summary` is supplied, the bundle also includes `release-artifact-summary.json` and `release-artifact-summary.tsv`; the collector preserves failed verifier summaries and marks the row nonzero if the verifier did not pass, if the verifier summary omits `schemaID: https://vifty.local/schemas/release-artifact-summary.schema.json`, if any verifier check was skipped or failed, if `expectedSHA` and `actualSHA` differ, if `expectedArtifactName` does not match the cask version, or if the verifier's `bundleVersion` / `caskVersion` does not match the installed app's `CFBundleShortVersionString`. If `--release-checklist` is supplied, the bundle also includes `release-checklist.md` and `release-checklist.tsv`; the collector marks the row nonzero if the checklist title version does not match the installed app or if required workflow/post-publication follow-up sections are missing. Release evidence review enforces the same install-provenance, release-summary, release-checklist, capabilities-contract, privacy-review, manifest, and checksum consistency rules by requiring `manifest.tsv` rows to match summary statuses and bundle-local output files, requiring every captured regular file except reviewer output to appear in `checksums.tsv`, and recomputing those entries. A blocked `diagnose` report exits nonzero but is still captured as useful evidence. The audit report is read-only and should declare `coolingCommandsRun: false`. The script does not call `prepare`, `run`, `restore-auto`, `setFixed`, `auto`, or any other fan-write command.

If a report needs direct helper fan probe output, run the helper probe explicitly through the collector:

```sh
sudo make validation-evidence VALIDATION_EVIDENCE_INCLUDE_PROBE_LOCAL=1
```

Review the bundle before sharing it publicly, especially any files named by `privacy-review.tsv`, then paste or attach the relevant files to the GitHub **Hardware Validation Report** issue template.

The helper probe fan rows include `hardwareMode`, `hardwareModeRawValue`, `hardwareModeKey`, and `targetRPM` fields in addition to current/min/max RPM. Use those fields to confirm whether Vifty and macOS agree about Auto, Forced, or System-managed fan state before and after a smoke test, including whether the machine reports uppercase `F{n}Md` or lowercase `F{n}md` fan mode keys.

Source-first and unsigned-dev `v1.1.1` hardware reports may leave release-artifact verifier evidence skipped or absent. Do not use those reports as proof of public binary trust; use them only for hardware behavior, agent readiness, helper telemetry, and manual smoke-test evidence.

Maintainers can review a captured bundle without rerunning any diagnostics:

```sh
make validation-evidence-review \
  VALIDATION_EVIDENCE_BUNDLE=.build/vifty-validation-<timestamp> \
  VALIDATION_EVIDENCE_REVIEW_MODE=supported-hardware \
  VALIDATION_EVIDENCE_REVIEW_SUMMARY=.build/vifty-validation-<timestamp>/review-result.json
```

`make validation-evidence-review` wraps `scripts/review-validation-evidence.sh`; use `VALIDATION_EVIDENCE_REVIEW_MODE=release` for installed public-release trust evidence and `VALIDATION_EVIDENCE_REVIEW_MODE=unsupported-hardware` for reports that prove unsupported machines block safely. The reviewer checks only captured files; it does not call `viftyctl`, `ViftyHelper`, `launchctl`, `codesign`, `stapler`, `spctl`, or fan-write commands. In release mode it requires the release artifact summary to identify the `release-artifact-summary.schema.json` contract and rejects `source-build-tag`, `source-first-unsigned-dev-zip`, local ad-hoc, unrecorded, or other install sources as release-trust proof. In unsupported-hardware mode, passing review is safe-block evidence only; it does not expand fan-control support. When `VALIDATION_EVIDENCE_REVIEW_SUMMARY` is supplied, it writes `review-result.json` with `schemaID: https://vifty.local/schemas/validation-review-result.schema.json`, the review mode, pass/fail status, install/source provenance fields, key diagnose decision fields, explicit manual smoke-test evidence, optional supervised agent-run smoke evidence, and any failures or warnings.

For a supported-hardware report, leave the default `VALIDATION_EVIDENCE_MANUAL_SMOKE_RESULT=not-recorded` until the GitHub issue template says **Passed and Auto restore confirmed**. After that, rerun the review with the issue URL or note:

```sh
make validation-evidence-review \
  VALIDATION_EVIDENCE_BUNDLE=.build/vifty-validation-<timestamp> \
  VALIDATION_EVIDENCE_REVIEW_MODE=supported-hardware \
  VALIDATION_EVIDENCE_MANUAL_SMOKE_RESULT=passed-auto-restored \
  VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE=<hardware-validation-issue-url> \
  VALIDATION_EVIDENCE_REVIEW_SUMMARY=.build/vifty-validation-<timestamp>/review-result.json
```

The supported-hardware smoke-test result values are `not-recorded`, `passed-auto-restored`, `skipped-blocked`, `skipped-unsupported`, and `failed`. Only `passed-auto-restored` can make a supported Apple Silicon MacBook Pro report count as validated hardware evidence; `failed`, `skipped-blocked`, or `skipped-unsupported` fail the supported-hardware review instead of being silently indexed as support.

If the supervised **viftyctl run smoke test** bundle is available, prefer the captured summary in the machine-readable review:

```sh
make validation-evidence-review \
  VALIDATION_EVIDENCE_BUNDLE=.build/vifty-validation-<timestamp> \
  VALIDATION_EVIDENCE_REVIEW_MODE=supported-hardware \
  VALIDATION_EVIDENCE_MANUAL_SMOKE_RESULT=passed-auto-restored \
  VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE=<hardware-validation-issue-url> \
  VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY=.build/vifty-agent-run-smoke-<timestamp>/agent-run-smoke-evidence-summary.json \
  VALIDATION_EVIDENCE_REVIEW_SUMMARY=.build/vifty-validation-<timestamp>/review-result.json
```

The agent-run smoke summary declares `schemaID: https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json`. The reviewer validates that schema identity and derives `agentRunSmokeResult` / `agentRunSmokeSource` from the captured file only after checking the adjacent smoke bundle: `manifest.tsv` must match the summary `commands[]`, each command's stdout/stderr/status file must exist and match its recorded status, and `checksums.tsv` must cover and recompute the summary, manifest, command stdout/stderr, and status files. When `rateLimitRetry.attempted=true`, the reviewer also requires the initial `viftyctl-run` JSON to be structured `PREPARE_RATE_LIMITED` cooldown evidence with `safeToProceed=false`, matching `retryAfterSeconds`, no lease prepared, no Auto restore attempted, and a nonzero exit status that matches the recorded `rateLimitRetry.initialExitStatus`; the final `run` proof must reference the `viftyctl-run-retry` stdout/stderr/status files. A passed captured summary must also report `coolingLeasePrepared=true`, `autoRestoreAttempted=true`, `autoRestoreSucceeded=true`, and `childExitCode=0` in its `run` object, so developer-workload proof includes the bounded lease and Auto-restore outcome rather than only the wrapper exit status. If only issue-template text is available, use `VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_RESULT=passed-auto-restored VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SOURCE=<hardware-validation-issue-url>#agent-run-smoke`.

The agent-run smoke result uses the same values as the manual smoke test and is preserved as developer-workload proof for the guarded `viftyctl run` lifecycle, but it does not replace `manualSmokeTestResult: "passed-auto-restored"` for validated hardware claims. A `failed` agent-run smoke result fails supported-hardware review so unsafe agent/build/test cooling evidence cannot be indexed as supported.

After several reports are reviewed, build a local index for maintainers:

```sh
scripts/summarize-validation-reports.sh --input .build/validation-reports \
  --output-json .build/validation-reports/compatibility-index.json \
  --output-tsv .build/validation-reports/compatibility-index.tsv \
  --output-markdown .build/validation-reports/compatibility-matrix.md
```

The index reads `review-result.json` files only and writes schema-backed JSON with `schemaID: https://vifty.local/schemas/validation-report-index.schema.json`. It requires each input review result to declare `schemaID: https://vifty.local/schemas/validation-review-result.schema.json`, then rejects malformed review results, non-read-only review results, review results that declare cooling commands ran, unsupported modes/statuses, unsupported install-source values, release-mode rows whose install source is source-first or otherwise not release-capable, invalid or missing required source SHA/checksum fields, mutable or missing source refs for source-build tag evidence, missing `daemonControlPathReady`, missing or unsupported `recommendedAgentAction`, missing or unsupported `recommendedRecoveryAction`, and contradictory passed results with failures. Valid index rows can show release-trust evidence, unsupported-hardware safe-block evidence, supported-hardware candidate evidence, and `validated-hardware-evidence` rows when the review result includes `manualSmokeTestResult: "passed-auto-restored"`, while preserving `installSource`, `sourceRef`, `sourceSHA`, `sourceArtifactName`, `sourceArtifactSHA256`, `modelFamily`, `recommendedAgentAction`, `recommendedRecoveryAction`, `daemonControlPathReady`, `agentRunSmokeResult`, and `agentRunSmokeSource` for compatibility-table filtering. `modelFamily` is derived from the model identifier prefix, for example `MacBookPro18`; use the summary fields `countsByModelFamily` and `validatedHardwareReportsByModelFamily` to group reviewed reports without manually scanning every row. The optional `--output-markdown` file is a conservative compatibility matrix draft generated from hardware rows only; it ignores release-trust rows for hardware status, keeps agent-run smoke separate from validated-hardware claims, and labels rows as validated only when manual smoke evidence passed. The JSON summary also includes counts by `recommendedAgentAction`, `recommendedRecoveryAction`, `safeToRequestCooling`, and `daemonControlPathReady` so maintainers can spot stop-before-cooling and helper-repair reports without scanning every row.

## Readiness Report

After installing a release build and approving the helper, run:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
```

The command is read-only. It gathers the daemon hardware snapshot, fan mode/target telemetry, macOS thermal pressure, and agent-control policy/status. It does not prepare a lease, restore Auto, or write SMC keys. If daemon snapshot or agent-control status reads fail, the command still emits JSON with `state: "blocked"`, explicit `daemonSnapshotAvailable` / `agentControlStatusAvailable` / `daemonControlPathReady` failure checks, and `recommendedRecoveryAction: "repairHelper"`. `ready` and `degraded` reports exit `0`; `blocked` reports exit `75` after printing JSON. Agents should use `safeToRequestCooling`, `daemonControlPathReady`, `recommendedAgentAction`, and `recommendedRecoveryAction` as the direct machine-readable decision fields.

Interpret `state` as:

- `ready` — all required checks pass; build/test agents may request bounded cooling.
- `degraded` — required safety checks pass, but a warning needs attention, such as an active lease, serious/unknown thermal pressure, missing fan mode telemetry, or System/protected fan mode.
- `blocked` — an agent should not request cooling. Common causes are unavailable daemon/helper telemetry, unsupported hardware, disabled agent policy, missing temperature sensors, missing controllable fans, invalid or duplicate controllable fan IDs, invalid fan RPM ranges, or critical thermal pressure.

Attach the full JSON to validation notes. The most important fields are:

- `modelIdentifier`
- `isAppleSilicon`
- `isMacBookPro`
- `thermalPressure`
- `recommendedAgentAction`
- `recommendedRecoveryAction`
- `safeToRequestCooling`
- `daemonControlPathReady`
- `fanCount`
- `controllableFanCount`
- `temperatureSensorCount`
- `fans[].hardwareMode`
- `fans[].hardwareModeRawValue`
- `fans[].hardwareModeKey`
- `fans[].targetRPM`
- `agentControl.policy`
- `daemonSnapshotError`
- `agentControlStatusError`
- `checks[]`

## Release Validation Matrix

Collect at least one passing GitHub hardware-validation report for each available model family before calling a release broadly validated.

| Hardware | macOS | Expected result | Evidence |
|---|---|---|---|
| M1 Pro/Max MacBook Pro | macOS 15+ | `ready` or explained `degraded` | `viftyctl diagnose --json`, `ViftyHelper probeLocal` |
| M2 Pro/Max MacBook Pro | macOS 15+ | `ready` or explained `degraded` | `viftyctl diagnose --json`, `ViftyHelper probeLocal` |
| M3 Pro/Max MacBook Pro | macOS 15+ | `ready` or explained `degraded` | `viftyctl diagnose --json`, `ViftyHelper probeLocal` |
| M4 Pro/Max MacBook Pro | macOS 15+ | `ready` or explained `degraded` | `viftyctl diagnose --json`, `ViftyHelper probeLocal` |
| M5 Pro/Max MacBook Pro | macOS 15+ | `ready` or explained `degraded` | `viftyctl diagnose --json`, `ViftyHelper probeLocal` |
| Apple Silicon non-MacBook-Pro | macOS 15+ | `blocked` | `viftyctl diagnose --json` |
| Intel MacBook Pro | macOS 15+ if available | `blocked` | `viftyctl diagnose --json` |

## M1 Pro Local Validation Quick Path

Use this path for the available `MacBookPro18,1` / M1 Pro machine before changing the M1 Pro/Max row from **Needs manual smoke** to validated hardware evidence. Keep the installed app, helper, collected bundle, reviewed `sourceSHA`, and compatibility index aligned with the exact source build being validated.

1. Collect the read-only bundle with explicit source provenance. For current `main` or local ad-hoc builds, use the exact commit SHA of the installed app rather than a release-tag install source:

   ```sh
   scripts/collect-validation-evidence.sh --app /Applications/Vifty.app \
     --install-source local-ad-hoc-build \
     --source-ref main \
     --source-sha <40-character-source-sha>
   ```

2. Collect the read-only helper probe when supported readiness is still safe:

   ```sh
   sudo scripts/collect-validation-evidence.sh --app /Applications/Vifty.app \
     --install-source local-ad-hoc-build \
     --source-ref main \
     --source-sha <40-character-source-sha> \
     --include-probe-local
   ```

3. Run the daemon-backed manual smoke below only if `diagnose --json` is `ready` or safely `degraded`, `safeToRequestCooling=true`, and `daemonControlPathReady=true`. The `prepare` and `restore-auto` commands write fan state through Vifty's bounded daemon path; the diagnose and probe commands are read-only.

4. Keep Fixed and Curve smoke human-supervised in the app UI: apply one conservative Fixed target, collect diagnose/probe evidence, restore Auto, then repeat with one conservative Curve profile and restore Auto again. Do not automate UI clicking, raw `ViftyHelper setFixed`, raw `ViftyHelper auto`, or third-party SMC writes for support promotion.

5. After the issue/template note records **Passed and Auto restore confirmed**, rerun the reviewer with `VALIDATION_EVIDENCE_MANUAL_SMOKE_RESULT=passed-auto-restored`, then regenerate the compatibility index and matrix. A supervised agent-run smoke bundle can be attached as developer-workload proof, but it does not replace manual Auto/Fixed/Curve smoke for `validated-hardware-evidence`.

## Manual Fan Write Smoke Test

Only run this on supported Apple Silicon MacBook Pro hardware after saving the readiness report.

1. Record the baseline:

   ```sh
   sudo /Applications/Vifty.app/Contents/MacOS/ViftyHelper probeLocal
   ```

2. Start a short lease:

   ```sh
   /Applications/Vifty.app/Contents/MacOS/viftyctl prepare --workload test --duration 2m --max-rpm-percent 55 --reason "release smoke test" --json
   ```

3. Confirm fan target/mode changed without exceeding per-fan min/max:

   ```sh
   /Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
   sudo /Applications/Vifty.app/Contents/MacOS/ViftyHelper probeLocal
   ```

4. Restore Auto:

   ```sh
   /Applications/Vifty.app/Contents/MacOS/viftyctl restore-auto --reason "release smoke test complete" --json
   ```

5. Confirm Auto restore:

   ```sh
   /Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
   sudo /Applications/Vifty.app/Contents/MacOS/ViftyHelper probeLocal
   ```

If any step reports critical thermal pressure, missing sensors, missing controllable fans, invalid or duplicate fan IDs, or invalid RPM ranges, stop and keep the machine under macOS automatic fan control.

## Supervised Agent Run Smoke Test

The manual smoke test proves direct prepare/restore behavior. For developer-workload evidence, also run one supervised `viftyctl run` smoke test on supported Apple Silicon MacBook Pro hardware after readiness is `ready` or safely `degraded`.

If this follows the manual smoke test above, wait for the advertised prepare cooldown before starting the run smoke. Use `capabilities --json` or `status --json` to read `policy.prepareCooldownSeconds`; the default policy is 30 seconds. If the first run attempt returns `PREPARE_RATE_LIMITED`, keep that JSON as evidence, wait for `retryAfterSeconds`, and retry once. Do not treat the first cooldown response as a failed agent-run smoke test, and do not busy-loop retries. The collector below handles exactly one structured cooldown retry automatically: it records the initial response in `viftyctl-run.json`, records retry metadata in `rateLimitRetry`, waits once, and stores the final proof in `viftyctl-run-retry.json`.

The preferred captured path for installed testers is:

```sh
/Applications/Vifty.app/Contents/Resources/collect-agent-run-smoke-evidence.sh \
  --viftyctl /Applications/Vifty.app/Contents/MacOS/viftyctl
```

When validating directly from a clean source checkout before installing an app
bundle, use the current-build Make target:

```sh
make agent-run-smoke-evidence-current-build
```

This requires a clean git worktree, builds `.build/Vifty.app`, and runs the
smoke through `.build/Vifty.app/Contents/MacOS/viftyctl` so the evidence follows
the current source checkout. The smoke summary records `installSource`, `sourceRef`, `sourceSHA`, and optional source artifact fields; this target sets
`installSource=local-ad-hoc-build`, the current git ref, and the current
40-character source SHA automatically. If you are intentionally validating an
already installed app from a source checkout, use the generic supervised Make
target with explicit provenance and the installed `viftyctl` path:

```sh
make agent-run-smoke-evidence \
  VIFTYCTL=/Applications/Vifty.app/Contents/MacOS/viftyctl \
  AGENT_RUN_SMOKE_INSTALL_SOURCE=local-ad-hoc-build \
  AGENT_RUN_SMOKE_SOURCE_REF=<ref> \
  AGENT_RUN_SMOKE_SOURCE_SHA=<40-char-sha>
```

The Make target keeps the default `/bin/sleep 5`, `2m`, `55%`, and
`agent run smoke test` reason used by the collector. Set
`AGENT_RUN_SMOKE_OUTPUT=<dir>`, `AGENT_RUN_SMOKE_DURATION=<duration>`,
`AGENT_RUN_SMOKE_MAX_RPM_PERCENT=<percent>`, `AGENT_RUN_SMOKE_REASON=<text>`,
`AGENT_RUN_SMOKE_AUDIT_LIMIT=<count>`, or
`AGENT_RUN_SMOKE_SOURCE_ARTIFACT=<zip-or-artifact>` only for a supervised validation
scenario that needs different bounded values or stronger source provenance. The raw
`scripts/collect-agent-run-smoke-evidence.sh` path remains available for
advanced/manual runs.

This writes an agent-run smoke bundle with `manifest.tsv`,
`agent-run-smoke-evidence-summary.json`, the `viftyctl run` stdout/stderr/status
when the run is attempted, optional `viftyctl-run-retry.*` files after a
structured `PREPARE_RATE_LIMITED` cooldown, and follow-up
capabilities/status/audit/diagnose files. It is not read-only when readiness is
safe because it requests one bounded `viftyctl run --json` cooling lease for
`/bin/sleep 5` by default, with at most one cooldown retry when the daemon tells
it exactly how long to wait. It records the run proof fields
`coolingLeasePrepared`, `autoRestoreAttempted`, `autoRestoreSucceeded`, and
`childExitCode` in the summary; on successful child runs these are derived from
`viftyctl run` exit semantics and the advertised safe `runLifecycle` contract
when child stdout is not JSON. It stops before `viftyctl run` when
`pre-capabilities.json` does not advertise
`policyStatusAvailable: true`, the `run` command, `test` workload, and safe `runLifecycle` contract, or when readiness is
blocked. In those cases it writes a blocked summary, captures read-only
status/audit follow-up, and exits `75`.

To run the same smoke manually:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl run \
  --workload test \
  --duration 2m \
  --max-rpm-percent 55 \
  --reason "agent run smoke test" \
  --json \
  -- /bin/sleep 5
```

Then collect the read-only follow-up:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl capabilities --json
/Applications/Vifty.app/Contents/MacOS/viftyctl status --json
/Applications/Vifty.app/Contents/MacOS/viftyctl audit --limit 20 --json
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
```

Paste the run stdout/stderr, child exit code, restore result, any `PREPARE_RATE_LIMITED` / `retryAfterSeconds` JSON from the first cooldown response or the collector's `rateLimitRetry` object, and the follow-up capabilities/status/audit/diagnose output into the hardware report. This proves the supervised agent/build/test path advertises the safe `runLifecycle` contract, `policyStatusAvailable: true`, and policy/metadata limits, validates the child command before cooling, creates one bounded lease, restores Auto after the child exits, and leaves read-only audit evidence. Do not run this smoke test when readiness is `blocked`; use the blocked diagnose JSON as evidence instead.

## Signing Validation

For release builds, prefer the signed/notarized workflow in [release.md](release.md). To smoke-test the signing path locally, verify the daemon trust boundary:

```sh
make app CONFIGURATION=release SIGNING_IDENTITY="<Developer ID Application identity>" VIFTY_XPC_ALLOWED_TEAM_ID="<TEAMID>"
plutil -p .build/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
codesign --verify --deep --strict .build/Vifty.app
codesign -dvvv .build/Vifty.app 2>&1 | grep TeamIdentifier
```

The LaunchDaemon plist must contain the same `VIFTY_XPC_ALLOWED_TEAM_ID` as the signed app's TeamIdentifier. Ad-hoc local builds may leave the value empty.
