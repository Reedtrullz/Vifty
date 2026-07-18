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
    VIFTY_RELEASE_PROVENANCE_ROOT="${VIFTY_RELEASE_PROVENANCE_ROOT:-}" \
    VIFTY_RELEASE_MANIFEST_BASE_REF="${VIFTY_RELEASE_MANIFEST_BASE_REF:-}" \
    VIFTY_REQUIRE_RELEASE_MANIFEST_BASE="${VIFTY_REQUIRE_RELEASE_MANIFEST_BASE:-}" \
    VIFTY_RELEASE_SOURCE_REPOSITORY_ROOT="${VIFTY_RELEASE_SOURCE_REPOSITORY_ROOT:-}" \
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
  unset INHERITED_GH_TOKEN GH_TOKEN GITHUB_TOKEN
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
ROOT_DIR="${VIFTY_RELEASE_PROVENANCE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
TAG=""
REPO="Reedtrullz/Vifty"
MAIN_REF="origin/main"
TRUSTED_WORKFLOW_REF=""
MANIFEST_PATH="${ROOT_DIR}/.github/release-manifest.json"
ALLOWED_SIGNERS_PATH="${ROOT_DIR}/.github/release-signers.allowed"
CI_RUNS_FILE=""
REMOTE_REFS_FILE=""
GOVERNANCE_EVIDENCE_OUTPUT=""
SKIP_SIGNATURE_FOR_FIXTURE=0
REQUIRE_CURRENT_GOVERNANCE_FRESHNESS=0
JSON_OUTPUT=0
GOVERNANCE_VALIDATOR_PATH="${ROOT_DIR}/scripts/validate-release-governance-evidence.rb"
OUTPUT_TMP=""
OUTPUT_WRITTEN=0
INVOCATION_DIR="$(pwd -P)"
REMOTE_READBACK_ATTEMPTS=30
REMOTE_READBACK_DELAY_SECONDS=2

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-provenance.sh --tag <signed-tag> [options]

Options:
  --repo <owner/repo>          GitHub repository (default: Reedtrullz/Vifty).
  --main-ref <ref>             Fetched intended main ref (default: origin/main).
  --trusted-workflow-ref <ref> Require the checker worktree itself to remain at
                               this trusted workflow ref instead of the tag.
  --manifest <path>            Release manifest path.
  --allowed-signers <path>     Public SSH allowed-signers file.
  --ci-runs-file <path>        Test/offline gh run-list JSON fixture.
  --remote-refs-file <path>    Test/offline remote tag JSON fixture.
  --governance-evidence-output <path>
                               Copy the exact validated signed evidence bytes.
  --skip-signature-for-fixture Test-only; requires both fixture files.
  --require-current-governance-freshness
                               Require the signed administrator evidence to be
                               no more than 15 minutes old when this check runs.
  --json                       Emit a machine-readable summary.

The live path is read-only against GitHub. It verifies an annotated SSH-signed
tag against the checked-in public signer, exact remote tag object/commit parity,
ancestry from the supplied main ref, successful CI at the exact commit, and manifest +
Info.plist version/build agreement. It does not infer environment protection.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --main-ref)
      MAIN_REF="${2:-}"
      shift 2
      ;;
    --trusted-workflow-ref)
      TRUSTED_WORKFLOW_REF="${2:-}"
      shift 2
      ;;
    --manifest)
      MANIFEST_PATH="${2:-}"
      shift 2
      ;;
    --allowed-signers)
      ALLOWED_SIGNERS_PATH="${2:-}"
      shift 2
      ;;
    --ci-runs-file)
      CI_RUNS_FILE="${2:-}"
      shift 2
      ;;
    --remote-refs-file)
      REMOTE_REFS_FILE="${2:-}"
      shift 2
      ;;
    --governance-evidence-output)
      GOVERNANCE_EVIDENCE_OUTPUT="${2:-}"
      shift 2
      ;;
    --skip-signature-for-fixture)
      SKIP_SIGNATURE_FOR_FIXTURE=1
      shift
      ;;
    --require-current-governance-freshness)
      REQUIRE_CURRENT_GOVERNANCE_FRESHNESS=1
      shift
      ;;
    --json)
      JSON_OUTPUT=1
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

