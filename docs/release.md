# Release Process

<!-- BEGIN GENERATED RELEASE FACTS -->
> Release facts authority: `.github/release-manifest.json` (schema `docs/schemas/release-manifest.schema.json`).
> Published: `v1.3.2` (version `1.3.2`, build `7`), `arm64` only, minimum macOS `15.0`.
> Runtime identities: app `tech.reidar.vifty`, daemon `tech.reidar.vifty.daemon`, helper `tech.reidar.vifty.helper`, CLI `tech.reidar.vifty.ctl`.
> Canonical artifact: `Vifty-v1.3.2.zip` with checksum asset `Vifty-v1.3.2.zip.sha256` and SHA-256 `8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0`.
> Public artifact trust: `passed` / `developer-id-notarized` for TeamID `X88J3853S2`; source `6a771c2ea10386bf7a0a8369a759930f01d56062`, CI run `29284751837`, Release run `29285576026`.
> Tag policy: `v1.3.2` remains recorded as `historical-unsigned` evidence; signed tags are mandatory from version `1.3.3` onward.
> Separate exact-build claims: installed release review `passed`; manual Fixed/Curve/Auto compatibility `passed-auto-restored` on `MacBookPro18,1` only (review `docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/review-result.json`; attestation `docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/manual-smoke-attestation.md`).
<!-- END GENERATED RELEASE FACTS -->

Vifty has two release modes:

- **Source-first release:** used when Developer ID credentials are unavailable. The GitHub Release is the source tag plus release notes, with an optional clearly marked unsigned tester app zip.
- **Developer ID release:** trusted binary lane. Artifacts must be Developer ID signed, notarized, stapled, and tied to the same TeamID that the privileged daemon enforces over XPC.

For the current public release trust state, see [release-status.md](release-status.md). Keep that page updated when a release workflow fails, succeeds, or when the cask checksum is updated.

Release-availability checking, manual public-archive installation, and future in-place updating are three separate trust lanes. Source-first, unsigned-dev, local ad-hoc, and CI builds must remain ineligible and make zero update requests. The checker is absent from the current `v1.3.2` artifact. The manual bridge takes only an operator-supplied archive selected as the reviewed checkout's current `publishedRelease`, performs no download, verifies the manifest-pinned SHA plus Developer ID/notarization evidence, and enters the existing fail-closed replacement transaction. Do not enable Sparkle for those artifacts; the checker, manual bridge, and future installer requirements live in [auto-update.md](auto-update.md).

## Manual Published-Archive Install

After publication, manifest promotion, and review of the exact public archive, an operator can install that current published release without rebuilding it:

```sh
scripts/install-vifty.sh --public-release-archive /absolute/path/Vifty-vX.Y.Z.zip
# or
make install-public-release PUBLIC_RELEASE_ARCHIVE=/absolute/path/Vifty-vX.Y.Z.zip
```

Use a reviewed checkout whose `.github/release-manifest.json` has already promoted the intended version to `publishedRelease`. The bridge starts at `v1.4.0`, when the public bundle includes the root snapshot binding contract. The command refuses a candidate, historical entry, direct `.app`, URL, relative path, noncanonical name, or SHA override. It first requires the exact pinned archive checksum and verified signed tag/signer-policy continuity, then performs bounded private extraction and complete content binding. A no-skip verifier result plus independent extracted-bundle checks must then pass version/build, bundle identities, Developer ID TeamID, deep signing, notarization/stapling, and Gatekeeper before installation begins. Installation uses a private per-destination lock and the same Auto/System replacement preflight, authority freeze, exact root snapshot, post-swap verification, and rollback transaction as the source-build lane; it refuses authenticated downgrades and never retries at a second destination after replacement starts. This command does not fetch GitHub, is not invoked by **Update to latest version**, and is not a Sparkle or automatic-update path.

## Source-First Release Mode

Use this mode when Apple Developer Program credentials are unavailable. It does not create a trusted public binary and must not claim Developer ID signing, notarization, stapling, Gatekeeper approval, or Homebrew trust.

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

   The Makefile target requires the current source to match `v<version>` by default. If you are building from an unpublished candidate, run the script directly with `--require-source-ref <candidate-ref-or-sha>` or set `UNSIGNED_DEV_SOURCE_REF=<candidate-ref-or-sha>` intentionally. Do not build a `Vifty-v<version>-unsigned-dev.zip` from later `main` hardening, and do not use `Vifty-v<version>.zip` or `Vifty-v<version>.zip.sha256` for an unsigned build. Those names are reserved for Developer ID signed and notarized artifacts.

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

