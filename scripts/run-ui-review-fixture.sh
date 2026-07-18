#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

mode=""
manifest_path="${REPO_ROOT}/docs/ui-review/evidence-manifest.local.json"
evidence_dir="${REPO_ROOT}/.build/ui-review-evidence"
products_root="${REPO_ROOT}/.build/ui-review-products"
release_binary="${products_root}/release/Vifty"
debug_executable="${products_root}/debug/Vifty.app/Contents/MacOS/Vifty"
collector_executable="${products_root}/debug/ViftyAXCollector"
manifest_supplied=0
evidence_dir_supplied=0
release_binary_supplied=0
debug_executable_supplied=0
collector_executable_supplied=0

usage() {
  echo "Usage:" >&2
  echo "  scripts/run-ui-review-fixture.sh --capture --row-kind <fixture|visual|accessibility> --row-id <id> --manifest <json> --evidence-dir <dir> --debug-executable <path> [--timeout-seconds <seconds>] [--fixture-hold-seconds <seconds>]" >&2
  echo "  scripts/run-ui-review-fixture.sh --collect-ax --capture-id <id> --manifest <json> --evidence-dir <dir> --debug-executable <path> --collector-executable <path> [bounded collector options]" >&2
  echo "  scripts/run-ui-review-fixture.sh --seal --capture-id <id> --manifest <json> --evidence-dir <dir> --debug-executable <path> [--collector-executable <path>]" >&2
  echo "  scripts/run-ui-review-fixture.sh --verify-request-ledger-contract --manifest <json> --evidence-dir <dir> --release-binary <path> --debug-executable <path> --collector-executable <path>" >&2
  echo "  scripts/run-ui-review-fixture.sh --verify-automated --manifest <json> --evidence-dir <dir> --release-binary <path> --debug-executable <path> --collector-executable <path>" >&2
  echo "  scripts/run-ui-review-fixture.sh --verify-matrix --manifest <json> --evidence-dir <dir> --release-binary <path> --debug-executable <path> --collector-executable <path>" >&2
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "${value}" || "${value}" == --* ]]; then
    echo "${option} requires a value." >&2
    exit 64
  fi
}

case "${1:-}" in
  --capture|--collect-ax|--seal)
    orchestration_mode="${1#--}"
    shift
    exec /usr/bin/ruby \
      "${SCRIPT_DIR}/lib/ui_review_orchestrator.rb" \
      "${orchestration_mode}" \
      "$@"
    ;;
esac

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify-request-ledger-contract)
      mode="verify-request-ledger-contract"
      shift
      ;;
    --verify-automated)
      mode="verify-automated"
      shift
      ;;
    --verify-matrix)
      mode="verify-matrix"
      shift
      ;;
    --manifest)
      require_value "$1" "${2:-}"
      manifest_path="$2"
      manifest_supplied=1
      shift 2
      ;;
    --evidence-dir)
      require_value "$1" "${2:-}"
      evidence_dir="$2"
      evidence_dir_supplied=1
      shift 2
      ;;
    --release-binary)
      require_value "$1" "${2:-}"
      release_binary="$2"
      release_binary_supplied=1
      shift 2
      ;;
    --debug-executable)
      require_value "$1" "${2:-}"
      debug_executable="$2"
      debug_executable_supplied=1
      shift 2
      ;;
    --collector-executable)
      require_value "$1" "${2:-}"
      collector_executable="$2"
      collector_executable_supplied=1
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ "${mode}" != "verify-request-ledger-contract" && "${mode}" != "verify-automated" && "${mode}" != "verify-matrix" ]]; then
  usage
  exit 64
fi

if [[ "${manifest_supplied}" -ne 1 || "${evidence_dir_supplied}" -ne 1 || "${release_binary_supplied}" -ne 1 || "${debug_executable_supplied}" -ne 1 || "${collector_executable_supplied}" -ne 1 ]]; then
  echo "${mode} requires explicit --manifest, --evidence-dir, --release-binary, --debug-executable, and --collector-executable paths." >&2
  exit 64
fi

verifier_mode="contract"
if [[ "${mode}" == "verify-automated" ]]; then
  verifier_mode="automated"
elif [[ "${mode}" == "verify-matrix" ]]; then
  verifier_mode="matrix"
fi

exec /usr/bin/ruby \
  "${SCRIPT_DIR}/lib/ui_review_verifier.rb" \
  "${manifest_path}" \
  "${evidence_dir}" \
  "${release_binary}" \
  "${debug_executable}" \
  "${collector_executable}" \
  "${verifier_mode}"
