#!/bin/sh
set -eu

usage() {
  cat >&2 <<'USAGE'
Usage:
  local-model.sh -- <command> [args...]

Example:
  local-model.sh -- ./run-local-model.sh
USAGE
}

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

exec "$script_dir/guarded-run.sh" localModel 30m 75 "local model run" -- "$@"
