#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "${ROOT_DIR}"

VERSION=""
OUTPUT_PATH=""

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/write-release-checklist.sh [--version version] [--output path]

Writes the release checklist that is prepended to GitHub Release notes and
uploaded as a release asset. If --version is omitted, the version is read from
Resources/Info.plist.
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

if [ -z "${OUTPUT_PATH}" ]; then
  OUTPUT_PATH=".build/Vifty-v${VERSION}-release-checklist.md"
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

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
- [ ] Collect a release-mode evidence bundle with \`scripts/collect-validation-evidence.sh --release-summary ./Vifty-v${VERSION}-artifact-summary.json\`.
- [ ] Review that bundle with \`scripts/review-validation-evidence.sh --mode release --summary <evidence-dir>/review-result.json\`.
- [ ] Update \`docs/release-status.md\` after the signed artifact, checksum, verifier summary, and cask SHA are aligned.
- [ ] Keep compatibility claims gated on reviewed hardware reports with \`manualSmokeTestResult: "passed-auto-restored"\`.

Until the post-publication checks pass, do not describe the Homebrew path as a fully trusted public binary install.
EOF

echo "Wrote ${OUTPUT_PATH}"
