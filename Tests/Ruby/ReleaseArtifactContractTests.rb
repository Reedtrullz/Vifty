# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../../scripts/lib/release_artifact_contract"

class ReleaseArtifactContractTests < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  V132_COMMIT = "6a771c2ea10386bf7a0a8369a759930f01d56062"
  V132_SHA = "8bbc48b7db7bbe342a6c053a58aa655c969d9b803794f981a4cd8e7d3514bcc0"
  TEAM_ID = "X88J3853S2"
  DIFFERENT_SHA = "f" * 64

  def test_tag_snapshot_reads_use_absolute_hermetic_git_without_replacement_objects
    environment = ViftyReleaseArtifactContract::HERMETIC_GIT_ENV

    assert_equal "/usr/bin:/bin:/usr/sbin:/sbin", environment.fetch("PATH")
    assert_equal "1", environment.fetch("GIT_CONFIG_NOSYSTEM")
    assert_equal "/dev/null", environment.fetch("GIT_CONFIG_GLOBAL")
    assert_equal "1", environment.fetch("GIT_NO_REPLACE_OBJECTS")
    source = File.read(File.join(ROOT, "scripts/lib/release_artifact_contract.rb"))
    assert_operator source.scan('"/usr/bin/git"').length, :>=, 2
    assert_operator source.scan("unsetenv_others: true").length, :>=, 2
    assert_includes source, '"refs/tags/#{tag}^{commit}"'
  end

  def test_promoted_tagged_candidate_rejects_differing_expected_sha_override
    error = assert_raises(ViftyReleaseArtifactContract::SHAPolicyError) do
      ViftyReleaseArtifactContract.resolve_expected_sha(
        current_kind: "published",
        current_sha: V132_SHA,
        tagged_kind: "candidate",
        tagged_sha: nil,
        override: DIFFERENT_SHA
      )
    end

    assert_match(/conflicts with the selected release's pinned manifest sha256/, error.message)
  end

  def test_promoted_tagged_candidate_uses_current_immutable_manifest_sha
    resolved = ViftyReleaseArtifactContract.resolve_expected_sha(
      current_kind: "published",
      current_sha: V132_SHA,
      tagged_kind: "candidate",
      tagged_sha: nil,
      override: nil
    )

    assert_equal V132_SHA, resolved.fetch(:sha)
    assert_equal "manifest sha256", resolved.fetch(:source)
  end

  def test_current_candidate_pin_cannot_be_overridden
    error = assert_raises(ViftyReleaseArtifactContract::SHAPolicyError) do
      ViftyReleaseArtifactContract.resolve_expected_sha(
        current_kind: "candidate",
        current_sha: V132_SHA,
        tagged_kind: "candidate",
        tagged_sha: nil,
        override: DIFFERENT_SHA
      )
    end

    assert_match(/conflicts with the selected release's pinned manifest sha256/, error.message)
  end

  def test_tagged_candidate_pin_cannot_be_overridden
    error = assert_raises(ViftyReleaseArtifactContract::SHAPolicyError) do
      ViftyReleaseArtifactContract.resolve_expected_sha(
        current_kind: "candidate",
        current_sha: nil,
        tagged_kind: "candidate",
        tagged_sha: V132_SHA,
        override: DIFFERENT_SHA
      )
    end

    assert_match(/conflicts with the selected release's pinned manifest sha256/, error.message)
  end

  def test_candidate_override_is_allowed_only_when_both_manifest_pins_are_null
    resolved = ViftyReleaseArtifactContract.resolve_expected_sha(
      current_kind: "candidate",
      current_sha: nil,
      tagged_kind: "candidate",
      tagged_sha: nil,
      override: V132_SHA
    )

    assert_equal V132_SHA, resolved.fetch(:sha)
    assert_equal "expected sha256", resolved.fetch(:source)
  end

  def test_matching_override_for_pinned_candidate_preserves_manifest_source
    resolved = ViftyReleaseArtifactContract.resolve_expected_sha(
      current_kind: "candidate",
      current_sha: V132_SHA,
      tagged_kind: "candidate",
      tagged_sha: V132_SHA,
      override: V132_SHA
    )

    assert_equal V132_SHA, resolved.fetch(:sha)
    assert_equal "manifest sha256", resolved.fetch(:source)
  end

  def test_conflicting_current_and_tagged_candidate_pins_are_rejected
    error = assert_raises(ViftyReleaseArtifactContract::SHAPolicyError) do
      ViftyReleaseArtifactContract.resolve_expected_sha(
        current_kind: "published",
        current_sha: V132_SHA,
        tagged_kind: "candidate",
        tagged_sha: DIFFERENT_SHA,
        override: nil
      )
    end

    assert_match(/current and tagged manifest sha256 values conflict/, error.message)
  end

  def test_promoted_summary_rejects_sha_drift_from_a_pinned_tagged_candidate
    errors = validate_promoted_v2_summary(
      tagged_candidate_sha: V132_SHA,
      current_sha: DIFFERENT_SHA,
      evidence_sha: DIFFERENT_SHA,
      source: "manifest sha256"
    )

    assert_includes errors, "current and tagged manifest sha256 values conflict for the selected release"
  end

  def test_promoted_summary_preserves_original_unpinned_candidate_sha_source
    errors = validate_promoted_v2_summary(
      tagged_candidate_sha: nil,
      current_sha: V132_SHA,
      evidence_sha: V132_SHA,
      source: "expected sha256"
    )

    assert_empty errors
  end

  def test_verifier_passes_current_manifest_entry_kind_to_sha_policy
    verifier = File.read(File.join(ROOT, "scripts/verify-release-artifact.sh"))

    assert_includes verifier, "ViftyReleaseArtifactContract.resolve_expected_sha("
    assert_includes verifier, '"${CURRENT_RELEASE_MANIFEST_ENTRY_KIND}" "${CURRENT_MANIFEST_RELEASE_SHA}"'
  end

  def test_exact_schema_v1_v132_contract_passes
    assert_empty validate_v1(manifest: canonical_manifest, summary: canonical_summary)
  end

  def test_schema_v1_rejects_manifest_build_mutation
    manifest = canonical_manifest
    manifest.fetch("publishedRelease")["build"] = 8

    assert_v1_boundary_rejected(manifest: manifest)
  end

  def test_schema_v1_rejects_source_and_tag_commit_mutation
    Dir.mktmpdir("vifty-v132-tag-") do |root|
      repository = File.join(root, "repository")
      run!("/usr/bin/git", "clone", "--quiet", "--no-checkout", "--shared", ROOT, repository)
      mutated_commit = run!("/usr/bin/git", "-C", repository, "rev-parse", "HEAD").strip
      refute_equal V132_COMMIT, mutated_commit
      run!("/usr/bin/git", "-C", repository, "tag", "-f", "v1.3.2", mutated_commit)
      manifest = canonical_manifest
      manifest.fetch("publishedRelease")["sourceCommit"] = mutated_commit

      assert_v1_boundary_rejected(manifest: manifest, source_repository: repository)
    end
  end

  def test_schema_v1_rejects_team_mutation_even_when_summary_matches_it
    manifest = canonical_manifest
    manifest.fetch("releasePolicy")["developerTeamID"] = "MUTATED123"
    summary = canonical_summary
    summary["expectedTeamID"] = "MUTATED123"
    summary["requiredTeamID"] = "MUTATED123"

    assert_v1_boundary_rejected(manifest: manifest, summary: summary)
  end

  def test_schema_v1_rejects_runtime_identifier_mutation
    manifest = canonical_manifest
    manifest.fetch("product")["helperID"] = "tech.reidar.vifty.mutated"

    assert_v1_boundary_rejected(manifest: manifest)
  end

  def test_schema_v1_rejects_architecture_mutation
    manifest = canonical_manifest
    manifest.fetch("product")["architectures"] = %w[arm64 x86_64]

    assert_v1_boundary_rejected(manifest: manifest)
  end

  def test_published_install_command_accepts_exact_current_v132_verifier_v2_fallback
    with_published_install_fixture do |summary_path, manifest_path|
      _stdout, stderr, status = Open3.capture3(
        "/usr/bin/ruby",
        File.join(ROOT, "scripts/lib/release_artifact_contract.rb"),
        "validate-published-install-summary",
        summary_path,
        manifest_path,
        ROOT
      )

      assert status.success?, stderr
    end
  end

  def test_published_install_accepts_promoted_release_with_candidate_tag_snapshot
    errors = validate_promoted_v2_summary(
      tagged_candidate_sha: nil,
      current_sha: V132_SHA,
      evidence_sha: V132_SHA,
      source: "manifest sha256",
      published_install: true
    )

    assert_empty errors
  end

  def test_published_install_rejects_schema_v1_evidence
    errors = validate_published_install(manifest: canonical_manifest, summary: canonical_summary)

    assert_includes errors, "published release installation requires schemaVersion 2 verifier evidence"
  end

  def test_published_install_rejects_candidate_selection
    manifest = canonical_manifest
    manifest["candidate"] = {
      "version" => "1.4.0",
      "build" => 8,
      "tag" => "v1.4.0",
      "artifact" => "Vifty-v1.4.0.zip",
      "checksumAsset" => "Vifty-v1.4.0.zip.sha256",
      "artifactSummary" => "Vifty-v1.4.0-artifact-summary.json",
      "releaseChecklist" => "Vifty-v1.4.0-release-checklist.md",
      "sha256" => DIFFERENT_SHA
    }
    summary = canonical_v132_verifier_v2_summary
    summary["releaseVersion"] = "1.4.0"

    errors = validate_published_install(manifest: manifest, summary: summary)

    assert_includes errors, "release evidence must select the current publishedRelease, not a candidate or historical release"
    assert_includes errors, "releaseVersion must match the current publishedRelease version"
  end

  def test_published_install_rejects_historical_selection
    manifest = canonical_manifest
    manifest["historicalReleases"] = [manifest.fetch("publishedRelease")]
    manifest["publishedRelease"] = {
      "version" => "1.4.0",
      "build" => 8,
      "tag" => "v1.4.0",
      "sourceCommit" => "a" * 40,
      "artifact" => "Vifty-v1.4.0.zip",
      "checksumAsset" => "Vifty-v1.4.0.zip.sha256",
      "artifactSummary" => "Vifty-v1.4.0-artifact-summary.json",
      "releaseChecklist" => "Vifty-v1.4.0-release-checklist.md",
      "sha256" => DIFFERENT_SHA,
      "artifactTrust" => "passed",
      "signingTrust" => "developer-id-notarized"
    }

    errors = validate_published_install(
      manifest: manifest,
      summary: canonical_v132_verifier_v2_summary
    )

    assert_includes errors, "release evidence must select the current publishedRelease, not a candidate or historical release"
    assert_includes errors, "releaseVersion must match the current publishedRelease version"
  end

  def test_published_install_rejects_checksum_drift_and_non_manifest_source
    summary = canonical_v132_verifier_v2_summary
    summary["actualSHA"] = DIFFERENT_SHA
    summary["expectedSHASource"] = "expected sha256"

    errors = validate_published_install(manifest: canonical_manifest, summary: summary)

    assert_includes errors, "actualSHA must exactly match current publishedRelease sha256"
    assert_includes errors, "published release installation requires manifest sha256 evidence"
  end

  def test_published_install_rejects_untrusted_published_manifest_state
    manifest = canonical_manifest
    manifest.fetch("publishedRelease")["artifactTrust"] = "pending"
    manifest.fetch("publishedRelease")["signingTrust"] = "pending"

    errors = validate_published_install(
      manifest: manifest,
      summary: canonical_v132_verifier_v2_summary
    )

    assert_includes errors, "current publishedRelease artifactTrust must be passed"
    assert_includes errors, "current publishedRelease signingTrust must be developer-id-notarized"
  end

  def test_published_install_rejects_skipped_or_incomplete_evidence
    summary = canonical_v132_verifier_v2_summary
    summary["status"] = "failed"
    summary["signatureChecksSkipped"] = true
    summary["notarizationChecksSkipped"] = true
    summary["checks"].pop

    errors = validate_published_install(manifest: canonical_manifest, summary: summary)

    assert_includes errors, "release artifact summary status must be passed"
    assert_includes errors, "release evidence must not skip signature checks"
    assert_includes errors, "release evidence must not skip notarization checks"
    assert_includes errors, "checks must contain the exact verifier check-name set"
  end

  def test_published_install_rejects_nonpassed_check_evidence
    summary = canonical_v132_verifier_v2_summary
    summary.fetch("checks").first["status"] = "skipped"

    errors = validate_published_install(manifest: canonical_manifest, summary: summary)

    assert_includes errors, "every verifier check must be passed release-trust evidence with a non-empty note"
  end

  private

  def canonical_manifest
    JSON.parse(File.read(File.join(ROOT, ".github/release-manifest.json")))
  end

  def v2_manifest(candidate_sha:, published_sha:)
    release = lambda do |version, build, sha|
      {
        "version" => version,
        "build" => build,
        "tag" => "v#{version}",
        "artifact" => "Vifty-v#{version}.zip",
        "checksumAsset" => "Vifty-v#{version}.zip.sha256",
        "artifactSummary" => "Vifty-v#{version}-artifact-summary.json",
        "releaseChecklist" => "Vifty-v#{version}-release-checklist.md",
        "sha256" => sha
      }
    end
    {
      "schemaVersion" => 1,
      "product" => {
        "bundleID" => "tech.reidar.vifty",
        "daemonID" => "tech.reidar.vifty.daemon",
        "helperID" => "tech.reidar.vifty.helper",
        "ctlID" => "tech.reidar.vifty.ctl",
        "architectures" => ["arm64"]
      },
      "releasePolicy" => { "developerTeamID" => TEAM_ID },
      "historicalReleases" => [],
      "publishedRelease" => release.call("1.9.0", 19, published_sha),
      "candidate" => release.call("2.0.0", 20, candidate_sha)
    }
  end

  def validate_promoted_v2_summary(
    tagged_candidate_sha:,
    current_sha:,
    evidence_sha:,
    source:,
    published_install: false
  )
    Dir.mktmpdir("vifty-promoted-candidate-sha-") do |root|
      repository = File.join(root, "repository")
      tagged_manifest_path = File.join(repository, ".github", "release-manifest.json")
      FileUtils.mkdir_p(File.dirname(tagged_manifest_path))
      tagged_manifest = v2_manifest(
        candidate_sha: tagged_candidate_sha,
        published_sha: "e" * 64
      )
      tagged_manifest_bytes = JSON.pretty_generate(tagged_manifest) << "\n"
      File.write(tagged_manifest_path, tagged_manifest_bytes)
      run!("/usr/bin/git", "-C", repository, "init", "--quiet")
      run!("/usr/bin/git", "-C", repository, "add", ".github/release-manifest.json")
      run!(
        "/usr/bin/git", "-C", repository,
        "-c", "user.name=Vifty Tests",
        "-c", "user.email=vifty-tests@example.invalid",
        "-c", "commit.gpgsign=false",
        "commit", "--quiet", "-m", "tag candidate manifest"
      )
      run!("/usr/bin/git", "-C", repository, "tag", "v2.0.0")
      commit = run!("/usr/bin/git", "-C", repository, "rev-parse", "HEAD").strip

      current_manifest = JSON.parse(JSON.generate(tagged_manifest))
      promoted = current_manifest.fetch("candidate")
      promoted["sourceCommit"] = commit
      promoted["sha256"] = current_sha
      if published_install
        promoted["artifactTrust"] = "passed"
        promoted["signingTrust"] = "developer-id-notarized"
      end
      current_manifest["publishedRelease"] = promoted
      current_manifest["candidate"] = nil
      current_manifest_path = File.join(root, "current-manifest.json")
      File.write(current_manifest_path, JSON.pretty_generate(current_manifest) << "\n")

      product = tagged_manifest.fetch("product")
      summary = {
        "schemaVersion" => 2,
        "schemaID" => ViftyReleaseArtifactContract::SUMMARY_SCHEMA_ID,
        "status" => "passed",
        "signatureChecksSkipped" => false,
        "notarizationChecksSkipped" => false,
        "releaseVersion" => "2.0.0",
        "releaseTag" => "v2.0.0",
        "releaseSourceCommit" => commit,
        "releaseManifestEntryKind" => "candidate",
        "releaseManifestSchemaVersion" => 1,
        "releaseManifestSHA256" => Digest::SHA256.hexdigest(tagged_manifest_bytes),
        "bundleVersion" => "2.0.0",
        "bundleBuild" => 20,
        "bundleIdentifier" => product.fetch("bundleID"),
        "expectedArtifactName" => "Vifty-v2.0.0.zip",
        "expectedSHA" => evidence_sha,
        "actualSHA" => evidence_sha,
        "expectedSHASource" => source,
        "runtimeIdentifiers" => {
          "app" => product.fetch("bundleID"),
          "daemon" => product.fetch("daemonID"),
          "helper" => product.fetch("helperID"),
          "ctl" => product.fetch("ctlID")
        },
        "launchDaemonLabel" => product.fetch("daemonID"),
        "machServiceName" => product.fetch("daemonID"),
        "architectures" => %w[expected app helper daemon ctl].to_h { |field| [field, ["arm64"]] },
        "expectedTeamID" => TEAM_ID,
        "requiredTeamID" => TEAM_ID,
        "checks" => ViftyReleaseArtifactContract::REQUIRED_CHECK_NAMES.map do |name|
          { "name" => name, "status" => "passed", "scope" => "release-trust", "note" => "fixture" }
        end
      }
      summary_path = File.join(root, "summary.json")
      File.write(summary_path, JSON.generate(summary))

      validation_arguments = {
        summary_path: summary_path,
        manifest_path: current_manifest_path,
        source_repository: repository
      }
      return ViftyReleaseArtifactContract.validate_published_install_summary(**validation_arguments) if published_install

      return ViftyReleaseArtifactContract.validate_summary(**validation_arguments)
    end
  end

  def canonical_v132_verifier_v2_summary(manifest_sha: nil)
    manifest_sha ||= Digest::SHA256.hexdigest(JSON.generate(canonical_manifest))
    {
      "schemaVersion" => 2,
      "schemaID" => ViftyReleaseArtifactContract::SUMMARY_SCHEMA_ID,
      "status" => "passed",
      "signatureChecksSkipped" => false,
      "notarizationChecksSkipped" => false,
      "releaseVersion" => "1.3.2",
      "releaseTag" => "v1.3.2",
      "releaseSourceCommit" => V132_COMMIT,
      "releaseManifestEntryKind" => "published",
      "releaseManifestSchemaVersion" => 1,
      "releaseManifestSHA256" => manifest_sha,
      "caskVersion" => "1.3.2",
      "bundleVersion" => "1.3.2",
      "bundleBuild" => 7,
      "bundleIdentifier" => "tech.reidar.vifty",
      "expectedArtifactName" => "Vifty-v1.3.2.zip",
      "expectedSHA" => V132_SHA,
      "actualSHA" => V132_SHA,
      "expectedSHASource" => "manifest sha256",
      "runtimeIdentifiers" => {
        "app" => "tech.reidar.vifty",
        "daemon" => "tech.reidar.vifty.daemon",
        "helper" => "tech.reidar.vifty.helper",
        "ctl" => "tech.reidar.vifty.ctl"
      },
      "launchDaemonLabel" => "tech.reidar.vifty.daemon",
      "machServiceName" => "tech.reidar.vifty.daemon",
      "architectures" => %w[expected app helper daemon ctl].to_h { |field| [field, ["arm64"]] },
      "expectedTeamID" => TEAM_ID,
      "requiredTeamID" => TEAM_ID,
      "checks" => ViftyReleaseArtifactContract::REQUIRED_CHECK_NAMES.map do |name|
        { "name" => name, "status" => "passed", "scope" => "release-trust", "note" => "fixture" }
      end
    }
  end

  def with_published_install_fixture(manifest: canonical_manifest, summary: nil)
    Dir.mktmpdir("vifty-published-install-contract-") do |root|
      manifest_path = File.join(root, "manifest.json")
      manifest_bytes = JSON.generate(manifest)
      File.write(manifest_path, manifest_bytes)
      summary ||= canonical_v132_verifier_v2_summary(
        manifest_sha: Digest::SHA256.hexdigest(manifest_bytes)
      )
      summary["releaseManifestSHA256"] = Digest::SHA256.hexdigest(manifest_bytes)
      summary_path = File.join(root, "summary.json")
      File.write(summary_path, JSON.generate(summary))
      yield summary_path, manifest_path
    end
  end

  def validate_published_install(manifest:, summary:)
    with_published_install_fixture(manifest: manifest, summary: summary) do |summary_path, manifest_path|
      return ViftyReleaseArtifactContract.validate_published_install_summary(
        summary_path: summary_path,
        manifest_path: manifest_path,
        source_repository: ROOT
      )
    end
  end

  def canonical_summary
    {
      "schemaVersion" => 1,
      "schemaID" => ViftyReleaseArtifactContract::SUMMARY_SCHEMA_ID,
      "status" => "passed",
      "generatedAtUTC" => "2026-07-16T00:00:00Z",
      "caskVersion" => "1.3.2",
      "caskURL" => "https://example.invalid/Vifty-v1.3.2.zip",
      "expectedArtifactName" => "Vifty-v1.3.2.zip",
      "artifactPath" => "/tmp/Vifty-v1.3.2.zip",
      "appPath" => "/tmp/Vifty.app",
      "bundleVersion" => "1.3.2",
      "expectedSHA" => V132_SHA,
      "expectedSHASource" => "expected sha256",
      "actualSHA" => V132_SHA,
      "expectedTeamID" => TEAM_ID,
      "requiredTeamID" => TEAM_ID,
      "signatureChecksSkipped" => false,
      "notarizationChecksSkipped" => false,
      "checks" => ViftyReleaseArtifactContract::GRANDFATHERED_V132_CHECK_NAMES.map do |name|
        { "name" => name, "status" => "passed", "scope" => "release-trust", "note" => "fixture" }
      end
    }
  end

  def assert_v1_boundary_rejected(manifest:, summary: canonical_summary, source_repository: ROOT)
    errors = validate_v1(
      manifest: manifest,
      summary: summary,
      source_repository: source_repository
    )
    assert_includes errors, "schemaVersion 1 is grandfathered only for exact public v1.3.2 evidence"
  end

  def validate_v1(manifest:, summary:, source_repository: ROOT)
    Dir.mktmpdir("vifty-v132-contract-") do |root|
      manifest_path = File.join(root, "manifest.json")
      summary_path = File.join(root, "summary.json")
      File.write(manifest_path, JSON.generate(manifest))
      File.write(summary_path, JSON.generate(summary))
      return ViftyReleaseArtifactContract.validate_summary(
        summary_path: summary_path,
        manifest_path: manifest_path,
        source_repository: source_repository
      )
    end
  end

  def run!(*command)
    stdout, stderr, status = Open3.capture3(*command)
    raise "#{command.join(" ")} failed: #{stderr}" unless status.success?

    stdout
  end
end
