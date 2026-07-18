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
    VIFTY_RELEASE_METADATA_ROOT="${VIFTY_RELEASE_METADATA_ROOT:-}" \
    VIFTY_RELEASE_PINNED_GH="${VIFTY_RELEASE_PINNED_GH:-}" \
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
  BASH_ENV ENV RUBYOPT RUBYLIB \
  http_proxy https_proxy all_proxy no_proxy \
  HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY \
  CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR \
  GH_CONFIG_DIR XDG_CONFIG_HOME GH_PATH GH_FORCE_TTY GITHUB_API_URL; do
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
unset BASH_ENV ENV RUBYOPT RUBYLIB CDPATH

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
export PATH
CURL_BIN="/usr/bin/curl"
GIT_BIN="/usr/bin/git"
INVOCATION_DIR="$(pwd -P)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd -P)}"
GH_TOOLCHAIN_VERIFIER_PATH="${ROOT_DIR}/scripts/verify-release-gh-toolchain.rb"
GH_TOOLCHAIN_POLICY_PATH="${ROOT_DIR}/.github/release-gh-toolchain.json"
GH_BIN=""
for gh_candidate in /opt/homebrew/bin/gh /usr/local/bin/gh /usr/bin/gh; do
  if [[ -x "${gh_candidate}" ]]; then
    GH_BIN="${gh_candidate}"
    break
  fi
done

REPO="Reedtrullz/Vifty"
ENVIRONMENT_NAME="release"
BRANCH_NAME="main"
JSON_FILE=""
BRANCH_PROTECTION_JSON_FILE=""
DEPLOYMENT_POLICIES_JSON=""
OUTPUT_PATH=""
WORKFLOW_PUBLIC=0
EXPECTED_BRANCH_SHA=""
TOOLCHAIN_SCRATCH=""
output_tmp=""

cleanup_release_environment_check() {
  [[ -z "${output_tmp}" ]] || /bin/rm -f -- "${output_tmp}"
  [[ -z "${TOOLCHAIN_SCRATCH}" ]] || /bin/rm -rf "${TOOLCHAIN_SCRATCH}"
}
trap cleanup_release_environment_check EXIT

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-environment.sh [options]

Options:
  --repo <owner/repo>       GitHub repository (default: Reedtrullz/Vifty).
  --environment <name>      Environment name (default: release).
  --branch <name>           Protected source/main branch to bind (default: main).
  --json-file <path>        Parse an offline/API fixture instead of calling gh.
                            The fixture must include a
                            deployment_branch_policies API response.
  --branch-protection-json-file <path>
                            Parse combined branch-summary/full-protection evidence
                            with --json-file.
  --workflow-public         Use only public environment and branch-summary fields
                            available to GitHub's built-in workflow token.
  --expected-branch-sha <sha>
                            Require the public branch summary to bind this commit.
  --output <path>           Write normalized read-only JSON evidence.

Fails unless the exact solo-maintainer release environment exists without a
required-reviewer gate, disables administrator bypass, and admits deployments
only from one custom tag policy whose type is `tag` and whose pattern is `v*`.
Workflow YAML can declare an environment, but only this settings/API readback
proves the actual deployment boundary. Separately, the required main branch
must require a pull request without an unavailable peer approval, enforce the
Actions-owned SwiftPM check for administrators, require conversation
resolution, and forbid force pushes and deletion.

The default administrator-full mode requires repository-administration read access.
Workflow-public mode intentionally proves only public environment policy,
protected-branch status, exact branch SHA, and the Actions-owned status check;
it never fabricates privileged branch settings that GitHub does not expose.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --environment)
      ENVIRONMENT_NAME="${2:-}"
      shift 2
      ;;
    --json-file)
      JSON_FILE="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH_NAME="${2:-}"
      shift 2
      ;;
    --branch-protection-json-file)
      BRANCH_PROTECTION_JSON_FILE="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --workflow-public)
      WORKFLOW_PUBLIC=1
      shift
      ;;
    --expected-branch-sha)
      EXPECTED_BRANCH_SHA="${2:-}"
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

if [[ ! "${REPO}" =~ ^[^/]+/[^/]+$ || -z "${ENVIRONMENT_NAME}" || -z "${BRANCH_NAME}" ]]; then
  echo "error: repository, environment, and branch must be non-empty" >&2
  exit 64
