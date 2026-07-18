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

Future Developer ID publication uses an explicit solo-maintainer governance boundary rather than pretending an unavailable peer review exists. There is no eligible second human release reviewer today: zero required approvals is not a reviewer pass and must never be recorded as one. As of the 2026-07-18 administrator readback, active GitHub ruleset `18940029` (`Immutable Vifty release tags`) covers `refs/tags/v*`, prevents update and deletion, has a visible empty bypass list, and reports that the current administrator cannot bypass it. The live `release` environment has no required-reviewer rule and administrator bypass is disabled. Its deployment admission is now tag-only: `protected_branches: false`, `custom_branch_policies: true`, no branch policy, and exactly one custom policy (`54991885`) with type `tag` and pattern `v*`. Both the administrator and workflow-public environment checkers passed that exact state. This readback resolves the prior protected-branch-only blocker; every release must still acquire fresh pre-tag governance evidence after exact-main CI rather than treating this point-in-time statement as permanent proof.

Protected `main` requires a pull request with zero approvals and no bypass actors, strict Actions-owned `SwiftPM checks` for administrators, conversation resolution, and forbids force pushes and deletion. The existing six release secret names remain deliberately repository-scoped for this solo-maintainer workflow; the environment contains no same-name copies, and the checked-in workflow contract restricts every secret reference to the protected `sign-notarize` job after its non-secret checks. Only after release prep merge and successful push CI on that exact `main` SHA may `scripts/create-signed-release-tag.sh` run. The creator requires both the signer allowlist and `.github/release-gh-toolchain.json` to be byte-identical to the exact first parent, runs the exact committed manifest-history and workflow-contract gates, copies and verifies the pinned Darwin arm64 `gh` bytes before token access, rechecks exact-main CI, invokes the exact committed `scripts/check-release-governance.sh`, proves tag absence and the privileged facts, embeds those exact live `administrator-pretag` bytes plus the verifier/policy hashes in the signed annotated tag, and repeats the full live readback before reporting success. Despite its retained filename, `scripts/push-and-dispatch-signed-release-tag.sh` does not dispatch: it revalidates those facts, creates only the exact absent annotated tag with a compare-and-swap push, reads it back, and observes the `Release <tag>` run that GitHub automatically creates for that tag push. It requires exactly one `push`-event run at attempt 1 and verifies its actor ID/login, repository, workflow path/ID, tag, commit, URL, and creation time. Immediately before the push boundary it creates a checkout-independent retired-tag marker and private receipt under `~/Library/Application Support/Vifty/ReleaseTransactions/Reedtrullz-Vifty/<tag>/`. Those files are inspection evidence only and never retry authorization. A failure conclusively before both marker creation and remote mutation may be retried with fresh gates and proven exact-ref absence; once the marker exists or the tag may exist, a second helper invocation, manual dispatch, workflow rerun, or deleting/moving/reusing that tag is forbidden. Inspect the original marker, receipt, immutable tag, first-attempt run, and release state while the outcome is inconclusive; cut a new patch version only after the original transaction is conclusively shown not to have published. The workflow validates the embedded evidence with the committed `scripts/validate-release-governance-evidence.rb`, carries a current-fresh admission record in a complete inventoried candidate handoff, requires the signed ruleset ID to match the narrower public ruleset readback, and rechecks the same public revision and its own no-bypass state before and after promotion. The manifest candidate records `v1.4.0` build `8` as pending until exact-main CI and signed-tag publication; no release is authorized by candidate metadata alone.

This solo-maintainer design has an explicit remote-proof limit. GitHub can verify the signed annotated tag, embedded governance, actor/ref/commit, push event, and first attempt, but it cannot prove that the supported local helper created `retired.json` and `receipt.json`. The sole signer/repository administrator is therefore trusted not to bypass that helper with a raw tag push or out-of-band GitHub Release mutation. Either bypass is unsupported and lacks the local one-shot transaction guarantee even if remote admission passes; manual dispatch and rerun remain forbidden.

Release lanes:

