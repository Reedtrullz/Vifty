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
  BASH_ENV ENV RUBYOPT RUBYLIB \
  http_proxy https_proxy all_proxy no_proxy \
  HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY \
  CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR \
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

run_pinned_tool_with_token() {
  local script_path="$1"
  local status
  shift
  exec 9<<<"${SAFE_GH_TOKEN}"
  set +e
  VIFTY_GH_TOKEN_FD=9 VIFTY_RELEASE_PINNED_GH="${GH_BIN}" \
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
INVOCATION_DIR="$(pwd -P)"
ROOT_DIR="${INVOCATION_DIR}"
REPO="Reedtrullz/Vifty"
ENVIRONMENT_NAME="release"
BRANCH_NAME="main"
TAG=""
EXPECTED_MAIN=""
EXPECTED_EXISTING_TAG_OBJECT=""
OUTPUT_PATH=""
REPO_JSON_FILE=""
BRANCH_JSON_FILE=""
ENVIRONMENT_JSON_FILE=""
BRANCH_PROTECTION_JSON_FILE=""
REPOSITORY_SECRET_LIST_FILE=""
ENVIRONMENT_SECRET_LIST_FILE=""
RULESET_JSON_FILE=""
REMOTE_TAG_REFS_FILE=""
OUTPUT_TMP=""
ACTOR_JSON=""
ENVIRONMENT_TOOL_PATH="${SCRIPT_DIR}/check-release-environment.sh"
SECRETS_TOOL_PATH="${SCRIPT_DIR}/check-release-secrets.sh"
GH_TOOLCHAIN_VERIFIER_PATH="${SCRIPT_DIR}/verify-release-gh-toolchain.rb"
GH_TOOLCHAIN_POLICY_PATH="${SCRIPT_DIR}/../.github/release-gh-toolchain.json"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-governance.sh --tag v<version> --expected-main <sha> [options]

Runs the administrator-authenticated, read-only pre-tag governance gate. It requires
repository-administrator visibility, the full solo-maintainer environment and
branch policy, all six repository release-secret names with no same-name
environment shadows, and an active update/deletion tag ruleset whose
bypass_actors field is visibly present and empty.

Options:
  --repo <owner/repo>       Repository (default: Reedtrullz/Vifty).
  --environment <name>      Release environment (default: release).
  --branch <name>           Protected release branch (default: main).
  --tag <tag>               Candidate tag, formatted v<major>.<minor>.<patch>.
  --expected-main <sha>     Exact 40-character release-prep main commit.
  --expected-existing-tag-object <sha>
                             Post-push mode: require this exact annotated tag
                             object and its exact commit instead of tag absence.
  --output <path>           Write normalized JSON evidence.

Fixture-only options (all eight are required together):
  --repo-json-file <path>
  --branch-json-file <path>
  --environment-json-file <path>
  --branch-protection-json-file <path>
  --repository-secret-list-file <path>
  --environment-secret-list-file <path>
  --ruleset-json-file <path>
  --remote-tag-refs-file <path>
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --environment) ENVIRONMENT_NAME="${2:-}"; shift 2 ;;
    --branch) BRANCH_NAME="${2:-}"; shift 2 ;;
    --tag) TAG="${2:-}"; shift 2 ;;
    --expected-main) EXPECTED_MAIN="${2:-}"; shift 2 ;;
    --expected-existing-tag-object)
      EXPECTED_EXISTING_TAG_OBJECT="${2:-}"
      shift 2
      ;;
    --output) OUTPUT_PATH="${2:-}"; shift 2 ;;
    --repo-json-file) REPO_JSON_FILE="${2:-}"; shift 2 ;;
    --branch-json-file) BRANCH_JSON_FILE="${2:-}"; shift 2 ;;
    --environment-json-file) ENVIRONMENT_JSON_FILE="${2:-}"; shift 2 ;;
    --branch-protection-json-file) BRANCH_PROTECTION_JSON_FILE="${2:-}"; shift 2 ;;
    --repository-secret-list-file) REPOSITORY_SECRET_LIST_FILE="${2:-}"; shift 2 ;;
    --environment-secret-list-file) ENVIRONMENT_SECRET_LIST_FILE="${2:-}"; shift 2 ;;
    --ruleset-json-file) RULESET_JSON_FILE="${2:-}"; shift 2 ;;
    --remote-tag-refs-file) REMOTE_TAG_REFS_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

