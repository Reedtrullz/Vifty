#!/bin/sh
set -eu

usage() {
  cat >&2 <<'USAGE'
Usage:
  custom-workload.sh <duration> <max-rpm-percent> <reason> -- <command> [args...]

Example:
  custom-workload.sh 15m 65 "project smoke test" -- ./scripts/smoke-test.sh
USAGE
}

if [ "$#" -lt 5 ]; then
  usage
  exit 64
fi

duration="$1"
max_rpm_percent="$2"
reason="$3"
shift 3

if [ "${1:-}" != "--" ]; then
  usage
  exit 64
fi
shift

if [ "$#" -eq 0 ]; then
  usage
  exit 64
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

exec "$script_dir/guarded-run.sh" custom "$duration" "$max_rpm_percent" "$reason" -- "$@"