1. **Published Developer ID release:** `v1.3.2` public artifact and cask trust checks passed for the tagged workflow, canonical assets, checksum handoff, public verifier, release readiness, TeamID, notarization, stapling, and Gatekeeper. Installed helper parity, explicit Auto restoration, and manual Fixed/Curve compatibility also passed as separately reviewed claims for exact build 7 on `MacBookPro18,1`; they do not transfer to other builds or models.
2. **Source release:** `v1.1.1` remains the published source-first fallback. Do not claim it or any unsigned-dev artifact is Developer ID signed, notarized, stapled, Gatekeeper-approved, or Homebrew-trusted.
3. **Unsigned convenience app zip:** optional tester convenience only. The attached hotfix artifact is named `Vifty-v1.1.1-unsigned-dev.zip` with `Vifty-v1.1.1-unsigned-dev.zip.sha256`. The unsigned-dev zip is valid only with its `.sha256` sidecar, and the SHA-256 digest in that sidecar must match the zip bytes. It is ad-hoc signed, not notarized, not the official trusted binary, and may trigger macOS Gatekeeper warnings.

Update status: the exact public `v1.3.2` binary has no update checker and cannot gain one retroactively. Current source contains an advisory release-availability checker for the first future exact Developer ID release, which must be installed manually. Eligible builds may check only the fixed GitHub latest-release endpoint at most daily with an opt-out; availability metadata is accepted only when its stable version and exact four canonical uploaded nonempty asset records validate, and **Update to latest version** opens the locally constructed tag page. The checker does not download or install executable code, and its filename/size checks are not archive, checksum, signed-tag, or notarization proof. Current source also provides a separate manual operator bridge, `scripts/install-vifty.sh --public-release-archive /absolute/path/Vifty-vX.Y.Z.zip`, for promoted `v1.4.0` and newer releases whose bundles carry the root snapshot binding contract. It performs no network request, selects only the reviewed checkout's current `publishedRelease`, verifies its exact pinned checksum, signed tag, and Developer ID/notarization evidence without skips, and feeds bounded extraction into the existing fail-closed app-replacement transaction. It cannot install `v1.3.2`, a candidate, historical release, direct app bundle, URL, or API-selected asset. Local ad-hoc, CI, source-first, and unsigned-dev builds make zero update requests. A future Sparkle signed-appcast installer remains separate work and must use Vifty's existing app-replacement transaction; see [auto-update.md](auto-update.md).

Public release facts:

- Release candidate metadata in `Resources/Info.plist` is staged at `1.4.0` build `8`, while `Casks/vifty.rb` remains pinned to published `1.3.2` with SHA-256 `8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0`; candidate signing, installation, and hardware evidence remain pending.
- Source CI run `29284751837` passed on release commit `6a771c2ea10386bf7a0a8369a759930f01d56062`, and Release run `29285576026` passed all signing, notarization, pre-publication verification, checklist, and publication steps.
- The GitHub Release publishes `Vifty-v1.3.2.zip`, `Vifty-v1.3.2.zip.sha256`, `Vifty-v1.3.2-artifact-summary.json`, and `Vifty-v1.3.2-release-checklist.md`.
- The published workflow summary and an independent downloaded-artifact verification both passed with TeamID `X88J3853S2`, no signature skips, and no notarization skips.
- `scripts/check-release-readiness.sh --mode developer-id --version 1.3.2 --repo Reedtrullz/Vifty --require-source-ref 6a771c2ea10386bf7a0a8369a759930f01d56062 --json` reported `ready` before the cask follow-up moved `main`.
- Independent verification of the downloaded public `v1.3.2` artifact passed. Exact-build installed release-mode, signed-helper parity, Auto-restoration, and manual Fixed/Curve compatibility are now reviewed for build 7 on `MacBookPro18,1`; broad hardware and future-release claims remain unmade.
- The `v1.3.2` workflow used the release credentials configured at that time; the historical run does not prove their repository-versus-organization scope. Current solo-maintainer releases deliberately use the six repository-scoped names. `scripts/check-release-secrets.sh --repo Reedtrullz/Vifty` reads repository and `release`-environment secret names only; it never reads values. The protected `release` environment is a deployment/provenance control and must not contain same-name shadow copies. Static workflow validation restricts all six secret references to the protected `sign-notarize` job.
- Solo-maintainer branch, tag-ruleset, and release-environment governance are live: the environment has no reviewer gate, disables administrator bypass, and admits only the single `tag: v*` policy with no branch policy; both administrator and workflow-public checks passed on 2026-07-18. `main` requires a PR with zero approvals and no bypass actors, enforces strict Actions-owned `SwiftPM checks` for administrators plus conversation resolution, and disables force-push/deletion. The absent peer reviewer is disclosed, not replaced with fictitious approval. Only after release prep merges and exact-main push CI passes may the tag creator embed fresh administrator-pretag evidence and the one-shot tag-push helper create the exact remote tag; that push automatically triggers the only permitted first-attempt Release run. A future move to peer review requires an explicit policy change.
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

