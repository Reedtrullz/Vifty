#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Vifty"
CONFIGURATION="${CONFIGURATION:-release}"
INSTALL_DIR="${VIFTY_INSTALL_DIR:-/Applications}"
OPEN_AFTER_INSTALL="${OPEN_AFTER_INSTALL:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${ROOT_DIR}/.build/${APP_NAME}.app"
DEST_APP="${INSTALL_DIR}/${APP_NAME}.app"
ERR_LOG="$(mktemp -t vifty-install.XXXXXX)"
trap 'rm -f "${ERR_LOG}"' EXIT

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

echo "==> Building ${APP_NAME}.app (${CONFIGURATION})"
cd "${ROOT_DIR}"
make app CONFIGURATION="${CONFIGURATION}"

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

if [[ "${OPEN_AFTER_INSTALL}" == "1" ]]; then
  echo "==> Launching ${APP_NAME}"
  /usr/bin/open "${DEST_APP}"
fi
