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
  --expected-sha <sha256>        Verify the artifact against this SHA-256 instead
                                  of the cask sha256. Used by the release workflow
                                  before the cask checksum follow-up commit exists.
  --summary <path>               Write a machine-readable JSON verification summary
                                  after checks pass or a release-trust check fails.
  --team-id <TEAMID>             Require this Apple Developer TeamID. If omitted,
                                  the script requires a non-ad-hoc TeamIdentifier
                                  and uses it for LaunchDaemon validation.
  --skip-signature-checks        Skip codesign and TeamID checks. For tests/local
                                  diagnostics only; do not use for public release.
  --skip-notarization-checks     Skip stapler and Gatekeeper checks. For tests/local
                                  diagnostics only; do not use for public release.
  -h, --help                     Show this help.

By default this is a public-release trust gate: it verifies the cask SHA-256,
bundle version, required executables, bundled schema validity, plist validity,
bundled evidence collector scripts, guarded workload wrappers, Developer ID TeamID, daemon TeamID allowlist,
stapled notarization ticket, and Gatekeeper assessment.
USAGE
}

ROOT_DIR="${VIFTY_RELEASE_ARTIFACT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CASK_PATH="${ROOT_DIR}/Casks/vifty.rb"
RELEASE_ARTIFACT_SUMMARY_SCHEMA_ID="https://vifty.local/schemas/release-artifact-summary.schema.json"
ARTIFACT_PATH=""
EXPECTED_SHA_OVERRIDE=""
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

