#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/review-validation-evidence.sh --bundle <dir> --mode <mode> [options]

Review a Vifty validation evidence bundle that was already captured by
scripts/collect-validation-evidence.sh. This script is read-only: it only
inspects files in the bundle and never runs viftyctl, ViftyHelper, launchctl,
codesign, stapler, spctl, or fan-control commands.

Modes:
  release               Installed public-release trust evidence.
  supported-hardware    Apple Silicon MacBook Pro compatibility evidence.
  unsupported-hardware  Unsupported machine evidence that blocks safely.

Options:
  --bundle <dir>         Evidence bundle directory to review.
  --mode <mode>          Review mode. Defaults to supported-hardware.
  --summary <path>       Write a JSON review summary whether the review passes
                         or fails.
  --manual-smoke-result <result>
                         Issue-template manual smoke-test answer. One of:
                         not-recorded, passed-auto-restored, skipped-blocked,
                         skipped-unsupported, failed. Defaults to not-recorded.
  --manual-smoke-source <text>
                         Issue URL, note, or other source for the manual smoke
                         result.
  -h, --help             Show this help.
USAGE
}

BUNDLE_DIR=""
MODE="supported-hardware"
SUMMARY_PATH=""
MANUAL_SMOKE_RESULT="not-recorded"
MANUAL_SMOKE_SOURCE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      if [[ $# -lt 2 ]]; then
        echo "error: --bundle requires a directory" >&2
        exit 64
      fi
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --mode)
      if [[ $# -lt 2 ]]; then
        echo "error: --mode requires a value" >&2
        exit 64
      fi
      MODE="$2"
      shift 2
      ;;
    --summary)
      if [[ $# -lt 2 ]]; then
        echo "error: --summary requires a path" >&2
        exit 64
      fi
      SUMMARY_PATH="$2"
      shift 2
      ;;
    --manual-smoke-result)
      if [[ $# -lt 2 ]]; then
        echo "error: --manual-smoke-result requires a value" >&2
        exit 64
      fi
      MANUAL_SMOKE_RESULT="$2"
      shift 2
      ;;
    --manual-smoke-source)
      if [[ $# -lt 2 ]]; then
        echo "error: --manual-smoke-source requires text" >&2
        exit 64
      fi
      MANUAL_SMOKE_SOURCE="$2"
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

if [[ -z "${BUNDLE_DIR}" ]]; then
  echo "error: --bundle is required" >&2
  usage >&2
  exit 64
fi

case "${MODE}" in
  release|supported-hardware|unsupported-hardware)
    ;;
  *)
    echo "error: unsupported mode: ${MODE}" >&2
    usage >&2
    exit 64
    ;;
esac

case "${MANUAL_SMOKE_RESULT}" in
  not-recorded|passed-auto-restored|skipped-blocked|skipped-unsupported|failed)
    ;;
  *)
    echo "error: unsupported manual smoke result: ${MANUAL_SMOKE_RESULT}" >&2
    usage >&2
    exit 64
    ;;
esac

if [[ ! -d "${BUNDLE_DIR}" ]]; then
  echo "error: evidence bundle not found: ${BUNDLE_DIR}" >&2
  exit 66
fi

ruby -rjson -rcsv -rdigest -rfileutils -e '
  bundle = File.expand_path(ARGV.fetch(0))
  mode = ARGV.fetch(1)
  summary_path = ARGV.fetch(2, "")
  manual_smoke_result = ARGV.fetch(3, "not-recorded")
  manual_smoke_source = ARGV.fetch(4, "")
  failures = []
  warnings = []

  EXPECTED_EXECUTABLES = {
    "Vifty" => "Contents/MacOS/Vifty",
    "ViftyHelper" => "Contents/MacOS/ViftyHelper",
    "ViftyDaemon" => "Contents/MacOS/ViftyDaemon",
    "viftyctl" => "Contents/MacOS/viftyctl"
  }.freeze

  EXPECTED_SCHEMA_RESOURCES = {
    "release-artifact-summary.schema.json" => "Contents/Resources/schemas/release-artifact-summary.schema.json",
    "viftyctl-audit.schema.json" => "Contents/Resources/schemas/viftyctl-audit.schema.json",
    "viftyctl-capabilities.schema.json" => "Contents/Resources/schemas/viftyctl-capabilities.schema.json",
    "viftyctl-command-error.schema.json" => "Contents/Resources/schemas/viftyctl-command-error.schema.json",
    "viftyctl-diagnose.schema.json" => "Contents/Resources/schemas/viftyctl-diagnose.schema.json",
    "viftyctl-status.schema.json" => "Contents/Resources/schemas/viftyctl-status.schema.json"
  }.freeze

  EXPECTED_CAPABILITIES_SCHEMA_RESOURCES = {
    "audit" => "Contents/Resources/schemas/viftyctl-audit.schema.json",
    "capabilities" => "Contents/Resources/schemas/viftyctl-capabilities.schema.json",
    "commandError" => "Contents/Resources/schemas/viftyctl-command-error.schema.json",
    "diagnose" => "Contents/Resources/schemas/viftyctl-diagnose.schema.json",
    "status" => "Contents/Resources/schemas/viftyctl-status.schema.json"
  }.freeze

  EXPECTED_CAPABILITIES_CONTRACT = {
    "supportsForceRetry" => "true",
    "runLifecycle.childCommandPreflightBeforeCooling" => "true",
    "runLifecycle.autoRestoreAfterChildExit" => "true",
    "runLifecycle.structuredPreChildFailures" => "true",
    "runLifecycle.cleanupStateReportedOnLaunchFailure" => "true",
    "runLifecycle.signalsForwardedToChild" => "INT,TERM,HUP",
    "directControlLifecycle.prepareUsesIdempotencyKey" => "true",
    "directControlLifecycle.restoreAutoAcceptsIdempotencyKey" => "false",
    "directControlLifecycle.restoreAutoScopedByIdempotencyKey" => "false",
    "directControlLifecycle.preferRunForSingleChildWorkloads" => "true"
  }.freeze

  REQUIRED_COMMON_FILES = %w[
    review-summary.json
    review-summary.tsv
    manifest.tsv
    checksums.tsv
    metadata.txt
    viftyctl-diagnose.json
    viftyctl-audit.json
    bundle-executables.tsv
    privacy-review.tsv
    schema-resources.tsv
    capabilities-schema-resources.tsv
    capabilities-contract.tsv
  ].freeze

  COMMON_ZERO_CHECKS = %w[
    app-info-plist
    bundle-executables
    privacy-review
    schema-resources
    capabilities-schema-resources
    capabilities-contract
    launchdaemon-lint
    viftyctl-status
    viftyctl-audit
  ].freeze

  RELEASE_ZERO_CHECKS = %w[
    release-artifact-summary
    release-checklist
    launchdaemon-teamid
    launchctl-print-daemon
    codesign-verify-app
    codesign-verify-viftyctl
    codesign-verify-viftyhelper
    codesign-verify-viftydaemon
    spctl-assess-app
    stapler-validate-app
  ].freeze

  RELEASE_ARTIFACT_SUMMARY_SCHEMA_ID = "https://vifty.local/schemas/release-artifact-summary.schema.json"

  def bundle_path(bundle, relative_path)
    File.join(bundle, relative_path)
  end

  def read_file(bundle, relative_path, failures)
    path = bundle_path(bundle, relative_path)
    unless File.file?(path)
      failures << "missing required file: #{relative_path}"
      return nil
    end
    File.read(path)
  rescue StandardError => error
    failures << "could not read #{relative_path}: #{error.message}"
    nil
  end

  def parse_json(bundle, relative_path, failures)
    text = read_file(bundle, relative_path, failures)
    return nil if text.nil?
    JSON.parse(text)
  rescue StandardError => error
    failures << "could not parse #{relative_path}: #{error.message}"
    nil
  end

  def parse_tsv(bundle, relative_path, failures)
    text = read_file(bundle, relative_path, failures)
    return [] if text.nil?
    CSV.parse(text, col_sep: "\t", headers: true).map(&:to_h)
  rescue StandardError => error
    failures << "could not parse #{relative_path}: #{error.message}"
    []
  end

  def status_for(checks, name)
    value = checks[name]
    value.nil? ? nil : value.to_s
  end

  def require_status(checks, name, allowed, failures)
    status = status_for(checks, name)
    if status.nil?
      failures << "review-summary.json is missing check #{name}"
    elsif !allowed.include?(status)
      failures << "#{name} status #{status.inspect} was not one of #{allowed.join(", ")}"
    end
  end

  def require_review_summary_tsv_matches_json(tsv_rows, json_checks, failures)
    if tsv_rows.empty?
      failures << "review-summary.tsv must include check rows"
      return
    end

    missing_headers = %w[name status].reject { |header| tsv_rows.first.key?(header) }
    unless missing_headers.empty?
      failures << "review-summary.tsv is missing required header(s): #{missing_headers.join(", ")}"
      return
    end

    tsv_checks = {}
    tsv_rows.each do |row|
      name = row["name"].to_s
      next if name.empty?
      if tsv_checks.key?(name)
        failures << "review-summary.tsv has duplicate check #{name}"
        next
      end
      tsv_checks[name] = row["status"].to_s
    end

    json_checks.each do |name, json_status|
      tsv_status = tsv_checks[name]
      if tsv_status.nil?
        failures << "review-summary.tsv is missing check #{name}"
      elsif tsv_status != json_status
        failures << "review-summary.tsv #{name} status #{tsv_status.inspect} did not match review-summary.json #{json_status.inspect}"
      end
    end
  end

  def require_manifest_matches_summary(bundle, manifest_rows, json_checks, failures)
    if manifest_rows.empty?
      failures << "manifest.tsv must include command rows"
      return
    end

    missing_headers = %w[name status stdout stderr].reject { |header| manifest_rows.first.key?(header) }
    unless missing_headers.empty?
      failures << "manifest.tsv is missing required header(s): #{missing_headers.join(", ")}"
      return
    end

    manifest_checks = {}
    manifest_files = {}
    manifest_rows.each do |row|
      name = row["name"].to_s
      if name.empty?
        failures << "manifest.tsv has a row with an empty name"
        next
      end
      unless name.match?(/\A[A-Za-z0-9_.-]+\z/) && !name.start_with?(".")
        failures << "manifest.tsv name #{name.inspect} must be a command name"
        next
      end
      if manifest_checks.key?(name)
        failures << "manifest.tsv has duplicate command #{name}"
        next
      end

      status = row["status"].to_s
      if status.empty?
        failures << "manifest.tsv #{name} status is empty"
      end
      manifest_checks[name] = status

      json_status = json_checks[name]
      if !json_status.nil? && status != json_status
        failures << "manifest.tsv #{name} status #{status.inspect} did not match review-summary.json #{json_status.inspect}"
      end

      %w[stdout stderr].each do |field|
        relative_path = row[field].to_s
        if relative_path.empty?
          failures << "manifest.tsv #{name} #{field} is empty"
          next
        end
        if relative_path.include?("/") || relative_path.start_with?(".")
          failures << "manifest.tsv #{name} #{field} #{relative_path.inspect} must be a bundle-local filename"
          next
        end
        if manifest_files.key?(relative_path)
          failures << "manifest.tsv #{name} #{field} #{relative_path.inspect} duplicates another manifest file"
        else
          manifest_files[relative_path] = true
        end
        unless File.file?(bundle_path(bundle, relative_path))
          failures << "manifest.tsv #{name} #{field} references missing file #{relative_path}"
        end
      end

      status_path = "#{name}.status"
      if manifest_files.key?(status_path)
        failures << "manifest.tsv #{name} status file #{status_path.inspect} duplicates another manifest file"
      else
        manifest_files[status_path] = true
      end
      status_file_path = bundle_path(bundle, status_path)
      unless File.file?(status_file_path)
        failures << "manifest.tsv #{name} status references missing file #{status_path}"
        next
      end
      status_file_value = File.read(status_file_path).strip
      unless status_file_value == status
        failures << "manifest.tsv #{name} status #{status.inspect} did not match #{status_path} #{status_file_value.inspect}"
      end
    end

    json_checks.each do |name, json_status|
      next if json_status == "skipped"
      next if manifest_checks.key?(name)

      failures << "manifest.tsv is missing command #{name}"
    end
  rescue StandardError => error
    failures << "could not validate manifest.tsv: #{error.message}"
  end

  def require_checksums_match_bundle(bundle, checksum_rows, summary_path, failures)
    if checksum_rows.empty?
      failures << "checksums.tsv must include evidence rows"
      return
    end

    missing_headers = %w[sha256 bytes file].reject { |header| checksum_rows.first.key?(header) }
    unless missing_headers.empty?
      failures << "checksums.tsv is missing required header(s): #{missing_headers.join(", ")}"
      return
    end

    seen_files = {}
    checksum_rows.each do |row|
      relative_path = row["file"].to_s
      if relative_path.empty?
        failures << "checksums.tsv has a row with an empty file"
        next
      end
      if relative_path == "checksums.tsv"
        failures << "checksums.tsv must not include itself"
        next
      end
      if relative_path.include?("/") || relative_path.start_with?(".")
        failures << "checksums.tsv file #{relative_path.inspect} must be a bundle-local filename"
        next
      end
      if seen_files.key?(relative_path)
        failures << "checksums.tsv has duplicate file #{relative_path}"
        next
      end
      seen_files[relative_path] = true

      require_sha256(row["sha256"], "checksums.tsv #{relative_path} sha256", failures)
      declared_bytes = row["bytes"].to_s
      require_nonnegative_integer(declared_bytes, "checksums.tsv #{relative_path} bytes", failures)

      path = bundle_path(bundle, relative_path)
      unless File.file?(path)
        failures << "checksums.tsv references missing file #{relative_path}"
        next
      end

      actual_sha256 = Digest::SHA256.file(path).hexdigest
      actual_bytes = File.size(path).to_s
      unless row["sha256"].to_s == actual_sha256
        failures << "checksums.tsv #{relative_path} sha256 #{row["sha256"].to_s.inspect} did not match actual #{actual_sha256.inspect}"
      end
      unless declared_bytes == actual_bytes
        failures << "checksums.tsv #{relative_path} bytes #{declared_bytes.inspect} did not match actual #{actual_bytes.inspect}"
      end
    end

    excluded_paths = [bundle_path(bundle, "checksums.tsv")]
    excluded_paths << File.expand_path(summary_path) unless summary_path.to_s.empty?

    Dir.children(bundle).sort.each do |name|
      path = bundle_path(bundle, name)
      next unless File.file?(path)
      next if excluded_paths.include?(File.expand_path(path))

      failures << "checksums.tsv is missing file #{name}" unless seen_files.key?(name)
    end
  end

  def require_positive_integer(value, field, failures)
    integer = Integer(value)
    failures << "#{field} must be greater than zero" unless integer.positive?
  rescue StandardError
    failures << "#{field} must be a positive integer"
  end

  def require_nonnegative_integer(value, field, failures)
    integer = Integer(value)
    failures << "#{field} must be zero or greater" if integer.negative?
  rescue StandardError
    failures << "#{field} must be a nonnegative integer"
  end

  def require_sha256(value, field, failures)
    return if value.to_s.match?(/\A[0-9a-f]{64}\z/)

    failures << "#{field} must be a lowercase 64-character SHA-256 checksum"
  end

  def write_review_result(path, bundle, mode, status, failures, warnings, review_summary, diagnose, manual_smoke_result, manual_smoke_source)
    return if path.to_s.empty?

    payload = {
      "schemaVersion" => 1,
      "generatedAtUTC" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      "status" => status,
      "mode" => mode,
      "bundlePath" => bundle,
      "readOnly" => true,
      "coolingCommandsRun" => false,
      "appPath" => review_summary["appPath"],
      "releaseArtifactSummaryPath" => review_summary["releaseArtifactSummaryPath"],
      "releaseChecklistPath" => review_summary["releaseChecklistPath"],
      "diagnoseState" => diagnose["state"],
      "recommendedAgentAction" => diagnose["recommendedAgentAction"],
      "safeToRequestCooling" => diagnose["safeToRequestCooling"],
      "modelIdentifier" => diagnose["modelIdentifier"],
      "isAppleSilicon" => diagnose["isAppleSilicon"],
      "isMacBookPro" => diagnose["isMacBookPro"],
      "fanCount" => diagnose["fanCount"],
      "controllableFanCount" => diagnose["controllableFanCount"],
      "temperatureSensorCount" => diagnose["temperatureSensorCount"],
      "thermalPressure" => diagnose["thermalPressure"],
      "manualSmokeTestResult" => manual_smoke_result,
      "manualSmokeTestSource" => manual_smoke_source,
      "failures" => failures,
      "warnings" => warnings
    }

    directory = File.dirname(path)
    FileUtils.mkdir_p(directory) unless directory == "." || Dir.exist?(directory)
    File.write(path, JSON.pretty_generate(payload) + "\n")
  rescue StandardError => error
    warn "could not write review summary #{path}: #{error.message}"
    exit 73
  end

  REQUIRED_COMMON_FILES.each do |relative_path|
    path = bundle_path(bundle, relative_path)
    failures << "missing required file: #{relative_path}" unless File.file?(path)
  end

  summary = parse_json(bundle, "review-summary.json", failures) || {}
  unless summary["schemaVersion"] == 1
    failures << "review-summary.json schemaVersion must be 1"
  end
  unless summary["readOnly"] == true
    failures << "review-summary.json must declare readOnly=true"
  end
  unless summary["coolingCommandsRun"] == false
    failures << "review-summary.json must declare coolingCommandsRun=false"
  end

  checks_array = summary["checks"]
  unless checks_array.is_a?(Array)
    failures << "review-summary.json checks must be an array"
    checks_array = []
  end
  checks = {}
  checks_array.each do |check|
    next unless check.is_a?(Hash) && check["name"]
    checks[check["name"].to_s] = check["status"].to_s
  end
  review_summary_rows = parse_tsv(bundle, "review-summary.tsv", failures)
  require_review_summary_tsv_matches_json(review_summary_rows, checks, failures)
  manifest_rows = parse_tsv(bundle, "manifest.tsv", failures)
  require_manifest_matches_summary(bundle, manifest_rows, checks, failures)
  checksum_rows = parse_tsv(bundle, "checksums.tsv", failures)
  require_checksums_match_bundle(bundle, checksum_rows, summary_path, failures)

  COMMON_ZERO_CHECKS.each do |name|
    require_status(checks, name, ["0"], failures)
  end
  require_status(checks, "viftyctl-capabilities", ["0", "69"], failures)

  executable_rows = parse_tsv(bundle, "bundle-executables.tsv", failures)
  executable_by_name = executable_rows.to_h { |row| [row["executable"], row] }
  EXPECTED_EXECUTABLES.each do |name, expected_bundle_path|
    row = executable_by_name[name]
    if row.nil?
      failures << "bundle-executables.tsv is missing #{name}"
      next
    end
    unless row["bundlePath"] == expected_bundle_path
      failures << "#{name} bundlePath #{row["bundlePath"].inspect} did not match #{expected_bundle_path}"
    end
    require_sha256(row["sha256"], "#{name} sha256", failures)
    require_positive_integer(row["bytes"], "#{name} bytes", failures)
  end

  schema_rows = parse_tsv(bundle, "schema-resources.tsv", failures)
  schema_by_name = schema_rows.to_h { |row| [row["schema"].to_s, row] }
  EXPECTED_SCHEMA_RESOURCES.each do |schema, expected_bundle_path|
    row = schema_by_name[schema]
    if row.nil?
      failures << "schema-resources.tsv is missing #{schema}"
      next
    end
    unless row["bundlePath"] == expected_bundle_path
      failures << "#{schema} bundlePath #{row["bundlePath"].inspect} did not match #{expected_bundle_path}"
    end
    require_sha256(row["sha256"], "#{schema} sha256", failures)
    require_positive_integer(row["bytes"], "#{schema} bytes", failures)
  end

  capabilities_resource_rows = parse_tsv(bundle, "capabilities-schema-resources.tsv", failures)
  capabilities_resource_by_key = capabilities_resource_rows.to_h { |row| [row["key"].to_s, row] }
  EXPECTED_CAPABILITIES_SCHEMA_RESOURCES.each do |key, expected_resource|
    row = capabilities_resource_by_key[key]
    if row.nil?
      failures << "capabilities-schema-resources.tsv is missing #{key}"
      next
    end
    unless row["advertisedResource"] == expected_resource
      failures << "capabilities-schema-resources.tsv #{key} advertisedResource #{row["advertisedResource"].inspect} did not match #{expected_resource}"
    end
    unless row["expectedResource"] == expected_resource
      failures << "capabilities-schema-resources.tsv #{key} expectedResource #{row["expectedResource"].inspect} did not match #{expected_resource}"
    end
  end

  capabilities_contract_rows = parse_tsv(bundle, "capabilities-contract.tsv", failures)
  capabilities_contract_by_field = capabilities_contract_rows.to_h { |row| [row["field"].to_s, row] }
  EXPECTED_CAPABILITIES_CONTRACT.each do |field, expected_value|
    row = capabilities_contract_by_field[field]
    if row.nil?
      failures << "capabilities-contract.tsv is missing #{field}"
      next
    end
    unless row["expected"] == expected_value
      failures << "capabilities-contract.tsv #{field} expected #{row["expected"].inspect} did not match #{expected_value}"
    end
    unless row["actual"] == expected_value
      failures << "capabilities-contract.tsv #{field} actual #{row["actual"].inspect} did not match #{expected_value}"
    end
  end

  diagnose = parse_json(bundle, "viftyctl-diagnose.json", failures) || {}
  audit = parse_json(bundle, "viftyctl-audit.json", failures) || {}
  unless audit["readOnly"] == true
    failures << "viftyctl-audit.json must declare readOnly=true"
  end
  unless audit["coolingCommandsRun"] == false
    failures << "viftyctl-audit.json must declare coolingCommandsRun=false"
  end
  unless audit["events"].is_a?(Array)
    failures << "viftyctl-audit.json events must be an array"
  end
  diagnose_checks = {}
  Array(diagnose["checks"]).each do |check|
    next unless check.is_a?(Hash) && check["id"]
    diagnose_checks[check["id"].to_s] = check
  end

  case mode
  when "supported-hardware"
    require_status(checks, "viftyctl-diagnose", ["0"], failures)
    require_status(checks, "viftyhelper-probeLocal", ["0"], failures)

    unless %w[ready degraded].include?(diagnose["state"].to_s)
      failures << "supported hardware reports must have diagnose state ready or degraded"
    end
    unless diagnose["safeToRequestCooling"] == true
      failures << "supported hardware reports must have safeToRequestCooling=true"
    end
    unless %w[requestCooling requestCoolingWithCaution].include?(diagnose["recommendedAgentAction"].to_s)
      failures << "supported hardware reports must recommend requestCooling or requestCoolingWithCaution"
    end
    unless diagnose["isAppleSilicon"] == true && diagnose["isMacBookPro"] == true
      failures << "supported hardware reports must be from an Apple Silicon MacBook Pro"
    end
    require_positive_integer(diagnose["fanCount"], "fanCount", failures)
    require_positive_integer(diagnose["controllableFanCount"], "controllableFanCount", failures)
    require_positive_integer(diagnose["temperatureSensorCount"], "temperatureSensorCount", failures)

    Array(diagnose["checks"]).each do |check|
      next unless check.is_a?(Hash)
      if check["severity"].to_s == "error" && check["passed"] != true
        failures << "supported hardware report has failing error check #{check["id"]}"
      end
    end

    if diagnose["state"].to_s == "degraded"
      warnings << "diagnose state is degraded; require the GitHub report to explain the warning before marking the model validated"
    end

    probe = read_file(bundle, "viftyhelper-probeLocal.txt", failures).to_s
    ["fan[", "hardwareMode=", "hardwareModeRawValue=", "hardwareModeKey=", "targetRPM="].each do |token|
      failures << "viftyhelper-probeLocal.txt is missing #{token}" unless probe.include?(token)
    end
    case manual_smoke_result
    when "passed-auto-restored"
      if manual_smoke_source.to_s.empty?
        warnings << "manual smoke test passed, but no issue URL or source note was recorded"
      end
    when "not-recorded"
      warnings << "manual fan-write smoke-test result is not recorded; keep this report as candidate evidence"
    else
      failures << "supported hardware validation requires manual smoke result passed-auto-restored"
    end

  when "unsupported-hardware"
    require_status(checks, "viftyctl-diagnose", ["75"], failures)

    unless diagnose["state"].to_s == "blocked"
      failures << "unsupported hardware reports must have diagnose state blocked"
    end
    unless diagnose["safeToRequestCooling"] == false
      failures << "unsupported hardware reports must have safeToRequestCooling=false"
    end
    unless diagnose["recommendedAgentAction"].to_s == "doNotRequestCooling"
      failures << "unsupported hardware reports must recommend doNotRequestCooling"
    end

    daemon_check = diagnose_checks["daemonSnapshotAvailable"]
    if daemon_check && daemon_check["passed"] != true
      failures << "unsupported hardware proof requires daemonSnapshotAvailable to pass; otherwise the report only proves daemon failure"
    end
    agent_check = diagnose_checks["agentControlStatusAvailable"]
    if agent_check && agent_check["passed"] != true
      failures << "unsupported hardware proof requires agentControlStatusAvailable to pass; otherwise the report only proves agent status failure"
    end
    supported_check = diagnose_checks["supportedHardware"]
    if supported_check.nil?
      failures << "unsupported hardware reports must include supportedHardware check"
    elsif supported_check["passed"] != false
      failures << "unsupported hardware reports must fail the supportedHardware check"
    end

    if %w[passed-auto-restored failed].include?(manual_smoke_result)
      failures << "unsupported hardware reports must not include a manual fan-write smoke test result"
    end

  when "release"
    REQUIRED_COMMON_FILES.each { |_| }
    %w[
      release-artifact-summary.json
      release-artifact-summary.tsv
      release-checklist.md
      release-checklist.tsv
      launchdaemon-teamid.txt
    ].each do |relative_path|
      failures << "missing required file for release mode: #{relative_path}" unless File.file?(bundle_path(bundle, relative_path))
    end
    RELEASE_ZERO_CHECKS.each do |name|
      require_status(checks, name, ["0"], failures)
    end
    require_status(checks, "viftyctl-diagnose", ["0", "75"], failures)

    if summary["releaseArtifactSummaryPath"].to_s.empty?
      failures << "release mode requires review-summary.json releaseArtifactSummaryPath"
    end
    if summary["releaseChecklistPath"].to_s.empty?
      failures << "release mode requires review-summary.json releaseChecklistPath"
    end

    release_summary = parse_json(bundle, "release-artifact-summary.json", failures) || {}
    unless release_summary["schemaVersion"] == 1
      failures << "release-artifact-summary.json schemaVersion must be 1"
    end
    unless release_summary["schemaID"] == RELEASE_ARTIFACT_SUMMARY_SCHEMA_ID
      failures << "release-artifact-summary.json schemaID must be #{RELEASE_ARTIFACT_SUMMARY_SCHEMA_ID}"
    end
    unless release_summary["status"] == "passed"
      failures << "release-artifact-summary.json status must be passed"
    end
    unless release_summary["signatureChecksSkipped"] == false
      failures << "release evidence must not skip signature checks"
    end
    unless release_summary["notarizationChecksSkipped"] == false
      failures << "release evidence must not skip notarization checks"
    end
    if release_summary["caskVersion"].to_s.empty?
      failures << "release-artifact-summary.json must include caskVersion"
    end
    if release_summary["bundleVersion"].to_s.empty?
      failures << "release-artifact-summary.json must include bundleVersion"
    elsif release_summary["caskVersion"].to_s != release_summary["bundleVersion"].to_s
      failures << "release caskVersion must match bundleVersion"
    end
    unless release_summary["expectedArtifactName"].to_s == "Vifty-v#{release_summary["caskVersion"]}.zip"
      failures << "release-artifact-summary.json expectedArtifactName must be Vifty-v#{release_summary["caskVersion"]}.zip"
    end
    %w[expectedSHA actualSHA].each do |field|
      unless release_summary[field].to_s.match?(/\A[0-9a-f]{64}\z/)
        failures << "release-artifact-summary.json #{field} must be a lowercase 64-character SHA-256 checksum"
      end
    end
    unless release_summary["expectedSHA"].to_s.empty? || release_summary["actualSHA"].to_s.empty? || release_summary["expectedSHA"].to_s == release_summary["actualSHA"].to_s
      failures << "release-artifact-summary.json expectedSHA must match actualSHA"
    end
    release_checks = release_summary["checks"]
    unless release_checks.is_a?(Array) && !release_checks.empty?
      failures << "release-artifact-summary.json checks must be a non-empty array"
      release_checks = []
    end
    release_checks.each do |check|
      unless check.is_a?(Hash)
        failures << "release-artifact-summary.json checks must contain objects"
        next
      end
      check_name = check["name"].to_s
      check_status = check["status"].to_s
      if check_name.empty?
        failures << "release-artifact-summary.json check is missing name"
      end
      if check_status != "passed"
        failures << "release-artifact-summary.json check #{check_name.empty? ? "(missing)" : check_name} status #{check_status.inspect} must be passed"
      end
    end

    release_rows = parse_tsv(bundle, "release-artifact-summary.tsv", failures)
    release_fields = release_rows.to_h { |row| [row["field"], row["value"]] }
    installed_version = release_fields["installedAppBundleVersion"].to_s
    if installed_version.empty?
      failures << "release-artifact-summary.tsv must include installedAppBundleVersion"
    elsif !release_summary["bundleVersion"].to_s.empty? && installed_version != release_summary["bundleVersion"].to_s
      failures << "installedAppBundleVersion must match release bundleVersion"
    end

    release_checklist_rows = parse_tsv(bundle, "release-checklist.tsv", failures)
    release_checklist_fields = release_checklist_rows.to_h { |row| [row["field"], row["value"]] }
    checklist_version = release_checklist_fields["titleVersion"].to_s
    if checklist_version.empty?
      failures << "release-checklist.tsv must include titleVersion"
    elsif !release_summary["caskVersion"].to_s.empty? && checklist_version != release_summary["caskVersion"].to_s
      failures << "release checklist titleVersion must match release caskVersion"
    end
    checklist_installed_version = release_checklist_fields["installedAppBundleVersion"].to_s
    if checklist_installed_version.empty?
      failures << "release-checklist.tsv must include installedAppBundleVersion"
    elsif !release_summary["bundleVersion"].to_s.empty? && checklist_installed_version != release_summary["bundleVersion"].to_s
      failures << "release checklist installedAppBundleVersion must match release bundleVersion"
    end
    %w[
      hasWorkflowSection
      hasFollowUpSection
      hasCaskChecksumFollowUp
      hasPublicVerifierFollowUp
      hasEvidenceReviewFollowUp
      hasCompatibilityGate
      hasTrustedHomebrewWarning
    ].each do |field|
      failures << "release-checklist.tsv #{field} must be true" unless release_checklist_fields[field].to_s == "true"
    end

    team_id = read_file(bundle, "launchdaemon-teamid.txt", failures).to_s.strip
    if team_id.empty?
      failures << "release mode requires non-empty LaunchDaemon VIFTY_XPC_ALLOWED_TEAM_ID"
    end
  end

  if failures.empty?
    write_review_result(summary_path, bundle, mode, "passed", failures, warnings, summary, diagnose, manual_smoke_result, manual_smoke_source)
    puts "Validation evidence review OK: mode #{mode}"
    puts "Bundle: #{bundle}"
    warnings.each { |warning| warn "warning: #{warning}" }
    exit 0
  end

  write_review_result(summary_path, bundle, mode, "failed", failures, warnings, summary, diagnose, manual_smoke_result, manual_smoke_source)
  warn "Validation evidence review failed: mode #{mode}"
  failures.each { |failure| warn "- #{failure}" }
  warnings.each { |warning| warn "warning: #{warning}" }
  exit 65
' "${BUNDLE_DIR}" "${MODE}" "${SUMMARY_PATH}" "${MANUAL_SMOKE_RESULT}" "${MANUAL_SMOKE_SOURCE}"
