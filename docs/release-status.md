# Release Status

<!-- BEGIN GENERATED RELEASE FACTS -->
> Release facts authority: `.github/release-manifest.json` (schema `docs/schemas/release-manifest.schema.json`).
> Published: `v1.3.2` (version `1.3.2`, build `7`), `arm64` only, minimum macOS `15.0`.
> Runtime identities: app `tech.reidar.vifty`, daemon `tech.reidar.vifty.daemon`, helper `tech.reidar.vifty.helper`, CLI `tech.reidar.vifty.ctl`.
> Canonical artifact: `Vifty-v1.3.2.zip` with checksum asset `Vifty-v1.3.2.zip.sha256` and SHA-256 `8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0`.
> Public artifact trust: `passed` / `developer-id-notarized` for TeamID `X88J3853S2`; source `6a771c2ea10386bf7a0a8369a759930f01d56062`, CI run `29284751837`, Release run `29285576026`.
> Tag policy: `v1.3.2` remains recorded as `historical-unsigned` evidence; signed tags are mandatory from version `1.3.3` onward.
> Separate exact-build claims: installed release review `passed`; manual Fixed/Curve/Auto compatibility `passed-auto-restored` on `MacBookPro18,1` only (review `docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/review-result.json`; attestation `docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/manual-smoke-attestation.md`).
<!-- END GENERATED RELEASE FACTS -->

This page is the current public trust status for Vifty releases. Update it whenever the source tag, GitHub Release notes/assets, Developer ID release workflow outcome, Homebrew cask checksum, or published release assets change.

## Current Status

