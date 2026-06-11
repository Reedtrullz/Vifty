#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "${ROOT_DIR}"

REPO=""
SECRET_LIST_FILE=""

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-secrets.sh [--repo owner/name] [--secret-list-file path]

Checks that the GitHub repository has the release secrets required by
docs/release.md. The script reads secret names only; it never reads values.

Options:
  --repo owner/name          Repository to inspect. Defaults to gh's current repo.
  --secret-list-file path    Read pre-captured `gh secret list` output for tests.
  -h, --help                 Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
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

required_secrets=(
  "APPLE_TEAM_ID"
  "APPLE_ID"
  "APPLE_APP_SPECIFIC_PASSWORD"
  "DEVELOPER_ID_APPLICATION_IDENTITY"
  "DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64"
  "DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD"
)

if [ -n "${SECRET_LIST_FILE}" ]; then
  if [ ! -f "${SECRET_LIST_FILE}" ]; then
    echo "error: secret list file does not exist: ${SECRET_LIST_FILE}" >&2
    exit 66
  fi
  secret_names="$(awk 'NF { print $1 }' "${SECRET_LIST_FILE}")"
else
  if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh CLI is required unless --secret-list-file is supplied" >&2
    exit 69
  fi
  if [ -z "${REPO}" ]; then
    if ! REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"; then
      echo "error: could not determine GitHub repository; pass --repo owner/name" >&2
      exit 69
    fi
  fi
  if ! secret_names="$(gh secret list --repo "${REPO}" 2>/dev/null | awk 'NF { print $1 }')"; then
    echo "error: could not list GitHub Actions secrets for ${REPO}" >&2
    exit 69
  fi
fi

missing=()
for name in "${required_secrets[@]}"; do
  if ! printf '%s\n' "${secret_names}" | grep -Fxq "${name}"; then
    missing+=("${name}")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  for name in "${missing[@]}"; do
    echo "Missing required release secret: ${name}" >&2
  done
  echo "Configure the required repository secrets in docs/release.md before rerunning the Release workflow." >&2
  exit 1
fi

if [ -n "${REPO}" ]; then
  echo "Release secrets OK for ${REPO}: ${#required_secrets[@]} required names are configured."
else
  echo "Release secrets OK: ${#required_secrets[@]} required names are configured."
fi
