#!/usr/bin/env bash
set -euo pipefail

PLIST_PATH=""
CONFIGURATION=""
TEAM_ID="${VIFTY_XPC_ALLOWED_TEAM_ID:-}"
ADHOC_DEVELOPMENT="${VIFTY_XPC_ADHOC_DEVELOPMENT:-0}"
ADHOC_UID="${VIFTY_XPC_ADHOC_ALLOWED_UID:-}"
ADHOC_APP_PATH="${VIFTY_XPC_ADHOC_APP_PATH:-}"
ADHOC_CTL_PATH="${VIFTY_XPC_ADHOC_CTL_PATH:-}"
ADHOC_HELPER_PATH="${VIFTY_XPC_ADHOC_HELPER_PATH:-}"
VALIDATE_ONLY=0

usage() {
  cat >&2 <<'USAGE'
Usage:
  configure-daemon-plist.sh --configuration debug|release [--plist path]
    [--team-id TEAMID]
    [--enable-adhoc --adhoc-uid UID --adhoc-app-path /absolute/.../Vifty
                    --adhoc-ctl-path /absolute/.../viftyctl]
    [--validate-only]

Ad-hoc XPC access is explicit, debug-only, and all-or-nothing. The deprecated
VIFTY_XPC_ADHOC_HELPER_PATH is always rejected because ViftyHelper is not an
XPC client. Release configuration rejects every ad-hoc development value.
USAGE
}

require_value() {
  if [[ -z "${2:-}" || "${2:-}" == --* ]]; then
    echo "configure-daemon-plist: $1 requires a value." >&2
    exit 64
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --plist)
      require_value "$1" "${2:-}"
      PLIST_PATH="$2"
      shift 2
      ;;
    --configuration)
      require_value "$1" "${2:-}"
      CONFIGURATION="$2"
      shift 2
      ;;
    --team-id)
      TEAM_ID="${2:-}"
      shift 2
      ;;
    --enable-adhoc)
      ADHOC_DEVELOPMENT=1
      shift
      ;;
    --adhoc-uid)
      require_value "$1" "${2:-}"
      ADHOC_UID="$2"
      shift 2
      ;;
    --adhoc-app-path)
      require_value "$1" "${2:-}"
      ADHOC_APP_PATH="$2"
      shift 2
      ;;
    --adhoc-ctl-path)
      require_value "$1" "${2:-}"
      ADHOC_CTL_PATH="$2"
      shift 2
      ;;
    --adhoc-helper-path)
      require_value "$1" "${2:-}"
      ADHOC_HELPER_PATH="$2"
      shift 2
      ;;
    --validate-only)
      VALIDATE_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "configure-daemon-plist: unknown argument: $1" >&2
      exit 64
      ;;
  esac
done

case "${CONFIGURATION}" in
  debug|release) ;;
  *)
    echo "configure-daemon-plist: --configuration must be debug or release." >&2
    exit 64
    ;;
esac

if [[ -n "${ADHOC_HELPER_PATH}" ]]; then
  echo "configure-daemon-plist: VIFTY_XPC_ADHOC_HELPER_PATH is unsupported and must be empty." >&2
  exit 65
fi

has_adhoc_value=0
if [[ "${ADHOC_DEVELOPMENT}" != "0" || -n "${ADHOC_UID}" || -n "${ADHOC_APP_PATH}" || -n "${ADHOC_CTL_PATH}" ]]; then
  has_adhoc_value=1
fi

if [[ "${CONFIGURATION}" == "release" && "${has_adhoc_value}" -eq 1 ]]; then
  echo "configure-daemon-plist: release builds reject every VIFTY_XPC_ADHOC_* value." >&2
  exit 65
fi

if [[ "${ADHOC_DEVELOPMENT}" == "1" ]]; then
  if [[ -n "${TEAM_ID}" ]]; then
    echo "configure-daemon-plist: ad-hoc development and TeamID trust cannot be mixed." >&2
    exit 65
  fi
  if [[ -z "${ADHOC_UID}" || -z "${ADHOC_APP_PATH}" || -z "${ADHOC_CTL_PATH}" ]]; then
    echo "configure-daemon-plist: ad-hoc development requires UID plus exact Vifty and viftyctl paths." >&2
    exit 65
  fi
  if [[ ! "${ADHOC_UID}" =~ ^[0-9]+$ ]]; then
    echo "configure-daemon-plist: ad-hoc UID must be numeric." >&2
    exit 65
  fi
  case "${ADHOC_APP_PATH}" in
    /*/Contents/MacOS/Vifty) ;;
    *)
      echo "configure-daemon-plist: ad-hoc app path must be an absolute Vifty executable path." >&2
      exit 65
      ;;
  esac
  case "${ADHOC_CTL_PATH}" in
    /*/Contents/MacOS/viftyctl) ;;
    *)
      echo "configure-daemon-plist: ad-hoc ctl path must be an absolute lowercase viftyctl executable path." >&2
      exit 65
      ;;
  esac
  if [[ "${ADHOC_APP_PATH}" == *"/../"* || "${ADHOC_CTL_PATH}" == *"/../"* ]]; then
    echo "configure-daemon-plist: ad-hoc executable paths must not contain parent traversal." >&2
    exit 65
  fi
elif [[ "${has_adhoc_value}" -eq 1 ]]; then
  echo "configure-daemon-plist: partial ad-hoc configuration is forbidden; set VIFTY_XPC_ADHOC_DEVELOPMENT=1 explicitly." >&2
  exit 65
fi

if [[ "${VALIDATE_ONLY}" -eq 1 ]]; then
  exit 0
fi

if [[ -z "${PLIST_PATH}" || ! -f "${PLIST_PATH}" || -L "${PLIST_PATH}" ]]; then
  echo "configure-daemon-plist: --plist must name an existing regular non-symlink plist." >&2
  exit 66
fi
if ! /usr/bin/plutil -lint "${PLIST_PATH}" >/dev/null; then
  echo "configure-daemon-plist: plist is invalid." >&2
  exit 66
fi

set_plist_string() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Delete :EnvironmentVariables:${key}" "${PLIST_PATH}" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:${key} string ${value}" "${PLIST_PATH}"
}

delete_plist_key() {
  /usr/libexec/PlistBuddy -c "Delete :EnvironmentVariables:$1" "${PLIST_PATH}" >/dev/null 2>&1 || true
}

set_plist_string VIFTY_XPC_ALLOWED_TEAM_ID "${TEAM_ID}"
delete_plist_key VIFTY_XPC_ADHOC_ALLOWED_UID
delete_plist_key VIFTY_XPC_ADHOC_DEVELOPMENT
delete_plist_key VIFTY_XPC_ADHOC_APP_PATH
delete_plist_key VIFTY_XPC_ADHOC_CTL_PATH
delete_plist_key VIFTY_XPC_ADHOC_HELPER_PATH

if [[ "${ADHOC_DEVELOPMENT}" == "1" ]]; then
  set_plist_string VIFTY_XPC_ADHOC_DEVELOPMENT "1"
  set_plist_string VIFTY_XPC_ADHOC_ALLOWED_UID "${ADHOC_UID}"
  set_plist_string VIFTY_XPC_ADHOC_APP_PATH "${ADHOC_APP_PATH}"
  set_plist_string VIFTY_XPC_ADHOC_CTL_PATH "${ADHOC_CTL_PATH}"
fi

/usr/bin/plutil -lint "${PLIST_PATH}" >/dev/null
