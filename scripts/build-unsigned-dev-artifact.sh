#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "${ROOT_DIR}"

VERSION=""
OUTPUT_DIR=".build"
SKIP_BUILD=false

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/build-unsigned-dev-artifact.sh [--version version] [--output-dir dir] [--skip-build]

Builds an ad-hoc-signed Vifty.app convenience zip for source-first tester
releases. The artifact is intentionally named
Vifty-v<version>-unsigned-dev.zip so it cannot be confused with the future
Developer ID signed and notarized Vifty-v<version>.zip artifact.

The generated app is not Developer ID signed, not notarized, and not an
official trusted binary. macOS may show Gatekeeper warnings.
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
    --output-dir)
      if [ "$#" -lt 2 ]; then
        echo "error: --output-dir requires a value" >&2
        exit 64
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
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

mkdir -p "${OUTPUT_DIR}"

ZIP_PATH="${OUTPUT_DIR}/Vifty-v${VERSION}-unsigned-dev.zip"
CHECKSUM_PATH="${ZIP_PATH}.sha256"
CANONICAL_ZIP="${OUTPUT_DIR}/Vifty-v${VERSION}.zip"

if [ "${ZIP_PATH}" = "${CANONICAL_ZIP}" ]; then
  echo "error: unsigned-dev artifact must not use canonical notarized artifact name ${CANONICAL_ZIP}" >&2
  exit 1
fi

if ! "${SKIP_BUILD}"; then
  /Applications/Xcode.app/Contents/Developer/usr/bin/make app \
    CONFIGURATION=release \
    SIGNING_IDENTITY="-" \
    VIFTY_XPC_ALLOWED_TEAM_ID=""
fi

if [ ! -d ".build/Vifty.app" ]; then
  echo "error: .build/Vifty.app does not exist; run without --skip-build or build the app first" >&2
  exit 1
fi

rm -f "${ZIP_PATH}" "${CHECKSUM_PATH}"
ditto -c -k --keepParent ".build/Vifty.app" "${ZIP_PATH}"
shasum -a 256 "${ZIP_PATH}" | tee "${CHECKSUM_PATH}"

cat <<EOF
Built unsigned tester artifact:
  ${ZIP_PATH}
  ${CHECKSUM_PATH}

Warning: this app is ad-hoc signed, not Developer ID signed, and not notarized.
For the most trusted v${VERSION} path, build from source.
EOF