### Developer ID Ownership And Secret Hygiene

Use only the Apple Developer team intentionally designated to own Vifty's public signing identity, GitHub Release trust, Homebrew trust, support burden, and revocation risk. Do not borrow a different organization's Developer ID certificate for a release.

Keep the signing boundary reproducible and private:

1. Keep the Developer ID workflow strict and require artifact verification before publication.
2. Configure the GitHub `release` environment for Vifty's explicit solo-maintainer policy: no required-reviewer rule, administrator bypass disabled, `protected_branches: false`, `custom_branch_policies: true`, no branch policy, and exactly one custom deployment policy with type `tag` and pattern `v*`. This admits the immutable signed-tag workflow ref while rejecting branch-based deployment. A YAML `environment: release` declaration alone is not proof of protection because GitHub can create a referenced missing environment with permissive defaults. There is no eligible second human release reviewer in the current policy: zero required approvals is an explicit solo-maintainer constraint, not independent review evidence, and release records must not invent a reviewer or label the absence of a reviewer as approval. After release prep is merged and exact-commit CI passes, and immediately before creating the release tag, an authenticated repository administrator runs `scripts/create-signed-release-tag.sh`. The tag creator invokes the exact committed `scripts/check-release-governance.sh` itself to bind that protected-main SHA to the complete environment, branch, secret-scope, tag-absence, and no-bypass tag-ruleset contract; it embeds those exact live bytes, verifies signature and current freshness, then repeats the full live readback after signing. It never accepts caller-authored evidence. The trusted `sign-notarize` job separately checks out the exact signed-tag `github.sha`, validates the embedded evidence with the committed `scripts/validate-release-governance-evidence.rb`, consumes the current-fresh admission record persisted by the read-only prepare job, and repeats only the governance facts available through GitHub's public API before any step consumes a signing secret. GitHub may resolve repository secrets when the workflow is queued; this ordering constrains use, not GitHub's internal read time. A future move to peer approval must be a reviewed policy change rather than a dormant or misleading reviewer count.
3. Keep Sparkle installation keys out of `Resources/Info.plist` until a separately verified signed-appcast installer release is ready. The advisory GitHub release checker does not require or imply `SUFeedURL`, `SUPublicEDKey`, an appcast, executable download, or in-place installation.
4. Store certificate material, `.p12` passwords, Apple app-specific passwords, and other secret values only in the local keychain or the repository's GitHub Actions secrets; never commit them or record them in project notes. Vifty deliberately retains its existing six repository-scoped release secrets for the solo-maintainer workflow. Do not add same-name environment copies: GitHub would give those values precedence inside the environment-bound job. The operator preflight requires all six repository names and rejects every matching environment name. The workflow contract allowlists the exact six `${{ secrets.NAME }}` references and permits them only on the protected `sign-notarize` job after the non-secret validation steps.
5. Run the local signing/notarization smoke test and the release-secret name preflight before pushing a public tag.

## Required GitHub Repository Secrets

Configure these six GitHub Actions secrets at repository scope before running the `Release` workflow. The name-only operator preflight calls both `gh secret list --repo ...` and `gh secret list --env release --repo ...`; it never reads values. It requires all repository names and rejects any same-name environment secret. Environment protection and secret storage are separate controls here: the environment admits only a custom `tag: v*` deployment policy with administrator bypass disabled, while the checked-in workflow contract confines all secret references to the exact protected signing job.

