#!/usr/bin/env -S -i HOME=/var/empty PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash --noprofile --norc
set -euo pipefail

OPERATION=""
APP_PATH="${VIFTY_APP:-/Applications/Vifty.app}"
REPLACEMENT_PHASE=""
REPLACEMENT_DESTINATION=""
REPLACEMENT_TRANSACTION_ID=""
REPLACEMENT_CANDIDATE_APP=""
REPLACEMENT_PREVIOUS_APP=""
REPLACEMENT_RESULT=""
REPLACEMENT_LIFECYCLE_SOURCE=""
REPLACEMENT_LIFECYCLE_EXPECTED_SHA256=""
REPLACEMENT_PUBLIC_CONTENT_MANIFEST_SHA256=""
REPLACEMENT_PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256=""
REPLACEMENT_PUBLIC_VERSION=""
REPLACEMENT_PUBLIC_BUILD=""
REPLACEMENT_PUBLIC_TEAM_ID=""
REPLACEMENT_PUBLIC_ARCHIVE_SHA256=""
REPLACEMENT_PUBLIC_CANDIDATE_EXPECTATION=""
REPLACEMENT_LIFECYCLE_STAGED_PATH=""
REPLACEMENT_LIFECYCLE_STAGED_SHA256=""
REPLACEMENT_CANDIDATE_SNAPSHOT_APP=""
REPLACEMENT_CANDIDATE_BINDING=""
REPLACEMENT_PREVIOUS_BINDING=""
REPLACEMENT_LOCKED_BINDING=""
DRY_RUN=0
RECORD_PATH=""
MAINTENANCE_REPORT=""
CALLER_UID="$(/usr/bin/id -u)"
REQUESTING_USER_UID="${CALLER_UID}"
REQUESTING_PROCESS_ID="$$"
REQUESTING_PROCESS_START_ID=""
ROOT_FIXTURE_SIGNAL="${VIFTY_FIXTURE_ROOT_SIGNAL:-}"
ROOT_FIXTURE_RETURN_INCOMPLETE="${VIFTY_FIXTURE_ROOT_RETURN_INCOMPLETE:-0}"
ROOT_FIXTURE_CORRUPT_COMPLETION="${VIFTY_FIXTURE_CORRUPT_COMPLETION:-0}"
ROOT_FIXTURE_SWAP_BEFORE_REGISTER="${VIFTY_FIXTURE_SWAP_BEFORE_REGISTER:-0}"
ROOT_FIXTURE_SWAP_BEFORE_ENABLE="${VIFTY_FIXTURE_SWAP_BEFORE_ENABLE:-0}"
ROOT_FIXTURE_ALTERNATE_APP="${VIFTY_FIXTURE_ALTERNATE_APP:-}"
ROOT_FIXTURE_LOCK_RECORD_FAILURE="${VIFTY_FIXTURE_LOCK_RECORD_FAILURE:-0}"
ROOT_FIXTURE_PARTIAL_LOCK="${VIFTY_FIXTURE_PARTIAL_LOCK:-0}"
ROOT_FIXTURE_PARTIAL_UNLOCK="${VIFTY_FIXTURE_PARTIAL_UNLOCK:-0}"
ROOT_FIXTURE_EXIT_AFTER_LOCK="${VIFTY_FIXTURE_EXIT_AFTER_LOCK:-0}"
ROOT_FIXTURE_EXIT_AFTER_UNLOCK="${VIFTY_FIXTURE_EXIT_AFTER_UNLOCK:-0}"
ROOT_FIXTURE_RECORD_POST_RENAME_FAILURE="${VIFTY_FIXTURE_RECORD_POST_RENAME_FAILURE:-}"
ROOT_FIXTURE_SWAP_CANDIDATE_AFTER_SNAPSHOT="${VIFTY_FIXTURE_SWAP_CANDIDATE_AFTER_SNAPSHOT:-0}"
ROOT_FIXTURE_SWAP_CANDIDATE_DURING_SNAPSHOT="${VIFTY_FIXTURE_SWAP_CANDIDATE_DURING_SNAPSHOT:-0}"
FIXTURE_INVOCATION_LOG="${VIFTY_FIXTURE_INVOCATION_LOG:-}"
PHASE_LOG=""
TEST_ROOT="${VIFTY_LIFECYCLE_TEST_ROOT:-}"
FIXTURE_PARENT_START_SOURCE="${VIFTY_FIXTURE_PARENT_START_ID:-}"
RUN_DIR=""
REPORT_PATH=""
SERVICE_PATH=""
HELPER_SNAPSHOT=""
HELPER_SNAPSHOT_SHA256=""
RECORD_TMP=""
STATUS="blocked"
BLOCKER="Helper maintenance has not completed."
TOKEN_CONSUMED=0
OFFLINE_AUTHORITY_REQUIRED=0
ROOT_AUTHORITY_EXPECTATION=""

cleanup() {
  if [[ -n "${RUN_DIR}" && -d "${RUN_DIR}" ]]; then
    /bin/rm -rf "${RUN_DIR}"
  fi
  if [[ -n "${RECORD_TMP}" && -e "${RECORD_TMP}" ]]; then
    /bin/rm -f "${RECORD_TMP}"
  fi
}
outer_signal_exit() {
  local code="$1"
  trap - HUP INT TERM
  exit "${code}"
}

process_start_identity() {
  local pid="$1"
  local uid="$2"
  local start_source=""
  if [[ -n "${TEST_ROOT}" && -n "${FIXTURE_PARENT_START_SOURCE}" ]]; then
    start_source="${FIXTURE_PARENT_START_SOURCE}"
  else
    start_source="$(/usr/bin/ruby -rfiddle/import -e '
      module LibProc
        extend Fiddle::Importer
        dlload "/usr/lib/libproc.dylib"
        ProcBSDInfo = struct [
          "unsigned int pbi_flags", "unsigned int pbi_status", "unsigned int pbi_xstatus",
          "unsigned int pbi_pid", "unsigned int pbi_ppid", "unsigned int pbi_uid",
          "unsigned int pbi_gid", "unsigned int pbi_ruid", "unsigned int pbi_rgid",
          "unsigned int pbi_svuid", "unsigned int pbi_svgid", "unsigned int rfu_1",
          "char pbi_comm[16]", "char pbi_name[32]", "unsigned int pbi_nfiles",
          "unsigned int pbi_pgid", "unsigned int pbi_pjobc", "unsigned int e_tdev",
          "unsigned int e_tpgid", "int pbi_nice", "unsigned long long pbi_start_tvsec",
          "unsigned long long pbi_start_tvusec"
        ]
        extern "int proc_pidinfo(int, int, unsigned long long, void *, int)"
      end
      pid = Integer(ARGV.fetch(0), 10); expected_uid = Integer(ARGV.fetch(1), 10)
      info = LibProc::ProcBSDInfo.malloc
      bytes = LibProc.proc_pidinfo(pid, 3, 0, info, LibProc::ProcBSDInfo.size)
      exit 75 unless bytes == LibProc::ProcBSDInfo.size && info.pbi_pid == pid && info.pbi_uid == expected_uid
      sec = info.pbi_start_tvsec; usec = info.pbi_start_tvusec
      exit 75 unless sec.positive? && usec.between?(0, 999_999)
      print "#{sec}.#{usec.to_s.rjust(6, "0")}"
    ' "${pid}" "${uid}")" || return 1
  fi
  [[ -n "${start_source}" ]] || return 1
  /usr/bin/printf '%s\0%s\0%s' "${pid}" "${uid}" "${start_source}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}
trap cleanup EXIT
trap 'outer_signal_exit 129' HUP
trap 'outer_signal_exit 130' INT
trap 'outer_signal_exit 143' TERM

usage() {
  cat >&2 <<'USAGE'
Usage:
  vifty-helper-lifecycle.sh --operation repair|uninstall [--app /Applications/Vifty.app]
                            [--dry-run] [--record command-record.json]
                            [--replacement-phase prepare|finish
                             --replacement-destination /Applications/Vifty.app
                             --replacement-transaction-id UUID
                             --replacement-candidate /path/Vifty.app
                             --replacement-previous /Applications/Vifty.app
                             [--replacement-public-content-manifest-sha256 SHA256
                              --replacement-public-previous-content-manifest-sha256 SHA256
                              --replacement-public-version X.Y.Z
                              --replacement-public-build INTEGER
                              --replacement-public-team-id TEAMID
                              [--replacement-public-archive-sha256 SHA256]]
                             --replacement-result installed|rolled-back]

Protocol-v2 teardown requires a short-lived root-owned receipt written by the
authenticated daemon after quiesce, full-set Auto restoration, fresh readback,
and token consumption. Only an explicit machine-readable protocol-mismatch
report, or an exact helper-unreachable report paired with either a still-valid
receipt or root re-verification of the published v1.3.2 daemon binary, may
select offline recovery; all other
command errors, safety blockers, and malformed reports fail closed. Both paths enter the
administrator/root boundary, disable and prove the exact launchd label offline,
then run a root-staged, digest-bound, Developer-ID-verified Auto-only helper
before any legacy artifact is removed. Uninstall finalizes SMAppService
unregistration only after that root proof and caller-bound execution evidence.
USAGE
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "${value}" || "${value}" == --* ]]; then
    echo "helper-lifecycle: ${option} requires a value." >&2
    exit 64
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --operation) require_value "$1" "${2:-}"; OPERATION="$2"; shift 2 ;;
    --app) require_value "$1" "${2:-}"; APP_PATH="${2%/}"; shift 2 ;;
    --record) require_value "$1" "${2:-}"; RECORD_PATH="$2"; shift 2 ;;
    --maintenance-report) require_value "$1" "${2:-}"; MAINTENANCE_REPORT="$2"; shift 2 ;;
    --replacement-phase) require_value "$1" "${2:-}"; REPLACEMENT_PHASE="$2"; shift 2 ;;
    --replacement-destination) require_value "$1" "${2:-}"; REPLACEMENT_DESTINATION="$2"; shift 2 ;;
    --replacement-transaction-id) require_value "$1" "${2:-}"; REPLACEMENT_TRANSACTION_ID="$2"; shift 2 ;;
    --replacement-candidate) require_value "$1" "${2:-}"; REPLACEMENT_CANDIDATE_APP="${2%/}"; shift 2 ;;
    --replacement-previous) require_value "$1" "${2:-}"; REPLACEMENT_PREVIOUS_APP="${2%/}"; shift 2 ;;
    --replacement-result) require_value "$1" "${2:-}"; REPLACEMENT_RESULT="$2"; shift 2 ;;
    --replacement-lifecycle-source) require_value "$1" "${2:-}"; REPLACEMENT_LIFECYCLE_SOURCE="${2%/}"; shift 2 ;;
    --replacement-lifecycle-sha256) require_value "$1" "${2:-}"; REPLACEMENT_LIFECYCLE_EXPECTED_SHA256="$2"; shift 2 ;;
    --replacement-public-content-manifest-sha256) require_value "$1" "${2:-}"; REPLACEMENT_PUBLIC_CONTENT_MANIFEST_SHA256="$2"; shift 2 ;;
    --replacement-public-previous-content-manifest-sha256) require_value "$1" "${2:-}"; REPLACEMENT_PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256="$2"; shift 2 ;;
    --replacement-public-version) require_value "$1" "${2:-}"; REPLACEMENT_PUBLIC_VERSION="$2"; shift 2 ;;
    --replacement-public-build) require_value "$1" "${2:-}"; REPLACEMENT_PUBLIC_BUILD="$2"; shift 2 ;;
    --replacement-public-team-id) require_value "$1" "${2:-}"; REPLACEMENT_PUBLIC_TEAM_ID="$2"; shift 2 ;;
    --replacement-public-archive-sha256) require_value "$1" "${2:-}"; REPLACEMENT_PUBLIC_ARCHIVE_SHA256="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "helper-lifecycle: unknown argument: $1" >&2; usage; exit 64 ;;
  esac
done

