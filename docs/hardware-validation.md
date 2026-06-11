# Hardware Validation

Vifty should earn trust with repeatable hardware evidence, not guesses. Use this checklist when validating a release on Apple Silicon MacBook Pro hardware or when collecting compatibility reports from contributors.

Contributor reports should use the GitHub **Hardware Validation Report** issue template. The template asks for the exact readiness JSON, local helper fan probe output, model identifier, install source, and manual smoke-test result so compatibility claims remain auditable.

The public compatibility status is tracked in [compatibility.md](compatibility.md). Do not treat the intended support scope as broad validation until the compatibility page links to real reports. Unsupported machines should follow [unsupported-hardware.md](unsupported-hardware.md): collect read-only evidence, expect a blocked report, and do not run manual fan-write smoke tests.

For `v1.1.0`, record whether the app came from a source build from the tag or the optional `Vifty-v1.1.0-unsigned-dev.zip` tester artifact. Those reports can still prove hardware behavior, but they do not prove Developer ID signing, notarization, Homebrew trust, or trusted binary distribution. Future Developer ID or Homebrew reports should choose the corresponding install source only after that trusted-binary lane exists.

## Evidence Collector

For release candidates and contributor reports, the easiest read-only collection path is:

```sh
scripts/collect-validation-evidence.sh --app /Applications/Vifty.app
```

When validating a published release, include the verifier summary too:

```sh
scripts/collect-validation-evidence.sh --app /Applications/Vifty.app \
  --release-summary ./Vifty-v<version>-artifact-summary.json \
  --release-checklist ./Vifty-v<version>-release-checklist.md
```

The script writes a local evidence bundle under `.build/vifty-validation-<timestamp>/` by default. It captures system metadata without the local hostname, bundle Info.plist, bundled executable hashes, bundled JSON Schema resource hashes, bundled LaunchDaemon plist and TeamID setting, launchctl daemon status, app/CLI/helper/daemon signing checks, notarization/Gatekeeper checks, `viftyctl capabilities --json`, `viftyctl status --json`, `viftyctl diagnose --json`, and `viftyctl audit --limit 20 --json`, then writes `manifest.tsv` with each command's exit status, `bundle-executables.tsv` with installed app/helper/daemon/CLI SHA-256 digests and bundle paths, `schema-resources.tsv` with installed schema SHA-256 digests and bundle paths, `capabilities-schema-resources.tsv` proving the CLI advertises those installed schema resource paths, `capabilities-contract.tsv` proving the CLI advertises the safe `runLifecycle` and `supportsForceRetry` contract used by guarded workload wrappers, `privacy-review.tsv` to flag likely hostnames, `/Users/...` paths, serial-number labels, or hardware UUID labels before sharing, `review-summary.tsv` for reviewers, `review-summary.json` for automation, and `checksums.tsv` with SHA-256 digests and byte counts for the captured files. If `--release-summary` is supplied, the bundle also includes `release-artifact-summary.json` and `release-artifact-summary.tsv`; the collector preserves failed verifier summaries and marks the row nonzero if the verifier did not pass, if the verifier summary omits `schemaID: https://vifty.local/schemas/release-artifact-summary.schema.json`, if any verifier check was skipped or failed, if `expectedSHA` and `actualSHA` differ, if `expectedArtifactName` does not match the cask version, or if the verifier's `bundleVersion` / `caskVersion` does not match the installed app's `CFBundleShortVersionString`. If `--release-checklist` is supplied, the bundle also includes `release-checklist.md` and `release-checklist.tsv`; the collector marks the row nonzero if the checklist title version does not match the installed app or if required workflow/post-publication follow-up sections are missing. Release evidence review enforces the same release-summary, release-checklist, capabilities-contract, privacy-review, and checksum consistency rules by requiring every captured regular file except reviewer output to appear in `checksums.tsv` and recomputing those entries. A blocked `diagnose` report exits nonzero but is still captured as useful evidence. The audit report is read-only and should declare `coolingCommandsRun: false`. The script does not call `prepare`, `run`, `restore-auto`, `setFixed`, `auto`, or any other fan-write command.

If a report needs direct helper fan probe output, run the helper probe explicitly through the collector:

```sh
sudo scripts/collect-validation-evidence.sh --app /Applications/Vifty.app --include-probe-local
```

Review the bundle before sharing it publicly, especially any files named by `privacy-review.tsv`, then paste or attach the relevant files to the GitHub **Hardware Validation Report** issue template.

