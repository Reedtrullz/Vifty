#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${VIFTY_RELEASE_FACTS_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
MODE="check"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/render-release-facts.sh [--check|--write]

Checks or refreshes bounded generated release-fact blocks in the public trust,
support, compatibility, and release documentation. The prose outside each block
may explain the evidence but must not redefine current release facts.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      MODE="check"
      shift
      ;;
    --write)
      MODE="write"
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

VIFTY_RELEASE_MANIFEST_ROOT="${ROOT_DIR}" "${SCRIPT_DIR}/check-release-manifest.sh" >/dev/null

ruby -rjson - "${ROOT_DIR}" "${MODE}" <<'RUBY'
root, mode = ARGV
manifest = JSON.parse(File.read(File.join(root, ".github/release-manifest.json")))
product = manifest.fetch("product")
policy = manifest.fetch("releasePolicy")
published = manifest.fetch("publishedRelease")
candidate = manifest["candidate"]

files = [
  "README.md",
  "SECURITY.md",
  "SUPPORT.md",
  "docs/release-status.md",
  "docs/trust-model.md",
  "docs/competitive-analysis.md",
  "docs/compatibility.md",
  "docs/release.md",
  "docs/auto-update.md"
]

start_marker = "<!-- BEGIN GENERATED RELEASE FACTS -->"
end_marker = "<!-- END GENERATED RELEASE FACTS -->"
architecture_label = product.fetch("architectures").join(" + ")
manual_compatibility = published.fetch("manualCompatibility")
manual_compatibility_fact = if manual_compatibility == "passed-auto-restored"
  scope = published.fetch("manualCompatibilityScope")
  models = scope.fetch("modelIdentifiers").map { |identifier| "`#{identifier}`" }.join(", ")
  "manual Fixed/Curve/Auto compatibility `#{manual_compatibility}` on #{models} only " \
    "(review `#{scope.fetch("reviewReport")}`; attestation `#{scope.fetch("attestation")}`)"
else
  "manual Fixed/Curve/Auto compatibility `#{manual_compatibility}`"
end
block = <<~MARKDOWN.chomp
  #{start_marker}
  > Release facts authority: `.github/release-manifest.json` (schema `docs/schemas/release-manifest.schema.json`).
  > Published: `#{published.fetch("tag")}` (version `#{published.fetch("version")}`, build `#{published.fetch("build")}`), `#{architecture_label}` only, minimum macOS `#{product.fetch("minimumMacOS")}`.
  > Runtime identities: app `#{product.fetch("bundleID")}`, daemon `#{product.fetch("daemonID")}`, helper `#{product.fetch("helperID")}`, CLI `#{product.fetch("ctlID")}`.
  > Canonical artifact: `#{published.fetch("artifact")}` with checksum asset `#{published.fetch("checksumAsset")}` and SHA-256 `#{published.fetch("sha256")}`.
  > Public artifact trust: `#{published.fetch("artifactTrust")}` / `#{published.fetch("signingTrust")}` for TeamID `#{policy.fetch("developerTeamID")}`; source `#{published.fetch("sourceCommit")}`, CI run `#{published.fetch("sourceCIRunID")}`, Release run `#{published.fetch("releaseWorkflowRunID")}`.
  > Tag policy: `#{published.fetch("tag")}` remains recorded as `#{published.fetch("tagTrust")}` evidence; signed tags are mandatory from version `#{policy.fetch("signedTagsRequiredFromVersion")}` onward.
  > Separate exact-build claims: installed release review `#{published.fetch("installedReleaseReview")}`; #{manual_compatibility_fact}.
  #{end_marker}
MARKDOWN

release_status_metadata_fact = if candidate
  "Release candidate metadata in `Resources/Info.plist` is staged at " \
    "`#{candidate.fetch("version")}` build `#{candidate.fetch("build")}`, while " \
    "`Casks/vifty.rb` remains pinned to published `#{published.fetch("version")}` " \
    "with SHA-256 `#{published.fetch("sha256")}`"
else
  "Release metadata in `Resources/Info.plist` and `Casks/vifty.rb` is aligned at " \
    "`#{published.fetch("version")}` build `#{published.fetch("build")}`"
end

