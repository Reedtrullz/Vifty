#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_MANIFEST_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
MANIFEST_PATH="${ROOT_DIR}/.github/release-manifest.json"
SCHEMA_PATH="${ROOT_DIR}/docs/schemas/release-manifest.schema.json"
PUBLICATION_VERSION=""
MANIFEST_ONLY=0
BASE_REF="${VIFTY_RELEASE_MANIFEST_BASE_REF:-}"
REQUIRE_BASE="${VIFTY_REQUIRE_RELEASE_MANIFEST_BASE:-0}"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-manifest.sh [--manifest-only] [--publication-version version]
                                         [--base-ref trusted-git-object] [--require-base]

Validates .github/release-manifest.json against its checked-in JSON Schema and
enforces semantic release invariants. With --publication-version, the manifest
must contain a newer candidate at that exact version and the signed-tag policy
must already apply. Project metadata is checked unless --manifest-only is used.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest-only)
      MANIFEST_ONLY=1
      shift
      ;;
    --publication-version)
      if [[ $# -lt 2 ]]; then
        echo "error: --publication-version requires a value" >&2
        exit 64
      fi
      PUBLICATION_VERSION="$2"
      shift 2
      ;;
    --base-ref)
      if [[ $# -lt 2 ]]; then
        echo "error: --base-ref requires a value" >&2
        exit 64
      fi
      BASE_REF="$2"
      shift 2
      ;;
    --require-base)
      REQUIRE_BASE=1
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

if [[ ! -f "${MANIFEST_PATH}" ]]; then
  echo "error: release manifest not found: ${MANIFEST_PATH}" >&2
  exit 66
fi
if [[ ! -f "${SCHEMA_PATH}" ]]; then
  echo "error: release manifest schema not found: ${SCHEMA_PATH}" >&2
  exit 66
fi

ruby -rjson - "${MANIFEST_PATH}" "${SCHEMA_PATH}" "${PUBLICATION_VERSION}" <<'RUBY'
manifest_path, schema_path, publication_version = ARGV

begin
  manifest = JSON.parse(File.read(manifest_path))
  schema = JSON.parse(File.read(schema_path))
rescue JSON::ParserError => error
  warn "error: invalid release manifest/schema JSON: #{error.message}"
  exit 1
end

unless schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
  warn "error: release manifest schema must use JSON Schema draft 2020-12"
  exit 1
end
unless schema["$id"] == "https://vifty.local/schemas/release-manifest.schema.json"
  warn "error: release manifest schema $id is invalid"
  exit 1
end

def schema_ref(root, reference)
  unless reference.start_with?("#/")
    raise "unsupported non-local schema reference #{reference.inspect}"
  end
  reference.delete_prefix("#/").split("/").reduce(root) do |node, component|
    key = component.gsub("~1", "/").gsub("~0", "~")
    node.fetch(key)
  end
end

def type_matches?(value, expected)
  case expected
  when "object" then value.is_a?(Hash)
  when "array" then value.is_a?(Array)
  when "string" then value.is_a?(String)
  when "integer" then value.is_a?(Integer)
  when "number" then value.is_a?(Numeric)
  when "boolean" then value == true || value == false
  when "null" then value.nil?
  else false
  end
end

def validate_schema(value, node, path, root)
  if node.key?("$ref")
    return validate_schema(value, schema_ref(root, node.fetch("$ref")), path, root)
  end

  if node.key?("oneOf")
    results = node.fetch("oneOf").map { |option| validate_schema(value, option, path, root) }
    matches = results.count(&:empty?)
    return [] if matches == 1
    return ["#{path} must match exactly one schema option (matched #{matches})"]
  end

  errors = []
  expected_types = Array(node["type"]).compact
  unless expected_types.empty? || expected_types.any? { |type| type_matches?(value, type) }
    return ["#{path} must be #{expected_types.join(" or ")}"]
  end

  errors << "#{path} must equal #{node["const"].inspect}" if node.key?("const") && value != node["const"]
  if node.key?("enum") && !node.fetch("enum").include?(value)
    errors << "#{path} must be one of #{node.fetch("enum").map(&:inspect).join(", ")}"
  end
  if value.is_a?(String) && node.key?("pattern") && !Regexp.new(node.fetch("pattern")).match?(value)
    errors << "#{path} must match #{node.fetch("pattern").inspect}"
  end
  if value.is_a?(Numeric) && node.key?("minimum") && value < node.fetch("minimum")
    errors << "#{path} must be >= #{node.fetch("minimum")}"
  end

  if value.is_a?(Array)
    errors << "#{path} must contain at least #{node.fetch("minItems")} items" if node.key?("minItems") && value.length < node.fetch("minItems")
    errors << "#{path} must contain unique items" if node["uniqueItems"] == true && value.uniq.length != value.length
    if node.key?("items")
      value.each_with_index do |item, index|
        errors.concat(validate_schema(item, node.fetch("items"), "#{path}[#{index}]", root))
      end
    end
  end

  if value.is_a?(Hash)
    Array(node["required"]).each do |key|
      errors << "#{path}.#{key} is required" unless value.key?(key)
    end
    properties = node.fetch("properties", {})
    if node["additionalProperties"] == false
      (value.keys - properties.keys).each { |key| errors << "#{path}.#{key} is not allowed" }
    end
    value.each do |key, child|
      next unless properties.key?(key)
      errors.concat(validate_schema(child, properties.fetch(key), "#{path}.#{key}", root))
    end
  end

  errors
end

errors = validate_schema(manifest, schema, "$", schema)

def semver(value)
  match = /\A(\d+)\.(\d+)\.(\d+)\z/.match(value.to_s)
  match && match.captures.map(&:to_i)
end

def release_name_errors(release, label)
  version = release.fetch("version")
  expected = {
    "tag" => "v#{version}",
    "artifact" => "Vifty-v#{version}.zip",
    "checksumAsset" => "Vifty-v#{version}.zip.sha256",
    "artifactSummary" => "Vifty-v#{version}-artifact-summary.json",
    "releaseChecklist" => "Vifty-v#{version}-release-checklist.md"
  }
  expected.each_with_object([]) do |(field, value), errors|
    errors << "#{label}.#{field} #{release[field].inspect} must equal #{value.inspect}" unless release[field] == value
  end
end

def manual_compatibility_errors(release, label)
  status = release["manualCompatibility"]
  scope = release["manualCompatibilityScope"]
  errors = []

  if status == "passed-auto-restored"
    unless scope.is_a?(Hash)
      errors << "#{label}.manualCompatibilityScope is required when manualCompatibility is passed-auto-restored"
      return errors
    end

    models = scope["modelIdentifiers"]
    if !models.is_a?(Array) || models.empty?
      errors << "#{label}.manualCompatibilityScope.modelIdentifiers must contain at least one validated model"
    elsif models.uniq.length != models.length
      errors << "#{label}.manualCompatibilityScope.modelIdentifiers must be unique"
    end
    errors << "#{label}.manualCompatibilityScope.reviewReport is required" if scope["reviewReport"].to_s.empty?
    errors << "#{label}.manualCompatibilityScope.attestation is required" if scope["attestation"].to_s.empty?
  elsif !scope.nil?
    errors << "#{label}.manualCompatibilityScope must be null while manualCompatibility is pending"
  end

  errors
end

history = manifest["historicalReleases"].is_a?(Array) ? manifest["historicalReleases"] : []
published = manifest["publishedRelease"] || {}
candidate = manifest["candidate"]
policy = manifest["releasePolicy"] || {}
published_version = semver(published["version"])
boundary_version = semver(policy["signedTagsRequiredFromVersion"])

history.each_with_index do |release, index|
  errors.concat(release_name_errors(release, "historicalReleases[#{index}]"))
  errors.concat(manual_compatibility_errors(release, "historicalReleases[#{index}]"))
end
errors.concat(release_name_errors(published, "publishedRelease")) unless published.empty?
errors.concat(manual_compatibility_errors(published, "publishedRelease")) unless published.empty?
errors << "releasePolicy.signedTagsRequiredFromVersion must be non-null SemVer" unless boundary_version

published_entries = history + (published.empty? ? [] : [published])
published_entries.each_with_index do |release, index|
  version = semver(release["version"])
  label = index < history.length ? "historicalReleases[#{index}]" : "publishedRelease"
  next unless version && boundary_version
  if release["tagTrust"] == "historical-unsigned" && !((version <=> boundary_version) == -1)
    errors << "historical unsigned #{label} must be older than signedTagsRequiredFromVersion"
  end
  if release["tagTrust"] == "signed-verified" && (version <=> boundary_version) == -1
    errors << "signed-verified #{label} cannot predate signedTagsRequiredFromVersion"
  end
end

history.each_cons(2).with_index do |(older, newer), index|
  older_version = semver(older["version"])
  newer_version = semver(newer["version"])
  versions_increase = older_version && newer_version && (older_version <=> newer_version) == -1
  builds_increase = older["build"].is_a?(Integer) && newer["build"].is_a?(Integer) && older["build"] < newer["build"]
  unless versions_increase && builds_increase
    errors << "historicalReleases must be append-ordered by increasing version and build (entries #{index} and #{index + 1})"
  end
end

unless history.empty?
  history_versions = history.map { |release| semver(release["version"]) }
  unless published_version && history_versions.all? { |version| version && (version <=> published_version) == -1 }
    errors << "publishedRelease version #{published["version"]} must be newer than every historical release"
  end
  history_builds = history.map { |release| release["build"] }
  unless published["build"].is_a?(Integer) && history_builds.all? { |build| build.is_a?(Integer) && build < published["build"] }
    errors << "publishedRelease build #{published["build"]} must be greater than every historical release build"
  end
end

if candidate
  errors.concat(release_name_errors(candidate, "candidate"))
  errors.concat(manual_compatibility_errors(candidate, "candidate"))
  candidate_version = semver(candidate["version"])
  if published_version && candidate_version && !((candidate_version <=> published_version) == 1)
    errors << "candidate version #{candidate["version"]} must be newer than published version #{published["version"]}"
  end
  if candidate["build"].is_a?(Integer) && published["build"].is_a?(Integer) && candidate["build"] <= published["build"]
    errors << "candidate build #{candidate["build"]} must be greater than published build #{published["build"]}"
  end
  if candidate_version && boundary_version && (candidate_version <=> boundary_version) == -1
    errors << "candidate version #{candidate["version"]} must be covered by signedTagsRequiredFromVersion #{policy["signedTagsRequiredFromVersion"]}"
  end
end

all_releases = published_entries + (candidate ? [candidate] : [])
versions = all_releases.map { |release| release["version"] }
tags = all_releases.map { |release| release["tag"] }
errors << "release versions must be unique across history, publishedRelease, and candidate" unless versions.compact.uniq.length == versions.compact.length
errors << "release tags must be unique across history, publishedRelease, and candidate" unless tags.compact.uniq.length == tags.compact.length

unless publication_version.empty?
  unless candidate
    errors << "publication version #{publication_version} requires a non-null candidate"
  else
    errors << "publication version #{publication_version} does not match candidate #{candidate["version"]}" unless candidate["version"] == publication_version
    errors << "publication candidate must require a signed tag" unless candidate["tagTrust"] == "signed-required"
  end
end

unless errors.empty?
  errors.each { |error| warn "error: #{error}" }
  exit 1
end
RUBY

if [[ -n "${BASE_REF}" ]]; then
  VIFTY_RELEASE_MANIFEST_ROOT="${ROOT_DIR}" \
    VIFTY_RELEASE_SOURCE_REPOSITORY_ROOT="${VIFTY_RELEASE_SOURCE_REPOSITORY_ROOT:-${ROOT_DIR}}" \
    "${SCRIPT_DIR}/check-release-manifest-history-from-git.sh" --base-ref "${BASE_REF}"
elif [[ "${REQUIRE_BASE}" == "1" ]]; then
  echo "error: trusted release-manifest base ref is required" >&2
  exit 65
fi

if [[ "${MANIFEST_ONLY}" != "1" ]]; then
  INFO_PLIST="${ROOT_DIR}/Resources/Info.plist"
  DAEMON_PLIST="${ROOT_DIR}/Resources/tech.reidar.vifty.daemon.plist"
  CASK_PATH="${ROOT_DIR}/Casks/vifty.rb"
  PACKAGE_PATH="${ROOT_DIR}/Package.swift"

  for required_path in "${INFO_PLIST}" "${DAEMON_PLIST}" "${CASK_PATH}" "${PACKAGE_PATH}"; do
    if [[ ! -f "${required_path}" ]]; then
      echo "error: project release metadata file not found: ${required_path}" >&2
      exit 66
    fi
  done

  facts="$(ruby -rjson -e '
    data = JSON.parse(File.read(ARGV.fetch(0)))
    product = data.fetch("product")
    policy = data.fetch("releasePolicy")
    published = data.fetch("publishedRelease")
    candidate = data["candidate"] || {}
    puts [
      product.fetch("bundleID"), product.fetch("daemonID"), product.fetch("helperID"),
      product.fetch("ctlID"), product.fetch("architectures").join(" "),
      product.fetch("minimumMacOS"), policy.fetch("developerTeamID"),
      published.fetch("version"), published.fetch("build"), published.fetch("artifact"),
      published.fetch("sha256"), candidate["version"], candidate["build"], candidate["sha256"]
    ].map { |value| value.to_s }.join("\t")
  ' "${MANIFEST_PATH}")"
  IFS=$'\t' read -r bundle_id daemon_id helper_id ctl_id architectures minimum_macos team_id published_version published_build published_artifact published_sha candidate_version candidate_build candidate_sha <<< "${facts}"

  plist_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
  plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
  plist_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
  plist_minimum="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${INFO_PLIST}")"
  if [[ "${plist_bundle_id}" != "${bundle_id}" ]]; then
    echo "error: Info.plist CFBundleIdentifier ${plist_bundle_id} does not match manifest ${bundle_id}" >&2
    exit 1
  fi
  if [[ "${plist_minimum}" != "${minimum_macos}" ]]; then
    echo "error: Info.plist minimum macOS ${plist_minimum} does not match manifest ${minimum_macos}" >&2
    exit 1
  fi
  if [[ "${plist_version}" == "${published_version}" ]]; then
    expected_build="${published_build}"
  elif [[ -n "${candidate_version}" && "${plist_version}" == "${candidate_version}" ]]; then
    expected_build="${candidate_build}"
  else
    echo "error: Info.plist version ${plist_version} matches neither published ${published_version} nor candidate ${candidate_version:-null}" >&2
    exit 1
  fi
  if [[ "${plist_build}" != "${expected_build}" ]]; then
    echo "error: Info.plist build ${plist_build} does not match manifest build ${expected_build} for ${plist_version}" >&2
    exit 1
  fi

  daemon_label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "${DAEMON_PLIST}")"
  daemon_mach_service="$(/usr/libexec/PlistBuddy -c "Print :MachServices:${daemon_id}" "${DAEMON_PLIST}" 2>/dev/null || true)"
  if [[ "${daemon_label}" != "${daemon_id}" || "${daemon_mach_service}" != "true" ]]; then
    echo "error: LaunchDaemon Label/MachServices must match manifest daemonID ${daemon_id}" >&2
    exit 1
  fi
  if /usr/bin/plutil -convert json -o - -- "${DAEMON_PLIST}" | ruby -rjson -e '
    data = JSON.parse(STDIN.read)
    keys = Hash(data["EnvironmentVariables"]).keys.grep(/\AVIFTY_XPC_ADHOC_/)
    exit(keys.empty? ? 1 : 0)
  '; then
    echo "error: public release LaunchDaemon metadata must not contain VIFTY_XPC_ADHOC_* keys" >&2
    exit 1
  fi

  cask_version="$(ruby -ne 'puts $1 if /^\s*version "([^"]+)"/' "${CASK_PATH}")"
  cask_sha="$(ruby -ne 'puts $1 if /^\s*sha256 "([^"]+)"/' "${CASK_PATH}")"
  if [[ "${cask_version}" != "${published_version}" ]]; then
    echo "error: cask version ${cask_version} must remain on published manifest release ${published_version}" >&2
    exit 1
  fi
  if [[ ! "${cask_sha}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: cask checksum must be a lowercase 64-character SHA-256 value" >&2
    exit 1
  fi
  if [[ "${cask_sha}" != "${published_sha}" ]]; then
    echo "error: cask checksum must match published manifest checksum ${published_sha} for ${published_version}" >&2
    exit 1
  fi
  if ! grep -Fq "depends_on arch: :arm64" "${CASK_PATH}" || [[ "${architectures}" != "arm64" ]]; then
    echo "error: cask architecture must match manifest arm64-only contract" >&2
    exit 1
  fi
  if ! grep -Fq '.macOS(.v15)' "${PACKAGE_PATH}"; then
    echo "error: Package.swift macOS deployment target must match manifest minimum macOS ${minimum_macos}" >&2
    exit 1
  fi
fi

manifest_status="$(ruby -rjson -e '
  data = JSON.parse(File.read(ARGV.fetch(0)))
  candidate = data["candidate"]
  print "#{data.fetch("historicalReleases").length} historical, " \
    "published v#{data.fetch("publishedRelease").fetch("version")}, " \
    "candidate #{candidate ? "v#{candidate.fetch("version")}" : "null"}"
' "${MANIFEST_PATH}")"
echo "Release manifest OK: ${manifest_status}"
