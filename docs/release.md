# Release Process

Vifty release artifacts should be Developer ID signed, notarized, stapled, and tied to the same TeamID that the privileged daemon enforces over XPC.

For the current public release trust state, see [release-status.md](release-status.md). Keep that page updated when a release workflow fails, succeeds, or when the cask checksum is updated.

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

## Release Checklist

1. Confirm the release secrets are configured:

   ```sh
   scripts/check-release-secrets.sh --repo Reedtrullz/Vifty
   ```

   This checks only secret names, not values. It should report all required Developer ID and notarization secret names before a release tag is pushed or a failed release workflow is rerun.

2. Confirm the local tree is clean and tests pass:

   ```sh
   make verify
   ```

3. Update `CHANGELOG.md`: move `Unreleased` entries under the new version and date.
4. Update `Resources/Info.plist` and `Casks/vifty.rb` to the release version.
5. Commit the release prep. The cask checksum can be updated in a follow-up commit after the notarized artifact exists.
6. Tag the commit:

   ```sh
   git tag v<version>
   git push origin main --tags
   ```

7. Watch the `Release` workflow. It will:

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
   - publish the zip, SHA-256 checksum, and verification summary to the GitHub Release.

8. Update `Casks/vifty.rb` with the SHA-256 checksum from the release artifact:

   ```sh
   scripts/update-cask-checksum.sh \
     --checksum-file ./Vifty-v<version>.zip.sha256 \
     --version <version>
   ```

   The updater accepts the normal `shasum -a 256` output from the release workflow, requires the checksum artifact name to match the cask version, and re-runs release metadata validation before and after editing the cask.

9. Verify the public artifact and cask agree:

   ```sh
   scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"
   ```

   This downloads the cask URL unless `--artifact <zip>` is provided, checks the SHA-256, extracts `Vifty.app`, verifies bundle version, required executables, and bundled `Contents/Resources/schemas` JSON Schemas including stable `$schema` and `$id` values, validates plist files, checks Developer ID TeamID alignment including the LaunchDaemon `VIFTY_XPC_ALLOWED_TEAM_ID`, validates stapling, and runs Gatekeeper assessment. The release workflow runs the same verifier before publishing with `--expected-sha` because the final cask checksum follow-up commit does not exist yet, and publishes the verifier's JSON summary as release evidence. The summary declares `schemaID: https://vifty.local/schemas/release-artifact-summary.schema.json`, and release evidence review rejects summaries with a missing or drifted schema identity. When `--summary` is provided and a release-trust check fails, the verifier writes a failed summary naming the failing check so reviewers do not have to reconstruct the failure from transient logs alone.

   If this fails after an artifact has already been published, cut a corrected patch release instead of treating the Homebrew cask as trusted.

10. After publication, verify on hardware with [hardware-validation.md](hardware-validation.md). Prefer `scripts/collect-validation-evidence.sh --app /Applications/Vifty.app --release-summary ./Vifty-v<version>-artifact-summary.json` so release reports include the same read-only evidence bundle, including `review-summary.tsv`, `review-summary.json`, `bundle-executables.tsv`, `schema-resources.tsv`, `capabilities-schema-resources.tsv`, `viftyctl-audit.json`, `release-artifact-summary.json`, `release-artifact-summary.tsv`, bundle plist, LaunchDaemon TeamID, per-binary signing, notarization, Gatekeeper files, and the release verifier result. The collector marks the release-summary row nonzero if the verifier result does not pass or if its version does not match the installed app being tested. Before treating the installed release as trusted, run `scripts/review-validation-evidence.sh --bundle <evidence-dir> --mode release --summary <evidence-dir>/review-result.json` on the captured bundle and keep `review-result.json` with the report.
11. Update [compatibility.md](compatibility.md) only with report-backed results. Use `scripts/summarize-validation-reports.sh --input <reports-dir> --output-json <reports-dir>/compatibility-index.json --output-tsv <reports-dir>/compatibility-index.tsv` to index valid reviewed `review-result.json` files; the indexer rejects malformed, non-read-only, cooling-mutating, unsupported-mode, or contradictory passed review outputs. Leave model families as "needs validation" until supported-hardware rows are indexed as `validated-hardware-evidence` from `manualSmokeTestResult: "passed-auto-restored"`.

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

Ad-hoc builds remain supported for local development, but public releases should use the workflow above.
