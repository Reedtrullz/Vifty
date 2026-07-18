#!/bin/bash -p
set -euo pipefail

PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

APP_NAME="Vifty"
INSTALL_MODE="source"
PUBLIC_RELEASE_ARCHIVE=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/install-vifty.sh
  scripts/install-vifty.sh --public-release-archive /absolute/path/Vifty-vX.Y.Z.zip

With no arguments, Vifty builds and installs the current source checkout.
The public-release mode installs only the exact current publishedRelease archive
pinned by .github/release-manifest.json; it accepts no caller-supplied version,
checksum, TeamID, verifier, or trust-skip override.
USAGE
}

case "$#" in
  0) ;;
  1)
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
      usage
      exit 0
    fi
    echo "error: unsupported or incomplete installer arguments." >&2
    usage >&2
    exit 64
    ;;
  2)
    if [[ "$1" != "--public-release-archive" || -z "$2" || "$2" == --* ]]; then
      echo "error: expected --public-release-archive followed by one absolute zip path." >&2
      usage >&2
      exit 64
    fi
    INSTALL_MODE="public-release"
    PUBLIC_RELEASE_ARCHIVE="$2"
    ;;
  *)
    echo "error: unexpected installer arguments." >&2
    usage >&2
    exit 64
    ;;
esac

CONFIGURATION="${CONFIGURATION:-release}"
INSTALL_DIR="${VIFTY_INSTALL_DIR:-/Applications}"
OPEN_AFTER_INSTALL="${OPEN_AFTER_INSTALL:-0}"
QUIT_RUNNING_APP="${QUIT_RUNNING_APP:-1}"
CHECK_HELPER_DAEMON="${CHECK_HELPER_DAEMON:-1}"
HELPER_TARGET="${VIFTY_HELPER_TARGET:-/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon}"
ENABLE_ADHOC_XPC="${VIFTY_ENABLE_ADHOC_XPC:-0}"
FIXTURE_SYSTEM_FALLBACK="${VIFTY_INSTALL_FIXTURE_SYSTEM_FALLBACK:-0}"
FIXTURE_PUBLISHED_V132="${VIFTY_INSTALL_FIXTURE_PUBLISHED_V132:-0}"
FIXTURE_PROTOCOL_V2="${VIFTY_INSTALL_FIXTURE_PROTOCOL_V2:-0}"
FIXTURE_STAGE_MKTEMP_FAILURE="${VIFTY_INSTALL_FIXTURE_STAGE_MKTEMP_FAILURE:-0}"
FIXTURE_SHA256_FAILURE="${VIFTY_INSTALL_FIXTURE_SHA256_FAILURE:-0}"
FIXTURE_ROLLBACK_RESTORE_FAILURE="${VIFTY_INSTALL_FIXTURE_ROLLBACK_RESTORE_FAILURE:-0}"
FIXTURE_POST_SWAP_VERIFICATION_FAILURE="${VIFTY_INSTALL_FIXTURE_POST_SWAP_VERIFICATION_FAILURE:-0}"
FIXTURE_HIDE_PREVIOUS_BEFORE_ROLLBACK="${VIFTY_INSTALL_FIXTURE_HIDE_PREVIOUS_BEFORE_ROLLBACK:-0}"
FIXTURE_UNSIGNED_BUILD="${VIFTY_INSTALL_FIXTURE_UNSIGNED_BUILD:-0}"
FIXTURE_NO_RUNNING_APP="${VIFTY_INSTALL_FIXTURE_NO_RUNNING_APP:-0}"
FIXTURE_MUTATE_LIFECYCLE_AFTER_PREPARE="${VIFTY_INSTALL_FIXTURE_MUTATE_LIFECYCLE_AFTER_PREPARE:-0}"
FIXTURE_ROOT="${VIFTY_INSTALL_FIXTURE_ROOT:-}"
FIXTURE_CONTEXT_VALID=0
MAKE_COMMAND="${VIFTY_MAKE:-make}"
DITTO_COMMAND="${VIFTY_DITTO:-/usr/bin/ditto}"
WAS_RUNNING=0
PUBLIC_RELEASE_VERSION=""
PUBLIC_RELEASE_BUILD=""
PUBLIC_RELEASE_TAG=""
PUBLIC_RELEASE_SOURCE_COMMIT=""
PUBLIC_RELEASE_ARTIFACT_NAME=""
PUBLIC_RELEASE_SHA256=""
PUBLIC_RELEASE_TEAM_ID=""
PUBLIC_RELEASE_ARCHITECTURES=""
PUBLIC_CONTENT_MANIFEST_SHA256=""
PUBLIC_HELPER_SHA256=""
PUBLIC_LIFECYCLE_SHA256=""
PUBLIC_QUARANTINE_HEX=""
PUBLIC_QUARANTINE_STATE=""
PUBLIC_INSTALL_LOCK=""
PUBLIC_INSTALL_LOCK_ROOT=""
PUBLIC_DESTINATION_EXPECTATION=""
PUBLIC_PRECHECK_DESTINATION_EXPECTATION=""
PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256=""

PUBLISHED_V132_VERSION="1.3.2"
PUBLISHED_V132_BUILD="7"
PUBLISHED_V132_TEAM_ID="X88J3853S2"
PUBLISHED_V132_AUTHORITY="Developer ID Application: REIDAR OVERREIN JOESSUND (X88J3853S2)"
PUBLISHED_V132_MAIN_SHA256="10e6ca95faa8167bf81df49bfa7407ad5f8ab3e55cf7720085ec61334897c55e"
PUBLISHED_V132_CTL_SHA256="63d2837795f22a34f1833c9c38a49b2c95d87339262347cca89b0245f7068f3e"
PUBLISHED_V132_DAEMON_SHA256="7543c573528a57bb096b045b9a7476b1d4da4aef88b7cd8b54d4cd2ca5bf7dac"
PUBLISHED_V132_HELPER_SHA256="f081eb5f0f3097d0baf8b96b8655cb038d6b5e8abb406e53192305af31a98cf0"
PUBLISHED_V132_MAIN_CDHASH="666e4972fcb31fa3fcb3134c956daae0bdf62189"
PUBLISHED_V132_CTL_CDHASH="95a55844ba7b4983712c69693ec4c4b80a7e1205"
PUBLISHED_V132_DAEMON_CDHASH="c5613e3020d94de1d141917d7b950fc367a6e61a"
PUBLISHED_V132_HELPER_CDHASH="c5802ef35c7cbeabad37db5657dd20fa95f727ba"
# These executable identities were extracted from the public v1.3.2 archive
# whose immutable zip SHA-256 is also pinned here for review provenance.
PUBLISHED_V132_ARCHIVE_SHA256="8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0"
APP_BUNDLE_ID="tech.reidar.vifty"
DAEMON_BUNDLE_ID="tech.reidar.vifty.daemon"
HELPER_BUNDLE_ID="tech.reidar.vifty.helper"
CTL_BUNDLE_ID="tech.reidar.vifty.ctl"

SCRIPT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && /bin/pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && /bin/pwd -P)"
APP_DIR="${VIFTY_BUILD_APP_PATH:-${ROOT_DIR}/.build/${APP_NAME}.app}"
DEST_APP="${INSTALL_DIR}/${APP_NAME}.app"
HELPER_LIFECYCLE_SOURCE="${VIFTY_HELPER_LIFECYCLE:-${APP_DIR}/Contents/Resources/vifty-helper-lifecycle.sh}"
HELPER_LIFECYCLE_OVERRIDE="${VIFTY_HELPER_LIFECYCLE:-}"
REPLACEMENT_LIFECYCLE_ROOT="${VIFTY_REPLACEMENT_LIFECYCLE_ROOT:-/Library/Application Support/ViftyMaintenanceEvidence/ReplacementTransactions}"
REPLACEMENT_LIFECYCLE_ROOT_OVERRIDE="${VIFTY_REPLACEMENT_LIFECYCLE_ROOT:-}"

validate_fixture_context() {
  [[ "${CONFIGURATION}" == "debug" && -n "${FIXTURE_ROOT}" ]] || return 1
  /usr/bin/ruby -e '
    root, install_dir, app_dir, helper, make_command, ditto_command, lifecycle, lifecycle_root, tmpdir, home, owner_text = ARGV
    owner = Integer(owner_text, 10)
    root_stat = File.lstat(root)
    exit 75 unless root_stat.directory? && !root_stat.symlink? && root_stat.uid == owner &&
      (root_stat.mode & 0777) == 0700
    canonical_root = File.realpath(root)
    allowed_root = canonical_root.start_with?("/private/tmp/vifty-install-preflight-") ||
      (canonical_root.start_with?("/private/var/folders/") && File.basename(canonical_root).start_with?("vifty-install-preflight-"))
    exit 75 unless allowed_root

    install_stat = File.lstat(install_dir)
    exit 75 unless install_stat.directory? && !install_stat.symlink? &&
      File.realpath(install_dir) == File.join(canonical_root, "install")
    app_stat = File.lstat(app_dir)
    exit 75 unless app_stat.directory? && !app_stat.symlink? &&
      File.realpath(app_dir) == File.join(canonical_root, "build", "Vifty.app")
    exit 75 unless File.realpath(helper) == File.join(canonical_root, "installed-helper", "tech.reidar.vifty.daemon")
    exit 75 unless File.realpath(make_command) == File.join(canonical_root, "make")
    exit 75 unless File.realpath(ditto_command) == File.join(canonical_root, "ditto")
    exit 75 unless File.realpath(lifecycle) == File.join(canonical_root, "replacement-lifecycle")
    exit 75 unless File.expand_path(lifecycle_root) == File.join(canonical_root, "root-staged-lifecycle")
    exit 75 unless File.realpath(tmpdir) == canonical_root
    exit 75 unless File.realpath(home) == File.join(canonical_root, "home")
  ' "${FIXTURE_ROOT}" "${INSTALL_DIR}" "${APP_DIR}" "${HELPER_TARGET}" \
    "${MAKE_COMMAND}" "${DITTO_COMMAND}" "${HELPER_LIFECYCLE_SOURCE}" "${REPLACEMENT_LIFECYCLE_ROOT}" \
    "${TMPDIR:-}" "${HOME}" "$(/usr/bin/id -u)"
}

fixture_requested=0
for fixture_value in \
  "${FIXTURE_SYSTEM_FALLBACK}" \
  "${FIXTURE_PUBLISHED_V132}" \
  "${FIXTURE_PROTOCOL_V2}" \
  "${FIXTURE_STAGE_MKTEMP_FAILURE}" \
  "${FIXTURE_SHA256_FAILURE}" \
  "${FIXTURE_ROLLBACK_RESTORE_FAILURE}" \
  "${FIXTURE_POST_SWAP_VERIFICATION_FAILURE}" \
  "${FIXTURE_HIDE_PREVIOUS_BEFORE_ROLLBACK}" \
  "${FIXTURE_UNSIGNED_BUILD}" \
  "${FIXTURE_NO_RUNNING_APP}" \
  "${FIXTURE_MUTATE_LIFECYCLE_AFTER_PREPARE}"; do
  if [[ "${fixture_value}" == "1" ]]; then
    fixture_requested=1
  fi