1. Keep Sparkle installation metadata out of `Resources/Info.plist` unless a separate signed-appcast installer release has been reviewed. The advisory GitHub release checker is not an in-place installer and does not authorize `SUFeedURL` or `SUPublicEDKey`.
2. Keep `.github/workflows/release.yml` strict about Developer ID signing, `VIFTY_XPC_ALLOWED_TEAM_ID`, notarization, stapling, Gatekeeper, artifact verification, and release checklist publication.
3. Prepare the manifest/Info.plist/changelog candidate, keep the cask on the exact published manifest version/SHA, merge the prep through protected `main`, and require CI to pass on that exact merged SHA.
4. Verify the six required repository-scoped secret names and the local signing/notarization path without storing certificate material, passwords, or secret values in the repo or Obsidian. The name-only preflight must also confirm that the `release` environment contains no same-name shadow. The workflow contract constrains every secret reference to the protected `sign-notarize` job.
5. Only after that exact-main CI pass, run `scripts/create-signed-release-tag.sh --tag v<version> --commit <exact-main-sha> --evidence-output .build/release-governance-administrator-pretag.json`. It requires the complete reviewed release-tool set, release signer allowlist, and `.github/release-gh-toolchain.json` to be byte-identical to the exact first parent; privately copies and verifies the pinned Darwin arm64 `gh` bytes before token access; verifies the Apple/1Password signing program while keeping GitHub credentials out of its environment; runs the exact committed manifest/workflow gates and exact-main successful push-CI check; and embeds same-actor live administrator-pretag evidence plus verifier/policy hashes in the signed tag. It does not accept caller-authored evidence or push.
6. Push only that exact tag with the one-shot helper. It first uses the same authenticated actor to prove exact `refs/tags/v*` update/deletion governance and paginated absence of every draft or published release for the tag, creates the durable retired-tag marker immediately before the push boundary, then verifies the exact remote object and requires exactly one automatically triggered `push`-event Release run at attempt 1 whose actor ID/login, repository, workflow path/ID, tag, commit, URL, and creation time match the transaction. The checkout-independent `retired.json` and `receipt.json` under `~/Library/Application Support/Vifty/ReleaseTransactions/Reedtrullz-Vifty/<tag>/` are inspection evidence, not retry authorization. A failure conclusively before marker creation and remote mutation may be retried only after fresh gates prove the exact ref remains absent. Once the marker exists or the tag exists or may exist after any unknown, duplicate, accepted-but-unconfirmed, post-tag, missing-run, ambiguous-run, or mismatched-run outcome, do not invoke the helper again, dispatch manually, rerun the workflow, or delete, move, or reuse the tag. Inspect the original marker, receipt, immutable tag, first-attempt workflow run, and release state while the outcome is inconclusive, and cut a new patch version only after the original transaction is conclusively shown not to have published. The workflow must admit the embedded evidence while it is still current-fresh; carry the archive, complete tree inventory, and admission provenance as the exact candidate handoff; validate them with trusted committed tooling; and bind the signed ruleset ID/revision to the same public ruleset with `current_user_can_bypass: "never"` before and after promotion.
7. If the initial admission window is missed, cut a new patch version rather than reusing or moving the immutable tag.
8. Repoint the cask only after the candidate artifact passes, the manifest is promoted, and the checksum handoff/public verifier pass.

All of these must be true before calling a future public binary release trusted:

1. `scripts/check-release-secrets.sh --repo Reedtrullz/Vifty` reports all six required repository-scoped release secret names and a passed `release`-environment shadow check; a missing name, unreadable scope, or matching environment name blocks the operator preflight.
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
