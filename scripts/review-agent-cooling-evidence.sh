#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/review-agent-cooling-evidence.sh --bundle <dir> [--summary <path>]

Reviews a read-only agent/helper support evidence bundle created by
scripts/collect-agent-cooling-evidence.sh.
EOF
}

BUNDLE=""
SUMMARY_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --bundle requires a directory" >&2
        usage
        exit 64
      fi
      BUNDLE="$2"
      shift 2
      ;;
    --summary)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "error: --summary requires a path" >&2
        usage
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
      usage
      exit 64
      ;;
  esac
done

if [[ -z "${BUNDLE}" ]]; then
  echo "error: --bundle is required" >&2
  usage
  exit 64
fi

if [[ ! -d "${BUNDLE}" ]]; then
  echo "error: bundle directory not found: ${BUNDLE}" >&2
  exit 66
fi

ruby - "${BUNDLE}" "${SUMMARY_PATH}" <<'RUBY'
require "csv"
require "digest"
require "fileutils"
require "json"
require "time"

bundle = File.expand_path(ARGV.fetch(0))
summary_path = ARGV.fetch(1, "").to_s
summary_path = summary_path.empty? ? nil : File.expand_path(summary_path)

EXPECTED_SCHEMA_ID = "https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json"
REVIEW_SCHEMA_ID = "https://vifty.local/schemas/agent-cooling-evidence-review.schema.json"
CAPABILITIES_SCHEMA_ID = "https://vifty.local/schemas/viftyctl-capabilities.schema.json"
DIAGNOSE_SCHEMA_ID = "https://vifty.local/schemas/viftyctl-diagnose.schema.json"
COMMAND_ERROR_SCHEMA_ID = "https://vifty.local/schemas/viftyctl-command-error.schema.json"
RUN_SCHEMA_ID = "https://vifty.local/schemas/viftyctl-run.schema.json"
GUARDED_RUN_DECISION_SCHEMA_ID = "https://vifty.local/schemas/guarded-run-decision.schema.json"
DIAGNOSE_STATES = %w[ready degraded blocked].freeze
DIAGNOSE_AGENT_ACTIONS = %w[
  requestCooling
  requestCoolingWithCaution
  restoreAutoBeforeRequestingCooling
  doNotRequestCooling
].freeze
DIAGNOSE_RECOVERY_ACTIONS = %w[
  none
  repairHelper
  restoreAutoBeforeRetry
  backOffWorkload
  inspectPolicy
  collectHardwareEvidence
].freeze
STARTUP_MODES = %w[Auto Curve Fixed].freeze
GUARDED_RUN_DECISION_REASONS = %w[
  readinessBlocked
  safeToRequestCoolingFalse
  daemonControlPathNotReady
  manualControlActive
  coolingBlockersPresent
  recoveryActionBlocksUncooledFallback
  preflightReady
  uncooledFallbackAllowed
  unknownNoCoolingDecision
].freeze
STARTUP_MODE_SOURCES = %w[
  persisted
  defaultMissingFile
  defaultMissingKey
  unreadable
  unavailable
].freeze
REQUIRED_FILES = %w[
  agent-cooling-evidence-summary.json
  manifest.tsv
  checksums.tsv
  privacy-review.tsv
].freeze
REQUIRED_COMMANDS = %w[
  viftyctl-capabilities
  viftyctl-diagnose
  viftyctl-status
  viftyctl-audit
  launchctl-print-daemon
  launchdaemon-plist
  helper-file-metadata
  app-info-plist
  privacy-review
].freeze

failures = []
warnings = []
diagnose_decision = {
  "exitStatus" => nil,
  "state" => nil,
  "recommendedAgentAction" => nil,
  "recommendedRecoveryAction" => nil,
  "safeToRequestCooling" => nil,
  "daemonControlPathReady" => nil,
  "manualControlActive" => nil,
  "failedCheckIDs" => [],
  "coolingBlockerIDs" => [],
  "appPreferences" => {
    "startupMode" => nil,
    "startupModeSource" => nil,
    "readError" => nil
  }
}
capabilities_decision = {
  "exitStatus" => nil,
  "schemaVersion" => nil,
  "capabilitiesSchemaID" => nil,
  "diagnoseSchemaID" => nil,
  "commandErrorSchemaID" => nil,
  "runSchemaID" => nil,
  "daemonStatusAvailable" => nil,
  "policySource" => nil,
  "policyStatusAvailable" => nil,
  "policyEnabled" => nil,
  "supportsRunCommand" => false,
  "supportsForceRetry" => nil,
  "runLifecycleSafe" => false,
  "directControlLifecycleSafe" => false,
  "metadataLimitsPresent" => false,
  "unavailableExitCode" => nil
}
app_info = {
  "exitStatus" => nil,
  "bundleIdentifier" => nil,
  "shortVersion" => nil,
  "bundleVersion" => nil
}
guarded_run_decision = {
  "present" => false,
  "sourceFile" => nil,
  "schemaVersion" => nil,
  "schemaID" => nil,
  "safeToProceed" => nil,
  "coolingRequested" => nil,
  "uncooledFallbackRequested" => nil,
  "uncooledFallbackAllowed" => nil,
  "decisionReason" => nil,
  "exitCode" => nil,
  "message" => nil,
  "recommendedAgentAction" => nil,
  "recommendedRecoveryAction" => nil,
  "diagnoseState" => nil,
  "safeToRequestCooling" => nil,
  "daemonControlPathReady" => nil,
  "manualControlActive" => nil,
  "startupMode" => nil,
  "failedCheckIDs" => [],
  "coolingBlockerIDs" => [],
  "requestedWorkload" => nil,
  "requestedDuration" => nil,
  "requestedMaxRPMPercent" => nil,
  "reasonCharacterCount" => nil,
  "childCommandName" => nil,
  "childCommandKind" => nil,
  "childArgumentCount" => nil
}
accepted_command_errors = []

def bundle_entry?(value)
  value.is_a?(String) &&
    !value.empty? &&
    value == File.basename(value) &&
    value != "." &&
    value != ".."
