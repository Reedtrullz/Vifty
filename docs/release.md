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

## Source-First Release Mode

Use this mode when Apple Developer Program credentials are unavailable. It does not create a trusted public binary and must not claim Developer ID signing, notarization, stapling, Gatekeeper approval, or Homebrew trust.

Sparkle auto-update is separate trusted-release work. Do not enable Sparkle for source-first, unsigned-dev, or the current `v1.3.2` artifact. The updater requirements and test plan live in [auto-update.md](auto-update.md).

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
2. Configure the GitHub `release` environment with at least one directly verified non-owner User reviewer, self-review prevention, and administrator bypass disabled. A Team slug alone is not accepted because the environment response does not prove that the Team contains another eligible human. A YAML `environment: release` declaration alone is not proof of protection: GitHub can create a referenced missing environment without protection rules, and GitHub otherwise allows administrators to bypass protection by default. The trusted `sign-notarize` job therefore checks out the exact protected-main `github.sha`, hashes and runs its workflow contract plus `scripts/check-release-environment.sh --repo Reedtrullz/Vifty` before any signing-secret reference is evaluated. That checker also requires strict `SwiftPM checks` from GitHub Actions, branch protection enforced for administrators, at least one approving pull-request review, stale-review dismissal, CODEOWNERS review, approval after the latest push, conversation resolution, and no pull-request bypass, force-push, or deletion allowance. Its normalized readback is SHA-bound into the publication contract, revalidated by the isolated publish job, and retained in the private workflow handoff artifact for 90 days.
3. Keep Sparkle updater keys out of `Resources/Info.plist` until a separately verified signed-appcast release is ready.
4. Store certificate material, `.p12` passwords, Apple app-specific passwords, and other secret values only in the local keychain or GitHub Actions secrets on the protected `release` environment; never commit them or record them in project notes. Do not configure repository- or organization-scoped copies. GitHub's `${{ secrets.NAME }}` expression exposes the resolved value, not its storage scope, and falls back to a same-name repository or organization secret when the environment copy is absent. The workflow can constrain where secret references occur, but it cannot attest their origin from inside the job.
5. Run the local signing/notarization smoke test and the release-secret name preflight before pushing a public tag.

## Required GitHub Environment Secrets

Configure these secrets on the protected GitHub `release` environment before running the `Release` workflow. Do not configure repository- or organization-scoped copies. The release-secret operator preflight deliberately calls `gh secret list --env release --repo ...`, so a missing environment or credentials available only outside the environment fail that preflight. This proves that the required names exist on the environment at check time; it does not prove that duplicate names are absent at broader scopes or retrospectively prove which scope supplied a prior workflow run.

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

   This checks only secret names, not values, on the GitHub `release` environment. It should report all required Developer ID and notarization secret names before a release tag is pushed or a failed release workflow is rerun. A missing or unreadable `release` environment, or names configured only outside that environment, blocks the operator preflight. Because GitHub does not expose secret-origin metadata to the running job, separately confirm that same-name repository or organization secrets do not exist.

   Confirm the protected scheduling gate separately:

   ```sh
   scripts/check-release-environment.sh --repo Reedtrullz/Vifty \
     --output .build/release-environment-readback.json
   ```

   This read-only API check must show at least one complete eligible non-owner User login, `preventSelfReview: true`, `administratorsCanBypass: false`, protected-branch-only deployment policy, and the full strong-protection contract for `main`. Team-only configuration remains blocked because membership is not proved by the environment response. A missing/unreadable environment, owner-only or Team-only reviewer rule, enabled or unreadable administrator bypass, deployment-policy drift, administrator-exempt branch protection, missing reviewed CI/PR/CODEOWNERS/last-push/conversation gates, any pull-request bypass, or force-push/deletion allowance blocks publication setup. If no eligible reviewer exists, keep the manifest candidate `null`, do not create an owner-only substitute, and do not dispatch the Release workflow. The trusted `sign-notarize` job validates the exact protected-main workflow contract, repeats this API readback, binds it into the publication contract, and keeps the revalidated normalized evidence for 90 days in the workflow artifact; the job fails before signing secrets are used even if GitHub has auto-created an unprotected environment from the workflow reference.

   Publication also requires GitHub's rulesets API to expose an active tag-target ruleset that applies to the exact `refs/tags/v<version>` ref, has no bypass actors, and contains both the `update` and `deletion` restrictions. The release workflow performs that semantic read itself, records the matching ruleset ID, include-pattern evidence, rule types, empty bypass set, and API-visibility result in the protected publication contract, then rechecks the same ruleset immediately before and after promotion. Missing API visibility, an excluded tag, a bypass actor, or either missing restriction blocks publication.

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
5. Add the release candidate to `.github/release-manifest.json`, choose a build number greater than the published build, and update `Resources/Info.plist` to the candidate version/build. Do not edit, delete, or reorder prior `historicalReleases`. During a later promotion, append the exact previous `publishedRelease` before replacing it. Keep `Casks/vifty.rb` exactly on the current published manifest version/SHA throughout candidate build, signing, notarization, and publication. The candidate SHA may remain `null` until the notarized artifact exists. Do not repoint or recommend Homebrew until the candidate is promoted and the public checksum has been applied and verified.
6. Commit the release prep, merge it to protected `main`, and wait for CI to pass on that exact merged commit. The cask checksum and published manifest facts are post-publication follow-up changes.
7. Create and push an annotated signed tag for that exact CI-passed commit:

   ```sh
   git tag -s v<version> <exact-merged-main-sha> -m "Vifty v<version>"
   git verify-tag v<version>
   git push origin v<version>
   gh workflow run Release --ref main -f tag=v<version>
   ```

   Future signed-tag policy starts at the manifest's non-null `signedTagsRequiredFromVersion`; the historical unsigned `v1.3.2` record remains evidence and is not rewritten. Release publication is deliberately not triggered by tag push: dispatch the reviewed workflow from protected `main` and pass the existing signed tag as input. The workflow uses the exact protected-main workflow revision's signer policy for `git verify-tag`; the release tag cannot authorize its own signer. The verified annotated-tag object SHA and peeled commit SHA are carried in the publication contract and rechecked against the remote ref around promotion. The publication job creates the draft through the GitHub REST API only after that exact identity check; it never treats tag existence or a tag-addressed release CLI as signature proof. Separately, the workflow must prove through GitHub's rulesets API that the exact tag is covered by an active, no-bypass update-and-deletion ruleset; that evidence is embedded in the publication contract and revalidated by ruleset ID before the draft can become public.

