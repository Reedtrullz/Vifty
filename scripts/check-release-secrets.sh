#!/bin/bash -p
if [[ "$0" != "vifty-release-clean" ]]; then
  release_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [[ "${release_token}" == *[[:space:]]* ]]; then
    echo "error: GitHub token must not contain whitespace" >&2
    exit 69
  fi
  exec 9<<<"${release_token}"
  unset release_token GH_TOKEN GITHUB_TOKEN
  exec /usr/bin/env -i \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    HOME="${HOME:-}" TMPDIR="${TMPDIR:-/tmp}" USER="${USER:-}" LOGNAME="${LOGNAME:-}" \
    SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-}" VIFTY_GH_TOKEN_FD=9 \
    GH_HOST="${GH_HOST:-}" \
    GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}" GITHUB_SHA="${GITHUB_SHA:-}" \
    GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-}" RUNNER_TEMP="${RUNNER_TEMP:-}" \
    VIFTY_RELEASE_TAG_ROOT="${VIFTY_RELEASE_TAG_ROOT:-}" \
    VIFTY_RELEASE_METADATA_ROOT="${VIFTY_RELEASE_METADATA_ROOT:-}" \
    VIFTY_RELEASE_PINNED_GH="${VIFTY_RELEASE_PINNED_GH:-}" \
    VIFTY_GH_ARGUMENTS_FILE="${VIFTY_GH_ARGUMENTS_FILE:-}" \
    /bin/bash -p -c 'source "$1" "${@:2}"' vifty-release-clean "$0" "$@"
fi
set -euo pipefail

INHERITED_GH_TOKEN=""
if [[ "${VIFTY_GH_TOKEN_FD:-}" == "9" ]]; then
  IFS= read -r INHERITED_GH_TOKEN <&9 || true
  exec 9<&-
fi
unset VIFTY_GH_TOKEN_FD GH_TOKEN GITHUB_TOKEN

inherited_functions="$(builtin declare -F)"
if [[ -n "${inherited_functions}" ]]; then
  builtin printf '%s\n' "error: inherited shell functions are not allowed" >&2
  exit 69
fi

for hostile_name in \
  BASH_ENV ENV RUBYOPT RUBYLIB \
  http_proxy https_proxy all_proxy no_proxy \
  HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY \
  CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR \
  GH_CONFIG_DIR XDG_CONFIG_HOME GH_PATH GH_FORCE_TTY GITHUB_API_URL; do
  if [[ -n "${!hostile_name:-}" ]]; then
    echo "error: hostile interpreter environment is not allowed: ${hostile_name}" >&2
    exit 69
  fi
done

assert_safe_gh_config() {
  local unix_socket token
  unix_socket="$("${GH_BIN}" config get http_unix_socket --host github.com 2>/dev/null || true)"
  if [[ -n "${unix_socket}" ]]; then
    echo "error: GitHub CLI http_unix_socket must be empty for github.com" >&2
    exit 69
  fi
  token="${INHERITED_GH_TOKEN:-}"
  if [[ -z "${token}" ]]; then
    token="$("${GH_BIN}" auth token --hostname github.com 2>/dev/null || true)"
  fi
  if [[ -z "${token}" || "${token}" == *[[:space:]]* ||
        ! -d /var/empty || -w /var/empty ]]; then
    echo "error: an authenticated github.com token and trusted empty gh config root are required" >&2
    exit 69
  fi
  SAFE_GH_TOKEN="${token}"
  unset GH_TOKEN GITHUB_TOKEN
}

safe_gh() {
  GH_CONFIG_DIR=/var/empty \
    GH_TOKEN="${SAFE_GH_TOKEN}" \
    GH_HOST=github.com \
    GH_NO_UPDATE_NOTIFIER=1 \
    GH_NO_EXTENSION_UPDATE_NOTIFIER=1 \
    "${GH_BIN}" "$@"
}
unset BASH_ENV ENV RUBYOPT RUBYLIB CDPATH

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
export PATH
GH_BIN=""
for gh_candidate in /opt/homebrew/bin/gh /usr/local/bin/gh /usr/bin/gh; do
  if [[ -x "${gh_candidate}" ]]; then
    GH_BIN="${gh_candidate}"
    break
  fi
done

ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "${ROOT_DIR}"
GH_TOOLCHAIN_VERIFIER_PATH="${ROOT_DIR}/scripts/verify-release-gh-toolchain.rb"
GH_TOOLCHAIN_POLICY_PATH="${ROOT_DIR}/.github/release-gh-toolchain.json"

REPO=""
ENVIRONMENT_NAME="release"
SECRET_LIST_FILE=""
ENVIRONMENT_SECRET_LIST_FILE=""
TOOLCHAIN_SCRATCH=""

cleanup_release_secret_check() {
  [[ -z "${TOOLCHAIN_SCRATCH}" ]] || /bin/rm -rf "${TOOLCHAIN_SCRATCH}"
}
trap cleanup_release_secret_check EXIT

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-secrets.sh [--repo owner/name] [--environment name] [--secret-list-file path] [--environment-secret-list-file path]

Checks that the GitHub repository has the release secrets required by
docs/release.md. The script reads repository Actions secret names only; it
never reads values. The release workflow separately constrains every secret
reference to the protected sign-notarize job. It also rejects same-name
secrets on the release environment because those would shadow repository
values inside an environment-bound job.