fi
if [[ -n "${EXPECTED_BRANCH_SHA}" && ! "${EXPECTED_BRANCH_SHA}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: --expected-branch-sha must be a full lowercase commit SHA" >&2
  exit 64
fi
if [[ "${WORKFLOW_PUBLIC}" != "1" && -n "${EXPECTED_BRANCH_SHA}" ]]; then
  echo "error: --expected-branch-sha requires --workflow-public" >&2
  exit 64
fi

canonical_existing_path() {
  local path="$1"
  local parent base
  [[ -e "${path}" || -L "${path}" ]] || return 1
  parent="$(cd "$(dirname "${path}")" && pwd -P)" || return 1
  base="$(basename "${path}")"
  printf '%s/%s\n' "${parent}" "${base}"
}

prepare_output_path() {
  local requested="$1"
  local requested_parent output_parent output_base worktree_root git_dir git_common relative
  local protected_path canonical_protected
  [[ -n "${requested}" ]] || return 0
  if [[ "${requested}" != /* ]]; then
    requested="${INVOCATION_DIR}/${requested}"
  fi
  requested_parent="$(dirname "${requested}")"
  output_base="$(basename "${requested}")"
  if [[ ! -d "${requested_parent}" || "${output_base}" == "." || "${output_base}" == ".." ]]; then
    echo "error: environment evidence output parent must already be a real directory" >&2
    exit 66
  fi
  output_parent="$(cd "${requested_parent}" && pwd -P)"
  OUTPUT_PATH="${output_parent}/${output_base}"
  worktree_root="$("${GIT_BIN}" -C "${INVOCATION_DIR}" rev-parse --show-toplevel 2>/dev/null || true)"
  git_dir="$("${GIT_BIN}" -C "${INVOCATION_DIR}" rev-parse --path-format=absolute --absolute-git-dir 2>/dev/null || true)"
  git_common="$("${GIT_BIN}" -C "${INVOCATION_DIR}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -z "${worktree_root}" || -z "${git_dir}" || -z "${git_common}" ]]; then
    echo "error: environment evidence output requires a Git worktree" >&2
    exit 65
  fi
  worktree_root="$(cd "${worktree_root}" && pwd -P)"
  case "${OUTPUT_PATH}" in
    "${git_dir}"|"${git_dir}"/*|"${git_common}"|"${git_common}"/*)
      echo "error: environment evidence output must not be inside Git metadata" >&2
      exit 65
      ;;
  esac
  case "${OUTPUT_PATH}" in
    "${worktree_root}"/*)
      relative="${OUTPUT_PATH#"${worktree_root}/"}"
      if "${GIT_BIN}" -C "${worktree_root}" ls-files --error-unmatch -- "${relative}" >/dev/null 2>&1; then
        echo "error: environment evidence output must not replace a tracked worktree path" >&2
        exit 65
      fi
      ;;
  esac
  for protected_path in "${JSON_FILE}" "${BRANCH_PROTECTION_JSON_FILE}"; do
    [[ -n "${protected_path}" ]] || continue
    if [[ "${protected_path}" != /* ]]; then
      protected_path="${INVOCATION_DIR}/${protected_path}"
    fi
    canonical_protected="$(canonical_existing_path "${protected_path}" 2>/dev/null || true)"
    if [[ -n "${canonical_protected}" && "${OUTPUT_PATH}" == "${canonical_protected}" ]]; then
      echo "error: environment evidence output must not replace an input fixture" >&2
      exit 65
    fi
  done
  if [[ -L "${OUTPUT_PATH}" ||
        ( -e "${OUTPUT_PATH}" && ! -f "${OUTPUT_PATH}" ) ]]; then
    echo "error: environment evidence output must be a regular non-symlink file" >&2
    exit 65
  fi
  rm -f -- "${OUTPUT_PATH}" || {
    echo "error: could not clear stale environment output: ${OUTPUT_PATH}" >&2
    exit 73
  }
}

prepare_output_path "${OUTPUT_PATH}"

if [[ -n "${JSON_FILE}" ]]; then
  if [[ ! -f "${JSON_FILE}" ]]; then
    echo "error: environment JSON file not found: ${JSON_FILE}" >&2
    exit 66
  fi
  RAW_JSON="$(<"${JSON_FILE}")"
  if [[ -z "${BRANCH_PROTECTION_JSON_FILE}" || ! -f "${BRANCH_PROTECTION_JSON_FILE}" ]]; then
    echo "error: --json-file requires a readable --branch-protection-json-file" >&2
    exit 66
  fi
  BRANCH_PROTECTION_JSON="$(<"${BRANCH_PROTECTION_JSON_FILE}")"
  DEPLOYMENT_POLICIES_JSON="${RAW_JSON}"
else
  if [[ -n "${GH_HOST:-}" && "${GH_HOST}" != "github.com" ]]; then
    echo "error: release environment evidence requires github.com, not GH_HOST=${GH_HOST}" >&2
    exit 65
  fi
  if [[ "${WORKFLOW_PUBLIC}" == "1" ]]; then
    if [[ -n "${GITHUB_API_URL:-}" && "${GITHUB_API_URL%/}" != "https://api.github.com" ]]; then
      echo "error: workflow-public environment evidence requires https://api.github.com" >&2
      exit 65
    fi
    API_ROOT="https://api.github.com"
    CURL_HEADERS=(
      -H 'Accept: application/vnd.github+json'
      -H 'X-GitHub-Api-Version: 2022-11-28'
      -H 'Cache-Control: no-cache'
      -H 'Pragma: no-cache'
    )
    workflow_public_curl() {
      if [[ -n "${INHERITED_GH_TOKEN:-}" ]]; then
        builtin printf 'Authorization: Bearer %s\n' "${INHERITED_GH_TOKEN}" |
          "${CURL_BIN}" --disable --fail --silent --show-error \
            --header @- \
            "${CURL_HEADERS[@]}" "$@"
      else
        "${CURL_BIN}" --disable --fail --silent --show-error \
          "${CURL_HEADERS[@]}" "$@"
      fi
    }
    if ! RAW_JSON="$(workflow_public_curl \
      "${API_ROOT}/repos/${REPO}/environments/${ENVIRONMENT_NAME}")"; then
      echo "error: public GitHub environment ${REPO}/${ENVIRONMENT_NAME} is missing or unreadable" >&2
      exit 65
    fi
    if ! BRANCH_PROTECTION_JSON="$(workflow_public_curl \
      "${API_ROOT}/repos/${REPO}/branches/${BRANCH_NAME}")"; then
      echo "error: public release branch ${REPO}@${BRANCH_NAME} is missing or unreadable" >&2
      exit 65
    fi
    if ! DEPLOYMENT_POLICIES_JSON="$(workflow_public_curl \
      "${API_ROOT}/repos/${REPO}/environments/${ENVIRONMENT_NAME}/deployment-branch-policies?per_page=100")"; then
      echo "error: public deployment policies for GitHub environment ${REPO}/${ENVIRONMENT_NAME} are missing or unreadable" >&2
      exit 65
    fi
  else
    [[ -z "${VIFTY_RELEASE_PINNED_GH:-}" ]] || GH_BIN="${VIFTY_RELEASE_PINNED_GH}"
    if [[ -z "${GH_BIN}" ]]; then
      echo "error: gh CLI is required for administrator environment evidence" >&2
      exit 65
    fi
    unverified_gh_bin="${GH_BIN}"
    TOOLCHAIN_SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/vifty-release-environment-gh.XXXXXX")"
    /bin/chmod 700 "${TOOLCHAIN_SCRATCH}"
    GH_BIN="${TOOLCHAIN_SCRATCH}/pinned-gh"
    /usr/bin/ruby "${GH_TOOLCHAIN_VERIFIER_PATH}" \
      --policy "${GH_TOOLCHAIN_POLICY_PATH}" \
      --source "${unverified_gh_bin}" \
      --destination "${GH_BIN}" >/dev/null
    assert_safe_gh_config
    if ! RAW_JSON="$(safe_gh api --hostname github.com "repos/${REPO}/environments/${ENVIRONMENT_NAME}" 2>/dev/null)"; then
      echo "error: GitHub environment ${REPO}/${ENVIRONMENT_NAME} is missing or unreadable" >&2
      exit 65
    fi
    if ! BRANCH_SUMMARY_JSON="$(safe_gh api --hostname github.com "repos/${REPO}/branches/${BRANCH_NAME}" 2>/dev/null)"; then
      echo "error: required release branch ${REPO}@${BRANCH_NAME} is missing or unreadable" >&2
      exit 65
    fi
    if ! BRANCH_SETTINGS_JSON="$(safe_gh api --hostname github.com "repos/${REPO}/branches/${BRANCH_NAME}/protection" 2>/dev/null)"; then
      echo "error: required release branch ${REPO}@${BRANCH_NAME} has no readable strong protection settings" >&2
      exit 65
    fi
    BRANCH_PROTECTION_JSON="$(/usr/bin/ruby -rjson -e '
      summary = JSON.parse(ARGV.fetch(0))
      protection = JSON.parse(ARGV.fetch(1))
      puts JSON.generate({
        "name" => summary["name"],
        "protected" => summary["protected"],
        "commitSHA" => summary.dig("commit", "sha"),
        "protection" => protection
      })
    ' "${BRANCH_SUMMARY_JSON}" "${BRANCH_SETTINGS_JSON}")"
    if ! DEPLOYMENT_POLICIES_JSON="$(safe_gh api \
      --hostname github.com \
      -H 'Cache-Control: no-cache' \
      -H 'Pragma: no-cache' \
      "repos/${REPO}/environments/${ENVIRONMENT_NAME}/deployment-branch-policies?per_page=100" 2>/dev/null)"; then
      echo "error: deployment policies for GitHub environment ${REPO}/${ENVIRONMENT_NAME} are missing or unreadable" >&2
      exit 65
    fi
  fi
fi

if ! NORMALIZED="$(/usr/bin/ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  expected_name = ARGV.fetch(0)
  expected_branch = ARGV.fetch(1)
  branch = JSON.parse(ARGV.fetch(2))
  evidence_scope = ARGV.fetch(3)
  expected_branch_sha = ARGV.fetch(4)
  policy_source = JSON.parse(ARGV.fetch(5))
  data_source = ARGV.fetch(6)
  fixture_mode = data_source == "test-fixture"
  abort("environment evidence data source is invalid") unless fixture_mode || data_source == "github-api-live"
  normalized_status = fixture_mode ? "test-fixture" : "passed"
  release_authorized = !fixture_mode
  actual_name = data["name"]
  abort("environment name #{actual_name.inspect} does not match #{expected_name}") unless actual_name == expected_name

  protection_rules = data["protection_rules"]
  abort("environment protection_rules evidence must be an array") unless protection_rules.is_a?(Array)
  reviewer_rule = protection_rules.find { |item| item.is_a?(Hash) && item["type"] == "required_reviewers" }
  abort("solo-maintainer release environment must not configure required reviewers") if reviewer_rule
  abort("administrators must not be allowed to bypass environment protection rules") unless data["can_admins_bypass"] == false

  policy = data["deployment_branch_policy"]
  abort("deployment policy must disable protected-branch admission and require custom policies") unless
    policy.is_a?(Hash) && policy["protected_branches"] == false && policy["custom_branch_policies"] == true
  policy_listing = if policy_source.is_a?(Hash) && policy_source.key?("deployment_branch_policies")
    policy_source["deployment_branch_policies"]
  else
    policy_source
  end
  abort("deployment branch policy listing must be an API response object") unless policy_listing.is_a?(Hash)
  policy_count = policy_listing["total_count"]
  deployment_policies = policy_listing["branch_policies"]
  abort("deployment branch policy listing must expose a complete policy count and array") unless
    policy_count.is_a?(Integer) && policy_count >= 0 &&
      deployment_policies.is_a?(Array) && policy_count == deployment_policies.length
  abort("release environment must configure exactly one deployment policy") unless policy_count == 1
  release_tag_policy = deployment_policies.fetch(0)
  abort("release environment deployment policy must be an object") unless release_tag_policy.is_a?(Hash)
  abort("release environment deployment policy must be tag-only with pattern v*") unless
    release_tag_policy["type"] == "tag" && release_tag_policy["name"] == "v*"
  normalized_deployment_policies = deployment_policies.map do |item|
    {"type" => item.fetch("type"), "name" => item.fetch("name")}
  end
  abort("required release branch name does not match #{expected_branch}") unless branch.is_a?(Hash) && branch["name"] == expected_branch
  abort("required release branch #{expected_branch} is not protected") unless branch["protected"] == true

  protection = branch["protection"]
  abort("required release branch #{expected_branch} is missing protection evidence") unless protection.is_a?(Hash)
  if evidence_scope == "workflow-public"
    branch_sha = branch.dig("commit", "sha") || branch["commitSHA"]
    abort("public branch summary must bind expected commit #{expected_branch_sha}") unless
      !expected_branch_sha.empty? && branch_sha == expected_branch_sha
    status_checks = protection["required_status_checks"]
    abort("public branch summary must show status checks enforced for everyone") unless
      status_checks.is_a?(Hash) && status_checks["enforcement_level"] == "everyone"
    checks = Array(status_checks["checks"])
    trusted_ci_check = checks.find do |check|
      check.is_a?(Hash) && check["context"] == "SwiftPM checks" && check["app_id"] == 15_368
    end
    abort("public branch summary must require SwiftPM checks from the GitHub Actions app") unless trusted_ci_check
    puts JSON.pretty_generate({
      "schemaVersion" => 5,
      "status" => normalized_status,
      "releaseAuthorized" => release_authorized,
      "dataSource" => data_source,
      "evidenceScope" => "workflow-public",
      "privilegedSettingsVerified" => false,
      "environment" => actual_name,
      "releaseGovernanceMode" => "solo-maintainer",
      "requiredReviewerGate" => false,
      "requiredReviewers" => [],
      "preventSelfReview" => false,
      "administratorsCanBypass" => false,
      "deploymentBranchPolicy" => policy,
      "releaseTagDeploymentPolicy" => {
        "policyCount" => policy_count,
        "branchPolicyCount" => 0,
        "tagPolicyCount" => 1,
        "requiredTagPattern" => "v*",
        "policies" => normalized_deployment_policies
      },
      "requiredBranch" => expected_branch,
      "requiredBranchCommitSHA" => branch_sha,
      "requiredBranchProtected" => true,
      "requiredBranchProtection" => {
        "statusCheckEnforcementLevel" => "everyone",
        "requiredStatusCheck" => {
          "context" => trusted_ci_check.fetch("context"),
          "appID" => trusted_ci_check.fetch("app_id")
        }
      },
      "operatorOnlyChecks" => [
        "pull-request-required-zero-approvals-no-bypass",
        "conversation-resolution",
        "force-push-disabled",
        "deletion-disabled"
      ],
      "readOnly" => true
    })
    exit
  end

  branch_sha = branch["commitSHA"] || branch.dig("commit", "sha")
  abort("administrator branch summary must contain a full commit SHA") unless
    branch_sha.is_a?(String) && branch_sha.match?(/\A[0-9a-f]{40}\z/)

  status_checks = protection["required_status_checks"]
  abort("required release branch #{expected_branch} must require strict status checks") unless
    status_checks.is_a?(Hash) && status_checks["strict"] == true
  checks = Array(status_checks["checks"])
  trusted_ci_check = checks.find do |check|
    check.is_a?(Hash) && check["context"] == "SwiftPM checks" && check["app_id"] == 15_368
  end
  abort("required release branch #{expected_branch} must require SwiftPM checks from the GitHub Actions app") unless trusted_ci_check

  enforce_admins = protection.dig("enforce_admins", "enabled")
  abort("required release branch #{expected_branch} must enforce protection for administrators") unless enforce_admins == true
  pull_request = protection["required_pull_request_reviews"]
  abort("required release branch #{expected_branch} must require a pull request") unless pull_request.is_a?(Hash)
  abort("required release branch #{expected_branch} must not require peer approval in solo-maintainer mode") unless
    pull_request["required_approving_review_count"] == 0 &&
      pull_request["require_code_owner_reviews"] == false &&
      pull_request["require_last_push_approval"] == false
  bypass = pull_request["bypass_pull_request_allowances"]
  bypass_actors = if bypass.nil?
    []
  elsif bypass.is_a?(Hash)
    %w[users teams apps].flat_map { |key| Array(bypass[key]) }
  else
    abort("required release branch #{expected_branch} has malformed pull-request bypass evidence")
  end
  abort("required release branch #{expected_branch} must not allow pull-request bypass actors") unless
    bypass_actors.empty?

  conversation_resolution = protection.dig("required_conversation_resolution", "enabled")
  abort("required release branch #{expected_branch} must require conversation resolution") unless conversation_resolution == true
  abort("required release branch #{expected_branch} must forbid force pushes") unless
    protection.dig("allow_force_pushes", "enabled") == false
  abort("required release branch #{expected_branch} must forbid deletion") unless
    protection.dig("allow_deletions", "enabled") == false

  puts JSON.pretty_generate({
    "schemaVersion" => 5,
    "status" => normalized_status,
    "releaseAuthorized" => release_authorized,
    "dataSource" => data_source,
    "evidenceScope" => "administrator-full",
    "privilegedSettingsVerified" => true,
    "environment" => actual_name,
    "releaseGovernanceMode" => "solo-maintainer",
    "requiredReviewerGate" => false,
    "requiredReviewers" => [],
    "preventSelfReview" => false,
    "administratorsCanBypass" => false,
    "deploymentBranchPolicy" => policy,
    "releaseTagDeploymentPolicy" => {
      "policyCount" => policy_count,
      "branchPolicyCount" => 0,
      "tagPolicyCount" => 1,
      "requiredTagPattern" => "v*",
      "policies" => normalized_deployment_policies
    },
    "requiredBranch" => expected_branch,
    "requiredBranchCommitSHA" => branch_sha,
    "requiredBranchProtected" => true,
    "requiredBranchProtection" => {
      "strictStatusChecks" => true,
      "requiredStatusCheck" => {
        "context" => trusted_ci_check.fetch("context"),
        "appID" => trusted_ci_check.fetch("app_id")
      },
      "enforceAdministrators" => true,
      "pullRequestRequired" => true,
      "peerApprovalRequired" => false,
      "requiredApprovingReviewCount" => 0,
      "codeOwnerReviewRequired" => false,
      "lastPushApprovalRequired" => false,
      "pullRequestBypassActors" => [],
      "requireConversationResolution" => true,
      "allowForcePushes" => false,
      "allowDeletions" => false
    },
    "readOnly" => true
  })
' "${ENVIRONMENT_NAME}" "${BRANCH_NAME}" "${BRANCH_PROTECTION_JSON}" "$([[ "${WORKFLOW_PUBLIC}" == "1" ]] && printf workflow-public || printf administrator-full)" "${EXPECTED_BRANCH_SHA}" "${DEPLOYMENT_POLICIES_JSON}" "$([[ -n "${JSON_FILE}" ]] && printf test-fixture || printf github-api-live)" <<< "${RAW_JSON}" 2>&1)"; then
  echo "error: release environment protection failed: ${NORMALIZED}" >&2
  exit 65
fi

if [[ -n "${OUTPUT_PATH}" ]]; then
  output_dir="$(dirname "${OUTPUT_PATH}")"
  output_base="$(basename "${OUTPUT_PATH}")"
  output_tmp="$(mktemp "${output_dir}/.${output_base}.tmp.XXXXXX")"
  printf '%s\n' "${NORMALIZED}" > "${output_tmp}"
  expected_output_sha="$(/usr/bin/shasum -a 256 "${output_tmp}" | /usr/bin/awk '{print $1}')"
  if [[ "$(cd "${output_dir}" && pwd -P)" != "${output_dir}" ||
        -L "${OUTPUT_PATH}" ||
        ( -e "${OUTPUT_PATH}" && ! -f "${OUTPUT_PATH}" ) ]]; then
    echo "error: environment evidence output path changed before publication" >&2
    exit 73
  fi
  mv -f -- "${output_tmp}" "${OUTPUT_PATH}"
  output_tmp=""
  if [[ -L "${OUTPUT_PATH}" || ! -f "${OUTPUT_PATH}" ||
        "$(/usr/bin/shasum -a 256 "${OUTPUT_PATH}" | /usr/bin/awk '{print $1}')" != "${expected_output_sha}" ]]; then
    rm -f -- "${OUTPUT_PATH}" >/dev/null 2>&1 || true
    echo "error: environment evidence output changed during publication" >&2
    exit 73
  fi
fi
printf '%s\n' "${NORMALIZED}"
