# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "shellwords"
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

  def test_rejects_unsupported_ruleset_pattern_matching_in_governance_checker
    mutate_support_script(
      "check-release-governance.sh",
      "File.fnmatch?(pattern, full_ref, File::FNM_PATHNAME)",
      "File.fnmatch?(pattern, full_ref, File::FNM_PATHNAME | File::FNM_EXTGLOB)"
    )

    assert_contract_failure(
      "administrator governance checker must bind exact-main, exact-ref pre-tag absence or " \
      "exact-object post-tag presence, committed-tool, no-bypass ruleset, and anti-shadow secret evidence"
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

  def test_created_draft_response_captures_repository_scoped_immutable_id_before_marker_validation
    code = release_inline_ruby(
      "capture_created_release_id()",
      "capture_owned_draft_release_id()"
    )
    response = {
      "id" => 356_237_268,
      "url" => "https://api.github.com/repos/Reedtrullz/Vifty/releases/356237268",
      "assets_url" => "https://api.github.com/repos/Reedtrullz/Vifty/releases/356237268/assets",
      "upload_url" => "https://uploads.github.com/repos/Reedtrullz/Vifty/releases/356237268/assets{?name,label}",
      "tag_name" => "v1.4.2",
      "draft" => true,
      "prerelease" => false,
      "assets" => []
    }

    path = write_json_fixture("created-draft.json", response)
    stdout, stderr, status = Open3.capture3(
      "/usr/bin/ruby", "-rjson", "-e", code,
      path, "Reedtrullz/Vifty", "v1.4.2"
    )

    assert_predicate status, :success?, stderr
    assert_equal "356237268", stdout

    response["draft"] = false
    response["prerelease"] = true
    response["assets"] = [{ "id" => 1 }]
    response["name"] = "unexpected mutable state"
    path = write_json_fixture("anomalous-created-release.json", response)
    stdout, stderr, status = Open3.capture3(
      "/usr/bin/ruby", "-rjson", "-e", code,
      path, "Reedtrullz/Vifty", "v1.4.2"
    )

    assert_predicate status, :success?, stderr
    assert_equal "356237268", stdout,
      "repository-scoped immutable ID retention must not depend on mutable publication state"

    response["url"] = "https://api.github.com/repos/other/repository/releases/356237268"
    path = write_json_fixture("wrong-repository-draft.json", response)
    _stdout, stderr, status = Open3.capture3(
      "/usr/bin/ruby", "-rjson", "-e", code,
      path, "Reedtrullz/Vifty", "v1.4.2"
    )

    refute_predicate status, :success?
    assert_includes stderr, "repository-scoped ID/tag identity"
  end

  def test_owned_draft_marker_count_is_literal_exact_and_single
    code = release_inline_ruby(
      "capture_owned_draft_release_id()",
      "discover_owned_release_by_tag_for_containment()"
    )
    marker = "<!-- vifty-release-owner:29668876169:1:b5627041 -->"
    title = "Vifty 1.4.2 [draft b5627041]"
    response = {
      "id" => 356_237_268,
      "tag_name" => "v1.4.2",
      "draft" => true,
      "name" => title,
      "body" => "release checklist\n\n#{marker}\n",
      "assets" => []
    }

    assert_equal 1, response.fetch("body").scan(marker).length
    assert_equal 0, response.fetch("body").scan(Regexp.escape(marker)).length,
      "escaped String scan must reproduce the retired v1.4.1 validator bug"

    path = write_json_fixture("owned-draft.json", response)
    stdout, stderr, status = Open3.capture3(
      "/usr/bin/ruby", "-rjson", "-e", code,
      path, "v1.4.2", title, marker
    )
    assert_predicate status, :success?, stderr
    assert_equal "356237268", stdout

    response["body"] = "#{marker}\n#{marker}\n"
    path = write_json_fixture("duplicate-marker-draft.json", response)
    _stdout, _stderr, status = Open3.capture3(
      "/usr/bin/ruby", "-rjson", "-e", code,
      path, "v1.4.2", title, marker
    )
    refute_predicate status, :success?

    response["body"] = "prefix #{marker} suffix\n"
    path = write_json_fixture("inline-marker-draft.json", response)
    _stdout, _stderr, status = Open3.capture3(
      "/usr/bin/ruby", "-rjson", "-e", code,
      path, "v1.4.2", title, marker
    )
    refute_predicate status, :success?
  end

  def test_post_creation_release_discovery_retries_empty_then_visible_and_fails_closed_on_persistent_absence
    function = release_shell_function(
      "wait_for_owned_release_by_tag_for_containment()",
      "verify_release_state()"
    )
    destination = File.join(@fixture_root, "discovered-draft.json")
    retry_script = <<~BASH
      set -euo pipefail
      RELEASE_TAG=v1.4.2
      attempts=0
      discover_owned_release_by_tag_for_containment() {
        attempts=$((attempts + 1))
        if [[ "${attempts}" -eq 1 ]]; then
          return 3
        fi
        printf '{}\n' > "$1"
        return 0
      }
      #{function}
      wait_for_owned_release_by_tag_for_containment #{Shellwords.escape(destination)}
      test "${attempts}" -eq 2
    BASH
    _stdout, stderr, status = Open3.capture3("/bin/bash", "-c", retry_script)
    assert_predicate status, :success?, stderr

    absence_script = <<~BASH
      set -euo pipefail
      RELEASE_TAG=v1.4.2
      discover_owned_release_by_tag_for_containment() {
        SECONDS="${deadline}"
        return 3
      }
      #{function}
      if wait_for_owned_release_by_tag_for_containment #{Shellwords.escape(destination)}; then
        exit 99
      fi
    BASH
    _stdout, stderr, status = Open3.capture3("/bin/bash", "-c", absence_script)
    assert_predicate status, :success?, stderr
    assert_includes stderr, "could not prove post-creation absence or exact marker ownership"
  end

  def test_containment_retries_owned_id_before_patch_and_never_patches_unproved_ownership
    ownership_wait = release_shell_function(
      "wait_for_release_owned_for_containment()",
      "wait_for_release_contained_by_id()"
    )
    containment = release_shell_function(
      "contain_release_by_id()",
      "containment_guard()"
    )
    runner_temp = Shellwords.escape(@fixture_root)

    success_script = <<~BASH
      set -euo pipefail
      RUNNER_TEMP=#{runner_temp}
      RELEASE_ID=356237268
      RELEASE_TAG=v1.4.2
      GITHUB_REPOSITORY=Reedtrullz/Vifty
      query_attempts=0
      patch_attempts=0
      query_release_by_id_for_convergence() {
        query_attempts=$((query_attempts + 1))
        if [[ "${query_attempts}" -eq 1 ]]; then
          return 75
        fi
        printf '{}\n' > "$2"
      }
      verify_release_owned_for_containment() { return 0; }
      release_gh() { patch_attempts=$((patch_attempts + 1)); printf '{}\n'; }
      wait_for_release_contained_by_id() { printf '{}\n' > "$1"; }
      verify_release_contained() { return 0; }
      wait_for_owned_release_by_tag_for_containment() { return 1; }
      capture_created_release_id() { return 1; }
      #{ownership_wait}
      #{containment}
      contain_release_by_id
      test "${query_attempts}" -eq 2
      test "${patch_attempts}" -eq 1
    BASH
    _stdout, stderr, status = Open3.capture3("/bin/bash", "-c", success_script)
    assert_predicate status, :success?, stderr

    persistent_script = <<~BASH
      set -euo pipefail
      RUNNER_TEMP=#{runner_temp}
      RELEASE_ID=356237268
      RELEASE_TAG=v1.4.2
      GITHUB_REPOSITORY=Reedtrullz/Vifty
      patch_attempts=0
      query_release_by_id_for_convergence() { SECONDS="${deadline}"; return 75; }
      verify_release_owned_for_containment() { return 0; }
      release_gh() { patch_attempts=$((patch_attempts + 1)); printf '{}\n'; }
      wait_for_release_contained_by_id() { return 0; }
      verify_release_contained() { return 0; }
      wait_for_owned_release_by_tag_for_containment() { return 1; }
      capture_created_release_id() { return 1; }
      #{ownership_wait}
      #{containment}
      if contain_release_by_id; then
        exit 99
      fi
      test "${patch_attempts}" -eq 0
    BASH
    _stdout, stderr, status = Open3.capture3("/bin/bash", "-c", persistent_script)
    assert_predicate status, :success?, stderr
    assert_includes stderr, "no mutation was attempted"

    mismatch_script = <<~BASH
      set -euo pipefail
      RUNNER_TEMP=#{runner_temp}
      RELEASE_ID=356237268
      RELEASE_TAG=v1.4.2
      GITHUB_REPOSITORY=Reedtrullz/Vifty
      patch_attempts=0
      query_release_by_id_for_convergence() { printf '{}\n' > "$2"; }
      verify_release_owned_for_containment() { return 1; }
      release_gh() { patch_attempts=$((patch_attempts + 1)); printf '{}\n'; }
      wait_for_release_contained_by_id() { return 0; }
      verify_release_contained() { return 0; }
      wait_for_owned_release_by_tag_for_containment() { return 1; }
      capture_created_release_id() { return 1; }
      #{ownership_wait}
      #{containment}
      if contain_release_by_id; then
        exit 99
      fi
      test "${patch_attempts}" -eq 0
    BASH
    _stdout, stderr, status = Open3.capture3("/bin/bash", "-c", mismatch_script)
    assert_predicate status, :success?, stderr
    assert_includes stderr, "changed immutable ID, tag, title, or ownership marker"
  end

  def test_ambiguous_creation_with_retained_id_enters_containment_without_state_poll
    creation_state = release_shell_function(
      'CREATED_STATE="${RUNNER_TEMP}/vifty-release-created-state.json"',
      'if ! upload_release_asset_by_id "${ZIP_PATH}"'
    )
    contained_path = File.join(@fixture_root, "creation-contained")
    wait_called_path = File.join(@fixture_root, "creation-wait-called")
    verify_called_path = File.join(@fixture_root, "creation-verify-called")
    script = <<~BASH
      set -uo pipefail
      RUNNER_TEMP=#{Shellwords.escape(@fixture_root)}
      CREATE_STATUS=0
      CREATE_RESPONSE_STATUS=1
      CREATE_QUERY_STATUS=99
      RELEASE_ID=356237268
      DRAFT_TITLE='Vifty 1.4.2 [draft nonce]'
      EXPECTED_BODY_PATH=#{Shellwords.escape(File.join(@fixture_root, "missing-body"))}
      EXPECTED_ASSETS_PATH=#{Shellwords.escape(File.join(@fixture_root, "expected-assets"))}
      containment_guard() { printf 'contained\n' > #{Shellwords.escape(contained_path)}; }
      wait_for_release_state_by_id() {
        printf 'called\n' > #{Shellwords.escape(wait_called_path)}
        return 0
      }
      verify_release_state() {
        printf 'called\n' > #{Shellwords.escape(verify_called_path)}
        return 0
      }
      trap containment_guard EXIT
      #{creation_state}
      exit 99
    BASH

    _stdout, stderr, status = Open3.capture3("/bin/bash", "-c", script)

    refute_predicate status, :success?
    assert_equal "contained\n", File.binread(contained_path), stderr
    refute File.exist?(wait_called_path), "creation convergence poll unexpectedly ran"
    refute File.exist?(verify_called_path), "creation state verification unexpectedly ran"
  end

  def test_rejects_escaped_string_marker_scan_regression
    mutate_all_release_workflow(
      "body.scan(marker).length == 1",
      "body.scan(Regexp.escape(marker)).length == 1"
    )

    assert_contract_failure(
      "publish may discover an ambiguous draft by tag only with exact immutable-ID/tag/draft/title/marker ownership proof"
    )
  end

  def test_rejects_clearing_captured_release_id_after_marker_validation_failure
    mutate_release_workflow(
      "              fi\n            fi\n          fi\n\n          CREATED_STATE=",
      "              fi\n            else\n              RELEASE_ID=\"\"\n            fi\n          fi\n\n          CREATED_STATE="
    )

    assert_contract_failure(
      "publish must REST-create the marked draft, capture its immutable ID directly, and forbid " \
      "tag-based release mutation"
    )
  end

  def test_rejects_coupling_immutable_release_id_retention_to_mutable_draft_state
    mutate_release_workflow(
      'release["tag_name"] == tag',
      'release["tag_name"] == tag && release["draft"] == true'
    )

    assert_contract_failure(
      "publish must retain the repository-scoped created release ID independently of mutable " \
      "draft, publication, asset, title, or body state"
    )
  end

  def test_rejects_single_by_id_read_before_containment_patch
    mutate_release_workflow(
      'wait_for_release_owned_for_containment "${ownership_state}" "${RELEASE_ID}"',
      'query_release_by_id "${RELEASE_ID}" "${ownership_state}" && ' \
      'verify_release_owned_for_containment "${ownership_state}" "${RELEASE_ID}"'
    )

    assert_contract_failure(
      "publish containment must prove owned immutable-ID state with bounded GET-only retries " \
      "before its single re-draft mutation"
    )
  end

  def test_rejects_creation_state_poll_guarded_only_by_retained_id
    mutate_release_workflow(
      "if [[ \"${CREATE_STATUS}\" -eq 0 ]] && \\\n" \
      "             [[ \"${CREATE_RESPONSE_STATUS}\" -eq 0 ]] && \\\n" \
      "             [[ -n \"${RELEASE_ID}\" ]]; then",
      'if [[ -n "${RELEASE_ID}" ]]; then'
    )

    assert_contract_failure(
      "publish must enter containment immediately after ambiguous creation instead of polling " \
      "state without a validated direct response body"
    )
  end

  def test_rejects_single_empty_release_list_as_post_creation_containment_proof
    mutate_release_workflow(
      'wait_for_owned_release_by_tag_for_containment "${discovered_state}"',
      'discover_owned_release_by_tag_for_containment "${discovered_state}"'
    )

    assert_contract_failure(
      "publish must re-draft by immutable release ID on every ambiguous failure and hard-fail " \
      "unless containment readback succeeds"
    )
  end

  def test_rejects_losing_discovery_exit_status_after_failed_if_condition
    mutate_release_workflow(
      "              else\n                discovery_status=$?\n              fi",
      "              fi\n              discovery_status=$?"
    )

    assert_contract_failure(
      "publish must re-draft by immutable release ID on every ambiguous failure and hard-fail " \
      "unless containment readback succeeds"
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
      "          wait_for_release_state_by_id() {\n" \
      "            local destination=\"$1\"\n" \
      "            local release_id=\"$2\"\n" \
      "            local expected_draft=\"$3\"\n" \
      "            local expected_title=\"$4\"\n" \
      "            local expected_body_path=\"$5\"\n" \
      "            local expected_assets_path=\"$6\"\n" \
      "            local deadline=$((SECONDS + 60))",
      "          wait_for_release_state_by_id() {\n" \
      "            local destination=\"$1\"\n" \
      "            local release_id=\"$2\"\n" \
      "            local expected_draft=\"$3\"\n" \
      "            local expected_title=\"$4\"\n" \
      "            local expected_body_path=\"$5\"\n" \
      "            local expected_assets_path=\"$6\"\n" \
      "            local deadline=$((SECONDS + 600))"
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

  def release_inline_ruby(function_name, next_function_name)
    workflow = File.binread(release_workflow_path)
    start_index = workflow.index(function_name)
    refute_nil start_index, "missing #{function_name} in release workflow"
    end_index = workflow.index(next_function_name, start_index + function_name.length)
    refute_nil end_index, "missing #{next_function_name} after #{function_name}"
    function_text = workflow[start_index...end_index]
    match = function_text.match(/ruby -rjson -e '\n(?<code>.*?)\n\s*' "\$\{state_path\}"/m)
    refute_nil match, "could not extract inline Ruby from #{function_name}"
    match[:code]
  end

  def release_shell_function(function_name, next_function_name)
    workflow = File.binread(release_workflow_path)
    start_index = workflow.index(function_name)
    refute_nil start_index, "missing #{function_name} in release workflow"
    end_index = workflow.index(next_function_name, start_index + function_name.length)
    refute_nil end_index, "missing #{next_function_name} after #{function_name}"
    workflow[start_index...end_index]
  end

  def write_json_fixture(name, value)
    path = File.join(@fixture_root, name)
    File.binwrite(path, JSON.generate(value) + "\n")
    path
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
