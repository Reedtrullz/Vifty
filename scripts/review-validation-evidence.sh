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
  --manual-smoke-readiness-summary <path>
                         Captured manual-smoke-readiness JSON from
                         scripts/check-manual-smoke-readiness.sh --json. For
                         passed local-ad-hoc manual smoke evidence, the
                         reviewer requires this summary to prove the installed
                         daemon matched the expected build daemon before smoke.
  --agent-run-smoke-result <result>
                         Supervised viftyctl run smoke-test answer. One of:
                         not-recorded, passed-auto-restored, skipped-blocked,
                         skipped-unsupported, failed. Defaults to not-recorded.
  --agent-run-smoke-source <text>
                         Issue URL, note, or other source for the supervised
                         viftyctl run smoke result.
  --agent-run-smoke-readiness-summary <path>
                         Captured agent-run-smoke-readiness JSON from
                         scripts/check-agent-run-smoke-readiness.sh --json.
                         For passed local-ad-hoc agent-run smoke evidence
                         without a captured smoke bundle, the reviewer requires
                         this summary to prove the preflight was read-only,
                         safe, and daemon-matched before smoke.
  --agent-run-smoke-summary <path>
                         Captured agent-run-smoke-evidence-summary.json from
                         scripts/collect-agent-run-smoke-evidence.sh. When
                         supplied, the reviewer validates schema identity and
                         derives agent-run smoke result/source from the file.
  -h, --help             Show this help.
USAGE
}

