#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JSON=false

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-community-standards.sh [--root path] [--json]

Checks Vifty's GitHub community and support surface for required files and
safety-critical support text. This is a local trust gate; it does not contact
GitHub.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      if [ "$#" -lt 2 ]; then
        echo "error: --root requires a value" >&2
        exit 64
      fi
      ROOT_DIR="$2"
      shift 2
      ;;
    --json)
      JSON=true
      shift
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

CHECKS_FILE="$(mktemp "${TMPDIR:-/tmp}/vifty-community-checks.XXXXXX")"
trap 'rm -f "${CHECKS_FILE}"' EXIT

add_check() {
  local name="$1"
  local status="$2"
  local message="$3"
  printf '%s\t%s\t%s\n' "${name}" "${status}" "${message}" >> "${CHECKS_FILE}"
}

required_files=(
  "README.md"
  "LICENSE"
  "CODE_OF_CONDUCT.md"
  "CONTRIBUTING.md"
  "SECURITY.md"
  "SUPPORT.md"
  ".github/CODEOWNERS"
  ".github/PULL_REQUEST_TEMPLATE.md"
  ".github/ISSUE_TEMPLATE/config.yml"
  ".github/ISSUE_TEMPLATE/bug-report.yml"
  ".github/ISSUE_TEMPLATE/feature-request.yml"
  ".github/ISSUE_TEMPLATE/agent-cooling.yml"
  ".github/ISSUE_TEMPLATE/hardware-validation.yml"
  ".github/ISSUE_TEMPLATE/release-trust.yml"
)

for relative_path in "${required_files[@]}"; do
  if [ -f "${ROOT_DIR}/${relative_path}" ]; then
    add_check "file:${relative_path}" "passed" "${relative_path} is present."
  else
    add_check "file:${relative_path}" "blocked" "${relative_path} is missing."
  fi
done

check_contains() {
  local name="$1"
  local relative_path="$2"
  local token="$3"
  local message="$4"

  if [ ! -f "${ROOT_DIR}/${relative_path}" ]; then
    add_check "${name}" "blocked" "${relative_path} is missing; cannot verify ${message}."
    return
  fi

  if grep -Fq "${token}" "${ROOT_DIR}/${relative_path}"; then
    add_check "${name}" "passed" "${message}"
  else
    add_check "${name}" "blocked" "${relative_path} must include token: ${token}"
  fi
}

check_contains "readme-support-link" "README.md" "[SUPPORT.md](SUPPORT.md)" "README links the standard support entrypoint."
check_contains "contributing-support-link" "CONTRIBUTING.md" "[SUPPORT.md](SUPPORT.md)" "Contributing guide routes questions through support."

check_contains "support-security" "SUPPORT.md" "[SECURITY.md](SECURITY.md)" "Support routes vulnerabilities to the security policy."
check_contains "support-triage" "SUPPORT.md" "[docs/support-triage.md](docs/support-triage.md)" "Support links maintainer triage."
check_contains "support-readiness" "SUPPORT.md" "viftyctl diagnose --json" "Support starts with read-only readiness evidence."
check_contains "support-audit" "SUPPORT.md" "viftyctl audit --limit 20 --json" "Support includes read-only audit evidence."
check_contains "support-agent-evidence-collector" "SUPPORT.md" "scripts/collect-agent-cooling-evidence.sh" "Support links the read-only agent/helper evidence collector."
check_contains "support-agent-launchd-evidence" "SUPPORT.md" "read-only launchd/helper install files" "Support explains helper evidence includes launchd/install files."
check_contains "support-agent-privacy-review" "SUPPORT.md" "redaction-needed" "Support tells reporters how to handle flagged agent evidence bundles."
check_contains "support-source-first" "SUPPORT.md" "source-first" "Support preserves current source-first release language."
check_contains "support-unsigned" "SUPPORT.md" 'unsigned `.app` zip is tester convenience only' "Support distinguishes unsigned tester artifacts."
check_contains "support-no-raw-smc" "SUPPORT.md" "raw SMC tools" "Support forbids raw SMC tools in unsafe states."
check_contains "support-no-setfixed" "SUPPORT.md" "sudo ViftyHelper setFixed" "Support forbids manual helper writes in unsafe states."
check_contains "support-blocked-state" "SUPPORT.md" 'state: "blocked"' "Support treats blocked readiness as a stop signal."
check_contains "support-safe-to-request" "SUPPORT.md" "safeToRequestCooling: false" "Support treats unsafe cooling decisions as stop signals."
check_contains "support-daemon-control-path" "SUPPORT.md" "daemonControlPathReady: false" "Support treats unavailable daemon control paths as stop signals."
check_contains "support-unsupported-readonly" "SUPPORT.md" "read-only evidence only" "Support keeps unsupported hardware on read-only evidence."

