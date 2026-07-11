# Release Status

This page is the current public trust status for Vifty releases. Update it whenever the source tag, GitHub Release notes/assets, Developer ID release workflow outcome, Homebrew cask checksum, or published release assets change.

## Current Status

As of 2026-07-11, `v1.2.0` is the first published Developer ID release. Its immutable tag resolves to `9bf45f9afc56a36580bede696c479bff0df0cf6a`, source CI run `29160869645` passed, signed/notarized Release run `29161176933` passed, and the four canonical trust assets are public at the [v1.2.0 GitHub Release](https://github.com/Reedtrullz/Vifty/releases/tag/v1.2.0). `v1.1.1` remains the published source-first fallback; its immutable tag resolves to `a82f2237ff39c24a6b366dca8f95a17ee54fd972`.

Developer ID publication evidence: the intended personal TeamID `X88J3853S2` is active, all required GitHub release secret names are configured, and both workflow and independent local verification accepted the signed public artifact's TeamID, Apple notarization ticket, stapling, LaunchDaemon allowlist, and Gatekeeper assessment. The exact public zip and cask now pass those checks independently. Do not use another organization's team or certificate for Vifty.

The public `Vifty-v1.2.0.zip` and checked-in cask both resolve to SHA-256 `7b4b6528a696bfb23995c89c994489cf25e6f4b5cdf50242b7f0a21b897ab28e`. The published artifact summary declares `status: "passed"`, uses schema ID `https://vifty.local/schemas/release-artifact-summary.schema.json`, and records that signature and notarization checks were not skipped. Developer ID readiness reports `status: "ready"` with release source ref, source CI, Release workflow, secret names, and all four public assets passed.

Local installed release-mode validation remains pending on this workstation. `/Applications/Vifty.app` is still `v1.1.1`, and read-only diagnostics found the two fans in intentional Forced mode. Replacing it requires an explicit human decision to restore Auto first, followed by installation of the exact public zip, helper repair, read-only evidence collection, and release-mode review. This pending local evidence blocks an installed-hardware validation claim; it does not change the verified identity or checksum of the published artifact.

Release lanes:

1. **Published Developer ID release:** `v1.2.0` public artifact and cask trust checks passed for the tagged workflow, canonical assets, checksum handoff, public verifier, release readiness, TeamID, notarization, stapling, and Gatekeeper. Local installed release-mode evidence is still pending and must not be implied by those distribution checks.
2. **Source release:** `v1.1.1` remains the published source-first fallback. Do not claim it or any unsigned-dev artifact is Developer ID signed, notarized, stapled, Gatekeeper-approved, or Homebrew-trusted.
3. **Unsigned convenience app zip:** optional tester convenience only. The attached hotfix artifact is named `Vifty-v1.1.1-unsigned-dev.zip` with `Vifty-v1.1.1-unsigned-dev.zip.sha256`. The unsigned-dev zip is valid only with its `.sha256` sidecar, and the SHA-256 digest in that sidecar must match the zip bytes. It is ad-hoc signed, not notarized, not the official trusted binary, and may trigger macOS Gatekeeper warnings.

Auto-update status: unavailable in `v1.2.0`, source-first, and unsigned-dev builds. Vifty should use Sparkle only in a separately reviewed Developer ID signed/notarized release with signed appcast metadata; see [auto-update.md](auto-update.md).

Public release facts:

- `Resources/Info.plist` and `Casks/vifty.rb` are aligned at `1.2.0`; the cask uses the published SHA-256 `7b4b6528a696bfb23995c89c994489cf25e6f4b5cdf50242b7f0a21b897ab28e`.
- Source CI run `29160869645` passed on release commit `9bf45f9afc56a36580bede696c479bff0df0cf6a`, and Release run `29161176933` passed all signing, notarization, pre-publication verification, checklist, and publication steps.
- The GitHub Release publishes `Vifty-v1.2.0.zip`, `Vifty-v1.2.0.zip.sha256`, `Vifty-v1.2.0-artifact-summary.json`, and `Vifty-v1.2.0-release-checklist.md`.
- The published workflow summary and an independent downloaded-artifact verification both passed with TeamID `X88J3853S2`, no signature skips, and no notarization skips.
- `scripts/check-release-readiness.sh --mode developer-id --version 1.2.0 --repo Reedtrullz/Vifty --require-source-ref origin/main --json` reported `ready` before the cask follow-up moved `main`.
- `scripts/check-release-secrets.sh --repo Reedtrullz/Vifty` reports every required secret name. It does not read or print secret values.
- Earlier local TeamID, hardened-runtime, notarization, stapling, LaunchDaemon allowlist, and Gatekeeper smoke checks passed for a locally built candidate. The published GitHub Release artifact has now repeated those checks independently; the local smoke remains corroborating preflight, not public artifact proof.

Historical source-first facts:

- The `v1.1.1` source tag points at `a82f2237ff39c24a6b366dca8f95a17ee54fd972`, and the SwiftPM CI gate passed for source, tests, release app bundle construction, bundle verification, temporary install-script verification, archive, and CI artifact upload before publication.
- `scripts/check-release-readiness.sh --mode source-first --version 1.1.1 --repo Reedtrullz/Vifty --source-sha a82f2237ff39c24a6b366dca8f95a17ee54fd972 --json` reports `ready` with the attached `Vifty-v1.1.1-unsigned-dev.zip` and checksum assets after verifying that the sidecar digest matches the zip bytes.
- Known issue: the published `v1.1.0` source/unsigned-dev release predates helper-install and app-polling hardening on `main` (`6b0690b`, `4f729d7`, and `3064b9e`). Users may see "Fan helper unreachable" after updating even on supported hardware.
- Do not retag `v1.1.0`, rebuild `Vifty-v1.1.0-unsigned-dev.zip` from later `main`, or claim the published `v1.1.0` convenience artifact is the official trusted binary. The honest remediation is the `v1.1.1` source-first hotfix release, still unsigned/not notarized until Apple Developer Program credentials exist.
- `main` may move after `v1.1.1` publication. Do not use `--require-source-ref origin/main` as a post-publication source-first check unless `origin/main` is intentionally still the release commit.
- At `v1.1.1` publication, `Resources/Info.plist` carried `1.1.1` while `Casks/vifty.rb` remained disabled on `1.1.0`, preventing the source-first hotfix from moving Homebrew to an unsigned artifact.
- Source-first readiness proves the release notes/assets/trust boundaries for the immutable tag. It does not prove the release has no post-publication functional defects; helper reports still need `viftyctl diagnose --json`, launchd evidence, and a follow-up release decision if a new defect appears.
- Before tagging a source-first candidate, maintainers may add `--require-source-ref <candidate-ref-or-sha>` to reject a stale tag. After publication, use the immutable release commit SHA if a source-ref check is still needed.
- `scripts/check-release-readiness.sh --mode developer-id ...` is the strict trusted-binary preflight. It requires Apple release secrets, a successful signed/notarized Release workflow, canonical `Vifty-v<version>.zip` assets, verifier summary, and release checklist.
- No unsigned build may use `Vifty-v<version>.zip` or `Vifty-v<version>.zip.sha256`; those canonical names are reserved for Developer ID signed and notarized artifacts.
- Do not update the Homebrew cask checksum for a source-first release, do not re-enable the cask, and do not point Homebrew at unsigned-dev artifacts.
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

The unsigned-dev zip is valid only with its `.sha256` sidecar, and the SHA-256 digest in that sidecar must match the zip bytes.

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

The unsigned-dev zip is valid only with its `.sha256` sidecar, and the SHA-256 digest in that sidecar must match the zip bytes.

If the GitHub Release is not created yet, source-first readiness should block only on `github-release` after source/ref/CI checks pass. After publication, it should pass without requiring Apple Developer Program secrets.

For the `v1.1.0` helper issue, use these checks only to reproduce and audit the release boundary. Do not use the `v1.1.0` unsigned-dev target to refresh public assets from `main`; prepare a new source-first hotfix release and make its release notes repeat the unsigned/not-notarized warning.

## Developer ID Release Checks

Before pushing a Developer ID tag:

1. Keep Sparkle/update metadata out of `Resources/Info.plist` unless a separate signed-appcast release has been reviewed.
2. Keep `.github/workflows/release.yml` strict about Developer ID signing, `VIFTY_XPC_ALLOWED_TEAM_ID`, notarization, stapling, Gatekeeper, artifact verification, and release checklist publication.
3. Verify required secret names and the local signing/notarization path without storing certificate material, passwords, or secret values in the repo or Obsidian.
4. Enable the cask only in the final candidate commit, and do not recommend it until the workflow checksum handoff and public verifier pass.

All of these must be true before calling a future public binary release trusted:

1. `scripts/check-release-secrets.sh --repo Reedtrullz/Vifty` reports all required release secret names.
2. After `git fetch origin main --tags`, `scripts/check-release-readiness.sh --mode developer-id --version <version> --repo Reedtrullz/Vifty --require-source-ref origin/main --json` reports `release-source-ref`, `source-ci`, `release-workflow`, `release-secrets`, and `github-release` passed.
3. The `Release` workflow for the `v<version>` tag completes successfully.
4. The GitHub Release includes:
   - `Vifty-v<version>.zip`
   - `Vifty-v<version>.zip.sha256`
   - `Vifty-v<version>-artifact-summary.json`
   - `Vifty-v<version>-release-checklist.md`
5. `Casks/vifty.rb` is re-enabled and updated with the checksum from the published release artifact using `scripts/update-cask-checksum.sh`.
6. `scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"` passes against the published cask artifact.
7. A release-mode validation evidence bundle is collected with both `--release-summary` and `--release-checklist`, then reviewed with `make validation-evidence-review VALIDATION_EVIDENCE_REVIEW_MODE=release`.

Until the installed release-mode evidence is collected and reviewed, do not describe this workstation or its hardware as validated by `v1.2.0`. The public artifact and cask checks above establish distribution identity and integrity; they do not substitute for hardware smoke evidence.
