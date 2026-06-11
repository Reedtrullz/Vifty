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

if [ "$#" -lt 6 ]; then
  usage
  exit 64
fi

workload="$1"
duration="$2"
max_rpm_percent="$3"
reason="$4"
shift 4

if [ "${1:-}" != "--" ]; then
  usage
  exit 64
fi
shift

if [ "$#" -eq 0 ]; then
  usage
  exit 64
fi

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
safe_to_request="$(printf '%s\n' "$diagnose_json" | /usr/bin/plutil -extract safeToRequestCooling raw -o - - 2>/dev/null || printf '')"

[ "$state" = "null" ] && state=""
[ "$recommended_action" = "null" ] && recommended_action=""
[ "$safe_to_request" = "null" ] && safe_to_request=""

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
  ready|degraded)
    ;;
  blocked)
    echo "guarded-run: Vifty readiness is blocked; refusing to request cooling." >&2
    printf '%s\n' "$diagnose_json" >&2
    exit 75
    ;;
  *)
    echo "guarded-run: unknown Vifty readiness state '$state'; refusing to request cooling." >&2
    printf '%s\n' "$diagnose_json" >&2
    exit 75
    ;;
esac

if [ -z "$recommended_action" ] || [ -z "$safe_to_request" ]; then
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

case "$recommended_action" in
  requestCooling|requestCoolingWithCaution|restoreAutoBeforeRequestingCooling|doNotRequestCooling)
    ;;
  *)
    echo "guarded-run: Vifty diagnose is missing agent decision fields; refusing to request cooling." >&2
    printf '%s\n' "$diagnose_json" >&2
    exit 75
    ;;
esac

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
