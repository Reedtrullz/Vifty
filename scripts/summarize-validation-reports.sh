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

This script is read-only. It does not run viftyctl, ViftyHelper, launchctl,
codesign, stapler, spctl, or fan-control commands.

Options:
  --input <path>       review-result.json file or directory. Repeatable.
  --output-json <path> Write machine-readable summary JSON.
  --output-tsv <path>  Write TSV rows instead of printing them to stdout.
  -h, --help           Show this help.
USAGE
}

INPUTS=()
OUTPUT_JSON=""
OUTPUT_TSV=""
VALIDATION_REPORT_INDEX_SCHEMA_ID="https://vifty.local/schemas/validation-report-index.schema.json"

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

ruby -rjson -rcsv -rfileutils -e '
  schema_id = ARGV.shift.to_s
  output_json = ARGV.shift.to_s
  output_tsv = ARGV.shift.to_s
  inputs = ARGV
  failures = []

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

  def validate_result(path, result, failures)
    valid = true

    unless result["schemaVersion"] == 1
      failures << "#{path} schemaVersion must be 1"
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

    source_sha = result.fetch("sourceSHA", "").to_s
    unless source_sha.empty? || source_sha.match?(/\A[0-9a-f]{40}\z/)
      failures << "#{path} sourceSHA must be a lowercase 40-character git commit SHA"
      valid = false
    end

    source_artifact_sha = result.fetch("sourceArtifactSHA256", "").to_s
    unless source_artifact_sha.empty? || source_artifact_sha.match?(/\A[0-9a-f]{64}\z/)
      failures << "#{path} sourceArtifactSHA256 must be a lowercase 64-character SHA-256 checksum"
      valid = false
    end

    unless result["failures"].is_a?(Array)
      failures << "#{path} failures must be an array"
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

    valid
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

  paths = inputs.flat_map { |input| resolve_input(input, failures) }.uniq
  if paths.empty? && failures.empty?
    failures << "no review-result.json files found"
  end

  rows = []
  paths.each do |path|
    result = read_result(path, failures)
    next if result.nil?
    next unless validate_result(path, result, failures)

    warnings = result["warnings"].is_a?(Array) ? result["warnings"] : []
    failures_list = result["failures"].is_a?(Array) ? result["failures"] : []
    claim = claim_for(result)
    manual_smoke_required = claim == "supported-hardware-evidence-needs-manual-smoke"
    manual_smoke_result = result.fetch("manualSmokeTestResult", "not-recorded").to_s
    manual_smoke_validated = result["status"].to_s == "passed" &&
      result["mode"].to_s == "supported-hardware" &&
      manual_smoke_result == "passed-auto-restored"

    rows << {
      "source" => path,
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
      "manualSmokeValidated" => boolean_string(manual_smoke_validated),
      "modelIdentifier" => result["modelIdentifier"].to_s,
      "isAppleSilicon" => boolean_string(result["isAppleSilicon"]),
      "isMacBookPro" => boolean_string(result["isMacBookPro"]),
      "diagnoseState" => result["diagnoseState"].to_s,
      "safeToRequestCooling" => boolean_string(result["safeToRequestCooling"]),
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
  rows.each do |row|
    counts_by_mode[row["mode"]] += 1
    counts_by_claim[row["claim"]] += 1
    counts_by_install_source[row["installSource"]] += 1 unless row["installSource"].empty?
    counts_by_model[row["modelIdentifier"]] += 1 unless row["modelIdentifier"].empty?
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
    "validatedHardwareReports" => rows.count { |row| row["claim"] == "validated-hardware-evidence" },
    "countsByMode" => counts_by_mode.sort.to_h,
    "countsByClaim" => counts_by_claim.sort.to_h,
    "countsByInstallSource" => counts_by_install_source.sort.to_h,
    "countsByModelIdentifier" => counts_by_model.sort.to_h,
    "reports" => rows
  }

  headers = %w[
    source
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
    manualSmokeValidated
    modelIdentifier
    isAppleSilicon
    isMacBookPro
    diagnoseState
    safeToRequestCooling
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
' "${VALIDATION_REPORT_INDEX_SCHEMA_ID}" "${OUTPUT_JSON}" "${OUTPUT_TSV}" "${INPUTS[@]}"