As of 2026-07-14, `v1.3.2` is the current published Developer ID release. Its immutable tag resolves to `6a771c2ea10386bf7a0a8369a759930f01d56062`, source CI run `29284751837` passed, signed/notarized Release run `29285576026` passed, and the four canonical trust assets are public at the [v1.3.2 GitHub Release](https://github.com/Reedtrullz/Vifty/releases/tag/v1.3.2). `v1.1.1` remains the published source-first fallback; its immutable tag resolves to `a82f2237ff39c24a6b366dca8f95a17ee54fd972`.

The supervised `v1.3.1` manual smoke is not a passed compatibility claim. Fixed and Curve control reached their targets and the right-fan curve line rendered, but selecting Auto during an in-flight Curve tick could briefly show Auto active before the suspended write resumed and returned both fans to Forced mode. Operator recovery after quitting Vifty restored and read-only diagnostics confirmed hardware Auto. The exact public v1.3.2 build repeated the sequence and passed without later reassertion; prior-version evidence remains historical and does not substitute for the v1.3.2 review.

Developer ID publication evidence for immutable `v1.3.2`: at publication time, the workflow had the required release secret names available, and both that completed workflow and independent local verification accepted the signed public artifact's TeamID `X88J3853S2`, Apple notarization ticket, stapling, LaunchDaemon allowlist, and Gatekeeper assessment. The published workflow summary and prior independent downloaded-artifact verification record passes for the exact public zip and cask. This is historical evidence, not a claim that a fresh verifier run has succeeded on every current host or that a protected GitHub `release` environment currently exists; the current governance state is recorded below. Do not use another organization's team or certificate for Vifty.

The public `Vifty-v1.3.2.zip` and checked-in cask both resolve to SHA-256 `8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0`. The published artifact summary declares `status: "passed"`, uses schema ID `https://vifty.local/schemas/release-artifact-summary.schema.json`, and records that signature and notarization checks were not skipped. At publication time, independent artifact verification and Developer ID readiness both passed with the exact source ref, source CI, completed Release workflow, then-available secret names, and all four public assets; this is immutable-release evidence, not a claim about today's environment configuration. The current verifier resolves the published schema set, packaged support/wrapper inventory, and entitlements from that exact historical source commit; it also requires the selected manifest tag to peel to that source commit and compares every packaged schema byte-for-byte. CI and release checkouts fetch full history, and missing or invalid historical source now blocks verification instead of substituting current candidate policy. Future promotions must append the prior `publishedRelease` unchanged to `historicalReleases`; history is never edited, deleted, or reordered, while Homebrew remains bound only to the current published entry.

The exact installed public `v1.3.2` build `7` passed release-mode review on `MacBookPro18,1`. The privacy-safe review records `status: "passed"`, `readOnly: true`, `coolingCommandsRun: false`, `installSource: "notarized-github-release"`, source commit `6a771c2ea10386bf7a0a8369a759930f01d56062`, artifact SHA `8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0`, daemon/helper parity, ready Auto state, no manual marker or blockers, and no failures or warnings. The reviewed summary is checked in at [validation-reports/2026-07-14-v1.3.2-macbookpro18-release/review-result.json](validation-reports/2026-07-14-v1.3.2-macbookpro18-release/review-result.json); older v1.3.0 release review remains historical only.

The separate supported-hardware review also passed with `manualSmokeTestResult: "passed-auto-restored"`. A physically present operator applied 2,800 RPM Fixed control, restored Auto, applied a 55 C / 1,800 RPM → 70 C / 3,000 RPM → 85 C / 4,200 RPM curve, and restored Auto again. Final daemon diagnostics and a direct helper probe showed both fans at literal `Auto`/raw `0`, normal targets, no manual marker, no failed checks or blockers, nominal thermal pressure, and matching installed/bundled daemon hashes. The [review result](validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/review-result.json) and [attestation](validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/manual-smoke-attestation.md) disclose the observed settling UI states and scope the claim to this exact binary and model identifier.

Future Developer ID publication remains deliberately blocked at the human governance boundary. As of 2026-07-15, active GitHub ruleset `18940029` (`Immutable Vifty release tags`) covers `refs/tags/v*`, prevents update and deletion, and has no bypass actors, but the protected `release` environment is absent and no eligible non-owner reviewer or Team is available. The manifest candidate remains `null`; an owner-only environment is not an acceptable substitute. Any future `release` environment must also prevent self-review and disable administrator bypass. The Release workflow now validates the exact protected-`main` workflow contract and repeats the trusted environment/protected-`main` API readback before signing secrets, so a missing environment that GitHub auto-creates without protection cannot continue to signing or publication.

Release lanes:

1. **Published Developer ID release:** `v1.3.2` public artifact and cask trust checks passed for the tagged workflow, canonical assets, checksum handoff, public verifier, release readiness, TeamID, notarization, stapling, and Gatekeeper. Installed helper parity, explicit Auto restoration, and manual Fixed/Curve compatibility also passed as separately reviewed claims for exact build 7 on `MacBookPro18,1`; they do not transfer to other builds or models.
2. **Source release:** `v1.1.1` remains the published source-first fallback. Do not claim it or any unsigned-dev artifact is Developer ID signed, notarized, stapled, Gatekeeper-approved, or Homebrew-trusted.
3. **Unsigned convenience app zip:** optional tester convenience only. The attached hotfix artifact is named `Vifty-v1.1.1-unsigned-dev.zip` with `Vifty-v1.1.1-unsigned-dev.zip.sha256`. The unsigned-dev zip is valid only with its `.sha256` sidecar, and the SHA-256 digest in that sidecar must match the zip bytes. It is ad-hoc signed, not notarized, not the official trusted binary, and may trigger macOS Gatekeeper warnings.

Auto-update status: unavailable in `v1.3.2`, source-first, and unsigned-dev builds. Vifty should use Sparkle only in a separately reviewed Developer ID signed/notarized release with signed appcast metadata; see [auto-update.md](auto-update.md).

Public release facts:

- Release metadata in `Resources/Info.plist` and `Casks/vifty.rb` is aligned at `1.3.2` build `7`, and the checked-in cask checksum matches the immutable public artifact.
- Source CI run `29284751837` passed on release commit `6a771c2ea10386bf7a0a8369a759930f01d56062`, and Release run `29285576026` passed all signing, notarization, pre-publication verification, checklist, and publication steps.
- The GitHub Release publishes `Vifty-v1.3.2.zip`, `Vifty-v1.3.2.zip.sha256`, `Vifty-v1.3.2-artifact-summary.json`, and `Vifty-v1.3.2-release-checklist.md`.
- The published workflow summary and an independent downloaded-artifact verification both passed with TeamID `X88J3853S2`, no signature skips, and no notarization skips.
- `scripts/check-release-readiness.sh --mode developer-id --version 1.3.2 --repo Reedtrullz/Vifty --require-source-ref 6a771c2ea10386bf7a0a8369a759930f01d56062 --json` reported `ready` before the cask follow-up moved `main`.
- Independent verification of the downloaded public `v1.3.2` artifact passed. Exact-build installed release-mode, signed-helper parity, Auto-restoration, and manual Fixed/Curve compatibility are now reviewed for build 7 on `MacBookPro18,1`; broad hardware and future-release claims remain unmade.
- The `v1.3.2` workflow used the then-configured release credentials. Future releases require every required name on the protected GitHub `release` environment: `scripts/check-release-secrets.sh --repo Reedtrullz/Vifty` reads names only with `gh secret list --env release --repo ...` and blocks while that environment is absent or unreadable. This operator check proves environment-name presence at check time, not secret origin inside an earlier run; same-name repository or organization secrets remain prohibited and must be checked separately.
- Future releases also remain blocked until `main` enforces the full reviewed branch contract for administrators (strict `SwiftPM checks`, PR/CODEOWNERS/last-push approval, stale-review dismissal, conversation resolution, and no review bypass, force push, or deletion) and the `release` environment has a directly verified non-owner User reviewer. Team-only configuration is not treated as proof of another eligible human.
- Earlier local TeamID, hardened-runtime, notarization, stapling, LaunchDaemon allowlist, and Gatekeeper smoke checks passed for a locally built candidate. The published GitHub Release artifact has now repeated those checks independently; the local smoke remains corroborating preflight, not public artifact proof.

Historical source-first facts:

- The `v1.1.1` source tag points at `a82f2237ff39c24a6b366dca8f95a17ee54fd972`, and the SwiftPM CI gate passed for source, tests, release app bundle construction, bundle verification, temporary install-script verification, archive, and CI artifact upload before publication.
- `scripts/check-release-readiness.sh --mode source-first --version 1.1.1 --repo Reedtrullz/Vifty --source-sha a82f2237ff39c24a6b366dca8f95a17ee54fd972 --json` reports `ready` with the attached `Vifty-v1.1.1-unsigned-dev.zip` and checksum assets after verifying that the sidecar digest matches the zip bytes.
- Known issue: the published `v1.1.0` source/unsigned-dev release predates helper-install and app-polling hardening on `main` (`6b0690b`, `4f729d7`, and `3064b9e`). Users may see "Fan helper unreachable" after updating even on supported hardware.
- Do not retag `v1.1.0`, rebuild `Vifty-v1.1.0-unsigned-dev.zip` from later `main`, or claim the published `v1.1.0` convenience artifact is the official trusted binary. The honest remediation is the immutable `v1.1.1` source-first hotfix release, which remains permanently unsigned/not notarized as published; credentials obtained later cannot change that release boundary.
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
3. Verify required secret names on the protected GitHub `release` environment and the local signing/notarization path without storing certificate material, passwords, or secret values in the repo or Obsidian. Repository- and organization-scoped copies are outside the approved release boundary. The workflow constrains secret-reference placement but cannot report which scope supplied a resolved secret.
4. Keep the cask on the exact published manifest version/SHA during candidate work; repoint it only after the candidate artifact passes, the manifest is promoted, and the checksum handoff/public verifier pass.

All of these must be true before calling a future public binary release trusted:

1. `scripts/check-release-secrets.sh --repo Reedtrullz/Vifty` reports all required release secret names from the protected GitHub `release` environment; a missing/unreadable environment or credentials configured only outside it blocks the operator preflight. Separately confirm that no same-name repository or organization secrets exist, because a running workflow cannot attest the resolved secret's scope.
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

The public artifact, cask, and installed release-mode checks establish release identity, integrity, signed helper parity, and a safe System-managed installation. The separate supervised report establishes explicit Fixed → Auto → Curve → Auto behavior for exact v1.3.2 build 7 on `MacBookPro18,1`. Neither claim extends to another Vifty build, model identifier, agent-run workflow, or broad Apple Silicon compatibility.