failures = []
files.each do |relative_path|
  path = File.join(root, relative_path)
  unless File.file?(path)
    failures << "missing documentation target #{relative_path}"
    next
  end
  text = File.read(path)
  marker_pattern = /#{Regexp.escape(start_marker)}.*?#{Regexp.escape(end_marker)}/m
  if mode == "write"
    updated = if text.match?(marker_pattern)
      text.sub(marker_pattern, block)
    else
      heading_end = text.index("\n")
      raise "#{relative_path} must begin with a Markdown heading" unless heading_end
      text.dup.insert(heading_end + 1, "\n#{block}\n")
    end
    File.write(path, updated) unless updated == text
  else
    actual = text[marker_pattern]
    failures << "#{relative_path} generated release fact block is missing or stale" unless actual == block
  end
end

current_requirements = {
  "README.md" => [
    "Vifty `#{published.fetch("tag")}` is the current published Developer ID release.",
    "The exact public zip and the checked-in cask both resolve to SHA-256 `#{published.fetch("sha256")}`.",
    "The Homebrew cask now points at the published `#{published.fetch("tag")}` notarized zip with SHA-256 `#{published.fetch("sha256")}`."
  ],
  "SECURITY.md" => [
    "| #{published.fetch("version")} | Supported Developer ID signed/notarized release;"
  ],
  "docs/release-status.md" => [
    "`#{published.fetch("tag")}` is the current published Developer ID release.",
    "The public `#{published.fetch("artifact")}` and checked-in cask both resolve to SHA-256 `#{published.fetch("sha256")}`.",
    "**Published Developer ID release:** `#{published.fetch("tag")}`",
    release_status_metadata_fact
  ],
  "docs/trust-model.md" => [
    "The exact `#{published.fetch("tag")}` public artifact passes release-level signing/notarization checks"
  ],
  "docs/competitive-analysis.md" => [
    "preserve the verified `#{published.fetch("tag")}` Developer ID artifact"
  ],
  "docs/release.md" => [
    "the current `#{published.fetch("tag")}` artifact"
  ],
  "docs/auto-update.md" => [
    "Auto-update is not enabled for `#{published.fetch("tag")}`"
  ],
  "docs/support-triage.md" => [
    "current `#{published.fetch("tag")}` artifact"
  ]
}

current_claim_patterns = {
  "README.md" => [
    /Vifty `(v\d+\.\d+\.\d+)` is the current published Developer ID release/,
    /The Homebrew cask now points at the published `(v\d+\.\d+\.\d+)` notarized zip/
  ],
  "docs/release-status.md" => [
    /`(v\d+\.\d+\.\d+)` is the current published Developer ID release/,
    /\*\*Published Developer ID release:\*\* `(v\d+\.\d+\.\d+)`/
  ],
  "docs/release.md" => [/the current `(v\d+\.\d+\.\d+)` artifact/],
  "docs/support-triage.md" => [/current `(v\d+\.\d+\.\d+)` artifact/]
}

forbidden = {
  "SECURITY.md" => [/\| 1\.2\.0 \| Supported Developer ID/],
  "docs/trust-model.md" => [/Vifty `v1\.2\.0` is the current published Developer ID release/],
  "docs/competitive-analysis.md" => [/publish `v1\.2\.0` only through the strict Developer ID workflow/],
  "docs/auto-update.md" => [/Auto-update is not enabled for `v1\.2\.0`/],
  "docs/release.md" => [/Do not enable Sparkle for source-first, unsigned-dev, or `v1\.2\.0` artifacts/]
}
if mode == "check"
  current_requirements.each do |relative_path, fragments|
    text = File.read(File.join(root, relative_path))
    fragments.each do |fragment|
      failures << "#{relative_path} is missing manifest-derived current release prose: #{fragment}" unless text.include?(fragment)
    end
  end
  current_claim_patterns.each do |relative_path, patterns|
    text = File.read(File.join(root, relative_path))
    patterns.each do |pattern|
      text.scan(pattern).flatten.each do |claimed_tag|
        unless claimed_tag == published.fetch("tag")
          failures << "#{relative_path} labels stale #{claimed_tag} as current; manifest publishes #{published.fetch("tag")}"
        end
      end
    end
  end
  forbidden.each do |relative_path, patterns|
    text = File.read(File.join(root, relative_path))
    patterns.each do |pattern|
      failures << "#{relative_path} retains stale release fact matching #{pattern.inspect}" if text.match?(pattern)
    end
  end
end

unless failures.empty?
  failures.each { |failure| warn "error: #{failure}" }
  exit 1
end

puts mode == "write" ? "Updated generated release fact blocks" : "Release fact blocks OK"
RUBY
