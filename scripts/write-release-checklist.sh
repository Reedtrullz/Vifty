#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "${ROOT_DIR}"

VERSION=""
OUTPUT_PATH=""
RELEASE_MODE="developer-id"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/write-release-checklist.sh [--mode developer-id|source-first] [--version version] [--output path]

Writes release checklist or source-first release-note text. Developer ID mode
is the default and writes the checklist prepended to notarized GitHub Release
notes. Source-first mode writes release notes for a source-first release with
an optional unsigned-dev tester artifact. If --version is omitted, the version
is read from Resources/Info.plist.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      if [ "$#" -lt 2 ]; then
        echo "error: --version requires a value" >&2
        exit 64
      fi
      VERSION="$2"
      shift 2
      ;;
    --mode)
      if [ "$#" -lt 2 ]; then
        echo "error: --mode requires a value" >&2
        exit 64
      fi
      RELEASE_MODE="$2"
      shift 2
      ;;
    --output)
      if [ "$#" -lt 2 ]; then
        echo "error: --output requires a value" >&2
        exit 64
      fi
      OUTPUT_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [ -z "${VERSION}" ]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
fi

if [[ ! "${VERSION}" =~ ^[0-9]+[.][0-9]+[.][0-9]+([-+][0-9A-Za-z.-]+)?$ ]]; then
  echo "error: release version must be a SemVer-like value, got: ${VERSION}" >&2
  exit 64
fi

case "${RELEASE_MODE}" in
  developer-id|source-first)
    ;;
  *)
    echo "error: --mode must be developer-id or source-first" >&2
    exit 64
    ;;
esac

if [ -z "${OUTPUT_PATH}" ]; then
  if [ "${RELEASE_MODE}" = "source-first" ]; then
    OUTPUT_PATH=".build/Vifty-v${VERSION}-source-first-release-notes.md"
  else
    OUTPUT_PATH=".build/Vifty-v${VERSION}-release-checklist.md"
  fi
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

if [ "${RELEASE_MODE}" = "source-first" ]; then
  cat > "${OUTPUT_PATH}" <<EOF
# Vifty ${VERSION} Source-First Release Notes

This is a source-first release. Vifty v${VERSION} does not yet include a Developer ID signed or notarized public binary because the project does not currently have Apple Developer Program credentials.

A convenience unsigned \`.app\` build is attached for testers who understand macOS Gatekeeper warnings and prefer not to build locally. For the most trusted path, build from source.

## Recommended Install Path

Build from source:

\`\`\`sh
git clone https://github.com/Reedtrullz/Vifty.git
cd Vifty
git checkout v${VERSION}
make verify
make install
\`\`\`

## Optional Unsigned Tester Artifact

- Optional artifact name: \`Vifty-v${VERSION}-unsigned-dev.zip\`
- Optional checksum name: \`Vifty-v${VERSION}-unsigned-dev.zip.sha256\`
- The unsigned convenience app is not Developer ID signed.
- The unsigned convenience app is not notarized.
- The unsigned convenience app is not the official trusted binary.
- macOS may show Gatekeeper warnings or block launch until the tester explicitly chooses to trust the local build.
- Do not use \`Vifty-v${VERSION}.zip\` for the unsigned build; that canonical name is reserved for a future Developer ID signed and notarized artifact.
- Do not update the Homebrew cask for this source-first release.

## Source-First Checks

- [ ] \`make verify\` passed before publishing the tag/release notes.
- [ ] The \`v${VERSION}\` tag points at the intended source commit.
- [ ] Before publication, if checking a moving branch or candidate ref, \`scripts/check-release-readiness.sh --mode source-first --version ${VERSION} --repo Reedtrullz/Vifty --require-source-ref <candidate-ref-or-sha> --json\` passed against the intended release commit.
- [ ] After publication, \`scripts/check-release-readiness.sh --mode source-first --version ${VERSION} --repo Reedtrullz/Vifty --json\` passed against the immutable release tag and GitHub Release assets. Do not require \`origin/main\` after \`main\` has moved on.
- [ ] Any attached unsigned-dev zip uses the \`Vifty-v${VERSION}-unsigned-dev.zip\` name and has a matching \`.sha256\` file.
- [ ] No release notes, assets, README text, or cask metadata claim this source-first release is Developer ID signed, notarized, or Homebrew-trusted.

The future Developer ID release path remains stricter: it still requires Apple Developer Program credentials, the signed/notarized Release workflow, canonical \`Vifty-v${VERSION}.zip\` assets, verifier summary, release checklist, and Homebrew checksum follow-up.
EOF
else
  cat > "${OUTPUT_PATH}" <<EOF
# Vifty ${VERSION} Release Checklist

This checklist is prepended to the GitHub Release notes and uploaded as a release asset. It distinguishes the checks completed by the release workflow from the follow-up checks that must happen after publication.

## Verified By The Release Workflow

- [x] Release tag \`v${VERSION}\` matched \`Resources/Info.plist\`.
- [x] Release metadata matched the Homebrew cask version, artifact name, SHA shape, helper cleanup path, TeamID wiring, notarization gates, verifier checks, and publication assets.
- [x] Required Developer ID and notarization secret names were present in GitHub Actions.
- [x] Swift tests passed on the release runner.
- [x] \`Vifty.app\` was built with the configured Developer ID signing identity and \`VIFTY_XPC_ALLOWED_TEAM_ID\`.
- [x] Bundle plist files, signing TeamID, \`viftyctl\` signing identifier, and bundled LaunchDaemon TeamID allowlist were verified.
- [x] Apple notarization completed, the ticket was stapled, stapling was validated, and Gatekeeper assessment passed.
- [x] \`Vifty-v${VERSION}.zip\` and \`Vifty-v${VERSION}.zip.sha256\` were generated.
- [x] \`scripts/verify-release-artifact.sh\` passed before publication and wrote \`Vifty-v${VERSION}-artifact-summary.json\`.

## Required Post-Publication Follow-Up

- [ ] Update \`Casks/vifty.rb\` with the published \`Vifty-v${VERSION}.zip.sha256\` using \`scripts/update-cask-checksum.sh --version ${VERSION}\`.
- [ ] Run \`scripts/verify-release-artifact.sh --team-id "\$APPLE_TEAM_ID"\` against the public cask artifact after the checksum update.
- [ ] Collect a release-mode evidence bundle with \`scripts/collect-validation-evidence.sh --release-summary ./Vifty-v${VERSION}-artifact-summary.json --release-checklist ./Vifty-v${VERSION}-release-checklist.md\`.
- [ ] Review that bundle with \`scripts/review-validation-evidence.sh --mode release --summary <evidence-dir>/review-result.json\`.
- [ ] Update \`docs/release-status.md\` after the signed artifact, checksum, verifier summary, and cask SHA are aligned.
- [ ] Keep compatibility claims gated on reviewed hardware reports with \`manualSmokeTestResult: "passed-auto-restored"\`.

Until the post-publication checks pass, do not describe the Homebrew path as a fully trusted public binary install.
EOF
fi

echo "Wrote ${OUTPUT_PATH}"
