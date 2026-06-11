#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/collect-validation-evidence.sh [options]

Collect read-only Vifty release and hardware-validation evidence.

Options:
  --app <path>              Vifty.app path (default: /Applications/Vifty.app)
  --output <dir>            Output directory (default: .build/vifty-validation-<timestamp>)
  --release-summary <path>  Copy a release artifact verification summary into
                            the evidence bundle and summarize its pass/fail state.
  --release-checklist <path>
                            Copy the GitHub Release checklist into the evidence
                            bundle and summarize its version/follow-up coverage.
  --include-probe-local     Also run ViftyHelper probeLocal. Run the script with sudo if
                            direct SMC fan probe output is required.
  -h, --help                Show this help.

This script is read-only. It runs viftyctl capabilities/status/diagnose JSON
commands plus bundle, signing, daemon, and system inspection. It does not
request cooling leases, restore Auto, or write SMC keys.
USAGE
}

APP_PATH="${VIFTY_APP_PATH:-/Applications/Vifty.app}"
OUTPUT_DIR="${VIFTY_VALIDATION_OUTPUT_DIR:-}"
RELEASE_SUMMARY_PATH="${VIFTY_RELEASE_ARTIFACT_SUMMARY:-}"
RELEASE_CHECKLIST_PATH="${VIFTY_RELEASE_CHECKLIST:-}"
INCLUDE_PROBE_LOCAL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      if [[ $# -lt 2 ]]; then
        echo "error: --app requires a path" >&2
        exit 64
      fi
      APP_PATH="$2"
      shift 2
      ;;
    --output)
      if [[ $# -lt 2 ]]; then
        echo "error: --output requires a directory" >&2
        exit 64
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --release-summary)
      if [[ $# -lt 2 ]]; then
        echo "error: --release-summary requires a path" >&2
        exit 64
      fi
      RELEASE_SUMMARY_PATH="$2"
      shift 2
      ;;
    --release-checklist)
      if [[ $# -lt 2 ]]; then
        echo "error: --release-checklist requires a path" >&2
        exit 64
      fi
      RELEASE_CHECKLIST_PATH="$2"
      shift 2
      ;;
    --include-probe-local)
      INCLUDE_PROBE_LOCAL=1
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ -z "${OUTPUT_DIR}" ]]; then
  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  OUTPUT_DIR="${ROOT_DIR}/.build/vifty-validation-${timestamp}"
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: app bundle not found: ${APP_PATH}" >&2
  exit 69
fi

if [[ -n "${RELEASE_SUMMARY_PATH}" && ! -f "${RELEASE_SUMMARY_PATH}" ]]; then
  echo "error: release summary not found: ${RELEASE_SUMMARY_PATH}" >&2
  exit 66
fi

if [[ -n "${RELEASE_CHECKLIST_PATH}" && ! -f "${RELEASE_CHECKLIST_PATH}" ]]; then
  echo "error: release checklist not found: ${RELEASE_CHECKLIST_PATH}" >&2
  exit 66
fi

VIFTYCTL="${APP_PATH}/Contents/MacOS/viftyctl"
VIFTYHELPER="${APP_PATH}/Contents/MacOS/ViftyHelper"
VIFTYDAEMON="${APP_PATH}/Contents/MacOS/ViftyDaemon"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
SCHEMA_DIR="${APP_PATH}/Contents/Resources/schemas"
DAEMON_PLIST="${APP_PATH}/Contents/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
DAEMON_LABEL="tech.reidar.vifty.daemon"
RELEASE_ARTIFACT_SUMMARY_SCHEMA_ID="https://vifty.local/schemas/release-artifact-summary.schema.json"
EXPECTED_SCHEMA_FILES=(
  "release-artifact-summary.schema.json"
  "release-readiness.schema.json"
  "viftyctl-audit.schema.json"
  "viftyctl-capabilities.schema.json"
  "viftyctl-command-error.schema.json"
  "viftyctl-diagnose.schema.json"
  "viftyctl-status.schema.json"
)
EXPECTED_EXECUTABLES=(
  "Vifty"
  "ViftyHelper"
  "ViftyDaemon"
  "viftyctl"
)

if [[ ! -x "${VIFTYCTL}" ]]; then
  echo "error: viftyctl is not executable: ${VIFTYCTL}" >&2
  exit 69
fi

if [[ "${INCLUDE_PROBE_LOCAL}" == "1" && ! -x "${VIFTYHELPER}" ]]; then
  echo "error: ViftyHelper is not executable: ${VIFTYHELPER}" >&2
  exit 69
fi

if [[ -e "${OUTPUT_DIR}" ]]; then
  if [[ ! -d "${OUTPUT_DIR}" ]]; then
    echo "error: output path exists but is not a directory: ${OUTPUT_DIR}" >&2
    exit 73
  fi
  if [[ -n "$(ls -A "${OUTPUT_DIR}" 2>/dev/null)" ]]; then
    echo "error: output directory is not empty: ${OUTPUT_DIR}" >&2
    exit 73
  fi
fi

mkdir -p "${OUTPUT_DIR}"
MANIFEST_PATH="${OUTPUT_DIR}/manifest.tsv"
printf 'name\tstatus\tstdout\tstderr\n' > "${MANIFEST_PATH}"
SUMMARY_PATH="${OUTPUT_DIR}/review-summary.tsv"
SUMMARY_JSON_PATH="${OUTPUT_DIR}/review-summary.json"
CHECKSUM_PATH="${OUTPUT_DIR}/checksums.tsv"
GENERATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

run_capture() {
  local name="$1"
  local stdout_name="$2"
  shift 2

  local stdout_path="${OUTPUT_DIR}/${stdout_name}"
  local stderr_name="${name}.stderr"
  local stderr_path="${OUTPUT_DIR}/${stderr_name}"
  local status_path="${OUTPUT_DIR}/${name}.status"
  local status

  set +e
  "$@" > "${stdout_path}" 2> "${stderr_path}"
  status=$?
  set -e

  printf '%s\n' "${status}" > "${status_path}"
  printf '%s\t%s\t%s\t%s\n' "${name}" "${status}" "${stdout_name}" "${stderr_name}" >> "${MANIFEST_PATH}"
}

status_for() {
  local name="$1"
  local status_path="${OUTPUT_DIR}/${name}.status"
  if [[ -f "${status_path}" ]]; then
    /bin/cat "${status_path}"
  else
    printf 'skipped'
  fi
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\t'/\\t}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  printf '%s' "${value}"
}

json_string() {
  printf '"'
  json_escape "$1"
  printf '"'
}

summary_row() {
  local name="$1"
  local expected="$2"
  local scope="$3"
  local note="$4"
  local status

  status="$(status_for "${name}")"

  printf '%s\t%s\t%s\t%s\t%s\n' "${name}" "${status}" "${expected}" "${scope}" "${note}" >> "${SUMMARY_PATH}"

  if [[ "${SUMMARY_JSON_FIRST_ROW}" == "0" ]]; then
    printf ',\n' >> "${SUMMARY_JSON_PATH}"
  fi
  SUMMARY_JSON_FIRST_ROW=0

  {
    printf '    {"name":'
    json_string "${name}"
    printf ',"status":'
    json_string "${status}"
    printf ',"expected":'
    json_string "${expected}"
    printf ',"scope":'
    json_string "${scope}"
    printf ',"note":'
    json_string "${note}"
    printf '}'
  } >> "${SUMMARY_JSON_PATH}"
}

capture_schema_resources() {
  local name="schema-resources"
  local stdout_name="schema-resources.tsv"
  local stdout_path="${OUTPUT_DIR}/${stdout_name}"
  local stderr_name="${name}.stderr"
  local stderr_path="${OUTPUT_DIR}/${stderr_name}"
  local status_path="${OUTPUT_DIR}/${name}.status"
  local status=0

  printf 'schema\tsha256\tbytes\tbundlePath\n' > "${stdout_path}"
  : > "${stderr_path}"

  for schema in "${EXPECTED_SCHEMA_FILES[@]}"; do
    local schema_path="${SCHEMA_DIR}/${schema}"
    local bundle_path="Contents/Resources/schemas/${schema}"
    if [[ ! -s "${schema_path}" ]]; then
      printf 'missing bundled schema: %s\n' "${schema_path}" >> "${stderr_path}"
      status=1
      continue
    fi

    local digest
    local bytes
    if ! digest="$(/usr/bin/shasum -a 256 "${schema_path}" | /usr/bin/awk '{print $1}')"; then
      printf 'could not hash bundled schema: %s\n' "${schema_path}" >> "${stderr_path}"
      status=1
      continue
    fi
    if ! bytes="$(/usr/bin/stat -f '%z' "${schema_path}")"; then
      printf 'could not stat bundled schema: %s\n' "${schema_path}" >> "${stderr_path}"
      status=1
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' "${schema}" "${digest}" "${bytes}" "${bundle_path}" >> "${stdout_path}"
  done

  printf '%s\n' "${status}" > "${status_path}"
  printf '%s\t%s\t%s\t%s\n' "${name}" "${status}" "${stdout_name}" "${stderr_name}" >> "${MANIFEST_PATH}"
}

capture_bundle_executables() {
  local name="bundle-executables"
  local stdout_name="bundle-executables.tsv"
  local stdout_path="${OUTPUT_DIR}/${stdout_name}"
  local stderr_name="${name}.stderr"
  local stderr_path="${OUTPUT_DIR}/${stderr_name}"
  local status_path="${OUTPUT_DIR}/${name}.status"
  local macos_dir="${APP_PATH}/Contents/MacOS"
  local status=0

  printf 'executable\tsha256\tbytes\tbundlePath\n' > "${stdout_path}"
  : > "${stderr_path}"

  for executable in "${EXPECTED_EXECUTABLES[@]}"; do
    local executable_path="${macos_dir}/${executable}"
    local bundle_path="Contents/MacOS/${executable}"
    if [[ ! -x "${executable_path}" ]]; then
      printf 'missing or non-executable bundled executable: %s\n' "${executable_path}" >> "${stderr_path}"
      status=1
      continue
    fi

    local digest
    local bytes
    if ! digest="$(/usr/bin/shasum -a 256 "${executable_path}" | /usr/bin/awk '{print $1}')"; then
      printf 'could not hash bundled executable: %s\n' "${executable_path}" >> "${stderr_path}"
      status=1
      continue
    fi
    if ! bytes="$(/usr/bin/stat -f '%z' "${executable_path}")"; then
      printf 'could not stat bundled executable: %s\n' "${executable_path}" >> "${stderr_path}"
      status=1
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' "${executable}" "${digest}" "${bytes}" "${bundle_path}" >> "${stdout_path}"
  done

  printf '%s\n' "${status}" > "${status_path}"
  printf '%s\t%s\t%s\t%s\n' "${name}" "${status}" "${stdout_name}" "${stderr_name}" >> "${MANIFEST_PATH}"
}

capture_capabilities_schema_resources() {
  local name="capabilities-schema-resources"
  local stdout_name="capabilities-schema-resources.tsv"
  local stdout_path="${OUTPUT_DIR}/${stdout_name}"
  local stderr_name="${name}.stderr"
  local stderr_path="${OUTPUT_DIR}/${stderr_name}"
  local status_path="${OUTPUT_DIR}/${name}.status"
  local capabilities_path="${OUTPUT_DIR}/viftyctl-capabilities.json"
  local status

  set +e
  ruby -rjson -e '
    path = ARGV.fetch(0)
    expected = {
      "audit" => "Contents/Resources/schemas/viftyctl-audit.schema.json",
      "capabilities" => "Contents/Resources/schemas/viftyctl-capabilities.schema.json",
      "commandError" => "Contents/Resources/schemas/viftyctl-command-error.schema.json",
      "diagnose" => "Contents/Resources/schemas/viftyctl-diagnose.schema.json",
      "status" => "Contents/Resources/schemas/viftyctl-status.schema.json"
    }

    puts "key\tadvertisedResource\texpectedResource"
    begin
      data = JSON.parse(File.read(path))
    rescue StandardError => error
      warn "could not parse viftyctl capabilities JSON: #{error.message}"
      exit 1
    end

    resources = data["schemaResources"]
    unless resources.is_a?(Hash)
      warn "viftyctl capabilities JSON did not include schemaResources"
      exit 1
    end

    ok = true
    expected.each do |key, expected_resource|
      actual = resources[key]
      puts "#{key}\t#{actual}\t#{expected_resource}"
      if actual != expected_resource
        warn "schemaResources.#{key} #{actual.inspect} did not match #{expected_resource}"
        ok = false
      end
    end

    exit(ok ? 0 : 1)
  ' "${capabilities_path}" > "${stdout_path}" 2> "${stderr_path}"
  status=$?
  set -e

  printf '%s\n' "${status}" > "${status_path}"
  printf '%s\t%s\t%s\t%s\n' "${name}" "${status}" "${stdout_name}" "${stderr_name}" >> "${MANIFEST_PATH}"
}

capture_release_artifact_summary() {
  if [[ -z "${RELEASE_SUMMARY_PATH}" ]]; then
    return
  fi

  local name="release-artifact-summary"
  local stdout_name="release-artifact-summary.tsv"
  local stdout_path="${OUTPUT_DIR}/${stdout_name}"
  local stderr_name="${name}.stderr"
  local stderr_path="${OUTPUT_DIR}/${stderr_name}"
  local status_path="${OUTPUT_DIR}/${name}.status"
  local json_name="release-artifact-summary.json"
  local json_path="${OUTPUT_DIR}/${json_name}"
  local installed_app_version=""
  local status

  : > "${stderr_path}"
  if ! /bin/cp "${RELEASE_SUMMARY_PATH}" "${json_path}" 2> "${stderr_path}"; then
    status=1
    printf 'field\tvalue\n' > "${stdout_path}"
  else
    if ! installed_app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}" 2>> "${stderr_path}")"; then
      installed_app_version=""
    fi

    set +e
    ruby -rjson -e '
      source_path, copied_path, installed_app_version, expected_schema_id = ARGV

      def clean(value)
        value.to_s.gsub(/[\t\r\n]+/, " ")
      end

      begin
        data = JSON.parse(File.read(copied_path))
      rescue StandardError => error
        warn "could not parse release artifact summary JSON: #{error.message}"
        exit 1
      end

      fields = {
        "sourcePath" => source_path,
        "copiedFile" => File.basename(copied_path),
        "schemaVersion" => data["schemaVersion"],
        "schemaID" => data["schemaID"],
        "status" => data["status"],
        "installedAppBundleVersion" => installed_app_version,
        "caskVersion" => data["caskVersion"],
        "bundleVersion" => data["bundleVersion"],
        "expectedArtifactName" => data["expectedArtifactName"],
        "expectedSHA" => data["expectedSHA"],
        "expectedSHASource" => data["expectedSHASource"],
        "actualSHA" => data["actualSHA"],
        "expectedTeamID" => data["expectedTeamID"],
        "requiredTeamID" => data["requiredTeamID"],
        "signatureChecksSkipped" => data["signatureChecksSkipped"],
        "notarizationChecksSkipped" => data["notarizationChecksSkipped"],
        "failureCheck" => data["failureCheck"],
        "failureMessage" => data["failureMessage"]
      }

      puts "field\tvalue"
      fields.each do |field, value|
        next if value.nil?
        puts "#{field}\t#{clean(value)}"
      end

      ok = true
      unless data["schemaID"] == expected_schema_id
        warn "release artifact summary schemaID #{data["schemaID"].inspect} did not match #{expected_schema_id}"
        ok = false
      end

      unless data["status"] == "passed"
        warn "release artifact summary status #{data["status"].inspect} did not report passed"
        ok = false
      end

      if installed_app_version.to_s.empty?
        warn "installed app bundle version could not be read from Info.plist"
        ok = false
      end

      summary_bundle_version = data["bundleVersion"].to_s
      if !summary_bundle_version.empty? && summary_bundle_version != installed_app_version
        warn "release artifact summary bundleVersion #{summary_bundle_version.inspect} did not match installed app bundle version #{installed_app_version.inspect}"
        ok = false
      end

      summary_cask_version = data["caskVersion"].to_s
      if !summary_cask_version.empty? && summary_cask_version != installed_app_version
        warn "release artifact summary caskVersion #{summary_cask_version.inspect} did not match installed app bundle version #{installed_app_version.inspect}"
        ok = false
      end

      expected_artifact_name = "Vifty-v#{summary_cask_version}.zip"
      if data["expectedArtifactName"].to_s != expected_artifact_name
        warn "release artifact summary expectedArtifactName #{data["expectedArtifactName"].inspect} did not match #{expected_artifact_name}"
        ok = false
      end

      %w[expectedSHA actualSHA].each do |field|
        unless data[field].to_s.match?(/\A[0-9a-f]{64}\z/)
          warn "release artifact summary #{field} must be a lowercase 64-character SHA-256 checksum"
          ok = false
        end
      end

      if !data["expectedSHA"].to_s.empty? && !data["actualSHA"].to_s.empty? && data["expectedSHA"].to_s != data["actualSHA"].to_s
        warn "release artifact summary expectedSHA did not match actualSHA"
        ok = false
      end

      if data["signatureChecksSkipped"] != false
        warn "release artifact summary must not skip signature checks"
        ok = false
      end

      if data["notarizationChecksSkipped"] != false
        warn "release artifact summary must not skip notarization checks"
        ok = false
      end

      checks = data["checks"]
      unless checks.is_a?(Array) && !checks.empty?
        warn "release artifact summary checks must be a non-empty array"
        ok = false
        checks = []
      end

      checks.each do |check|
        unless check.is_a?(Hash)
          warn "release artifact summary checks must contain objects"
          ok = false
          next
        end
        name = check["name"].to_s
        status = check["status"].to_s
        if name.empty?
          warn "release artifact summary check is missing name"
          ok = false
        end
        if status != "passed"
          warn "release artifact summary check #{name.empty? ? "(missing)" : name} status #{status.inspect} did not report passed"
          ok = false
        end
      end

      exit(ok ? 0 : 1)
    ' "${RELEASE_SUMMARY_PATH}" "${json_path}" "${installed_app_version}" "${RELEASE_ARTIFACT_SUMMARY_SCHEMA_ID}" > "${stdout_path}" 2>> "${stderr_path}"
    status=$?
    set -e
  fi

  printf '%s\n' "${status}" > "${status_path}"
  printf '%s\t%s\t%s\t%s\n' "${name}" "${status}" "${stdout_name}" "${stderr_name}" >> "${MANIFEST_PATH}"
}

capture_release_checklist() {
  if [[ -z "${RELEASE_CHECKLIST_PATH}" ]]; then
    return
  fi

  local name="release-checklist"
  local stdout_name="release-checklist.tsv"
  local stdout_path="${OUTPUT_DIR}/${stdout_name}"
  local stderr_name="${name}.stderr"
  local stderr_path="${OUTPUT_DIR}/${stderr_name}"
  local status_path="${OUTPUT_DIR}/${name}.status"
  local markdown_name="release-checklist.md"
  local markdown_path="${OUTPUT_DIR}/${markdown_name}"
  local installed_app_version=""
  local status

  : > "${stderr_path}"
  if ! /bin/cp "${RELEASE_CHECKLIST_PATH}" "${markdown_path}" 2> "${stderr_path}"; then
    status=1
    printf 'field\tvalue\n' > "${stdout_path}"
  else
    if ! installed_app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}" 2>> "${stderr_path}")"; then
      installed_app_version=""
    fi

    set +e
    ruby -e '
      source_path, copied_path, installed_app_version = ARGV
      text = File.read(copied_path)

      title_version = text[/^# Vifty ([^\s]+) Release Checklist\s*$/, 1].to_s
      checks = {
        "hasWorkflowSection" => text.include?("## Verified By The Release Workflow"),
        "hasFollowUpSection" => text.include?("## Required Post-Publication Follow-Up"),
        "hasCaskChecksumFollowUp" => text.include?("scripts/update-cask-checksum.sh"),
        "hasPublicVerifierFollowUp" => text.include?("scripts/verify-release-artifact.sh"),
        "hasEvidenceReviewFollowUp" => text.include?("scripts/review-validation-evidence.sh"),
        "hasCompatibilityGate" => text.include?("manualSmokeTestResult: \"passed-auto-restored\""),
        "hasTrustedHomebrewWarning" => text.include?("do not describe the Homebrew path as a fully trusted public binary install")
      }

      puts "field\tvalue"
      puts "sourcePath\t#{source_path}"
      puts "copiedFile\t#{File.basename(copied_path)}"
      puts "titleVersion\t#{title_version}"
      puts "installedAppBundleVersion\t#{installed_app_version}"
      checks.each { |field, value| puts "#{field}\t#{value}" }

      ok = true
      if title_version.empty?
        warn "release checklist title must be # Vifty <version> Release Checklist"
        ok = false
      elsif installed_app_version.to_s.empty?
        warn "installed app bundle version could not be read from Info.plist"
        ok = false
      elsif title_version != installed_app_version
        warn "release checklist title version #{title_version.inspect} did not match installed app bundle version #{installed_app_version.inspect}"
        ok = false
      end

      checks.each do |field, value|
        unless value
          warn "release checklist is missing #{field}"
          ok = false
        end
      end

      expected_zip = "Vifty-v#{title_version}.zip"
      expected_checksum = "Vifty-v#{title_version}.zip.sha256"
      expected_summary = "Vifty-v#{title_version}-artifact-summary.json"
      [expected_zip, expected_checksum, expected_summary].each do |token|
        unless title_version.empty? || text.include?(token)
          warn "release checklist is missing #{token}"
          ok = false
        end
      end

      exit(ok ? 0 : 1)
    ' "${RELEASE_CHECKLIST_PATH}" "${markdown_path}" "${installed_app_version}" > "${stdout_path}" 2>> "${stderr_path}"
    status=$?
    set -e
  fi

  printf '%s\n' "${status}" > "${status_path}"
  printf '%s\t%s\t%s\t%s\n' "${name}" "${status}" "${stdout_name}" "${stderr_name}" >> "${MANIFEST_PATH}"
}

capture_privacy_review() {
  local name="privacy-review"
  local stdout_name="privacy-review.tsv"
  local stdout_path="${OUTPUT_DIR}/${stdout_name}"
  local stderr_name="${name}.stderr"
  local stderr_path="${OUTPUT_DIR}/${stderr_name}"
  local status_path="${OUTPUT_DIR}/${name}.status"
  local status
  local host_name=""
  local short_host_name=""

  host_name="$(/bin/hostname 2>/dev/null || true)"
  short_host_name="$(/bin/hostname -s 2>/dev/null || true)"

  set +e
  ruby -e '
    bundle, home_path, host_name, short_host_name = ARGV
    ignored = {
      "privacy-review.tsv" => true,
      "privacy-review.stderr" => true,
      "privacy-review.status" => true
    }
    common_host_tokens = %w[localhost mac macbook macbookpro]
    host_tokens = [host_name, short_host_name]
      .map(&:to_s)
      .map(&:strip)
      .uniq
      .select { |value| value.length >= 5 }
      .reject { |value| common_host_tokens.include?(value.downcase.gsub(/[^a-z0-9]/, "")) }
    patterns = [
      ["serial-number-label", /serial\s+number|IOPlatformSerialNumber/i],
      ["hardware-uuid-label", /hardware\s+uuid|platform\s+uuid|IOPlatformUUID/i],
      ["user-home-path", %r{/Users/[^/\s]+}]
    ]
    if home_path.to_s.start_with?("/Users/")
      patterns << ["current-home-path", Regexp.new(Regexp.escape(home_path))]
    end
    host_tokens.each do |token|
      patterns << ["local-hostname", Regexp.new(Regexp.escape(token), Regexp::IGNORECASE)]
    end

    findings = []
    Dir.children(bundle).sort.each do |entry|
      next if ignored[entry]
      path = File.join(bundle, entry)
      next unless File.file?(path)
      begin
        File.foreach(path).with_index(1) do |line, line_number|
          patterns.each do |kind, pattern|
            findings << [entry, line_number, kind] if line.match?(pattern)
          end
        end
      rescue ArgumentError
        next
      end
    end

    puts "finding\tfile\tline\tkind"
    if findings.empty?
      puts "none\t-\t-\tpassed"
      exit 0
    end

    findings.each do |file, line, kind|
      puts "redaction-needed\t#{file}\t#{line}\t#{kind}"
    end
    warn "privacy review found local identifiers; review or redact the named files before sharing the bundle"
    exit 1
  ' "${OUTPUT_DIR}" "${HOME:-}" "${host_name}" "${short_host_name}" > "${stdout_path}" 2> "${stderr_path}"
  status=$?
  set -e

  printf '%s\n' "${status}" > "${status_path}"
  printf '%s\t%s\t%s\t%s\n' "${name}" "${status}" "${stdout_name}" "${stderr_name}" >> "${MANIFEST_PATH}"
}

write_review_summary() {
  printf 'name\tstatus\texpected\tscope\tnote\n' > "${SUMMARY_PATH}"
  SUMMARY_JSON_FIRST_ROW=1

  {
    printf '{\n'
    printf '  "schemaVersion": 1,\n'
    printf '  "generatedAtUTC": '
    json_string "${GENERATED_AT_UTC}"
    printf ',\n'
    printf '  "appPath": '
    json_string "${APP_PATH}"
    printf ',\n'
    printf '  "readOnly": true,\n'
    printf '  "coolingCommandsRun": false,\n'
    printf '  "includeProbeLocal": '
    if [[ "${INCLUDE_PROBE_LOCAL}" == "1" ]]; then
      printf 'true'
    else
      printf 'false'
    fi
    printf ',\n'
    printf '  "releaseArtifactSummaryPath": '
    json_string "${RELEASE_SUMMARY_PATH}"
    printf ',\n'
    printf '  "releaseChecklistPath": '
    json_string "${RELEASE_CHECKLIST_PATH}"
    printf ',\n'
    printf '  "checks": [\n'
  } > "${SUMMARY_JSON_PATH}"

  summary_row "system-hw-model" "0" "hardware-validation" "Machine model source for the report."
  summary_row "app-info-plist" "0" "release-and-hardware" "Bundle metadata identifies the tested app version."
  summary_row "bundle-executables" "0" "release-and-hardware" "Bundled app/helper/daemon/CLI executables should be present, executable, and hashed."
  summary_row "privacy-review" "0" "public-report-privacy" "Evidence bundle should not contain local hostnames, /Users paths, serial labels, or hardware identifier labels."
  summary_row "release-artifact-summary" "0 or skipped" "release-trust" "Optional verifier summary should pass and match the installed app version when supplied."
  summary_row "release-checklist" "0 or skipped" "release-trust" "Optional release checklist should match the installed app version and include post-publication trust follow-up when supplied."
  summary_row "schema-resources" "0" "release-and-agent-contract" "Bundled release and viftyctl JSON Schemas should be present and hashed."
  summary_row "launchdaemon-lint" "0" "release-trust" "Bundled LaunchDaemon plist should be valid."
  summary_row "launchdaemon-teamid" "0 for public release" "release-trust" "Public releases should expose VIFTY_XPC_ALLOWED_TEAM_ID; ad-hoc builds may be empty."
  summary_row "launchctl-print-daemon" "0 when installed" "hardware-validation" "Nonzero means the daemon was not registered or not visible to launchctl."
  summary_row "codesign-verify-app" "0 for public release" "release-trust" "App signature should verify."
  summary_row "codesign-verify-viftyctl" "0 for public release" "release-trust" "Bundled viftyctl signature should verify."
  summary_row "codesign-verify-viftyhelper" "0 for public release" "release-trust" "Bundled helper signature should verify."
  summary_row "codesign-verify-viftydaemon" "0 for public release" "release-trust" "Bundled daemon signature should verify."
  summary_row "spctl-assess-app" "0 for public release" "release-trust" "Gatekeeper assessment should pass for notarized releases."
  summary_row "stapler-validate-app" "0 for public release" "release-trust" "Stapled notarization ticket should validate for public releases."
  summary_row "viftyctl-capabilities" "0 or 69" "agent-contract" "69 still preserves static JSON but means daemon status was unavailable."
  summary_row "capabilities-schema-resources" "0" "agent-contract" "Capabilities output should advertise installed schema resource paths."
  summary_row "viftyctl-status" "0" "agent-contract" "Nonzero means agent status could not be read."
  summary_row "viftyctl-diagnose" "0 or 75" "hardware-and-agent" "75 means a structured blocked readiness report was captured."
  summary_row "viftyctl-audit" "0" "agent-contract" "Read-only recent agent-control audit export should be captured."
  summary_row "viftyhelper-probeLocal" "0 or skipped" "hardware-validation" "Optional direct fan probe; use sudo on supported hardware."

  {
    printf '\n'
    printf '  ]\n'
    printf '}\n'
  } >> "${SUMMARY_JSON_PATH}"
}

cat > "${OUTPUT_DIR}/README.txt" <<'README'
Vifty validation evidence bundle.

Attach these files to a Hardware Validation Report issue when validating real
hardware. The viftyctl JSON files are read-only diagnostics and audit evidence. Bundle plist,
bundled executable hashes, bundled schema resource hashes, advertised schema
resource paths, privacy-review.tsv, LaunchDaemon, signing, notarization, and Gatekeeper files
identify exactly what
app/helper/daemon/CLI contract was tested. If --release-summary was supplied,
release-artifact-summary.json is a copy of the verifier output and
release-artifact-summary.tsv summarizes its pass/fail state. If
--release-checklist was supplied, release-checklist.md is a copy of the GitHub
Release checklist and release-checklist.tsv summarizes its version and follow-up
coverage. If
viftyhelper-probeLocal.txt is present, it was collected only because
--include-probe-local was requested. review-summary.tsv highlights the key
captured statuses for reviewers, review-summary.json provides the same status
rows for automation, and checksums.tsv contains SHA-256 digests and byte counts
for the captured evidence files.
README

{
  echo "generatedAtUTC=${GENERATED_AT_UTC}"
  echo "appPath=${APP_PATH}"
  echo "viftyctl=${VIFTYCTL}"
  echo "viftyHelper=${VIFTYHELPER}"
  echo "viftyDaemon=${VIFTYDAEMON}"
  echo "infoPlist=${INFO_PLIST}"
  echo "schemaDir=${SCHEMA_DIR}"
  echo "daemonPlist=${DAEMON_PLIST}"
  echo "daemonLabel=${DAEMON_LABEL}"
  echo "releaseArtifactSummaryPath=${RELEASE_SUMMARY_PATH}"
  echo "releaseChecklistPath=${RELEASE_CHECKLIST_PATH}"
  echo "includeProbeLocal=${INCLUDE_PROBE_LOCAL}"
  echo "readOnly=true"
  echo "coolingCommandsRun=false"
} > "${OUTPUT_DIR}/metadata.txt"

run_capture "system-sw_vers" "system-sw_vers.txt" /usr/bin/sw_vers
run_capture "system-uname" "system-uname.txt" /usr/bin/uname -srm
run_capture "system-hw-model" "system-hw-model.txt" /usr/sbin/sysctl -n hw.model

run_capture "app-info-plist" "app-info-plist.txt" /usr/libexec/PlistBuddy -c Print "${INFO_PLIST}"
capture_bundle_executables
capture_release_artifact_summary
capture_release_checklist
capture_schema_resources
run_capture "launchdaemon-plist" "launchdaemon-plist.txt" /usr/bin/plutil -p "${DAEMON_PLIST}"
run_capture "launchdaemon-lint" "launchdaemon-lint.txt" /usr/bin/plutil -lint "${DAEMON_PLIST}"
run_capture "launchdaemon-teamid" "launchdaemon-teamid.txt" /usr/bin/plutil -extract EnvironmentVariables.VIFTY_XPC_ALLOWED_TEAM_ID raw -o - "${DAEMON_PLIST}"
run_capture "launchctl-print-daemon" "launchctl-print-daemon.txt" /bin/launchctl print "system/${DAEMON_LABEL}"

run_capture "codesign-app" "codesign-app.txt" /usr/bin/codesign -dvvv "${APP_PATH}"
run_capture "codesign-verify-app" "codesign-verify-app.txt" /usr/bin/codesign --verify --deep --strict "${APP_PATH}"
run_capture "codesign-viftyctl" "codesign-viftyctl.txt" /usr/bin/codesign -dvvv "${VIFTYCTL}"
run_capture "codesign-verify-viftyctl" "codesign-verify-viftyctl.txt" /usr/bin/codesign --verify --strict "${VIFTYCTL}"
run_capture "codesign-viftyhelper" "codesign-viftyhelper.txt" /usr/bin/codesign -dvvv "${VIFTYHELPER}"
run_capture "codesign-verify-viftyhelper" "codesign-verify-viftyhelper.txt" /usr/bin/codesign --verify --strict "${VIFTYHELPER}"
run_capture "codesign-viftydaemon" "codesign-viftydaemon.txt" /usr/bin/codesign -dvvv "${VIFTYDAEMON}"
run_capture "codesign-verify-viftydaemon" "codesign-verify-viftydaemon.txt" /usr/bin/codesign --verify --strict "${VIFTYDAEMON}"
run_capture "spctl-assess-app" "spctl-assess-app.txt" /usr/sbin/spctl --assess --type execute --verbose "${APP_PATH}"
run_capture "stapler-validate-app" "stapler-validate-app.txt" /usr/bin/xcrun stapler validate "${APP_PATH}"

run_capture "viftyctl-capabilities" "viftyctl-capabilities.json" "${VIFTYCTL}" capabilities --json
capture_capabilities_schema_resources
run_capture "viftyctl-status" "viftyctl-status.json" "${VIFTYCTL}" status --json
run_capture "viftyctl-diagnose" "viftyctl-diagnose.json" "${VIFTYCTL}" diagnose --json
run_capture "viftyctl-audit" "viftyctl-audit.json" "${VIFTYCTL}" audit --limit 20 --json

if [[ "${INCLUDE_PROBE_LOCAL}" == "1" ]]; then
  run_capture "viftyhelper-probeLocal" "viftyhelper-probeLocal.txt" "${VIFTYHELPER}" probeLocal
else
  echo "Skipped. Re-run with --include-probe-local to collect direct helper fan probe output." > "${OUTPUT_DIR}/viftyhelper-probeLocal.txt"
fi

# Write a provisional summary so the privacy review also scans generated summary JSON.
write_review_summary
capture_privacy_review
write_review_summary

printf 'sha256\tbytes\tfile\n' > "${CHECKSUM_PATH}"
for evidence_file in "${OUTPUT_DIR}"/*; do
  if [[ ! -f "${evidence_file}" || "${evidence_file}" == "${CHECKSUM_PATH}" ]]; then
    continue
  fi

  digest="$(/usr/bin/shasum -a 256 "${evidence_file}" | /usr/bin/awk '{print $1}')"
  bytes="$(/usr/bin/stat -f '%z' "${evidence_file}")"
  printf '%s\t%s\t%s\n' "${digest}" "${bytes}" "$(basename "${evidence_file}")" >> "${CHECKSUM_PATH}"
done

echo "Validation evidence written to:"
echo "  ${OUTPUT_DIR}"
echo ""
echo "Review files before sharing. Attach the bundle contents to the Hardware Validation Report issue template."
