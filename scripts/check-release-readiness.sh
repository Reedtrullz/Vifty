#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_METADATA_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
cd "${ROOT_DIR}"

RELEASE_READINESS_SCHEMA_ID="https://vifty.local/schemas/release-readiness.schema.json"
REPO=""
VERSION=""
SECRET_LIST_FILE=""
RELEASE_VIEW_FILE=""
CI_RUN_LIST_FILE=""
RELEASE_RUN_LIST_FILE=""
UNSIGNED_DEV_ARTIFACT_FILE=""
UNSIGNED_DEV_CHECKSUM_FILE=""
SOURCE_SHA=""
REQUIRE_SOURCE_REF=""
RELEASE_MODE="developer-id"
JSON_OUTPUT=false

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-readiness.sh [--mode developer-id|source-first] [--version version] [--repo owner/name] [--source-sha sha] [--require-source-ref ref-or-sha] [--secret-list-file path] [--ci-run-list-file path] [--release-run-list-file path] [--release-view-file path] [--unsigned-dev-artifact-file path] [--unsigned-dev-checksum-file path] [--json]

Runs a read-only release trust preflight. The script validates local release
metadata, verifies source CI for the release tag commit, and inspects GitHub
Release state for the selected release mode.

Developer ID mode is the default and keeps the strict signed/notarized release
checks: required GitHub Actions release secret names, successful Release
workflow, and canonical trusted release assets.

Source-first mode is for releases without Apple Developer Program credentials.
It requires source/tag/CI checks and honest GitHub Release labeling, allows an
optional unsigned-dev tester zip, and rejects canonical trusted binary asset
names.

Options:
  --mode mode                developer-id (default) or source-first.
  --version version          Release version to check. Defaults to Info.plist.
  --repo owner/name          Repository to inspect. Defaults to gh's current repo.
  --source-sha sha           Override the release tag commit SHA, mainly for tests.
  --require-source-ref ref   Block if the release tag commit does not match this
                             ref or commit SHA, such as origin/main.
  --secret-list-file path    Read pre-captured `gh secret list` output for tests.
  --ci-run-list-file path    Read pre-captured `gh run list --json ...` output.
  --release-run-list-file path
                             Read pre-captured Release workflow `gh run list`
                             JSON output for tests.
  --release-view-file path   Read pre-captured `gh release view --json ...` output.
  --unsigned-dev-artifact-file path
                             Verify this local unsigned-dev artifact fixture
                             instead of downloading the GitHub Release asset.
  --unsigned-dev-checksum-file path
                             Verify this local unsigned-dev checksum fixture
                             instead of downloading the GitHub Release asset.
  --json                     Print a machine-readable summary instead of text.
  -h, --help                 Show this help.
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      if [ "$#" -lt 2 ]; then
        echo "error: --version requires a value" >&2
        exit 64
      fi
      VERSION="$2"
      shift 2
      ;;
    --mode)
      if [ "$#" -lt 2 ]; then
        echo "error: --mode requires a value" >&2
        exit 64
      fi
      RELEASE_MODE="$2"
      shift 2
      ;;
    --repo)
      if [ "$#" -lt 2 ]; then
        echo "error: --repo requires a value" >&2
        exit 64
      fi
      REPO="$2"
      shift 2
      ;;
    --source-sha)
      if [ "$#" -lt 2 ]; then
        echo "error: --source-sha requires a value" >&2
        exit 64
      fi
      SOURCE_SHA="$2"
      shift 2
      ;;
    --require-source-ref)
      if [ "$#" -lt 2 ]; then
        echo "error: --require-source-ref requires a value" >&2
        exit 64
      fi
      REQUIRE_SOURCE_REF="$2"
      shift 2
      ;;
    --secret-list-file)
      if [ "$#" -lt 2 ]; then
        echo "error: --secret-list-file requires a value" >&2
        exit 64
      fi
      SECRET_LIST_FILE="$2"
      shift 2
      ;;
    --release-view-file)
      if [ "$#" -lt 2 ]; then
        echo "error: --release-view-file requires a value" >&2
        exit 64
      fi
      RELEASE_VIEW_FILE="$2"
      shift 2
      ;;
    --unsigned-dev-artifact-file)
      if [ "$#" -lt 2 ]; then
        echo "error: --unsigned-dev-artifact-file requires a value" >&2
        exit 64
      fi
      UNSIGNED_DEV_ARTIFACT_FILE="$2"
      shift 2
      ;;
    --unsigned-dev-checksum-file)
      if [ "$#" -lt 2 ]; then
        echo "error: --unsigned-dev-checksum-file requires a value" >&2
        exit 64
      fi
      UNSIGNED_DEV_CHECKSUM_FILE="$2"
      shift 2
      ;;
    --ci-run-list-file)
      if [ "$#" -lt 2 ]; then
        echo "error: --ci-run-list-file requires a value" >&2
        exit 64
      fi
      CI_RUN_LIST_FILE="$2"
      shift 2
      ;;
    --release-run-list-file)
      if [ "$#" -lt 2 ]; then
        echo "error: --release-run-list-file requires a value" >&2
        exit 64
      fi
      RELEASE_RUN_LIST_FILE="$2"
      shift 2
      ;;
    --json)
      JSON_OUTPUT=true
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

