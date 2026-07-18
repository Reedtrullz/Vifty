#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "${ROOT_DIR}"

RELEASE_METADATA_MODE="developer-id"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/validate-release-metadata.sh [--mode developer-id|source-first]

Validates release metadata. Developer ID mode accepts either the published app
identity or a newer manifest candidate in Info.plist while requiring Homebrew
to remain on the exact published manifest version/SHA. Source-first mode keeps
the future Developer ID workflow and cask shape strict while allowing the app
bundle version to advance without repointing Homebrew.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      if [ "$#" -lt 2 ]; then
        echo "error: --mode requires a value" >&2
        exit 64
      fi
      RELEASE_METADATA_MODE="$2"
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

case "${RELEASE_METADATA_MODE}" in
  developer-id|source-first)
    ;;
  *)
    echo "error: --mode must be developer-id or source-first" >&2
    exit 64
    ;;
esac

CASK_PATH="${VIFTY_RELEASE_CASK_PATH:-Casks/vifty.rb}"
CI_WORKFLOW=".github/workflows/ci.yml"
RELEASE_WORKFLOW=".github/workflows/release.yml"
INFO_PLIST="Resources/Info.plist"
DAEMON_PLIST="Resources/tech.reidar.vifty.daemon.plist"
RELEASE_MANIFEST=".github/release-manifest.json"

VIFTY_RELEASE_MANIFEST_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/check-release-manifest.sh" --manifest-only >/dev/null

if [[ -f "${DAEMON_PLIST}" ]] &&
   /usr/bin/plutil -convert json -o - -- "${DAEMON_PLIST}" | ruby -rjson -e '
     data = JSON.parse(STDIN.read)
     keys = Hash(data["EnvironmentVariables"]).keys.grep(/\AVIFTY_XPC_ADHOC_/)
     exit(keys.empty? ? 1 : 0)
   '; then
  echo "error: ${DAEMON_PLIST} public release metadata must not contain VIFTY_XPC_ADHOC_* keys" >&2
  exit 1
fi

manifest_facts="$(ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  product = data.fetch("product")
  published = data.fetch("publishedRelease")
  candidate = data["candidate"] || {}
  puts [
    product.fetch("bundleID"), product.fetch("architectures").join(" "),
    product.fetch("minimumMacOS"), published.fetch("version"),
    published.fetch("build"), published.fetch("sha256"),
    candidate["version"], candidate["build"], candidate["sha256"]
  ].map { |value| value.to_s }.join("\t")
' "${RELEASE_MANIFEST}")"
IFS=$'\t' read -r manifest_bundle_id manifest_architectures manifest_minimum_macos published_version published_build published_sha candidate_version candidate_build candidate_sha <<< "${manifest_facts}"

source_first_sparkle_keys() {
  /usr/bin/plutil -convert json -o - -- "$1" | ruby -rjson -e '
    data = JSON.parse(STDIN.read)
    keys = data.keys.grep(/\ASU/).sort
    puts keys.join(", ") unless keys.empty?
  '
}

bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
bundle_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
bundle_minimum_macos="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${INFO_PLIST}")"
cask_version="$(ruby -ne 'puts $1 if /^\s*version "([^"]+)"/' "${CASK_PATH}")"
cask_sha="$(ruby -ne 'puts $1 if /^\s*sha256 "([^"]+)"/' "${CASK_PATH}")"
cask_disabled=0
if grep -Fq 'disable!' "${CASK_PATH}"; then
  cask_disabled=1
fi

if [[ -z "${cask_version}" ]]; then
  echo "error: could not read version from ${CASK_PATH}" >&2
  exit 1
fi

if [[ ! "${cask_sha}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: ${CASK_PATH} must contain a lowercase 64-character SHA-256 checksum for the notarized zip" >&2
  exit 1
fi

if [[ "${bundle_identifier}" != "${manifest_bundle_id}" ]]; then
  echo "error: bundle identifier ${bundle_identifier} does not match release manifest ${manifest_bundle_id}" >&2
  exit 1
fi

if [[ "${bundle_minimum_macos}" != "${manifest_minimum_macos}" ]]; then
  echo "error: bundle minimum macOS ${bundle_minimum_macos} does not match release manifest ${manifest_minimum_macos}" >&2
  exit 1
fi

if [[ "${manifest_architectures}" != "arm64" ]] || ! grep -Fq 'depends_on arch: :arm64' "${CASK_PATH}"; then
  echo "error: ${CASK_PATH} must declare the manifest arm64-only architecture" >&2
  exit 1
fi

if [[ "${RELEASE_METADATA_MODE}" = "developer-id" ]]; then
  if [[ "${cask_version}" != "${published_version}" ]]; then
    echo "error: cask version ${cask_version} must remain on published manifest version ${published_version}" >&2
    exit 1
  fi
  if [[ "${cask_sha}" != "${published_sha}" ]]; then
    echo "error: cask sha256 does not match published manifest checksum ${published_sha}" >&2
    exit 1
  fi
  if [[ "${bundle_version}" = "${published_version}" ]]; then
    expected_bundle_build="${published_build}"
  elif [[ -n "${candidate_version}" && "${bundle_version}" = "${candidate_version}" ]]; then
    expected_bundle_build="${candidate_build}"
  else
    echo "error: bundle version ${bundle_version} does not match published manifest ${published_version} or candidate ${candidate_version:-null}" >&2
    exit 1
  fi
  if [[ "${bundle_build}" != "${expected_bundle_build}" ]]; then
    echo "error: bundle build ${bundle_build} does not match release manifest build ${expected_bundle_build}" >&2
    exit 1
  fi
fi

if [[ "${RELEASE_METADATA_MODE}" = "developer-id" && "${cask_disabled}" = "1" ]]; then
  echo "error: ${CASK_PATH} must not be disabled for a Developer ID/Homebrew release" >&2
  exit 1
fi

if [[ "${RELEASE_METADATA_MODE}" = "source-first" ]]; then
  if [[ "${cask_version}" != "${published_version}" ]]; then
    echo "error: source-first cask version ${cask_version} does not match published manifest version ${published_version}" >&2
    exit 1
  fi
  if [[ "${cask_sha}" != "${published_sha}" ]]; then
    echo "error: source-first cask sha256 does not match published manifest checksum ${published_sha}" >&2
    exit 1
  fi
  sparkle_keys="$(source_first_sparkle_keys "${INFO_PLIST}")"
  if [[ -n "${sparkle_keys}" ]]; then
    echo "error: source-first Info.plist must not include Sparkle updater metadata: ${sparkle_keys}" >&2
    exit 1
  fi
  if [[ "${cask_disabled}" != "1" ]]; then
    echo "error: ${CASK_PATH} must remain disabled for a source-first release until a Developer ID signed and notarized artifact exists" >&2
    exit 1
  fi
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

if ! grep -Fq 'executable: "#{appdir}/Vifty.app/Contents/Resources/uninstall-vifty.sh"' "${CASK_PATH}" ||
   ! grep -Fq 'args:       ["--app", "#{appdir}/Vifty.app"]' "${CASK_PATH}"; then
  echo "error: ${CASK_PATH} must use the bundled safe uninstall lifecycle script" >&2
  exit 1
fi

if grep -Eq 'sudo (launchctl|rm )' "${CASK_PATH}"; then
  echo "error: ${CASK_PATH} must not bypass the safe uninstall lifecycle with direct sudo teardown" >&2
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

if ! grep -Fq 'FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"' "${CI_WORKFLOW}"; then
  echo "error: ${CI_WORKFLOW} must opt GitHub JavaScript actions into Node.js 24" >&2
  exit 1
fi

if grep -Fq 'uses: actions/cache@v4' "${CI_WORKFLOW}" ||
   { ! grep -Eq 'uses: actions/cache@([0-9a-f]{40}|v5)([[:space:]]+# v5)?$' "${CI_WORKFLOW}"; }; then
  echo "error: ${CI_WORKFLOW} must use actions/cache@v5 for native Node.js 24 support" >&2
  exit 1
fi

if grep -Fq 'SWIFT_BUILD_PATH: ${{ runner.temp }}/' "${CI_WORKFLOW}"; then
  echo "error: ${CI_WORKFLOW} must not use runner.temp in job-level SWIFT_BUILD_PATH env; write it from RUNNER_TEMP to GITHUB_ENV inside a step" >&2
  exit 1
fi

if ! grep -Fq 'echo "SWIFT_BUILD_PATH=${RUNNER_TEMP}/vifty-ci-swiftpm-build" >> "${GITHUB_ENV}"' "${CI_WORKFLOW}" ||
   ! grep -Fq 'path: ${{ runner.temp }}/vifty-ci-swiftpm-build' "${CI_WORKFLOW}"; then
  echo "error: ${CI_WORKFLOW} must isolate SwiftPM products with SWIFT_BUILD_PATH" >&2
  exit 1
fi

if ! grep -Fq 'make verify-full' "${CI_WORKFLOW}"; then
  echo "error: ${CI_WORKFLOW} must run make verify-full so GitHub Actions carries the slow XCTest suites" >&2
  exit 1
fi

if ! grep -Fq 'FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: "true"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must opt GitHub JavaScript actions into Node.js 24" >&2
  exit 1
fi

if ! grep -Fq 'scripts/check-release-manifest.sh' "${RELEASE_WORKFLOW}" ||
   ! grep -Fq -- '--publication-version "${VERSION}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must require an exact manifest candidate before publication" >&2
  exit 1
fi

if [[ ! -f "scripts/check-release-manifest-history-from-git.sh" ||
      ! -f "scripts/check-release-manifest-history.rb" ]]; then
  echo "error: trusted Git-base release-manifest continuity checkers are missing" >&2
  exit 1
fi

release_history_tools_inventoried=0
if { grep -Fq 'scripts/check-release-manifest-history-from-git.sh' "${RELEASE_WORKFLOW}" &&
     grep -Fq 'scripts/check-release-manifest-history.rb' "${RELEASE_WORKFLOW}"; } ||
   { grep -Fq 'git ls-files -z | xargs -0 shasum -a 256' "${RELEASE_WORKFLOW}" &&
     grep -Fq 'trusted_status="$(git status --porcelain=v1 --untracked-files=all)"' "${RELEASE_WORKFLOW}"; }; then
  release_history_tools_inventoried=1
fi

if ! grep -Fq 'Verify trusted base release-manifest continuity' "${CI_WORKFLOW}" ||
   ! grep -Fq -- '--base-ref "${BASE_SHA}"' "${CI_WORKFLOW}" ||
   ! grep -Fq -- '--require-base' "${CI_WORKFLOW}" ||
   ! grep -Fq -- '--base-ref "${GITHUB_SHA}^"' "${RELEASE_WORKFLOW}" ||
   [[ "${release_history_tools_inventoried}" != "1" ]]; then
  echo "error: CI and release workflows must enforce trusted Git-base append-only release-manifest continuity" >&2
  exit 1
fi

if ! grep -Fq 'scripts/lib/release_artifact_contract.rb' "${RELEASE_WORKFLOW}" ||
   ! grep -Fq 'data["releaseSourceCommit"] == contract.fetch("tagCommitSHA")' "${RELEASE_WORKFLOW}" ||
   ! grep -Fq 'data["releaseManifestSHA256"] == contract.fetch("releaseManifestSHA256")' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must bind publication evidence to the canonical artifact contract, peeled tag commit, and manifest digest" >&2
  exit 1
fi

if ! grep -Fq 'git verify-tag "${RELEASE_TAG}"' "${RELEASE_WORKFLOW}" &&
   ! { { grep -Fq 'gpg.ssh.allowedSignersFile=.github/release-signers.allowed' "${RELEASE_WORKFLOW}" ||
         grep -Fq 'gpg.ssh.allowedSignersFile="${TRUSTED_SIGNERS}"' "${RELEASE_WORKFLOW}"; } &&
       { grep -Fq 'verify-tag "${RELEASE_TAG}"' "${RELEASE_WORKFLOW}" ||
         grep -Fq 'verify-tag "${TAG_OBJECT}"' "${RELEASE_WORKFLOW}"; }; }; then
  echo "error: ${RELEASE_WORKFLOW} must cryptographically verify the signed release tag" >&2
  exit 1
fi

if grep -Fq 'SWIFT_BUILD_PATH: ${{ runner.temp }}/' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must not use runner.temp in job-level SWIFT_BUILD_PATH env; write it from RUNNER_TEMP to GITHUB_ENV inside a step" >&2
  exit 1
fi

if ! grep -Fq 'echo "SWIFT_BUILD_PATH=${RUNNER_TEMP}/vifty-release-swiftpm-build" >> "${GITHUB_ENV}"' "${RELEASE_WORKFLOW}" ||
   { ! grep -Fq 'swift test --build-path "${SWIFT_BUILD_PATH}"' "${RELEASE_WORKFLOW}" &&
     ! grep -Fq 'make verify-full SWIFT_BUILD_PATH="${SWIFT_BUILD_PATH}"' "${RELEASE_WORKFLOW}"; }; then
  echo "error: ${RELEASE_WORKFLOW} must isolate SwiftPM products with SWIFT_BUILD_PATH" >&2
  exit 1
fi

if ! grep -Fq 'Vifty-v${VERSION}.zip"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish Vifty-v\${VERSION}.zip to match the cask URL" >&2
  exit 1
fi

if ! grep -Fq 'CHECKSUM_PATH="${ZIP_PATH}.sha256"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish a checksum derived from ZIP_PATH" >&2
  exit 1
fi

if ! grep -Fq 'Vifty-v${VERSION}-artifact-summary.json"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must write a release artifact verification summary" >&2
  exit 1
fi

if ! grep -Fq 'Vifty-v${VERSION}-release-checklist.md"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must write a release checklist for GitHub Release notes" >&2
  exit 1
fi

if ! grep -Fq 'write-release-checklist.sh' "${RELEASE_WORKFLOW}" ||
   ! grep -Fq -- '--version "${VERSION}"' "${RELEASE_WORKFLOW}" ||
   ! grep -Fq -- '--output "${RELEASE_CHECKLIST_PATH}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must generate the release checklist from the validated VERSION" >&2
  exit 1
fi

if ! grep -Fq 'APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}' "${RELEASE_WORKFLOW}" &&
   ! grep -Fq 'VIFTY_XPC_ALLOWED_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must bind protected signing to APPLE_TEAM_ID" >&2
  exit 1
fi

if ! grep -Fq 'VIFTY_XPC_ALLOWED_TEAM_ID="${TEAM_ID}"' "${RELEASE_WORKFLOW}" &&
   ! grep -Fq 'make app CONFIGURATION=release SIGNING_IDENTITY="${SIGNING_IDENTITY}" VIFTY_XPC_ALLOWED_TEAM_ID="${VIFTY_XPC_ALLOWED_TEAM_ID}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must pass VIFTY_XPC_ALLOWED_TEAM_ID into make app" >&2
  exit 1
fi

if ! grep -Fq 'scripts/sign-release-candidate.sh' "${RELEASE_WORKFLOW}" &&
   ! grep -Fq '/usr/bin/plutil -extract EnvironmentVariables.VIFTY_XPC_ALLOWED_TEAM_ID raw -o - .build/Vifty.app/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist | grep "^${VIFTY_XPC_ALLOWED_TEAM_ID}$"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must verify the bundled LaunchDaemon TeamID allowlist" >&2
  exit 1
fi

if ! grep -Fq "codesign -dvvv .build/Vifty.app/Contents/MacOS/ViftyHelper 2>&1 | grep 'Identifier=tech.reidar.vifty.helper'" "${RELEASE_WORKFLOW}" &&
   ! grep -Fq 'codesign -dvvv .build/Vifty.app/Contents/MacOS/ViftyHelper 2>&1 | grep "Identifier=${HELPER_ID}"' "${RELEASE_WORKFLOW}" &&
   ! grep -Fq 'scripts/sign-release-candidate.sh' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must verify ViftyHelper signing identifier" >&2
  exit 1
fi

if ! grep -Fq 'xcrun notarytool submit' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must submit the app for notarization" >&2
  exit 1
fi

if ! grep -Fq 'xcrun stapler staple' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must staple the notarized app" >&2
  exit 1
fi

if ! grep -Fq 'xcrun stapler validate' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must validate the stapled app" >&2
  exit 1
fi

if ! grep -Fq '/usr/sbin/spctl --assess --type execute --verbose' "${RELEASE_WORKFLOW}"; then
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

if ! grep -Fq -- '--release-version "${VERSION}"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must select the manifest release by validated VERSION" >&2
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

if ! grep -Fq 'upload_release_asset_by_id "${ZIP_PATH}" "Vifty ${VERSION} notarized app"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish the notarized zip artifact" >&2
  exit 1
fi

if ! grep -Fq 'upload_release_asset_by_id "${CHECKSUM_PATH}" "Vifty ${VERSION} SHA-256 checksum"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish the release artifact checksum" >&2
  exit 1
fi

if ! grep -Fq 'upload_release_asset_by_id "${SUMMARY_PATH}" "Vifty ${VERSION} release artifact verification summary"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish the release artifact verification summary" >&2
  exit 1
fi

if ! grep -Fq 'upload_release_asset_by_id "${RELEASE_CHECKLIST_PATH}" "Vifty ${VERSION} release checklist"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must publish the release checklist asset" >&2
  exit 1
fi

if ! grep -Fq 'body = File.read(checklist_path).rstrip' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must prepend the release checklist to GitHub Release notes" >&2
  exit 1
fi

if [[ "$(grep -Fc 'verify_remote_tag_identity "${TAG_OBJECT_SHA}" "${TAG_COMMIT_SHA}"' "${RELEASE_WORKFLOW}")" -lt 3 ]]; then
  echo "error: ${RELEASE_WORKFLOW} must verify the exact remote tag object and peeled commit around publication" >&2
  exit 1
fi

if ! { grep -Fq 'gh api --method POST' "${RELEASE_WORKFLOW}" ||
       grep -Fq 'gh api --hostname github.com --method POST' "${RELEASE_WORKFLOW}"; } ||
   ! grep -Fq '"repos/${GITHUB_REPOSITORY}/releases"' "${RELEASE_WORKFLOW}" ||
   ! grep -Fq 'RELEASE_ID="$(capture_owned_draft_release_id "${CREATE_RESPONSE}")"' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must REST-create the draft and capture its immutable release ID directly" >&2
  exit 1
fi

if grep -Eq 'gh release (create|edit|upload|delete)' "${RELEASE_WORKFLOW}"; then
  echo "error: ${RELEASE_WORKFLOW} must not mutate a GitHub Release by tag" >&2
  exit 1
fi

if [[ "${RELEASE_METADATA_MODE}" = "source-first" ]]; then
  cask_hold="Homebrew cask is disabled and held until a future Developer ID release"
  if [[ "${bundle_version}" = "${cask_version}" ]]; then
    echo "Source-first release metadata OK: bundle version ${bundle_version}; ${cask_hold} and source-first mode does not publish or require Vifty-v${bundle_version}.zip"
  else
    echo "Source-first release metadata OK: bundle version ${bundle_version}, cask version ${cask_version}; ${cask_hold} and source-first mode does not publish or require Vifty-v${bundle_version}.zip"
  fi
else
  echo "Release metadata OK: version ${bundle_version}, artifact Vifty-v${bundle_version}.zip"
fi
