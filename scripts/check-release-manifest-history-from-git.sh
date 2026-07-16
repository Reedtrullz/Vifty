#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_MANIFEST_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
SOURCE_REPOSITORY="${VIFTY_RELEASE_SOURCE_REPOSITORY_ROOT:-${ROOT_DIR}}"
CURRENT_MANIFEST="${ROOT_DIR}/.github/release-manifest.json"
BASE_REF=""

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-manifest-history-from-git.sh --base-ref <trusted-git-object>

Materializes the continuity checker and any prior release manifest from the
trusted base Git object before enforcing append-only release history. A missing
base manifest is accepted only when that already-trusted checker recognizes the
exact pinned v1.3.2 introduction boundary.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-ref)
      [[ $# -ge 2 ]] || { echo "error: --base-ref requires a value" >&2; exit 64; }
      BASE_REF="$2"
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

[[ -n "${BASE_REF}" ]] || { echo "error: --base-ref is required" >&2; exit 64; }
[[ -f "${CURRENT_MANIFEST}" ]] || { echo "error: current release manifest not found: ${CURRENT_MANIFEST}" >&2; exit 66; }

if ! BASE_COMMIT="$(git -C "${SOURCE_REPOSITORY}" rev-parse --verify "${BASE_REF}^{commit}" 2>/dev/null)"; then
  echo "error: trusted release-manifest base ref is unavailable: ${BASE_REF}" >&2
  exit 65
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/vifty-release-manifest-history.XXXXXX")"
cleanup() {
  rm -rf "${scratch}"
}
trap cleanup EXIT

base_manifest="${scratch}/base-release-manifest.json"
trusted_checker="${scratch}/check-release-manifest-history.rb"

if ! git -C "${SOURCE_REPOSITORY}" show "${BASE_COMMIT}:scripts/check-release-manifest-history.rb" > "${trusted_checker}" 2>/dev/null; then
  echo "error: trusted base ${BASE_COMMIT} has no release-manifest continuity checker; land the pinned checker before introducing the manifest" >&2
  exit 65
fi

if git -C "${SOURCE_REPOSITORY}" cat-file -e "${BASE_COMMIT}:.github/release-manifest.json" 2>/dev/null; then
  if ! git -C "${SOURCE_REPOSITORY}" show "${BASE_COMMIT}:.github/release-manifest.json" > "${base_manifest}"; then
    echo "error: could not materialize trusted base release manifest from ${BASE_COMMIT}" >&2
    exit 65
  fi
  ruby "${trusted_checker}" --current "${CURRENT_MANIFEST}" --base "${base_manifest}"
else
  ruby "${trusted_checker}" \
    --current "${CURRENT_MANIFEST}" \
    --allow-initial-v1.3.2
fi
