#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
configuration="${CONFIGURATION:-debug}"
app_path="${VIFTY_APP_PATH:-${repo_root}/.build/Vifty.app}"

cd "${repo_root}"
make app \
  CONFIGURATION="${configuration}" \
  SIGNING_IDENTITY="${SIGNING_IDENTITY:--}" \
  VIFTY_XPC_ALLOWED_TEAM_ID="${VIFTY_XPC_ALLOWED_TEAM_ID:-}"

if [[ ! -d "${app_path}" ]]; then
  echo "error: app bundle was not created at ${app_path}" >&2
  exit 66
fi

open "${app_path}"