end

def read_json(path, failures, label)
  unless File.file?(path)
    failures << "missing #{label}: #{File.basename(path)}"
    return nil
  end

  JSON.parse(File.read(path))
rescue JSON::ParserError => error
  failures << "invalid #{label} JSON: #{error.message}"
  nil
end

def parse_tsv(path, failures, label)
  unless File.file?(path)
    failures << "missing #{label}: #{File.basename(path)}"
    return []
  end

  rows = CSV.read(path, col_sep: "\t", headers: true)
  unless rows.headers
    failures << "#{label} is missing a header row"
    return []
  end

  rows.map(&:to_h)
rescue CSV::MalformedCSVError => error
  failures << "invalid #{label} TSV: #{error.message}"
  []
end

def integer_value(value)
  return value if value.is_a?(Integer)
  return nil if value.nil?

  Integer(value.to_s, exception: false)
end

def boolean?(value)
  value == true || value == false
end

def string_array?(value)
  value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) }
end

def optional_string?(value)
  value.nil? || value.is_a?(String)
end

def includes_all?(array, values)
  array.is_a?(Array) && values.all? { |value| array.include?(value) }
end

def command_error_report?(bundle, command_name, failures, expected_command:, expected_error_code:, expected_recovery_action:)
  path = File.join(bundle, "#{command_name}.json")
  unless File.file?(path)
    failures << "#{command_name}.json is missing for nonzero command review"
    return false
  end

  begin
    data = JSON.parse(File.read(path))
  rescue JSON::ParserError => error
    failures << "invalid #{command_name}.json command-error JSON: #{error.message}"
    return false
  end

  unless data.is_a?(Hash)
    failures << "#{command_name}.json command-error must contain a JSON object"
    return false
  end

  ok = true
  checks = {
    "schemaVersion" => 1,
    "schemaID" => COMMAND_ERROR_SCHEMA_ID,
    "command" => expected_command,
    "errorCode" => expected_error_code,
    "safeToProceed" => false,
    "recommendedRecoveryAction" => expected_recovery_action,
    "coolingLeasePrepared" => false,
    "autoRestoreAttempted" => false
  }
  checks.each do |field, expected|
    next if data[field] == expected

    failures << "#{command_name}.json command-error #{field} #{data[field].inspect} did not match #{expected.inspect}"
    ok = false
  end
  if data["autoRestoreSucceeded"] != nil
    failures << "#{command_name}.json command-error autoRestoreSucceeded must be null"
    ok = false
  end
  unless data["message"].is_a?(String) && !data["message"].strip.empty?
    failures << "#{command_name}.json command-error message must be nonempty"
    ok = false
  end

  ok
end

def helper_repair_diagnose?(diagnose_decision)
  diagnose_decision["exitStatus"] == 75 &&
    diagnose_decision["state"] == "blocked" &&
    diagnose_decision["recommendedAgentAction"] == "doNotRequestCooling" &&
    diagnose_decision["recommendedRecoveryAction"] == "repairHelper" &&
    diagnose_decision["safeToRequestCooling"] == false &&
    diagnose_decision["daemonControlPathReady"] == false
end

def infer_daemon_control_path_ready(state, agent_action, recovery_action, safe_to_request)
  if %w[ready degraded].include?(state) &&
      %w[requestCooling requestCoolingWithCaution].include?(agent_action) &&
      safe_to_request == true &&
      recovery_action != "repairHelper"
    return true
  end

  if state == "blocked" &&
      agent_action == "doNotRequestCooling" &&
      safe_to_request == false &&
      recovery_action == "repairHelper"
    return false
  end

  nil
end

def plutil_string_value(text, key)
  match = text.match(/^\s*"#{Regexp.escape(key)}"\s*=>\s*"([^"]*)"\s*$/)
  match && match[1]
end

def share_safe_bundle_path(bundle)
  File.basename(File.expand_path(bundle.to_s))
end

