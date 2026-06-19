#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/collect-agent-run-smoke-evidence.sh [options] [-- child args...]

Collect supervised Vifty agent-run smoke evidence for supported hardware reports.

Options:
  --viftyctl <path>          viftyctl path (default:
                             /Applications/Vifty.app/Contents/MacOS/viftyctl)
  --output <dir>             Output directory (default:
                             .build/vifty-agent-run-smoke-<timestamp>)
  --duration <duration>      Smoke lease duration, e.g. 2m (default: 2m)
  --max-rpm-percent <count>  Max RPM percent for smoke run, 1 through 100
                             (default: 55)
  --reason <text>            Audit reason (default: agent run smoke test)
  --audit-limit <count>      Bounded audit event count, 1 through 200
                             (default: 20)
  --install-source <source>  Record where the viftyctl under test came from.
                             Values: not-recorded, source-build-tag,
                             source-first-unsigned-dev-zip,
                             notarized-github-release, homebrew-cask,
                             local-developer-id-build, local-ad-hoc-build,
                             other. Default: not-recorded.
  --source-ref <ref>         Record the source tag/ref/commit used for the build.
  --source-sha <sha>         Record the immutable 40-character source commit SHA.
                             Required for source-build-tag,
                             source-first-unsigned-dev-zip, and
                             local-ad-hoc-build.
  --source-artifact <path>   Hash the source-first tester zip or release artifact
                             used for the tested app, when available locally.
  -h, --help                 Show this help.

By default the smoke child command is:
  /bin/sleep 5

