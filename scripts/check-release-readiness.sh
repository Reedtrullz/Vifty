#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "${ROOT_DIR}"

RELEASE_READINESS_SCHEMA_ID="https://vifty.local/schemas/release-readiness.schema.json"
REPO=""
VERSION=""
SECRET_LIST_FILE=""
RELEASE_VIEW_FILE=""
JSON_OUTPUT=false

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-readiness.sh [--version version] [--repo owner/name] [--secret-list-file path] [--release-view-file path] [--json]

Runs a read-only release trust preflight. The script validates local release
metadata, checks required GitHub Actions release secret names, and verifies that
the GitHub Release has the required public trust assets.

Options:
  --version version          Release version to check. Defaults to Info.plist.
  --repo owner/name          Repository to inspect. Defaults to gh's current repo.
  --secret-list-file path    Read pre-captured `gh secret list` output for tests.
  --release-view-file path   Read pre-captured `gh release view --json ...` output.
  --json                     Print a machine-readable summary instead of text.
  -h, --help                 Show this help.
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
    --repo)
      if [ "$#" -lt 2 ]; then
        echo "error: --repo requires a value" >&2
        exit 64
      fi
      REPO="$2"
      shift 2
      ;;
    --secret-list-file)
      if [ "$#" -lt 2 ]; then
        echo "error: --secret-list-file requires a value" >&2
        exit 64
      fi
      SECRET_LIST_FILE="$2"
      shift 2
      ;;
    --release-view-file)
      if [ "$#" -lt 2 ]; then
        echo "error: --release-view-file requires a value" >&2
        exit 64
      fi
      RELEASE_VIEW_FILE="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
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

if [[ ! "${VERSION}" =~ ^[0-9]+([.][0-9]+){1,2}([-.][0-9A-Za-z]+)?$ ]]; then
  echo "error: release version must be a SemVer-like value" >&2
  exit 64
fi

TAG="v${VERSION}"

check_names=()
check_statuses=()
check_messages=()
blockers=()

add_check() {
  local name="$1"
  local status="$2"
  local message="$3"
  check_names+=("${name}")
  check_statuses+=("${status}")
  check_messages+=("${message}")
  if [ "${status}" != "passed" ]; then
    blockers+=("${name}")
  fi
}

json_string() {
  ruby -rjson -e 'print ARGV.fetch(0).to_json' "$1"
}

emit_json() {
  local status="ready"
  local known_readiness_blockers_clear="true"
  if [ "${#blockers[@]}" -gt 0 ]; then
    status="blocked"
    known_readiness_blockers_clear="false"
  fi

  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "schemaID": %s,\n' "$(json_string "${RELEASE_READINESS_SCHEMA_ID}")"
  printf '  "version": %s,\n' "$(json_string "${VERSION}")"
  printf '  "tag": %s,\n' "$(json_string "${TAG}")"
  printf '  "status": %s,\n' "$(json_string "${status}")"
  printf '  "knownReadinessBlockersClear": %s,\n' "${known_readiness_blockers_clear}"
  printf '  "checks": [\n'
  for index in "${!check_names[@]}"; do
    printf '    {"name": %s, "status": %s, "message": %s}' \
      "$(json_string "${check_names[$index]}")" \
      "$(json_string "${check_statuses[$index]}")" \
      "$(json_string "${check_messages[$index]}")"
    if [ "${index}" -lt "$((${#check_names[@]} - 1))" ]; then
      printf ','
    fi
    printf '\n'
  done
  printf '  ],\n'
  printf '  "blockers": ['
  for index in "${!blockers[@]}"; do
    printf '%s' "$(json_string "${blockers[$index]}")"
    if [ "${index}" -lt "$((${#blockers[@]} - 1))" ]; then
      printf ', '
    fi
  done
  printf ']\n'
  printf '}\n'
}

emit_text() {
  local status="ready"
  if [ "${#blockers[@]}" -gt 0 ]; then
    status="blocked"
  fi

  echo "Release readiness for ${TAG}: ${status}"
  for index in "${!check_names[@]}"; do
    printf '[%s] %s - %s\n' "${check_statuses[$index]}" "${check_names[$index]}" "${check_messages[$index]}"
  done

  if [ "${status}" = "blocked" ]; then
    echo "Do not describe ${TAG} as a trusted public binary release until the blockers are cleared."
  else
    echo "${TAG} has no known release-readiness blockers from this preflight."
  fi
}

if metadata_output="$(VIFTY_RELEASE_METADATA_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/validate-release-metadata.sh" 2>&1)"; then
  add_check "release-metadata" "passed" "${metadata_output}"
else
  add_check "release-metadata" "blocked" "${metadata_output}"
fi

secret_args=()
if [ -n "${REPO}" ]; then
  secret_args+=(--repo "${REPO}")
fi
if [ -n "${SECRET_LIST_FILE}" ]; then
  secret_args+=(--secret-list-file "${SECRET_LIST_FILE}")
fi

if secret_output="$(VIFTY_RELEASE_METADATA_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/check-release-secrets.sh" "${secret_args[@]}" 2>&1)"; then
  add_check "release-secrets" "passed" "${secret_output}"
else
  add_check "release-secrets" "blocked" "${secret_output}"
fi

release_json=""
release_output=""
if [ -n "${RELEASE_VIEW_FILE}" ]; then
  if [ ! -f "${RELEASE_VIEW_FILE}" ]; then
    release_output="release view file does not exist: ${RELEASE_VIEW_FILE}"
  else
    release_json="$(cat "${RELEASE_VIEW_FILE}")"
  fi
else
  if command -v gh >/dev/null 2>&1; then
    release_args=("${TAG}" --json tagName,isDraft,isPrerelease,assets)
    if [ -n "${REPO}" ]; then
      release_args+=(--repo "${REPO}")
    fi
    if ! release_json="$(gh release view "${release_args[@]}" 2>&1)"; then
      release_output="${release_json}"
      release_json=""
    fi
  else
    release_output="gh CLI is required unless --release-view-file is supplied"
  fi
fi

if [ -z "${release_json}" ]; then
  add_check "github-release" "blocked" "GitHub Release ${TAG} is not available: ${release_output}"
else
  if release_output="$(ruby -rjson -e '
    version = ARGV.fetch(0)
    tag = "v#{version}"
    data = JSON.parse(STDIN.read)
    required = [
      "Vifty-v#{version}.zip",
      "Vifty-v#{version}.zip.sha256",
      "Vifty-v#{version}-artifact-summary.json",
      "Vifty-v#{version}-release-checklist.md"
    ]
    assets = Array(data["assets"]).map { |asset| asset["name"].to_s }
    problems = []
    problems << "tagName #{data["tagName"].inspect} does not match #{tag}" if data["tagName"] != tag
    problems << "release is draft" if data["isDraft"]
    problems << "release is marked prerelease" if data["isPrerelease"]
    missing = required - assets
    problems << "missing assets: #{missing.join(", ")}" unless missing.empty?
    if problems.empty?
      puts "GitHub Release #{tag} has required public trust assets: #{required.join(", ")}"
    else
      warn "GitHub Release #{tag} is not trust-complete: #{problems.join("; ")}"
      exit 1
    end
  ' "${VERSION}" <<< "${release_json}" 2>&1)"; then
    add_check "github-release" "passed" "${release_output}"
  else
    add_check "github-release" "blocked" "${release_output}"
  fi
fi

if "${JSON_OUTPUT}"; then
  emit_json
else
  emit_text
fi

if [ "${#blockers[@]}" -gt 0 ]; then
  exit 1
fi
