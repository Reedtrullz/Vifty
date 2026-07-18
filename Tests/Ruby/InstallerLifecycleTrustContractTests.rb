# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"

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

  def lifecycle_function(name)
    bash_function(lifecycle, name)
  end

  def installer_function(name)
    bash_function(installer, name)
  end

  def bash_function(source, name)
    start = source.index("#{name}() {")
    refute_nil start, "missing #{name}"
    finish = source.index("\n}\n", start)
    refute_nil finish, "unterminated #{name}"
    source[start..(finish + 2)]
  end

  def assert_ordered(source, *needles)
    positions = needles.map do |needle|
      position = source.index(needle)
      refute_nil position, "missing ordered contract fragment: #{needle}"
      position
    end
    assert_equal positions.sort, positions, "contract fragments are out of order"
  end

  def run_installer(*arguments, environment: {})
    clean_environment = {
      "HOME" => Dir.home,
      "LANG" => "C",
      "LC_ALL" => "C",
      "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin"
    }.merge(environment)
    Open3.capture3(
      clean_environment,
      "/bin/bash",
      File.join(ROOT, "scripts/install-vifty.sh"),
      *arguments,
      unsetenv_others: true
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

  def test_public_archive_mode_selects_only_the_manifest_published_release
    contract = installer_function("load_public_release_contract")

    assert_includes contract, 'manifest.fetch("publishedRelease")'
    refute_includes contract, 'manifest.fetch("candidate")'
    refute_includes contract, 'manifest.fetch("historicalReleases")'
    assert_includes contract, '${public_artifact_trust}" == "passed"'
    assert_includes contract, '${public_signing_trust}" == "developer-id-notarized"'
    assert_includes contract, '${public_tag_trust}" == "signed-verified"'
    assert_includes contract, '${PUBLIC_RELEASE_SHA256}" =~ ^[0-9a-f]{64}$'
  end

  def test_public_archive_verifier_and_evidence_validator_are_fixed_and_have_no_skip_lane
    prepare = installer_function("prepare_public_release_candidate")
    verifier_start = prepare.index(
      'system_tool_environment /bin/bash "${ROOT_DIR}/scripts/verify-release-artifact.sh"'
    )
    validator_start = prepare.index(
      'system_tool_environment /usr/bin/ruby "${ROOT_DIR}/scripts/lib/release_artifact_contract.rb"'
    )
    refute_nil verifier_start
    refute_nil validator_start
    assert_operator verifier_start, :<, validator_start

    verifier = prepare[verifier_start...validator_start]
    assert_includes verifier, '--artifact "${staged_archive}"'
    assert_includes verifier, '--release-version "${PUBLIC_RELEASE_VERSION}"'
    assert_includes verifier, '--summary "${summary}"'
    refute_match(/--(?:skip|team-id|expected-sha|artifact-sha|manifest|tag|source)/, verifier)
    refute_match(/VIFTY_[A-Z0-9_]*(?:VERIFIER|SKIP|TEAM|SHA)/, verifier)

    validator = prepare[validator_start..]
    assert_includes validator, "validate-published-install-summary"
    assert_includes validator, '"${ROOT_DIR}/.github/release-manifest.json"'
    assert_includes validator, '"${ROOT_DIR}"'

    sanitized_environment = installer_function("system_tool_environment")
    assert_includes sanitized_environment, "/usr/bin/env -i"
    assert_includes sanitized_environment, "PATH=/usr/bin:/bin:/usr/sbin:/sbin"
    assert_includes sanitized_environment, "GIT_NO_REPLACE_OBJECTS=1"
  end

  def test_installer_checkout_root_does_not_depend_on_caller_path_tools
    assert installer.start_with?("#!/bin/bash -p\nset -euo pipefail\n\nPATH=/usr/bin:/bin:/usr/sbin:/sbin\nexport PATH\n")
    assert_includes installer,
      'SCRIPT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")" && /bin/pwd -P)"'
    assert_includes installer,
      'ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && /bin/pwd -P)"'
    refute_match(/SCRIPT_DIR=.*\$\(dirname /, installer)
  end

  def test_public_install_lock_is_destination_global_and_not_keyed_by_home_or_path_spelling
    lock = installer_function("acquire_public_install_lock")

    assert_includes lock, 'File.realpath(destination_parent) == destination_parent'
    assert_includes lock, 'File.join(destination_parent, ".vifty-public-install.lock")'
    assert_includes lock, "Dir.mkdir(lock, 0700)"
    refute_includes lock, "HOME"
    refute_includes lock, "Application Support"
  end

  def test_public_archive_quarantine_is_bounded_and_propagated_without_blanket_clearing
    read = installer_function("read_public_quarantine_state")
    capture = installer_function("capture_public_archive_quarantine")
    apply = installer_function("apply_public_archive_quarantine")
    verify = installer_function("verify_public_quarantine_state")
    prepare = installer_function("prepare_public_release_candidate")
    bundle = installer_function("verify_public_release_bundle")
    copy = installer_function("copy_app_bundle")

    assert_includes read, '/usr/bin/xattr -px com.apple.quarantine "${path}"'
    assert_includes read, '${#hex} -le 8192'
    assert_includes read, '${#hex} % 2'
    assert_includes read, '"${hex}" =~ ^[0-9a-f]+$'
    assert_includes capture, 'PUBLIC_QUARANTINE_STATE="$(read_public_quarantine_state'
    assert_includes apply,
      '/usr/bin/xattr -wx com.apple.quarantine "${PUBLIC_QUARANTINE_HEX}" "${path}"'
    assert_includes verify, '"${actual}" == "${PUBLIC_QUARANTINE_STATE}"'
    assert_ordered(
      prepare,
      "capture_public_archive_quarantine || return 1",
      'release-candidate-inventory.rb" stage-public',
      'read_public_quarantine_state "${PUBLIC_RELEASE_ARCHIVE}"',
      'apply_public_archive_quarantine "${staged_archive}"',
      'verify_public_quarantine_state "${staged_archive}"',
      'release-candidate-inventory.rb" extract-public',
      'apply_public_archive_quarantine "${extract_dir}/${APP_NAME}.app"',
      'verify_public_quarantine_state "${extract_dir}/${APP_NAME}.app"',
      'verify-release-artifact.sh"'
    )
    assert_includes bundle, 'verify_public_quarantine_state "${app}"'
    assert_includes copy,
      '"${DITTO_COMMAND}" --rsrc --extattr --acl "${source_app}" "${staged_app}"'
    public_branch = copy[
      copy.index('if [[ "${INSTALL_MODE}" == "public-release" ]]')...
      copy.index("else", copy.index('if [[ "${INSTALL_MODE}" == "public-release" ]]'))
    ]
    refute_includes public_branch, "xattr -cr"
    refute_includes public_branch, "--noextattr"
    refute_includes public_branch, "--noqtn"
  end

  def test_public_release_floor_requires_root_snapshot_binding_generation
    contract = installer_function("load_public_release_contract")

    assert_includes contract, '(parts.map(&:to_i) <=> [1, 4, 0]) >= 0'
    assert_includes contract,
      "safe public-archive replacement requires a published Vifty v1.4.0 or newer bundle carrying the root snapshot binding contract"
  end

  def test_public_fresh_install_binds_absence_and_rejects_orphan_helper_authority
    preflight = installer_function("preflight_existing_install_before_replacement")
    copy = installer_function("copy_app_bundle")

    assert_ordered(
      preflight,
      'if ! path_exists_without_following "${DEST_APP}"',
      'path_exists_without_following "${HELPER_TARGET}"',
      'path_exists_without_following "${daemon_plist_target}"',
      '/bin/launchctl print "system/${DAEMON_BUNDLE_ID}"',
      'PUBLIC_DESTINATION_EXPECTATION="absent"'
    )
    assert_includes preflight, 'PUBLIC_DESTINATION_EXPECTATION="present"'
    assert_includes copy, 'absent) ! path_exists_without_following "${dest_app}" || return 1'
    assert_includes copy, 'present) path_exists_without_following "${dest_app}" || return 1'
    assert_ordered(
      copy,
      '"${PUBLIC_DESTINATION_EXPECTATION}" == "absent"',
      "COPY_ROLLBACK_HAD_PREVIOUS=0",
      'rename_exclusive "${staged_app}" "${dest_app}"',
      "COPY_ROLLBACK_NEW_INSTALLED=1"
    )
    assert_includes copy, 'rename_exclusive "${staged_app}" "${dest_app}"'
    rollback = installer_function("rollback_interrupted_copy")
    assert_includes rollback, '"${COPY_ROLLBACK_NEW_INSTALLED}" == "1"'
    assert_ordered(
      rollback,
      'rename_exclusive "${COPY_ROLLBACK_DEST}" "${rejected_app}"',
      'verify_candidate_bundle "${rejected_app}"',
      'bundles_have_identical_file_bytes "${COPY_ROLLBACK_SOURCE}" "${rejected_app}"',
      'unexpected destination bundle is preserved at ${rejected_app}',
      '/bin/rm -rf "${rejected_app}"'
    )
  end

  def test_public_mode_never_falls_back_or_retries_after_destination_selection
    driver = installer[installer.index('if ! /bin/mkdir -p "${INSTALL_DIR}"')..]

    assert_includes driver,
      'the existing public-release destination ${DEST_APP} cannot be replaced in place; refusing to create a second installation'
    assert_includes driver,
      'verified public-release replacement failed; refusing a second destination, fallback, or retry'
    assert_ordered(
      driver,
      'if [[ "${INSTALL_MODE}" == "public-release" ]] && path_exists_without_following "${DEST_APP}"',
      "fallback_to_user_applications",
      "if [[ \"${INSTALL_MODE}\" == \"public-release\" ]]; then\n    /bin/cat \"${ERR_LOG}\"",
      'refusing a second destination, fallback, or retry'
    )
  end

  def test_public_execution_uses_privileged_shell_fixed_path_and_absolute_tools
    assert installer.start_with?("#!/bin/bash -p")
    assert_includes installer, "PATH=/usr/bin:/bin:/usr/sbin:/sbin\nexport PATH"
    assert_includes installer, "/bin/sleep 0.2"
    assert_includes installer, '/usr/bin/sed "s/'
    refute_match(/^\s*sleep\s/m, installer)
    refute_match(/\|\s*sed\s/, installer)
  end

  def test_archive_sha_and_tree_binding_are_checked_before_bundle_identity_verification
    prepare = installer_function("prepare_public_release_candidate")

    assert_includes prepare,
      'system_tool_environment /usr/bin/ruby "${ROOT_DIR}/scripts/release-candidate-inventory.rb" stage-public'
    assert_includes prepare,
      'system_tool_environment /usr/bin/ruby "${ROOT_DIR}/scripts/release-candidate-inventory.rb" extract-public'
    assert_operator prepare.scan('--expected-sha "${PUBLIC_RELEASE_SHA256}"').length, :>=, 2

    assert_ordered(
      prepare,
      "load_public_release_contract || return 1",
      "verify_public_release_tag ||",
      'release-candidate-inventory.rb" stage-public',
      'release-candidate-inventory.rb" extract-public',
      'verify-release-artifact.sh"',
      "validate-published-install-summary",
      'PUBLIC_HELPER_SHA256="$(sha256_file',
      'verify_public_release_bundle "${APP_DIR}"'
    )

    bundle_verifier = installer_function("verify_public_release_bundle")
    assert_ordered(
      bundle_verifier,
      "verify-public-tree",
      "verify_install_bundle",
      "CFBundleShortVersionString",
      "public_release_component_matches",
      "/usr/bin/xcrun stapler validate",
      "/usr/sbin/spctl --assess"
    )
    assert_includes bundle_verifier,
      '--expected-content-manifest-sha256 "${PUBLIC_CONTENT_MANIFEST_SHA256}"'
    assert_includes bundle_verifier,
      '/usr/libexec/PlistBuddy -c "Print :MachServices:${DAEMON_BUNDLE_ID}"'
    refute_includes bundle_verifier,
      'plist_raw_value "${daemon_plist}" MachServices.${DAEMON_BUNDLE_ID}'
  end

  def test_public_candidate_is_verified_before_quit_preflight_freeze_copy_and_finish
    driver_start = installer.index('ADHOC_UID="$(/usr/bin/id -u)"')
    refute_nil driver_start
    driver = installer[driver_start..]

    assert_ordered(
      driver,
      "prepare_public_release_candidate || exit 75",
      "public_release_is_not_a_downgrade ||",
      'if ! verify_candidate_bundle "${APP_DIR}"',
      "quit_running_app_if_needed",
      "preflight_existing_install_before_replacement",
      "prepare_replacement_authority_freeze",
      'copy_app_bundle "${APP_DIR}" "${DEST_APP}"',
      "complete_replacement_after_successful_copy"
    )
  end

  def test_public_release_downgrade_check_authenticates_before_reading_version
    downgrade = installer_function("public_release_is_not_a_downgrade")

    assert_ordered(
      downgrade,
      "existing_developer_id_source_is_authenticated || return 0",
      "CFBundleShortVersionString",
      "CFBundleVersion",
      "parse = lambda",
      "comparison = installed <=> candidate"
    )
    assert_includes downgrade,
      "comparison.negative? || (comparison.zero? && installed_build.to_i <= candidate_build.to_i)"
    assert_includes downgrade,
      '"${installed_version}" "${installed_build}" "${PUBLIC_RELEASE_VERSION}" "${PUBLIC_RELEASE_BUILD}"'
  end

  def test_public_release_tag_requires_annotated_signature_and_first_parent_signer_continuity
    tag = installer_function("verify_public_release_tag")

    assert_ordered(
      tag,
      'rev-parse --verify "refs/tags/${PUBLIC_RELEASE_TAG}^{tag}"',
      'rev-parse --verify "refs/tags/${PUBLIC_RELEASE_TAG}^{commit}"',
      '"${tag_commit}" == "${PUBLIC_RELEASE_SOURCE_COMMIT}"',
      'cat-file tag "${tag_object}"',
      'tag_headers == ["tag #{expected}"]',
      'rev-parse --verify "${tag_commit}^"',
      'show "${tag_commit}:.github/release-signers.allowed"',
      'show "${parent_commit}:.github/release-signers.allowed"',
      '/usr/bin/cmp -s "${current_signers}" "${tagged_signers}"',
      '/usr/bin/cmp -s "${tagged_signers}" "${parent_signers}"',
      "-c gpg.format=ssh",
      "-c gpg.ssh.program=/usr/bin/ssh-keygen",
      'verify-tag "${tag_object}"'
    )
    assert_operator tag.scan("system_tool_environment /usr/bin/git").length, :>=, 7
    refute_match(/git\s+verify-tag\s+"\$\{PUBLIC_RELEASE_TAG\}"/, tag)
  end

  def test_privileged_snapshot_binds_the_verified_public_candidate_contract
    prepare = installer_function("prepare_replacement_authority_freeze")
    %w[
      --replacement-public-content-manifest-sha256
      --replacement-public-previous-content-manifest-sha256
      --replacement-public-version
      --replacement-public-build
      --replacement-public-team-id
      --replacement-public-archive-sha256
    ].each { |option| assert_includes prepare, option }
    assert_includes prepare, '${PUBLIC_CONTENT_MANIFEST_SHA256}'
    assert_includes prepare, '${PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256}'
    assert_includes prepare, '${PUBLIC_RELEASE_VERSION}'
    assert_includes prepare, '${PUBLIC_RELEASE_BUILD}'
    assert_includes prepare, '${PUBLIC_RELEASE_TEAM_ID}'
    assert_includes prepare, '${PUBLIC_RELEASE_SHA256}'

    bind = lifecycle_function("bind_replacement_public_candidate_snapshot")
    assert_includes bind, 'binding["contentManifestSHA256"] == content_sha'
    assert_includes bind, "content_sha == expected_content_sha"
    assert_includes bind, 'identity["bundleVersion"] == expected_version'
    assert_includes bind, 'identity["bundleBuild"] == expected_build'
    assert_includes bind, 'identity["kind"] == "developer-id"'
    assert_includes bind, 'identity["teamID"] == expected_team'

    snapshot = lifecycle_function("stage_replacement_candidate_snapshot")
    assert_ordered(
      snapshot,
      'snapshot_binding="$(capture_bundle_binding',
      'bind_replacement_public_candidate_snapshot "${snapshot_binding}"',
      'REPLACEMENT_CANDIDATE_BINDING="${snapshot_binding}"',
      "force_lock_replacement_tree"
    )
    assert_includes lifecycle,
      'payload["replacementPublicCandidateExpectation"] = JSON.parse(public_candidate_expectation_json)'
    assert_includes lifecycle,
      'candidate["contentManifestSHA256"] == public_expectation["contentManifestSHA256"]'
    previous = lifecycle_function("bind_replacement_public_previous_snapshot")
    assert_includes previous, 'content_sha == expected_sha'
    assert_includes previous, 'expectation["previousContentManifestSHA256"] = content_sha'
    copy = installer_function("copy_app_bundle")
    assert_ordered(
      copy,
      'rename_exclusive "${dest_app}" "${previous_app}"',
      'verify-public-tree',
      '--app "${previous_app}"',
      '--expected-content-manifest-sha256 "${PUBLIC_PREVIOUS_CONTENT_MANIFEST_SHA256}"',
      'rename_exclusive "${staged_app}" "${dest_app}"'
    )
  end

  def test_public_archive_cli_rejects_incomplete_unknown_and_relative_inputs_before_install_work
    cases = [
      [["--public-release-archive"], 64, "unsupported or incomplete installer arguments"],
      [["--not-an-installer-option", "/tmp/Vifty-v1.4.0.zip"], 64, "expected --public-release-archive"],
      [["--public-release-archive", "Vifty-v1.4.0.zip"], 64, "requires an absolute path"]
    ]

    cases.each do |arguments, expected_status, expected_error|
      stdout, stderr, status = run_installer(*arguments)
      assert_equal expected_status, status.exitstatus, "stdout=#{stdout}\nstderr=#{stderr}"
      assert_includes stderr, expected_error
      refute_includes stdout, "Building Vifty.app"
      refute_includes stdout, "Installing to"
    end
  end

  def test_public_archive_cli_rejects_debug_adhoc_and_tool_override_configuration
    archive = "/tmp/Vifty-v1.4.0.zip"
    cases = [
      [{ "CONFIGURATION" => "debug" }, "CONFIGURATION=release"],
      [{ "VIFTY_ENABLE_ADHOC_XPC" => "1" }, "VIFTY_ENABLE_ADHOC_XPC=0"],
      [{ "VIFTY_MAKE" => "/bin/true" }, "reject build, helper, copy-tool, lifecycle, and fixture overrides"],
      [{ "VIFTY_HELPER_TARGET" => "/tmp/not-the-helper" }, "reject build, helper, copy-tool, lifecycle, and fixture overrides"]
    ]

    cases.each do |environment, expected_error|
      stdout, stderr, status = run_installer(
        "--public-release-archive",
        archive,
        environment: environment
      )
      assert_equal 65, status.exitstatus, "stdout=#{stdout}\nstderr=#{stderr}"
      assert_includes stderr, expected_error
      refute_includes stdout, "Building Vifty.app"
      refute_includes stdout, "Installing to"
    end
  end
end
