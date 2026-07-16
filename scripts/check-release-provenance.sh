#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_PROVENANCE_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
TAG=""
REPO="Reedtrullz/Vifty"
MAIN_REF="origin/main"
TRUSTED_WORKFLOW_REF=""
MANIFEST_PATH="${ROOT_DIR}/.github/release-manifest.json"
ALLOWED_SIGNERS_PATH="${ROOT_DIR}/.github/release-signers.allowed"
CI_RUNS_FILE=""
REMOTE_REFS_FILE=""
SKIP_SIGNATURE_FOR_FIXTURE=0
JSON_OUTPUT=0

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-provenance.sh --tag <signed-tag> [options]

Options:
  --repo <owner/repo>          GitHub repository (default: Reedtrullz/Vifty).
  --main-ref <ref>             Fetched intended main ref (default: origin/main).
  --trusted-workflow-ref <ref> Require the checker worktree itself to remain at
                               this trusted workflow ref instead of the tag.
  --manifest <path>            Release manifest path.
  --allowed-signers <path>     Public SSH allowed-signers file.
  --ci-runs-file <path>        Test/offline gh run-list JSON fixture.
  --remote-refs-file <path>    Test/offline remote tag JSON fixture.
  --skip-signature-for-fixture Test-only; requires both fixture files.
  --json                       Emit a machine-readable summary.

The live path is read-only against GitHub. It verifies an annotated SSH-signed
tag against the checked-in public signer, exact remote tag object/commit parity,
ancestry from the supplied main ref, successful CI at the exact commit, and manifest +
Info.plist version/build agreement. It does not infer environment protection.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --main-ref)
      MAIN_REF="${2:-}"
      shift 2
      ;;
    --trusted-workflow-ref)
      TRUSTED_WORKFLOW_REF="${2:-}"
      shift 2
      ;;
    --manifest)
      MANIFEST_PATH="${2:-}"
      shift 2
      ;;
    --allowed-signers)
      ALLOWED_SIGNERS_PATH="${2:-}"
      shift 2
      ;;
    --ci-runs-file)
      CI_RUNS_FILE="${2:-}"
      shift 2
      ;;
    --remote-refs-file)
      REMOTE_REFS_FILE="${2:-}"
      shift 2
      ;;
    --skip-signature-for-fixture)
      SKIP_SIGNATURE_FOR_FIXTURE=1
      shift
      ;;
    --json)
      JSON_OUTPUT=1
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