case "${OPERATION}" in repair|uninstall) ;; *) echo "helper-lifecycle: --operation must be repair or uninstall." >&2; exit 64 ;; esac
case "${REPLACEMENT_PHASE}" in ""|prepare|finish|release-lock) ;; *) echo "helper-lifecycle: --replacement-phase must be prepare, finish, or release-lock." >&2; exit 64 ;; esac
if [[ -n "${REPLACEMENT_PHASE}" ]]; then
  [[ "${OPERATION}" == "repair" && -n "${REPLACEMENT_DESTINATION}" && "${REPLACEMENT_DESTINATION}" == /* ]] || {
    echo "helper-lifecycle: replacement prepare/finish requires repair and an absolute replacement destination." >&2
    exit 64
  }
  [[ "${DRY_RUN}" -eq 0 && -z "${MAINTENANCE_REPORT}" ]] || {
    echo "helper-lifecycle: replacement prepare/finish cannot use dry-run or caller-supplied maintenance reports." >&2
    exit 64
  }
  case "${PPID}" in ''|*[!0-9]*) echo "helper-lifecycle: replacement parent-process binding is invalid." >&2; exit 64 ;; esac
  [[ "${PPID}" -gt 1 ]] || { echo "helper-lifecycle: replacement parent-process binding is unsafe." >&2; exit 64; }
  REQUESTING_PROCESS_ID="${PPID}"
  REQUESTING_PROCESS_START_ID="$(process_start_identity "${REQUESTING_PROCESS_ID}" "${REQUESTING_USER_UID}")" || {
    echo "helper-lifecycle: replacement parent-process start identity is unavailable before any exact-label offline proof; helper authority is active or unknown." >&2
    exit 76
  }
  [[ "${REQUESTING_PROCESS_START_ID}" =~ ^[a-f0-9]{64}$ ]] || {
    echo "helper-lifecycle: replacement parent-process start identity is invalid before any exact-label offline proof; helper authority is active or unknown." >&2
    exit 76
  }
fi

APP_PATH="$(cd "$(/usr/bin/dirname "${APP_PATH}")" 2>/dev/null && pwd -P)/$(/usr/bin/basename "${APP_PATH}")"
if [[ -n "${REPLACEMENT_PHASE}" ]]; then
  replacement_parent="$(cd "$(/usr/bin/dirname "${REPLACEMENT_DESTINATION}")" 2>/dev/null && pwd -P)" || {
    echo "helper-lifecycle: replacement destination parent is unavailable." >&2
    exit 66
  }
  REPLACEMENT_DESTINATION="${replacement_parent}/$(/usr/bin/basename "${REPLACEMENT_DESTINATION}")"
  [[ "$(/usr/bin/basename "${REPLACEMENT_DESTINATION}")" == "Vifty.app" ]] || {
    echo "helper-lifecycle: replacement destination must be a Vifty.app bundle path." >&2
    exit 64
  }
  if [[ "${REPLACEMENT_PHASE}" != "prepare" && "${APP_PATH}" != "${REPLACEMENT_DESTINATION}" ]]; then
    echo "helper-lifecycle: replacement finish/release is not executing from the prepared destination and no exact-label offline proof was made; helper authority is active or unknown." >&2
    exit 76
  fi
  [[ "${REPLACEMENT_TRANSACTION_ID}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || {
    echo "helper-lifecycle: replacement transaction ID must be a lowercase UUID." >&2
    exit 64
  }
  if [[ "${REPLACEMENT_PHASE}" == "prepare" ]]; then
    [[ -n "${REPLACEMENT_CANDIDATE_APP}" && -n "${REPLACEMENT_PREVIOUS_APP}" &&
       -n "${REPLACEMENT_LIFECYCLE_SOURCE}" && -z "${REPLACEMENT_RESULT}" &&
       "${REPLACEMENT_LIFECYCLE_EXPECTED_SHA256}" =~ ^[a-f0-9]{64}$ ]] || {
      echo "helper-lifecycle: replacement prepare requires candidate, previous, and exact lifecycle source bindings without a result." >&2
      exit 64
    }
    public_binding_count=0
    for public_binding_value in \
      "${REPLACEMENT_PUBLIC_CONTENT_MANIFEST_SHA256}" \
      "${REPLACEMENT_PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256}" \
      "${REPLACEMENT_PUBLIC_VERSION}" \
      "${REPLACEMENT_PUBLIC_BUILD}" \
      "${REPLACEMENT_PUBLIC_TEAM_ID}"; do
      [[ -n "${public_binding_value}" ]] && public_binding_count=$((public_binding_count + 1))
    done
    if [[ "${public_binding_count}" -ne 0 && "${public_binding_count}" -ne 5 ]]; then
      echo "helper-lifecycle: replacement public candidate binding requires complete candidate/previous content manifests, version, build, and TeamID." >&2
      exit 64
    fi
    if [[ "${public_binding_count}" -eq 0 ]]; then
      [[ -z "${REPLACEMENT_PUBLIC_ARCHIVE_SHA256}" ]] || {
        echo "helper-lifecycle: replacement public archive evidence requires the complete public candidate binding." >&2
        exit 64
      }
    else
      [[ "${REPLACEMENT_PUBLIC_CONTENT_MANIFEST_SHA256}" =~ ^[a-f0-9]{64}$ &&
         "${REPLACEMENT_PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256}" =~ ^[a-f0-9]{64}$ &&
         "${REPLACEMENT_PUBLIC_VERSION}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ &&
         "${REPLACEMENT_PUBLIC_BUILD}" =~ ^[1-9][0-9]*$ &&
         "${REPLACEMENT_PUBLIC_TEAM_ID}" == "X88J3853S2" &&
         ( -z "${REPLACEMENT_PUBLIC_ARCHIVE_SHA256}" || "${REPLACEMENT_PUBLIC_ARCHIVE_SHA256}" =~ ^[a-f0-9]{64}$ ) ]] || {
        echo "helper-lifecycle: replacement public candidate binding is malformed or does not name Vifty's release TeamID." >&2
        exit 64
      }
    fi
    candidate_parent="$(cd "$(/usr/bin/dirname "${REPLACEMENT_CANDIDATE_APP}")" 2>/dev/null && pwd -P)" || exit 66
    previous_parent="$(cd "$(/usr/bin/dirname "${REPLACEMENT_PREVIOUS_APP}")" 2>/dev/null && pwd -P)" || exit 66
    REPLACEMENT_CANDIDATE_APP="${candidate_parent}/$(/usr/bin/basename "${REPLACEMENT_CANDIDATE_APP}")"
    REPLACEMENT_PREVIOUS_APP="${previous_parent}/$(/usr/bin/basename "${REPLACEMENT_PREVIOUS_APP}")"
    [[ "$(/usr/bin/basename "${REPLACEMENT_CANDIDATE_APP}")" == "Vifty.app" &&
       "${REPLACEMENT_PREVIOUS_APP}" == "${REPLACEMENT_DESTINATION}" &&
       "${REPLACEMENT_LIFECYCLE_SOURCE}" == "${REPLACEMENT_CANDIDATE_APP}/Contents/Resources/vifty-helper-lifecycle.sh" ]] || {
      echo "helper-lifecycle: replacement prepare bundle paths do not match the declared destination." >&2
      exit 64
    }
  else
    [[ -z "${REPLACEMENT_CANDIDATE_APP}" && -z "${REPLACEMENT_PREVIOUS_APP}" &&
       -z "${REPLACEMENT_LIFECYCLE_SOURCE}" && -z "${REPLACEMENT_LIFECYCLE_EXPECTED_SHA256}" &&
       -z "${REPLACEMENT_PUBLIC_CONTENT_MANIFEST_SHA256}" && -z "${REPLACEMENT_PUBLIC_VERSION}" &&
       -z "${REPLACEMENT_PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256}" &&
       -z "${REPLACEMENT_PUBLIC_BUILD}" && -z "${REPLACEMENT_PUBLIC_TEAM_ID}" &&
       -z "${REPLACEMENT_PUBLIC_ARCHIVE_SHA256}" ]] || {
      echo "helper-lifecycle: replacement finish takes bundle identity only from the root prepare record." >&2
      exit 64
    }
    if [[ "${REPLACEMENT_PHASE}" == "finish" ]]; then
      case "${REPLACEMENT_RESULT}" in installed|rolled-back) ;; *) echo "helper-lifecycle: replacement finish requires installed or rolled-back result." >&2; exit 64 ;; esac
    else
      [[ "${REPLACEMENT_RESULT}" == "installed" ]] || { echo "helper-lifecycle: replacement lock release requires the installed result." >&2; exit 64; }
    fi
  fi
fi
VIFTY_CTL="${APP_PATH}/Contents/MacOS/viftyctl"
VIFTY_MAIN="${APP_PATH}/Contents/MacOS/Vifty"
VIFTY_HELPER="${APP_PATH}/Contents/MacOS/ViftyHelper"
VIFTY_DAEMON="${APP_PATH}/Contents/MacOS/ViftyDaemon"
PLIST_NAME="tech.reidar.vifty.daemon.plist"
SERVICE_LABEL="tech.reidar.vifty.daemon"
RELEASE_TEAM_ID="X88J3853S2"
HELPER_SIGNING_ID="tech.reidar.vifty.helper"
DAEMON_SIGNING_ID="tech.reidar.vifty.daemon"
V132_DAEMON_SHA256="7543c573528a57bb096b045b9a7476b1d4da4aef88b7cd8b54d4cd2ca5bf7dac"
V132_DAEMON_CDHASH="c5613e3020d94de1d141917d7b950fc367a6e61a"
V132_FIXTURE_DAEMON_SHA256="66f0b66e7ed10074476cbd239194adbe3e8cb49fca3e43a3fc5f6c7b81cdeea5"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "helper-lifecycle: app bundle not found: ${APP_PATH}" >&2
  exit 66
fi

if [[ -n "${TEST_ROOT}" ]]; then
  TEST_ROOT="$(cd "${TEST_ROOT}" 2>/dev/null && pwd -P)"
  case "${APP_PATH}" in "${TEST_ROOT}"/*) ;; *) echo "helper-lifecycle: fixture app must remain under VIFTY_LIFECYCLE_TEST_ROOT." >&2; exit 65 ;; esac
  if [[ "${REPLACEMENT_PHASE}" == "prepare" ]]; then
    case "${REPLACEMENT_CANDIDATE_APP}" in "${TEST_ROOT}"/*) ;; *) echo "helper-lifecycle: fixture replacement candidate escaped the test root." >&2; exit 65 ;; esac
    case "${REPLACEMENT_PREVIOUS_APP}" in "${TEST_ROOT}"/*) ;; *) echo "helper-lifecycle: fixture previous bundle escaped the test root." >&2; exit 65 ;; esac
    case "${REPLACEMENT_LIFECYCLE_SOURCE}" in "${REPLACEMENT_CANDIDATE_APP}"/*) ;; *) echo "helper-lifecycle: fixture lifecycle source escaped the candidate bundle." >&2; exit 65 ;; esac
  fi
  LAUNCHCTL="${TEST_ROOT}/bin/launchctl"
  PRIVILEGED_HELPER="${TEST_ROOT}/Library/PrivilegedHelperTools/${SERVICE_LABEL}"
  LEGACY_PLIST="${TEST_ROOT}/Library/LaunchDaemons/${PLIST_NAME}"
  STDOUT_LOG="${TEST_ROOT}/var/log/${SERVICE_LABEL}.out.log"
  STDERR_LOG="${TEST_ROOT}/var/log/${SERVICE_LABEL}.err.log"
  MAINTENANCE_DIR="${TEST_ROOT}/Library/Application Support/Vifty/Maintenance"
  EXECUTION_DIR="${TEST_ROOT}/Library/Application Support/ViftyMaintenanceEvidence"
  case "${CALLER_UID}" in ''|*[!0-9]*) echo "helper-lifecycle: fixture caller UID is invalid." >&2; exit 64 ;; esac
  EXPECTED_OWNER_UID="${CALLER_UID}"
  EXPECTED_BOOT_SESSION_ID="boot"
else
  LAUNCHCTL="/bin/launchctl"
  PRIVILEGED_HELPER="/Library/PrivilegedHelperTools/${SERVICE_LABEL}"
  LEGACY_PLIST="/Library/LaunchDaemons/${PLIST_NAME}"
  STDOUT_LOG="/var/log/${SERVICE_LABEL}.out.log"
  STDERR_LOG="/var/log/${SERVICE_LABEL}.err.log"
  MAINTENANCE_DIR="/Library/Application Support/Vifty/Maintenance"
  EXECUTION_DIR="/Library/Application Support/ViftyMaintenanceEvidence"
  EXPECTED_OWNER_UID=0
  EXPECTED_BOOT_SESSION_ID="$(/usr/sbin/sysctl -n kern.boottime | /usr/bin/ruby -e 'value = STDIN.read; match = value.match(/sec = ([0-9]+), usec = ([0-9]+)/); abort "invalid kern.boottime" unless match; print "#{match[1]}.#{match[2]}"')"
fi
AUTHORITY_PATH="${MAINTENANCE_DIR}/authorized-v1.json"
CLAIMED_AUTHORITY_PATH="${MAINTENANCE_DIR}/claimed-v1.json"
ROOT_EXECUTION_RECORD="${EXECUTION_DIR}/last-execution-v1.json"
ROOT_REPLACEMENT_RECORD="${EXECUTION_DIR}/replacement-state-v1.json"
REPLACEMENT_TRANSACTION_ROOT="${EXECUTION_DIR}/ReplacementTransactions"
if [[ -n "${REPLACEMENT_TRANSACTION_ID}" ]]; then
  REPLACEMENT_TRANSACTION_DIR="${REPLACEMENT_TRANSACTION_ROOT}/${REPLACEMENT_TRANSACTION_ID}"
  REPLACEMENT_CANDIDATE_SNAPSHOT_APP="${REPLACEMENT_TRANSACTION_DIR}/CandidateSnapshot/Vifty.app"
  REPLACEMENT_LIFECYCLE_STAGED_PATH="${REPLACEMENT_TRANSACTION_DIR}/vifty-helper-lifecycle.sh"
else
  REPLACEMENT_TRANSACTION_DIR=""
fi
ROOT_SCRATCH_PARENT="/private/tmp"
if [[ -n "${TEST_ROOT}" ]]; then ROOT_SCRATCH_PARENT="${TEST_ROOT}"; fi

if [[ "${OPERATION}" == "repair" && "${REPLACEMENT_PHASE}" == "prepare" ]]; then
  PLANNED_PHASES=(
    inspect-ownership
    quiesce-restore-confirm
    consume-single-use-token
    unregister-smappservice-and-verify
    disable-service-and-confirm-offline
    post-freeze-offline-auto-confirm
    remove-legacy-helper-plist-and-logs
    preserve-replacement-freeze
  )
elif [[ "${OPERATION}" == "repair" ]]; then
  PLANNED_PHASES=(
    inspect-ownership
    quiesce-restore-confirm
    consume-single-use-token
    unregister-smappservice-and-verify
    disable-service-and-confirm-offline
    post-freeze-offline-auto-confirm
    remove-legacy-helper-plist-and-logs
    reenable-service-after-cleanup
    register-smappservice-and-verify
  )
else
  PLANNED_PHASES=(
    inspect-ownership
    quiesce-restore-confirm
    consume-single-use-token
    unregister-smappservice-and-verify
    disable-service-and-confirm-offline
    post-freeze-offline-auto-confirm
    remove-legacy-helper-plist-and-logs
    preserve-agentcontrol-and-fancontrol-recovery-state
  )
fi

append_phase() {
  [[ -n "${PHASE_LOG}" ]] || return 0
  /usr/bin/printf '%s\n' "$1" >> "${PHASE_LOG}"
}

write_record() {
  [[ -n "${RECORD_PATH}" ]] || return 0
  local record_dir
  record_dir="$(/usr/bin/dirname "${RECORD_PATH}")"
  [[ -d "${record_dir}" ]] || { echo "helper-lifecycle: record directory does not exist: ${record_dir}" >&2; return 1; }
  RECORD_TMP="$(/usr/bin/mktemp "${RECORD_PATH}.tmp.XXXXXX")"
  /usr/bin/ruby -rjson -rdigest -e '
    operation, app, dry_run, status, blocker, phase_log, privileged_record, *planned = ARGV
    executed = File.file?(phase_log) ? File.readlines(phase_log, chomp: true).reject(&:empty?) : []
    payload = {
      schemaVersion: 1,
      operation: operation,
      app: app,
      mode: dry_run == "1" ? "dry-run" : "live",
      status: status,
      commandsExecuted: !executed.empty?,
      blocker: blocker,
      plannedPhases: planned,
      executedPhases: executed,
      privilegedEvidencePath: privileged_record
    }
    STDOUT.write(JSON.pretty_generate(payload)); STDOUT.write("\n")
  ' "${OPERATION}" "${APP_PATH}" "${DRY_RUN}" "${STATUS}" "${BLOCKER}" "${PHASE_LOG}" "${ROOT_EXECUTION_RECORD}" "${PLANNED_PHASES[@]}" > "${RECORD_TMP}"
  /bin/chmod 600 "${RECORD_TMP}"
  /bin/mv -f "${RECORD_TMP}" "${RECORD_PATH}"
  RECORD_TMP=""
}

validate_prepare_report() {
  /usr/bin/ruby -rjson -rdigest -e '
    report = JSON.parse(File.read(ARGV[0])); operation = ARGV[1]; expected_helper_digest = ARGV[2]
    token = report["token"]
    ok = report["schemaVersion"] == 1 &&
      report["schemaID"] == "https://vifty.app/schemas/helper-maintenance-report-v1.json" &&
      report["operation"] == operation && report["safeToStop"] == true &&
      report["quiesced"] == true && report["restoreAttempted"] == true &&
      report["restoreSucceeded"] == true && report["completeExpectedSetConfirmed"] == true &&
      report["blockers"] == [] && report["tokenConsumed"] == false && token.is_a?(Hash) &&
      token["schemaVersion"] == 1 && token["operation"] == operation &&
      token["tokenID"].is_a?(String) && !token["tokenID"].empty? &&
      token["expectedFanIDs"].is_a?(Array) && !token["expectedFanIDs"].empty? &&
      token["expectedFanIDs"].all? { |id| id.is_a?(Integer) && id.between?(0, 9) } &&
      token["expectedFanIDs"].uniq.sort == token["expectedFanIDs"] &&
      token["helperSHA256"] == expected_helper_digest && expected_helper_digest.match?(/\A[a-f0-9]{64}\z/) &&
      token["expiresAt"].is_a?(Numeric) && token["issuedAt"].is_a?(Numeric) && token["expiresAt"] > token["issuedAt"]
    exit(ok ? 0 : 75)
  ' "$1" "$2" "$3"
}

validate_protocol_mismatch_report() {
  /usr/bin/ruby -rjson -e '
    report = JSON.parse(File.read(ARGV[0])); operation = ARGV[1]
    blockers = report["blockers"]
    allowed_keys = %w[blockers completeExpectedSetConfirmed fanResults operation quiesced restoreAttempted restoreSucceeded safeToStop schemaID schemaVersion token tokenConsumed]
    required_keys = allowed_keys - ["token"]
    ok = (report.keys - allowed_keys).empty? && (required_keys - report.keys).empty? &&
      report["schemaVersion"] == 1 &&
      report["schemaID"] == "https://vifty.app/schemas/helper-maintenance-report-v1.json" &&
      report["operation"] == operation && report["safeToStop"] == false &&
      report["quiesced"] == true && report["restoreAttempted"] == true &&
      report["token"].nil? && report["tokenConsumed"] == false &&
      blockers.is_a?(Array) && blockers.length == 1 &&
      blockers[0].is_a?(Hash) && blockers[0]["code"] == "PROTOCOL_MISMATCH" &&
      blockers[0]["message"].is_a?(String) && !blockers[0]["message"].empty? &&
      blockers[0]["recommendedRecoveryAction"].is_a?(String) &&
      !blockers[0]["recommendedRecoveryAction"].empty?
    exit(ok ? 0 : 75)
  ' "$1" "$2"
}

validate_legacy_unavailable_error() {
  /usr/bin/ruby -rjson -e '
    report = JSON.parse(File.read(ARGV[0]))
    allowed = %w[schemaVersion schemaID command errorCode message safeToProceed recommendedRecoveryAction recoverySteps coolingLeasePrepared autoRestoreAttempted autoRestoreSucceeded childProcessFailurePhase childExitCode descendantCleanupCompleted backgroundProcessesMayRemain retryAfterSeconds generatedAt]
    required = %w[schemaVersion schemaID command errorCode message safeToProceed recommendedRecoveryAction recoverySteps coolingLeasePrepared autoRestoreAttempted generatedAt]
    valid = (report.keys - allowed).empty? && (required - report.keys).empty? &&
      report["schemaVersion"] == 1 &&
      report["schemaID"] == "https://vifty.local/schemas/viftyctl-command-error.schema.json" &&
      report["command"] == "helper-maintenance-prepare" &&
      report["errorCode"] == "HELPER_UNREACHABLE" &&
      report["message"].is_a?(String) && !report["message"].empty? &&
      report["safeToProceed"] == false &&
      report["recommendedRecoveryAction"] == "repairHelper" &&
      report["recoverySteps"].is_a?(Array) &&
      report["coolingLeasePrepared"] == false &&
      report["autoRestoreAttempted"] == false &&
      [nil, false].include?(report["autoRestoreSucceeded"]) &&
      report["generatedAt"].is_a?(Numeric) &&
      (Time.now.to_f - (report["generatedAt"] + 978_307_200)).abs <= 120
    exit(valid ? 0 : 75)
  ' "$1"
}

validate_service_report() {
  /usr/bin/ruby -rjson -e '
    report = JSON.parse(File.read(ARGV[0])); action = ARGV[1]; state = ARGV[2]; maintenance = ARGV[3] == "1"
    ok = report["action"] == action && report["state"] == state &&
      report["complete"] == true && report["operatorActionRequired"] == false &&
      report["maintenanceAuthorized"] == maintenance
    if maintenance
      prepared = JSON.parse(File.read(ARGV[4]))
      ok &&= report["tokenID"] == prepared.dig("token", "tokenID")
    else
      ok &&= report["tokenID"].nil?
    end
    exit(ok ? 0 : 75)
  ' "$1" "$2" "$3" "$4" "${5:-/dev/null}"
}

validate_legacy_service_report() {
  /usr/bin/ruby -rjson -e '
    report = JSON.parse(File.read(ARGV[0]))
    ok = report["action"] == "unregister" && report["state"] == "notRegistered" &&
      report["complete"] == true && report["operatorActionRequired"] == false &&
      report["maintenanceAuthorized"] == false && report["tokenID"].nil? &&
      report["legacyProtocolGateUsed"] == true
    exit(ok ? 0 : 75)
  ' "$1"
}

validate_completed_root_record() {
  /usr/bin/ruby -rjson -e '
    path, dir, owner_text, operation, requesting_uid_text, requesting_pid_text, replacement_phase, replacement_path = ARGV
    owner = Integer(owner_text, 10)
    requesting_uid = Integer(requesting_uid_text, 10)
    requesting_pid = Integer(requesting_pid_text, 10)
    dst = File.lstat(dir); pst = File.lstat(path)
    exit 75 unless dst.directory? && !dst.symlink? && dst.uid == owner && (dst.mode & 0777) == 0755 &&
      pst.file? && !pst.symlink? && pst.uid == owner && pst.nlink == 1 && (pst.mode & 0777) == 0644 && pst.size.between?(1, 4_194_304)
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      opened = file.stat
      exit 75 unless opened.dev == pst.dev && opened.ino == pst.ino && opened.size == pst.size
      record = JSON.parse(file.read(4_194_305))
      phases = record["phases"]
      succeeded = phases.is_a?(Array) ? phases.select { |phase| phase["attempted"] == true && phase["succeeded"] == true }.map { |phase| phase["phase"] } : []
      required = ["verify-privileged-authority", "disable-service-and-confirm-offline", "post-freeze-offline-auto-confirm", "remove-legacy-helper-plist-and-logs"]
      required << "reenable-service-after-cleanup" if operation == "repair" && replacement_phase != "prepare"
      required << "register-smappservice-and-verify" if replacement_phase == "finish"
      expected_status = replacement_phase == "prepare" ? "replacement-prepared" : "completed"
      valid = record["schemaVersion"] == 1 &&
        record["schemaID"] == "https://vifty.app/schemas/helper-maintenance-execution-v1.json" &&
        record["operation"] == operation && record["status"] == expected_status && record["blocker"] == "" &&
        ["daemon-receipt", "offline-auto"].include?(record["authorityMode"]) &&
        record["requestingUserID"] == requesting_uid && record["requestingProcessID"] == requesting_pid &&
        record["updatedAt"].is_a?(Numeric) && (Time.now.to_f - record["updatedAt"]).abs <= 120 &&
        required.all? { |phase| succeeded.include?(phase) } &&
        (replacement_phase.empty? || record["replacementAppPath"] == replacement_path)
      exit 75 unless valid
      final = file.stat
      exit 75 unless final.dev == opened.dev && final.ino == opened.ino && final.size == opened.size
    end
  ' "${ROOT_EXECUTION_RECORD}" "${EXECUTION_DIR}" "${EXPECTED_OWNER_UID}" "${OPERATION}" "${REQUESTING_USER_UID}" "${REQUESTING_PROCESS_ID}" "${REPLACEMENT_PHASE}" "${REPLACEMENT_DESTINATION}"
}

cancel_unconsumed() {
  [[ "${TOKEN_CONSUMED}" -eq 0 ]] || return 0
  [[ -x "${VIFTY_CTL}" ]] || return 0
  "${VIFTY_CTL}" helper-maintenance-cancel --json >/dev/null 2>&1 || true
}

if [[ "${DRY_RUN}" -eq 1 ]]; then
  RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/vifty-lifecycle-dry-run.XXXXXX")"
  PHASE_LOG="${RUN_DIR}/phases"
  : > "${PHASE_LOG}"
  BLOCKER="Dry-run never invokes viftyctl, Vifty, ViftyHelper, sudo, launchctl, helper binaries, or AppleSMC."
  write_record
  echo "helper-lifecycle: dry-run recorded; no commands were executed." >&2
  exit 75
fi

ensure_privileged_authority_directory() {
  /usr/bin/ruby -e '
    dir, owner_text, test_mode = ARGV
    owner = Integer(owner_text, 10)
    parent = File.dirname(dir)
    unless File.directory?(parent)
      if test_mode == "1"
        require "fileutils"; FileUtils.mkdir_p(parent, mode: 0700)
      else
        abort "privileged maintenance parent is missing"
      end
    end
    pst = File.lstat(parent)
    abort "unsafe privileged maintenance parent" unless pst.directory? && !pst.symlink? && pst.uid == owner && (pst.mode & 0022).zero?
    begin
      Dir.mkdir(dir, 0700)
    rescue Errno::EEXIST
    end
    st = File.lstat(dir)
    abort "unsafe privileged maintenance directory" unless st.directory? && !st.symlink? && st.uid == owner && (st.mode & 0777) == 0700
  ' "${MAINTENANCE_DIR}" "${EXPECTED_OWNER_UID}" "$([[ -n "${TEST_ROOT}" ]] && echo 1 || echo 0)"
}

ensure_privileged_execution_directory() {
  /usr/bin/ruby -e '
    dir, owner_text, test_mode = ARGV
    owner = Integer(owner_text, 10)
    parent = File.dirname(dir)
    unless File.directory?(parent)
      if test_mode == "1"
        require "fileutils"; FileUtils.mkdir_p(parent, mode: 0755)
      else
        abort "privileged execution-evidence parent is missing"
      end
    end
    pst = File.lstat(parent)
    abort "unsafe privileged execution-evidence parent" unless pst.directory? && !pst.symlink? && pst.uid == owner && (pst.mode & 0022).zero?
    begin
      Dir.mkdir(dir, 0755)
    rescue Errno::EEXIST
    end
    st = File.lstat(dir)
    abort "unsafe privileged execution-evidence directory" unless st.directory? && !st.symlink? && st.uid == owner && (st.mode & 0777) == 0755
  ' "${EXECUTION_DIR}" "${EXPECTED_OWNER_UID}" "$([[ -n "${TEST_ROOT}" ]] && echo 1 || echo 0)"
}

replacement_lock_flag() {
  if [[ -n "${TEST_ROOT}" ]]; then
    /usr/bin/printf '%s' uchg
  else
    /usr/bin/printf '%s' schg
  fi
}

path_has_replacement_lock() {
  local path="$1"
  local expected_flag
  local flags
  expected_flag="$(replacement_lock_flag)"
  flags="$(/usr/bin/stat -f '%Sf' "${path}" 2>/dev/null)" || return 1
  case ",${flags}," in
    *",${expected_flag},"*) return 0 ;;
    *) return 1 ;;
  esac
}

replacement_tree_is_locked() {
  local root="$1"
  [[ -d "${root}" && ! -L "${root}" ]] || return 1
  local entry
  while IFS= read -r -d '' entry; do
    [[ -L "${entry}" ]] && continue
    path_has_replacement_lock "${entry}" || return 1
  done < <(/usr/bin/find -x "${root}" -print0)
}

replacement_tree_flag_state() {
  local root="$1"
  [[ -d "${root}" && ! -L "${root}" ]] || return 1
  local entry locked=0 unlocked=0
  while IFS= read -r -d '' entry; do
    [[ -L "${entry}" ]] && continue
    if path_has_replacement_lock "${entry}"; then
      locked=$((locked + 1))
    else
      unlocked=$((unlocked + 1))
    fi
  done < <(/usr/bin/find -x "${root}" -print0)
  if [[ "${locked}" -gt 0 && "${unlocked}" -eq 0 ]]; then
    /usr/bin/printf '%s\n' locked
  elif [[ "${unlocked}" -gt 0 && "${locked}" -eq 0 ]]; then
    /usr/bin/printf '%s\n' unlocked
  else
    /usr/bin/printf '%s\n' mixed
  fi
}

force_lock_replacement_tree() {
  local root="$1" flag
  flag="$(replacement_lock_flag)"
  /usr/bin/chflags -R "${flag}" "${root}" || return 1
  [[ "$(replacement_tree_flag_state "${root}")" == "locked" ]]
}

force_unlock_replacement_tree() {
  local root="$1" flag
  flag="$(replacement_lock_flag)"
  [[ -d "${root}" && ! -L "${root}" ]] || return 1
  /usr/bin/chflags -R "no${flag}" "${root}" || return 1
  [[ "$(replacement_tree_flag_state "${root}")" == "unlocked" ]]
}

lock_replacement_tree() {
  local root="$1"
  local flag
  flag="$(replacement_lock_flag)"
  if [[ -n "${TEST_ROOT}" && "${ROOT_FIXTURE_PARTIAL_LOCK:-0}" == "1" ]]; then
    /usr/bin/chflags "${flag}" "${root}" || return 1
    return 1
  fi
  /usr/bin/chflags -R "${flag}" "${root}" || return 1
  replacement_tree_is_locked "${root}"
}

unlock_replacement_tree() {
  local root="$1"
  local flag
  flag="$(replacement_lock_flag)"
  [[ -d "${root}" && ! -L "${root}" ]] || return 1
  if [[ -n "${TEST_ROOT}" && "${ROOT_FIXTURE_PARTIAL_UNLOCK:-0}" == "1" ]]; then
    /usr/bin/chflags "no${flag}" "${root}" || return 1
    return 1
  fi
  /usr/bin/chflags -R "no${flag}" "${root}" || return 1
  local entry
  while IFS= read -r -d '' entry; do
    [[ -L "${entry}" ]] && continue
    path_has_replacement_lock "${entry}" && return 1
  done < <(/usr/bin/find -x "${root}" -print0)
  return 0
}

bind_replacement_public_candidate_snapshot() {
  local snapshot_binding="$1"
  if [[ -z "${REPLACEMENT_PUBLIC_CONTENT_MANIFEST_SHA256}" ]]; then
    REPLACEMENT_PUBLIC_CANDIDATE_EXPECTATION=""
    return 0
  fi
  REPLACEMENT_PUBLIC_CANDIDATE_EXPECTATION="$(/usr/bin/ruby -rjson -rdigest -e '
    binding = JSON.parse(ARGV.fetch(0))
    expected_content_sha, expected_version, expected_build, expected_team, archive_sha,
      snapshot_path, test_root, release_team = ARGV.drop(1)
    manifest = binding["manifest"]
    exit 75 unless manifest.is_a?(Array) && !manifest.empty?
    content_manifest = manifest.map do |row|
      exit 75 unless row.is_a?(Hash)
      row.reject do |key, _|
        ["uid", "gid", "nlink"].include?(key) || (row["type"] == "symlink" && key == "size")
      end
    end
    content_sha = Digest::SHA256.hexdigest(JSON.generate(content_manifest))
    identity = binding["identity"]
    exit 75 unless binding["sourcePath"] == snapshot_path &&
      binding["contentManifestSHA256"] == content_sha && content_sha == expected_content_sha &&
      identity.is_a?(Hash) && identity["bundleVersion"] == expected_version &&
      identity["bundleBuild"] == expected_build && expected_team == release_team
    if test_root.empty?
      exit 75 unless identity["kind"] == "developer-id" && identity["teamID"] == expected_team
    else
      exit 75 unless identity["kind"] == "adhoc" && identity["teamID"].nil?
    end
    expectation = {
      "contentManifestSHA256" => content_sha,
      "version" => expected_version,
      "build" => expected_build,
      "teamID" => expected_team
    }
    expectation["reportedArchiveSHA256"] = archive_sha unless archive_sha.empty?
    print JSON.generate(expectation)
  ' "${snapshot_binding}" "${REPLACEMENT_PUBLIC_CONTENT_MANIFEST_SHA256}" "${REPLACEMENT_PUBLIC_VERSION}" \
    "${REPLACEMENT_PUBLIC_BUILD}" "${REPLACEMENT_PUBLIC_TEAM_ID}" "${REPLACEMENT_PUBLIC_ARCHIVE_SHA256}" \
    "${REPLACEMENT_CANDIDATE_SNAPSHOT_APP}" "${TEST_ROOT}" "${RELEASE_TEAM_ID}")" || return 1
  [[ -n "${REPLACEMENT_PUBLIC_CANDIDATE_EXPECTATION}" ]] || return 1
}

bind_replacement_public_previous_snapshot() {
  local previous_binding="$1"
  [[ -n "${REPLACEMENT_PUBLIC_CONTENT_MANIFEST_SHA256}" ]] || return 0
  REPLACEMENT_PUBLIC_CANDIDATE_EXPECTATION="$(/usr/bin/ruby -rjson -rdigest -e '
    binding = JSON.parse(ARGV.fetch(0))
    expectation = JSON.parse(ARGV.fetch(1))
    expected_sha, expected_path = ARGV.drop(2)
    manifest = binding["manifest"]
    exit 75 unless binding["sourcePath"] == expected_path && manifest.is_a?(Array) && !manifest.empty?
    content_manifest = manifest.map do |row|
      exit 75 unless row.is_a?(Hash)
      row.reject do |key, _|
        ["uid", "gid", "nlink"].include?(key) || (row["type"] == "symlink" && key == "size")
      end
    end
    content_sha = Digest::SHA256.hexdigest(JSON.generate(content_manifest))
    exit 75 unless binding["contentManifestSHA256"] == content_sha && content_sha == expected_sha
    expectation["previousContentManifestSHA256"] = content_sha
    print JSON.generate(expectation)
  ' "${previous_binding}" "${REPLACEMENT_PUBLIC_CANDIDATE_EXPECTATION}" \
    "${REPLACEMENT_PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256}" "${REPLACEMENT_PREVIOUS_APP}")" || return 1
  [[ -n "${REPLACEMENT_PUBLIC_CANDIDATE_EXPECTATION}" ]] || return 1
}

stage_replacement_candidate_snapshot() {
  [[ "${REPLACEMENT_PHASE}" == "prepare" &&
     "${REPLACEMENT_LIFECYCLE_SOURCE}" == "${REPLACEMENT_CANDIDATE_APP}/Contents/Resources/vifty-helper-lifecycle.sh" &&
     "${REPLACEMENT_LIFECYCLE_EXPECTED_SHA256}" =~ ^[a-f0-9]{64}$ ]] || return 1
  local source_before source_after snapshot_binding
  source_before="$(capture_bundle_binding "${REPLACEMENT_CANDIDATE_APP}")" || return 1
  if [[ -n "${TEST_ROOT}" && "${ROOT_FIXTURE_SWAP_CANDIDATE_DURING_SNAPSHOT:-0}" == "1" ]]; then
    /usr/bin/printf '%s\n' mid-snapshot-source-mutation > "${REPLACEMENT_CANDIDATE_APP}/Contents/Resources/mid-snapshot-source-mutation" || return 1
  fi
  /usr/bin/ruby -e '
    root, dir, snapshot_parent, owner_text = ARGV
    owner = Integer(owner_text, 10)
    begin
      Dir.mkdir(root, 0755)
    rescue Errno::EEXIST
    end
    rst = File.lstat(root)
    exit 75 unless rst.directory? && !rst.symlink? && rst.uid == owner && (rst.mode & 0022).zero?
    Dir.mkdir(dir, 0755)
    dst = File.lstat(dir)
    exit 75 unless dst.directory? && !dst.symlink? && dst.uid == owner && (dst.mode & 0022).zero?
    Dir.mkdir(snapshot_parent, 0700)
    parent = File.lstat(snapshot_parent)
    exit 75 unless parent.directory? && !parent.symlink? && parent.uid == owner && (parent.mode & 0777) == 0700
    File.open(root, File::RDONLY) { |directory| directory.fsync }
    File.open(dir, File::RDONLY) { |directory| directory.fsync }
  ' "${REPLACEMENT_TRANSACTION_ROOT}" "${REPLACEMENT_TRANSACTION_DIR}" "$(/usr/bin/dirname "${REPLACEMENT_CANDIDATE_SNAPSHOT_APP}")" "${EXPECTED_OWNER_UID}" || return 1
  /usr/bin/ditto --rsrc --extattr --acl "${REPLACEMENT_CANDIDATE_APP}" "${REPLACEMENT_CANDIDATE_SNAPSHOT_APP}" || return 1
  source_after="$(capture_bundle_binding "${REPLACEMENT_CANDIDATE_APP}")" || return 1
  snapshot_binding="$(capture_bundle_binding "${REPLACEMENT_CANDIDATE_SNAPSHOT_APP}")" || return 1
  /usr/bin/ruby -rjson -e '
    before = JSON.parse(ARGV[0]); after = JSON.parse(ARGV[1]); snapshot = JSON.parse(ARGV[2])
    def content_rows(binding)
      binding.fetch("manifest").map do |row|
        row.reject { |key, _| ["uid", "gid", "nlink"].include?(key) }
      end
    end
    def signing_identity(binding)
      binding.fetch("identity").reject { |key, _| key == "ownerUID" }
    end
    stable_source = before == after
    exact_snapshot = content_rows(before) == content_rows(snapshot) &&
      signing_identity(before) == signing_identity(snapshot)
    exit(stable_source && exact_snapshot ? 0 : 75)
  ' "${source_before}" "${source_after}" "${snapshot_binding}" || return 1
  bind_replacement_public_candidate_snapshot "${snapshot_binding}" || return 1
  REPLACEMENT_CANDIDATE_BINDING="${snapshot_binding}"
  REPLACEMENT_PREVIOUS_BINDING="$(capture_bundle_binding "${REPLACEMENT_PREVIOUS_APP}")" || return 1
  bind_replacement_public_previous_snapshot "${REPLACEMENT_PREVIOUS_BINDING}" || return 1
  local snapshot_lifecycle="${REPLACEMENT_CANDIDATE_SNAPSHOT_APP}/Contents/Resources/vifty-helper-lifecycle.sh"
  /usr/bin/ruby -e '
    source, destination, owner_text = ARGV; owner = Integer(owner_text, 10)
    src = File.lstat(source)
    exit 75 unless src.file? && !src.symlink? && src.nlink == 1 && src.size.between?(1, 1_048_576)
    File.open(source, File::RDONLY | File::NOFOLLOW) do |input|
      opened = input.stat
      exit 75 unless opened.dev == src.dev && opened.ino == src.ino && opened.size == src.size && opened.mtime == src.mtime && opened.ctime == src.ctime
      File.open(destination, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0555) do |output|
        IO.copy_stream(input, output); output.flush; output.fsync
        final = input.stat
        exit 75 unless final.dev == opened.dev && final.ino == opened.ino && final.size == opened.size && final.mtime == opened.mtime && final.ctime == opened.ctime && output.stat.size == opened.size
      end
    end
    File.chown(owner, -1, destination) unless File.lstat(destination).uid == owner
    File.chmod(0555, destination)
    File.open(File.dirname(destination), File::RDONLY) { |directory| directory.fsync }
  ' "${snapshot_lifecycle}" "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" "${EXPECTED_OWNER_UID}" || return 1
  REPLACEMENT_LIFECYCLE_STAGED_SHA256="$(/usr/bin/shasum -a 256 "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" | /usr/bin/awk '{print $1}')" || return 1
  [[ "${REPLACEMENT_LIFECYCLE_STAGED_SHA256}" == "${REPLACEMENT_LIFECYCLE_EXPECTED_SHA256}" ]] || return 1
  force_lock_replacement_tree "${REPLACEMENT_TRANSACTION_DIR}" || return 1
  [[ -f "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" && -x "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" &&
     ! -L "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" ]] || return 1
  replacement_tree_is_locked "${REPLACEMENT_TRANSACTION_DIR}" || return 1
  if [[ -n "${TEST_ROOT}" && "${ROOT_FIXTURE_SWAP_CANDIDATE_AFTER_SNAPSHOT:-0}" == "1" ]]; then
    force_unlock_replacement_tree "${REPLACEMENT_CANDIDATE_APP}" >/dev/null 2>&1 || true
    /usr/bin/printf '%s\n' post-snapshot-source-mutation > "${REPLACEMENT_CANDIDATE_APP}/Contents/Resources/post-snapshot-source-mutation" || return 1
  fi
}

fixture_swap_locked_destination() {
  local checkpoint="$1"
  [[ -n "${TEST_ROOT}" && -n "${ROOT_FIXTURE_ALTERNATE_APP}" ]] || return 0
  case "${ROOT_FIXTURE_ALTERNATE_APP}" in "${TEST_ROOT}"/*) ;; *) return 75 ;; esac
  local requested=0
  if [[ "${checkpoint}" == "before-register" && "${ROOT_FIXTURE_SWAP_BEFORE_REGISTER:-0}" == "1" ]]; then requested=1; fi
  if [[ "${checkpoint}" == "before-enable" && "${ROOT_FIXTURE_SWAP_BEFORE_ENABLE:-0}" == "1" ]]; then requested=1; fi
  [[ "${requested}" -eq 1 ]] || return 0
  local displaced="${TEST_ROOT}/displaced-${checkpoint}-Vifty.app"
  unlock_replacement_tree "${REPLACEMENT_DESTINATION}" || return 75
  /bin/mv "${REPLACEMENT_DESTINATION}" "${displaced}" || return 75
  /bin/cp -R "${ROOT_FIXTURE_ALTERNATE_APP}" "${REPLACEMENT_DESTINATION}" || return 75
  lock_replacement_tree "${REPLACEMENT_DESTINATION}" || return 75
}

snapshot_prior_replacement_record() {
  local destination="$1"
  [[ -e "${ROOT_REPLACEMENT_RECORD}" && ! -L "${ROOT_REPLACEMENT_RECORD}" ]] || return 2
  /usr/bin/ruby -e '
    source, destination, owner_text = ARGV; owner = Integer(owner_text, 10)
    st = File.lstat(source)
    exit 75 unless st.file? && !st.symlink? && st.uid == owner && st.nlink == 1 &&
      (st.mode & 0777) == 0600 && st.size.between?(1, 4_194_304)
    File.open(source, File::RDONLY | File::NOFOLLOW) do |input|
      opened = input.stat
      File.open(destination, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0600) do |output|
        IO.copy_stream(input, output); output.flush; output.fsync
      end
      final = input.stat
      exit 75 unless final.dev == opened.dev && final.ino == opened.ino && final.size == opened.size
    end
  ' "${ROOT_REPLACEMENT_RECORD}" "${destination}" "${EXPECTED_OWNER_UID}"
}

remove_replacement_ledger_durably() {
  local prior_record="$1"
  /usr/bin/ruby -e '
    current, snapshot, dir, owner_text = ARGV; owner = Integer(owner_text, 10)
    cst = File.lstat(current); sst = File.lstat(snapshot)
    exit 75 unless cst.file? && !cst.symlink? && cst.uid == owner && cst.nlink == 1 &&
      (cst.mode & 0777) == 0600 && cst.size.between?(1, 4_194_304) &&
      sst.file? && !sst.symlink? && sst.size == cst.size &&
      File.binread(current) == File.binread(snapshot)
    File.unlink(current)
    File.open(dir, File::RDONLY) { |directory| directory.fsync }
    exit 75 if File.exist?(current) || File.symlink?(current)
  ' "${ROOT_REPLACEMENT_RECORD}" "${prior_record}" "${EXECUTION_DIR}" "${EXPECTED_OWNER_UID}"
}

remove_replacement_transaction_durably() {
  local transaction_dir="$1"
  [[ "${transaction_dir}" == "${REPLACEMENT_TRANSACTION_ROOT}/"* &&
     "$(/usr/bin/dirname "${transaction_dir}")" == "${REPLACEMENT_TRANSACTION_ROOT}" ]] || return 1
  /bin/rm -rf "${transaction_dir}" || return 1
  /usr/bin/ruby -e '
    removed, parent = ARGV
    exit 75 if File.exist?(removed) || File.symlink?(removed)
    st = File.lstat(parent)
    exit 75 unless st.directory? && !st.symlink?
    File.open(parent, File::RDONLY) { |directory| directory.fsync }
  ' "${transaction_dir}" "${REPLACEMENT_TRANSACTION_ROOT}"
}

release_prior_replacement_lock_after_quiesce() {
  local prior_record="$1"
  [[ "${OPERATION}" == "uninstall" || "${REPLACEMENT_PHASE}" == "prepare" ]] || return 0
  [[ -f "${prior_record}" && ! -L "${prior_record}" ]] || return 0
  local prior_descriptor prior_record_status prior_lifecycle_path prior_transaction_id
  if prior_descriptor="$(/usr/bin/ruby -rjson -e '
    record = JSON.parse(File.read(ARGV[0])); app = ARGV[1]; transaction_root = ARGV[2]
    status = record["status"]
    exit 2 unless ["replacement-prepared", "replacement-locked", "completed"].include?(status) && record["replacementAppPath"] == app
    transaction_id = record["replacementTransactionID"]
    exit 75 unless transaction_id.is_a?(String) &&
      transaction_id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
    lifecycle = record["replacementLifecyclePath"]
    expected_lifecycle = File.join(transaction_root, transaction_id, "vifty-helper-lifecycle.sh")
    lifecycle_sha = record["replacementLifecycleSHA256"]
    candidate = record["replacementCandidateBinding"]
    previous = record["replacementPreviousBinding"]
    locked = record["replacementLockedBinding"]
    transition = record["replacementFlagTransition"]
    transition_matches = lambda do |operation, target|
      transition.is_a?(Hash) && transition.keys.sort == %w[operation startedAt targetState].sort &&
        transition["operation"] == operation && transition["targetState"] == target &&
        transition["startedAt"].is_a?(Numeric)
    end
    transition_valid = case status
    when "replacement-prepared"
      transition.nil? || transition_matches.call("locking", "locked")
    when "replacement-locked"
      transition.nil? || transition_matches.call("unlocking", "unlocked")
    else
      transition.nil?
    end
    exit 75 unless lifecycle == expected_lifecycle && lifecycle_sha.is_a?(String) &&
      lifecycle_sha.match?(/\A[a-f0-9]{64}\z/) && transition_valid &&
      candidate.is_a?(Hash) && candidate["sourcePath"] == File.join(transaction_root, transaction_id, "CandidateSnapshot", "Vifty.app") &&
      previous.is_a?(Hash) && previous["sourcePath"] == app
    unless status == "replacement-prepared"
      result = record["replacementResult"]
      expected = result == "installed" ? candidate : (result == "rolled-back" ? previous : nil)
      same_identity = expected.is_a?(Hash) && locked.is_a?(Hash) && locked["sourcePath"] == app &&
        locked["manifest"] == expected["manifest"] && locked["manifestSHA256"] == expected["manifestSHA256"] &&
        locked["identity"] == expected["identity"]
      exit 75 unless same_identity
    end
    print "#{status}\t#{lifecycle}\t#{transaction_id}"
  ' "${prior_record}" "${APP_PATH}" "${REPLACEMENT_TRANSACTION_ROOT}")"; then
    :
  else
    local prior_status=$?
    [[ "${prior_status}" -eq 2 ]] && return 0
    return 1
  fi
  IFS=$'\t' read -r prior_record_status prior_lifecycle_path prior_transaction_id <<<"${prior_descriptor}"
  [[ -n "${prior_record_status}" && -n "${prior_lifecycle_path}" &&
     "${prior_lifecycle_path}" == "${REPLACEMENT_TRANSACTION_ROOT}/${prior_transaction_id}/vifty-helper-lifecycle.sh" ]] || return 1
  local prior_transaction_dir
  prior_transaction_dir="$(/usr/bin/dirname "${prior_lifecycle_path}")" || return 1

  # The flag-transition journal is intentionally inspected on a later
  # prepare/uninstall, not only by the process that changed the flags. A power
  # loss can leave either the destination or transaction tree fully changed,
  # partially changed, or already removed while the root-private ledger still
  # contains the preceding durable state. Authenticate the destination against
  # the candidate/previous identities before clearing any surviving lock.
  local before_binding after_binding destination_flag_state
  before_binding="$(capture_bundle_binding "${APP_PATH}")" || return 1
  /usr/bin/ruby -rjson -e '
    record = JSON.parse(File.read(ARGV[0])); current = JSON.parse(ARGV[1]); status = ARGV[2]; app = ARGV[3]
    equivalent = lambda do |expected|
      expected.is_a?(Hash) && current["sourcePath"] == app &&
        current["manifest"] == expected["manifest"] &&
        current["manifestSHA256"] == expected["manifestSHA256"] &&
        current["identity"] == expected["identity"]
    end
    valid = if status == "replacement-prepared"
      equivalent.call(record["replacementCandidateBinding"]) || equivalent.call(record["replacementPreviousBinding"])
    else
      equivalent.call(record["replacementLockedBinding"])
    end
    exit(valid ? 0 : 75)
  ' "${prior_record}" "${before_binding}" "${prior_record_status}" "${APP_PATH}" || return 1
  destination_flag_state="$(replacement_tree_flag_state "${APP_PATH}")" || return 1
  if [[ "${destination_flag_state}" != "unlocked" ]]; then
    force_unlock_replacement_tree "${APP_PATH}" || return 1
  fi
  after_binding="$(capture_bundle_binding "${APP_PATH}")" || return 1
  [[ "${before_binding}" == "${after_binding}" ]] || return 1

  # A prior retirement may itself have stopped after unlocking or removing the
  # transaction directory. The root-owned direct-child path and the still
  # authenticated ledger make each of those states safe to resume.
  if [[ -e "${prior_transaction_dir}" || -L "${prior_transaction_dir}" ]]; then
    [[ -d "${prior_transaction_dir}" && ! -L "${prior_transaction_dir}" ]] || return 1
    force_unlock_replacement_tree "${prior_transaction_dir}" || return 1
  fi
  remove_replacement_transaction_durably "${prior_transaction_dir}" || return 1
  remove_replacement_ledger_durably "${prior_record}" || return 1
}

capture_bundle_binding() {
  local app="$1"
  local kind="adhoc"
  local team_id=""
  local bundle_version=""
  local bundle_build=""
  local main_id="tech.reidar.vifty"
  local ctl_id="tech.reidar.vifty.ctl"
  local daemon_id="tech.reidar.vifty.daemon"
  local helper_id="tech.reidar.vifty.helper"
  if [[ -z "${TEST_ROOT}" ]]; then
    /usr/bin/codesign --verify --deep --strict "${app}" >/dev/null 2>&1 || return 1
    local executable expected_id details observed_id observed_team main_details
    local observed_teams=""
    local all_developer_id=1
    for executable in Vifty viftyctl ViftyDaemon ViftyHelper; do
      case "${executable}" in
        Vifty) expected_id="${main_id}" ;;
        viftyctl) expected_id="${ctl_id}" ;;
        ViftyDaemon) expected_id="${daemon_id}" ;;
        ViftyHelper) expected_id="${helper_id}" ;;
      esac
      details="$(/usr/bin/codesign -dv --verbose=4 "${app}/Contents/MacOS/${executable}" 2>&1)" || return 1
      observed_id="$(/usr/bin/printf '%s\n' "${details}" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')"
      observed_team="$(/usr/bin/printf '%s\n' "${details}" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
      [[ "${observed_id}" == "${expected_id}" ]] || return 1
      if ! /usr/bin/printf '%s\n' "${details}" | /usr/bin/grep -E '^Authority=Developer ID Application:' >/dev/null; then
        all_developer_id=0
      fi
      observed_teams="${observed_teams}${observed_team}\n"
      if [[ "${executable}" == "Vifty" ]]; then main_details="${details}"; team_id="${observed_team}"; fi
    done
    if /usr/bin/printf '%s\n' "${main_details}" | /usr/bin/grep -E '^Authority=Developer ID Application:' >/dev/null; then
      [[ "${all_developer_id}" -eq 1 ]] || return 1
      [[ "${team_id}" =~ ^[A-Z0-9]{10}$ ]] || return 1
      while IFS= read -r observed_team; do
        [[ "${observed_team}" == "${team_id}" ]] || return 1
      done < <(/usr/bin/printf '%b' "${observed_teams}")
      kind="developer-id"
    else
      team_id=""
    fi
  fi
  bundle_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "${app}/Contents/Info.plist" 2>/dev/null || true)"
  bundle_build="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "${app}/Contents/Info.plist" 2>/dev/null || true)"
  /usr/bin/ruby -rjson -rdigest -e '
    root, kind, team_id, main_id, ctl_id, daemon_id, helper_id, bundle_version, bundle_build = ARGV
    components = {
      "Vifty" => main_id,
      "viftyctl" => ctl_id,
      "ViftyDaemon" => daemon_id,
      "ViftyHelper" => helper_id
    }
    root = File.expand_path(root)
    rst = File.lstat(root)
    exit 75 unless rst.directory? && !rst.symlink?

    def unchanged?(before, after)
      before.dev == after.dev && before.ino == after.ino && before.size == after.size &&
        before.mode == after.mode && before.uid == after.uid && before.gid == after.gid &&
        before.nlink == after.nlink && before.mtime == after.mtime && before.ctime == after.ctime
    end

    def file_digest(path, expected)
      digest = Digest::SHA256.new
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        opened = file.stat
        exit 75 unless unchanged?(expected, opened)
        while (chunk = file.read(1_048_576))
          digest.update(chunk)
        end
        final = file.stat
        exit 75 unless unchanged?(opened, final)
      end
      digest.hexdigest
    end

    snapshot = lambda do
      entries = [{
        "path" => ".", "type" => "directory", "mode" => (rst.mode & 07777),
        "uid" => rst.uid, "gid" => rst.gid, "nlink" => rst.nlink
      }]
      walk = nil
      walk = lambda do |directory, prefix|
        dst = File.lstat(directory)
        exit 75 unless dst.directory? && !dst.symlink?
        Dir.children(directory).sort.each do |name|
          path = File.join(directory, name)
          relative = prefix.empty? ? name : File.join(prefix, name)
          stat = File.lstat(path)
          mode = stat.mode & 07777
          if stat.directory? && !stat.symlink?
            entries << {
              "path" => relative, "type" => "directory", "mode" => mode,
              "uid" => stat.uid, "gid" => stat.gid, "nlink" => stat.nlink
            }
            walk.call(path, relative)
          elsif stat.file? && !stat.symlink?
            entries << {
              "path" => relative, "type" => "file", "mode" => mode,
              "uid" => stat.uid, "gid" => stat.gid, "nlink" => stat.nlink,
              "size" => stat.size, "sha256" => file_digest(path, stat)
            }
          elsif stat.symlink?
            target = File.readlink(path)
            resolved = File.expand_path(target, File.dirname(path))
            exit 75 if target.start_with?("/") || (resolved != root && !resolved.start_with?(root + "/"))
            final_link = File.lstat(path)
            exit 75 unless unchanged?(stat, final_link) && File.readlink(path) == target
            entries << {
              "path" => relative, "type" => "symlink", "mode" => mode,
              "uid" => stat.uid, "gid" => stat.gid, "nlink" => stat.nlink,
              "size" => stat.size, "linkTarget" => target
            }
          else
            exit 75
          end
        end
        final = File.lstat(directory)
        exit 75 unless unchanged?(dst, final)
      end
      walk.call(root, "")
      # This ordering is part of the user/root public-candidate contract and
      # must match release-candidate-inventory.rb exactly, including prefix
      # cases such as A.foo sorting before A/child.
      entries.sort_by { |entry| entry.fetch("path").b }
    end

    first = snapshot.call
    second = snapshot.call
    final_root = File.lstat(root)
    exit 75 unless first == second && unchanged?(rst, final_root)
    by_path = {}
    first.each { |entry| by_path[entry.fetch("path")] = entry }
    component_hashes = {}
    components.each_key do |name|
      entry = by_path["Contents/MacOS/#{name}"]
      exit 75 unless entry && entry["type"] == "file" && (entry["mode"] & 0111) != 0
      component_hashes[name] = entry["sha256"]
    end
    identity = {
      "kind" => kind,
      "ownerUID" => rst.uid,
      "teamID" => (kind == "developer-id" ? team_id : nil),
      "bundleVersion" => (bundle_version.empty? ? nil : bundle_version),
      "bundleBuild" => (bundle_build.empty? ? nil : bundle_build),
      "componentIdentifiers" => components,
      "componentSHA256" => component_hashes
    }
    content_manifest = first.map do |row|
      row.reject do |key, _|
        ["uid", "gid", "nlink"].include?(key) || (row["type"] == "symlink" && key == "size")
      end
    end
    payload = {
      "sourcePath" => root,
      "manifest" => first,
      "manifestSHA256" => Digest::SHA256.hexdigest(JSON.generate(first)),
      "contentManifestSHA256" => Digest::SHA256.hexdigest(JSON.generate(content_manifest)),
      "identity" => identity
    }
    print JSON.generate(payload)
  ' "${app}" "${kind}" "${team_id}" "${main_id}" "${ctl_id}" "${daemon_id}" "${helper_id}" "${bundle_version}" "${bundle_build}"
}

persist_root_record() {
  local record_status="$1"
  local record_blocker="${2:-}"
  ensure_privileged_execution_directory
  /usr/bin/ruby -rjson -e '
    path, replacement_record_path, owner_text, operation, status, blocker, phases_path, authority_mode, requesting_uid_text, requesting_pid_text, replacement_path, requesting_start_id, transaction_id, replacement_result, candidate_binding_json, previous_binding_json, lifecycle_path, lifecycle_sha, locked_binding_json, public_candidate_expectation_json = ARGV
    owner = Integer(owner_text, 10)
    requesting_uid = Integer(requesting_uid_text, 10)
    requesting_pid = Integer(requesting_pid_text, 10)
    abort "invalid lifecycle caller binding" unless requesting_uid >= 0 && requesting_pid > 1
    phases = []
    index = {}
    if File.file?(phases_path)
      File.readlines(phases_path, chomp: true).each do |line|
        phase, state = line.split("\t", 2)
        next unless phase && state
        unless index.key?(phase)
          index[phase] = phases.length
          phases << {"phase" => phase, "attempted" => false, "succeeded" => false}
        end
        row = phases.fetch(index.fetch(phase))
        row["attempted"] = true if state == "attempted"
        row["succeeded"] = true if state == "succeeded"
      end
    end
    payload = {
      "schemaVersion" => 1,
      "schemaID" => "https://vifty.app/schemas/helper-maintenance-execution-v1.json",
      "operation" => operation,
      "status" => status,
      "blocker" => blocker,
      "authorityMode" => authority_mode,
      "requestingUserID" => requesting_uid,
      "requestingProcessID" => requesting_pid,
      "updatedAt" => Time.now.to_f,
      "phases" => phases
    }
    unless replacement_path.empty?
      abort "invalid replacement caller start binding" unless requesting_start_id.match?(/\A[a-f0-9]{64}\z/)
      abort "invalid replacement transaction binding" unless transaction_id.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
      payload["replacementAppPath"] = replacement_path
      payload["requestingProcessStartID"] = requesting_start_id
      payload["replacementTransactionID"] = transaction_id
      payload["replacementResult"] = replacement_result unless replacement_result.empty?
      payload["replacementCandidateBinding"] = JSON.parse(candidate_binding_json) unless candidate_binding_json.empty?
      payload["replacementPreviousBinding"] = JSON.parse(previous_binding_json) unless previous_binding_json.empty?
      payload["replacementLifecyclePath"] = lifecycle_path unless lifecycle_path.empty?
      payload["replacementLifecycleSHA256"] = lifecycle_sha unless lifecycle_sha.empty?
      payload["replacementLockedBinding"] = JSON.parse(locked_binding_json) unless locked_binding_json.empty?
      payload["replacementPublicCandidateExpectation"] = JSON.parse(public_candidate_expectation_json) unless public_candidate_expectation_json.empty?
      if status == "replacement-prepared"
        abort "missing immutable replacement bindings" unless payload["replacementCandidateBinding"].is_a?(Hash) &&
          payload["replacementPreviousBinding"].is_a?(Hash) && payload["replacementLifecyclePath"].is_a?(String) &&
          payload["replacementLifecycleSHA256"].to_s.match?(/\A[a-f0-9]{64}\z/)
      end
    end
    atomic_write = lambda do |destination, mode|
      dir = File.dirname(destination)
      tmp = File.join(dir, ".#{File.basename(destination)}.#{Process.pid}.tmp")
      flags = File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW
      File.open(tmp, flags, mode) do |file|
        file.write(JSON.generate(payload)); file.write("\n"); file.flush; file.fsync
      end
      File.chown(owner, -1, tmp) unless File.lstat(tmp).uid == owner
      File.chmod(mode, tmp)
      File.rename(tmp, destination)
      File.open(dir, File::RDONLY) { |directory| directory.fsync }
    end
    if !replacement_path.empty? && ["replacement-prepared", "replacement-locked", "completed"].include?(status)
      atomic_write.call(replacement_record_path, 0600)
    end
    atomic_write.call(path, 0644)
  ' "${ROOT_EXECUTION_RECORD}" "${ROOT_REPLACEMENT_RECORD}" "${EXPECTED_OWNER_UID}" "${OPERATION}" "${record_status}" "${record_blocker}" "${ROOT_PHASE_LOG}" "${ROOT_AUTHORITY_MODE:-undetermined}" "${REQUESTING_USER_UID}" "${REQUESTING_PROCESS_ID}" "${REPLACEMENT_DESTINATION}" "${REQUESTING_PROCESS_START_ID}" "${REPLACEMENT_TRANSACTION_ID}" "${REPLACEMENT_RESULT}" "${REPLACEMENT_CANDIDATE_BINDING}" "${REPLACEMENT_PREVIOUS_BINDING}" "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" "${REPLACEMENT_LIFECYCLE_STAGED_SHA256}" "${REPLACEMENT_LOCKED_BINDING}" "${REPLACEMENT_PUBLIC_CANDIDATE_EXPECTATION}"
}

record_root_phase() {
  local phase="$1"
  local state="$2"
  /usr/bin/printf '%s\t%s\n' "${phase}" "${state}" >> "${ROOT_PHASE_LOG}"
  persist_root_record in-progress ""
}

root_fail() {
  local message="$1"
  ROOT_FAILURE="${message}"
  persist_root_record blocked "${message}" || true
  echo "helper-lifecycle: ${message}" >&2
  exit 75
}

validate_root_authority() {
  /usr/bin/ruby -rjson -e '
    path, claimed_path, dir, owner_text, operation, expected_boot, helper_snapshot_digest = ARGV
    owner = Integer(owner_text, 10)
    exit 2 unless File.exist?(path) || File.symlink?(path)
    exit 75 if File.exist?(claimed_path) || File.symlink?(claimed_path)
    begin
      dst = File.lstat(dir); pst = File.lstat(path)
      safe = dst.directory? && !dst.symlink? && dst.uid == owner && (dst.mode & 0777) == 0700 &&
        pst.file? && !pst.symlink? && pst.uid == owner && pst.nlink == 1 && (pst.mode & 0777) == 0600 && pst.size.between?(1, 65_536)
      exit 75 unless safe
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        fst = file.stat
        exit 75 unless fst.dev == pst.dev && fst.ino == pst.ino && fst.size == pst.size
        data = file.read(65_537)
        exit 75 if data.nil? || data.bytesize > 65_536
        receipt = JSON.parse(data)
        fans = receipt["expectedFanIDs"]
        digest = receipt["helperSHA256"]
        valid = receipt["schemaVersion"] == 1 &&
          receipt["schemaID"] == "https://vifty.app/schemas/helper-maintenance-authority-v1.json" &&
          receipt["recordKind"] == "daemon-authorized-helper-maintenance" &&
          receipt["operation"].is_a?(String) &&
          receipt["tokenID"].is_a?(String) && !receipt["tokenID"].empty? &&
          receipt["tokenIssuedAt"].is_a?(Numeric) && receipt["authorizedAt"].is_a?(Numeric) && receipt["expiresAt"].is_a?(Numeric) &&
          receipt["tokenIssuedAt"] <= receipt["authorizedAt"] && receipt["authorizedAt"] < receipt["expiresAt"] &&
          (receipt["expiresAt"] - receipt["authorizedAt"]).between?(30, 600) &&
          receipt["bootSessionID"].is_a?(String) && !receipt["bootSessionID"].empty? &&
          receipt["daemonSessionID"].is_a?(String) && !receipt["daemonSessionID"].empty? &&
          receipt["journalGeneration"].is_a?(Integer) && receipt["journalGeneration"] >= 0 &&
          receipt["quiesceGeneration"].is_a?(Integer) && receipt["quiesceGeneration"] > 0 &&
          fans.is_a?(Array) && !fans.empty? && fans.all? { |id| id.is_a?(Integer) && id.between?(0, 9) } && fans.uniq.sort == fans &&
          digest.is_a?(String) && digest.match?(/\A[a-f0-9]{64}\z/) &&
          receipt["quiesced"] == true && receipt["tokenConsumed"] == true
        exit 75 unless valid
        exit 3 if receipt["operation"] != operation || Time.now.to_f > receipt["expiresAt"] ||
          receipt["bootSessionID"] != expected_boot || digest != helper_snapshot_digest
      end
      final = File.lstat(path)
      exit 75 unless final.dev == pst.dev && final.ino == pst.ino && final.size == pst.size
      File.link(path, claimed_path)
      claimed = File.lstat(claimed_path)
      exit 75 unless claimed.dev == pst.dev && claimed.ino == pst.ino && claimed.nlink == 2
      File.unlink(path)
      claimed = File.lstat(claimed_path)
      exit 75 unless claimed.dev == pst.dev && claimed.ino == pst.ino && claimed.nlink == 1 &&
        claimed.uid == owner && (claimed.mode & 0777) == 0600
      File.open(dir, File::RDONLY) { |directory| directory.fsync }
      exit 0
    rescue JSON::ParserError, SystemCallError
      exit 75
    end
  ' "${AUTHORITY_PATH}" "${CLAIMED_AUTHORITY_PATH}" "${MAINTENANCE_DIR}" "${EXPECTED_OWNER_UID}" "${OPERATION}" "${EXPECTED_BOOT_SESSION_ID}" "${HELPER_SNAPSHOT_SHA256}"
}

remove_validated_authority() {
  [[ -e "${AUTHORITY_PATH}" ]] || return 0
  /bin/rm -f "${AUTHORITY_PATH}"
}

remove_claimed_authority() {
  [[ -e "${CLAIMED_AUTHORITY_PATH}" ]] || return 0
  /bin/rm -f "${CLAIMED_AUTHORITY_PATH}"
}

validate_offline_report() {
  /usr/bin/ruby -rjson -e '
    report = JSON.parse(File.read(ARGV[0])); operation = ARGV[1]; claimed_path = ARGV[2]; owner = Integer(ARGV[3], 10)
    fans = report["fanResults"]
    ids = fans.is_a?(Array) ? fans.map { |fan| fan["fanID"] } : []
    expected_ids = nil
    unless claimed_path == "-"
      st = File.lstat(claimed_path)
      exit 75 unless st.file? && !st.symlink? && st.uid == owner && st.nlink == 1 && (st.mode & 0777) == 0600
      File.open(claimed_path, File::RDONLY | File::NOFOLLOW) do |file|
        expected_ids = JSON.parse(file.read(65_537))["expectedFanIDs"]
      end
    end
    ok = report["schemaVersion"] == 1 &&
      report["schemaID"] == "https://vifty.app/schemas/helper-maintenance-report-v1.json" &&
      report["operation"] == operation && report["safeToStop"] == true &&
      report["quiesced"] == true && report["restoreAttempted"] == true &&
      report["restoreSucceeded"] == true && report["completeExpectedSetConfirmed"] == true &&
      report["blockers"] == [] && report["token"].nil? && report["tokenConsumed"] == false &&
      fans.is_a?(Array) && !fans.empty? && ids.all? { |id| id.is_a?(Integer) && id.between?(0, 9) } && ids.uniq.sort == ids &&
      (expected_ids.nil? || ids == expected_ids) &&
      fans.all? { |fan| fan["confirmedOSManaged"] == true && fan["freshConfirmationAt"].is_a?(Numeric) && (Time.now.to_f - fan["freshConfirmationAt"]).abs <= 60 }
    exit(ok ? 0 : 75)
  ' "$1" "$2" "$3" "${EXPECTED_OWNER_UID}"
}

is_service_disabled() {
  "${LAUNCHCTL}" print-disabled system 2>/dev/null \
    | /usr/bin/ruby -e '
      label = ARGV.fetch(0)
      disabled = STDIN.each_line.any? do |line|
        match = line.match(/\A\s*"?([A-Za-z0-9._-]+)"?\s*=>\s*true\s*,?\s*\z/)
        match && match[1] == label
      end
      exit(disabled ? 0 : 1)
    ' "${SERVICE_LABEL}"
}

disable_and_confirm_service() {
  "${LAUNCHCTL}" disable "system/${SERVICE_LABEL}" >/dev/null 2>&1 || return 1
  is_service_disabled
}

enable_and_confirm_service() {
  "${LAUNCHCTL}" enable "system/${SERVICE_LABEL}" >/dev/null 2>&1 || return 1
  ! is_service_disabled
}

stop_and_confirm_offline() {
  local attempts=30
  if "${LAUNCHCTL}" print "system/${SERVICE_LABEL}" >/dev/null 2>&1; then
    "${LAUNCHCTL}" bootout "system/${SERVICE_LABEL}" >/dev/null 2>&1 || return 1
  fi
  while [[ "${attempts}" -gt 0 ]]; do
    if ! "${LAUNCHCTL}" print "system/${SERVICE_LABEL}" >/dev/null 2>&1; then
      is_service_disabled || return 1
      return 0
    fi
    /bin/sleep 0.1
    attempts=$((attempts - 1))
  done
  return 1
}

stage_trusted_helper() {
  local helper_dir="$1"
  local staged="${helper_dir}/ViftyHelper"
  /bin/cp "${HELPER_SNAPSHOT}" "${staged}"
  /bin/chmod 500 "${staged}"
  if [[ -z "${TEST_ROOT}" ]]; then
    /usr/sbin/chown 0:0 "${staged}"
  fi
  local actual details identifier team runtime_line
  actual="$(/usr/bin/shasum -a 256 "${staged}" | /usr/bin/awk '{print $1}')"
  [[ "${actual}" == "${HELPER_SNAPSHOT_SHA256}" ]] || return 1
  if [[ -z "${TEST_ROOT}" ]]; then
    /usr/bin/codesign --verify --strict \
      --test-requirement "=anchor apple generic and identifier \"${HELPER_SIGNING_ID}\" and certificate leaf[subject.OU] = \"${RELEASE_TEAM_ID}\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" \
      "${staged}" >/dev/null 2>&1 || return 1
    details="$(/usr/bin/codesign -dvvv "${staged}" 2>&1)"
    identifier="$(/usr/bin/printf '%s\n' "${details}" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')"
    team="$(/usr/bin/printf '%s\n' "${details}" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    runtime_line="$(/usr/bin/printf '%s\n' "${details}" | /usr/bin/grep -E '^CodeDirectory .*flags=.*\(runtime\)' || true)"
    /usr/bin/printf '%s\n' "${details}" | /usr/bin/grep -E '^Authority=Developer ID Application: .+ \('"${RELEASE_TEAM_ID}"'\)$' >/dev/null || return 1
    /usr/bin/printf '%s\n' "${details}" | /usr/bin/grep -F 'Authority=Developer ID Certification Authority' >/dev/null || return 1
    /usr/bin/printf '%s\n' "${details}" | /usr/bin/grep -F 'Authority=Apple Root CA' >/dev/null || return 1
    [[ "${identifier}" == "${HELPER_SIGNING_ID}" && "${team}" == "${RELEASE_TEAM_ID}" && -n "${runtime_line}" ]] || return 1
  fi
  TRUSTED_HELPER="${staged}"
}

stage_verified_legacy_v132_daemon() {
  local daemon_dir="$1"
  local staged="${daemon_dir}/ViftyDaemon.v1.3.2"
  local expected_digest="${V132_DAEMON_SHA256}"
  if [[ -n "${TEST_ROOT}" ]]; then expected_digest="${V132_FIXTURE_DAEMON_SHA256}"; fi
  /usr/bin/ruby -e '
    source, destination, owner_text = ARGV
    owner = Integer(owner_text, 10)
    st = File.lstat(source)
    exit 75 unless st.file? && !st.symlink? && st.uid == owner && st.nlink == 1 &&
      (st.mode & 0022).zero? && (st.mode & 0111) != 0 && st.size.between?(1, 134_217_728)
    File.open(source, File::RDONLY | File::NOFOLLOW) do |input|
      opened = input.stat
      exit 75 unless opened.dev == st.dev && opened.ino == st.ino && opened.size == st.size
      File.open(destination, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0500) do |output|
        IO.copy_stream(input, output); output.flush; output.fsync
        final = input.stat
        exit 75 unless final.dev == opened.dev && final.ino == opened.ino &&
          final.size == opened.size && output.stat.size == opened.size
      end
    end
  ' "${PRIVILEGED_HELPER}" "${staged}" "${EXPECTED_OWNER_UID}" || return 1
  /bin/chmod 500 "${staged}"
  if [[ -z "${TEST_ROOT}" ]]; then /usr/sbin/chown 0:0 "${staged}"; fi
  local actual details identifier team runtime_line cdhash
  actual="$(/usr/bin/shasum -a 256 "${staged}" | /usr/bin/awk '{print $1}')"
  [[ "${actual}" == "${expected_digest}" ]] || return 1
  if [[ -z "${TEST_ROOT}" ]]; then
    /usr/bin/codesign --verify --strict \
      --test-requirement "=anchor apple generic and identifier \"${DAEMON_SIGNING_ID}\" and certificate leaf[subject.OU] = \"${RELEASE_TEAM_ID}\" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" \
      "${staged}" >/dev/null 2>&1 || return 1
    details="$(/usr/bin/codesign -dvvv "${staged}" 2>&1)"
    identifier="$(/usr/bin/printf '%s\n' "${details}" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')"
    team="$(/usr/bin/printf '%s\n' "${details}" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    cdhash="$(/usr/bin/printf '%s\n' "${details}" | /usr/bin/awk -F= '/^CDHash=/{print $2; exit}')"
    runtime_line="$(/usr/bin/printf '%s\n' "${details}" | /usr/bin/grep -E '^CodeDirectory .*flags=.*\(runtime\)' || true)"
    /usr/bin/printf '%s\n' "${details}" | /usr/bin/grep -E '^Authority=Developer ID Application: .+ \('"${RELEASE_TEAM_ID}"'\)$' >/dev/null || return 1
    /usr/bin/printf '%s\n' "${details}" | /usr/bin/grep -F 'Authority=Developer ID Certification Authority' >/dev/null || return 1
    /usr/bin/printf '%s\n' "${details}" | /usr/bin/grep -F 'Authority=Apple Root CA' >/dev/null || return 1
    [[ "${identifier}" == "${DAEMON_SIGNING_ID}" && "${team}" == "${RELEASE_TEAM_ID}" && "${cdhash}" == "${V132_DAEMON_CDHASH}" && -n "${runtime_line}" ]] || return 1
  fi
}

root_worker() {
  (
    set -euo pipefail
    if [[ -z "${TEST_ROOT}" && "$(/usr/bin/id -u)" -ne 0 ]]; then
      echo "helper-lifecycle: internal cleanup worker requires administrator authorization." >&2
      exit 77
    fi
    case "${EXPECTED_OWNER_UID}" in ''|*[!0-9]*) echo "helper-lifecycle: invalid privileged evidence owner." >&2; exit 64 ;; esac
    case "${REQUESTING_USER_UID}" in ''|*[!0-9]*) echo "helper-lifecycle: invalid requesting user binding." >&2; exit 64 ;; esac
    case "${REQUESTING_PROCESS_ID}" in ''|*[!0-9]*) echo "helper-lifecycle: invalid requesting process binding." >&2; exit 64 ;; esac
    [[ "${REQUESTING_PROCESS_ID}" -gt 1 ]] || { echo "helper-lifecycle: requesting process binding is unsafe." >&2; exit 64; }
    if [[ -n "${REPLACEMENT_PHASE}" ]]; then
      current_process_start_id="$(process_start_identity "${REQUESTING_PROCESS_ID}" "${REQUESTING_USER_UID}")" || exit 75
      [[ "${current_process_start_id}" == "${REQUESTING_PROCESS_START_ID}" ]] || {
        echo "helper-lifecycle: requesting parent process start identity changed before root prepare." >&2
        exit 75
      }
    fi
    [[ -x "${LAUNCHCTL}" ]] || { echo "helper-lifecycle: launchctl is unavailable." >&2; exit 66; }

    local local_tmp authority_status authority_mode offline_report claimed_for_validation
    local requires_legacy_v132=0
    local_tmp="$(/usr/bin/mktemp -d "${ROOT_SCRATCH_PARENT}/vifty-lifecycle-worker.XXXXXX")"
    ROOT_WORKER_TMP="${local_tmp}"
    root_worker_scratch_cleanup() {
      local code=$?
      trap - EXIT
      if [[ -n "${ROOT_WORKER_TMP:-}" ]]; then
        /bin/rm -rf "${ROOT_WORKER_TMP}"
        ROOT_WORKER_TMP=""
      fi
      exit "${code}"
    }
    trap root_worker_scratch_cleanup EXIT
    if [[ -z "${TEST_ROOT}" ]]; then /usr/sbin/chown 0:0 "${local_tmp}"; fi
    /bin/chmod 700 "${local_tmp}"
    ROOT_PHASE_LOG="${local_tmp}/root-phases.tsv"
    : > "${ROOT_PHASE_LOG}"
    /bin/chmod 600 "${ROOT_PHASE_LOG}"
    ROOT_FAILURE="Privileged lifecycle worker exited before completion."
    ROOT_AUTHORITY_MODE="undetermined"
    ROOT_AUTHORITY_CLAIMED=0
    ROOT_COMPLETED=0
    ROOT_NEW_TRANSACTION_OWNED=0
    ROOT_NEW_TRANSACTION_COMMITTED=0
    PRIOR_REPLACEMENT_RECORD="${local_tmp}/prior-replacement-record.json"
    if [[ -e "${ROOT_REPLACEMENT_RECORD}" || -L "${ROOT_REPLACEMENT_RECORD}" ]]; then
      snapshot_prior_replacement_record "${PRIOR_REPLACEMENT_RECORD}" || root_fail "The prior privileged replacement record could not be snapshotted safely."
    fi
    root_worker_exit() {
      local code=$?
      trap - EXIT HUP INT TERM
      if [[ "${ROOT_COMPLETED}" -eq 0 ]]; then
        persist_root_record blocked "${ROOT_FAILURE}" >/dev/null 2>&1 || true
        if [[ "${ROOT_NEW_TRANSACTION_OWNED}" -eq 1 && "${ROOT_NEW_TRANSACTION_COMMITTED}" -eq 0 &&
              -d "${REPLACEMENT_TRANSACTION_DIR}" && ! -L "${REPLACEMENT_TRANSACTION_DIR}" ]]; then
          force_unlock_replacement_tree "${REPLACEMENT_TRANSACTION_DIR}" >/dev/null 2>&1 || true
          remove_replacement_transaction_durably "${REPLACEMENT_TRANSACTION_DIR}" >/dev/null 2>&1 || true
        fi
        if [[ "${ROOT_AUTHORITY_CLAIMED}" -eq 1 ]]; then
          remove_claimed_authority >/dev/null 2>&1 || true
        fi
      fi
      if [[ -n "${ROOT_WORKER_TMP:-}" ]]; then
        /bin/rm -rf "${ROOT_WORKER_TMP}"
        ROOT_WORKER_TMP=""
      fi
      exit "${code}"
    }
    # Replace the setup-only scratch trap once authenticated failure evidence is safe to persist.
    trap root_worker_exit EXIT
    trap 'ROOT_FAILURE="Privileged lifecycle worker received HUP."; exit 129' HUP
    trap 'ROOT_FAILURE="Privileged lifecycle worker received INT."; exit 130' INT
    trap 'ROOT_FAILURE="Privileged lifecycle worker received TERM."; exit 143' TERM

    ensure_privileged_authority_directory || root_fail "The fixed privileged authority directory is unsafe."
    ensure_privileged_execution_directory || root_fail "The fixed root execution-evidence directory is unsafe."
    if [[ "${REPLACEMENT_PHASE}" == "prepare" ]]; then
      [[ ! -e "${REPLACEMENT_TRANSACTION_DIR}" && ! -L "${REPLACEMENT_TRANSACTION_DIR}" ]] || root_fail "The replacement transaction ID already exists and cannot be replayed."
      ROOT_NEW_TRANSACTION_OWNED=1
      stage_replacement_candidate_snapshot || root_fail "The complete candidate could not be copied, independently identity-verified, lifecycle-bound, and locked in a root-owned snapshot before helper teardown."
    fi
    if [[ -e "${CLAIMED_AUTHORITY_PATH}" || -L "${CLAIMED_AUTHORITY_PATH}" ]]; then
      root_fail "A prior or concurrent root worker already claimed maintenance authority."
    fi
    record_root_phase verify-privileged-authority attempted
    case "${ROOT_AUTHORITY_EXPECTATION}" in
      daemon-receipt)
        if validate_root_authority; then
          authority_mode="daemon-receipt"
          ROOT_AUTHORITY_CLAIMED=1
        else
          authority_status=$?
          if [[ "${authority_status}" -eq 3 ]]; then
            remove_validated_authority || root_fail "An expired daemon receipt could not be revoked."
          fi
          root_fail "Protocol-v2 teardown requires its exact current root-owned daemon receipt."
        fi
        ;;
      protocol-mismatch-offline)
        if validate_root_authority; then
          authority_mode="daemon-receipt"
          ROOT_AUTHORITY_CLAIMED=1
        else
          authority_status=$?
          case "${authority_status}" in
            2) authority_mode="offline-auto" ;;
            3)
              remove_validated_authority || root_fail "An expired or operation-mismatched daemon receipt could not be revoked."
              authority_mode="offline-auto"
              ;;
            *) root_fail "The root-owned daemon maintenance receipt is malformed or unsafe." ;;
          esac
        fi
        ;;
      helper-unreachable)
        if validate_root_authority; then
          authority_mode="daemon-receipt"
          ROOT_AUTHORITY_CLAIMED=1
        else
          authority_status=$?
          case "${authority_status}" in
            2)
              authority_mode="offline-auto"
              requires_legacy_v132=1
              ;;
            3)
              remove_validated_authority || root_fail "An expired or operation-mismatched daemon receipt could not be revoked."
              authority_mode="offline-auto"
              requires_legacy_v132=1
              ;;
            *) root_fail "The root-owned daemon maintenance receipt is malformed or unsafe." ;;
          esac
        fi
        ;;
      *) root_fail "The root worker received no authenticated maintenance-authority classification." ;;
    esac
    ROOT_AUTHORITY_MODE="${authority_mode}"
    if [[ "${requires_legacy_v132}" -eq 1 ]]; then
      stage_verified_legacy_v132_daemon "${local_tmp}" || root_fail "The installed daemon is not the exact published Developer ID v1.3.2 compatibility binary."
    fi
    record_root_phase verify-privileged-authority succeeded

    record_root_phase disable-service-and-confirm-offline attempted
    disable_and_confirm_service || root_fail "The helper service label could not be disabled before teardown."
    stop_and_confirm_offline || root_fail "The helper service could not be proven disabled and offline; no files were removed."
    record_root_phase disable-service-and-confirm-offline succeeded

    if [[ -n "${TEST_ROOT}" && "${ROOT_FIXTURE_SIGNAL}" == "TERM" ]]; then
      /bin/kill -TERM "${BASHPID}"
      root_fail "Fixture TERM did not stop the root worker."
    fi

    record_root_phase post-freeze-offline-auto-confirm attempted
    stage_trusted_helper "${local_tmp}" || root_fail "The offline helper snapshot failed digest, Developer ID, identifier, or hardened-runtime verification."
    offline_report="${local_tmp}/offline-authority.json"
    if ! "${TRUSTED_HELPER}" authorizeLegacyTeardown --operation "${OPERATION}" --json > "${offline_report}"; then
      root_fail "Offline full-set Auto restoration did not authorize teardown."
    fi
    /bin/chmod 600 "${offline_report}"
    if [[ "${authority_mode}" == "daemon-receipt" ]]; then
      claimed_for_validation="${CLAIMED_AUTHORITY_PATH}"
    else
      claimed_for_validation="-"
    fi
    validate_offline_report "${offline_report}" "${OPERATION}" "${claimed_for_validation}" || root_fail "Offline Auto readback did not confirm the authorized complete trusted fan inventory."
    is_service_disabled || root_fail "The service relaunch freeze was lost after offline Auto confirmation."
    if "${LAUNCHCTL}" print "system/${SERVICE_LABEL}" >/dev/null 2>&1; then
      root_fail "The helper service relaunched after offline Auto confirmation."
    fi
    record_root_phase post-freeze-offline-auto-confirm succeeded

    release_prior_replacement_lock_after_quiesce "${PRIOR_REPLACEMENT_RECORD}" || root_fail "A prior immutable replacement bundle or lifecycle copy could not be released after quiesce and Auto proof."

    if [[ "${authority_mode}" == "daemon-receipt" ]]; then
      remove_claimed_authority || root_fail "The single-use daemon receipt claim could not be consumed after offline Auto proof."
      ROOT_AUTHORITY_CLAIMED=0
    fi

    record_root_phase remove-legacy-helper-plist-and-logs attempted
    /bin/rm -f "${PRIVILEGED_HELPER}" "${LEGACY_PLIST}" "${STDOUT_LOG}" "${STDERR_LOG}" \
      || root_fail "Legacy helper artifacts could not be removed."
    record_root_phase remove-legacy-helper-plist-and-logs succeeded

    if [[ -n "${TEST_ROOT}" && "${ROOT_FIXTURE_RETURN_INCOMPLETE}" == "1" ]]; then
      ROOT_COMPLETED=1
      exit 0
    fi

    if [[ "${OPERATION}" == "repair" && "${REPLACEMENT_PHASE}" != "prepare" ]]; then
      record_root_phase reenable-service-after-cleanup attempted
      enable_and_confirm_service || root_fail "The helper service label could not be re-enabled after cleanup."
      record_root_phase reenable-service-after-cleanup succeeded
    fi

    if [[ "${REPLACEMENT_PHASE}" == "prepare" ]]; then
      if persist_root_record replacement-prepared ""; then
        ROOT_NEW_TRANSACTION_COMMITTED=1
      elif validate_root_replacement_prepared_record; then
        ROOT_NEW_TRANSACTION_COMMITTED=1
        root_fail "The durable replacement ledger committed, but its generic operator-evidence mirror did not; preserve the transaction for an authorized retry."
      else
        root_fail "The root-owned replacement prepare ledger could not be durably committed."
      fi
    else
      persist_root_record completed ""
    fi
    ROOT_COMPLETED=1
  )
}

build_root_program() {
  /usr/bin/printf '%s\n' 'set -euo pipefail'
  builtin declare -f ensure_privileged_authority_directory
  builtin declare -f ensure_privileged_execution_directory
  builtin declare -f process_start_identity
  builtin declare -f replacement_lock_flag
  builtin declare -f path_has_replacement_lock
  builtin declare -f replacement_tree_is_locked
  builtin declare -f replacement_tree_flag_state
  builtin declare -f force_lock_replacement_tree
  builtin declare -f force_unlock_replacement_tree
  builtin declare -f lock_replacement_tree
  builtin declare -f unlock_replacement_tree
  builtin declare -f bind_replacement_public_candidate_snapshot
  builtin declare -f stage_replacement_candidate_snapshot
  builtin declare -f bind_replacement_public_previous_snapshot
  builtin declare -f snapshot_prior_replacement_record
  builtin declare -f remove_replacement_ledger_durably
  builtin declare -f remove_replacement_transaction_durably
  builtin declare -f release_prior_replacement_lock_after_quiesce
  builtin declare -f capture_bundle_binding
  builtin declare -f validate_bound_replacement_record
  builtin declare -f validate_root_replacement_prepared_record
  builtin declare -f persist_root_record
  builtin declare -f record_root_phase
  builtin declare -f root_fail
  builtin declare -f validate_root_authority
  builtin declare -f remove_validated_authority
  builtin declare -f remove_claimed_authority
  builtin declare -f validate_offline_report
  builtin declare -f is_service_disabled
  builtin declare -f disable_and_confirm_service
  builtin declare -f enable_and_confirm_service
  builtin declare -f stop_and_confirm_offline
  builtin declare -f stage_trusted_helper
  builtin declare -f stage_verified_legacy_v132_daemon
  builtin declare -f root_worker
  local variable
  for variable in TEST_ROOT APP_PATH OPERATION REPLACEMENT_PHASE REPLACEMENT_DESTINATION REPLACEMENT_TRANSACTION_ID REPLACEMENT_CANDIDATE_APP REPLACEMENT_PREVIOUS_APP REPLACEMENT_RESULT REPLACEMENT_CANDIDATE_SNAPSHOT_APP REPLACEMENT_CANDIDATE_BINDING REPLACEMENT_PREVIOUS_BINDING REPLACEMENT_LOCKED_BINDING REPLACEMENT_LIFECYCLE_SOURCE REPLACEMENT_LIFECYCLE_EXPECTED_SHA256 REPLACEMENT_PUBLIC_CONTENT_MANIFEST_SHA256 REPLACEMENT_PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256 REPLACEMENT_PUBLIC_VERSION REPLACEMENT_PUBLIC_BUILD REPLACEMENT_PUBLIC_TEAM_ID REPLACEMENT_PUBLIC_ARCHIVE_SHA256 REPLACEMENT_PUBLIC_CANDIDATE_EXPECTATION REPLACEMENT_LIFECYCLE_STAGED_PATH REPLACEMENT_LIFECYCLE_STAGED_SHA256 REPLACEMENT_TRANSACTION_ROOT REPLACEMENT_TRANSACTION_DIR LAUNCHCTL PRIVILEGED_HELPER LEGACY_PLIST STDOUT_LOG STDERR_LOG SERVICE_LABEL MAINTENANCE_DIR EXECUTION_DIR AUTHORITY_PATH CLAIMED_AUTHORITY_PATH ROOT_EXECUTION_RECORD ROOT_REPLACEMENT_RECORD ROOT_SCRATCH_PARENT EXPECTED_OWNER_UID REQUESTING_USER_UID REQUESTING_PROCESS_ID REQUESTING_PROCESS_START_ID FIXTURE_PARENT_START_SOURCE EXPECTED_BOOT_SESSION_ID HELPER_SNAPSHOT HELPER_SNAPSHOT_SHA256 RELEASE_TEAM_ID HELPER_SIGNING_ID DAEMON_SIGNING_ID V132_DAEMON_SHA256 V132_DAEMON_CDHASH V132_FIXTURE_DAEMON_SHA256 ROOT_AUTHORITY_EXPECTATION ROOT_FIXTURE_SIGNAL ROOT_FIXTURE_RETURN_INCOMPLETE ROOT_FIXTURE_SWAP_CANDIDATE_AFTER_SNAPSHOT ROOT_FIXTURE_SWAP_CANDIDATE_DURING_SNAPSHOT ROOT_FIXTURE_PARTIAL_LOCK ROOT_FIXTURE_PARTIAL_UNLOCK; do
    builtin printf '%s=%q\n' "${variable}" "${!variable}"
  done
  if [[ -n "${TEST_ROOT}" ]]; then
    builtin printf 'export VIFTY_LIFECYCLE_TEST_ROOT=%q\n' "${TEST_ROOT}"
    builtin printf 'export VIFTY_FIXTURE_INVOCATION_LOG=%q\n' "${FIXTURE_INVOCATION_LOG}"
    builtin printf 'export VIFTY_FIXTURE_BOOTOUT_FAIL=%q\n' "${VIFTY_FIXTURE_BOOTOUT_FAIL:-0}"
    builtin printf 'export VIFTY_FIXTURE_STILL_LOADED=%q\n' "${VIFTY_FIXTURE_STILL_LOADED:-0}"
    builtin printf 'export VIFTY_FIXTURE_LEGACY_UNSAFE=%q\n' "${VIFTY_FIXTURE_LEGACY_UNSAFE:-0}"
    builtin printf 'export VIFTY_FIXTURE_ONE_FAN=%q\n' "${VIFTY_FIXTURE_ONE_FAN:-0}"
    builtin printf 'export VIFTY_FIXTURE_DECOY_DISABLED=%q\n' "${VIFTY_FIXTURE_DECOY_DISABLED:-0}"
  fi
  /usr/bin/printf '%s\n' 'root_worker'
}

validate_replacement_bundle_identity() {
  [[ -d "${APP_PATH}" && ! -L "${APP_PATH}" && "${APP_PATH}" == "${REPLACEMENT_DESTINATION}" ]] || return 1
  local executable
  for executable in Vifty viftyctl ViftyDaemon ViftyHelper; do
    [[ -f "${APP_PATH}/Contents/MacOS/${executable}" &&
       -x "${APP_PATH}/Contents/MacOS/${executable}" &&
       ! -L "${APP_PATH}/Contents/MacOS/${executable}" ]] || return 1
  done
  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "${APP_PATH}/Contents/Info.plist" 2>/dev/null)" == "tech.reidar.vifty" ]] || return 1
  if [[ -z "${TEST_ROOT}" ]]; then
    /usr/bin/codesign --verify --deep --strict "${APP_PATH}" >/dev/null 2>&1 || return 1
    local details
    details="$(/usr/bin/codesign -dv --verbose=4 "${APP_PATH}/Contents/MacOS/Vifty" 2>&1)" || return 1
    /usr/bin/grep -Fqx "Identifier=tech.reidar.vifty" <<<"${details}" || return 1
  fi
}

validate_bound_replacement_record() {
  local expected_status="$1"
  local record_path="${2:-${ROOT_EXECUTION_RECORD}}"
  local record_mode="${3:-0644}"
  local current_start_id current_binding lifecycle_sha
  current_start_id="$(process_start_identity "${REQUESTING_PROCESS_ID}" "${REQUESTING_USER_UID}")" || return 75
  [[ "${current_start_id}" == "${REQUESTING_PROCESS_START_ID}" ]] || return 75
  current_binding="$(capture_bundle_binding "${REPLACEMENT_DESTINATION}")" || return 75
  [[ -f "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" && -x "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" &&
     ! -L "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" ]] || return 75
  replacement_tree_is_locked "${REPLACEMENT_TRANSACTION_DIR}" || return 75
  lifecycle_sha="$(/usr/bin/shasum -a 256 "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" | /usr/bin/awk '{print $1}')" || return 75
  [[ "${lifecycle_sha}" =~ ^[a-f0-9]{64}$ ]] || return 75
  /usr/bin/ruby -rjson -rdigest -e '
    path, record_mode_text, dir, owner_text, requesting_uid_text, requesting_pid_text, requesting_start_id,
      replacement_path, transaction_id, replacement_result, expected_status, current_binding_json,
      lifecycle_path, lifecycle_sha, test_root, release_team = ARGV
    owner = Integer(owner_text, 10); record_mode = Integer(record_mode_text, 8)
    requesting_uid = Integer(requesting_uid_text, 10); requesting_pid = Integer(requesting_pid_text, 10)
    dst = File.lstat(dir); pst = File.lstat(path); app = File.lstat(replacement_path)
    exit 75 unless dst.directory? && !dst.symlink? && dst.uid == owner && (dst.mode & 0777) == 0755 &&
      pst.file? && !pst.symlink? && pst.uid == owner && pst.nlink == 1 && (pst.mode & 0777) == record_mode && pst.size.between?(1, 4_194_304) &&
      app.directory? && !app.symlink?
    expected_components = {
      "Vifty" => "tech.reidar.vifty",
      "viftyctl" => "tech.reidar.vifty.ctl",
      "ViftyDaemon" => "tech.reidar.vifty.daemon",
      "ViftyHelper" => "tech.reidar.vifty.helper"
    }
    valid_binding = lambda do |binding|
      next false unless binding.is_a?(Hash) && binding["sourcePath"].is_a?(String) && binding["sourcePath"].start_with?("/") &&
        File.basename(binding["sourcePath"]) == "Vifty.app" && binding["manifestSHA256"].is_a?(String) &&
        binding["manifestSHA256"].match?(/\A[a-f0-9]{64}\z/)
      manifest = binding["manifest"]
      next false unless manifest.is_a?(Array) && !manifest.empty? &&
        manifest.count { |row| row.is_a?(Hash) && row["path"] == "." && row["type"] == "directory" } == 1 &&
        manifest.map { |row| row.is_a?(Hash) ? row["path"] : nil }.uniq.length == manifest.length &&
        Digest::SHA256.hexdigest(JSON.generate(manifest)) == binding["manifestSHA256"]
      content_manifest = manifest.map do |row|
        next false unless row.is_a?(Hash)
        row.reject do |key, _|
          ["uid", "gid", "nlink"].include?(key) || (row["type"] == "symlink" && key == "size")
        end
      end
      next false if content_manifest.include?(false)
      next false unless binding["contentManifestSHA256"].is_a?(String) &&
        binding["contentManifestSHA256"].match?(/\A[a-f0-9]{64}\z/) &&
        Digest::SHA256.hexdigest(JSON.generate(content_manifest)) == binding["contentManifestSHA256"]
      manifest_valid = manifest.all? do |row|
        next false unless row.is_a?(Hash) && row["path"].is_a?(String) && !row["path"].empty? &&
          !row["path"].start_with?("/") && !row["path"].match?(/[\x00-\x1f]/) &&
          (row["path"] == "." || !row["path"].split("/").include?("..")) &&
          row["uid"].is_a?(Integer) && row["uid"] >= 0 && row["gid"].is_a?(Integer) && row["gid"] >= 0 &&
          row["mode"].is_a?(Integer) && row["mode"].between?(0, 4095) &&
          row["nlink"].is_a?(Integer) && row["nlink"] >= 1
        common = %w[path type uid gid mode nlink]
        case row["type"]
        when "directory"
          row.keys.sort == common.sort
        when "file"
          row.keys.sort == (common + %w[size sha256]).sort && row["size"].is_a?(Integer) && row["size"] >= 0 &&
            row["sha256"].is_a?(String) && row["sha256"].match?(/\A[a-f0-9]{64}\z/)
        when "symlink"
          row.keys.sort == (common + %w[size linkTarget]).sort && row["size"].is_a?(Integer) && row["size"] >= 0 &&
            row["linkTarget"].is_a?(String) && !row["linkTarget"].start_with?("/")
        else
          false
        end
      end
      next false unless manifest_valid
      identity = binding["identity"]
      next false unless identity.is_a?(Hash) && ["developer-id", "adhoc"].include?(identity["kind"]) &&
        identity["ownerUID"].is_a?(Integer) && identity["ownerUID"] >= 0 &&
        (identity["bundleVersion"].nil? || (identity["bundleVersion"].is_a?(String) &&
          identity["bundleVersion"].match?(/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/))) &&
        (identity["bundleBuild"].nil? || (identity["bundleBuild"].is_a?(String) &&
          identity["bundleBuild"].match?(/\A[1-9][0-9]*\z/))) &&
        identity["componentIdentifiers"] == expected_components && identity["componentSHA256"].is_a?(Hash) &&
        identity["componentSHA256"].keys.sort == expected_components.keys.sort &&
        identity["componentSHA256"].values.all? { |digest| digest.is_a?(String) && digest.match?(/\A[a-f0-9]{64}\z/) }
      if identity["kind"] == "developer-id"
        next false unless identity["teamID"].is_a?(String) && identity["teamID"].match?(/\A[A-Z0-9]{10}\z/)
      else
        next false unless identity["teamID"].nil?
      end
      true
    end
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      opened = file.stat
      exit 75 unless opened.dev == pst.dev && opened.ino == pst.ino && opened.size == pst.size
      record = JSON.parse(file.read(4_194_305)); phases = record["phases"]
      candidate = record["replacementCandidateBinding"]; previous = record["replacementPreviousBinding"]
      current = JSON.parse(current_binding_json)
      expected = replacement_result == "installed" ? candidate : previous
      public_expectation = record["replacementPublicCandidateExpectation"]
      public_expectation_valid = if public_expectation.nil?
        true
      else
        required_public_keys = %w[contentManifestSHA256 previousContentManifestSHA256 version build teamID]
        optional_public_keys = %w[reportedArchiveSHA256]
        identity = candidate.is_a?(Hash) ? candidate["identity"] : nil
        keys_valid = (public_expectation.keys - required_public_keys - optional_public_keys).empty? &&
          required_public_keys.all? { |key| public_expectation.key?(key) }
        values_valid = public_expectation["contentManifestSHA256"].is_a?(String) &&
          public_expectation["contentManifestSHA256"].match?(/\A[a-f0-9]{64}\z/) &&
          public_expectation["previousContentManifestSHA256"].is_a?(String) &&
          public_expectation["previousContentManifestSHA256"].match?(/\A[a-f0-9]{64}\z/) &&
          public_expectation["version"].is_a?(String) &&
          public_expectation["version"].match?(/\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\z/) &&
          public_expectation["build"].is_a?(String) && public_expectation["build"].match?(/\A[1-9][0-9]*\z/) &&
          public_expectation["teamID"] == release_team &&
          (!public_expectation.key?("reportedArchiveSHA256") ||
            (public_expectation["reportedArchiveSHA256"].is_a?(String) &&
             public_expectation["reportedArchiveSHA256"].match?(/\A[a-f0-9]{64}\z/)))
        candidate_valid = candidate.is_a?(Hash) && identity.is_a?(Hash) &&
          candidate["contentManifestSHA256"] == public_expectation["contentManifestSHA256"] &&
          previous.is_a?(Hash) &&
          previous["contentManifestSHA256"] == public_expectation["previousContentManifestSHA256"] &&
          identity["bundleVersion"] == public_expectation["version"] &&
          identity["bundleBuild"] == public_expectation["build"]
        signing_valid = if test_root.empty?
          identity.is_a?(Hash) && identity["kind"] == "developer-id" &&
            identity["teamID"] == public_expectation["teamID"]
        else
          identity.is_a?(Hash) && identity["kind"] == "adhoc" && identity["teamID"].nil?
        end
        keys_valid && values_valid && candidate_valid && signing_valid
      end
      succeeded = phases.is_a?(Array) ? phases.select { |phase| phase["attempted"] == true && phase["succeeded"] == true }.map { |phase| phase["phase"] } : []
      required = ["verify-privileged-authority", "disable-service-and-confirm-offline", "post-freeze-offline-auto-confirm", "remove-legacy-helper-plist-and-logs"]
      if expected_status == "completed"
        required += ["register-smappservice-and-verify", "reenable-service-after-cleanup"]
      end
      required << "lock-replacement-bundle-and-verify" if ["replacement-locked", "completed"].include?(expected_status)
      status_result_valid = expected_status == "replacement-prepared" ? record["replacementResult"].nil? : record["replacementResult"] == replacement_result
      exit 75 unless record["schemaVersion"] == 1 &&
        record["schemaID"] == "https://vifty.app/schemas/helper-maintenance-execution-v1.json" &&
        record["operation"] == "repair" && record["status"] == expected_status && record["blocker"] == "" && status_result_valid &&
        ["daemon-receipt", "offline-auto"].include?(record["authorityMode"]) &&
        record["requestingUserID"] == requesting_uid && record["requestingProcessID"] == requesting_pid &&
        record["requestingProcessStartID"] == requesting_start_id && record["replacementTransactionID"] == transaction_id &&
        record["replacementAppPath"] == replacement_path && record["updatedAt"].is_a?(Numeric) &&
        (Time.now.to_f - record["updatedAt"]).between?(-5, 300) && required.all? { |phase| succeeded.include?(phase) } &&
        (expected_status == "completed" || !succeeded.include?("reenable-service-after-cleanup")) &&
        public_expectation_valid &&
        valid_binding.call(candidate) && valid_binding.call(previous) && valid_binding.call(current) &&
        candidate["sourcePath"] == File.join(File.dirname(lifecycle_path), "CandidateSnapshot", "Vifty.app") &&
        previous["sourcePath"] == replacement_path && current["sourcePath"] == replacement_path &&
        current["manifest"] == expected["manifest"] && current["manifestSHA256"] == expected["manifestSHA256"] &&
        current["contentManifestSHA256"] == expected["contentManifestSHA256"] && current["identity"] == expected["identity"] &&
        record["replacementLifecyclePath"] == lifecycle_path && record["replacementLifecycleSHA256"] == lifecycle_sha &&
        record["replacementFlagTransition"].nil? &&
        (expected_status == "replacement-prepared" ? record["replacementLockedBinding"].nil? : record["replacementLockedBinding"] == current)
      final = file.stat
      exit 75 unless final.dev == opened.dev && final.ino == opened.ino && final.size == opened.size
    end
  ' "${record_path}" "${record_mode}" "${EXECUTION_DIR}" "${EXPECTED_OWNER_UID}" "${REQUESTING_USER_UID}" "${REQUESTING_PROCESS_ID}" "${REQUESTING_PROCESS_START_ID}" "${REPLACEMENT_DESTINATION}" "${REPLACEMENT_TRANSACTION_ID}" "${REPLACEMENT_RESULT}" "${expected_status}" "${current_binding}" "${REPLACEMENT_LIFECYCLE_STAGED_PATH}" "${lifecycle_sha}" "${TEST_ROOT}" "${RELEASE_TEAM_ID}"
}

validate_replacement_prepared_record() {
  validate_bound_replacement_record replacement-prepared
}

validate_replacement_completed_record() {
  validate_bound_replacement_record completed
}

validate_replacement_locked_record() {
  replacement_tree_is_locked "${REPLACEMENT_DESTINATION}" || return 75
  validate_bound_replacement_record replacement-locked
}

validate_root_replacement_prepared_record() {
  validate_bound_replacement_record replacement-prepared "${ROOT_REPLACEMENT_RECORD}" 0600
}

validate_root_replacement_completed_record() {
  validate_bound_replacement_record completed "${ROOT_REPLACEMENT_RECORD}" 0600
}

validate_root_replacement_locked_record() {
  replacement_tree_is_locked "${REPLACEMENT_DESTINATION}" || return 75
  validate_bound_replacement_record replacement-locked "${ROOT_REPLACEMENT_RECORD}" 0600
}

validate_replacement_prepare_source_record() {
  # The caller-owned source is intentionally no longer consulted after the
  # privileged bootstrap. The durable ledger binds the independently verified
  # root snapshot and its lifecycle copy, and all later phases use only those.
  validate_replacement_prepared_record
}

sync_generic_replacement_record() {
  /usr/bin/ruby -e '
    source, destination, owner_text = ARGV; owner = Integer(owner_text, 10)
    st = File.lstat(source)
    exit 75 unless st.file? && !st.symlink? && st.uid == owner && st.nlink == 1 &&
      (st.mode & 0777) == 0600 && st.size.between?(1, 4_194_304)
    data = nil
    File.open(source, File::RDONLY | File::NOFOLLOW) do |file|
      opened = file.stat; data = file.read(4_194_305); final = file.stat
      exit 75 unless opened.dev == st.dev && opened.ino == st.ino && final.dev == opened.dev &&
        final.ino == opened.ino && final.size == opened.size && data.bytesize == opened.size
    end
    dir = File.dirname(destination); tmp = File.join(dir, ".#{File.basename(destination)}.#{Process.pid}.tmp")
    File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0644) do |file|
      file.write(data); file.flush; file.fsync
    end
    File.chown(owner, -1, tmp) unless File.lstat(tmp).uid == owner
    File.chmod(0644, tmp); File.rename(tmp, destination)
    File.open(dir, File::RDONLY) { |directory| directory.fsync }
  ' "${ROOT_REPLACEMENT_RECORD}" "${ROOT_EXECUTION_RECORD}" "${EXPECTED_OWNER_UID}"
}

mutate_replacement_record() {
  local action="$1"
  local locked_binding_json="${2:-}"
  local fixture_failure=""
  if [[ -n "${TEST_ROOT}" ]]; then
    fixture_failure="${ROOT_FIXTURE_RECORD_POST_RENAME_FAILURE:-}"
  fi
  /usr/bin/ruby -rjson -e '
    path, owner_text, action, replacement_result, locked_binding_json, fixture_failure = ARGV
    owner = Integer(owner_text, 10); st = File.lstat(path)
    exit 75 unless st.file? && !st.symlink? && st.uid == owner && st.nlink == 1 &&
      (st.mode & 0777) == 0600 && st.size.between?(1, 4_194_304)
    record = JSON.parse(File.read(path)); phases = record.fetch("phases")
    lock_phase = phases.find { |phase| phase["phase"] == "lock-replacement-bundle-and-verify" }
    unless lock_phase
      lock_phase = {"phase" => "lock-replacement-bundle-and-verify", "attempted" => false, "succeeded" => false}
      phases << lock_phase
    end
    case action
    when "locking"
      exit 75 unless record["status"] == "replacement-prepared" && record["replacementResult"].nil?
      lock_phase["attempted"] = true
      record["replacementFlagTransition"] = {"operation" => "locking", "targetState" => "locked", "startedAt" => Time.now.to_f}
    when "unlocking"
      exit 75 unless record["status"] == "replacement-locked" && record["replacementResult"] == "installed"
      record["replacementFlagTransition"] = {"operation" => "unlocking", "targetState" => "unlocked", "startedAt" => Time.now.to_f}
    when "locked"
      exit 75 unless ["replacement-prepared", "replacement-locked"].include?(record["status"]) &&
        ["installed", "rolled-back"].include?(replacement_result)
      binding = JSON.parse(locked_binding_json)
      expected = replacement_result == "installed" ? record["replacementCandidateBinding"] : record["replacementPreviousBinding"]
      exit 75 unless binding.is_a?(Hash) && expected.is_a?(Hash) &&
        binding["sourcePath"] == record["replacementAppPath"] &&
        binding["manifest"] == expected["manifest"] && binding["manifestSHA256"] == expected["manifestSHA256"] &&
        binding["identity"] == expected["identity"]
      lock_phase["attempted"] = true; lock_phase["succeeded"] = true
      record["status"] = "replacement-locked"; record["replacementResult"] = replacement_result
      record["replacementLockedBinding"] = binding; record.delete("replacementFlagTransition")
    when "unlocked"
      exit 75 unless ["replacement-prepared", "replacement-locked"].include?(record["status"])
      record["status"] = "replacement-prepared"
      record.delete("replacementResult"); record.delete("replacementLockedBinding"); record.delete("replacementFlagTransition")
    when "completed"
      exit 75 unless record["status"] == "replacement-locked" && record["replacementResult"] == replacement_result
      ["register-smappservice-and-verify", "reenable-service-after-cleanup"].each do |name|
        row = phases.find { |phase| phase["phase"] == name }
        unless row
          row = {"phase" => name, "attempted" => false, "succeeded" => false}; phases << row
        end
        row["attempted"] = true; row["succeeded"] = true
      end
      record["status"] = "completed"; record.delete("replacementFlagTransition")
    else
      exit 64
    end
    record["blocker"] = ""; record["updatedAt"] = Time.now.to_f
    dir = File.dirname(path); tmp = File.join(dir, ".#{File.basename(path)}.#{Process.pid}.tmp")
    File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0600) do |file|
      file.write(JSON.generate(record)); file.write("\n"); file.flush; file.fsync
    end
    File.chown(owner, -1, tmp) unless File.lstat(tmp).uid == owner
    File.chmod(0600, tmp); File.rename(tmp, path)
    exit 74 if !fixture_failure.empty? && fixture_failure == action
    File.open(dir, File::RDONLY) { |directory| directory.fsync }
  ' "${ROOT_REPLACEMENT_RECORD}" "${EXPECTED_OWNER_UID}" "${action}" "${REPLACEMENT_RESULT}" "${locked_binding_json}" "${fixture_failure}"
}

persist_replacement_flag_transition() {
  local operation="$1"
  case "${operation}" in locking|unlocking) ;; *) return 64 ;; esac
  mutate_replacement_record "${operation}" || return 1
  sync_generic_replacement_record
}

persist_replacement_completed_record() {
  validate_root_replacement_locked_record || return 1
  mutate_replacement_record completed || return 1
  sync_generic_replacement_record
}

persist_replacement_locked_record() {
  REPLACEMENT_LOCKED_BINDING="$(capture_bundle_binding "${REPLACEMENT_DESTINATION}")" || return 1
  mutate_replacement_record locked "${REPLACEMENT_LOCKED_BINDING}" || return 1
  sync_generic_replacement_record
}

persist_replacement_released_record() {
  mutate_replacement_record unlocked || return 1
  sync_generic_replacement_record
}

reconcile_replacement_flag_state() {
  local desired="$1" actual
  actual="$(replacement_tree_flag_state "${REPLACEMENT_DESTINATION}")" || return 76
  case "${desired}:${actual}" in
    locked:locked)
      persist_replacement_locked_record
      ;;
    unlocked:unlocked)
      persist_replacement_released_record
      ;;
    locked:*)
      if force_unlock_replacement_tree "${REPLACEMENT_DESTINATION}" &&
         persist_replacement_released_record; then
        return 75
      fi
      if force_lock_replacement_tree "${REPLACEMENT_DESTINATION}" &&
         persist_replacement_locked_record; then
        return 75
      fi
      return 76
      ;;
    unlocked:*)
      if force_lock_replacement_tree "${REPLACEMENT_DESTINATION}" &&
         persist_replacement_locked_record; then
        return 75
      fi
      if force_unlock_replacement_tree "${REPLACEMENT_DESTINATION}" &&
         persist_replacement_released_record; then
        return 75
      fi
      return 76
      ;;
    *) return 64 ;;
  esac
}

replacement_release_lock_root_worker() {
  set -euo pipefail
  if [[ -z "${TEST_ROOT}" && "$(/usr/bin/id -u)" -ne 0 ]]; then
    echo "helper-lifecycle: replacement lock release requires administrator authorization." >&2
    exit 77
  fi
  replacement_authority_is_proven_disabled_offline || exit 76
  validate_root_replacement_locked_record || exit 75
  if ! persist_replacement_flag_transition unlocking; then
    reconcile_replacement_flag_state unlocked >/dev/null 2>&1 || true
    exit 75
  fi
  if ! unlock_replacement_tree "${REPLACEMENT_DESTINATION}"; then
    reconcile_replacement_flag_state unlocked >/dev/null 2>&1 || true
    exit 75
  fi
  if [[ -n "${TEST_ROOT}" && "${ROOT_FIXTURE_EXIT_AFTER_UNLOCK}" == "1" ]]; then
    echo "helper-lifecycle: fixture exited after immutable unlock and before durable released evidence." >&2
    exit 75
  fi
  if ! persist_replacement_released_record; then
    reconcile_replacement_flag_state unlocked || exit $?
  fi
  validate_root_replacement_prepared_record || exit 75
}

build_replacement_release_lock_root_program() {
  /usr/bin/printf '%s\n' 'set -euo pipefail'
  builtin declare -f process_start_identity
  builtin declare -f replacement_lock_flag
  builtin declare -f path_has_replacement_lock
  builtin declare -f replacement_tree_is_locked
  builtin declare -f replacement_tree_flag_state
  builtin declare -f force_lock_replacement_tree
  builtin declare -f force_unlock_replacement_tree
  builtin declare -f lock_replacement_tree
  builtin declare -f unlock_replacement_tree
  builtin declare -f capture_bundle_binding
  builtin declare -f validate_bound_replacement_record
  builtin declare -f validate_replacement_prepared_record
  builtin declare -f validate_replacement_locked_record
  builtin declare -f validate_root_replacement_prepared_record
  builtin declare -f validate_root_replacement_locked_record
  builtin declare -f sync_generic_replacement_record
  builtin declare -f mutate_replacement_record
  builtin declare -f persist_replacement_flag_transition
  builtin declare -f persist_replacement_locked_record
  builtin declare -f persist_replacement_released_record
  builtin declare -f reconcile_replacement_flag_state
  builtin declare -f is_service_disabled
  builtin declare -f replacement_authority_is_proven_disabled_offline
  builtin declare -f replacement_release_lock_root_worker
  local variable
  for variable in TEST_ROOT LAUNCHCTL SERVICE_LABEL EXECUTION_DIR ROOT_EXECUTION_RECORD ROOT_REPLACEMENT_RECORD EXPECTED_OWNER_UID REQUESTING_USER_UID REQUESTING_PROCESS_ID REQUESTING_PROCESS_START_ID FIXTURE_PARENT_START_SOURCE REPLACEMENT_DESTINATION REPLACEMENT_TRANSACTION_ID REPLACEMENT_RESULT REPLACEMENT_TRANSACTION_ROOT REPLACEMENT_TRANSACTION_DIR REPLACEMENT_LIFECYCLE_STAGED_PATH RELEASE_TEAM_ID ROOT_FIXTURE_PARTIAL_LOCK ROOT_FIXTURE_PARTIAL_UNLOCK ROOT_FIXTURE_EXIT_AFTER_UNLOCK ROOT_FIXTURE_RECORD_POST_RENAME_FAILURE; do
    builtin printf '%s=%q\n' "${variable}" "${!variable}"
  done
  if [[ -n "${TEST_ROOT}" ]]; then
    builtin printf 'export VIFTY_LIFECYCLE_TEST_ROOT=%q\n' "${TEST_ROOT}"
    builtin printf 'export VIFTY_FIXTURE_INVOCATION_LOG=%q\n' "${FIXTURE_INVOCATION_LOG}"
  fi
  /usr/bin/printf '%s\n' 'replacement_release_lock_root_worker'
}

replacement_lock_root_worker() {
  set -euo pipefail
  if [[ -z "${TEST_ROOT}" && "$(/usr/bin/id -u)" -ne 0 ]]; then
    echo "helper-lifecycle: replacement lock requires administrator authorization." >&2
    exit 77
  fi
  replacement_authority_is_proven_disabled_offline || {
    echo "helper-lifecycle: replacement authority was not frozen before bundle lock." >&2
    exit 76
  }
  validate_root_replacement_prepared_record || {
    echo "helper-lifecycle: prepared replacement binding failed before bundle lock." >&2
    exit 75
  }
  if ! persist_replacement_flag_transition locking; then
    reconcile_replacement_flag_state locked >/dev/null 2>&1 || true
    echo "helper-lifecycle: immutable-lock transition could not be durably journaled; actual flags were reconciled." >&2
    exit 75
  fi
  if ! lock_replacement_tree "${REPLACEMENT_DESTINATION}"; then
    reconcile_replacement_flag_state locked >/dev/null 2>&1 || true
    echo "helper-lifecycle: system-immutable replacement bundle lock is unavailable or incomplete." >&2
    exit 75
  fi
  if [[ -n "${TEST_ROOT}" && "${ROOT_FIXTURE_EXIT_AFTER_LOCK}" == "1" ]]; then
    echo "helper-lifecycle: fixture exited after immutable lock and before durable locked evidence." >&2
    exit 75
  fi
  if [[ -n "${TEST_ROOT}" && "${ROOT_FIXTURE_LOCK_RECORD_FAILURE}" == "1" ]]; then
    force_unlock_replacement_tree "${REPLACEMENT_DESTINATION}" >/dev/null 2>&1 || true
    persist_replacement_released_record >/dev/null 2>&1 || true
    echo "helper-lifecycle: fixture interrupted after immutable lock and before durable lock evidence." >&2
    exit 75
  fi
  if ! persist_replacement_locked_record; then
    reconcile_replacement_flag_state locked || exit $?
  fi
  validate_root_replacement_locked_record
}

build_replacement_lock_root_program() {
  /usr/bin/printf '%s\n' 'set -euo pipefail'
  builtin declare -f process_start_identity
  builtin declare -f replacement_lock_flag
  builtin declare -f path_has_replacement_lock
  builtin declare -f replacement_tree_is_locked
  builtin declare -f replacement_tree_flag_state
  builtin declare -f force_lock_replacement_tree
  builtin declare -f force_unlock_replacement_tree
  builtin declare -f lock_replacement_tree
  builtin declare -f unlock_replacement_tree
  builtin declare -f capture_bundle_binding
  builtin declare -f validate_bound_replacement_record
  builtin declare -f validate_replacement_prepared_record
  builtin declare -f validate_replacement_locked_record
  builtin declare -f validate_root_replacement_prepared_record
  builtin declare -f validate_root_replacement_locked_record
  builtin declare -f sync_generic_replacement_record
  builtin declare -f mutate_replacement_record
  builtin declare -f persist_replacement_flag_transition
  builtin declare -f persist_replacement_locked_record
  builtin declare -f persist_replacement_released_record
  builtin declare -f reconcile_replacement_flag_state
  builtin declare -f is_service_disabled
  builtin declare -f replacement_authority_is_proven_disabled_offline
  builtin declare -f replacement_lock_root_worker
  local variable
  for variable in TEST_ROOT LAUNCHCTL SERVICE_LABEL EXECUTION_DIR ROOT_EXECUTION_RECORD ROOT_REPLACEMENT_RECORD EXPECTED_OWNER_UID REQUESTING_USER_UID REQUESTING_PROCESS_ID REQUESTING_PROCESS_START_ID FIXTURE_PARENT_START_SOURCE REPLACEMENT_DESTINATION REPLACEMENT_TRANSACTION_ID REPLACEMENT_RESULT REPLACEMENT_TRANSACTION_ROOT REPLACEMENT_TRANSACTION_DIR REPLACEMENT_LIFECYCLE_STAGED_PATH RELEASE_TEAM_ID ROOT_FIXTURE_LOCK_RECORD_FAILURE ROOT_FIXTURE_PARTIAL_LOCK ROOT_FIXTURE_PARTIAL_UNLOCK ROOT_FIXTURE_EXIT_AFTER_LOCK ROOT_FIXTURE_RECORD_POST_RENAME_FAILURE; do
    builtin printf '%s=%q\n' "${variable}" "${!variable}"
  done
  if [[ -n "${TEST_ROOT}" ]]; then
    builtin printf 'export VIFTY_LIFECYCLE_TEST_ROOT=%q\n' "${TEST_ROOT}"
    builtin printf 'export VIFTY_FIXTURE_INVOCATION_LOG=%q\n' "${FIXTURE_INVOCATION_LOG}"
  fi
  /usr/bin/printf '%s\n' 'replacement_lock_root_worker'
}

replacement_finish_root_worker() {
  set -euo pipefail
  if [[ -z "${TEST_ROOT}" && "$(/usr/bin/id -u)" -ne 0 ]]; then
    echo "helper-lifecycle: replacement finish requires administrator authorization." >&2
    exit 77
  fi
  disable_and_confirm_service || { echo "helper-lifecycle: replacement service could not be refrozen after registration." >&2; exit 76; }
  stop_and_confirm_offline || { echo "helper-lifecycle: replacement helper could not be proven offline after registration." >&2; exit 76; }
  fixture_swap_locked_destination before-enable || { echo "helper-lifecycle: fixture destination substitution failed closed before enable." >&2; exit 75; }
  validate_root_replacement_locked_record || { echo "helper-lifecycle: locked replacement root record validation failed before enable." >&2; exit 75; }
  enable_and_confirm_service || { echo "helper-lifecycle: replacement service label could not be re-enabled." >&2; exit 75; }
  validate_root_replacement_locked_record || {
    disable_and_confirm_service >/dev/null 2>&1 || true
    stop_and_confirm_offline >/dev/null 2>&1 || true
    echo "helper-lifecycle: locked replacement identity changed across enable; authority was refrozen." >&2
    exit 75
  }
  if ! persist_replacement_completed_record; then
    echo "helper-lifecycle: replacement completion evidence could not be persisted; refreezing." >&2
    disable_and_confirm_service >/dev/null 2>&1 || true
    stop_and_confirm_offline >/dev/null 2>&1 || true
    exit 75
  fi
  if [[ -n "${TEST_ROOT}" && "${ROOT_FIXTURE_CORRUPT_COMPLETION}" == "1" ]]; then
    /usr/bin/printf '{}\n' > "${ROOT_REPLACEMENT_RECORD}"
    /usr/bin/printf '{}\n' > "${ROOT_EXECUTION_RECORD}"
  fi
}

build_replacement_finish_root_program() {
  /usr/bin/printf '%s\n' 'set -euo pipefail'
  builtin declare -f process_start_identity
  builtin declare -f replacement_lock_flag
  builtin declare -f path_has_replacement_lock
  builtin declare -f replacement_tree_is_locked
  builtin declare -f replacement_tree_flag_state
  builtin declare -f force_lock_replacement_tree
  builtin declare -f force_unlock_replacement_tree
  builtin declare -f lock_replacement_tree
  builtin declare -f unlock_replacement_tree
  builtin declare -f fixture_swap_locked_destination
  builtin declare -f capture_bundle_binding
  builtin declare -f validate_bound_replacement_record
  builtin declare -f validate_replacement_prepared_record
  builtin declare -f validate_replacement_completed_record
  builtin declare -f validate_replacement_locked_record
  builtin declare -f validate_root_replacement_completed_record
  builtin declare -f validate_root_replacement_locked_record
  builtin declare -f sync_generic_replacement_record
  builtin declare -f mutate_replacement_record
  builtin declare -f persist_replacement_completed_record
  builtin declare -f is_service_disabled
  builtin declare -f disable_and_confirm_service
  builtin declare -f enable_and_confirm_service
  builtin declare -f stop_and_confirm_offline
  builtin declare -f replacement_finish_root_worker
  local variable
  for variable in TEST_ROOT LAUNCHCTL SERVICE_LABEL EXECUTION_DIR ROOT_EXECUTION_RECORD ROOT_REPLACEMENT_RECORD EXPECTED_OWNER_UID REQUESTING_USER_UID REQUESTING_PROCESS_ID REQUESTING_PROCESS_START_ID FIXTURE_PARENT_START_SOURCE REPLACEMENT_DESTINATION REPLACEMENT_TRANSACTION_ID REPLACEMENT_RESULT REPLACEMENT_TRANSACTION_ROOT REPLACEMENT_TRANSACTION_DIR REPLACEMENT_LIFECYCLE_STAGED_PATH RELEASE_TEAM_ID ROOT_FIXTURE_CORRUPT_COMPLETION ROOT_FIXTURE_SWAP_BEFORE_ENABLE ROOT_FIXTURE_ALTERNATE_APP ROOT_FIXTURE_RECORD_POST_RENAME_FAILURE; do
    builtin printf '%s=%q\n' "${variable}" "${!variable}"
  done
  if [[ -n "${TEST_ROOT}" ]]; then
    builtin printf 'export VIFTY_LIFECYCLE_TEST_ROOT=%q\n' "${TEST_ROOT}"
    builtin printf 'export VIFTY_FIXTURE_INVOCATION_LOG=%q\n' "${FIXTURE_INVOCATION_LOG}"
  fi
  /usr/bin/printf '%s\n' 'replacement_finish_root_worker'
}

run_replacement_finish_root_program() {
  local root_program="$1"
  if [[ -n "${TEST_ROOT}" ]]; then
    /usr/bin/env -i HOME="${HOME:-/tmp}" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
      /bin/bash --noprofile --norc -c "${root_program}"
    return
  fi
  local root_digest root_base64 root_stager
  root_digest="$(/usr/bin/printf '%s' "${root_program}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  root_base64="$(/usr/bin/printf '%s' "${root_program}" | /usr/bin/base64 | /usr/bin/tr -d '\n')"
  root_stager='set -euo pipefail
encoded_worker="$1"; expected_digest="$2"
[[ "${expected_digest}" =~ ^[a-f0-9]{64}$ ]] || exit 78
worker_dir="$(/usr/bin/mktemp -d /private/tmp/vifty-replacement-finish.XXXXXX)"
/bin/chmod 700 "${worker_dir}"
trap '\''/bin/rm -rf "${worker_dir}"'\'' EXIT
worker_path="${worker_dir}/worker.sh"
/usr/bin/printf "%s" "${encoded_worker}" | /usr/bin/base64 -D > "${worker_path}"
/bin/chmod 500 "${worker_path}"
actual_digest="$(/usr/bin/shasum -a 256 "${worker_path}" | /usr/bin/awk '\''{print $1}'\'')"
[[ "${actual_digest}" == "${expected_digest}" ]] || exit 78
/usr/bin/env -i HOME=/var/root PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash --noprofile --norc "${worker_path}"'
  /usr/bin/osascript - "${root_stager}" "${root_base64}" "${root_digest}" <<'APPLESCRIPT'
on run argv
  set stagingProgram to item 1 of argv
  set encodedWorker to item 2 of argv
  set expectedDigest to item 3 of argv
  set commandText to "/usr/bin/env -i HOME=/var/root PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash --noprofile --norc -c " & quoted form of stagingProgram & " -- " & quoted form of encodedWorker & " " & quoted form of expectedDigest
  do shell script commandText with administrator privileges
end run
APPLESCRIPT
}

replacement_authority_is_proven_disabled_offline() {
  is_service_disabled && ! "${LAUNCHCTL}" print "system/${SERVICE_LABEL}" >/dev/null 2>&1
}

fail_prepare_or_root() {
  local base_message="$1"
  local failure_exit=75
  if [[ "${REPLACEMENT_PHASE}" == "prepare" ]]; then
    if replacement_authority_is_proven_disabled_offline; then
      BLOCKER="${base_message} The exact helper label is proven disabled and offline."
      failure_exit=75
    else
      BLOCKER="${base_message} The exact helper label is not proven disabled and offline; helper authority is active or unknown."
      failure_exit=76
    fi
  else
    BLOCKER="${base_message}"
  fi
  write_record
  echo "helper-lifecycle: ${BLOCKER}" >&2
  exit "${failure_exit}"
}

fail_replacement_before_register() {
  local disabled_message="$1"
  local unknown_message="$2"
  local finish_exit
  if replacement_authority_is_proven_disabled_offline; then
    BLOCKER="${disabled_message}"
    finish_exit=75
  else
    BLOCKER="${unknown_message}"
    finish_exit=76
  fi
  write_record
  echo "helper-lifecycle: ${BLOCKER}" >&2
  exit "${finish_exit}"
}

if [[ "${REPLACEMENT_PHASE}" == "release-lock" ]]; then
  RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/vifty-lifecycle-release-lock.XXXXXX")"
  /bin/chmod 700 "${RUN_DIR}"
  PHASE_LOG="${RUN_DIR}/phases"
  : > "${PHASE_LOG}"
  if ! validate_replacement_bundle_identity ||
     ! validate_replacement_locked_record ||
     ! replacement_authority_is_proven_disabled_offline; then
    fail_replacement_before_register \
      "The exact locked replacement could not be authenticated for rollback release; helper authority remains disabled and offline." \
      "The replacement lock release failed while helper authority is active or unknown; preserve the destination and do not roll back."
  fi
  ROOT_PROGRAM="$(build_replacement_release_lock_root_program)"
  set +e
  run_replacement_finish_root_program "${ROOT_PROGRAM}"
  ROOT_STATUS=$?
  set -e
  if [[ "${ROOT_STATUS}" -ne 0 ]] || ! validate_replacement_prepared_record; then
    fail_replacement_before_register \
      "The replacement registration lock could not be safely released for exact rollback; helper authority remains disabled and offline." \
      "The replacement lock release failed while helper authority is active or unknown; preserve the destination and do not roll back."
  fi
  STATUS="replacement-prepared"
  BLOCKER=""
  write_record
  echo "helper-lifecycle: exact replacement registration lock released for installer rollback while helper authority remains frozen." >&2
  exit 0
fi

if [[ "${REPLACEMENT_PHASE}" == "finish" ]]; then
  RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/vifty-lifecycle-finish.XXXXXX")"
  /bin/chmod 700 "${RUN_DIR}"
  PHASE_LOG="${RUN_DIR}/phases"
  : > "${PHASE_LOG}"
  if ! validate_replacement_bundle_identity; then
    fail_replacement_before_register \
      "The replacement destination no longer has the exact required Vifty bundle identity; helper authority remains proven disabled and offline." \
      "The replacement destination identity failed while helper authority is active or unknown; preserve the destination and do not roll back."
  fi
  if ! validate_replacement_prepared_record; then
    fail_replacement_before_register \
      "The root-owned replacement prepare record is stale, malformed, replayed, or not bound to this caller and destination; helper authority remains proven disabled and offline." \
      "The root-owned replacement prepare record failed while helper authority is active or unknown; preserve the destination and do not roll back."
  fi
  if ! replacement_authority_is_proven_disabled_offline; then
    fail_replacement_before_register \
      "The helper remains proven disabled and offline, but replacement finish was blocked before registration." \
      "The helper is no longer proven disabled and offline; authority is active or unknown, so the destination must not be rolled back."
  fi
  ROOT_PROGRAM="$(build_replacement_lock_root_program)"
  set +e
  run_replacement_finish_root_program "${ROOT_PROGRAM}"
  ROOT_STATUS=$?
  set -e
  if [[ "${ROOT_STATUS}" -ne 0 ]]; then
    fail_replacement_before_register \
      "The exact replacement bundle could not enter and prove its root-controlled immutable registration lock; helper authority remains disabled and offline." \
      "The replacement registration lock failed while helper authority is active or unknown; preserve the destination and do not roll back."
  fi
  if ! fixture_swap_locked_destination before-register || ! validate_replacement_locked_record; then
    fail_replacement_before_register \
      "The immutable replacement destination changed before registrar execution; helper authority remains disabled and offline." \
      "The replacement destination changed before registrar execution while helper authority is active or unknown; preserve it and do not roll back."
  fi
  SERVICE_PATH="${RUN_DIR}/register.json"
  register_safe=0
  if "${VIFTY_MAIN}" --helper-service-management register --json > "${SERVICE_PATH}" &&
     validate_service_report "${SERVICE_PATH}" register enabled 0; then
    register_safe=1
  fi
  if [[ "${register_safe}" -ne 1 ]]; then
    if is_service_disabled && ! "${LAUNCHCTL}" print "system/${SERVICE_LABEL}" >/dev/null 2>&1; then
      BLOCKER="The verified destination could not register, but the helper remains proven disabled and offline."
      finish_exit=75
    else
      BLOCKER="Replacement registration failed without proving the helper frozen; preserve the verified destination and do not roll it back."
      finish_exit=76
    fi
    write_record
    echo "helper-lifecycle: ${BLOCKER}" >&2
    exit "${finish_exit}"
  fi
  append_phase register-smappservice-and-verify
  ROOT_PROGRAM="$(build_replacement_finish_root_program)"
  set +e
  run_replacement_finish_root_program "${ROOT_PROGRAM}"
  ROOT_STATUS=$?
  set -e
  if [[ "${ROOT_STATUS}" -ne 0 ]]; then
    if is_service_disabled && ! "${LAUNCHCTL}" print "system/${SERVICE_LABEL}" >/dev/null 2>&1; then
      BLOCKER="The service could not be safely re-enabled from the exact root-owned replacement prepare record; the helper remains disabled."
      finish_exit=75
    else
      BLOCKER="Replacement finish could not prove the helper frozen after registration; preserve the verified destination and do not roll it back."
      finish_exit=76
    fi
    write_record
    echo "helper-lifecycle: ${BLOCKER}" >&2
    exit "${finish_exit}"
  fi
  if ! validate_replacement_completed_record; then
    if is_service_disabled && ! "${LAUNCHCTL}" print "system/${SERVICE_LABEL}" >/dev/null 2>&1; then
      BLOCKER="Replacement finish did not produce complete caller- and destination-bound root evidence, but the helper remains proven disabled and offline."
      finish_exit=75
    else
      BLOCKER="Replacement finish evidence failed after enable without proving the helper frozen; preserve the verified destination and do not roll it back."
      finish_exit=76
    fi
    write_record
    echo "helper-lifecycle: ${BLOCKER}" >&2
    exit "${finish_exit}"
  fi
  append_phase reenable-service-after-cleanup
  STATUS="completed"
  BLOCKER=""
  write_record
  echo "helper-lifecycle: replacement finish registered the verified bundle and re-enabled helper authority." >&2
  exit 0
fi

if [[ -n "${MAINTENANCE_REPORT}" ]]; then
  BLOCKER="Caller-supplied maintenance reports cannot authorize live teardown; prepare must run in this invocation."
  PHASE_LOG="/dev/null"
  write_record
  echo "helper-lifecycle: ${BLOCKER}" >&2
  exit 75
fi

RUN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/vifty-lifecycle.XXXXXX")"
/bin/chmod 700 "${RUN_DIR}"
REPORT_PATH="${RUN_DIR}/maintenance-report.json"
PHASE_LOG="${RUN_DIR}/phases"
HELPER_SNAPSHOT="${RUN_DIR}/ViftyHelper.snapshot"
: > "${PHASE_LOG}"

if [[ ! -x "${VIFTY_CTL}" || ! -x "${VIFTY_MAIN}" || ! -x "${VIFTY_HELPER}" || ! -x "${VIFTY_DAEMON}" ]]; then
  fail_prepare_or_root "The installed app is missing viftyctl, Vifty, ViftyHelper, or ViftyDaemon."
fi

/usr/bin/ruby -e '
  source, destination = ARGV
  st = File.lstat(source)
  exit 75 unless st.file? && !st.symlink? && st.nlink == 1 && st.size.between?(1, 134_217_728)
  File.open(source, File::RDONLY | File::NOFOLLOW) do |input|
    opened = input.stat
    exit 75 unless opened.dev == st.dev && opened.ino == st.ino && opened.size == st.size
    File.open(destination, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0500) do |output|
      IO.copy_stream(input, output); output.flush; output.fsync
      final = input.stat
      exit 75 unless final.dev == opened.dev && final.ino == opened.ino && final.size == opened.size && output.stat.size == opened.size
    end
  end
' "${VIFTY_HELPER}" "${HELPER_SNAPSHOT}" || {
  fail_prepare_or_root "The bundled offline helper could not be snapshotted safely before authorization."
}
/bin/chmod 500 "${HELPER_SNAPSHOT}"
HELPER_SNAPSHOT_SHA256="$(/usr/bin/shasum -a 256 "${HELPER_SNAPSHOT}" | /usr/bin/awk '{print $1}')"

append_phase inspect-ownership
/bin/rm -f "${REPORT_PATH}"
set +e
"${VIFTY_CTL}" helper-maintenance-prepare --operation "${OPERATION}" --json > "${REPORT_PATH}"
PREPARE_STATUS=$?
set -e
if [[ "${PREPARE_STATUS}" -eq 0 ]]; then
  /bin/chmod 600 "${REPORT_PATH}"
  if ! validate_prepare_report "${REPORT_PATH}" "${OPERATION}" "${HELPER_SNAPSHOT_SHA256}"; then
    cancel_unconsumed
    fail_prepare_or_root "The daemon maintenance report was incomplete, stale, or unsafe."
  fi
  append_phase quiesce-restore-confirm
  SERVICE_PATH="${RUN_DIR}/unregister.json"
  if ! "${VIFTY_MAIN}" --helper-service-management unregister --operation "${OPERATION}" --report "${REPORT_PATH}" --json > "${SERVICE_PATH}"; then
    cancel_unconsumed
    fail_prepare_or_root "Daemon token consumption or SMAppService unregister was not verified; retry the same operation if a root receipt was already persisted."
  fi
  validate_service_report "${SERVICE_PATH}" unregister notRegistered 1 "${REPORT_PATH}" || {
    fail_prepare_or_root "Combined daemon authorization and SMAppService unregister readback was unsafe."
  }
  TOKEN_CONSUMED=1
  ROOT_AUTHORITY_EXPECTATION="daemon-receipt"
  append_phase consume-single-use-token
  append_phase unregister-smappservice-and-verify
elif [[ "${PREPARE_STATUS}" -eq 75 ]] && validate_protocol_mismatch_report "${REPORT_PATH}" "${OPERATION}"; then
  cancel_unconsumed
  OFFLINE_AUTHORITY_REQUIRED=1
  ROOT_AUTHORITY_EXPECTATION="protocol-mismatch-offline"
elif [[ "${PREPARE_STATUS}" -eq 1 ]] && validate_legacy_unavailable_error "${REPORT_PATH}"; then
  cancel_unconsumed
  OFFLINE_AUTHORITY_REQUIRED=1
  ROOT_AUTHORITY_EXPECTATION="helper-unreachable"
else
  cancel_unconsumed
  fail_prepare_or_root "Helper maintenance prepare failed without an exact protocol-mismatch or published-v1.3.2 compatibility classification. No privileged teardown was started."
fi

if [[ -n "${TEST_ROOT}" && "${VIFTY_FIXTURE_ADMIN_CANCEL:-0}" == "1" ]]; then
  if [[ "${TOKEN_CONSUMED}" -eq 1 ]]; then
    BLOCKER="Fixture administrator authorization was cancelled after daemon authorization; root cleanup did not start and the receipt was preserved for fail-closed retry."
  else
    BLOCKER="Fixture administrator authorization was cancelled before service freeze; helper state was not changed."
  fi
  fail_prepare_or_root "${BLOCKER}"
fi

ROOT_PROGRAM="$(build_root_program)"
if [[ -n "${TEST_ROOT}" ]]; then
  set +e
  /usr/bin/env -i HOME="${HOME:-/tmp}" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /bin/bash --noprofile --norc -c "${ROOT_PROGRAM}"
  ROOT_STATUS=$?
  set -e
  if [[ "${ROOT_STATUS}" -ne 0 ]]; then
    fail_prepare_or_root "Authorized fixture lifecycle cleanup failed; inspect the privileged phase record."
  fi
else
  ROOT_PROGRAM_SHA256="$(/usr/bin/printf '%s' "${ROOT_PROGRAM}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  ROOT_PROGRAM_BASE64="$(/usr/bin/printf '%s' "${ROOT_PROGRAM}" | /usr/bin/base64 | /usr/bin/tr -d '\n')"
  ROOT_STAGER="$(/bin/cat <<'ROOTSTAGER'
set -euo pipefail
encoded_worker="$1"
expected_digest="$2"
[[ "${expected_digest}" =~ ^[a-f0-9]{64}$ ]] || exit 78
worker_dir="$(/usr/bin/mktemp -d /private/tmp/vifty-lifecycle-root.XXXXXX)"
/bin/chmod 700 "${worker_dir}"
stager_cleanup() { /bin/rm -rf "${worker_dir}"; }
trap stager_cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
worker_path="${worker_dir}/worker.sh"
/usr/bin/printf '%s' "${encoded_worker}" | /usr/bin/base64 -D > "${worker_path}"
/bin/chmod 500 "${worker_path}"
actual_digest="$(/usr/bin/shasum -a 256 "${worker_path}" | /usr/bin/awk '{print $1}')"
[[ "${actual_digest}" == "${expected_digest}" ]] || exit 78
/usr/bin/env -i HOME=/var/root PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /bin/bash --noprofile --norc "${worker_path}"
ROOTSTAGER
)"
  if ! /usr/bin/osascript - "${ROOT_STAGER}" "${ROOT_PROGRAM_BASE64}" "${ROOT_PROGRAM_SHA256}" <<'APPLESCRIPT'
on run argv
  set stagingProgram to item 1 of argv
  set encodedWorker to item 2 of argv
  set expectedDigest to item 3 of argv
  set commandText to "/usr/bin/env -i HOME=/var/root PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/bash --noprofile --norc -c " & quoted form of stagingProgram & " -- " & quoted form of encodedWorker & " " & quoted form of expectedDigest
  do shell script commandText with administrator privileges
end run
APPLESCRIPT
  then
    if [[ "${TOKEN_CONSUMED}" -eq 1 ]]; then
      BLOCKER="Administrator authorization or privileged cleanup was cancelled/failed after daemon authorization. The helper remains disabled and fail-closed; retry the same operation before the root receipt expires, or use the reviewed offline recovery fallback afterward."
    else
      BLOCKER="Administrator authorization or privileged offline recovery failed; no legacy files were removed."
    fi
    fail_prepare_or_root "${BLOCKER}"
  fi
fi

if ! validate_completed_root_record ||
   { [[ "${REPLACEMENT_PHASE}" == "prepare" ]] && ! validate_replacement_prepare_source_record; }; then
  fail_prepare_or_root "Privileged lifecycle execution did not produce complete, caller-bound root evidence; no post-root service transition is allowed."
fi

append_phase disable-service-and-confirm-offline
append_phase post-freeze-offline-auto-confirm
append_phase remove-legacy-helper-plist-and-logs
if [[ "${REPLACEMENT_PHASE}" == "prepare" ]]; then
  append_phase preserve-replacement-freeze
  STATUS="replacement-prepared"
  BLOCKER=""
  write_record
  echo "helper-lifecycle: replacement prepare completed with the helper disabled, offline, and Auto/System confirmed." >&2
  exit 0
fi
if [[ "${OFFLINE_AUTHORITY_REQUIRED}" -eq 1 && "${OPERATION}" == "uninstall" ]]; then
  SERVICE_PATH="${RUN_DIR}/legacy-unregister.json"
  if ! "${VIFTY_MAIN}" --helper-service-management unregister-legacy --operation "${OPERATION}" --root-record "${ROOT_EXECUTION_RECORD}" --json > "${SERVICE_PATH}"; then
    BLOCKER="The post-root SMAppService unregister could not verify privileged offline recovery evidence. The service remains disabled."
    write_record
    echo "helper-lifecycle: ${BLOCKER}" >&2
    exit 75
  fi
  validate_legacy_service_report "${SERVICE_PATH}" || {
    BLOCKER="The post-root protocol-v1 unregister transition readback was unsafe."
    write_record
    echo "helper-lifecycle: ${BLOCKER}" >&2
    exit 75
  }
  append_phase unregister-smappservice-and-verify
fi
if [[ "${OPERATION}" == "repair" ]]; then
  append_phase reenable-service-after-cleanup
  SERVICE_PATH="${RUN_DIR}/register.json"
  if ! "${VIFTY_MAIN}" --helper-service-management register --json > "${SERVICE_PATH}"; then
    BLOCKER="SMAppService registration is not enabled; approve it in Login Items and retry. Privileged cleanup evidence was preserved."
    write_record
    echo "helper-lifecycle: ${BLOCKER}" >&2
    exit 75
  fi
  if ! validate_service_report "${SERVICE_PATH}" register enabled 0; then
    BLOCKER="SMAppService registration did not reach verified enabled state."
    write_record
    echo "helper-lifecycle: ${BLOCKER}" >&2
    exit 75
  fi
  append_phase register-smappservice-and-verify
else
  append_phase preserve-agentcontrol-and-fancontrol-recovery-state
fi

STATUS="completed"
BLOCKER=""
write_record
echo "helper-lifecycle: ${OPERATION} completed through privileged receipt/offline authority and verified service state." >&2
exit 0
