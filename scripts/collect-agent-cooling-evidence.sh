#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/collect-agent-cooling-evidence.sh [options]

Collect read-only Vifty agent/helper support evidence for Agent Cooling reports.

Options:
  --viftyctl <path>      viftyctl path (default:
                         /Applications/Vifty.app/Contents/MacOS/viftyctl)
  --output <dir>         Output directory (default:
                         .build/vifty-agent-cooling-<timestamp>)
  --ui-context-file <path>
                         Optional current Vifty UI context text file to copy
                         into the evidence bundle as ui-context.txt.
  --guarded-run-stderr-file <path>
                         Optional captured guarded-run stderr transcript to copy
                         into the evidence bundle as guarded-run-stderr.txt.
                         Used only for bracketed decision JSON; no command runs.
  --guarded-run-script <path>
                         Optional guarded-run.sh path for --guarded-run-preflight
                         (default: source examples or bundled resources).
  --guarded-run-preflight <workload> <duration> <max-rpm-percent> <reason> -- <command> [args...]
                         Final option. Runs guarded-run.sh in read-only
                         preflight-only mode and captures guarded-run-stderr.txt.
  --audit-limit <count>  Bounded audit event count, 1 through 200 (default: 20)
  -h, --help             Show this help.

This script is read-only. It runs only:
  viftyctl capabilities --json
  viftyctl diagnose --json
  viftyctl status --json
  viftyctl audit --limit <count> --json
  launchctl print system/tech.reidar.vifty.daemon
  plutil -p /Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
  ls -ldO@ /Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
           /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon

With --guarded-run-preflight, it also runs guarded-run.sh --preflight-only,
which validates the exact workload command through read-only capabilities and
diagnose checks without requesting cooling or launching the child command.

