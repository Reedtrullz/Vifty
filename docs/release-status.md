# Release Status

This page is the current public trust status for Vifty releases. Update it whenever the source tag, GitHub Release notes/assets, Developer ID release workflow outcome, Homebrew cask checksum, or published release assets change.

## Current Status

As of 2026-06-11, `v1.1.0` is a source-first public release because the project does not currently have Apple Developer Program credentials.

Release lanes:

1. **Trusted notarized Developer ID release:** unavailable until the project has Apple Developer Program credentials. Do not claim that `v1.1.0` is Developer ID signed, notarized, stapled, Gatekeeper-approved, or Homebrew-trusted.
2. **Source release:** canonical and recommended path for `v1.1.0`. Users should build from source after checking out the `v1.1.0` tag.
3. **Unsigned convenience app zip:** optional tester convenience only. If attached, it must be named `Vifty-v1.1.0-unsigned-dev.zip` with `Vifty-v1.1.0-unsigned-dev.zip.sha256`. It is ad-hoc signed, not notarized, not the official trusted binary, and may trigger macOS Gatekeeper warnings.

Current facts:

- The `v1.1.0` source tag should pass the SwiftPM CI gate for source, tests, release app bundle construction, bundle verification, temporary install-script verification, archive, and CI artifact upload before publication.
- `main` may move after `v1.1.0` is published. Do not use `--require-source-ref origin/main` as a post-publication source-first check unless `origin/main` is intentionally still the release commit.
- `scripts/check-release-readiness.sh --mode source-first --version 1.1.0 --repo Reedtrullz/Vifty --json` is the published source-first release preflight. It requires source-tag CI readiness and honest GitHub Release notes/assets, while treating Apple Developer Program secrets and the Developer ID Release workflow as not required for this mode.
- Before tagging a source-first candidate, maintainers may add `--require-source-ref <candidate-ref-or-sha>` to reject a stale tag. After publication, use the immutable release commit SHA if a source-ref check is still needed.
- `scripts/check-release-readiness.sh --mode developer-id ...` remains the strict future trusted-binary preflight. It still requires Apple release secrets, a successful signed/notarized Release workflow, canonical `Vifty-v<version>.zip` assets, verifier summary, and release checklist.
- No unsigned build may use `Vifty-v1.1.0.zip` or `Vifty-v1.1.0.zip.sha256`; those canonical names are reserved for a future Developer ID signed and notarized artifact.
- Do not update the Homebrew cask for this source-first release, and do not point Homebrew at the unsigned-dev artifact.
- The older `v1.0.0` public asset is not trust-complete because release verification found a bundle-version mismatch between the extracted app and cask metadata.

## Source-First v1.1.0 Operator Checks

Use these checks before publishing or updating the `v1.1.0` GitHub Release:

```sh
git fetch origin main --tags
make verify
make source-first-release-notes
make unsigned-dev-artifact
make source-first-readiness
```

`make source-first-release-notes` writes `.build/Vifty-v1.1.0-source-first-release-notes.md`. Those generated notes should tell maintainers to use `--require-source-ref <candidate-ref-or-sha>` only before publication or with an immutable intended release commit, never as a blanket `origin/main` post-publication check. `make source-first-readiness` runs the published-release readiness preflight with `scripts/check-release-readiness.sh --mode source-first --version 1.1.0 --repo Reedtrullz/Vifty --json`.

If the readiness check is being run before the release tag is pushed, run the script directly with `--require-source-ref <candidate-ref-or-sha>` so a stale local tag cannot be promoted. Do not require `origin/main` for an already-published source-first tag after `main` has moved on.

Expected source-first release notes must include:

> This is a source-first release. Vifty v1.1.0 does not yet include a Developer ID signed or notarized public binary because the project does not currently have Apple Developer Program credentials.
>
> A convenience unsigned `.app` build is attached for testers who understand macOS Gatekeeper warnings and prefer not to build locally. For the most trusted path, build from source.

The optional unsigned-dev assets are valid only when both files are present:

- `Vifty-v1.1.0-unsigned-dev.zip`
- `Vifty-v1.1.0-unsigned-dev.zip.sha256`

If the GitHub Release is not created yet, source-first readiness should block only on `github-release` after source/ref/CI checks pass. After publication, it should pass without requiring Apple Developer Program secrets.

## Future Developer ID Release Checks

All of these must be true before calling a future public binary release trusted:

1. `scripts/check-release-secrets.sh --repo Reedtrullz/Vifty` reports all required release secret names.
2. After `git fetch origin main --tags`, `scripts/check-release-readiness.sh --mode developer-id --version <version> --repo Reedtrullz/Vifty --require-source-ref origin/main --json` reports `release-source-ref`, `source-ci`, `release-workflow`, `release-secrets`, and `github-release` passed.
3. The `Release` workflow for the `v<version>` tag completes successfully.
4. The GitHub Release includes:
   - `Vifty-v<version>.zip`
   - `Vifty-v<version>.zip.sha256`
   - `Vifty-v<version>-artifact-summary.json`
   - `Vifty-v<version>-release-checklist.md`
5. `Casks/vifty.rb` is updated with the checksum from the published release artifact using `scripts/update-cask-checksum.sh`.
6. `scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"` passes against the published cask artifact.
7. A release-mode validation evidence bundle is collected with both `--release-summary` and `--release-checklist`, then reviewed with `scripts/review-validation-evidence.sh --mode release`.

Until those future checks pass, prefer source builds and do not describe the Homebrew path as a trusted public binary install.
