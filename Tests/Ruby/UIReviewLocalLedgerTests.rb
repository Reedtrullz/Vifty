# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../../scripts/lib/ui_review_local_ledger"
require_relative "../../scripts/lib/ui_review_verifier"

class UIReviewLocalLedgerTests < Minitest::Test
  TEMPLATE = File.expand_path("../../docs/ui-review/evidence-manifest.json", __dir__)
  INITIALIZER = File.expand_path("../../scripts/initialize-ui-review-ledger.rb", __dir__)
  LOCK_WRAPPER = File.expand_path("../../scripts/with-ui-review-ledger-lock.rb", __dir__)
  TRANSACTION_A = "1" * 64
  TRANSACTION_B = "2" * 64

  def setup
    @temporary = Dir.mktmpdir("vifty-ui-ledger-test-")
    @root = File.join(@temporary, "repository")
    FileUtils.mkdir_p(File.join(@root, "docs/ui-review"))
    File.binwrite(File.join(@root, ".gitignore"), ".build/\ndocs/ui-review/evidence-manifest.local.json\n")
    FileUtils.cp(TEMPLATE, File.join(@root, ViftyUIReview::LocalLedger::TEMPLATE_RELATIVE_PATH))
    git("init", "-q")
    git("config", "user.name", "Vifty Tests")
    git("config", "user.email", "vifty-tests@example.invalid")
    git("add", ".gitignore", ViftyUIReview::LocalLedger::TEMPLATE_RELATIVE_PATH)
    git("commit", "-q", "-m", "fixture")
    @head = git("rev-parse", "HEAD").strip
    @tree = git("rev-parse", "HEAD^{tree}").strip
    write_products(transaction: TRANSACTION_A)
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary && File.exist?(@temporary)
  end

  def test_initializes_exact_product_bound_private_ledger_without_mutating_template
    template_path = path(ViftyUIReview::LocalLedger::TEMPLATE_RELATIVE_PATH)
    template_before = File.binread(template_path)

    result = ViftyUIReview::LocalLedger.initialize!(
      repository_root: @root,
      now: Time.utc(2026, 7, 17, 10, 0, 0)
    )

    output = path(ViftyUIReview::LocalLedger::OUTPUT_RELATIVE_PATH)
    document = JSON.parse(File.binread(output))
    template = JSON.parse(template_before)
    release = document.fetch("releaseExclusion")
    assert_equal "initialized", result.fetch("status")
    assert_equal @head, result.fetch("sourceCommit")
    assert_equal @tree, result.fetch("sourceTree")
    assert_equal TRANSACTION_A, result.fetch("buildTransactionID")
    assert_nil result.fetch("archivedPreviousLedger")
    assert_equal template_before, File.binread(template_path)
    assert_equal "pending", document.fetch("status")
    assert_equal({}, document.fetch("captureLedger"))
    assert document.fetch("fixtureReports").all? { |row| row["status"] == "pending" && row["captureID"].nil? }
    assert document.fetch("visualCells").all? { |row| row["status"] == "pending" && row["captureID"].nil? }
    assert document.fetch("accessibilityChecks").all? { |row| row["status"] == "pending" && row["captureID"].nil? }
    assert_equal "passed", release.fetch("status")
    assert_equal ViftyUIReview::LocalLedger::RELEASE_RELATIVE_PATH, release.fetch("binary")
    assert_equal ViftyUIReview::LocalLedger::RELEASE_FORBIDDEN_MARKERS, release.fetch("forbiddenMarkers")
    assert_equal Digest::SHA256.file(path(ViftyUIReview::LocalLedger::RELEASE_RELATIVE_PATH)).hexdigest,
                 release.fetch("sha256")
    assert_equal "release-exclusion", release.dig("buildProvenance", "productRole")
    template["releaseExclusion"] = release
    assert_equal template, document
    assert_equal 0o600, File.stat(output).mode & 0o777
    assert_equal ViftyUIReview.canonical_json(document) + "\n", File.binread(output)
  end

  def test_cli_initializes_the_canonical_ledger_and_reports_machine_readable_identity
    stdout, stderr, status = Open3.capture3(
      "/usr/bin/ruby", INITIALIZER, "--repository-root", @root
    )

    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "initialized", result.fetch("status")
    assert_equal @head, result.fetch("sourceCommit")
    assert_equal TRANSACTION_A, result.fetch("buildTransactionID")
    assert_equal "passed", JSON.parse(
      File.binread(path(ViftyUIReview::LocalLedger::OUTPUT_RELATIVE_PATH))
    ).dig("releaseExclusion", "status")
  end

  def test_initialized_ledger_is_accepted_by_the_shared_product_and_request_verifier
    ViftyUIReview::LocalLedger.initialize!(repository_root: @root)
    evidence = path(".build/ui-review-evidence")
    FileUtils.mkdir_p(evidence)
    result = nil
    stdout, stderr = capture_io do
      result = ViftyUIReview::Verifier.run(
        manifest_path: path(ViftyUIReview::LocalLedger::OUTPUT_RELATIVE_PATH),
        evidence_dir: evidence,
        release_binary: path(ViftyUIReview::LocalLedger::RELEASE_RELATIVE_PATH),
        debug_executable: path(ViftyUIReview::LocalLedger::DEBUG_RELATIVE_PATH),
        collector_executable: path(ViftyUIReview::LocalLedger::COLLECTOR_RELATIVE_PATH),
        mode: "initialized"
      )
    end

    assert_equal 0, result, stderr
    assert_match(/Initialized UI review ledger passed/, stdout)
    assert_empty stderr
  end

  def test_initialized_verifier_rejects_any_populated_row_or_capture_ledger_entry
    ViftyUIReview::LocalLedger.initialize!(repository_root: @root)
    manifest_path = path(ViftyUIReview::LocalLedger::OUTPUT_RELATIVE_PATH)
    document = JSON.parse(File.binread(manifest_path))
    document.fetch("fixtureReports").first["status"] = "passed"
    document.fetch("fixtureReports").first["captureID"] = "stale-capture"
    document.fetch("captureLedger")["stale-capture"] = {}
    File.binwrite(manifest_path, ViftyUIReview.canonical_json(document) + "\n")
    evidence = path(".build/ui-review-evidence")
    FileUtils.mkdir_p(evidence)
    result = nil
    _stdout, stderr = capture_io do
      result = ViftyUIReview::Verifier.run(
        manifest_path: manifest_path,
        evidence_dir: evidence,
        release_binary: path(ViftyUIReview::LocalLedger::RELEASE_RELATIVE_PATH),
        debug_executable: path(ViftyUIReview::LocalLedger::DEBUG_RELATIVE_PATH),
        collector_executable: path(ViftyUIReview::LocalLedger::COLLECTOR_RELATIVE_PATH),
        mode: "initialized"
      )
    end

    assert_equal 1, result
    assert_match(/initialized ledger is not the exact empty request/, stderr)
  end

  def test_archives_existing_ledger_byte_for_byte_before_replacement
    output = path(ViftyUIReview::LocalLedger::OUTPUT_RELATIVE_PATH)
    old = "{\"historical\":true}\n".b
    File.binwrite(output, old)
    File.chmod(0o600, output)

    result = ViftyUIReview::LocalLedger.initialize!(
      repository_root: @root,
      now: Time.utc(2026, 7, 17, 10, 1, 0)
    )

    archive_relative = result.fetch("archivedPreviousLedger")
    refute_nil archive_relative
    archive = path(archive_relative)
    assert_equal old, File.binread(archive)
    assert_equal 0o600, File.stat(archive).mode & 0o777
    assert_equal "passed", JSON.parse(File.binread(output)).dig("releaseExclusion", "status")
    assert_equal 0o700, File.stat(File.dirname(archive)).mode & 0o777
  end

  def test_dirty_repository_and_tracked_template_drift_fail_closed
    output = path(ViftyUIReview::LocalLedger::OUTPUT_RELATIVE_PATH)
    File.binwrite(output, "sentinel\n")
    File.chmod(0o600, output)
    File.binwrite(path("untracked.txt"), "dirty")

    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      ViftyUIReview::LocalLedger.initialize!(repository_root: @root)
    end
    assert_match(/clean/, error.message)
    assert_equal "sentinel\n", File.binread(output)

    File.unlink(path("untracked.txt"))
    File.open(path(ViftyUIReview::LocalLedger::TEMPLATE_RELATIVE_PATH), "ab") { |file| file.write(" ") }
    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      ViftyUIReview::LocalLedger.initialize!(repository_root: @root)
    end
    assert_match(/clean|differs from HEAD/, error.message)
    assert_equal "sentinel\n", File.binread(output)
  end

  def test_mixed_product_transaction_and_release_marker_fail_closed
    output = path(ViftyUIReview::LocalLedger::OUTPUT_RELATIVE_PATH)
    File.binwrite(output, "sentinel\n")
    File.chmod(0o600, output)
    write_product("release-exclusion", transaction: TRANSACTION_B)

    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      ViftyUIReview::LocalLedger.initialize!(repository_root: @root)
    end
    assert_match(/one build transaction/, error.message)
    assert_equal "sentinel\n", File.binread(output)

    write_products(transaction: TRANSACTION_A)
    File.open(path(ViftyUIReview::LocalLedger::RELEASE_RELATIVE_PATH), "ab") do |file|
      file.write("--ui-review-fixture")
    end
    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      ViftyUIReview::LocalLedger.initialize!(repository_root: @root)
    end
    assert_match(/fixture marker/, error.message)
    assert_equal "sentinel\n", File.binread(output)
  end

  def test_product_and_output_symlinks_are_rejected_without_replacing_existing_data
    release = path(ViftyUIReview::LocalLedger::RELEASE_RELATIVE_PATH)
    real_release = "#{release}.real"
    File.rename(release, real_release)
    File.symlink(real_release, release)
    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      ViftyUIReview::LocalLedger.initialize!(repository_root: @root)
    end
    assert_match(/non-symlink/, error.message)

    File.unlink(release)
    File.rename(real_release, release)
    output = path(ViftyUIReview::LocalLedger::OUTPUT_RELATIVE_PATH)
    target = path(".build/outside-ledger.json")
    FileUtils.mkdir_p(File.dirname(target))
    File.binwrite(target, "outside\n")
    File.symlink(target, output)
    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      ViftyUIReview::LocalLedger.initialize!(repository_root: @root)
    end
    assert_match(/symbolic link/, error.message)
    assert_equal "outside\n", File.binread(target)
  end

  def test_capture_binding_rejects_stale_debug_or_collector_transaction
    provenance = product_provenance(transaction: TRANSACTION_A)
    manifest = JSON.parse(File.binread(path(ViftyUIReview::LocalLedger::TEMPLATE_RELATIVE_PATH)))
    manifest["releaseExclusion"] = {
      "status" => "passed",
      "binary" => ViftyUIReview::LocalLedger::RELEASE_RELATIVE_PATH,
      "sha256" => "a" * 64,
      "buildProvenance" => provenance.fetch("release-exclusion"),
      "forbiddenMarkers" => ViftyUIReview::LocalLedger::RELEASE_FORBIDDEN_MARKERS
    }
    assert ViftyUIReview::LocalLedger.verify_capture_binding!(
      manifest: manifest,
      debug_provenance: provenance.fetch("debug-fixture-app"),
      collector_provenance: provenance.fetch("ax-collector")
    )

    stale = product_document("debug-fixture-app", transaction: TRANSACTION_B)
    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      ViftyUIReview::LocalLedger.verify_capture_binding!(manifest: manifest, debug_provenance: stale)
    end
    assert_match(/buildTransactionID/, error.message)
  end

  def test_actual_product_binding_rejects_release_byte_tamper_and_collector_drift
    ViftyUIReview::LocalLedger.initialize!(repository_root: @root)
    manifest_path = path(ViftyUIReview::LocalLedger::OUTPUT_RELATIVE_PATH)
    manifest = JSON.parse(File.binread(manifest_path))
    release = path(ViftyUIReview::LocalLedger::RELEASE_RELATIVE_PATH)
    File.open(release, "ab") { |file| file.write("tamper") }

    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      verify_actual_binding(manifest_path, manifest)
    end
    assert_match(/release checksum/, error.message)

    write_products(transaction: TRANSACTION_A)
    write_product("ax-collector", transaction: TRANSACTION_B)
    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      verify_actual_binding(manifest_path, manifest)
    end
    assert_match(/one build transaction/, error.message)
  end

  def test_archive_symlink_fails_closed_and_preserves_existing_ledger
    output = path(ViftyUIReview::LocalLedger::OUTPUT_RELATIVE_PATH)
    File.binwrite(output, "sentinel\n")
    File.chmod(0o600, output)
    outside = path("outside-archive")
    FileUtils.mkdir_p(outside)
    archive_parent = path(".build/ui-review-evidence-archive")
    FileUtils.mkdir_p(File.dirname(archive_parent))
    File.symlink(outside, archive_parent)

    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      ViftyUIReview::LocalLedger.initialize!(repository_root: @root)
    end
    assert_match(/ignored by Git|unsafe path component/, error.message)
    assert_equal "sentinel\n", File.binread(output)
  end

  def test_shared_lock_contention_fails_with_bounded_retry_status
    lock = ViftyUIReview::LocalLedger.acquire_repository_lock!(@root)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    _stdout, stderr, status = Open3.capture3(
      "/usr/bin/ruby", LOCK_WRAPPER,
      "--repository-root", @root,
      "--timeout-seconds", "0.05",
      "--", "/usr/bin/true"
    )
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal 75, status.exitstatus, stderr
    assert_match(/busy/, stderr)
    assert_operator elapsed, :<, 1.0
  ensure
    ViftyUIReview::LocalLedger.release_lock(lock)
  end

  def test_lock_wrapper_forwards_termination_to_the_entire_child_process_group
    ready = path(".build/lock-wrapper-ready")
    FileUtils.mkdir_p(File.dirname(ready))
    command = <<~'BASH'
      trap 'exit 143' TERM
      /bin/sleep 10 &
      descendant=$!
      printf '%s %s\n' "$$" "$descendant" > "$1"
      wait "$descendant"
    BASH
    wrapper = Process.spawn(
      "/usr/bin/ruby", LOCK_WRAPPER,
      "--repository-root", @root,
      "--timeout-seconds", "0.5",
      "--", "/bin/bash", "-c", command, "vifty-lock-test", ready,
      out: File::NULL,
      err: File::NULL
    )
    wait_until(timeout: 2.0) { File.file?(ready) && !File.zero?(ready) }
    child, descendant = File.read(ready).split.map { |value| Integer(value, 10) }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.kill("TERM", wrapper)
    _pid, status = wait_for_process(wrapper, timeout: 2.0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal 143, status.exitstatus
    assert_operator elapsed, :<, 2.0
    wait_until(timeout: 1.0) { !process_exists?(descendant) }
    refute process_exists?(descendant), "descendant process remained alive after wrapper termination"
    lock = ViftyUIReview::LocalLedger.acquire_repository_lock!(@root, timeout_seconds: 0.2)
    assert lock
  ensure
    ViftyUIReview::LocalLedger.release_lock(lock) if defined?(lock)
    if defined?(child) && child && process_exists?(child)
      Process.kill("KILL", -child)
    end
    if defined?(wrapper) && wrapper
      begin
        Process.kill("KILL", wrapper)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(wrapper)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_lock_wrapper_forwards_session_hangup_before_releasing_the_lock
    ready = path(".build/lock-wrapper-hup-ready")
    FileUtils.mkdir_p(File.dirname(ready))
    command = <<~'BASH'
      trap 'exit 129' HUP
      /bin/sleep 10 &
      descendant=$!
      printf '%s %s\n' "$$" "$descendant" > "$1"
      wait "$descendant"
    BASH
    wrapper = Process.spawn(
      "/usr/bin/ruby", LOCK_WRAPPER,
      "--repository-root", @root,
      "--timeout-seconds", "0.5",
      "--", "/bin/bash", "-c", command, "vifty-lock-test", ready,
      out: File::NULL,
      err: File::NULL
    )
    wait_until(timeout: 2.0) { File.file?(ready) && !File.zero?(ready) }
    child, descendant = File.read(ready).split.map { |value| Integer(value, 10) }

    Process.kill("HUP", wrapper)
    _pid, status = wait_for_process(wrapper, timeout: 2.0)

    assert_equal 129, status.exitstatus
    wait_until(timeout: 1.0) { !process_exists?(descendant) }
    refute process_exists?(descendant), "descendant process remained alive after wrapper hangup"
    lock = ViftyUIReview::LocalLedger.acquire_repository_lock!(@root, timeout_seconds: 0.2)
    assert lock
  ensure
    ViftyUIReview::LocalLedger.release_lock(lock) if defined?(lock)
    Process.kill("KILL", -child) if defined?(child) && child && process_exists?(child)
    if defined?(wrapper) && wrapper
      begin
        Process.kill("KILL", wrapper)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(wrapper)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_lock_wrapper_kills_residual_descendant_that_ignores_forwarded_signal
    ready = path(".build/lock-wrapper-resistant-ready")
    resistant_ready = path(".build/lock-wrapper-resistant-child-ready")
    FileUtils.mkdir_p(File.dirname(ready))
    command = <<~'BASH'
      (
        trap '' TERM
        printf 'ready\n' > "$2"
        while :; do /bin/sleep 1; done
      ) &
      descendant=$!
      while [ ! -s "$2" ]; do /bin/sleep 0.01; done
      trap 'exit 143' TERM
      printf '%s %s\n' "$$" "$descendant" > "$1"
      while :; do /bin/sleep 1; done
    BASH
    wrapper = Process.spawn(
      "/usr/bin/ruby", LOCK_WRAPPER,
      "--repository-root", @root,
      "--timeout-seconds", "0.5",
      "--", "/bin/bash", "-c", command, "vifty-lock-test", ready, resistant_ready,
      out: File::NULL,
      err: File::NULL
    )
    wait_until(timeout: 2.0) { File.file?(ready) && !File.zero?(ready) }
    child, descendant = File.read(ready).split.map { |value| Integer(value, 10) }

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.kill("TERM", wrapper)
    _pid, status = wait_for_process(wrapper, timeout: 2.0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal 143, status.exitstatus
    assert_operator elapsed, :<, 2.0
    wait_until(timeout: 1.0) { !process_exists?(descendant) }
    refute process_exists?(descendant), "TERM-resistant descendant survived bounded escalation"
    lock = ViftyUIReview::LocalLedger.acquire_repository_lock!(@root, timeout_seconds: 0.2)
    assert lock
  ensure
    ViftyUIReview::LocalLedger.release_lock(lock) if defined?(lock)
    Process.kill("KILL", -child) if defined?(child) && child && process_exists?(child)
    if defined?(wrapper) && wrapper
      begin
        Process.kill("KILL", wrapper)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(wrapper)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_lock_wrapper_allows_direct_child_exit_cleanup_to_finish_before_residual_escalation
    ready = path(".build/lock-wrapper-cleanup-ready")
    cleanup_started = path(".build/lock-wrapper-cleanup-started")
    cleanup_finished = path(".build/lock-wrapper-cleanup-finished")
    FileUtils.mkdir_p(File.dirname(ready))
    command = <<~'BASH'
      cleanup_started_path="$2"
      cleanup_finished_path="$3"
      cleanup() {
        trap - EXIT
        trap '' HUP INT QUIT TERM
        printf 'started\n' > "$cleanup_started_path"
        /bin/sleep 1.1
        printf 'finished\n' > "$cleanup_finished_path"
      }
      trap cleanup EXIT
      trap 'trap "" HUP INT QUIT TERM; exit 143' TERM
      printf '%s\n' "$$" > "$1"
      /bin/sleep 10
    BASH
    wrapper = Process.spawn(
      "/usr/bin/ruby", LOCK_WRAPPER,
      "--repository-root", @root,
      "--timeout-seconds", "0.5",
      "--", "/bin/bash", "-c", command, "vifty-lock-test",
      ready, cleanup_started, cleanup_finished,
      out: File::NULL,
      err: File::NULL
    )
    wait_until(timeout: 2.0) { File.file?(ready) && !File.zero?(ready) }
    child = Integer(File.read(ready), 10)

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Process.kill("TERM", wrapper)
    _pid, status = wait_for_process(wrapper, timeout: 3.0)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal 143, status.exitstatus
    assert_operator elapsed, :>=, 1.0
    assert_equal "started\n", File.binread(cleanup_started)
    assert_equal "finished\n", File.binread(cleanup_finished)
    refute process_exists?(child)
    lock = ViftyUIReview::LocalLedger.acquire_repository_lock!(@root, timeout_seconds: 0.2)
    assert lock
  ensure
    ViftyUIReview::LocalLedger.release_lock(lock) if defined?(lock)
    Process.kill("KILL", -child) if defined?(child) && child && process_exists?(child)
    if defined?(wrapper) && wrapper
      begin
        Process.kill("KILL", wrapper)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(wrapper)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_lock_wrapper_does_not_drop_immediate_post_spawn_termination
    reader, writer = IO.pipe
    wrapper = Process.spawn(
      "/usr/bin/ruby", LOCK_WRAPPER,
      "--repository-root", @root,
      "--timeout-seconds", "0.5",
      "--", "/bin/bash", "-c",
      'trap \'exit 143\' TERM; printf \'READY:%s\n\' "$$"; /bin/sleep 10',
      out: writer,
      err: File::NULL
    )
    writer.close
    assert IO.select([reader], nil, nil, 2.0), "child did not publish immediate readiness"
    ready = reader.gets
    assert_match(/\AREADY:\d+\n\z/, ready)
    child = Integer(ready.delete_prefix("READY:"), 10)

    Process.kill("TERM", wrapper)
    _pid, status = wait_for_process(wrapper, timeout: 2.0)

    assert_equal 143, status.exitstatus
    wrapper = nil
    wait_until(timeout: 1.0) { !process_exists?(child) }
    refute process_exists?(child), "immediate child process remained alive"
    child = nil
    lock = ViftyUIReview::LocalLedger.acquire_repository_lock!(@root, timeout_seconds: 0.2)
    assert lock
  ensure
    reader.close if defined?(reader) && reader && !reader.closed?
    writer.close if defined?(writer) && writer && !writer.closed?
    ViftyUIReview::LocalLedger.release_lock(lock) if defined?(lock)
    Process.kill("KILL", -child) if defined?(child) && child && process_exists?(child)
    if defined?(wrapper) && wrapper
      begin
        Process.kill("KILL", wrapper)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(wrapper)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_lock_wrapper_preserves_back_to_back_distinct_signals
    reader, writer = IO.pipe
    wrapper = Process.spawn(
      "/usr/bin/ruby", LOCK_WRAPPER,
      "--repository-root", @root,
      "--timeout-seconds", "0.5",
      "--", "/bin/bash", "-c",
      'trap \'\' INT; trap \'exit 143\' TERM; printf \'READY:%s\n\' "$$"; /bin/sleep 10',
      out: writer,
      err: File::NULL
    )
    writer.close
    assert IO.select([reader], nil, nil, 2.0), "child did not publish immediate readiness"
    ready = reader.gets
    assert_match(/\AREADY:\d+\n\z/, ready)
    child = Integer(ready.delete_prefix("READY:"), 10)

    Process.kill("INT", wrapper)
    Process.kill("TERM", wrapper)
    _pid, status = wait_for_process(wrapper, timeout: 2.0)

    assert_equal 143, status.exitstatus
    wrapper = nil
    wait_until(timeout: 1.0) { !process_exists?(child) }
    refute process_exists?(child), "child that ignored INT remained alive after TERM"
    child = nil
    lock = ViftyUIReview::LocalLedger.acquire_repository_lock!(@root, timeout_seconds: 0.2)
    assert lock
  ensure
    reader.close if defined?(reader) && reader && !reader.closed?
    writer.close if defined?(writer) && writer && !writer.closed?
    ViftyUIReview::LocalLedger.release_lock(lock) if defined?(lock)
    Process.kill("KILL", -child) if defined?(child) && child && process_exists?(child)
    if defined?(wrapper) && wrapper
      begin
        Process.kill("KILL", wrapper)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(wrapper)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_child_inherits_lock_so_untrappable_wrapper_exit_cannot_enable_overlap
    lock = nil
    ready = path(".build/lock-wrapper-kill-ready")
    FileUtils.mkdir_p(File.dirname(ready))
    wrapper = Process.spawn(
      "/usr/bin/ruby", LOCK_WRAPPER,
      "--repository-root", @root,
      "--timeout-seconds", "0.5",
      "--", "/bin/bash", "-c", 'printf "%s\n" "$$" > "$1"; /bin/sleep 10',
      "vifty-lock-test", ready,
      out: File::NULL,
      err: File::NULL
    )
    wait_until(timeout: 2.0) { File.file?(ready) && !File.zero?(ready) }
    child = Integer(File.read(ready), 10)

    Process.kill("KILL", wrapper)
    _pid, status = wait_for_process(wrapper, timeout: 2.0)
    assert status.signaled?
    assert_equal Signal.list.fetch("KILL"), status.termsig
    wrapper = nil

    error = assert_raises(ViftyUIReview::LocalLedger::LedgerError) do
      ViftyUIReview::LocalLedger.acquire_repository_lock!(@root, timeout_seconds: 0.05)
    end
    assert_equal 75, error.exit_code
    assert process_exists?(child)

    Process.kill("TERM", -child)
    wait_until(timeout: 2.0) do
      begin
        lock = ViftyUIReview::LocalLedger.acquire_repository_lock!(@root, timeout_seconds: 0.05)
        true
      rescue ViftyUIReview::LocalLedger::LedgerError => error
        raise unless error.exit_code == 75
        false
      end
    end
    assert lock
    child = nil
  ensure
    ViftyUIReview::LocalLedger.release_lock(lock) if defined?(lock)
    Process.kill("KILL", -child) if defined?(child) && child && process_exists?(child)
    if defined?(wrapper) && wrapper
      begin
        Process.kill("KILL", wrapper)
      rescue Errno::ESRCH
        nil
      end
      begin
        Process.wait(wrapper)
      rescue Errno::ECHILD
        nil
      end
    end
  end

  def test_wrapper_closes_its_lock_descriptor_without_explicitly_unlocking_inherited_holders
    source = File.binread(LOCK_WRAPPER)

    assert_includes source, "lock.fileno => lock.fileno"
    assert_includes source, "lock.close if lock && !lock.closed?"
    assert_includes source, "direct_kill_started_at"
    assert_includes source, "UI review direct child did not terminate after bounded KILL escalation"
    refute_includes source, "LocalLedger.release_lock(lock)"
  end

  private

  def path(relative)
    File.join(@root, relative)
  end

  def git(*arguments)
    stdout, stderr, status = Open3.capture3("/usr/bin/git", "-C", @root, *arguments)
    raise "git #{arguments.join(" ")} failed: #{stderr}" unless status.success?
    stdout
  end

  def write_products(transaction:)
    ViftyUIReview::BuildProvenance::ROLE_CONFIGURATIONS.each_key do |role|
      write_product(role, transaction: transaction)
    end
  end

  def write_product(role, transaction:)
    relative = {
      "debug-fixture-app" => ViftyUIReview::LocalLedger::DEBUG_RELATIVE_PATH,
      "release-exclusion" => ViftyUIReview::LocalLedger::RELEASE_RELATIVE_PATH,
      "ax-collector" => ViftyUIReview::LocalLedger::COLLECTOR_RELATIVE_PATH
    }.fetch(role)
    destination = path(relative)
    FileUtils.mkdir_p(File.dirname(destination))
    File.binwrite(destination, macho(product_document(role, transaction: transaction)))
    File.chmod(0o755, destination)
  end

  def product_provenance(transaction:)
    ViftyUIReview::BuildProvenance::ROLE_CONFIGURATIONS.to_h do |role, _configuration|
      [role, product_document(role, transaction: transaction)]
    end
  end

  def product_document(role, transaction:)
    {
      "schemaVersion" => 1,
      "schemaID" => ViftyUIReview::BuildProvenance::SCHEMA_ID,
      "sourceCommit" => @head,
      "sourceTree" => @tree,
      "productRole" => role,
      "configuration" => ViftyUIReview::BuildProvenance::ROLE_CONFIGURATIONS.fetch(role),
      "buildTransactionID" => transaction
    }
  end

  def macho(document)
    payload = ViftyUIReview.canonical_json(document)
    header_size = 32
    command_size = 72 + 80
    data_offset = header_size + command_size
    header = [0xfeedfacf, 0x0100000c, 0, 2, 1, command_size, 0, 0].pack("V8")
    segment = [0x19, command_size].pack("V2") + fixed_name("__TEXT") +
      [0, 0, data_offset, payload.bytesize].pack("Q<4") + [7, 5, 1, 0].pack("V4")
    section = fixed_name("__vifty_src") + fixed_name("__TEXT") +
      [0, payload.bytesize].pack("Q<2") + [data_offset, 0, 0, 0, 0, 0, 0, 0].pack("V8")
    header + segment + section + payload
  end

  def fixed_name(value)
    value.b.ljust(16, "\0")
  end

  def verify_actual_binding(manifest_path, manifest)
    manifest_path = File.realpath(manifest_path)
    debug = File.realpath(path(ViftyUIReview::LocalLedger::DEBUG_RELATIVE_PATH))
    data = File.binread(debug)
    ViftyUIReview::LocalLedger.verify_actual_product_binding!(
      manifest_path: manifest_path,
      manifest: manifest,
      debug_path: debug,
      debug_sha256: Digest::SHA256.hexdigest(data),
      debug_provenance: ViftyUIReview::BuildProvenance.extract!(data, label: "debug")
    )
  end

  def wait_until(timeout:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "timed out waiting for condition" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.01
    end
  end

  def wait_for_process(pid, timeout:)
    result = nil
    wait_until(timeout: timeout) do
      result = Process.waitpid2(pid, Process::WNOHANG)
      !result.nil?
    end
    result
  end

  def process_exists?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end
end