It does not request cooling leases, restore Auto, call ViftyHelper, use sudo,
launch the guarded-run child command, or write SMC keys. If diagnose exits
nonzero because readiness is blocked, the JSON and exit status are still
captured for maintainers.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIFTYCTL="${VIFTYCTL:-/Applications/Vifty.app/Contents/MacOS/viftyctl}"
OUTPUT_DIR="${VIFTY_AGENT_EVIDENCE_OUTPUT_DIR:-}"
AUDIT_LIMIT="${VIFTY_AGENT_EVIDENCE_AUDIT_LIMIT:-20}"
UI_CONTEXT_FILE=""
GUARDED_RUN_STDERR_FILE=""
GUARDED_RUN_SCRIPT="${VIFTY_GUARDED_RUN_SCRIPT:-}"
GUARDED_RUN_PREFLIGHT=0
GUARDED_RUN_PREFLIGHT_ARGS=()
GUARDED_RUN_PREFLIGHT_STATUS=""

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
    --audit-limit)
      if [[ $# -lt 2 ]]; then
        echo "error: --audit-limit requires a count" >&2
        exit 64
      fi
      AUDIT_LIMIT="$2"
      shift 2
      ;;
    --ui-context-file)
      if [[ $# -lt 2 ]]; then
        echo "error: --ui-context-file requires a path" >&2
        exit 64
      fi
      UI_CONTEXT_FILE="$2"
      shift 2
      ;;
    --guarded-run-stderr-file)
      if [[ $# -lt 2 ]]; then
        echo "error: --guarded-run-stderr-file requires a path" >&2
        exit 64
      fi
      GUARDED_RUN_STDERR_FILE="$2"
      shift 2
      ;;
    --guarded-run-script)
      if [[ $# -lt 2 ]]; then
        echo "error: --guarded-run-script requires a path" >&2
        exit 64
      fi
      GUARDED_RUN_SCRIPT="$2"
      shift 2
      ;;
    --guarded-run-preflight)
      shift
      if [[ $# -lt 6 ]]; then
        echo "error: --guarded-run-preflight requires: <workload> <duration> <max-rpm-percent> <reason> -- <command> [args...]" >&2
        exit 64
      fi
      GUARDED_RUN_PREFLIGHT=1
      GUARDED_RUN_PREFLIGHT_ARGS=("$@")
      set --
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

if [[ ! "${AUDIT_LIMIT}" =~ ^[0-9]+$ ]] || [[ "${AUDIT_LIMIT}" -lt 1 ]] || [[ "${AUDIT_LIMIT}" -gt 200 ]]; then
  echo "error: --audit-limit must be an integer from 1 through 200" >&2
  exit 64
fi

if [[ ! -x "${VIFTYCTL}" ]]; then
  echo "error: viftyctl is not executable: ${VIFTYCTL}" >&2
  exit 69
fi

if [[ -n "${UI_CONTEXT_FILE}" && ! -f "${UI_CONTEXT_FILE}" ]]; then
  echo "error: --ui-context-file is not a readable file: ${UI_CONTEXT_FILE}" >&2
  exit 66
fi

if [[ -n "${GUARDED_RUN_STDERR_FILE}" && ! -f "${GUARDED_RUN_STDERR_FILE}" ]]; then
  echo "error: --guarded-run-stderr-file is not a readable file: ${GUARDED_RUN_STDERR_FILE}" >&2
  exit 66
fi

if [[ "${GUARDED_RUN_PREFLIGHT}" -eq 1 && -n "${GUARDED_RUN_STDERR_FILE}" ]]; then
  echo "error: --guarded-run-preflight and --guarded-run-stderr-file are mutually exclusive" >&2
  exit 64
fi

resolve_guarded_run_script() {
  if [[ -n "${GUARDED_RUN_SCRIPT}" ]]; then
    printf '%s\n' "${GUARDED_RUN_SCRIPT}"
    return
  fi

  if [[ -x "${ROOT_DIR}/examples/viftyctl/guarded-run.sh" ]]; then
    printf '%s\n' "${ROOT_DIR}/examples/viftyctl/guarded-run.sh"
    return
  fi

  if [[ -x "${SCRIPT_DIR}/viftyctl-wrappers/guarded-run.sh" ]]; then
    printf '%s\n' "${SCRIPT_DIR}/viftyctl-wrappers/guarded-run.sh"
    return
  fi

  if [[ -x "${ROOT_DIR}/Resources/viftyctl-wrappers/guarded-run.sh" ]]; then
    printf '%s\n' "${ROOT_DIR}/Resources/viftyctl-wrappers/guarded-run.sh"
    return
  fi

  printf '%s\n' ""
}

if [[ "${GUARDED_RUN_PREFLIGHT}" -eq 1 ]]; then
  GUARDED_RUN_SCRIPT="$(resolve_guarded_run_script)"
  if [[ -z "${GUARDED_RUN_SCRIPT}" ]]; then
    echo "error: guarded-run.sh was not found; pass --guarded-run-script <path>" >&2
    exit 66
  fi
  if [[ ! -x "${GUARDED_RUN_SCRIPT}" ]]; then
    echo "error: guarded-run.sh is not executable: ${GUARDED_RUN_SCRIPT}" >&2
    exit 69
  fi
fi

if [[ -z "${OUTPUT_DIR}" ]]; then
  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  OUTPUT_DIR="${ROOT_DIR}/.build/vifty-agent-cooling-${timestamp}"
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
if [[ -n "${UI_CONTEXT_FILE}" ]]; then
  cp "${UI_CONTEXT_FILE}" "${OUTPUT_DIR}/ui-context.txt"
  chmod 600 "${OUTPUT_DIR}/ui-context.txt"
fi
if [[ -n "${GUARDED_RUN_STDERR_FILE}" ]]; then
  cp "${GUARDED_RUN_STDERR_FILE}" "${OUTPUT_DIR}/guarded-run-stderr.txt"
  chmod 600 "${OUTPUT_DIR}/guarded-run-stderr.txt"
fi
MANIFEST_PATH="${OUTPUT_DIR}/manifest.tsv"
CHECKSUM_PATH="${OUTPUT_DIR}/checksums.tsv"
SUMMARY_JSON_PATH="${OUTPUT_DIR}/agent-cooling-evidence-summary.json"
GENERATED_AT_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
AGENT_COOLING_EVIDENCE_SUMMARY_SCHEMA_ID="https://vifty.local/schemas/agent-cooling-evidence-summary.schema.json"

resolve_app_info_plist() {
  local viftyctl_dir=""
  local viftyctl_real=""

  viftyctl_dir="$(cd "$(dirname "${VIFTYCTL}")" && pwd -P)"
  viftyctl_real="${viftyctl_dir}/$(basename "${VIFTYCTL}")"

  case "${viftyctl_real}" in
    */Contents/MacOS/viftyctl)
      printf '%s\n' "${viftyctl_real%/Contents/MacOS/viftyctl}/Contents/Info.plist"
      ;;
    *)
      printf '%s\n' "/Applications/Vifty.app/Contents/Info.plist"
      ;;
  esac
}

APP_INFO_PLIST="$(resolve_app_info_plist)"

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

run_viftyctl_capture() {
  local name="$1"
  local stdout_name="$2"
  shift 2

  if [[ "${VIFTY_TEST_SHELL_FIXTURES:-0}" == "1" ]]; then
    run_capture "${name}" "${stdout_name}" /bin/sh "${VIFTYCTL}" "$@"
  else
    run_capture "${name}" "${stdout_name}" "${VIFTYCTL}" "$@"
  fi
}

run_guarded_run_preflight_capture() {
  local stdout_path="${OUTPUT_DIR}/guarded-run-stdout.txt"
  local stderr_path="${OUTPUT_DIR}/guarded-run-stderr.txt"
  local status_path="${OUTPUT_DIR}/guarded-run-preflight.status"
  local status

  set +e
  VIFTYCTL="${VIFTYCTL}" \
  VIFTY_GUARDED_RUN_PREFLIGHT_ONLY=1 \
  VIFTY_GUARDED_RUN_FORCE_RETRY=0 \
  VIFTY_GUARDED_RUN_ALLOW_UNCOOLED=0 \
    "${GUARDED_RUN_SCRIPT}" --preflight-only "${GUARDED_RUN_PREFLIGHT_ARGS[@]}" > "${stdout_path}" 2> "${stderr_path}"
  status=$?
  set -e

  GUARDED_RUN_PREFLIGHT_STATUS="${status}"
  printf '%s\n' "${status}" > "${status_path}"
  chmod 600 "${stdout_path}" "${stderr_path}" "${status_path}"
}

if [[ "${GUARDED_RUN_PREFLIGHT}" -eq 1 ]]; then
  run_guarded_run_preflight_capture
fi

run_viftyctl_capture "viftyctl-capabilities" "viftyctl-capabilities.json" capabilities --json
run_viftyctl_capture "viftyctl-diagnose" "viftyctl-diagnose.json" diagnose --json
run_viftyctl_capture "viftyctl-status" "viftyctl-status.json" status --json
run_viftyctl_capture "viftyctl-audit" "viftyctl-audit.json" audit --limit "${AUDIT_LIMIT}" --json
run_capture "launchctl-print-daemon" "launchctl-print-daemon.txt" \
  /bin/launchctl print system/tech.reidar.vifty.daemon
run_capture "launchdaemon-plist" "launchdaemon-plist.txt" \
  /usr/bin/plutil -p /Library/LaunchDaemons/tech.reidar.vifty.daemon.plist
run_capture "helper-file-metadata" "helper-file-metadata.txt" \
  /bin/ls -ldO@ \
    /Library/LaunchDaemons/tech.reidar.vifty.daemon.plist \
    /Library/PrivilegedHelperTools/tech.reidar.vifty.daemon
run_capture "app-info-plist" "app-info-plist.txt" \
  /usr/bin/plutil -p "${APP_INFO_PLIST}"

cat > "${OUTPUT_DIR}/README.txt" <<EOF
Vifty agent/helper support evidence
===================================

This bundle was generated by scripts/collect-agent-cooling-evidence.sh.

It is read-only evidence for Agent Cooling reports, helper-unreachable reports,
rate limits, expired leases, restore failures, and guarded-run issues.

It does not request cooling leases, restore Auto, call ViftyHelper, use sudo,
launch guarded-run child workloads, or write SMC keys.

Attach or paste:
- viftyctl-diagnose.json
- viftyctl-capabilities.json
- viftyctl-status.json
- viftyctl-audit.json
- launchctl-print-daemon.txt
- launchdaemon-plist.txt
- helper-file-metadata.txt
- app-info-plist.txt
- manifest.tsv
- agent-cooling-evidence-summary.json
- privacy-review.tsv
- guarded-run-stderr.txt if you supplied --guarded-run-stderr-file
  or --guarded-run-preflight
- guarded-run-preflight.status and guarded-run-stdout.txt if you supplied
  --guarded-run-preflight

If viftyctl-diagnose.status is 75, readiness was blocked. Do not retry prepare
or run while diagnose reports blocked readiness, safeToRequestCooling=false, or
daemonControlPathReady=false.

If guarded-run-stderr.txt exists, maintainers should parse only the JSON between
guarded-run: BEGIN_VIFTY_GUARDED_RUN_DECISION_JSON and
guarded-run: END_VIFTY_GUARDED_RUN_DECISION_JSON. Do not parse surrounding
recovery prose.

If the helper is unreachable, launchctl-print-daemon.txt, launchdaemon-plist.txt,
and helper-file-metadata.txt show whether launchd can see the privileged daemon,
which plist is installed, and whether helper/plist files exist with expected
ownership and permissions. Nonzero status rows for these files are evidence; do
not rerun with sudo just to make them pass.

app-info-plist.txt records the app metadata found beside Vifty.app's viftyctl,
or /Applications/Vifty.app/Contents/Info.plist for source/dev viftyctl paths. It
helps maintainers distinguish v1.1.0 helper-unreachable reports from v1.1.1 or
current-source reports. A nonzero app-info-plist status means no app plist was
found at that read-only path.

If this report comes from the published v1.1.0 release and shows "Fan helper
unreachable" after updating, move to the v1.1.1 source-first hotfix or build the
current source before retrying helper repair.
Do not retag v1.1.0 or replace its unsigned-dev assets with a later build.

Before sharing publicly, check privacy-review.tsv. A nonzero privacy review
means the named files may contain private local paths, hostnames, serial-number
labels, hardware-identifier labels, or other identifiers.
EOF

cat > "${OUTPUT_DIR}/metadata.txt" <<EOF
generatedAtUTC=${GENERATED_AT_UTC}
readOnly=true
coolingCommandsRun=false
viftyctl=${VIFTYCTL}
auditLimit=${AUDIT_LIMIT}
guardedRunPreflight=$([[ "${GUARDED_RUN_PREFLIGHT}" -eq 1 ]] && printf 'true' || printf 'false')
EOF

if [[ "${GUARDED_RUN_PREFLIGHT}" -eq 1 ]]; then
  cat >> "${OUTPUT_DIR}/metadata.txt" <<EOF
guardedRunPreflightStatus=${GUARDED_RUN_PREFLIGHT_STATUS}
guardedRunPreflightTranscript=guarded-run-stderr.txt
EOF
fi

write_summary_json() {
  ruby -rjson -e '
    manifest_path, generated_at, viftyctl, audit_limit, schema_id = ARGV
    checks = File.readlines(manifest_path, chomp: true).drop(1).map do |line|
      name, status, stdout, stderr = line.split("\t", 4)
      {
        "name" => name,
        "status" => status.to_i,
        "stdout" => stdout,
        "stderr" => stderr,
        "statusFile" => "#{name}.status"
      }
    end
    puts JSON.pretty_generate({
      "schemaVersion" => 1,
      "schemaID" => schema_id,
      "generatedAtUTC" => generated_at,
      "readOnly" => true,
      "coolingCommandsRun" => false,
      "viftyctl" => viftyctl,
      "auditLimit" => audit_limit.to_i,
      "commands" => checks
    })
  ' "${MANIFEST_PATH}" "${GENERATED_AT_UTC}" "${VIFTYCTL}" "${AUDIT_LIMIT}" "${AGENT_COOLING_EVIDENCE_SUMMARY_SCHEMA_ID}" > "${SUMMARY_JSON_PATH}"
}

capture_privacy_review() {
  local name="privacy-review"
  local stdout_name="privacy-review.tsv"
  local stdout_path="${OUTPUT_DIR}/${stdout_name}"
  local stderr_name="${name}.stderr"
  local stderr_path="${OUTPUT_DIR}/${stderr_name}"
  local status_path="${OUTPUT_DIR}/${name}.status"
  local host_name=""
  local short_host_name=""
  local status

  host_name="$(/bin/hostname 2>/dev/null || true)"
  short_host_name="$(/bin/hostname -s 2>/dev/null || true)"

  set +e
  ruby -e '
    bundle, home_path, host_name, short_host_name = ARGV
    ignored = {
      "privacy-review.tsv" => true,
      "privacy-review.stderr" => true,
      "privacy-review.status" => true,
      "checksums.tsv" => true
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

# Write a provisional summary so privacy review also scans generated summary JSON.
write_summary_json
capture_privacy_review
write_summary_json

printf 'sha256\tbytes\tfile\n' > "${CHECKSUM_PATH}"
while IFS= read -r -d '' file_path; do
  relative_path="${file_path#"${OUTPUT_DIR}/"}"
  if [[ "${relative_path}" == "checksums.tsv" ]]; then
    continue
  fi
  sha="$(shasum -a 256 "${file_path}" | awk '{ print $1 }')"
  bytes="$(wc -c < "${file_path}" | tr -d '[:space:]')"
  printf '%s\t%s\t%s\n' "${sha}" "${bytes}" "${relative_path}" >> "${CHECKSUM_PATH}"
done < <(find "${OUTPUT_DIR}" -type f -print0)

echo "Agent cooling evidence written to ${OUTPUT_DIR}"
