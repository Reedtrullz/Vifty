#!/bin/bash -p
if [[ "$0" != "vifty-release-clean" ]]; then
  release_token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [[ "${release_token}" == *[[:space:]]* ]]; then
    echo "error: GitHub token must not contain whitespace" >&2
    exit 65
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
  exit 65
fi

for hostile_name in \
  BASH_ENV ENV RUBYOPT RUBYLIB TAR_OPTIONS \
  http_proxy https_proxy all_proxy no_proxy \
  HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY \
  CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR \
  GIT_SSL_CAINFO GIT_SSL_CAPATH GIT_SSH GIT_SSH_COMMAND GIT_ASKPASS SSH_ASKPASS \
  GIT_EXEC_PATH GIT_CONFIG_PARAMETERS GIT_EXTERNAL_DIFF GIT_DIFF_OPTS GIT_PROXY_COMMAND \
  GH_CONFIG_DIR XDG_CONFIG_HOME GH_PATH GH_FORCE_TTY GITHUB_API_URL \
  VIFTY_RELEASE_METADATA_ROOT; do
  if [[ -n "${!hostile_name:-}" ]]; then
    echo "error: hostile interpreter environment is not allowed: ${hostile_name}" >&2
    exit 65
  fi
done

assert_safe_gh_config() {
  local unix_socket token
  unix_socket="$("${GH_BIN}" config get http_unix_socket --host github.com 2>/dev/null || true)"
  if [[ -n "${unix_socket}" ]]; then
    echo "error: GitHub CLI http_unix_socket must be empty for github.com" >&2
    exit 65
  fi
  token="${INHERITED_GH_TOKEN:-}"
  if [[ -z "${token}" ]]; then
    token="$("${GH_BIN}" auth token --hostname github.com 2>/dev/null || true)"
  fi
  if [[ -z "${token}" || "${token}" == *[[:space:]]* ||
        ! -d /var/empty || -w /var/empty ]]; then
    echo "error: an authenticated github.com token and trusted empty gh config root are required" >&2
    exit 65
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

run_clean_script_with_token() {
  local script_path="$1"
  local status
  shift
  exec 9<<<"${SAFE_GH_TOKEN}"
  set +e
  VIFTY_GH_TOKEN_FD=9 \
    /bin/bash -p -c 'source "$1" "${@:2}"' \
      vifty-release-clean "${script_path}" "$@"
  status=$?
  set -e
  exec 9<&-
  return "${status}"
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

export GIT_NO_REPLACE_OBJECTS=1
for git_environment_name in \
  GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_REPLACE_REF_BASE \
  GIT_CONFIG GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL GIT_CONFIG_COUNT \
  GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0; do
  unset "${git_environment_name}"
done
GIT_BIN="/usr/bin/git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_TAG_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
REPOSITORY="Reedtrullz/Vifty"
REMOTE="origin"
TAG=""
COMMIT=""
EVIDENCE_OUTPUT_PATH=""
GOVERNANCE_TOOL_PATH="scripts/check-release-governance.sh"
ENVIRONMENT_TOOL_PATH="scripts/check-release-environment.sh"
SECRETS_TOOL_PATH="scripts/check-release-secrets.sh"
VALIDATOR_PATH="scripts/validate-release-governance-evidence.rb"
TAGGER_PATH="scripts/create-signed-release-tag.sh"
ALLOWED_SIGNERS_PATH=".github/release-signers.allowed"
MANIFEST_CHECKER_PATH="scripts/check-release-manifest.sh"
RELEASE_PREP_DIFF_CHECKER_PATH="scripts/check-release-prep-diff.sh"
WORKFLOW_CONTRACT_PATH="scripts/check-workflow-contract.rb"
GH_TOOLCHAIN_VERIFIER_PATH="scripts/verify-release-gh-toolchain.rb"
GH_TOOLCHAIN_POLICY_PATH=".github/release-gh-toolchain.json"
INVOCATION_DIR="$(pwd -P)"
EVIDENCE_OUTPUT_WRITTEN=0

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/create-signed-release-tag.sh --tag v<version> --commit <sha> [options]

Creates, but never pushes, one SSH-signed annotated release tag. The command
requires a clean worktree at the exact protected-main commit, a matching remote
main, and an absent local and remote tag. It acquires administrator pre-tag
evidence itself from github.com, embeds the exact bytes in the signed tag, and
rechecks live governance after interactive signing before reporting success.

Options:
  --repository <owner/repo>  Evidence repository (default: Reedtrullz/Vifty).
  --remote <name>            Git remote (default: origin).
  --tag <tag>                Release tag, formatted v<major>.<minor>.<patch>.
  --commit <sha>             Exact 40-character protected-main commit.
  --evidence-output <path>   Atomically retain the exact embedded evidence JSON.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repository) REPOSITORY="${2:-}"; shift 2 ;;
    --remote) REMOTE="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    --commit) COMMIT="${2:-}"; shift 2 ;;
    --evidence-output) EVIDENCE_OUTPUT_PATH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

