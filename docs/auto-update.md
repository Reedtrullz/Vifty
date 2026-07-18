# Auto-Update Strategy

<!-- BEGIN GENERATED RELEASE FACTS -->
> Release facts authority: `.github/release-manifest.json` (schema `docs/schemas/release-manifest.schema.json`).
> Published: `v1.3.2` (version `1.3.2`, build `7`), `arm64` only, minimum macOS `15.0`.
> Runtime identities: app `tech.reidar.vifty`, daemon `tech.reidar.vifty.daemon`, helper `tech.reidar.vifty.helper`, CLI `tech.reidar.vifty.ctl`.
> Canonical artifact: `Vifty-v1.3.2.zip` with checksum asset `Vifty-v1.3.2.zip.sha256` and SHA-256 `8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0`.
> Public artifact trust: `passed` / `developer-id-notarized` for TeamID `X88J3853S2`; source `6a771c2ea10386bf7a0a8369a759930f01d56062`, CI run `29284751837`, Release run `29285576026`.
> Tag policy: `v1.3.2` remains recorded as `historical-unsigned` evidence; signed tags are mandatory from version `1.3.3` onward.
> Separate exact-build claims: installed release review `passed`; manual Fixed/Curve/Auto compatibility `passed-auto-restored` on `MacBookPro18,1` only (review `docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/review-result.json`; attestation `docs/validation-reports/2026-07-14-v1.3.2-macbookpro18-supported/manual-smoke-attestation.md`).
<!-- END GENERATED RELEASE FACTS -->

Auto-update is not enabled for `v1.3.2`; its exact public binary does not contain update checking and cannot gain it retroactively. The first public release that contains the current update-checking code must therefore be installed manually. Source-first, unsigned-dev, local ad-hoc, CI, and other ineligible builds do not make update requests.

Current source implements an advisory release-availability checker for future exact Vifty Developer ID builds. It does not download executable code, replace `Vifty.app`, run an installer, or silently change the privileged helper. A separate in-place updater has a higher trust bar and has not been implemented.

## Current Policy

- Only an exact Developer ID signed Vifty build with bundle identifier `tech.reidar.vifty` and TeamID `X88J3853S2` is eligible to check. Source-first, unsigned-dev, local ad-hoc, CI, debug fixture, and other ineligible builds make zero update requests.
- Eligible builds check the fixed `https://api.github.com/repos/Reedtrullz/Vifty/releases/latest` endpoint. Automatic checking is enabled by default, can be turned off in Settings, and runs no more than once per 24 hours; **Check now** remains available as an explicit action. The scheduler combines its persisted wall-clock attempt with an in-process monotonic deadline so clock changes cannot shorten that automatic interval.
- A response is accepted only when it is a non-draft, non-prerelease stable `vMAJOR.MINOR.PATCH` release with exactly four uploaded, nonempty canonical assets: `Vifty-v<version>.zip`, `Vifty-v<version>.zip.sha256`, `Vifty-v<version>-artifact-summary.json`, and `Vifty-v<version>-release-checklist.md`.
- Vifty does not trust release or asset links supplied by the API. When newer availability metadata matches, **Update to latest version** opens the locally constructed `https://github.com/Reedtrullz/Vifty/releases/tag/v<version>` page in the user's browser.
- The checker never downloads the archive or other release assets and never installs or replaces executable code. Users retain the documented release-verification and app-replacement path.
- Keep the canonical `Vifty-v<version>.zip` name reserved for a Developer ID signed and notarized release artifact, and keep Homebrew checksum handoff tied to that verified artifact rather than an unsigned-dev zip.

## Privacy And Local State

This is availability metadata, not artifact-trust proof. The checker does not fetch or validate the checksum body, artifact-summary contents, release checklist, signed tag, archive bytes, Developer ID signature, notarization ticket, stapling, or Gatekeeper result.

An eligible build's automatic or manual check sends an ordinary HTTPS request to GitHub. GitHub receives normal request metadata such as the Mac's public IP address, request timing, and Vifty's version-bearing User-Agent. Vifty sends no account, fan, sensor, power, Codex, profile, or analytics payload.

The request uses an ephemeral session with no persistent cookie, URL cache, or credential store. Vifty stores only the opt-out preference, timestamps, an HTTP ETag, and the last validated release version in the private `~/Library/Application Support/Vifty/software-update.json` file. An empty private owner-lock file in the same directory ensures only one running Vifty instance owns this state and request lane. The lock is acquired atomically, keyed by its filesystem identity rather than a path spelling, and held by its open descriptor; an instance that loses ownership remains fail-closed until relaunch. Both files use descriptor-anchored, no-follow, crash-durable storage. Turning automatic checking off cancels scheduled automatic checks; it does not enable a different update channel.