Options:
  --repo owner/name          Repository to inspect. Defaults to gh's current repo.
  --environment name         Environment checked for shadowing. Defaults to release.
  --secret-list-file path    Read pre-captured `gh secret list` output for tests.
  --environment-secret-list-file path
                             Read pre-captured environment secret names for tests.
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
    --environment-secret-list-file)
      if [ "$#" -lt 2 ]; then
        echo "error: --environment-secret-list-file requires a value" >&2
        exit 64
      fi
      ENVIRONMENT_SECRET_LIST_FILE="$2"
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

if [ -n "${SECRET_LIST_FILE}" ] && [ -z "${ENVIRONMENT_SECRET_LIST_FILE}" ]; then
  echo "error: --secret-list-file requires --environment-secret-list-file; pass an explicit empty file when the environment has no secrets" >&2
  exit 64
fi
if [ -z "${SECRET_LIST_FILE}" ] && [ -n "${ENVIRONMENT_SECRET_LIST_FILE}" ]; then
  echo "error: --environment-secret-list-file requires --secret-list-file; fixture arguments must be supplied together" >&2
  exit 64
fi

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
  secret_names="$(/usr/bin/awk 'NF { print $1 }' "${SECRET_LIST_FILE}")"
  if [ ! -f "${ENVIRONMENT_SECRET_LIST_FILE}" ]; then
    echo "error: environment secret list file does not exist: ${ENVIRONMENT_SECRET_LIST_FILE}" >&2
    exit 66
  fi
  environment_secret_names="$(/usr/bin/awk 'NF { print $1 }' "${ENVIRONMENT_SECRET_LIST_FILE}")"
else
  if [ -n "${GH_HOST:-}" ] && [ "${GH_HOST}" != "github.com" ]; then
    echo "error: live release-secret evidence requires github.com, not GH_HOST=${GH_HOST}" >&2
    exit 69
  fi
  [[ -z "${VIFTY_RELEASE_PINNED_GH:-}" ]] || GH_BIN="${VIFTY_RELEASE_PINNED_GH}"
  if [[ -z "${GH_BIN}" ]]; then
    echo "error: gh CLI is required unless --secret-list-file is supplied" >&2
    exit 69
  fi
  unverified_gh_bin="${GH_BIN}"
  TOOLCHAIN_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/vifty-release-secrets-gh.XXXXXX")"
  /bin/chmod 700 "${TOOLCHAIN_SCRATCH}"
  GH_BIN="${TOOLCHAIN_SCRATCH}/pinned-gh"
  /usr/bin/ruby "${GH_TOOLCHAIN_VERIFIER_PATH}" \
    --policy "${GH_TOOLCHAIN_POLICY_PATH}" \
    --source "${unverified_gh_bin}" \
    --destination "${GH_BIN}" >/dev/null
  assert_safe_gh_config
  if [ -z "${REPO}" ]; then
    if ! REPO="$(safe_gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)"; then
      echo "error: could not determine GitHub repository; pass --repo owner/name" >&2
      exit 69
    fi
  fi
  if ! secret_names="$(safe_gh secret list --repo "github.com/${REPO}" --json name --jq '.[].name' 2>/dev/null)"; then
    echo "error: could not list GitHub Actions repository secrets for ${REPO}" >&2
    echo "The repository must be readable by the authenticated gh session." >&2
    exit 69
  fi
  if ! environment_secret_names="$(safe_gh secret list --env "${ENVIRONMENT_NAME}" --repo "github.com/${REPO}" --json name --jq '.[].name' 2>/dev/null)"; then
    echo "error: could not list GitHub Actions environment secrets for ${REPO}/${ENVIRONMENT_NAME}" >&2
    echo "The environment must exist and be readable so shadowing can be ruled out." >&2
    exit 69
  fi
fi

missing=()
for name in "${required_secrets[@]}"; do
  if ! printf '%s\n' "${secret_names}" | /usr/bin/grep -Fxq "${name}"; then
    missing+=("${name}")
  fi
done

shadowed=()
for name in "${required_secrets[@]}"; do
  if printf '%s\n' "${environment_secret_names}" | /usr/bin/grep -Fxq "${name}"; then
    shadowed+=("${name}")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  for name in "${missing[@]}"; do
    echo "Missing required release secret: ${name}" >&2
  done
  echo "Configure the required GitHub Actions repository secrets documented in docs/release.md before starting a release transaction." >&2
  exit 1
fi

if [ "${#shadowed[@]}" -gt 0 ]; then
  for name in "${shadowed[@]}"; do
    echo "Environment secret shadows repository release secret: ${name}" >&2
  done
  echo "Remove same-name secrets from the GitHub ${ENVIRONMENT_NAME} environment before starting a release transaction." >&2
  exit 1
fi

if [ -n "${REPO}" ]; then
  echo "Release repository secrets OK for ${REPO}: ${#required_secrets[@]} required names are configured."
else
  echo "Release repository secrets OK: ${#required_secrets[@]} required names are configured."
fi
echo "Shadow check OK for ${ENVIRONMENT_NAME}: no required repository secret name is duplicated on the environment."
echo "Scope note: this name-only preflight never reads values; workflow-contract validation separately restricts where every release secret may be referenced."
