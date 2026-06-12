# Compatibility Status

Vifty's compatibility claims are evidence-based. A model family is considered validated only when a real machine report includes the read-only readiness JSON, helper fan probe output, install source, macOS version, bundle/signing evidence, and manual smoke-test result when the hardware is supported.

Use the GitHub **Hardware Validation Report** issue template to contribute evidence. The validation procedure lives in [hardware-validation.md](hardware-validation.md), and `scripts/collect-validation-evidence.sh` can gather the standard read-only evidence bundle from an installed app.

Install source matters. For `v1.1.0`, source builds from the tag and `Vifty-v1.1.0-unsigned-dev.zip` reports can contribute hardware compatibility evidence, but they are not Developer ID signed, notarized, Homebrew-trusted, or trusted public binary evidence.

## Current Claim

Vifty targets Apple Silicon MacBook Pro models on macOS 15+. That is the intended support scope, not a blanket guarantee for every machine in that family.

Until enough public reports exist, treat each model family as **needs validation**. Unsupported Macs should remain under macOS automatic fan control. The canonical unsupported-machine behavior is documented in [unsupported-hardware.md](unsupported-hardware.md).

## Status Table

| Hardware family | Public status | Required evidence |
| --- | --- | --- |
| M1 Pro/Max MacBook Pro | Needs validation | `viftyctl diagnose --json`, `ViftyHelper probeLocal`, manual smoke test if `ready` or safely `degraded` |
| M2 Pro/Max MacBook Pro | Needs validation | `viftyctl diagnose --json`, `ViftyHelper probeLocal`, manual smoke test if `ready` or safely `degraded` |
| M3 Pro/Max MacBook Pro | Needs validation | `viftyctl diagnose --json`, `ViftyHelper probeLocal`, manual smoke test if `ready` or safely `degraded` |
| M4 Pro/Max MacBook Pro | Needs validation | `viftyctl diagnose --json`, `ViftyHelper probeLocal`, manual smoke test if `ready` or safely `degraded` |
| M5 Pro/Max MacBook Pro | Needs validation | `viftyctl diagnose --json`, `ViftyHelper probeLocal`, manual smoke test if `ready` or safely `degraded` |
| Apple Silicon non-MacBook-Pro | Expected blocked | `viftyctl diagnose --json` showing the hardware gate |
| Intel MacBook Pro | Expected blocked | `viftyctl diagnose --json` showing the Apple Silicon gate |
| Other Macs | Unsupported | Do not run manual fan writes |

## Evidence Rules

- Always capture `viftyctl diagnose --json` before any manual smoke test. It is read-only and should say whether the machine is `ready`, `degraded`, or `blocked`.
- Always capture `sudo /Applications/Vifty.app/Contents/MacOS/ViftyHelper probeLocal` for supported MacBook Pro validation, because it shows fan count, per-fan min/max RPM, `hardwareMode`, `hardwareModeRawValue`, `hardwareModeKey`, and `targetRPM` telemetry.
- Do not run the manual smoke test when readiness is `blocked`, when thermal pressure is critical, when fans/sensors are missing, or when RPM ranges look invalid. Follow [unsupported-hardware.md](unsupported-hardware.md) for unsupported-hardware safe-block reports.
- A `degraded` report can still be useful, but the reason must be explained. Examples include missing optional fan mode telemetry, System-managed fan mode, or an already-active lease.
- For `v1.1.0`, record whether the install source was a source build from the tag or the unsigned-dev convenience zip. Treat those as compatibility-only evidence, not release-trust evidence.
- A Homebrew or GitHub Release report should include the collector's `release-artifact-summary.json` / `release-artifact-summary.tsv` when `--release-summary` is supplied, `release-checklist.md` / `release-checklist.tsv` when `--release-checklist` is supplied, `review-summary.tsv`, `review-summary.json`, `bundle-executables.tsv`, `schema-resources.tsv`, `capabilities-schema-resources.tsv`, `capabilities-contract.tsv`, `viftyctl-audit.json`, the app/CLI/helper/daemon signing files, notarization/Gatekeeper files, bundled LaunchDaemon plist, and whether the app was installed from the expected `Vifty-v<version>.zip` artifact. The release-summary row should be `0` only when the verifier passed, matched the installed app version, did not skip or fail individual checks, and kept SHA/artifact-name fields consistent. The release-checklist row should be `0` only when the checklist version matches the installed app and includes the required post-publication trust follow-up. The capabilities-contract row should be `0` so agent wrappers can rely on safe `runLifecycle`, direct prepare/restore lifecycle, and force-retry discovery fields.
- Before adding a report link to this page, run `scripts/review-validation-evidence.sh --bundle <evidence-dir> --mode supported-hardware --summary <evidence-dir>/review-result.json` for supported Apple Silicon MacBook Pro claims, `--mode unsupported-hardware` for expected-blocked reports, or `--mode release` for installed public-release trust evidence. The reviewer is read-only, checks only captured files, and can write a machine-readable `review-result.json` pass/fail summary. After the issue template records **Passed and Auto restore confirmed**, rerun supported-hardware review with `--manual-smoke-result passed-auto-restored --manual-smoke-source <issue-url>` so the report can be indexed as validated hardware evidence.
- Use `scripts/summarize-validation-reports.sh --input <reports-dir> --output-json <reports-dir>/compatibility-index.json --output-tsv <reports-dir>/compatibility-index.tsv` to build a schema-backed report index from valid `review-result.json` files. The JSON index declares `schemaID: https://vifty.local/schemas/validation-report-index.schema.json`; the indexer rejects malformed, non-read-only, cooling-mutating, unsupported-mode, or contradictory passed review results. Supported-hardware rows are intentionally labeled `supported-hardware-evidence-needs-manual-smoke` until the review result includes `manualSmokeTestResult: "passed-auto-restored"`, at which point they become `validated-hardware-evidence`.

## Before Broad Support Claims

Before calling a release broadly Apple Silicon MacBook Pro ready, collect at least:

- five validated Apple Silicon MacBook Pro reports across multiple model families;
- at least two reports from M3/M4 or newer Pro/Max machines;
- one clean Homebrew cask install report from a fresh machine;
- one report proving unsupported hardware blocks safely.

Do not add a README compatibility badge or broad marketing claim until the status table has real report links.
