# Release Process

Vifty has two release modes:

- **Source-first release:** used for `v1.1.0` because the project does not currently have Apple Developer Program credentials. The GitHub Release is the source tag plus release notes, with an optional clearly marked unsigned tester app zip.
- **Developer ID release:** future trusted binary lane. Artifacts should be Developer ID signed, notarized, stapled, and tied to the same TeamID that the privileged daemon enforces over XPC.

For the current public release trust state, see [release-status.md](release-status.md). Keep that page updated when a release workflow fails, succeeds, or when the cask checksum is updated.

## Source-First Release Mode

Use this mode when Apple Developer Program credentials are unavailable. It does not create a trusted public binary and must not claim Developer ID signing, notarization, stapling, Gatekeeper approval, or Homebrew trust.

The required `v1.1.0` release-note warning is:

> This is a source-first release. Vifty v1.1.0 does not yet include a Developer ID signed or notarized public binary because the project does not currently have Apple Developer Program credentials.
>
> A convenience unsigned `.app` build is attached for testers who understand macOS Gatekeeper warnings and prefer not to build locally. For the most trusted path, build from source.

Source-first checklist:

1. Run the local verification suite:

   ```sh
   make verify
   ```

2. Generate source-first release notes:

   ```sh
   scripts/write-release-checklist.sh \
     --mode source-first \
     --version <version> \
     --output .build/Vifty-v<version>-source-first-release-notes.md
   ```

3. Optionally build the unsigned tester artifact:

   ```sh
   make unsigned-dev-artifact
   ```

   The only acceptable unsigned tester names are:

   - `Vifty-v<version>-unsigned-dev.zip`
   - `Vifty-v<version>-unsigned-dev.zip.sha256`

   Do not use `Vifty-v<version>.zip` or `Vifty-v<version>.zip.sha256` for an unsigned build. Those names are reserved for the future Developer ID signed and notarized artifact.

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

5. Push the source tag and create or update the GitHub Release with the source-first notes. The unsigned-dev zip/checksum are optional tester convenience assets only.
6. Confirm published source-first readiness:

   ```sh
   git fetch origin main --tags
   scripts/check-release-readiness.sh \
     --mode source-first \
     --version <version> \
     --repo Reedtrullz/Vifty \
     --json
   ```

   If you need an immutable source-ref check after publication, use the release commit SHA rather than a moving branch.

7. Do not update `Casks/vifty.rb` for the source-first release and do not point the cask at the unsigned-dev artifact.

## Developer ID Release Mode

## Required GitHub Secrets

Configure these repository secrets before running the `Release` workflow:

- `APPLE_TEAM_ID` — Apple Developer TeamID used for signing and XPC allowlisting.
- `APPLE_ID` — Apple ID email for `xcrun notarytool`.
- `APPLE_APP_SPECIFIC_PASSWORD` — app-specific password for notarization.
- `DEVELOPER_ID_APPLICATION_IDENTITY` — exact codesign identity, for example `Developer ID Application: Example, Inc. (TEAMID)`.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64` — base64-encoded `.p12` Developer ID Application certificate.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD` — password for the `.p12`.

## Version Requirements

Before tagging, update all release-facing versions to the same value:

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
   make verify
   ```

4. Update `CHANGELOG.md`: move `Unreleased` entries under the new version and date.
5. Update `Resources/Info.plist` and `Casks/vifty.rb` to the release version.
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
   - run `swift test`;
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

   This downloads the cask URL unless `--artifact <zip>` is provided, checks the SHA-256, extracts `Vifty.app`, verifies bundle version, required executables, and bundled `Contents/Resources/schemas` JSON Schemas including stable `$schema` and `$id` values for release-readiness, release-artifact-summary, and `viftyctl` contracts, validates plist files, checks Developer ID TeamID alignment including the LaunchDaemon `VIFTY_XPC_ALLOWED_TEAM_ID`, validates stapling, and runs Gatekeeper assessment. The release workflow runs the same verifier before publishing with `--expected-sha` because the final cask checksum follow-up commit does not exist yet, and publishes the verifier's JSON summary as release evidence. The summary declares `schemaID: https://vifty.local/schemas/release-artifact-summary.schema.json`, and release evidence review rejects summaries with a missing or drifted schema identity. When `--summary` is provided and a release-trust check fails, the verifier writes a failed summary naming the failing check so reviewers do not have to reconstruct the failure from transient logs alone.

   If this fails after an artifact has already been published, cut a corrected patch release instead of treating the Homebrew cask as trusted.

11. After publication, run `git fetch origin main --tags` and `scripts/check-release-readiness.sh --mode developer-id --version <version> --repo Reedtrullz/Vifty --require-source-ref origin/main --json` again, then keep the passed schema-backed JSON with release notes or validation evidence. The final JSON should show `releaseMode: "developer-id"` plus `release-source-ref`, `source-ci`, `release-workflow`, `release-secrets`, and `github-release` all passed.
12. After publication, verify on hardware with [hardware-validation.md](hardware-validation.md). Prefer `scripts/collect-validation-evidence.sh --app /Applications/Vifty.app --release-summary ./Vifty-v<version>-artifact-summary.json --release-checklist ./Vifty-v<version>-release-checklist.md` so release reports include the same read-only evidence bundle, including `review-summary.tsv`, `review-summary.json`, `bundle-executables.tsv`, `schema-resources.tsv`, `capabilities-schema-resources.tsv`, `viftyctl-audit.json`, `release-artifact-summary.json`, `release-artifact-summary.tsv`, `release-checklist.md`, `release-checklist.tsv`, bundle plist, LaunchDaemon TeamID, per-binary signing, notarization, Gatekeeper files, the release verifier result, and the release checklist. The collector marks the release-summary row nonzero if the verifier result does not pass or if its version does not match the installed app being tested; it marks the release-checklist row nonzero if the checklist title version does not match the installed app or if required follow-up sections are missing. Before treating the installed release as trusted, run `scripts/review-validation-evidence.sh --bundle <evidence-dir> --mode release --summary <evidence-dir>/review-result.json` on the captured bundle and keep `review-result.json` with the report.
13. Update [compatibility.md](compatibility.md) only with report-backed results. Use `scripts/summarize-validation-reports.sh --input <reports-dir> --output-json <reports-dir>/compatibility-index.json --output-tsv <reports-dir>/compatibility-index.tsv` to index valid reviewed `review-result.json` files; the indexer rejects malformed, non-read-only, cooling-mutating, unsupported-mode, or contradictory passed review outputs. Leave model families as "needs validation" until supported-hardware rows are indexed as `validated-hardware-evidence` from `manualSmokeTestResult: "passed-auto-restored"`.

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