cd "${ROOT_DIR}"
ROOT_DIR="$(pwd -P)"

prepare_evidence_output() {
  local requested="$1"
  local requested_parent output_parent output_base git_dir git_common relative
  [[ -n "${requested}" ]] || return 0
  if [[ "${requested}" != /* ]]; then
    requested="${INVOCATION_DIR}/${requested}"
  fi
  requested_parent="$(dirname "${requested}")"
  output_base="$(basename "${requested}")"
  if [[ ! -d "${requested_parent}" || "${output_base}" == "." || "${output_base}" == ".." ]]; then
    echo "error: evidence output parent must already be a real directory" >&2
    exit 66
  fi
  output_parent="$(cd "${requested_parent}" && pwd -P)"
  EVIDENCE_OUTPUT_PATH="${output_parent}/${output_base}"
  git_dir="$("${GIT_BIN}" rev-parse --path-format=absolute --absolute-git-dir 2>/dev/null || true)"
  git_common="$("${GIT_BIN}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -z "${git_dir}" || -z "${git_common}" ]]; then
    echo "error: release tagging root must be a Git worktree" >&2
    exit 65
  fi
  case "${EVIDENCE_OUTPUT_PATH}" in
    "${git_dir}"|"${git_dir}"/*|"${git_common}"|"${git_common}"/*)
      echo "error: evidence output must not be inside Git metadata" >&2
      exit 65
      ;;
  esac
  case "${EVIDENCE_OUTPUT_PATH}" in
    "${ROOT_DIR}"/*)
      relative="${EVIDENCE_OUTPUT_PATH#"${ROOT_DIR}/"}"
      if "${GIT_BIN}" ls-files --error-unmatch -- "${relative}" >/dev/null 2>&1; then
        echo "error: evidence output must not replace a tracked worktree path" >&2
        exit 65
      fi
      ;;
  esac
  if [[ -L "${EVIDENCE_OUTPUT_PATH}" ||
        ( -e "${EVIDENCE_OUTPUT_PATH}" && ! -f "${EVIDENCE_OUTPUT_PATH}" ) ]]; then
    echo "error: evidence output must be a regular non-symlink file" >&2
    exit 65
  fi
  rm -f -- "${EVIDENCE_OUTPUT_PATH}"
}

prepare_evidence_output "${EVIDENCE_OUTPUT_PATH}"

if [[ ! "${REPOSITORY}" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
  echo "error: --repository must be OWNER/REPO" >&2
  exit 64
fi
if [[ -z "${REMOTE}" ]]; then
  echo "error: --remote must be non-empty" >&2
  exit 64
fi
if [[ ! "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: --tag must be v<major>.<minor>.<patch>" >&2
  exit 64
fi
if [[ ! "${COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: --commit must be a full lowercase commit SHA" >&2
  exit 64
fi
for path in \
  "${GOVERNANCE_TOOL_PATH}" \
  "${ENVIRONMENT_TOOL_PATH}" \
  "${SECRETS_TOOL_PATH}" \
  "${VALIDATOR_PATH}" \
  "${TAGGER_PATH}" \
  "${ALLOWED_SIGNERS_PATH}" \
  "${MANIFEST_CHECKER_PATH}" \
  "${RELEASE_PREP_DIFF_CHECKER_PATH}" \
  "${WORKFLOW_CONTRACT_PATH}" \
  "${GH_TOOLCHAIN_VERIFIER_PATH}" \
  "${GH_TOOLCHAIN_POLICY_PATH}" \
  ".github/release-manifest.json" \
  "Resources/Info.plist"; do
  if [[ ! -f "${ROOT_DIR}/${path}" ]]; then
    echo "error: required release-tag file is missing: ${path}" >&2
    exit 66
  fi
done

signing_program="$("${GIT_BIN}" config --get gpg.ssh.program 2>/dev/null || true)"
[[ -n "${signing_program}" ]] || signing_program="/usr/bin/ssh-keygen"
signing_key="$("${GIT_BIN}" config --get user.signingkey 2>/dev/null || true)"
tagger_name="$("${GIT_BIN}" config --get user.name 2>/dev/null || true)"
tagger_email="$("${GIT_BIN}" config --get user.email 2>/dev/null || true)"
case "${signing_program}" in
  /usr/bin/ssh-keygen|/Applications/1Password.app/Contents/MacOS/op-ssh-sign) ;;
  *)
    echo "error: unsupported SSH signing program: ${signing_program}" >&2
    exit 65
    ;;
esac
if [[ ! -x "${signing_program}" ]]; then
  echo "error: approved SSH signing program is not executable: ${signing_program}" >&2
  exit 66
fi
case "${signing_program}" in
  /usr/bin/ssh-keygen)
    signing_requirement='anchor apple and identifier "com.apple.ssh-keygen"'
    ;;
  /Applications/1Password.app/Contents/MacOS/op-ssh-sign)
    signing_requirement='anchor apple generic and identifier "op-ssh-sign" and certificate leaf[subject.OU] = "2BUA8C4S2C"'
    ;;
esac
if [[ -L "${signing_program}" || ! -f "${signing_program}" ]] ||
   ! /usr/bin/codesign --verify --strict --verbose=2 \
      -R="${signing_requirement}" "${signing_program}" >/dev/null 2>&1; then
  echo "error: approved SSH signing program failed its exact code-signing requirement" >&2
  exit 65
fi
signing_program_sha="$(/usr/bin/shasum -a 256 "${signing_program}" | /usr/bin/awk '{print $1}')"
if [[ -z "${signing_key}" || -z "${tagger_name}" || -z "${tagger_email}" ]]; then
  echo "error: release tagging requires explicit signing key and tagger identity configuration" >&2
  exit 65
fi

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=12
export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
export GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1=false
export GIT_CONFIG_KEY_2=core.untrackedCache GIT_CONFIG_VALUE_2=false
export GIT_CONFIG_KEY_3=core.attributesFile GIT_CONFIG_VALUE_3=/dev/null
export GIT_CONFIG_KEY_4=core.excludesFile GIT_CONFIG_VALUE_4=/dev/null
export GIT_CONFIG_KEY_5=core.worktree GIT_CONFIG_VALUE_5="${ROOT_DIR}"
export GIT_CONFIG_KEY_6=core.bare GIT_CONFIG_VALUE_6=false
export GIT_CONFIG_KEY_7=gpg.format GIT_CONFIG_VALUE_7=ssh
export GIT_CONFIG_KEY_8=gpg.ssh.program GIT_CONFIG_VALUE_8="${signing_program}"
export GIT_CONFIG_KEY_9=user.signingkey GIT_CONFIG_VALUE_9="${signing_key}"
export GIT_CONFIG_KEY_10=user.name GIT_CONFIG_VALUE_10="${tagger_name}"
export GIT_CONFIG_KEY_11=user.email GIT_CONFIG_VALUE_11="${tagger_email}"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/vifty-signed-release-tag.XXXXXX")"
tag_created=0
created_tag_object=""
success=0
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "${tag_created}" == "1" && "${success}" != "1" && -n "${created_tag_object}" ]]; then
    "${GIT_BIN}" update-ref -d "refs/tags/${TAG}" "${created_tag_object}" >/dev/null 2>&1 || true
  fi
  if [[ "${success}" != "1" && "${EVIDENCE_OUTPUT_WRITTEN}" == "1" ]]; then
    rm -f -- "${EVIDENCE_OUTPUT_PATH}" >/dev/null 2>&1 || true
  fi
  rm -rf "${scratch}"
  exit "${status}"
}
trap cleanup EXIT

read_exact_remote_tag_ref() {
  local response api_status parsed encoded_body
  EXACT_TAG_HTTP_STATUS=""
  EXACT_TAG_BODY=""
  set +e
  response="$(safe_gh api --hostname github.com --include \
    -H 'Cache-Control: no-cache' \
    -H 'Pragma: no-cache' \
    "repos/${REPOSITORY}/git/ref/tags/${TAG}" \
    2>"${scratch}/exact-tag-ref.stderr")"
  api_status=$?
  set -e
  if ! parsed="$(/usr/bin/ruby -rbase64 -e '
    response = STDIN.read
    statuses = []
    response.to_enum(:scan, /^HTTP\/\S+\s+(\d{3})[^\r\n]*\r?$/).each do
      match = Regexp.last_match
      statuses << [match[1], match.end(0)]
    end
    abort("exact-tag response must contain one HTTP status") unless statuses.length == 1
    status, status_end = statuses.fetch(0)
    separator = response.match(/\r?\n\r?\n/, status_end)
    body = separator ? response.byteslice(separator.end(0)..) : ""
    abort("successful exact-tag response lacks a body") if status == "200" && body.empty?
    print status, "\t", Base64.strict_encode64(body)
  ' <<< "${response}")"; then
    return 1
  fi
  EXACT_TAG_HTTP_STATUS="${parsed%%$'\t'*}"
  encoded_body="${parsed#*$'\t'}"
  EXACT_TAG_BODY="$(/usr/bin/ruby -rbase64 -e \
    'print Base64.strict_decode64(ARGV.fetch(0))' "${encoded_body}")"
  if [[ "${api_status}" -eq 0 && "${EXACT_TAG_HTTP_STATUS}" == "200" ]]; then
    return 0
  fi
  if [[ "${api_status}" -ne 0 && "${EXACT_TAG_HTTP_STATUS}" == "404" ]]; then
    return 0
  fi
  return 1
}

if ! worktree_status="$("${GIT_BIN}" status --porcelain=v1 --untracked-files=all)"; then
  echo "error: failed to inspect release-tag worktree state" >&2
  exit 65
fi
if [[ -n "${worktree_status}" ]]; then
  echo "error: release tagging requires a completely clean worktree" >&2
  exit 65
fi

head_commit="$("${GIT_BIN}" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)"
if [[ "${head_commit}" != "${COMMIT}" ]]; then
  echo "error: checked-out commit ${head_commit:-missing} does not match requested release commit ${COMMIT}" >&2
  exit 65
fi

verify_committed_file() {
  local path="$1"
  local committed_path="${scratch}/committed-$(basename "${path}")"
  local working_sha committed_sha
  if ! "${GIT_BIN}" show "${COMMIT}:${path}" > "${committed_path}" 2>/dev/null; then
    echo "error: ${path} is not present in exact release commit ${COMMIT}" >&2
    return 1
  fi
  working_sha="$(/usr/bin/shasum -a 256 "${ROOT_DIR}/${path}" | /usr/bin/awk '{print $1}')"
  committed_sha="$(/usr/bin/shasum -a 256 "${committed_path}" | /usr/bin/awk '{print $1}')"
  if [[ "${working_sha}" != "${committed_sha}" ]]; then
    echo "error: running ${path} does not match exact release commit ${COMMIT}" >&2
    return 1
  fi
}

verify_committed_file "${GOVERNANCE_TOOL_PATH}"
verify_committed_file "${ENVIRONMENT_TOOL_PATH}"
verify_committed_file "${SECRETS_TOOL_PATH}"
verify_committed_file "${VALIDATOR_PATH}"
verify_committed_file "${TAGGER_PATH}"
verify_committed_file "${ALLOWED_SIGNERS_PATH}"
verify_committed_file "${MANIFEST_CHECKER_PATH}"
verify_committed_file "${RELEASE_PREP_DIFF_CHECKER_PATH}"
verify_committed_file "${WORKFLOW_CONTRACT_PATH}"
verify_committed_file "${GH_TOOLCHAIN_VERIFIER_PATH}"
verify_committed_file "${GH_TOOLCHAIN_POLICY_PATH}"
verify_committed_file ".github/release-manifest.json"
verify_committed_file "Resources/Info.plist"

parent_commit="$("${GIT_BIN}" rev-parse --verify "${COMMIT}^" 2>/dev/null || true)"
if [[ ! "${parent_commit}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: release commit must have a trusted first parent" >&2
  exit 65
fi
protected_release_paths=(
  ".github/release-gh-toolchain.json"
  ".github/release-signers.allowed"
  ".github/workflows/ci.yml"
  ".github/workflows/release.yml"
  "scripts/check-release-environment.sh"
  "scripts/check-release-governance.sh"
  "scripts/check-release-manifest-history-from-git.sh"
  "scripts/check-release-manifest-history.rb"
  "scripts/check-release-manifest.sh"
  "scripts/check-release-prep-diff.sh"
  "scripts/check-release-provenance.sh"
  "scripts/check-release-secrets.sh"
  "scripts/check-workflow-contract.rb"
  "scripts/create-signed-release-tag.sh"
  "scripts/lib/release_artifact_contract.rb"
  "scripts/push-and-dispatch-signed-release-tag.sh"
  "scripts/release-candidate-inventory.rb"
  "scripts/render-release-facts.sh"
  "scripts/run-actionlint.sh"
  "scripts/sign-release-candidate.sh"
  "scripts/validate-release-governance-evidence.rb"
  "scripts/validate-release-metadata.sh"
  "scripts/verify-release-artifact.sh"
  "scripts/verify-release-gh-toolchain.rb"
  "scripts/write-release-checklist.sh"
)
for protected_path in "${protected_release_paths[@]}"; do
  current_blob="$("${GIT_BIN}" rev-parse --verify "${COMMIT}:${protected_path}" 2>/dev/null || true)"
  parent_blob="$("${GIT_BIN}" rev-parse --verify "${parent_commit}:${protected_path}" 2>/dev/null || true)"
  if [[ ! "${current_blob}" =~ ^[0-9a-f]{40}$ || "${current_blob}" != "${parent_blob}" ||
        ! -f "${ROOT_DIR}/${protected_path}" || -L "${ROOT_DIR}/${protected_path}" ]]; then
    echo "error: protected release tooling must be byte-identical to the exact first parent: ${protected_path}" >&2
    exit 65
  fi
done

commit_signers="${scratch}/commit-release-signers.allowed"
parent_signers="${scratch}/parent-release-signers.allowed"
commit_gh_policy="${scratch}/commit-release-gh-toolchain.json"
parent_gh_policy="${scratch}/parent-release-gh-toolchain.json"
"${GIT_BIN}" show "${COMMIT}:${ALLOWED_SIGNERS_PATH}" > "${commit_signers}"
"${GIT_BIN}" show "${parent_commit}:${ALLOWED_SIGNERS_PATH}" > "${parent_signers}"
"${GIT_BIN}" show "${COMMIT}:${GH_TOOLCHAIN_POLICY_PATH}" > "${commit_gh_policy}"
"${GIT_BIN}" show "${parent_commit}:${GH_TOOLCHAIN_POLICY_PATH}" > "${parent_gh_policy}"
if ! /usr/bin/cmp -s "${commit_signers}" "${parent_signers}" ||
   ! /usr/bin/cmp -s "${ROOT_DIR}/${ALLOWED_SIGNERS_PATH}" "${commit_signers}"; then
  echo "error: release signer policy must be byte-identical to the exact first parent" >&2
  exit 65
fi
if ! /usr/bin/cmp -s "${commit_gh_policy}" "${parent_gh_policy}" ||
   ! /usr/bin/cmp -s "${ROOT_DIR}/${GH_TOOLCHAIN_POLICY_PATH}" "${commit_gh_policy}"; then
  echo "error: release gh toolchain policy must be byte-identical to the exact first parent" >&2
  exit 65
fi

committed_root="${scratch}/committed-source"
mkdir -p "${committed_root}"
if ! "${GIT_BIN}" archive --format=tar "${COMMIT}" |
  /usr/bin/tar -xf - -C "${committed_root}"; then
  echo "error: failed to materialize exact committed release tooling" >&2
  exit 65
fi
for executable_path in \
  "${GOVERNANCE_TOOL_PATH}" \
  "${ENVIRONMENT_TOOL_PATH}" \
  "${SECRETS_TOOL_PATH}" \
  "${VALIDATOR_PATH}" \
  "${TAGGER_PATH}" \
  "${MANIFEST_CHECKER_PATH}" \
  "${RELEASE_PREP_DIFF_CHECKER_PATH}" \
  "${WORKFLOW_CONTRACT_PATH}" \
  "${GH_TOOLCHAIN_VERIFIER_PATH}"; do
  if [[ ! -f "${committed_root}/${executable_path}" || -L "${committed_root}/${executable_path}" ]]; then
    echo "error: exact committed release tool is not a regular file: ${executable_path}" >&2
    exit 65
  fi
done
if [[ ! -f "${committed_root}/${GH_TOOLCHAIN_POLICY_PATH}" ||
      -L "${committed_root}/${GH_TOOLCHAIN_POLICY_PATH}" ]]; then
  echo "error: exact committed release gh policy is not a regular file" >&2
  exit 65
fi

version="${TAG#v}"
"${committed_root}/${RELEASE_PREP_DIFF_CHECKER_PATH}" \
  --root "${ROOT_DIR}" \
  --commit "${COMMIT}" >/dev/null
VIFTY_RELEASE_MANIFEST_ROOT="${committed_root}" \
  VIFTY_RELEASE_SOURCE_REPOSITORY_ROOT="${ROOT_DIR}" \
  "${committed_root}/${MANIFEST_CHECKER_PATH}" \
    --publication-version "${version}" \
    --base-ref "${parent_commit}" \
    --require-base >/dev/null
VIFTY_WORKFLOW_CONTRACT_ROOT="${committed_root}" \
  /usr/bin/ruby "${committed_root}/${WORKFLOW_CONTRACT_PATH}" >/dev/null
plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${committed_root}/Resources/Info.plist")"
if [[ "${plist_version}" != "${version}" ]]; then
  echo "error: release tag version ${version} does not match exact committed Info.plist ${plist_version}" >&2
  exit 65
fi

if [[ -n "${GH_HOST:-}" && "${GH_HOST}" != "github.com" ]]; then
  echo "error: release-tag creation requires github.com, not GH_HOST=${GH_HOST}" >&2
  exit 65
fi
if [[ -z "${GH_BIN}" ]]; then
  echo "error: gh CLI is required to prove exact-main push CI before signing" >&2
  exit 65
fi
unverified_gh_bin="${GH_BIN}"
GH_BIN="${scratch}/pinned-gh"
"${committed_root}/${GH_TOOLCHAIN_VERIFIER_PATH}" \
  --policy "${committed_root}/${GH_TOOLCHAIN_POLICY_PATH}" \
  --source "${unverified_gh_bin}" \
  --destination "${GH_BIN}" > "${scratch}/gh-toolchain-verification.json"
assert_safe_gh_config
ci_runs_json="$(safe_gh run list \
  --repo "github.com/${REPOSITORY}" \
  --workflow .github/workflows/ci.yml \
  --limit 100 \
  --json databaseId,headBranch,headSha,status,conclusion,event,url)"
source_ci_run_id="$(/usr/bin/ruby -rjson -e '
  runs = JSON.parse(STDIN.read)
  abort("CI run list must be an array") unless runs.is_a?(Array)
  sha = ARGV.fetch(0)
  matches = runs.select do |run|
    run.is_a?(Hash) &&
      run["headSha"] == sha &&
      run["headBranch"] == "main" &&
      run["event"] == "push" &&
      run["status"] == "completed" &&
      run["conclusion"] == "success" &&
      run["databaseId"].is_a?(Integer) &&
      run["databaseId"].positive?
  end
  abort("no successful completed push CI run on main for exact commit #{sha}") if matches.empty?
  print matches.max_by { |run| run.fetch("databaseId") }.fetch("databaseId")
' "${COMMIT}" <<< "${ci_runs_json}")" || {
  echo "error: no successful completed push CI run on main for exact commit ${COMMIT}" >&2
  exit 65
}

if "${GIT_BIN}" show-ref --verify --quiet "refs/tags/${TAG}"; then
  echo "error: local tag ${TAG} already exists" >&2
  exit 65
fi

configured_remote_url="$("${GIT_BIN}" config --get "remote.${REMOTE}.url" 2>/dev/null || true)"
case "${configured_remote_url}" in
  "https://github.com/${REPOSITORY}"|"https://github.com/${REPOSITORY}.git"|"git@github.com:${REPOSITORY}.git") ;;
  *)
    echo "error: remote ${REMOTE} is not bound to declared GitHub repository ${REPOSITORY}" >&2
    exit 65
    ;;
esac

if ! remote_main_json="$(safe_gh api --hostname github.com \
  -H 'Cache-Control: no-cache' \
  -H 'Pragma: no-cache' \
  "repos/${REPOSITORY}/branches/main" 2>/dev/null)"; then
  echo "error: failed to read remote main identity from github.com/${REPOSITORY}" >&2
  exit 65
fi
remote_main="$(/usr/bin/ruby -rjson -e '
  branch = JSON.parse(STDIN.read)
  sha = branch.dig("commit", "sha")
  abort("remote main response lacks an exact commit SHA") unless sha.is_a?(String) && sha.match?(/\A[0-9a-f]{40}\z/)
  print sha
' <<< "${remote_main_json}")" || {
  echo "error: malformed remote main response from github.com/${REPOSITORY}" >&2
  exit 65
}
if [[ "${remote_main}" != "${COMMIT}" ]]; then
  echo "error: remote github.com/${REPOSITORY} main ${remote_main:-missing} does not match release commit ${COMMIT}" >&2
  exit 65
fi
if ! read_exact_remote_tag_ref; then
  echo "error: exact remote tag state is unknown on github.com/${REPOSITORY}" >&2
  exit 65
fi
if [[ "${EXACT_TAG_HTTP_STATUS}" == "200" ]]; then
  if ! /usr/bin/ruby -rjson -e '
    ref = JSON.parse(STDIN.read)
    tag = ARGV.fetch(0)
    abort("exact tag ref response must be an object") unless ref.is_a?(Hash)
    abort("exact tag ref name mismatch") unless ref["ref"] == "refs/tags/#{tag}"
    object = ref["object"]
    abort("exact tag ref object is malformed") unless
      object.is_a?(Hash) &&
        %w[tag commit].include?(object["type"]) &&
        object["sha"].is_a?(String) &&
        object["sha"].match?(/\A[0-9a-f]{40}\z/)
  ' "${TAG}" <<< "${EXACT_TAG_BODY}"; then
    echo "error: malformed exact remote tag response from github.com/${REPOSITORY}" >&2
    exit 65
  fi
  echo "error: remote tag ${TAG} already exists" >&2
  exit 65
fi

evidence_snapshot="${scratch}/governance-evidence.json"
run_clean_script_with_token "${committed_root}/${GOVERNANCE_TOOL_PATH}" \
  --repo "${REPOSITORY}" \
  --environment release \
  --branch main \
  --tag "${TAG}" \
  --expected-main "${COMMIT}" \
  --output "${evidence_snapshot}" >/dev/null
evidence_bytes="$(/usr/bin/wc -c < "${evidence_snapshot}" | /usr/bin/tr -d '[:space:]')"
if [[ ! "${evidence_bytes}" =~ ^[0-9]+$ || "${evidence_bytes}" -eq 0 || "${evidence_bytes}" -gt 1048576 ]]; then
  echo "error: governance evidence must contain between 1 and 1048576 bytes" >&2
  exit 65
fi

tagger_time="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
/usr/bin/ruby "${committed_root}/${VALIDATOR_PATH}" \
  --root "${ROOT_DIR}" \
  --evidence "${evidence_snapshot}" \
  --repository "${REPOSITORY}" \
  --tag "${TAG}" \
  --commit "${COMMIT}" \
  --tagger-time "${tagger_time}" > "${scratch}/validation.json"

evidence_base64="$(/usr/bin/base64 < "${evidence_snapshot}" | /usr/bin/tr -d '\r\n')"
if [[ -z "${evidence_base64}" ]]; then
  echo "error: failed to encode governance evidence" >&2
  exit 65
fi
message_path="${scratch}/tag-message.txt"
printf 'Vifty release %s\n\nVifty-Release-Governance-Base64: %s\n' \
  "${TAG}" "${evidence_base64}" > "${message_path}"

if [[ "$(/usr/bin/shasum -a 256 "${signing_program}" | /usr/bin/awk '{print $1}')" != "${signing_program_sha}" ]] ||
   ! /usr/bin/codesign --verify --strict --verbose=2 \
      -R="${signing_requirement}" "${signing_program}" >/dev/null 2>&1; then
  echo "error: approved SSH signing program changed before tag signing" >&2
  exit 65
fi
if ! GIT_COMMITTER_DATE="${tagger_time}" "${GIT_BIN}" \
  -c gpg.format=ssh \
  -c "gpg.ssh.program=${signing_program}" \
  tag \
  --sign \
  --annotate \
  --file "${message_path}" \
  "${TAG}" \
  "${COMMIT}"; then
  echo "error: failed to create signed release tag ${TAG}" >&2
  exit 65
fi
tag_created=1
created_tag_object="$("${GIT_BIN}" rev-parse --verify "${TAG}^{tag}" 2>/dev/null || true)"
if [[ ! "${created_tag_object}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: created release tag is not one annotated tag object" >&2
  exit 65
fi

if ! "${GIT_BIN}" -c gpg.format=ssh \
  -c gpg.ssh.program=/usr/bin/ssh-keygen \
  -c "gpg.ssh.allowedSignersFile=${commit_signers}" \
  verify-tag "${created_tag_object}" >/dev/null; then
  echo "error: signed release tag ${TAG} did not verify against ${ALLOWED_SIGNERS_PATH}" >&2
  exit 65
fi

tag_commit="$("${GIT_BIN}" rev-parse --verify "${created_tag_object}^{commit}" 2>/dev/null || true)"
if [[ "${tag_commit}" != "${COMMIT}" ]]; then
  echo "error: created tag ${TAG} does not resolve to ${COMMIT}" >&2
  exit 65
fi

if ! "${GIT_BIN}" cat-file tag "${created_tag_object}" | /usr/bin/ruby -rbase64 -rtime -e '
  raw = STDIN.read.b
  expected_evidence = File.binread(ARGV.fetch(0))
  expected_time = Time.iso8601(ARGV.fetch(1)).to_i
  header, body = raw.split("\n\n", 2)
  abort("annotated tag body is missing") unless header && body
  tag_header = header.lines.find { |line| line.start_with?("tag ") }
  abort("annotated tag name does not match requested release tag") unless tag_header == "tag #{ARGV.fetch(2)}\n"
  object_header = header.lines.find { |line| line.start_with?("object ") }
  abort("annotated tag object does not match release commit") unless object_header == "object #{ARGV.fetch(3)}\n"
  type_header = header.lines.find { |line| line.start_with?("type ") }
  abort("annotated tag must point directly to a commit") unless type_header == "type commit\n"
  tagger = header.lines.find { |line| line.start_with?("tagger ") }
  match = tagger&.match(/ (\d+) [+-]\d{4}\z/)
  abort("annotated tagger timestamp is missing") unless match && match[1].to_i == expected_time
  prefix = "Vifty-Release-Governance-Base64: "
  fields = body.lines.select { |line| line.start_with?(prefix) }
  abort("signed tag must contain exactly one governance evidence field") unless fields.length == 1
  encoded = fields.fetch(0).delete_suffix("\n").delete_suffix("\r")
  encoded = encoded.delete_prefix(prefix)
  decoded = Base64.strict_decode64(encoded)
  abort("signed tag governance evidence bytes do not match") unless decoded == expected_evidence
' "${evidence_snapshot}" "${tagger_time}" "${TAG}" "${COMMIT}"; then
  echo "error: created tag ${TAG} did not preserve exact governance evidence/time binding" >&2
  exit 65
fi

run_clean_script_with_token "${committed_root}/${GOVERNANCE_TOOL_PATH}" \
  --repo "${REPOSITORY}" \
  --environment release \
  --branch main \
  --tag "${TAG}" \
  --expected-main "${COMMIT}" \
  --output "${scratch}/completion-governance-evidence.json" >/dev/null

/usr/bin/ruby -rjson -e '
  signed = JSON.parse(File.read(ARGV.fetch(0)))
  completion = JSON.parse(File.read(ARGV.fetch(1)))
  signed_id = signed.dig("tagRulesetEvidence", "rulesetID")
  completion_id = completion.dig("tagRulesetEvidence", "rulesetID")
  signed_updated_at = signed.dig("tagRulesetEvidence", "rulesetUpdatedAt")
  completion_updated_at = completion.dig("tagRulesetEvidence", "rulesetUpdatedAt")
  abort("live tag ruleset ID changed during signed-tag creation") unless
    signed_id.is_a?(Integer) && signed_id.positive? && completion_id == signed_id
  abort("live tag ruleset revision changed during signed-tag creation") unless
    signed_updated_at.is_a?(String) && completion_updated_at == signed_updated_at
  abort("live actor acquired tag-ruleset bypass during signed-tag creation") unless
    signed.dig("tagRulesetEvidence", "currentUserCanBypass") == "never" &&
      completion.dig("tagRulesetEvidence", "currentUserCanBypass") == "never"
  abort("protected main changed during signed-tag creation") unless
    completion["expectedMainSHA"] == signed["expectedMainSHA"]
  abort("authenticated GitHub actor changed during signed-tag creation") unless
    completion["authenticatedActor"] == signed["authenticatedActor"]
' "${evidence_snapshot}" "${scratch}/completion-governance-evidence.json"

if [[ "$(/usr/bin/shasum -a 256 "${signing_program}" | /usr/bin/awk '{print $1}')" != "${signing_program_sha}" ]] ||
   ! /usr/bin/codesign --verify --strict --verbose=2 \
      -R="${signing_requirement}" "${signing_program}" >/dev/null 2>&1; then
  echo "error: approved SSH signing program changed during tag signing" >&2
  exit 65
fi

completion_time="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
/usr/bin/ruby "${committed_root}/${VALIDATOR_PATH}" \
  --root "${ROOT_DIR}" \
  --evidence "${evidence_snapshot}" \
  --repository "${REPOSITORY}" \
  --tag "${TAG}" \
  --commit "${COMMIT}" \
  --tagger-time "${tagger_time}" \
  --current-time "${completion_time}" > "${scratch}/completion-validation.json"

if [[ "$("${GIT_BIN}" rev-parse --verify "refs/tags/${TAG}^{tag}" 2>/dev/null || true)" != "${created_tag_object}" ]] ||
   [[ "$("${GIT_BIN}" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)" != "${COMMIT}" ]] ||
   [[ -n "$("${GIT_BIN}" status --porcelain=v1 --untracked-files=all)" ]]; then
  echo "error: release worktree, HEAD, or local tag changed during signed-tag creation" >&2
  exit 65
fi
for path in \
  "${GOVERNANCE_TOOL_PATH}" \
  "${ENVIRONMENT_TOOL_PATH}" \
  "${SECRETS_TOOL_PATH}" \
  "${VALIDATOR_PATH}" \
  "${TAGGER_PATH}" \
  "${ALLOWED_SIGNERS_PATH}" \
  "${MANIFEST_CHECKER_PATH}" \
  "${WORKFLOW_CONTRACT_PATH}" \
  ".github/release-manifest.json" \
  "Resources/Info.plist"; do
  verify_committed_file "${path}"
done

final_time="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
/usr/bin/ruby "${committed_root}/${VALIDATOR_PATH}" \
  --root "${ROOT_DIR}" \
  --evidence "${evidence_snapshot}" \
  --repository "${REPOSITORY}" \
  --tag "${TAG}" \
  --commit "${COMMIT}" \
  --tagger-time "${tagger_time}" \
  --current-time "${final_time}" > "${scratch}/final-validation.json"

if [[ -n "${EVIDENCE_OUTPUT_PATH}" ]]; then
  evidence_output_dir="$(dirname "${EVIDENCE_OUTPUT_PATH}")"
  evidence_output_base="$(basename "${EVIDENCE_OUTPUT_PATH}")"
  evidence_output_tmp="$(mktemp "${evidence_output_dir}/.${evidence_output_base}.tmp.XXXXXX")"
  cp "${evidence_snapshot}" "${evidence_output_tmp}"
  mv -f -- "${evidence_output_tmp}" "${EVIDENCE_OUTPUT_PATH}"
  EVIDENCE_OUTPUT_WRITTEN=1
fi

evidence_sha="$(/usr/bin/shasum -a 256 "${evidence_snapshot}" | /usr/bin/awk '{print $1}')"
if [[ "$("${GIT_BIN}" rev-parse --verify "refs/tags/${TAG}^{tag}" 2>/dev/null || true)" != "${created_tag_object}" ]] ||
   [[ "$("${GIT_BIN}" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)" != "${COMMIT}" ]] ||
   [[ -n "$("${GIT_BIN}" status --porcelain=v1 --untracked-files=all)" ]] ||
   { [[ -n "${EVIDENCE_OUTPUT_PATH}" ]] &&
     [[ "$(/usr/bin/shasum -a 256 "${EVIDENCE_OUTPUT_PATH}" | /usr/bin/awk '{print $1}')" != "${evidence_sha}" ]]; }; then
  echo "error: release worktree, HEAD, local tag, or retained evidence changed at completion" >&2
  exit 65
fi
success=1
tag_created=0
echo "Created and verified local signed tag ${TAG} at ${COMMIT}."
echo "Exact-main push CI run: ${source_ci_run_id}"
echo "Governance evidence SHA-256: ${evidence_sha}"
echo "The tag was not pushed."
