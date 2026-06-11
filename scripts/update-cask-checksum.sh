#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/update-cask-checksum.sh --checksum-file <path> [options]

Update Casks/vifty.rb with the SHA-256 emitted by the release workflow.

Options:
  --checksum-file <path>  File created by shasum, usually Vifty-v<version>.zip.sha256.
  --version <version>     Require the cask version to match this value.
  -h, --help              Show this help.

The checksum file may contain either a bare lowercase SHA-256 or the normal
`shasum -a 256` output with an artifact path. When an artifact path is present,
its basename must be Vifty-v<cask-version>.zip so a checksum from another
release cannot be applied accidentally.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CASK_PATH="${ROOT_DIR}/Casks/vifty.rb"
CHECKSUM_FILE=""
EXPECTED_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --checksum-file)
      if [[ $# -lt 2 ]]; then
        echo "error: --checksum-file requires a path" >&2
        exit 64
      fi
      CHECKSUM_FILE="$2"
      shift 2
      ;;
    --version)
      if [[ $# -lt 2 ]]; then
        echo "error: --version requires a value" >&2
        exit 64
      fi
      EXPECTED_VERSION="$2"
      shift 2
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

if [[ -z "${CHECKSUM_FILE}" ]]; then
  echo "error: --checksum-file is required" >&2
  usage >&2
  exit 64
fi

if [[ ! -f "${CHECKSUM_FILE}" ]]; then
  echo "error: checksum file not found: ${CHECKSUM_FILE}" >&2
  exit 66
fi

if [[ ! -f "${CASK_PATH}" ]]; then
  echo "error: cask not found: ${CASK_PATH}" >&2
  exit 66
fi

cask_version="$(ruby -ne 'puts $1 if /^\s*version "([^"]+)"/' "${CASK_PATH}")"
if [[ -z "${cask_version}" ]]; then
  echo "error: could not read version from ${CASK_PATH}" >&2
  exit 1
fi

if [[ -n "${EXPECTED_VERSION}" && "${EXPECTED_VERSION}" != "${cask_version}" ]]; then
  echo "error: expected version ${EXPECTED_VERSION} does not match cask version ${cask_version}" >&2
  exit 1
fi

checksum_line="$(awk 'NF {print; exit}' "${CHECKSUM_FILE}")"
read -r checksum artifact_path _ <<< "${checksum_line}"

if [[ ! "${checksum}" =~ ^[0-9a-f]{64}$ ]]; then
  echo "error: checksum file must start with a lowercase 64-character SHA-256 checksum" >&2
  exit 1
fi

if [[ -n "${artifact_path:-}" ]]; then
  artifact_name="$(basename "${artifact_path}")"
  expected_artifact_name="Vifty-v${cask_version}.zip"
  if [[ "${artifact_name}" != "${expected_artifact_name}" ]]; then
    echo "error: checksum artifact ${artifact_name} does not match ${expected_artifact_name}" >&2
    exit 1
  fi
fi

VIFTY_RELEASE_METADATA_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/validate-release-metadata.sh" >/dev/null

ruby -e '
  path, checksum = ARGV
  text = File.read(path)
  matches = text.scan(/^\s*sha256 "[^"]+"/)
  unless matches.length == 1
    warn "error: expected exactly one sha256 stanza in #{path}, found #{matches.length}"
    exit 1
  end
  updated = text.sub(/^(\s*sha256 )"[^"]+"/) { "#{$1}\"#{checksum}\"" }
  File.write(path, updated)
' "${CASK_PATH}" "${checksum}"

VIFTY_RELEASE_METADATA_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/validate-release-metadata.sh" >/dev/null

echo "Updated ${CASK_PATH} to sha256 ${checksum} for Vifty ${cask_version}"
