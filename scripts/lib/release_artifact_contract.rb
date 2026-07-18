#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"

module ViftyReleaseArtifactContract
  SUMMARY_SCHEMA_ID = "https://vifty.local/schemas/release-artifact-summary.schema.json"
  SHA256_PATTERN = /\A[0-9a-f]{64}\z/
  COMMIT_PATTERN = /\A[0-9a-f]{40}\z/

  class SHAPolicyError < StandardError; end

  REQUIRED_CHECK_NAMES = %w[
    artifact-sha
    app-bundle-present
    required-executables
    support-scripts
    workload-wrappers
    schema-resources
    plist-lint
    bundle-version
    bundle-identity
    xpc-trust-metadata
    binary-architectures
    codesign-teamid
    codesign-runtime-entitlements
    notarization-gatekeeper
  ].freeze

  GRANDFATHERED_V132_CHECK_NAMES = %w[
    artifact-sha
    app-bundle-present
    required-executables
    support-scripts
    workload-wrappers
    schema-resources
    plist-lint
    bundle-version
    codesign-teamid
    notarization-gatekeeper
  ].freeze

  GRANDFATHERED_V132_VERSION = "1.3.2"
  GRANDFATHERED_V132_TAG = "v1.3.2"
  GRANDFATHERED_V132_ARTIFACT = "Vifty-v1.3.2.zip"
  GRANDFATHERED_V132_SHA256 = "8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0"
  GRANDFATHERED_V132_SOURCE_COMMIT = "6a771c2ea10386bf7a0a8369a759930f01d56062"
  GRANDFATHERED_V132_BUILD = 7
  GRANDFATHERED_V132_TEAM_ID = "X88J3853S2"
  GRANDFATHERED_V132_RUNTIME_IDENTIFIERS = {
    "app" => "tech.reidar.vifty",
    "daemon" => "tech.reidar.vifty.daemon",
    "helper" => "tech.reidar.vifty.helper",
    "ctl" => "tech.reidar.vifty.ctl"
  }.freeze

  module_function

  def resolve_expected_sha(current_kind:, current_sha:, tagged_kind:, tagged_sha:, override:)
    current_sha = nil if current_sha.to_s.empty?
    tagged_sha = nil if tagged_sha.to_s.empty?
    override = nil if override.to_s.empty?

    if override && (!override.is_a?(String) || !override.match?(SHA256_PATTERN))
      raise SHAPolicyError, "--expected-sha must be a lowercase 64-character SHA-256 checksum"
    end

    if current_sha && (!current_sha.is_a?(String) || !current_sha.match?(SHA256_PATTERN))
      raise SHAPolicyError,
            "current #{current_kind} manifest sha256 must be null or a lowercase 64-character SHA-256 checksum"
    end
    if tagged_sha && (!tagged_sha.is_a?(String) || !tagged_sha.match?(SHA256_PATTERN))
      raise SHAPolicyError,
            "tagged #{tagged_kind} manifest sha256 must be null or a lowercase 64-character SHA-256 checksum"
    end

    if current_kind != "candidate" && current_sha.nil?
      raise SHAPolicyError,
            "#{current_kind} release must carry a current immutable manifest sha256"
    end
    if tagged_kind != "candidate" && tagged_sha.nil?
      raise SHAPolicyError,
            "tagged #{tagged_kind} release must carry an immutable manifest sha256"
    end

    if current_sha && tagged_sha && current_sha != tagged_sha
      raise SHAPolicyError,
            "current and tagged manifest sha256 values conflict for the selected release"
    end

    pinned_sha = current_sha || tagged_sha
    if pinned_sha
      if override && override != pinned_sha
        raise SHAPolicyError,
              "--expected-sha conflicts with the selected release's pinned manifest sha256"
      end
      return { sha: pinned_sha, source: "manifest sha256" }
    end

    return { sha: override, source: "expected sha256" } if override

    raise SHAPolicyError,
          "--expected-sha is required while current and tagged candidate manifest checksums are null"
  end

  def read_json(path, label, errors)
    JSON.parse(File.read(path))
  rescue Errno::ENOENT
    errors << "#{label} not found: #{path}"
    nil
  rescue JSON::ParserError => error
    errors << "#{label} is invalid JSON: #{error.message}"
    nil
  end

  def selected_release(manifest, version, errors)
    entries = []
    entries << ["candidate", manifest["candidate"]] if manifest["candidate"].is_a?(Hash)
    entries << ["published", manifest["publishedRelease"]] if manifest["publishedRelease"].is_a?(Hash)
    Array(manifest["historicalReleases"]).each do |release|
      entries << ["historical", release] if release.is_a?(Hash)
    end
    matches = entries.select { |_kind, release| release["version"] == version }
    if matches.length != 1
      errors << "releaseVersion must select exactly one authoritative manifest entry"
      return nil
    end
    matches.first
  end

  def tag_commit(repository, tag, errors)
    stdout, stderr, status = Open3.capture3(
      "git", "-C", repository, "rev-parse", "--verify", "#{tag}^{commit}"
    )
    commit = stdout.strip
    unless status.success? && commit.match?(COMMIT_PATTERN)
      detail = stderr.strip
      errors << "selected manifest tag #{tag.inspect} is unavailable as a commit#{detail.empty? ? "" : ": #{detail}"}"
      return nil
    end
    commit
  rescue Errno::ENOENT => error
    errors << "could not resolve selected manifest tag: #{error.message}"
    nil
  end

  def tagged_manifest_snapshot(repository, commit, errors)
    stdout, stderr, status = Open3.capture3(
      "git", "-C", repository, "show", "#{commit}:.github/release-manifest.json"
    )
    unless status.success?
      detail = stderr.strip
      errors << "tagged source commit is missing its release manifest snapshot#{detail.empty? ? "" : ": #{detail}"}"
      return nil
    end

    manifest = JSON.parse(stdout)
    unless manifest.is_a?(Hash)
      errors << "tagged release manifest snapshot must decode to an object"
      return nil
    end
    [manifest, stdout.b]
  rescue JSON::ParserError => error
    errors << "tagged release manifest snapshot is invalid JSON: #{error.message}"
    nil
  rescue Errno::ENOENT => error
    errors << "could not read tagged release manifest snapshot: #{error.message}"
    nil
  end

  def validate_check_set(summary, required_names, errors)
    checks = summary["checks"]
    unless checks.is_a?(Array)
      errors << "checks must contain the exact verifier check-name set"
      return
    end

    names = checks.map { |check| check.is_a?(Hash) ? check["name"] : nil }
    errors << "checks must contain unique names" unless names.compact.uniq.length == names.length
    unless names.length == required_names.length && names.sort == required_names.sort
      errors << "checks must contain the exact verifier check-name set"
    end
    checks.each do |check|
      unless check.is_a?(Hash) &&
             check["status"] == "passed" &&
             check["scope"] == "release-trust" &&
             check["note"].is_a?(String) && !check["note"].empty?
        errors << "every verifier check must be passed release-trust evidence with a non-empty note"
        break
      end
    end
  end

  def validate_common_summary(summary, errors)
    errors << "release artifact summary must decode to an object" unless summary.is_a?(Hash)
    return unless summary.is_a?(Hash)

    errors << "release artifact summary schemaID is invalid" unless summary["schemaID"] == SUMMARY_SCHEMA_ID
    errors << "release artifact summary status must be passed" unless summary["status"] == "passed"
    errors << "release evidence must not skip signature checks" unless summary["signatureChecksSkipped"] == false
    errors << "release evidence must not skip notarization checks" unless summary["notarizationChecksSkipped"] == false
  end

  def validate_grandfathered_v1(summary, manifest, source_repository, errors)
    exact_values = {
      "caskVersion" => GRANDFATHERED_V132_VERSION,
      "bundleVersion" => GRANDFATHERED_V132_VERSION,
      "expectedArtifactName" => GRANDFATHERED_V132_ARTIFACT,
      "expectedSHA" => GRANDFATHERED_V132_SHA256,
      "actualSHA" => GRANDFATHERED_V132_SHA256,
      "expectedSHASource" => "expected sha256",
      "expectedTeamID" => GRANDFATHERED_V132_TEAM_ID,
      "requiredTeamID" => GRANDFATHERED_V132_TEAM_ID
    }
    exact_boundary = exact_values.all? { |field, expected| summary[field] == expected }
    selected = selected_release(manifest, GRANDFATHERED_V132_VERSION, errors)
    if selected
      kind, release = selected
      product = manifest["product"].is_a?(Hash) ? manifest["product"] : {}
      runtime_identifiers = {
        "app" => product["bundleID"],
        "daemon" => product["daemonID"],
        "helper" => product["helperID"],
        "ctl" => product["ctlID"]
      }
      exact_boundary &&=
        %w[published historical].include?(kind) &&
        release["build"] == GRANDFATHERED_V132_BUILD &&
        release["tag"] == GRANDFATHERED_V132_TAG &&
        release["sourceCommit"] == GRANDFATHERED_V132_SOURCE_COMMIT &&
        release["artifact"] == GRANDFATHERED_V132_ARTIFACT &&
        release["sha256"] == GRANDFATHERED_V132_SHA256 &&
        manifest.dig("releasePolicy", "developerTeamID") == GRANDFATHERED_V132_TEAM_ID &&
        runtime_identifiers == GRANDFATHERED_V132_RUNTIME_IDENTIFIERS &&
        product["architectures"] == ["arm64"]
      commit = tag_commit(source_repository, GRANDFATHERED_V132_TAG, errors)
      exact_boundary &&= commit == GRANDFATHERED_V132_SOURCE_COMMIT
    else
      exact_boundary = false
    end
    errors << "schemaVersion 1 is grandfathered only for exact public v1.3.2 evidence" unless exact_boundary
    validate_check_set(summary, GRANDFATHERED_V132_CHECK_NAMES, errors)
  end

  def validate_legacy_v132_verifier_v2(summary, manifest, manifest_path, current_kind, current_release, commit, errors)
    exact_summary = {
      "caskVersion" => GRANDFATHERED_V132_VERSION,
      "bundleVersion" => GRANDFATHERED_V132_VERSION,
      "bundleBuild" => GRANDFATHERED_V132_BUILD,
      "bundleIdentifier" => GRANDFATHERED_V132_RUNTIME_IDENTIFIERS.fetch("app"),
      "releaseVersion" => GRANDFATHERED_V132_VERSION,
      "releaseTag" => GRANDFATHERED_V132_TAG,
      "releaseSourceCommit" => GRANDFATHERED_V132_SOURCE_COMMIT,
      "releaseManifestEntryKind" => current_kind,
      "releaseManifestSchemaVersion" => manifest["schemaVersion"],
      "releaseManifestSHA256" => Digest::SHA256.file(manifest_path).hexdigest,
      "expectedArtifactName" => GRANDFATHERED_V132_ARTIFACT,
      "expectedSHA" => GRANDFATHERED_V132_SHA256,
      "actualSHA" => GRANDFATHERED_V132_SHA256,
      "expectedSHASource" => "manifest sha256",
      "expectedTeamID" => GRANDFATHERED_V132_TEAM_ID,
      "requiredTeamID" => GRANDFATHERED_V132_TEAM_ID,
      "runtimeIdentifiers" => GRANDFATHERED_V132_RUNTIME_IDENTIFIERS,
      "launchDaemonLabel" => GRANDFATHERED_V132_RUNTIME_IDENTIFIERS.fetch("daemon"),
      "machServiceName" => GRANDFATHERED_V132_RUNTIME_IDENTIFIERS.fetch("daemon"),
      "architectures" => %w[expected app helper daemon ctl].to_h { |field| [field, ["arm64"]] }
    }
    release_exact = %w[published historical].include?(current_kind) &&
      current_release["version"] == GRANDFATHERED_V132_VERSION &&
      current_release["build"] == GRANDFATHERED_V132_BUILD &&
      current_release["tag"] == GRANDFATHERED_V132_TAG &&
      current_release["sourceCommit"] == GRANDFATHERED_V132_SOURCE_COMMIT &&
      current_release["artifact"] == GRANDFATHERED_V132_ARTIFACT &&
      current_release["sha256"] == GRANDFATHERED_V132_SHA256 &&
      commit == GRANDFATHERED_V132_SOURCE_COMMIT &&
      manifest.dig("releasePolicy", "developerTeamID") == GRANDFATHERED_V132_TEAM_ID
    summary_exact = exact_summary.all? { |field, expected| summary[field] == expected }
    unless release_exact && summary_exact
      errors << "tagless verifier fallback is limited to the exact public v1.3.2 release"
      return
    end

    validate_check_set(summary, REQUIRED_CHECK_NAMES, errors)
  rescue Errno::ENOENT
    errors << "authoritative release manifest not found: #{manifest_path}"
  end

  def validate_v2(
    summary,
    manifest,
    manifest_path,
    source_repository,
    errors,
    allow_unpinned_candidate_sha:,
    allow_legacy_v132_verifier_v2:
  )
    version = summary["releaseVersion"].to_s
    current_selected = selected_release(manifest, version, errors)
    return unless current_selected

    current_kind, current_release = current_selected
    tag = current_release["tag"].to_s
    commit = tag_commit(source_repository, tag, errors)
    return unless commit

    tagged_snapshot_errors = []
    tagged_snapshot = tagged_manifest_snapshot(source_repository, commit, tagged_snapshot_errors)
    unless tagged_snapshot
      if allow_legacy_v132_verifier_v2 &&
         version == GRANDFATHERED_V132_VERSION &&
         tag == GRANDFATHERED_V132_TAG &&
         commit == GRANDFATHERED_V132_SOURCE_COMMIT
        validate_legacy_v132_verifier_v2(
          summary,
          manifest,
          manifest_path,
          current_kind,
          current_release,
          commit,
          errors
        )
      else
        errors.concat(tagged_snapshot_errors)
      end
      return
    end

    tagged_manifest, tagged_manifest_bytes = tagged_snapshot
    tagged_selected = selected_release(tagged_manifest, version, errors)
    return unless tagged_selected

    tagged_kind, tagged_release = tagged_selected
    tagged_tag = tagged_release["tag"].to_s
    tagged_manifest_sha = Digest::SHA256.hexdigest(tagged_manifest_bytes)

    errors << "releaseManifestEntryKind does not match tagged release manifest snapshot" unless summary["releaseManifestEntryKind"] == tagged_kind
    errors << "releaseTag does not match tagged release manifest snapshot" unless summary["releaseTag"] == tagged_tag
    unless summary["releaseSourceCommit"] == commit
      errors << "releaseSourceCommit does not match selected manifest tag commit"
    end
    errors << "releaseManifestSHA256 does not match tagged release manifest snapshot" unless summary["releaseManifestSHA256"] == tagged_manifest_sha
    errors << "releaseManifestSchemaVersion does not match tagged release manifest snapshot" unless summary["releaseManifestSchemaVersion"] == tagged_manifest["schemaVersion"]
    errors << "bundleVersion must match selected manifest releaseVersion" unless summary["bundleVersion"] == version
    errors << "bundleBuild must match tagged release manifest snapshot" unless summary["bundleBuild"] == tagged_release["build"]
    errors << "expectedArtifactName does not match tagged release manifest snapshot" unless summary["expectedArtifactName"] == tagged_release["artifact"]

    %w[version build tag artifact checksumAsset artifactSummary releaseChecklist].each do |field|
      unless current_release[field] == tagged_release[field]
        errors << "current authoritative manifest #{field} does not preserve the tagged release identity"
      end
    end
    if current_kind == "candidate"
      unless allow_unpinned_candidate_sha
        errors << "current authoritative manifest must promote the tagged candidate before evidence review"
      end
    elsif current_release["sourceCommit"] != commit
      errors << "current authoritative manifest sourceCommit does not match selected manifest tag commit"
    end

    expected_sha = summary["expectedSHA"].to_s
    actual_sha = summary["actualSHA"].to_s
    errors << "expectedSHA must be a lowercase 64-character SHA-256 checksum" unless expected_sha.match?(SHA256_PATTERN)
    errors << "actualSHA must be a lowercase 64-character SHA-256 checksum" unless actual_sha.match?(SHA256_PATTERN)
    errors << "expectedSHA must match actualSHA" unless expected_sha == actual_sha

    tagged_release_sha = tagged_release["sha256"]
    current_release_sha = current_release["sha256"]
    source = summary["expectedSHASource"]
    current_sha_valid = current_release_sha.is_a?(String) &&
      current_release_sha.match?(SHA256_PATTERN)
    tagged_sha_valid = tagged_release_sha.is_a?(String) &&
      tagged_release_sha.match?(SHA256_PATTERN)

    if !current_release_sha.nil? && !current_sha_valid
      errors << "current #{current_kind} manifest sha256 must be null or a lowercase 64-character SHA-256 checksum"
    end
    if !tagged_release_sha.nil? && !tagged_sha_valid
      errors << "tagged #{tagged_kind} manifest sha256 must be null or a lowercase 64-character SHA-256 checksum"
    end
    if current_kind != "candidate" && !current_sha_valid
      errors << "current authoritative manifest must pin the immutable artifact SHA"
    end
    if tagged_kind != "candidate" && !tagged_sha_valid
      errors << "tagged published and historical manifest entries must carry an immutable sha256"
    end
    if current_sha_valid && tagged_sha_valid && current_release_sha != tagged_release_sha
      errors << "current and tagged manifest sha256 values conflict for the selected release"
    end
    if current_sha_valid && current_release_sha != actual_sha
      errors << "current authoritative manifest artifact SHA does not match immutable release evidence"
    end
    if tagged_sha_valid && tagged_release_sha != actual_sha
      errors << "artifact SHA does not match tagged release manifest snapshot"
    end

    allowed_sources =
      if tagged_sha_valid
        ["manifest sha256"]
      elsif tagged_kind == "candidate"
        sources = ["expected sha256"]
        sources << "manifest sha256" if current_sha_valid
        sources
      else
        []
      end
    unless allowed_sources.include?(source)
      errors << "expectedSHASource does not match the selected release SHA policy"
    end

    if current_kind == "candidate" && current_release_sha.nil? && !allow_unpinned_candidate_sha
      errors << "current authoritative manifest must pin the immutable artifact SHA"
    end

    product = tagged_manifest["product"].is_a?(Hash) ? tagged_manifest["product"] : {}
    policy = tagged_manifest["releasePolicy"].is_a?(Hash) ? tagged_manifest["releasePolicy"] : {}
    expected_runtime = {
      "app" => product["bundleID"],
      "daemon" => product["daemonID"],
      "helper" => product["helperID"],
      "ctl" => product["ctlID"]
    }
    expected_architectures = Array(product["architectures"]).sort
    errors << "bundleIdentifier does not match tagged release manifest snapshot" unless summary["bundleIdentifier"] == product["bundleID"]
    errors << "runtimeIdentifiers do not match tagged release manifest snapshot" unless summary["runtimeIdentifiers"] == expected_runtime
    errors << "launchDaemonLabel does not match tagged release manifest snapshot" unless summary["launchDaemonLabel"] == product["daemonID"]
    errors << "machServiceName does not match tagged release manifest snapshot" unless summary["machServiceName"] == product["daemonID"]
    expected_architecture_map = %w[expected app helper daemon ctl].to_h { |field| [field, expected_architectures] }
    errors << "architectures do not match tagged release manifest snapshot" unless summary["architectures"] == expected_architecture_map
    errors << "expectedTeamID does not match tagged release manifest snapshot" unless summary["expectedTeamID"] == policy["developerTeamID"]
    errors << "requiredTeamID does not match tagged release manifest snapshot" unless summary["requiredTeamID"] == policy["developerTeamID"]

    validate_check_set(summary, REQUIRED_CHECK_NAMES, errors)
  rescue Errno::ENOENT
    errors << "authoritative release manifest not found: #{manifest_path}"
  end

  def validate_summary(
    summary_path:,
    manifest_path:,
    source_repository:,
    allow_unpinned_candidate_sha: false,
    allow_legacy_v132_verifier_v2: false
  )
    errors = []
    summary = read_json(summary_path, "release artifact summary", errors)
    manifest = read_json(manifest_path, "authoritative release manifest", errors)
    return errors unless summary.is_a?(Hash) && manifest.is_a?(Hash)

    validate_common_summary(summary, errors)
    case summary["schemaVersion"]
    when 1
      validate_grandfathered_v1(summary, manifest, source_repository, errors)
    when 2
      validate_v2(
        summary,
        manifest,
        manifest_path,
        source_repository,
        errors,
        allow_unpinned_candidate_sha: allow_unpinned_candidate_sha,
        allow_legacy_v132_verifier_v2: allow_legacy_v132_verifier_v2
      )
    else
      errors << "release artifact summary schemaVersion must be 1 or 2"
    end
    errors.uniq
  end