def extract_guarded_run_decision_json(text, failures)
  begin_marker = "guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON"
  end_marker = "guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON"
  begin_count = text.scan(/^#{Regexp.escape(begin_marker)}$/).length
  end_count = text.scan(/^#{Regexp.escape(end_marker)}$/).length

  if begin_count != 1 || end_count != 1
    failures << "guarded-run-stderr.txt must contain exactly one guarded-run decision JSON marker pair"
    return nil
  end

  match = text.match(/^#{Regexp.escape(begin_marker)}\n(?<json>.*?)^#{Regexp.escape(end_marker)}$/m)
  unless match
    failures << "guarded-run-stderr.txt decision JSON markers are malformed"
    return nil
  end

  JSON.parse(match[:json])
rescue JSON::ParserError => error
  failures << "invalid guarded-run decision JSON: #{error.message}"
  nil
end

def write_review_summary(summary_path, bundle, status, read_only, cooling_commands_run, commands_reviewed, diagnose_decision, capabilities_decision, app_info, guarded_run_decision, accepted_command_errors, failures, warnings)
  return unless summary_path

  FileUtils.mkdir_p(File.dirname(summary_path))
  review = {
    "schemaVersion" => 1,
    "schemaID" => REVIEW_SCHEMA_ID,
    "generatedAtUTC" => Time.now.utc.iso8601,
    "bundlePath" => share_safe_bundle_path(bundle),
    "status" => status,
    "readOnly" => read_only,
    "coolingCommandsRun" => cooling_commands_run,
    "commandsReviewed" => commands_reviewed,
    "diagnoseDecision" => diagnose_decision,
    "capabilitiesDecision" => capabilities_decision,
    "appInfo" => app_info,
    "guardedRunDecision" => guarded_run_decision,
    "acceptedCommandErrors" => accepted_command_errors,
    "failures" => failures,
    "warnings" => warnings
  }
  File.write(summary_path, "#{JSON.pretty_generate(review)}\n")
end

REQUIRED_FILES.each do |entry|
  failures << "missing required file: #{entry}" unless File.file?(File.join(bundle, entry))
end

summary = read_json(File.join(bundle, "agent-cooling-evidence-summary.json"), failures, "agent evidence summary")
manifest_rows = parse_tsv(File.join(bundle, "manifest.tsv"), failures, "manifest")
checksum_rows = parse_tsv(File.join(bundle, "checksums.tsv"), failures, "checksums")
privacy_rows = parse_tsv(File.join(bundle, "privacy-review.tsv"), failures, "privacy review")

commands = []
read_only = false
cooling_commands_run = true

if summary.is_a?(Hash)
  failures << "summary schemaVersion must be 1" unless summary["schemaVersion"] == 1
  failures << "summary schemaID must be #{EXPECTED_SCHEMA_ID}" unless summary["schemaID"] == EXPECTED_SCHEMA_ID
  failures << "summary readOnly must be true" unless summary["readOnly"] == true
  failures << "summary coolingCommandsRun must be false" unless summary["coolingCommandsRun"] == false

  audit_limit = integer_value(summary["auditLimit"])
  failures << "summary auditLimit must be an integer from 1 through 200" unless audit_limit && audit_limit.between?(1, 200)

  commands = summary["commands"] if summary["commands"].is_a?(Array)
  failures << "summary commands must be a nonempty array" if commands.empty?

  read_only = summary["readOnly"] == true
  cooling_commands_run = summary["coolingCommandsRun"] == true
end

manifest_by_name = {}
manifest_rows.each do |row|
  name = row["name"]
  if manifest_by_name.key?(name)
    failures << "manifest has duplicate command row: #{name}"
  else
    manifest_by_name[name] = row
  end
end

commands_by_name = {}
commands.each do |command|
  unless command.is_a?(Hash)
    failures << "summary commands must contain objects"
    next
  end

  name = command["name"]
  unless bundle_entry?(name)
    failures << "summary command has invalid name: #{name.inspect}"
    next
  end

  if commands_by_name.key?(name)
    failures << "summary commands contain duplicate name: #{name}"
  else
    commands_by_name[name] = command
  end
end

REQUIRED_COMMANDS.each do |name|
  failures << "summary is missing required command: #{name}" unless commands_by_name.key?(name)
  failures << "manifest is missing required command: #{name}" unless manifest_by_name.key?(name)
end

commands_by_name.each do |name, command|
  status = integer_value(command["status"])
  stdout_name = command["stdout"]
  stderr_name = command["stderr"]
  status_name = command["statusFile"]

  failures << "summary command #{name} has non-integer status" unless status
  failures << "summary command #{name} statusFile must be #{name}.status" unless status_name == "#{name}.status"

  [["stdout", stdout_name], ["stderr", stderr_name], ["statusFile", status_name]].each do |field, file_name|
    unless bundle_entry?(file_name)
      failures << "summary command #{name} has invalid #{field}: #{file_name.inspect}"
      next
    end
    failures << "summary command #{name} #{field} file is missing: #{file_name}" unless File.file?(File.join(bundle, file_name))
  end

  manifest = manifest_by_name[name]
  next unless manifest

  manifest_status = integer_value(manifest["status"])
  failures << "manifest command #{name} has non-integer status" unless manifest_status
  failures << "manifest/summary status drift for #{name}" if status && manifest_status && status != manifest_status
  failures << "manifest/summary stdout drift for #{name}" unless manifest["stdout"] == stdout_name
  failures << "manifest/summary stderr drift for #{name}" unless manifest["stderr"] == stderr_name

  status_file = File.join(bundle, "#{name}.status")
  if File.file?(status_file) && status
    status_file_value = integer_value(File.read(status_file).strip)
    if status_file_value
      failures << "status-file/summary drift for #{name}" unless status_file_value == status
    else
      failures << "status file for #{name} is not an integer"
    end
  end
end

capabilities_status = integer_value(commands_by_name.dig("viftyctl-capabilities", "status"))
capabilities_decision["exitStatus"] = capabilities_status
capabilities_path = File.join(bundle, "viftyctl-capabilities.json")
if File.file?(capabilities_path)
  begin
    capabilities = JSON.parse(File.read(capabilities_path))
    unless capabilities.is_a?(Hash)
      failures << "viftyctl-capabilities.json must contain a JSON object"
    else
      schema_version = capabilities["schemaVersion"]
      capabilities_schema_id = capabilities.dig("schemaIDs", "capabilities")
      diagnose_schema_id = capabilities.dig("schemaIDs", "diagnose")
      command_error_schema_id = capabilities.dig("schemaIDs", "commandError")
      run_schema_id = capabilities.dig("schemaIDs", "run")
      capabilities_commands = capabilities["commands"]
      workloads = capabilities["workloads"]
      daemon_status_available = capabilities["daemonStatusAvailable"]
      policy_source = capabilities["policySource"]
      policy_status_available = capabilities["policyStatusAvailable"]
      policy_enabled = capabilities.dig("policy", "enabled")
      supports_force_retry = capabilities["supportsForceRetry"]
      unavailable_exit_code = integer_value(capabilities.dig("exitCodes", "unavailable"))
      run_lifecycle = capabilities["runLifecycle"]
      direct_lifecycle = capabilities["directControlLifecycle"]
      metadata_limits = capabilities["metadataLimits"]
      metadata_limits_present = capabilities.key?("metadataLimits")

      capabilities_decision["schemaVersion"] = schema_version if schema_version.is_a?(Integer)
      capabilities_decision["capabilitiesSchemaID"] = capabilities_schema_id if capabilities_schema_id.is_a?(String)
      capabilities_decision["diagnoseSchemaID"] = diagnose_schema_id if diagnose_schema_id.is_a?(String)
      capabilities_decision["commandErrorSchemaID"] = command_error_schema_id if command_error_schema_id.is_a?(String)
      capabilities_decision["runSchemaID"] = run_schema_id if run_schema_id.is_a?(String)
      capabilities_decision["daemonStatusAvailable"] = daemon_status_available if boolean?(daemon_status_available)
      capabilities_decision["policySource"] = policy_source if %w[daemonStatus fallbackUnavailable].include?(policy_source)
      capabilities_decision["policyStatusAvailable"] = policy_status_available if boolean?(policy_status_available)
      capabilities_decision["policyEnabled"] = policy_enabled if boolean?(policy_enabled)
      capabilities_decision["supportsRunCommand"] = includes_all?(capabilities_commands, %w[run])
      capabilities_decision["supportsForceRetry"] = supports_force_retry if boolean?(supports_force_retry)
      capabilities_decision["unavailableExitCode"] = unavailable_exit_code

      failures << "viftyctl-capabilities.json schemaVersion must be 1" unless schema_version == 1
      failures << "viftyctl-capabilities.json schemaIDs.capabilities must be #{CAPABILITIES_SCHEMA_ID}" unless capabilities_schema_id == CAPABILITIES_SCHEMA_ID
      failures << "viftyctl-capabilities.json schemaIDs.diagnose must be #{DIAGNOSE_SCHEMA_ID}" unless diagnose_schema_id == DIAGNOSE_SCHEMA_ID
      failures << "viftyctl-capabilities.json schemaIDs.commandError must be #{COMMAND_ERROR_SCHEMA_ID}" unless command_error_schema_id == COMMAND_ERROR_SCHEMA_ID
      failures << "viftyctl-capabilities.json schemaIDs.run must be #{RUN_SCHEMA_ID}" unless run_schema_id == RUN_SCHEMA_ID
      failures << "viftyctl-capabilities.json commands must include run" unless capabilities_decision["supportsRunCommand"]
      failures << "viftyctl-capabilities.json commands must include core read-only and cooling commands" unless includes_all?(capabilities_commands, %w[capabilities diagnose status audit prepare restore-auto run])
      failures << "viftyctl-capabilities.json workloads must include build, test, and custom" unless includes_all?(workloads, %w[build test custom])
      failures << "viftyctl-capabilities.json daemonStatusAvailable must be boolean" unless boolean?(daemon_status_available)
      failures << "viftyctl-capabilities.json policySource is missing or unsupported" unless %w[daemonStatus fallbackUnavailable].include?(policy_source)
      failures << "viftyctl-capabilities.json policyStatusAvailable must be boolean" unless boolean?(policy_status_available)
      failures << "viftyctl-capabilities.json policy.enabled must be boolean" unless boolean?(policy_enabled)
      failures << "viftyctl-capabilities.json supportsForceRetry must be boolean" unless boolean?(supports_force_retry)
      failures << "viftyctl-capabilities.json exitCodes.unavailable must be an integer" unless unavailable_exit_code

      if capabilities_status == 0 && daemon_status_available != true
        failures << "successful capabilities review requires daemonStatusAvailable true"
      end
      if capabilities_status == 0 && policy_source != "daemonStatus"
        failures << "successful capabilities review requires policySource daemonStatus"
      end
      if capabilities_status == 0 && policy_status_available != true
        failures << "successful capabilities review requires policyStatusAvailable true"
      end
      if capabilities_status == 0 && policy_enabled != true
        failures << "successful capabilities review requires policy.enabled true"
      end
      if capabilities_status && capabilities_status != 0 && unavailable_exit_code && capabilities_status != unavailable_exit_code
        failures << "nonzero capabilities exit must match exitCodes.unavailable"
      end
      if capabilities_status && capabilities_status != 0 && daemon_status_available != false
        failures << "nonzero capabilities exit requires daemonStatusAvailable false"
      end
      if capabilities_status && capabilities_status != 0 && policy_source != "fallbackUnavailable"
        failures << "nonzero capabilities exit requires policySource fallbackUnavailable"
      end
      if capabilities_status && capabilities_status != 0 && policy_status_available != false
        failures << "nonzero capabilities exit requires policyStatusAvailable false"
      end

      run_safe = run_lifecycle.is_a?(Hash) &&
        run_lifecycle["childCommandPreflightBeforeCooling"] == true &&
        run_lifecycle["autoRestoreAfterChildExit"] == true &&
        run_lifecycle["structuredPreChildFailures"] == true &&
        run_lifecycle["cleanupStateReportedOnLaunchFailure"] == true &&
        run_lifecycle["resolvedChildExecutableReported"] == true &&
        includes_all?(run_lifecycle["signalsForwardedToChild"], %w[INT TERM HUP])
      capabilities_decision["runLifecycleSafe"] = run_safe
      failures << "viftyctl-capabilities.json runLifecycle is missing or unsafe" unless run_safe

      direct_safe = direct_lifecycle.is_a?(Hash) &&
        direct_lifecycle["prepareUsesIdempotencyKey"] == true &&
        direct_lifecycle["restoreAutoAcceptsIdempotencyKey"] == false &&
        direct_lifecycle["restoreAutoScopedByIdempotencyKey"] == false &&
        direct_lifecycle["preferRunForSingleChildWorkloads"] == true
      capabilities_decision["directControlLifecycleSafe"] = direct_safe
      failures << "viftyctl-capabilities.json directControlLifecycle is missing or unsafe" unless direct_safe

      reason_limit = metadata_limits.is_a?(Hash) ? integer_value(metadata_limits["maximumReasonLength"]) : nil
      idempotency_key_limit = metadata_limits.is_a?(Hash) ? integer_value(metadata_limits["maximumIdempotencyKeyLength"]) : nil
      metadata_present = metadata_limits.is_a?(Hash) &&
        reason_limit &&
        reason_limit.positive? &&
        idempotency_key_limit &&
        idempotency_key_limit.positive?
      capabilities_decision["metadataLimitsPresent"] = metadata_present
      if metadata_limits_present
        failures << "viftyctl-capabilities.json metadataLimits are invalid" unless metadata_present
      else
        warnings << "viftyctl-capabilities.json is missing metadataLimits; accepted as legacy read-only evidence"
      end
    end
  rescue JSON::ParserError => error
    failures << "invalid viftyctl-capabilities.json: #{error.message}"
  end
else
  failures << "missing viftyctl-capabilities.json"
end

diagnose_status = integer_value(commands_by_name.dig("viftyctl-diagnose", "status"))
diagnose_decision["exitStatus"] = diagnose_status
unless [0, 75].include?(diagnose_status)
  failures << "viftyctl-diagnose must exit 0 or 75 for reviewed read-only evidence"
end
warnings << "viftyctl-diagnose exited 75; blocked readiness is accepted as evidence" if diagnose_status == 75

diagnose_path = File.join(bundle, "viftyctl-diagnose.json")
if File.file?(diagnose_path)
  begin
    diagnose = JSON.parse(File.read(diagnose_path))
    unless diagnose.is_a?(Hash)
      failures << "viftyctl-diagnose.json must contain a JSON object"
    else
      state = diagnose["state"]
      agent_action = diagnose["recommendedAgentAction"]
      recovery_action = diagnose["recommendedRecoveryAction"]
      safe_to_request = diagnose["safeToRequestCooling"]
      daemon_ready = diagnose["daemonControlPathReady"]
      daemon_ready_present = diagnose.key?("daemonControlPathReady")
      manual_control_active = diagnose["manualControlActive"]
      manual_control_active_present = diagnose.key?("manualControlActive")
      failed_check_ids = diagnose["failedCheckIDs"]
      failed_check_ids_present = diagnose.key?("failedCheckIDs")
      cooling_blocker_ids = diagnose["coolingBlockerIDs"]
      cooling_blocker_ids_present = diagnose.key?("coolingBlockerIDs")
      app_preferences = diagnose["appPreferences"]
      app_preferences_present = diagnose.key?("appPreferences")

      diagnose_decision["state"] = state if DIAGNOSE_STATES.include?(state)
      diagnose_decision["recommendedAgentAction"] = agent_action if DIAGNOSE_AGENT_ACTIONS.include?(agent_action)
      diagnose_decision["recommendedRecoveryAction"] = recovery_action if DIAGNOSE_RECOVERY_ACTIONS.include?(recovery_action)
      diagnose_decision["safeToRequestCooling"] = safe_to_request if [true, false].include?(safe_to_request)
      diagnose_decision["manualControlActive"] = manual_control_active if [true, false].include?(manual_control_active)
      if failed_check_ids_present
        if string_array?(failed_check_ids)
          diagnose_decision["failedCheckIDs"] = failed_check_ids
        else
          failures << "viftyctl-diagnose.json failedCheckIDs must be an array of strings"
        end
      else
        warnings << "viftyctl-diagnose.json is missing failedCheckIDs; legacy reports may require checks[] parsing for failed readiness IDs"
      end
      if cooling_blocker_ids_present
        if string_array?(cooling_blocker_ids)
          diagnose_decision["coolingBlockerIDs"] = cooling_blocker_ids
        else
          failures << "viftyctl-diagnose.json coolingBlockerIDs must be an array of strings"
        end
      else
        warnings << "viftyctl-diagnose.json is missing coolingBlockerIDs; legacy reports may require checks[] parsing for hard cooling blockers"
      end
      if [true, false].include?(daemon_ready)
        diagnose_decision["daemonControlPathReady"] = daemon_ready
      elsif daemon_ready_present
        failures << "viftyctl-diagnose.json daemonControlPathReady must be boolean"
      else
        inferred_daemon_ready = infer_daemon_control_path_ready(
          state,
          agent_action,
          recovery_action,
          safe_to_request
        )
        if [true, false].include?(inferred_daemon_ready)
          daemon_ready = inferred_daemon_ready
          diagnose_decision["daemonControlPathReady"] = inferred_daemon_ready
          warnings << "viftyctl-diagnose.json is missing daemonControlPathReady; inferred #{inferred_daemon_ready} from legacy readiness fields"
        else
          failures << "viftyctl-diagnose.json daemonControlPathReady is missing and could not be inferred"
        end
      end

      failures << "viftyctl-diagnose.json state is missing or unsupported" unless DIAGNOSE_STATES.include?(state)
      failures << "viftyctl-diagnose.json recommendedAgentAction is missing or unsupported" unless DIAGNOSE_AGENT_ACTIONS.include?(agent_action)
      failures << "viftyctl-diagnose.json recommendedRecoveryAction is missing or unsupported" unless DIAGNOSE_RECOVERY_ACTIONS.include?(recovery_action)
      failures << "viftyctl-diagnose.json safeToRequestCooling must be boolean" unless [true, false].include?(safe_to_request)
      if manual_control_active_present && ![true, false].include?(manual_control_active)
        failures << "viftyctl-diagnose.json manualControlActive must be boolean"
      elsif !manual_control_active_present
        warnings << "viftyctl-diagnose.json is missing manualControlActive; legacy reports may not distinguish manual/user fan ownership"
      end
      if app_preferences_present
        if app_preferences.is_a?(Hash)
          startup_mode = app_preferences["startupMode"]
          startup_mode_source = app_preferences["startupModeSource"]
          read_error = app_preferences["readError"]

          if STARTUP_MODES.include?(startup_mode) || startup_mode.nil?
            diagnose_decision["appPreferences"]["startupMode"] = startup_mode
          else
            failures << "viftyctl-diagnose.json appPreferences.startupMode is missing or unsupported"
          end

          if STARTUP_MODE_SOURCES.include?(startup_mode_source)
            diagnose_decision["appPreferences"]["startupModeSource"] = startup_mode_source
          else
            failures << "viftyctl-diagnose.json appPreferences.startupModeSource is missing or unsupported"
          end

          if read_error.is_a?(String) || read_error.nil?
            diagnose_decision["appPreferences"]["readError"] = read_error
          else
            failures << "viftyctl-diagnose.json appPreferences.readError must be string or null"
          end

          if manual_control_active == true && %w[Curve Fixed].include?(startup_mode)
            warnings << "manualControlActive is true and Vifty default startup mode is #{startup_mode}; switch the default mode to Auto before retrying agent cooling"
          end
        else
          failures << "viftyctl-diagnose.json appPreferences must be an object"
        end
      else
        warnings << "viftyctl-diagnose.json is missing appPreferences; legacy reports may not identify Vifty startup/default mode"
      end

      if diagnose_status == 75 && state != "blocked"
        failures << "viftyctl-diagnose exit 75 must report state blocked"
      end
      if diagnose_status == 0 && state == "blocked"
        failures << "viftyctl-diagnose state blocked must use blocked-readiness exit 75"
      end
      if state == "blocked" && agent_action != "doNotRequestCooling"
        failures << "blocked diagnose must recommend doNotRequestCooling"
      end
      if state == "blocked" && safe_to_request != false
        failures << "blocked diagnose must set safeToRequestCooling false"
      end
      expected_safe = %w[requestCooling requestCoolingWithCaution].include?(agent_action)
      if DIAGNOSE_AGENT_ACTIONS.include?(agent_action) && [true, false].include?(safe_to_request) && safe_to_request != expected_safe
        failures << "safeToRequestCooling does not match recommendedAgentAction"
      end
      if daemon_ready == false && recovery_action != "repairHelper"
        failures << "daemonControlPathReady false must recommend repairHelper"
      end
      if manual_control_active == true && safe_to_request != false
        failures << "manualControlActive true must set safeToRequestCooling false"
      end
      if manual_control_active == true && %w[requestCooling requestCoolingWithCaution].include?(agent_action)
        failures << "manualControlActive true must not recommend agent cooling"
      end
      if diagnose_decision["coolingBlockerIDs"].any? && safe_to_request == true
        failures << "coolingBlockerIDs must be empty when safeToRequestCooling is true"
      end
    end
  rescue JSON::ParserError => error
    failures << "invalid viftyctl-diagnose.json: #{error.message}"
  end
else
  failures << "missing viftyctl-diagnose.json"
end

%w[viftyctl-status viftyctl-audit].each do |name|
  status = integer_value(commands_by_name.dig(name, "status"))
  next if status == 0

  command = name.delete_prefix("viftyctl-")
  if helper_repair_diagnose?(diagnose_decision) &&
      command_error_report?(
        bundle,
        name,
        failures,
        expected_command: command,
        expected_error_code: "HELPER_UNREACHABLE",
        expected_recovery_action: "repairHelper"
      )
    accepted_command_errors << name
    warnings << "#{name} exited #{status}; accepted structured HELPER_UNREACHABLE command error because diagnose requires helper repair"
  else
    failures << "#{name} must exit 0 unless blocked diagnose recommends repairHelper and the command JSON is HELPER_UNREACHABLE"
  end
end

%w[launchctl-print-daemon launchdaemon-plist helper-file-metadata app-info-plist].each do |name|
  status = integer_value(commands_by_name.dig(name, "status"))
  warnings << "#{name} exited #{status}; captured failures may still be useful evidence" if status && status != 0
end

app_info_status = integer_value(commands_by_name.dig("app-info-plist", "status"))
app_info["exitStatus"] = app_info_status
app_info_path = File.join(bundle, "app-info-plist.txt")
if app_info_status == 0 && File.file?(app_info_path)
  app_info_text = File.read(app_info_path)
  app_info["bundleIdentifier"] = plutil_string_value(app_info_text, "CFBundleIdentifier")
  app_info["shortVersion"] = plutil_string_value(app_info_text, "CFBundleShortVersionString")
  app_info["bundleVersion"] = plutil_string_value(app_info_text, "CFBundleVersion")

  failures << "app-info-plist.txt must include CFBundleIdentifier tech.reidar.vifty" unless app_info["bundleIdentifier"] == "tech.reidar.vifty"
  failures << "app-info-plist.txt must include CFBundleShortVersionString" if app_info["shortVersion"].to_s.empty?
  failures << "app-info-plist.txt must include CFBundleVersion" if app_info["bundleVersion"].to_s.empty?
end
if helper_repair_diagnose?(diagnose_decision) &&
    app_info["shortVersion"] == "1.1.0" &&
    accepted_command_errors.any?
  warnings << "known v1.1.0 helper-unreachable issue: use the v1.1.1 source-first hotfix or current source; do not retag v1.1.0 or replace its unsigned-dev assets"
end

guarded_run_stderr_path = File.join(bundle, "guarded-run-stderr.txt")
if File.file?(guarded_run_stderr_path)
  guarded_run_decision["present"] = true
  guarded_run_decision["sourceFile"] = "guarded-run-stderr.txt"
  guarded_run_stderr_text = File.read(guarded_run_stderr_path)
  guarded_payload = extract_guarded_run_decision_json(guarded_run_stderr_text, failures)

  if guarded_payload.is_a?(Hash)
    schema_version = guarded_payload["schemaVersion"]
    schema_id = guarded_payload["schemaID"]
    command = guarded_payload["command"]
    safe_to_proceed = guarded_payload["safeToProceed"]
    cooling_requested = guarded_payload["coolingRequested"]
    uncooled_requested = guarded_payload["uncooledFallbackRequested"]
    uncooled_allowed = guarded_payload["uncooledFallbackAllowed"]
    decision_reason = guarded_payload["decisionReason"]
    exit_code = integer_value(guarded_payload["exitCode"])
    message = guarded_payload["message"]
    agent_action = guarded_payload["recommendedAgentAction"]
    recovery_action = guarded_payload["recommendedRecoveryAction"]
    diagnose_state = guarded_payload["diagnoseState"]
    safe_to_request = guarded_payload["safeToRequestCooling"]
    daemon_ready = guarded_payload["daemonControlPathReady"]
    manual_active = guarded_payload["manualControlActive"]
    startup_mode = guarded_payload["startupMode"]
    failed_check_ids = guarded_payload["failedCheckIDs"]
    cooling_blocker_ids = guarded_payload["coolingBlockerIDs"]
    requested_workload = guarded_payload["requestedWorkload"]
    requested_duration = guarded_payload["requestedDuration"]
    requested_max_rpm_percent = integer_value(guarded_payload["requestedMaxRPMPercent"])
    reason_character_count = integer_value(guarded_payload["reasonCharacterCount"])
    child_command_name = guarded_payload["childCommandName"]
    child_command_kind = guarded_payload["childCommandKind"]
    child_argument_count = integer_value(guarded_payload["childArgumentCount"])

    guarded_run_decision["schemaVersion"] = schema_version if schema_version.is_a?(Integer)
    guarded_run_decision["schemaID"] = schema_id if schema_id.is_a?(String)
    guarded_run_decision["safeToProceed"] = safe_to_proceed if boolean?(safe_to_proceed)
    guarded_run_decision["coolingRequested"] = cooling_requested if boolean?(cooling_requested)
    guarded_run_decision["uncooledFallbackRequested"] = uncooled_requested if boolean?(uncooled_requested)
    guarded_run_decision["uncooledFallbackAllowed"] = uncooled_allowed if boolean?(uncooled_allowed)
    guarded_run_decision["decisionReason"] = decision_reason if optional_string?(decision_reason)
    guarded_run_decision["exitCode"] = exit_code
    guarded_run_decision["message"] = message if message.is_a?(String)
    guarded_run_decision["recommendedAgentAction"] = agent_action if optional_string?(agent_action)
    guarded_run_decision["recommendedRecoveryAction"] = recovery_action if optional_string?(recovery_action)
    guarded_run_decision["diagnoseState"] = diagnose_state if optional_string?(diagnose_state)
    guarded_run_decision["safeToRequestCooling"] = safe_to_request if boolean?(safe_to_request)
    guarded_run_decision["daemonControlPathReady"] = daemon_ready if boolean?(daemon_ready)
    guarded_run_decision["manualControlActive"] = manual_active if boolean?(manual_active)
    guarded_run_decision["startupMode"] = startup_mode if optional_string?(startup_mode)
    guarded_run_decision["failedCheckIDs"] = failed_check_ids if string_array?(failed_check_ids)
    guarded_run_decision["coolingBlockerIDs"] = cooling_blocker_ids if string_array?(cooling_blocker_ids)
    guarded_run_decision["requestedWorkload"] = requested_workload if optional_string?(requested_workload)
    guarded_run_decision["requestedDuration"] = requested_duration if optional_string?(requested_duration)
    guarded_run_decision["requestedMaxRPMPercent"] = requested_max_rpm_percent
    guarded_run_decision["reasonCharacterCount"] = reason_character_count
    guarded_run_decision["childCommandName"] = child_command_name if optional_string?(child_command_name)
    guarded_run_decision["childCommandKind"] = child_command_kind if optional_string?(child_command_kind)
    guarded_run_decision["childArgumentCount"] = child_argument_count

    failures << "guarded-run decision schemaVersion must be 1" unless schema_version == 1
    failures << "guarded-run decision schemaID must be #{GUARDED_RUN_DECISION_SCHEMA_ID}" unless schema_id == GUARDED_RUN_DECISION_SCHEMA_ID
    failures << "guarded-run decision command must be guarded-run" unless command == "guarded-run"
    failures << "guarded-run decision safeToProceed must be boolean" unless boolean?(safe_to_proceed)
    failures << "guarded-run decision coolingRequested must be false for support evidence" unless cooling_requested == false
    failures << "guarded-run decision uncooledFallbackRequested must be boolean" unless boolean?(uncooled_requested)
    failures << "guarded-run decision uncooledFallbackAllowed must be boolean" unless boolean?(uncooled_allowed)
    failures << "guarded-run decision decisionReason is unsupported" unless decision_reason.nil? || GUARDED_RUN_DECISION_REASONS.include?(decision_reason)
    failures << "guarded-run decision exitCode must be an integer" unless exit_code
    failures << "guarded-run decision message must be nonempty" unless message.is_a?(String) && !message.strip.empty?
    failures << "guarded-run decision recommendedAgentAction is unsupported" unless agent_action.nil? || DIAGNOSE_AGENT_ACTIONS.include?(agent_action)
    failures << "guarded-run decision recommendedRecoveryAction is unsupported" unless recovery_action.nil? || DIAGNOSE_RECOVERY_ACTIONS.include?(recovery_action)
    failures << "guarded-run decision diagnoseState is unsupported" unless diagnose_state.nil? || DIAGNOSE_STATES.include?(diagnose_state)
    failures << "guarded-run decision safeToRequestCooling must be boolean" unless boolean?(safe_to_request)
    failures << "guarded-run decision daemonControlPathReady must be boolean" unless boolean?(daemon_ready)
    failures << "guarded-run decision manualControlActive must be boolean" unless boolean?(manual_active)
    failures << "guarded-run decision startupMode is unsupported" unless startup_mode.nil? || STARTUP_MODES.include?(startup_mode)
    failures << "guarded-run decision failedCheckIDs must be an array of strings" unless string_array?(failed_check_ids)
    failures << "guarded-run decision coolingBlockerIDs must be an array of strings" unless string_array?(cooling_blocker_ids)

    workload_envelope_values = {
      "requestedWorkload" => requested_workload,
      "requestedDuration" => requested_duration,
      "requestedMaxRPMPercent" => requested_max_rpm_percent,
      "reasonCharacterCount" => reason_character_count,
      "childCommandName" => child_command_name,
      "childCommandKind" => child_command_kind,
      "childArgumentCount" => child_argument_count
    }
    if workload_envelope_values.values.compact.any?
      failures << "guarded-run decision requestedWorkload must be nonempty" unless requested_workload.is_a?(String) && !requested_workload.strip.empty?
      failures << "guarded-run decision requestedDuration is unsupported" unless requested_duration.is_a?(String) && requested_duration.match?(/\A[1-9][0-9]*([mh])?\z/)
      failures << "guarded-run decision requestedMaxRPMPercent must be 1...100" unless requested_max_rpm_percent && requested_max_rpm_percent >= 1 && requested_max_rpm_percent <= 100
      failures << "guarded-run decision reasonCharacterCount must be positive" unless reason_character_count && reason_character_count.positive?
      failures << "guarded-run decision childCommandName must be a basename without slashes" unless child_command_name.is_a?(String) && !child_command_name.empty? && !child_command_name.include?("/")
      failures << "guarded-run decision childCommandKind is unsupported" unless %w[path pathLookup].include?(child_command_kind)
      failures << "guarded-run decision childArgumentCount must be nonnegative" unless child_argument_count && child_argument_count >= 0
    else
      warnings << "guarded-run decision omits workload envelope; accepted as legacy evidence"
    end

    if safe_to_proceed == true
      failures << "guarded-run decision safeToProceed true requires exitCode 0" unless exit_code == 0
      if decision_reason == "preflightReady"
        failures << "guarded-run decision preflightReady must not request uncooled fallback" unless uncooled_requested == false && uncooled_allowed == false
      else
        failures << "guarded-run decision safeToProceed true requires uncooled fallback allowed" unless uncooled_requested == true && uncooled_allowed == true
      end
    elsif safe_to_proceed == false
      failures << "guarded-run decision safeToProceed false requires nonzero exitCode" if exit_code == 0
    end
    if decision_reason == "preflightReady" && safe_to_proceed != true
      failures << "guarded-run decision preflightReady requires safeToProceed true"
    end
    if uncooled_allowed == true && uncooled_requested != true
      failures << "guarded-run decision cannot allow uncooled fallback unless it was requested"
    end
    if cooling_blocker_ids.is_a?(Array) && cooling_blocker_ids.any? && safe_to_request == true
      failures << "guarded-run decision coolingBlockerIDs must be empty when safeToRequestCooling is true"
    end
    if manual_active == true && safe_to_proceed == true
      failures << "guarded-run decision must not proceed while manualControlActive is true"
    end

    comparisons = [
      ["diagnoseState", diagnose_state, diagnose_decision["state"]],
      ["recommendedAgentAction", agent_action, diagnose_decision["recommendedAgentAction"]],
      ["recommendedRecoveryAction", recovery_action, diagnose_decision["recommendedRecoveryAction"]],
      ["safeToRequestCooling", safe_to_request, diagnose_decision["safeToRequestCooling"]],
      ["daemonControlPathReady", daemon_ready, diagnose_decision["daemonControlPathReady"]],
      ["manualControlActive", manual_active, diagnose_decision["manualControlActive"]],
      ["startupMode", startup_mode, diagnose_decision.dig("appPreferences", "startupMode")]
    ]
    comparisons.each do |field, guarded_value, diagnose_value|
      next if guarded_value.nil? || diagnose_value.nil?
      failures << "guarded-run decision #{field} does not match diagnose evidence" unless guarded_value == diagnose_value
    end
    if string_array?(failed_check_ids) && diagnose_decision["failedCheckIDs"].any? && failed_check_ids != diagnose_decision["failedCheckIDs"]
      failures << "guarded-run decision failedCheckIDs do not match diagnose evidence"
    end
    if string_array?(cooling_blocker_ids) && diagnose_decision["coolingBlockerIDs"].any? && cooling_blocker_ids != diagnose_decision["coolingBlockerIDs"]
      failures << "guarded-run decision coolingBlockerIDs do not match diagnose evidence"
    end
  elsif !guarded_payload.nil?
    failures << "guarded-run decision JSON must contain an object"
  end
end

privacy_status = integer_value(commands_by_name.dig("privacy-review", "status"))
failures << "privacy-review must exit 0 before sharing the bundle" unless privacy_status == 0
privacy_rows.each do |row|
  if row["finding"] == "redaction-needed"
    failures << "privacy-review found redaction-needed entry in #{row["file"]}:#{row["line"]}"
  end
end

audit_path = File.join(bundle, "viftyctl-audit.json")
if File.file?(audit_path) && integer_value(commands_by_name.dig("viftyctl-audit", "status")) == 0
  begin
    audit = JSON.parse(File.read(audit_path))
    failures << "viftyctl-audit.json readOnly must be true" unless audit.is_a?(Hash) && audit["readOnly"] == true
    failures << "viftyctl-audit.json coolingCommandsRun must be false" unless audit.is_a?(Hash) && audit["coolingCommandsRun"] == false
  rescue JSON::ParserError => error
    failures << "invalid viftyctl-audit.json: #{error.message}"
  end
end

checksum_by_file = {}
checksum_rows.each do |row|
  file_name = row["file"]
  unless bundle_entry?(file_name)
    failures << "checksum row has invalid bundle-local file: #{file_name.inspect}"
    next
  end
  if checksum_by_file.key?(file_name)
    failures << "checksums has duplicate file row: #{file_name}"
  else
    checksum_by_file[file_name] = row
  end
end

summary_path_in_bundle = nil
if summary_path
  summary_dir = File.expand_path(File.dirname(summary_path))
  summary_path_in_bundle = File.basename(summary_path) if summary_dir == bundle
end

expected_checksum_files = Dir.children(bundle).sort.select do |entry|
  path = File.join(bundle, entry)
  File.file?(path) && entry != "checksums.tsv" && entry != summary_path_in_bundle
end

expected_checksum_files.each do |entry|
  row = checksum_by_file[entry]
  unless row
    failures << "checksum missing entry for #{entry}"
    next
  end

  path = File.join(bundle, entry)
  expected_sha = Digest::SHA256.file(path).hexdigest
  expected_bytes = File.size(path).to_s
  failures << "checksum sha256 drift for #{entry}" unless row["sha256"] == expected_sha
  failures << "checksum byte-count drift for #{entry}" unless row["bytes"] == expected_bytes
end

checksum_by_file.each_key do |entry|
  failures << "checksum references unexpected file #{entry}" unless expected_checksum_files.include?(entry)
end

status = failures.empty? ? "passed" : "failed"
write_review_summary(summary_path, bundle, status, read_only, cooling_commands_run, commands.length, diagnose_decision, capabilities_decision, app_info, guarded_run_decision, accepted_command_errors, failures, warnings)

warnings.each { |warning| warn "warning: #{warning}" }

if failures.empty?
  puts "Agent cooling evidence OK: #{bundle}"
  exit 0
end

failures.each { |failure| warn "failure: #{failure}" }
exit 65
RUBY
