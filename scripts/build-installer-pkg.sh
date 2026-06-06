#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Vifty"
PKG_IDENTIFIER="tech.reidar.vifty.pkg"
CONFIGURATION="${CONFIGURATION:-release}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${ROOT_DIR}/.build/${APP_NAME}.app"
PKG_ROOT="${ROOT_DIR}/.build/pkg-root"

cd "${ROOT_DIR}"

echo "==> Building ${APP_NAME}.app (${CONFIGURATION})"
make app CONFIGURATION="${CONFIGURATION}"

if [[ ! -d "${APP_DIR}" ]]; then
  echo "error: expected app bundle was not created: ${APP_DIR}" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_DIR}/Contents/Info.plist")"
PKG_OUT="${PKG_OUT:-${ROOT_DIR}/.build/${APP_NAME}-${VERSION}.pkg}"

echo "==> Preparing package root"
rm -rf "${PKG_ROOT}"
mkdir -p "${PKG_ROOT}/Applications"
COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc --noextattr --noqtn "${APP_DIR}" "${PKG_ROOT}/Applications/${APP_NAME}.app"
/usr/bin/xattr -cr "${PKG_ROOT}" 2>/dev/null || true

# Build an unsigned local installer package. The app itself is ad-hoc signed by
# `make app`; this package is meant for Reidar's local machines/dev workflow.
echo "==> Building installer package"
COPYFILE_DISABLE=1 /usr/bin/pkgbuild \
  --root "${PKG_ROOT}" \
  --identifier "${PKG_IDENTIFIER}" \
  --version "${VERSION}" \
  --install-location "/" \
  "${PKG_OUT}"

echo ""
echo "Built installer package:"
echo "  ${PKG_OUT}"
echo ""
echo "Install with Finder, or from Terminal:"
echo "  open \"${PKG_OUT}\""