- `APPLE_TEAM_ID` — Apple Developer TeamID used for signing and XPC allowlisting.
- `APPLE_ID` — Apple ID email for `xcrun notarytool`.
- `APPLE_APP_SPECIFIC_PASSWORD` — app-specific password for notarization.
- `DEVELOPER_ID_APPLICATION_IDENTITY` — exact codesign identity, for example `Developer ID Application: Example, Inc. (TEAMID)`.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64` — base64-encoded `.p12` Developer ID Application certificate.
- `DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD` — password for the `.p12`.

## Developer ID Version Requirements

Before tagging a Developer ID release, add a non-null `candidate` to `.github/release-manifest.json` and align the candidate identity without repointing Homebrew:

- `.github/release-manifest.json` candidate `version`, `build`, tag, and canonical asset names
- `Resources/Info.plist` `CFBundleShortVersionString`
- `Resources/Info.plist` monotonically increasing `CFBundleVersion`
- Git tag, formatted as `v<version>`

The candidate build must be greater than the published build. `Casks/vifty.rb` must remain exactly on the manifest's published version and SHA until the new notarized artifact exists, passes verification, and the candidate is promoted; pointing the cask at an unpublished candidate would create a broken install URL/checksum. The release workflow fails if the tag-derived version, candidate, bundle version/build, published cask version/SHA, release artifact names, cask signing metadata, safe bundled uninstall lifecycle, TeamID-gated daemon build configuration, notarization/stapling gates, verifier signature/notarization checks, Gatekeeper assessment, or GitHub Release asset publication does not align. A candidate checksum may remain `null` until the notarized zip exists; only the protected pre-publication verifier may use a differing explicit `--expected-sha` from the just-created sidecar. Current and historical published entries are always verified against their immutable manifest SHA, and every selected entry—including a candidate—must resolve `releaseSourceCommit` from the exact manifest tag's peeled commit. The Homebrew cask remains bound only to the current `publishedRelease`.

`historicalReleases` is append-only. CI materializes the prior manifest and its continuity checker from the trusted PR base, push-before commit, or exact first parent. Existing historical entries must remain an unchanged prefix; when `publishedRelease` changes, the previous published object must be appended unchanged exactly once. A missing prior manifest is accepted only for the pinned initial v1.3.2 manifest introduction.

In a version-2 verifier summary, `releaseVersion`, `releaseTag`, `releaseSourceCommit`, `releaseManifestEntryKind`, and `releaseManifestSHA256` bind the evidence to the exact `.github/release-manifest.json` bytes stored at the peeled release-tag commit. Promotion does not rewrite that immutable identity: a summary created from a tagged `candidate` remains a candidate-snapshot summary after the current manifest moves the release to `publishedRelease` and later `historicalReleases`. Evidence collection/review separately requires the current authoritative manifest to preserve the tagged version/build/tag/artifact asset names, bind `sourceCommit` to the peeled tag commit, and pin the summary's actual artifact SHA. Passed summaries contain the exact unique 14-check verifier set, with every check marked `passed` in `release-trust` scope. The protected release workflow may temporarily verify a current candidate with a null manifest SHA only because the protected publication contract independently carries that just-built SHA into the write-scoped publish job. Legacy schema-version-1 evidence acceptance is limited to the exact public v1.3.2 artifact and its historical check set; a separate verifier-only v1.3.2 fallback exists because that tag predates the manifest file, but its generated v2 result is not accepted by strict evidence collection/review. Later releases cannot use either escape hatch. The workflow must not pass verifier skip flags that disable public signature or notarization checks. The cask must not declare `signing_identity identity: "-"` or bypass the bundled lifecycle with direct `sudo launchctl`/`rm` teardown.

The candidate notarized release asset is named `Vifty-v<version>.zip`; `Casks/vifty.rb` points at that name only after candidate promotion and checksum handoff.

## Developer ID Release Checklist

1. Confirm the release secrets are configured:

   ```sh
   scripts/check-release-secrets.sh --repo Reedtrullz/Vifty
   ```

   This checks only secret names, never values. It should report all required repository-scoped Developer ID and notarization names and confirm that the `release` environment contains no same-name shadow before a release tag is pushed. A Release workflow run is never rerun; if an original transaction conclusively fails without publication and a new patch is prepared, repeat this preflight for that new tag. An unreadable scope, missing repository name, or matching environment name blocks the operator preflight.

2. Update `CHANGELOG.md`: move `Unreleased` entries under the new version and date. Add the release candidate to `.github/release-manifest.json`, choose a build number greater than the published build, and update `Resources/Info.plist` to the candidate version/build. Do not edit, delete, or reorder prior `historicalReleases`. During a later promotion, append the exact previous `publishedRelease` before replacing it. Keep `Casks/vifty.rb` exactly on the current published manifest version/SHA throughout candidate build, signing, notarization, and publication. The candidate SHA may remain `null` until the notarized artifact exists. Do not repoint or recommend Homebrew until the candidate is promoted and the public checksum has been applied and verified.

3. Run the exact local release gate on the prepared candidate:

   ```sh
   RELEASE_METADATA_MODE=developer-id make verify-full
   ```

4. Commit the release prep, merge it to protected `main`, and wait for CI to pass on that exact merged commit. The cask checksum and published manifest facts are post-publication follow-up changes.

5. Immediately after that exact-commit CI pass, move to a clean checkout of that exact protected-main commit and let the tag creator acquire the complete administrator-visible governance boundary itself:

   ```sh
   git fetch origin main --tags
   EXACT_MAIN_SHA="$(git rev-parse origin/main)"
   git switch --detach "$EXACT_MAIN_SHA"
   test "$(git rev-parse HEAD)" = "$EXACT_MAIN_SHA"
   test -z "$(git status --porcelain=v1 --untracked-files=all)"
   ```

   Before collecting governance evidence, the tag creator materializes the exact commit, runs that snapshot's manifest-history checker against the exact first parent, validates that snapshot's workflow contract and Info.plist version, and requires a successful completed `push` CI run whose branch is `main` and whose `headSha` is the exact release commit. It requires the complete reviewed release-tool set—including both workflows, governance/provenance/inventory/signing/verification scripts, the signer allowlist, and the pinned `gh` policy/verifier—to be byte-identical to the exact first parent, so a release-prep commit cannot silently revise its own release authority.

   The internally invoked administrator-authenticated read-only gate must show `apiHost: "github.com"`, `dataSource: "github-api-live"`, `evidenceScope: "administrator-pretag"`; the exact authenticated actor ID/login; the exact expected `main` SHA; proof that the tag is still absent; `releaseGovernanceMode: "solo-maintainer"`; no environment reviewer gate; `administratorsCanBypass: false`; `protected_branches: false`; `custom_branch_policies: true`; no branch policy; exactly one custom deployment policy with type `tag` and pattern `v*`; a required pull request with zero approvals and no bypass actors; strict Actions-owned `SwiftPM checks` enforced for administrators; conversation resolution; no force-push or deletion allowance; all six repository secret names with no environment shadow; exactly one active tag ruleset whose conditions are exactly `include: [refs/tags/v*]` and `exclude: []`, whose visible bypass list is empty, whose `rulesetUpdatedAt` is a canonical UTC revision no later than the observation, whose `currentUserCanBypass` is `never`, and whose rules are exactly `update` plus `deletion`; and the SHA-256 digests of the governance checker, environment checker, secret checker, `scripts/verify-release-gh-toolchain.rb`, and `.github/release-gh-toolchain.json`. Any missing, unreadable, ambiguous, stale, or drifting fact blocks tag creation.

   The workflow cannot truthfully re-prove administrator-only branch settings or the complete tag-ruleset bypass-actor list with its built-in token. It records `privilegedSettingsVerified: false` and `bypassActorsVerified: false`, while independently requiring the public environment policy, exact protected-main SHA, Actions-owned required check, the same ruleset ID/ref, exact `updated_at` revision, `current_user_can_bypass: "never"` for the workflow caller, and `update` plus `deletion` rules. It rechecks that exact public revision and caller-bypass state immediately before and after promotion. The signed administrator-pretag evidence proves the privileged empty-bypass-list facts at observation time; the workflow's public readbacks prove only the facts its token can observe during the run.

6. Create the signed annotated tag, then let the hardened helper push that exact object and observe the automatically triggered workflow:

   ```sh
   scripts/create-signed-release-tag.sh \
     --tag v<version> \
     --commit "$EXACT_MAIN_SHA" \
     --evidence-output .build/release-governance-administrator-pretag.json
   scripts/push-and-dispatch-signed-release-tag.sh \
     --tag v<version> \
     --commit "$EXACT_MAIN_SHA"
   ```

   `scripts/create-signed-release-tag.sh` requires a clean checkout at the exact commit, complete first-parent release-tool/signer/toolchain continuity, the exact committed manifest/workflow gates, and an exact-main successful push-CI run before it invokes the exact committed governance checker against github.com. It verifies the Apple or 1Password signing program's exact code-signing requirement, removes GitHub credentials from the signer's environment, embeds the same-actor live evidence bytes in the annotated tag, signs it, verifies the exact annotated-tag object against the continuous signer policy, enforces freshness again after the interactive signing prompt, and repeats the full live governance/tag-absence/main/ruleset ID/revision/current-caller-bypass check before reporting success. It never accepts caller-authored evidence and never pushes. `scripts/verify-release-gh-toolchain.rb` copies and verifies the reviewed Darwin arm64 `gh` bytes before token access, and both verifier/policy hashes are bound into the signed governance evidence. Despite its retained filename, `scripts/push-and-dispatch-signed-release-tag.sh` never calls `workflow_dispatch`: it repeats the clean-tree, signature, first-parent continuity, exact-main CI, current signed-evidence, same-actor live governance, remote-main/tag/branch checks, and an authenticated paginated scan proving that no draft or published release owns the tag; pushes only the captured annotated-tag object to the literal github.com tag ref with an absent-ref compare-and-swap lease; and reads back the exact remote tag object and peeled commit. That tag push automatically starts `Release <tag>`. The helper resolves the numeric Release workflow ID only to correlate and verify exactly one `push`-event run at attempt 1, including its actor ID/login, repository, workflow path/ID, tag, commit, URL, and creation time. Immediately before the push boundary it atomically creates `~/Library/Application Support/Vifty/ReleaseTransactions/Reedtrullz-Vifty/<tag>/retired.json`; it keeps the private `receipt.json` beside that checkout-independent marker. The marker and receipt are inspection evidence only and never authorize a retry. Do not replace this helper with raw push commands, manual workflow dispatch, or a workflow rerun.

   Remote proof stops at the GitHub boundary. The workflow can verify the signed annotated tag, embedded governance evidence, actor, ref, commit, push event, and run attempt, but GitHub cannot attest that the local helper ran or that `retired.json` or `receipt.json` exists. The sole signer/repository administrator is therefore an explicit operational trust root not to bypass the supported helper with a raw tag push or out-of-band GitHub Release create, edit, or delete. Such a path is unsupported and lacks the local one-shot transaction guarantee even if every remote admission check passes; it never authorizes manual dispatch or rerun.

   Treat the helper as a one-shot transaction. A failure conclusively proven to precede both creation of the durable retired-tag marker and any remote mutation may be retried only after reacquiring fresh gates and proving the exact remote tag ref is still absent. Once that marker exists or the push began—including an unknown push result, duplicate or concurrent creation, accepted-but-unconfirmed push, post-tag governance failure, missing/ambiguous run observation, or mismatched run verification—do not invoke the helper a second time, dispatch manually, rerun the workflow, or delete, move, or reuse the tag. Inspect the original `retired.json`, `receipt.json`, immutable tag, first-attempt workflow run, and release state; while the outcome is inconclusive, keep inspecting rather than starting a replacement transaction. If the original transaction is conclusively shown not to have published, cut a new patch version.

   Future signed-tag policy starts at the manifest's non-null `signedTagsRequiredFromVersion`; the historical unsigned `v1.3.2` record remains evidence and is not rewritten. Release publication is triggered only by pushing the exact signed `v*` tag. The first and only permitted workflow attempt must admit that tag within the 15-minute live-evidence window and persist the current-fresh admission in the hashed candidate handoff, whose canonical complete-tree inventory also binds the archive and admission bytes. A missed admission window, rejected first attempt, or other failure is never repaired by manual dispatch or rerun; once non-publication is conclusive, prepare a new patch version rather than reusing the immutable tag. Later signing, notarization, and publication steps validate the persisted admission record and current live facts without extending that initial 15-minute window across the entire release. The workflow revision must be the exact signed-tag commit. It extracts the embedded evidence and runs the committed `scripts/validate-release-governance-evidence.rb`, which binds the observation start/end, tag name, tagger time, protected-main/tag commit, committed checker/dependency SHAs, ruleset revision/current-caller-bypass state, and initial admission freshness. The verified annotated-tag object SHA, peeled commit SHA, governance-evidence digest, signed ruleset ID/revision, and admission digest are carried in the publication contract and rechecked around promotion.

7. Watch the automatically triggered first-attempt `Release <tag>` workflow. It will:

   - validate the manifest candidate, exact-first-parent signer-policy continuity, exact tag-object signature, and bundle version/build;
   - extract the exact administrator-pretag evidence embedded in the signed annotated tag and validate its committed checker SHA, freshness, tag/tagger/main identity, and privileged governance contract;
   - verify remote tag-object parity, protected-main ancestry, manifest history against the exact first parent, and a successful completed main-push CI run for the exact tag commit;
   - validate candidate bundle identity while proving the cask still names the exact published manifest artifact and SHA;
   - run pinned, checksum-verified `actionlint`, the full XCTest suite, warnings-as-errors build, and ad-hoc app assembly in the read-only prepare job;
   - create a canonical complete candidate inventory covering every directory, regular file content/size/mode, and relative in-bundle symlink target, plus the normalized archive size/digest and current-fresh admission-provenance size/digest; round-trip that archive and upload exactly the archive, admission, and inventory with no extra handoff entries;
   - enter the protected GitHub `release` environment and complete the non-secret governance and provenance steps before any step consumes a signing secret;
   - check out the exact trusted signed-tag workflow revision separately, inventory its workflows, workflow-contract checker, release scripts, schemas, manifest, cask, and entitlements, validate that exact workflow contract, then revalidate the trusted inventory around protected execution;
   - download the exact three-file handoff, reject missing or extra entries, verify archive/admission bytes before and after extraction, safely extract only `Vifty.app`, and require the complete extracted tree to equal the recorded inventory without executing release scripts supplied by the candidate tag;
   - import the Developer ID Application certificate with private file modes into a temporary keychain, bind `codesign` to that keychain, and sign the already-built candidate without SwiftPM, tests, or a general `make` target;
   - verify all signing identifiers, TeamID, bundle/daemon identities, build number, exact architectures, hardened runtime flags, and exact manifest-authorized app entitlements;
   - submit the app to Apple notarization;
   - staple the notarization ticket;
   - delete the temporary keychain and certificate in an `always()` cleanup step;
   - zip `Vifty.app` as `Vifty-v<version>.zip`;
   - verify the generated zip artifact against its just-created checksum, signing TeamID, hardened runtime/entitlements, stapling, Gatekeeper state, and bundled schemas exactly matching the manifest-authorized source contracts;
   - write `Vifty-v<version>-artifact-summary.json`;
   - write `Vifty-v<version>-release-checklist.md`;
   - pass only the verified assets to a separate publication job, the only job with `contents: write`; that job rechecks the full v2 identity/build/architecture/check-array contract, checklist structure, and contract-bound public tag ruleset ID, revision, current-caller no-bypass state, ref coverage, and update/deletion rules before publishing the zip, SHA-256 checksum, verification summary, and release checklist;
   - generate a cryptographically random run-unique ownership nonce, place its exact marker in the draft body and nonce in the draft title, REST-create the draft, and capture its immutable GitHub release database ID directly from that mutation response;
   - upload every canonical asset through the GitHub uploads API path containing that captured database ID; bind each upload response's immutable asset ID, name, byte size, `uploaded` state, and `sha256:` digest, and require the exact returned release body and complete asset records in every pre/post-promotion GET-by-ID readback; tag-addressed create, edit, upload, and delete commands are forbidden;
   - refuse promotion unless the exact tag object/commit and the public update/deletion ruleset ID and `updated_at` revision still match the signed governance evidence and the workflow caller still reports `current_user_can_bypass: "never"`, then use only the captured database ID for promotion or containment mutations;
   - query the release post-state after every create, upload, promote, or re-draft outcome; a nonzero or ambiguous mutation, identity mismatch, signal, or failed final readback arms an ID-based re-draft, and the job hard-fails if a subsequent immutable-ID readback cannot prove `draft: true` plus the exact ownership marker;
   - if REST creation returns an ambiguous response before an ID is trusted, discover by tag only to locate a unique draft whose numeric ID, exact tag, draft title/state, empty initial asset set, and cryptographically random marker all match this run; an unrelated by-tag release is never patched, even when that makes containment a hard failure;
   - prepend the release checklist to generated GitHub Release notes.

   Published-artifact verification is version-pinned, not partially pinned: schemas, executable support-script destinations, the complete bundled workload-wrapper set, and app entitlements are derived from the published manifest entry's exact `sourceCommit`. Candidate verification deliberately uses the current checkout policy. CI therefore checks out full Git history (`fetch-depth: 0`); if a published source commit or any required historical contract file is unavailable or invalid, verification fails closed rather than applying future `main` policy to old immutable bytes.

8. After the exact public artifact and sidecar checksum exist and pass verification, append the complete existing `publishedRelease` object unchanged to the end of `historicalReleases`; never edit, delete, or reorder earlier history entries. Then replace `publishedRelease` with the exact candidate facts: version/build/tag, source commit, exact source-CI and Release run IDs, four canonical asset names, SHA-256, and trust states; finally clear `candidate`. The appended history entry must remain fact-for-fact identical to the prior current entry, and the new current version/build must be greater than every historical entry. Do not promote the manifest before those public facts exist. Apply the same authorized SHA-256 to `Casks/vifty.rb`:

   ```sh
   git switch -c codex/v<version>-release-facts
   RELEASE_ASSET_DIR="$PWD/.build/release-assets/v<version>"
   rm -rf "$RELEASE_ASSET_DIR"
   mkdir -p "$RELEASE_ASSET_DIR"
   gh release download v<version> --repo Reedtrullz/Vifty \
     --dir "$RELEASE_ASSET_DIR" \
     --pattern 'Vifty-v<version>.zip' \
     --pattern 'Vifty-v<version>.zip.sha256' \
     --pattern 'Vifty-v<version>-artifact-summary.json' \
     --pattern 'Vifty-v<version>-release-checklist.md'
   scripts/update-cask-checksum.sh \
     --checksum-file "$RELEASE_ASSET_DIR/Vifty-v<version>.zip.sha256" \
     --version <version>
   ```

   The updater accepts the normal `shasum -a 256` output from the release workflow, requires the target version, artifact name, and checksum to match the newly promoted published manifest, writes and validates a same-directory sibling candidate, then atomically renames it over the cask. It restores the original cask with the same rename discipline if final release-metadata validation fails. Then run `scripts/render-release-facts.sh --write`, `scripts/check-release-manifest.sh`, and `scripts/render-release-facts.sh --check` before committing the manifest/cask/docs follow-up. The fact check also rejects prose that still labels an older version as current.

9. Verify the public artifact and cask agree:

   ```sh
   scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"
   ```

   This downloads the cask URL unless `--artifact <zip>` is provided, checks the SHA-256, extracts `Vifty.app`, verifies bundle version, required executables, and bundled `Contents/Resources/schemas` JSON Schemas exactly matching the manifest-authorized source contracts for release-readiness, release-artifact-summary, agent-cooling evidence summary/review, agent-run smoke evidence summary, validation-report-index, validation-review-result, and `viftyctl`, verifies the bundled read-only and supervised agent evidence collector scripts, validates plist files, checks Developer ID TeamID alignment including the LaunchDaemon `VIFTY_XPC_ALLOWED_TEAM_ID`, verifies hardened runtime flags and exact app entitlements, validates stapling, and runs Gatekeeper assessment. The release workflow runs the same verifier before publishing with `--expected-sha` because the final cask checksum follow-up commit does not exist yet, and publishes the verifier's JSON summary as release evidence. The summary declares `schemaID: https://vifty.local/schemas/release-artifact-summary.schema.json`, and release evidence review rejects summaries with a missing or drifted schema identity. When `--summary` is provided and a release-trust check fails, including manifest or other early setup failures, the verifier writes a schema-valid failed summary naming the failing check so reviewers do not have to reconstruct the failure from transient logs alone.

   If this fails after an artifact has already been published, cut a corrected patch release instead of treating the Homebrew cask as trusted.

