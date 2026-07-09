# Release Process

Vifty has two release modes:

- **Source-first release:** used while the project does not currently have Apple Developer Program credentials. The GitHub Release is the source tag plus release notes, with an optional clearly marked unsigned tester app zip.
- **Developer ID release:** future trusted binary lane. Artifacts should be Developer ID signed, notarized, stapled, and tied to the same TeamID that the privileged daemon enforces over XPC.

For the current public release trust state, see [release-status.md](release-status.md). Keep that page updated when a release workflow fails, succeeds, or when the cask checksum is updated.

## Source-First Release Mode

Use this mode when Apple Developer Program credentials are unavailable. It does not create a trusted public binary and must not claim Developer ID signing, notarization, stapling, Gatekeeper approval, or Homebrew trust.

Sparkle auto-update is future Developer ID release work. Do not enable Sparkle for source-first or unsigned-dev artifacts. The updater requirements and test plan live in [auto-update.md](auto-update.md).

The required source-first release-note warning is:

> This is a source-first release. Vifty v<version> does not yet include a Developer ID signed or notarized public binary because the project does not currently have Apple Developer Program credentials.
>
> A convenience unsigned `.app` build is attached for testers who understand macOS Gatekeeper warnings and prefer not to build locally. For the most trusted path, build from source.

Source-first checklist:

1. Run the local verification suite:

   ```sh
   make verify-full
   ```

2. Generate source-first release notes:

   ```sh
   RELEASE_VERSION=<version> make source-first-release-notes
   ```

   The generated notes include a **Source Provenance** section with the source ref and immutable commit SHA. The Makefile target resolves `v<version>` by default, so fetch tags first if needed. For an unpublished candidate, intentionally override the ref:

   ```sh
   SOURCE_FIRST_SOURCE_REF=<candidate-ref-or-sha> RELEASE_VERSION=<version> make source-first-release-notes
   ```

   Keep any later `main` commits described as post-release hardening until a future release is cut.

3. Optionally build the unsigned tester artifact:

   ```sh
   git fetch origin main --tags
   git checkout v<version>
   make unsigned-dev-artifact
   ```

   The only acceptable unsigned tester names are:

   - `Vifty-v<version>-unsigned-dev.zip`
   - `Vifty-v<version>-unsigned-dev.zip.sha256`

   The unsigned-dev zip is valid only with its `.sha256` sidecar, and the SHA-256 digest in that sidecar must match the zip bytes.

   The Makefile target requires the current source to match `v<version>` by default. If you are building from an unpublished candidate, run the script directly with `--require-source-ref <candidate-ref-or-sha>` or set `UNSIGNED_DEV_SOURCE_REF=<candidate-ref-or-sha>` intentionally. Do not build a `Vifty-v<version>-unsigned-dev.zip` from later `main` hardening, and do not use `Vifty-v<version>.zip` or `Vifty-v<version>.zip.sha256` for an unsigned build. Those names are reserved for the future Developer ID signed and notarized artifact.

4. Before pushing the source tag, optionally confirm that the tag or candidate commit matches the intended source ref:

   ```sh
   git fetch origin main --tags
   scripts/check-release-readiness.sh \
     --mode source-first \
     --version <version> \
     --repo Reedtrullz/Vifty \
     --require-source-ref <candidate-ref-or-sha> \
     --json
   ```

   Use a moving branch such as `origin/main` only while it is intentionally the release candidate. After publication, `main` may move on; do not compare an already-published source-first tag to `origin/main` unless that is still the intended release commit.

5. Push the source tag and create or update the GitHub Release with the source-first notes, including the generated immutable source provenance. The unsigned-dev zip/checksum are optional tester convenience assets only; if attached, the `.sha256` digest must match the zip bytes.
6. Confirm published source-first readiness:

   ```sh
   git fetch origin main --tags
   RELEASE_VERSION=<version> make source-first-readiness
   ```

   If you need an immutable source-ref check after publication, use the release commit SHA rather than a moving branch.

7. Keep `Casks/vifty.rb` disabled for the source-first release. Do not update its checksum, re-enable it, or point the cask at the unsigned-dev artifact.