check_contains "security-advisories" "SECURITY.md" "GitHub Security Advisories" "Security policy uses private vulnerability reporting."
check_contains "security-trust-model" "SECURITY.md" "[docs/trust-model.md](docs/trust-model.md)" "Security policy links the trust model."
check_contains "security-release-status" "SECURITY.md" "[docs/release-status.md](docs/release-status.md)" "Security policy links release trust status."

check_contains "pr-safety-impact" ".github/PULL_REQUEST_TEMPLATE.md" "## Safety Impact" "PR template requires safety impact."
check_contains "pr-make-verify" ".github/PULL_REQUEST_TEMPLATE.md" "make verify" "PR template asks for the local trust gate."
check_contains "pr-agent-gates" ".github/PULL_REQUEST_TEMPLATE.md" "safeToRequestCooling" "PR template protects agent cooling gates."
check_contains "pr-agent-daemon-control-path" ".github/PULL_REQUEST_TEMPLATE.md" "daemonControlPathReady" "PR template protects daemon control readiness gates."

check_contains "bug-readonly" ".github/ISSUE_TEMPLATE/bug-report.yml" "read-only diagnostics" "Bug report template starts fan reports with read-only diagnostics."
check_contains "bug-no-raw-smc" ".github/ISSUE_TEMPLATE/bug-report.yml" "do not run manual fan-write commands or raw SMC tools" "Bug report template blocks unsafe fan-write evidence."
check_contains "agent-template-no-retry" ".github/ISSUE_TEMPLATE/agent-cooling.yml" 'do not retry `viftyctl prepare` or `viftyctl run`' "Agent-cooling template blocks retries while readiness is unsafe."
check_contains "agent-template-audit" ".github/ISSUE_TEMPLATE/agent-cooling.yml" "viftyctl audit --limit 20 --json" "Agent-cooling template asks for read-only audit evidence."
check_contains "agent-template-evidence-collector" ".github/ISSUE_TEMPLATE/agent-cooling.yml" "scripts/collect-agent-cooling-evidence.sh" "Agent-cooling template points reporters to the read-only evidence collector."
check_contains "agent-template-launchd-evidence" ".github/ISSUE_TEMPLATE/agent-cooling.yml" "read-only launchd/helper install evidence" "Agent-cooling template asks for read-only launchd/helper evidence."
check_contains "agent-template-privacy-review" ".github/ISSUE_TEMPLATE/agent-cooling.yml" "privacy-review.tsv" "Agent-cooling template asks reporters to check privacy review before public sharing."
check_contains "hardware-template-unsupported" ".github/ISSUE_TEMPLATE/hardware-validation.yml" "Unsupported machines should follow docs/unsupported-hardware.md and collect read-only evidence only." "Hardware template keeps unsupported reports read-only."
check_contains "hardware-template-agent-run-smoke" ".github/ISSUE_TEMPLATE/hardware-validation.yml" "Supervised viftyctl run smoke test" "Hardware template collects supervised agent-run smoke evidence."
check_contains "release-template-source-first" ".github/ISSUE_TEMPLATE/release-trust.yml" "source-first unsigned-dev app zips are tester convenience artifacts" "Release trust template distinguishes source-first tester artifacts."

check_contains "codeowners-support" ".github/CODEOWNERS" "SUPPORT.md" "CODEOWNERS covers support policy."
check_contains "codeowners-schemas" ".github/CODEOWNERS" "docs/schemas/" "CODEOWNERS covers agent-facing schemas."
check_contains "codeowners-scripts" ".github/CODEOWNERS" "scripts/" "CODEOWNERS covers release and validation scripts."

blocked_count="$(awk -F '\t' '$2 == "blocked" { count++ } END { print count + 0 }' "${CHECKS_FILE}")"
overall_status="passed"
if [ "${blocked_count}" -gt 0 ]; then
  overall_status="blocked"
fi

if "${JSON}"; then
  ruby -rjson -e '
    checks = File.readlines(ARGV.fetch(0), chomp: true).map do |line|
      name, status, message = line.split("\t", 3)
      { "name" => name, "status" => status, "message" => message }
    end
    status = ARGV.fetch(1)
    puts JSON.pretty_generate({
      "schemaVersion" => 1,
      "status" => status,
      "checks" => checks
    })
  ' "${CHECKS_FILE}" "${overall_status}"
else
  echo "Community standards: ${overall_status}"
  awk -F '\t' '{ printf "[%s] %s - %s\n", $2, $1, $3 }' "${CHECKS_FILE}"
fi

exit "${blocked_count}"