## Manual Verified Public-Archive Install Bridge

Current source includes an operator-invoked bridge for a public archive that has already been downloaded manually. From a reviewed source checkout whose manifest has promoted that release to the single current `publishedRelease`, run:

```sh
scripts/install-vifty.sh --public-release-archive /absolute/path/Vifty-vX.Y.Z.zip
# or
make install-public-release PUBLIC_RELEASE_ARCHIVE=/absolute/path/Vifty-vX.Y.Z.zip
```

This bridge is deliberately narrower than a general installer and starts with `v1.4.0`; the historical `v1.3.2` bundle lacks its root snapshot binding contract. It selects only `.github/release-manifest.json` `publishedRelease`, requires the exact canonical filename, pinned SHA-256, and verified signed tag, and rejects a candidate, historical release, direct `.app`, relative path, URL, or other archive. After that archive-level authority passes, safe bounded private extraction establishes a complete candidate-content binding. The public release verifier and independent extracted-bundle checks must then confirm the exact version/build, bundle identities, Developer ID TeamID, deep signature, notarization/stapling, and Gatekeeper result without skip flags before the candidate feeds the unchanged fail-closed app-replacement transaction, including a private per-destination lock, existing Auto/System preflight, authority freeze, post-swap verification, authenticated downgrade refusal, and rollback behavior without a second-destination fallback.

The bridge performs no network request and never chooses or downloads a release. The in-app advisory checker still opens only the locally constructed GitHub tag page; the user separately downloads the canonical archive and explicitly invokes the bridge from a trusted checkout. This is a manual/operator migration path for the first checker-aware public release and later recovery or verification work. It is not automatic update, silent installation, Sparkle, or evidence that API filename/size metadata authenticated an archive.

## Future Trusted In-Place Update Lane

Use [Sparkle 2](https://sparkle-project.org/documentation/) only if Vifty later adds an in-place installer. That work is separate from the advisory checker above. It must enter Vifty's documented app-replacement transaction rather than replacing the bundle independently, and it should be enabled only after the release flow can produce and verify all of these:

- a Developer ID signed, notarized, stapled `Vifty.app`;
- the daemon built with the release `VIFTY_XPC_ALLOWED_TEAM_ID`;
- a canonical `Vifty-v<version>.zip` archive and `Vifty-v<version>.zip.sha256`;
- an HTTPS `SUFeedURL` appcast hosted from a stable project-controlled location;
- an EdDSA-signed appcast generated from the protected release key;
- a committed public `SUPublicEDKey` whose private EdDSA key is stored outside the release host;
- `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` enabled for signed appcast/feed validation;
- Sparkle's [`generate_appcast`](https://sparkle-project.org/documentation/publishing/) output for the canonical release archive;
- `scripts/verify-release-artifact.sh --team-id <TEAMID>` passing before publication;
- Homebrew checksum handoff after the same artifact is published;
- pre-replacement daemon quiescence, complete Auto/System proof, no active lease or manual marker, post-swap verification, and rollback through the same root-ledger transaction required by Vifty's existing app-replacement boundary.

## Implementation Shape

If the signed appcast and replacement integration exist, wire Sparkle as an additive app feature:

- Add Sparkle as the app updater framework and copy `Sparkle.framework` into `Vifty.app/Contents/Frameworks/` while preserving symlinks and executable permissions.
- Reconcile Sparkle's commands and preferences with the existing Vifty **Check for Updates...** / **Update to latest version** advisory UI instead of exposing two ambiguous update channels.
- Keep `SUFeedURL`, `SUPublicEDKey`, signed-feed settings, and automatic-check defaults in the app bundle `Info.plist`, generated from release configuration rather than ad-hoc local defaults.
- Extend release metadata validation to reject missing updater keys, non-HTTPS feeds, unsigned appcasts, missing Sparkle framework bundling, or updater-enabled unsigned/source-first artifacts.
- Extend artifact verification to confirm the published app contains the intended updater metadata and that the release notes keep source-first, unsigned-dev, Homebrew, and auto-update lanes separate.

## Testing Requirements

Before calling in-place auto-update available:

- test the updater UI on an older Developer ID signed build against a newer notarized build;
- verify Sparkle refuses unsigned, wrong-key, wrong-version, and non-canonical artifacts;
- verify update install preserves the bundled helper, daemon plist, `viftyctl`, schemas, app icon, and TeamID-gated XPC settings;
- verify a failed update does not leave fan control in a forced state and does not bypass helper repair/status guidance;
- verify every update enters the same replacement transaction, Auto/System proof, daemon/helper authority boundary, rollback, and root-ledger recovery path as a manual replacement;
- verify source-first builds still omit `SUFeedURL`, `SUPublicEDKey`, and signed-feed keys.
