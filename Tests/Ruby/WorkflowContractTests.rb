# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class WorkflowContractTests < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  CHECKER = File.join(ROOT, "scripts/check-workflow-contract.rb")
  SUPPORT_SCRIPTS = %w[
    check-release-environment.sh
    check-release-governance.sh
    check-release-prep-diff.sh
    check-release-provenance.sh
    check-release-secrets.sh
    create-signed-release-tag.sh
    push-and-dispatch-signed-release-tag.sh
    release-candidate-inventory.rb
    run-actionlint.sh
    validate-release-governance-evidence.rb
    verify-release-gh-toolchain.rb
    write-release-checklist.sh
  ].freeze

  def setup
    @fixture_root = Dir.mktmpdir("vifty-workflow-contract-ruby-")
    FileUtils.mkdir_p(File.join(@fixture_root, ".github/workflows"))
    FileUtils.mkdir_p(File.join(@fixture_root, "scripts"))

    %w[ci.yml release.yml].each do |workflow|
      FileUtils.cp(
        File.join(ROOT, ".github/workflows", workflow),
        File.join(@fixture_root, ".github/workflows", workflow)
      )
    end
    FileUtils.cp(
      File.join(ROOT, ".github/release-gh-toolchain.json"),
      File.join(@fixture_root, ".github/release-gh-toolchain.json")
    )
    SUPPORT_SCRIPTS.each do |script|
      FileUtils.cp(
        File.join(ROOT, "scripts", script),
        File.join(@fixture_root, "scripts", script)
      )
    end
  end

  def teardown
    FileUtils.remove_entry(@fixture_root) if @fixture_root && File.exist?(@fixture_root)
  end

  def test_rejects_release_job_wrapper_drift_with_dedicated_diagnostic
    mutate_release_workflow(
      "  sign-notarize:\n" \
      "    name: Sign and notarize inventoried candidate\n" \
      "    needs: prepare-candidate\n" \
      "    if: ${{ github.run_attempt == 1 }}\n" \
      "    runs-on: macos-15\n" \
      "    timeout-minutes: 25\n",
      "  sign-notarize:\n" \
      "    name: Sign and notarize inventoried candidate\n" \
      "    needs: prepare-candidate\n" \
      "    if: ${{ github.run_attempt == 1 }}\n" \
      "    runs-on: macos-15\n" \
      "    timeout-minutes: 30\n"
    )

    assert_contract_failure(
      ".github/workflows/release.yml job sign-notarize wrapper must match the reviewed runner, " \
      "timeout, dependencies, permissions, environment, and fields exactly"
    )
  end

  def test_rejects_release_run_name_not_bound_to_pushed_tag
    mutate_release_workflow(
      'run-name: Release ${{ github.ref_name }}',
      'run-name: Release from mutable context'
    )

    assert_contract_failure(
      ".github/workflows/release.yml run-name must bind the exact pushed tag ref name"
    )
  end

  def test_rejects_release_environment_checker_outside_trusted_worktree
    mutate_release_workflow(
      "            cd \"${TRUSTED_ROOT}\"\n" \
      "            GH_TOKEN=\"${RELEASE_GH_TOKEN}\"",
      "            cd \"${GITHUB_WORKSPACE}\"\n" \
      "            GH_TOKEN=\"${RELEASE_GH_TOKEN}\""
    )

    assert_contract_failure(
      "sign-notarize release-environment checker must execute from the exact trusted worktree"
    )
  end

  def test_rejects_checkout_not_bound_to_exact_pushed_tag
    mutate_release_workflow(
      '          ref: refs/tags/${{ github.ref_name }}',
      '          ref: refs/heads/main'
    )

    assert_contract_failure(
      "prepare-candidate checkout must bind the exact immutable pushed tag with full history " \
      "and no persisted credentials"
    )
  end

  def test_rejects_publish_job_rerun_enablement
    mutate_release_workflow(
      "    needs: sign-notarize\n" \
      "    if: ${{ github.run_attempt == 1 }}\n",
      "    needs: sign-notarize\n" \
      "    if: ${{ github.run_attempt >= 1 }}\n"
    )

    assert_contract_failure("publish must refuse workflow reruns")
  end

  def test_rejects_release_job_rerun_enablement
    mutate_release_workflow(
      "    if: ${{ github.run_attempt == 1 }}\n",
      "    if: ${{ github.run_attempt >= 1 }}\n"
    )

    assert_contract_failure(
      "sign-notarize must refuse workflow reruns"
    )
  end

  def test_rejects_prepare_context_without_first_attempt_guard
    mutate_release_workflow(
      '          test "${GITHUB_RUN_ATTEMPT}" = "1"',
      '          test "${GITHUB_RUN_ATTEMPT}" -ge "1"'
    )

    assert_contract_failure(
      "prepare-candidate must fail closed outside the first attempt of an exact immutable " \
      "signed-tag push"
    )
  end

  def test_rejects_tag_push_actor_binding_drift
    mutate_release_workflow(
      '                actor["id"].to_s == ARGV.fetch(1) &&',
      '                actor["id"].to_s.length.positive? &&'
    )

    assert_contract_failure(
      "prepare-candidate must bind signed administrator actor ID and login to the tag-push actor"
    )
  end

  def test_rejects_non_exact_tag_push_trigger
    mutate_release_workflow(
      "  push:\n" \
      "    tags:\n" \
      "      - \"v*\"\n",
      "  push:\n" \
      "    tags:\n" \
      "      - \"v[0-9]*\"\n"
    )

    assert_contract_failure("release workflow must trigger only on pushed tags matching v*")
  end

  def test_rejects_candidate_without_exact_release_prep_diff_gate
    mutate_release_workflow(
      "          scripts/check-release-prep-diff.sh \\\n" \
      "            --root \"${GITHUB_WORKSPACE}\" \\\n" \
      "            --commit \"${GITHUB_SHA}\"\n",
      "          true # exact release-prep diff gate removed\n"
    )

    assert_contract_failure(
      "prepare-candidate must enforce the exact protected release-prep diff before candidate scripts"
    )
  end

  def test_rejects_push_without_first_parent_release_prep_diff_gate
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      "\"${committed_root}/${RELEASE_PREP_DIFF_CHECKER_PATH}\" \\\n",
      "/usr/bin/true \\\n"
    )

    assert_contract_failure(
      "tag creation and push must execute the first-parent-protected release-prep diff checker"
    )
  end

  def test_rejects_candidate_producer_run_attempt_artifact_name
    mutate_release_workflow(
      "name: vifty-candidate-${{ github.run_id }}\n          path: |",
      "name: vifty-candidate-${{ github.run_id }}-${{ github.run_attempt }}\n          path: |"
    )

    assert_contract_failure(
      "candidate artifact handoff must use one rerun-stable run ID name with overwrite enabled"
    )
  end

  def test_rejects_candidate_consumer_run_attempt_artifact_name
    mutate_release_workflow(
      "name: vifty-candidate-${{ github.run_id }}\n          path: .build/release-input",
      "name: vifty-candidate-${{ github.run_id }}-${{ github.run_attempt }}\n" \
      "          path: .build/release-input"
    )

    assert_contract_failure(
      "candidate artifact consumer must use the same rerun-stable run ID handoff name"
    )
  end

  def test_rejects_release_producer_run_attempt_artifact_name
    mutate_release_workflow(
      "name: vifty-release-${{ github.run_id }}\n          path: .build/release-output",
      "name: vifty-release-${{ github.run_id }}-${{ github.run_attempt }}\n" \
      "          path: .build/release-output"
    )

    assert_contract_failure(
      "verified release workflow evidence must retain the complete protected handoff for 90 days"
    )
  end

  def test_rejects_release_consumer_run_attempt_artifact_name
    mutate_release_workflow(
      "name: vifty-release-${{ github.run_id }}\n          path: .build/release-assets",
      "name: vifty-release-${{ github.run_id }}-${{ github.run_attempt }}\n" \
      "          path: .build/release-assets"
    )

    assert_contract_failure(
      "release artifact consumer must use the same rerun-stable run ID handoff name"
    )
  end

  def test_rejects_public_ruleset_revision_binding_drift
    mutate_release_workflow(
      'live_updated_at == expected_updated_at',
      'live_updated_at.is_a?(String)'
    )

    assert_contract_failure(
      "sign-notarize must bind final annotated-tag identity and honest public update/deletion " \
      "ruleset evidence into the publication contract"
    )
  end

  def test_rejects_public_ruleset_revision_canonicalization_drift
    mutate_release_workflow(
      'live_updated_at = Time.iso8601(raw_updated_at).utc.iso8601(9)',
      'live_updated_at = Time.iso8601(raw_updated_at).utc.iso8601'
    )

    assert_contract_failure(
      "sign-notarize must bind final annotated-tag identity and honest public update/deletion " \
      "ruleset evidence into the publication contract"
    )
  end

  def test_rejects_public_ruleset_current_user_bypass_drift
    mutate_release_workflow(
      'ruleset["current_user_can_bypass"] == "never"',
      'ruleset["current_user_can_bypass"] != "always"'
    )

    assert_contract_failure(
      "sign-notarize must bind final annotated-tag identity and honest public update/deletion " \
      "ruleset evidence into the publication contract"
    )
  end

  def test_rejects_github_unsupported_ruleset_pattern_matching
    mutate_all_release_workflow(
      'includes == ["refs/tags/v*"]',
      'includes.include?("refs/tags/{v*,release-*}")'
    )

    assert_contract_failure(
      "sign-notarize must bind final annotated-tag identity and honest public update/deletion " \
      "ruleset evidence into the publication contract"
    )
  end

  def test_rejects_draft_creation_body_prefix_drift
    mutate_release_workflow(
      "body.b.start_with?(submitted_body.b)",
      "body.b.include?(submitted_body.b)"
    )

    assert_contract_failure(
      "publish must REST-create the marked draft, capture its immutable ID directly, and forbid " \
      "tag-based release mutation"
    )
  end

  def test_rejects_prerelease_readback_drift
    mutate_all_release_workflow(
      'release["prerelease"] == false',
      'release["prerelease"] != true'
    )

    assert_contract_failure(
      "publish must REST-create the marked draft, capture its immutable ID directly, and forbid " \
      "tag-based release mutation"
    )
  end

  def test_rejects_curl_config_loading_drift
    mutate_release_workflow(
      "/usr/bin/curl --disable --fail --silent --show-error",
      "/usr/bin/curl --fail --silent --show-error"
    )

    assert_contract_failure(
      "sign-notarize public governance readbacks must pin api.github.com, disable ambient curl " \
      "config, send authentication only on stdin, and bypass caches"
    )
  end

  def test_rejects_unpinned_github_api_host_drift
    mutate_release_workflow(
      "https://api.github.com/repos/${GITHUB_REPOSITORY}/rulesets",
      "${GITHUB_API_URL}/repos/${GITHUB_REPOSITORY}/rulesets"
    )

    assert_contract_failure(
      "sign-notarize public governance readbacks must pin api.github.com, disable ambient curl " \
      "config, send authentication only on stdin, and bypass caches"
    )
  end

  def test_rejects_curl_authorization_header_in_process_arguments
    mutate_release_workflow(
      "                --header @- \\\n",
      "                -H \"Authorization: Bearer ${RELEASE_GH_TOKEN}\" \\\n"
    )

    assert_contract_failure(
      "sign-notarize public governance readbacks must pin api.github.com, disable ambient curl " \
      "config, send authentication only on stdin, and bypass caches"
    )
  end

  def test_rejects_unbounded_release_state_convergence
    mutate_release_workflow(
      '            local deadline=$((SECONDS + 60))',
      '            local deadline=$((SECONDS + 600))'
    )

    assert_contract_failure(
      "publish must use bounded GET-only immutable-ID convergence polling after create, upload, " \
      "and promotion without retrying mutations"
    )
  end

  def test_rejects_mutation_inside_release_state_convergence
    mutate_release_workflow(
      "          verify_release_convergence_identity() {",
      "          release_gh api --hostname github.com --method PATCH /unexpected\n\n" \
      "          verify_release_convergence_identity() {"
    )

    assert_contract_failure(
      "publish must use bounded GET-only immutable-ID convergence polling after create, upload, " \
      "and promotion without retrying mutations"
    )
  end

  def test_rejects_unbounded_release_containment_convergence
    mutate_release_workflow(
      '            local containment_deadline=$((SECONDS + 60))',
      '            local containment_deadline=$((SECONDS + 600))'
    )

    assert_contract_failure(
      "publish containment must use bounded GET-only immutable-ID ownership polling without " \
      "requiring expected body or asset files"
    )
  end

  def test_rejects_sign_notarize_without_independent_release_prep_diff
    mutate_release_workflow(
      "          \"${TRUSTED_ROOT}/scripts/check-release-prep-diff.sh\" \\\n" \
      "            --root \"${TRUSTED_ROOT}\" \\\n" \
      "            --commit \"${GITHUB_SHA}\"\n",
      ""
    )

    assert_contract_failure(
      "sign-notarize must independently enforce the exact protected release-prep diff before " \
      "manifest and provenance checks"
    )
  end

  def test_rejects_incomplete_candidate_inventory_creation
    mutate_release_workflow(
      '"${GITHUB_WORKSPACE}/scripts/release-candidate-inventory.rb" create',
      '"${GITHUB_WORKSPACE}/scripts/release-candidate-inventory.rb" verify-tree'
    )

    assert_contract_failure(
      "prepare-candidate must inventory the complete candidate tree, archive, modes, links, and " \
      "admission provenance"
    )
  end

  def test_rejects_candidate_handoff_without_hashed_admission_provenance
    mutate_release_workflow(
      "              --supplemental release-admission-provenance.json \\\n",
      ""
    )

    assert_contract_failure(
      "prepare-candidate must persist current-fresh signed governance admission in the hashed " \
      "candidate handoff"
    )
  end

  def test_rejects_candidate_consumer_without_safe_complete_tree_extraction
    mutate_release_workflow(
      '"${TRUSTED_ROOT}/scripts/release-candidate-inventory.rb" extract',
      '"${TRUSTED_ROOT}/scripts/release-candidate-inventory.rb" verify-tree'
    )

    assert_contract_failure(
      "sign-notarize must safely extract and verify the complete trusted candidate inventory " \
      "before secrets and signing"
    )
  end

  def test_rejects_extending_initial_freshness_window_through_signing
    mutate_release_workflow(
      "              --allowed-signers \"${TRUSTED_ROOT}/.github/release-signers.allowed\" \\\n" \
      "              --json",
      "              --allowed-signers \"${TRUSTED_ROOT}/.github/release-signers.allowed\" \\\n" \
      "              --require-current-governance-freshness \\\n" \
      "              --json"
    )

    assert_contract_failure(
      "sign-notarize must consume the hashed fresh-admission record without extending the " \
      "15-minute preflight window through signing and notarization"
    )
  end

  def test_rejects_asset_step_without_its_verified_candidate_path
    mutate_release_workflow(
      "          OUTPUT_DIR=\".build/release-output\"\n" \
      "          CANDIDATE_APP=\".build/release-candidate/Vifty.app\"",
      "          OUTPUT_DIR=\".build/release-output\"\n" \
      "          CANDIDATE_APP=\"\""
    )

    assert_contract_failure(
      "release asset creation must define and package the verified candidate app in the same shell step"
    )
  end

  def test_rejects_admission_record_without_bounded_initial_freshness
    mutate_release_workflow(
      'admission_validation["currentEvidenceAgeSeconds"].between?(0, 900)',
      'admission_validation["currentEvidenceAgeSeconds"] >= 0'
    )

    assert_contract_failure(
      "sign-notarize must bind the hashed current-fresh admission provenance into the publication contract"
    )
  end

  def test_rejects_governance_checker_without_explicit_posttag_tuple
    mutate_support_script(
      "check-release-governance.sh",
      'posttag_mode ? "administrator-posttag" : "administrator-pretag"',
      '"administrator-pretag"'
    )

    assert_contract_failure(
      "administrator governance checker must bind exact-main, exact-ref pre-tag absence or " \
      "exact-object post-tag presence, committed-tool, no-bypass ruleset, and anti-shadow secret evidence"
    )
  end

  def test_rejects_governance_validator_without_posttag_mode
    mutate_support_script(
      "validate-release-governance-evidence.rb",
      '"administrator-posttag"',
      '"administrator-pretag"'
    )

    assert_contract_failure(
      "governance validator must bind explicit pre-tag/post-tag state tuples, chronology, " \
      "administrator scopes, exact branch commit, and committed checker SHA"
    )
  end

  def test_rejects_push_helper_repository_scope_drift
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      'if [[ "${REPOSITORY}" != "Reedtrullz/Vifty" ]]',
      'if [[ -z "${REPOSITORY}" ]]'
    )

    assert_contract_failure(
      "signed-tag push helper must bind the canonical Reedtrullz/Vifty source and " \
      "exact committed release tooling"
    )
  end

  def test_rejects_unreviewed_release_gh_binary_digest
    policy_path = File.join(@fixture_root, ".github/release-gh-toolchain.json")
    policy = JSON.parse(File.read(policy_path))
    policy["sha256"] = "f" * 64
    File.write(policy_path, JSON.pretty_generate(policy) + "\n")

    assert_contract_failure(
      "release gh toolchain must pin the reviewed Darwin arm64 gh 2.93.0 bytes before token access"
    )
  end

  def test_rejects_gh_verifier_that_inherits_credentials
    mutate_support_script(
      "verify-release-gh-toolchain.rb",
      "    unsetenv_others: true",
      "    unsetenv_others: false"
    )

    assert_contract_failure(
      "release gh toolchain must pin the reviewed Darwin arm64 gh 2.93.0 bytes before token access"
    )
  end

  def test_rejects_push_helper_without_first_parent_gh_policy_continuity
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      "release gh toolchain policy must be byte-identical to the exact first parent",
      "release gh toolchain policy was inspected"
    )

    assert_contract_failure(
      "release operator entrypoints must verify the first-parent-pinned gh binary before token " \
      "access and bind it into governance evidence"
    )
  end

  def test_rejects_incomplete_first_parent_release_tool_continuity
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      '  "scripts/verify-release-artifact.sh"',
      '  "scripts/not-the-release-verifier.sh"'
    )

    assert_contract_failure(
      "release prep must keep the complete reviewed release-tool set byte-identical to its exact first parent"
    )
  end

  def test_rejects_push_helper_matching_ref_lookup
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      '"repos/${REPOSITORY}/git/ref/${namespace}/${name}"',
      '"repos/${REPOSITORY}/git/matching-refs/${namespace}/${name}"'
    )

    assert_contract_failure(
      "signed-tag push helper must prove exact absent-ref compare-and-swap creation, " \
      "exact tag-object readback, strict new-tag ownership, and same-named branch absence"
    )
  end

  def test_rejects_push_helper_published_only_release_lookup
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      '"repos/${REPOSITORY}/releases?per_page=100"',
      '"repos/${REPOSITORY}/releases/tags/${TAG}"'
    )

    assert_contract_failure(
      "signed-tag push helper must prove exact absent-ref compare-and-swap creation, " \
      "exact tag-object readback, strict new-tag ownership, and same-named branch absence"
    )
  end

  def test_rejects_push_helper_without_strict_new_tag_ownership
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      'fields[2] == "[new tag]"',
      'fields[2] != "[rejected]"'
    )

    assert_contract_failure(
      "signed-tag push helper must prove exact absent-ref compare-and-swap creation, " \
      "exact tag-object readback, strict new-tag ownership, and same-named branch absence"
    )
  end

  def test_rejects_push_helper_without_exact_posttag_validation
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      '--expected-existing-tag-object "${TAG_OBJECT}"',
      '--current-time "${postpush_time}"'
    )

    assert_contract_failure(
      "signed-tag push helper must run the exact committed checker and validator in " \
      "exact-object post-tag mode before accepting the tag-push run"
    )
  end

  def test_rejects_push_helper_without_pre_push_retirement_marker
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      "create_retirement_marker\n" \
      'write_receipt "push-started-remote-outcome-unknown" "${CURRENT_STAGE}"',
      "true # durable retirement marker removed\n" \
      'write_receipt "push-started-remote-outcome-unknown" "${CURRENT_STAGE}"'
    )

    assert_contract_failure(
      "signed-tag push helper must durably retire the tag before its one compare-and-swap " \
      "push, never manually dispatch or rerun, and never authorize retry or resume"
    )
  end

  def test_rejects_push_helper_without_retired_receipt_tombstone
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      'receipt["status"] == "validated-pre-push"',
      'receipt["status"].is_a?(String)'
    )

    assert_contract_failure(
      "signed-tag push helper must durably retire the tag before its one compare-and-swap " \
      "push, never manually dispatch or rerun, and never authorize retry or resume"
    )
  end

  def test_rejects_push_helper_repo_local_transaction_state
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      'transactions_dir="${vifty_state_dir}/ReleaseTransactions"',
      'transactions_dir="${ROOT_DIR}/.build/release-transactions"'
    )

    assert_contract_failure(
      "signed-tag push helper must durably retire the tag before its one compare-and-swap " \
      "push, never manually dispatch or rerun, and never authorize retry or resume"
    )
  end

  def test_rejects_push_helper_caller_controlled_transaction_home
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      "passwd_home = Etc.getpwuid(Process.uid).dir",
      'passwd_home = ENV.fetch("HOME")'
    )

    assert_contract_failure(
      "signed-tag push helper must durably retire the tag before its one compare-and-swap " \
      "push, never manually dispatch or rerun, and never authorize retry or resume"
    )
  end

  def test_rejects_push_helper_manual_workflow_dispatch
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      'CURRENT_STAGE="tag-push-run-observation"',
      "safe_gh workflow run \"${WORKFLOW_ID}\"\n" \
      'CURRENT_STAGE="tag-push-run-observation"'
    )

    assert_contract_failure(
      "signed-tag push helper must durably retire the tag before its one compare-and-swap " \
      "push, never manually dispatch or rerun, and never authorize retry or resume"
    )
  end

  def test_rejects_push_helper_retry_authorization
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      '"receiptAuthorizesRetry" => false',
      '"receiptAuthorizesRetry" => true'
    )

    assert_contract_failure(
      "signed-tag push helper must durably retire the tag before its one compare-and-swap " \
      "push, never manually dispatch or rerun, and never authorize retry or resume"
    )
  end

  def test_rejects_push_helper_weak_run_correlation
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      "    abort(\"release run head ref mismatch\") unless run[\"head_branch\"] == tag\n" \
      "    abort(\"release run head SHA mismatch\") unless run[\"head_sha\"] == commit",
      "    abort(\"release run head ref mismatch\") unless run[\"head_branch\"] == tag\n" \
      "    abort(\"release run head SHA mismatch\") unless run[\"head_sha\"].is_a?(String)"
    )

    assert_contract_failure(
      "signed-tag push helper must correlate exactly one first-attempt push-triggered Release " \
      "run to the exact actor, repository, workflow, tag, commit, time, and URL"
    )
  end

  def test_rejects_push_helper_without_numeric_actor_binding
    mutate_support_script(
      "push-and-dispatch-signed-release-tag.sh",
      'run.dig("actor", "id") == signed_actor["id"]',
      'run.dig("actor", "login").is_a?(String)'
    )

    assert_contract_failure(
      "release governance, tag push, and run evidence must use one recorded authenticated " \
      "actor while keeping tokens out of the signer and clean-shell argv"
    )
  end

  private

  def release_workflow_path
    File.join(@fixture_root, ".github/workflows/release.yml")
  end

  def mutate_release_workflow(needle, replacement)
    original = File.binread(release_workflow_path)
    assert_includes original, needle, "release workflow mutation marker is stale"
    updated = original.sub(needle, replacement)
    refute_equal original, updated
    File.binwrite(release_workflow_path, updated)
  end

  def mutate_all_release_workflow(needle, replacement)
    original = File.binread(release_workflow_path)
    occurrences = original.scan(needle).length
    assert_operator occurrences, :>, 0, "release workflow mutation marker is stale"
    updated = original.gsub(needle, replacement)
    refute_equal original, updated
    File.binwrite(release_workflow_path, updated)
  end

  def mutate_support_script(script, needle, replacement)
    path = File.join(@fixture_root, "scripts", script)
    original = File.binread(path)
    assert_includes original, needle, "#{script} mutation marker is stale"
    updated = original.sub(needle, replacement)
    refute_equal original, updated
    File.binwrite(path, updated)
  end

  def assert_contract_failure(diagnostic)
    _stdout, stderr, status = Open3.capture3(
      { "VIFTY_WORKFLOW_CONTRACT_ROOT" => @fixture_root },
      "/usr/bin/ruby",
      CHECKER
    )

    refute status.success?, "mutated workflow unexpectedly passed the contract"
    assert_includes stderr, "error: #{diagnostic}", stderr
  end
end