## Developer ID Release Mode

Use this mode only after the intended personal Apple Developer team is active and Vifty is ready to cross from source-first distribution into trusted-binary release claims.

### Pending Developer ID Account Setup

While the intended personal Apple Developer team is pending, keep Vifty in source-first mode. Do not use a different organization's Developer ID certificate unless that organization is intentionally meant to own Vifty's public signing identity, release trust, Homebrew trust, support burden, and revocation risk.

Preparation that is safe before Apple activates the team:

1. Keep the Developer ID workflow strict and unrun for public trust claims.
2. Keep `Casks/vifty.rb` disabled.
3. Keep source-first and unsigned-dev release wording intact.
4. Keep Sparkle updater keys out of `Resources/Info.plist`.
5. Prepare GitHub secret names only; do not commit certificate material, `.p12` files, app-specific passwords, or exported secret values.
6. After the team becomes active, create the Developer ID Application certificate under the intended personal team, configure the secrets below, run the manual local signing smoke test, then use the normal Developer ID release checklist.

## Required GitHub Secrets

Configure these repository secrets before running the `Release` workflow:

- `APPLE_TEAM_ID` — Apple Developer TeamID used for signing and XPC allowlisting.
- `APPLE_ID` — Apple ID email for `xcrun notarytool`.
- `APPLE_APP_SPECIFIC_PASSWORD` — app-specific password for notarization.
- `DEVELOPER_ID_APPLICATION_IDENTITY` — exact codesign identity, for example `Developer ID Application: Example, Inc. (TEAMID)`.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64` — base64-encoded `.p12` Developer ID Application certificate.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD` — password for the `.p12`.

## Developer ID Version Requirements

Before tagging a Developer ID release, update all trusted-binary release-facing versions to the same value:

- `Resources/Info.plist` `CFBundleShortVersionString`
- `Casks/vifty.rb` `version`
- Git tag, formatted as `v<version>`

The release workflow fails if the tag-derived release version, bundle version, cask version, release artifact URL, cask SHA shape, cask signing metadata, privileged-helper cleanup path, TeamID-gated daemon build configuration, notarization/stapling workflow gates, release verifier signature/notarization checks, Gatekeeper assessment, or GitHub Release asset publication does not align. The workflow must not pass verifier skip flags that disable public signature or notarization checks. The cask must not declare `signing_identity identity: "-"`, and its uninstall caveats must remove `/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon`. Update the Homebrew cask checksum with `scripts/update-cask-checksum.sh` after the workflow publishes the final notarized zip and checksum, then run `scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"` to verify the published artifact still matches the cask and passes signing, stapling, and Gatekeeper checks.

The notarized release asset is named `Vifty-v<version>.zip`; `Casks/vifty.rb` must point at the same name.

## Developer ID Release Checklist

1. Confirm the release secrets are configured:

   ```sh
   scripts/check-release-secrets.sh --repo Reedtrullz/Vifty
   ```

   This checks only secret names, not values. It should report all required Developer ID and notarization secret names before a release tag is pushed or a failed release workflow is rerun.

2. Confirm the read-only release readiness preflight. Fetch the intended release source first so the preflight can reject stale local refs:

   ```sh
   git fetch origin main --tags
   scripts/check-release-readiness.sh \
     --mode developer-id \
     --version <version> \
     --repo Reedtrullz/Vifty \
     --require-source-ref origin/main
   ```

   This validates local release metadata, optionally checks that the release tag commit matches the intended source ref, checks source CI for the release commit, checks the Release workflow result for the tag, checks required release secret names, and inspects the GitHub Release asset list. Its JSON output declares `schemaID: https://vifty.local/schemas/release-readiness.schema.json` and `releaseMode: "developer-id"` so release evidence can reject drift. Before the tag exists, this may report a missing source-CI/tag check; before publication it may still report a missing or failed Release workflow and missing GitHub Release. If `--require-source-ref` is supplied and the tag points at an older commit than the intended release branch, the preflight blocks with `release-source-ref` before anyone promotes a stale source candidate. After publication it should pass only when source-ref alignment, source CI, Release workflow status, release secrets, and the zip, checksum, artifact summary, and release checklist assets are present.

