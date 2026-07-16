#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/verify-release-artifact.sh [options]

Verify the published Vifty release artifact referenced by the Homebrew cask.

Options:
  --cask <path>                  Cask file (default: Casks/vifty.rb)
  --artifact <zip>               Use an already-downloaded release zip instead of
                                  downloading the cask URL.
  --expected-sha <sha256>        Verify a candidate against this SHA-256 before its
                                  checksum is promoted into the manifest. Published
                                  and historical releases remain manifest-pinned.
  --release-version <version>    Select an exact candidate/current/history manifest entry.
                                  Required for a pre-publish candidate whose cask is
                                  intentionally still on the published release.
  --summary <path>               Write a machine-readable JSON verification summary
                                  after checks pass or a release-trust check fails.
  --team-id <TEAMID>             Require this Apple Developer TeamID. If omitted,
                                  use the authoritative release-manifest TeamID.
  --skip-signature-checks        Skip codesign and TeamID checks. For tests/local
                                  diagnostics only; do not use for public release.
  --skip-notarization-checks     Skip stapler and Gatekeeper checks. For tests/local
                                  diagnostics only; do not use for public release.
  -h, --help                     Show this help.

By default this is a public-release trust gate: it verifies the cask SHA-256,
release-manifest facts, bundle identity/build/architecture, required executables, bundled schema validity, plist validity,
bundled evidence collector scripts, guarded workload wrappers, Developer ID TeamID, daemon TeamID allowlist,
stapled notarization ticket, and Gatekeeper assessment.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_ARTIFACT_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
SOURCE_REPOSITORY_ROOT="${VIFTY_RELEASE_SOURCE_REPOSITORY_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CASK_PATH="${ROOT_DIR}/Casks/vifty.rb"
RELEASE_MANIFEST_PATH="${ROOT_DIR}/.github/release-manifest.json"
RELEASE_ARTIFACT_CONTRACT_PATH="${ROOT_DIR}/scripts/lib/release_artifact_contract.rb"
BUNDLED_SCHEMA_INVENTORY_RELATIVE_PATH="scripts/bundled-schema-inventory.txt"
RELEASE_ARTIFACT_SUMMARY_SCHEMA_ID="https://vifty.local/schemas/release-artifact-summary.schema.json"
ARTIFACT_PATH=""
EXPECTED_SHA_OVERRIDE=""
RELEASE_VERSION_OVERRIDE=""
EXPECTED_TEAM_ID="${VIFTY_RELEASE_TEAM_ID:-}"
SUMMARY_PATH=""
SKIP_SIGNATURE_CHECKS=0
SKIP_NOTARIZATION_CHECKS=0

CASK_VERSION=""
CASK_SHA=""
CASK_URL_TEMPLATE=""
CASK_URL=""
EXPECTED_ARTIFACT_NAME=""
EXPECTED_SHA=""
EXPECTED_SHA_SOURCE=""
ACTUAL_SHA=""
EXTRACT_DIR=""
APP_PATH=""
MACOS_DIR=""
INFO_PLIST=""
DAEMON_PLIST=""
BUNDLE_VERSION=""
APP_TEAM_ID=""
REQUIRED_TEAM_ID=""
RELEASE_VERSION=""
RELEASE_BUILD=""
RELEASE_MANIFEST_SCHEMA_VERSION=""
RELEASE_MANIFEST_ENTRY_KIND=""
RELEASE_MANIFEST_SHA256=""
RELEASE_SOURCE_COMMIT=""
RELEASE_TAG=""
RELEASE_TAG_COMMIT=""
CURRENT_RELEASE_MANIFEST_ENTRY_KIND=""
CURRENT_RELEASE_SOURCE_COMMIT=""
CURRENT_MANIFEST_RELEASE_SHA=""
TAGGED_MANIFEST_RELEASE_SHA=""
EXPECTED_BUNDLE_ID=""
EXPECTED_DAEMON_ID=""
EXPECTED_HELPER_ID=""
EXPECTED_CTL_ID=""
EXPECTED_ARCHITECTURES=""
MANIFEST_TEAM_ID=""
BUNDLE_BUILD=""
BUNDLE_IDENTIFIER=""
LAUNCH_DAEMON_LABEL=""
MACH_SERVICE_NAME=""
APP_ARCHITECTURES=""
HELPER_ARCHITECTURES=""
DAEMON_ARCHITECTURES=""
CTL_ARCHITECTURES=""
LIPO_PATH="${VIFTY_LIPO_PATH:-/usr/bin/lipo}"
SUMMARY_IDENTITY_READY=0

