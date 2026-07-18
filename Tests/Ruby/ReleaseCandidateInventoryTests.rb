# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

class ReleaseCandidateInventoryTests < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(ROOT, "scripts/release-candidate-inventory.rb")

  def setup
    @root = Dir.mktmpdir("vifty-release-candidate-inventory.")
    @app = File.join(@root, "Vifty.app")
    @binary = File.join(@app, "Contents", "MacOS", "Vifty")
    @resources = File.join(@app, "Contents", "Resources")
    @configuration = File.join(@resources, "configuration.json")
    @configuration_link = File.join(@resources, "current-configuration.json")
    @handoff = File.join(@root, "handoff")
    @archive = File.join(@handoff, "Vifty-v9.9.9.zip")
    @supplemental = File.join(@handoff, "release-admission-provenance.json")
    @inventory = File.join(@handoff, "candidate-inventory.json")

    FileUtils.mkdir_p(File.dirname(@binary))
    FileUtils.mkdir_p(@resources)
    FileUtils.mkdir_p(@handoff)
    File.binwrite(@binary, "#!/bin/sh\nprintf 'Vifty fixture\\n'\n")
    File.chmod(0o755, @binary)
    File.binwrite(@configuration, JSON.generate("mode" => "automatic") << "\n")
    File.chmod(0o640, @configuration)
    File.symlink("configuration.json", @configuration_link)
    File.binwrite(@supplemental, JSON.pretty_generate("sourceCommit" => "a" * 40) << "\n")
    build_archive!
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_create_is_deterministic_and_records_the_complete_tree_and_handoff_files
    first_stdout, first_stderr, first_status = create_inventory(@inventory)
    second_inventory = File.join(@root, "candidate-inventory-second.json")
    second_stdout, second_stderr, second_status = create_inventory(second_inventory)

    assert first_status.success?, first_stderr
    assert second_status.success?, second_stderr
    assert_equal "Candidate inventory created and archive round-trip verified.\n", first_stdout
    assert_equal first_stdout, second_stdout
    assert_equal File.binread(@inventory), File.binread(second_inventory)

    bytes = File.binread(@inventory)
    data = JSON.parse(bytes)
    assert_equal JSON.pretty_generate(data) << "\n", bytes
    assert_equal 1, data.fetch("schemaVersion")
    assert_equal "vifty-release-candidate-inventory", data.fetch("kind")
    assert_equal(
      {
        "name" => File.basename(@archive),
        "size" => File.size(@archive),
        "sha256" => Digest::SHA256.file(@archive).hexdigest
      },
      data.fetch("archive")
    )
    assert_equal(
      [{
        "path" => File.basename(@supplemental),
        "size" => File.size(@supplemental),
        "sha256" => Digest::SHA256.file(@supplemental).hexdigest
      }],
      data.fetch("supplementalFiles")
    )

    entries = data.fetch("tree").fetch("entries")
    assert_equal "Vifty.app", data.fetch("tree").fetch("root")
    assert_equal entries.map { |entry| entry.fetch("path") }.sort_by(&:b),
                 entries.map { |entry| entry.fetch("path") }
    assert_equal(
      %w[
        .
        Contents
        Contents/MacOS
        Contents/MacOS/Vifty
        Contents/Resources
        Contents/Resources/configuration.json
        Contents/Resources/current-configuration.json
      ],
      entries.map { |entry| entry.fetch("path") }
    )

    binary = entries.find { |entry| entry.fetch("path") == "Contents/MacOS/Vifty" }
    assert_equal "file", binary.fetch("type")
    assert_equal 0o755, binary.fetch("mode")
    assert_equal File.size(@binary), binary.fetch("size")
    assert_equal Digest::SHA256.file(@binary).hexdigest, binary.fetch("sha256")

    configuration = entries.find do |entry|
      entry.fetch("path") == "Contents/Resources/configuration.json"
    end
    assert_equal 0o640, configuration.fetch("mode")

    link = entries.find do |entry|
      entry.fetch("path") == "Contents/Resources/current-configuration.json"
    end
    assert_equal "symlink", link.fetch("type")
    assert_equal "configuration.json", link.fetch("linkTarget")
  end

  def test_extract_verifies_the_exact_handoff_and_verify_tree_accepts_the_extracted_app
    assert_create_succeeds
    extraction = File.join(@root, "extracted")
    FileUtils.mkdir_p(extraction)

    stdout, stderr, status = inventory_command(
      "extract",
      "--inventory", @inventory,
      "--handoff-dir", @handoff,
      "--extract-to", extraction
    )

    assert status.success?, stderr
    extracted_app = File.join(extraction, "Vifty.app")
    assert_equal "Candidate handoff verified and extracted: #{extracted_app}\n", stdout
    assert_equal File.binread(@binary),
                 File.binread(File.join(extracted_app, "Contents", "MacOS", "Vifty"))
    assert_equal 0o755,
                 File.stat(File.join(extracted_app, "Contents", "MacOS", "Vifty")).mode & 0o777
    assert_equal "configuration.json",
                 File.readlink(File.join(extracted_app, "Contents", "Resources", "current-configuration.json"))

    verify_stdout, verify_stderr, verify_status = inventory_command(
      "verify-tree",
      "--app", extracted_app,
      "--inventory", @inventory
    )
    assert verify_status.success?, verify_stderr
    assert_equal "Candidate tree matches complete inventory.\n", verify_stdout
  end

  def test_verify_tree_rejects_same_size_content_drift
    assert_create_succeeds
    bytes = File.binread(@binary)
    bytes.setbyte(0, bytes.getbyte(0) ^ 1)
    File.binwrite(@binary, bytes)

    assert_inventory_failure(
      "verify-tree", "--app", @app, "--inventory", @inventory,
      message: /candidate tree does not match the complete recorded inventory/
    )
  end

  def test_verify_tree_rejects_mode_drift
    assert_create_succeeds
    File.chmod(0o700, @binary)

    assert_inventory_failure(
      "verify-tree", "--app", @app, "--inventory", @inventory,
      message: /candidate tree does not match the complete recorded inventory/
    )
  end

  def test_verify_tree_rejects_an_extra_tree_entry
    assert_create_succeeds
    File.binwrite(File.join(@resources, "unreviewed.txt"), "extra\n")

    assert_inventory_failure(
      "verify-tree", "--app", @app, "--inventory", @inventory,
      message: /candidate tree does not match the complete recorded inventory/
    )
  end

  def test_extract_rejects_archive_digest_drift_before_unpacking
    assert_create_succeeds
    File.open(@archive, "ab") { |file| file.write("tamper") }
    extraction = empty_extraction_directory

    assert_inventory_failure(
      "extract",
      "--inventory", @inventory,
      "--handoff-dir", @handoff,
      "--extract-to", extraction,
      message: /candidate archive size mismatch/
    )
    assert_empty Dir.children(extraction)
  end

  def test_extract_rejects_supplemental_digest_drift_before_unpacking
    assert_create_succeeds
    bytes = File.binread(@supplemental)
    bytes.setbyte(0, bytes.getbyte(0) ^ 1)
    File.binwrite(@supplemental, bytes)
    extraction = empty_extraction_directory

    assert_inventory_failure(
      "extract",
      "--inventory", @inventory,
      "--handoff-dir", @handoff,
      "--extract-to", extraction,
      message: /release admission provenance SHA-256 mismatch/
    )
    assert_empty Dir.children(extraction)
  end

  def test_extract_rejects_an_extra_handoff_entry
    assert_create_succeeds
    File.binwrite(File.join(@handoff, "unreviewed.txt"), "extra\n")

    assert_inventory_failure(
      "extract",
      "--inventory", @inventory,
      "--handoff-dir", @handoff,
      "--extract-to", empty_extraction_directory,
      message: /candidate handoff contains missing or extra entries/
    )
  end

  def test_extract_rejects_a_nonempty_destination
    assert_create_succeeds
    extraction = empty_extraction_directory
    File.binwrite(File.join(extraction, "existing.txt"), "do not overwrite\n")

    assert_inventory_failure(
      "extract",
      "--inventory", @inventory,
      "--handoff-dir", @handoff,
      "--extract-to", extraction,
      message: /candidate extraction destination must be empty/
    )
    assert_equal "do not overwrite\n", File.binread(File.join(extraction, "existing.txt"))
  end

  def test_extract_rejects_a_canonically_encoded_inventory_with_extra_fields
    assert_create_succeeds
    data = JSON.parse(File.binread(@inventory))
    data["unreviewed"] = true
    File.binwrite(@inventory, JSON.pretty_generate(data) << "\n")

    assert_inventory_failure(
      "extract",
      "--inventory", @inventory,
      "--handoff-dir", @handoff,
      "--extract-to", empty_extraction_directory,
      message: /candidate inventory fields must be exactly/
    )
  end

  def test_extract_rejects_noncanonical_inventory_json
    assert_create_succeeds
    data = JSON.parse(File.binread(@inventory))
    File.binwrite(@inventory, JSON.generate(data))

    assert_inventory_failure(
      "extract",
      "--inventory", @inventory,
      "--handoff-dir", @handoff,
      "--extract-to", empty_extraction_directory,
      message: /candidate inventory is not canonical JSON/
    )
  end

  def test_create_rejects_an_absolute_symlink_target
    File.unlink(@configuration_link)
    File.symlink("/private/tmp/outside-vifty", @configuration_link)

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /symlink target .* must be relative/
    )
  end

  def test_create_rejects_a_symlink_target_that_escapes_the_app
    File.unlink(@configuration_link)
    File.symlink("../../../outside-vifty", @configuration_link)

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /symlink target .* escapes Vifty\.app/
    )
  end

  def test_create_rejects_a_chained_symlink_that_resolves_outside_the_app
    FileUtils.mkdir_p(File.join(@root, "outside"))
    File.symlink(".", File.join(@resources, "pivot"))
    File.symlink("pivot/../../../outside", File.join(@resources, "chained-escape"))

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /symlink target .* resolves outside Vifty\.app/
    )
  end

  def test_create_rejects_hard_linked_files
    File.link(@binary, File.join(File.dirname(@binary), "Vifty-copy"))

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /must not be hard linked/
    )
  end

  def test_create_rejects_special_permission_bits
    File.chmod(0o4755, @binary)

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /uses unsupported special permission bits/
    )
  end

  def test_create_round_trip_rejects_archive_tree_drift
    unreviewed = File.join(@resources, "archive-only.txt")
    File.binwrite(unreviewed, "not in the reviewed tree\n")
    build_archive!
    FileUtils.rm_f(unreviewed)

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /candidate tree does not match the complete recorded inventory/
    )
  end

  def test_create_rejects_an_archive_over_the_finite_byte_limit_before_hashing
    File.truncate(@archive, (512 * 1024 * 1024) + 1)

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /candidate archive exceeds 536870912 bytes/
    )
  end

  def test_create_rejects_a_non_zip_archive_before_listing_or_extraction
    File.binwrite(@archive, "\x1f\x8bnot-a-zip".b)

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /candidate archive must be a ZIP archive/
    )
  end

  def test_create_rejects_a_terminal_file_beyond_the_path_depth_limit
    deepest_directory = @resources
    62.times do |index|
      deepest_directory = File.join(deepest_directory, format("d%02d", index))
    end
    FileUtils.mkdir_p(deepest_directory)
    File.binwrite(File.join(deepest_directory, "terminal.txt"), "too deep\n")

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /candidate path exceeds 64 path components/
    )
  end

  def test_load_rejects_an_inventory_over_the_finite_byte_limit_before_reading
    File.open(@inventory, "wb") do |file|
      file.truncate((2 * 1024 * 1024) + 1)
    end

    assert_inventory_failure(
      "verify-tree",
      "--app", @app,
      "--inventory", @inventory,
      message: /candidate inventory exceeds 2097152 bytes/
    )
  end

  def test_load_rejects_too_many_inventory_entries
    assert_create_succeeds
    rewrite_inventory do |data|
      data.fetch("tree")["entries"] = [
        { "path" => ".", "type" => "directory", "mode" => 0o755 }
      ] + Array.new(4_096) do |index|
        {
          "path" => format("bounded/%04d", index),
          "type" => "directory",
          "mode" => 0o755
        }
      end
    end

    assert_inventory_failure(
      "verify-tree",
      "--app", @app,
      "--inventory", @inventory,
      message: /candidate inventory exceeds 4096 entries/
    )
  end

  def test_load_rejects_an_inventory_path_over_the_byte_limit
    assert_create_succeeds
    rewrite_inventory do |data|
      entry = data.fetch("tree").fetch("entries").find { |candidate| candidate["type"] == "file" }
      entry["path"] = "x" * 4_097
    end

    assert_inventory_failure(
      "verify-tree",
      "--app", @app,
      "--inventory", @inventory,
      message: /candidate inventory path exceeds 4096 bytes/
    )
  end

  def test_load_rejects_an_inventory_path_over_the_depth_limit
    assert_create_succeeds
    rewrite_inventory do |data|
      entry = data.fetch("tree").fetch("entries").find { |candidate| candidate["type"] == "file" }
      entry["path"] = Array.new(65, "segment").join("/")
    end

    assert_inventory_failure(
      "verify-tree",
      "--app", @app,
      "--inventory", @inventory,
      message: /candidate inventory path exceeds 64 path components/
    )
  end

  def test_load_rejects_an_inventory_file_over_the_expanded_byte_limit
    assert_create_succeeds
    rewrite_inventory do |data|
      entry = data.fetch("tree").fetch("entries").find { |candidate| candidate["type"] == "file" }
      entry["size"] = (256 * 1024 * 1024) + 1
    end

    assert_inventory_failure(
      "verify-tree",
      "--app", @app,
      "--inventory", @inventory,
      message: /candidate file exceeds 268435456 bytes/
    )
  end

  def test_load_rejects_an_inventory_over_the_total_expanded_byte_limit
    assert_create_succeeds
    rewrite_inventory do |data|
      entries = data.fetch("tree").fetch("entries")
      4.times do |index|
        entries << {
          "path" => format("Synthetic/%02d", index),
          "type" => "file",
          "mode" => 0o644,
          "size" => 256 * 1024 * 1024,
          "sha256" => "0" * 64
        }
      end
      entries.sort_by! { |entry| entry.fetch("path").b }
    end

    assert_inventory_failure(
      "verify-tree",
      "--app", @app,
      "--inventory", @inventory,
      message: /candidate inventory tree exceeds 1073741824 expanded bytes/
    )
  end

  def test_create_rejects_an_archive_entry_over_the_expanded_byte_limit
    mutate_zip_uncompressed_sizes!(count: 1, size: (256 * 1024 * 1024) + 1)

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /candidate archive entry exceeds 268435456 expanded bytes/
    )
  end

  def test_create_rejects_an_archive_over_the_total_expanded_byte_limit
    4.times do |index|
      File.binwrite(File.join(@resources, "fixture-#{index}.txt"), "fixture\n")
    end
    build_archive!
    mutate_zip_uncompressed_sizes!(count: 5, size: 220 * 1024 * 1024)

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /candidate archive exceeds 1073741824 expanded bytes/
    )
  end

  def test_create_stops_an_archive_listing_at_the_streaming_byte_limit
    names = Array.new(1_030) do |index|
      "Vifty.app/#{format('%04d', index)}-#{"x" * 4_070}/"
    end
    write_empty_stored_zip!(names)

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /candidate archive listing is too large/
    )
  end

  def test_create_rejects_too_many_archive_entries
    names = Array.new(4_097) do |index|
      "Vifty.app/bounded-#{format('%04d', index)}/"
    end
    write_empty_stored_zip!(names)

    assert_inventory_failure(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", @inventory,
      message: /candidate archive exceeds 4096 entries/
    )
  end

  def test_extract_public_stages_the_exact_sha_and_extracts_only_vifty_app
    extraction = empty_extraction_directory
    expected_sha = Digest::SHA256.file(@archive).hexdigest

    stdout, stderr, status = inventory_command(
      "extract-public",
      "--archive", @archive,
      "--expected-sha", expected_sha,
      "--extract-to", extraction
    )

    assert status.success?, stderr
    extracted_app = File.join(extraction, "Vifty.app")
    assert_equal "Public release archive verified and extracted: #{extracted_app}\n", stdout
    assert_equal File.binread(@binary),
                 File.binread(File.join(extracted_app, "Contents", "MacOS", "Vifty"))
  end

  def test_extract_public_rejects_sha_drift_before_unpacking
    extraction = empty_extraction_directory

    assert_inventory_failure(
      "extract-public",
      "--archive", @archive,
      "--expected-sha", "0" * 64,
      "--extract-to", extraction,
      message: /candidate archive SHA-256 mismatch/
    )
    assert_empty Dir.children(extraction)
  end

  def test_extract_public_rejects_a_malformed_expected_sha
    assert_inventory_failure(
      "extract-public",
      "--archive", @archive,
      "--expected-sha", "ABC123",
      "--extract-to", empty_extraction_directory,
      message: /--expected-sha must be a lowercase SHA-256 digest/
    )
  end

  def test_extract_public_rejects_a_symlink_archive
    archive_link = File.join(@root, "public-release.zip")
    File.symlink(@archive, archive_link)

    assert_inventory_failure(
      "extract-public",
      "--archive", archive_link,
      "--expected-sha", Digest::SHA256.file(@archive).hexdigest,
      "--extract-to", empty_extraction_directory,
      message: /candidate archive must be a regular non-symlink file/
    )
  end

  def test_extract_public_rejects_an_extra_archive_root
    write_empty_stored_zip!(["Vifty.app/", "outside.txt"])
    extraction = empty_extraction_directory

    assert_inventory_failure(
      "extract-public",
      "--archive", @archive,
      "--expected-sha", Digest::SHA256.file(@archive).hexdigest,
      "--extract-to", extraction,
      message: /candidate archive contains an unexpected top-level entry/
    )
    assert_empty Dir.children(extraction)
  end

  def test_extract_public_rejects_case_colliding_archive_entries
    write_empty_stored_zip!(["Vifty.app/Contents/Thing", "Vifty.app/Contents/thing"])
    extraction = empty_extraction_directory

    assert_inventory_failure(
      "extract-public",
      "--archive", @archive,
      "--expected-sha", Digest::SHA256.file(@archive).hexdigest,
      "--extract-to", extraction,
      message: /candidate archive contains case-colliding entries/
    )
    assert_empty Dir.children(extraction)
  end

  def test_stage_public_copies_exact_bytes_to_the_requested_canonical_name
    stage = File.join(@root, "stage")
    FileUtils.mkdir(stage, mode: 0o700)
    output = File.join(stage, "Vifty-v9.9.9.zip")
    expected_sha = Digest::SHA256.file(@archive).hexdigest

    stdout, stderr, status = inventory_command(
      "stage-public",
      "--archive", @archive,
      "--expected-sha", expected_sha,
      "--output", output
    )

    assert status.success?, stderr
    assert_equal "Public release archive verified and staged: #{output}\n", stdout
    assert_equal File.binread(@archive), File.binread(output)
    assert_equal 0o400, File.stat(output).mode & 0o777
  end

  def test_stage_public_binds_the_final_path_to_the_created_output_inode
    source = File.read(SCRIPT)

    assert_includes source, "staged_identity = stable_stat_identity(output.stat)"
    assert_includes source, 'fail_inventory("staged candidate archive path changed after creation")'
    assert_includes source, "stable_stat_identity(staged) == staged_identity"
  end

  def test_extract_public_can_return_a_stable_complete_tree_digest
    extraction = empty_extraction_directory
    expected_sha = Digest::SHA256.file(@archive).hexdigest

    stdout, stderr, status = inventory_command(
      "extract-public",
      "--archive", @archive,
      "--expected-sha", expected_sha,
      "--extract-to", extraction,
      "--print-content-manifest-sha256"
    )

    assert status.success?, stderr
    digest = stdout.strip
    assert_match(/\A[0-9a-f]{64}\z/, digest)
    verify_stdout, verify_stderr, verify_status = inventory_command(
      "verify-public-tree",
      "--app", File.join(extraction, "Vifty.app"),
      "--expected-content-manifest-sha256", digest
    )
    assert verify_status.success?, verify_stderr
    assert_equal "Candidate tree matches exact public archive content binding.\n", verify_stdout
  end

  def test_public_tree_sha256_uses_the_same_globally_sorted_content_contract
    FileUtils.mkdir_p(File.join(@app, "A"))
    File.binwrite(File.join(@app, "A", "child"), "child\n")
    File.binwrite(File.join(@app, "A.foo"), "sibling\n")

    stdout, stderr, status = inventory_command("public-tree-sha256", "--app", @app)

    assert status.success?, stderr
    assert_match(/\A[0-9a-f]{64}\n\z/, stdout)
    verify_stdout, verify_stderr, verify_status = inventory_command(
      "verify-public-tree",
      "--app", @app,
      "--expected-content-manifest-sha256", stdout.strip
    )
    assert verify_status.success?, verify_stderr
    assert_equal "Candidate tree matches exact public archive content binding.\n", verify_stdout
  end

  def test_verify_public_tree_rejects_post_extraction_mutation
    extraction = empty_extraction_directory
    expected_sha = Digest::SHA256.file(@archive).hexdigest
    stdout, stderr, status = inventory_command(
      "extract-public",
      "--archive", @archive,
      "--expected-sha", expected_sha,
      "--extract-to", extraction,
      "--print-content-manifest-sha256"
    )
    assert status.success?, stderr
    File.binwrite(File.join(extraction, "Vifty.app", "Contents", "MacOS", "Vifty"), "mutated")

    assert_inventory_failure(
      "verify-public-tree",
      "--app", File.join(extraction, "Vifty.app"),
      "--expected-content-manifest-sha256", stdout.strip,
      message: /candidate tree does not match the exact public archive content binding/
    )
  end

  private

  def build_archive!
    FileUtils.rm_f(@archive)
    stdout, stderr, status = Open3.capture3(
      "/usr/bin/ditto",
      "-c", "-k", "--keepParent", "--norsrc", "--noqtn",
      @app, @archive
    )
    assert status.success?, "archive fixture creation failed: #{stdout}#{stderr}"
  end

  def create_inventory(path)
    inventory_command(
      "create",
      "--app", @app,
      "--archive", @archive,
      "--supplemental", @supplemental,
      "--output", path
    )
  end

  def assert_create_succeeds
    stdout, stderr, status = create_inventory(@inventory)
    assert status.success?, stderr
    assert_equal "Candidate inventory created and archive round-trip verified.\n", stdout
  end

  def rewrite_inventory
    data = JSON.parse(File.binread(@inventory))
    yield data
    File.binwrite(@inventory, JSON.pretty_generate(data) << "\n")
  end

  def mutate_zip_uncompressed_sizes!(count:, size:)
    bytes = File.binread(@archive)
    signature = "PK\x01\x02".b
    cursor = 0
    changed = 0
    while changed < count && (offset = bytes.index(signature, cursor))
      name_length = bytes.byteslice(offset + 28, 2).unpack1("v")
      extra_length = bytes.byteslice(offset + 30, 2).unpack1("v")
      comment_length = bytes.byteslice(offset + 32, 2).unpack1("v")
      name = bytes.byteslice(offset + 46, name_length)
      local_offset = bytes.byteslice(offset + 42, 4).unpack1("V")
      unless name.end_with?("/".b)
        bytes[offset + 24, 4] = [size].pack("V")
        bytes[local_offset + 22, 4] = [size].pack("V")
        changed += 1
      end
      cursor = offset + 46 + name_length + extra_length + comment_length
    end
    assert_equal count, changed, "archive fixture did not contain enough non-directory entries"
    File.binwrite(@archive, bytes)
  end

  def write_empty_stored_zip!(names)
    local_records = String.new(encoding: Encoding::BINARY)
    central_records = String.new(encoding: Encoding::BINARY)
    names.each do |name|
      encoded_name = name.b
      local_offset = local_records.bytesize
      local_records << [
        0x04034b50, 20, 0, 0, 0, 0, 0, 0, 0, encoded_name.bytesize, 0
      ].pack("VvvvvvVVVvv")
      local_records << encoded_name
      central_records << [
        0x02014b50, (3 << 8) | 20, 20, 0, 0, 0, 0, 0, 0, 0,
        encoded_name.bytesize, 0, 0, 0, 0, 0o040755 << 16, local_offset
      ].pack("VvvvvvvVVVvvvvvVV")
      central_records << encoded_name
    end
    end_of_central_directory = [
      0x06054b50, 0, 0, names.length, names.length,
      central_records.bytesize, local_records.bytesize, 0
    ].pack("VvvvvVVv")
    File.binwrite(
      @archive,
      local_records << central_records << end_of_central_directory
    )
  end

  def inventory_command(*arguments)
    Open3.capture3("/usr/bin/ruby", SCRIPT, *arguments)
  end

  def assert_inventory_failure(*arguments, message:)
    stdout, stderr, status = inventory_command(*arguments)
    refute status.success?, "command unexpectedly passed: #{arguments.join(' ')}"
    assert_equal 65, status.exitstatus, stderr
    assert_empty stdout
    assert_match message, stderr
  end

  def empty_extraction_directory
    path = File.join(@root, "extract-#{Dir.children(@root).length}")
    FileUtils.mkdir_p(path)
    path
  end
end