8. Watch the manually dispatched `Release` workflow. It will:

   - validate the manifest candidate, tag signature, and bundle version/build;
   - verify remote tag-object parity, protected-main ancestry, and a successful CI run for the exact tag commit;
   - validate candidate bundle identity while proving the cask still names the exact published manifest artifact and SHA;
   - run pinned, checksum-verified `actionlint`, the full XCTest suite, warnings-as-errors build, and ad-hoc app assembly in the read-only prepare job;
   - hash every candidate file and upload only that unsigned/ad-hoc candidate plus its inventory;
   - pause at the GitHub `release` environment scheduling gate before any signing secret is exposed;
   - check out the exact trusted protected-main workflow revision separately, inventory its workflows, workflow-contract checker, release scripts, schemas, manifest, cask, and entitlements, validate that exact workflow contract, then revalidate the trusted inventory around protected execution;
   - download and revalidate the candidate without executing release scripts supplied by the candidate tag;
   - import the Developer ID Application certificate with private file modes into a temporary keychain, bind `codesign` to that keychain, and sign the already-built candidate without SwiftPM, tests, or a general `make` target;
   - verify all signing identifiers, TeamID, bundle/daemon identities, build number, exact architectures, hardened runtime flags, and exact reviewed app entitlements;
   - submit the app to Apple notarization;
   - staple the notarization ticket;
   - delete the temporary keychain and certificate in an `always()` cleanup step;
   - zip `Vifty.app` as `Vifty-v<version>.zip`;
   - verify the generated zip artifact against its just-created checksum, signing TeamID, hardened runtime/entitlements, stapling, Gatekeeper state, and bundled schemas exactly matching the reviewed source contracts;
   - write `Vifty-v<version>-artifact-summary.json`;
   - write `Vifty-v<version>-release-checklist.md`;
   - pass only the verified assets to a separate publication job, the only job with `contents: write`; that job rechecks the full v2 identity/build/architecture/check-array contract, checklist structure, and contract-bound immutable-tag ruleset evidence before publishing the zip, SHA-256 checksum, verification summary, and release checklist;
   - generate a cryptographically random run-unique ownership nonce, place its exact marker in the draft body and nonce in the draft title, REST-create the draft, and capture its immutable GitHub release database ID directly from that mutation response;
   - upload every canonical asset through the GitHub uploads API path containing that captured database ID, with a GET-by-ID post-state check after each upload; tag-addressed create, edit, upload, and delete commands are forbidden;
   - refuse promotion unless the exact tag object/commit and the recorded active no-bypass update/deletion ruleset still match, then use only the captured database ID for promotion or containment mutations;
   - query the release post-state after every create, upload, promote, or re-draft outcome; a nonzero or ambiguous mutation, identity mismatch, signal, or failed final readback arms an ID-based re-draft, and the job hard-fails if a subsequent immutable-ID readback cannot prove `draft: true` plus the exact ownership marker;
   - if REST creation returns an ambiguous response before an ID is trusted, discover by tag only to locate a unique draft whose numeric ID, exact tag, draft title/state, empty initial asset set, and cryptographically random marker all match this run; an unrelated by-tag release is never patched, even when that makes containment a hard failure;
   - prepend the release checklist to generated GitHub Release notes.

   Published-artifact verification is version-pinned, not partially pinned: schemas, executable support-script destinations, the complete bundled workload-wrapper set, and app entitlements are derived from the published manifest entry's exact `sourceCommit`. Candidate verification deliberately uses the current checkout policy. CI therefore checks out full Git history (`fetch-depth: 0`); if a published source commit or any required historical contract file is unavailable or invalid, verification fails closed rather than applying future `main` policy to old immutable bytes.

