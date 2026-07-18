# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "../../scripts/lib/ui_review_source_archive"

class UIReviewSourceArchiveTests < Minitest::Test
  BUILD_SCRIPT = File.expand_path("../../scripts/build-ui-review-products.sh", __dir__)

  def test_regular_files_and_directories_are_accepted
    Dir.mktmpdir("vifty-ui-source-archive-") do |root|
      FileUtils.mkdir_p(File.join(root, "Sources", "Nested"))
      File.binwrite(File.join(root, "Sources", "Nested", "main.swift"), "print(1)\n")

      assert ViftyUIReview::SourceArchive.validate_extracted_tree!(root)
    end
  end

  def test_symbolic_link_is_rejected
    Dir.mktmpdir("vifty-ui-source-archive-") do |root|
      File.binwrite(File.join(root, "target"), "target")
      File.symlink("target", File.join(root, "link"))

      error = assert_raises(ViftyUIReview::SourceArchive::UnsafeEntryError) do
        ViftyUIReview::SourceArchive.validate_extracted_tree!(root)
      end

      assert_match(/symbolic link/, error.message)
    end
  end

  def test_fifo_is_rejected_as_non_regular_entry
    skip "mkfifo is unavailable" unless File.executable?("/usr/bin/mkfifo")

    Dir.mktmpdir("vifty-ui-source-archive-") do |root|
      fifo = File.join(root, "named-pipe")
      assert system("/usr/bin/mkfifo", fifo)

      error = assert_raises(ViftyUIReview::SourceArchive::UnsafeEntryError) do
        ViftyUIReview::SourceArchive.validate_extracted_tree!(root)
      end

      assert_match(/non-regular/, error.message)
    end
  end

  def test_extracted_tree_is_validated_after_extraction_and_before_any_build
    script = File.read(BUILD_SCRIPT)
    extraction = script.index('/usr/bin/tar -xf "$source_archive" -C "$source_root"')
    validation = script.index("ViftyUIReview::SourceArchive.validate_extracted_tree!")
    first_build = script.index('/usr/bin/make -C "$source_root" app')

    refute_nil extraction, "Git archive extraction must remain explicit"
    refute_nil validation, "extracted archive validation must remain wired"
    refute_nil first_build, "first product build must remain identifiable"
    assert_operator extraction, :<, validation
    assert_operator validation, :<, first_build
  end
end
