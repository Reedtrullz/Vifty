#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/check-agent-run-smoke-readiness.sh [options]

Run a read-only preflight before supervised viftyctl run smoke evidence.

Options:
  --viftyctl <path>          viftyctl path (default:
                             /Applications/Vifty.app/Contents/MacOS/viftyctl)
  --duration <duration>      Smoke lease duration, e.g. 2m (default: 2m)
  --max-rpm-percent <count>  Max RPM percent for smoke run, 1 through 100
                             (default: 55)
  --reason <text>            Audit reason (default: agent run smoke test)
  --expected-daemon <path>   Hash the daemon binary expected to service a
                             current-build smoke run.
  --require-daemon-match     Block unless the installed helper daemon hash
                             matches --expected-daemon.
  --json                     Print the readiness summary as JSON instead of prose.
  --summary <path>           Write the readiness summary JSON to this path,
                             creating parent directories when needed.
  -h, --help                 Show this help.

This script only runs:
  viftyctl capabilities --json
  viftyctl diagnose --json

It may also hash the installed LaunchDaemon helper and --expected-daemon when
provided. It does not call prepare, run, restore-auto, ViftyHelper, sudo, or raw
SMC tools. Exit 0 means the supervised agent-run smoke collector may proceed.
Exit 75 means the smoke collector must be skipped until the printed blockers
are cleared. JSON output uses schemaID:
  https://vifty.local/schemas/agent-run-smoke-readiness.schema.json
USAGE
}

