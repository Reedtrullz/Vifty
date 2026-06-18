#!/bin/sh
set -eu

usage() {
  cat >&2 <<'USAGE'
Usage:
  guarded-run.sh <workload> <duration> <max-rpm-percent> <reason> -- <command> [args...]

Example:
  guarded-run.sh test 20m 70 "swift test" -- swift test

Environment:
  VIFTYCTL  Path to viftyctl. Defaults to /Applications/Vifty.app/Contents/MacOS/viftyctl.
  VIFTY_GUARDED_RUN_FORCE_RETRY
            Set to 1/true/yes to pass --force to viftyctl run. Defaults to off.
  VIFTY_GUARDED_RUN_ALLOW_UNCOOLED
            Set to 1/true/yes to run the child without Vifty cooling after a
            valid readiness report blocks cooling. Defaults to off.
USAGE
}

preflight_child_command() {
  child_command="$1"

  case "$child_command" in
    */*)
      if [ ! -e "$child_command" ]; then
        echo "guarded-run: child command path does not exist: $child_command" >&2
        exit 127
      fi
      if [ ! -f "$child_command" ] || [ ! -x "$child_command" ]; then
        echo "guarded-run: child command is not executable: $child_command" >&2
        exit 126
      fi
      return
      ;;
  esac

  old_ifs="$IFS"
  IFS=:
  found_child_command=0
  for path_directory in ${PATH:-/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}; do
    if [ -z "$path_directory" ]; then
      continue
    fi
    candidate="$path_directory/$child_command"
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
      found_child_command=1
      break
    fi
  done
  IFS="$old_ifs"

  if [ "$found_child_command" -ne 1 ]; then
    echo "guarded-run: child command was not found on PATH: $child_command" >&2
    exit 127
  fi
}

preflight_duration() {
  duration_value="$1"

  case "$duration_value" in
    *m|*h)
      duration_number="${duration_value%?}"
      ;;
    *[!0123456789]*|"")
      echo "guarded-run: duration must be a positive integer number of seconds, minutes (m), or hours (h): $duration_value" >&2
      exit 64
      ;;
    *)
      duration_number="$duration_value"
      ;;
  esac

  case "$duration_number" in
    ""|*[!0123456789]*)
      echo "guarded-run: duration must be a positive integer number of seconds, minutes (m), or hours (h): $duration_value" >&2
      exit 64
      ;;
  esac

  if ! printf '%s\n' "$duration_number" | /usr/bin/awk '/^[0-9]+$/ { exit !(($0 + 0) > 0) } { exit 1 }'; then
    echo "guarded-run: duration must be greater than zero: $duration_value" >&2
    exit 64
  fi
}

preflight_max_rpm_percent() {
  rpm_percent_value="$1"

  case "$rpm_percent_value" in
    ""|*[!0123456789]*)
      echo "guarded-run: max-rpm-percent must be an integer from 1 through 100: $rpm_percent_value" >&2
      exit 64
      ;;
  esac

  if ! printf '%s\n' "$rpm_percent_value" | /usr/bin/awk '/^[0-9]+$/ { value = $0 + 0; exit !(value >= 1 && value <= 100) } { exit 1 }'; then
    echo "guarded-run: max-rpm-percent must be an integer from 1 through 100: $rpm_percent_value" >&2
    exit 64
  fi
}

print_readiness_recovery_action() {
  case "$1" in
    none|"")
      ;;
    repairHelper)
      echo "guarded-run: Vifty recovery action is repairHelper; open Vifty and use Repair/Reinstall Helper before retrying." >&2
      ;;
    restoreAutoBeforeRetry)
      echo "guarded-run: Vifty recovery action is restoreAutoBeforeRetry; restore Auto or wait before retrying." >&2
      ;;
    backOffWorkload)
      echo "guarded-run: Vifty recovery action is backOffWorkload; pause or reduce the workload instead of requesting cooling." >&2
      ;;
    inspectPolicy)
      echo "guarded-run: Vifty recovery action is inspectPolicy; inspect Vifty policy/status before retrying." >&2
      ;;
    collectHardwareEvidence)
      echo "guarded-run: Vifty recovery action is collectHardwareEvidence; collect read-only validation evidence before retrying." >&2
      ;;
  esac
}

finish_without_cooling_request() {
  message="$1"
  shift

  echo "guarded-run: $message" >&2
  print_readiness_recovery_action "$recommended_recovery_action"
  printf '%s\n' "$diagnose_json" >&2

  if [ "$allow_uncooled" -eq 1 ]; then
    case "$recommended_recovery_action" in
      repairHelper|backOffWorkload|restoreAutoBeforeRetry|inspectPolicy|collectHardwareEvidence)
        echo "guarded-run: VIFTY_GUARDED_RUN_ALLOW_UNCOOLED is set, but recovery action is $recommended_recovery_action; not running workload without cooling." >&2
        exit 75
        ;;
    esac

    if [ "${manual_control_active:-}" = "true" ]; then
      echo "guarded-run: VIFTY_GUARDED_RUN_ALLOW_UNCOOLED is set, but manualControlActive is true; not running workload without cooling." >&2
      exit 75
    fi

    if [ "${daemon_control_path_ready:-}" != "true" ]; then
      echo "guarded-run: VIFTY_GUARDED_RUN_ALLOW_UNCOOLED is set, but daemonControlPathReady is ${daemon_control_path_ready:-unknown}; not running workload without cooling." >&2
      exit 75
    fi

    echo "guarded-run: VIFTY_GUARDED_RUN_ALLOW_UNCOOLED is set; running child without Vifty cooling." >&2
    exec "$@"
  fi

  exit 75
}

is_positive_integer() {
  printf '%s\n' "$1" | /usr/bin/awk '/^[0-9]+$/ { exit !(($0 + 0) > 0) } { exit 1 }'
}

duration_within_maximum() {
  duration_value="$1"
  maximum_seconds="$2"

  case "$duration_value" in
    *m)
      duration_number="${duration_value%?}"
      duration_multiplier=60
      ;;
    *h)
      duration_number="${duration_value%?}"
      duration_multiplier=3600
      ;;
    *)
      duration_number="$duration_value"
      duration_multiplier=1
      ;;
  esac

  /usr/bin/awk -v number="$duration_number" -v multiplier="$duration_multiplier" -v maximum="$maximum_seconds" '
    BEGIN {
      seconds = (number + 0) * (multiplier + 0)
      exit !(seconds >= 1 && seconds <= (maximum + 0))
    }
  '
}

trimmed_character_count() {
  printf '%s' "$1" | /usr/bin/awk '
    {
      value = value (NR == 1 ? "" : "\n") $0
    }
    END {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print length(value)
    }
  '
}

if [ "$#" -lt 6 ]; then
  usage
  exit 64
fi

workload="$1"
duration="$2"
max_rpm_percent="$3"
reason="$4"
shift 4

if [ -z "$reason" ]; then
  echo "guarded-run: reason must not be empty." >&2
  exit 64
fi

reason_without_spaces="$(printf '%s' "$reason" | /usr/bin/tr -d '[:space:]')"
if [ -z "$reason_without_spaces" ]; then
  echo "guarded-run: reason must not be blank." >&2
  exit 64
fi

preflight_duration "$duration"
preflight_max_rpm_percent "$max_rpm_percent"

if [ "${1:-}" != "--" ]; then
  usage
  exit 64
fi
shift

if [ "$#" -eq 0 ]; then
  usage
  exit 64
fi

preflight_child_command "$1"

viftyctl="${VIFTYCTL:-/Applications/Vifty.app/Contents/MacOS/viftyctl}"
force_retry="${VIFTY_GUARDED_RUN_FORCE_RETRY:-0}"
allow_uncooled="${VIFTY_GUARDED_RUN_ALLOW_UNCOOLED:-0}"
expected_capabilities_schema_id="https://vifty.local/schemas/viftyctl-capabilities.schema.json"
expected_diagnose_schema_id="https://vifty.local/schemas/viftyctl-diagnose.schema.json"
expected_command_error_schema_id="https://vifty.local/schemas/viftyctl-command-error.schema.json"

if [ ! -x "$viftyctl" ]; then
  echo "guarded-run: viftyctl is not executable at $viftyctl" >&2
  exit 69
fi

case "$force_retry" in
  1|true|yes)
    force_retry=1
    ;;
  0|false|no|"")
    force_retry=0
    ;;
  *)
    echo "guarded-run: VIFTY_GUARDED_RUN_FORCE_RETRY must be 1/true/yes or 0/false/no." >&2
    exit 64
    ;;
esac

case "$allow_uncooled" in
  1|true|yes)
    allow_uncooled=1
    ;;
  0|false|no|"")
    allow_uncooled=0
    ;;
  *)
    echo "guarded-run: VIFTY_GUARDED_RUN_ALLOW_UNCOOLED must be 1/true/yes or 0/false/no." >&2
    exit 64
    ;;
esac

if [ "$force_retry" -eq 1 ] && [ "$allow_uncooled" -eq 1 ]; then
  echo "guarded-run: VIFTY_GUARDED_RUN_FORCE_RETRY and VIFTY_GUARDED_RUN_ALLOW_UNCOOLED are mutually exclusive; choose either a supervised cooling retry or an uncooled fallback." >&2
  exit 64
fi

set +e
capabilities_json="$("$viftyctl" capabilities --json)"
capabilities_status=$?
set -e

capability_commands="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract commands json -o - - 2>/dev/null || printf '')"
capability_workloads="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract workloads json -o - - 2>/dev/null || printf '')"
capabilities_schema_version="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract schemaVersion raw -o - - 2>/dev/null || printf '')"
capabilities_schema_id="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract schemaIDs.capabilities raw -o - - 2>/dev/null || printf '')"
capabilities_diagnose_schema_id="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract schemaIDs.diagnose raw -o - - 2>/dev/null || printf '')"
capabilities_command_error_schema_id="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract schemaIDs.commandError raw -o - - 2>/dev/null || printf '')"
capabilities_unavailable_exit="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract exitCodes.unavailable raw -o - - 2>/dev/null || printf '')"
daemon_status_available="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract daemonStatusAvailable raw -o - - 2>/dev/null || printf '')"
policy_source="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract policySource raw -o - - 2>/dev/null || printf '')"
policy_status_available="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract policyStatusAvailable raw -o - - 2>/dev/null || printf '')"
policy_enabled="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract policy.enabled raw -o - - 2>/dev/null || printf '')"
wrapper_source_directory="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract wrapperResources.sourceDirectory raw -o - - 2>/dev/null || printf '')"
wrapper_bundle_directory="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract wrapperResources.bundleDirectory raw -o - - 2>/dev/null || printf '')"
wrapper_guarded_run_script="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract wrapperResources.guardedRunScript raw -o - - 2>/dev/null || printf '')"
wrapper_workload_scripts="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract wrapperResources.workloadScripts json -o - - 2>/dev/null || printf '')"
run_child_preflight="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract runLifecycle.childCommandPreflightBeforeCooling raw -o - - 2>/dev/null || printf '')"
auto_restore_after_child="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract runLifecycle.autoRestoreAfterChildExit raw -o - - 2>/dev/null || printf '')"
structured_pre_child_failures="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract runLifecycle.structuredPreChildFailures raw -o - - 2>/dev/null || printf '')"
cleanup_state_reported="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract runLifecycle.cleanupStateReportedOnLaunchFailure raw -o - - 2>/dev/null || printf '')"
signals_forwarded="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract runLifecycle.signalsForwardedToChild json -o - - 2>/dev/null || printf '')"
supports_force_retry="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract supportsForceRetry raw -o - - 2>/dev/null || printf '')"
minimum_agent_rpm_percent="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract policy.minimumAgentRPMPercent raw -o - - 2>/dev/null || printf '')"
maximum_allowed_rpm_percent="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract policy.maximumAllowedRPMPercent raw -o - - 2>/dev/null || printf '')"
max_duration_seconds="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract policy.maxDurationSeconds raw -o - - 2>/dev/null || printf '')"
maximum_reason_length="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract metadataLimits.maximumReasonLength raw -o - - 2>/dev/null || printf '')"
maximum_idempotency_key_length="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract metadataLimits.maximumIdempotencyKeyLength raw -o - - 2>/dev/null || printf '')"

[ "$run_child_preflight" = "null" ] && run_child_preflight=""
[ "$auto_restore_after_child" = "null" ] && auto_restore_after_child=""
[ "$structured_pre_child_failures" = "null" ] && structured_pre_child_failures=""
[ "$cleanup_state_reported" = "null" ] && cleanup_state_reported=""
[ "$supports_force_retry" = "null" ] && supports_force_retry=""
[ "$capabilities_schema_version" = "null" ] && capabilities_schema_version=""
[ "$capabilities_schema_id" = "null" ] && capabilities_schema_id=""
[ "$capabilities_diagnose_schema_id" = "null" ] && capabilities_diagnose_schema_id=""
[ "$capabilities_command_error_schema_id" = "null" ] && capabilities_command_error_schema_id=""
[ "$capabilities_unavailable_exit" = "null" ] && capabilities_unavailable_exit=""
[ "$daemon_status_available" = "null" ] && daemon_status_available=""
[ "$policy_source" = "null" ] && policy_source=""
[ "$policy_status_available" = "null" ] && policy_status_available=""
[ "$policy_enabled" = "null" ] && policy_enabled=""
[ "$wrapper_source_directory" = "null" ] && wrapper_source_directory=""
[ "$wrapper_bundle_directory" = "null" ] && wrapper_bundle_directory=""
[ "$wrapper_guarded_run_script" = "null" ] && wrapper_guarded_run_script=""
[ "$wrapper_workload_scripts" = "null" ] && wrapper_workload_scripts=""
[ "$minimum_agent_rpm_percent" = "null" ] && minimum_agent_rpm_percent=""
[ "$maximum_allowed_rpm_percent" = "null" ] && maximum_allowed_rpm_percent=""
[ "$max_duration_seconds" = "null" ] && max_duration_seconds=""
[ "$maximum_reason_length" = "null" ] && maximum_reason_length=""
[ "$maximum_idempotency_key_length" = "null" ] && maximum_idempotency_key_length=""

if [ "$capabilities_status" -ne 0 ] && [ "$capabilities_status" != "$capabilities_unavailable_exit" ]; then
  echo "guarded-run: viftyctl capabilities exited $capabilities_status instead of advertised unavailable exit ${capabilities_unavailable_exit:-unknown}; refusing to request cooling." >&2
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

if [ "$capabilities_schema_version" != "1" ] ||
   [ "$capabilities_schema_id" != "$expected_capabilities_schema_id" ]; then
  echo "guarded-run: viftyctl capabilities schema identity is not recognized; refusing to request cooling." >&2
  echo "guarded-run: expected schemaVersion=1 and schemaIDs.capabilities=$expected_capabilities_schema_id." >&2
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

if [ "$capabilities_diagnose_schema_id" != "$expected_diagnose_schema_id" ]; then
  echo "guarded-run: viftyctl capabilities diagnose schema identity is not recognized; refusing to request cooling." >&2
  echo "guarded-run: expected schemaIDs.diagnose=$expected_diagnose_schema_id." >&2
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

if [ "$capabilities_command_error_schema_id" != "$expected_command_error_schema_id" ]; then
  echo "guarded-run: viftyctl capabilities command-error schema identity is not recognized; refusing to request cooling." >&2
  echo "guarded-run: expected schemaIDs.commandError=$expected_command_error_schema_id." >&2
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

if [ "$capabilities_status" -ne 0 ] || [ "$daemon_status_available" != "true" ] || [ "$policy_source" != "daemonStatus" ] || [ "$policy_status_available" != "true" ]; then
  echo "guarded-run: viftyctl capabilities did not report daemon-backed policy status; refusing to request cooling." >&2
  echo "guarded-run: expected exit=0, daemonStatusAvailable=true, policySource=daemonStatus, and policyStatusAvailable=true." >&2
  if [ "$capabilities_status" -ne 0 ]; then
    echo "guarded-run: capabilities exited $capabilities_status." >&2
  fi
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

if [ "$policy_enabled" != "true" ]; then
  echo "guarded-run: viftyctl capabilities does not advertise enabled agent policy; refusing to request cooling." >&2
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

if ! printf '%s\n' "$capability_commands" | /usr/bin/grep -F '"run"' >/dev/null 2>&1; then
  echo "guarded-run: viftyctl capabilities does not advertise run command support; refusing to request cooling." >&2
  if [ "$capabilities_status" -ne 0 ]; then
    echo "guarded-run: capabilities exited $capabilities_status." >&2
  fi
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

if ! printf '%s\n' "$capability_workloads" | /usr/bin/grep -F "\"$workload\"" >/dev/null 2>&1; then
  echo "guarded-run: viftyctl capabilities does not advertise workload '$workload'; refusing to request cooling." >&2
  if [ "$capabilities_status" -ne 0 ]; then
    echo "guarded-run: capabilities exited $capabilities_status." >&2
  fi
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

missing_wrapper_script=0
for expected_wrapper_script in \
  cargo-build.sh \
  cargo-test.sh \
  custom-workload.sh \
  local-model.sh \
  make-build.sh \
  make-test.sh \
  make-verify.sh \
  npm-build.sh \
  npm-test.sh \
  pytest.sh \
  swift-release-build.sh \
  swift-test.sh \
  xcode-build.sh \
  xcode-test.sh
do
  case "$wrapper_workload_scripts" in
    *"\"$expected_wrapper_script\""*) ;;
    *) missing_wrapper_script=1 ;;
  esac
done

if [ "$wrapper_source_directory" != "examples/viftyctl" ] ||
   [ "$wrapper_bundle_directory" != "Contents/Resources/viftyctl-wrappers" ] ||
   [ "$wrapper_guarded_run_script" != "guarded-run.sh" ] ||
   [ "$missing_wrapper_script" -ne 0 ]; then
  echo "guarded-run: viftyctl capabilities does not advertise wrapper resource discovery; refusing to request cooling." >&2
  if [ "$capabilities_status" -ne 0 ]; then
    echo "guarded-run: capabilities exited $capabilities_status." >&2
  fi
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

case "$signals_forwarded" in
  *'"INT"'*) forwards_int=1 ;;
  *) forwards_int=0 ;;
esac

case "$signals_forwarded" in
  *'"TERM"'*) forwards_term=1 ;;
  *) forwards_term=0 ;;
esac

case "$signals_forwarded" in
  *'"HUP"'*) forwards_hup=1 ;;
  *) forwards_hup=0 ;;
esac

if [ "$run_child_preflight" != "true" ] ||
   [ "$auto_restore_after_child" != "true" ] ||
   [ "$structured_pre_child_failures" != "true" ] ||
   [ "$cleanup_state_reported" != "true" ] ||
   [ "$forwards_int" -ne 1 ] ||
   [ "$forwards_term" -ne 1 ] ||
   [ "$forwards_hup" -ne 1 ]; then
  echo "guarded-run: viftyctl capabilities does not advertise the safe run lifecycle; refusing to request cooling." >&2
  if [ "$capabilities_status" -ne 0 ]; then
    echo "guarded-run: capabilities exited $capabilities_status." >&2
  fi
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

if ! is_positive_integer "$minimum_agent_rpm_percent" ||
   ! is_positive_integer "$maximum_allowed_rpm_percent" ||
   ! /usr/bin/awk -v minimum="$minimum_agent_rpm_percent" -v maximum="$maximum_allowed_rpm_percent" 'BEGIN { exit !((minimum + 0) <= (maximum + 0)) }'; then
  echo "guarded-run: viftyctl capabilities does not advertise usable RPM policy limits; refusing to request cooling." >&2
  if [ "$capabilities_status" -ne 0 ]; then
    echo "guarded-run: capabilities exited $capabilities_status." >&2
  fi
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

if ! /usr/bin/awk -v value="$max_rpm_percent" -v minimum="$minimum_agent_rpm_percent" -v maximum="$maximum_allowed_rpm_percent" 'BEGIN { exit !((value + 0) >= (minimum + 0) && (value + 0) <= (maximum + 0)) }'; then
  echo "guarded-run: max-rpm-percent $max_rpm_percent is outside advertised policy range $minimum_agent_rpm_percent...$maximum_allowed_rpm_percent." >&2
  exit 64
fi

if ! is_positive_integer "$max_duration_seconds"; then
  echo "guarded-run: viftyctl capabilities does not advertise a usable duration policy limit; refusing to request cooling." >&2
  if [ "$capabilities_status" -ne 0 ]; then
    echo "guarded-run: capabilities exited $capabilities_status." >&2
  fi
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

if ! duration_within_maximum "$duration" "$max_duration_seconds"; then
  echo "guarded-run: duration $duration exceeds advertised policy maximum $max_duration_seconds seconds." >&2
  exit 64
fi

if ! is_positive_integer "$maximum_reason_length" ||
   ! is_positive_integer "$maximum_idempotency_key_length"; then
  echo "guarded-run: viftyctl capabilities does not advertise metadata limits; refusing to request cooling." >&2
  if [ "$capabilities_status" -ne 0 ]; then
    echo "guarded-run: capabilities exited $capabilities_status." >&2
  fi
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

reason_length="$(trimmed_character_count "$reason")"
if ! printf '%s\n' "$reason_length" | /usr/bin/awk -v maximum="$maximum_reason_length" '
  /^[0-9]+$/ { exit !(($0 + 0) <= (maximum + 0)) }
  { exit 1 }
'; then
  echo "guarded-run: reason is $reason_length characters after trimming; maximum is $maximum_reason_length." >&2
  exit 64
fi

if [ "$force_retry" -eq 1 ] && [ "$supports_force_retry" != "true" ]; then
  echo "guarded-run: viftyctl capabilities does not advertise force retry support; refusing to pass --force." >&2
  if [ "$capabilities_status" -ne 0 ]; then
    echo "guarded-run: capabilities exited $capabilities_status." >&2
  fi
  if [ -n "$capabilities_json" ]; then
    printf '%s\n' "$capabilities_json" >&2
  fi
  exit 75
fi

set +e
diagnose_json="$("$viftyctl" diagnose --json)"
diagnose_status=$?
set -e

state="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract state raw -o - - 2>/dev/null || printf '')"
diagnose_schema_version="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract schemaVersion raw -o - - 2>/dev/null || printf '')"
diagnose_schema_id="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract schemaID raw -o - - 2>/dev/null || printf '')"
recommended_action="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract recommendedAgentAction raw -o - - 2>/dev/null || printf '')"
recommended_recovery_action="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract recommendedRecoveryAction raw -o - - 2>/dev/null || printf '')"
safe_to_request="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract safeToRequestCooling raw -o - - 2>/dev/null || printf '')"
daemon_control_path_ready="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract daemonControlPathReady raw -o - - 2>/dev/null || printf '')"
manual_control_active="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract manualControlActive raw -o - - 2>/dev/null || printf '')"

[ "$state" = "null" ] && state=""
[ "$diagnose_schema_version" = "null" ] && diagnose_schema_version=""
[ "$diagnose_schema_id" = "null" ] && diagnose_schema_id=""
[ "$recommended_action" = "null" ] && recommended_action=""
[ "$recommended_recovery_action" = "null" ] && recommended_recovery_action=""
[ "$safe_to_request" = "null" ] && safe_to_request=""
[ "$daemon_control_path_ready" = "null" ] && daemon_control_path_ready=""
[ "$manual_control_active" = "null" ] && manual_control_active=""

if [ "$diagnose_status" -ne 0 ] && [ "$state" != "blocked" ]; then
  if [ "$diagnose_schema_version" != "1" ] ||
     [ "$diagnose_schema_id" != "$capabilities_command_error_schema_id" ]; then
    echo "guarded-run: Vifty diagnose command-error schema identity is not recognized; refusing to request cooling." >&2
    echo "guarded-run: expected schemaVersion=1 and schemaID=$capabilities_command_error_schema_id." >&2
    if [ -n "$diagnose_json" ]; then
      printf '%s\n' "$diagnose_json" >&2
    fi
    exit 75
  fi

  echo "guarded-run: Vifty diagnose failed; refusing to request cooling." >&2
  if [ -n "$diagnose_json" ]; then
    printf '%s\n' "$diagnose_json" >&2
  fi
  exit 75
fi

if [ "$diagnose_schema_version" != "1" ]; then
  echo "guarded-run: Vifty diagnose readiness schema version is not recognized; refusing to request cooling." >&2
  echo "guarded-run: expected schemaVersion=1." >&2
  if [ -n "$diagnose_json" ]; then
    printf '%s\n' "$diagnose_json" >&2
  fi
  exit 75
fi

if [ -z "$state" ]; then
  state="blocked"
fi

case "$state" in
  ready|degraded|blocked)
    ;;
  *)
    echo "guarded-run: unknown Vifty readiness state '$state'; refusing to request cooling." >&2
    printf '%s\n' "$diagnose_json" >&2
    exit 75
    ;;
esac

if [ -z "$recommended_action" ] ||
   [ -z "$recommended_recovery_action" ] ||
   [ -z "$safe_to_request" ] ||
   [ -z "$daemon_control_path_ready" ] ||
   [ -z "$manual_control_active" ]; then
  echo "guarded-run: Vifty diagnose is missing agent decision fields; refusing to request cooling." >&2
  printf '%s\n' "$diagnose_json" >&2
  exit 75
fi

case "$safe_to_request" in
  true|false)
    ;;
  *)
    echo "guarded-run: Vifty diagnose is missing agent decision fields; refusing to request cooling." >&2
    printf '%s\n' "$diagnose_json" >&2
    exit 75
    ;;
esac

case "$daemon_control_path_ready" in
  true|false)
    ;;
  *)
    echo "guarded-run: Vifty diagnose is missing agent decision fields; refusing to request cooling." >&2
    printf '%s\n' "$diagnose_json" >&2
    exit 75
    ;;
esac

case "$manual_control_active" in
  true|false)
    ;;
  *)
    echo "guarded-run: Vifty diagnose is missing agent decision fields; refusing to request cooling." >&2
    printf '%s\n' "$diagnose_json" >&2
    exit 75
    ;;
esac

case "$recommended_action" in
  requestCooling|requestCoolingWithCaution|restoreAutoBeforeRequestingCooling|doNotRequestCooling)
    ;;
  *)
    echo "guarded-run: Vifty diagnose is missing agent decision fields; refusing to request cooling." >&2
    printf '%s\n' "$diagnose_json" >&2
    exit 75
    ;;
esac

case "$recommended_recovery_action" in
  none|repairHelper|restoreAutoBeforeRetry|backOffWorkload|inspectPolicy|collectHardwareEvidence)
    ;;
  *)
    echo "guarded-run: Vifty diagnose is missing agent decision fields; refusing to request cooling." >&2
    printf '%s\n' "$diagnose_json" >&2
    exit 75
    ;;
esac

if [ "$state" = "blocked" ]; then
  finish_without_cooling_request "Vifty readiness is blocked; refusing to request cooling." "$@"
fi

if [ "$safe_to_request" != "true" ]; then
  case "$recommended_action" in
    restoreAutoBeforeRequestingCooling)
      no_cooling_message="Vifty recommends restoring Auto before requesting new cooling."
      ;;
    doNotRequestCooling)
      no_cooling_message="Vifty recommends not requesting cooling."
      ;;
    *)
      no_cooling_message="Vifty reports safeToRequestCooling=$safe_to_request for action '$recommended_action'; refusing to request cooling."
      ;;
  esac
  finish_without_cooling_request "$no_cooling_message" "$@"
fi

if [ "$daemon_control_path_ready" != "true" ]; then
  finish_without_cooling_request "Vifty daemon control path is not ready; refusing to request cooling." "$@"
fi

if [ "$manual_control_active" = "true" ]; then
  finish_without_cooling_request "Vifty/manual fan control is active; restore Auto before requesting agent cooling." "$@"
fi

case "$recommended_action" in
  requestCooling)
    ;;
  requestCoolingWithCaution)
    echo "guarded-run: Vifty recommends caution; proceeding with bounded cooling." >&2
    ;;
  *)
    echo "guarded-run: unknown Vifty agent action '$recommended_action'; refusing to request cooling." >&2
    printf '%s\n' "$diagnose_json" >&2
    exit 75
    ;;
esac

if [ "$force_retry" -eq 1 ]; then
  exec "$viftyctl" run \
    --json \
    --workload "$workload" \
    --duration "$duration" \
    --max-rpm-percent "$max_rpm_percent" \
    --force \
    --reason "$reason" \
    -- "$@"
fi

exec "$viftyctl" run \
  --json \
  --workload "$workload" \
  --duration "$duration" \
  --max-rpm-percent "$max_rpm_percent" \
  --reason "$reason" \
  -- "$@"
