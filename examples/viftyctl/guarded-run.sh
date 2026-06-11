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

if [ ! -x "$viftyctl" ]; then
  echo "guarded-run: viftyctl is not executable at $viftyctl" >&2
  exit 69
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

exec "$viftyctl" run \
  --json \
  --workload "$workload" \
  --duration "$duration" \
  --max-rpm-percent "$max_rpm_percent" \
  --force \
  --reason "$reason" \
  -- "$@"