if [ -z "${VERSION}" ]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
fi

if [[ ! "${VERSION}" =~ ^[0-9]+([.][0-9]+){1,2}([-.][0-9A-Za-z]+)?$ ]]; then
  echo "error: release version must be a SemVer-like value" >&2
  exit 64
fi

if [ -n "${SOURCE_SHA}" ] && [[ ! "${SOURCE_SHA}" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "error: --source-sha must be a 40-character hexadecimal commit SHA" >&2
  exit 64
fi

case "${RELEASE_MODE}" in
  developer-id|source-first)
    ;;
  *)
    echo "error: --mode must be developer-id or source-first" >&2
    exit 64
    ;;
esac

TAG="v${VERSION}"

check_names=()
check_statuses=()
check_messages=()
blockers=()

add_check() {
  local name="$1"
  local status="$2"
  local message="$3"
  check_names+=("${name}")
  check_statuses+=("${status}")
  check_messages+=("${message}")
  if [ "${status}" != "passed" ]; then
    blockers+=("${name}")
  fi
}

json_string() {
  ruby -rjson -e 'print ARGV.fetch(0).to_json' "$1"
}

emit_json() {
  local status="ready"
  local known_readiness_blockers_clear="true"
  if [ "${#blockers[@]}" -gt 0 ]; then
    status="blocked"
    known_readiness_blockers_clear="false"
  fi

  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "schemaID": %s,\n' "$(json_string "${RELEASE_READINESS_SCHEMA_ID}")"
  printf '  "version": %s,\n' "$(json_string "${VERSION}")"
  printf '  "tag": %s,\n' "$(json_string "${TAG}")"
  printf '  "releaseMode": %s,\n' "$(json_string "${RELEASE_MODE}")"
  printf '  "sourceCommit": %s,\n' "$(json_string "${resolved_source_sha}")"
  printf '  "status": %s,\n' "$(json_string "${status}")"
  printf '  "knownReadinessBlockersClear": %s,\n' "${known_readiness_blockers_clear}"
  printf '  "checks": [\n'
  for index in "${!check_names[@]}"; do
    printf '    {"name": %s, "status": %s, "message": %s}' \
      "$(json_string "${check_names[$index]}")" \
      "$(json_string "${check_statuses[$index]}")" \
      "$(json_string "${check_messages[$index]}")"
    if [ "${index}" -lt "$((${#check_names[@]} - 1))" ]; then
      printf ','
    fi
    printf '\n'
  done
  printf '  ],\n'
  printf '  "blockers": ['
  for index in "${!blockers[@]}"; do
    printf '%s' "$(json_string "${blockers[$index]}")"
    if [ "${index}" -lt "$((${#blockers[@]} - 1))" ]; then
      printf ', '
    fi
  done
  printf ']\n'
  printf '}\n'
}

emit_text() {
  local status="ready"
  if [ "${#blockers[@]}" -gt 0 ]; then
    status="blocked"
  fi

  echo "Release readiness for ${TAG}: ${status}"
  echo "Release mode: ${RELEASE_MODE}"
  for index in "${!check_names[@]}"; do
    printf '[%s] %s - %s\n' "${check_statuses[$index]}" "${check_names[$index]}" "${check_messages[$index]}"
  done

  if [ "${status}" = "blocked" ]; then
    if [ "${RELEASE_MODE}" = "source-first" ]; then
      echo "Do not publish ${TAG} as a source-first release until the blockers are cleared."
    else
      echo "Do not describe ${TAG} as a trusted public binary release until the blockers are cleared."
    fi
  else
    echo "${TAG} has no known release-readiness blockers from this preflight."
  fi
}