verify_schema_resource() {
  local path="$1"
  local expected_id="$2"
  ruby -rjson -e '
    path, expected_id = ARGV
    begin
      data = JSON.parse(File.read(path))
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
  ' "${path}" "${expected_id}"
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
    printf '  "schemaVersion": 1,\n'
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

if [[ ! "${CASK_SHA}" =~ ^[0-9a-f]{64}$ ]]; then
  fail_check "cask-sha-format" "cask sha256 must be a lowercase 64-character SHA-256 checksum"
fi

if [[ -n "${EXPECTED_SHA_OVERRIDE}" && ! "${EXPECTED_SHA_OVERRIDE}" =~ ^[0-9a-f]{64}$ ]]; then
  fail_check "expected-sha-format" "--expected-sha must be a lowercase 64-character SHA-256 checksum"
fi

CASK_URL="${CASK_URL_TEMPLATE//\#\{version\}/${CASK_VERSION}}"
EXPECTED_ARTIFACT_NAME="Vifty-v${CASK_VERSION}.zip"

if [[ "${CASK_URL}" != *"/${EXPECTED_ARTIFACT_NAME}" ]]; then
  fail_check "cask-url-artifact-name" "cask URL must end with ${EXPECTED_ARTIFACT_NAME}"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vifty-release-artifact.XXXXXX")"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

if [[ -z "${ARTIFACT_PATH}" ]]; then
  ARTIFACT_PATH="${TMP_DIR}/${EXPECTED_ARTIFACT_NAME}"
  curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 "${CASK_URL}" -o "${ARTIFACT_PATH}"
fi

if [[ ! -f "${ARTIFACT_PATH}" ]]; then
  write_failure_summary "artifact-present" "release artifact not found: ${ARTIFACT_PATH}"
  echo "error: release artifact not found: ${ARTIFACT_PATH}" >&2
  exit 66
fi

ACTUAL_SHA="$(shasum -a 256 "${ARTIFACT_PATH}" | awk '{print $1}')"
EXPECTED_SHA="${EXPECTED_SHA_OVERRIDE:-${CASK_SHA}}"
EXPECTED_SHA_SOURCE="cask sha256"
if [[ -n "${EXPECTED_SHA_OVERRIDE}" ]]; then
  EXPECTED_SHA_SOURCE="expected sha256"
fi
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

for support_script in collect-agent-cooling-evidence.sh collect-agent-run-smoke-evidence.sh; do
  if [[ ! -x "${RESOURCES_DIR}/${support_script}" ]]; then
    fail_check "support-scripts" "missing executable support script ${RESOURCES_DIR}/${support_script}"
  fi
done

for workload_wrapper in \
  guarded-run.sh \
  bun-build.sh \
  bun-test.sh \
  swift-test.sh \
  swift-release-build.sh \
  xcode-build.sh \
  xcode-test.sh \
  make-build.sh \
  make-test.sh \
  make-verify.sh \
  npm-build.sh \
  npm-test.sh \
  pnpm-build.sh \
  pnpm-test.sh \
  go-build.sh \
  go-test.sh \
  cargo-build.sh \
  cargo-test.sh \
  pytest.sh \
  uv-build.sh \
  uv-test.sh \
  local-model.sh \
  custom-workload.sh
do
  if [[ ! -x "${WRAPPERS_DIR}/${workload_wrapper}" ]]; then
    fail_check "workload-wrappers" "missing executable workload wrapper ${WRAPPERS_DIR}/${workload_wrapper}"
  fi
done
if [[ ! -s "${WRAPPERS_DIR}/README.md" ]]; then
  fail_check "workload-wrappers" "missing bundled workload wrapper README ${WRAPPERS_DIR}/README.md"
fi

for schema_reference in \
  "agent-cooling-evidence-summary.schema.json|https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json" \
  "agent-cooling-evidence-review.schema.json|https://vifty.local/schemas/agent-cooling-evidence-review.schema.json" \
  "agent-run-smoke-readiness.schema.json|https://vifty.local/schemas/agent-run-smoke-readiness.schema.json" \
  "agent-run-smoke-evidence-summary.schema.json|https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json" \
  "guarded-run-decision.schema.json|https://vifty.local/schemas/guarded-run-decision.schema.json" \
  "manual-smoke-readiness.schema.json|https://vifty.local/schemas/manual-smoke-readiness.schema.json" \
  "release-artifact-summary.schema.json|https://vifty.local/schemas/release-artifact-summary.schema.json" \
  "release-readiness.schema.json|https://vifty.local/schemas/release-readiness.schema.json" \
  "validation-report-index.schema.json|https://vifty.local/schemas/validation-report-index.schema.json" \
  "validation-review-result.schema.json|https://vifty.local/schemas/validation-review-result.schema.json" \
  "viftyctl-audit.schema.json|https://vifty.local/schemas/viftyctl-audit.schema.json" \
  "viftyctl-agent-rule.schema.json|https://vifty.local/schemas/viftyctl-agent-rule.schema.json" \
  "viftyctl-capabilities.schema.json|https://vifty.local/schemas/viftyctl-capabilities.schema.json" \
  "viftyctl-command-error.schema.json|https://vifty.local/schemas/viftyctl-command-error.schema.json" \
  "viftyctl-diagnose.schema.json|https://vifty.local/schemas/viftyctl-diagnose.schema.json" \
  "viftyctl-run.schema.json|https://vifty.local/schemas/viftyctl-run.schema.json" \
  "viftyctl-status.schema.json|https://vifty.local/schemas/viftyctl-status.schema.json"
do
  schema="${schema_reference%%|*}"
  expected_schema_id="${schema_reference#*|}"
  schema_path="${SCHEMA_DIR}/${schema}"
  if [[ ! -s "${SCHEMA_DIR}/${schema}" ]]; then
    fail_check "schema-resources" "missing bundled schema ${schema_path}"
  fi
  if ! schema_error="$(verify_schema_resource "${schema_path}" "${expected_schema_id}" 2>&1)"; then
    fail_check "schema-resources" "invalid bundled schema ${schema_path}: ${schema_error}"
  fi
done

if ! plutil -lint "${INFO_PLIST}" >/dev/null; then
  fail_check "plist-lint" "Info.plist is not valid: ${INFO_PLIST}"
fi
if ! plutil -lint "${DAEMON_PLIST}" >/dev/null; then
  fail_check "plist-lint" "LaunchDaemon plist is not valid: ${DAEMON_PLIST}"
fi

if ! BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"; then
  fail_check "bundle-version" "Info.plist is missing CFBundleShortVersionString"
fi
if [[ "${BUNDLE_VERSION}" != "${CASK_VERSION}" ]]; then
  fail_check "bundle-version" "bundle version ${BUNDLE_VERSION} does not match cask version ${CASK_VERSION}"
fi

team_identifier_for() {
  local path="$1"
  codesign -dvvv "${path}" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}'
}

if [[ "${SKIP_SIGNATURE_CHECKS}" != "1" ]]; then
  if ! codesign --verify --deep --strict "${APP_PATH}"; then
    fail_check "codesign-teamid" "codesign strict verification failed for ${APP_PATH}"
  fi
  if ! codesign -dvvv "${MACOS_DIR}/viftyctl" 2>&1 | grep 'Identifier=tech.reidar.vifty.ctl' >/dev/null; then
    fail_check "codesign-teamid" "viftyctl signing identifier is not tech.reidar.vifty.ctl"
  fi
  if ! codesign -dvvv "${MACOS_DIR}/ViftyHelper" 2>&1 | grep 'Identifier=tech.reidar.vifty.helper' >/dev/null; then
    fail_check "codesign-teamid" "ViftyHelper signing identifier is not tech.reidar.vifty.helper"
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
  write_check 0 "bundle-version" "passed" "release-trust" "Bundle version matched the cask version."
  if [[ "${SKIP_SIGNATURE_CHECKS}" == "1" ]]; then
    write_check 0 "codesign-teamid" "skipped" "release-trust" "Signature and TeamID checks were explicitly skipped."
  else
    write_check 0 "codesign-teamid" "passed" "release-trust" "App, helper, daemon, viftyctl, and LaunchDaemon TeamID checks passed."
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
fi

echo "Release artifact OK: version ${CASK_VERSION}, sha256 ${ACTUAL_SHA}"
