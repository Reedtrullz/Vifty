# frozen_string_literal: true

require "json"
require "minitest/autorun"

class InstallerLifecycleTrustContractTests < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def lifecycle
    @lifecycle ||= File.read(File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"))
  end

  def installer
    @installer ||= File.read(File.join(ROOT, "scripts/install-vifty.sh"))
  end

  def schema
    @schema ||= JSON.parse(
      File.read(File.join(ROOT, "docs/schemas/helper-maintenance-execution-v1.schema.json"))
    )
  end

  def test_replacement_state_has_a_dedicated_durable_ledger
    assert_includes lifecycle, 'ROOT_REPLACEMENT_RECORD="${EXECUTION_DIR}/replacement-state-v1.json"'
    assert_includes lifecycle, "snapshot_prior_replacement_record"
    assert_includes lifecycle, "remove_replacement_ledger_durably"
    assert_match(/snapshot_prior_replacement_record[\s\S]+ROOT_REPLACEMENT_RECORD/, lifecycle)
  end

  def test_flag_changes_are_journaled_and_reconciled_from_real_flags
    assert_includes lifecycle, "persist_replacement_flag_transition"
    assert_includes lifecycle, "replacement_tree_flag_state"
    assert_includes lifecycle, "reconcile_replacement_flag_state"
    assert_includes lifecycle, "replacementFlagTransition"
    assert_includes lifecycle, "ROOT_FIXTURE_PARTIAL_LOCK"
    assert_includes lifecycle, "ROOT_FIXTURE_PARTIAL_UNLOCK"
    assert_includes lifecycle, "ROOT_FIXTURE_RECORD_POST_RENAME_FAILURE"
  end

  def test_privileged_prepare_uses_a_complete_candidate_snapshot
    assert_includes lifecycle, "stage_replacement_candidate_snapshot"
    assert_includes lifecycle, "CandidateSnapshot/Vifty.app"
    assert_includes lifecycle, "REPLACEMENT_CANDIDATE_SNAPSHOT_APP"
    refute_match(/REPLACEMENT_CANDIDATE_BINDING="\$\(capture_bundle_binding "\$\{REPLACEMENT_CANDIDATE_APP\}"\)"/, lifecycle)
  end

  def test_prepare_and_root_failures_have_a_state_derived_exit_classifier
    assert_includes lifecycle, "fail_prepare_or_root"
    assert_match(/fail_prepare_or_root[\s\S]+replacement_authority_is_proven_disabled_offline/, lifecycle)
    assert_includes installer, "helper authority is active or unknown"
  end

  def test_bundle_binding_schema_requires_a_complete_metadata_manifest
    binding = schema.fetch("$defs").fetch("bundleBinding")
    assert_includes binding.fetch("required"), "manifest"

    row = schema.fetch("$defs").fetch("bundleManifestRow")
    serialized = JSON.generate(row)
    %w[path type uid gid mode nlink size sha256 linkTarget].each do |field|
      assert_includes serialized, field
    end

    assert_includes lifecycle, '"path" => "."'
    assert_includes lifecycle, '"manifest" => first'
  end
end