The helper probe fan rows include `hardwareMode`, `hardwareModeRawValue`, and `targetRPM` fields in addition to current/min/max RPM. Use those fields to confirm whether Vifty and macOS agree about Auto, Forced, or System-managed fan state before and after a smoke test.

Source-first and unsigned-dev `v1.1.0` hardware reports may leave release-artifact verifier evidence skipped or absent. Do not use those reports as proof of public binary trust; use them only for hardware behavior, agent readiness, helper telemetry, and manual smoke-test evidence.

Maintainers can review a captured bundle without rerunning any diagnostics:

```sh
scripts/review-validation-evidence.sh --bundle .build/vifty-validation-<timestamp> \
  --mode supported-hardware \
  --summary .build/vifty-validation-<timestamp>/review-result.json
```

Use `--mode release` for installed public-release trust evidence and `--mode unsupported-hardware` for reports that prove unsupported machines block safely. The reviewer checks only captured files; it does not call `viftyctl`, `ViftyHelper`, `launchctl`, `codesign`, `stapler`, `spctl`, or fan-write commands. In release mode it requires the release artifact summary to identify the `release-artifact-summary.schema.json` contract. In unsupported-hardware mode, passing review is safe-block evidence only; it does not expand fan-control support. When `--summary` is supplied, it writes `review-result.json` with the review mode, pass/fail status, key diagnose decision fields, explicit manual smoke-test evidence, and any failures or warnings.

For a supported-hardware report, leave the default `--manual-smoke-result not-recorded` until the GitHub issue template says **Passed and Auto restore confirmed**. After that, rerun the review with the issue URL or note:

```sh
scripts/review-validation-evidence.sh --bundle .build/vifty-validation-<timestamp> \
  --mode supported-hardware \
  --manual-smoke-result passed-auto-restored \
  --manual-smoke-source <hardware-validation-issue-url> \
  --summary .build/vifty-validation-<timestamp>/review-result.json
```

The supported-hardware smoke-test result values are `not-recorded`, `passed-auto-restored`, `skipped-blocked`, `skipped-unsupported`, and `failed`. Only `passed-auto-restored` can make a supported Apple Silicon MacBook Pro report count as validated hardware evidence; `failed`, `skipped-blocked`, or `skipped-unsupported` fail the supported-hardware review instead of being silently indexed as support.

After several reports are reviewed, build a local index for maintainers:

```sh
scripts/summarize-validation-reports.sh --input .build/validation-reports \
  --output-json .build/validation-reports/compatibility-index.json \
  --output-tsv .build/validation-reports/compatibility-index.tsv
```

The index reads `review-result.json` files only. It rejects malformed review results, non-read-only review results, review results that declare cooling commands ran, unsupported modes/statuses, and contradictory passed results with failures. Valid index rows can show release-trust evidence, unsupported-hardware safe-block evidence, supported-hardware candidate evidence, and `validated-hardware-evidence` rows when the review result includes `manualSmokeTestResult: "passed-auto-restored"`.

## Readiness Report

After installing a release build and approving the helper, run:

```sh
/Applications/Vifty.app/Contents/MacOS/viftyctl diagnose --json
```

The command is read-only. It gathers the daemon hardware snapshot, fan mode/target telemetry, macOS thermal pressure, and agent-control policy/status. It does not prepare a lease, restore Auto, or write SMC keys. If daemon snapshot or agent-control status reads fail, the command still emits JSON with `state: "blocked"` and explicit `daemonSnapshotAvailable` / `agentControlStatusAvailable` failure checks. `ready` and `degraded` reports exit `0`; `blocked` reports exit `75` after printing JSON. Agents should use `safeToRequestCooling` and `recommendedAgentAction` as the direct machine-readable decision fields.

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
- `safeToRequestCooling`
- `fanCount`
- `controllableFanCount`
- `temperatureSensorCount`
- `fans[].hardwareMode`
- `fans[].hardwareModeRawValue`
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

## Signing Validation

For release builds, prefer the signed/notarized workflow in [release.md](release.md). To smoke-test the signing path locally, verify the daemon trust boundary:

```sh
make app CONFIGURATION=release SIGNING_IDENTITY="<Developer ID Application identity>" VIFTY_XPC_ALLOWED_TEAM_ID="<TEAMID>"
plutil -p .build/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
codesign --verify --deep --strict .build/Vifty.app
codesign -dvvv .build/Vifty.app 2>&1 | grep TeamIdentifier
```

The LaunchDaemon plist must contain the same `VIFTY_XPC_ALLOWED_TEAM_ID` as the signed app's TeamIdentifier. Ad-hoc local builds may leave the value empty.