verify_schema_resource() {
  local path="$1"
  local expected_id="$2"
  local reviewed_path="$3"
  ruby -rjson -e '
    path, reviewed_path, expected_id = ARGV
    begin
      data = JSON.parse(File.read(path))
      reviewed = JSON.parse(File.read(reviewed_path))
    rescue StandardError => error
      warn "invalid JSON: #{error.message}"
      exit 10
    end

    schema = data["$schema"]
    unless schema == "https://json-schema.org/draft/2020-12/schema"
      warn "$schema #{schema.inspect} does not match https://json-schema.org/draft/2020-12/schema"
      exit 11
    end

    id = data["$id"]
    unless id == expected_id
      warn "$id #{id.inspect} does not match #{expected_id}"
      exit 12
    end
    unless reviewed["$schema"] == "https://json-schema.org/draft/2020-12/schema" && reviewed["$id"] == expected_id
      warn "reviewed source schema does not carry the expected draft/ID contract"
      exit 13
    end
    unless File.binread(path) == File.binread(reviewed_path)
      warn "bundled schema does not byte-match reviewed source contract #{reviewed_path}"
      exit 14
    end
  ' "${path}" "${reviewed_path}" "${expected_id}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cask)
      if [[ $# -lt 2 ]]; then
        echo "error: --cask requires a path" >&2
        exit 64
      fi
      CASK_PATH="$2"
      shift 2
      ;;
    --artifact)
      if [[ $# -lt 2 ]]; then
        echo "error: --artifact requires a path" >&2
        exit 64
      fi
      ARTIFACT_PATH="$2"
      shift 2
      ;;
    --expected-sha)
      if [[ $# -lt 2 ]]; then
        echo "error: --expected-sha requires a value" >&2
        exit 64
      fi
      EXPECTED_SHA_OVERRIDE="$2"
      shift 2
      ;;
    --release-version)
      if [[ $# -lt 2 ]]; then
        echo "error: --release-version requires a value" >&2
        exit 64
      fi
      RELEASE_VERSION_OVERRIDE="$2"
      shift 2
      ;;
    --summary)
      if [[ $# -lt 2 ]]; then
        echo "error: --summary requires a path" >&2
        exit 64
      fi
      SUMMARY_PATH="$2"
      shift 2
      ;;
    --team-id)
      if [[ $# -lt 2 ]]; then
        echo "error: --team-id requires a value" >&2
        exit 64
      fi
      EXPECTED_TEAM_ID="$2"
      shift 2
      ;;
    --skip-signature-checks)
      SKIP_SIGNATURE_CHECKS=1
      shift
      ;;
    --skip-notarization-checks)
      SKIP_NOTARIZATION_CHECKS=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -n "${EXPECTED_SHA_OVERRIDE}" ]]; then
  EXPECTED_SHA_SOURCE="expected sha256"
else
  EXPECTED_SHA_SOURCE="cask sha256"
fi

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\t'/\\t}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  printf '%s' "${value}"
}

json_string() {
  printf '"'
  json_escape "$1"
  printf '"'
}

json_word_array() {
  local words="$1"
  ruby -rjson -e 'print ARGV.fetch(0).split.sort.to_json' "${words}"
}

write_check() {
  local first="$1"
  local name="$2"
  local status="$3"
  local scope="$4"
  local note="$5"
  if [[ "${first}" != "1" ]]; then
    printf ',\n' >> "${SUMMARY_PATH}"
  fi
  {
    printf '    {"name":'
    json_string "${name}"
    printf ',"status":'
    json_string "${status}"
    printf ',"scope":'
    json_string "${scope}"
    printf ',"note":'
    json_string "${note}"
    printf '}'
  } >> "${SUMMARY_PATH}"
}

write_summary_header() {
  local status="$1"
  local generated_at_utc
  generated_at_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  mkdir -p "$(dirname "${SUMMARY_PATH}")"
  {
    printf '{\n'
    if [[ "${SUMMARY_IDENTITY_READY}" == "1" ]]; then
      printf '  "schemaVersion": 2,\n'
    else
      printf '  "schemaVersion": 1,\n'
    fi
    printf '  "schemaID": '
    json_string "${RELEASE_ARTIFACT_SUMMARY_SCHEMA_ID}"
    printf ',\n'
    printf '  "status": '
    json_string "${status}"
    printf ',\n'
    printf '  "generatedAtUTC": '
    json_string "${generated_at_utc}"
    printf ',\n'
    printf '  "caskVersion": '
    json_string "${CASK_VERSION}"
    printf ',\n'
    printf '  "caskURL": '
    json_string "${CASK_URL}"
    printf ',\n'
    printf '  "expectedArtifactName": '
    json_string "${EXPECTED_ARTIFACT_NAME}"
    printf ',\n'
    printf '  "artifactPath": '
    json_string "${ARTIFACT_PATH}"
    printf ',\n'
    printf '  "appPath": '
    json_string "${APP_PATH}"
    printf ',\n'
    printf '  "bundleVersion": '
    json_string "${BUNDLE_VERSION}"
    printf ',\n'
    if [[ "${SUMMARY_IDENTITY_READY}" == "1" ]]; then
      printf '  "bundleBuild": '
      printf '%s' "${BUNDLE_BUILD}"
      printf ',\n'
      printf '  "bundleIdentifier": '
      json_string "${BUNDLE_IDENTIFIER}"
      printf ',\n'
      printf '  "releaseVersion": '
      json_string "${RELEASE_VERSION}"
      printf ',\n'
      printf '  "releaseTag": '
      json_string "${RELEASE_TAG}"
      printf ',\n'
      printf '  "releaseSourceCommit": '
      if [[ -n "${RELEASE_SOURCE_COMMIT}" ]]; then
        json_string "${RELEASE_SOURCE_COMMIT}"
      else
        printf 'null'
      fi
      printf ',\n'
      printf '  "releaseManifestEntryKind": '
      json_string "${RELEASE_MANIFEST_ENTRY_KIND}"
      printf ',\n'
      printf '  "releaseManifestSchemaVersion": '
      printf '%s' "${RELEASE_MANIFEST_SCHEMA_VERSION}"
      printf ',\n'
      printf '  "releaseManifestSHA256": '
      json_string "${RELEASE_MANIFEST_SHA256}"
      printf ',\n'
      printf '  "runtimeIdentifiers": {"app":'
      json_string "${EXPECTED_BUNDLE_ID}"
      printf ',"daemon":'
      json_string "${EXPECTED_DAEMON_ID}"
      printf ',"helper":'
      json_string "${EXPECTED_HELPER_ID}"
      printf ',"ctl":'
      json_string "${EXPECTED_CTL_ID}"
      printf '},\n'
      printf '  "launchDaemonLabel": '
      json_string "${LAUNCH_DAEMON_LABEL}"
      printf ',\n'
      printf '  "machServiceName": '
      json_string "${MACH_SERVICE_NAME}"
      printf ',\n'
      printf '  "architectures": {"expected":'
      json_word_array "${EXPECTED_ARCHITECTURES}"
      printf ',"app":'
      json_word_array "${APP_ARCHITECTURES}"
      printf ',"helper":'
      json_word_array "${HELPER_ARCHITECTURES}"
      printf ',"daemon":'
      json_word_array "${DAEMON_ARCHITECTURES}"
      printf ',"ctl":'
      json_word_array "${CTL_ARCHITECTURES}"
      printf '},\n'
    fi
    printf '  "expectedSHA": '
    json_string "${EXPECTED_SHA}"
    printf ',\n'
    printf '  "expectedSHASource": '
    json_string "${EXPECTED_SHA_SOURCE}"
    printf ',\n'
    printf '  "actualSHA": '
    json_string "${ACTUAL_SHA}"
    printf ',\n'
    printf '  "expectedTeamID": '
    json_string "${EXPECTED_TEAM_ID}"
    printf ',\n'
    printf '  "requiredTeamID": '
    json_string "${REQUIRED_TEAM_ID}"
    printf ',\n'
    printf '  "signatureChecksSkipped": '
    if [[ "${SKIP_SIGNATURE_CHECKS}" == "1" ]]; then printf 'true'; else printf 'false'; fi
    printf ',\n'
    printf '  "notarizationChecksSkipped": '
    if [[ "${SKIP_NOTARIZATION_CHECKS}" == "1" ]]; then printf 'true'; else printf 'false'; fi
  } > "${SUMMARY_PATH}"
}

write_failure_summary() {
  local check_name="$1"
  local message="$2"
  if [[ -z "${SUMMARY_PATH}" ]]; then
    return
  fi
  write_summary_header "failed"
  {
    printf ',\n'
    printf '  "failureCheck": '
    json_string "${check_name}"
    printf ',\n'
    printf '  "failureMessage": '
    json_string "${message}"
    printf ',\n'
    printf '  "checks": [\n'
  } >> "${SUMMARY_PATH}"
  write_check 1 "${check_name}" "failed" "release-trust" "${message}"
  {
    printf '\n'
    printf '  ]\n'
    printf '}\n'
  } >> "${SUMMARY_PATH}"
}

fail_check() {
  local check_name="$1"
  local message="$2"
  write_failure_summary "${check_name}" "${message}"
  echo "error: ${message}" >&2
  exit 65
}

unexpected_failure() {
  local exit_code=$?
  local line_number="${BASH_LINENO[0]:-unknown}"
  trap - ERR
  write_failure_summary "unexpected-error" "unexpected verifier command failure near line ${line_number} (exit ${exit_code})" || true
  echo "error: unexpected verifier command failure near line ${line_number} (exit ${exit_code})" >&2
  exit "${exit_code}"
}
trap unexpected_failure ERR

if ! manifest_error="$(VIFTY_RELEASE_MANIFEST_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/check-release-manifest.sh" --manifest-only 2>&1)"; then
  fail_check "release-manifest" "release manifest validation failed: ${manifest_error}"
fi
if [[ ! -f "${RELEASE_ARTIFACT_CONTRACT_PATH}" ]]; then
  fail_check "release-manifest" "release artifact contract validator not found: ${RELEASE_ARTIFACT_CONTRACT_PATH}"
fi

if [[ ! -f "${CASK_PATH}" ]]; then
  write_failure_summary "cask-present" "cask not found: ${CASK_PATH}"
  echo "error: cask not found: ${CASK_PATH}" >&2
  exit 66
fi

CASK_VERSION="$(ruby -ne 'puts $1 if /^\s*version "([^"]+)"/' "${CASK_PATH}")"
CASK_SHA="$(ruby -ne 'puts $1 if /^\s*sha256 "([^"]+)"/' "${CASK_PATH}")"
CASK_URL_TEMPLATE="$(ruby -ne 'puts $1 if /^\s*url "([^"]+)"/' "${CASK_PATH}")"

if [[ -z "${CASK_VERSION}" || -z "${CASK_SHA}" || -z "${CASK_URL_TEMPLATE}" ]]; then
  fail_check "cask-metadata" "could not read version, sha256, or url from ${CASK_PATH}"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vifty-release-artifact.XXXXXX")"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

RELEASE_VERSION="${RELEASE_VERSION_OVERRIDE:-${CASK_VERSION}}"
if ! selected_manifest_facts="$(ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  version = ARGV.fetch(1)
  entries = []
  entries << ["candidate", data["candidate"]] if data["candidate"]
  entries << ["published", data.fetch("publishedRelease")]
  data.fetch("historicalReleases").each { |release| entries << ["historical", release] }
  kind, release = entries.find { |_kind, item| item["version"] == version }
  abort("release manifest has no candidate/current/history entry for #{version}") unless release
  product = data.fetch("product")
  policy = data.fetch("releasePolicy")
  puts [
    data.fetch("schemaVersion"), product.fetch("bundleID"), product.fetch("daemonID"),
    product.fetch("helperID"), product.fetch("ctlID"), product.fetch("architectures").sort.join(" "),
    policy.fetch("developerTeamID"), release.fetch("build"), release.fetch("artifact"),
    release["sha256"] || "-", kind, release["sourceCommit"] || "-", release.fetch("tag"),
    policy.fetch("signedTagsRequiredFromVersion")
  ].map { |value| value.to_s }.join("\t")
' "${RELEASE_MANIFEST_PATH}" "${RELEASE_VERSION}" 2>&1)"; then
  fail_check "release-manifest" "${selected_manifest_facts}"
fi
IFS=$'\t' read -r _CURRENT_MANIFEST_SCHEMA _CURRENT_BUNDLE_ID _CURRENT_DAEMON_ID _CURRENT_HELPER_ID _CURRENT_CTL_ID _CURRENT_ARCHITECTURES _CURRENT_TEAM_ID _CURRENT_BUILD _CURRENT_ARTIFACT CURRENT_MANIFEST_RELEASE_SHA CURRENT_RELEASE_MANIFEST_ENTRY_KIND CURRENT_RELEASE_SOURCE_COMMIT RELEASE_TAG SIGNED_TAG_BOUNDARY <<< "${selected_manifest_facts}"
if [[ "${CURRENT_RELEASE_SOURCE_COMMIT}" == "-" ]]; then
  CURRENT_RELEASE_SOURCE_COMMIT=""
fi
if [[ "${CURRENT_MANIFEST_RELEASE_SHA}" == "-" ]]; then
  CURRENT_MANIFEST_RELEASE_SHA=""
fi

if ! RELEASE_TAG_COMMIT="$(git -C "${SOURCE_REPOSITORY_ROOT}" rev-parse --verify "${RELEASE_TAG}^{commit}" 2>/dev/null)"; then
  fail_check "release-source-contract" "release tag ${RELEASE_TAG} is unavailable in ${SOURCE_REPOSITORY_ROOT}"
fi
if [[ ! "${RELEASE_TAG_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
  fail_check "release-source-contract" "release tag ${RELEASE_TAG} did not resolve to a lowercase 40-character commit"
fi
TAGGED_RELEASE_MANIFEST_PATH="${TMP_DIR}/tagged-release-manifest.json"
if ! git -C "${SOURCE_REPOSITORY_ROOT}" show "${RELEASE_TAG_COMMIT}:.github/release-manifest.json" > "${TAGGED_RELEASE_MANIFEST_PATH}" 2>/dev/null; then
  if ruby -e '
    version = ARGV.fetch(0).split(".").map(&:to_i)
    boundary = ARGV.fetch(1).split(".").map(&:to_i)
    exit((version <=> boundary) >= 0 ? 0 : 1)
  ' "${RELEASE_VERSION}" "${SIGNED_TAG_BOUNDARY}"; then
    fail_check "release-source-contract" "release tag ${RELEASE_TAG} source commit is missing .github/release-manifest.json"
  fi
  cp "${RELEASE_MANIFEST_PATH}" "${TAGGED_RELEASE_MANIFEST_PATH}"
fi
RELEASE_MANIFEST_SHA256="$(shasum -a 256 "${TAGGED_RELEASE_MANIFEST_PATH}" | awk '{print $1}')"
if ! tagged_manifest_facts="$(ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  version = ARGV.fetch(1)
  expected_tag = ARGV.fetch(2)
  entries = []
  entries << ["candidate", data["candidate"]] if data["candidate"]
  entries << ["published", data.fetch("publishedRelease")]
  data.fetch("historicalReleases").each { |release| entries << ["historical", release] }
  matches = entries.select { |_kind, item| item["version"] == version }
  abort("tagged release manifest must select exactly one entry for #{version}") unless matches.length == 1
  kind, release = matches.first
  abort("tagged release manifest tag #{release["tag"].inspect} does not match #{expected_tag}") unless release["tag"] == expected_tag
  product = data.fetch("product")
  policy = data.fetch("releasePolicy")
  puts [
    data.fetch("schemaVersion"), product.fetch("bundleID"), product.fetch("daemonID"),
    product.fetch("helperID"), product.fetch("ctlID"), product.fetch("architectures").sort.join(" "),
    policy.fetch("developerTeamID"), release.fetch("build"), release.fetch("artifact"),
    release["sha256"] || "-", kind
  ].map { |value| value.to_s }.join("\t")
' "${TAGGED_RELEASE_MANIFEST_PATH}" "${RELEASE_VERSION}" "${RELEASE_TAG}" 2>&1)"; then
  fail_check "release-source-contract" "${tagged_manifest_facts}"
fi
IFS=$'\t' read -r RELEASE_MANIFEST_SCHEMA_VERSION EXPECTED_BUNDLE_ID EXPECTED_DAEMON_ID EXPECTED_HELPER_ID EXPECTED_CTL_ID EXPECTED_ARCHITECTURES MANIFEST_TEAM_ID RELEASE_BUILD EXPECTED_ARTIFACT_NAME TAGGED_MANIFEST_RELEASE_SHA RELEASE_MANIFEST_ENTRY_KIND <<< "${tagged_manifest_facts}"
if [[ "${TAGGED_MANIFEST_RELEASE_SHA}" == "-" ]]; then
  TAGGED_MANIFEST_RELEASE_SHA=""
fi
RELEASE_SOURCE_COMMIT="${RELEASE_TAG_COMMIT}"

if ! manifest_cask_facts="$(ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  release = data.fetch("publishedRelease")
  puts [release.fetch("version"), release.fetch("artifact"), release.fetch("sha256")].join("\t")
' "${RELEASE_MANIFEST_PATH}" 2>&1)"; then
  fail_check "release-manifest" "${manifest_cask_facts}"
fi
IFS=$'\t' read -r MANIFEST_CASK_VERSION MANIFEST_CASK_ARTIFACT MANIFEST_CASK_SHA <<< "${manifest_cask_facts}"

if [[ -n "${EXPECTED_TEAM_ID}" && "${EXPECTED_TEAM_ID}" != "${MANIFEST_TEAM_ID}" ]]; then
  fail_check "release-manifest" "requested TeamID ${EXPECTED_TEAM_ID} does not match release manifest TeamID ${MANIFEST_TEAM_ID}"
fi
EXPECTED_TEAM_ID="${MANIFEST_TEAM_ID}"

if [[ ! "${CASK_SHA}" =~ ^[0-9a-f]{64}$ ]]; then
  fail_check "cask-sha-format" "cask sha256 must be a lowercase 64-character SHA-256 checksum"
fi

if [[ "${CASK_VERSION}" != "${MANIFEST_CASK_VERSION}" ]]; then
  fail_check "release-manifest" "cask version ${CASK_VERSION} must match current published manifest release ${MANIFEST_CASK_VERSION}"
fi

if [[ "${CASK_SHA}" != "${MANIFEST_CASK_SHA}" ]]; then
  fail_check "release-manifest" "cask checksum must match manifest checksum ${MANIFEST_CASK_SHA} for ${CASK_VERSION}"
fi

if ! grep -Fq 'depends_on arch: :arm64' "${CASK_PATH}"; then
  fail_check "cask-metadata" "cask must declare the release manifest arm64-only architecture"
fi

if [[ -n "${EXPECTED_SHA_OVERRIDE}" && ! "${EXPECTED_SHA_OVERRIDE}" =~ ^[0-9a-f]{64}$ ]]; then
  fail_check "expected-sha-format" "--expected-sha must be a lowercase 64-character SHA-256 checksum"
fi

CASK_URL="${CASK_URL_TEMPLATE//\#\{version\}/${CASK_VERSION}}"
CASK_EXPECTED_ARTIFACT_NAME="Vifty-v${CASK_VERSION}.zip"

if [[ "${CASK_URL}" != *"/${CASK_EXPECTED_ARTIFACT_NAME}" ]] || [[ "${MANIFEST_CASK_ARTIFACT}" != "${CASK_EXPECTED_ARTIFACT_NAME}" ]]; then
  fail_check "cask-url-artifact-name" "cask URL and selected manifest artifact must end with ${CASK_EXPECTED_ARTIFACT_NAME}"
fi

SCHEMA_CONTRACT_DIR=""
SCHEMA_INVENTORY_PATH=""
SCHEMA_CONTRACT_DESCRIPTION=""
BUNDLE_CONTRACT_DESCRIPTION=""
BUNDLE_CONTRACT_MAKEFILE=""
EXPECTED_ENTITLEMENTS_PATH=""
if [[ "${CURRENT_RELEASE_MANIFEST_ENTRY_KIND}" != "candidate" ]]; then
  if [[ ! "${CURRENT_RELEASE_SOURCE_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
    fail_check "release-source-contract" "${CURRENT_RELEASE_MANIFEST_ENTRY_KIND} release ${RELEASE_VERSION} has no valid immutable source commit for bundle verification"
  fi
  if ! git -C "${SOURCE_REPOSITORY_ROOT}" cat-file -e "${CURRENT_RELEASE_SOURCE_COMMIT}^{commit}" 2>/dev/null; then
    fail_check "release-source-contract" "immutable source commit ${CURRENT_RELEASE_SOURCE_COMMIT} is unavailable in ${SOURCE_REPOSITORY_ROOT}"
  fi
  if [[ "${RELEASE_TAG_COMMIT}" != "${CURRENT_RELEASE_SOURCE_COMMIT}" ]]; then
    fail_check "release-source-contract" "release tag ${RELEASE_TAG} resolves to ${RELEASE_TAG_COMMIT}, not manifest sourceCommit ${CURRENT_RELEASE_SOURCE_COMMIT}"
  fi
  SOURCE_CONTRACT_DIR="${TMP_DIR}/reviewed-source-contract"
  SCHEMA_CONTRACT_DIR="${SOURCE_CONTRACT_DIR}/docs/schemas"
  mkdir -p "${SCHEMA_CONTRACT_DIR}"
  BUNDLE_CONTRACT_MAKEFILE="${SOURCE_CONTRACT_DIR}/Makefile"
  EXPECTED_ENTITLEMENTS_PATH="${SOURCE_CONTRACT_DIR}/Resources/Vifty.entitlements"
  mkdir -p "$(dirname "${EXPECTED_ENTITLEMENTS_PATH}")"
  if ! git -C "${SOURCE_REPOSITORY_ROOT}" show "${CURRENT_RELEASE_SOURCE_COMMIT}:Makefile" > "${BUNDLE_CONTRACT_MAKEFILE}" 2>/dev/null; then
    fail_check "release-source-contract" "immutable source commit ${CURRENT_RELEASE_SOURCE_COMMIT} is missing Makefile"
  fi
  if ! git -C "${SOURCE_REPOSITORY_ROOT}" show "${CURRENT_RELEASE_SOURCE_COMMIT}:Resources/Vifty.entitlements" > "${EXPECTED_ENTITLEMENTS_PATH}" 2>/dev/null; then
    fail_check "release-source-contract" "immutable source commit ${CURRENT_RELEASE_SOURCE_COMMIT} is missing Resources/Vifty.entitlements"
  fi
  if ! schema_source_paths="$(git -C "${SOURCE_REPOSITORY_ROOT}" ls-tree -r --name-only "${CURRENT_RELEASE_SOURCE_COMMIT}" -- docs/schemas 2>/dev/null)"; then
    fail_check "schema-resources" "could not enumerate schemas at immutable source commit ${CURRENT_RELEASE_SOURCE_COMMIT}"
  fi
  schema_source_count=0
  while IFS= read -r schema_source_path; do
    [[ -n "${schema_source_path}" ]] || continue
    if [[ ! "${schema_source_path}" =~ ^docs/schemas/[^/]+\.schema\.json$ ]]; then
      continue
    fi
    schema_source_name="${schema_source_path##*/}"
    if ! git -C "${SOURCE_REPOSITORY_ROOT}" show "${CURRENT_RELEASE_SOURCE_COMMIT}:${schema_source_path}" > "${SCHEMA_CONTRACT_DIR}/${schema_source_name}"; then
      fail_check "schema-resources" "could not read ${schema_source_path} at immutable source commit ${CURRENT_RELEASE_SOURCE_COMMIT}"
    fi
    schema_source_count=$((schema_source_count + 1))
  done <<< "${schema_source_paths}"
  if [[ "${schema_source_count}" -eq 0 ]]; then
    fail_check "schema-resources" "immutable source commit ${CURRENT_RELEASE_SOURCE_COMMIT} contains no reviewed JSON Schemas"
  fi
  SCHEMA_INVENTORY_PATH="${SOURCE_CONTRACT_DIR}/bundled-schema-inventory.txt"
  if git -C "${SOURCE_REPOSITORY_ROOT}" cat-file -e "${CURRENT_RELEASE_SOURCE_COMMIT}:${BUNDLED_SCHEMA_INVENTORY_RELATIVE_PATH}" 2>/dev/null; then
    if ! git -C "${SOURCE_REPOSITORY_ROOT}" show "${CURRENT_RELEASE_SOURCE_COMMIT}:${BUNDLED_SCHEMA_INVENTORY_RELATIVE_PATH}" > "${SCHEMA_INVENTORY_PATH}"; then
      fail_check "schema-resources" "could not read bundled schema inventory at immutable source commit ${CURRENT_RELEASE_SOURCE_COMMIT}"
    fi
  # Exact v1.3.2 source predates this inventory and its immutable Makefile copied
  # every then-existing schema; no AX-only schema contracts existed at that commit.
  elif [[ "${CURRENT_RELEASE_SOURCE_COMMIT}" == "6a771c2ea10386bf7a0a8369a759930f01d56062" ]]; then
    find "${SCHEMA_CONTRACT_DIR}" -maxdepth 1 -type f -name '*.schema.json' -exec basename {} \; \
      | LC_ALL=C sort > "${SCHEMA_INVENTORY_PATH}"
  else
    fail_check "schema-resources" "immutable source commit ${CURRENT_RELEASE_SOURCE_COMMIT} is missing ${BUNDLED_SCHEMA_INVENTORY_RELATIVE_PATH}"
  fi
  SCHEMA_CONTRACT_DESCRIPTION="immutable source commit ${CURRENT_RELEASE_SOURCE_COMMIT}"
  BUNDLE_CONTRACT_DESCRIPTION="immutable source commit ${CURRENT_RELEASE_SOURCE_COMMIT} bundle contract"
else
  SCHEMA_CONTRACT_DIR="${ROOT_DIR}/docs/schemas"
  SCHEMA_INVENTORY_PATH="${ROOT_DIR}/${BUNDLED_SCHEMA_INVENTORY_RELATIVE_PATH}"
  SCHEMA_CONTRACT_DESCRIPTION="current candidate schema contract"
  if [[ ! -d "${SCHEMA_CONTRACT_DIR}" ]]; then
    fail_check "schema-resources" "current candidate schema contract is unavailable at ${SCHEMA_CONTRACT_DIR}"
  fi
  BUNDLE_CONTRACT_MAKEFILE="${ROOT_DIR}/Makefile"
  EXPECTED_ENTITLEMENTS_PATH="${ROOT_DIR}/Resources/Vifty.entitlements"
  BUNDLE_CONTRACT_DESCRIPTION="current candidate bundle contract"
fi

if [[ ! -f "${BUNDLE_CONTRACT_MAKEFILE}" ]]; then
  fail_check "release-source-contract" "${BUNDLE_CONTRACT_DESCRIPTION} is missing Makefile"
fi
if [[ ! -f "${EXPECTED_ENTITLEMENTS_PATH}" ]]; then
  fail_check "release-source-contract" "${BUNDLE_CONTRACT_DESCRIPTION} is missing Resources/Vifty.entitlements"
fi
if ! plutil -lint "${EXPECTED_ENTITLEMENTS_PATH}" >/dev/null; then
  fail_check "release-source-contract" "${BUNDLE_CONTRACT_DESCRIPTION} contains invalid Resources/Vifty.entitlements"
fi

support_contract_rows="${TMP_DIR}/expected-support-contract.tsv"
if ! ruby -e '
  path = ARGV.fetch(0)
  rows = File.readlines(path).each_with_object([]) do |line, found|
    match = line.match(/^\s*install\s+-m\s+755\s+scripts\/([A-Za-z0-9._-]+)\s+"\$\(CONTENTS\)\/Resources\/([A-Za-z0-9._-]+)"\s*$/)
    found << [match[1], match[2]] if match
  end
  abort("Makefile declares no executable support scripts for Contents/Resources") if rows.empty?
  destinations = rows.map(&:last)
  abort("Makefile declares duplicate support-script destinations") unless destinations.uniq.length == destinations.length
  rows.each { |source, destination| puts [source, destination].join("\t") }
' "${BUNDLE_CONTRACT_MAKEFILE}" > "${support_contract_rows}" 2>/dev/null; then
  fail_check "release-source-contract" "could not derive support-script inventory from ${BUNDLE_CONTRACT_DESCRIPTION}"
fi

EXPECTED_SUPPORT_INVENTORY_PATH="${TMP_DIR}/expected-support-inventory.txt"
cut -f2 "${support_contract_rows}" | LC_ALL=C sort > "${EXPECTED_SUPPORT_INVENTORY_PATH}"
while IFS=$'\t' read -r support_source support_destination; do
  if [[ "${CURRENT_RELEASE_MANIFEST_ENTRY_KIND}" != "candidate" ]]; then
    if ! git -C "${SOURCE_REPOSITORY_ROOT}" cat-file -e "${CURRENT_RELEASE_SOURCE_COMMIT}:scripts/${support_source}" 2>/dev/null; then
      fail_check "release-source-contract" "${BUNDLE_CONTRACT_DESCRIPTION} references missing support source scripts/${support_source}"
    fi
  elif [[ ! -f "${ROOT_DIR}/scripts/${support_source}" ]]; then
    fail_check "release-source-contract" "${BUNDLE_CONTRACT_DESCRIPTION} references missing support source scripts/${support_source}"
  fi
done < "${support_contract_rows}"

if ! ruby -e '
  text = File.read(ARGV.fetch(0))
  abort("Makefile does not bundle the viftyctl wrapper script inventory") unless text.match?(/^\s*install\s+-m\s+755\s+examples\/viftyctl\/\*\.sh\s+"\$\(WRAPPERS\)\/"\s*$/)
  abort("Makefile does not bundle the viftyctl wrapper README") unless text.match?(/^\s*install\s+-m\s+644\s+examples\/viftyctl\/README\.md\s+"\$\(WRAPPERS\)\/README\.md"\s*$/)
' "${BUNDLE_CONTRACT_MAKEFILE}" 2>/dev/null; then
  fail_check "release-source-contract" "could not derive workload-wrapper inventory from ${BUNDLE_CONTRACT_DESCRIPTION}"
fi

EXPECTED_WRAPPER_SCRIPT_INVENTORY_PATH="${TMP_DIR}/expected-wrapper-scripts.txt"
if [[ "${CURRENT_RELEASE_MANIFEST_ENTRY_KIND}" != "candidate" ]]; then
  if ! git -C "${SOURCE_REPOSITORY_ROOT}" ls-tree -r --name-only "${CURRENT_RELEASE_SOURCE_COMMIT}" -- examples/viftyctl 2>/dev/null \
      | ruby -ne 'path = $_.strip; puts File.basename(path) if path.match?(%r{\Aexamples/viftyctl/[^/]+\.sh\z})' \
      | LC_ALL=C sort > "${EXPECTED_WRAPPER_SCRIPT_INVENTORY_PATH}"; then
    fail_check "release-source-contract" "could not enumerate workload wrappers from ${BUNDLE_CONTRACT_DESCRIPTION}"
  fi
  if ! git -C "${SOURCE_REPOSITORY_ROOT}" cat-file -e "${CURRENT_RELEASE_SOURCE_COMMIT}:examples/viftyctl/README.md" 2>/dev/null; then
    fail_check "release-source-contract" "${BUNDLE_CONTRACT_DESCRIPTION} is missing examples/viftyctl/README.md"
  fi
else
  if [[ ! -d "${ROOT_DIR}/examples/viftyctl" || ! -f "${ROOT_DIR}/examples/viftyctl/README.md" ]]; then
    fail_check "release-source-contract" "${BUNDLE_CONTRACT_DESCRIPTION} is missing examples/viftyctl or its README"
  fi
  find "${ROOT_DIR}/examples/viftyctl" -maxdepth 1 -type f -name '*.sh' -exec basename {} \; \
    | LC_ALL=C sort > "${EXPECTED_WRAPPER_SCRIPT_INVENTORY_PATH}"
fi
if [[ ! -s "${EXPECTED_WRAPPER_SCRIPT_INVENTORY_PATH}" ]]; then
  fail_check "release-source-contract" "${BUNDLE_CONTRACT_DESCRIPTION} contains no workload wrapper scripts"
fi
EXPECTED_WRAPPER_INVENTORY_PATH="${TMP_DIR}/expected-wrapper-inventory.txt"
{
  cat "${EXPECTED_WRAPPER_SCRIPT_INVENTORY_PATH}"
  printf 'README.md\n'
} | LC_ALL=C sort > "${EXPECTED_WRAPPER_INVENTORY_PATH}"

if [[ -z "${ARTIFACT_PATH}" ]]; then
  if [[ "${RELEASE_VERSION}" != "${CASK_VERSION}" ]]; then
    fail_check "artifact-present" "--artifact is required when --release-version selects ${RELEASE_MANIFEST_ENTRY_KIND} ${RELEASE_VERSION} while the cask remains ${CASK_VERSION}"
  fi
  ARTIFACT_PATH="${TMP_DIR}/${EXPECTED_ARTIFACT_NAME}"
  curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 "${CASK_URL}" -o "${ARTIFACT_PATH}"
fi

if [[ ! -f "${ARTIFACT_PATH}" ]]; then
  write_failure_summary "artifact-present" "release artifact not found: ${ARTIFACT_PATH}"
  echo "error: release artifact not found: ${ARTIFACT_PATH}" >&2
  exit 66
fi

ACTUAL_SHA="$(shasum -a 256 "${ARTIFACT_PATH}" | awk '{print $1}')"
if ! sha_policy_facts="$(ruby -r"${RELEASE_ARTIFACT_CONTRACT_PATH}" -e '
  begin
    result = ViftyReleaseArtifactContract.resolve_expected_sha(
      current_kind: ARGV.fetch(0),
      current_sha: ARGV.fetch(1),
      tagged_kind: ARGV.fetch(2),
      tagged_sha: ARGV.fetch(3),
      override: ARGV.fetch(4)
    )
    puts [result.fetch(:sha), result.fetch(:source)].join("\t")
  rescue ViftyReleaseArtifactContract::SHAPolicyError => error
    warn error.message
    exit 1
  end
' "${CURRENT_RELEASE_MANIFEST_ENTRY_KIND}" "${CURRENT_MANIFEST_RELEASE_SHA}" \
  "${RELEASE_MANIFEST_ENTRY_KIND}" "${TAGGED_MANIFEST_RELEASE_SHA}" \
  "${EXPECTED_SHA_OVERRIDE}" 2>&1)"; then
  fail_check "expected-sha-format" "${sha_policy_facts}"
fi
IFS=$'\t' read -r EXPECTED_SHA EXPECTED_SHA_SOURCE <<< "${sha_policy_facts}"
if [[ "${ACTUAL_SHA}" != "${EXPECTED_SHA}" ]]; then
  fail_check "artifact-sha" "artifact SHA-256 ${ACTUAL_SHA} does not match ${EXPECTED_SHA_SOURCE} ${EXPECTED_SHA}"
fi

EXTRACT_DIR="${TMP_DIR}/extract"
mkdir -p "${EXTRACT_DIR}"
ditto -x -k "${ARTIFACT_PATH}" "${EXTRACT_DIR}"

APP_PATH="${EXTRACT_DIR}/Vifty.app"
if [[ ! -d "${APP_PATH}" ]]; then
  fail_check "app-bundle-present" "artifact did not contain Vifty.app at the zip root"
fi

MACOS_DIR="${APP_PATH}/Contents/MacOS"
SCHEMA_DIR="${APP_PATH}/Contents/Resources/schemas"
RESOURCES_DIR="${APP_PATH}/Contents/Resources"
WRAPPERS_DIR="${RESOURCES_DIR}/viftyctl-wrappers"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
DAEMON_PLIST="${APP_PATH}/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"

for executable in Vifty ViftyHelper ViftyDaemon viftyctl; do
  if [[ ! -x "${MACOS_DIR}/${executable}" ]]; then
    fail_check "required-executables" "missing executable ${MACOS_DIR}/${executable}"
  fi
done

actual_support_inventory_path="${TMP_DIR}/actual-support-inventory.txt"
find "${RESOURCES_DIR}" -maxdepth 1 -type f -name '*.sh' -exec basename {} \; \
  | LC_ALL=C sort > "${actual_support_inventory_path}"
missing_support_scripts="$(comm -23 "${EXPECTED_SUPPORT_INVENTORY_PATH}" "${actual_support_inventory_path}" | paste -sd ' ' -)"
unexpected_support_scripts="$(comm -13 "${EXPECTED_SUPPORT_INVENTORY_PATH}" "${actual_support_inventory_path}" | paste -sd ' ' -)"
if [[ -n "${missing_support_scripts}" ]]; then
  first_missing_support="${missing_support_scripts%% *}"
  fail_check "support-scripts" "missing executable support script ${RESOURCES_DIR}/${first_missing_support}; ${BUNDLE_CONTRACT_DESCRIPTION} also requires: ${missing_support_scripts}"
fi
if [[ -n "${unexpected_support_scripts}" ]]; then
  fail_check "support-scripts" "bundled support-script inventory does not match ${BUNDLE_CONTRACT_DESCRIPTION}; unexpected: ${unexpected_support_scripts}"
fi
while IFS= read -r support_script; do
  if [[ ! -x "${RESOURCES_DIR}/${support_script}" ]]; then
    fail_check "support-scripts" "missing executable support script ${RESOURCES_DIR}/${support_script}"
  fi
done < "${EXPECTED_SUPPORT_INVENTORY_PATH}"

actual_wrapper_inventory_path="${TMP_DIR}/actual-wrapper-inventory.txt"
if [[ -d "${WRAPPERS_DIR}" ]]; then
  find "${WRAPPERS_DIR}" -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort > "${actual_wrapper_inventory_path}"
else
  : > "${actual_wrapper_inventory_path}"
fi
missing_workload_wrappers="$(comm -23 "${EXPECTED_WRAPPER_INVENTORY_PATH}" "${actual_wrapper_inventory_path}" | paste -sd ' ' -)"
unexpected_workload_wrappers="$(comm -13 "${EXPECTED_WRAPPER_INVENTORY_PATH}" "${actual_wrapper_inventory_path}" | paste -sd ' ' -)"
missing_workload_wrapper_scripts="$(comm -23 "${EXPECTED_WRAPPER_SCRIPT_INVENTORY_PATH}" "${actual_wrapper_inventory_path}" | paste -sd ' ' -)"
if [[ -n "${missing_workload_wrapper_scripts}" ]]; then
  first_missing_wrapper="${missing_workload_wrapper_scripts%% *}"
  fail_check "workload-wrappers" "missing executable workload wrapper ${WRAPPERS_DIR}/${first_missing_wrapper}; ${BUNDLE_CONTRACT_DESCRIPTION} also requires: ${missing_workload_wrapper_scripts}"
fi
if [[ " ${missing_workload_wrappers} " == *" README.md "* ]]; then
  fail_check "workload-wrappers" "missing bundled workload wrapper README ${WRAPPERS_DIR}/README.md"
fi
if [[ -n "${unexpected_workload_wrappers}" ]]; then
  fail_check "workload-wrappers" "bundled workload-wrapper inventory does not match ${BUNDLE_CONTRACT_DESCRIPTION}; unexpected: ${unexpected_workload_wrappers}"
fi
while IFS= read -r workload_wrapper; do
  if [[ ! -x "${WRAPPERS_DIR}/${workload_wrapper}" ]]; then
    fail_check "workload-wrappers" "missing executable workload wrapper ${WRAPPERS_DIR}/${workload_wrapper}"
  fi
done < "${EXPECTED_WRAPPER_SCRIPT_INVENTORY_PATH}"
if [[ ! -s "${WRAPPERS_DIR}/README.md" ]]; then
  fail_check "workload-wrappers" "missing bundled workload wrapper README ${WRAPPERS_DIR}/README.md"
fi

expected_schema_names_path="${TMP_DIR}/expected-schema-names.txt"
actual_schema_names_path="${TMP_DIR}/actual-schema-names.txt"
if ! expected_schema_names="$(ruby -I "${SCRIPT_DIR}/lib" -rbundled_schema_inventory -e '
  puts ViftyBundledSchemaInventory.load!(ARGV.fetch(0))
' "${SCHEMA_INVENTORY_PATH}" 2>&1)"; then
  fail_check "schema-resources" "invalid bundled schema inventory for ${SCHEMA_CONTRACT_DESCRIPTION}: ${expected_schema_names}"
fi
printf '%s\n' "${expected_schema_names}" > "${expected_schema_names_path}"
if [[ -d "${SCHEMA_DIR}" ]]; then
  find "${SCHEMA_DIR}" -maxdepth 1 -type f -name '*.schema.json' -exec basename {} \; | LC_ALL=C sort > "${actual_schema_names_path}"
else
  : > "${actual_schema_names_path}"
fi
if [[ ! -s "${expected_schema_names_path}" ]]; then
  fail_check "schema-resources" "${SCHEMA_CONTRACT_DESCRIPTION} contains no reviewed JSON Schemas"
fi

missing_schema_names="$(comm -23 "${expected_schema_names_path}" "${actual_schema_names_path}" | paste -sd ' ' -)"
unexpected_schema_names="$(comm -13 "${expected_schema_names_path}" "${actual_schema_names_path}" | paste -sd ' ' -)"
if [[ -n "${missing_schema_names}" || -n "${unexpected_schema_names}" ]]; then
  schema_set_message="bundled schema set does not match ${SCHEMA_CONTRACT_DESCRIPTION}"
  if [[ -n "${missing_schema_names}" ]]; then
    schema_set_message="${schema_set_message}; missing bundled schema(s) from ${SCHEMA_DIR}: ${missing_schema_names}"
  fi
  if [[ -n "${unexpected_schema_names}" ]]; then
    schema_set_message="${schema_set_message}; unexpected: ${unexpected_schema_names}"
  fi
  fail_check "schema-resources" "${schema_set_message}"
fi

while IFS= read -r schema; do
  schema_path="${SCHEMA_DIR}/${schema}"
  reviewed_schema_path="${SCHEMA_CONTRACT_DIR}/${schema}"
  if ! expected_schema_id="$(ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    id = data.fetch("$id")
    abort("reviewed schema $id must be an https URL") unless id.is_a?(String) && id.start_with?("https://")
    print id
  ' "${reviewed_schema_path}" 2>&1)"; then
    fail_check "schema-resources" "invalid reviewed schema in ${SCHEMA_CONTRACT_DESCRIPTION}: ${reviewed_schema_path}: ${expected_schema_id}"
  fi
  if ! schema_error="$(verify_schema_resource "${schema_path}" "${expected_schema_id}" "${reviewed_schema_path}" 2>&1)"; then
    fail_check "schema-resources" "invalid bundled schema ${schema_path} against ${SCHEMA_CONTRACT_DESCRIPTION}: ${schema_error}"
  fi
done < "${expected_schema_names_path}"

if ! plutil -lint "${INFO_PLIST}" >/dev/null; then
  fail_check "plist-lint" "Info.plist is not valid: ${INFO_PLIST}"
fi
if ! plutil -lint "${DAEMON_PLIST}" >/dev/null; then
  fail_check "plist-lint" "LaunchDaemon plist is not valid: ${DAEMON_PLIST}"
fi

if ! BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"; then
  fail_check "bundle-version" "Info.plist is missing CFBundleShortVersionString"
fi
if [[ "${BUNDLE_VERSION}" != "${RELEASE_VERSION}" ]]; then
  if [[ "${RELEASE_VERSION}" == "${CASK_VERSION}" ]]; then
    fail_check "bundle-version" "bundle version ${BUNDLE_VERSION} does not match cask version ${CASK_VERSION}"
  else
    fail_check "bundle-version" "bundle version ${BUNDLE_VERSION} does not match selected manifest release ${RELEASE_VERSION}"
  fi
fi

if ! BUNDLE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"; then
  fail_check "bundle-identity" "Info.plist is missing CFBundleVersion"
fi
if [[ "${BUNDLE_BUILD}" != "${RELEASE_BUILD}" ]]; then
  fail_check "bundle-identity" "bundle build ${BUNDLE_BUILD} does not match release manifest build ${RELEASE_BUILD}"
fi
if ! BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"; then
  fail_check "bundle-identity" "Info.plist is missing CFBundleIdentifier"
fi
if [[ "${BUNDLE_IDENTIFIER}" != "${EXPECTED_BUNDLE_ID}" ]]; then
  fail_check "bundle-identity" "bundle identifier ${BUNDLE_IDENTIFIER} does not match release manifest ${EXPECTED_BUNDLE_ID}"
fi
if ! LAUNCH_DAEMON_LABEL="$(/usr/libexec/PlistBuddy -c 'Print :Label' "${DAEMON_PLIST}")"; then
  fail_check "bundle-identity" "LaunchDaemon plist is missing Label"
fi
if [[ "${LAUNCH_DAEMON_LABEL}" != "${EXPECTED_DAEMON_ID}" ]]; then
  fail_check "bundle-identity" "LaunchDaemon Label ${LAUNCH_DAEMON_LABEL} does not match release manifest ${EXPECTED_DAEMON_ID}"
fi
if [[ "$(/usr/libexec/PlistBuddy -c "Print :MachServices:${EXPECTED_DAEMON_ID}" "${DAEMON_PLIST}" 2>/dev/null || true)" != "true" ]]; then
  fail_check "bundle-identity" "LaunchDaemon MachServices is missing enabled ${EXPECTED_DAEMON_ID}"
fi
MACH_SERVICE_NAME="${EXPECTED_DAEMON_ID}"

if /usr/bin/plutil -convert json -o - -- "${DAEMON_PLIST}" | ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  keys = Hash(data["EnvironmentVariables"]).keys.grep(/\AVIFTY_XPC_ADHOC_/)
  exit(keys.empty? ? 1 : 0)
'; then
  fail_check "xpc-trust-metadata" "public release LaunchDaemon must not contain VIFTY_XPC_ADHOC_* development keys"
fi

architectures_for() {
  local path="$1"
  "${LIPO_PATH}" -archs "${path}" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort | xargs
}

if ! APP_ARCHITECTURES="$(architectures_for "${MACOS_DIR}/Vifty")" || [[ -z "${APP_ARCHITECTURES}" ]]; then
  fail_check "binary-architectures" "could not read architectures for ${MACOS_DIR}/Vifty"
fi
if ! HELPER_ARCHITECTURES="$(architectures_for "${MACOS_DIR}/ViftyHelper")" || [[ -z "${HELPER_ARCHITECTURES}" ]]; then
  fail_check "binary-architectures" "could not read architectures for ${MACOS_DIR}/ViftyHelper"
fi
if ! DAEMON_ARCHITECTURES="$(architectures_for "${MACOS_DIR}/ViftyDaemon")" || [[ -z "${DAEMON_ARCHITECTURES}" ]]; then
  fail_check "binary-architectures" "could not read architectures for ${MACOS_DIR}/ViftyDaemon"
fi
if ! CTL_ARCHITECTURES="$(architectures_for "${MACOS_DIR}/viftyctl")" || [[ -z "${CTL_ARCHITECTURES}" ]]; then
  fail_check "binary-architectures" "could not read architectures for ${MACOS_DIR}/viftyctl"
fi
for actual_architectures in "${APP_ARCHITECTURES}" "${HELPER_ARCHITECTURES}" "${DAEMON_ARCHITECTURES}" "${CTL_ARCHITECTURES}"; do
  if [[ "${actual_architectures}" != "${EXPECTED_ARCHITECTURES}" ]]; then
    fail_check "binary-architectures" "binary architectures ${actual_architectures} do not match release manifest ${EXPECTED_ARCHITECTURES}"
  fi
done
SUMMARY_IDENTITY_READY=1

team_identifier_for() {
  local path="$1"
  /usr/bin/codesign -dvvv "${path}" 2>&1 | awk -F= '/^TeamIdentifier=/ && !found {print $2; found=1}'
}

signing_identifier_for() {
  local path="$1"
  /usr/bin/codesign -dvvv "${path}" 2>&1 | awk -F= '/^Identifier=/ && !found {print $2; found=1}'
}

signing_details_for() {
  local path="$1"
  /usr/bin/codesign -dvvv "${path}" 2>&1
}

if [[ "${SKIP_SIGNATURE_CHECKS}" != "1" ]]; then
  if ! /usr/bin/codesign --verify --deep --strict "${APP_PATH}"; then
    fail_check "codesign-teamid" "codesign strict verification failed for ${APP_PATH}"
  fi
  for signed_identity in \
    "${APP_PATH}|${EXPECTED_BUNDLE_ID}" \
    "${MACOS_DIR}/ViftyHelper|${EXPECTED_HELPER_ID}" \
    "${MACOS_DIR}/ViftyDaemon|${EXPECTED_DAEMON_ID}" \
    "${MACOS_DIR}/viftyctl|${EXPECTED_CTL_ID}"
  do
    signed_path="${signed_identity%%|*}"
    expected_identifier="${signed_identity#*|}"
    actual_identifier="$(signing_identifier_for "${signed_path}")"
    if [[ "${actual_identifier}" != "${expected_identifier}" ]]; then
      fail_check "codesign-teamid" "${signed_path} signing identifier ${actual_identifier:-missing} does not match ${expected_identifier}"
    fi
    if ! grep -Fq '(runtime)' <<< "$(signing_details_for "${signed_path}")"; then
      fail_check "codesign-runtime-entitlements" "${signed_path} is missing the hardened runtime signing flag"
    fi
  done

  expected_entitlements_json="$(/usr/bin/plutil -convert json -o - -- "${EXPECTED_ENTITLEMENTS_PATH}")"
  if ! actual_entitlements_json="$(/usr/bin/codesign --display --entitlements - --xml "${APP_PATH}" 2>/dev/null | /usr/bin/plutil -convert json -o - -- -)"; then
    fail_check "codesign-runtime-entitlements" "could not read signed app entitlements"
  fi
  if ! ruby -rjson -e '
    expected = JSON.parse(ARGV.fetch(0))
    actual = JSON.parse(ARGV.fetch(1))
    abort("signed app entitlements differ from reviewed source") unless actual == expected
  ' "${expected_entitlements_json}" "${actual_entitlements_json}"; then
    fail_check "codesign-runtime-entitlements" "signed app entitlements do not exactly match ${BUNDLE_CONTRACT_DESCRIPTION} Resources/Vifty.entitlements"
  fi

  APP_TEAM_ID="$(team_identifier_for "${APP_PATH}")"
  if [[ -z "${APP_TEAM_ID}" || "${APP_TEAM_ID}" == "not set" ]]; then
    fail_check "codesign-teamid" "app is not signed with a Developer ID TeamIdentifier"
  fi

  if [[ -n "${EXPECTED_TEAM_ID}" && "${APP_TEAM_ID}" != "${EXPECTED_TEAM_ID}" ]]; then
    fail_check "codesign-teamid" "app TeamIdentifier ${APP_TEAM_ID} does not match expected ${EXPECTED_TEAM_ID}"
  fi

  REQUIRED_TEAM_ID="${EXPECTED_TEAM_ID:-${APP_TEAM_ID}}"
  for signed_path in "${MACOS_DIR}/ViftyHelper" "${MACOS_DIR}/ViftyDaemon" "${MACOS_DIR}/viftyctl"; do
    TEAM_ID="$(team_identifier_for "${signed_path}")"
    if [[ "${TEAM_ID}" != "${REQUIRED_TEAM_ID}" ]]; then
      fail_check "codesign-teamid" "${signed_path} TeamIdentifier ${TEAM_ID:-missing} does not match ${REQUIRED_TEAM_ID}"
    fi
  done

  if ! DAEMON_TEAM_ID="$(/usr/bin/plutil -extract EnvironmentVariables.VIFTY_XPC_ALLOWED_TEAM_ID raw -o - "${DAEMON_PLIST}")"; then
    fail_check "codesign-teamid" "LaunchDaemon is missing VIFTY_XPC_ALLOWED_TEAM_ID"
  fi
  if [[ "${DAEMON_TEAM_ID}" != "${REQUIRED_TEAM_ID}" ]]; then
    fail_check "codesign-teamid" "LaunchDaemon VIFTY_XPC_ALLOWED_TEAM_ID ${DAEMON_TEAM_ID:-missing} does not match ${REQUIRED_TEAM_ID}"
  fi
fi

if [[ "${SKIP_NOTARIZATION_CHECKS}" != "1" ]]; then
  if ! xcrun stapler validate "${APP_PATH}"; then
    fail_check "notarization-gatekeeper" "stapler validation failed for ${APP_PATH}"
  fi
  if ! /usr/sbin/spctl --assess --type execute --verbose "${APP_PATH}"; then
    fail_check "notarization-gatekeeper" "Gatekeeper assessment failed for ${APP_PATH}"
  fi
fi

write_summary() {
  REQUIRED_TEAM_ID="${EXPECTED_TEAM_ID:-${APP_TEAM_ID:-}}"
  write_summary_header "passed"
  printf ',\n  "checks": [\n' >> "${SUMMARY_PATH}"

  write_check 1 "artifact-sha" "passed" "release-trust" "Artifact SHA-256 matched ${EXPECTED_SHA_SOURCE}."
  write_check 0 "app-bundle-present" "passed" "release-trust" "Zip contained Vifty.app at the root."
  write_check 0 "required-executables" "passed" "release-trust" "App bundle contained Vifty, ViftyHelper, ViftyDaemon, and viftyctl executables."
  write_check 0 "support-scripts" "passed" "release-trust" "App bundle contained executable read-only agent/helper and supervised agent-run smoke evidence collectors."
  write_check 0 "workload-wrappers" "passed" "release-trust" "App bundle contained executable guarded viftyctl workload wrappers in Contents/Resources/viftyctl-wrappers."
  write_check 0 "schema-resources" "passed" "release-trust" "App bundle contained valid support, release, validation, and viftyctl JSON Schemas with expected IDs in Contents/Resources/schemas."
  write_check 0 "plist-lint" "passed" "release-trust" "Info.plist and bundled LaunchDaemon plist were valid."
  write_check 0 "bundle-version" "passed" "release-trust" "Bundle version matched the selected release-manifest entry."
  write_check 0 "bundle-identity" "passed" "release-trust" "Bundle ID/build and LaunchDaemon label/Mach service matched the release manifest."
  write_check 0 "xpc-trust-metadata" "passed" "release-trust" "LaunchDaemon contained TeamID release policy and no ad-hoc development allowlist keys."
  write_check 0 "binary-architectures" "passed" "release-trust" "App, helper, daemon, and viftyctl architectures matched the release manifest."
  if [[ "${SKIP_SIGNATURE_CHECKS}" == "1" ]]; then
    write_check 0 "codesign-teamid" "skipped" "release-trust" "Signature and TeamID checks were explicitly skipped."
    write_check 0 "codesign-runtime-entitlements" "skipped" "release-trust" "Hardened runtime and entitlement checks were explicitly skipped."
  else
    write_check 0 "codesign-teamid" "passed" "release-trust" "App, helper, daemon, viftyctl, and LaunchDaemon TeamID checks passed."
    write_check 0 "codesign-runtime-entitlements" "passed" "release-trust" "App, helper, daemon, and viftyctl used hardened runtime; app entitlements exactly matched reviewed source."
  fi
  if [[ "${SKIP_NOTARIZATION_CHECKS}" == "1" ]]; then
    write_check 0 "notarization-gatekeeper" "skipped" "release-trust" "Stapler and Gatekeeper checks were explicitly skipped."
  else
    write_check 0 "notarization-gatekeeper" "passed" "release-trust" "Stapler validation and Gatekeeper assessment passed."
  fi

  {
    printf '\n'
    printf '  ]\n'
    printf '}\n'
  } >> "${SUMMARY_PATH}"
}

if [[ -n "${SUMMARY_PATH}" ]]; then
  write_summary
  if [[ "${SKIP_SIGNATURE_CHECKS}" != "1" && "${SKIP_NOTARIZATION_CHECKS}" != "1" ]]; then
    if ! summary_contract_error="$(ruby "${RELEASE_ARTIFACT_CONTRACT_PATH}" validate-verifier-summary \
      "${SUMMARY_PATH}" "${RELEASE_MANIFEST_PATH}" "${SOURCE_REPOSITORY_ROOT}" 2>&1)"; then
      echo "error: release artifact summary contract validation failed: ${summary_contract_error}" >&2
      exit 65
    fi
  fi
fi

echo "Release artifact OK: version ${RELEASE_VERSION}, sha256 ${ACTUAL_SHA}"
