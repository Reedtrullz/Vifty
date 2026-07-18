#!/usr/bin/ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"

class ReleaseGHToolchainError < StandardError; end

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: scripts/verify-release-gh-toolchain.rb --policy <json> --source <gh> --destination <path>"
  opts.on("--policy PATH", "Committed release gh policy") { |value| options[:policy] = value }
  opts.on("--source PATH", "Candidate gh executable") { |value| options[:source] = value }
  opts.on("--destination PATH", "Required private path for the verified executable copy") do |value|
    options[:destination] = value
  end
  opts.on("-h", "--help", "Show help") do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "error: #{e.message}"
  warn parser
  exit 64
end

def fail_toolchain(message)
  raise ReleaseGHToolchainError, message
end

def exact_absolute_file(path, label)
  fail_toolchain("#{label} must be an absolute path") unless path.is_a?(String) && path.start_with?("/")
  stat = File.lstat(path)
  fail_toolchain("#{label} must resolve to a regular file") unless File.stat(path).file?
  [path, stat]
rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
  fail_toolchain("#{label} is unreadable: #{e.message}")
end

destination = nil
begin
  %i[policy source destination].each do |key|
    fail_toolchain("--#{key} is required") if options[key].to_s.empty?
    fail_toolchain("--#{key} must be an absolute path") unless options[key].start_with?("/")
  end
  fail_toolchain("unexpected positional arguments: #{ARGV.join(' ')}") unless ARGV.empty?

  policy_path, policy_lstat = exact_absolute_file(File.expand_path(options[:policy]), "policy")
  fail_toolchain("policy must not be a symlink") if policy_lstat.symlink?
  source_path, = exact_absolute_file(File.expand_path(options[:source]), "source")
  policy_bytes = File.binread(policy_path)
  policy = JSON.parse(policy_bytes)
  fail_toolchain("policy must be an object") unless policy.is_a?(Hash)
  expected_keys = %w[platform schemaVersion sha256 tool version]
  fail_toolchain("policy must contain only the exact reviewed keys") unless policy.keys.sort == expected_keys
  fail_toolchain("policy schemaVersion must be 1") unless policy["schemaVersion"] == 1
  fail_toolchain("policy tool must be gh") unless policy["tool"] == "gh"
  fail_toolchain("policy platform must be darwin-arm64") unless policy["platform"] == "darwin-arm64"
  fail_toolchain("policy version must be an exact semantic version") unless
    policy["version"].is_a?(String) && policy["version"].match?(/\A\d+\.\d+\.\d+\z/)
  fail_toolchain("policy sha256 must be a lowercase digest") unless
    policy["sha256"].is_a?(String) && policy["sha256"].match?(/\A[0-9a-f]{64}\z/)

  uname_s, uname_s_error, uname_s_status = Open3.capture3("/usr/bin/uname", "-s")
  uname_m, uname_m_error, uname_m_status = Open3.capture3("/usr/bin/uname", "-m")
  fail_toolchain("failed to identify release host: #{uname_s_error} #{uname_m_error}".strip) unless
    uname_s_status.success? && uname_m_status.success?
  fail_toolchain("release gh policy is only valid on Darwin arm64") unless
    uname_s.strip == "Darwin" && uname_m.strip == "arm64"

  destination = File.expand_path(options[:destination])
  parent = File.dirname(destination)
  parent_stat = File.lstat(parent)
  fail_toolchain("destination parent must be a real private directory") unless
    parent_stat.directory? && !parent_stat.symlink? && (parent_stat.mode & 0o077).zero?
  fail_toolchain("destination must not already exist") if File.exist?(destination) || File.symlink?(destination)

  digest = Digest::SHA256.new
  File.open(source_path, "rb") do |source|
    fail_toolchain("source changed away from a regular file") unless source.stat.file?
    File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o500) do |output|
      while (chunk = source.read(1024 * 1024))
        digest.update(chunk)
        output.write(chunk)
      end
      output.flush
      output.fsync
    end
  end
  File.chmod(0o500, destination)
  fail_toolchain("gh binary SHA-256 does not match the committed release policy") unless
    digest.hexdigest == policy["sha256"]

  version_output, version_error, version_status = Open3.capture3(
    {"PATH" => "/usr/bin:/bin:/usr/sbin:/sbin"},
    destination,
    "version",
    unsetenv_others: true
  )
  expected_prefix = "gh version #{policy.fetch('version')} ("
  fail_toolchain("verified gh binary did not report the pinned version: #{version_error.strip}") unless
    version_status.success? && version_output.lines.first.to_s.start_with?(expected_prefix)

  puts JSON.generate({
    "schemaVersion" => 1,
    "status" => "passed",
    "tool" => "gh",
    "version" => policy.fetch("version"),
    "platform" => policy.fetch("platform"),
    "sha256" => policy.fetch("sha256"),
    "policySHA256" => Digest::SHA256.hexdigest(policy_bytes),
    "copied" => true,
    "readOnly" => true
  })
rescue JSON::ParserError => e
  warn "error: release gh policy is not valid JSON: #{e.message}"
  FileUtils.rm_f(destination) if destination
  exit 65
rescue ReleaseGHToolchainError, KeyError, SystemCallError => e
  warn "error: release gh toolchain verification failed: #{e.message}"
  FileUtils.rm_f(destination) if destination
  exit 65
end
