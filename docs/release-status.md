# Release Status

This page is the current public trust status for Vifty releases. Update it whenever the source tag, GitHub Release notes/assets, Developer ID release workflow outcome, Homebrew cask checksum, or published release assets change.

## Current Status

As of 2026-06-12, the latest published public release is `v1.1.1`, a source-first hotfix release because the project does not currently have Apple Developer Program credentials. The immutable `v1.1.1` source tag resolves to `a82f2237ff39c24a6b366dca8f95a17ee54fd972` and supersedes `v1.1.0` for users who hit the helper-unreachable update issue.

Release lanes:

1. **Trusted notarized Developer ID release:** unavailable until the project has Apple Developer Program credentials. Do not claim that `v1.1.1` or any source-first unsigned-dev artifact is Developer ID signed, notarized, stapled, Gatekeeper-approved, or Homebrew-trusted.
2. **Source release:** canonical and recommended path while Apple credentials are unavailable. `v1.1.1` is the recommended source tag.
3. **Unsigned convenience app zip:** optional tester convenience only. The attached hotfix artifact is named `Vifty-v1.1.1-unsigned-dev.zip` with `Vifty-v1.1.1-unsigned-dev.zip.sha256`. It is ad-hoc signed, not notarized, not the official trusted binary, and may trigger macOS Gatekeeper warnings.

Current facts:

- The `v1.1.1` source tag points at `a82f2237ff39c24a6b366dca8f95a17ee54fd972`, and the SwiftPM CI gate passed for source, tests, release app bundle construction, bundle verification, temporary install-script verification, archive, and CI artifact upload before publication.
- `scripts/check-release-readiness.sh --mode source-first --version 1.1.1 --repo Reedtrullz/Vifty --source-sha a82f2237ff39c24a6b366dca8f95a17ee54fd972 --json` reports `ready` with the attached `Vifty-v1.1.1-unsigned-dev.zip` and checksum assets.
- Known issue: the published `v1.1.0` source/unsigned-dev release predates helper-install and app-polling hardening on `main` (`6b0690b`, `4f729d7`, and `3064b9e`). Users may see "Fan helper unreachable" after updating even on supported hardware.
- Do not retag `v1.1.0`, rebuild `Vifty-v1.1.0-unsigned-dev.zip` from later `main`, or claim the published `v1.1.0` convenience artifact is the official trusted binary. The honest remediation is the `v1.1.1` source-first hotfix release, still unsigned/not notarized until Apple Developer Program credentials exist.
- `main` may move after `v1.1.1` publication. Do not use `--require-source-ref origin/main` as a post-publication source-first check unless `origin/main` is intentionally still the release commit.
- `Resources/Info.plist` now carries `1.1.1`; `Casks/vifty.rb` remains on `1.1.0` because source-first releases must not move Homebrew to an unsigned artifact. Source-first metadata validation allows this cask hold, while Developer ID metadata validation still requires bundle/cask alignment before any future notarized cask release.
- Source-first readiness proves the release notes/assets/trust boundaries for the immutable tag. It does not prove the release has no post-publication functional defects; helper reports still need `viftyctl diagnose --json`, launchd evidence, and a follow-up release decision if a new defect appears.
- Before tagging a source-first candidate, maintainers may add `--require-source-ref <candidate-ref-or-sha>` to reject a stale tag. After publication, use the immutable release commit SHA if a source-ref check is still needed.
- `scripts/check-release-readiness.sh --mode developer-id ...` remains the strict future trusted-binary preflight. It still requires Apple release secrets, a successful signed/notarized Release workflow, canonical `Vifty-v<version>.zip` assets, verifier summary, and release checklist.
- No unsigned build may use `Vifty-v<version>.zip` or `Vifty-v<version>.zip.sha256`; those canonical names are reserved for a future Developer ID signed and notarized artifact.
- Do not update the Homebrew cask checksum for a source-first release, and do not point Homebrew at unsigned-dev artifacts.
- The older `v1.0.0` public asset is not trust-complete because release verification found a bundle-version mismatch between the extracted app and cask metadata.

