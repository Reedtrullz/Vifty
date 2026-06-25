#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${VIFTY_APP:-/Applications/Vifty.app}"
DRY_RUN=0
HELPER_TARGET="${VIFTY_HELPER_TARGET:-/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon}"
PLIST_TARGET="${VIFTY_DAEMON_PLIST_TARGET:-/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist}"
STDOUT_LOG_TARGET="${VIFTY_DAEMON_STDOUT_LOG:-/var/log/tech.reidar.vifty.daemon.out.log}"
STDERR_LOG_TARGET="${VIFTY_DAEMON_STDERR_LOG:-/var/log/tech.reidar.vifty.daemon.err.log}"
SERVICE_TARGET="system/tech.reidar.vifty.daemon"

usage() {
  cat >&2 <<'USAGE'
Usage:
  repair-vifty-helper.sh [--app /Applications/Vifty.app] [--dry-run]

Repairs Vifty's privileged LaunchDaemon helper from an installed app bundle.
This is an explicit operator action and may prompt for administrator approval.
It does not request cooling or write fan state directly.

Environment:
  VIFTY_APP                  App bundle to repair from. Defaults to /Applications/Vifty.app.
  VIFTY_HELPER_TARGET        Privileged helper destination.
  VIFTY_DAEMON_PLIST_TARGET  LaunchDaemon plist destination.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --app)
      if [ "$#" -lt 2 ]; then
        echo "repair-helper: --app requires a path." >&2
        exit 64
      fi
      APP_PATH="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "repair-helper: unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

shell_quote() {
  printf "'"
  printf "%s" "$1" | sed "s/'/'\\\\''/g"
  printf "'"
}

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

APP_PATH="${APP_PATH%/}"
DAEMON_SOURCE="${APP_PATH}/Contents/MacOS/ViftyDaemon"
PLIST_SOURCE="${APP_PATH}/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
VIFTYCTL="${APP_PATH}/Contents/MacOS/viftyctl"

if [ ! -d "$APP_PATH" ]; then
  echo "repair-helper: app bundle not found: $APP_PATH" >&2
  exit 66
fi

if [ ! -x "$DAEMON_SOURCE" ]; then
  echo "repair-helper: bundled daemon is missing or not executable: $DAEMON_SOURCE" >&2
  exit 66
fi

if [ ! -f "$PLIST_SOURCE" ]; then
  echo "repair-helper: bundled LaunchDaemon plist is missing: $PLIST_SOURCE" >&2
  exit 66
fi

if ! /usr/bin/plutil -lint "$PLIST_SOURCE" >/dev/null; then
  echo "repair-helper: bundled LaunchDaemon plist is invalid: $PLIST_SOURCE" >&2
  exit 66
fi

ADMIN_SCRIPT="$(cat <<SCRIPT
set -e
mkdir -p /Library/PrivilegedHelperTools
launchctl bootout system $(shell_quote "$PLIST_TARGET") 2>/dev/null || true
helper_tmp="\$(mktemp $(shell_quote "${HELPER_TARGET}.XXXXXX"))"
plist_tmp="\$(mktemp $(shell_quote "${PLIST_TARGET}.XXXXXX"))"
trap 'rm -f "\$helper_tmp" "\$plist_tmp"' EXIT
cp $(shell_quote "$DAEMON_SOURCE") "\$helper_tmp"
chmod 755 "\$helper_tmp"
chown root:wheel "\$helper_tmp"
cp $(shell_quote "$PLIST_SOURCE") "\$plist_tmp"
chmod 644 "\$plist_tmp"
chown root:wheel "\$plist_tmp"
xattr -cr "\$helper_tmp" "\$plist_tmp" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Delete :BundleProgram' "\$plist_tmp" 2>/dev/null || true
if ! /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "\$plist_tmp" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c 'Delete :ProgramArguments' "\$plist_tmp" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "\$plist_tmp"
fi
if ! /usr/libexec/PlistBuddy -c $(shell_quote "Add :ProgramArguments:0 string ${HELPER_TARGET}") "\$plist_tmp" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c $(shell_quote "Set :ProgramArguments:0 ${HELPER_TARGET}") "\$plist_tmp"
fi
mv -f "\$helper_tmp" $(shell_quote "$HELPER_TARGET")
mv -f "\$plist_tmp" $(shell_quote "$PLIST_TARGET")
for log_path in $(shell_quote "$STDOUT_LOG_TARGET") $(shell_quote "$STDERR_LOG_TARGET"); do
  touch "\$log_path"
  chmod 600 "\$log_path"
  chown root:wheel "\$log_path"
done
launchctl bootstrap system $(shell_quote "$PLIST_TARGET")
launchctl kickstart -k $(shell_quote "$SERVICE_TARGET")
SCRIPT
)"

if [ "$DRY_RUN" -eq 1 ]; then
  printf '%s\n' "$ADMIN_SCRIPT"
  exit 0
fi

echo "repair-helper: repairing Vifty fan helper from $APP_PATH"
echo "repair-helper: macOS may ask for administrator approval."

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vifty-helper-repair.XXXXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
ADMIN_SCRIPT_PATH="${TMP_DIR}/repair-helper.sh"
printf '%s\n' "$ADMIN_SCRIPT" > "$ADMIN_SCRIPT_PATH"
chmod 700 "$ADMIN_SCRIPT_PATH"

/usr/bin/osascript <<APPLESCRIPT
do shell script "/bin/bash " & quoted form of "${ADMIN_SCRIPT_PATH}" with administrator privileges
APPLESCRIPT

bundled_sha="$(sha256_file "$DAEMON_SOURCE")"
if [ ! -f "$HELPER_TARGET" ]; then
  echo "repair-helper: helper repair finished, but installed helper was not found at $HELPER_TARGET" >&2
  exit 75
fi

installed_sha="$(sha256_file "$HELPER_TARGET")"
if [ "$bundled_sha" != "$installed_sha" ]; then
  echo "repair-helper: helper repair finished, but installed helper still differs from the app bundle." >&2
  echo "repair-helper: bundled daemon:   $bundled_sha" >&2
  echo "repair-helper: installed helper: $installed_sha" >&2
  exit 75
fi

echo "repair-helper: installed helper matches the app bundle."

if [ -x "$VIFTYCTL" ]; then
  set +e
  diagnose_output="$("$VIFTYCTL" diagnose --json 2>/dev/null)"
  diagnose_status=$?
  set -e
  echo "repair-helper: viftyctl diagnose exited $diagnose_status after repair."
  printf '%s\n' "$diagnose_output" | /usr/bin/ruby -rjson -e '
    begin
      payload = JSON.parse(STDIN.read)
      puts "repair-helper: state=#{payload["state"] || "unknown"} recommendedRecoveryAction=#{payload["recommendedRecoveryAction"] || "unknown"} safeToRequestCooling=#{payload["safeToRequestCooling"].inspect} manualControlActive=#{payload["manualControlActive"].inspect}"
      blockers = payload["coolingBlockerIDs"]
      puts "repair-helper: coolingBlockerIDs=#{blockers.join(",")}" if blockers.is_a?(Array) && !blockers.empty?
    rescue JSON::ParserError
      puts "repair-helper: diagnose output was not parseable JSON."
    end
  '
  if [ "$diagnose_status" -ne 0 ]; then
    echo "repair-helper: fan writes may still be blocked. Follow the JSON recovery action before requesting cooling."
  fi
fi
