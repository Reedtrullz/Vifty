#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/sign-release-candidate.sh --app <Vifty.app> --manifest <release-manifest.json> --entitlements <Vifty.entitlements> --identity <Developer ID identity> --team-id <TEAMID> --keychain <temporary-keychain>

Signs an already-built, hash-inventoried Vifty candidate. This script never
builds source or runs package tooling; it validates manifest identity, build,
architecture, and LaunchDaemon facts before and after signing.
USAGE
}

APP_PATH=""
MANIFEST_PATH=""
ENTITLEMENTS_PATH=""
SIGNING_IDENTITY=""
EXPECTED_TEAM_ID=""
SIGNING_KEYCHAIN=""
LIPO_PATH="${VIFTY_LIPO_PATH:-/usr/bin/lipo}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --manifest)
      MANIFEST_PATH="${2:-}"
      shift 2
      ;;
    --entitlements)
      ENTITLEMENTS_PATH="${2:-}"
      shift 2
      ;;
    --identity)
      SIGNING_IDENTITY="${2:-}"
      shift 2
      ;;
    --team-id)
      EXPECTED_TEAM_ID="${2:-}"
      shift 2
      ;;
    --keychain)
      SIGNING_KEYCHAIN="${2:-}"
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

for required_value in APP_PATH MANIFEST_PATH ENTITLEMENTS_PATH SIGNING_IDENTITY EXPECTED_TEAM_ID SIGNING_KEYCHAIN; do
  if [[ -z "${!required_value}" ]]; then
    echo "error: ${required_value} is required" >&2
    usage
    exit 64
  fi
done

for required_path in "${APP_PATH}" "${MANIFEST_PATH}" "${ENTITLEMENTS_PATH}" "${SIGNING_KEYCHAIN}"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "error: required path not found: ${required_path}" >&2
    exit 66
  fi
done

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
DAEMON_PLIST="${APP_PATH}/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
MACOS_DIR="${APP_PATH}/Contents/MacOS"
for required_path in "${INFO_PLIST}" "${DAEMON_PLIST}" \
  "${MACOS_DIR}/Vifty" "${MACOS_DIR}/ViftyHelper" \
  "${MACOS_DIR}/ViftyDaemon" "${MACOS_DIR}/viftyctl"; do
  if [[ ! -e "${required_path}" ]]; then
    echo "error: release candidate is missing ${required_path}" >&2
    exit 66
  fi
done

manifest_facts="$(ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  candidate = data["candidate"] or abort("release manifest candidate is null")
  product = data.fetch("product")
  policy = data.fetch("releasePolicy")
  puts [
    product.fetch("bundleID"), product.fetch("daemonID"), product.fetch("helperID"),
    product.fetch("ctlID"), product.fetch("architectures").sort.join(" "),
    policy.fetch("developerTeamID"), candidate.fetch("version"), candidate.fetch("build")
  ].join("\t")
' "${MANIFEST_PATH}")"
IFS=$'\t' read -r BUNDLE_ID DAEMON_ID HELPER_ID CTL_ID EXPECTED_ARCHITECTURES MANIFEST_TEAM_ID CANDIDATE_VERSION CANDIDATE_BUILD <<< "${manifest_facts}"

if [[ "${EXPECTED_TEAM_ID}" != "${MANIFEST_TEAM_ID}" ]]; then
  echo "error: requested TeamID ${EXPECTED_TEAM_ID} does not match manifest TeamID ${MANIFEST_TEAM_ID}" >&2
  exit 65
fi

assert_plist_value() {
  local plist="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "${plist}" 2>/dev/null || true)"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "error: ${plist} ${key} ${actual:-missing} does not match ${expected}" >&2
    exit 65
  fi
}

assert_plist_value "${INFO_PLIST}" "CFBundleIdentifier" "${BUNDLE_ID}"
assert_plist_value "${INFO_PLIST}" "CFBundleShortVersionString" "${CANDIDATE_VERSION}"
assert_plist_value "${INFO_PLIST}" "CFBundleVersion" "${CANDIDATE_BUILD}"
assert_plist_value "${DAEMON_PLIST}" "Label" "${DAEMON_ID}"
assert_plist_value "${DAEMON_PLIST}" "MachServices:${DAEMON_ID}" "true"
assert_plist_value "${DAEMON_PLIST}" "EnvironmentVariables:VIFTY_XPC_ALLOWED_TEAM_ID" "${EXPECTED_TEAM_ID}"
if /usr/bin/plutil -convert json -o - -- "${DAEMON_PLIST}" | ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  keys = Hash(data["EnvironmentVariables"]).keys.grep(/\AVIFTY_XPC_ADHOC_/)
  exit(keys.empty? ? 1 : 0)