done
if [[ "${INSTALL_MODE}" == "public-release" ]]; then
  if [[ "${PUBLIC_RELEASE_ARCHIVE}" != /* ]]; then
    echo "error: --public-release-archive requires an absolute path." >&2
    exit 64
  fi
  if [[ "${CONFIGURATION}" != "release" || "${ENABLE_ADHOC_XPC}" != "0" ]]; then
    echo "error: public release archives require CONFIGURATION=release and VIFTY_ENABLE_ADHOC_XPC=0." >&2
    exit 65
  fi
  if [[ "${fixture_requested}" == "1" || -n "${VIFTY_BUILD_APP_PATH+x}" ||
        -n "${VIFTY_MAKE+x}" || -n "${VIFTY_DITTO+x}" || -n "${SWIFT_BUILD_PATH+x}" ||
        -n "${VIFTY_HELPER_LIFECYCLE+x}" || -n "${VIFTY_HELPER_TARGET+x}" ||
        -n "${VIFTY_REPLACEMENT_LIFECYCLE_ROOT+x}" ]]; then
    echo "error: public release archives reject build, helper, copy-tool, lifecycle, and fixture overrides." >&2
    exit 65
  fi
fi
if [[ "${fixture_requested}" == "1" ]]; then
  if ! validate_fixture_context; then
    echo "error: install fixtures require a canonical owner-private VIFTY_INSTALL_FIXTURE_ROOT under the macOS temporary area, with all fixture paths contained inside it." >&2
    exit 65
  fi
  FIXTURE_CONTEXT_VALID=1
fi
if [[ -n "${HELPER_LIFECYCLE_OVERRIDE}" && "${FIXTURE_CONTEXT_VALID}" != "1" ]]; then
  echo "error: VIFTY_HELPER_LIFECYCLE is fixture-only; production installs must execute the lifecycle inside the verified candidate app." >&2
  exit 65
fi
if [[ -n "${REPLACEMENT_LIFECYCLE_ROOT_OVERRIDE}" && "${FIXTURE_CONTEXT_VALID}" != "1" ]]; then
  echo "error: VIFTY_REPLACEMENT_LIFECYCLE_ROOT is fixture-only; production lifecycle staging uses the fixed root-owned evidence directory." >&2
  exit 65
fi

/bin/mkdir -p "${ROOT_DIR}/.build"
RUN_DIR="$(/usr/bin/mktemp -d "${ROOT_DIR}/.build/vifty-install.XXXXXXXX")"
/bin/chmod 700 "${RUN_DIR}"
ERR_LOG="${RUN_DIR}/copy-error.log"
BUILD_LOG="${RUN_DIR}/build.log"
COPY_ROLLBACK_ACTIVE=0
COPY_ROLLBACK_HAD_PREVIOUS=0
COPY_ROLLBACK_NEW_INSTALLED=0
COPY_ROLLBACK_SOURCE=""
COPY_ROLLBACK_DEST=""
COPY_ROLLBACK_PREVIOUS=""
COPY_ROLLBACK_STAGE=""
REPLACEMENT_LIFECYCLE=""
REPLACEMENT_LIFECYCLE_APP=""
REPLACEMENT_AUTHORITY_STATE="not-prepared"
REPLACEMENT_TRANSACTION_ID=""
REPLACEMENT_PREPARE_LIFECYCLE=""
REPLACEMENT_PREPARE_LIFECYCLE_SHA256=""
REPLACEMENT_STAGED_LIFECYCLE=""
REPLACEMENT_FINISH_ALLOWED=0

path_exists_without_following() {
  [[ -e "$1" || -L "$1" ]]
}

rollback_interrupted_copy() {
  [[ "${COPY_ROLLBACK_ACTIVE}" == "1" ]] || return 0
  if [[ -z "${COPY_ROLLBACK_DEST}" || -z "${COPY_ROLLBACK_STAGE}" ||
        "${COPY_ROLLBACK_STAGE}" != "${COPY_ROLLBACK_DEST%/*}/.vifty-install-stage."* ]]; then
    echo "HARD FAILURE: invalid rollback paths; refusing destructive cleanup." >&2
    return 1
  fi
  local rejected_app="${COPY_ROLLBACK_STAGE}/rejected-${APP_NAME}.app"
  if [[ "${COPY_ROLLBACK_HAD_PREVIOUS}" == "1" ]]; then
    local rejected_matches_candidate=1
    if ! path_exists_without_following "${COPY_ROLLBACK_PREVIOUS}"; then
      echo "HARD FAILURE: staged previous app is missing; refusing to accept any destination bundle as a successful rollback. Recovery material and helper authority are preserved at ${COPY_ROLLBACK_STAGE}" >&2
      return 1
    fi
    if path_exists_without_following "${COPY_ROLLBACK_DEST}"; then
      if path_exists_without_following "${rejected_app}" || ! rename_exclusive "${COPY_ROLLBACK_DEST}" "${rejected_app}"; then
        echo "HARD FAILURE: could not isolate the rejected app; previous app preserved at ${COPY_ROLLBACK_PREVIOUS}" >&2
        return 1
      fi
      if [[ "${COPY_ROLLBACK_NEW_INSTALLED}" != "1" || -z "${COPY_ROLLBACK_SOURCE}" ]] ||
         ! verify_candidate_bundle "${rejected_app}" ||
         ! bundles_have_identical_file_bytes "${COPY_ROLLBACK_SOURCE}" "${rejected_app}"; then
        rejected_matches_candidate=0
      fi
    fi
    if [[ "${FIXTURE_ROLLBACK_RESTORE_FAILURE}" == "1" ]] ||
       ! rename_exclusive "${COPY_ROLLBACK_PREVIOUS}" "${COPY_ROLLBACK_DEST}"; then
      echo "HARD FAILURE: could not restore the previous app; recover it from ${COPY_ROLLBACK_PREVIOUS}" >&2
      return 1
    fi
    if [[ "${rejected_matches_candidate}" != "1" ]]; then
      COPY_ROLLBACK_ACTIVE=0
      echo "HARD FAILURE: the previous app was restored, but an unexpected destination bundle is preserved at ${rejected_app}; refusing transaction-stage cleanup." >&2
      return 1
    fi
  elif [[ "${COPY_ROLLBACK_HAD_PREVIOUS}" == "0" &&
          "${COPY_ROLLBACK_NEW_INSTALLED}" == "1" &&
          -n "${COPY_ROLLBACK_DEST}" ]]; then
    if path_exists_without_following "${COPY_ROLLBACK_DEST}"; then
      if path_exists_without_following "${rejected_app}" ||
         ! rename_exclusive "${COPY_ROLLBACK_DEST}" "${rejected_app}"; then
        echo "HARD FAILURE: could not atomically isolate the rejected fresh-install destination; preserving the transaction stage at ${COPY_ROLLBACK_STAGE}" >&2
        return 1
      fi
      if [[ -z "${COPY_ROLLBACK_SOURCE}" ]] ||
         ! verify_candidate_bundle "${rejected_app}" ||
         ! bundles_have_identical_file_bytes "${COPY_ROLLBACK_SOURCE}" "${rejected_app}"; then
        echo "HARD FAILURE: isolated fresh-install destination no longer matches the verified candidate; preserving it at ${rejected_app}" >&2
        return 1
      fi
      if ! /bin/rm -rf "${rejected_app}"; then
        echo "HARD FAILURE: could not remove isolated rejected app at ${rejected_app}; stage preserved at ${COPY_ROLLBACK_STAGE}" >&2
        return 1
      fi
    fi
  fi
  COPY_ROLLBACK_ACTIVE=0
  return 0
}

clear_copy_transaction_paths() {
  COPY_ROLLBACK_DEST=""
  COPY_ROLLBACK_PREVIOUS=""
  COPY_ROLLBACK_STAGE=""
  COPY_ROLLBACK_HAD_PREVIOUS=0
  COPY_ROLLBACK_NEW_INSTALLED=0
  COPY_ROLLBACK_SOURCE=""
}

remove_completed_copy_stage() {
  local stage="${COPY_ROLLBACK_STAGE}"
  [[ -n "${stage}" && "${stage}" == "${COPY_ROLLBACK_DEST%/*}/.vifty-install-stage."* ]] || return 1
  if ! /bin/rm -rf "${stage}"; then
    echo "warning: verified install completed, but transaction cleanup remains at ${stage}" >&2
    return 1
  fi
  clear_copy_transaction_paths
}

commit_verified_copy() {
  [[ "${COPY_ROLLBACK_ACTIVE}" == "1" ]] || return 0
  COPY_ROLLBACK_ACTIVE=0
  remove_completed_copy_stage || true
}

cleanup_install_run() {
  local status=$?
  local finish_status=0
  trap - EXIT
  trap '' HUP INT TERM
  if [[ "${status}" -ne 76 && "${REPLACEMENT_AUTHORITY_STATE}" != "unknown-active" ]] &&
     rollback_interrupted_copy; then
    if [[ "${REPLACEMENT_AUTHORITY_STATE}" == "frozen" && "${REPLACEMENT_FINISH_ALLOWED}" == "1" && -n "${REPLACEMENT_LIFECYCLE}" ]] &&
       verify_install_bundle "${DEST_APP}"; then
      if finish_replacement_authority_freeze rolled-back; then
        finish_status=0
      else
        finish_status=$?
      fi
      if [[ "${finish_status}" -eq 76 ]]; then
        status=76
        echo "HARD FAILURE: installer exit cleanup found helper authority active or unknown; no second finish or rollback is allowed." >&2
      elif [[ "${finish_status}" -ne 0 ]]; then
        echo "HARD FAILURE: installer exit cleanup could not re-register the verified previous app; helper authority was last proven disabled and offline." >&2
      fi
    fi
  fi
  if [[ -n "${PUBLIC_INSTALL_LOCK}" && -n "${PUBLIC_INSTALL_LOCK_ROOT}" &&
        "${PUBLIC_INSTALL_LOCK}" == "${PUBLIC_INSTALL_LOCK_ROOT}/"*.lock ]]; then
    /bin/rmdir "${PUBLIC_INSTALL_LOCK}" 2>/dev/null ||
      echo "warning: public-release install lock remains at ${PUBLIC_INSTALL_LOCK}" >&2
  fi
  if [[ -d "${RUN_DIR}/public-archive" && ! -L "${RUN_DIR}/public-archive" ]]; then
    /bin/chmod 700 "${RUN_DIR}/public-archive" 2>/dev/null || true
  fi
  /bin/rm -rf "${RUN_DIR}" || true
  exit "${status}"
}

trap cleanup_install_run EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fallback_to_user_applications() {
  INSTALL_DIR="${HOME}/Applications"
  DEST_APP="${INSTALL_DIR}/${APP_NAME}.app"
  /bin/mkdir -p "${INSTALL_DIR}"
}

verify_install_bundle() {
  local app="$1"
  local executable

  [[ -d "${app}" && ! -L "${app}" ]] || return 1
  for executable in Vifty viftyctl ViftyDaemon ViftyHelper; do
    [[ -f "${app}/Contents/MacOS/${executable}" && -x "${app}/Contents/MacOS/${executable}" && ! -L "${app}/Contents/MacOS/${executable}" ]] || return 1
  done
  if [[ "${FIXTURE_UNSIGNED_BUILD}" == "1" ]]; then
    return 0
  fi
  /usr/bin/codesign --verify --deep --strict "${app}" >/dev/null 2>&1
}

system_tool_environment() {
  /usr/bin/env -i \
    HOME="${HOME}" \
    USER="$(/usr/bin/id -un)" \
    LOGNAME="$(/usr/bin/id -un)" \
    LANG=C \
    LC_ALL=C \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    TMPDIR="${RUN_DIR}" \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_NO_REPLACE_OBJECTS=1 \
    "$@"
}

rename_exclusive() {
  local source="$1"
  local destination="$2"
  system_tool_environment /usr/bin/ruby -rfiddle/import -e '
    module DarwinRename
      extend Fiddle::Importer
      dlload Fiddle.dlopen(nil)
      extern "int renameatx_np(int, const char*, int, const char*, unsigned int)"
    end
    at_fdcwd = -2
    rename_exclusive = 0x00000004
    exit(DarwinRename.renameatx_np(at_fdcwd, ARGV.fetch(0), at_fdcwd, ARGV.fetch(1), rename_exclusive).zero? ? 0 : 75)
  ' "${source}" "${destination}"
}

load_public_release_contract() {
  local manifest="${ROOT_DIR}/.github/release-manifest.json"
  local facts

  system_tool_environment /bin/bash "${ROOT_DIR}/scripts/check-release-manifest.sh" --manifest-only >/dev/null || {
    echo "error: the checked-in release manifest is not a valid install authority." >&2
    return 1
  }
  facts="$(system_tool_environment /usr/bin/ruby -rjson -e '
    manifest = JSON.parse(File.binread(ARGV.fetch(0)))
    release = manifest.fetch("publishedRelease")
    product = manifest.fetch("product")
    policy = manifest.fetch("releasePolicy")
    values = [
      release.fetch("version"), release.fetch("build"), release.fetch("tag"),
      release.fetch("sourceCommit"), release.fetch("artifact"), release.fetch("sha256"),
      release.fetch("artifactTrust"), release.fetch("signingTrust"), release.fetch("tagTrust"),
      policy.fetch("developerTeamID"), product.fetch("bundleID"), product.fetch("daemonID"),
      product.fetch("helperID"), product.fetch("ctlID"), product.fetch("architectures").join(" ")
    ]
    abort "published release contract contains an unsafe scalar" unless values.all? do |value|
      (value.is_a?(String) || value.is_a?(Integer)) && !value.to_s.match?(/[\t\r\n]/)
    end
    STDOUT.write(values.join("\t"))
  ' "${manifest}")" || return 1
  IFS=$'\t' read -r \
    PUBLIC_RELEASE_VERSION \
    PUBLIC_RELEASE_BUILD \
    PUBLIC_RELEASE_TAG \
    PUBLIC_RELEASE_SOURCE_COMMIT \
    PUBLIC_RELEASE_ARTIFACT_NAME \
    PUBLIC_RELEASE_SHA256 \
    public_artifact_trust \
    public_signing_trust \
    public_tag_trust \
    PUBLIC_RELEASE_TEAM_ID \
    public_app_id \
    public_daemon_id \
    public_helper_id \
    public_ctl_id \
    PUBLIC_RELEASE_ARCHITECTURES <<<"${facts}"

  [[ "${public_artifact_trust}" == "passed" &&
     "${public_signing_trust}" == "developer-id-notarized" &&
     "${PUBLIC_RELEASE_BUILD}" =~ ^[1-9][0-9]*$ &&
     "${PUBLIC_RELEASE_SHA256}" =~ ^[0-9a-f]{64}$ &&
     "${PUBLIC_RELEASE_SOURCE_COMMIT}" =~ ^[0-9a-f]{40}$ &&
     "${PUBLIC_RELEASE_TEAM_ID}" =~ ^[A-Z0-9]{10}$ &&
     "${public_app_id}" == "${APP_BUNDLE_ID}" &&
     "${public_daemon_id}" == "${DAEMON_BUNDLE_ID}" &&
     "${public_helper_id}" == "${HELPER_BUNDLE_ID}" &&
     "${public_ctl_id}" == "${CTL_BUNDLE_ID}" ]] || {
    echo "error: current publishedRelease is not an immutable Developer ID install authority." >&2
    return 1
  }
  if ! system_tool_environment /usr/bin/ruby -e '
    version = ARGV.fetch(0)
    parts = version.split(".")
    exit 75 unless parts.length == 3 && parts.all? { |part| part.match?(/\A(?:0|[1-9][0-9]*)\z/) }
    exit((parts.map(&:to_i) <=> [1, 4, 0]) >= 0 ? 0 : 75)
  ' "${PUBLIC_RELEASE_VERSION}"; then
    echo "error: safe public-archive replacement requires a published Vifty v1.4.0 or newer bundle carrying the root snapshot binding contract." >&2
    return 1
  fi
  [[ "${public_tag_trust}" == "signed-verified" ]] || {
    echo "error: published Vifty ${PUBLIC_RELEASE_VERSION} lacks the required signed-verified tag trust state." >&2
    return 1
  }
}

verify_public_release_tag() {
  local tag_object tag_commit parent_commit
  local tagged_signers="${RUN_DIR}/tagged-release-signers.allowed"
  local parent_signers="${RUN_DIR}/parent-release-signers.allowed"
  local current_signers="${ROOT_DIR}/.github/release-signers.allowed"

  tag_object="$(system_tool_environment /usr/bin/git -C "${ROOT_DIR}" rev-parse --verify "refs/tags/${PUBLIC_RELEASE_TAG}^{tag}" 2>/dev/null)" || return 1
  tag_commit="$(system_tool_environment /usr/bin/git -C "${ROOT_DIR}" rev-parse --verify "refs/tags/${PUBLIC_RELEASE_TAG}^{commit}" 2>/dev/null)" || return 1
  [[ "${tag_object}" =~ ^[0-9a-f]{40}$ && "${tag_commit}" == "${PUBLIC_RELEASE_SOURCE_COMMIT}" ]] || return 1
  system_tool_environment /usr/bin/git -C "${ROOT_DIR}" cat-file tag "${tag_object}" \
    | system_tool_environment /usr/bin/ruby -e '
        expected = ARGV.fetch(0)
        data = STDIN.read(1_048_577)
        exit 75 if data.bytesize > 1_048_576
        headers, separator, = data.partition("\n\n")
        exit 75 if separator.empty?
        tag_headers = headers.lines(chomp: true).grep(/\Atag /)
        exit(tag_headers == ["tag #{expected}"] ? 0 : 75)
      ' "${PUBLIC_RELEASE_TAG}" || return 1
  parent_commit="$(system_tool_environment /usr/bin/git -C "${ROOT_DIR}" rev-parse --verify "${tag_commit}^" 2>/dev/null)" || return 1
  system_tool_environment /usr/bin/git -C "${ROOT_DIR}" show "${tag_commit}:.github/release-signers.allowed" >"${tagged_signers}" || return 1
  system_tool_environment /usr/bin/git -C "${ROOT_DIR}" show "${parent_commit}:.github/release-signers.allowed" >"${parent_signers}" || return 1
  /usr/bin/cmp -s "${current_signers}" "${tagged_signers}" || return 1
  /usr/bin/cmp -s "${tagged_signers}" "${parent_signers}" || return 1
  system_tool_environment /usr/bin/git -C "${ROOT_DIR}" \
    -c gpg.format=ssh \
    -c gpg.ssh.program=/usr/bin/ssh-keygen \
    -c "gpg.ssh.allowedSignersFile=${tagged_signers}" \
    verify-tag "${tag_object}" >/dev/null 2>&1
}

public_release_component_matches() {
  local path="$1"
  local expected_identifier="$2"
  local requirement details
  requirement="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"${PUBLIC_RELEASE_TEAM_ID}\" and identifier \"${expected_identifier}\""
  /usr/bin/codesign --verify --strict -R="${requirement}" "${path}" >/dev/null 2>&1 || return 1
  details="$(/usr/bin/codesign -dv --verbose=4 "${path}" 2>&1)" || return 1
  /usr/bin/grep -Fqx "Identifier=${expected_identifier}" <<<"${details}" || return 1
  /usr/bin/grep -Fqx "TeamIdentifier=${PUBLIC_RELEASE_TEAM_ID}" <<<"${details}" || return 1
  /usr/bin/grep -Eq '^Authority=Developer ID Application:' <<<"${details}" || return 1
  /usr/bin/grep -Fq '(runtime)' <<<"${details}" || return 1
}

verify_public_release_bundle() {
  local app="$1"
  local info_plist="${app}/Contents/Info.plist"
  local daemon_plist="${app}/Contents/Library/LaunchDaemons/${DAEMON_BUNDLE_ID}.plist"
  local executable expected_identifier actual_architectures

  system_tool_environment /usr/bin/ruby "${ROOT_DIR}/scripts/release-candidate-inventory.rb" verify-public-tree \
    --app "${app}" \
    --expected-content-manifest-sha256 "${PUBLIC_CONTENT_MANIFEST_SHA256}" >/dev/null || return 1
  verify_public_quarantine_state "${app}" || return 1
  verify_install_bundle "${app}" || return 1
  /usr/bin/plutil -lint "${info_plist}" >/dev/null || return 1
  /usr/bin/plutil -lint "${daemon_plist}" >/dev/null || return 1
  [[ "$(plist_raw_value "${info_plist}" CFBundleIdentifier)" == "${APP_BUNDLE_ID}" &&
     "$(plist_raw_value "${info_plist}" CFBundleShortVersionString)" == "${PUBLIC_RELEASE_VERSION}" &&
     "$(plist_raw_value "${info_plist}" CFBundleVersion)" == "${PUBLIC_RELEASE_BUILD}" &&
     "$(plist_raw_value "${daemon_plist}" Label)" == "${DAEMON_BUNDLE_ID}" &&
     "$(/usr/libexec/PlistBuddy -c "Print :MachServices:${DAEMON_BUNDLE_ID}" "${daemon_plist}" 2>/dev/null)" == "true" &&
     "$(plist_raw_value "${daemon_plist}" EnvironmentVariables.VIFTY_XPC_ALLOWED_TEAM_ID)" == "${PUBLIC_RELEASE_TEAM_ID}" ]] || return 1
  if /usr/bin/plutil -convert json -o - -- "${daemon_plist}" | system_tool_environment /usr/bin/ruby -rjson -e '
    keys = Hash(JSON.parse(STDIN.read)["EnvironmentVariables"]).keys.grep(/\AVIFTY_XPC_ADHOC_/)
    exit(keys.empty? ? 1 : 0)
  '; then
    return 1
  fi
  for executable in Vifty viftyctl ViftyDaemon ViftyHelper; do
    case "${executable}" in
      Vifty) expected_identifier="${APP_BUNDLE_ID}" ;;
      viftyctl) expected_identifier="${CTL_BUNDLE_ID}" ;;
      ViftyDaemon) expected_identifier="${DAEMON_BUNDLE_ID}" ;;
      ViftyHelper) expected_identifier="${HELPER_BUNDLE_ID}" ;;
    esac
    public_release_component_matches "${app}/Contents/MacOS/${executable}" "${expected_identifier}" || return 1
    actual_architectures="$(/usr/bin/lipo -archs "${app}/Contents/MacOS/${executable}" 2>/dev/null | /usr/bin/tr ' ' '\n' | /usr/bin/sed '/^$/d' | LC_ALL=C /usr/bin/sort | /usr/bin/xargs)" || return 1
    [[ "${actual_architectures}" == "${PUBLIC_RELEASE_ARCHITECTURES}" ]] || return 1
  done
  public_release_component_matches "${app}" "${APP_BUNDLE_ID}" || return 1
  /usr/bin/xcrun stapler validate "${app}" >/dev/null 2>&1 || return 1
  /usr/sbin/spctl --assess --type execute --verbose "${app}" >/dev/null 2>&1
}

verify_candidate_bundle() {
  if [[ "${INSTALL_MODE}" == "public-release" ]]; then
    verify_public_release_bundle "$1"
  else
    verify_install_bundle "$1"
  fi
}

acquire_public_install_lock() {
  local lock_path
  lock_path="$(system_tool_environment /usr/bin/ruby -e '
    destination, owner_text = ARGV
    owner = Integer(owner_text, 10)
    destination_parent = File.dirname(File.expand_path(destination))
    destination_parent_stat = File.lstat(destination_parent)
    abort "unsafe destination parent" unless destination_parent_stat.directory? && !destination_parent_stat.symlink? &&
      File.realpath(destination_parent) == destination_parent
    lock = File.join(destination_parent, ".vifty-public-install.lock")
    Dir.mkdir(lock, 0700)
    lock_stat = File.lstat(lock)
    abort "unsafe public installer lock" unless lock_stat.directory? && !lock_stat.symlink? &&
      lock_stat.uid == owner && (lock_stat.mode & 0777) == 0700
    STDOUT.write(lock)
  ' "${DEST_APP}" "$(/usr/bin/id -u)" 2>/dev/null)" || {
    echo "error: another public-release install is active, a stale lock requires review, or the private lock directory is unsafe." >&2
    return 1
  }
  PUBLIC_INSTALL_LOCK="${lock_path}"
  PUBLIC_INSTALL_LOCK_ROOT="${lock_path%/*}"
  [[ -d "${PUBLIC_INSTALL_LOCK}" && ! -L "${PUBLIC_INSTALL_LOCK}" ]] || return 1
}

validate_public_install_destination() {
  system_tool_environment /usr/bin/ruby -e '
    path = ARGV.fetch(0)
    stat = File.lstat(path)
    exit 75 unless stat.directory? && !stat.symlink? && File.realpath(path) == File.expand_path(path)
  ' "${INSTALL_DIR}"
}

read_public_quarantine_state() {
  local path="$1"
  local names raw hex
  names="$(/usr/bin/xattr "${path}" 2>/dev/null)" || return 1
  if ! /usr/bin/grep -Fqx 'com.apple.quarantine' <<<"${names}"; then
    /usr/bin/printf 'absent'
    return 0
  fi
  raw="$(/usr/bin/xattr -px com.apple.quarantine "${path}" 2>/dev/null)" || return 1
  hex="$(/usr/bin/printf '%s' "${raw}" | /usr/bin/tr -d '[:space:]' | /usr/bin/tr '[:upper:]' '[:lower:]')"
  [[ -n "${hex}" && ${#hex} -le 8192 &&
     $(( ${#hex} % 2 )) -eq 0 &&
     "${hex}" =~ ^[0-9a-f]+$ ]] || return 1
  /usr/bin/printf 'present:%s' "${hex}"
}

capture_public_archive_quarantine() {
  PUBLIC_QUARANTINE_STATE="$(read_public_quarantine_state "${PUBLIC_RELEASE_ARCHIVE}")" || {
    echo "error: source archive quarantine state could not be read safely." >&2
    return 1
  }
  case "${PUBLIC_QUARANTINE_STATE}" in
    absent) PUBLIC_QUARANTINE_HEX="" ;;
    present:*) PUBLIC_QUARANTINE_HEX="${PUBLIC_QUARANTINE_STATE#present:}" ;;
    *) return 1 ;;
  esac
}

apply_public_archive_quarantine() {
  local path="$1"
  [[ -n "${PUBLIC_QUARANTINE_HEX}" ]] || return 0
  /usr/bin/xattr -wx com.apple.quarantine "${PUBLIC_QUARANTINE_HEX}" "${path}"
}

verify_public_quarantine_state() {
  local actual
  [[ -n "${PUBLIC_QUARANTINE_STATE}" ]] || return 1
  actual="$(read_public_quarantine_state "$1")" || return 1
  [[ "${actual}" == "${PUBLIC_QUARANTINE_STATE}" ]]
}

public_tree_sha256() {
  local digest
  digest="$(system_tool_environment /usr/bin/ruby "${ROOT_DIR}/scripts/release-candidate-inventory.rb" \
    public-tree-sha256 --app "$1")" || return 1
  [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || return 1
  /usr/bin/printf '%s' "${digest}"
}

prepare_public_release_candidate() {
  local archive_dir="${RUN_DIR}/public-archive"
  local extract_dir="${RUN_DIR}/public-candidate"
  local staged_archive summary

  load_public_release_contract || return 1
  verify_public_release_tag || {
    echo "error: current publishedRelease tag/signature/signer-policy continuity verification failed." >&2
    return 1
  }
  [[ "$(/usr/bin/basename "${PUBLIC_RELEASE_ARCHIVE}")" == "${PUBLIC_RELEASE_ARTIFACT_NAME}" ]] || {
    echo "error: public archive must use the canonical name ${PUBLIC_RELEASE_ARTIFACT_NAME}." >&2
    return 1
  }
  capture_public_archive_quarantine || return 1
  /bin/mkdir "${archive_dir}" "${extract_dir}"
  /bin/chmod 700 "${archive_dir}" "${extract_dir}"
  staged_archive="${archive_dir}/${PUBLIC_RELEASE_ARTIFACT_NAME}"
  system_tool_environment /usr/bin/ruby "${ROOT_DIR}/scripts/release-candidate-inventory.rb" stage-public \
    --archive "${PUBLIC_RELEASE_ARCHIVE}" \
    --expected-sha "${PUBLIC_RELEASE_SHA256}" \
    --output "${staged_archive}" >/dev/null || return 1
  [[ "$(read_public_quarantine_state "${PUBLIC_RELEASE_ARCHIVE}")" == "${PUBLIC_QUARANTINE_STATE}" ]] || {
    echo "error: source archive quarantine state changed while its bytes were staged." >&2
    return 1
  }
  if [[ -n "${PUBLIC_QUARANTINE_HEX}" ]]; then
    /bin/chmod 600 "${staged_archive}"
    apply_public_archive_quarantine "${staged_archive}" || return 1
    /bin/chmod 400 "${staged_archive}"
  fi
  verify_public_quarantine_state "${staged_archive}" || return 1
  /bin/chmod 500 "${archive_dir}"
  PUBLIC_CONTENT_MANIFEST_SHA256="$(system_tool_environment /usr/bin/ruby "${ROOT_DIR}/scripts/release-candidate-inventory.rb" extract-public \
    --archive "${staged_archive}" \
    --expected-sha "${PUBLIC_RELEASE_SHA256}" \
    --extract-to "${extract_dir}" \
    --print-content-manifest-sha256)" || return 1
  [[ "${PUBLIC_CONTENT_MANIFEST_SHA256}" =~ ^[0-9a-f]{64}$ ]] || return 1
  apply_public_archive_quarantine "${extract_dir}/${APP_NAME}.app" || return 1
  verify_public_quarantine_state "${extract_dir}/${APP_NAME}.app" || return 1

  summary="${RUN_DIR}/public-release-verifier-summary.json"
  system_tool_environment /bin/bash "${ROOT_DIR}/scripts/verify-release-artifact.sh" \
    --artifact "${staged_archive}" \
    --release-version "${PUBLIC_RELEASE_VERSION}" \
    --summary "${summary}" >/dev/null || {
    echo "error: the exact public archive failed the complete release artifact verifier." >&2
    return 1
  }
  system_tool_environment /usr/bin/ruby "${ROOT_DIR}/scripts/lib/release_artifact_contract.rb" \
    validate-published-install-summary \
    "${summary}" \
    "${ROOT_DIR}/.github/release-manifest.json" \
    "${ROOT_DIR}" || {
    echo "error: public archive verifier evidence is not valid for the current publishedRelease." >&2
    return 1
  }

  APP_DIR="${extract_dir}/${APP_NAME}.app"
  HELPER_LIFECYCLE_SOURCE="${APP_DIR}/Contents/Resources/vifty-helper-lifecycle.sh"
  PUBLIC_HELPER_SHA256="$(sha256_file "${APP_DIR}/Contents/MacOS/ViftyHelper")" || return 1
  PUBLIC_LIFECYCLE_SHA256="$(sha256_file "${HELPER_LIFECYCLE_SOURCE}")" || return 1
  [[ "${PUBLIC_HELPER_SHA256}" =~ ^[0-9a-f]{64}$ && "${PUBLIC_LIFECYCLE_SHA256}" =~ ^[0-9a-f]{64}$ ]] || return 1
  verify_public_release_bundle "${APP_DIR}" || {
    echo "error: safely extracted public bundle failed exact identity, content, Developer ID, notarization, or Gatekeeper verification." >&2
    return 1
  }
  echo "==> Verified exact published Vifty ${PUBLIC_RELEASE_VERSION} build ${PUBLIC_RELEASE_BUILD} archive, signed tag, complete content binding, Developer ID identity, stapling, and Gatekeeper acceptance."
}

public_release_is_not_a_downgrade() {
  [[ -d "${DEST_APP}" && ! -L "${DEST_APP}" ]] || return 0
  existing_developer_id_source_is_authenticated || return 0
  local installed_version installed_build
  installed_version="$(plist_raw_value "${DEST_APP}/Contents/Info.plist" CFBundleShortVersionString)" || return 1
  installed_build="$(plist_raw_value "${DEST_APP}/Contents/Info.plist" CFBundleVersion)" || return 1
  system_tool_environment /usr/bin/ruby -e '
    installed_version, installed_build, candidate_version, candidate_build = ARGV
    parse = lambda do |value|
      parts = value.split(".")
      exit 75 unless parts.length == 3 && parts.all? { |part| part.match?(/\A(?:0|[1-9][0-9]*)\z/) }
      parts.map(&:to_i)
    end
    exit 75 unless installed_build.match?(/\A(?:0|[1-9][0-9]*)\z/) && candidate_build.match?(/\A(?:0|[1-9][0-9]*)\z/)
    installed = parse.call(installed_version)
    candidate = parse.call(candidate_version)
    comparison = installed <=> candidate
    exit(comparison.negative? || (comparison.zero? && installed_build.to_i <= candidate_build.to_i) ? 0 : 75)
  ' "${installed_version}" "${installed_build}" "${PUBLIC_RELEASE_VERSION}" "${PUBLIC_RELEASE_BUILD}"
}

bundles_have_identical_file_bytes() {
  local source_app="$1"
  local copied_app="$2"
  system_tool_environment /usr/bin/ruby -rdigest -rfind -e '
    def manifest(root)
      entries = []
      Find.find(root) do |path|
        next if path == root
        relative = path.delete_prefix(root + "/")
        stat = File.lstat(path)
        mode = stat.mode & 0o777
        if stat.directory?
          entries << [relative, "directory", mode]
        elsif stat.file?
          entries << [relative, "file", mode, stat.size, Digest::SHA256.file(path).hexdigest]
        elsif stat.symlink?
          entries << [relative, "symlink", mode, File.readlink(path)]
        else
          exit 75
        end
      end
      entries.sort
    end
    exit(manifest(ARGV[0]) == manifest(ARGV[1]) ? 0 : 75)
  ' "${source_app}" "${copied_app}"
}

copy_app_bundle() {
  local source_app="$1"
  local dest_app="$2"
  local install_parent
  local stage_dir
  local staged_app
  local previous_app

  verify_candidate_bundle "${source_app}" || return 1
  if [[ "${INSTALL_MODE}" == "public-release" ]]; then
    case "${PUBLIC_DESTINATION_EXPECTATION}" in
      absent) ! path_exists_without_following "${dest_app}" || return 1 ;;
      present) path_exists_without_following "${dest_app}" || return 1 ;;
      *) return 1 ;;
    esac
  fi
  if path_exists_without_following "${dest_app}"; then
    [[ -d "${dest_app}" && ! -L "${dest_app}" ]] || return 1
  fi
  if ! install_parent="$(/usr/bin/dirname "${dest_app}")" || [[ -z "${install_parent}" ]]; then
    return 1
  fi
  if [[ "${FIXTURE_STAGE_MKTEMP_FAILURE}" == "1" ]] ||
     ! stage_dir="$(/usr/bin/mktemp -d "${install_parent}/.vifty-install-stage.XXXXXXXX")"; then
    return 1
  fi
  if [[ -z "${stage_dir}" || ! -d "${stage_dir}" ||
        "${stage_dir}" != "${install_parent}/.vifty-install-stage."* ||
        "${stage_dir%/*}" != "${install_parent}" ]]; then
    [[ -n "${stage_dir}" && "${stage_dir}" == "${install_parent}/.vifty-install-stage."* ]] && /bin/rm -rf "${stage_dir}"
    return 1
  fi
  staged_app="${stage_dir}/${APP_NAME}.app"
  previous_app="${stage_dir}/previous-${APP_NAME}.app"

  if [[ "${INSTALL_MODE}" == "public-release" ]]; then
    if ! "${DITTO_COMMAND}" --rsrc --extattr --acl "${source_app}" "${staged_app}"; then
      /bin/rm -rf "${stage_dir}"
      return 1
    fi
  else
    if ! COPYFILE_DISABLE=1 "${DITTO_COMMAND}" --norsrc --noextattr --noqtn "${source_app}" "${staged_app}"; then
      /bin/rm -rf "${stage_dir}"
      return 1
    fi
    /usr/bin/xattr -cr "${staged_app}" 2>/dev/null || true
  fi
  if ! verify_candidate_bundle "${staged_app}" || ! bundles_have_identical_file_bytes "${source_app}" "${staged_app}"; then
    /bin/rm -rf "${stage_dir}"
    return 1
  fi

  COPY_ROLLBACK_ACTIVE=1
  COPY_ROLLBACK_SOURCE="${source_app}"
  COPY_ROLLBACK_DEST="${dest_app}"
  COPY_ROLLBACK_PREVIOUS="${previous_app}"
  COPY_ROLLBACK_STAGE="${stage_dir}"
  COPY_ROLLBACK_NEW_INSTALLED=0
  if [[ "${INSTALL_MODE}" == "public-release" && "${PUBLIC_DESTINATION_EXPECTATION}" == "absent" ]]; then
    COPY_ROLLBACK_HAD_PREVIOUS=0
  elif [[ "${INSTALL_MODE}" == "public-release" && "${PUBLIC_DESTINATION_EXPECTATION}" == "present" ]] &&
       ! path_exists_without_following "${dest_app}"; then
    COPY_ROLLBACK_ACTIVE=0
    /bin/rm -rf "${stage_dir}"
    return 1
  elif path_exists_without_following "${dest_app}"; then
    COPY_ROLLBACK_HAD_PREVIOUS=1
    if ! rename_exclusive "${dest_app}" "${previous_app}"; then
      COPY_ROLLBACK_ACTIVE=0
      /bin/rm -rf "${stage_dir}"
      return 1
    fi
    if [[ "${INSTALL_MODE}" == "public-release" ]] &&
       { [[ "${PUBLIC_DESTINATION_EXPECTATION}" != "present" ]] ||
         [[ -z "${PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256}" ]] ||
         ! system_tool_environment /usr/bin/ruby "${ROOT_DIR}/scripts/release-candidate-inventory.rb" verify-public-tree \
           --app "${previous_app}" \
           --expected-content-manifest-sha256 "${PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256}" >/dev/null; }; then
      COPY_ROLLBACK_ACTIVE=0
      echo "HARD FAILURE: atomically isolated previous app does not match the exact preflighted public destination; preserving it at ${previous_app} while helper authority remains frozen." >&2
      return 1
    fi
  else
    COPY_ROLLBACK_HAD_PREVIOUS=0
  fi
  if ! rename_exclusive "${staged_app}" "${dest_app}"; then
    if rollback_interrupted_copy; then
      /bin/rm -rf "${stage_dir}"
    else
      echo "HARD FAILURE: rollback did not complete; recovery material preserved at ${stage_dir}" >&2
    fi
    return 1
  fi
  COPY_ROLLBACK_NEW_INSTALLED=1
  if [[ "${FIXTURE_HIDE_PREVIOUS_BEFORE_ROLLBACK}" == "1" && "${COPY_ROLLBACK_HAD_PREVIOUS}" == "1" ]]; then
    rename_exclusive "${previous_app}" "${stage_dir}/displaced-previous-${APP_NAME}.app"
  fi
  if [[ "${FIXTURE_POST_SWAP_VERIFICATION_FAILURE}" == "1" ]] ||
     ! verify_candidate_bundle "${dest_app}" ||
     ! bundles_have_identical_file_bytes "${source_app}" "${dest_app}"; then
    if rollback_interrupted_copy; then
      /bin/rm -rf "${stage_dir}"
    else
      echo "HARD FAILURE: post-swap verification failed and rollback did not complete; recovery material preserved at ${stage_dir}" >&2
    fi
    return 1
  fi
  if [[ "${REPLACEMENT_AUTHORITY_STATE}" == "frozen" ]]; then
    [[ "${COPY_ROLLBACK_HAD_PREVIOUS}" == "1" ]] || return 1
    return 0
  fi
  commit_verified_copy
  return 0
}

running_app_pids() {
  if [[ "${FIXTURE_NO_RUNNING_APP}" == "1" ]]; then
    [[ "${FIXTURE_CONTEXT_VALID}" == "1" ]] || {
      echo "error: VIFTY_INSTALL_FIXTURE_NO_RUNNING_APP requires the validated fixture root." >&2
      exit 65
    }
    return 0
  fi
  /usr/bin/pgrep -x "${APP_NAME}" 2>/dev/null || true
}

wait_for_app_exit() {
  local attempts="${1:-50}"
  while [[ "${attempts}" -gt 0 ]]; do
    if [[ -z "$(running_app_pids)" ]]; then
      return 0
    fi
    /bin/sleep 0.2
    attempts=$((attempts - 1))
  done
  return 1
}

sha256_file() {
  [[ "${FIXTURE_SHA256_FAILURE}" != "1" ]] || return 1
  system_tool_environment /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

plist_raw_value() {
  local plist="$1"
  local key="$2"
  /usr/bin/plutil -extract "${key}" raw -o - "${plist}" 2>/dev/null
}

signed_component_matches() {
  local path="$1"
  local expected_identifier="$2"
  local expected_sha256="$3"
  local expected_cdhash="$4"
  local actual_sha256

  developer_id_component_matches "${path}" "${expected_identifier}" "${expected_cdhash}" || return 1
  if ! actual_sha256="$(sha256_file "${path}")" ||
     [[ ! "${actual_sha256}" =~ ^[0-9a-f]{64}$ ]]; then
    return 1
  fi
  [[ "${actual_sha256}" == "${expected_sha256}" ]] || return 1
}

developer_id_component_matches() {
  local path="$1"
  local expected_identifier="$2"
  local expected_cdhash="${3:-}"
  local details
  local requirement

  requirement="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"${PUBLISHED_V132_TEAM_ID}\" and identifier \"${expected_identifier}\""
  /usr/bin/codesign --verify --strict -R="${requirement}" "${path}" >/dev/null 2>&1 || return 1
  details="$(/usr/bin/codesign -dv --verbose=4 "${path}" 2>&1)" || return 1
  /usr/bin/grep -Fqx "Identifier=${expected_identifier}" <<<"${details}" || return 1
  /usr/bin/grep -Fqx "TeamIdentifier=${PUBLISHED_V132_TEAM_ID}" <<<"${details}" || return 1
  /usr/bin/grep -Fqx "Authority=${PUBLISHED_V132_AUTHORITY}" <<<"${details}" || return 1
  if [[ -n "${expected_cdhash}" ]]; then
    /usr/bin/grep -Fqx "CDHash=${expected_cdhash}" <<<"${details}" || return 1
  fi
}

published_v132_source_is_allowlisted() {
  local info_plist="${DEST_APP}/Contents/Info.plist"
  local daemon_plist="${DEST_APP}/Contents/Library/LaunchDaemons/${DAEMON_BUNDLE_ID}.plist"
  local existing_main="${DEST_APP}/Contents/MacOS/Vifty"
  local existing_ctl="${DEST_APP}/Contents/MacOS/viftyctl"
  local existing_daemon="${DEST_APP}/Contents/MacOS/ViftyDaemon"
  local existing_helper="${DEST_APP}/Contents/MacOS/ViftyHelper"

  [[ -f "${info_plist}" && ! -L "${info_plist}" ]] || return 1
  [[ -f "${daemon_plist}" && ! -L "${daemon_plist}" ]] || return 1
  for executable in "${existing_main}" "${existing_ctl}" "${existing_daemon}" "${existing_helper}"; do
    [[ -f "${executable}" && -x "${executable}" && ! -L "${executable}" ]] || return 1
  done

  [[ "$(plist_raw_value "${info_plist}" CFBundleIdentifier)" == "${APP_BUNDLE_ID}" ]] || return 1
  [[ "$(plist_raw_value "${info_plist}" CFBundlePackageType)" == "APPL" ]] || return 1
  [[ "$(plist_raw_value "${info_plist}" CFBundleShortVersionString)" == "${PUBLISHED_V132_VERSION}" ]] || return 1
  [[ "$(plist_raw_value "${info_plist}" CFBundleVersion)" == "${PUBLISHED_V132_BUILD}" ]] || return 1
  [[ "$(plist_raw_value "${daemon_plist}" Label)" == "${DAEMON_BUNDLE_ID}" ]] || return 1
  [[ "$(plist_raw_value "${daemon_plist}" EnvironmentVariables.VIFTY_XPC_ALLOWED_TEAM_ID)" == "${PUBLISHED_V132_TEAM_ID}" ]] || return 1

  if [[ "${FIXTURE_PUBLISHED_V132}" == "1" ]]; then
    return 0
  fi

  local app_requirement
  app_requirement="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"${PUBLISHED_V132_TEAM_ID}\" and identifier \"${APP_BUNDLE_ID}\""
  /usr/bin/codesign --verify --deep --strict -R="${app_requirement}" "${DEST_APP}" >/dev/null 2>&1 || return 1
  signed_component_matches "${existing_main}" "${APP_BUNDLE_ID}" "${PUBLISHED_V132_MAIN_SHA256}" "${PUBLISHED_V132_MAIN_CDHASH}" || return 1
  signed_component_matches "${existing_ctl}" "${CTL_BUNDLE_ID}" "${PUBLISHED_V132_CTL_SHA256}" "${PUBLISHED_V132_CTL_CDHASH}" || return 1
  signed_component_matches "${existing_daemon}" "${DAEMON_BUNDLE_ID}" "${PUBLISHED_V132_DAEMON_SHA256}" "${PUBLISHED_V132_DAEMON_CDHASH}" || return 1
  signed_component_matches "${existing_helper}" "${HELPER_BUNDLE_ID}" "${PUBLISHED_V132_HELPER_SHA256}" "${PUBLISHED_V132_HELPER_CDHASH}" || return 1
}

existing_developer_id_source_is_authenticated() {
  local info_plist="${DEST_APP}/Contents/Info.plist"
  local daemon_plist="${DEST_APP}/Contents/Library/LaunchDaemons/${DAEMON_BUNDLE_ID}.plist"
  local existing_main="${DEST_APP}/Contents/MacOS/Vifty"
  local existing_ctl="${DEST_APP}/Contents/MacOS/viftyctl"
  local existing_daemon="${DEST_APP}/Contents/MacOS/ViftyDaemon"
  local existing_helper="${DEST_APP}/Contents/MacOS/ViftyHelper"

  [[ -f "${info_plist}" && ! -L "${info_plist}" ]] || return 1
  [[ -f "${daemon_plist}" && ! -L "${daemon_plist}" ]] || return 1
  for executable in "${existing_main}" "${existing_ctl}" "${existing_daemon}" "${existing_helper}"; do
    [[ -f "${executable}" && -x "${executable}" && ! -L "${executable}" ]] || return 1
  done
  [[ "$(plist_raw_value "${info_plist}" CFBundleIdentifier)" == "${APP_BUNDLE_ID}" ]] || return 1
  [[ "$(plist_raw_value "${info_plist}" CFBundlePackageType)" == "APPL" ]] || return 1
  [[ "$(plist_raw_value "${daemon_plist}" Label)" == "${DAEMON_BUNDLE_ID}" ]] || return 1
  [[ "$(plist_raw_value "${daemon_plist}" EnvironmentVariables.VIFTY_XPC_ALLOWED_TEAM_ID)" == "${PUBLISHED_V132_TEAM_ID}" ]] || return 1

  local app_requirement
  app_requirement="anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"${PUBLISHED_V132_TEAM_ID}\" and identifier \"${APP_BUNDLE_ID}\""
  /usr/bin/codesign --verify --deep --strict -R="${app_requirement}" "${DEST_APP}" >/dev/null 2>&1 || return 1
  developer_id_component_matches "${existing_main}" "${APP_BUNDLE_ID}" || return 1
  developer_id_component_matches "${existing_ctl}" "${CTL_BUNDLE_ID}" || return 1
  developer_id_component_matches "${existing_daemon}" "${DAEMON_BUNDLE_ID}" || return 1
  developer_id_component_matches "${existing_helper}" "${HELPER_BUNDLE_ID}" || return 1
}

adhoc_component_matches() {
  local path="$1"
  local expected_identifier="$2"
  local details

  /usr/bin/codesign --verify --strict "${path}" >/dev/null 2>&1 || return 1
  details="$(/usr/bin/codesign -dv --verbose=4 "${path}" 2>&1)" || return 1
  /usr/bin/grep -Fqx "Identifier=${expected_identifier}" <<<"${details}" || return 1
  /usr/bin/grep -Fqx "Signature=adhoc" <<<"${details}" || return 1
  /usr/bin/grep -Fqx "TeamIdentifier=not set" <<<"${details}" || return 1
}

existing_adhoc_development_source_is_authenticated() {
  [[ "${CONFIGURATION}" == "debug" && "${ENABLE_ADHOC_XPC}" == "1" ]] || return 1

  local info_plist="${DEST_APP}/Contents/Info.plist"
  local daemon_plist="${DEST_APP}/Contents/Library/LaunchDaemons/${DAEMON_BUNDLE_ID}.plist"
  local existing_main="${DEST_APP}/Contents/MacOS/Vifty"
  local existing_ctl="${DEST_APP}/Contents/MacOS/viftyctl"
  local existing_daemon="${DEST_APP}/Contents/MacOS/ViftyDaemon"
  local existing_helper="${DEST_APP}/Contents/MacOS/ViftyHelper"
  local expected_app_path="${DEST_APP}/Contents/MacOS/Vifty"
  local expected_ctl_path="${DEST_APP}/Contents/MacOS/viftyctl"
  local allowed_team_id
  local adhoc_enabled
  local allowed_uid
  local configured_app_path
  local configured_ctl_path

  [[ -f "${info_plist}" && ! -L "${info_plist}" ]] || return 1
  [[ -f "${daemon_plist}" && ! -L "${daemon_plist}" ]] || return 1
  for executable in "${existing_main}" "${existing_ctl}" "${existing_daemon}" "${existing_helper}"; do
    [[ -f "${executable}" && -x "${executable}" && ! -L "${executable}" ]] || return 1
  done
  [[ "$(plist_raw_value "${info_plist}" CFBundleIdentifier)" == "${APP_BUNDLE_ID}" ]] || return 1
  [[ "$(plist_raw_value "${info_plist}" CFBundlePackageType)" == "APPL" ]] || return 1
  [[ "$(plist_raw_value "${daemon_plist}" Label)" == "${DAEMON_BUNDLE_ID}" ]] || return 1
  allowed_team_id="$(plist_raw_value "${daemon_plist}" EnvironmentVariables.VIFTY_XPC_ALLOWED_TEAM_ID)" || return 1
  adhoc_enabled="$(plist_raw_value "${daemon_plist}" EnvironmentVariables.VIFTY_XPC_ADHOC_DEVELOPMENT)" || return 1
  allowed_uid="$(plist_raw_value "${daemon_plist}" EnvironmentVariables.VIFTY_XPC_ADHOC_ALLOWED_UID)" || return 1
  configured_app_path="$(plist_raw_value "${daemon_plist}" EnvironmentVariables.VIFTY_XPC_ADHOC_APP_PATH)" || return 1
  configured_ctl_path="$(plist_raw_value "${daemon_plist}" EnvironmentVariables.VIFTY_XPC_ADHOC_CTL_PATH)" || return 1
  [[ -z "${allowed_team_id}" ]] || return 1
  [[ "${adhoc_enabled}" == "1" ]] || return 1
  [[ "${allowed_uid}" == "${ADHOC_UID}" ]] || return 1
  [[ "${configured_app_path}" == "${expected_app_path}" ]] || return 1
  [[ "${configured_ctl_path}" == "${expected_ctl_path}" ]] || return 1
  /usr/bin/codesign --verify --deep --strict "${DEST_APP}" >/dev/null 2>&1 || return 1
  adhoc_component_matches "${existing_main}" "${APP_BUNDLE_ID}" || return 1
  adhoc_component_matches "${existing_ctl}" "${CTL_BUNDLE_ID}" || return 1
  adhoc_component_matches "${existing_daemon}" "${DAEMON_BUNDLE_ID}" || return 1
  adhoc_component_matches "${existing_helper}" "${HELPER_BUNDLE_ID}" || return 1
}

shell_quote() {
  printf "'"
  /usr/bin/printf "%s" "$1" | /usr/bin/sed "s/'/'\\\\''/g"
  printf "'"
}

is_swiftpm_build_database_error() {
  /usr/bin/grep -Eiq "build\\.db|build database|disk I/O error|database is locked" "${BUILD_LOG}"
}

make_app_once() {
  local build_status
  local make_args=(app "CONFIGURATION=${CONFIGURATION}")
  if [[ "${ENABLE_ADHOC_XPC}" == "1" ]]; then
    make_args+=(
      "VIFTY_XPC_ADHOC_DEVELOPMENT=1"
      "VIFTY_XPC_ADHOC_ALLOWED_UID=${ADHOC_UID}"
      "VIFTY_XPC_ADHOC_APP_PATH=${DEST_APP}/Contents/MacOS/Vifty"
      "VIFTY_XPC_ADHOC_CTL_PATH=${DEST_APP}/Contents/MacOS/viftyctl"
    )
  fi
  set +e
  "${MAKE_COMMAND}" "${make_args[@]}" 2>&1 | /usr/bin/tee "${BUILD_LOG}"
  build_status=${PIPESTATUS[0]}
  set -e
  return "${build_status}"
}

build_app_bundle() {
  local build_status
  if make_app_once; then
    return 0
  else
    build_status=$?
  fi

  if [[ -z "${SWIFT_BUILD_PATH:-}" ]] && is_swiftpm_build_database_error; then
    local fallback_build_path="${RUN_DIR}/swiftpm"
    echo "==> SwiftPM build database failed; retrying with SWIFT_BUILD_PATH=${fallback_build_path}"
    if SWIFT_BUILD_PATH="${fallback_build_path}" make_app_once; then
      build_status=0
    else
      build_status=$?
    fi
  fi

  return "${build_status}"
}

report_helper_daemon_status() {
  if [[ "${CHECK_HELPER_DAEMON}" != "1" ]]; then
    return 0
  fi

  local repair_command
  repair_command="REPAIR_HELPER_APP=$(shell_quote "${DEST_APP}") make repair-helper"

  local bundled_daemon="${DEST_APP}/Contents/MacOS/ViftyDaemon"
  if [[ ! -x "${bundled_daemon}" ]]; then
    echo "==> Could not check fan helper parity; bundled ViftyDaemon is missing."
    return 0
  fi

  if [[ ! -f "${HELPER_TARGET}" ]]; then
    echo "==> Fan helper is not installed yet."
    if [[ "${INSTALL_MODE}" == "public-release" ]]; then
      echo "    RESULT: App installed; helper installation or repair is required before manual fan control."
    fi
    echo "    Open Vifty and choose Install Helper before manual fan control or current-build smoke evidence."
    return 0
  fi

  local bundled_sha
  local installed_sha
  bundled_sha="$(sha256_file "${bundled_daemon}")"
  installed_sha="$(sha256_file "${HELPER_TARGET}")"

  if [[ "${bundled_sha}" == "${installed_sha}" ]]; then
    echo "==> Fan helper matches the installed app daemon."
    return 0
  fi

  echo "==> Fan helper daemon differs from the installed app bundle."
  if [[ "${INSTALL_MODE}" == "public-release" ]]; then
    echo "    RESULT: App installed; helper repair is required before manual fan control."
  fi
  echo "    Bundled daemon:   ${bundled_sha}"
  echo "    Installed helper: ${installed_sha}"
  echo "    Open Vifty and choose Reinstall Helper or Repair Helper, or run: ${repair_command}"
  echo "    Do that before current-build manual/agent smoke evidence."
  echo "    Then rerun: AGENT_RUN_SMOKE_READINESS_JSON=1 make agent-run-smoke-readiness-current-build"
}

quit_running_app_if_needed() {
  local pids
  pids="$(running_app_pids)"
  if [[ -z "${pids}" ]]; then
    return 0
  fi

  if [[ "${QUIT_RUNNING_APP}" != "1" ]]; then
    echo "error: QUIT_RUNNING_APP=0 cannot replace an existing running Vifty app without verified safe termination." >&2
    echo "error: Quit Vifty through its normal Auto-restoring termination flow, then retry." >&2
    exit 75
  fi

  WAS_RUNNING=1
  echo "==> Quitting running ${APP_NAME} before install"
  /usr/bin/osascript -e 'tell application id "tech.reidar.vifty" to quit' >/dev/null 2>&1 \
    || /usr/bin/osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 \
    || true

  if ! wait_for_app_exit 50; then
    echo "error: ${APP_NAME} did not complete its safe termination; refusing to replace the app bundle." >&2
    echo "error: Restore Auto or follow the in-app recovery guidance, then retry. No forced termination was attempted." >&2
    exit 75
  fi
}

legacy_v132_replacement_evidence_passes() {
  local legacy_report="$1"
  local local_probe="$2"
  local expected_daemon_path="$3"
  local installed_daemon_path="$4"

  /usr/bin/ruby -rjson -e '
    begin
      report = JSON.parse(File.read(ARGV[0]))
      probe_lines = File.readlines(ARGV[1], chomp: true)
    rescue StandardError
      exit 75
    end

    def fresh_apple_reference_date?(value)
      return false unless value.is_a?(Numeric)
      age_seconds = Time.now.to_f - (value.to_f + 978_307_200.0)
      age_seconds >= -5.0 && age_seconds <= 60.0
    end

    def exactly_one_passing_check?(report, id)
      checks = report["checks"]
      return false unless checks.is_a?(Array)
      matches = checks.select { |check| check.is_a?(Hash) && check["id"] == id }
      matches.length == 1 && matches.first["passed"] == true
    end

    required_legacy_checks = [
      "daemonSnapshotAvailable",
      "agentControlStatusAvailable",
      "daemonControlPathReady",
      "supportedHardware",
      "activeLeaseClear",
      "manualControlClear"
    ]
    legacy_shape = report["schemaVersion"] == 1 &&
      fresh_apple_reference_date?(report["generatedAt"]) &&
      required_legacy_checks.all? { |id| exactly_one_passing_check?(report, id) } &&
      !report.key?("fanControlOwnership") &&
      !report.key?("fanControlOwnershipStatusError")

    legacy_fans = report["fans"]
    legacy_count = report["fanCount"]
    legacy_inventory = legacy_fans.is_a?(Array) && !legacy_fans.empty? &&
      legacy_count.is_a?(Integer) && legacy_count.between?(1, 10) &&
      legacy_count == legacy_fans.length
    legacy_by_id = {}
    if legacy_inventory
      legacy_fans.each do |fan|
        unless fan.is_a?(Hash) && fan["id"].is_a?(Integer)
          legacy_inventory = false
          break
        end
        id = fan["id"]
        pair = [fan["hardwareMode"], fan["hardwareModeRawValue"]]
        key = fan["hardwareModeKey"]
        mode_safe = [["Auto", 0], ["System", 3]].include?(pair)
        key_safe = key.is_a?(String) && key.match?(/\AF#{id}[Mm]d\z/)
        if legacy_by_id.key?(id) || !mode_safe || !key_safe
          legacy_inventory = false
          break
        end
        legacy_by_id[id] = { "mode" => pair[0], "raw" => pair[1], "key" => key }
      end
      legacy_inventory &&= legacy_by_id.keys.sort == (0...legacy_count).to_a
    end

    agent = report["agentControl"]
    no_lease = agent.is_a?(Hash) && agent["activeLease"].nil? &&
      report["agentControlStatusError"].nil?
    runtime = report["daemonRuntime"]
    runtime_hashes_match = runtime.is_a?(Hash) &&
      runtime["installedDaemonPath"] == ARGV[3] &&
      runtime["expectedDaemonPath"] == ARGV[2] &&
      runtime["installedDaemonPresent"] == true &&
      runtime["expectedDaemonPresent"] == true &&
      runtime["matchRequired"] == true &&
      runtime["matchesExpectedDaemon"] == true &&
      runtime["installedDaemonSHA256"].is_a?(String) &&
      runtime["installedDaemonSHA256"].match?(/\A[0-9a-f]{64}\z/) &&
      runtime["installedDaemonSHA256"] == runtime["expectedDaemonSHA256"]
    legacy_safe = legacy_shape && legacy_inventory && no_lease && runtime_hashes_match &&
      report["daemonSnapshotError"].nil? &&
      report["isAppleSilicon"] == true && report["isMacBookPro"] == true &&
      report["manualControlActive"] == false

    header = probe_lines.find { |line| line.start_with?("model=") }
    count_line = probe_lines.find { |line| line.start_with?("fans=") }
    header_match = header&.match(/\Amodel=(\S+) appleSilicon=(true|false) macBookPro=(true|false)\z/)
    local_count = count_line&.match(/\Afans=(\d+)\z/)&.[](1)&.to_i
    fan_pattern = /\Afan\[(?<id>\d+)\] name="[^"]*" rpm=-?\d+ min=-?\d+ max=-?\d+ controllable=(?:true|false) hardwareMode=(?<mode>\S+) hardwareModeRawValue=(?<raw>-?\d+|nil) hardwareModeKey=(?<key>\S+) targetRPM=\S+ canApplyFixedRPM=(?:true|false) canRestoreOSManagedMode=(?<restore>true|false) controlIneligibilityReasons=(?<reasons>\S+)\z/
    local_matches = probe_lines.map { |line| line.match(fan_pattern) }.compact
    local_inventory = header_match && header_match[2] == "true" && header_match[3] == "true" &&
      local_count.is_a?(Integer) && local_count.between?(1, 10) &&
      local_matches.length == local_count
    local_by_id = {}
    restore_blockers = ["legacyUnspecified", "missingFanCount", "missingModeKey", "invalidFanID"]
    if local_inventory
      local_matches.each do |match|
        id = match[:id].to_i
        raw = match[:raw] == "nil" ? nil : match[:raw].to_i
        pair = [match[:mode], raw]
        reasons = match[:reasons] == "none" ? [] : match[:reasons].split(",")
        mode_safe = [["Auto", 0], ["System", 3]].include?(pair)
        key_safe = match[:key].match?(/\AF#{id}[Mm]d\z/)
        restore_safe = match[:restore] == "true" && (reasons & restore_blockers).empty?
        if local_by_id.key?(id) || !mode_safe || !key_safe || !restore_safe
          local_inventory = false
          break
        end
        local_by_id[id] = { "mode" => pair[0], "raw" => pair[1], "key" => match[:key] }
      end
      local_inventory &&= local_by_id.keys.sort == (0...local_count).to_a
    end

    inventories_agree = legacy_inventory && local_inventory &&
      header_match[1] == report["modelIdentifier"] &&
      legacy_count == local_count && legacy_by_id == local_by_id

    exit(legacy_safe && inventories_agree ? 0 : 75)
  ' "${legacy_report}" "${local_probe}" "${expected_daemon_path}" "${installed_daemon_path}"
}

protocol_v2_replacement_evidence_passes() {
  local report_path="$1"

  /usr/bin/ruby -rjson -e '
    begin
      report = JSON.parse(File.read(ARGV[0]))
    rescue StandardError
      exit 75
    end

    generated_at = report["generatedAt"]
    generated_at_unix = generated_at.is_a?(Numeric) ? generated_at.to_f + 978_307_200.0 : nil
    age_seconds = generated_at_unix ? Time.now.to_f - generated_at_unix : nil
    fresh = age_seconds && age_seconds >= -5.0 && age_seconds <= 60.0

    checks = report["checks"]
    required_attestation_checks = [
      "daemonSnapshotAvailable",
      "agentControlStatusAvailable",
      "fanControlOwnershipStatusAvailable",
      "daemonControlPathReady",
      "supportedHardware",
      "activeLeaseClear",
      "manualControlClear",
      "fanControlProtocolCurrent",
      "fanControlOwnershipStateValid",
      "fanControlRecoveryClear",
      "fanControlOwnershipClear",
      "fanControlHardwareConsistent",
      "replacementMaintenanceAttestation"
    ]
    attested = checks.is_a?(Array) && required_attestation_checks.all? do |id|
      matches = checks.select { |check| check.is_a?(Hash) && check["id"] == id }
      matches.length == 1 && matches.first["passed"] == true
    end

    fans = report["fans"]
    fan_count = report["fanCount"]
    inventory = fans.is_a?(Array) && !fans.empty? && fan_count.is_a?(Integer) &&
      fan_count == fans.length && fan_count.between?(1, 10)
    ids = inventory ? fans.map { |fan| fan["id"] } : []
    inventory &&= ids == (0...fan_count).to_a

    inventory_trust_blockers = ["legacyUnspecified", "missingFanCount", "missingModeKey", "invalidFanID"]
    modes_safe = inventory && fans.all? do |fan|
      id = fan["id"]
      mode_safe = [["Auto", 0], ["System", 3]].include?([fan["hardwareMode"], fan["hardwareModeRawValue"]])
      key_safe = fan["hardwareModeKey"].is_a?(String) && fan["hardwareModeKey"].match?(/\AF#{id}[Mm]d\z/)
      reasons = fan["controlIneligibilityReasons"]
      restore_safe = fan["canRestoreOSManagedMode"] == true && reasons.is_a?(Array) &&
        (reasons & inventory_trust_blockers).empty?
      mode_safe && key_safe && restore_safe
    end

    agent = report["agentControl"]
    lease_clear = agent.is_a?(Hash) && agent["activeLease"].nil? && report["agentControlStatusError"].nil?
    ownership = report["fanControlOwnership"]
    ownership_safe = ownership.is_a?(Hash) && ownership["protocolVersion"] == 2 &&
      ownership["owner"].nil? && ownership["phase"].nil? && ownership["transactionID"].nil? &&
      ownership["expectedFanIDs"] == [] && ownership["confirmedOSManagedFanIDs"] == [] &&
      ownership["recoveryPending"] == false && ownership["errorCode"].nil? && ownership["errorMessage"].nil? &&
      ownership["recoveryAttemptCount"].is_a?(Integer) && ownership["recoveryAttemptCount"] >= 0 &&
      report["fanControlOwnershipStatusError"].nil?
    supported_hardware = report["isAppleSilicon"] == true && report["isMacBookPro"] == true
    safe = report["schemaVersion"] == 1 && fresh && attested && supported_hardware &&
      report["daemonSnapshotError"].nil? && inventory && modes_safe && lease_clear && ownership_safe &&
      report["manualControlActive"] == false
    exit(safe ? 0 : 75)
  ' "${report_path}"
}

copy_stable_executable_to_run_dir() {
  local source="$1"
  local private_copy="$2"
  local source_sha_before
  local source_sha_after
  local private_sha

  [[ -f "${source}" && -x "${source}" && ! -L "${source}" ]] || return 1
  if ! source_sha_before="$(sha256_file "${source}")" ||
     [[ ! "${source_sha_before}" =~ ^[0-9a-f]{64}$ ]]; then
    return 1
  fi
  /bin/cp -p "${source}" "${private_copy}" || return 1
  /bin/chmod 500 "${private_copy}" || return 1
  [[ -f "${private_copy}" && -x "${private_copy}" && ! -L "${private_copy}" ]] || return 1
  if ! private_sha="$(sha256_file "${private_copy}")" ||
     [[ ! "${private_sha}" =~ ^[0-9a-f]{64}$ ]] ||
     ! source_sha_after="$(sha256_file "${source}")" ||
     [[ ! "${source_sha_after}" =~ ^[0-9a-f]{64}$ ]]; then
    return 1
  fi
  [[ "${source_sha_before}" == "${private_sha}" && "${private_sha}" == "${source_sha_after}" ]]
}

verify_root_staged_lifecycle() {
  local lifecycle="$1"
  local expected_sha="$2"
  local expected_owner=0
  local expected_flag=schg
  if [[ "${FIXTURE_CONTEXT_VALID}" == "1" ]]; then
    expected_owner="$(/usr/bin/id -u)"
    expected_flag=uchg
  fi
  [[ "${lifecycle}" == "${REPLACEMENT_LIFECYCLE_ROOT}/${REPLACEMENT_TRANSACTION_ID}/vifty-helper-lifecycle.sh" ]] || return 1
  local transaction_dir="${lifecycle%/*}"
  /usr/bin/ruby -e '
    path, transaction_dir, transaction_root, owner_text = ARGV; owner = Integer(owner_text, 10)
    root = File.lstat(transaction_root); dir = File.lstat(transaction_dir); file = File.lstat(path)
    exit 75 unless root.directory? && !root.symlink? && root.uid == owner && (root.mode & 0022).zero? &&
      dir.directory? && !dir.symlink? && dir.uid == owner && (dir.mode & 0022).zero? &&
      file.file? && !file.symlink? && file.uid == owner && file.nlink == 1 &&
      (file.mode & 0111) != 0 && (file.mode & 0022).zero? && file.size.between?(1, 1_048_576)
  ' "${lifecycle}" "${transaction_dir}" "${REPLACEMENT_LIFECYCLE_ROOT}" "${expected_owner}" || return 1
  local file_flags dir_flags actual_sha
  file_flags="$(/usr/bin/stat -f '%Sf' "${lifecycle}" 2>/dev/null)" || return 1
  dir_flags="$(/usr/bin/stat -f '%Sf' "${transaction_dir}" 2>/dev/null)" || return 1
  case ",${file_flags}," in *",${expected_flag},"*) ;; *) return 1 ;; esac
  case ",${dir_flags}," in *",${expected_flag},"*) ;; *) return 1 ;; esac
  actual_sha="$(sha256_file "${lifecycle}")" || return 1
  [[ "${actual_sha}" == "${expected_sha}" ]]
}

prepared_lifecycle_source_is_unchanged() {
  [[ -n "${REPLACEMENT_PREPARE_LIFECYCLE}" && -n "${REPLACEMENT_PREPARE_LIFECYCLE_SHA256}" ]] || return 1
  local current_sha
  current_sha="$(sha256_file "${REPLACEMENT_PREPARE_LIFECYCLE}")" || return 1
  [[ "${current_sha}" == "${REPLACEMENT_PREPARE_LIFECYCLE_SHA256}" ]]
}

prepare_replacement_authority_freeze() {
  [[ -n "${REPLACEMENT_LIFECYCLE_APP}" ]] || return 0
  if ! verify_candidate_bundle "${APP_DIR}"; then
    echo "error: candidate app identity changed after the initial build verification; refusing to execute its lifecycle or replace the existing app." >&2
    exit 75
  fi
  REPLACEMENT_FINISH_ALLOWED=0
  REPLACEMENT_PREPARE_LIFECYCLE="${RUN_DIR}/vifty-helper-lifecycle.$(/usr/bin/uuidgen | /usr/bin/tr 'A-F' 'a-f')"
  if ! copy_stable_executable_to_run_dir \
    "${HELPER_LIFECYCLE_SOURCE}" \
    "${REPLACEMENT_PREPARE_LIFECYCLE}"; then
    echo "error: the verified candidate helper lifecycle could not be isolated before replacement." >&2
    exit 75
  fi
  REPLACEMENT_PREPARE_LIFECYCLE_SHA256="$(sha256_file "${REPLACEMENT_PREPARE_LIFECYCLE}")" || exit 75
  if [[ "${INSTALL_MODE}" == "public-release" &&
        "${REPLACEMENT_PREPARE_LIFECYCLE_SHA256}" != "${PUBLIC_LIFECYCLE_SHA256}" ]]; then
    echo "error: isolated public-release lifecycle does not match the exact verified archive binding." >&2
    exit 75
  fi
  # This is a public correlation ID, not an authorization nonce. The durable
  # replacement ledger is root-private (0600); last-execution is only a 0644
  # operator-evidence mirror and is never replacement authority.
  REPLACEMENT_TRANSACTION_ID="$(/usr/bin/uuidgen | /usr/bin/tr 'A-F' 'a-f')" || {
    echo "error: could not generate the public replacement transaction correlation ID." >&2
    exit 75
  }
  [[ "${REPLACEMENT_TRANSACTION_ID}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || exit 75
  local prepare_status=0
  REPLACEMENT_STAGED_LIFECYCLE="${REPLACEMENT_LIFECYCLE_ROOT}/${REPLACEMENT_TRANSACTION_ID}/vifty-helper-lifecycle.sh"
  local prepare_arguments=(
    --operation repair
    --app "${REPLACEMENT_LIFECYCLE_APP}"
    --replacement-phase prepare
    --replacement-destination "${DEST_APP}"
    --replacement-transaction-id "${REPLACEMENT_TRANSACTION_ID}"
    --replacement-candidate "${APP_DIR}"
    --replacement-previous "${DEST_APP}"
    --replacement-lifecycle-source "${HELPER_LIFECYCLE_SOURCE}"
    --replacement-lifecycle-sha256 "${REPLACEMENT_PREPARE_LIFECYCLE_SHA256}"
  )
  if [[ "${INSTALL_MODE}" == "public-release" ]]; then
    prepare_arguments+=(
      --replacement-public-content-manifest-sha256 "${PUBLIC_CONTENT_MANIFEST_SHA256}"
      --replacement-public-previous-content-manifest-sha256 "${PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256}"
      --replacement-public-version "${PUBLIC_RELEASE_VERSION}"
      --replacement-public-build "${PUBLIC_RELEASE_BUILD}"
      --replacement-public-team-id "${PUBLIC_RELEASE_TEAM_ID}"
      --replacement-public-archive-sha256 "${PUBLIC_RELEASE_SHA256}"
    )
  fi
  if "${REPLACEMENT_PREPARE_LIFECYCLE}" "${prepare_arguments[@]}"; then
    prepare_status=0
  else
    prepare_status=$?
  fi
  if [[ "${prepare_status}" -ne 0 ]]; then
    if [[ "${prepare_status}" -ne 75 ]]; then
      REPLACEMENT_AUTHORITY_STATE="unknown-active"
      echo "HARD FAILURE: replacement prepare exited with status ${prepare_status}; helper authority is active or unknown, so no copy, rollback, retry, or fallback is allowed." >&2
      exit 76
    fi
    echo "error: the authoritative helper could not be quiesced, restored, confirmed, and frozen before replacement." >&2
    exit 75
  fi
  REPLACEMENT_AUTHORITY_STATE="frozen"
  if ! prepared_lifecycle_source_is_unchanged ||
     ! verify_root_staged_lifecycle "${REPLACEMENT_STAGED_LIFECYCLE}" "${REPLACEMENT_PREPARE_LIFECYCLE_SHA256}"; then
    echo "error: lifecycle source changed after root staging or the immutable root-staged copy failed exact verification; helper authority remains frozen." >&2
    exit 75
  fi
  REPLACEMENT_LIFECYCLE="${REPLACEMENT_STAGED_LIFECYCLE}"
  REPLACEMENT_FINISH_ALLOWED=1
}

finish_replacement_authority_freeze() {
  local replacement_result="${1:-}"
  case "${replacement_result}" in installed|rolled-back) ;; *) return 75 ;; esac
  if [[ "${REPLACEMENT_AUTHORITY_STATE}" == "unknown-active" ]]; then
    return 76
  fi
  [[ "${REPLACEMENT_AUTHORITY_STATE}" == "frozen" ]] || return 0
  [[ "${REPLACEMENT_FINISH_ALLOWED}" == "1" ]] || return 75
  prepared_lifecycle_source_is_unchanged || return 75
  verify_root_staged_lifecycle "${REPLACEMENT_LIFECYCLE}" "${REPLACEMENT_PREPARE_LIFECYCLE_SHA256}" || return 75
  local finish_status
  if "${REPLACEMENT_LIFECYCLE}" \
    --operation repair \
    --app "${DEST_APP}" \
    --replacement-phase finish \
    --replacement-destination "${DEST_APP}" \
    --replacement-transaction-id "${REPLACEMENT_TRANSACTION_ID}" \
    --replacement-result "${replacement_result}"; then
    finish_status=0
  else
    finish_status=$?
  fi
  if [[ "${finish_status}" -ne 0 ]]; then
    if [[ "${finish_status}" -eq 75 ]]; then
      echo "error: the replacement bundle is verified, but helper registration could not be safely resumed; helper authority is still proven disabled and offline." >&2
      return 75
    fi
    REPLACEMENT_AUTHORITY_STATE="unknown-active"
    echo "HARD FAILURE: replacement finish exited with status ${finish_status} and could not prove a frozen helper; preserving the verified new bundle instead of rolling back beneath possibly active authority." >&2
    return 76
  fi
  REPLACEMENT_AUTHORITY_STATE="resumed"
}

release_replacement_lock_for_rollback() {
  [[ "${REPLACEMENT_AUTHORITY_STATE}" == "frozen" && "${REPLACEMENT_FINISH_ALLOWED}" == "1" ]] || return 75
  prepared_lifecycle_source_is_unchanged || return 75
  verify_root_staged_lifecycle "${REPLACEMENT_LIFECYCLE}" "${REPLACEMENT_PREPARE_LIFECYCLE_SHA256}" || return 75
  local release_status
  if "${REPLACEMENT_LIFECYCLE}" \
    --operation repair \
    --app "${DEST_APP}" \
    --replacement-phase release-lock \
    --replacement-destination "${DEST_APP}" \
    --replacement-transaction-id "${REPLACEMENT_TRANSACTION_ID}" \
    --replacement-result installed; then
    return 0
  else
    release_status=$?
  fi
  if [[ "${release_status}" -ne 75 ]]; then
    REPLACEMENT_AUTHORITY_STATE="unknown-active"
    return 76
  fi
  return 75
}

restore_install_signal_traps() {
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

complete_replacement_after_successful_copy() {
  if [[ "${REPLACEMENT_AUTHORITY_STATE}" == "unknown-active" ]]; then
    return 76
  fi
  [[ "${REPLACEMENT_AUTHORITY_STATE}" == "frozen" ]] || return 0
  local finish_status
  local rollback_finish_status
  trap '' HUP INT TERM
  if finish_replacement_authority_freeze installed; then
    finish_status=0
  else
    finish_status=$?
  fi
  if [[ "${finish_status}" -eq 0 ]]; then
    commit_verified_copy
    restore_install_signal_traps
    return 0
  fi
  if [[ "${finish_status}" -eq 76 ]]; then
    # Never roll back beneath authority that may already be active. Keep the
    # previous bundle in the transaction stage for explicit operator recovery.
    COPY_ROLLBACK_ACTIVE=0
    restore_install_signal_traps
    echo "HARD FAILURE: helper authority is active or unknown after replacement finish; the verified destination is preserved and recovery material remains at ${COPY_ROLLBACK_STAGE}." >&2
    return 76
  fi

  local release_status=0
  if release_replacement_lock_for_rollback; then
    release_status=0
  else
    release_status=$?
  fi
  if [[ "${release_status}" -ne 0 ]]; then
    COPY_ROLLBACK_ACTIVE=0
    restore_install_signal_traps
    if [[ "${release_status}" -eq 76 ]]; then
      echo "HARD FAILURE: replacement lock release left helper authority active or unknown; preserving the exact destination and recovery material without rollback." >&2
      return 76
    fi
    echo "HARD FAILURE: replacement registration failed and its root-controlled lock could not be safely released; preserving the exact destination and recovery material while helper authority remains frozen." >&2
    return 75
  fi

  if [[ "${COPY_ROLLBACK_ACTIVE}" == "1" ]] &&
     rollback_interrupted_copy &&
     verify_install_bundle "${DEST_APP}"; then
    rollback_finish_status=0
    if finish_replacement_authority_freeze rolled-back; then
      rollback_finish_status=0
    else
      rollback_finish_status=$?
    fi
    if [[ "${rollback_finish_status}" -eq 0 ]]; then
      remove_completed_copy_stage || true
      restore_install_signal_traps
      echo "error: replacement helper registration failed; the verified previous app was restored and re-registered instead." >&2
      return 75
    elif [[ "${rollback_finish_status}" -eq 76 ]]; then
      restore_install_signal_traps
      echo "HARD FAILURE: previous bundle rollback completed, but helper authority is active or unknown; preserving recovery material with no second finish." >&2
      return 76
    fi
  fi

  restore_install_signal_traps
  echo "HARD FAILURE: replacement registration failed and the previous app could not be both restored and re-registered; helper authority was last proven disabled and offline." >&2
  return 75
}

resume_replacement_authority_after_failed_copy() {
  if [[ "${REPLACEMENT_AUTHORITY_STATE}" == "unknown-active" ]]; then
    return 76
  fi
  [[ "${REPLACEMENT_AUTHORITY_STATE}" == "frozen" ]] || return 0
  verify_install_bundle "${DEST_APP}" || return 75
  finish_replacement_authority_freeze rolled-back
}

preflight_existing_install_before_replacement() {
  if [[ "${REPLACEMENT_AUTHORITY_STATE}" == "unknown-active" ]]; then
    echo "HARD FAILURE: helper authority is active or unknown; refusing any second preflight, finish, rollback, or fallback." >&2
    exit 76
  fi
  if [[ "${REPLACEMENT_AUTHORITY_STATE}" == "frozen" ]]; then
    echo "HARD FAILURE: a prior replacement freeze is still active; refusing to overwrite its transaction state." >&2
    exit 75
  fi
  REPLACEMENT_LIFECYCLE_APP=""
  local existing_main="${DEST_APP}/Contents/MacOS/Vifty"
  local existing_ctl="${DEST_APP}/Contents/MacOS/viftyctl"
  if [[ -L "${DEST_APP}" ]]; then
    echo "error: existing Vifty app root is a symbolic link; refusing replacement before executing or copying anything." >&2
    exit 75
  fi
  if ! path_exists_without_following "${DEST_APP}"; then
    if [[ "${INSTALL_MODE}" == "public-release" ]]; then
      local daemon_plist_target="/Library/LaunchDaemons/${DAEMON_BUNDLE_ID}.plist"
      if path_exists_without_following "${HELPER_TARGET}" ||
         path_exists_without_following "${daemon_plist_target}" ||
         /bin/launchctl print "system/${DAEMON_BUNDLE_ID}" >/dev/null 2>&1; then
        echo "error: no destination app exists, but privileged Vifty helper authority or registration remains; repair or uninstall it before a fresh public-release install." >&2
        exit 75
      fi
      PUBLIC_DESTINATION_EXPECTATION="absent"
    fi
    return 0
  fi
  if [[ "${INSTALL_MODE}" == "public-release" ]]; then
    PUBLIC_DESTINATION_EXPECTATION="present"
  fi
  [[ -d "${DEST_APP}" ]] || {
    echo "error: existing Vifty app root is not a directory; refusing replacement." >&2
    exit 75
  }

  if [[ ! -x "${existing_main}" ]]; then
    echo "error: existing Vifty install has no executable main app safety interface; refusing replacement." >&2
    echo "error: Reboot/recover or restore a complete existing install before replacing its recovery UI." >&2
    exit 75
  fi

  if published_v132_source_is_allowlisted; then
    REPLACEMENT_LIFECYCLE_APP="${APP_DIR}"
    local private_v132_dir
    if ! private_v132_dir="$(/usr/bin/mktemp -d "${RUN_DIR}/published-v1.3.2.XXXXXXXX")" ||
       [[ -z "${private_v132_dir}" || "${private_v132_dir%/*}" != "${RUN_DIR}" ]]; then
      echo "error: could not create private published-v1.3.2 diagnosis directory." >&2
      exit 75
    fi
    local private_v132_ctl="${private_v132_dir}/viftyctl"
    local private_v132_daemon="${private_v132_dir}/ViftyDaemon"
    local legacy_report="${RUN_DIR}/published-v1.3.2-diagnose.json"
    local legacy_diagnose_status
    /bin/chmod 700 "${private_v132_dir}"
    if ! copy_stable_executable_to_run_dir "${existing_ctl}" "${private_v132_ctl}" ||
       ! copy_stable_executable_to_run_dir "${DEST_APP}/Contents/MacOS/ViftyDaemon" "${private_v132_daemon}"; then
      echo "error: exact published-v1.3.2 executables changed while being isolated for diagnosis; refusing migration." >&2
      exit 75
    fi
    if [[ "${FIXTURE_PUBLISHED_V132}" != "1" ]]; then
      signed_component_matches "${private_v132_ctl}" "${CTL_BUNDLE_ID}" "${PUBLISHED_V132_CTL_SHA256}" "${PUBLISHED_V132_CTL_CDHASH}" || {
        echo "error: private published-v1.3.2 viftyctl copy failed canonical Developer ID verification; refusing migration." >&2
        exit 75
      }
      signed_component_matches "${private_v132_daemon}" "${DAEMON_BUNDLE_ID}" "${PUBLISHED_V132_DAEMON_SHA256}" "${PUBLISHED_V132_DAEMON_CDHASH}" || {
        echo "error: private published-v1.3.2 daemon copy failed canonical Developer ID verification; refusing migration." >&2
        exit 75
      }
    fi
    local private_ctl_sha_before
    local private_ctl_sha_after
    if ! private_ctl_sha_before="$(sha256_file "${private_v132_ctl}")" ||
       [[ ! "${private_ctl_sha_before}" =~ ^[0-9a-f]{64}$ ]]; then
      echo "error: could not hash private published-v1.3.2 viftyctl; refusing migration." >&2
      exit 75
    fi
    set +e
    "${private_v132_ctl}" diagnose --json >"${legacy_report}" 2>"${RUN_DIR}/published-v1.3.2-diagnose.err"
    legacy_diagnose_status=$?
    set -e
    if ! private_ctl_sha_after="$(sha256_file "${private_v132_ctl}")" ||
       [[ ! "${private_ctl_sha_after}" =~ ^[0-9a-f]{64}$ ]]; then
      echo "error: could not re-hash private published-v1.3.2 viftyctl; refusing migration." >&2
      exit 75
    fi
    if [[ "${private_ctl_sha_before}" != "${private_ctl_sha_after}" || "${legacy_diagnose_status}" -ne 0 ]]; then
      echo "error: private published-v1.3.2 diagnose failed or changed during execution; refusing replacement." >&2
      exit 75
    fi

    local migration_probe_source="${APP_DIR}/Contents/MacOS/ViftyHelper"
    local migration_probe="${private_v132_dir}/ViftyHelper-probe"
    local migration_probe_output="${RUN_DIR}/published-v1.3.2-local-probe.txt"
    local migration_probe_error="${RUN_DIR}/published-v1.3.2-local-probe.err"
    if ! copy_stable_executable_to_run_dir "${migration_probe_source}" "${migration_probe}"; then
      echo "error: exact new app bundle has no stable regular executable ViftyHelper read-only probe; refusing published-v1.3.2 migration." >&2
      exit 75
    fi
    if [[ "${INSTALL_MODE}" == "public-release" ]]; then
      local isolated_probe_sha
      isolated_probe_sha="$(sha256_file "${migration_probe}")" || exit 75
      if [[ "${isolated_probe_sha}" != "${PUBLIC_HELPER_SHA256}" ]] ||
         ! public_release_component_matches "${migration_probe}" "${HELPER_BUNDLE_ID}"; then
        echo "error: isolated helper probe does not match the exact verified public archive Developer ID binding." >&2
        exit 75
      fi
    fi

    local migration_probe_sha_before
    local migration_probe_sha_after
    local migration_probe_status
    if ! migration_probe_sha_before="$(sha256_file "${migration_probe}")" ||
       [[ ! "${migration_probe_sha_before}" =~ ^[0-9a-f]{64}$ ]]; then
      echo "error: could not hash isolated new-bundle helper probe; refusing migration." >&2
      exit 75
    fi
    set +e
    "${migration_probe}" probeLocal >"${migration_probe_output}" 2>"${migration_probe_error}"
    migration_probe_status=$?
    set -e
    if ! migration_probe_sha_after="$(sha256_file "${migration_probe}")" ||
       [[ ! "${migration_probe_sha_after}" =~ ^[0-9a-f]{64}$ ]]; then
      echo "error: could not re-hash isolated new-bundle helper probe; refusing migration." >&2
      exit 75
    fi
    if [[ "${migration_probe_status}" -ne 0 || "${migration_probe_sha_before}" != "${migration_probe_sha_after}" ]]; then
      echo "error: exact new-bundle read-only local fan probe failed or changed during execution; refusing published-v1.3.2 migration." >&2
      exit 75
    fi

    if ! legacy_v132_replacement_evidence_passes \
      "${legacy_report}" \
      "${migration_probe_output}" \
      "${private_v132_daemon}" \
      "${HELPER_TARGET}"; then
      echo "error: published v1.3.2 legacy state and the exact new-bundle local fan inventory did not provide matching complete Auto/System proof; refusing replacement." >&2
      echo "error: No helper stop, helper replacement, maintenance command, or fan write was attempted." >&2
      exit 75
    fi

    echo "==> Published v1.3.2/build 7 passed the read-only migration preflight using canonical private CLI evidence and exact new-bundle local Auto/System inventory proof."
    return 0
  fi

  local existing_source_kind=""
  if existing_developer_id_source_is_authenticated; then
    existing_source_kind="developer-id"
  elif existing_adhoc_development_source_is_authenticated; then
    existing_source_kind="adhoc-exact-path"
  elif [[ "${FIXTURE_PROTOCOL_V2}" == "1" ]]; then
    existing_source_kind="fixture-private-copy"
  else
    echo "error: existing app is neither canonical v1.3.2 nor an authenticated Developer ID or explicit exact-path ad-hoc development source; refusing replacement without executing its CLI." >&2
    exit 75
  fi

  local authenticated_ctl="${existing_ctl}"
  local existing_report="${RUN_DIR}/authenticated-existing-diagnose.json"
  local authenticated_ctl_sha_before
  local authenticated_ctl_sha_after
  if [[ "${existing_source_kind}" != "adhoc-exact-path" ]]; then
    local private_existing_dir
    if ! private_existing_dir="$(/usr/bin/mktemp -d "${RUN_DIR}/authenticated-existing.XXXXXXXX")" ||
       [[ -z "${private_existing_dir}" || "${private_existing_dir%/*}" != "${RUN_DIR}" ]]; then
      echo "error: could not create private authenticated-existing diagnosis directory." >&2
      exit 75
    fi
    authenticated_ctl="${private_existing_dir}/viftyctl"
    /bin/chmod 700 "${private_existing_dir}"
    if ! copy_stable_executable_to_run_dir "${existing_ctl}" "${authenticated_ctl}" ||
       ! copy_stable_executable_to_run_dir "${DEST_APP}/Contents/MacOS/ViftyDaemon" "${private_existing_dir}/ViftyDaemon"; then
      echo "error: authenticated existing executables changed while being isolated; refusing replacement." >&2
      exit 75
    fi
    if [[ "${existing_source_kind}" == "developer-id" ]]; then
      developer_id_component_matches "${authenticated_ctl}" "${CTL_BUNDLE_ID}" || exit 75
      developer_id_component_matches "${private_existing_dir}/ViftyDaemon" "${DAEMON_BUNDLE_ID}" || exit 75
    fi
  fi

  if ! authenticated_ctl_sha_before="$(sha256_file "${authenticated_ctl}")" ||
     [[ ! "${authenticated_ctl_sha_before}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: could not hash authenticated existing viftyctl; refusing replacement." >&2
    exit 75
  fi
  set +e
  "${authenticated_ctl}" diagnose --json >"${existing_report}" 2>"${RUN_DIR}/authenticated-existing-diagnose.err"
  local existing_diagnose_status=$?
  set -e
  if ! authenticated_ctl_sha_after="$(sha256_file "${authenticated_ctl}")" ||
     [[ ! "${authenticated_ctl_sha_after}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: could not re-hash authenticated existing viftyctl; refusing replacement." >&2
    exit 75
  fi
  if [[ "${authenticated_ctl_sha_before}" != "${authenticated_ctl_sha_after}" ]]; then
    echo "error: authenticated existing viftyctl changed during diagnosis; refusing replacement." >&2
    exit 75
  fi
  if [[ "${existing_diagnose_status}" -eq 0 ]] && protocol_v2_replacement_evidence_passes "${existing_report}"; then
    REPLACEMENT_LIFECYCLE_APP="${DEST_APP}"
    echo "==> Existing authenticated ${existing_source_kind} install passed protocol-v2 Auto/System replacement preflight (diagnose exit ${existing_diagnose_status})."
    return 0
  fi
  echo "error: authenticated existing protocol-v2 diagnosis did not provide complete Auto/System ownership proof; refusing replacement." >&2
  exit 75
}

case "${ENABLE_ADHOC_XPC}" in
  0|1) ;;
  *)
    echo "error: VIFTY_ENABLE_ADHOC_XPC must be 0 or 1." >&2
    exit 64
    ;;
esac
case "${FIXTURE_SYSTEM_FALLBACK}" in
  0) ;;
  1)
    [[ "${FIXTURE_CONTEXT_VALID}" == "1" ]] || {
      echo "error: VIFTY_INSTALL_FIXTURE_SYSTEM_FALLBACK requires the validated fixture root." >&2
      exit 65
    }
    ;;
  *)
    echo "error: VIFTY_INSTALL_FIXTURE_SYSTEM_FALLBACK must be 0 or 1." >&2
    exit 64
    ;;
esac
case "${FIXTURE_PUBLISHED_V132}" in
  0) ;;
  1)
    [[ "${FIXTURE_CONTEXT_VALID}" == "1" ]] || {
      echo "error: VIFTY_INSTALL_FIXTURE_PUBLISHED_V132 requires the validated fixture root." >&2
      exit 65
    }
    ;;
  *)
    echo "error: VIFTY_INSTALL_FIXTURE_PUBLISHED_V132 must be 0 or 1." >&2
    exit 64
    ;;
esac
case "${FIXTURE_PROTOCOL_V2}" in
  0) ;;
  1)
    [[ "${FIXTURE_CONTEXT_VALID}" == "1" ]] || {
      echo "error: VIFTY_INSTALL_FIXTURE_PROTOCOL_V2 requires the validated fixture root." >&2
      exit 65
    }
    ;;
  *)
    echo "error: VIFTY_INSTALL_FIXTURE_PROTOCOL_V2 must be 0 or 1." >&2
    exit 64
    ;;
esac
for test_failure_fixture in \
  "${FIXTURE_STAGE_MKTEMP_FAILURE}" \
  "${FIXTURE_SHA256_FAILURE}" \
  "${FIXTURE_ROLLBACK_RESTORE_FAILURE}" \
  "${FIXTURE_POST_SWAP_VERIFICATION_FAILURE}" \
  "${FIXTURE_HIDE_PREVIOUS_BEFORE_ROLLBACK}" \
  "${FIXTURE_UNSIGNED_BUILD}" \
  "${FIXTURE_NO_RUNNING_APP}" \
  "${FIXTURE_MUTATE_LIFECYCLE_AFTER_PREPARE}"; do
  case "${test_failure_fixture}" in
    0|1) ;;
    *)
      echo "error: install failure-injection fixture values must be 0 or 1." >&2
      exit 64
      ;;
  esac
done
if [[ "${FIXTURE_STAGE_MKTEMP_FAILURE}${FIXTURE_SHA256_FAILURE}${FIXTURE_ROLLBACK_RESTORE_FAILURE}${FIXTURE_POST_SWAP_VERIFICATION_FAILURE}${FIXTURE_HIDE_PREVIOUS_BEFORE_ROLLBACK}${FIXTURE_UNSIGNED_BUILD}${FIXTURE_MUTATE_LIFECYCLE_AFTER_PREPARE}" != "0000000" ]]; then
  [[ "${FIXTURE_CONTEXT_VALID}" == "1" ]] || {
    echo "error: install failure-injection fixtures require the validated fixture root." >&2
    exit 65
  }
fi
if [[ "${ENABLE_ADHOC_XPC}" == "1" && "${CONFIGURATION}" == "release" ]]; then
  echo "error: VIFTY_ENABLE_ADHOC_XPC=1 is debug-only and is forbidden for release installs." >&2
  exit 65
fi

if ! /bin/mkdir -p "${INSTALL_DIR}" 2>/dev/null || [[ ! -w "${INSTALL_DIR}" ]]; then
  if [[ "${INSTALL_MODE}" == "public-release" ]] && path_exists_without_following "${DEST_APP}"; then
    echo "error: the existing public-release destination ${DEST_APP} cannot be replaced in place; refusing to create a second installation." >&2
    exit 75
  fi
  echo "==> ${INSTALL_DIR} is not writable; installing to ~/Applications instead"
  fallback_to_user_applications
fi
ADHOC_UID="$(/usr/bin/id -u)"

if [[ "${INSTALL_MODE}" == "public-release" ]]; then
  validate_public_install_destination || {
    echo "error: public-release install destination must be a canonical non-symlink Applications directory." >&2
    exit 75
  }
  acquire_public_install_lock || exit 75
  prepare_public_release_candidate || exit 75
  public_release_is_not_a_downgrade || {
    echo "error: refusing to replace an authenticated newer installed Vifty with published ${PUBLIC_RELEASE_VERSION} build ${PUBLIC_RELEASE_BUILD}." >&2
    exit 75
  }
else
  echo "==> Building ${APP_NAME}.app (${CONFIGURATION})"
  cd "${ROOT_DIR}"
  build_app_bundle
fi

if [[ ! -d "${APP_DIR}" ]]; then
  echo "error: expected app bundle was not created: ${APP_DIR}" >&2
  exit 1
fi

if [[ ! -x "${APP_DIR}/Contents/MacOS/${APP_NAME}" ]]; then
  echo "error: app executable is missing or not executable: ${APP_DIR}/Contents/MacOS/${APP_NAME}" >&2
  exit 1
fi

if ! verify_candidate_bundle "${APP_DIR}"; then
  echo "error: candidate app bundle failed the required install verification before replacement preflight." >&2
  exit 1
fi

quit_running_app_if_needed
if [[ "${INSTALL_MODE}" == "public-release" ]]; then
  if path_exists_without_following "${DEST_APP}"; then
    PUBLIC_PRECHECK_DESTINATION_EXPECTATION="present"
    PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256="$(public_tree_sha256 "${DEST_APP}")" || {
      echo "error: existing public destination could not be bound before replacement preflight." >&2
      exit 75
    }
  else
    PUBLIC_PRECHECK_DESTINATION_EXPECTATION="absent"
  fi
fi
preflight_existing_install_before_replacement
if [[ "${INSTALL_MODE}" == "public-release" ]]; then
  [[ "${PUBLIC_DESTINATION_EXPECTATION}" == "${PUBLIC_PRECHECK_DESTINATION_EXPECTATION}" ]] || {
    echo "error: public destination presence changed during replacement preflight." >&2
    exit 75
  }
  if [[ "${PUBLIC_DESTINATION_EXPECTATION}" == "present" ]]; then
    system_tool_environment /usr/bin/ruby "${ROOT_DIR}/scripts/release-candidate-inventory.rb" verify-public-tree \
      --app "${DEST_APP}" \
      --expected-content-manifest-sha256 "${PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256}" >/dev/null || {
      echo "error: public destination content changed during replacement preflight." >&2
      exit 75
    }
  fi
fi
prepare_replacement_authority_freeze
if [[ "${REPLACEMENT_AUTHORITY_STATE}" == "frozen" ]] &&
   { ! prepared_lifecycle_source_is_unchanged ||
     ! verify_root_staged_lifecycle "${REPLACEMENT_LIFECYCLE}" "${REPLACEMENT_PREPARE_LIFECYCLE_SHA256}"; }; then
  REPLACEMENT_FINISH_ALLOWED=0
  echo "error: lifecycle source changed after root staging; refusing copy, registrar, retry, rollback, or fallback while helper authority remains frozen." >&2
  exit 75
fi

echo "==> Installing to ${DEST_APP}"
if ! copy_app_bundle "${APP_DIR}" "${DEST_APP}" 2>"${ERR_LOG}"; then
  if [[ "${COPY_ROLLBACK_ACTIVE}" == "0" && "${REPLACEMENT_AUTHORITY_STATE}" == "frozen" ]]; then
    resume_status=0
    if resume_replacement_authority_after_failed_copy; then
      resume_status=0
    else
      resume_status=$?
    fi
    if [[ "${resume_status}" -eq 76 ]]; then
      /bin/cat "${ERR_LOG}" >&2 || true
      echo "HARD FAILURE: the app copy failed and helper authority is active or unknown; preserving the verified destination with no second finish, rollback, or fallback." >&2
      exit 76
    elif [[ "${resume_status}" -ne 0 ]]; then
      /bin/cat "${ERR_LOG}" >&2 || true
      echo "HARD FAILURE: the app copy failed and the previous bundle could not be safely re-registered; helper authority was last proven disabled and offline." >&2
      exit 75
    fi
  fi
  if [[ "${COPY_ROLLBACK_ACTIVE}" == "1" ]]; then
    /bin/cat "${ERR_LOG}" >&2 || true
    echo "HARD FAILURE: install rollback remains unresolved and helper authority was last proven disabled and offline; refusing fallback or retry. Recover the previous app from ${COPY_ROLLBACK_PREVIOUS}" >&2
    exit 75
  fi
  if [[ "${ENABLE_ADHOC_XPC}" == "1" ]]; then
    /bin/cat "${ERR_LOG}" >&2 || true
    echo "error: ad-hoc XPC trust is bound to ${DEST_APP}; refusing path fallback after copy failure." >&2
    exit 1
  fi
  if [[ "${INSTALL_MODE}" == "public-release" ]]; then
    /bin/cat "${ERR_LOG}" >&2 || true
    echo "error: verified public-release replacement failed; refusing a second destination, fallback, or retry." >&2
    exit 1
  elif [[ "${INSTALL_DIR}" == "/Applications" || "${FIXTURE_SYSTEM_FALLBACK}" == "1" ]]; then
    echo "==> Could not write /Applications; installing to ~/Applications instead"
    fallback_to_user_applications
    preflight_existing_install_before_replacement
    prepare_replacement_authority_freeze
    if ! copy_app_bundle "${APP_DIR}" "${DEST_APP}"; then
      if [[ "${COPY_ROLLBACK_ACTIVE}" == "0" && "${REPLACEMENT_AUTHORITY_STATE}" == "frozen" ]]; then
        fallback_resume_status=0
        if resume_replacement_authority_after_failed_copy; then
          fallback_resume_status=0
        else
          fallback_resume_status=$?
        fi
        if [[ "${fallback_resume_status}" -eq 76 ]]; then
          echo "HARD FAILURE: fallback copy failed and helper authority is active or unknown; preserving the verified destination with no second finish or rollback." >&2
          exit 76
        elif [[ "${fallback_resume_status}" -ne 0 ]]; then
          echo "HARD FAILURE: fallback copy failed and the previous fallback bundle could not be safely re-registered; helper authority was last proven disabled and offline." >&2
          exit 75
        fi
      fi
      if [[ "${COPY_ROLLBACK_ACTIVE}" == "1" ]]; then
        echo "HARD FAILURE: fallback install rollback remains unresolved. Recover the previous app from ${COPY_ROLLBACK_PREVIOUS}" >&2
        exit 75
      fi
      exit 1
    fi
  else
    /bin/cat "${ERR_LOG}" >&2 || true
    exit 1
  fi
fi

complete_replacement_after_successful_copy

if [[ "${INSTALL_MODE}" == "public-release" ]]; then
  echo "==> Public archive, extracted candidate, staged copy, and installed app passed exact content, Developer ID, notarization, Gatekeeper, and byte-identity verification"
else
  echo "==> Source, staged, and installed app bundles passed byte-identity and deep code-signature verification"
fi
report_helper_daemon_status

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -f "${DEST_APP}" >/dev/null 2>&1 || true
fi

echo ""
echo "Installed ${APP_NAME}:"
echo "  ${DEST_APP}"
echo ""
echo "Start it from Spotlight/Launchpad/Finder, or run:"
echo "  open \"${DEST_APP}\""

if [[ "${OPEN_AFTER_INSTALL}" == "1" || "${WAS_RUNNING}" == "1" ]]; then
  echo "==> Launching ${APP_NAME}"
  /usr/bin/open "${DEST_APP}"
fi