BUNDLE_DIR=""
MODE="supported-hardware"
SUMMARY_PATH=""
MANUAL_SMOKE_RESULT="not-recorded"
MANUAL_SMOKE_SOURCE=""
MANUAL_SMOKE_READINESS_SUMMARY_PATH=""
AGENT_RUN_SMOKE_RESULT="not-recorded"
AGENT_RUN_SMOKE_SOURCE=""
AGENT_RUN_SMOKE_READINESS_SUMMARY_PATH=""
AGENT_RUN_SMOKE_SUMMARY_PATH=""

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
    --manual-smoke-readiness-summary)
      if [[ $# -lt 2 ]]; then
        echo "error: --manual-smoke-readiness-summary requires a path" >&2
        exit 64
      fi
      MANUAL_SMOKE_READINESS_SUMMARY_PATH="$2"
      shift 2
      ;;
    --agent-run-smoke-result)
      if [[ $# -lt 2 ]]; then
        echo "error: --agent-run-smoke-result requires a value" >&2
        exit 64
      fi
      AGENT_RUN_SMOKE_RESULT="$2"
      shift 2
      ;;
    --agent-run-smoke-source)
      if [[ $# -lt 2 ]]; then
        echo "error: --agent-run-smoke-source requires text" >&2
        exit 64
      fi
      AGENT_RUN_SMOKE_SOURCE="$2"
      shift 2
      ;;
    --agent-run-smoke-readiness-summary)
      if [[ $# -lt 2 ]]; then
        echo "error: --agent-run-smoke-readiness-summary requires a path" >&2
        exit 64
      fi
      AGENT_RUN_SMOKE_READINESS_SUMMARY_PATH="$2"
      shift 2
      ;;
    --agent-run-smoke-summary)
      if [[ $# -lt 2 ]]; then
        echo "error: --agent-run-smoke-summary requires a path" >&2
        exit 64
      fi
      AGENT_RUN_SMOKE_SUMMARY_PATH="$2"
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

case "${AGENT_RUN_SMOKE_RESULT}" in
  not-recorded|passed-auto-restored|skipped-blocked|skipped-unsupported|failed)
    ;;
  *)
    echo "error: unsupported agent run smoke result: ${AGENT_RUN_SMOKE_RESULT}" >&2
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
  manual_smoke_readiness_summary_path = ARGV.fetch(5, "")
  agent_run_smoke_result = ARGV.fetch(6, "not-recorded")
  agent_run_smoke_source = ARGV.fetch(7, "")
  agent_run_smoke_readiness_summary_path = ARGV.fetch(8, "")
  agent_run_smoke_summary_path = ARGV.fetch(9, "")
  failures = []
  warnings = []
  VALIDATION_REVIEW_RESULT_SCHEMA_ID = "https://vifty.local/schemas/validation-review-result.schema.json"
  MANUAL_SMOKE_READINESS_SCHEMA_ID = "https://vifty.local/schemas/manual-smoke-readiness.schema.json"
  AGENT_RUN_SMOKE_READINESS_SCHEMA_ID = "https://vifty.local/schemas/agent-run-smoke-readiness.schema.json"
  AGENT_RUN_SMOKE_SUMMARY_SCHEMA_ID = "https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json"
  CAPABILITIES_SCHEMA_ID = "https://vifty.local/schemas/viftyctl-capabilities.schema.json"
  DIAGNOSE_SCHEMA_ID = "https://vifty.local/schemas/viftyctl-diagnose.schema.json"
  COMMAND_ERROR_SCHEMA_ID = "https://vifty.local/schemas/viftyctl-command-error.schema.json"
  RUN_SCHEMA_ID = "https://vifty.local/schemas/viftyctl-run.schema.json"

  EXPECTED_EXECUTABLES = {
    "Vifty" => "Contents/MacOS/Vifty",
    "ViftyHelper" => "Contents/MacOS/ViftyHelper",
    "ViftyDaemon" => "Contents/MacOS/ViftyDaemon",
    "viftyctl" => "Contents/MacOS/viftyctl"
  }.freeze

  EXPECTED_SCHEMA_RESOURCES = {
    "agent-cooling-evidence-summary.schema.json" => "Contents/Resources/schemas/agent-cooling-evidence-summary.schema.json",
    "agent-cooling-evidence-review.schema.json" => "Contents/Resources/schemas/agent-cooling-evidence-review.schema.json",
    "agent-run-smoke-readiness.schema.json" => "Contents/Resources/schemas/agent-run-smoke-readiness.schema.json",
    "agent-run-smoke-evidence-summary.schema.json" => "Contents/Resources/schemas/agent-run-smoke-evidence-summary.schema.json",
    "guarded-run-decision.schema.json" => "Contents/Resources/schemas/guarded-run-decision.schema.json",
    "manual-smoke-readiness.schema.json" => "Contents/Resources/schemas/manual-smoke-readiness.schema.json",
    "release-artifact-summary.schema.json" => "Contents/Resources/schemas/release-artifact-summary.schema.json",
    "release-readiness.schema.json" => "Contents/Resources/schemas/release-readiness.schema.json",
    "validation-report-index.schema.json" => "Contents/Resources/schemas/validation-report-index.schema.json",
    "validation-review-result.schema.json" => "Contents/Resources/schemas/validation-review-result.schema.json",
    "viftyctl-audit.schema.json" => "Contents/Resources/schemas/viftyctl-audit.schema.json",
    "viftyctl-agent-rule.schema.json" => "Contents/Resources/schemas/viftyctl-agent-rule.schema.json",
    "viftyctl-capabilities.schema.json" => "Contents/Resources/schemas/viftyctl-capabilities.schema.json",
    "viftyctl-command-error.schema.json" => "Contents/Resources/schemas/viftyctl-command-error.schema.json",
    "viftyctl-diagnose.schema.json" => "Contents/Resources/schemas/viftyctl-diagnose.schema.json",
    "viftyctl-run.schema.json" => "Contents/Resources/schemas/viftyctl-run.schema.json",
    "viftyctl-status.schema.json" => "Contents/Resources/schemas/viftyctl-status.schema.json"
  }.freeze

  EXPECTED_CAPABILITIES_SCHEMA_RESOURCES = {
    "audit" => "Contents/Resources/schemas/viftyctl-audit.schema.json",
    "agentRule" => "Contents/Resources/schemas/viftyctl-agent-rule.schema.json",
    "capabilities" => "Contents/Resources/schemas/viftyctl-capabilities.schema.json",
    "commandError" => "Contents/Resources/schemas/viftyctl-command-error.schema.json",
    "diagnose" => "Contents/Resources/schemas/viftyctl-diagnose.schema.json",
    "run" => "Contents/Resources/schemas/viftyctl-run.schema.json",
    "status" => "Contents/Resources/schemas/viftyctl-status.schema.json"
  }.freeze

  EXPECTED_CAPABILITIES_CONTRACT = {
    "policyStatusAvailable" => "true",
    "policy.enabled" => "true",
    "supportsForceRetry" => "true",
    "runLifecycle.childCommandPreflightBeforeCooling" => "true",
    "runLifecycle.autoRestoreAfterChildExit" => "true",
    "runLifecycle.structuredPreChildFailures" => "true",
    "runLifecycle.cleanupStateReportedOnLaunchFailure" => "true",
    "runLifecycle.resolvedChildExecutableReported" => "true",
    "runLifecycle.signalsForwardedToChild" => "INT,TERM,HUP",
    "directControlLifecycle.prepareUsesIdempotencyKey" => "true",
    "directControlLifecycle.restoreAutoAcceptsIdempotencyKey" => "false",
    "directControlLifecycle.restoreAutoScopedByIdempotencyKey" => "false",
    "directControlLifecycle.preferRunForSingleChildWorkloads" => "true",
    "metadataLimits.maximumReasonLength" => "512",
    "metadataLimits.maximumIdempotencyKeyLength" => "256",
    "wrapperResources.sourceDirectory" => "examples/viftyctl",
    "wrapperResources.bundleDirectory" => "Contents/Resources/viftyctl-wrappers",
    "wrapperResources.guardedRunScript" => "guarded-run.sh",
    "wrapperResources.workloadScripts" => "bun-build.sh,bun-test.sh,cargo-build.sh,cargo-test.sh,custom-workload.sh,go-build.sh,go-test.sh,local-model.sh,make-build.sh,make-test.sh,make-verify.sh,npm-build.sh,npm-test.sh,pnpm-build.sh,pnpm-test.sh,pytest.sh,swift-release-build.sh,swift-test.sh,uv-build.sh,uv-test.sh,xcode-build.sh,xcode-test.sh"
  }.freeze

  SUPPORTED_INSTALL_SOURCES = %w[
    not-recorded
    source-build-tag
    source-first-unsigned-dev-zip
    notarized-github-release
    homebrew-cask
    local-developer-id-build
    local-ad-hoc-build
    other
  ].freeze

  SOURCE_SHA_REQUIRED_INSTALL_SOURCES = %w[
    source-build-tag
    source-first-unsigned-dev-zip
    local-ad-hoc-build
  ].freeze

  RELEASE_INSTALL_SOURCES = %w[
    notarized-github-release
    homebrew-cask
    local-developer-id-build
  ].freeze

  REQUIRED_COMMON_FILES = %w[
    review-summary.json
    review-summary.tsv
    manifest.tsv
    checksums.tsv
    metadata.txt
    viftyctl-diagnose.json
    viftyctl-audit.json
    install-provenance.tsv
    bundle-executables.tsv
    privacy-review.tsv
    schema-resources.tsv
    capabilities-schema-resources.tsv
    capabilities-contract.tsv
  ].freeze

  COMMON_ZERO_CHECKS = %w[
    app-info-plist
    install-provenance
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

  def string_array?(value)
    value.is_a?(Array) && value.all? { |entry| entry.is_a?(String) }
  end

  def require_sha256(value, field, failures)
    return if value.to_s.match?(/\A[0-9a-f]{64}\z/)

    failures << "#{field} must be a lowercase 64-character SHA-256 checksum"
  end

  def require_recommended_recovery_action(value, field, failures)
    return if %w[
      none
      repairHelper
      restoreAutoBeforeRetry
      backOffWorkload
      inspectPolicy
      collectHardwareEvidence
    ].include?(value.to_s)

    failures << "#{field} must be one of none, repairHelper, restoreAutoBeforeRetry, backOffWorkload, inspectPolicy, collectHardwareEvidence"
  end

  def require_git_sha(value, field, failures)
    return if value.to_s.empty? || value.to_s.match?(/\A[0-9a-f]{40}\z/)

    failures << "#{field} must be a lowercase 40-character git commit SHA"
  end

  def field_rows_to_map(rows, relative_path, failures)
    if rows.empty?
      failures << "#{relative_path} must include field rows"
      return {}
    end

    missing_headers = %w[field value].reject { |header| rows.first.key?(header) }
    unless missing_headers.empty?
      failures << "#{relative_path} is missing required header(s): #{missing_headers.join(", ")}"
      return {}
    end

    fields = {}
    rows.each do |row|
      field = row["field"].to_s
      next if field.empty?
      if fields.key?(field)
        failures << "#{relative_path} has duplicate field #{field}"
        next
      end
      fields[field] = row["value"].to_s
    end
    fields
  end

  def validate_install_provenance(fields, failures, warnings)
    install_source = fields["installSource"].to_s
    unless SUPPORTED_INSTALL_SOURCES.include?(install_source)
      failures << "install-provenance.tsv installSource #{install_source.inspect} is not supported"
    end

    require_git_sha(fields["sourceSHA"], "install-provenance.tsv sourceSHA", failures)
    unless fields["sourceArtifactSHA256"].to_s.empty?
      require_sha256(fields["sourceArtifactSHA256"], "install-provenance.tsv sourceArtifactSHA256", failures)
    end
    unless fields["sourceArtifactBytes"].to_s.empty?
      require_positive_integer(fields["sourceArtifactBytes"], "install-provenance.tsv sourceArtifactBytes", failures)
    end

    if install_source.empty? || install_source == "not-recorded"
      warnings << "install source provenance is not recorded; keep compatibility and trust claims conservative"
    end
    if SOURCE_SHA_REQUIRED_INSTALL_SOURCES.include?(install_source) && fields["sourceSHA"].to_s.empty?
      failures << "#{install_source} evidence requires install-provenance.tsv sourceSHA to pin the immutable source commit"
    end
    if %w[source-build-tag source-first-unsigned-dev-zip].include?(install_source) &&
        !fields["sourceRef"].to_s.match?(/\Av[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?\z/)
      failures << "#{install_source} evidence requires install-provenance.tsv sourceRef to be the version tag used for the source build"
    end
    if install_source == "source-first-unsigned-dev-zip" && fields["sourceArtifactSHA256"].to_s.empty?
      warnings << "source-first unsigned-dev zip evidence should include sourceArtifactSHA256 when the tester zip is available"
    end
  end

  def parse_external_json(path, failures, label)
    unless File.file?(path)
      failures << "#{label} not found: #{path}"
      return nil
    end
    JSON.parse(File.read(path))
  rescue StandardError => error
    failures << "could not parse #{label}: #{error.message}"
    nil
  end

  def parse_external_tsv(path, failures, label)
    unless File.file?(path)
      failures << "#{label} not found: #{path}"
      return []
    end
    CSV.parse(File.read(path), col_sep: "\t", headers: true).map(&:to_h)
  rescue StandardError => error
    failures << "could not parse #{label}: #{error.message}"
    []
  end

  def agent_run_smoke_local_filename(value, field, failures)
    relative_path = value.to_s
    if relative_path.empty?
      failures << "agent-run-smoke #{field} is empty"
      return nil
    end
    if relative_path.include?("/") || relative_path.start_with?(".")
      failures << "agent-run-smoke #{field} #{relative_path.inspect} must be a bundle-local filename"
      return nil
    end
    relative_path
  end

  def agent_run_smoke_share_safe_source(summary_path)
    "#{File.basename(File.dirname(summary_path))}/#{File.basename(summary_path)}"
  end

  def manual_smoke_readiness_share_safe_source(summary_path)
    "#{File.basename(File.dirname(summary_path))}/#{File.basename(summary_path)}"
  end

  def agent_run_smoke_readiness_share_safe_source(summary_path)
    "#{File.basename(File.dirname(summary_path))}/#{File.basename(summary_path)}"
  end

  def likely_user_home_path?(value)
    value.to_s.match?(%r{/Users/[^/\s]+})
  end

  def validate_manual_smoke_readiness_daemon_runtime(summary, failures)
    daemon_runtime = summary["daemonRuntime"]
    unless daemon_runtime.is_a?(Hash)
      failures << "manual-smoke readiness summary daemonRuntime is required"
      return
    end

    unless [true, false].include?(daemon_runtime["installedDaemonPresent"])
      failures << "manual-smoke readiness summary daemonRuntime.installedDaemonPresent must be boolean"
    end
    unless [true, false].include?(daemon_runtime["matchRequired"])
      failures << "manual-smoke readiness summary daemonRuntime.matchRequired must be boolean"
    end
    unless [true, false, nil].include?(daemon_runtime["matchesExpectedDaemon"])
      failures << "manual-smoke readiness summary daemonRuntime.matchesExpectedDaemon must be boolean or null"
    end
    unless daemon_runtime["installedDaemonSHA256"].nil?
      require_sha256(
        daemon_runtime["installedDaemonSHA256"],
        "manual-smoke readiness summary daemonRuntime.installedDaemonSHA256",
        failures
      )
    end
    unless daemon_runtime["expectedDaemonSHA256"].nil?
      require_sha256(
        daemon_runtime["expectedDaemonSHA256"],
        "manual-smoke readiness summary daemonRuntime.expectedDaemonSHA256",
        failures
      )
    end
  end

  def validate_manual_smoke_readiness_summary(path, expected_schema_id, diagnose, failures)
    summary = parse_external_json(path, failures, "manual-smoke readiness summary")
    return nil if summary.nil?

    unless summary["schemaVersion"] == 1
      failures << "manual-smoke readiness summary schemaVersion must be 1"
    end
    unless summary["schemaID"] == expected_schema_id
      failures << "manual-smoke readiness summary schemaID must be #{expected_schema_id}"
    end
    unless summary["kind"].to_s == "vifty-manual-smoke-readiness"
      failures << "manual-smoke readiness summary kind must be vifty-manual-smoke-readiness"
    end
    unless summary["readOnly"] == true
      failures << "manual-smoke readiness summary must declare readOnly=true"
    end
    unless summary["coolingCommandsRun"] == false
      failures << "manual-smoke readiness summary must declare coolingCommandsRun=false"
    end
    unless summary["status"].to_s == "ready" && summary["manualSmokeReady"] == true
      failures << "manual-smoke readiness summary must be ready before a passed manual smoke claim"
    end
    unless summary["diagnoseExitStatus"] == 0
      failures << "manual-smoke readiness summary diagnoseExitStatus must be 0 before passed manual smoke"
    end
    unless %w[ready degraded].include?(summary["diagnoseState"].to_s)
      failures << "manual-smoke readiness summary diagnoseState must be ready or degraded"
    end
    unless summary["safeToRequestCooling"] == true
      failures << "manual-smoke readiness summary safeToRequestCooling must be true"
    end
    unless summary["daemonControlPathReady"] == true
      failures << "manual-smoke readiness summary daemonControlPathReady must be true"
    end
    unless summary["manualControlActive"] == false
      failures << "manual-smoke readiness summary manualControlActive must be false"
    end
    unless summary["isAppleSilicon"] == true && summary["isMacBookPro"] == true
      failures << "manual-smoke readiness summary must be from an Apple Silicon MacBook Pro"
    end
    require_positive_integer(summary["fanCount"], "manual-smoke readiness summary fanCount", failures)
    require_positive_integer(summary["controllableFanCount"], "manual-smoke readiness summary controllableFanCount", failures)
    require_positive_integer(summary["temperatureSensorCount"], "manual-smoke readiness summary temperatureSensorCount", failures)
    failures << "manual-smoke readiness summary failedCheckIDs must be an array of strings" unless string_array?(summary["failedCheckIDs"])
    failures << "manual-smoke readiness summary coolingBlockerIDs must be an array of strings" unless string_array?(summary["coolingBlockerIDs"])
    if string_array?(summary["coolingBlockerIDs"]) && !summary["coolingBlockerIDs"].empty?
      failures << "manual-smoke readiness summary coolingBlockerIDs must be empty before passed manual smoke"
    end
    unless summary["parseError"].nil?
      failures << "manual-smoke readiness summary parseError must be null before passed manual smoke"
    end

    %w[
      modelIdentifier
      isAppleSilicon
      isMacBookPro
      safeToRequestCooling
      daemonControlPathReady
      manualControlActive
      fanCount
      controllableFanCount
      temperatureSensorCount
    ].each do |field|
      next if diagnose[field].nil? && summary[field].nil?
      unless summary[field] == diagnose[field]
        failures << "manual-smoke readiness summary #{field} must match viftyctl-diagnose.json"
      end
    end

    validate_manual_smoke_readiness_daemon_runtime(summary, failures)
    summary
  end

  def validate_agent_run_smoke_readiness_daemon_runtime(summary, failures)
    daemon_runtime = summary["daemonRuntime"]
    unless daemon_runtime.is_a?(Hash)
      failures << "agent-run-smoke readiness summary daemonRuntime is required"
      return
    end

    unless [true, false].include?(daemon_runtime["installedDaemonPresent"])
      failures << "agent-run-smoke readiness summary daemonRuntime.installedDaemonPresent must be boolean"
    end
    unless [true, false].include?(daemon_runtime["matchRequired"])
      failures << "agent-run-smoke readiness summary daemonRuntime.matchRequired must be boolean"
    end
    unless [true, false, nil].include?(daemon_runtime["matchesExpectedDaemon"])
      failures << "agent-run-smoke readiness summary daemonRuntime.matchesExpectedDaemon must be boolean or null"
    end
    %w[installedDaemonPath expectedDaemonPath].each do |field|
      if likely_user_home_path?(daemon_runtime[field])
        failures << "agent-run-smoke readiness summary daemonRuntime.#{field} must not contain /Users/... paths"
      end
    end
    %w[installedDaemonPathPrivacy expectedDaemonPathPrivacy].each do |field|
      next if daemon_runtime[field].nil?
      unless %w[system relative basenameOnly notProvided].include?(daemon_runtime[field].to_s)
        failures << "agent-run-smoke readiness summary daemonRuntime.#{field} has unsupported privacy value"
      end
    end
    unless daemon_runtime["installedDaemonSHA256"].nil?
      require_sha256(
        daemon_runtime["installedDaemonSHA256"],
        "agent-run-smoke readiness summary daemonRuntime.installedDaemonSHA256",
        failures
      )
    end
    unless daemon_runtime["expectedDaemonSHA256"].nil?
      require_sha256(
        daemon_runtime["expectedDaemonSHA256"],
        "agent-run-smoke readiness summary daemonRuntime.expectedDaemonSHA256",
        failures
      )
    end
  end

  def validate_agent_run_smoke_readiness_summary(path, expected_schema_id, diagnose, failures)
    summary = parse_external_json(path, failures, "agent-run-smoke readiness summary")
    return nil if summary.nil?

    unless summary["schemaVersion"] == 1
      failures << "agent-run-smoke readiness summary schemaVersion must be 1"
    end
    unless summary["schemaID"] == expected_schema_id
      failures << "agent-run-smoke readiness summary schemaID must be #{expected_schema_id}"
    end
    unless summary["kind"].to_s == "vifty-agent-run-smoke-readiness"
      failures << "agent-run-smoke readiness summary kind must be vifty-agent-run-smoke-readiness"
    end
    unless summary["readOnly"] == true
      failures << "agent-run-smoke readiness summary must declare readOnly=true"
    end
    unless summary["coolingCommandsRun"] == false
      failures << "agent-run-smoke readiness summary must declare coolingCommandsRun=false"
    end
    if likely_user_home_path?(summary["reason"])
      failures << "agent-run-smoke readiness summary reason must not contain /Users/... paths"
    end
    unless summary["reasonCharacterCount"].nil?
      require_positive_integer(summary["reasonCharacterCount"], "agent-run-smoke readiness summary reasonCharacterCount", failures)
    end
    unless summary["reasonPrivacy"].nil?
      failures << "agent-run-smoke readiness summary reasonPrivacy must be omitted" unless summary["reasonPrivacy"].to_s == "omitted"
    end
    unless string_array?(summary["recoverySteps"])
      failures << "agent-run-smoke readiness summary recoverySteps must be an array of strings"
    end
    failures << "agent-run-smoke readiness summary failedCheckIDs must be an array of strings" unless string_array?(summary["failedCheckIDs"])
    failures << "agent-run-smoke readiness summary coolingBlockerIDs must be an array of strings" unless string_array?(summary["coolingBlockerIDs"])
    failures << "agent-run-smoke readiness summary blockers must be an array of strings" unless string_array?(summary["blockers"])
    failures << "agent-run-smoke readiness summary parseErrors must be an array of strings" unless string_array?(summary["parseErrors"])

    if summary["status"].to_s == "ready"
      unless summary["agentRunSmokeReady"] == true
        failures << "agent-run-smoke readiness summary agentRunSmokeReady must be true when ready"
      end
      unless summary["capabilitiesExitStatus"] == 0
        failures << "agent-run-smoke readiness summary capabilitiesExitStatus must be 0 before passed agent-run smoke"
      end
      unless summary["diagnoseExitStatus"] == 0
        failures << "agent-run-smoke readiness summary diagnoseExitStatus must be 0 before passed agent-run smoke"
      end
      unless %w[ready degraded].include?(summary["state"].to_s)
        failures << "agent-run-smoke readiness summary state must be ready or degraded"
      end
      unless %w[requestCooling requestCoolingWithCaution].include?(summary["recommendedAgentAction"].to_s)
        failures << "agent-run-smoke readiness summary must recommend requestCooling or requestCoolingWithCaution"
      end
      unless summary["safeToRequestCooling"] == true
        failures << "agent-run-smoke readiness summary safeToRequestCooling must be true"
      end
      unless summary["daemonControlPathReady"] == true
        failures << "agent-run-smoke readiness summary daemonControlPathReady must be true"
      end
      unless summary["manualControlActive"] == false
        failures << "agent-run-smoke readiness summary manualControlActive must be false"
      end
      unless summary["isAppleSilicon"] == true && summary["isMacBookPro"] == true
        failures << "agent-run-smoke readiness summary must be from an Apple Silicon MacBook Pro"
      end
      require_positive_integer(summary["fanCount"], "agent-run-smoke readiness summary fanCount", failures)
      require_positive_integer(summary["controllableFanCount"], "agent-run-smoke readiness summary controllableFanCount", failures)
      require_positive_integer(summary["temperatureSensorCount"], "agent-run-smoke readiness summary temperatureSensorCount", failures)
      if string_array?(summary["coolingBlockerIDs"]) && !summary["coolingBlockerIDs"].empty?
        failures << "agent-run-smoke readiness summary coolingBlockerIDs must be empty before passed agent-run smoke"
      end
      if string_array?(summary["blockers"]) && !summary["blockers"].empty?
        failures << "agent-run-smoke readiness summary blockers must be empty before passed agent-run smoke"
      end
      if string_array?(summary["parseErrors"]) && !summary["parseErrors"].empty?
        failures << "agent-run-smoke readiness summary parseErrors must be empty before passed agent-run smoke"
      end
      capabilities = summary["capabilities"].is_a?(Hash) ? summary["capabilities"] : {}
      unless capabilities["daemonStatusAvailable"] == true &&
          capabilities["policySource"] == "daemonStatus" &&
          capabilities["policyStatusAvailable"] == true &&
          capabilities["policyEnabled"] == true &&
          capabilities["supportsForceRetry"] == true &&
          capabilities["resolvedChildExecutableReported"] == true
        failures << "agent-run-smoke readiness summary must have daemon-backed policy and run lifecycle capability evidence"
      end
    elsif summary["status"].to_s == "blocked"
      unless summary["agentRunSmokeReady"] == false
        failures << "agent-run-smoke readiness summary agentRunSmokeReady must be false when blocked"
      end
      unless [false, nil].include?(summary["safeToRequestCooling"])
        failures << "agent-run-smoke readiness summary safeToRequestCooling must be false or null when blocked"
      end
    else
      failures << "agent-run-smoke readiness summary status must be ready or blocked"
    end

    field_pairs = {
      "state" => "state",
      "modelIdentifier" => "modelIdentifier",
      "isAppleSilicon" => "isAppleSilicon",
      "isMacBookPro" => "isMacBookPro",
      "safeToRequestCooling" => "safeToRequestCooling",
      "daemonControlPathReady" => "daemonControlPathReady",
      "manualControlActive" => "manualControlActive",
      "fanCount" => "fanCount",
      "controllableFanCount" => "controllableFanCount",
      "temperatureSensorCount" => "temperatureSensorCount",
      "thermalPressure" => "thermalPressure",
      "recommendedAgentAction" => "recommendedAgentAction",
      "recommendedRecoveryAction" => "recommendedRecoveryAction"
    }
    field_pairs.each do |summary_field, diagnose_field|
      next if diagnose[diagnose_field].nil? && summary[summary_field].nil?
      unless summary[summary_field] == diagnose[diagnose_field]
        failures << "agent-run-smoke readiness summary #{summary_field} must match viftyctl-diagnose.json"
      end
    end

    validate_agent_run_smoke_readiness_daemon_runtime(summary, failures)
    summary
  end

  def validate_agent_run_smoke_bundle(summary_path, summary, failures)
    smoke_bundle = File.dirname(summary_path)
    manifest_path = File.join(smoke_bundle, "manifest.tsv")
    checksum_path = File.join(smoke_bundle, "checksums.tsv")
    manifest_rows = parse_external_tsv(manifest_path, failures, "agent-run-smoke manifest.tsv")
    checksum_rows = parse_external_tsv(checksum_path, failures, "agent-run-smoke checksums.tsv")
    commands = summary["commands"].is_a?(Array) ? summary["commands"] : []

    required_files = {
      File.basename(summary_path) => true,
      "manifest.tsv" => true
    }

    unless manifest_rows.empty?
      missing_headers = %w[name status stdout stderr].reject { |header| manifest_rows.first.key?(header) }
      unless missing_headers.empty?
        failures << "agent-run-smoke manifest.tsv is missing required header(s): #{missing_headers.join(", ")}"
      end
    end

    manifest_by_name = {}
    manifest_rows.each do |row|
      name = row["name"].to_s
      if name.empty?
        failures << "agent-run-smoke manifest.tsv has a row with an empty name"
        next
      end
      unless name.match?(/\A[A-Za-z0-9_.-]+\z/) && !name.start_with?(".")
        failures << "agent-run-smoke manifest.tsv name #{name.inspect} must be a command name"
        next
      end
      if manifest_by_name.key?(name)
        failures << "agent-run-smoke manifest.tsv has duplicate command #{name}"
        next
      end
      manifest_by_name[name] = row
    end

    commands_by_name = {}
    commands.each do |command|
      unless command.is_a?(Hash)
        failures << "agent-run-smoke summary commands entries must be objects"
        next
      end
      name = command["name"].to_s
      if name.empty?
        failures << "agent-run-smoke summary command has an empty name"
        next
      end
      unless name.match?(/\A[A-Za-z0-9_.-]+\z/) && !name.start_with?(".")
        failures << "agent-run-smoke summary command name #{name.inspect} must be a command name"
        next
      end
      if commands_by_name.key?(name)
        failures << "agent-run-smoke summary has duplicate command #{name}"
        next
      end
      commands_by_name[name] = command

      manifest_row = manifest_by_name[name]
      if manifest_row.nil?
        failures << "agent-run-smoke manifest.tsv is missing command #{name}"
      else
        expected_status = command["status"].to_s
        if manifest_row["status"].to_s != expected_status
          failures << "agent-run-smoke manifest.tsv #{name} status #{manifest_row["status"].to_s.inspect} did not match summary #{expected_status.inspect}"
        end
        %w[stdout stderr].each do |field|
          summary_file = command[field].to_s
          manifest_file = manifest_row[field].to_s
          if manifest_file != summary_file
            failures << "agent-run-smoke manifest.tsv #{name} #{field} #{manifest_file.inspect} did not match summary #{summary_file.inspect}"
          end
        end
      end

      %w[stdout stderr statusFile].each do |field|
        relative_path = agent_run_smoke_local_filename(command[field], "#{name} #{field}", failures)
        next if relative_path.nil?

        required_files[relative_path] = true
        unless File.file?(File.join(smoke_bundle, relative_path))
          failures << "agent-run-smoke summary #{name} #{field} references missing file #{relative_path}"
        end
      end

      status_file = command["statusFile"].to_s
      unless status_file.empty? || status_file.include?("/") || status_file.start_with?(".")
        status_path = File.join(smoke_bundle, status_file)
        if File.file?(status_path)
          status_file_value = File.read(status_path).strip
          expected_status = command["status"].to_s
          unless status_file_value == expected_status
            failures << "agent-run-smoke summary #{name} status #{expected_status.inspect} did not match #{status_file} #{status_file_value.inspect}"
          end
        end
      end
    end

    manifest_by_name.each_key do |name|
      failures << "agent-run-smoke summary commands is missing manifest command #{name}" unless commands_by_name.key?(name)
    end

    run = summary["run"].is_a?(Hash) ? summary["run"] : {}
    %w[stdout stderr].each do |field|
      next if run[field].nil?
      relative_path = agent_run_smoke_local_filename(run[field], "run #{field}", failures)
      next if relative_path.nil?

      required_files[relative_path] = true
      unless File.file?(File.join(smoke_bundle, relative_path))
        failures << "agent-run-smoke run #{field} references missing file #{relative_path}"
      end
    end

    if checksum_rows.empty?
      failures << "agent-run-smoke checksums.tsv must include evidence rows"
      return
    end

    missing_checksum_headers = %w[sha256 bytes file].reject { |header| checksum_rows.first.key?(header) }
    unless missing_checksum_headers.empty?
      failures << "agent-run-smoke checksums.tsv is missing required header(s): #{missing_checksum_headers.join(", ")}"
      return
    end

    checksum_by_file = {}
    checksum_rows.each do |row|
      relative_path = row["file"].to_s
      if relative_path.empty?
        failures << "agent-run-smoke checksums.tsv has a row with an empty file"
        next
      end
      if relative_path == "checksums.tsv"
        failures << "agent-run-smoke checksums.tsv must not include itself"
        next
      end
      if relative_path.include?("/") || relative_path.start_with?(".")
        failures << "agent-run-smoke checksums.tsv file #{relative_path.inspect} must be a bundle-local filename"
        next
      end
      if checksum_by_file.key?(relative_path)
        failures << "agent-run-smoke checksums.tsv has duplicate file #{relative_path}"
        next
      end
      checksum_by_file[relative_path] = row
      require_sha256(row["sha256"], "agent-run-smoke checksums.tsv #{relative_path} sha256", failures)
      declared_bytes = row["bytes"].to_s
      require_nonnegative_integer(declared_bytes, "agent-run-smoke checksums.tsv #{relative_path} bytes", failures)
      path = File.join(smoke_bundle, relative_path)
      unless File.file?(path)
        failures << "agent-run-smoke checksums.tsv references missing file #{relative_path}"
        next
      end
      actual_sha256 = Digest::SHA256.file(path).hexdigest
      actual_bytes = File.size(path).to_s
      unless row["sha256"].to_s == actual_sha256
        failures << "agent-run-smoke checksums.tsv #{relative_path} sha256 #{row["sha256"].to_s.inspect} did not match actual #{actual_sha256.inspect}"
      end
      unless declared_bytes == actual_bytes
        failures << "agent-run-smoke checksums.tsv #{relative_path} bytes #{declared_bytes.inspect} did not match actual #{actual_bytes.inspect}"
      end
    end

    required_files.keys.sort.each do |relative_path|
      failures << "agent-run-smoke checksums.tsv is missing file #{relative_path}" unless checksum_by_file.key?(relative_path)
    end
  rescue StandardError => error
    failures << "could not validate agent-run-smoke bundle: #{error.message}"
  end

  def agent_run_smoke_command_json(summary_path, summary, command_name, failures)
    commands = summary["commands"].is_a?(Array) ? summary["commands"] : []
    command = commands.find { |entry| entry.is_a?(Hash) && entry["name"].to_s == command_name }
    if command.nil?
      failures << "agent-run-smoke summary commands is missing #{command_name}"
      return nil
    end

    relative_path = agent_run_smoke_local_filename(command["stdout"], "#{command_name} stdout", failures)
    return nil if relative_path.nil?

    parse_external_json(File.join(File.dirname(summary_path), relative_path), failures, "agent-run-smoke #{command_name} JSON")
  end

  def validate_agent_run_smoke_rate_limit_retry(summary_path, summary, failures)
    commands = summary["commands"].is_a?(Array) ? summary["commands"] : []
    commands_by_name = commands
      .select { |entry| entry.is_a?(Hash) }
      .each_with_object({}) { |entry, by_name| by_name[entry["name"].to_s] = entry }
    retry_command = commands_by_name["viftyctl-run-retry"]
    retry_metadata = summary["rateLimitRetry"]

    if retry_metadata.nil?
      if retry_command
        failures << "agent-run-smoke summary rateLimitRetry is required when viftyctl-run-retry is captured"
      end
      return
    end

    unless retry_metadata.is_a?(Hash)
      failures << "agent-run-smoke summary rateLimitRetry must be an object"
      return
    end

    if retry_metadata["attempted"] != true
      if retry_metadata["attempted"] != false
        failures << "agent-run-smoke summary rateLimitRetry.attempted must be true or false"
      end
      if retry_command
        failures << "agent-run-smoke summary must not capture viftyctl-run-retry when rateLimitRetry.attempted=false"
      end
      %w[retryAfterSeconds initialExitStatus stdout stderr].each do |field|
        unless retry_metadata[field].nil?
          failures << "agent-run-smoke summary rateLimitRetry.#{field} must be null when attempted=false"
        end
      end
      return
    end

    run = summary["run"].is_a?(Hash) ? summary["run"] : {}
    initial_command = commands_by_name["viftyctl-run"]
    if initial_command.nil?
      failures << "agent-run-smoke summary rateLimitRetry requires initial viftyctl-run command evidence"
      return
    end
    if retry_command.nil?
      failures << "agent-run-smoke summary rateLimitRetry requires viftyctl-run-retry command evidence"
      return
    end

    retry_after = retry_metadata["retryAfterSeconds"]
    unless retry_after.is_a?(Integer) && retry_after >= 1 && retry_after <= 300
      failures << "agent-run-smoke summary rateLimitRetry.retryAfterSeconds must be an integer from 1 through 300"
    end
    initial_exit_status = retry_metadata["initialExitStatus"]
    unless initial_exit_status.is_a?(Integer) && initial_exit_status != 0
      failures << "agent-run-smoke summary rateLimitRetry.initialExitStatus must be a nonzero integer"
    end
    if initial_command["status"] != initial_exit_status
      failures << "agent-run-smoke summary rateLimitRetry.initialExitStatus must match viftyctl-run command status"
    end
    if retry_metadata["stdout"] != initial_command["stdout"]
      failures << "agent-run-smoke summary rateLimitRetry.stdout must match viftyctl-run stdout"
    end
    if retry_metadata["stderr"] != initial_command["stderr"]
      failures << "agent-run-smoke summary rateLimitRetry.stderr must match viftyctl-run stderr"
    end
    if run["stdout"] != retry_command["stdout"]
      failures << "agent-run-smoke summary run.stdout must reference viftyctl-run-retry stdout after rate-limit retry"
    end
    if run["stderr"] != retry_command["stderr"]
      failures << "agent-run-smoke summary run.stderr must reference viftyctl-run-retry stderr after rate-limit retry"
    end
    if run["exitStatus"] != retry_command["status"]
      failures << "agent-run-smoke summary run.exitStatus must match viftyctl-run-retry command status after rate-limit retry"
    end

    initial_json = agent_run_smoke_command_json(summary_path, summary, "viftyctl-run", failures)
    return if initial_json.nil?

    unless initial_json["errorCode"] == "PREPARE_RATE_LIMITED" &&
        initial_json["safeToProceed"] == false &&
        initial_json["coolingLeasePrepared"] == false &&
        initial_json["autoRestoreAttempted"] == false &&
        initial_json["retryAfterSeconds"] == retry_after
      failures << "agent-run-smoke initial viftyctl-run JSON must be PREPARE_RATE_LIMITED cooldown evidence matching rateLimitRetry"
    end
  end

  def validate_agent_run_smoke_provenance(summary, failures)
    install_source = summary["installSource"].to_s
    unless SUPPORTED_INSTALL_SOURCES.include?(install_source)
      failures << "agent-run-smoke summary installSource #{install_source.inspect} is not supported"
    end

    require_git_sha(summary["sourceSHA"], "agent-run-smoke summary sourceSHA", failures)
    unless summary["sourceArtifactSHA256"].to_s.empty?
      require_sha256(summary["sourceArtifactSHA256"], "agent-run-smoke summary sourceArtifactSHA256", failures)
    end
    unless summary["sourceArtifactBytes"].to_s.empty?
      require_positive_integer(summary["sourceArtifactBytes"], "agent-run-smoke summary sourceArtifactBytes", failures)
    end

    if SOURCE_SHA_REQUIRED_INSTALL_SOURCES.include?(install_source) && summary["sourceSHA"].to_s.empty?
      failures << "agent-run-smoke summary #{install_source} evidence requires sourceSHA to pin the immutable source commit"
    end
    if %w[source-build-tag source-first-unsigned-dev-zip].include?(install_source) &&
        !summary["sourceRef"].to_s.match?(/\Av[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?\z/)
      failures << "agent-run-smoke summary #{install_source} evidence requires sourceRef to be the version tag used for the source build"
    end
    if !summary["sourceArtifactName"].to_s.empty? && summary["sourceArtifactSHA256"].to_s.empty?
      failures << "agent-run-smoke summary sourceArtifactName requires sourceArtifactSHA256"
    end
  end

  def validate_agent_run_smoke_viftyctl_path(summary, failures)
    viftyctl = summary["viftyctl"]
    unless viftyctl.is_a?(String) &&
        !viftyctl.empty? &&
        !viftyctl.include?("/") &&
        !viftyctl.start_with?(".")
      failures << "agent-run-smoke summary viftyctl must be a basename-only command name"
    end

    unless %w[appBundle sourceCheckout customExecutable].include?(summary["viftyctlPathKind"].to_s)
      failures << "agent-run-smoke summary viftyctlPathKind must be appBundle, sourceCheckout, or customExecutable"
    end

    unless summary["viftyctlPathPrivacy"] == "basenameOnly"
      failures << "agent-run-smoke summary viftyctlPathPrivacy must be basenameOnly"
    end
  end

  def validate_agent_run_smoke_daemon_runtime(summary, failures)
    daemon_runtime = summary["daemonRuntime"]
    unless daemon_runtime.is_a?(Hash)
      failures << "agent-run-smoke summary daemonRuntime is required"
      return
    end

    unless [true, false].include?(daemon_runtime["installedDaemonPresent"])
      failures << "agent-run-smoke summary daemonRuntime.installedDaemonPresent must be boolean"
    end
    unless [true, false].include?(daemon_runtime["matchRequired"])
      failures << "agent-run-smoke summary daemonRuntime.matchRequired must be boolean"
    end
    unless [true, false, nil].include?(daemon_runtime["matchesExpectedDaemon"])
      failures << "agent-run-smoke summary daemonRuntime.matchesExpectedDaemon must be boolean or null"
    end
    %w[installedDaemonPath expectedDaemonPath].each do |field|
      if likely_user_home_path?(daemon_runtime[field])
        failures << "agent-run-smoke summary daemonRuntime.#{field} must not contain /Users/... paths"
      end
    end
    %w[installedDaemonPathPrivacy expectedDaemonPathPrivacy].each do |field|
      next if daemon_runtime[field].nil?
      unless %w[system relative basenameOnly notProvided].include?(daemon_runtime[field].to_s)
        failures << "agent-run-smoke summary daemonRuntime.#{field} has unsupported privacy value"
      end
    end
    unless daemon_runtime["installedDaemonSHA256"].nil?
      require_sha256(
        daemon_runtime["installedDaemonSHA256"],
        "agent-run-smoke summary daemonRuntime.installedDaemonSHA256",
        failures
      )
    end
    unless daemon_runtime["expectedDaemonSHA256"].nil?
      require_sha256(
        daemon_runtime["expectedDaemonSHA256"],
        "agent-run-smoke summary daemonRuntime.expectedDaemonSHA256",
        failures
      )
    end

    return unless summary["status"].to_s == "passed" &&
      summary["installSource"].to_s == "local-ad-hoc-build"

    unless daemon_runtime["matchRequired"] == true &&
        daemon_runtime["installedDaemonPresent"] == true &&
        daemon_runtime["matchesExpectedDaemon"] == true &&
        daemon_runtime["installedDaemonSHA256"].is_a?(String) &&
        daemon_runtime["expectedDaemonSHA256"].is_a?(String)
      failures << "passed local-ad-hoc agent-run-smoke summary must match the installed daemon to the expected build daemon"
    end
  end

  def normalize_agent_run_smoke_app_preferences(value)
    return nil unless value.is_a?(Hash)

    {
      "startupMode" => value.key?("startupMode") ? value["startupMode"] : nil,
      "startupModeSource" => value.key?("startupModeSource") ? value["startupModeSource"] : nil,
      "readError" => value.key?("readError") ? value["readError"] : nil
    }
  end

  def review_agent_run_smoke_app_preferences(value)
    preferences = normalize_agent_run_smoke_app_preferences(value)
    return {
      "startupMode" => "",
      "startupModeSource" => "",
      "readError" => ""
    } if preferences.nil?

    {
      "startupMode" => preferences["startupMode"].to_s,
      "startupModeSource" => preferences["startupModeSource"].to_s,
      "readError" => preferences["readError"].to_s
    }
  end

  def validate_agent_run_smoke_app_preferences(path, summary, preflight, failures)
    summary_preferences = normalize_agent_run_smoke_app_preferences(preflight["appPreferences"])
    return if summary_preferences.nil?

    pre_diagnose = agent_run_smoke_command_json(path, summary, "pre-diagnose", failures)
    return if pre_diagnose.nil?

    diagnose_preferences = normalize_agent_run_smoke_app_preferences(pre_diagnose["appPreferences"])
    if diagnose_preferences.nil?
      return if summary_preferences.values.all?(&:nil?)

      failures << "agent-run-smoke summary preflight.appPreferences must match pre-diagnose appPreferences"
      return
    end

    unless summary_preferences == diagnose_preferences
      failures << "agent-run-smoke summary preflight.appPreferences must match pre-diagnose appPreferences"
    end
  end

  def validate_agent_run_smoke_summary(path, expected_schema_id, failures)
    summary = parse_external_json(path, failures, "agent-run-smoke summary")
    return nil if summary.nil?

    validate_agent_run_smoke_bundle(path, summary, failures)
    validate_agent_run_smoke_rate_limit_retry(path, summary, failures)
    validate_agent_run_smoke_provenance(summary, failures)
    validate_agent_run_smoke_viftyctl_path(summary, failures)
    validate_agent_run_smoke_daemon_runtime(summary, failures)

    unless summary["schemaVersion"] == 1
      failures << "agent-run-smoke summary schemaVersion must be 1"
    end
    unless summary["schemaID"] == expected_schema_id
      failures << "agent-run-smoke summary schemaID must be #{expected_schema_id}"
    end
    unless summary["kind"] == "vifty-agent-run-smoke"
      failures << "agent-run-smoke summary kind must be vifty-agent-run-smoke"
    end
    if likely_user_home_path?(summary["reason"])
      failures << "agent-run-smoke summary reason must not contain /Users/... paths"
    end
    unless summary["reasonCharacterCount"].nil?
      require_positive_integer(summary["reasonCharacterCount"], "agent-run-smoke summary reasonCharacterCount", failures)
    end
    unless summary["reasonPrivacy"].nil?
      failures << "agent-run-smoke summary reasonPrivacy must be omitted" unless summary["reasonPrivacy"].to_s == "omitted"
    end

    preflight = summary["preflight"].is_a?(Hash) ? summary["preflight"] : {}
    run = summary["run"].is_a?(Hash) ? summary["run"] : {}
    validate_agent_run_smoke_app_preferences(path, summary, preflight, failures)
    unless summary["commands"].is_a?(Array) && !summary["commands"].empty?
      failures << "agent-run-smoke summary commands must be a non-empty array"
    end

    derived_result = case summary["status"].to_s
    when "passed"
      unless summary["readOnly"] == false
        failures << "passed agent-run-smoke summary must declare readOnly=false"
      end
      unless summary["coolingCommandsRun"] == true
        failures << "passed agent-run-smoke summary must declare coolingCommandsRun=true"
      end
      unless preflight["safeToRequestCooling"] == true
        failures << "passed agent-run-smoke summary must have safeToRequestCooling=true"
      end
      unless preflight["daemonControlPathReady"] == true
        failures << "passed agent-run-smoke summary must have daemonControlPathReady=true"
      end
      unless preflight["manualControlActive"] == false
        failures << "passed agent-run-smoke summary must have manualControlActive=false"
      end
      unless %w[requestCooling requestCoolingWithCaution].include?(preflight["recommendedAgentAction"].to_s)
        failures << "passed agent-run-smoke summary must recommend requestCooling or requestCoolingWithCaution"
      end
      unless preflight["capabilitiesExitStatus"] == 0 &&
          preflight["capabilitiesSchemaVersion"] == 1 &&
          preflight["capabilitiesSchemaID"] == CAPABILITIES_SCHEMA_ID &&
          preflight["diagnoseSchemaID"] == DIAGNOSE_SCHEMA_ID &&
          preflight["commandErrorSchemaID"] == COMMAND_ERROR_SCHEMA_ID &&
          preflight["runSchemaID"] == RUN_SCHEMA_ID &&
          preflight["daemonStatusAvailable"] == true &&
          preflight["policySource"] == "daemonStatus" &&
          preflight["policyStatusAvailable"] == true &&
          preflight["policyEnabled"] == true
        failures << "passed agent-run-smoke summary must have daemon-backed capabilities policy status"
      end
      unless preflight["capabilitiesSchemaVersion"] == 1
        failures << "passed agent-run-smoke summary must have capabilitiesSchemaVersion=1"
      end
      unless preflight["capabilitiesSchemaID"] == CAPABILITIES_SCHEMA_ID
        failures << "passed agent-run-smoke summary must have capabilitiesSchemaID=#{CAPABILITIES_SCHEMA_ID}"
      end
      unless preflight["diagnoseSchemaID"] == DIAGNOSE_SCHEMA_ID
        failures << "passed agent-run-smoke summary must have diagnoseSchemaID=#{DIAGNOSE_SCHEMA_ID}"
      end
      unless preflight["commandErrorSchemaID"] == COMMAND_ERROR_SCHEMA_ID
        failures << "passed agent-run-smoke summary must have commandErrorSchemaID=#{COMMAND_ERROR_SCHEMA_ID}"
      end
      unless preflight["runSchemaID"] == RUN_SCHEMA_ID
        failures << "passed agent-run-smoke summary must have runSchemaID=#{RUN_SCHEMA_ID}"
      end
      unless preflight["policyEnabled"] == true
        failures << "passed agent-run-smoke summary must have policyEnabled=true"
      end
      pre_capabilities = agent_run_smoke_command_json(path, summary, "pre-capabilities", failures)
      if pre_capabilities
        unless pre_capabilities["schemaVersion"] == 1 &&
            pre_capabilities.dig("schemaIDs", "capabilities") == CAPABILITIES_SCHEMA_ID &&
            pre_capabilities.dig("schemaIDs", "diagnose") == DIAGNOSE_SCHEMA_ID &&
            pre_capabilities.dig("schemaIDs", "commandError") == COMMAND_ERROR_SCHEMA_ID &&
            pre_capabilities.dig("schemaIDs", "run") == RUN_SCHEMA_ID &&
            pre_capabilities["daemonStatusAvailable"] == true &&
            pre_capabilities["policySource"] == "daemonStatus" &&
            pre_capabilities["policyStatusAvailable"] == true &&
            pre_capabilities.dig("policy", "enabled") == true
          failures << "passed agent-run-smoke pre-capabilities JSON must have daemon-backed policy status"
        end
      end
      unless run["exitStatus"] == 0
        failures << "passed agent-run-smoke summary run.exitStatus must be 0"
      end
      unless run["schemaVersion"] == 1
        failures << "passed agent-run-smoke summary run.schemaVersion must be 1"
      end
      unless run["schemaID"] == RUN_SCHEMA_ID
        failures << "passed agent-run-smoke summary run.schemaID must be #{RUN_SCHEMA_ID}"
      end
      unless run["command"] == "run"
        failures << "passed agent-run-smoke summary run.command must be run"
      end
      unless run["coolingLeasePrepared"] == true
        failures << "passed agent-run-smoke summary must report coolingLeasePrepared=true"
      end
      unless run["autoRestoreAttempted"] == true
        failures << "passed agent-run-smoke summary must report autoRestoreAttempted=true"
      end
      unless run["autoRestoreSucceeded"] == true
        failures << "passed agent-run-smoke summary must report autoRestoreSucceeded=true"
      end
      unless run["childExitCode"] == 0
        failures << "passed agent-run-smoke summary must report childExitCode=0"
      end
      if preflight["resolvedChildExecutableReported"] == true
        resolved_child_executable = run["resolvedChildExecutable"]
        unless resolved_child_executable.is_a?(String) && resolved_child_executable.start_with?("/")
          failures << "passed agent-run-smoke summary must report absolute resolvedChildExecutable when capabilities advertise resolvedChildExecutableReported"
        end
        final_run_json = nil
        if run["stdout"].is_a?(String)
          relative_path = agent_run_smoke_local_filename(run["stdout"], "final run stdout", failures)
          final_run_json = parse_external_json(File.join(File.dirname(path), relative_path), failures, "agent-run-smoke final run JSON") unless relative_path.nil?
        end
        if final_run_json && final_run_json["resolvedChildExecutable"] != resolved_child_executable
          failures << "passed agent-run-smoke final run JSON resolvedChildExecutable must match summary run.resolvedChildExecutable"
        end
        child_termination_reason = run["childTerminationReason"]
        child_signal = run["childSignal"]
        child_signal_name = run["childSignalName"]
        if run.key?("childTerminationReason") && !child_termination_reason.nil?
          unless ["exited", "signalInferred"].include?(child_termination_reason)
            failures << "passed agent-run-smoke summary childTerminationReason must be exited or signalInferred when present"
          end
          if final_run_json && final_run_json["childTerminationReason"] != child_termination_reason
            failures << "passed agent-run-smoke final run JSON childTerminationReason must match summary run.childTerminationReason"
          end
          if child_termination_reason == "exited" && (!child_signal.nil? || !child_signal_name.nil?)
            failures << "passed agent-run-smoke summary childSignal fields must be null when childTerminationReason is exited"
          end
          if child_termination_reason == "signalInferred"
            unless child_signal.is_a?(Integer) && child_signal >= 1 && child_signal <= 64
              failures << "passed agent-run-smoke summary childSignal must be an integer from 1 through 64 when childTerminationReason is signalInferred"
            end
            if child_signal.is_a?(Integer) && run["childExitCode"] != 128 + child_signal
              failures << "passed agent-run-smoke summary childExitCode must equal 128 + childSignal when childTerminationReason is signalInferred"
            end
          end
        elsif final_run_json && final_run_json.key?("childTerminationReason") && !final_run_json["childTerminationReason"].nil?
          failures << "passed agent-run-smoke summary must preserve final run JSON childTerminationReason when present"
        end
        if final_run_json && final_run_json["childSignal"] != child_signal
          failures << "passed agent-run-smoke final run JSON childSignal must match summary run.childSignal"
        end
        if final_run_json && final_run_json["childSignalName"] != child_signal_name
          failures << "passed agent-run-smoke final run JSON childSignalName must match summary run.childSignalName"
        end
        resolved_child_executable_sha256 = run["resolvedChildExecutableSHA256"]
        resolved_child_executable_sha256_status = run["resolvedChildExecutableSHA256Status"]
        if run.key?("resolvedChildExecutableSHA256") && !resolved_child_executable_sha256.nil?
          unless resolved_child_executable_sha256.is_a?(String) && resolved_child_executable_sha256.match?(/\A[a-f0-9]{64}\z/)
            failures << "passed agent-run-smoke summary resolvedChildExecutableSHA256 must be a lowercase SHA-256 digest when present"
          end
          if final_run_json && final_run_json["resolvedChildExecutableSHA256"] != resolved_child_executable_sha256
            failures << "passed agent-run-smoke final run JSON resolvedChildExecutableSHA256 must match summary run.resolvedChildExecutableSHA256"
          end
        elsif final_run_json && final_run_json.key?("resolvedChildExecutableSHA256") && !final_run_json["resolvedChildExecutableSHA256"].nil?
          failures << "passed agent-run-smoke summary must preserve final run JSON resolvedChildExecutableSHA256 when present"
        end
        if run.key?("resolvedChildExecutableSHA256Status") && !resolved_child_executable_sha256_status.nil?
          unless ["computed", "unavailable"].include?(resolved_child_executable_sha256_status)
            failures << "passed agent-run-smoke summary resolvedChildExecutableSHA256Status must be computed or unavailable when present"
          end
          if final_run_json && final_run_json["resolvedChildExecutableSHA256Status"] != resolved_child_executable_sha256_status
            failures << "passed agent-run-smoke final run JSON resolvedChildExecutableSHA256Status must match summary run.resolvedChildExecutableSHA256Status"
          end
          if resolved_child_executable_sha256_status == "computed" && !(resolved_child_executable_sha256.is_a?(String) && resolved_child_executable_sha256.match?(/\A[a-f0-9]{64}\z/))
            failures << "passed agent-run-smoke summary resolvedChildExecutableSHA256Status computed requires resolvedChildExecutableSHA256"
          end
          if resolved_child_executable_sha256_status == "unavailable" && !resolved_child_executable_sha256.nil?
            failures << "passed agent-run-smoke summary resolvedChildExecutableSHA256Status unavailable must not include resolvedChildExecutableSHA256"
          end
        elsif final_run_json && final_run_json.key?("resolvedChildExecutableSHA256Status") && !final_run_json["resolvedChildExecutableSHA256Status"].nil?
          failures << "passed agent-run-smoke summary must preserve final run JSON resolvedChildExecutableSHA256Status when present"
        end
      end
      "passed-auto-restored"
    when "failed"
      unless summary["readOnly"] == false
        failures << "failed agent-run-smoke summary must declare readOnly=false"
      end
      unless summary["coolingCommandsRun"] == true
        failures << "failed agent-run-smoke summary must declare coolingCommandsRun=true"
      end
      unless run["exitStatus"].is_a?(Integer) && run["exitStatus"] != 0
        failures << "failed agent-run-smoke summary run.exitStatus must be a nonzero integer"
      end
      "failed"
    when "blocked"
      unless summary["readOnly"] == true
        failures << "blocked agent-run-smoke summary must declare readOnly=true"
      end
      unless summary["coolingCommandsRun"] == false
        failures << "blocked agent-run-smoke summary must declare coolingCommandsRun=false"
      end
      unless run["exitStatus"].nil?
        failures << "blocked agent-run-smoke summary run.exitStatus must be null"
      end
      "skipped-blocked"
    else
      failures << "agent-run-smoke summary status must be passed, failed, or blocked"
      nil
    end

    return nil if derived_result.nil?

    {
      "result" => derived_result,
      "appPreferences" => review_agent_run_smoke_app_preferences(preflight["appPreferences"])
    }
  end

  def share_safe_bundle_path(bundle)
    File.basename(File.expand_path(bundle.to_s))
  end

  def model_family_for(model_identifier)
    value = model_identifier.to_s.strip
    return nil if value.empty?

    value.split(",", 2).first
  end

  def write_review_result(path, bundle, mode, status, failures, warnings, review_summary, diagnose, install_fields, manual_smoke_result, manual_smoke_source, manual_smoke_readiness_source, agent_run_smoke_result, agent_run_smoke_source, agent_run_smoke_readiness_source, agent_run_smoke_app_preferences)
    return if path.to_s.empty?

    failed_check_ids = string_array?(diagnose["failedCheckIDs"]) ? diagnose["failedCheckIDs"] : []
    cooling_blocker_ids = string_array?(diagnose["coolingBlockerIDs"]) ? diagnose["coolingBlockerIDs"] : []

    payload = {
      "schemaVersion" => 1,
      "schemaID" => VALIDATION_REVIEW_RESULT_SCHEMA_ID,
      "generatedAtUTC" => Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
      "status" => status,
      "mode" => mode,
      "bundlePath" => share_safe_bundle_path(bundle),
      "readOnly" => true,
      "coolingCommandsRun" => false,
      "appPath" => review_summary["appPath"],
      "releaseArtifactSummaryPath" => review_summary["releaseArtifactSummaryPath"],
      "releaseChecklistPath" => review_summary["releaseChecklistPath"],
      "installSource" => install_fields["installSource"].to_s,
      "sourceRef" => install_fields["sourceRef"].to_s,
      "sourceSHA" => install_fields["sourceSHA"].to_s,
      "sourceArtifactName" => install_fields["sourceArtifactName"].to_s,
      "sourceArtifactSHA256" => install_fields["sourceArtifactSHA256"].to_s,
      "sourceArtifactBytes" => install_fields["sourceArtifactBytes"].to_s,
      "diagnoseState" => diagnose["state"],
      "recommendedAgentAction" => diagnose["recommendedAgentAction"],
      "recommendedRecoveryAction" => diagnose["recommendedRecoveryAction"],
      "safeToRequestCooling" => diagnose["safeToRequestCooling"],
      "daemonControlPathReady" => diagnose["daemonControlPathReady"],
      "manualControlActive" => diagnose.key?("manualControlActive") ? diagnose["manualControlActive"] : nil,
      "failedCheckIDs" => failed_check_ids,
      "coolingBlockerIDs" => cooling_blocker_ids,
      "modelIdentifier" => diagnose["modelIdentifier"],
      "modelFamily" => model_family_for(diagnose["modelIdentifier"]),
      "isAppleSilicon" => diagnose["isAppleSilicon"],
      "isMacBookPro" => diagnose["isMacBookPro"],
      "fanCount" => diagnose["fanCount"],
      "controllableFanCount" => diagnose["controllableFanCount"],
      "temperatureSensorCount" => diagnose["temperatureSensorCount"],
      "thermalPressure" => diagnose["thermalPressure"],
      "manualSmokeTestResult" => manual_smoke_result,
      "manualSmokeTestSource" => manual_smoke_source,
      "manualSmokeReadinessSource" => manual_smoke_readiness_source,
      "agentRunSmokeResult" => agent_run_smoke_result,
      "agentRunSmokeSource" => agent_run_smoke_source,
      "agentRunSmokeReadinessSource" => agent_run_smoke_readiness_source,
      "agentRunSmokeStartupMode" => agent_run_smoke_app_preferences["startupMode"].to_s,
      "agentRunSmokeStartupModeSource" => agent_run_smoke_app_preferences["startupModeSource"].to_s,
      "agentRunSmokeStartupModeReadError" => agent_run_smoke_app_preferences["readError"].to_s,
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
  require_status(checks, "viftyctl-capabilities", ["0"], failures)

  install_rows = parse_tsv(bundle, "install-provenance.tsv", failures)
  install_fields = field_rows_to_map(install_rows, "install-provenance.tsv", failures)
  validate_install_provenance(install_fields, failures, warnings)

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
  require_recommended_recovery_action(
    diagnose["recommendedRecoveryAction"],
    "viftyctl-diagnose.json recommendedRecoveryAction",
    failures
  )
  failed_check_ids = diagnose["failedCheckIDs"]
  failed_check_ids_present = diagnose.key?("failedCheckIDs")
  cooling_blocker_ids = diagnose["coolingBlockerIDs"]
  cooling_blocker_ids_present = diagnose.key?("coolingBlockerIDs")
  if failed_check_ids_present
    failures << "viftyctl-diagnose.json failedCheckIDs must be an array of strings" unless string_array?(failed_check_ids)
  else
    warnings << "viftyctl-diagnose.json is missing failedCheckIDs; legacy reports may require checks[] parsing for failed readiness IDs"
    failed_check_ids = []
  end
  if cooling_blocker_ids_present
    failures << "viftyctl-diagnose.json coolingBlockerIDs must be an array of strings" unless string_array?(cooling_blocker_ids)
  else
    warnings << "viftyctl-diagnose.json is missing coolingBlockerIDs; legacy reports may require checks[] parsing for hard cooling blockers"
    cooling_blocker_ids = []
  end
  if string_array?(cooling_blocker_ids) && !cooling_blocker_ids.empty? && diagnose["safeToRequestCooling"] == true
    failures << "viftyctl-diagnose.json coolingBlockerIDs must be empty when safeToRequestCooling=true"
  end

  agent_run_smoke_app_preferences = {
    "startupMode" => "",
    "startupModeSource" => "",
    "readError" => ""
  }
  manual_smoke_readiness = nil
  manual_smoke_readiness_source = ""
  unless manual_smoke_readiness_summary_path.to_s.empty?
    expanded_manual_smoke_readiness_path = File.expand_path(manual_smoke_readiness_summary_path)
    manual_smoke_readiness = validate_manual_smoke_readiness_summary(
      expanded_manual_smoke_readiness_path,
      MANUAL_SMOKE_READINESS_SCHEMA_ID,
      diagnose,
      failures
    )
    manual_smoke_readiness_source = manual_smoke_readiness_share_safe_source(expanded_manual_smoke_readiness_path) unless manual_smoke_readiness.nil?
  end
  agent_run_smoke_readiness = nil
  agent_run_smoke_readiness_source = ""
  unless agent_run_smoke_readiness_summary_path.to_s.empty?
    expanded_agent_run_smoke_readiness_path = File.expand_path(agent_run_smoke_readiness_summary_path)
    agent_run_smoke_readiness = validate_agent_run_smoke_readiness_summary(
      expanded_agent_run_smoke_readiness_path,
      AGENT_RUN_SMOKE_READINESS_SCHEMA_ID,
      diagnose,
      failures
    )
    agent_run_smoke_readiness_source = agent_run_smoke_readiness_share_safe_source(expanded_agent_run_smoke_readiness_path) unless agent_run_smoke_readiness.nil?
  end
  unless agent_run_smoke_summary_path.to_s.empty?
    derived_agent_run_smoke = validate_agent_run_smoke_summary(
      File.expand_path(agent_run_smoke_summary_path),
      AGENT_RUN_SMOKE_SUMMARY_SCHEMA_ID,
      failures
    )
    unless derived_agent_run_smoke.nil?
      derived_agent_run_smoke_result = derived_agent_run_smoke["result"]
      agent_run_smoke_app_preferences = derived_agent_run_smoke["appPreferences"]
      if agent_run_smoke_result == "not-recorded"
        agent_run_smoke_result = derived_agent_run_smoke_result
      elsif agent_run_smoke_result != derived_agent_run_smoke_result
        failures << "agent-run-smoke summary result #{derived_agent_run_smoke_result.inspect} conflicts with --agent-run-smoke-result #{agent_run_smoke_result.inspect}"
      end
      if agent_run_smoke_source.to_s.empty?
        agent_run_smoke_source = agent_run_smoke_share_safe_source(File.expand_path(agent_run_smoke_summary_path))
      end
    end
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
    unless diagnose["daemonControlPathReady"] == true
      failures << "supported hardware reports must have daemonControlPathReady=true"
    end
    unless diagnose["manualControlActive"] == false
      failures << "supported hardware reports must have manualControlActive=false"
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
      if manual_smoke_source.to_s.strip.empty?
        failures << "manual smoke result passed-auto-restored requires --manual-smoke-source"
      end
      if install_fields["installSource"].to_s == "local-ad-hoc-build"
        if manual_smoke_readiness.nil?
          failures << "passed local-ad-hoc manual smoke requires --manual-smoke-readiness-summary"
        else
          daemon_runtime = manual_smoke_readiness["daemonRuntime"].is_a?(Hash) ? manual_smoke_readiness["daemonRuntime"] : {}
          unless daemon_runtime["matchRequired"] == true &&
              daemon_runtime["installedDaemonPresent"] == true &&
              daemon_runtime["matchesExpectedDaemon"] == true &&
              daemon_runtime["installedDaemonSHA256"].is_a?(String) &&
              daemon_runtime["expectedDaemonSHA256"].is_a?(String)
            failures << "passed local-ad-hoc manual smoke readiness summary must match the installed daemon to the expected build daemon"
          end
        end
      end
    when "not-recorded"
      warnings << "manual fan-write smoke-test result is not recorded; keep this report as candidate evidence"
    else
      failures << "supported hardware validation requires manual smoke result passed-auto-restored"
    end
    case agent_run_smoke_result
    when "passed-auto-restored"
      if agent_run_smoke_source.to_s.empty?
        warnings << "supervised viftyctl run smoke test passed, but no issue URL or source note was recorded"
      end
      if install_fields["installSource"].to_s == "local-ad-hoc-build" && agent_run_smoke_summary_path.to_s.empty?
        if agent_run_smoke_readiness.nil?
          failures << "passed local-ad-hoc agent-run smoke requires --agent-run-smoke-readiness-summary or --agent-run-smoke-summary"
        else
          daemon_runtime = agent_run_smoke_readiness["daemonRuntime"].is_a?(Hash) ? agent_run_smoke_readiness["daemonRuntime"] : {}
          unless daemon_runtime["matchRequired"] == true &&
              daemon_runtime["installedDaemonPresent"] == true &&
              daemon_runtime["matchesExpectedDaemon"] == true &&
              daemon_runtime["installedDaemonSHA256"].is_a?(String) &&
              daemon_runtime["expectedDaemonSHA256"].is_a?(String)
            failures << "passed local-ad-hoc agent-run smoke readiness summary must match the installed daemon to the expected build daemon"
          end
        end
      end
    when "failed"
      failures << "supported hardware validation cannot pass with a failed supervised viftyctl run smoke test"
    end

  when "unsupported-hardware"
    require_status(checks, "viftyctl-diagnose", ["75"], failures)

    unless diagnose["state"].to_s == "blocked"
      failures << "unsupported hardware reports must have diagnose state blocked"
    end
    unless diagnose["safeToRequestCooling"] == false
      failures << "unsupported hardware reports must have safeToRequestCooling=false"
    end
    unless diagnose["daemonControlPathReady"] == true
      failures << "unsupported hardware reports must have daemonControlPathReady=true so the safe block proves hardware policy, not helper outage"
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
    if %w[passed-auto-restored failed].include?(agent_run_smoke_result)
      failures << "unsupported hardware reports must not include a supervised viftyctl run smoke test result"
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
    unless RELEASE_INSTALL_SOURCES.include?(install_fields["installSource"].to_s)
      failures << "release mode requires installSource notarized-github-release, homebrew-cask, or local-developer-id-build"
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
    write_review_result(summary_path, bundle, mode, "passed", failures, warnings, summary, diagnose, install_fields, manual_smoke_result, manual_smoke_source, manual_smoke_readiness_source, agent_run_smoke_result, agent_run_smoke_source, agent_run_smoke_readiness_source, agent_run_smoke_app_preferences)
    puts "Validation evidence review OK: mode #{mode}"
    puts "Bundle: #{bundle}"
    warnings.each { |warning| warn "warning: #{warning}" }
    exit 0
  end

  write_review_result(summary_path, bundle, mode, "failed", failures, warnings, summary, diagnose, install_fields, manual_smoke_result, manual_smoke_source, manual_smoke_readiness_source, agent_run_smoke_result, agent_run_smoke_source, agent_run_smoke_readiness_source, agent_run_smoke_app_preferences)
  warn "Validation evidence review failed: mode #{mode}"
  failures.each { |failure| warn "- #{failure}" }
  warnings.each { |warning| warn "warning: #{warning}" }
  exit 65
' "${BUNDLE_DIR}" "${MODE}" "${SUMMARY_PATH}" "${MANUAL_SMOKE_RESULT}" "${MANUAL_SMOKE_SOURCE}" "${MANUAL_SMOKE_READINESS_SUMMARY_PATH}" "${AGENT_RUN_SMOKE_RESULT}" "${AGENT_RUN_SMOKE_SOURCE}" "${AGENT_RUN_SMOKE_READINESS_SUMMARY_PATH}" "${AGENT_RUN_SMOKE_SUMMARY_PATH}"