if [[ ! "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: --tag must be v<major>.<minor>.<patch>" >&2
  exit 64
fi
if [[ ! -f "${MANIFEST_PATH}" || ! -f "${ALLOWED_SIGNERS_PATH}" ]]; then
  echo "error: manifest and allowed-signers files are required" >&2
  exit 66
fi
if [[ "${SKIP_SIGNATURE_FOR_FIXTURE}" == "1" && ( -z "${CI_RUNS_FILE}" || -z "${REMOTE_REFS_FILE}" ) ]]; then
  echo "error: signature skipping is test-only and requires both fixture files" >&2
  exit 64
fi

cd "${ROOT_DIR}"
VERSION="${TAG#v}"
VIFTY_RELEASE_MANIFEST_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/check-release-manifest.sh" --publication-version "${VERSION}" >/dev/null

TAG_COMMIT="$(git rev-parse "${TAG}^{commit}" 2>/dev/null || true)"
TAG_OBJECT="$(git rev-parse "${TAG}^{tag}" 2>/dev/null || true)"
if [[ ! "${TAG_COMMIT}" =~ ^[0-9a-f]{40}$ || ! "${TAG_OBJECT}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: ${TAG} must be a local annotated tag" >&2
  exit 65
fi
CHECKOUT_COMMIT="$(git rev-parse "HEAD^{commit}" 2>/dev/null || true)"
if [[ -n "${TRUSTED_WORKFLOW_REF}" ]]; then
  TRUSTED_WORKFLOW_COMMIT="$(git rev-parse "${TRUSTED_WORKFLOW_REF}^{commit}" 2>/dev/null || true)"
  if [[ ! "${TRUSTED_WORKFLOW_COMMIT}" =~ ^[0-9a-f]{40}$ || "${CHECKOUT_COMMIT}" != "${TRUSTED_WORKFLOW_COMMIT}" ]]; then
    echo "error: checker worktree ${CHECKOUT_COMMIT:-missing} does not match trusted workflow ref ${TRUSTED_WORKFLOW_REF}" >&2
    exit 65
  fi
elif [[ "${CHECKOUT_COMMIT}" != "${TAG_COMMIT}" ]]; then
  echo "error: checked-out commit ${CHECKOUT_COMMIT:-missing} does not match ${TAG} commit ${TAG_COMMIT}" >&2
  exit 65
fi

if [[ "${SKIP_SIGNATURE_FOR_FIXTURE}" != "1" ]]; then
  if ! git -c gpg.format=ssh -c gpg.ssh.allowedSignersFile="${ALLOWED_SIGNERS_PATH}" verify-tag "${TAG}" >/dev/null; then
    echo "error: ${TAG} did not verify against ${ALLOWED_SIGNERS_PATH}" >&2
    exit 65
  fi
fi

if [[ -n "${REMOTE_REFS_FILE}" ]]; then
  remote_facts="$(ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    puts [data.fetch("tagObjectSHA"), data.fetch("tagCommitSHA")].join("\t")
  ' "${REMOTE_REFS_FILE}")"
  IFS=$'\t' read -r REMOTE_TAG_OBJECT REMOTE_TAG_COMMIT <<< "${remote_facts}"
else
  remote_lines="$(git ls-remote --tags origin "refs/tags/${TAG}" "refs/tags/${TAG}^{}")"
  REMOTE_TAG_OBJECT="$(printf '%s\n' "${remote_lines}" | awk -v ref="refs/tags/${TAG}" '$2 == ref {print $1; exit}')"
  REMOTE_TAG_COMMIT="$(printf '%s\n' "${remote_lines}" | awk -v ref="refs/tags/${TAG}^{}" '$2 == ref {print $1; exit}')"
fi
if [[ "${REMOTE_TAG_OBJECT}" != "${TAG_OBJECT}" || "${REMOTE_TAG_COMMIT}" != "${TAG_COMMIT}" ]]; then
  echo "error: remote ${TAG} object/commit does not match local signed tag" >&2
  exit 65
fi

if ! git rev-parse --verify "${MAIN_REF}^{commit}" >/dev/null 2>&1; then
  echo "error: main ref ${MAIN_REF} is unavailable; fetch the intended main ref before checking provenance" >&2
  exit 66
fi
if ! git merge-base --is-ancestor "${TAG_COMMIT}" "${MAIN_REF}"; then
  echo "error: tag commit ${TAG_COMMIT} is not an ancestor of ${MAIN_REF}" >&2
  exit 65
fi

if [[ -n "${CI_RUNS_FILE}" ]]; then
  CI_RUNS_JSON="$(<"${CI_RUNS_FILE}")"
else
  CI_RUNS_JSON="$(gh run list --repo "${REPO}" --workflow CI --limit 100 --json databaseId,headBranch,headSha,status,conclusion,event,url)"
fi
CI_RUN_FACTS="$(ruby -rjson -e '
  runs = JSON.parse(STDIN.read)
  sha = ARGV.fetch(0)
  run = runs.find do |item|
    item["headSha"] == sha &&
      item["headBranch"] == "main" &&
      item["event"] == "push" &&
      item["status"] == "completed" &&
      item["conclusion"] == "success"
  end
  abort("no successful completed push CI run on main for exact commit #{sha}") unless run
  print [run.fetch("databaseId"), run.fetch("headBranch"), run.fetch("event")].join("\t")
' "${TAG_COMMIT}" <<< "${CI_RUNS_JSON}" 2>/dev/null || true)"
if [[ -z "${CI_RUN_FACTS}" ]]; then
  echo "error: no successful completed push CI run on main for exact commit ${TAG_COMMIT}" >&2
  exit 65
fi
IFS=$'\t' read -r CI_RUN_ID CI_HEAD_BRANCH CI_EVENT <<< "${CI_RUN_FACTS}"

manifest_facts="$(ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  candidate = data["candidate"] or abort("candidate is null")
  puts [candidate.fetch("version"), candidate.fetch("build")].join("\t")
' "${MANIFEST_PATH}")"
IFS=$'\t' read -r MANIFEST_VERSION MANIFEST_BUILD <<< "${manifest_facts}"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
PLIST_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"
if [[ "${VERSION}" != "${MANIFEST_VERSION}" || "${VERSION}" != "${PLIST_VERSION}" || "${MANIFEST_BUILD}" != "${PLIST_BUILD}" ]]; then
  echo "error: tag, manifest candidate, and Info.plist version/build do not agree" >&2
  exit 65
fi

if [[ "${JSON_OUTPUT}" == "1" ]]; then
  ruby -rjson -e '
    puts JSON.pretty_generate({
      "schemaVersion" => 1,
      "status" => "passed",
      "tag" => ARGV.fetch(0),
      "tagObjectSHA" => ARGV.fetch(1),
      "tagCommitSHA" => ARGV.fetch(2),
      "checkoutCommitSHA" => ARGV.fetch(3),
      "mainRef" => ARGV.fetch(4),
      "sourceCIRunID" => ARGV.fetch(5).to_i,
      "sourceCIHeadBranch" => ARGV.fetch(6),
      "sourceCIEvent" => ARGV.fetch(7),
      "version" => ARGV.fetch(8),
      "build" => ARGV.fetch(9).to_i,
      "signatureVerified" => ARGV.fetch(10) == "true",
      "readOnly" => true
    })
  ' "${TAG}" "${TAG_OBJECT}" "${TAG_COMMIT}" "${CHECKOUT_COMMIT}" "${MAIN_REF}" "${CI_RUN_ID}" "${CI_HEAD_BRANCH}" "${CI_EVENT}" "${VERSION}" "${MANIFEST_BUILD}" "$([[ "${SKIP_SIGNATURE_FOR_FIXTURE}" == "1" ]] && echo false || echo true)"
else
  echo "Release provenance OK: ${TAG} ${TAG_COMMIT}, CI run ${CI_RUN_ID}, build ${MANIFEST_BUILD}"
fi
