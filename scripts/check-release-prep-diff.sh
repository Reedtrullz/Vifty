#!/bin/bash -p
if [[ "$0" != "vifty-release-clean" ]]; then
  exec /usr/bin/env -i \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    HOME="${HOME:-}" TMPDIR="${TMPDIR:-/tmp}" USER="${USER:-}" LOGNAME="${LOGNAME:-}" \
    /bin/bash -p -c 'source "$1" "${@:2}"' vifty-release-clean "$0" "$@"
fi
set -euo pipefail
umask 077

inherited_functions="$(builtin declare -F)"
if [[ -n "${inherited_functions}" ]]; then
  builtin printf '%s\n' "error: inherited shell functions are not allowed" >&2
  exit 65
fi

for hostile_name in \
  BASH_ENV ENV RUBYOPT RUBYLIB CDPATH \
  GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_REPLACE_REF_BASE \
  GIT_CONFIG GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL GIT_CONFIG_COUNT \
  GIT_CONFIG_PARAMETERS GIT_EXEC_PATH GIT_EXTERNAL_DIFF GIT_DIFF_OPTS; do
  if [[ -n "${!hostile_name:-}" ]]; then
    echo "error: hostile release-prep environment is not allowed: ${hostile_name}" >&2
    exit 65
  fi
done
unset BASH_ENV ENV RUBYOPT RUBYLIB CDPATH

PATH="/usr/bin:/bin:/usr/sbin:/sbin"
export PATH GIT_NO_REPLACE_OBJECTS=1
GIT_BIN="/usr/bin/git"
PLUTIL_BIN="/usr/bin/plutil"
RUBY_BIN="/usr/bin/ruby"
ROOT_DIR=""
COMMIT=""

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-prep-diff.sh --root <repository> --commit <sha>

Requires the release-prep commit to differ from its exact first parent only in
the reviewed candidate manifest, bundle version, changelog, and release-status
prose. All four changes are mandatory. Every build, signing, workflow, source,
entitlement, schema, and release-tool change must land in an earlier reviewed
commit before release prep.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_DIR="${2:-}"; shift 2 ;;
    --commit) COMMIT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

