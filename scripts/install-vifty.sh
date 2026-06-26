#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Vifty"
CONFIGURATION="${CONFIGURATION:-release}"
INSTALL_DIR="${VIFTY_INSTALL_DIR:-/Applications}"
OPEN_AFTER_INSTALL="${OPEN_AFTER_INSTALL:-0}"
QUIT_RUNNING_APP="${QUIT_RUNNING_APP:-1}"
CHECK_HELPER_DAEMON="${CHECK_HELPER_DAEMON:-1}"
HELPER_TARGET="${VIFTY_HELPER_TARGET:-/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon}"
WAS_RUNNING=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${ROOT_DIR}/.build/${APP_NAME}.app"
DEST_APP="${INSTALL_DIR}/${APP_NAME}.app"
ERR_LOG="$(mktemp -t vifty-install.XXXXXX)"
BUILD_LOG="$(mktemp -t vifty-install-build.XXXXXX)"
trap 'rm -f "${ERR_LOG}" "${BUILD_LOG}"' EXIT

fallback_to_user_applications() {
  INSTALL_DIR="${HOME}/Applications"
  DEST_APP="${INSTALL_DIR}/${APP_NAME}.app"
  mkdir -p "${INSTALL_DIR}"
}

copy_app_bundle() {
  local source_app="$1"
  local dest_app="$2"

  if [[ -e "${dest_app}" ]]; then
    rm -rf "${dest_app}"
  fi

  COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noqtn "${source_app}" "${dest_app}"
}

running_app_pids() {
  /usr/bin/pgrep -x "${APP_NAME}" 2>/dev/null || true
}

wait_for_app_exit() {
  local attempts="${1:-50}"
  while [[ "${attempts}" -gt 0 ]]; do
    if [[ -z "$(running_app_pids)" ]]; then
      return 0
    fi
    sleep 0.2
    attempts=$((attempts - 1))
  done
  return 1
}

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

shell_quote() {
  printf "'"
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

is_swiftpm_build_database_error() {
  /usr/bin/grep -Eiq "build\\.db|build database|disk I/O error|database is locked" "${BUILD_LOG}"
}

make_app_once() {
  local build_status
  set +e
  make app CONFIGURATION="${CONFIGURATION}" 2>&1 | tee "${BUILD_LOG}"
  build_status=${PIPESTATUS[0]}
  set -e
  return "${build_status}"
}

build_app_bundle() {
  local build_status
  if make_app_once; then
    return 0
  else
    build_status=$?
  fi

  if [[ -z "${SWIFT_BUILD_PATH:-}" ]] && is_swiftpm_build_database_error; then
    local fallback_build_path="${TMPDIR:-/tmp}/vifty-install-swiftpm-$$"
    echo "==> SwiftPM build database failed; retrying with SWIFT_BUILD_PATH=${fallback_build_path}"
    set +e
    SWIFT_BUILD_PATH="${fallback_build_path}" make app CONFIGURATION="${CONFIGURATION}" 2>&1 | tee "${BUILD_LOG}"
    build_status=${PIPESTATUS[0]}
    set -e
  fi

  return "${build_status}"
}

report_helper_daemon_status() {
  if [[ "${CHECK_HELPER_DAEMON}" != "1" ]]; then
    return 0
  fi

  local repair_command
  repair_command="REPAIR_HELPER_APP=$(shell_quote "${DEST_APP}") make repair-helper"

  local bundled_daemon="${DEST_APP}/Contents/MacOS/ViftyDaemon"
  if [[ ! -x "${bundled_daemon}" ]]; then
    echo "==> Could not check fan helper parity; bundled ViftyDaemon is missing."
    return 0
  fi

  if [[ ! -f "${HELPER_TARGET}" ]]; then
    echo "==> Fan helper is not installed yet."
    echo "    Open Vifty and choose Install Helper before manual fan control or current-build smoke evidence."
    return 0
  fi

  local bundled_sha
  local installed_sha
  bundled_sha="$(sha256_file "${bundled_daemon}")"
  installed_sha="$(sha256_file "${HELPER_TARGET}")"

  if [[ "${bundled_sha}" == "${installed_sha}" ]]; then
    echo "==> Fan helper matches the installed app daemon."
    return 0
  fi

  echo "==> Fan helper daemon differs from the installed app bundle."
  echo "    Bundled daemon:   ${bundled_sha}"
  echo "    Installed helper: ${installed_sha}"
  echo "    Open Vifty and choose Reinstall Helper or Repair Helper, or run: ${repair_command}"
  echo "    Do that before current-build manual/agent smoke evidence."
  echo "    Then rerun: AGENT_RUN_SMOKE_READINESS_JSON=1 make agent-run-smoke-readiness-current-build"
}

quit_running_app_if_needed() {
  if [[ "${QUIT_RUNNING_APP}" != "1" ]]; then
    return 0
  fi

  local pids
  pids="$(running_app_pids)"
  if [[ -z "${pids}" ]]; then
    return 0
  fi

  WAS_RUNNING=1
  echo "==> Quitting running ${APP_NAME} before install"
  /usr/bin/osascript -e 'tell application id "tech.reidar.vifty" to quit' >/dev/null 2>&1 \
    || /usr/bin/osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 \
    || true

  if ! wait_for_app_exit 50; then
    echo "==> ${APP_NAME} did not quit; terminating stale process"
    /usr/bin/pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
    wait_for_app_exit 25 || true
  fi
}

echo "==> Building ${APP_NAME}.app (${CONFIGURATION})"
cd "${ROOT_DIR}"
build_app_bundle

if [[ ! -d "${APP_DIR}" ]]; then
  echo "error: expected app bundle was not created: ${APP_DIR}" >&2
  exit 1
fi

if [[ ! -x "${APP_DIR}/Contents/MacOS/${APP_NAME}" ]]; then
  echo "error: app executable is missing or not executable: ${APP_DIR}/Contents/MacOS/${APP_NAME}" >&2
  exit 1
fi

if ! mkdir -p "${INSTALL_DIR}" 2>/dev/null; then
  echo "==> ${INSTALL_DIR} is not writable; installing to ~/Applications instead"
  fallback_to_user_applications
fi

quit_running_app_if_needed

echo "==> Installing to ${DEST_APP}"
if ! copy_app_bundle "${APP_DIR}" "${DEST_APP}" 2>"${ERR_LOG}"; then
  if [[ "${INSTALL_DIR}" == "/Applications" ]]; then
    echo "==> Could not write /Applications; installing to ~/Applications instead"
    fallback_to_user_applications
    copy_app_bundle "${APP_DIR}" "${DEST_APP}"
  else
    cat "${ERR_LOG}" >&2 || true
    exit 1
  fi
fi

# Strip removable local metadata/quarantine where macOS allows it.
/usr/bin/xattr -cr "${DEST_APP}" 2>/dev/null || true

echo "==> Verifying code signature"
/usr/bin/codesign --verify --deep --strict "${DEST_APP}"
report_helper_daemon_status

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -f "${DEST_APP}" >/dev/null 2>&1 || true
fi

echo ""
echo "Installed ${APP_NAME}:"
echo "  ${DEST_APP}"
echo ""
echo "Start it from Spotlight/Launchpad/Finder, or run:"
echo "  open \"${DEST_APP}\""

if [[ "${OPEN_AFTER_INSTALL}" == "1" || "${WAS_RUNNING}" == "1" ]]; then
  echo "==> Launching ${APP_NAME}"
  /usr/bin/open "${DEST_APP}"
fi