verify_unsigned_dev_checksum() {
  local artifact_file="$1"
  local checksum_file="$2"
  local artifact_name="$3"
  local expected_sha=""
  local actual_sha=""

  if [ ! -f "${artifact_file}" ]; then
    echo "unsigned-dev artifact file does not exist: ${artifact_file}"
    return 1
  fi
  if [ ! -f "${checksum_file}" ]; then
    echo "unsigned-dev checksum file does not exist: ${checksum_file}"
    return 1
  fi

  if ! expected_sha="$(ruby -e '
    checksum_file = ARGV.fetch(0)
    expected_name = ARGV.fetch(1)
    text = File.read(checksum_file).strip
    match = text.match(/\A([0-9a-f]{64})(?:[[:space:]]+[* ]?(.+))?\z/)
    unless match
      warn "checksum file must contain a lowercase 64-character SHA-256, optionally followed by #{expected_name}"
      exit 1
    end
    if match[2] && File.basename(match[2]) != expected_name
      warn "checksum file names #{match[2].inspect}, expected #{expected_name}"
      exit 1
    end
    print match[1]
  ' "${checksum_file}" "${artifact_name}" 2>&1)"; then
    echo "${expected_sha}"
    return 1
  fi

  actual_sha="$(shasum -a 256 "${artifact_file}" | awk '{print $1}')"
  if [ "${actual_sha}" != "${expected_sha}" ]; then
    echo "checksum mismatch for ${artifact_name}: expected ${expected_sha}, actual ${actual_sha}"
    return 1
  fi

  echo "checksum verified for ${artifact_name}: ${actual_sha}"
}

if [ "${RELEASE_MODE}" = "source-first" ]; then
  add_check "release-mode" "passed" "Source-first mode: Developer ID signing/notarization is unavailable; source is the recommended v${VERSION} path and any unsigned-dev zip is tester convenience only."
else
  add_check "release-mode" "passed" "Developer ID mode: require signed, notarized, stapled canonical release assets and Apple release credentials."
fi

if metadata_output="$(VIFTY_RELEASE_METADATA_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/validate-release-metadata.sh" --mode "${RELEASE_MODE}" 2>&1)"; then
  if [ "${RELEASE_MODE}" = "source-first" ]; then
    add_check "release-metadata" "passed" "${metadata_output}"
  else
    add_check "release-metadata" "passed" "${metadata_output}"
  fi
else
  add_check "release-metadata" "blocked" "${metadata_output}"
fi

resolved_source_sha=""
if [ -n "${SOURCE_SHA}" ]; then
  resolved_source_sha="${SOURCE_SHA}"
elif command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if resolved_source_sha="$(git rev-parse "${TAG}^{commit}" 2>&1)"; then
    :
  else
    resolved_source_sha=""
  fi
fi

