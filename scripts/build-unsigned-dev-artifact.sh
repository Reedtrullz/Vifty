#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "${ROOT_DIR}"

VERSION=""
OUTPUT_DIR=".build"
SKIP_BUILD=false
SOURCE_SHA=""
REQUIRE_SOURCE_REF=""

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/build-unsigned-dev-artifact.sh [--version version] [--output-dir dir] [--skip-build] [--source-sha sha] [--require-source-ref ref-or-sha]

Builds an ad-hoc-signed Vifty.app convenience zip for source-first tester
releases. The artifact is intentionally named
Vifty-v<version>-unsigned-dev.zip so it cannot be confused with the future
Developer ID signed and notarized Vifty-v<version>.zip artifact.

Use --require-source-ref when building a release attachment so a zip named for
v<version> cannot be accidentally built from later post-release source.

The generated app is not Developer ID signed, not notarized, and not an
official trusted binary. macOS may show Gatekeeper warnings.
USAGE
}

is_sha() {
  [[ "$1" =~ ^[0-9a-fA-F]{7,40}$ ]]
}

lowercase() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

source_first_sparkle_keys() {
  /usr/bin/plutil -convert json -o - -- "$1" | ruby -rjson -e '
    data = JSON.parse(STDIN.read)
    keys = data.keys.grep(/\ASU/).sort
    puts keys.join(", ") unless keys.empty?
  '
}

validate_unsigned_app_plist() {
  local plist_path="$1"
  if [ ! -f "${plist_path}" ]; then
    echo "error: unsigned-dev app bundle is missing ${plist_path}" >&2
    exit 1
  fi

  local sparkle_keys
  sparkle_keys="$(source_first_sparkle_keys "${plist_path}")"
  if [ -n "${sparkle_keys}" ]; then
    echo "error: unsigned-dev app bundle must not include Sparkle updater metadata: ${sparkle_keys}" >&2
    exit 1
  fi
}

resolve_ref() {
  local ref="$1"
  if is_sha "${ref}"; then
    printf '%s' "${ref}"
    return 0
  fi
  git rev-parse "${ref}^{commit}" 2>/dev/null
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
    --source-sha)
      if [ "$#" -lt 2 ]; then
        echo "error: --source-sha requires a value" >&2
        exit 64
      fi
      SOURCE_SHA="$2"
      shift 2
      ;;
    --require-source-ref)
      if [ "$#" -lt 2 ]; then
        echo "error: --require-source-ref requires a value" >&2
        exit 64
      fi
      REQUIRE_SOURCE_REF="$2"
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

if [ -n "${SOURCE_SHA}" ] && ! is_sha "${SOURCE_SHA}"; then
  echo "error: --source-sha must be a 7-40 character hexadecimal commit SHA" >&2
  exit 64
fi

if [ -n "${REQUIRE_SOURCE_REF}" ]; then
  if [ -z "${SOURCE_SHA}" ]; then
    if ! SOURCE_SHA="$(git rev-parse HEAD 2>/dev/null)"; then
      echo "error: --require-source-ref needs a Git checkout or explicit --source-sha" >&2
      exit 1
    fi
  fi

  if ! REQUIRED_SOURCE_SHA="$(resolve_ref "${REQUIRE_SOURCE_REF}")"; then
    echo "error: could not resolve required source ref ${REQUIRE_SOURCE_REF}; run git fetch origin --tags before building a release attachment, or pass an explicit commit SHA to --require-source-ref" >&2
    exit 1
  fi

  if [ "$(lowercase "${SOURCE_SHA}")" != "$(lowercase "${REQUIRED_SOURCE_SHA}")" ]; then
    echo "error: refusing to build Vifty-v${VERSION}-unsigned-dev.zip from source ${SOURCE_SHA}; required source ref ${REQUIRE_SOURCE_REF} resolves to ${REQUIRED_SOURCE_SHA}" >&2
    exit 1
  fi

  echo "Source provenance OK: ${SOURCE_SHA} matches ${REQUIRE_SOURCE_REF}."
fi

mkdir -p "${OUTPUT_DIR}"

ZIP_PATH="${OUTPUT_DIR}/Vifty-v${VERSION}-unsigned-dev.zip"
CHECKSUM_PATH="${ZIP_PATH}.sha256"
CANONICAL_ZIP="${OUTPUT_DIR}/Vifty-v${VERSION}.zip"

if [ "${ZIP_PATH}" = "${CANONICAL_ZIP}" ]; then
  echo "error: unsigned-dev artifact must not use canonical notarized artifact name ${CANONICAL_ZIP}" >&2
  exit 1
fi

"${SCRIPT_DIR}/validate-release-metadata.sh" --mode source-first

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

validate_unsigned_app_plist ".build/Vifty.app/Contents/Info.plist"

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
