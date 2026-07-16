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

unless current_history.length >= base_history.length && current_history.first(base_history.length) == base_history
  abort("error: prior historicalReleases prefix changed; deletion, mutation, and reorder are forbidden")
end

base_published = base.fetch("publishedRelease")
current_published = current.fetch("publishedRelease")

if current_published == base_published
  unless current_history.length == base_history.length
    abort("error: historicalReleases may grow only when publishedRelease changes")
  end
else
  unless current_history.length == base_history.length + 1 && current_history.last == base_published
    abort("error: previous publishedRelease must be appended unchanged before publishedRelease changes")
  end
end

puts "Release manifest history OK: trusted base prefix and previous published release preserved"