VIFTYCTL="${VIFTYCTL:-/Applications/Vifty.app/Contents/MacOS/viftyctl}"
DURATION="${VIFTY_AGENT_RUN_SMOKE_DURATION:-2m}"
MAX_RPM_PERCENT="${VIFTY_AGENT_RUN_SMOKE_MAX_RPM_PERCENT:-55}"
REASON="${VIFTY_AGENT_RUN_SMOKE_REASON:-agent run smoke test}"
EXPECTED_DAEMON_PATH="${VIFTY_AGENT_RUN_SMOKE_EXPECTED_DAEMON:-}"
REQUIRE_DAEMON_MATCH="${VIFTY_AGENT_RUN_SMOKE_REQUIRE_DAEMON_MATCH:-0}"
INSTALLED_DAEMON_PATH="${VIFTY_AGENT_RUN_SMOKE_INSTALLED_DAEMON_PATH:-/Library/PrivilegedHelperTools/tech.reidar.vifty.daemon}"
JSON_OUTPUT=0
SUMMARY_PATH="${VIFTY_AGENT_RUN_SMOKE_READINESS_SUMMARY:-}"

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
    --duration)
      if [[ $# -lt 2 ]]; then
        echo "error: --duration requires a value" >&2
        exit 64
      fi
      DURATION="$2"
      shift 2
      ;;
    --max-rpm-percent)
      if [[ $# -lt 2 ]]; then
        echo "error: --max-rpm-percent requires a count" >&2
        exit 64
      fi
      MAX_RPM_PERCENT="$2"
      shift 2
      ;;
    --reason)
      if [[ $# -lt 2 ]]; then
        echo "error: --reason requires text" >&2
        exit 64
      fi
      REASON="$2"
      shift 2
      ;;
    --expected-daemon)
      if [[ $# -lt 2 ]]; then
        echo "error: --expected-daemon requires a path" >&2
        exit 64
      fi
      EXPECTED_DAEMON_PATH="$2"
      shift 2
      ;;
    --require-daemon-match)
      REQUIRE_DAEMON_MATCH=1
      shift
      ;;
    --json)
      JSON_OUTPUT=1
      shift
      ;;
    --summary)
      if [[ $# -lt 2 ]]; then
        echo "error: --summary requires a path" >&2
        exit 64
      fi
      SUMMARY_PATH="$2"
      shift 2
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

if [[ ! "${MAX_RPM_PERCENT}" =~ ^[0-9]+$ ]] || [[ "${MAX_RPM_PERCENT}" -lt 1 ]] || [[ "${MAX_RPM_PERCENT}" -gt 100 ]]; then
  echo "error: --max-rpm-percent must be an integer from 1 through 100" >&2
  exit 64
fi

if [[ ! "${DURATION}" =~ ^[0-9]+[mh]$ ]]; then
  echo "error: --duration must be a positive minute/hour value like 2m or 1h" >&2
  exit 64
fi

if [[ ! "${DURATION%[mh]}" =~ ^[0-9]+$ ]] || [[ "${DURATION%[mh]}" -lt 1 ]]; then
  echo "error: --duration must be greater than zero" >&2
  exit 64
fi

if [[ -z "${REASON//[[:space:]]/}" ]]; then
  echo "error: --reason cannot be blank" >&2
  exit 64
fi

case "${REQUIRE_DAEMON_MATCH}" in
  1|true|yes)
    REQUIRE_DAEMON_MATCH=1
    ;;
  0|false|no)
    REQUIRE_DAEMON_MATCH=0
    ;;
  *)
    echo "error: VIFTY_AGENT_RUN_SMOKE_REQUIRE_DAEMON_MATCH must be 0 or 1" >&2
    exit 64
    ;;
esac

if [[ "${REQUIRE_DAEMON_MATCH}" -eq 1 && -z "${EXPECTED_DAEMON_PATH}" ]]; then
  echo "error: --require-daemon-match requires --expected-daemon" >&2
  exit 64
fi

if [[ -n "${EXPECTED_DAEMON_PATH}" && ! -f "${EXPECTED_DAEMON_PATH}" ]]; then
  echo "error: expected daemon not found: ${EXPECTED_DAEMON_PATH}" >&2
  exit 66
fi

if [[ ! -x "${VIFTYCTL}" ]]; then
  echo "error: viftyctl is not executable: ${VIFTYCTL}" >&2
  exit 69
fi

INSTALLED_DAEMON_PRESENT="false"
INSTALLED_DAEMON_SHA256=""
EXPECTED_DAEMON_SHA256=""
DAEMON_MATCHES_EXPECTED="unknown"

if [[ -f "${INSTALLED_DAEMON_PATH}" ]]; then
  INSTALLED_DAEMON_PRESENT="true"
  INSTALLED_DAEMON_SHA256="$(/usr/bin/shasum -a 256 "${INSTALLED_DAEMON_PATH}" | awk '{print $1}')"
fi

if [[ -n "${EXPECTED_DAEMON_PATH}" ]]; then
  EXPECTED_DAEMON_SHA256="$(/usr/bin/shasum -a 256 "${EXPECTED_DAEMON_PATH}" | awk '{print $1}')"
  if [[ -n "${INSTALLED_DAEMON_SHA256}" && "${INSTALLED_DAEMON_SHA256}" == "${EXPECTED_DAEMON_SHA256}" ]]; then
    DAEMON_MATCHES_EXPECTED="true"
  else
    DAEMON_MATCHES_EXPECTED="false"
  fi
fi

CAPABILITIES_JSON="$(mktemp "${TMPDIR:-/tmp}/vifty-agent-run-readiness-capabilities.XXXXXXXX.json")"
CAPABILITIES_STDERR="$(mktemp "${TMPDIR:-/tmp}/vifty-agent-run-readiness-capabilities.XXXXXXXX.stderr")"
DIAGNOSE_JSON="$(mktemp "${TMPDIR:-/tmp}/vifty-agent-run-readiness-diagnose.XXXXXXXX.json")"
DIAGNOSE_STDERR="$(mktemp "${TMPDIR:-/tmp}/vifty-agent-run-readiness-diagnose.XXXXXXXX.stderr")"
trap 'rm -f "${CAPABILITIES_JSON}" "${CAPABILITIES_STDERR}" "${DIAGNOSE_JSON}" "${DIAGNOSE_STDERR}"' EXIT

set +e
if [[ "${VIFTY_TEST_SHELL_FIXTURES:-0}" == "1" ]]; then
  /bin/sh "${VIFTYCTL}" capabilities --json > "${CAPABILITIES_JSON}" 2> "${CAPABILITIES_STDERR}"
else
  "${VIFTYCTL}" capabilities --json > "${CAPABILITIES_JSON}" 2> "${CAPABILITIES_STDERR}"
fi
CAPABILITIES_STATUS=$?

if [[ "${VIFTY_TEST_SHELL_FIXTURES:-0}" == "1" ]]; then
  /bin/sh "${VIFTYCTL}" diagnose --json > "${DIAGNOSE_JSON}" 2> "${DIAGNOSE_STDERR}"
else
  "${VIFTYCTL}" diagnose --json > "${DIAGNOSE_JSON}" 2> "${DIAGNOSE_STDERR}"
fi
DIAGNOSE_STATUS=$?
set -e

ruby -rjson -rfileutils - \
  "${CAPABILITIES_JSON}" \
  "${CAPABILITIES_STATUS}" \
  "${DIAGNOSE_JSON}" \
  "${DIAGNOSE_STATUS}" \
  "${JSON_OUTPUT}" \
  "${DURATION}" \
  "${MAX_RPM_PERCENT}" \
  "${REASON}" \
  "${INSTALLED_DAEMON_PATH}" \
  "${INSTALLED_DAEMON_PRESENT}" \
  "${INSTALLED_DAEMON_SHA256}" \
  "${EXPECTED_DAEMON_PATH}" \
  "${EXPECTED_DAEMON_SHA256}" \
  "${DAEMON_MATCHES_EXPECTED}" \
  "${REQUIRE_DAEMON_MATCH}" \
  "${SUMMARY_PATH}" <<'RUBY'
capabilities_path = ARGV.fetch(0)
capabilities_status = Integer(ARGV.fetch(1))
diagnose_path = ARGV.fetch(2)
diagnose_status = Integer(ARGV.fetch(3))
json_output = ARGV.fetch(4) == "1"
duration = ARGV.fetch(5)
max_rpm_percent = Integer(ARGV.fetch(6))
reason = ARGV.fetch(7)
installed_daemon_path = ARGV.fetch(8)
installed_daemon_present = ARGV.fetch(9) == "true"
installed_daemon_sha256 = ARGV.fetch(10)
expected_daemon_path = ARGV.fetch(11)
expected_daemon_sha256 = ARGV.fetch(12)
daemon_matches_expected_text = ARGV.fetch(13)
daemon_match_required = ARGV.fetch(14) == "1"
summary_path = ARGV.fetch(15)

def parsed_json(path)
  raw = File.read(path)
  [JSON.parse(raw), nil]
rescue JSON::ParserError => error
  [{}, error.message]
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

def duration_seconds(value)
  match = value.match(/\A([0-9]+)([mh])\z/)
  return nil unless match

  number = match[1].to_i
  match[2] == "h" ? number * 3600 : number * 60
end

def strings(value)
  value.is_a?(Array) ? value.map(&:to_s) : []
end

def string_array(value)
  value.is_a?(Array) && value.all? { |item| item.is_a?(String) } ? value : []
end

def share_safe_path(path)
  value = path.to_s
  return [nil, "notProvided"] if value.empty?

  if value.start_with?("/Library/PrivilegedHelperTools/") || value.start_with?("/Applications/Vifty.app/")
    [value, "system"]
  elsif !value.start_with?("/")
    [value, "relative"]
  else
    [File.basename(value), "basenameOnly"]
  end
end

capabilities, capabilities_parse_error = parsed_json(capabilities_path)
diagnose, diagnose_parse_error = parsed_json(diagnose_path)

schema_ids = capabilities["schemaIDs"].is_a?(Hash) ? capabilities["schemaIDs"] : {}
policy = capabilities["policy"].is_a?(Hash) ? capabilities["policy"] : {}
lifecycle = capabilities["runLifecycle"].is_a?(Hash) ? capabilities["runLifecycle"] : {}
metadata_limits = capabilities["metadataLimits"].is_a?(Hash) ? capabilities["metadataLimits"] : {}
wrapper_resources = capabilities["wrapperResources"].is_a?(Hash) ? capabilities["wrapperResources"] : {}
app_preferences = diagnose["appPreferences"].is_a?(Hash) ? diagnose["appPreferences"] : {}

commands = strings(capabilities["commands"])
workloads = strings(capabilities["workloads"])
signals = strings(lifecycle["signalsForwardedToChild"])
workload_scripts = strings(wrapper_resources["workloadScripts"])
expected_workload_scripts = %w[
  bun-build.sh
  bun-test.sh
  cargo-build.sh
  cargo-test.sh
  custom-workload.sh
  go-build.sh
  go-test.sh
  local-model.sh
  make-build.sh
  make-test.sh
  make-verify.sh
  npm-build.sh
  npm-test.sh
  pnpm-build.sh
  pnpm-test.sh
  pytest.sh
  swift-release-build.sh
  swift-test.sh
  uv-build.sh
  uv-test.sh
  xcode-build.sh
  xcode-test.sh
]

capabilities_schema_version = integer_value(capabilities["schemaVersion"])
capabilities_schema_id = schema_ids["capabilities"].is_a?(String) ? schema_ids["capabilities"] : nil
diagnose_schema_id = schema_ids["diagnose"].is_a?(String) ? schema_ids["diagnose"] : nil
command_error_schema_id = schema_ids["commandError"].is_a?(String) ? schema_ids["commandError"] : nil
run_schema_id = schema_ids["run"].is_a?(String) ? schema_ids["run"] : nil
daemon_status_available = boolean_value(capabilities["daemonStatusAvailable"])
policy_status_available = boolean_value(capabilities["policyStatusAvailable"])
policy_source = capabilities["policySource"].is_a?(String) ? capabilities["policySource"] : nil
policy_enabled = boolean_value(policy["enabled"])
supports_force_retry = boolean_value(capabilities["supportsForceRetry"])
max_duration_seconds = integer_value(policy["maxDurationSeconds"])
minimum_agent_rpm_percent = integer_value(policy["minimumAgentRPMPercent"])
maximum_allowed_rpm_percent = integer_value(policy["maximumAllowedRPMPercent"])
maximum_reason_length = integer_value(metadata_limits["maximumReasonLength"])
requested_duration_seconds = duration_seconds(duration)

schema_ids_safe = capabilities_schema_version == 1 &&
  capabilities_schema_id == "https://vifty.local/schemas/viftyctl-capabilities.schema.json" &&
  diagnose_schema_id == "https://vifty.local/schemas/viftyctl-diagnose.schema.json" &&
  command_error_schema_id == "https://vifty.local/schemas/viftyctl-command-error.schema.json" &&
  run_schema_id == "https://vifty.local/schemas/viftyctl-run.schema.json"
run_lifecycle_safe = lifecycle["childCommandPreflightBeforeCooling"] == true &&
  lifecycle["autoRestoreAfterChildExit"] == true &&
  lifecycle["structuredPreChildFailures"] == true &&
  lifecycle["cleanupStateReportedOnLaunchFailure"] == true &&
  lifecycle["resolvedChildExecutableReported"] == true &&
  %w[INT TERM HUP].all? { |signal| signals.include?(signal) }
wrapper_resources_safe = wrapper_resources["sourceDirectory"] == "examples/viftyctl" &&
  wrapper_resources["bundleDirectory"] == "Contents/Resources/viftyctl-wrappers" &&
  wrapper_resources["guardedRunScript"] == "guarded-run.sh" &&
  (expected_workload_scripts - workload_scripts).empty?
metadata_limits_available = maximum_reason_length.is_a?(Integer) && maximum_reason_length > 0
duration_within_policy = max_duration_seconds.is_a?(Integer) &&
  requested_duration_seconds.is_a?(Integer) &&
  requested_duration_seconds <= max_duration_seconds
rpm_within_policy = minimum_agent_rpm_percent.is_a?(Integer) &&
  maximum_allowed_rpm_percent.is_a?(Integer) &&
  max_rpm_percent >= minimum_agent_rpm_percent &&
  max_rpm_percent <= maximum_allowed_rpm_percent
reason_within_metadata_limit = metadata_limits_available && reason.length <= maximum_reason_length

recommended_action = diagnose["recommendedAgentAction"].to_s
recommended_recovery = diagnose["recommendedRecoveryAction"].to_s
recovery_steps = string_array(diagnose["recoverySteps"])
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
blockers << "capabilities did not produce parseable JSON" if capabilities_parse_error
blockers << "capabilities preflight did not complete successfully" if capabilities_status != 0
blockers << "capabilities schema IDs are missing or unsupported" unless schema_ids_safe
blockers << "capabilities are not daemon-backed" if daemon_status_available != true || policy_source != "daemonStatus"
blockers << "capabilities policy status is unavailable" if policy_status_available != true
blockers << "agent cooling policy is disabled" if policy_enabled != true
blockers << "capabilities do not advertise viftyctl run" unless commands.include?("run")
blockers << "capabilities do not advertise the test workload" unless workloads.include?("test")
blockers << "capabilities runLifecycle is missing or unsafe" unless run_lifecycle_safe
blockers << "capabilities wrapperResources are missing or incomplete" unless wrapper_resources_safe
blockers << "capabilities supportsForceRetry is missing" unless [true, false].include?(supports_force_retry)
blockers << "capabilities metadataLimits are missing or unusable" unless metadata_limits_available
blockers << "requested duration exceeds advertised policy maximum" unless duration_within_policy
blockers << "requested max RPM percent is outside advertised policy range" unless rpm_within_policy
blockers << "reason exceeds advertised metadata limit" unless reason_within_metadata_limit
if daemon_match_required && daemon_matches_expected_text != "true"
  blockers << "installed daemon does not match expected build daemon"
end
blockers << "diagnose did not produce parseable JSON" if diagnose_parse_error
blockers << "diagnose preflight did not complete successfully" if diagnose_status != 0
if is_apple_silicon != true || is_macbook_pro != true
  blockers << "hardware is not a supported Apple Silicon MacBook Pro"
end
blockers << "diagnose reported safeToRequestCooling is not true" if safe_to_request_cooling != true
blockers << "diagnose reported daemonControlPathReady is not true" if daemon_control_path_ready != true
if manual_control_active == true
  blockers << "manual control active before smoke run"
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
  "Run make agent-run-smoke-evidence, or make agent-run-smoke-evidence-current-build for clean current-source proof."
elsif daemon_match_required && daemon_matches_expected_text != "true"
  "Install or repair the freshly built app/helper so the LaunchDaemon hash matches, then rerun this preflight before smoke evidence."
elsif recommended_recovery == "restoreAutoBeforeRetry"
  "Restore Auto in Vifty, wait until manualControlActive=false, then rerun this preflight before agent-run smoke."
elsif recommended_recovery == "repairHelper"
  "Repair or reinstall the helper, approve Login Items if prompted, then rerun capabilities, diagnose, and this preflight."
else
  "Do not run supervised agent-run smoke. Collect read-only evidence and clear the listed blockers first."
end

daemon_matches_expected = case daemon_matches_expected_text
when "true" then true
when "false" then false
else nil
end
safe_installed_daemon_path, installed_daemon_path_privacy = share_safe_path(installed_daemon_path)
safe_expected_daemon_path, expected_daemon_path_privacy = share_safe_path(expected_daemon_path)

summary = {
  "kind" => "vifty-agent-run-smoke-readiness",
  "schemaVersion" => 1,
  "schemaID" => "https://vifty.local/schemas/agent-run-smoke-readiness.schema.json",
  "status" => status,
  "agentRunSmokeReady" => ready,
  "readOnly" => true,
  "coolingCommandsRun" => false,
  "duration" => duration,
  "durationSeconds" => requested_duration_seconds,
  "maxRPMPercent" => max_rpm_percent,
  "reason" => "omitted-for-privacy",
  "reasonCharacterCount" => reason.length,
  "reasonPrivacy" => "omitted",
  "capabilitiesExitStatus" => capabilities_status,
  "diagnoseExitStatus" => diagnose_status,
  "modelIdentifier" => diagnose["modelIdentifier"],
  "state" => diagnose["state"],
  "recommendedAgentAction" => recommended_action.empty? ? nil : recommended_action,
  "recommendedRecoveryAction" => recommended_recovery.empty? ? nil : recommended_recovery,
  "recoverySteps" => recovery_steps,
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
  "capabilities" => {
    "schemaVersion" => capabilities_schema_version,
    "capabilitiesSchemaID" => capabilities_schema_id,
    "diagnoseSchemaID" => diagnose_schema_id,
    "commandErrorSchemaID" => command_error_schema_id,
    "runSchemaID" => run_schema_id,
    "daemonStatusAvailable" => daemon_status_available,
    "policySource" => policy_source,
    "policyStatusAvailable" => policy_status_available,
    "policyEnabled" => policy_enabled,
    "supportsForceRetry" => supports_force_retry,
    "runCommandAvailable" => commands.include?("run"),
    "testWorkloadAvailable" => workloads.include?("test"),
    "runLifecycleSafe" => run_lifecycle_safe,
    "wrapperResourcesSafe" => wrapper_resources_safe,
    "metadataLimitsAvailable" => metadata_limits_available,
    "requestedDurationWithinPolicy" => duration_within_policy,
    "requestedRPMPercentWithinPolicy" => rpm_within_policy,
    "reasonWithinMetadataLimit" => reason_within_metadata_limit,
    "maxDurationSeconds" => max_duration_seconds,
    "minimumAgentRPMPercent" => minimum_agent_rpm_percent,
    "maximumAllowedRPMPercent" => maximum_allowed_rpm_percent,
    "maximumReasonLength" => maximum_reason_length,
    "resolvedChildExecutableReported" => boolean_value(lifecycle["resolvedChildExecutableReported"])
  },
  "daemonRuntime" => {
    "installedDaemonPath" => safe_installed_daemon_path,
    "installedDaemonPathPrivacy" => installed_daemon_path_privacy,
    "installedDaemonPresent" => installed_daemon_present,
    "installedDaemonSHA256" => installed_daemon_sha256.empty? ? nil : installed_daemon_sha256,
    "expectedDaemonPath" => safe_expected_daemon_path,
    "expectedDaemonPathPrivacy" => expected_daemon_path_privacy,
    "expectedDaemonSHA256" => expected_daemon_sha256.empty? ? nil : expected_daemon_sha256,
    "matchesExpectedDaemon" => daemon_matches_expected,
    "matchRequired" => daemon_match_required
  },
  "blockers" => blockers,
  "nextAction" => next_action,
  "parseErrors" => {
    "capabilities" => capabilities_parse_error,
    "diagnose" => diagnose_parse_error
  }
}

summary_json = JSON.pretty_generate(summary)
unless summary_path.empty?
  parent = File.dirname(summary_path)
  FileUtils.mkdir_p(parent) unless parent == "."
  File.write(summary_path, "#{summary_json}\n")
end

if json_output
  puts summary_json
else
  puts "Agent run smoke readiness: #{status}"
  if ready
    puts "Read-only preflight passed; no cooling command was run."
  else
    puts "Do not run supervised viftyctl run smoke."
    puts "Blockers:"
    blockers.each { |blocker| puts "- #{blocker}" }
    unless recovery_steps.empty?
      puts "Recovery steps:"
      recovery_steps.each { |step| puts "- #{step}" }
    end
  end

  puts "State: #{summary["state"] || "unknown"}"
  puts "Model: #{summary["modelIdentifier"] || "unknown"}"
  puts "safeToRequestCooling=#{safe_to_request_cooling.inspect} daemonControlPathReady=#{daemon_control_path_ready.inspect} manualControlActive=#{manual_control_active.inspect}"
  puts "capabilities: daemonStatusAvailable=#{daemon_status_available.inspect} policyStatusAvailable=#{policy_status_available.inspect} policyEnabled=#{policy_enabled.inspect} runLifecycleSafe=#{run_lifecycle_safe.inspect}"
  puts "request: duration=#{duration} maxRPMPercent=#{max_rpm_percent}"
  if app_preferences["startupMode"] || app_preferences["startupModeSource"]
    mode = app_preferences["startupMode"] || "unknown"
    source = app_preferences["startupModeSource"] || "unknown"
    puts "Startup mode: #{mode} (#{source})"
  end
  if daemon_match_required || !expected_daemon_path.empty?
    match = daemon_matches_expected.nil? ? "unknown" : daemon_matches_expected.to_s
    puts "Daemon match: #{match} (required=#{daemon_match_required})"
  end
  puts "Next action: #{next_action}"
end

exit(ready ? 0 : 75)
RUBY
