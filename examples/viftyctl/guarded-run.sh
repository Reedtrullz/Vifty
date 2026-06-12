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

set +e
capabilities_json="$("$viftyctl" capabilities --json)"
capabilities_status=$?
set -e

capability_commands="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract commands json -o - - 2>/dev/null || printf '')"
capability_workloads="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract workloads json -o - - 2>/dev/null || printf '')"
capabilities_unavailable_exit="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract exitCodes.unavailable raw -o - - 2>/dev/null || printf '')"
run_child_preflight="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract runLifecycle.childCommandPreflightBeforeCooling raw -o - - 2>/dev/null || printf '')"
auto_restore_after_child="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract runLifecycle.autoRestoreAfterChildExit raw -o - - 2>/dev/null || printf '')"
structured_pre_child_failures="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract runLifecycle.structuredPreChildFailures raw -o - - 2>/dev/null || printf '')"
cleanup_state_reported="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract runLifecycle.cleanupStateReportedOnLaunchFailure raw -o - - 2>/dev/null || printf '')"
signals_forwarded="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract runLifecycle.signalsForwardedToChild json -o - - 2>/dev/null || printf '')"
supports_force_retry="$(printf '%s\n' "$capabilities_json" | /usr/bin/plutil -extract supportsForceRetry raw -o - - 2>/dev/null || printf '')"

[ "$run_child_preflight" = "null" ] && run_child_preflight=""
[ "$auto_restore_after_child" = "null" ] && auto_restore_after_child=""
[ "$structured_pre_child_failures" = "null" ] && structured_pre_child_failures=""
[ "$cleanup_state_reported" = "null" ] && cleanup_state_reported=""
[ "$supports_force_retry" = "null" ] && supports_force_retry=""
[ "$capabilities_unavailable_exit" = "null" ] && capabilities_unavailable_exit=""

if [ "$capabilities_status" -ne 0 ] && [ "$capabilities_status" != "$capabilities_unavailable_exit" ]; then
  echo "guarded-run: viftyctl capabilities exited $capabilities_status instead of advertised unavailable exit ${capabilities_unavailable_exit:-unknown}; refusing to request cooling." >&2
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
recommended_action="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract recommendedAgentAction raw -o - - 2>/dev/null || printf '')"
recommended_recovery_action="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract recommendedRecoveryAction raw -o - - 2>/dev/null || printf '')"
safe_to_request="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract safeToRequestCooling raw -o - - 2>/dev/null || printf '')"
daemon_control_path_ready="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract daemonControlPathReady raw -o - - 2>/dev/null || printf '')"

[ "$state" = "null" ] && state=""
[ "$recommended_action" = "null" ] && recommended_action=""
[ "$recommended_recovery_action" = "null" ] && recommended_recovery_action=""
[ "$safe_to_request" = "null" ] && safe_to_request=""
[ "$daemon_control_path_ready" = "null" ] && daemon_control_path_ready=""

if [ "$diagnose_status" -ne 0 ] && [ "$state" != "blocked" ]; then
  echo "guarded-run: Vifty diagnose failed; refusing to request cooling." >&2
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
   [ -z "$daemon_control_path_ready" ]; then
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
  echo "guarded-run: Vifty readiness is blocked; refusing to request cooling." >&2
  print_readiness_recovery_action "$recommended_recovery_action"
  printf '%s\n' "$diagnose_json" >&2
  exit 75
fi

if [ "$safe_to_request" != "true" ]; then
  case "$recommended_action" in
    restoreAutoBeforeRequestingCooling)
      echo "guarded-run: Vifty recommends restoring Auto before requesting new cooling." >&2
      ;;
    doNotRequestCooling)
      echo "guarded-run: Vifty recommends not requesting cooling." >&2
      ;;
    *)
      echo "guarded-run: Vifty reports safeToRequestCooling=$safe_to_request for action '$recommended_action'; refusing to request cooling." >&2
      ;;
  esac
  print_readiness_recovery_action "$recommended_recovery_action"
  printf '%s\n' "$diagnose_json" >&2
  exit 75
fi

if [ "$daemon_control_path_ready" != "true" ]; then
  echo "guarded-run: Vifty daemon control path is not ready; refusing to request cooling." >&2
  print_readiness_recovery_action "$recommended_recovery_action"
  printf '%s\n' "$diagnose_json" >&2
  exit 75
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
