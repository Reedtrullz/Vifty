#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/update-cask-checksum.sh --checksum-file <path> [options]

Update Casks/vifty.rb with the SHA-256 emitted by the release workflow.

Options:
  --checksum-file <path>  File created by shasum, usually Vifty-v<version>.zip.sha256.
  --version <version>     Require the promoted published manifest to match this
                          target version. The cask version and checksum are then
                          advanced together.
  -h, --help              Show this help.

The checksum file may contain either a bare lowercase SHA-256 or the normal
`shasum -a 256` output with an artifact path. When an artifact path is present,
its basename must be Vifty-v<target-version>.zip so a checksum from another
release cannot be applied accidentally.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CASK_PATH="${ROOT_DIR}/Casks/vifty.rb"
RELEASE_MANIFEST_PATH="${ROOT_DIR}/.github/release-manifest.json"
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

VIFTY_RELEASE_MANIFEST_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/check-release-manifest.sh" --manifest-only >/dev/null
manifest_release="$(ruby -rjson -e '
  release = JSON.parse(File.read(ARGV.fetch(0))).fetch("publishedRelease")
  puts [release.fetch("version"), release.fetch("sha256")].join("\t")
' "${RELEASE_MANIFEST_PATH}")"
IFS=$'\t' read -r manifest_version manifest_sha <<< "${manifest_release}"
target_version="${EXPECTED_VERSION:-${manifest_version}}"

if [[ "${target_version}" != "${manifest_version}" ]]; then
  echo "error: target version ${target_version} does not match published manifest version ${manifest_version}" >&2
  exit 1
fi

if ! ruby -e '
  current, target = ARGV
  parse = ->(value) { value.match?(/\A\d+\.\d+\.\d+\z/) ? value.split(".").map(&:to_i) : nil }
  current_parts = parse.call(current)
  target_parts = parse.call(target)
  exit(current_parts && target_parts && (current_parts <=> target_parts) <= 0 ? 0 : 1)
' "${cask_version}" "${target_version}"; then
  echo "error: cask version ${cask_version} must be valid and no newer than target ${target_version}" >&2
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
  expected_artifact_name="Vifty-v${target_version}.zip"
  if [[ "${artifact_name}" != "${expected_artifact_name}" ]]; then
    echo "error: checksum artifact ${artifact_name} does not match ${expected_artifact_name}" >&2
    exit 1
  fi
fi

if [[ "${checksum}" != "${manifest_sha}" ]]; then
  echo "error: checksum ${checksum} does not match published manifest checksum ${manifest_sha}" >&2
  exit 1
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/vifty-cask-handoff.XXXXXX")"
cp "${CASK_PATH}" "${scratch}/vifty.rb"
cask_directory="$(cd "$(dirname "${CASK_PATH}")" && pwd)"
cask_basename="$(basename "${CASK_PATH}")"
candidate_cask="$(mktemp "${cask_directory}/.${cask_basename}.candidate.XXXXXX")"
cask_mode="$(stat -f '%Lp' "${CASK_PATH}")"
handoff_complete=0
live_replaced=0
cleanup() {
  local exit_code=$?
  rm -f "${candidate_cask}"
  if [[ "${handoff_complete}" != "1" && "${live_replaced}" == "1" && -f "${scratch}/vifty.rb" ]]; then
    local restore_cask
    restore_cask="$(mktemp "${cask_directory}/.${cask_basename}.restore.XXXXXX")"
    cp "${scratch}/vifty.rb" "${restore_cask}"
    chmod "${cask_mode}" "${restore_cask}"
    mv -f "${restore_cask}" "${CASK_PATH}"
  fi
  rm -rf "${scratch}"
  trap - EXIT
  exit "${exit_code}"
}
trap cleanup EXIT

ruby -e '
  path, version, checksum = ARGV
  source_path = ARGV.fetch(3)
  text = File.read(source_path)
  version_matches = text.scan(/^\s*version "[^"]+"/)
  matches = text.scan(/^\s*sha256 "[^"]+"/)
  unless version_matches.length == 1
    warn "error: expected exactly one version stanza in #{path}, found #{version_matches.length}"
    exit 1
  end
  unless matches.length == 1
    warn "error: expected exactly one sha256 stanza in #{path}, found #{matches.length}"
    exit 1
  end
  updated = text.sub(/^(\s*version )"[^"]+"/) { "#{$1}\"#{version}\"" }
  updated = updated.sub(/^(\s*sha256 )"[^"]+"/) { "#{$1}\"#{checksum}\"" }
  File.open(path, "w") do |file|
    file.write(updated)
    file.flush
    file.fsync
  end
' "${candidate_cask}" "${target_version}" "${checksum}" "${CASK_PATH}"
chmod "${cask_mode}" "${candidate_cask}"

if ! validation_error="$(VIFTY_RELEASE_METADATA_ROOT="${ROOT_DIR}" VIFTY_RELEASE_CASK_PATH="${candidate_cask}" "${SCRIPT_DIR}/validate-release-metadata.sh" 2>&1 >/dev/null)"; then
  echo "${validation_error}" >&2
  echo "error: candidate cask metadata handoff failed validation; live cask was not changed" >&2
  exit 1
fi

mv -f "${candidate_cask}" "${CASK_PATH}"
live_replaced=1

if ! validation_error="$(VIFTY_RELEASE_METADATA_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/validate-release-metadata.sh" 2>&1 >/dev/null)"; then
  echo "${validation_error}" >&2
  echo "error: final cask metadata validation failed; restoring the original cask atomically" >&2
  exit 1
fi

handoff_complete=1
echo "Updated ${CASK_PATH} from Vifty ${cask_version} to ${target_version} with sha256 ${checksum}"