10. After publication, first populate the checksum follow-up worktree with the exact public manifest facts and cask checksum from step 8. Before committing or merging that follow-up, run `git fetch origin main --tags` and `scripts/check-release-readiness.sh --mode developer-id --version <version> --repo Reedtrullz/Vifty --require-source-ref v<version> --json`. The readiness checker intentionally does not treat an unpromoted `candidate` as an authoritative public release, so it cannot pass until the follow-up worktree records the exact source-CI run, Release run, artifact digest, and trust states under `publishedRelease`. Keep the passed schema-backed JSON with release notes or validation evidence. After the follow-up moves `main`, rerun against the immutable tag or release commit rather than `origin/main`; the final JSON should show `releaseMode: "developer-id"` plus `release-source-ref`, `source-ci`, `release-workflow`, `release-secrets`, and `github-release` all passed.
11. After publication, verify on hardware with [hardware-validation.md](hardware-validation.md). Prefer `scripts/collect-validation-evidence.sh --app /Applications/Vifty.app --release-summary ./Vifty-v<version>-artifact-summary.json --release-checklist ./Vifty-v<version>-release-checklist.md` so release reports include the same read-only evidence bundle, including `review-summary.tsv`, `review-summary.json`, `bundle-executables.tsv`, `schema-resources.tsv`, `capabilities-schema-resources.tsv`, `capabilities-contract.tsv`, `viftyctl-audit.json`, `release-artifact-summary.json`, `release-artifact-summary.tsv`, `release-checklist.md`, `release-checklist.tsv`, bundle plist, LaunchDaemon TeamID, per-binary signing, notarization, Gatekeeper files, the release verifier result, and the release checklist. The collector marks the release-summary row nonzero if the verifier result does not pass or if its version does not match the installed app being tested; it marks the release-checklist row nonzero if the checklist title version does not match the installed app or if required follow-up sections are missing; it marks the capabilities-contract row nonzero if the installed CLI stops advertising the safe `runLifecycle`, direct prepare/restore lifecycle, `policyStatusAvailable: true`, wrapper resource discovery, metadata limits, or force-retry discovery fields. Before treating the installed release as trusted, run `make validation-evidence-review VALIDATION_EVIDENCE_BUNDLE=<evidence-dir> VALIDATION_EVIDENCE_REVIEW_MODE=release VALIDATION_EVIDENCE_REVIEW_SUMMARY=<evidence-dir>/review-result.json` on the captured bundle and keep the schema-backed `review-result.json` with the report.
12. For the first release containing the advisory checker, verify that only the exact Developer ID signed Vifty identity is eligible; automatic checks use only `https://api.github.com/repos/Reedtrullz/Vifty/releases/latest`, run at most once per 24 hours, and can be disabled; availability acceptance requires a stable release with exactly the four canonical uploaded nonempty asset records; and **Update to latest version** opens the locally constructed tag page without downloading or installing executable code. These metadata checks are not archive, checksum-content, signed-tag, or notarization proof. Verify local ad-hoc, CI, source-first, and unsigned-dev builds make zero requests. The first capable public release must be installed manually because `v1.3.2` cannot gain this code retroactively. For any later Sparkle installer, additionally verify that `SUFeedURL` is HTTPS, `SUPublicEDKey` matches the protected EdDSA private key, signed appcast settings are enabled, `generate_appcast` produced the signed appcast for the canonical `Vifty-v<version>.zip`, and installation enters Vifty's existing Auto/System, daemon-quiescence, root-ledger, post-swap verification, and rollback transaction rather than replacing the bundle independently.
13. Update [compatibility.md](compatibility.md) only with report-backed results. Use `scripts/summarize-validation-reports.sh --input <reports-dir> --output-json <reports-dir>/compatibility-index.json --output-tsv <reports-dir>/compatibility-index.tsv --output-markdown <reports-dir>/compatibility-matrix.md` to index valid reviewed `review-result.json` files and draft a conservative Markdown matrix; each review result declares `schemaID: https://vifty.local/schemas/validation-review-result.schema.json`, the JSON index declares `schemaID: https://vifty.local/schemas/validation-report-index.schema.json`, and the indexer rejects missing or drifted review-result schema IDs, malformed, non-read-only, cooling-mutating, unsupported-mode, unsupported install-source, invalid or missing required source SHA/checksum, mutable or missing source refs for source-build tag evidence, unsupported `agentRunSmokeResult` values, missing or unsupported agent decision/recovery fields, malformed `manualControlActive`, or contradictory passed review outputs. Leave model families as "needs validation" until supported-hardware rows are indexed as `validated-hardware-evidence` from `manualSmokeTestResult: "passed-auto-restored"`. Preserve `recommendedAgentAction`, `recommendedRecoveryAction`, `safeToRequestCooling`, `daemonControlPathReady`, `manualControlActive`, `agentRunSmokeResult`, and `agentRunSmokeSource` as separate developer-workload and readiness proof for guarded `viftyctl run`; do not use it as a substitute for manual fan-control smoke evidence. Use the generated `compatibility-matrix.md`, model-family counts, recommended agent action, recovery action, `safeToRequestCooling`, daemon control-path readiness, and manual-control ownership counts to spot unsafe readiness clusters before publishing compatibility claims.

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