end

if __FILE__ == $PROGRAM_NAME
  command = ARGV.shift
  case command
  when "checks"
    abort("usage: release_artifact_contract.rb checks") unless ARGV.empty?
    puts ViftyReleaseArtifactContract::REQUIRED_CHECK_NAMES
  when "validate-summary"
    abort("usage: release_artifact_contract.rb validate-summary SUMMARY MANIFEST SOURCE_REPOSITORY") unless ARGV.length == 3
    errors = ViftyReleaseArtifactContract.validate_summary(
      summary_path: ARGV.fetch(0),
      manifest_path: ARGV.fetch(1),
      source_repository: ARGV.fetch(2)
    )
    unless errors.empty?
      errors.each { |error| warn "error: #{error}" }
      exit 1
    end
  when "validate-verifier-summary"
    abort("usage: release_artifact_contract.rb validate-verifier-summary SUMMARY MANIFEST SOURCE_REPOSITORY") unless ARGV.length == 3
    errors = ViftyReleaseArtifactContract.validate_summary(
      summary_path: ARGV.fetch(0),
      manifest_path: ARGV.fetch(1),
      source_repository: ARGV.fetch(2),
      allow_unpinned_candidate_sha: true,
      allow_legacy_v132_verifier_v2: true
    )
    unless errors.empty?
      errors.each { |error| warn "error: #{error}" }
      exit 1
    end
  else
    abort("usage: release_artifact_contract.rb checks | validate-summary SUMMARY MANIFEST SOURCE_REPOSITORY | validate-verifier-summary SUMMARY MANIFEST SOURCE_REPOSITORY")
  end
end