if [[ -z "${ROOT_DIR}" || "${ROOT_DIR}" != /* || ! -d "${ROOT_DIR}" || -L "${ROOT_DIR}" ]]; then
  echo "error: --root must be an absolute real repository directory" >&2
  exit 64
fi
ROOT_DIR="$(cd "${ROOT_DIR}" && pwd -P)"
if [[ ! "${COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: --commit must be a full lowercase commit SHA" >&2
  exit 64
fi

safe_git() {
  GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_SYSTEM=/dev/null \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_COUNT=5 \
    GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
    GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1=false \
    GIT_CONFIG_KEY_2=core.untrackedCache GIT_CONFIG_VALUE_2=false \
    GIT_CONFIG_KEY_3=core.attributesFile GIT_CONFIG_VALUE_3=/dev/null \
    GIT_CONFIG_KEY_4=core.excludesFile GIT_CONFIG_VALUE_4=/dev/null \
    "${GIT_BIN}" -C "${ROOT_DIR}" "$@"
}

if [[ "$(safe_git rev-parse --show-toplevel 2>/dev/null || true)" != "${ROOT_DIR}" ]] ||
   [[ "$(safe_git rev-parse --verify "${COMMIT}^{commit}" 2>/dev/null || true)" != "${COMMIT}" ]]; then
  echo "error: --root and --commit must name the exact repository commit" >&2
  exit 65
fi
PARENT="$(safe_git rev-parse --verify "${COMMIT}^1" 2>/dev/null || true)"
if [[ ! "${PARENT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: release-prep commit must have an exact first parent" >&2
  exit 65
fi

scratch="$(mktemp -d "${TMPDIR:-/tmp}/vifty-release-prep-diff.XXXXXX")"
cleanup() {
  local status=$?
  trap - EXIT
  /bin/rm -rf "${scratch}"
  exit "${status}"
}
trap cleanup EXIT
changed_paths="${scratch}/changed-paths.zlist"
safe_git diff-tree --raw --no-commit-id --no-renames -r -z \
  "${PARENT}" "${COMMIT}" -- > "${changed_paths}"

"${RUBY_BIN}" -e '
  fields = File.binread(ARGV.fetch(0)).split("\0", -1)
  fields.pop if fields.last == ""
  abort("error: release-prep raw diff is malformed") unless fields.length.even?
  paths = []
  fields.each_slice(2) do |metadata, path|
    match = metadata.match(/\A:(\d{6}) (\d{6}) ([0-9a-f]{40}) ([0-9a-f]{40}) ([A-Z])\z/)
    abort("error: release-prep raw diff metadata is malformed") unless match
    old_mode, new_mode, old_oid, new_oid, status = match.captures
    abort("error: release-prep path must be a modification: #{path}") unless status == "M"
    abort("error: release-prep path mode/type changed: #{path}") unless
      old_mode == "100644" && new_mode == "100644"
    abort("error: release-prep path lacks regular blobs: #{path}") if
      old_oid == "0" * 40 || new_oid == "0" * 40
    abort("error: release-prep diff contains an empty path") if path.empty?
    paths << path
  end
  abort("error: release-prep diff contains duplicate paths") unless paths.uniq.length == paths.length

  allowed = [
    ".github/release-manifest.json",
    "CHANGELOG.md",
    "Resources/Info.plist",
    "docs/release-status.md"
  ]
  unexpected = paths - allowed
  missing = allowed - paths
  abort("error: release-prep commit changes forbidden paths: #{unexpected.sort.join(", ")}") unless unexpected.empty?
  abort("error: release-prep commit must change: #{missing.join(", ")}") unless missing.empty?
' "${changed_paths}"

parent_plist="${scratch}/parent-info.plist"
current_plist="${scratch}/current-info.plist"
parent_json="${scratch}/parent-info.json"
current_json="${scratch}/current-info.json"

if ! safe_git cat-file blob "${PARENT}:Resources/Info.plist" > "${parent_plist}"; then
  echo "error: could not extract first-parent Resources/Info.plist" >&2
  exit 65
fi
if ! safe_git cat-file blob "${COMMIT}:Resources/Info.plist" > "${current_plist}"; then
  echo "error: could not extract release-prep Resources/Info.plist" >&2
  exit 65
fi
if ! "${PLUTIL_BIN}" -lint -- "${parent_plist}" >/dev/null 2>&1; then
  echo "error: first-parent Resources/Info.plist is malformed" >&2
  exit 65
fi
if ! "${PLUTIL_BIN}" -lint -- "${current_plist}" >/dev/null 2>&1; then
  echo "error: release-prep Resources/Info.plist is malformed" >&2
  exit 65
fi
if ! "${PLUTIL_BIN}" -convert json -o "${parent_json}" -- "${parent_plist}" >/dev/null 2>&1; then
  echo "error: first-parent Resources/Info.plist cannot be normalized" >&2
  exit 65
fi
if ! "${PLUTIL_BIN}" -convert json -o "${current_json}" -- "${current_plist}" >/dev/null 2>&1; then
  echo "error: release-prep Resources/Info.plist cannot be normalized" >&2
  exit 65
fi

"${RUBY_BIN}" -rjson -e '
  parent = JSON.parse(File.binread(ARGV.fetch(0)))
  current = JSON.parse(File.binread(ARGV.fetch(1)))
  abort("error: first-parent Resources/Info.plist must be a dictionary") unless parent.is_a?(Hash)
  abort("error: release-prep Resources/Info.plist must be a dictionary") unless current.is_a?(Hash)

  version_key = "CFBundleShortVersionString"
  build_key = "CFBundleVersion"
  parent_version = parent[version_key]
  current_version = current[version_key]
  parent_build = parent[build_key]
  current_build = current[build_key]

  unless parent_version.is_a?(String) && current_version.is_a?(String)
    abort("error: Resources/Info.plist #{version_key} values must both be strings")
  end
  unless parent_build.is_a?(String) && current_build.is_a?(String)
    abort("error: Resources/Info.plist #{build_key} values must both be strings")
  end
  unless parent_version.match?(/\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/) &&
         current_version.match?(/\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/)
    abort("error: Resources/Info.plist #{version_key} values must be semantic version strings")
  end
  unless parent_build.match?(/\A[1-9]\d*\z/) && current_build.match?(/\A[1-9]\d*\z/)
    abort("error: Resources/Info.plist #{build_key} values must be positive integer strings")
  end
  abort("error: Resources/Info.plist #{version_key} must change") if parent_version == current_version
  abort("error: Resources/Info.plist #{build_key} must change") if parent_build == current_build

  [version_key, build_key].each do |key|
    parent.delete(key)
    current.delete(key)
  end
  unless parent == current
    abort("error: release-prep Resources/Info.plist may change only #{version_key} and #{build_key}")
  end

  puts "Release prep diff OK: .github/release-manifest.json, CHANGELOG.md, Resources/Info.plist, docs/release-status.md"
' "${parent_json}" "${current_json}"