3. Confirm the local tree is clean and tests pass:

   ```sh
   RELEASE_METADATA_MODE=developer-id make verify-full
   ```

4. Update `CHANGELOG.md`: move `Unreleased` entries under the new version and date.
5. Update `Resources/Info.plist` and `Casks/vifty.rb` to the release version. Remove the cask `disable!` stanza only for the Developer ID/notarized release lane, after the canonical `Vifty-v<version>.zip` artifact and release verifier are ready.
6. Commit the release prep. The cask checksum can be updated in a follow-up commit after the notarized artifact exists.
7. Tag the commit:

   ```sh
   git tag v<version>
   git push origin main --tags
   ```

8. Watch the `Release` workflow. It will:

   - validate tag and bundle versions;
   - validate that release metadata and the cask artifact URL agree;
   - import the Developer ID Application certificate into a temporary keychain;
   - run the full XCTest suite with an isolated SwiftPM build path;
   - build with `SIGNING_IDENTITY` and `VIFTY_XPC_ALLOWED_TEAM_ID`;
   - verify signing identifiers and TeamID;
   - submit the app to Apple notarization;
   - staple the notarization ticket;
   - zip `Vifty.app` as `Vifty-v<version>.zip`;
   - verify the generated zip artifact against its just-created checksum, signing TeamID, stapling, Gatekeeper state, and bundled schema resources;
   - write `Vifty-v<version>-artifact-summary.json`;
   - write `Vifty-v<version>-release-checklist.md`;
   - publish the zip, SHA-256 checksum, verification summary, and release checklist to the GitHub Release;
   - prepend the release checklist to generated GitHub Release notes.

9. Update `Casks/vifty.rb` with the SHA-256 checksum from the release artifact:

   ```sh
   scripts/update-cask-checksum.sh \
     --checksum-file ./Vifty-v<version>.zip.sha256 \
     --version <version>
   ```

   The updater accepts the normal `shasum -a 256` output from the release workflow, requires the checksum artifact name to match the cask version, and re-runs release metadata validation before and after editing the cask.

10. Verify the public artifact and cask agree:

   ```sh
   scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"
   ```

   This downloads the cask URL unless `--artifact <zip>` is provided, checks the SHA-256, extracts `Vifty.app`, verifies bundle version, required executables, bundled `Contents/Resources/schemas` JSON Schemas including stable `$schema` and `$id` values for release-readiness, release-artifact-summary, agent-cooling evidence summary/review, agent-run smoke evidence summary, validation-report-index, validation-review-result, and `viftyctl` contracts, verifies the bundled read-only and supervised agent evidence collector scripts, validates plist files, checks Developer ID TeamID alignment including the LaunchDaemon `VIFTY_XPC_ALLOWED_TEAM_ID`, validates stapling, and runs Gatekeeper assessment. The release workflow runs the same verifier before publishing with `--expected-sha` because the final cask checksum follow-up commit does not exist yet, and publishes the verifier's JSON summary as release evidence. The summary declares `schemaID: https://vifty.local/schemas/release-artifact-summary.schema.json`, and release evidence review rejects summaries with a missing or drifted schema identity. When `--summary` is provided and a release-trust check fails, the verifier writes a failed summary naming the failing check so reviewers do not have to reconstruct the failure from transient logs alone.

   If this fails after an artifact has already been published, cut a corrected patch release instead of treating the Homebrew cask as trusted.

