#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "${ROOT_DIR}"

CASK_PATH="Casks/vifty.rb"
RELEASE_WORKFLOW=".github/workflows/release.yml"
INFO_PLIST="Resources/Info.plist"

bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
cask_version="$(ruby -ne 'puts $1 if /^\s*version "([^"]+)"/' "${CASK_PATH}")"
cask_sha="$(ruby -ne 'puts $1 if /^\s*sha256 "([^"]+)"/' "${CASK_PATH}")"

if [[ -z "${cask_version}" ]]; then
  echo "error: could not read version from ${CASK_PATH}" >&2
  exit 1
fi

if [[ "${bundle_version}" != "${cask_version}" ]]; then
  echo "error: bundle version ${bundle_version} does not match cask version ${cask_version}" >&2
  exit 1
fi

if [[ ! "${cask_sha}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: ${CASK_PATH} must contain a lowercase 64-character SHA-256 checksum for the notarized zip" >&2
  exit 1
fi

if ! grep -Fq 'Vifty-v#{version}.zip' "${CASK_PATH}"; then
  echo "error: ${CASK_PATH} must download Vifty-v#{version}.zip" >&2
  exit 1
fi

if ! grep -Fq 'releases/download/v#{version}/Vifty-v#{version}.zip' "${CASK_PATH}"; then
  echo "error: ${CASK_PATH} must download the versioned GitHub release artifact" >&2
  exit 1
fi

if grep -Eq 'signing_identity[[:space:]]+identity:[[:space:]]*"-"' "${CASK_PATH}"; then
  echo "error: ${CASK_PATH} must not declare ad-hoc signing for public releases" >&2
  exit 1
fi

if grep -Fq '/Library/PrivilegedHelperTools/ViftyDaemon' "${CASK_PATH}"; then
  echo "error: ${CASK_PATH} must not reference the old ViftyDaemon privileged helper path" >&2
  exit 1
fi

if ! grep -Fq '/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon' "${CASK_PATH}"; then
  echo "error: ${CASK_PATH} must document removal of /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon" >&2
  exit 1
fi

if ! grep -Fq 'VERSION="${TAG#v}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must derive VERSION from the release tag" >&2
  exit 1
fi

if ! grep -Fq 'if [[ "${TAG}" == "${VERSION}" ]]; then' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must require release tags to start with v" >&2
  exit 1
fi

if ! grep -Fq 'if [[ "${VERSION}" != "${BUNDLE_VERSION}" ]]; then' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must compare release tag version to CFBundleShortVersionString" >&2
  exit 1
fi

if ! grep -Fq 'echo "VERSION=${VERSION}" >> "${GITHUB_ENV}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must export the validated release VERSION" >&2
  exit 1
fi

if ! grep -Fq 'ZIP_PATH=".build/Vifty-v${VERSION}.zip"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish .build/Vifty-v\${VERSION}.zip to match the cask URL" >&2
  exit 1
fi

if ! grep -Fq 'CHECKSUM_PATH="${ZIP_PATH}.sha256"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish a checksum derived from ZIP_PATH" >&2
  exit 1
fi

if ! grep -Fq 'SUMMARY_PATH=".build/Vifty-v${VERSION}-artifact-summary.json"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must write a release artifact verification summary" >&2
  exit 1
fi

if ! grep -Fq 'RELEASE_CHECKLIST_PATH=".build/Vifty-v${VERSION}-release-checklist.md"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must write a release checklist for GitHub Release notes" >&2
  exit 1
fi

if ! grep -Fq 'scripts/write-release-checklist.sh --version "${VERSION}" --output "${RELEASE_CHECKLIST_PATH}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must generate the release checklist from the validated VERSION" >&2
  exit 1
fi

if ! grep -Fq 'echo "RELEASE_CHECKLIST_PATH=${RELEASE_CHECKLIST_PATH}" >> "${GITHUB_ENV}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must export the release checklist path before publishing" >&2
  exit 1
fi

if ! grep -Fq 'VIFTY_XPC_ALLOWED_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must build releases with VIFTY_XPC_ALLOWED_TEAM_ID from APPLE_TEAM_ID" >&2
  exit 1
fi

if ! grep -Fq 'make app CONFIGURATION=release SIGNING_IDENTITY="${SIGNING_IDENTITY}" VIFTY_XPC_ALLOWED_TEAM_ID="${VIFTY_XPC_ALLOWED_TEAM_ID}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must pass VIFTY_XPC_ALLOWED_TEAM_ID into make app" >&2
  exit 1
fi

if ! grep -Fq '/usr/bin/plutil -extract EnvironmentVariables.VIFTY_XPC_ALLOWED_TEAM_ID raw -o - .build/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist | grep "^${VIFTY_XPC_ALLOWED_TEAM_ID}$"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must verify the bundled LaunchDaemon TeamID allowlist" >&2
  exit 1
fi

if ! grep -Fq 'xcrun notarytool submit' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must submit the app for notarization" >&2
  exit 1
fi

if ! grep -Fq 'xcrun stapler staple .build/Vifty.app' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must staple the notarized app" >&2
  exit 1
fi

if ! grep -Fq 'xcrun stapler validate .build/Vifty.app' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must validate the stapled app" >&2
  exit 1
fi

if ! grep -Fq '/usr/sbin/spctl --assess --type execute --verbose .build/Vifty.app' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must run Gatekeeper assessment on the notarized app" >&2
  exit 1
fi

if ! grep -Fq 'scripts/verify-release-artifact.sh' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must verify the release artifact before publishing" >&2
  exit 1
fi

if grep -Fq -- '--skip-signature-checks' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must not skip release artifact signature checks" >&2
  exit 1
fi

if grep -Fq -- '--skip-notarization-checks' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must not skip release artifact notarization checks" >&2
  exit 1
fi

if ! grep -Fq -- '--artifact "${ZIP_PATH}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must verify the generated release zip artifact" >&2
  exit 1
fi

if ! grep -Fq -- '--expected-sha "${EXPECTED_SHA}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must verify the generated release checksum" >&2
  exit 1
fi

if ! grep -Fq -- '--team-id "${APPLE_TEAM_ID}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must verify the release artifact TeamID" >&2
  exit 1
fi

if ! grep -Fq -- '--summary "${SUMMARY_PATH}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must write the release artifact verification summary" >&2
  exit 1
fi

if ! grep -Fq '"${ZIP_PATH}#Vifty ${VERSION} notarized app"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish the notarized zip artifact" >&2
  exit 1
fi

if ! grep -Fq '"${CHECKSUM_PATH}#Vifty ${VERSION} SHA-256 checksum"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish the release artifact checksum" >&2
  exit 1
fi

if ! grep -Fq '"${SUMMARY_PATH}#Vifty ${VERSION} release artifact verification summary"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish the release artifact verification summary" >&2
  exit 1
fi

if ! grep -Fq '"${RELEASE_CHECKLIST_PATH}#Vifty ${VERSION} release checklist"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish the release checklist asset" >&2
  exit 1
fi

if ! grep -Fq -- '--notes "$(cat "${RELEASE_CHECKLIST_PATH}")"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must prepend the release checklist to GitHub Release notes" >&2
  exit 1
fi

if ! grep -Fq -- '--verify-tag' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must verify the Git tag before publishing" >&2
  exit 1
fi

echo "Release metadata OK: version ${bundle_version}, artifact Vifty-v${bundle_version}.zip"
