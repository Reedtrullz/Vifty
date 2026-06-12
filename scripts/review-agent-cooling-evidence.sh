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
  privacy-review
].freeze

failures = []
warnings = []

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

def write_review_summary(summary_path, bundle, status, read_only, cooling_commands_run, commands_reviewed, failures, warnings)
  return unless summary_path

  FileUtils.mkdir_p(File.dirname(summary_path))
  review = {
    "schemaVersion" => 1,
    "generatedAtUTC" => Time.now.utc.iso8601,
    "bundlePath" => bundle,
    "status" => status,
    "readOnly" => read_only,
    "coolingCommandsRun" => cooling_commands_run,
    "commandsReviewed" => commands_reviewed,
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

%w[viftyctl-capabilities viftyctl-status viftyctl-audit].each do |name|
  status = integer_value(commands_by_name.dig(name, "status"))
  failures << "#{name} must exit 0 for a complete agent evidence review" unless status == 0
end

diagnose_status = integer_value(commands_by_name.dig("viftyctl-diagnose", "status"))
unless [0, 75].include?(diagnose_status)
  failures << "viftyctl-diagnose must exit 0 or 75 for reviewed read-only evidence"
end
warnings << "viftyctl-diagnose exited 75; blocked readiness is accepted as evidence" if diagnose_status == 75

%w[launchctl-print-daemon launchdaemon-plist helper-file-metadata].each do |name|
  status = integer_value(commands_by_name.dig(name, "status"))
  warnings << "#{name} exited #{status}; launchd/helper failures may still be useful evidence" if status && status != 0
end

privacy_status = integer_value(commands_by_name.dig("privacy-review", "status"))
failures << "privacy-review must exit 0 before sharing the bundle" unless privacy_status == 0
privacy_rows.each do |row|
  if row["finding"] == "redaction-needed"
    failures << "privacy-review found redaction-needed entry in #{row["file"]}:#{row["line"]}"
  end
end

audit_path = File.join(bundle, "viftyctl-audit.json")
if File.file?(audit_path)
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
write_review_summary(summary_path, bundle, status, read_only, cooling_commands_run, commands.length, failures, warnings)

warnings.each { |warning| warn "warning: #{warning}" }

if failures.empty?
  puts "Agent cooling evidence OK: #{bundle}"
  exit 0
end

failures.each { |failure| warn "failure: #{failure}" }
exit 65
RUBY
