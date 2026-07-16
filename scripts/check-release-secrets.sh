#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "${ROOT_DIR}"

REPO=""
ENVIRONMENT_NAME="release"
SECRET_LIST_FILE=""

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-secrets.sh [--repo owner/name] [--environment name] [--secret-list-file path]

Checks that the protected GitHub environment has the release secrets required
by docs/release.md. The script reads environment secret names only; it never
reads values. It proves name presence on that environment at check time, not
the absence of same-name repository/organization secrets or the storage scope
that supplied a prior workflow run.

Options:
  --repo owner/name          Repository to inspect. Defaults to gh's current repo.
  --environment name         GitHub environment to inspect. Defaults to release.
  --secret-list-file path    Read pre-captured `gh secret list --env` output for tests.
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
    --environment)
      if [ "$#" -lt 2 ]; then
        echo "error: --environment requires a value" >&2
        exit 64
      fi
      ENVIRONMENT_NAME="$2"
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
  if ! secret_names="$(gh secret list --env "${ENVIRONMENT_NAME}" --repo "${REPO}" 2>/dev/null | awk 'NF { print $1 }')"; then
    echo "error: could not list GitHub Actions secrets for environment ${ENVIRONMENT_NAME} in ${REPO}" >&2
    echo "The environment must exist and be readable; repository-scoped secrets do not satisfy this release gate." >&2
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
  echo "Configure the required secrets on the GitHub ${ENVIRONMENT_NAME} environment as documented in docs/release.md before rerunning the Release workflow." >&2
  exit 1
fi

if [ -n "${REPO}" ]; then
  echo "Release environment secrets OK for ${REPO}/${ENVIRONMENT_NAME}: ${#required_secrets[@]} required names are configured."
else
  echo "Release environment secrets OK for ${ENVIRONMENT_NAME}: ${#required_secrets[@]} required names are configured."
fi
echo "Scope note: this name-only preflight cannot prove that broader-scope duplicates are absent or attest the resolved secret origin inside a workflow run."
