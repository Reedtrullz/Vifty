#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"

GRANDFATHERED_INITIAL_V132_CANONICAL_SHA256 = "74a9b82aeb16afa308c92fad3af6db2bbc0d50fc6ed47b2a3212d2345ab67afa"

options = {
  current: nil,
  base: nil,
  allow_initial_v132: false
}

OptionParser.new do |parser|
  parser.banner = "Usage: check-release-manifest-history.rb --current PATH (--base PATH | --allow-initial-v1.3.2)"
  parser.on("--current PATH") { |value| options[:current] = value }
  parser.on("--base PATH") { |value| options[:base] = value }
  parser.on("--allow-initial-v1.3.2") { options[:allow_initial_v132] = true }
end.parse!

abort("error: --current is required") if options[:current].to_s.empty?
if options[:base].to_s.empty? == !options[:allow_initial_v132]
  abort("error: require exactly one of --base or --allow-initial-v1.3.2")
end

def read_manifest(path, label)
  data = JSON.parse(File.read(path))
  abort("error: #{label} release manifest must decode to an object") unless data.is_a?(Hash)
  abort("error: #{label} historicalReleases must be an array") unless data["historicalReleases"].is_a?(Array)
  abort("error: #{label} publishedRelease must be an object") unless data["publishedRelease"].is_a?(Hash)
  data
rescue Errno::ENOENT
  abort("error: #{label} release manifest not found: #{path}")
rescue JSON::ParserError => error
  abort("error: #{label} release manifest is invalid JSON: #{error.message}")
end

def deep_sort(value)
  case value
  when Hash
    value.keys.sort.to_h { |key| [key, deep_sort(value.fetch(key))] }
  when Array
    value.map { |item| deep_sort(item) }
  else
    value
  end
end

def semver(value)
  match = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/.match(value.to_s)
  match&.captures&.map(&:to_i)
end

current = read_manifest(options.fetch(:current), "current")

if options[:allow_initial_v132]
  canonical_sha = Digest::SHA256.hexdigest(JSON.generate(deep_sort(current)))
  unless canonical_sha == GRANDFATHERED_INITIAL_V132_CANONICAL_SHA256
    abort("error: initial manifest does not match grandfathered v1.3.2 boundary")
  end
  puts "Release manifest history OK: exact grandfathered v1.3.2 initial boundary"
  exit 0
end

base = read_manifest(options.fetch(:base), "trusted base")
base_history = base.fetch("historicalReleases")
current_history = current.fetch("historicalReleases")

immutable_authority_fields = ["$schema", "schemaVersion", "schemaID", "product", "releasePolicy"]
immutable_authority_fields.each do |field|
  unless current[field] == base[field]
    abort("error: release-manifest authority field #{field} changed; update the trusted checker in an earlier commit before changing this field")
  end
end

unless current_history.length >= base_history.length && current_history.first(base_history.length) == base_history
  abort("error: prior historicalReleases prefix changed; deletion, mutation, and reorder are forbidden")
end

base_published = base.fetch("publishedRelease")
current_published = current.fetch("publishedRelease")

if current_published == base_published
  unless current_history.length == base_history.length
    abort("error: historicalReleases may grow only when publishedRelease changes")
  end

  base_candidate = base["candidate"]
  current_candidate = current["candidate"]
  if base_candidate.is_a?(Hash) && current_candidate != base_candidate
    unless current_candidate.is_a?(Hash)
      abort("error: unpromoted trusted base candidate may be cleared only by promotion")
    end

    base_candidate_version = semver(base_candidate["version"])
    current_candidate_version = semver(current_candidate["version"])
    unless base_candidate_version &&
           current_candidate_version &&
           (base_candidate_version <=> current_candidate_version) == -1
      abort(
        "error: replacement candidate version #{current_candidate["version"]} " \
        "must be newer than trusted base candidate #{base_candidate["version"]}"
      )
    end

    base_candidate_build = base_candidate["build"]
    current_candidate_build = current_candidate["build"]
    unless base_candidate_build.is_a?(Integer) &&
           base_candidate_build.positive? &&
           current_candidate_build.is_a?(Integer) &&
           current_candidate_build > base_candidate_build
      abort(
        "error: replacement candidate build #{current_candidate_build} " \
        "must be greater than trusted base candidate build #{base_candidate_build}"
      )
    end
  end
else
  unless current_history.length == base_history.length + 1 && current_history.last == base_published
    abort("error: previous publishedRelease must be appended unchanged before publishedRelease changes")
  end

  base_candidate = base["candidate"]
  unless base_candidate.is_a?(Hash)
    abort("error: publishedRelease may change only by promoting the trusted base candidate")
  end

  identity_fields = [
    "version",
    "build",
    "tag",
    "artifact",
    "checksumAsset",
    "artifactSummary",
    "releaseChecklist"
  ]
  identity_fields.each do |field|
    unless current_published[field] == base_candidate[field]
      abort("error: promoted publishedRelease must preserve trusted base candidate field #{field}")
    end
  end

  if base_candidate["sha256"] && current_published["sha256"] != base_candidate["sha256"]
    abort("error: promoted publishedRelease sha256 must preserve the trusted base candidate checksum when present")
  end

  promotion_facts_valid =
    current_published["sourceCommit"].is_a?(String) &&
    current_published["sourceCommit"].match?(/\A[0-9a-f]{40}\z/) &&
    current_published["sourceCIRunID"].is_a?(Integer) &&
    current_published["sourceCIRunID"].positive? &&
    current_published["releaseWorkflowRunID"].is_a?(Integer) &&
    current_published["releaseWorkflowRunID"].positive? &&
    current_published["sha256"].is_a?(String) &&
    current_published["sha256"].match?(/\A[0-9a-f]{64}\z/) &&
    current_published["artifactTrust"] == "passed" &&
    current_published["signingTrust"] == "developer-id-notarized" &&
    current_published["tagTrust"] == "signed-verified" &&
    current_published["installedReleaseReview"] == base_candidate["installedReleaseReview"] &&
    current_published["manualCompatibility"] == base_candidate["manualCompatibility"] &&
    current_published["manualCompatibilityScope"] == base_candidate["manualCompatibilityScope"]
  unless promotion_facts_valid
    abort("error: promoted publishedRelease must add complete signed publication facts without fabricating post-release review evidence")
  end

  unless current["candidate"].nil?
    abort("error: candidate must be cleared when it is promoted into publishedRelease")
  end
end

puts "Release manifest history OK: trusted base prefix and previous published release preserved"
