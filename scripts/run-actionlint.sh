#!/usr/bin/env bash
set -euo pipefail

# Pinned release from https://github.com/rhysd/actionlint/releases/tag/v1.7.12.
# The archive digest is copied from the release's published checksums asset.
ACTIONLINT_VERSION="1.7.12"
ACTIONLINT_DARWIN_ARM64_SHA256="aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f"
ACTIONLINT_URL="https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_darwin_arm64.tar.gz"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "error: pinned actionlint runner supports only Darwin arm64" >&2
  exit 69
fi

ROOT_DIR="${VIFTY_ACTIONLINT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/vifty-actionlint.XXXXXX")"
trap 'rm -rf "${scratch}"' EXIT

archive="${scratch}/actionlint.tar.gz"
/usr/bin/curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 "${ACTIONLINT_URL}" -o "${archive}"
actual_sha="$(/usr/bin/shasum -a 256 "${archive}" | awk '{print $1}')"
if [[ "${actual_sha}" != "${ACTIONLINT_DARWIN_ARM64_SHA256}" ]]; then
  echo "error: actionlint archive checksum ${actual_sha} does not match pinned ${ACTIONLINT_DARWIN_ARM64_SHA256}" >&2
  exit 65
fi

/usr/bin/tar -xzf "${archive}" -C "${scratch}" actionlint
chmod 755 "${scratch}/actionlint"

mapfile_supported=0
if help mapfile >/dev/null 2>&1; then
  mapfile_supported=1
fi
workflow_list="${scratch}/workflows.txt"
find "${ROOT_DIR}/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print | LC_ALL=C sort > "${workflow_list}"
if [[ ! -s "${workflow_list}" ]]; then
  echo "error: no workflow YAML files found" >&2
  exit 66
fi

if [[ "${mapfile_supported}" == "1" ]]; then
  mapfile -t workflows < "${workflow_list}"
else
  workflows=()
  while IFS= read -r workflow; do
    workflows+=("${workflow}")
  done < "${workflow_list}"
fi

"${scratch}/actionlint" "${workflows[@]}"
