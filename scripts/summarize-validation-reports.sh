#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/summarize-validation-reports.sh --input <path> [options]

Summarize one or more review-result.json files produced by
scripts/review-validation-evidence.sh. Inputs may be files or directories; a
directory input resolves to its review-result.json file, or to nested
review-result.json files when the direct file is absent. Supported-hardware
reports are only classified as validated when the review result records
manualSmokeTestResult=passed-auto-restored.
Supervised viftyctl run smoke evidence is preserved as developer-workload
proof, but it does not replace the manual smoke gate for validated hardware.

This script is read-only. It does not run viftyctl, ViftyHelper, launchctl,
codesign, stapler, spctl, or fan-control commands.

Options:
  --input <path>       review-result.json file or directory. Repeatable.
  --output-json <path> Write machine-readable summary JSON.
  --output-tsv <path>  Write TSV rows instead of printing them to stdout.
  --output-markdown <path>
                       Write a conservative Markdown compatibility matrix draft.
  -h, --help           Show this help.
USAGE
}

INPUTS=()
OUTPUT_JSON=""
OUTPUT_TSV=""
OUTPUT_MARKDOWN=""
VALIDATION_REPORT_INDEX_SCHEMA_ID="https://vifty.local/schemas/validation-report-index.schema.json"
VALIDATION_REVIEW_RESULT_SCHEMA_ID="https://vifty.local/schemas/validation-review-result.schema.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      if [[ $# -lt 2 ]]; then
        echo "error: --input requires a path" >&2
        exit 64
      fi
      INPUTS+=("$2")
      shift 2
      ;;
    --output-json)
      if [[ $# -lt 2 ]]; then
        echo "error: --output-json requires a path" >&2
        exit 64
      fi
      OUTPUT_JSON="$2"
      shift 2
      ;;
    --output-tsv)
      if [[ $# -lt 2 ]]; then
        echo "error: --output-tsv requires a path" >&2
        exit 64
      fi
      OUTPUT_TSV="$2"
      shift 2
      ;;
    --output-markdown)
      if [[ $# -lt 2 ]]; then
        echo "error: --output-markdown requires a path" >&2
        exit 64
      fi
      OUTPUT_MARKDOWN="$2"
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

if [[ "${#INPUTS[@]}" -eq 0 ]]; then
  echo "error: at least one --input is required" >&2
  usage >&2
  exit 64
fi

ruby -rjson -rcsv -rfileutils -rpathname -rtime -e '
  schema_id = ARGV.shift.to_s
  review_result_schema_id = ARGV.shift.to_s
  output_json = ARGV.shift.to_s
  output_tsv = ARGV.shift.to_s
  output_markdown = ARGV.shift.to_s
  inputs = ARGV
  failures = []
  SOURCE_SHA_REQUIRED_INSTALL_SOURCES = %w[
    source-build-tag
    source-first-unsigned-dev-zip
    local-ad-hoc-build
  ].freeze

  def resolve_input(path, failures)
    expanded = File.expand_path(path)
    if File.file?(expanded)
      return [expanded]
    end

    unless File.directory?(expanded)
      failures << "input not found: #{path}"
      return []
    end

    direct = File.join(expanded, "review-result.json")
    return [direct] if File.file?(direct)

    nested = Dir.glob(File.join(expanded, "**", "review-result.json")).sort
    if nested.empty?
      failures << "no review-result.json files found under #{path}"
    end
    nested
  end

  def relative_child_path(path, base)
    relative = Pathname.new(path).relative_path_from(Pathname.new(base)).to_s
    return nil if relative == ".." || relative.start_with?("../")

    relative
  rescue ArgumentError
    nil
  end

  def display_source_for(path, input_roots)
    cwd_relative = relative_child_path(path, Dir.pwd)
    return cwd_relative unless cwd_relative.nil?

    input_relative = input_roots.map { |root| relative_child_path(path, root) }.compact
    input_relative.min_by(&:length) || File.basename(path)
  end

  def read_result(path, failures)
    data = JSON.parse(File.read(path))
    unless data.is_a?(Hash)
      failures << "#{path} did not contain a JSON object"
      return nil
    end
    data
  rescue StandardError => error
    failures << "could not parse #{path}: #{error.message}"
    nil
  end

  def validate_result(path, result, review_result_schema_id, failures)
    valid = true

    unless result["schemaVersion"] == 1
      failures << "#{path} schemaVersion must be 1"
      valid = false
    end

    unless result["schemaID"] == review_result_schema_id
      failures << "#{path} schemaID must be #{review_result_schema_id}"
      valid = false
    end

    unless iso8601_utc_timestamp?(result["generatedAtUTC"])
      failures << "#{path} generatedAtUTC must be an ISO-8601 UTC timestamp"
      valid = false
    end

    unless result["readOnly"] == true
      failures << "#{path} must declare readOnly=true"
      valid = false
    end

    unless result["coolingCommandsRun"] == false
      failures << "#{path} must declare coolingCommandsRun=false"
      valid = false
    end

    unless %w[passed failed].include?(result["status"].to_s)
      failures << "#{path} status must be passed or failed"
      valid = false
    end

    unless %w[release supported-hardware unsupported-hardware].include?(result["mode"].to_s)
      failures << "#{path} mode must be release, supported-hardware, or unsupported-hardware"
      valid = false
    end

    unless %w[not-recorded passed-auto-restored skipped-blocked skipped-unsupported failed].include?(result.fetch("manualSmokeTestResult", "").to_s)
      failures << "#{path} manualSmokeTestResult is not a supported value"
      valid = false
    end
    unless %w[not-recorded passed-auto-restored skipped-blocked skipped-unsupported failed].include?(result.fetch("agentRunSmokeResult", "").to_s)
      failures << "#{path} agentRunSmokeResult is not a supported value"
      valid = false
    end
    unless ["", "Auto", "Curve", "Fixed"].include?(result.fetch("agentRunSmokeStartupMode", "").to_s)
      failures << "#{path} agentRunSmokeStartupMode is not a supported value"
      valid = false
    end
    unless ["", "persisted", "defaultMissingFile", "defaultMissingKey", "unreadable", "unavailable"].include?(result.fetch("agentRunSmokeStartupModeSource", "").to_s)
      failures << "#{path} agentRunSmokeStartupModeSource is not a supported value"
      valid = false
    end

    unless %w[
      requestCooling
      requestCoolingWithCaution
      restoreAutoBeforeRequestingCooling
      doNotRequestCooling
    ].include?(result.fetch("recommendedAgentAction", "").to_s)
      failures << "#{path} recommendedAgentAction is not a supported value"
      valid = false
    end

    unless %w[
      none
      repairHelper
      restoreAutoBeforeRetry
      backOffWorkload
      inspectPolicy
      collectHardwareEvidence
    ].include?(result.fetch("recommendedRecoveryAction", "").to_s)
      failures << "#{path} recommendedRecoveryAction is not a supported value"
      valid = false
    end

    install_source = result.fetch("installSource", "").to_s
    unless install_source.empty? || %w[
      not-recorded
      source-build-tag
      source-first-unsigned-dev-zip
      notarized-github-release
      homebrew-cask
      local-developer-id-build
      local-ad-hoc-build
      other
    ].include?(install_source)
      failures << "#{path} installSource is not a supported value"
      valid = false
    end

    if result["mode"].to_s == "release" && !%w[
      notarized-github-release
      homebrew-cask
      local-developer-id-build
    ].include?(install_source)
      failures << "#{path} release mode requires installSource notarized-github-release, homebrew-cask, or local-developer-id-build"
      valid = false
    end

    source_sha = result.fetch("sourceSHA", "").to_s
    unless source_sha.empty? || source_sha.match?(/\A[0-9a-f]{40}\z/)
      failures << "#{path} sourceSHA must be a lowercase 40-character git commit SHA"
      valid = false
    end
    if SOURCE_SHA_REQUIRED_INSTALL_SOURCES.include?(install_source) && source_sha.empty?
      failures << "#{path} #{install_source} review result requires sourceSHA to pin the immutable source commit"
      valid = false
    end
    if %w[source-build-tag source-first-unsigned-dev-zip].include?(install_source) &&
        !result.fetch("sourceRef", "").to_s.match?(/\Av[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?\z/)
      failures << "#{path} #{install_source} review result requires sourceRef to be the version tag used for the source build"
      valid = false
    end

    source_artifact_sha = result.fetch("sourceArtifactSHA256", "").to_s
    unless source_artifact_sha.empty? || source_artifact_sha.match?(/\A[0-9a-f]{64}\z/)
      failures << "#{path} sourceArtifactSHA256 must be a lowercase 64-character SHA-256 checksum"
      valid = false
    end

    source_artifact_bytes = result.fetch("sourceArtifactBytes", "").to_s
    unless source_artifact_bytes.empty? || source_artifact_bytes.match?(/\A[1-9][0-9]*\z/)
      failures << "#{path} sourceArtifactBytes must be a positive integer"
      valid = false
    end

    unless result["failures"].is_a?(Array)
      failures << "#{path} failures must be an array"
      valid = false
    end

    unless [true, false].include?(result["daemonControlPathReady"])
      failures << "#{path} daemonControlPathReady must be true or false"
      valid = false
    end

    unless result["manualControlActive"].nil? || [true, false].include?(result["manualControlActive"])
      failures << "#{path} manualControlActive must be true, false, or null"
      valid = false
    end

    if result.key?("failedCheckIDs") && !string_array?(result["failedCheckIDs"])
      failures << "#{path} failedCheckIDs must be an array of strings"
      valid = false
    end

    if result.key?("coolingBlockerIDs") && !string_array?(result["coolingBlockerIDs"])
      failures << "#{path} coolingBlockerIDs must be an array of strings"
      valid = false
    end

    if string_array?(result["coolingBlockerIDs"]) && !result["coolingBlockerIDs"].empty? && result["safeToRequestCooling"] == true
      failures << "#{path} coolingBlockerIDs must be empty when safeToRequestCooling is true"
      valid = false
    end

    expected_model_family = model_family_for(result["modelIdentifier"])
    provided_model_family = result.fetch("modelFamily", "").to_s
    if !provided_model_family.empty? && provided_model_family != expected_model_family
      failures << "#{path} modelFamily #{provided_model_family.inspect} did not match derived modelIdentifier family #{expected_model_family.inspect}"
      valid = false
    end

    unless result["warnings"].is_a?(Array)
      failures << "#{path} warnings must be an array"
      valid = false
    end

    if result["status"].to_s == "passed" && result["failures"].is_a?(Array) && !result["failures"].empty?
      failures << "#{path} passed review results must not contain failures"
      valid = false
    end

    if result["status"].to_s == "failed" && result["failures"].is_a?(Array) && result["failures"].empty?
      failures << "#{path} failed review results must include at least one failure"
      valid = false
    end

    if result["manualSmokeTestResult"].to_s == "passed-auto-restored" &&
        result["manualSmokeTestSource"].to_s.strip.empty?
      failures << "#{path} manualSmokeTestSource is required when manualSmokeTestResult is passed-auto-restored"
      valid = false
    end
    if install_source == "local-ad-hoc-build" &&
        result["manualSmokeTestResult"].to_s == "passed-auto-restored" &&
        result.fetch("manualSmokeReadinessSource", "").to_s.strip.empty?
      failures << "#{path} manualSmokeReadinessSource is required for passed local-ad-hoc manual smoke evidence"
      valid = false
    end

    valid
  end

  def iso8601_utc_timestamp?(value)
    timestamp = value.to_s
    return false unless timestamp.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)

    Time.iso8601(timestamp)
    true
  rescue ArgumentError
    false
  end

  def reviewed_date_for(timestamp)
    Time.iso8601(timestamp.to_s).utc.strftime("%Y-%m-%d")
  rescue ArgumentError
    ""
  end

  def claim_for(result)
    return "rejected" unless result["status"].to_s == "passed"

    case result["mode"].to_s
    when "release"
      "release-trust-evidence"
    when "unsupported-hardware"
      "safe-block-evidence"
    when "supported-hardware"
      if result["manualSmokeTestResult"].to_s == "passed-auto-restored"
        "validated-hardware-evidence"
      else
        "supported-hardware-evidence-needs-manual-smoke"
      end
    else
      "unknown-mode"
    end
  end

  def boolean_string(value)
    case value
    when true
      "true"
    when false
      "false"
    else
      ""
    end
  end

  def string_array?(value)
    value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) }
  end

  def joined_string_array(value)
    return "" unless string_array?(value)

    value.join(",")
  end

  def model_family_for(model_identifier)
    value = model_identifier.to_s.strip
    return "" if value.empty?

    value.split(",", 2).first
  end

  def markdown_escape(value)
    value.to_s.gsub("|", "\\|").gsub(/\s+/, " ").strip
  end

  def join_unique(values)
    compact = values.map { |value| value.to_s.strip }.reject(&:empty?).uniq.sort
    compact.empty? ? "" : compact.join(", ")
  end

  def join_presence(values)
    normalized = values.map do |value|
      text = value.to_s.strip
      text.empty? ? "unknown" : text
    end.uniq.sort
    normalized.empty? ? "unknown" : normalized.join(", ")
  end

  def short_digest(value, length = 7)
    digest = value.to_s.strip
    return "" if digest.empty?

    digest[0, length]
  end

  def source_evidence_for(row)
    source_ref = row["sourceRef"].to_s.strip
    source_sha = row["sourceSHA"].to_s.strip
    artifact_name = row["sourceArtifactName"].to_s.strip
    artifact_sha = row["sourceArtifactSHA256"].to_s.strip

    source = if !source_ref.empty? && !source_sha.empty?
      "#{source_ref}@#{short_digest(source_sha)}"
    elsif !source_ref.empty?
      source_ref
    elsif !source_sha.empty?
      short_digest(source_sha)
    else
      ""
    end

    artifact = if !artifact_name.empty? && !artifact_sha.empty?
      "#{artifact_name}@#{short_digest(artifact_sha)}"
    else
      artifact_name
    end

    if source.empty?
      artifact
    elsif artifact.empty?
      source
    else
      "#{source} (#{artifact})"
    end
  end

  def compatibility_status_for(validated_count, candidate_count, safe_block_count, rejected_count)
    return "Validated hardware evidence" if validated_count.positive?
    return "Needs manual smoke" if candidate_count.positive?
    return "Expected blocked" if safe_block_count.positive?
    return "Rejected evidence" if rejected_count.positive?

    "Needs validation"
  end

  def readiness_evidence_for(group)
    lines = [
      "safeToRequestCooling=#{join_presence(group.map { |row| row["safeToRequestCooling"] })}",
      "daemonControlPathReady=#{join_presence(group.map { |row| row["daemonControlPathReady"] })}",
      "manualControlActive=#{join_presence(group.map { |row| row["manualControlActive"] })}",
      "agentAction=#{join_presence(group.map { |row| row["recommendedAgentAction"] })}",
      "recoveryAction=#{join_presence(group.map { |row| row["recommendedRecoveryAction"] })}"
    ]
    failed_ids = join_unique(group.map { |row| row["failedCheckIDs"] })
    blocker_ids = join_unique(group.map { |row| row["coolingBlockerIDs"] })
    lines << "failedCheckIDs=#{failed_ids}" unless failed_ids.empty?
    lines << "coolingBlockerIDs=#{blocker_ids}" unless blocker_ids.empty?
    lines.join("<br>")
  end

  def agent_run_startup_evidence_for(row)
    mode = row["agentRunSmokeStartupMode"].to_s.strip
    source = row["agentRunSmokeStartupModeSource"].to_s.strip
    read_error = row["agentRunSmokeStartupModeReadError"].to_s.strip
    return "" if mode.empty? && source.empty? && read_error.empty?

    mode_text = mode.empty? ? "unknown" : mode
    source_text = source.empty? ? "unknown" : source
    read_error_text = read_error.empty? ? "" : "; read error recorded"
    "#{mode_text} (#{source_text}#{read_error_text})"
  end

  def render_markdown_matrix(rows)
    hardware_rows = rows.reject { |row| row["mode"] == "release" }
    groups = Hash.new { |hash, key| hash[key] = [] }
    hardware_rows.each do |row|
      family = row["modelFamily"].to_s.empty? ? "unknown" : row["modelFamily"].to_s
      groups[family] << row
    end

    lines = [
      "# Vifty Compatibility Matrix Draft",
      "",
      "Generated from reviewed validation report summaries. Treat source-first and unsigned-dev reports as compatibility evidence only; they are not Developer ID, notarization, Homebrew, or trusted binary evidence.",
      "",
      "| Model family | Public status | Validated reports | Candidate reports | Agent run smoke reports | Safe-block reports | Rejected reports | Model identifiers | Install sources | Readiness | Evidence |",
      "| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |"
    ]

    if groups.empty?
      lines << "| No reviewed hardware reports | Needs validation | 0 | 0 | 0 | 0 | 0 |  |  |  | Add reviewed `review-result.json` files before changing public claims. |"
      return lines.join("\n") + "\n"
    end

    groups.sort.each do |family, group|
      validated_count = group.count { |row| row["claim"] == "validated-hardware-evidence" }
      candidate_count = group.count { |row| row["claim"] == "supported-hardware-evidence-needs-manual-smoke" }
      safe_block_count = group.count { |row| row["claim"] == "safe-block-evidence" }
      rejected_count = group.count { |row| row["claim"] == "rejected" }
      agent_run_count = group.count { |row| row["agentRunSmokeValidated"] == "true" }
      status = compatibility_status_for(validated_count, candidate_count, safe_block_count, rejected_count)
      identifiers = join_unique(group.map { |row| row["modelIdentifier"] })
      install_sources = join_unique(group.map { |row| row["installSource"] })
      readiness = readiness_evidence_for(group)

      evidence = []
      source_joined = join_unique(group.map { |row| source_evidence_for(row) })
      reviewed_joined = join_unique(group.map { |row| reviewed_date_for(row["reviewGeneratedAtUTC"]) })
      manual_sources = group.select { |row| row["manualSmokeValidated"] == "true" }.map { |row| row["manualSmokeTestSource"] }
      agent_sources = group.select { |row| row["agentRunSmokeValidated"] == "true" }.map { |row| row["agentRunSmokeSource"] }
      manual_joined = join_unique(manual_sources)
      agent_joined = join_unique(agent_sources)
      agent_startup_joined = join_unique(group.map { |row| agent_run_startup_evidence_for(row) })
      evidence << "source: #{source_joined}" unless source_joined.empty?
      evidence << "reviewed: #{reviewed_joined}" unless reviewed_joined.empty?
      evidence << "manual: #{manual_joined}" unless manual_joined.empty?
      evidence << "manual: not recorded" if candidate_count.positive? && validated_count.zero?
      evidence << "agent-run: #{agent_joined}" unless agent_joined.empty?
      evidence << "agent-run startup: #{agent_startup_joined}" unless agent_startup_joined.empty?
      evidence << "reviewed index only" if evidence.empty?

      lines << [
        family,
        status,
        validated_count,
        candidate_count,
        agent_run_count,
        safe_block_count,
        rejected_count,
        identifiers,
        install_sources,
        readiness,
        evidence.join("<br>")
      ].map { |value| markdown_escape(value) }.join(" | ").then { |row| "| #{row} |" }
    end

    lines.join("\n") + "\n"
  end

  input_roots = inputs.map do |input|
    expanded = File.expand_path(input)
    File.directory?(expanded) ? expanded : File.dirname(expanded)
  end.uniq

  paths = inputs.flat_map { |input| resolve_input(input, failures) }.uniq
  if paths.empty? && failures.empty?
    failures << "no review-result.json files found"
  end

  rows = []
  paths.each do |path|
    result = read_result(path, failures)
    next if result.nil?
    next unless validate_result(path, result, review_result_schema_id, failures)

    warnings = result["warnings"].is_a?(Array) ? result["warnings"] : []
    failures_list = result["failures"].is_a?(Array) ? result["failures"] : []
    claim = claim_for(result)
    manual_smoke_required = claim == "supported-hardware-evidence-needs-manual-smoke"
    manual_smoke_result = result.fetch("manualSmokeTestResult", "not-recorded").to_s
    agent_run_smoke_result = result.fetch("agentRunSmokeResult", "not-recorded").to_s
    manual_smoke_validated = result["status"].to_s == "passed" &&
      result["mode"].to_s == "supported-hardware" &&
      manual_smoke_result == "passed-auto-restored"
    agent_run_smoke_validated = result["status"].to_s == "passed" &&
      agent_run_smoke_result == "passed-auto-restored"
    model_identifier = result["modelIdentifier"].to_s
    model_family = result["modelFamily"].to_s.empty? ? model_family_for(model_identifier) : result["modelFamily"].to_s

    rows << {
      "source" => display_source_for(path, input_roots),
      "reviewGeneratedAtUTC" => result["generatedAtUTC"].to_s,
      "status" => result["status"].to_s,
      "mode" => result["mode"].to_s,
      "claim" => claim,
      "installSource" => result["installSource"].to_s,
      "sourceRef" => result["sourceRef"].to_s,
      "sourceSHA" => result["sourceSHA"].to_s,
      "sourceArtifactName" => result["sourceArtifactName"].to_s,
      "sourceArtifactSHA256" => result["sourceArtifactSHA256"].to_s,
      "manualSmokeTestResult" => manual_smoke_result,
      "manualSmokeTestSource" => result["manualSmokeTestSource"].to_s,
      "manualSmokeReadinessSource" => result["manualSmokeReadinessSource"].to_s,
      "manualSmokeValidated" => boolean_string(manual_smoke_validated),
      "agentRunSmokeResult" => agent_run_smoke_result,
      "agentRunSmokeSource" => result["agentRunSmokeSource"].to_s,
      "agentRunSmokeValidated" => boolean_string(agent_run_smoke_validated),
      "agentRunSmokeStartupMode" => result["agentRunSmokeStartupMode"].to_s,
      "agentRunSmokeStartupModeSource" => result["agentRunSmokeStartupModeSource"].to_s,
      "agentRunSmokeStartupModeReadError" => result["agentRunSmokeStartupModeReadError"].to_s,
      "modelIdentifier" => model_identifier,
      "modelFamily" => model_family,
      "isAppleSilicon" => boolean_string(result["isAppleSilicon"]),
      "isMacBookPro" => boolean_string(result["isMacBookPro"]),
      "diagnoseState" => result["diagnoseState"].to_s,
      "recommendedAgentAction" => result["recommendedAgentAction"].to_s,
      "recommendedRecoveryAction" => result["recommendedRecoveryAction"].to_s,
      "failedCheckIDs" => joined_string_array(result["failedCheckIDs"]),
      "coolingBlockerIDs" => joined_string_array(result["coolingBlockerIDs"]),
      "safeToRequestCooling" => boolean_string(result["safeToRequestCooling"]),
      "daemonControlPathReady" => boolean_string(result["daemonControlPathReady"]),
      "manualControlActive" => boolean_string(result["manualControlActive"]),
      "manualSmokeRequired" => boolean_string(manual_smoke_required),
      "warningCount" => warnings.count.to_s,
      "failureCount" => failures_list.count.to_s
    }
  end

  unless failures.empty?
    failures.each { |failure| warn failure }
    exit 65
  end

  passed_rows = rows.select { |row| row["status"] == "passed" }
  counts_by_mode = Hash.new(0)
  counts_by_claim = Hash.new(0)
  counts_by_install_source = Hash.new(0)
  counts_by_model = Hash.new(0)
  counts_by_model_family = Hash.new(0)
  validated_by_model_family = Hash.new(0)
  counts_by_agent_action = Hash.new(0)
  counts_by_recovery_action = Hash.new(0)
  counts_by_safe_to_request = Hash.new(0)
  counts_by_daemon_control_path = Hash.new(0)
  counts_by_manual_control_active = Hash.new(0)
  rows.each do |row|
    counts_by_mode[row["mode"]] += 1
    counts_by_claim[row["claim"]] += 1
    counts_by_install_source[row["installSource"]] += 1 unless row["installSource"].empty?
    counts_by_model[row["modelIdentifier"]] += 1 unless row["modelIdentifier"].empty?
    counts_by_model_family[row["modelFamily"]] += 1 unless row["modelFamily"].empty?
    if row["claim"] == "validated-hardware-evidence" && !row["modelFamily"].empty?
      validated_by_model_family[row["modelFamily"]] += 1
    end
    counts_by_agent_action[row["recommendedAgentAction"]] += 1 unless row["recommendedAgentAction"].empty?
    counts_by_recovery_action[row["recommendedRecoveryAction"]] += 1 unless row["recommendedRecoveryAction"].empty?
    counts_by_safe_to_request[row["safeToRequestCooling"]] += 1 unless row["safeToRequestCooling"].empty?
    counts_by_daemon_control_path[row["daemonControlPathReady"]] += 1 unless row["daemonControlPathReady"].empty?
    counts_by_manual_control_active[row["manualControlActive"]] += 1 unless row["manualControlActive"].empty?
  end

  summary = {
    "schemaVersion" => 1,
    "schemaID" => schema_id,
    "generatedAtUTC" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "readOnly" => true,
    "coolingCommandsRun" => false,
    "totalReports" => rows.count,
    "passedReports" => passed_rows.count,
    "failedReports" => rows.count - passed_rows.count,
    "manualSmokeRequiredReports" => rows.count { |row| row["manualSmokeRequired"] == "true" },
    "manualSmokePassedReports" => rows.count { |row| row["manualSmokeValidated"] == "true" },
    "agentRunSmokePassedReports" => rows.count { |row| row["agentRunSmokeValidated"] == "true" },
    "validatedHardwareReports" => rows.count { |row| row["claim"] == "validated-hardware-evidence" },
    "countsByMode" => counts_by_mode.sort.to_h,
    "countsByClaim" => counts_by_claim.sort.to_h,
    "countsByInstallSource" => counts_by_install_source.sort.to_h,
    "countsByModelIdentifier" => counts_by_model.sort.to_h,
    "countsByModelFamily" => counts_by_model_family.sort.to_h,
    "validatedHardwareReportsByModelFamily" => validated_by_model_family.sort.to_h,
    "countsByRecommendedAgentAction" => counts_by_agent_action.sort.to_h,
    "countsByRecommendedRecoveryAction" => counts_by_recovery_action.sort.to_h,
    "countsBySafeToRequestCooling" => counts_by_safe_to_request.sort.to_h,
    "countsByDaemonControlPathReady" => counts_by_daemon_control_path.sort.to_h,
    "countsByManualControlActive" => counts_by_manual_control_active.sort.to_h,
    "reports" => rows
  }

  headers = %w[
    source
    reviewGeneratedAtUTC
    status
    mode
    claim
    installSource
    sourceRef
    sourceSHA
    sourceArtifactName
    sourceArtifactSHA256
    manualSmokeTestResult
    manualSmokeTestSource
    manualSmokeReadinessSource
    manualSmokeValidated
    agentRunSmokeResult
    agentRunSmokeSource
    agentRunSmokeValidated
    agentRunSmokeStartupMode
    agentRunSmokeStartupModeSource
    agentRunSmokeStartupModeReadError
    modelIdentifier
    modelFamily
    isAppleSilicon
    isMacBookPro
    diagnoseState
    recommendedAgentAction
    recommendedRecoveryAction
    failedCheckIDs
    coolingBlockerIDs
    safeToRequestCooling
    daemonControlPathReady
    manualControlActive
    manualSmokeRequired
    warningCount
    failureCount
  ]
  tsv = CSV.generate(col_sep: "\t") do |csv|
    csv << headers
    rows.each do |row|
      csv << headers.map { |header| row[header] }
    end
  end

  unless output_json.empty?
    directory = File.dirname(output_json)
    FileUtils.mkdir_p(directory) unless directory == "." || Dir.exist?(directory)
    File.write(output_json, JSON.pretty_generate(summary) + "\n")
  end

  if output_tsv.empty?
    print tsv
  else
    directory = File.dirname(output_tsv)
    FileUtils.mkdir_p(directory) unless directory == "." || Dir.exist?(directory)
    File.write(output_tsv, tsv)
  end

  unless output_markdown.empty?
    directory = File.dirname(output_markdown)
    FileUtils.mkdir_p(directory) unless directory == "." || Dir.exist?(directory)
    File.write(output_markdown, render_markdown_matrix(rows))
  end
' "${VALIDATION_REPORT_INDEX_SCHEMA_ID}" "${VALIDATION_REVIEW_RESULT_SCHEMA_ID}" "${OUTPUT_JSON}" "${OUTPUT_TSV}" "${OUTPUT_MARKDOWN}" "${INPUTS[@]}"
