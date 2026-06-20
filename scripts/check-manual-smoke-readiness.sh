#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/check-manual-smoke-readiness.sh [options]

Run a read-only preflight before human-supervised Fixed/Curve fan smoke tests.

Options:
  --viftyctl <path>  viftyctl path (default:
                     /Applications/Vifty.app/Contents/MacOS/viftyctl)
  --json             Print the readiness summary as JSON instead of prose.
  -h, --help         Show this help.

This script only runs:
  viftyctl diagnose --json

It does not call prepare, run, restore-auto, ViftyHelper, sudo, or raw SMC
tools. Exit 0 means the manual smoke preflight is ready. Exit 75 means the
manual smoke test must be skipped until the printed blockers are cleared.
USAGE
}

VIFTYCTL="${VIFTYCTL:-/Applications/Vifty.app/Contents/MacOS/viftyctl}"
JSON_OUTPUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --viftyctl)
      if [[ $# -lt 2 ]]; then
        echo "error: --viftyctl requires a path" >&2
        exit 64
      fi
      VIFTYCTL="$2"
      shift 2
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
      usage >&2
      exit 64
      ;;
  esac
done

if [[ ! -x "${VIFTYCTL}" ]]; then
  echo "error: viftyctl is not executable: ${VIFTYCTL}" >&2
  exit 69
fi

DIAGNOSE_JSON="$(mktemp "${TMPDIR:-/tmp}/vifty-manual-smoke-diagnose.XXXXXXXX.json")"
DIAGNOSE_STDERR="$(mktemp "${TMPDIR:-/tmp}/vifty-manual-smoke-diagnose.XXXXXXXX.stderr")"
trap 'rm -f "${DIAGNOSE_JSON}" "${DIAGNOSE_STDERR}"' EXIT

set +e
if [[ "${VIFTY_TEST_SHELL_FIXTURES:-0}" == "1" ]]; then
  /bin/sh "${VIFTYCTL}" diagnose --json > "${DIAGNOSE_JSON}" 2> "${DIAGNOSE_STDERR}"
else
  "${VIFTYCTL}" diagnose --json > "${DIAGNOSE_JSON}" 2> "${DIAGNOSE_STDERR}"
fi
DIAGNOSE_STATUS=$?
set -e

ruby -rjson - "${DIAGNOSE_JSON}" "${DIAGNOSE_STATUS}" "${JSON_OUTPUT}" <<'RUBY'
path = ARGV.fetch(0)
diagnose_status = Integer(ARGV.fetch(1))
json_output = ARGV.fetch(2) == "1"

raw = File.read(path)
parse_error = nil
diagnose = begin
  JSON.parse(raw)
rescue JSON::ParserError => error
  parse_error = error.message
  {}
end

def boolean_value(value)
  value == true ? true : value == false ? false : nil
end

def integer_value(value)
  return value if value.is_a?(Integer)
  Integer(value)
rescue ArgumentError, TypeError
  nil
end

def array_value(value)
  value.is_a?(Array) ? value : []
end

app_preferences = diagnose["appPreferences"].is_a?(Hash) ? diagnose["appPreferences"] : {}
recommended_action = diagnose["recommendedAgentAction"].to_s
recommended_recovery = diagnose["recommendedRecoveryAction"].to_s
thermal_pressure = diagnose["thermalPressure"].to_s
fan_count = integer_value(diagnose["fanCount"])
controllable_fan_count = integer_value(diagnose["controllableFanCount"])
temperature_sensor_count = integer_value(diagnose["temperatureSensorCount"])
manual_control_active = boolean_value(diagnose["manualControlActive"])
safe_to_request_cooling = boolean_value(diagnose["safeToRequestCooling"])
daemon_control_path_ready = boolean_value(diagnose["daemonControlPathReady"])
is_apple_silicon = boolean_value(diagnose["isAppleSilicon"])
is_macbook_pro = boolean_value(diagnose["isMacBookPro"])

blockers = []
blockers << "diagnose did not produce parseable JSON" if parse_error
blockers << "diagnose preflight did not complete successfully" if diagnose_status != 0
if is_apple_silicon != true || is_macbook_pro != true
  blockers << "hardware is not a supported Apple Silicon MacBook Pro"
end
blockers << "diagnose reported safeToRequestCooling is not true" if safe_to_request_cooling != true
blockers << "diagnose reported daemonControlPathReady is not true" if daemon_control_path_ready != true
if manual_control_active == true
  blockers << "manual control active before manual smoke"
elsif manual_control_active != false
  blockers << "diagnose did not report manualControlActive=false"
end
blockers << "diagnose reported no controllable fans" if controllable_fan_count.nil? || controllable_fan_count < 1
blockers << "diagnose reported no temperature sensors" if temperature_sensor_count.nil? || temperature_sensor_count < 1
blockers << "thermal pressure is critical" if thermal_pressure == "critical"
unless %w[requestCooling requestCoolingWithCaution].include?(recommended_action)
  blockers << "diagnose recommended action is not requestCooling or requestCoolingWithCaution"
end

ready = blockers.empty?
status = ready ? "ready" : "blocked"
next_action = if ready
  "Capture baseline diagnose/probe evidence, run one human-supervised conservative Fixed smoke, restore Auto, then repeat with one conservative Curve smoke."
elsif recommended_recovery == "restoreAutoBeforeRetry"
  "Restore Auto in Vifty, wait until manualControlActive=false, then rerun this preflight before any smoke test."
elsif recommended_recovery == "repairHelper"
  "Repair or reinstall the helper, approve Login Items if prompted, then rerun diagnose and this preflight."
else
  "Do not run manual fan-write smoke. Collect read-only validation evidence and clear the listed blockers first."
end

summary = {
  "kind" => "vifty-manual-smoke-readiness",
  "schemaVersion" => 1,
  "status" => status,
  "manualSmokeReady" => ready,
  "readOnly" => true,
  "coolingCommandsRun" => false,
  "diagnoseExitStatus" => diagnose_status,
  "modelIdentifier" => diagnose["modelIdentifier"],
  "state" => diagnose["state"],
  "recommendedAgentAction" => recommended_action.empty? ? nil : recommended_action,
  "recommendedRecoveryAction" => recommended_recovery.empty? ? nil : recommended_recovery,
  "safeToRequestCooling" => safe_to_request_cooling,
  "daemonControlPathReady" => daemon_control_path_ready,
  "manualControlActive" => manual_control_active,
  "isAppleSilicon" => is_apple_silicon,
  "isMacBookPro" => is_macbook_pro,
  "fanCount" => fan_count,
  "controllableFanCount" => controllable_fan_count,
  "temperatureSensorCount" => temperature_sensor_count,
  "thermalPressure" => thermal_pressure.empty? ? nil : thermal_pressure,
  "failedCheckIDs" => array_value(diagnose["failedCheckIDs"]),
  "coolingBlockerIDs" => array_value(diagnose["coolingBlockerIDs"]),
  "appPreferences" => {
    "startupMode" => app_preferences["startupMode"],
    "startupModeSource" => app_preferences["startupModeSource"],
    "readError" => app_preferences["readError"]
  },
  "blockers" => blockers,
  "nextAction" => next_action,
  "parseError" => parse_error
}

if json_output
  puts JSON.pretty_generate(summary)
else
  puts "Manual smoke readiness: #{status}"
  if ready
    puts "Read-only preflight passed; no cooling command was run."
  else
    puts "Do not run manual Fixed/Curve fan-write smoke."
    puts "Blockers:"
    blockers.each { |blocker| puts "- #{blocker}" }
  end

  puts "State: #{summary["state"] || "unknown"}"
  puts "Model: #{summary["modelIdentifier"] || "unknown"}"
  puts "safeToRequestCooling=#{safe_to_request_cooling.inspect} daemonControlPathReady=#{daemon_control_path_ready.inspect} manualControlActive=#{manual_control_active.inspect}"
  if app_preferences["startupMode"] || app_preferences["startupModeSource"]
    mode = app_preferences["startupMode"] || "unknown"
    source = app_preferences["startupModeSource"] || "unknown"
    puts "Startup mode: #{mode} (#{source})"
  end
  puts "Next action: #{next_action}"
end

exit(ready ? 0 : 75)
RUBY
