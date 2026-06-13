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

diagnose_field_report() {
  ruby -rjson -e '
    path = ARGV.fetch(0)
    begin
      data = JSON.parse(File.read(path))
      values = [
        data["state"],
        data["safeToRequestCooling"],
        data["daemonControlPathReady"],
        data["recommendedAgentAction"],
        data["recommendedRecoveryAction"]
      ]
      puts values.map { |value| value.nil? ? "" : value.to_s }.join("\t")
    rescue StandardError
      puts ["", "", "", "", ""].join("\t")
    end
  ' "$1"
}

write_readme() {
  cat > "${OUTPUT_DIR}/README.txt" <<EOF
Vifty supervised agent-run smoke evidence
========================================

This bundle was generated by scripts/collect-agent-run-smoke-evidence.sh.

It is explicit smoke-test evidence for supported Apple Silicon MacBook Pro hardware. Unlike scripts/collect-agent-cooling-evidence.sh, this script is not read-only when readiness is safe: it requests one bounded \`viftyctl run --json\` cooling lease for a short child command and captures follow-up read-only evidence.

Do not run this smoke test when readiness is blocked, safeToRequestCooling is false, daemonControlPathReady is false, hardware is unsupported, thermal pressure is critical, fans or sensors are missing, or RPM ranges are invalid.
In those cases this script should stop before calling \`viftyctl run\` and keep
the read-only preflight files as evidence.

Attach or paste:
- pre-diagnose.json
- pre-capabilities.json
- viftyctl-run.json, when present
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

  ruby -rjson -e '
    manifest_path, generated_at, viftyctl, workload, duration, max_rpm_percent,
      reason, status, read_only, cooling_commands_run, run_status,
      skipped_reason, audit_limit, pre_diagnose_path = ARGV.shift(14)
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
    run = if run_status.to_s.empty?
      {
        "exitStatus" => nil,
        "stdout" => nil,
        "stderr" => nil,
        "skippedReason" => skipped_reason
      }
    else
      {
        "exitStatus" => run_status.to_i,
        "stdout" => "viftyctl-run.json",
        "stderr" => "viftyctl-run.stderr",
        "skippedReason" => nil
      }
    end
    puts JSON.pretty_generate({
      "schemaVersion" => 1,
      "schemaID" => "https://vifty.local/schemas/agent-run-smoke-evidence-summary.schema.json",
      "kind" => "vifty-agent-run-smoke",
      "generatedAtUTC" => generated_at,
      "status" => status,
      "readOnly" => read_only == "true",
      "coolingCommandsRun" => cooling_commands_run == "true",
      "viftyctl" => viftyctl,
      "workload" => workload,
      "duration" => duration,
      "maxRPMPercent" => max_rpm_percent.to_i,
      "reason" => reason,
      "auditLimit" => audit_limit.to_i,
      "childCommand" => ARGV,
      "preflight" => {
        "exitStatus" => commands.find { |command| command["name"] == "pre-diagnose" }.fetch("status"),
        "state" => diagnose["state"],
        "recommendedAgentAction" => diagnose["recommendedAgentAction"],
        "recommendedRecoveryAction" => diagnose["recommendedRecoveryAction"],
        "safeToRequestCooling" => diagnose["safeToRequestCooling"],
        "daemonControlPathReady" => diagnose["daemonControlPathReady"]
      },
      "run" => run,
      "commands" => commands
    })
  ' "${MANIFEST_PATH}" "${GENERATED_AT_UTC}" "${VIFTYCTL}" "test" "${DURATION}" \
    "${MAX_RPM_PERCENT}" "${REASON}" "${status}" "${read_only}" \
    "${cooling_commands_run}" "${run_status}" "${skipped_reason}" \
    "${AUDIT_LIMIT}" "${OUTPUT_DIR}/pre-diagnose.json" "${CHILD_COMMAND[@]}" \
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

pre_diagnose_status="$(command_status "pre-diagnose")"
IFS=$'\t' read -r readiness_state safe_to_request daemon_ready agent_action recovery_action < <(
  diagnose_field_report "${OUTPUT_DIR}/pre-diagnose.json"
)

if [[ "${pre_diagnose_status}" -ne 0 ||
      "${safe_to_request}" != "true" ||
      "${daemon_ready}" != "true" ||
      "${agent_action}" != "requestCooling" ]]; then
  run_capture "blocked-status" "blocked-status.json" \
    "${VIFTYCTL}" status --json
  run_capture "blocked-audit" "blocked-audit.json" \
    "${VIFTYCTL}" audit --limit "${AUDIT_LIMIT}" --json
  write_readme
  write_metadata "true" "false"
  write_summary_json "blocked" "true" "false" "" "readiness blocked before smoke run"
  write_checksums
  echo "Agent run smoke skipped: readiness blocked before smoke run"
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

run_capture "post-capabilities" "post-capabilities.json" \
  "${VIFTYCTL}" capabilities --json
run_capture "post-status" "post-status.json" \
  "${VIFTYCTL}" status --json
run_capture "post-audit" "post-audit.json" \
  "${VIFTYCTL}" audit --limit "${AUDIT_LIMIT}" --json
run_capture "post-diagnose" "post-diagnose.json" \
  "${VIFTYCTL}" diagnose --json

run_status="$(command_status "viftyctl-run")"
if [[ "${run_status}" -eq 0 ]]; then
  smoke_status="passed"
else
  smoke_status="failed"
fi

write_readme
write_metadata "false" "true"
write_summary_json "${smoke_status}" "false" "true" "${run_status}" ""
write_checksums

if [[ "${run_status}" -eq 0 ]]; then
  echo "Agent run smoke evidence written to ${OUTPUT_DIR}"
else
  echo "Agent run smoke evidence written to ${OUTPUT_DIR}; viftyctl run exited ${run_status}" >&2
fi

exit "${run_status}"
