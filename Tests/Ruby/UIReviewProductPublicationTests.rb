# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

class UIReviewProductPublicationTests < Minitest::Test
  HELPER = File.expand_path("../../scripts/lib/ui_review_product_publication.sh", __dir__)
  BUILD_SCRIPT = File.expand_path("../../scripts/build-ui-review-products.sh", __dir__)

  def test_failure_in_post_publication_verifier_restores_previous_output
    Dir.mktmpdir("vifty-ui-publication-") do |root|
      output = File.join(root, "products")
      stage = File.join(root, "stage")
      previous = File.join(root, "previous")
      FileUtils.mkdir_p(output)
      FileUtils.mkdir_p(stage)
      File.write(File.join(output, "identity"), "old")
      File.write(File.join(stage, "identity"), "new")

      status, stderr = run_publication(
        output: output,
        stage: stage,
        previous: previous,
        verifier_result: 73
      )

      assert_equal 73, status, stderr
      assert_equal "old", File.read(File.join(output, "identity"))
      refute File.exist?(previous)
      refute File.exist?(stage)
    end
  end

  def test_success_commits_new_output_only_after_verifier_passes
    Dir.mktmpdir("vifty-ui-publication-") do |root|
      output = File.join(root, "products")
      stage = File.join(root, "stage")
      previous = File.join(root, "previous")
      FileUtils.mkdir_p(output)
      FileUtils.mkdir_p(stage)
      File.write(File.join(output, "identity"), "old")
      File.write(File.join(stage, "identity"), "new")

      status, stderr = run_publication(
        output: output,
        stage: stage,
        previous: previous,
        verifier_result: 0
      )

      assert_equal 0, status, stderr
      assert_equal "new", File.read(File.join(output, "identity"))
      assert_equal "old", File.read(File.join(previous, "identity"))
    end
  end

  def test_prepublication_rejection_preserves_preexisting_non_directory_output
    Dir.mktmpdir("vifty-ui-publication-") do |root|
      output = File.join(root, "products")
      stage = File.join(root, "stage")
      previous = File.join(root, "previous")
      File.binwrite(output, "existing non-directory output")
      FileUtils.mkdir_p(stage)
      File.write(File.join(stage, "identity"), "new")

      status, stderr = run_publication(
        output: output,
        stage: stage,
        previous: previous,
        verifier_result: 0
      )

      assert_equal 65, status, stderr
      assert File.file?(output), "pre-existing output must remain a regular file"
      assert_equal "existing non-directory output", File.binread(output)
      refute File.exist?(previous)
    end
  end

  def test_term_after_previous_output_move_restores_previous_output
    Dir.mktmpdir("vifty-ui-publication-") do |root|
      output, stage, previous = create_product_sets(root)

      status, stderr = run_interrupted_publication(
        output: output,
        stage: stage,
        previous: previous,
        checkpoint: "after-previous-output-move"
      )

      assert_equal 143, status, stderr
      assert_equal "old", File.read(File.join(output, "identity"))
      refute File.exist?(previous)
      assert_equal "new", File.read(File.join(stage, "identity"))
    end
  end

  def test_term_during_previous_output_restore_retries_from_directory_state
    Dir.mktmpdir("vifty-ui-publication-") do |root|
      output, stage, previous = create_product_sets(root)

      status, stderr = run_interrupted_publication(
        output: output,
        stage: stage,
        previous: previous,
        checkpoint: "before-previous-output-restore",
        verifier_result: 73
      )

      assert_equal 143, status, stderr
      assert_equal "old", File.read(File.join(output, "identity"))
      refute File.exist?(previous)
      refute File.exist?(stage)
    end
  end

  def test_term_after_previous_output_restore_keeps_restored_output
    Dir.mktmpdir("vifty-ui-publication-") do |root|
      output, stage, previous = create_product_sets(root)

      status, stderr = run_interrupted_publication(
        output: output,
        stage: stage,
        previous: previous,
        checkpoint: "after-previous-output-restore",
        verifier_result: 73
      )

      assert_equal 143, status, stderr
      assert_equal "old", File.read(File.join(output, "identity"))
      refute File.exist?(previous)
      refute File.exist?(stage)
    end
  end

  def test_failed_restore_preserves_recovery_directory_and_blocks_scratch_cleanup
    Dir.mktmpdir("vifty-ui-publication-parent-") do |parent|
      scratch = File.join(parent, "transaction")
      FileUtils.mkdir_p(scratch)
      output = File.join(parent, "products")
      stage = File.join(scratch, "stage")
      previous = File.join(scratch, "previous")
      FileUtils.mkdir_p(output)
      FileUtils.mkdir_p(stage)
      File.write(File.join(output, "identity"), "old")
      File.write(File.join(stage, "identity"), "new")

      status, stderr = run_restore_failure(
        output: output,
        stage: stage,
        previous: previous,
        scratch: scratch
      )

      assert_equal 75, status, stderr
      assert File.directory?(scratch), "recovery transaction must not be deleted"
      assert_equal "old", File.read(File.join(previous, "identity"))
      assert_equal "restore obstruction", File.binread(output)
      assert_match(/recovery material is preserved/, stderr)
    end
  end

  def test_build_entrypoint_preserves_publication_failure_status
    script = File.read(BUILD_SCRIPT)

    assert_includes script, "publication_status=$?"
    assert_includes script, 'exit "$publication_status"'
    refute_match(/ui_review_publish_products[\s\\\n]+.*\|\|\s+fail/m, script)
  end

  def test_build_entrypoint_holds_the_shared_ledger_lock_for_the_transaction
    script = File.read(BUILD_SCRIPT)

    wrapper = script.index("with-ui-review-ledger-lock.rb")
    source_state = script.index("initial_status=")
    publication = script.index("ui_review_publish_products")
    refute_nil wrapper
    refute_nil source_state
    refute_nil publication
    assert_operator wrapper, :<, source_state
    assert_operator wrapper, :<, publication
    assert_includes script, 'VIFTY_UI_REVIEW_LOCK_HELD:-0'
  end

  def test_build_entrypoint_installs_cleanup_before_scratch_and_ignores_repeat_signals_during_rollback
    script = File.read(BUILD_SCRIPT)

    cleanup_trap = script.index("trap cleanup EXIT")
    scratch_creation = script.index('/bin/mkdir -m 700 "$scratch_root"')
    refute_nil cleanup_trap
    refute_nil scratch_creation
    assert_operator cleanup_trap, :<, scratch_creation
    assert_includes script, "trap '' HUP INT QUIT TERM"
    assert_includes script, "trap 'handle_signal 129' HUP"
    assert_includes script, "trap 'handle_signal 131' QUIT"
  end

  private

  def create_product_sets(root)
    output = File.join(root, "products")
    stage = File.join(root, "stage")
    previous = File.join(root, "previous")
    FileUtils.mkdir_p(output)
    FileUtils.mkdir_p(stage)
    File.write(File.join(output, "identity"), "old")
    File.write(File.join(stage, "identity"), "new")
    [output, stage, previous]
  end

  def run_publication(output:, stage:, previous:, verifier_result:)
    script = <<~BASH
      set -u
      . "$1"
      output_root="$2"
      previous="$3"
      publication_started=0
      publication_committed=0
      publication_rollback_failed=0
      publication_restore_in_progress=0
      had_previous_output=0
      verifier_result="$4"
      products_stage="$5"
      verify_after_publish() {
        test -f "$output_root/identity" || return 74
        test "$(/bin/cat "$output_root/identity")" = "new" || return 75
        return "$verifier_result"
      }
      ui_review_publish_products "$products_stage" verify_after_publish after-publication
      status=$?
      ui_review_rollback_product_publication
      exit "$status"
    BASH
    _stdout, stderr, process = Open3.capture3(
      "/bin/bash",
      "-c",
      script,
      "publication-test",
      HELPER,
      output,
      previous,
      verifier_result.to_s,
      stage
    )
    [process.exitstatus, stderr]
  end

  def run_interrupted_publication(output:, stage:, previous:, checkpoint:, verifier_result: 0)
    script = <<~BASH
      set -u
      . "$1"
      output_root="$2"
      previous="$3"
      publication_started=0
      publication_committed=0
      publication_rollback_failed=0
      publication_restore_in_progress=0
      had_previous_output=0
      verifier_result="$4"
      products_stage="$5"
      interrupt_checkpoint="$6"
      checkpoint_interrupted=0
      ui_review_publication_checkpoint() {
        if [[ "$1" == "$interrupt_checkpoint" && "$checkpoint_interrupted" -eq 0 ]]; then
          checkpoint_interrupted=1
          /bin/kill -TERM "$$"
        fi
      }
      verify_after_publish() { return "$verifier_result"; }
      cleanup() {
        status=$?
        trap - EXIT INT TERM
        ui_review_rollback_product_publication || true
        return "$status"
      }
      handle_term() {
        trap - INT TERM
        exit 143
      }
      trap cleanup EXIT
      trap handle_term TERM
      ui_review_publish_products "$products_stage" verify_after_publish after-publication
    BASH
    _stdout, stderr, process = Open3.capture3(
      "/bin/bash", "-c", script, "publication-interrupt-test", HELPER,
      output, previous, verifier_result.to_s, stage, checkpoint
    )
    [process.exitstatus, stderr]
  end

  def run_restore_failure(output:, stage:, previous:, scratch:)
    script = <<~BASH
      set -u
      . "$1"
      output_root="$2"
      previous="$3"
      publication_started=0
      publication_committed=0
      publication_rollback_failed=0
      publication_restore_in_progress=0
      had_previous_output=0
      products_stage="$4"
      scratch_root="$5"
      obstruction_written=0
      ui_review_publication_checkpoint() {
        if [[ "$1" == "before-previous-output-restore" && "$obstruction_written" -eq 0 ]]; then
          obstruction_written=1
          /usr/bin/printf '%s' 'restore obstruction' > "$output_root"
        fi
      }
      verify_after_publish() { return 73; }
      ui_review_publish_products "$products_stage" verify_after_publish after-publication
      status=$?
      ui_review_cleanup_product_transaction_scratch "$scratch_root" || status=$?
      exit "$status"
    BASH
    _stdout, stderr, process = Open3.capture3(
      "/bin/bash", "-c", script, "publication-restore-failure-test", HELPER,
      output, previous, stage, scratch
    )
    [process.exitstatus, stderr]
  end
end