'; then
  echo "error: release candidate LaunchDaemon must not contain VIFTY_XPC_ADHOC_* development keys" >&2
  exit 65
fi

assert_architectures() {
  local binary="$1"
  local actual
  actual="$("${LIPO_PATH}" -archs "${binary}" | tr ' ' '\n' | sort | xargs)"
  if [[ "${actual}" != "${EXPECTED_ARCHITECTURES}" ]]; then
    echo "error: ${binary} architectures ${actual:-missing} do not match ${EXPECTED_ARCHITECTURES}" >&2
    exit 65
  fi
}

for binary in \
  "${MACOS_DIR}/Vifty" \
  "${MACOS_DIR}/ViftyHelper" \
  "${MACOS_DIR}/ViftyDaemon" \
  "${MACOS_DIR}/viftyctl"; do
  assert_architectures "${binary}"
done

/usr/bin/codesign --force --keychain "${SIGNING_KEYCHAIN}" --sign "${SIGNING_IDENTITY}" --options runtime --identifier "${HELPER_ID}" "${MACOS_DIR}/ViftyHelper"
/usr/bin/codesign --force --keychain "${SIGNING_KEYCHAIN}" --sign "${SIGNING_IDENTITY}" --options runtime --identifier "${DAEMON_ID}" "${MACOS_DIR}/ViftyDaemon"
/usr/bin/codesign --force --keychain "${SIGNING_KEYCHAIN}" --sign "${SIGNING_IDENTITY}" --options runtime --identifier "${CTL_ID}" "${MACOS_DIR}/viftyctl"
/usr/bin/codesign --force --keychain "${SIGNING_KEYCHAIN}" --sign "${SIGNING_IDENTITY}" --options runtime --entitlements "${ENTITLEMENTS_PATH}" "${APP_PATH}"
/usr/bin/codesign --verify --deep --strict "${APP_PATH}"

assert_signature() {
  local path="$1"
  local expected_identifier="$2"
  local details identifier team_id
  details="$(/usr/bin/codesign -dvvv "${path}" 2>&1)"
  identifier="$(printf '%s\n' "${details}" | awk -F= '/^Identifier=/{print $2; exit}')"
  team_id="$(printf '%s\n' "${details}" | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
  if [[ "${identifier}" != "${expected_identifier}" || "${team_id}" != "${EXPECTED_TEAM_ID}" ]]; then
    echo "error: ${path} signed identity ${identifier:-missing}/${team_id:-missing} does not match ${expected_identifier}/${EXPECTED_TEAM_ID}" >&2
    exit 65
  fi
  if ! grep -Fq '(runtime)' <<< "${details}"; then
    echo "error: ${path} is missing the hardened runtime signing flag" >&2
    exit 65
  fi
}

assert_signature "${APP_PATH}" "${BUNDLE_ID}"
assert_signature "${MACOS_DIR}/ViftyHelper" "${HELPER_ID}"
assert_signature "${MACOS_DIR}/ViftyDaemon" "${DAEMON_ID}"
assert_signature "${MACOS_DIR}/viftyctl" "${CTL_ID}"

expected_entitlements_json="$(/usr/bin/plutil -convert json -o - -- "${ENTITLEMENTS_PATH}")"
if ! actual_entitlements_json="$(/usr/bin/codesign --display --entitlements - --xml "${APP_PATH}" 2>/dev/null | /usr/bin/plutil -convert json -o - -- -)"; then
  echo "error: could not read signed app entitlements" >&2
  exit 65
fi
if ! ruby -rjson -e '
  expected = JSON.parse(ARGV.fetch(0))
  actual = JSON.parse(ARGV.fetch(1))
  abort("signed app entitlements do not exactly match the reviewed entitlements file") unless actual == expected
' "${expected_entitlements_json}" "${actual_entitlements_json}"; then
  echo "error: signed app entitlements do not exactly match ${ENTITLEMENTS_PATH}" >&2
  exit 65
fi

echo "Signed Vifty ${CANDIDATE_VERSION} build ${CANDIDATE_BUILD} for ${EXPECTED_ARCHITECTURES} with TeamID ${EXPECTED_TEAM_ID}, reviewed entitlements, and hardened runtime"