if [[ ! "${resolved_source_sha}" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
  add_check "source-ci" "blocked" "Could not resolve release tag ${TAG} to a commit SHA. Run from a git checkout with the tag fetched or pass --source-sha."
  if [ "${RELEASE_MODE}" = "developer-id" ]; then
    add_check "release-workflow" "blocked" "Could not inspect Release workflow for ${TAG} because the release tag commit SHA is unavailable."
  else
    add_check "release-workflow" "passed" "Source-first mode does not require the Developer ID Release workflow; the notarized workflow remains strict for future developer-id releases."
  fi
else
  if [ -n "${REQUIRE_SOURCE_REF}" ]; then
    required_source_sha=""
    if [[ "${REQUIRE_SOURCE_REF}" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
      required_source_sha="${REQUIRE_SOURCE_REF}"
    elif command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if required_source_sha="$(git rev-parse "${REQUIRE_SOURCE_REF}^{commit}" 2>&1)"; then
        :
      else
        required_source_sha=""
      fi
    fi

    if [[ ! "${required_source_sha}" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
      add_check "release-source-ref" "blocked" "Could not resolve required source ref ${REQUIRE_SOURCE_REF}. Fetch the ref first or pass a commit SHA."
    elif [ "$(printf '%s' "${resolved_source_sha}" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "${required_source_sha}" | tr '[:upper:]' '[:lower:]')" ]; then
      add_check "release-source-ref" "passed" "Release tag ${TAG} matches required source ref ${REQUIRE_SOURCE_REF} (${required_source_sha})."
    else
      add_check "release-source-ref" "blocked" "Release tag ${TAG} points to ${resolved_source_sha}, but required source ref ${REQUIRE_SOURCE_REF} resolves to ${required_source_sha}."
    fi
  fi

  ci_run_json=""
  ci_output=""
  if [ -n "${CI_RUN_LIST_FILE}" ]; then
    if [ ! -f "${CI_RUN_LIST_FILE}" ]; then
      ci_output="CI run list file does not exist: ${CI_RUN_LIST_FILE}"
    else
      ci_run_json="$(cat "${CI_RUN_LIST_FILE}")"
    fi
  elif command -v gh >/dev/null 2>&1; then
    ci_args=(--workflow "CI" --commit "${resolved_source_sha}" --limit 20 --json "headSha,status,conclusion,event,url,workflowName,headBranch")
    if [ -n "${REPO}" ]; then
      ci_args+=(--repo "${REPO}")
    fi
    if ! ci_run_json="$(gh run list "${ci_args[@]}" 2>&1)"; then
      ci_output="${ci_run_json}"
      ci_run_json=""
    fi
  else
    ci_output="gh CLI is required unless --ci-run-list-file is supplied"
  fi

  if [ -z "${ci_run_json}" ]; then
    add_check "source-ci" "blocked" "CI status for ${TAG} (${resolved_source_sha}) is not available: ${ci_output}"
  elif ci_output="$(ruby -rjson -e '
    source_sha = ARGV.fetch(0).downcase
    runs = JSON.parse(STDIN.read)
    runs = [runs] if runs.is_a?(Hash)
    matching = Array(runs).select { |run| run["headSha"].to_s.downcase == source_sha }
    passed = matching.find { |run| run["status"] == "completed" && run["conclusion"] == "success" }
    if passed
      detail = passed["url"].to_s
      detail = "#{passed["workflowName"] || "CI"} on #{passed["headBranch"] || "unknown branch"}" if detail.empty?
      puts "CI passed for #{source_sha}: #{detail}"
    else
      if matching.empty?
        warn "No CI run found for #{source_sha}"
      else
        observed = matching.map do |run|
          "#{run["workflowName"] || "run"} #{run["status"] || "unknown"}/#{run["conclusion"] || "unknown"}"
        end.join(", ")
        warn "No successful completed CI run found for #{source_sha}; observed: #{observed}"
      end
      exit 1
    end
  ' "${resolved_source_sha}" <<< "${ci_run_json}" 2>&1)"; then
    add_check "source-ci" "passed" "${ci_output}"
  else
    add_check "source-ci" "blocked" "${ci_output}"
  fi

  if [ "${RELEASE_MODE}" = "developer-id" ]; then
    release_run_json=""
    release_run_output=""
    if [ -n "${RELEASE_RUN_LIST_FILE}" ]; then
      if [ ! -f "${RELEASE_RUN_LIST_FILE}" ]; then
        release_run_output="Release workflow run list file does not exist: ${RELEASE_RUN_LIST_FILE}"
      else
        release_run_json="$(cat "${RELEASE_RUN_LIST_FILE}")"
      fi
    elif command -v gh >/dev/null 2>&1; then
      release_run_args=(--workflow "Release" --commit "${resolved_source_sha}" --limit 20 --json "headSha,status,conclusion,event,url,workflowName,headBranch,databaseId,createdAt")
      if [ -n "${REPO}" ]; then
        release_run_args+=(--repo "${REPO}")
      fi
      if ! release_run_json="$(gh run list "${release_run_args[@]}" 2>&1)"; then
        release_run_output="${release_run_json}"
        release_run_json=""
      fi
    else
      release_run_output="gh CLI is required unless --release-run-list-file is supplied"
    fi

    if [ -z "${release_run_json}" ]; then
      add_check "release-workflow" "blocked" "Release workflow status for ${TAG} (${resolved_source_sha}) is not available: ${release_run_output}"
    elif release_run_output="$(ruby -rjson -e '
    tag = ARGV.fetch(0)
    source_sha = ARGV.fetch(1).downcase
    runs = JSON.parse(STDIN.read)
    runs = [runs] if runs.is_a?(Hash)
    matching = Array(runs).select do |run|
      run["headSha"].to_s.downcase == source_sha && run["headBranch"].to_s == tag
    end
    latest = matching.first
    if latest && latest["status"] == "completed" && latest["conclusion"] == "success"
      detail = latest["url"].to_s
      detail = "#{latest["workflowName"] || "Release"} run #{latest["databaseId"] || "unknown"}" if detail.empty?
      puts "Release workflow passed for #{tag} (#{source_sha}): #{detail}"
    elsif latest
      observed = "#{latest["workflowName"] || "Release"} #{latest["status"] || "unknown"}/#{latest["conclusion"] || "unknown"}"
      detail = latest["url"].to_s
      detail = " #{detail}" unless detail.empty?
      warn "Latest Release workflow for #{tag} (#{source_sha}) did not pass: #{observed}.#{detail}"
      exit 1
    else
      warn "No Release workflow run found for #{tag} (#{source_sha})"
      exit 1
    end
  ' "${TAG}" "${resolved_source_sha}" <<< "${release_run_json}" 2>&1)"; then
      add_check "release-workflow" "passed" "${release_run_output}"
    else
      add_check "release-workflow" "blocked" "${release_run_output}"
    fi
  else
    add_check "release-workflow" "passed" "Source-first mode does not require a successful Developer ID Release workflow; keep the workflow strict for future notarized releases."
  fi
fi

if [ "${RELEASE_MODE}" = "developer-id" ]; then
  secret_args=()
  if [ -n "${REPO}" ]; then
    secret_args+=(--repo "${REPO}")
  fi
  if [ -n "${SECRET_LIST_FILE}" ]; then
    secret_args+=(--secret-list-file "${SECRET_LIST_FILE}")
  fi

  if secret_output="$(VIFTY_RELEASE_METADATA_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/check-release-secrets.sh" "${secret_args[@]}" 2>&1)"; then
    add_check "release-secrets" "passed" "${secret_output}"
  else
    add_check "release-secrets" "blocked" "${secret_output}"
  fi
else
  add_check "release-secrets" "passed" "Source-first mode does not require Apple Developer Program secrets; developer-id mode still requires them before trusted binary publication."
fi

release_json=""
release_output=""
github_release_check_status="blocked"
if [ -n "${RELEASE_VIEW_FILE}" ]; then
  if [ ! -f "${RELEASE_VIEW_FILE}" ]; then
    release_output="release view file does not exist: ${RELEASE_VIEW_FILE}"
  else
    release_json="$(cat "${RELEASE_VIEW_FILE}")"
  fi
else
  if command -v gh >/dev/null 2>&1; then
    release_args=("${TAG}" --json tagName,isDraft,isPrerelease,assets,body)
    if [ -n "${REPO}" ]; then
      release_args+=(--repo "${REPO}")
    fi
    if ! release_json="$(gh release view "${release_args[@]}" 2>&1)"; then
      release_output="${release_json}"
      release_json=""
    fi
  else
    release_output="gh CLI is required unless --release-view-file is supplied"
  fi
fi

if [ -z "${release_json}" ]; then
  add_check "github-release" "blocked" "GitHub Release ${TAG} is not available: ${release_output}"
else
  if release_output="$(ruby -rjson -e '
    version = ARGV.fetch(0)
    mode = ARGV.fetch(1)
    source_sha = ARGV.fetch(2)
    tag = "v#{version}"
    data = JSON.parse(STDIN.read)
    assets = Array(data["assets"]).map { |asset| asset["name"].to_s }
    problems = []
    problems << "tagName #{data["tagName"].inspect} does not match #{tag}" if data["tagName"] != tag
    problems << "release is draft" if data["isDraft"]
    problems << "release is marked prerelease" if data["isPrerelease"]
    if mode == "developer-id"
      required = [
        "Vifty-v#{version}.zip",
        "Vifty-v#{version}.zip.sha256",
        "Vifty-v#{version}-artifact-summary.json",
        "Vifty-v#{version}-release-checklist.md"
      ]
      missing = required - assets
      problems << "missing assets: #{missing.join(", ")}" unless missing.empty?
      if problems.empty?
        puts "GitHub Release #{tag} has required public trust assets: #{required.join(", ")}"
      else
        warn "GitHub Release #{tag} is not trust-complete: #{problems.join("; ")}"
        exit 1
      end
    else
      canonical = [
        "Vifty-v#{version}.zip",
        "Vifty-v#{version}.zip.sha256",
        "Vifty-v#{version}-artifact-summary.json",
        "Vifty-v#{version}-release-checklist.md"
      ]
      forbidden = canonical & assets
      problems << "source-first release must not publish canonical trusted binary assets: #{forbidden.join(", ")}" unless forbidden.empty?

      unsigned_zip = "Vifty-v#{version}-unsigned-dev.zip"
      unsigned_checksum = "#{unsigned_zip}.sha256"
      has_unsigned_zip = assets.include?(unsigned_zip)
      has_unsigned_checksum = assets.include?(unsigned_checksum)
      problems << "#{unsigned_zip} is present without #{unsigned_checksum}" if has_unsigned_zip && !has_unsigned_checksum
      problems << "#{unsigned_checksum} is present without #{unsigned_zip}" if has_unsigned_checksum && !has_unsigned_zip

      body = data["body"].to_s
      [
        "This is a source-first release",
        "does not yet include a Developer ID signed or notarized public binary",
        "For the most trusted path, build from source",
        "Gatekeeper warnings",
        "## Source Provenance",
        source_sha,
        "post-release hardening"
      ].each do |needle|
        problems << "release notes must include #{needle.inspect}" unless body.include?(needle)
      end

      forbidden_claims = [
        ["auto-update is available", "auto-update is available"],
        ["auto updates are available", "auto updates are available"],
        ["automatic updates are available", "automatic updates are available"],
        ["sparkle updates are enabled", "Sparkle updates are enabled"],
        ["sparkle updater is enabled", "Sparkle updater is enabled"],
        ["homebrew cask is updated", "Homebrew cask is updated"],
        ["homebrew is updated for this release", "Homebrew is updated for this release"],
        ["homebrew install is the recommended path", "Homebrew install is the recommended path"],
        ["is the official trusted binary", "official trusted binary"],
        ["official trusted binary is attached", "official trusted binary"],
        ["developer id signed binary is attached", "Developer ID signed binary is attached"],
        ["developer id signed and notarized binary is attached", "Developer ID signed and notarized binary is attached"],
        ["notarized binary is attached", "notarized binary is attached"]
      ]
      body_downcase = body.downcase
      forbidden_claims.each do |needle, claim|
        problems << "source-first release notes must not claim #{claim.inspect}" if body_downcase.include?(needle)
      end

      if problems.empty?
        if has_unsigned_zip
          puts "GitHub Release #{tag} is source-first and has unsigned tester assets: #{unsigned_zip}, #{unsigned_checksum}"
        else
          puts "GitHub Release #{tag} is source-first with no canonical trusted binary assets; unsigned-dev tester assets are optional."
        end
      else
        warn "GitHub Release #{tag} is not a valid source-first release: #{problems.join("; ")}"
        exit 1
      end
    end
  ' "${VERSION}" "${RELEASE_MODE}" "${resolved_source_sha}" <<< "${release_json}" 2>&1)"; then
    add_check "github-release" "passed" "${release_output}"
    github_release_check_status="passed"
  else
    add_check "github-release" "blocked" "${release_output}"
    github_release_check_status="blocked"
  fi
fi

if [ "${RELEASE_MODE}" = "source-first" ]; then
  unsigned_zip="Vifty-v${VERSION}-unsigned-dev.zip"
  unsigned_checksum="${unsigned_zip}.sha256"

  if [ -z "${release_json}" ]; then
    add_check "source-first-unsigned-dev-assets" "passed" "Unsigned-dev checksum verification skipped because GitHub Release metadata is unavailable; github-release check blocks readiness."
  else
    asset_probe=""
    if asset_probe="$(ruby -rjson -e '
      version = ARGV.fetch(0)
      data = JSON.parse(STDIN.read)
      assets = Array(data["assets"]).map { |asset| asset["name"].to_s }
      unsigned_zip = "Vifty-v#{version}-unsigned-dev.zip"
      unsigned_checksum = "#{unsigned_zip}.sha256"
      puts [
        assets.include?(unsigned_zip) ? "true" : "false",
        assets.include?(unsigned_checksum) ? "true" : "false"
      ].join("\t")
    ' "${VERSION}" <<< "${release_json}" 2>&1)"; then
      IFS=$'\t' read -r has_unsigned_zip has_unsigned_checksum <<< "${asset_probe}"

      if [ "${has_unsigned_zip}" != "true" ] && [ "${has_unsigned_checksum}" != "true" ]; then
        add_check "source-first-unsigned-dev-assets" "passed" "No unsigned-dev tester assets published; checksum verification is optional for source-first releases."
      elif [ "${has_unsigned_zip}" != "true" ] || [ "${has_unsigned_checksum}" != "true" ]; then
        add_check "source-first-unsigned-dev-assets" "passed" "Unsigned-dev checksum verification skipped because the unsigned-dev asset pair is incomplete; github-release check blocks readiness."
      elif [ "${github_release_check_status}" != "passed" ]; then
        add_check "source-first-unsigned-dev-assets" "passed" "Unsigned-dev checksum verification skipped because github-release check blocks readiness."
      else
        artifact_file="${UNSIGNED_DEV_ARTIFACT_FILE}"
        checksum_file="${UNSIGNED_DEV_CHECKSUM_FILE}"
        cleanup_unsigned_dev_dir=""

        if [ -n "${artifact_file}" ] || [ -n "${checksum_file}" ]; then
          if [ -z "${artifact_file}" ] || [ -z "${checksum_file}" ]; then
            add_check "source-first-unsigned-dev-assets" "blocked" "Both --unsigned-dev-artifact-file and --unsigned-dev-checksum-file are required when verifying local unsigned-dev fixtures."
          else
            if verify_output="$(verify_unsigned_dev_checksum "${artifact_file}" "${checksum_file}" "${unsigned_zip}" 2>&1)"; then
              add_check "source-first-unsigned-dev-assets" "passed" "Unsigned-dev tester asset ${verify_output}"
            else
              add_check "source-first-unsigned-dev-assets" "blocked" "Unsigned-dev tester asset ${verify_output}"
            fi
          fi
        elif command -v gh >/dev/null 2>&1; then
          cleanup_unsigned_dev_dir="$(mktemp -d)"
          download_args=("${TAG}" --pattern "${unsigned_zip}" --pattern "${unsigned_checksum}" --dir "${cleanup_unsigned_dev_dir}" --clobber)
          if [ -n "${REPO}" ]; then
            download_args+=(--repo "${REPO}")
          fi

          if download_output="$(gh release download "${download_args[@]}" 2>&1)"; then
            artifact_file="${cleanup_unsigned_dev_dir}/${unsigned_zip}"
            checksum_file="${cleanup_unsigned_dev_dir}/${unsigned_checksum}"
            if verify_output="$(verify_unsigned_dev_checksum "${artifact_file}" "${checksum_file}" "${unsigned_zip}" 2>&1)"; then
              add_check "source-first-unsigned-dev-assets" "passed" "Unsigned-dev tester asset ${verify_output}"
            else
              add_check "source-first-unsigned-dev-assets" "blocked" "Unsigned-dev tester asset ${verify_output}"
            fi
          else
            add_check "source-first-unsigned-dev-assets" "blocked" "Could not download unsigned-dev tester assets from GitHub Release ${TAG}: ${download_output}"
          fi
          rm -rf "${cleanup_unsigned_dev_dir}"
        else
          add_check "source-first-unsigned-dev-assets" "blocked" "gh CLI is required to download and verify unsigned-dev tester assets unless local fixture files are supplied."
        fi
      fi
    else
      add_check "source-first-unsigned-dev-assets" "passed" "Unsigned-dev checksum verification skipped because release asset metadata could not be parsed; github-release check blocks readiness: ${asset_probe}"
    fi
  fi
fi

if "${JSON_OUTPUT}"; then
  emit_json
else
  emit_text
fi

if [ "${#blockers[@]}" -gt 0 ]; then
  exit 1
fi