## Source-First v1.1.1 Operator Checks

Use these checks to reproduce the published hotfix boundary:

```sh
git fetch origin main --tags
git checkout v1.1.1
make verify
make source-first-release-notes
make unsigned-dev-artifact
RELEASE_VERSION=1.1.1 make source-first-readiness
```

The published GitHub Release body repeats the source-first warning, names `a82f2237ff39c24a6b366dca8f95a17ee54fd972` as the immutable source tag commit, explains that the attached app is unsigned/not notarized/not trusted, and calls out the helper-install/app-polling fixes that supersede `v1.1.0`.

`make source-first-release-notes` writes `.build/Vifty-v1.1.1-source-first-release-notes.md`. Those generated notes tell maintainers to use `--require-source-ref <candidate-ref-or-sha>` only before publication or with an immutable intended release commit, never as a blanket `origin/main` post-publication check. `make unsigned-dev-artifact` requires the current source to match `UNSIGNED_DEV_SOURCE_REF`, which defaults to `v1.1.1`, so post-release `main` cannot silently produce a tester zip named as the `v1.1.1` release attachment. The optional current hotfix tester assets are valid only when both files are present:

- `Vifty-v1.1.1-unsigned-dev.zip`
- `Vifty-v1.1.1-unsigned-dev.zip.sha256`

## Superseded v1.1.0 Boundary Audit

Use these checks only to reproduce the already-published `v1.1.0` boundary. Do not publish, update, or refresh public `v1.1.0` assets from later source; the supported remediation is the `v1.1.1` source-first hotfix or a future new release.

```sh
git fetch origin main --tags
git checkout v1.1.0
make verify
make source-first-release-notes
make unsigned-dev-artifact
make source-first-readiness
```

`make source-first-release-notes` writes `.build/Vifty-v1.1.0-source-first-release-notes.md`. Those generated notes should tell maintainers to use `--require-source-ref <candidate-ref-or-sha>` only before publication or with an immutable intended release commit, never as a blanket `origin/main` post-publication check. `make unsigned-dev-artifact` requires the current source to match `UNSIGNED_DEV_SOURCE_REF`, which defaults to `v1.1.0`, so post-release `main` cannot silently produce a tester zip named as the `v1.1.0` release attachment. `make source-first-readiness` runs the published-release readiness preflight with `scripts/check-release-readiness.sh --mode source-first --version 1.1.0 --repo Reedtrullz/Vifty --json`.

If the readiness check is being run before the release tag is pushed, run the script directly with `--require-source-ref <candidate-ref-or-sha>` so a stale local tag cannot be promoted. Do not require `origin/main` for an already-published source-first tag after `main` has moved on.

Expected source-first release notes must include:

> This is a source-first release. Vifty v1.1.0 does not yet include a Developer ID signed or notarized public binary because the project does not currently have Apple Developer Program credentials.
>
> A convenience unsigned `.app` build is attached for testers who understand macOS Gatekeeper warnings and prefer not to build locally. For the most trusted path, build from source.

They should also include a source provenance section naming the immutable release tag commit and warning that later `main` commits are post-release hardening, not part of the already-published source release.

The optional unsigned-dev assets are valid only when both files are present:

- `Vifty-v1.1.0-unsigned-dev.zip`
- `Vifty-v1.1.0-unsigned-dev.zip.sha256`

If the GitHub Release is not created yet, source-first readiness should block only on `github-release` after source/ref/CI checks pass. After publication, it should pass without requiring Apple Developer Program secrets.

For the `v1.1.0` helper issue, use these checks only to reproduce and audit the release boundary. Do not use the `v1.1.0` unsigned-dev target to refresh public assets from `main`; prepare a new source-first hotfix release and make its release notes repeat the unsigned/not-notarized warning.

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