canonical_existing_path() {
  local path="$1"
  local parent base
  [[ -e "${path}" || -L "${path}" ]] || return 1
  parent="$(cd "$(dirname "${path}")" && pwd -P)" || return 1
  base="$(basename "${path}")"
  printf '%s/%s\n' "${parent}" "${base}"
}

safe_repository_git() {
  GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_SYSTEM=/dev/null \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_COUNT=6 \
    GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
    GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1=false \
    GIT_CONFIG_KEY_2=core.attributesFile GIT_CONFIG_VALUE_2=/dev/null \
    GIT_CONFIG_KEY_3=core.excludesFile GIT_CONFIG_VALUE_3=/dev/null \
    GIT_CONFIG_KEY_4=core.worktree GIT_CONFIG_VALUE_4="${ROOT_DIR}" \
    GIT_CONFIG_KEY_5=core.bare GIT_CONFIG_VALUE_5=false \
    /usr/bin/git -C "${ROOT_DIR}" "$@"
}

prepare_governance_output() {
  local requested="$1"
  local requested_parent output_parent output_base worktree_root git_dir git_common relative protected_path canonical_protected
  [[ -n "${requested}" ]] || return 0
  if [[ "${requested}" != /* ]]; then
    requested="${INVOCATION_DIR}/${requested}"
  fi
  requested_parent="$(dirname "${requested}")"
  output_base="$(basename "${requested}")"
  if [[ ! -d "${requested_parent}" || "${output_base}" == "." || "${output_base}" == ".." ]]; then
    echo "error: governance output parent must already be a real directory" >&2
    exit 66
  fi
  output_parent="$(cd "${requested_parent}" && pwd -P)"
  OUTPUT_PATH="${output_parent}/${output_base}"
  worktree_root="$(safe_repository_git rev-parse --show-toplevel 2>/dev/null || true)"
  git_dir="$(safe_repository_git rev-parse --path-format=absolute --absolute-git-dir 2>/dev/null || true)"
  git_common="$(safe_repository_git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -z "${worktree_root}" || -z "${git_dir}" || -z "${git_common}" ]]; then
    echo "error: governance checker invocation directory must be a Git worktree root" >&2
    exit 65
  fi
  worktree_root="$(cd "${worktree_root}" && pwd -P)"
  if [[ "${worktree_root}" != "${ROOT_DIR}" ]]; then
    echo "error: governance checker must be invoked from the Git worktree root" >&2
    exit 65
  fi
  case "${OUTPUT_PATH}" in
    "${git_dir}"|"${git_dir}"/*|"${git_common}"|"${git_common}"/*)
      echo "error: governance output must not be inside Git metadata" >&2
      exit 65
      ;;
  esac
  case "${OUTPUT_PATH}" in
    "${ROOT_DIR}"/*)
      relative="${OUTPUT_PATH#"${ROOT_DIR}/"}"
      if safe_repository_git ls-files --error-unmatch -- "${relative}" >/dev/null 2>&1; then
        echo "error: governance output must not replace a tracked worktree path" >&2
        exit 65
      fi
      ;;
  esac
  for protected_path in \
    "${REPO_JSON_FILE}" "${BRANCH_JSON_FILE}" "${ENVIRONMENT_JSON_FILE}" \
    "${BRANCH_PROTECTION_JSON_FILE}" "${REPOSITORY_SECRET_LIST_FILE}" \
    "${ENVIRONMENT_SECRET_LIST_FILE}" "${RULESET_JSON_FILE}" "${REMOTE_TAG_REFS_FILE}" \
    "${SELF_PATH}" "${ENVIRONMENT_TOOL_PATH}" "${SECRETS_TOOL_PATH}"; do
    [[ -n "${protected_path}" ]] || continue
    canonical_protected="$(canonical_existing_path "${protected_path}" 2>/dev/null || true)"
    if [[ -n "${canonical_protected}" && "${OUTPUT_PATH}" == "${canonical_protected}" ]]; then
      echo "error: governance output must not replace a checker input" >&2
      exit 65
    fi
  done
  if [[ -L "${OUTPUT_PATH}" || ( -e "${OUTPUT_PATH}" && ! -f "${OUTPUT_PATH}" ) ]]; then
    echo "error: governance output must be a regular non-symlink file" >&2
    exit 65
  fi
  rm -f -- "${OUTPUT_PATH}"
}

prepare_governance_output "${OUTPUT_PATH}"

if [[ ! "${REPO}" =~ ^[^/]+/[^/]+$ || -z "${ENVIRONMENT_NAME}" || -z "${BRANCH_NAME}" ]]; then
  echo "error: repository, environment, and branch must be non-empty" >&2
  exit 64
fi
if [[ ! "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: --tag must be v<major>.<minor>.<patch>" >&2
  exit 64
fi
if [[ ! "${EXPECTED_MAIN}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: --expected-main must be a full lowercase commit SHA" >&2
  exit 64
fi
if [[ -n "${EXPECTED_EXISTING_TAG_OBJECT}" &&
      ! "${EXPECTED_EXISTING_TAG_OBJECT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: --expected-existing-tag-object must be a full lowercase tag-object SHA" >&2
  exit 64
fi

fixture_values=(
  "${REPO_JSON_FILE}"
  "${BRANCH_JSON_FILE}"
  "${ENVIRONMENT_JSON_FILE}"
  "${BRANCH_PROTECTION_JSON_FILE}"
  "${REPOSITORY_SECRET_LIST_FILE}"
  "${ENVIRONMENT_SECRET_LIST_FILE}"
  "${RULESET_JSON_FILE}"
  "${REMOTE_TAG_REFS_FILE}"
)
fixture_count=0
for fixture_value in "${fixture_values[@]}"; do
  [[ -n "${fixture_value}" ]] && fixture_count=$((fixture_count + 1))
done
if [[ "${fixture_count}" -ne 0 && "${fixture_count}" -ne "${#fixture_values[@]}" ]]; then
  echo "error: governance fixture mode requires all eight fixture files" >&2
  exit 64
fi
FIXTURE_MODE=0
[[ "${fixture_count}" -eq "${#fixture_values[@]}" ]] && FIXTURE_MODE=1
for fixture_value in "${fixture_values[@]}"; do
  if [[ "${FIXTURE_MODE}" == "1" && ! -f "${fixture_value}" ]]; then
    echo "error: governance fixture file is missing: ${fixture_value}" >&2
    exit 66
  fi
done

scratch="$(mktemp -d "${TMPDIR:-/tmp}/vifty-release-governance.XXXXXX")"
cleanup() {
  rm -rf "${scratch}"
  [[ -z "${OUTPUT_TMP}" ]] || rm -f -- "${OUTPUT_TMP}"
}
trap cleanup EXIT
environment_evidence_path="${scratch}/environment.json"
ruleset_evidence_path="${scratch}/ruleset.json"

fetch_live_ruleset_details() {
  local suffix="$1"
  local ruleset_pages_path="${scratch}/rulesets-${suffix}.json"
  local ruleset_ids ruleset_id details_path
  safe_gh api --paginate --slurp \
    --hostname github.com \
    "repos/${REPO}/rulesets?includes_parents=true&per_page=100" > "${ruleset_pages_path}"
  ruleset_ids="$(/usr/bin/ruby -rjson -e '
    pages = JSON.parse(File.read(ARGV.fetch(0)))
    abort("ruleset listing must be paginated arrays") unless pages.is_a?(Array) && pages.all? { |page| page.is_a?(Array) }
    ids = pages.flatten(1).map do |ruleset|
      next unless ruleset["target"] == "tag" && ruleset["enforcement"] == "active"
      id = ruleset["id"]
      abort("active tag ruleset is missing an integer id") unless id.is_a?(Integer) && id.positive?
      id
    end.compact
    puts ids.uniq.sort
  ' "${ruleset_pages_path}")"
  details_paths=()
  while IFS= read -r ruleset_id; do
    [[ -n "${ruleset_id}" ]] || continue
    details_path="${scratch}/ruleset-${suffix}-${ruleset_id}.json"
    safe_gh api --hostname github.com "repos/${REPO}/rulesets/${ruleset_id}" > "${details_path}"
    details_paths+=("${details_path}")
  done <<< "${ruleset_ids}"
}

collect_matching_ruleset_evidence() {
  local details_path candidate_path
  matching_rulesets=()
  for details_path in "$@"; do
    candidate_path="${scratch}/candidate-$(basename "${details_path}")"
    if /usr/bin/ruby -rjson -rtime -e '
      ruleset = JSON.parse(File.read(ARGV.fetch(0)))
      abort("ruleset detail must be an object") unless ruleset.is_a?(Hash)
      repository = ARGV.fetch(1)
      tag = ARGV.fetch(2)
      output = ARGV.fetch(3)
      full_ref = "refs/tags/#{tag}"
      ref_name = ruleset.dig("conditions", "ref_name")
      includes = ref_name.is_a?(Hash) ? ref_name["include"] : nil
      excludes = ref_name.is_a?(Hash) ? ref_name["exclude"] : nil
      bypass = ruleset["bypass_actors"]
      rules = ruleset["rules"]
      updated_at = ruleset["updated_at"]
      current_user_can_bypass = ruleset["current_user_can_bypass"]
      abort("active tag ruleset detail is missing a positive integer id") unless ruleset["id"].is_a?(Integer) && ruleset["id"].positive?
      abort("active tag ruleset detail is missing a name") unless ruleset["name"].is_a?(String) && !ruleset["name"].empty?
      abort("active tag ruleset detail target/enforcement drifted") unless ruleset["target"] == "tag" && ruleset["enforcement"] == "active"
      abort("active tag ruleset ref conditions must contain string include/exclude arrays") unless
        includes.is_a?(Array) && includes.all? { |value| value.is_a?(String) } &&
        excludes.is_a?(Array) && excludes.all? { |value| value.is_a?(String) }
      abort("active tag ruleset bypass_actors must be visible") unless bypass.is_a?(Array)
      abort("active tag ruleset rules must be visible objects") unless
        rules.is_a?(Array) && rules.all? { |rule| rule.is_a?(Hash) && rule["type"].is_a?(String) }
      abort("active tag ruleset updated_at must be an exact ISO-8601 timestamp with timezone") unless
        updated_at.is_a?(String) &&
        updated_at.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})\z/)
      begin
        canonical_updated_at = Time.iso8601(updated_at).utc.iso8601(9)
      rescue ArgumentError
        abort("active tag ruleset updated_at must be a valid ISO-8601 timestamp with timezone")
      end
      abort("active tag ruleset current_user_can_bypass must be visible") unless current_user_can_bypass.is_a?(String)
      rule_types = rules.map { |rule| rule.fetch("type") }.uniq.sort
      exit 10 unless includes == ["refs/tags/v*"] && excludes == []
      matched_includes = includes
      matched_excludes = []
      evidence = {
        "schemaVersion" => 1,
        "repository" => repository,
        "releaseTag" => tag,
        "releaseRef" => full_ref,
        "rulesetID" => ruleset.fetch("id"),
        "rulesetName" => ruleset.fetch("name"),
        "rulesetUpdatedAt" => canonical_updated_at,
        "currentUserCanBypass" => current_user_can_bypass,
        "target" => "tag",
        "enforcement" => "active",
        "matchedIncludePatterns" => matched_includes.sort,
        "excludePatternsVerified" => excludes.is_a?(Array),
        "matchedExcludePatterns" => excludes.is_a?(Array) ? matched_excludes.sort : nil,
        "ruleTypes" => rule_types,
        "bypassActorsVerified" => bypass.is_a?(Array),
        "bypassActors" => bypass.is_a?(Array) ? bypass : nil,
        "preventsUpdate" => bypass.empty? && current_user_can_bypass == "never" && rule_types.include?("update"),
        "preventsDeletion" => bypass.empty? && current_user_can_bypass == "never" && rule_types.include?("deletion"),
        "readOnly" => true
      }
      File.write(output, JSON.pretty_generate(evidence) + "\n")
    ' "${details_path}" "${REPO}" "${TAG}" "${candidate_path}"; then
      matching_rulesets+=("${candidate_path}")
    else
      ruleset_status=$?
      if [[ "${ruleset_status}" -ne 10 ]]; then
        echo "error: active tag ruleset detail is malformed or incomplete: ${details_path}" >&2
        return 1
      fi
    fi
  done
}

require_single_compliant_ruleset() {
  if [[ "${#matching_rulesets[@]}" -ne 1 ]]; then
    echo "error: expected exactly one active tag ruleset whose ref conditions match refs/tags/${TAG}; found ${#matching_rulesets[@]}" >&2
    return 1
  fi
  if ! /usr/bin/ruby -rjson -e '
    evidence = JSON.parse(File.read(ARGV.fetch(0)))
    valid = evidence["excludePatternsVerified"] == true &&
      evidence["matchedIncludePatterns"] == ["refs/tags/v*"] &&
      evidence["matchedExcludePatterns"] == [] &&
      evidence["bypassActorsVerified"] == true &&
      evidence["bypassActors"] == [] &&
      evidence["currentUserCanBypass"] == "never" &&
      evidence["rulesetUpdatedAt"].is_a?(String) &&
      Array(evidence["ruleTypes"]).include?("update") &&
      Array(evidence["ruleTypes"]).include?("deletion") &&
      evidence["preventsUpdate"] == true &&
      evidence["preventsDeletion"] == true
    abort("sole matching tag ruleset lacks visible empty bypass, exclusion, update, or deletion evidence") unless valid
  ' "${matching_rulesets[0]}"; then
    echo "error: sole matching tag ruleset is not a complete no-bypass update/deletion policy" >&2
    return 1
  fi
}

read_exact_remote_tag_ref() {
  local response api_status parsed encoded_body
  EXACT_TAG_HTTP_STATUS=""
  EXACT_TAG_BODY=""
  set +e
  response="$(safe_gh api --hostname github.com --include \
    -H 'Cache-Control: no-cache' \
    -H 'Pragma: no-cache' \
    "repos/${REPO}/git/ref/tags/${TAG}" \
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

require_remote_tag_state() {
  local refs tag_object_json
  if [[ "${FIXTURE_MODE}" == "1" ]]; then
    refs="$(<"${REMOTE_TAG_REFS_FILE}")"
    if [[ -n "${EXPECTED_EXISTING_TAG_OBJECT}" ]]; then
      if ! /usr/bin/ruby -e '
        rows = STDIN.each_line.map(&:strip).reject(&:empty?).map { |line| line.split("\t", -1) }
        expected = ["refs/tags/#{ARGV.fetch(0)}", ARGV.fetch(1), ARGV.fetch(2)]
        abort("fixture exact tag row must be ref, annotated object, and commit") unless rows == [expected]
      ' "${TAG}" "${EXPECTED_EXISTING_TAG_OBJECT}" "${EXPECTED_MAIN}" <<< "${refs}"; then
        echo "error: fixture release tag does not match the exact expected annotated object" >&2
        return 1
      fi
      return 0
    fi
    if [[ -n "$(printf '%s\n' "${refs}" | /usr/bin/awk 'NF { print; exit }')" ]]; then
      echo "error: release tag ${TAG} already exists on ${REPO}; immutable tags cannot be reused" >&2
      return 1
    fi
    return 0
  fi

  if ! read_exact_remote_tag_ref; then
    echo "error: exact release tag state is unknown on ${REPO}" >&2
    return 1
  fi
  if [[ "${EXACT_TAG_HTTP_STATUS}" == "404" ]]; then
    if [[ -n "${EXPECTED_EXISTING_TAG_OBJECT}" ]]; then
      echo "error: expected release tag ${TAG} is absent on ${REPO}" >&2
      return 1
    fi
    return 0
  fi
  if ! /usr/bin/ruby -rjson -e '
    ref = JSON.parse(STDIN.read)
    tag, object = ARGV
    abort("exact release tag ref response must be an object") unless ref.is_a?(Hash)
    abort("exact release tag ref name mismatch") unless ref["ref"] == "refs/tags/#{tag}"
    ref_object = ref["object"]
    abort("exact release tag ref object is malformed") unless
      ref_object.is_a?(Hash) &&
        ref_object["type"] == "tag" &&
        ref_object["sha"].is_a?(String) &&
        ref_object["sha"].match?(/\A[0-9a-f]{40}\z/)
    abort("release tag ref is not the exact annotated object") unless
      object.empty? || ref_object["sha"] == object
  ' "${TAG}" "${EXPECTED_EXISTING_TAG_OBJECT}" <<< "${EXACT_TAG_BODY}"; then
    echo "error: malformed or mismatched exact release tag response from ${REPO}" >&2
    return 1
  fi
  if [[ -z "${EXPECTED_EXISTING_TAG_OBJECT}" ]]; then
    echo "error: release tag ${TAG} already exists on ${REPO}; immutable tags cannot be reused" >&2
    return 1
  fi
  if ! tag_object_json="$(safe_gh api --hostname github.com \
    -H 'Cache-Control: no-cache' \
    -H 'Pragma: no-cache' \
    "repos/${REPO}/git/tags/${EXPECTED_EXISTING_TAG_OBJECT}" 2>/dev/null)"; then
    echo "error: failed to read expected annotated tag object from ${REPO}" >&2
    return 1
  fi
  if ! /usr/bin/ruby -rjson -e '
    tag = JSON.parse(STDIN.read)
    abort("annotated tag object SHA mismatch") unless tag["sha"] == ARGV.fetch(2)
    abort("annotated tag name mismatch") unless tag["tag"] == ARGV.fetch(0)
    abort("annotated tag target mismatch") unless
      tag.dig("object", "type") == "commit" &&
        tag.dig("object", "sha") == ARGV.fetch(1)
  ' "${TAG}" "${EXPECTED_MAIN}" "${EXPECTED_EXISTING_TAG_OBJECT}" <<< "${tag_object_json}"; then
    echo "error: expected annotated tag object does not target exact main commit" >&2
    return 1
  fi
}

if [[ "${FIXTURE_MODE}" == "1" ]]; then
  REPO_JSON="$(<"${REPO_JSON_FILE}")"
  BRANCH_JSON="$(<"${BRANCH_JSON_FILE}")"
  "${ENVIRONMENT_TOOL_PATH}" \
    --repo "${REPO}" \
    --environment "${ENVIRONMENT_NAME}" \
    --branch "${BRANCH_NAME}" \
    --json-file "${ENVIRONMENT_JSON_FILE}" \
    --branch-protection-json-file "${BRANCH_PROTECTION_JSON_FILE}" \
    --output "${environment_evidence_path}" >/dev/null
  "${SECRETS_TOOL_PATH}" \
    --repo "${REPO}" \
    --environment "${ENVIRONMENT_NAME}" \
    --secret-list-file "${REPOSITORY_SECRET_LIST_FILE}" \
    --environment-secret-list-file "${ENVIRONMENT_SECRET_LIST_FILE}" >/dev/null
  fixture_ruleset_dir="${scratch}/fixture-rulesets"
  mkdir -p "${fixture_ruleset_dir}"
  /usr/bin/ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    rulesets = data.is_a?(Array) ? data : [data]
    abort("ruleset fixture must contain at least one detail object") if rulesets.empty?
    abort("ruleset fixture entries must be objects") unless rulesets.all? { |item| item.is_a?(Hash) }
    rulesets.each_with_index do |ruleset, index|
      File.write(File.join(ARGV.fetch(1), format("ruleset-%04d.json", index)), JSON.generate(ruleset) + "\n")
    end
  ' "${RULESET_JSON_FILE}" "${fixture_ruleset_dir}"
  details_paths=("${fixture_ruleset_dir}"/ruleset-*.json)
else
  if [[ -n "${GH_HOST:-}" && "${GH_HOST}" != "github.com" ]]; then
    echo "error: live governance evidence requires github.com, not GH_HOST=${GH_HOST}" >&2
    exit 65
  fi
  if [[ -z "${GH_BIN}" ]]; then
    echo "error: gh CLI is required for live governance evidence" >&2
    exit 65
  fi
  if [[ ! -f "${GH_TOOLCHAIN_VERIFIER_PATH}" || -L "${GH_TOOLCHAIN_VERIFIER_PATH}" ||
        ! -f "${GH_TOOLCHAIN_POLICY_PATH}" || -L "${GH_TOOLCHAIN_POLICY_PATH}" ]]; then
    echo "error: committed release gh toolchain verifier and policy are required" >&2
    exit 65
  fi
  unverified_gh_bin="${GH_BIN}"
  GH_BIN="${scratch}/pinned-gh"
  /usr/bin/ruby "${GH_TOOLCHAIN_VERIFIER_PATH}" \
    --policy "${GH_TOOLCHAIN_POLICY_PATH}" \
    --source "${unverified_gh_bin}" \
    --destination "${GH_BIN}" > "${scratch}/gh-toolchain-verification.json"
  assert_safe_gh_config
  if ! ACTOR_JSON="$(safe_gh api --hostname github.com user 2>/dev/null)"; then
    echo "error: authenticated GitHub actor identity is unreadable" >&2
    exit 65
  fi
  if ! REPO_JSON="$(safe_gh api --hostname github.com "repos/${REPO}" 2>/dev/null)"; then
    echo "error: repository ${REPO} is unreadable" >&2
    exit 65
  fi
  if ! BRANCH_JSON="$(safe_gh api --hostname github.com "repos/${REPO}/branches/${BRANCH_NAME}" 2>/dev/null)"; then
    echo "error: release branch ${REPO}@${BRANCH_NAME} is unreadable" >&2
    exit 65
  fi
  run_pinned_tool_with_token "${ENVIRONMENT_TOOL_PATH}" \
    --repo "${REPO}" \
    --environment "${ENVIRONMENT_NAME}" \
    --branch "${BRANCH_NAME}" \
    --output "${environment_evidence_path}" >/dev/null
  run_pinned_tool_with_token "${SECRETS_TOOL_PATH}" \
    --repo "${REPO}" \
    --environment "${ENVIRONMENT_NAME}" >/dev/null

  fetch_live_ruleset_details initial
fi

if ! collect_matching_ruleset_evidence "${details_paths[@]}"; then
  exit 65
fi
if ! require_single_compliant_ruleset; then
  exit 65
fi

observation_started_at="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ "${FIXTURE_MODE}" == "0" ]]; then
  run_pinned_tool_with_token "${ENVIRONMENT_TOOL_PATH}" \
    --repo "${REPO}" \
    --environment "${ENVIRONMENT_NAME}" \
    --branch "${BRANCH_NAME}" \
    --output "${environment_evidence_path}" >/dev/null
  run_pinned_tool_with_token "${SECRETS_TOOL_PATH}" \
    --repo "${REPO}" \
    --environment "${ENVIRONMENT_NAME}" >/dev/null
  fetch_live_ruleset_details final
  if ! collect_matching_ruleset_evidence "${details_paths[@]}"; then
    exit 65
  fi
  if ! require_single_compliant_ruleset; then
    exit 65
  fi
  if ! ACTOR_JSON="$(safe_gh api --hostname github.com user 2>/dev/null)" ||
     ! REPO_JSON="$(safe_gh api --hostname github.com "repos/${REPO}" 2>/dev/null)" ||
     ! BRANCH_JSON="$(safe_gh api --hostname github.com "repos/${REPO}/branches/${BRANCH_NAME}" 2>/dev/null)"; then
    echo "error: final administrator governance identity/main readback failed" >&2
    exit 65
  fi
fi

if ! require_remote_tag_state; then
  exit 65
fi

if ! /usr/bin/ruby -rjson -e '
  repo = JSON.parse(ARGV.fetch(0))
  branch = JSON.parse(ARGV.fetch(1))
  expected_sha = ARGV.fetch(2)
  expected_repo = ARGV.fetch(3)
  fixture_mode = ARGV.fetch(4) == "1"
  actor = fixture_mode ? nil : JSON.parse(ARGV.fetch(5))
  abort("repository identity does not match #{expected_repo}") unless repo["full_name"] == expected_repo
  abort("authenticated actor must have repository administrator visibility") unless repo.dig("permissions", "admin") == true
  abort("release branch does not bind expected main commit") unless branch.dig("commit", "sha") == expected_sha
  unless fixture_mode
    abort("authenticated actor id must be a positive integer") unless actor["id"].is_a?(Integer) && actor["id"].positive?
    abort("authenticated actor login must be non-empty") unless actor["login"].is_a?(String) && !actor["login"].empty?
  end
' "${REPO_JSON}" "${BRANCH_JSON}" "${EXPECTED_MAIN}" "${REPO}" "${FIXTURE_MODE}" "${ACTOR_JSON}"; then
  echo "error: administrator governance identity/main check failed" >&2
  exit 65
fi

cp "${matching_rulesets[0]}" "${ruleset_evidence_path}"

observed_at="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
governance_tool_sha="$(/usr/bin/shasum -a 256 "${SELF_PATH}" | /usr/bin/awk '{print $1}')"
environment_tool_sha="$(/usr/bin/shasum -a 256 "${ENVIRONMENT_TOOL_PATH}" | /usr/bin/awk '{print $1}')"
secrets_tool_sha="$(/usr/bin/shasum -a 256 "${SECRETS_TOOL_PATH}" | /usr/bin/awk '{print $1}')"
gh_verifier_sha="$(/usr/bin/shasum -a 256 "${GH_TOOLCHAIN_VERIFIER_PATH}" | /usr/bin/awk '{print $1}')"
gh_policy_sha="$(/usr/bin/shasum -a 256 "${GH_TOOLCHAIN_POLICY_PATH}" | /usr/bin/awk '{print $1}')"
NORMALIZED="$(/usr/bin/ruby -rjson -e '
  environment = JSON.parse(File.read(ARGV.fetch(0)))
  ruleset = JSON.parse(File.read(ARGV.fetch(1)))
  fixture_mode = ARGV.fetch(8) == "1"
  existing_tag_object = ARGV.fetch(11)
  posttag_mode = !existing_tag_object.empty?
  actor = fixture_mode ? nil : JSON.parse(ARGV.fetch(14))
  puts JSON.pretty_generate({
    "schemaVersion" => 1,
    "status" => fixture_mode ? "test-fixture" : "passed",
    "releaseAuthorized" => !fixture_mode,
    "evidenceScope" => posttag_mode ? "administrator-posttag" : "administrator-pretag",
    "apiHost" => "github.com",
    "dataSource" => fixture_mode ? "test-fixture" : "github-api-live",
    "liveAuthenticatedGitHubReadback" => !fixture_mode,
    "repository" => ARGV.fetch(2),
    "releaseTag" => ARGV.fetch(3),
    "expectedMainSHA" => ARGV.fetch(4),
    "observationStartedAt" => ARGV.fetch(5),
    "observedAt" => ARGV.fetch(6),
    "repositoryAdminVerified" => !fixture_mode,
    "authenticatedActor" => actor && {
      "id" => actor.fetch("id"),
      "login" => actor.fetch("login")
    },
    "tagAbsentVerified" => !fixture_mode && !posttag_mode,
    "existingTagVerified" => !fixture_mode && posttag_mode,
    "existingTagObjectSHA" => posttag_mode ? existing_tag_object : nil,
    "governanceTool" => {
      "path" => "scripts/check-release-governance.sh",
      "sha256" => ARGV.fetch(7)
    },
    "governanceDependencies" => [
      {
        "path" => "scripts/check-release-environment.sh",
        "sha256" => ARGV.fetch(9)
      },
      {
        "path" => "scripts/check-release-secrets.sh",
        "sha256" => ARGV.fetch(10)
      },
      {
        "path" => "scripts/verify-release-gh-toolchain.rb",
        "sha256" => ARGV.fetch(12)
      },
      {
        "path" => ".github/release-gh-toolchain.json",
        "sha256" => ARGV.fetch(13)
      }
    ],
    "releaseEnvironmentEvidence" => environment,
    "tagRulesetEvidence" => ruleset,
    "releaseSecrets" => {
      "storageScope" => "repository",
      "requiredNamesVerified" => !fixture_mode,
      "environmentShadowNames" => [],
      "valuesRead" => false
    },
    "readOnly" => true
  })
  ' "${environment_evidence_path}" "${ruleset_evidence_path}" "${REPO}" "${TAG}" "${EXPECTED_MAIN}" "${observation_started_at}" "${observed_at}" "${governance_tool_sha}" "${FIXTURE_MODE}" "${environment_tool_sha}" "${secrets_tool_sha}" "${EXPECTED_EXISTING_TAG_OBJECT}" "${gh_verifier_sha}" "${gh_policy_sha}" "${ACTOR_JSON}")"

if [[ -n "${OUTPUT_PATH}" ]]; then
  output_dir="$(dirname "${OUTPUT_PATH}")"
  output_base="$(basename "${OUTPUT_PATH}")"
  OUTPUT_TMP="$(mktemp "${output_dir}/.${output_base}.tmp.XXXXXX")"
  printf '%s\n' "${NORMALIZED}" > "${OUTPUT_TMP}"
  if [[ -L "${OUTPUT_PATH}" || ( -e "${OUTPUT_PATH}" && ! -f "${OUTPUT_PATH}" ) ]]; then
    echo "error: governance output changed to an unsafe path before commit" >&2
    exit 65
  fi
  mv -f -- "${OUTPUT_TMP}" "${OUTPUT_PATH}"
  OUTPUT_TMP=""
fi
printf '%s\n' "${NORMALIZED}"