for input_name in MANIFEST_PATH ALLOWED_SIGNERS_PATH GOVERNANCE_VALIDATOR_PATH CI_RUNS_FILE REMOTE_REFS_FILE; do
  input_value="${!input_name:-}"
  if [[ -n "${input_value}" && "${input_value}" != /* ]]; then
    printf -v "${input_name}" '%s/%s' "${INVOCATION_DIR}" "${input_value}"
  fi
done

cd "${ROOT_DIR}"
ROOT_DIR="$(pwd -P)"

canonical_existing_path() {
  local path="$1"
  local parent base
  [[ -e "${path}" || -L "${path}" ]] || return 1
  parent="$(cd "$(dirname "${path}")" && pwd -P)" || return 1
  base="$(basename "${path}")"
  printf '%s/%s\n' "${parent}" "${base}"
}

prepare_governance_output() {
  local requested="$1"
  local requested_parent output_parent output_base git_dir git_common relative protected_path canonical_protected
  [[ -n "${requested}" ]] || return 0
  if [[ "${requested}" != /* ]]; then
    requested="${INVOCATION_DIR}/${requested}"
  fi
  requested_parent="$(dirname "${requested}")"
  output_base="$(basename "${requested}")"
  if [[ ! -d "${requested_parent}" || "${output_base}" == "." || "${output_base}" == ".." ]]; then
    echo "error: governance evidence output parent must already be a real directory" >&2
    exit 66
  fi
  output_parent="$(cd "${requested_parent}" && pwd -P)"
  GOVERNANCE_EVIDENCE_OUTPUT="${output_parent}/${output_base}"
  git_dir="$("${GIT_BIN}" rev-parse --path-format=absolute --absolute-git-dir 2>/dev/null || true)"
  git_common="$("${GIT_BIN}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -z "${git_dir}" || -z "${git_common}" ]]; then
    echo "error: release provenance root must be a Git worktree" >&2
    exit 65
  fi
  case "${GOVERNANCE_EVIDENCE_OUTPUT}" in
    "${git_dir}"|"${git_dir}"/*|"${git_common}"|"${git_common}"/*)
      echo "error: governance evidence output must not be inside Git metadata" >&2
      exit 65
      ;;
  esac
  case "${GOVERNANCE_EVIDENCE_OUTPUT}" in
    "${ROOT_DIR}"/*)
      relative="${GOVERNANCE_EVIDENCE_OUTPUT#"${ROOT_DIR}/"}"
      if "${GIT_BIN}" ls-files --error-unmatch -- "${relative}" >/dev/null 2>&1; then
        echo "error: governance evidence output must not replace a tracked worktree path" >&2
        exit 65
      fi
      ;;
  esac
  for protected_path in \
    "${MANIFEST_PATH}" "${ALLOWED_SIGNERS_PATH}" "${GOVERNANCE_VALIDATOR_PATH}" \
    "${CI_RUNS_FILE}" "${REMOTE_REFS_FILE}"; do
    [[ -n "${protected_path}" ]] || continue
    canonical_protected="$(canonical_existing_path "${protected_path}" 2>/dev/null || true)"
    if [[ -n "${canonical_protected}" && "${GOVERNANCE_EVIDENCE_OUTPUT}" == "${canonical_protected}" ]]; then
      echo "error: governance evidence output must not replace a provenance input" >&2
      exit 65
    fi
  done
  if [[ -L "${GOVERNANCE_EVIDENCE_OUTPUT}" ||
        ( -e "${GOVERNANCE_EVIDENCE_OUTPUT}" && ! -f "${GOVERNANCE_EVIDENCE_OUTPUT}" ) ]]; then
    echo "error: governance evidence output must be a regular non-symlink file" >&2
    exit 65
  fi
  rm -f -- "${GOVERNANCE_EVIDENCE_OUTPUT}"
}

prepare_governance_output "${GOVERNANCE_EVIDENCE_OUTPUT}"

if [[ ! "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: --tag must be v<major>.<minor>.<patch>" >&2
  exit 64
fi
if [[ ! -f "${MANIFEST_PATH}" || ! -f "${ALLOWED_SIGNERS_PATH}" || ! -f "${GOVERNANCE_VALIDATOR_PATH}" ]]; then
  echo "error: manifest, allowed-signers, and governance validator files are required" >&2
  exit 66
fi
fixture_count=0
[[ -n "${CI_RUNS_FILE}" ]] && fixture_count=$((fixture_count + 1))
[[ -n "${REMOTE_REFS_FILE}" ]] && fixture_count=$((fixture_count + 1))
if [[ "${fixture_count}" -ne 0 && "${fixture_count}" -ne 2 ]]; then
  echo "error: provenance fixture mode requires both CI and remote-ref fixtures" >&2
  exit 64
fi
FIXTURE_MODE=0
[[ "${fixture_count}" -eq 2 ]] && FIXTURE_MODE=1
if [[ "${SKIP_SIGNATURE_FOR_FIXTURE}" != "${FIXTURE_MODE}" ]]; then
  echo "error: fixture files and --skip-signature-for-fixture must be supplied together" >&2
  exit 64
fi
if [[ "${FIXTURE_MODE}" == "1" ]]; then
  for fixture_path in "${CI_RUNS_FILE}" "${REMOTE_REFS_FILE}"; do
    if [[ ! -f "${fixture_path}" || -L "${fixture_path}" ]]; then
      echo "error: provenance fixture must be a regular file: ${fixture_path}" >&2
      exit 66
    fi
    fixture_bytes="$(/usr/bin/wc -c < "${fixture_path}" | /usr/bin/tr -d '[:space:]')"
    if [[ ! "${fixture_bytes}" =~ ^[0-9]+$ || "${fixture_bytes}" -eq 0 || "${fixture_bytes}" -gt 1048576 ]]; then
      echo "error: provenance fixture must contain between 1 and 1048576 bytes: ${fixture_path}" >&2
      exit 65
    fi
  done
fi
if [[ "${FIXTURE_MODE}" == "0" && -n "${GH_HOST:-}" && "${GH_HOST}" != "github.com" ]]; then
  echo "error: live release provenance requires github.com, not GH_HOST=${GH_HOST}" >&2
  exit 65
fi
VERSION="${TAG#v}"

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_COUNT=7
export GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null
export GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1=false
export GIT_CONFIG_KEY_2=core.untrackedCache GIT_CONFIG_VALUE_2=false
export GIT_CONFIG_KEY_3=core.attributesFile GIT_CONFIG_VALUE_3=/dev/null
export GIT_CONFIG_KEY_4=core.excludesFile GIT_CONFIG_VALUE_4=/dev/null
export GIT_CONFIG_KEY_5=core.worktree GIT_CONFIG_VALUE_5="${ROOT_DIR}"
export GIT_CONFIG_KEY_6=core.bare GIT_CONFIG_VALUE_6=false

scratch="$(mktemp -d "${TMPDIR:-/tmp}/vifty-release-provenance.XXXXXX")"
cleanup() {
  local status=$?
  rm -rf "${scratch}"
  [[ -z "${OUTPUT_TMP}" ]] || rm -f -- "${OUTPUT_TMP}"
  if [[ "${status}" -ne 0 && "${OUTPUT_WRITTEN}" == "1" ]]; then
    rm -f -- "${GOVERNANCE_EVIDENCE_OUTPUT}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

TAG_COMMIT="$("${GIT_BIN}" rev-parse "${TAG}^{commit}" 2>/dev/null || true)"
TAG_OBJECT="$("${GIT_BIN}" rev-parse "${TAG}^{tag}" 2>/dev/null || true)"
if [[ ! "${TAG_COMMIT}" =~ ^[0-9a-f]{40}$ || ! "${TAG_OBJECT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: ${TAG} must be a local annotated tag" >&2
  exit 65
fi
CHECKOUT_COMMIT="$("${GIT_BIN}" rev-parse "HEAD^{commit}" 2>/dev/null || true)"
if [[ -n "${TRUSTED_WORKFLOW_REF}" ]]; then
  TRUSTED_WORKFLOW_COMMIT="$("${GIT_BIN}" rev-parse "${TRUSTED_WORKFLOW_REF}^{commit}" 2>/dev/null || true)"
  if [[ ! "${TRUSTED_WORKFLOW_COMMIT}" =~ ^[0-9a-f]{40}$ || "${CHECKOUT_COMMIT}" != "${TRUSTED_WORKFLOW_COMMIT}" ]]; then
    echo "error: checker worktree ${CHECKOUT_COMMIT:-missing} does not match trusted workflow ref ${TRUSTED_WORKFLOW_REF}" >&2
    exit 65
  fi
  if [[ "${TRUSTED_WORKFLOW_COMMIT}" != "${TAG_COMMIT}" ]]; then
    echo "error: trusted workflow ref ${TRUSTED_WORKFLOW_REF} must resolve to exact signed tag commit ${TAG_COMMIT}" >&2
    exit 65
  fi
elif [[ "${CHECKOUT_COMMIT}" != "${TAG_COMMIT}" ]]; then
  echo "error: checked-out commit ${CHECKOUT_COMMIT:-missing} does not match ${TAG} commit ${TAG_COMMIT}" >&2
  exit 65
fi

if ! "${GIT_BIN}" diff --no-ext-diff --quiet --ignore-submodules -- ||
   ! "${GIT_BIN}" diff --no-ext-diff --cached --quiet --ignore-submodules --; then
  echo "error: release provenance requires no tracked or staged worktree changes" >&2
  exit 65
fi

PARENT_COMMIT="$("${GIT_BIN}" rev-parse --verify "${TAG_COMMIT}^" 2>/dev/null || true)"
if [[ ! "${PARENT_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: signed tag commit must have a trusted first parent" >&2
  exit 65
fi

COMMITTED_ROOT="${scratch}/committed-source"
mkdir -p "${COMMITTED_ROOT}"
if ! "${GIT_BIN}" archive --format=tar "${TAG_COMMIT}" |
  /usr/bin/tar -xf - -C "${COMMITTED_ROOT}"; then
  echo "error: failed to materialize exact signed-tag source" >&2
  exit 65
fi
for committed_path in \
  ".github/release-signers.allowed" \
  ".github/release-manifest.json" \
  "Resources/Info.plist" \
  "scripts/check-release-manifest.sh" \
  "scripts/validate-release-governance-evidence.rb"; do
  if [[ ! -f "${COMMITTED_ROOT}/${committed_path}" || -L "${COMMITTED_ROOT}/${committed_path}" ]]; then
    echo "error: exact signed-tag source is missing regular file ${committed_path}" >&2
    exit 65
  fi
done

COMMITTED_SIGNERS_PATH="${scratch}/committed-release-signers.allowed"
PARENT_SIGNERS_PATH="${scratch}/parent-release-signers.allowed"
if ! "${GIT_BIN}" show "${TAG_COMMIT}:.github/release-signers.allowed" > "${COMMITTED_SIGNERS_PATH}" 2>/dev/null ||
   ! "${GIT_BIN}" show "${PARENT_COMMIT}:.github/release-signers.allowed" > "${PARENT_SIGNERS_PATH}" 2>/dev/null; then
  echo "error: signed tag commit does not contain .github/release-signers.allowed" >&2
  exit 65
fi
if ! /usr/bin/cmp -s "${COMMITTED_SIGNERS_PATH}" "${PARENT_SIGNERS_PATH}"; then
  echo "error: release signer policy changed from the exact first parent" >&2
  exit 65
fi
if ! /usr/bin/cmp -s "${ALLOWED_SIGNERS_PATH}" "${COMMITTED_SIGNERS_PATH}" ||
   ! /usr/bin/cmp -s "${MANIFEST_PATH}" "${COMMITTED_ROOT}/.github/release-manifest.json"; then
  echo "error: caller release policy inputs do not match exact signed tag commit" >&2
  exit 65
fi

if [[ "${SKIP_SIGNATURE_FOR_FIXTURE}" != "1" ]]; then
  if ! "${GIT_BIN}" -c gpg.format=ssh -c gpg.ssh.program=/usr/bin/ssh-keygen -c gpg.ssh.allowedSignersFile="${COMMITTED_SIGNERS_PATH}" verify-tag "${TAG_OBJECT}" >/dev/null; then
    echo "error: ${TAG} did not verify against ${ALLOWED_SIGNERS_PATH}" >&2
    exit 65
  fi
fi

VIFTY_RELEASE_MANIFEST_ROOT="${COMMITTED_ROOT}" \
  VIFTY_RELEASE_SOURCE_REPOSITORY_ROOT="${ROOT_DIR}" \
  "${COMMITTED_ROOT}/scripts/check-release-manifest.sh" \
    --publication-version "${VERSION}" \
    --base-ref "${PARENT_COMMIT}" \
    --require-base >/dev/null

TAG_OBJECT_PATH="${scratch}/annotated-tag.txt"
GOVERNANCE_EVIDENCE_PATH="${scratch}/administrator-governance.json"
GOVERNANCE_VALIDATION_PATH="${scratch}/administrator-governance-validation.json"
"${GIT_BIN}" cat-file tag "${TAG_OBJECT}" > "${TAG_OBJECT_PATH}"
TAGGER_TIME="$(/usr/bin/ruby -rtime -e '
  raw = File.binread(ARGV.fetch(0))
  header, body = raw.split("\n\n", 2)
  abort("annotated tag header/body is missing") unless header && body
  object_lines = header.lines.select { |line| line.start_with?("object ") }
  type_lines = header.lines.select { |line| line.start_with?("type ") }
  tag_lines = header.lines.select { |line| line.start_with?("tag ") }
  abort("annotated tag object header mismatch") unless object_lines == ["object #{ARGV.fetch(1)}\n"]
  abort("annotated tag must point directly to a commit") unless type_lines == ["type commit\n"]
  abort("annotated tag internal name mismatch") unless tag_lines == ["tag #{ARGV.fetch(2)}\n"]
  tagger = header.lines.find { |line| line.start_with?("tagger ") }
  match = tagger&.match(/ (\d+) [+-]\d{4}\n?\z/)
  abort("annotated tagger timestamp is missing") unless match
  puts Time.at(Integer(match[1], 10)).utc.iso8601
' "${TAG_OBJECT_PATH}" "${TAG_COMMIT}" "${TAG}")"
if ! /usr/bin/ruby -rbase64 -e '
  raw = File.binread(ARGV.fetch(0))
  _header, body = raw.split("\n\n", 2)
  abort("annotated tag body is missing") unless body
  prefix = "Vifty-Release-Governance-Base64: "
  fields = body.lines.select { |line| line.start_with?(prefix) }
  abort("signed tag must contain exactly one governance evidence field") unless fields.length == 1
  line = fields.fetch(0)
  abort("governance evidence field must occupy one complete line") unless line.end_with?("\n")
  encoded = line.delete_suffix("\n").delete_suffix("\r").delete_prefix(prefix)
  abort("governance evidence field must use strict base64") unless Base64.strict_encode64(Base64.strict_decode64(encoded)) == encoded
  File.binwrite(ARGV.fetch(1), Base64.strict_decode64(encoded))
' "${TAG_OBJECT_PATH}" "${GOVERNANCE_EVIDENCE_PATH}"; then
  echo "error: ${TAG} does not carry one valid signed administrator-governance evidence field" >&2
  exit 65
fi
/usr/bin/ruby "${COMMITTED_ROOT}/scripts/validate-release-governance-evidence.rb" \
  --root "${ROOT_DIR}" \
  --evidence "${GOVERNANCE_EVIDENCE_PATH}" \
  --repository "${REPO}" \
  --tag "${TAG}" \
  --commit "${TAG_COMMIT}" \
  --tagger-time "${TAGGER_TIME}" \
  > "${GOVERNANCE_VALIDATION_PATH}"

read_github_get_response() {
  local endpoint="$1"
  local response api_status parsed parse_status encoded_body
  GITHUB_GET_HTTP_STATUS=""
  GITHUB_GET_BODY=""
  GITHUB_GET_CLASS="transient"

  if response="$(safe_gh api --hostname github.com --include \
    -H 'Cache-Control: no-cache' \
    -H 'Pragma: no-cache' \
    "${endpoint}" 2>"${scratch}/remote-readback.stderr")"; then
    api_status=0
  else
    api_status=$?
  fi

  if parsed="$(/usr/bin/ruby -rbase64 -e '
    response = STDIN.read
    statuses = []
    response.to_enum(:scan, /^HTTP\/\S+\s+(\d{3})[^\r\n]*\r?$/).each do
      match = Regexp.last_match
      statuses << [match[1], match.end(0)]
    end
    exit 2 unless statuses.length == 1
    status, status_end = statuses.fetch(0)
    separator = response.match(/\r?\n\r?\n/, status_end)
    body = separator ? response.byteslice(separator.end(0)..) : ""
    exit 2 if status == "200" && body.empty?
    print status, "\t", Base64.strict_encode64(body)
  ' <<< "${response}")"; then
    parse_status=0
  else
    parse_status=$?
  fi
  if [[ "${parse_status}" -ne 0 ]]; then
    return 2
  fi

  GITHUB_GET_HTTP_STATUS="${parsed%%$'\t'*}"
  encoded_body="${parsed#*$'\t'}"
  GITHUB_GET_BODY="$(/usr/bin/ruby -rbase64 -e \
    'print Base64.strict_decode64(ARGV.fetch(0))' "${encoded_body}")"

  if [[ "${api_status}" -eq 0 && "${GITHUB_GET_HTTP_STATUS}" == "200" ]]; then
    GITHUB_GET_CLASS="success"
    return 0
  fi
  case "${GITHUB_GET_HTTP_STATUS}" in
    200|404|408|409|425|429|5??)
      return 2
      ;;
    *)
      GITHUB_GET_CLASS="fatal-http-${GITHUB_GET_HTTP_STATUS:-unknown}"
      return 3
      ;;
  esac
}

read_remote_tag_identity_once() {
  local read_status parse_status parsed

  if read_github_get_response "repos/${REPO}/git/ref/tags/${TAG}"; then
    read_status=0
  else
    read_status=$?
  fi
  [[ "${read_status}" -eq 0 ]] || return "${read_status}"

  if parsed="$(/usr/bin/ruby -rjson -e '
    begin
      data = JSON.parse(STDIN.read)
    rescue JSON::ParserError
      exit 2
    end
    exit 2 unless data.is_a?(Hash)
    expected_ref, expected_object = ARGV
    ref = data["ref"]
    exit 2 unless ref.is_a?(String)
    exit 1 unless ref == expected_ref
    object = data["object"]
    exit 2 unless object.is_a?(Hash)
    type = object["type"]
    exit 2 unless type.is_a?(String)
    exit 1 unless type == "tag"
    sha = object["sha"]
    exit 2 unless sha.is_a?(String) && sha.match?(/\A[0-9a-f]{40}\z/)
    exit 1 unless sha == expected_object
    print sha
  ' "refs/tags/${TAG}" "${TAG_OBJECT}" <<< "${GITHUB_GET_BODY}")"; then
    parse_status=0
  else
    parse_status=$?
  fi
  [[ "${parse_status}" -eq 0 ]] || return "${parse_status}"
  REMOTE_TAG_OBJECT="${parsed}"

  if read_github_get_response "repos/${REPO}/git/tags/${REMOTE_TAG_OBJECT}"; then
    read_status=0
  else
    read_status=$?
  fi
  [[ "${read_status}" -eq 0 ]] || return "${read_status}"

  if parsed="$(/usr/bin/ruby -rjson -e '
    begin
      data = JSON.parse(STDIN.read)
    rescue JSON::ParserError
      exit 2
    end
    exit 2 unless data.is_a?(Hash)
    expected_name, expected_object, expected_commit = ARGV
    sha = data["sha"]
    exit 2 unless sha.is_a?(String) && sha.match?(/\A[0-9a-f]{40}\z/)
    exit 1 unless sha == expected_object
    name = data["tag"]
    exit 2 unless name.is_a?(String)
    exit 1 unless name == expected_name
    object = data["object"]
    exit 2 unless object.is_a?(Hash)
    type = object["type"]
    exit 2 unless type.is_a?(String)
    exit 1 unless type == "commit"
    commit = object["sha"]
    exit 2 unless commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/)
    exit 1 unless commit == expected_commit
    print commit
  ' "${TAG}" "${TAG_OBJECT}" "${TAG_COMMIT}" <<< "${GITHUB_GET_BODY}")"; then
    parse_status=0
  else
    parse_status=$?
  fi
  [[ "${parse_status}" -eq 0 ]] || return "${parse_status}"
  REMOTE_TAG_COMMIT="${parsed}"
  return 0
}

if [[ -n "${REMOTE_REFS_FILE}" ]]; then
  remote_facts="$(/usr/bin/ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    puts [data.fetch("tagObjectSHA"), data.fetch("tagCommitSHA")].join("\t")
  ' "${REMOTE_REFS_FILE}")"
  IFS=$'\t' read -r REMOTE_TAG_OBJECT REMOTE_TAG_COMMIT <<< "${remote_facts}"
else
  if [[ -z "${GH_BIN}" ]]; then
    echo "error: gh CLI is required for live release provenance" >&2
    exit 65
  fi
  assert_safe_gh_config
  remote_readback_complete=0
  for ((remote_attempt = 1; remote_attempt <= REMOTE_READBACK_ATTEMPTS; remote_attempt++)); do
    if read_remote_tag_identity_once; then
      remote_readback_status=0
    else
      remote_readback_status=$?
    fi
    case "${remote_readback_status}" in
      0)
        remote_readback_complete=1
        break
        ;;
      1)
        echo "error: remote ${TAG} returned a semantic ref, tag-object, or commit mismatch" >&2
        exit 65
        ;;
      3)
        echo "error: remote ${TAG} readback failed with non-retryable ${GITHUB_GET_CLASS}" >&2
        exit 65
        ;;
    esac
    if [[ "${remote_attempt}" -lt "${REMOTE_READBACK_ATTEMPTS}" ]]; then
      /bin/sleep "${REMOTE_READBACK_DELAY_SECONDS}"
    fi
  done
  if [[ "${remote_readback_complete}" != "1" ]]; then
    echo "error: remote ${TAG} did not converge to its exact signed tag object and commit after ${REMOTE_READBACK_ATTEMPTS} bounded read attempts" >&2
    exit 65
  fi
fi
if [[ "${REMOTE_TAG_OBJECT}" != "${TAG_OBJECT}" || "${REMOTE_TAG_COMMIT}" != "${TAG_COMMIT}" ]]; then
  echo "error: remote ${TAG} object/commit does not match local signed tag" >&2
  exit 65
fi

MAIN_REF_COMMIT="$("${GIT_BIN}" rev-parse --verify "${MAIN_REF}^{commit}" 2>/dev/null || true)"
if [[ ! "${MAIN_REF_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: main ref ${MAIN_REF} is unavailable; fetch the intended main ref before checking provenance" >&2
  exit 66
fi
if [[ "${MAIN_REF_COMMIT}" != "${TAG_COMMIT}" ]]; then
  echo "error: main ref ${MAIN_REF} must resolve to exact signed tag commit ${TAG_COMMIT}" >&2
  exit 65
fi

if [[ "${FIXTURE_MODE}" == "1" ]]; then
  CI_RUNS_JSON="$(<"${CI_RUNS_FILE}")"
else
  CI_RUNS_JSON="$(safe_gh run list --repo "github.com/${REPO}" --workflow .github/workflows/ci.yml --limit 100 --json databaseId,headBranch,headSha,status,conclusion,event,url)"
fi
CI_RUN_FACTS="$(/usr/bin/ruby -rjson -e '
  runs = JSON.parse(STDIN.read)
  sha = ARGV.fetch(0)
  run = runs.find do |item|
    item["headSha"] == sha &&
      item["headBranch"] == "main" &&
      item["event"] == "push" &&
      item["status"] == "completed" &&
      item["conclusion"] == "success"
  end
  abort("no successful completed push CI run on main for exact commit #{sha}") unless run
  print [run.fetch("databaseId"), run.fetch("headBranch"), run.fetch("event")].join("\t")
' "${TAG_COMMIT}" <<< "${CI_RUNS_JSON}" 2>/dev/null || true)"
if [[ -z "${CI_RUN_FACTS}" ]]; then
  echo "error: no successful completed push CI run on main for exact commit ${TAG_COMMIT}" >&2
  exit 65
fi
IFS=$'\t' read -r CI_RUN_ID CI_HEAD_BRANCH CI_EVENT <<< "${CI_RUN_FACTS}"

manifest_facts="$(/usr/bin/ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  candidate = data["candidate"] or abort("candidate is null")
  puts [candidate.fetch("version"), candidate.fetch("build")].join("\t")
' "${COMMITTED_ROOT}/.github/release-manifest.json")"
IFS=$'\t' read -r MANIFEST_VERSION MANIFEST_BUILD <<< "${manifest_facts}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${COMMITTED_ROOT}/Resources/Info.plist")"
PLIST_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${COMMITTED_ROOT}/Resources/Info.plist")"
if [[ "${VERSION}" != "${MANIFEST_VERSION}" || "${VERSION}" != "${PLIST_VERSION}" || "${MANIFEST_BUILD}" != "${PLIST_BUILD}" ]]; then
  echo "error: tag, manifest candidate, and Info.plist version/build do not agree" >&2
  exit 65
fi

if [[ "$("${GIT_BIN}" rev-parse --verify "refs/tags/${TAG}^{tag}" 2>/dev/null || true)" != "${TAG_OBJECT}" ]] ||
   [[ "$("${GIT_BIN}" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)" != "${CHECKOUT_COMMIT}" ]] ||
   ! "${GIT_BIN}" diff --no-ext-diff --quiet --ignore-submodules -- ||
   ! "${GIT_BIN}" diff --no-ext-diff --cached --quiet --ignore-submodules -- ||
   ! /usr/bin/cmp -s "${ALLOWED_SIGNERS_PATH}" "${COMMITTED_SIGNERS_PATH}" ||
   ! /usr/bin/cmp -s "${MANIFEST_PATH}" "${COMMITTED_ROOT}/.github/release-manifest.json"; then
  echo "error: local tag, checkout, or release policy inputs changed during provenance verification" >&2
  exit 65
fi

if [[ "${REQUIRE_CURRENT_GOVERNANCE_FRESHNESS}" == "1" ]]; then
  FINAL_VALIDATION_TIME="$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  /usr/bin/ruby "${COMMITTED_ROOT}/scripts/validate-release-governance-evidence.rb" \
    --root "${ROOT_DIR}" \
    --evidence "${GOVERNANCE_EVIDENCE_PATH}" \
    --repository "${REPO}" \
    --tag "${TAG}" \
    --commit "${TAG_COMMIT}" \
    --tagger-time "${TAGGER_TIME}" \
    --current-time "${FINAL_VALIDATION_TIME}" > "${GOVERNANCE_VALIDATION_PATH}"
fi

if [[ -n "${GOVERNANCE_EVIDENCE_OUTPUT}" ]]; then
  output_dir="$(dirname "${GOVERNANCE_EVIDENCE_OUTPUT}")"
  output_base="$(basename "${GOVERNANCE_EVIDENCE_OUTPUT}")"
  OUTPUT_TMP="$(mktemp "${output_dir}/.${output_base}.tmp.XXXXXX")"
  cp "${GOVERNANCE_EVIDENCE_PATH}" "${OUTPUT_TMP}"
  mv -f -- "${OUTPUT_TMP}" "${GOVERNANCE_EVIDENCE_OUTPUT}"
  OUTPUT_TMP=""
  OUTPUT_WRITTEN=1
fi

if [[ "$("${GIT_BIN}" rev-parse --verify "refs/tags/${TAG}^{tag}" 2>/dev/null || true)" != "${TAG_OBJECT}" ]] ||
   [[ "$("${GIT_BIN}" rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)" != "${CHECKOUT_COMMIT}" ]] ||
   ! "${GIT_BIN}" diff --no-ext-diff --quiet --ignore-submodules -- ||
   ! "${GIT_BIN}" diff --no-ext-diff --cached --quiet --ignore-submodules -- ||
   ! /usr/bin/cmp -s "${ALLOWED_SIGNERS_PATH}" "${COMMITTED_SIGNERS_PATH}" ||
   ! /usr/bin/cmp -s "${MANIFEST_PATH}" "${COMMITTED_ROOT}/.github/release-manifest.json" ||
   { [[ -n "${GOVERNANCE_EVIDENCE_OUTPUT}" ]] &&
     ! /usr/bin/cmp -s "${GOVERNANCE_EVIDENCE_OUTPUT}" "${GOVERNANCE_EVIDENCE_PATH}"; }; then
  echo "error: local tag, checkout, release policy inputs, or retained evidence changed at completion" >&2
  exit 65
fi

if [[ "${JSON_OUTPUT}" == "1" ]]; then
  /usr/bin/ruby -rjson -e '
    governance_evidence = JSON.parse(File.read(ARGV.fetch(11)))
    governance_validation = JSON.parse(File.read(ARGV.fetch(12)))
    data_source = ARGV.fetch(13)
    puts JSON.pretty_generate({
      "schemaVersion" => 3,
      "status" => data_source == "test-fixture" ? "test-fixture" : "passed",
      "authoritative" => data_source == "github-api-live",
      "dataSource" => data_source,
      "liveRemoteTagReadback" => data_source == "github-api-live",
      "liveSourceCIReadback" => data_source == "github-api-live",
      "tag" => ARGV.fetch(0),
      "tagObjectSHA" => ARGV.fetch(1),
      "tagCommitSHA" => ARGV.fetch(2),
      "checkoutCommitSHA" => ARGV.fetch(3),
      "mainRef" => ARGV.fetch(4),
      "sourceCIRunID" => ARGV.fetch(5).to_i,
      "sourceCIHeadBranch" => ARGV.fetch(6),
      "sourceCIEvent" => ARGV.fetch(7),
      "version" => ARGV.fetch(8),
      "build" => ARGV.fetch(9).to_i,
      "signatureVerified" => ARGV.fetch(10) == "true",
      "administratorGovernanceEvidence" => governance_evidence,
      "administratorGovernanceValidation" => governance_validation,
      "readOnly" => true
    })
  ' "${TAG}" "${TAG_OBJECT}" "${TAG_COMMIT}" "${CHECKOUT_COMMIT}" "${MAIN_REF}" "${CI_RUN_ID}" "${CI_HEAD_BRANCH}" "${CI_EVENT}" "${VERSION}" "${MANIFEST_BUILD}" "$([[ "${SKIP_SIGNATURE_FOR_FIXTURE}" == "1" ]] && echo false || echo true)" "${GOVERNANCE_EVIDENCE_PATH}" "${GOVERNANCE_VALIDATION_PATH}" "$([[ "${FIXTURE_MODE}" == "1" ]] && echo test-fixture || echo github-api-live)"
elif [[ "${FIXTURE_MODE}" == "1" ]]; then
  echo "Release provenance TEST FIXTURE only: ${TAG} ${TAG_COMMIT}, CI fixture ${CI_RUN_ID}, build ${MANIFEST_BUILD}"
else
  echo "Release provenance OK: ${TAG} ${TAG_COMMIT}, CI run ${CI_RUN_ID}, build ${MANIFEST_BUILD}"
fi