This script is intentionally not read-only when readiness is safe. It first
runs read-only capabilities and diagnose preflight. It runs exactly one bounded
viftyctl run --json smoke command only when diagnose says cooling is safe, then
captures read-only capabilities/status/audit/diagnose follow-up evidence. If
readiness is blocked or unsafe, it captures read-only status/audit evidence,
does not call viftyctl run, writes a blocked summary, and exits 75.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIFTYCTL="${VIFTYCTL:-/Applications/Vifty.app/Contents/MacOS/viftyctl}"
OUTPUT_DIR="${VIFTY_AGENT_RUN_SMOKE_OUTPUT_DIR:-}"
DURATION="${VIFTY_AGENT_RUN_SMOKE_DURATION:-2m}"
MAX_RPM_PERCENT="${VIFTY_AGENT_RUN_SMOKE_MAX_RPM_PERCENT:-55}"
REASON="${VIFTY_AGENT_RUN_SMOKE_REASON:-agent run smoke test}"
AUDIT_LIMIT="${VIFTY_AGENT_RUN_SMOKE_AUDIT_LIMIT:-20}"
INSTALL_SOURCE="${VIFTY_AGENT_RUN_SMOKE_INSTALL_SOURCE:-not-recorded}"
SOURCE_REF="${VIFTY_AGENT_RUN_SMOKE_SOURCE_REF:-}"
SOURCE_SHA="${VIFTY_AGENT_RUN_SMOKE_SOURCE_SHA:-}"
SOURCE_ARTIFACT_PATH="${VIFTY_AGENT_RUN_SMOKE_SOURCE_ARTIFACT:-}"
SOURCE_ARTIFACT_NAME=""
SOURCE_ARTIFACT_SHA256=""
SOURCE_ARTIFACT_BYTES=""
CHILD_COMMAND=("/bin/sleep" "5")
CUSTOM_CHILD=0

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
    --output)
      if [[ $# -lt 2 ]]; then
        echo "error: --output requires a directory" >&2
        exit 64
      fi
      OUTPUT_DIR="$2"
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
    --audit-limit)
      if [[ $# -lt 2 ]]; then
        echo "error: --audit-limit requires a count" >&2
        exit 64
      fi
      AUDIT_LIMIT="$2"
      shift 2
      ;;
    --install-source)
      if [[ $# -lt 2 ]]; then
        echo "error: --install-source requires a value" >&2
        exit 64
      fi
      INSTALL_SOURCE="$2"
      shift 2
      ;;
    --source-ref)
      if [[ $# -lt 2 ]]; then
        echo "error: --source-ref requires a value" >&2
        exit 64
      fi
      SOURCE_REF="$2"
      shift 2
      ;;
    --source-sha)
      if [[ $# -lt 2 ]]; then
        echo "error: --source-sha requires a value" >&2
        exit 64
      fi
      SOURCE_SHA="$2"
      shift 2
      ;;
    --source-artifact)
      if [[ $# -lt 2 ]]; then
        echo "error: --source-artifact requires a path" >&2
        exit 64
      fi
      SOURCE_ARTIFACT_PATH="$2"
      shift 2
      ;;
    --)
      shift
      CUSTOM_CHILD=1
      CHILD_COMMAND=("$@")
      break
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

if [[ "${CUSTOM_CHILD}" -eq 1 && "${#CHILD_COMMAND[@]}" -eq 0 ]]; then
  echo "error: custom child command after -- cannot be empty" >&2
  exit 64
fi

if [[ ! "${AUDIT_LIMIT}" =~ ^[0-9]+$ ]] || [[ "${AUDIT_LIMIT}" -lt 1 ]] || [[ "${AUDIT_LIMIT}" -gt 200 ]]; then
  echo "error: --audit-limit must be an integer from 1 through 200" >&2
  exit 64
fi

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

case "${INSTALL_SOURCE}" in
  not-recorded|source-build-tag|source-first-unsigned-dev-zip|notarized-github-release|homebrew-cask|local-developer-id-build|local-ad-hoc-build|other)
    ;;
  *)
    echo "error: unsupported --install-source: ${INSTALL_SOURCE}" >&2
    exit 64
    ;;
esac

if [[ -n "${SOURCE_SHA}" ]]; then
  if [[ ! "${SOURCE_SHA}" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    echo "error: --source-sha must be a 40-character hexadecimal commit SHA" >&2
    exit 64
  fi
  SOURCE_SHA="$(printf '%s' "${SOURCE_SHA}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
fi

case "${INSTALL_SOURCE}" in
  source-build-tag|source-first-unsigned-dev-zip|local-ad-hoc-build)
    if [[ -z "${SOURCE_SHA}" ]]; then
      echo "error: ${INSTALL_SOURCE} evidence requires --source-sha with the immutable 40-character source commit SHA" >&2
      exit 64
    fi
    ;;
esac

case "${INSTALL_SOURCE}" in
  source-build-tag|source-first-unsigned-dev-zip)
    if [[ ! "${SOURCE_REF}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
      echo "error: ${INSTALL_SOURCE} evidence requires --source-ref to be the version tag used for the source build, for example v1.1.1" >&2
      exit 64
    fi
    ;;
esac

if [[ -n "${SOURCE_ARTIFACT_PATH}" ]]; then
  if [[ ! -f "${SOURCE_ARTIFACT_PATH}" ]]; then
    echo "error: source artifact not found: ${SOURCE_ARTIFACT_PATH}" >&2
    exit 64
  fi
  SOURCE_ARTIFACT_NAME="$(basename "${SOURCE_ARTIFACT_PATH}")"
  SOURCE_ARTIFACT_SHA256="$(/usr/bin/shasum -a 256 "${SOURCE_ARTIFACT_PATH}" | awk '{print $1}')"
  SOURCE_ARTIFACT_BYTES="$(/usr/bin/stat -f%z "${SOURCE_ARTIFACT_PATH}")"
fi

if [[ ! -x "${VIFTYCTL}" ]]; then
  echo "error: viftyctl is not executable: ${VIFTYCTL}" >&2
  exit 69
fi

if [[ -z "${OUTPUT_DIR}" ]]; then
  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  OUTPUT_DIR="${ROOT_DIR}/.build/vifty-agent-run-smoke-${timestamp}"
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
CHECKSUM_PATH="${OUTPUT_DIR}/checksums.tsv"
SUMMARY_JSON_PATH="${OUTPUT_DIR}/agent-run-smoke-evidence-summary.json"
GENERATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

printf 'name\tstatus\tstdout\tstderr\n' > "${MANIFEST_PATH}"

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

command_status() {
  local name="$1"
  cat "${OUTPUT_DIR}/${name}.status"
}

prepare_rate_limited_retry_after() {
  ruby -rjson -e '
    path = ARGV.fetch(0)
    begin
      data = JSON.parse(File.read(path))
      retry_after = data["retryAfterSeconds"]
      retry_after = Integer(retry_after)
      if data["errorCode"] == "PREPARE_RATE_LIMITED" &&
          data["safeToProceed"] == false &&
          retry_after >= 1 &&
          retry_after <= 300
        puts retry_after
      end
    rescue StandardError
      # Not a structured rate-limit response; leave stdout empty.
    end
  ' "$1"
}

sleep_for_rate_limit_retry() {
  local retry_after="$1"
  if [[ "${VIFTY_AGENT_RUN_SMOKE_SKIP_RETRY_SLEEP:-0}" == "1" ]]; then
    return
  fi
  sleep "${retry_after}"
}

diagnose_field_report() {
  ruby -rjson -e '
    path = ARGV.fetch(0)
    begin
      data = JSON.parse(File.read(path))
      values = [
        data["state"],
        data["safeToRequestCooling"],
        data["daemonControlPathReady"],
        data["manualControlActive"],
        data["recommendedAgentAction"],
        data["recommendedRecoveryAction"]
      ]
      puts values.map { |value| value.nil? ? "" : value.to_s }.join("\t")
    rescue StandardError
      puts ["", "", "", "", "", ""].join("\t")
    end
  ' "$1"
}

capabilities_run_contract_safe() {
  ruby -rjson -e '
    path = ARGV.fetch(0)
    begin
      data = JSON.parse(File.read(path))
      commands = data["commands"].is_a?(Array) ? data["commands"].map(&:to_s) : []
      workloads = data["workloads"].is_a?(Array) ? data["workloads"].map(&:to_s) : []
      schema_ids = data["schemaIDs"].is_a?(Hash) ? data["schemaIDs"] : {}
      policy = data["policy"].is_a?(Hash) ? data["policy"] : {}
      lifecycle = data["runLifecycle"].is_a?(Hash) ? data["runLifecycle"] : {}
      wrapper_resources = data["wrapperResources"].is_a?(Hash) ? data["wrapperResources"] : {}
      signals = lifecycle["signalsForwardedToChild"].is_a?(Array) ? lifecycle["signalsForwardedToChild"].map(&:to_s) : []
      workload_scripts = wrapper_resources["workloadScripts"].is_a?(Array) ? wrapper_resources["workloadScripts"].map(&:to_s) : []
      expected_workload_scripts = %w[
        cargo-build.sh
        cargo-test.sh
        custom-workload.sh
        local-model.sh
        make-build.sh
        make-test.sh
        make-verify.sh
        npm-build.sh
        npm-test.sh
        pytest.sh
        swift-release-build.sh
        swift-test.sh
        xcode-build.sh
        xcode-test.sh
      ]
      safe = data["schemaVersion"] == 1 &&
        schema_ids["capabilities"] == "https://vifty.local/schemas/viftyctl-capabilities.schema.json" &&
        schema_ids["diagnose"] == "https://vifty.local/schemas/viftyctl-diagnose.schema.json" &&
        schema_ids["commandError"] == "https://vifty.local/schemas/viftyctl-command-error.schema.json" &&
        data["daemonStatusAvailable"] == true &&
        data["policySource"] == "daemonStatus" &&
        data["policyStatusAvailable"] == true &&
        policy["enabled"] == true &&
        commands.include?("run") &&
        workloads.include?("test") &&
        lifecycle["childCommandPreflightBeforeCooling"] == true &&
        lifecycle["autoRestoreAfterChildExit"] == true &&
        lifecycle["structuredPreChildFailures"] == true &&
        lifecycle["cleanupStateReportedOnLaunchFailure"] == true &&
        %w[INT TERM HUP].all? { |signal| signals.include?(signal) } &&
        wrapper_resources["sourceDirectory"] == "examples/viftyctl" &&
        wrapper_resources["bundleDirectory"] == "Contents/Resources/viftyctl-wrappers" &&
        wrapper_resources["guardedRunScript"] == "guarded-run.sh" &&
        (expected_workload_scripts - workload_scripts).empty?
      puts safe ? "true" : "false"
    rescue StandardError
      puts "false"
    end
  ' "$1"
}

write_readme() {
  cat > "${OUTPUT_DIR}/README.txt" <<EOF
Vifty supervised agent-run smoke evidence
========================================

This bundle was generated by scripts/collect-agent-run-smoke-evidence.sh.

It is explicit smoke-test evidence for supported Apple Silicon MacBook Pro hardware. Unlike scripts/collect-agent-cooling-evidence.sh, this script is not read-only when readiness is safe: it requests one bounded \`viftyctl run --json\` cooling lease for a short child command and captures follow-up read-only evidence.

The bundle records source provenance in \`metadata.txt\` and
\`agent-run-smoke-evidence-summary.json\`. The default is
\`installSource=not-recorded\`; clean source checkouts should prefer
\`make agent-run-smoke-evidence-current-build\`, which records
\`installSource=local-ad-hoc-build\`, the current git ref, and the immutable
40-character source SHA for the freshly built \`viftyctl\`.

The collector proceeds only when \`pre-capabilities.json\` exits 0, advertises \`schemaVersion=1\`, stable \`schemaIDs.capabilities\`, \`schemaIDs.diagnose\`, and \`schemaIDs.commandError\`, \`daemonStatusAvailable=true\`, \`policySource=daemonStatus\`, \`policyStatusAvailable=true\`, \`policy.enabled=true\`, \`run\`, the \`test\` workload, the expected \`wrapperResources\` source/app-bundle-relative discovery metadata, and the safe \`runLifecycle\` contract used by guarded wrappers, then \`pre-diagnose.json\` reports \`safeToRequestCooling=true\`, \`daemonControlPathReady=true\`, \`manualControlActive=false\`, and \`recommendedAgentAction\` is either \`requestCooling\` or \`requestCoolingWithCaution\`. The caution path is still bounded smoke evidence; do not raise duration or RPM just because the collector proceeds. If the first \`viftyctl run --json\` attempt returns a structured \`PREPARE_RATE_LIMITED\` response with \`retryAfterSeconds\`, the collector records that response, waits once, and captures exactly one retry as the final run proof.

Do not run this smoke test when readiness is blocked, safeToRequestCooling is false, daemonControlPathReady is false, manualControlActive is true, hardware is unsupported, thermal pressure is critical, fans or sensors are missing, or RPM ranges are invalid.
In those cases this script should stop before calling \`viftyctl run\` and keep
the read-only preflight files as evidence.

Attach or paste:
- pre-diagnose.json
- pre-capabilities.json
- viftyctl-run.json, when present
- viftyctl-run-retry.json, only after a structured PREPARE_RATE_LIMITED retry
- post-capabilities.json, when present
- post-status.json or blocked-status.json
- post-audit.json or blocked-audit.json
- post-diagnose.json, when present
- manifest.tsv
- agent-run-smoke-evidence-summary.json
- checksums.tsv

The default child command is /bin/sleep 5. Custom child commands are allowed
after --, but hardware-validation reports should keep this smoke short and
boring.
EOF
}

write_metadata() {
  local read_only="$1"
  local cooling_commands_run="$2"
  cat > "${OUTPUT_DIR}/metadata.txt" <<EOF
generatedAtUTC=${GENERATED_AT_UTC}
readOnly=${read_only}
coolingCommandsRun=${cooling_commands_run}
viftyctl=${VIFTYCTL}
installSource=${INSTALL_SOURCE}
sourceRef=${SOURCE_REF}
sourceSHA=${SOURCE_SHA}
sourceArtifactName=${SOURCE_ARTIFACT_NAME}
sourceArtifactSHA256=${SOURCE_ARTIFACT_SHA256}
sourceArtifactBytes=${SOURCE_ARTIFACT_BYTES}
workload=test
duration=${DURATION}
maxRPMPercent=${MAX_RPM_PERCENT}
reason=${REASON}
auditLimit=${AUDIT_LIMIT}
childCommand=${CHILD_COMMAND[*]}
EOF
}

write_summary_json() {
  local status="$1"
  local read_only="$2"
  local cooling_commands_run="$3"
  local run_status="$4"
  local skipped_reason="$5"
  local run_stdout_name="$6"
  local run_stderr_name="$7"
  local rate_limit_retry_attempted="$8"
  local rate_limit_retry_after="$9"
  local rate_limit_initial_status="${10}"

  ruby -rjson -e '
    manifest_path, generated_at, viftyctl, install_source, source_ref,
      source_sha, source_artifact_name, source_artifact_sha256,
      source_artifact_bytes, workload, duration, max_rpm_percent,
      reason, status, read_only, cooling_commands_run, run_status,
      skipped_reason, audit_limit, pre_capabilities_path, pre_diagnose_path,
      run_json_path, run_stdout_name, run_stderr_name, rate_limit_retry_attempted,
      rate_limit_retry_after, rate_limit_initial_status = ARGV.shift(27)

    def boolean_or_nil(value)
      [true, false].include?(value) ? value : nil
    end

    def integer_or_nil(value)
      value.is_a?(Integer) ? value : nil
    end

    commands = File.readlines(manifest_path, chomp: true).drop(1).map do |line|
      name, command_status, stdout, stderr = line.split("\t", 4)
      {
        "name" => name,
        "status" => command_status.to_i,
        "stdout" => stdout,
        "stderr" => stderr,
        "statusFile" => "#{name}.status"
      }
    end
    diagnose = begin
      JSON.parse(File.read(pre_diagnose_path))
    rescue StandardError
      {}
    end
    capabilities = begin
      JSON.parse(File.read(pre_capabilities_path))
    rescue StandardError
      {}
    end
    run_report = begin
      File.file?(run_json_path) ? JSON.parse(File.read(run_json_path)) : {}
    rescue StandardError
      {}
    end
    diagnose_app_preferences = diagnose["appPreferences"].is_a?(Hash) ? diagnose["appPreferences"] : {}
    preflight_app_preferences = {
      "startupMode" => diagnose_app_preferences["startupMode"],
      "startupModeSource" => diagnose_app_preferences["startupModeSource"],
      "readError" => diagnose_app_preferences.key?("readError") ? diagnose_app_preferences["readError"] : nil
    }
    run = if run_status.to_s.empty?
      {
        "exitStatus" => nil,
        "stdout" => nil,
        "stderr" => nil,
        "skippedReason" => skipped_reason,
        "coolingLeasePrepared" => nil,
        "autoRestoreAttempted" => nil,
        "autoRestoreSucceeded" => nil,
        "childExitCode" => nil
      }
    else
      exit_status = run_status.to_i
      cooling_lease_prepared = boolean_or_nil(run_report["coolingLeasePrepared"])
      auto_restore_attempted = boolean_or_nil(run_report["autoRestoreAttempted"])
      auto_restore_succeeded = boolean_or_nil(run_report["autoRestoreSucceeded"])
      child_exit_code = integer_or_nil(run_report["childExitCode"])

      if exit_status == 0
        cooling_lease_prepared = true if cooling_lease_prepared.nil?
        auto_restore_attempted = true if auto_restore_attempted.nil?
        auto_restore_succeeded = true if auto_restore_succeeded.nil?
        child_exit_code = 0 if child_exit_code.nil?
      end

      {
        "exitStatus" => exit_status,
        "stdout" => run_stdout_name,
        "stderr" => run_stderr_name,
        "skippedReason" => nil,
        "coolingLeasePrepared" => cooling_lease_prepared,
        "autoRestoreAttempted" => auto_restore_attempted,
        "autoRestoreSucceeded" => auto_restore_succeeded,
        "childExitCode" => child_exit_code
      }
    end
    rate_limit_retry = {
      "attempted" => rate_limit_retry_attempted == "true",
      "retryAfterSeconds" => rate_limit_retry_after.to_s.empty? ? nil : rate_limit_retry_after.to_i,
      "initialExitStatus" => rate_limit_initial_status.to_s.empty? ? nil : rate_limit_initial_status.to_i,
      "stdout" => rate_limit_retry_attempted == "true" ? "viftyctl-run.json" : nil,
      "stderr" => rate_limit_retry_attempted == "true" ? "viftyctl-run.stderr" : nil
    }
    puts JSON.pretty_generate({
      "schemaVersion" => 1,
      "schemaID" => "https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json",
      "kind" => "vifty-agent-run-smoke",
      "generatedAtUTC" => generated_at,
      "status" => status,
      "readOnly" => read_only == "true",
      "coolingCommandsRun" => cooling_commands_run == "true",
      "viftyctl" => viftyctl,
      "installSource" => install_source,
      "sourceRef" => source_ref,
      "sourceSHA" => source_sha,
      "sourceArtifactName" => source_artifact_name,
      "sourceArtifactSHA256" => source_artifact_sha256,
      "sourceArtifactBytes" => source_artifact_bytes,
      "workload" => workload,
      "duration" => duration,
      "maxRPMPercent" => max_rpm_percent.to_i,
      "reason" => reason,
      "auditLimit" => audit_limit.to_i,
      "childCommand" => ARGV,
      "preflight" => {
        "capabilitiesExitStatus" => commands.find { |command| command["name"] == "pre-capabilities" }&.fetch("status"),
        "capabilitiesSchemaVersion" => capabilities["schemaVersion"],
        "capabilitiesSchemaID" => capabilities.dig("schemaIDs", "capabilities"),
        "diagnoseSchemaID" => capabilities.dig("schemaIDs", "diagnose"),
        "commandErrorSchemaID" => capabilities.dig("schemaIDs", "commandError"),
        "daemonStatusAvailable" => capabilities["daemonStatusAvailable"],
        "policySource" => capabilities["policySource"],
        "policyStatusAvailable" => capabilities["policyStatusAvailable"],
        "policyEnabled" => capabilities.dig("policy", "enabled"),
        "exitStatus" => commands.find { |command| command["name"] == "pre-diagnose" }.fetch("status"),
        "state" => diagnose["state"],
        "recommendedAgentAction" => diagnose["recommendedAgentAction"],
        "recommendedRecoveryAction" => diagnose["recommendedRecoveryAction"],
        "safeToRequestCooling" => diagnose["safeToRequestCooling"],
        "daemonControlPathReady" => diagnose["daemonControlPathReady"],
        "manualControlActive" => diagnose["manualControlActive"],
        "appPreferences" => preflight_app_preferences
      },
      "rateLimitRetry" => rate_limit_retry,
      "run" => run,
      "commands" => commands
    })
  ' "${MANIFEST_PATH}" "${GENERATED_AT_UTC}" "${VIFTYCTL}" \
    "${INSTALL_SOURCE}" "${SOURCE_REF}" "${SOURCE_SHA}" \
    "${SOURCE_ARTIFACT_NAME}" "${SOURCE_ARTIFACT_SHA256}" "${SOURCE_ARTIFACT_BYTES}" \
    "test" "${DURATION}" \
    "${MAX_RPM_PERCENT}" "${REASON}" "${status}" "${read_only}" \
    "${cooling_commands_run}" "${run_status}" "${skipped_reason}" \
    "${AUDIT_LIMIT}" "${OUTPUT_DIR}/pre-capabilities.json" \
    "${OUTPUT_DIR}/pre-diagnose.json" \
    "${OUTPUT_DIR}/${run_stdout_name}" "${run_stdout_name}" "${run_stderr_name}" \
    "${rate_limit_retry_attempted}" "${rate_limit_retry_after}" \
    "${rate_limit_initial_status}" "${CHILD_COMMAND[@]}" \
    > "${SUMMARY_JSON_PATH}"
}

write_checksums() {
  printf 'sha256\tbytes\tfile\n' > "${CHECKSUM_PATH}"
  while IFS= read -r -d '' file_path; do
    local relative_path
    local digest
    local bytes
    relative_path="${file_path#${OUTPUT_DIR}/}"
    if [[ "${relative_path}" == "checksums.tsv" ]]; then
      continue
    fi
    digest="$(/usr/bin/shasum -a 256 "${file_path}" | awk '{print $1}')"
    bytes="$(/usr/bin/stat -f%z "${file_path}")"
    printf '%s\t%s\t%s\n' "${digest}" "${bytes}" "${relative_path}" >> "${CHECKSUM_PATH}"
  done < <(/usr/bin/find "${OUTPUT_DIR}" -type f -print0 | /usr/bin/sort -z)
}

run_capture "pre-capabilities" "pre-capabilities.json" \
  "${VIFTYCTL}" capabilities --json
run_capture "pre-diagnose" "pre-diagnose.json" \
  "${VIFTYCTL}" diagnose --json

pre_capabilities_status="$(command_status "pre-capabilities")"
pre_diagnose_status="$(command_status "pre-diagnose")"
capabilities_safe="$(capabilities_run_contract_safe "${OUTPUT_DIR}/pre-capabilities.json")"
IFS=$'\t' read -r readiness_state safe_to_request daemon_ready manual_control_active agent_action recovery_action < <(
  diagnose_field_report "${OUTPUT_DIR}/pre-diagnose.json"
)

skip_reason=""
if [[ "${pre_capabilities_status}" -ne 0 || "${capabilities_safe}" != "true" ]]; then
  skip_reason="capabilities preflight did not advertise safe viftyctl run"
elif [[ "${manual_control_active}" == "true" ]]; then
  skip_reason="manual control active before smoke run"
elif [[ "${pre_diagnose_status}" -ne 0 ||
        "${safe_to_request}" != "true" ||
        "${daemon_ready}" != "true" ||
        "${manual_control_active}" != "false" ||
        ( "${agent_action}" != "requestCooling" && "${agent_action}" != "requestCoolingWithCaution" ) ]]; then
  skip_reason="readiness blocked before smoke run"
fi

if [[ -n "${skip_reason}" ]]; then
  run_capture "blocked-status" "blocked-status.json" \
    "${VIFTYCTL}" status --json
  run_capture "blocked-audit" "blocked-audit.json" \
    "${VIFTYCTL}" audit --limit "${AUDIT_LIMIT}" --json
  write_readme
  write_metadata "true" "false"
  write_summary_json "blocked" "true" "false" "" "${skip_reason}" "" "" "false" "" ""
  write_checksums
  echo "Agent run smoke skipped: ${skip_reason}"
  exit 75
fi

run_capture "viftyctl-run" "viftyctl-run.json" \
  "${VIFTYCTL}" run \
    --workload test \
    --duration "${DURATION}" \
    --max-rpm-percent "${MAX_RPM_PERCENT}" \
    --reason "${REASON}" \
    --json \
    -- "${CHILD_COMMAND[@]}"

run_status="$(command_status "viftyctl-run")"
run_stdout_name="viftyctl-run.json"
run_stderr_name="viftyctl-run.stderr"
rate_limit_retry_attempted="false"
rate_limit_retry_after=""
rate_limit_initial_status=""

if [[ "${run_status}" -ne 0 ]]; then
  retry_after="$(prepare_rate_limited_retry_after "${OUTPUT_DIR}/viftyctl-run.json")"
  if [[ -n "${retry_after}" ]]; then
    rate_limit_retry_attempted="true"
    rate_limit_retry_after="${retry_after}"
    rate_limit_initial_status="${run_status}"
    echo "Agent run smoke rate-limited; waiting ${retry_after}s before one retry" >&2
    sleep_for_rate_limit_retry "${retry_after}"
    run_capture "viftyctl-run-retry" "viftyctl-run-retry.json" \
      "${VIFTYCTL}" run \
        --workload test \
        --duration "${DURATION}" \
        --max-rpm-percent "${MAX_RPM_PERCENT}" \
        --reason "${REASON}" \
        --json \
        -- "${CHILD_COMMAND[@]}"
    run_status="$(command_status "viftyctl-run-retry")"
    run_stdout_name="viftyctl-run-retry.json"
    run_stderr_name="viftyctl-run-retry.stderr"
  fi
fi

run_capture "post-capabilities" "post-capabilities.json" \
  "${VIFTYCTL}" capabilities --json
run_capture "post-status" "post-status.json" \
  "${VIFTYCTL}" status --json
run_capture "post-audit" "post-audit.json" \
  "${VIFTYCTL}" audit --limit "${AUDIT_LIMIT}" --json
run_capture "post-diagnose" "post-diagnose.json" \
  "${VIFTYCTL}" diagnose --json

if [[ "${run_status}" -eq 0 ]]; then
  smoke_status="passed"
else
  smoke_status="failed"
fi

write_readme
write_metadata "false" "true"
write_summary_json "${smoke_status}" "false" "true" "${run_status}" "" \
  "${run_stdout_name}" "${run_stderr_name}" "${rate_limit_retry_attempted}" \
  "${rate_limit_retry_after}" "${rate_limit_initial_status}"
write_checksums

if [[ "${run_status}" -eq 0 ]]; then
  echo "Agent run smoke evidence written to ${OUTPUT_DIR}"
else
  echo "Agent run smoke evidence written to ${OUTPUT_DIR}; viftyctl run exited ${run_status}" >&2
fi

exit "${run_status}"