9. After the exact public artifact and sidecar checksum exist and pass verification, append the complete existing `publishedRelease` object unchanged to the end of `historicalReleases`; never edit, delete, or reorder earlier history entries. Then replace `publishedRelease` with the exact candidate facts: version/build/tag, source commit, exact source-CI and Release run IDs, four canonical asset names, SHA-256, and trust states; finally clear `candidate`. The appended history entry must remain fact-for-fact identical to the prior current entry, and the new current version/build must be greater than every historical entry. Do not promote the manifest before those public facts exist. Apply the same authorized SHA-256 to `Casks/vifty.rb`:

   ```sh
   scripts/update-cask-checksum.sh \
     --checksum-file ./Vifty-v<version>.zip.sha256 \
     --version <version>
   ```

   The updater accepts the normal `shasum -a 256` output from the release workflow, requires the target version, artifact name, and checksum to match the newly promoted published manifest, writes and validates a same-directory sibling candidate, then atomically renames it over the cask. It restores the original cask with the same rename discipline if final release-metadata validation fails. Then run `scripts/render-release-facts.sh --write`, `scripts/check-release-manifest.sh`, and `scripts/render-release-facts.sh --check` before committing the manifest/cask/docs follow-up. The fact check also rejects prose that still labels an older version as current.

10. Verify the public artifact and cask agree:

   ```sh
   scripts/verify-release-artifact.sh --team-id "$APPLE_TEAM_ID"
   ```

   This downloads the cask URL unless `--artifact <zip>` is provided, checks the SHA-256, extracts `Vifty.app`, verifies bundle version, required executables, and bundled `Contents/Resources/schemas` JSON Schemas exactly matching the reviewed source contracts for release-readiness, release-artifact-summary, agent-cooling evidence summary/review, agent-run smoke evidence summary, validation-report-index, validation-review-result, and `viftyctl`, verifies the bundled read-only and supervised agent evidence collector scripts, validates plist files, checks Developer ID TeamID alignment including the LaunchDaemon `VIFTY_XPC_ALLOWED_TEAM_ID`, verifies hardened runtime flags and exact app entitlements, validates stapling, and runs Gatekeeper assessment. The release workflow runs the same verifier before publishing with `--expected-sha` because the final cask checksum follow-up commit does not exist yet, and publishes the verifier's JSON summary as release evidence. The summary declares `schemaID: https://vifty.local/schemas/release-artifact-summary.schema.json`, and release evidence review rejects summaries with a missing or drifted schema identity. When `--summary` is provided and a release-trust check fails, including manifest or other early setup failures, the verifier writes a schema-valid failed summary naming the failing check so reviewers do not have to reconstruct the failure from transient logs alone.

   If this fails after an artifact has already been published, cut a corrected patch release instead of treating the Homebrew cask as trusted.

11. After publication and before moving `main` with the checksum follow-up, run `git fetch origin main --tags` and `scripts/check-release-readiness.sh --mode developer-id --version <version> --repo Reedtrullz/Vifty --require-source-ref origin/main --json` again. Once `main` has moved, use the immutable `v<version>` tag or release commit SHA for `--require-source-ref` instead. Keep the passed schema-backed JSON with release notes or validation evidence. The final JSON should show `releaseMode: "developer-id"` plus `release-source-ref`, `source-ci`, `release-workflow`, `release-secrets`, and `github-release` all passed.
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
