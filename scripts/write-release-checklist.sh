#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "${ROOT_DIR}"

VERSION=""
OUTPUT_PATH=""
RELEASE_MODE="developer-id"
SOURCE_REF=""
SOURCE_SHA=""

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/write-release-checklist.sh [--mode developer-id|source-first] [--version version] [--source-ref ref-or-sha] [--source-sha sha] [--output path]

Writes release checklist or source-first release-note text. Developer ID mode
is the default and writes the checklist prepended to notarized GitHub Release
notes. Source-first mode writes release notes for a source-first release with
an optional unsigned-dev tester artifact. If --version is omitted, the version
is read from Resources/Info.plist.
USAGE
}

is_full_commit_sha() {
  [[ "$1" =~ ^[0-9a-fA-F]{40}$ ]]
}

lowercase_hex() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

resolve_source_ref_commit() {
  local ref="$1"
  if is_full_commit_sha "${ref}"; then
    lowercase_hex "${ref}"
    return 0
  fi

  git rev-parse "${ref}^{commit}" 2>/dev/null | tr '[:upper:]' '[:lower:]'
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
    --source-ref)
      if [ "$#" -lt 2 ]; then
        echo "error: --source-ref requires a value" >&2
        exit 64
      fi
      SOURCE_REF="$2"
      shift 2
      ;;
    --source-sha)
      if [ "$#" -lt 2 ]; then
        echo "error: --source-sha requires a value" >&2
        exit 64
      fi
      SOURCE_SHA="$2"
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

SOURCE_REF_DISPLAY=""
SOURCE_COMMIT_SHA=""
SOURCE_BOUNDARY_KIND="source ref"

if [ "${RELEASE_MODE}" = "source-first" ]; then
  if [ -n "${SOURCE_SHA}" ] && ! is_full_commit_sha "${SOURCE_SHA}"; then
    echo "error: --source-sha must be a 40-character hexadecimal commit SHA" >&2
    exit 64
  fi

  if [ -z "${SOURCE_REF}" ] && [ -z "${SOURCE_SHA}" ]; then
    SOURCE_REF="v${VERSION}"
  fi

  if [ -n "${SOURCE_REF}" ]; then
    if ! RESOLVED_SOURCE_SHA="$(resolve_source_ref_commit "${SOURCE_REF}")"; then
      echo "error: could not resolve source ref ${SOURCE_REF}; run git fetch origin --tags, pass --source-ref <ref-or-sha>, or pass --source-sha <40-character-sha> for source-first release notes." >&2
      exit 1
    fi
    if [ -z "${RESOLVED_SOURCE_SHA}" ] || ! is_full_commit_sha "${RESOLVED_SOURCE_SHA}"; then
      echo "error: could not resolve source ref ${SOURCE_REF}; run git fetch origin --tags, pass --source-ref <ref-or-sha>, or pass --source-sha <40-character-sha> for source-first release notes." >&2
      exit 1
    fi

    RESOLVED_SOURCE_SHA="$(lowercase_hex "${RESOLVED_SOURCE_SHA}")"
    if [ -n "${SOURCE_SHA}" ]; then
      SOURCE_SHA="$(lowercase_hex "${SOURCE_SHA}")"
      if [ "${RESOLVED_SOURCE_SHA}" != "${SOURCE_SHA}" ]; then
        echo "error: source ref ${SOURCE_REF} resolves to ${RESOLVED_SOURCE_SHA}, which does not match --source-sha ${SOURCE_SHA}" >&2
        exit 1
      fi
    fi

    SOURCE_REF_DISPLAY="${SOURCE_REF}"
    SOURCE_COMMIT_SHA="${RESOLVED_SOURCE_SHA}"
  else
    SOURCE_COMMIT_SHA="$(lowercase_hex "${SOURCE_SHA}")"
    SOURCE_REF_DISPLAY="${SOURCE_COMMIT_SHA}"
  fi

  if [ "${SOURCE_REF_DISPLAY}" = "v${VERSION}" ]; then
    SOURCE_BOUNDARY_KIND="tag"
  fi
fi

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

## Source Provenance

- Source ref: \`${SOURCE_REF_DISPLAY}\`
- Source commit: \`${SOURCE_COMMIT_SHA}\`

The \`${SOURCE_REF_DISPLAY}\` ${SOURCE_BOUNDARY_KIND} is the source release boundary at commit \`${SOURCE_COMMIT_SHA}\`. Do not replace it with a moving branch such as \`origin/main\` after publication. Later \`main\` commits are post-release hardening until a future release is cut.

## Optional Unsigned Tester Artifact

- Optional artifact name: \`Vifty-v${VERSION}-unsigned-dev.zip\`
- Optional checksum name: \`Vifty-v${VERSION}-unsigned-dev.zip.sha256\`
- The unsigned-dev zip is valid only with its \`.sha256\` sidecar, and the SHA-256 digest in that sidecar must match the zip bytes.
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
- [ ] Any attached unsigned-dev zip uses the \`Vifty-v${VERSION}-unsigned-dev.zip\` name and has a \`.sha256\` sidecar whose digest matches the zip bytes.
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
- [ ] Review that bundle with \`make validation-evidence-review VALIDATION_EVIDENCE_BUNDLE=<evidence-dir> VALIDATION_EVIDENCE_REVIEW_MODE=release VALIDATION_EVIDENCE_REVIEW_SUMMARY=<evidence-dir>/review-result.json\`.
- [ ] Update \`docs/release-status.md\` after the signed artifact, checksum, verifier summary, and cask SHA are aligned.
- [ ] Keep compatibility claims gated on reviewed hardware reports with \`manualSmokeTestResult: "passed-auto-restored"\`.

Until the post-publication checks pass, do not describe the Homebrew path as a fully trusted public binary install.
EOF
fi

echo "Wrote ${OUTPUT_PATH}"
