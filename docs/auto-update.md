# Auto-Update Strategy

Auto-update is not enabled for `v1.2.0`, `v1.1.1` source-first, or unsigned-dev builds.

That is intentional. Auto-update installs executable code, so it must meet a higher trust bar than a convenience tester zip. Until the project has Apple Developer Program credentials and a trusted binary release lane, Vifty should recommend source builds and clearly marked unsigned tester artifacts instead of a self-updating app.

## Current Policy

- Do not attach an updater to `Vifty-v<version>-unsigned-dev.zip` or any local ad-hoc build.
- Do not make source-first GitHub Releases, CI artifacts, or Homebrew cask metadata imply automatic binary trust.
- No updater network checks should run in source-first mode.
- Keep the canonical `Vifty-v<version>.zip` name reserved for a Developer ID signed and notarized release artifact.
- Keep Homebrew checksum handoff tied to the verified canonical artifact, not an updater feed or unsigned-dev zip.

## Future Trusted Auto-Update Lane

Use [Sparkle 2](https://sparkle-project.org/documentation/) for the future trusted binary lane only. The updater should be enabled after the release flow can produce and verify all of these:

- a Developer ID signed, notarized, stapled `Vifty.app`;
- the daemon built with the release `VIFTY_XPC_ALLOWED_TEAM_ID`;
- a canonical `Vifty-v<version>.zip` archive and `Vifty-v<version>.zip.sha256`;
- an HTTPS `SUFeedURL` appcast hosted from a stable project-controlled location;
- an EdDSA-signed appcast generated from the protected release key;
- a committed public `SUPublicEDKey` whose private EdDSA key is stored outside the release host;
- `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` enabled for signed appcast/feed validation;
- Sparkle's [`generate_appcast`](https://sparkle-project.org/documentation/publishing/) output for the canonical release archive;
- `scripts/verify-release-artifact.sh --team-id <TEAMID>` passing before publication;
- Homebrew checksum handoff after the same artifact is published.

## Implementation Shape

When Apple credentials and the updater feed exist, wire Sparkle as an additive app feature:

- Add Sparkle as the app updater framework and copy `Sparkle.framework` into `Vifty.app/Contents/Frameworks/` while preserving symlinks and executable permissions.
- Add a SwiftUI **Check for Updates...** command using Sparkle's [programmatic SwiftUI setup](https://sparkle-project.github.io/documentation/programmatic-setup/) and, if useful, a small settings row for Sparkle's built-in automatic-check preference.
- Keep `SUFeedURL`, `SUPublicEDKey`, signed-feed settings, and automatic-check defaults in the app bundle `Info.plist`, generated from release configuration rather than ad-hoc local defaults.
- Extend release metadata validation to reject missing updater keys, non-HTTPS feeds, unsigned appcasts, missing Sparkle framework bundling, or updater-enabled unsigned/source-first artifacts.
- Extend artifact verification to confirm the published app contains the intended updater metadata and that the release notes keep source-first, unsigned-dev, Homebrew, and auto-update lanes separate.

## Testing Requirements

Before calling auto-update available:

- test the updater UI on an older Developer ID signed build against a newer notarized build;
- verify Sparkle refuses unsigned, wrong-key, wrong-version, and non-canonical artifacts;
- verify update install preserves the bundled helper, daemon plist, `viftyctl`, schemas, app icon, and TeamID-gated XPC settings;
- verify a failed update does not leave fan control in a forced state and does not bypass helper repair/status guidance;
- verify source-first builds still omit `SUFeedURL`, `SUPublicEDKey`, and signed-feed keys.
