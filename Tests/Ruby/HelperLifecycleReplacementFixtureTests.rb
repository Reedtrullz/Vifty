# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class HelperLifecycleReplacementFixtureTests < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  TRANSACTION_ID = "11111111-2222-4333-8444-555555555555"

  def setup
    @root = File.realpath(Dir.mktmpdir("vifty-lifecycle-ruby-fixture."))
    @app = File.join(@root, "Vifty.app")
    @log = File.join(@root, "invocations.log")
    @record = File.join(@root, "command-record.json")
    @ledger = File.join(@root, "Library/Application Support/ViftyMaintenanceEvidence/replacement-state-v1.json")
    @staged_lifecycle = File.join(
      @root,
      "Library/Application Support/ViftyMaintenanceEvidence/ReplacementTransactions",
      TRANSACTION_ID,
      "vifty-helper-lifecycle.sh"
    )
    make_app(@app)
    make_launchctl
  end

  def teardown
    system("/usr/bin/chflags", "-R", "nouchg", @root, out: File::NULL, err: File::NULL)
    FileUtils.rm_rf(@root)
  end

  def test_completed_ledger_survives_ordinary_repair_and_uninstall_retires_it
    candidate = File.join(@root, "candidate", "Vifty.app")
    next_candidate = File.join(@root, "next-candidate", "Vifty.app")
    FileUtils.mkdir_p(File.dirname(candidate))
    FileUtils.mkdir_p(File.dirname(next_candidate))
    assert system("/usr/bin/ditto", @app, candidate)
    assert system("/usr/bin/ditto", @app, next_candidate)

    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(candidate)
    )
    assert_equal 0, prepared[:status], prepared[:output]
    assert File.file?(@ledger)
    assert_equal 0o600, File.stat(@ledger).mode & 0o777
    prepared_record = JSON.parse(File.read(@ledger))
    assert_equal "replacement-prepared", prepared_record.fetch("status")
    assert_equal File.join(File.dirname(@staged_lifecycle), "CandidateSnapshot/Vifty.app"),
                 prepared_record.dig("replacementCandidateBinding", "sourcePath")
    assert_equal ".", prepared_record.dig("replacementCandidateBinding", "manifest", 0, "path")

    FileUtils.rm_rf(@app)
    assert system("/usr/bin/ditto", candidate, @app)
    finished = run_lifecycle(
      script: @staged_lifecycle,
      args: replacement_finish_args
    )
    assert_equal 0, finished[:status], finished[:output]
    completed_bytes = File.binread(@ledger)
    assert_equal "completed", JSON.parse(completed_bytes).fetch("status")

    pre_unlock_failure = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: ["--operation", "repair", "--app", @app, "--record", @record],
      extra_env: {"VIFTY_FIXTURE_ADMIN_CANCEL" => "1"}
    )
    assert_equal 75, pre_unlock_failure[:status], pre_unlock_failure[:output]
    assert_equal completed_bytes, File.binread(@ledger)
    assert immutable?(@app)

    repaired = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: ["--operation", "repair", "--app", @app, "--record", @record]
    )
    assert_equal 0, repaired[:status], repaired[:output]
    assert_equal completed_bytes, File.binread(@ledger)

    next_id = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    next_prepare = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(next_candidate, transaction_id: next_id)
    )
    assert_equal 0, next_prepare[:status], next_prepare[:output]
    assert_equal next_id, JSON.parse(File.read(@ledger)).fetch("replacementTransactionID")

    uninstalled = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: ["--operation", "uninstall", "--app", @app, "--record", @record]
    )
    assert_equal 0, uninstalled[:status], uninstalled[:output]
    refute File.exist?(@ledger)
    refute immutable?(@app)
  end

  def test_partial_lock_converges_to_unlocked_prepared_state
    candidate = File.join(@root, "candidate", "Vifty.app")
    FileUtils.mkdir_p(File.dirname(candidate))
    assert system("/usr/bin/ditto", @app, candidate)
    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(candidate)
    )
    assert_equal 0, prepared[:status], prepared[:output]
    FileUtils.rm_rf(@app)
    assert system("/usr/bin/ditto", candidate, @app)

    finished = run_lifecycle(
      script: @staged_lifecycle,
      args: replacement_finish_args,
      extra_env: {"VIFTY_FIXTURE_PARTIAL_LOCK" => "1"}
    )
    assert_equal 75, finished[:status], finished[:output]
    record = JSON.parse(File.read(@ledger))
    assert_equal "replacement-prepared", record.fetch("status")
    refute record.key?("replacementFlagTransition")
    refute immutable?(@app)
  end

  def test_prepare_cancellation_is_uncertain_until_exact_label_is_proven_offline
    cancelled = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(@app),
      extra_env: {"VIFTY_FIXTURE_ADMIN_CANCEL" => "1"}
    )
    assert_equal 76, cancelled[:status], cancelled[:output]
    assert_includes cancelled[:output], "active or unknown"
  end

  def test_root_failure_is_75_only_after_exact_label_is_proven_disabled_and_offline
    failed = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(@app),
      extra_env: {"VIFTY_FIXTURE_ROOT_SIGNAL" => "TERM"}
    )
    assert_equal 75, failed[:status], failed[:output]
    assert_includes failed[:output], "proven disabled and offline"
    refute File.exist?(@ledger)
  end

  def test_partial_unlock_converges_back_to_locked_state
    candidate = File.join(@root, "candidate", "Vifty.app")
    FileUtils.mkdir_p(File.dirname(candidate))
    assert system("/usr/bin/ditto", @app, candidate)
    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(candidate)
    )
    assert_equal 0, prepared[:status], prepared[:output]
    FileUtils.rm_rf(@app)
    assert system("/usr/bin/ditto", candidate, @app)
    failed_finish = run_lifecycle(
      script: @staged_lifecycle,
      args: replacement_finish_args,
      extra_env: {"VIFTY_FIXTURE_REGISTER_FAIL_FROZEN" => "1"}
    )
    assert_equal 75, failed_finish[:status], failed_finish[:output]
    assert immutable?(@app)

    released = run_lifecycle(
      script: @staged_lifecycle,
      args: replacement_release_args,
      extra_env: {"VIFTY_FIXTURE_PARTIAL_UNLOCK" => "1"}
    )
    assert_equal 75, released[:status], released[:output]
    record = JSON.parse(File.read(@ledger))
    assert_equal "replacement-locked", record.fetch("status")
    refute record.key?("replacementFlagTransition")
    assert immutable?(@app)
  end

  def test_post_rename_pre_fsync_ambiguity_converges_from_actual_record_and_flags
    candidate = File.join(@root, "candidate", "Vifty.app")
    FileUtils.mkdir_p(File.dirname(candidate))
    assert system("/usr/bin/ditto", @app, candidate)
    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(candidate)
    )
    assert_equal 0, prepared[:status], prepared[:output]
    FileUtils.rm_rf(@app)
    assert system("/usr/bin/ditto", candidate, @app)

    finished = run_lifecycle(
      script: @staged_lifecycle,
      args: replacement_finish_args,
      extra_env: {"VIFTY_FIXTURE_RECORD_POST_RENAME_FAILURE" => "locking"}
    )
    assert_equal 75, finished[:status], finished[:output]
    record = JSON.parse(File.read(@ledger))
    assert_equal "replacement-prepared", record.fetch("status")
    refute record.key?("replacementFlagTransition")
    refute immutable?(@app)
  end

  def test_next_prepare_recovers_restart_after_lock_before_locked_ledger_update
    candidate = File.join(@root, "candidate", "Vifty.app")
    next_candidate = File.join(@root, "next-candidate", "Vifty.app")
    FileUtils.mkdir_p(File.dirname(candidate))
    FileUtils.mkdir_p(File.dirname(next_candidate))
    assert system("/usr/bin/ditto", @app, candidate)
    assert system("/usr/bin/ditto", @app, next_candidate)
    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(candidate)
    )
    assert_equal 0, prepared[:status], prepared[:output]
    FileUtils.rm_rf(@app)
    assert system("/usr/bin/ditto", candidate, @app)

    interrupted = run_lifecycle(
      script: @staged_lifecycle,
      args: replacement_finish_args,
      extra_env: {"VIFTY_FIXTURE_EXIT_AFTER_LOCK" => "1"}
    )
    assert_equal 75, interrupted[:status], interrupted[:output]
    interrupted_record = JSON.parse(File.read(@ledger))
    assert_equal "replacement-prepared", interrupted_record.fetch("status")
    assert_equal "locking", interrupted_record.dig("replacementFlagTransition", "operation")
    assert immutable?(@app)

    next_id = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
    recovered = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(next_candidate, transaction_id: next_id)
    )
    assert_equal 0, recovered[:status], recovered[:output]
    recovered_record = JSON.parse(File.read(@ledger))
    assert_equal "replacement-prepared", recovered_record.fetch("status")
    assert_equal next_id, recovered_record.fetch("replacementTransactionID")
    refute recovered_record.key?("replacementFlagTransition")
    refute File.exist?(File.dirname(@staged_lifecycle))
    refute immutable?(@app)
  end

  def test_uninstall_recovers_restart_after_unlock_before_released_ledger_update
    candidate = File.join(@root, "candidate", "Vifty.app")
    FileUtils.mkdir_p(File.dirname(candidate))
    assert system("/usr/bin/ditto", @app, candidate)
    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(candidate)
    )
    assert_equal 0, prepared[:status], prepared[:output]
    FileUtils.rm_rf(@app)
    assert system("/usr/bin/ditto", candidate, @app)
    failed_finish = run_lifecycle(
      script: @staged_lifecycle,
      args: replacement_finish_args,
      extra_env: {"VIFTY_FIXTURE_REGISTER_FAIL_FROZEN" => "1"}
    )
    assert_equal 75, failed_finish[:status], failed_finish[:output]
    assert_equal "replacement-locked", JSON.parse(File.read(@ledger)).fetch("status")
    assert immutable?(@app)

    interrupted = run_lifecycle(
      script: @staged_lifecycle,
      args: replacement_release_args,
      extra_env: {"VIFTY_FIXTURE_EXIT_AFTER_UNLOCK" => "1"}
    )
    assert_equal 75, interrupted[:status], interrupted[:output]
    interrupted_record = JSON.parse(File.read(@ledger))
    assert_equal "replacement-locked", interrupted_record.fetch("status")
    assert_equal "unlocking", interrupted_record.dig("replacementFlagTransition", "operation")
    refute immutable?(@app)

    recovered = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: ["--operation", "uninstall", "--app", @app, "--record", @record]
    )
    assert_equal 0, recovered[:status], recovered[:output]
    refute File.exist?(@ledger)
    refute File.exist?(File.dirname(@staged_lifecycle))
    refute immutable?(@app)
  end

  def test_caller_candidate_mutation_after_snapshot_cannot_change_recorded_candidate
    candidate = File.join(@root, "candidate", "Vifty.app")
    FileUtils.mkdir_p(File.dirname(candidate))
    assert system("/usr/bin/ditto", @app, candidate)
    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(candidate),
      extra_env: {"VIFTY_FIXTURE_SWAP_CANDIDATE_AFTER_SNAPSHOT" => "1"}
    )
    assert_equal 0, prepared[:status], prepared[:output]
    mutation = "Contents/Resources/post-snapshot-source-mutation"
    assert File.file?(File.join(candidate, mutation))
    refute File.exist?(File.join(File.dirname(@staged_lifecycle), "CandidateSnapshot/Vifty.app", mutation))
    manifest_paths = JSON.parse(File.read(@ledger)).dig("replacementCandidateBinding", "manifest").map { |row| row.fetch("path") }
    refute_includes manifest_paths, mutation
  end

  def test_caller_candidate_mutation_during_snapshot_fails_before_authority_teardown
    candidate = File.join(@root, "candidate", "Vifty.app")
    FileUtils.mkdir_p(File.dirname(candidate))
    assert system("/usr/bin/ditto", @app, candidate)

    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: replacement_prepare_args(candidate),
      extra_env: {"VIFTY_FIXTURE_SWAP_CANDIDATE_DURING_SNAPSHOT" => "1"}
    )

    assert_equal 76, prepared[:status], prepared[:output]
    assert_includes prepared[:output], "active or unknown"
    assert File.file?(File.join(candidate, "Contents/Resources/mid-snapshot-source-mutation"))
    refute File.exist?(@ledger)
    refute File.exist?(File.dirname(@staged_lifecycle))
    refute File.exist?(File.join(@root, "launchctl-disabled"))
  end

  def test_public_candidate_binding_matches_root_snapshot_and_is_preserved_as_evidence
    candidate = File.join(@root, "candidate", "Vifty.app")
    FileUtils.mkdir_p(File.dirname(candidate))
    assert system("/usr/bin/ditto", @app, candidate)
    FileUtils.mkdir_p(File.join(candidate, "A"))
    File.binwrite(File.join(candidate, "A", "child"), "child\n")
    File.binwrite(File.join(candidate, "A.foo"), "sibling\n")
    content_sha = content_manifest_sha256(candidate)
    previous_content_sha = content_manifest_sha256(@app)
    archive_sha = "a" * 64

    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: public_replacement_prepare_args(candidate, content_sha: content_sha, archive_sha: archive_sha)
    )

    assert_equal 0, prepared[:status], prepared[:output]
    record = JSON.parse(File.read(@ledger))
    assert_equal content_sha, record.dig("replacementCandidateBinding", "contentManifestSHA256")
    assert_equal(
      {
        "contentManifestSHA256" => content_sha,
        "previousContentManifestSHA256" => previous_content_sha,
        "version" => "1.4.0",
        "build" => "8",
        "teamID" => "X88J3853S2",
        "reportedArchiveSHA256" => archive_sha
      },
      record.fetch("replacementPublicCandidateExpectation")
    )
    assert File.exist?(File.join(@root, "launchctl-disabled"))

    FileUtils.rm_rf(@app)
    assert system("/usr/bin/ditto", candidate, @app)
    finished = run_lifecycle(script: @staged_lifecycle, args: replacement_finish_args)
    assert_equal 0, finished[:status], finished[:output]
    completed = JSON.parse(File.read(@ledger))
    assert_equal "completed", completed.fetch("status")
    assert_equal archive_sha,
                 completed.dig("replacementPublicCandidateExpectation", "reportedArchiveSHA256")
  end

  def test_public_candidate_content_mismatch_fails_before_helper_teardown
    assert_public_binding_mismatch_before_teardown(content_sha: "f" * 64)
  end

  def test_public_candidate_version_mismatch_fails_before_helper_teardown
    assert_public_binding_mismatch_before_teardown(version: "1.4.1")
  end

  def test_public_candidate_build_mismatch_fails_before_helper_teardown
    assert_public_binding_mismatch_before_teardown(build: "9")
  end

  def test_public_previous_content_mismatch_fails_before_helper_teardown
    assert_public_binding_mismatch_before_teardown(previous_content_sha: "f" * 64)
  end

  def test_public_candidate_binding_requires_complete_release_identity
    candidate = File.join(@root, "candidate", "Vifty.app")
    FileUtils.mkdir_p(File.dirname(candidate))
    assert system("/usr/bin/ditto", @app, candidate)
    args = replacement_prepare_args(candidate) + [
      "--replacement-public-content-manifest-sha256", content_manifest_sha256(candidate)
    ]

    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: args
    )

    assert_equal 64, prepared[:status], prepared[:output]
    assert_includes prepared[:output], "complete candidate/previous content manifests, version, build, and TeamID"
    refute File.exist?(File.join(@root, "launchctl-disabled"))
  end

  def test_finish_and_release_lock_reject_prepare_only_public_binding_arguments
    public_args = [
      "--replacement-public-content-manifest-sha256", "a" * 64,
      "--replacement-public-previous-content-manifest-sha256", "c" * 64,
      "--replacement-public-version", "1.4.0",
      "--replacement-public-build", "8",
      "--replacement-public-team-id", "X88J3853S2",
      "--replacement-public-archive-sha256", "b" * 64
    ]

    [replacement_finish_args, replacement_release_args].each do |base_args|
      result = run_lifecycle(
        script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
        args: base_args + public_args
      )
      assert_equal 64, result[:status], result[:output]
      assert_includes result[:output], "takes bundle identity only from the root prepare record"
    end
    refute File.exist?(File.join(@root, "launchctl-disabled"))
  end

  private

  def assert_public_binding_mismatch_before_teardown(
    content_sha: nil,
    previous_content_sha: nil,
    version: "1.4.0",
    build: "8"
  )
    candidate = File.join(@root, "candidate", "Vifty.app")
    legacy_helper = File.join(@root, "Library/PrivilegedHelperTools/tech.reidar.vifty.daemon")
    FileUtils.mkdir_p(File.dirname(candidate))
    FileUtils.mkdir_p(File.dirname(legacy_helper))
    File.write(legacy_helper, "legacy-helper\n")
    assert system("/usr/bin/ditto", @app, candidate)
    prepared = run_lifecycle(
      script: File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"),
      args: public_replacement_prepare_args(
        candidate,
        content_sha: content_sha || content_manifest_sha256(candidate),
        previous_content_sha: previous_content_sha || content_manifest_sha256(@app),
        version: version,
        build: build
      )
    )

    assert_equal 76, prepared[:status], prepared[:output]
    assert_includes prepared[:output], "active or unknown"
    refute File.exist?(@ledger)
    refute File.exist?(File.join(@root, "launchctl-disabled"))
    assert File.exist?(legacy_helper)
  end

  def public_replacement_prepare_args(
    candidate,
    content_sha: content_manifest_sha256(candidate),
    previous_content_sha: content_manifest_sha256(@app),
    version: "1.4.0",
    build: "8",
    team_id: "X88J3853S2",
    archive_sha: nil
  )
    args = replacement_prepare_args(candidate) + [
      "--replacement-public-content-manifest-sha256", content_sha,
      "--replacement-public-previous-content-manifest-sha256", previous_content_sha,
      "--replacement-public-version", version,
      "--replacement-public-build", build,
      "--replacement-public-team-id", team_id
    ]
    args += ["--replacement-public-archive-sha256", archive_sha] if archive_sha
    args
  end

  def content_manifest_sha256(app)
    root = File.realpath(app)
    entries = [{"path" => ".", "type" => "directory", "mode" => File.lstat(root).mode & 0o7777}]
    walk = nil
    walk = lambda do |directory, prefix|
      Dir.children(directory).sort.each do |name|
        path = File.join(directory, name)
        relative = prefix.empty? ? name : File.join(prefix, name)
        stat = File.lstat(path)
        mode = stat.mode & 0o7777
        if stat.directory? && !stat.symlink?
          entries << {"path" => relative, "type" => "directory", "mode" => mode}
          walk.call(path, relative)
        elsif stat.file? && !stat.symlink?
          entries << {
            "path" => relative,
            "type" => "file",
            "mode" => mode,
            "size" => stat.size,
            "sha256" => Digest::SHA256.file(path).hexdigest
          }
        elsif stat.symlink?
          entries << {
            "path" => relative,
            "type" => "symlink",
            "mode" => mode,
            "linkTarget" => File.readlink(path)
          }
        else
          raise "unsupported fixture entry: #{path}"
        end
      end
    end
    walk.call(root, "")
    entries.sort_by! { |entry| entry.fetch("path").b }
    Digest::SHA256.hexdigest(JSON.generate(entries))
  end

  def replacement_prepare_args(candidate, transaction_id: TRANSACTION_ID)
    lifecycle = File.join(candidate, "Contents/Resources/vifty-helper-lifecycle.sh")
    digest_output, digest_status = Open3.capture2("/usr/bin/shasum", "-a", "256", lifecycle)
    raise "fixture lifecycle hash failed" unless digest_status.success?
    digest = digest_output.split.first
    [
      "--operation", "repair", "--app", @app, "--record", @record,
      "--replacement-phase", "prepare", "--replacement-destination", @app,
      "--replacement-transaction-id", transaction_id,
      "--replacement-candidate", candidate, "--replacement-previous", @app,
      "--replacement-lifecycle-source", lifecycle,
      "--replacement-lifecycle-sha256", digest
    ]
  end

  def replacement_finish_args
    [
      "--operation", "repair", "--app", @app, "--record", @record,
      "--replacement-phase", "finish", "--replacement-destination", @app,
      "--replacement-transaction-id", TRANSACTION_ID,
      "--replacement-result", "installed"
    ]
  end

  def replacement_release_args
    [
      "--operation", "repair", "--app", @app, "--record", @record,
      "--replacement-phase", "release-lock", "--replacement-destination", @app,
      "--replacement-transaction-id", TRANSACTION_ID,
      "--replacement-result", "installed"
    ]
  end

  def run_lifecycle(script:, args:, extra_env: {})
    env = {
      "HOME" => "/var/empty",
      "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin",
      "TMPDIR" => @root,
      "VIFTY_LIFECYCLE_TEST_ROOT" => @root,
      "VIFTY_FIXTURE_INVOCATION_LOG" => @log,
      "VIFTY_FIXTURE_PARENT_START_ID" => "ruby-fixture-parent"
    }.merge(extra_env)
    stdout, stderr, status = Open3.capture3(
      env,
      "/bin/bash", "--noprofile", "--norc", script, *args,
      unsetenv_others: true
    )
    {status: status.exitstatus, output: stdout + stderr}
  end

  def immutable?(path)
    output, status = Open3.capture2("/usr/bin/stat", "-f", "%f", path)
    status.success? && (Integer(output.strip) & 0x2) == 0x2
  end

  def make_app(path)
    macos = File.join(path, "Contents/MacOS")
    resources = File.join(path, "Contents/Resources")
    FileUtils.mkdir_p(macos)
    FileUtils.mkdir_p(resources)
    FileUtils.cp(File.join(ROOT, "scripts/vifty-helper-lifecycle.sh"), File.join(resources, "vifty-helper-lifecycle.sh"))
    File.chmod(0o755, File.join(resources, "vifty-helper-lifecycle.sh"))
    File.write(
      File.join(path, "Contents/Info.plist"),
      <<~PLIST
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>tech.reidar.vifty</string>
        <key>CFBundleExecutable</key><string>Vifty</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>CFBundleShortVersionString</key><string>1.4.0</string>
        <key>CFBundleVersion</key><string>8</string>
        </dict></plist>
      PLIST
    )
    write_executable(File.join(macos, "viftyctl"), viftyctl_script)
    write_executable(File.join(macos, "Vifty"), vifty_script)
    write_executable(File.join(macos, "ViftyHelper"), helper_script)
    write_executable(File.join(macos, "ViftyDaemon"), "#!/bin/bash\nexit 0\n")
  end

  def make_launchctl
    path = File.join(@root, "bin/launchctl")
    FileUtils.mkdir_p(File.dirname(path))
    write_executable(path, <<~'SH')
      #!/bin/bash
      set -euo pipefail
      state="${VIFTY_LIFECYCLE_TEST_ROOT}/launchctl-state"
      disabled="${VIFTY_LIFECYCLE_TEST_ROOT}/launchctl-disabled"
      case "$1" in
        print) [[ ! -e "$state" ]] ;;
        print-disabled)
          if [[ -e "$disabled" ]]; then
            printf 'disabled services = {\n  "tech.reidar.vifty.daemon" => true\n}\n'
          else
            printf 'disabled services = { }\n'
          fi
          ;;
        disable) : > "$disabled" ;;
        enable) /bin/rm -f "$disabled" ;;
        bootout) : > "$state" ;;
        *) exit 64 ;;
      esac
    SH
  end

  def viftyctl_script
    <<~'SH'
      #!/bin/bash
      set -euo pipefail
      if [[ "$1" == "helper-maintenance-prepare" ]]; then
        operation="$3"
        helper_sha="$(/usr/bin/shasum -a 256 "$(/usr/bin/dirname "$0")/ViftyHelper" | /usr/bin/awk '{print $1}')"
        printf '{"schemaVersion":1,"schemaID":"https://vifty.app/schemas/helper-maintenance-report-v1.json","operation":"%s","safeToStop":true,"quiesced":true,"restoreAttempted":true,"restoreSucceeded":true,"completeExpectedSetConfirmed":true,"fanResults":[],"blockers":[],"token":{"schemaVersion":1,"tokenID":"fixture-token","operation":"%s","issuedAt":1000,"expiresAt":1030,"bootSessionID":"boot","daemonSessionID":"daemon","journalGeneration":1,"expectedFanIDs":[0,1],"helperSHA256":"%s","quiesceGeneration":1},"tokenConsumed":false}\n' "$operation" "$operation" "$helper_sha"
        exit 0
      fi
      [[ "$1" == "helper-maintenance-cancel" ]] && { printf '{"cancelled":true}\n'; exit 0; }
      exit 64
    SH
  end

  def vifty_script
    <<~'SH'
      #!/bin/bash
      set -euo pipefail
      action="$2"
      if [[ "$action" == "unregister" ]]; then
        operation="$4"; report="$6"
        token_id="$(/usr/bin/ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("token", "tokenID")' "$report")"
        helper_sha="$(/usr/bin/ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("token", "helperSHA256")' "$report")"
        authority_dir="${VIFTY_LIFECYCLE_TEST_ROOT}/Library/Application Support/Vifty/Maintenance"
        /bin/mkdir -p "$authority_dir"; /bin/chmod 700 "$authority_dir"
        now="$(/bin/date +%s)"; expires="$((now + 300))"
        printf '{"schemaVersion":1,"schemaID":"https://vifty.app/schemas/helper-maintenance-authority-v1.json","recordKind":"daemon-authorized-helper-maintenance","operation":"%s","tokenID":"%s","tokenIssuedAt":%s,"authorizedAt":%s,"expiresAt":%s,"bootSessionID":"boot","daemonSessionID":"daemon","journalGeneration":1,"expectedFanIDs":[0,1],"helperSHA256":"%s","quiesceGeneration":1,"quiesced":true,"tokenConsumed":true}\n' "$operation" "$token_id" "$now" "$now" "$expires" "$helper_sha" > "$authority_dir/authorized-v1.json"
        /bin/chmod 600 "$authority_dir/authorized-v1.json"
        printf '{"action":"unregister","state":"notRegistered","complete":true,"operatorActionRequired":false,"maintenanceAuthorized":true,"tokenID":"%s"}\n' "$token_id"
        exit 0
      fi
      if [[ "$action" == "register" ]]; then
        [[ "${VIFTY_FIXTURE_REGISTER_FAIL_FROZEN:-0}" != "1" ]] || exit 75
        printf '{"action":"register","state":"enabled","complete":true,"operatorActionRequired":false,"maintenanceAuthorized":false,"tokenID":null}\n'
        exit 0
      fi
      if [[ "$action" == "unregister-legacy" ]]; then
        printf '{"action":"unregister","state":"notRegistered","complete":true,"operatorActionRequired":false,"maintenanceAuthorized":false,"tokenID":null,"legacyProtocolGateUsed":true}\n'
        exit 0
      fi
      exit 64
    SH
  end

  def helper_script
    <<~'SH'
      #!/bin/bash
      set -euo pipefail
      operation="$3"; now="$(/bin/date +%s)"
      printf '{"schemaVersion":1,"schemaID":"https://vifty.app/schemas/helper-maintenance-report-v1.json","operation":"%s","safeToStop":true,"quiesced":true,"restoreAttempted":true,"restoreSucceeded":true,"completeExpectedSetConfirmed":true,"fanResults":[{"fanID":0,"observedMode":"automatic","confirmedOSManaged":true,"freshConfirmationAt":%s,"failure":null},{"fanID":1,"observedMode":"system","confirmedOSManaged":true,"freshConfirmationAt":%s,"failure":null}],"blockers":[],"token":null,"tokenConsumed":false}\n' "$operation" "$now" "$now"
    SH
  end

  def write_executable(path, contents)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    File.chmod(0o755, path)
  end
end
