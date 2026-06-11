# Release Status

This page is the current public trust status for Vifty releases. Update it whenever the release workflow outcome, Homebrew cask checksum, or published release assets change.

## Current Status

As of 2026-06-11, the `v1.1.0` source tag is the prepared release candidate, but the public binary release is not trust-complete yet.

Current facts:

- `main` and the `v1.1.0` tag have passed the SwiftPM CI gate for source, tests, release app bundle construction, bundle verification, temporary install-script verification, archive, and CI artifact upload.
- The `v1.1.0` GitHub Release workflow currently stops before signing and notarization because the required repository secrets are not configured.
- No `v1.1.0` GitHub Release artifact should be treated as published or trusted until the workflow publishes `Vifty-v1.1.0.zip`, `Vifty-v1.1.0.zip.sha256`, `Vifty-v1.1.0-artifact-summary.json`, and `Vifty-v1.1.0-release-checklist.md`.
- Homebrew install instructions are release-path documentation, not proof that the current cask artifact is trust-complete. Treat the Homebrew cask as trusted only after its version and SHA match a signed, notarized, stapled artifact that passes `scripts/verify-release-artifact.sh`.
- The older `v1.0.0` public asset is not trust-complete because release verification found a bundle-version mismatch between the extracted app and cask metadata.

## Required Before Calling A Public Release Trusted

All of these must be true for the current public release:

1. `scripts/check-release-secrets.sh --repo Reedtrullz/Vifty` reports all required release secret names.
2. The `Release` workflow for the `v<version>` tag completes successfully.
3. The GitHub Release includes:
   - `Vifty-v<version>.zip`
   - `Vifty-v<version>.zip.sha256`
   - `Vifty-v<version>-artifact-summary.json`
   - `Vifty-v<version>-release-checklist.md`
4. `Casks/vifty.rb` is updated with the checksum from the published release artifact using `scripts/update-cask-checksum.sh`.
5. `scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"` passes against the published cask artifact.
6. A release-mode validation evidence bundle is collected and reviewed with `scripts/review-validation-evidence.sh --mode release`.

Until those checks pass, prefer source builds for development and do not describe the Homebrew path as a trusted public binary install.

## Operator Checks

Use these checks before rerunning or promoting a release:

```sh
scripts/check-release-secrets.sh --repo Reedtrullz/Vifty
gh release view v1.1.0 --repo Reedtrullz/Vifty
scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"
```

Expected current result before secrets are configured:

- `scripts/check-release-secrets.sh` reports the missing Developer ID and notarization secret names.
- `gh release view v1.1.0` reports that the release is not found.
- `scripts/verify-release-artifact.sh` cannot pass for `v1.1.0` until the release asset and cask checksum exist.