11. After publication, run `git fetch origin main --tags` and `scripts/check-release-readiness.sh --mode developer-id --version <version> --repo Reedtrullz/Vifty --require-source-ref origin/main --json` again, then keep the passed schema-backed JSON with release notes or validation evidence. The final JSON should show `releaseMode: "developer-id"` plus `release-source-ref`, `source-ci`, `release-workflow`, `release-secrets`, and `github-release` all passed.
12. After publication, verify on hardware with [hardware-validation.md](hardware-validation.md). Prefer `scripts/collect-validation-evidence.sh --app /Applications/Vifty.app --release-summary ./Vifty-v<version>-artifact-summary.json --release-checklist ./Vifty-v<version>-release-checklist.md` so release reports include the same read-only evidence bundle, including `review-summary.tsv`, `review-summary.json`, `bundle-executables.tsv`, `schema-resources.tsv`, `capabilities-schema-resources.tsv`, `capabilities-contract.tsv`, `viftyctl-audit.json`, `release-artifact-summary.json`, `release-artifact-summary.tsv`, `release-checklist.md`, `release-checklist.tsv`, bundle plist, LaunchDaemon TeamID, per-binary signing, notarization, Gatekeeper files, the release verifier result, and the release checklist. The collector marks the release-summary row nonzero if the verifier result does not pass or if its version does not match the installed app being tested; it marks the release-checklist row nonzero if the checklist title version does not match the installed app or if required follow-up sections are missing; it marks the capabilities-contract row nonzero if the installed CLI stops advertising the safe `runLifecycle`, direct prepare/restore lifecycle, `policyStatusAvailable: true`, wrapper resource discovery, metadata limits, or force-retry discovery fields. Before treating the installed release as trusted, run `make validation-evidence-review VALIDATION_EVIDENCE_BUNDLE=<evidence-dir> VALIDATION_EVIDENCE_REVIEW_MODE=release VALIDATION_EVIDENCE_REVIEW_SUMMARY=<evidence-dir>/review-result.json` on the captured bundle and keep the schema-backed `review-result.json` with the report.
13. For a future auto-update-enabled release, verify Sparkle metadata before publication: `SUFeedURL` must be HTTPS, `SUPublicEDKey` must match the protected EdDSA private key, signed appcast settings must be enabled, `generate_appcast` must have produced the signed appcast for the canonical `Vifty-v<version>.zip`, and the updater must not point at unsigned-dev or source-first artifacts.
14. Update [compatibility.md](compatibility.md) only with report-backed results. Use `scripts/summarize-validation-reports.sh --input <reports-dir> --output-json <reports-dir>/compatibility-index.json --output-tsv <reports-dir>/compatibility-index.tsv --output-markdown <reports-dir>/compatibility-matrix.md` to index valid reviewed `review-result.json` files and draft a conservative Markdown matrix; each review result declares `schemaID: https://vifty.local/schemas/validation-review-result.schema.json`, the JSON index declares `schemaID: https://vifty.local/schemas/validation-report-index.schema.json`, and the indexer rejects missing or drifted review-result schema IDs, malformed, non-read-only, cooling-mutating, unsupported-mode, unsupported install-source, invalid or missing required source SHA/checksum, mutable or missing source refs for source-build tag evidence, unsupported `agentRunSmokeResult` values, missing or unsupported agent decision/recovery fields, malformed `manualControlActive`, or contradictory passed review outputs. Leave model families as "needs validation" until supported-hardware rows are indexed as `validated-hardware-evidence` from `manualSmokeTestResult: "passed-auto-restored"`. Preserve `recommendedAgentAction`, `recommendedRecoveryAction`, `safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`, `agentRunSmokeResult`, and `agentRunSmokeSource` as separate developer-workload and readiness proof for guarded `viftyctl run`; do not use it as a substitute for manual fan-control smoke evidence. Use the generated `compatibility-matrix.md`, model-family counts, recommended agent action, recovery action, `safeToRequestCooling`, daemon control-path readiness, and manual-control ownership counts to spot unsafe readiness clusters before publishing compatibility claims.

## Manual Local Signing Smoke Test

You can verify the signing path locally without publishing:

```sh
make app CONFIGURATION=release \
  SIGNING_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" \
  VIFTY_XPC_ALLOWED_TEAM_ID="TEAMID"
plutil -p .build/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
codesign --verify --deep --strict .build/Vifty.app
codesign -dvvv .build/Vifty.app 2>&1 | grep TeamIdentifier
```

Ad-hoc builds remain supported for local development and source-first tester convenience, but they are not trusted public binaries.
