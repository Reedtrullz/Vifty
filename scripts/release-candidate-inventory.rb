#!/usr/bin/ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require "tmpdir"

class CandidateInventoryError < StandardError; end

module ViftyCandidateInventory
  module_function

  SCHEMA_VERSION = 1
  KIND = "vifty-release-candidate-inventory"
  MAX_INVENTORY_BYTES = 2 * 1024 * 1024
  MAX_ARCHIVE_LISTING_BYTES = 4 * 1024 * 1024
  MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
  MAX_SUPPLEMENTAL_BYTES = 16 * 1024 * 1024
  MAX_ENTRY_COUNT = 4_096
  MAX_PATH_BYTES = 4_096
  MAX_PATH_DEPTH = 64
  MAX_FILE_BYTES = 256 * 1024 * 1024
  MAX_TOTAL_EXPANDED_BYTES = 1024 * 1024 * 1024
  MAX_COMMAND_OUTPUT_BYTES = 64 * 1024

  def fail_inventory(message)
    raise CandidateInventoryError, message
  end

  def exact_keys!(value, expected, label)
    fail_inventory("#{label} must be an object") unless value.is_a?(Hash)
    actual = value.keys.sort
    required = expected.sort
    fail_inventory("#{label} fields must be exactly #{required.join(', ')}") unless actual == required
  end

  def regular_file!(path, label)
    stat = File.lstat(path)
    fail_inventory("#{label} must be a regular non-symlink file") unless stat.file?
    fail_inventory("#{label} must not be hard linked") unless stat.nlink == 1
    stat
  rescue Errno::ENOENT, Errno::ENOTDIR
    fail_inventory("#{label} is missing: #{path}")
  end

  def stable_stat_identity(stat)
    [
      stat.dev, stat.ino, stat.mode, stat.uid, stat.gid, stat.nlink, stat.size,
      stat.mtime.to_i, stat.mtime.nsec, stat.ctime.to_i, stat.ctime.nsec
    ]
  end

  def stable_digest(path, label, max_bytes: nil)
    before = regular_file!(path, label)
    if max_bytes && before.size > max_bytes
      fail_inventory("#{label} exceeds #{max_bytes} bytes")
    end
    nofollow = File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0
    digest = Digest::SHA256.new
    bytes_read = 0
    File.open(path, File::RDONLY | File::BINARY | nofollow) do |file|
      opened = file.stat
      fail_inventory("#{label} changed before hashing") unless stable_stat_identity(opened) == stable_stat_identity(before)
      buffer = String.new(capacity: 1024 * 1024, encoding: Encoding::BINARY)
      while file.read(1024 * 1024, buffer)
        bytes_read += buffer.bytesize
        fail_inventory("#{label} exceeds #{max_bytes} bytes") if max_bytes && bytes_read > max_bytes
        digest.update(buffer)
      end
      after_open = file.stat
      fail_inventory("#{label} changed while hashing") unless stable_stat_identity(after_open) == stable_stat_identity(opened)
    end
    after = File.lstat(path)
    fail_inventory("#{label} changed after hashing") unless stable_stat_identity(after) == stable_stat_identity(before)
    [before.size, digest.hexdigest]
  rescue Errno::ELOOP
    fail_inventory("#{label} must not be a symlink")
  end

  def stable_read(path, label, max_bytes:)
    before = regular_file!(path, label)
    fail_inventory("#{label} exceeds #{max_bytes} bytes") if before.size > max_bytes
    nofollow = File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0
    bytes = String.new(capacity: [before.size, max_bytes].min, encoding: Encoding::BINARY)
    File.open(path, File::RDONLY | File::BINARY | nofollow) do |file|
      opened = file.stat
      fail_inventory("#{label} changed before reading") unless stable_stat_identity(opened) == stable_stat_identity(before)
      buffer = String.new(capacity: 64 * 1024, encoding: Encoding::BINARY)
      while file.read(64 * 1024, buffer)
        fail_inventory("#{label} exceeds #{max_bytes} bytes") if bytes.bytesize + buffer.bytesize > max_bytes
        bytes << buffer
      end
      after_open = file.stat
      fail_inventory("#{label} changed while reading") unless stable_stat_identity(after_open) == stable_stat_identity(opened)
    end
    after = File.lstat(path)
    fail_inventory("#{label} changed after reading") unless stable_stat_identity(after) == stable_stat_identity(before)
    bytes
  rescue Errno::ELOOP
    fail_inventory("#{label} must not be a symlink")
  end

  def validate_relative_path!(path, label, allow_root: false)
    fail_inventory("#{label} must be valid UTF-8") unless path.is_a?(String) && path.encoding == Encoding::UTF_8 && path.valid_encoding?
    fail_inventory("#{label} contains a control character") if path.match?(/[\x00-\x1f\x7f]/)
    return if allow_root && path == "."
    fail_inventory("#{label} must be a non-empty relative path") if path.empty? || path.start_with?("/")
    components = path.split("/", -1)
    fail_inventory("#{label} contains an empty, dot, or parent component") if components.any? { |part| part.empty? || part == "." || part == ".." }
    fail_inventory("#{label} exceeds #{MAX_PATH_BYTES} bytes") if path.bytesize > MAX_PATH_BYTES
    fail_inventory("#{label} exceeds #{MAX_PATH_DEPTH} path components") if components.length > MAX_PATH_DEPTH
  end

  def validate_symlink_target!(entry_path, target)
    fail_inventory("symlink target for #{entry_path} must be valid UTF-8") unless
      target.is_a?(String) && target.encoding == Encoding::UTF_8 && target.valid_encoding?
    fail_inventory("symlink target for #{entry_path} contains a control character") if target.match?(/[\x00-\x1f\x7f]/)
    fail_inventory("symlink target for #{entry_path} must be relative") if target.empty? || target.start_with?("/")
    fail_inventory("symlink target for #{entry_path} exceeds #{MAX_PATH_BYTES} bytes") if target.bytesize > MAX_PATH_BYTES
    normalized = Pathname.new(File.join(File.dirname(entry_path), target)).cleanpath.to_s
    if normalized == ".." || normalized.start_with?("../")
      fail_inventory("symlink target for #{entry_path} escapes Vifty.app")
    end
  end

  def entry_mode(stat, label)
    mode = stat.mode & 0o7777
    fail_inventory("#{label} uses unsupported special permission bits") unless (mode & 0o7000).zero?
    mode
  end

  def snapshot_tree(root)
    root = File.expand_path(root)
    root_stat = File.lstat(root)
    fail_inventory("candidate app must be a real directory") unless root_stat.directory? && !File.symlink?(root)
    entries = []
    bounds = { total_expanded_bytes: 0 }
    walk_directory(root, root, ".", entries, bounds)
    sorted = entries.sort_by { |entry| entry.fetch("path").b }
    fail_inventory("candidate tree contains duplicate paths") unless sorted.map { |entry| entry.fetch("path") }.uniq.length == sorted.length
    enforce_tree_bounds!(sorted, "candidate tree")
    sorted
  rescue Errno::ENOENT, Errno::ENOTDIR
    fail_inventory("candidate app is missing: #{root}")
  end

  def walk_directory(root, absolute_path, relative_path, entries, bounds)
    before = File.lstat(absolute_path)
    fail_inventory("candidate directory changed type: #{relative_path}") unless before.directory?
    validate_relative_path!(relative_path, "candidate path", allow_root: true)
    entries << {
      "path" => relative_path,
      "type" => "directory",
      "mode" => entry_mode(before, relative_path)
    }
    fail_inventory("candidate tree exceeds #{MAX_ENTRY_COUNT} entries") if entries.length > MAX_ENTRY_COUNT

    children = Dir.children(absolute_path)
    fail_inventory("candidate directory contains duplicate names: #{relative_path}") unless children.uniq.length == children.length
    children.sort_by(&:b).each do |name|
      validate_relative_path!(name, "candidate path component")
      child_absolute = File.join(absolute_path, name)
      child_relative = relative_path == "." ? name : "#{relative_path}/#{name}"
      validate_relative_path!(child_relative, "candidate path")
      stat = File.lstat(child_absolute)
      mode = entry_mode(stat, child_relative)
      case
      when stat.directory?
        walk_directory(root, child_absolute, child_relative, entries, bounds)
      when stat.file?
        fail_inventory("candidate tree file exceeds #{MAX_FILE_BYTES} bytes") if
          stat.size > MAX_FILE_BYTES
        prospective_total = bounds.fetch(:total_expanded_bytes) + stat.size
        fail_inventory("candidate tree exceeds #{MAX_TOTAL_EXPANDED_BYTES} expanded bytes") if
          prospective_total > MAX_TOTAL_EXPANDED_BYTES
        size, sha = stable_digest(child_absolute, child_relative, max_bytes: MAX_FILE_BYTES)
        bounds[:total_expanded_bytes] += size
        fail_inventory("candidate tree exceeds #{MAX_TOTAL_EXPANDED_BYTES} expanded bytes") if
          bounds.fetch(:total_expanded_bytes) > MAX_TOTAL_EXPANDED_BYTES
        entries << {
          "path" => child_relative,
          "type" => "file",
          "mode" => mode,
          "size" => size,
          "sha256" => sha
        }
      when stat.symlink?
        target = File.readlink(child_absolute)
        target = target.encode(Encoding::UTF_8)
        validate_symlink_target!(child_relative, target)
        begin
          resolved_root = File.realpath(root)
          resolved_target = File.realpath(child_absolute)
        rescue Errno::ENOENT, Errno::ENOTDIR, Errno::ELOOP
          fail_inventory("symlink target for #{child_relative} must resolve inside Vifty.app")
        end
        unless resolved_target == resolved_root || resolved_target.start_with?("#{resolved_root}/")
          fail_inventory("symlink target for #{child_relative} resolves outside Vifty.app")
        end
        after = File.lstat(child_absolute)
        fail_inventory("symlink changed while reading: #{child_relative}") unless
          stable_stat_identity(after) == stable_stat_identity(stat)
        entries << {
          "path" => child_relative,
          "type" => "symlink",
          "mode" => mode,
          "linkTarget" => target
        }
      else
        fail_inventory("candidate tree contains unsupported file type: #{child_relative}")
      end
      fail_inventory("candidate tree exceeds #{MAX_ENTRY_COUNT} entries") if entries.length > MAX_ENTRY_COUNT
    end

    after = File.lstat(absolute_path)
    fail_inventory("candidate directory changed while walking: #{relative_path}") unless
      stable_stat_identity(after) == stable_stat_identity(before)
  end

  def enforce_tree_bounds!(entries, label)
    fail_inventory("#{label} exceeds #{MAX_ENTRY_COUNT} entries") if entries.length > MAX_ENTRY_COUNT
    total = 0
    entries.each do |entry|
      next unless entry["type"] == "file"

      size = entry.fetch("size")
      fail_inventory("#{label} file exceeds #{MAX_FILE_BYTES} bytes") if size > MAX_FILE_BYTES
      total += size
      fail_inventory("#{label} exceeds #{MAX_TOTAL_EXPANDED_BYTES} expanded bytes") if
        total > MAX_TOTAL_EXPANDED_BYTES
    end
  end

  def stable_tree(root)
    first = snapshot_tree(root)
    second = snapshot_tree(root)
    fail_inventory("candidate tree changed between inventory passes") unless first == second
    first
  end

  def canonical_json(value)
    JSON.pretty_generate(value) + "\n"
  end

  def write_inventory(app:, archive:, supplemental:, output:)
    archive = File.expand_path(archive)
    supplemental = File.expand_path(supplemental)
    output = File.expand_path(output)
    archive_size, archive_sha = stable_digest(
      archive,
      "candidate archive",
      max_bytes: MAX_ARCHIVE_BYTES
    )
    supplemental_size, supplemental_sha = stable_digest(
      supplemental,
      "release admission provenance",
      max_bytes: MAX_SUPPLEMENTAL_BYTES
    )
    inventory = {
      "schemaVersion" => SCHEMA_VERSION,
      "kind" => KIND,
      "archive" => {
        "name" => File.basename(archive),
        "size" => archive_size,
        "sha256" => archive_sha
      },
      "tree" => {
        "root" => "Vifty.app",
        "entries" => stable_tree(app)
      },
      "supplementalFiles" => [
        {
          "path" => File.basename(supplemental),
          "size" => supplemental_size,
          "sha256" => supplemental_sha
        }
      ]
    }
    FileUtils.mkdir_p(File.dirname(output))
    temporary = "#{output}.tmp.#{$$}"
    File.binwrite(temporary, canonical_json(inventory))
    File.rename(temporary, output)
    inventory
  ensure
    FileUtils.rm_f(temporary) if defined?(temporary) && temporary && File.exist?(temporary)
  end

  def load_inventory(path)
    path = File.expand_path(path)
    bytes = stable_read(path, "candidate inventory", max_bytes: MAX_INVENTORY_BYTES)
    data = JSON.parse(bytes)
    fail_inventory("candidate inventory is not canonical JSON") unless bytes == canonical_json(data)
    exact_keys!(data, %w[archive kind schemaVersion supplementalFiles tree], "candidate inventory")
    fail_inventory("candidate inventory schemaVersion mismatch") unless data["schemaVersion"] == SCHEMA_VERSION
    fail_inventory("candidate inventory kind mismatch") unless data["kind"] == KIND

    archive = data["archive"]
    exact_keys!(archive, %w[name sha256 size], "candidate inventory archive")
    validate_relative_path!(archive["name"], "candidate archive name")
    fail_inventory("candidate archive name must be a basename") unless File.basename(archive["name"]) == archive["name"]
    fail_inventory("candidate archive size must be a nonnegative integer") unless archive["size"].is_a?(Integer) && archive["size"] >= 0
    fail_inventory("candidate archive exceeds #{MAX_ARCHIVE_BYTES} bytes") if archive["size"] > MAX_ARCHIVE_BYTES
    fail_inventory("candidate archive SHA-256 is invalid") unless archive["sha256"].is_a?(String) && archive["sha256"].match?(/\A[0-9a-f]{64}\z/)

    tree = data["tree"]
    exact_keys!(tree, %w[entries root], "candidate inventory tree")
    fail_inventory("candidate inventory root must be Vifty.app") unless tree["root"] == "Vifty.app"
    validate_entries!(tree["entries"])

    supplemental = data["supplementalFiles"]
    fail_inventory("candidate inventory must contain exactly one supplemental file") unless supplemental.is_a?(Array) && supplemental.length == 1
    exact_keys!(supplemental.first, %w[path sha256 size], "candidate supplemental file")
    validate_relative_path!(supplemental.first["path"], "candidate supplemental path")
    fail_inventory("candidate supplemental path must be a basename") unless File.basename(supplemental.first["path"]) == supplemental.first["path"]
    fail_inventory("candidate supplemental size must be a nonnegative integer") unless supplemental.first["size"].is_a?(Integer) && supplemental.first["size"] >= 0
    fail_inventory("candidate supplemental file exceeds #{MAX_SUPPLEMENTAL_BYTES} bytes") if
      supplemental.first["size"] > MAX_SUPPLEMENTAL_BYTES
    fail_inventory("candidate supplemental SHA-256 is invalid") unless supplemental.first["sha256"].is_a?(String) && supplemental.first["sha256"].match?(/\A[0-9a-f]{64}\z/)
    data
  rescue JSON::ParserError => error
    fail_inventory("candidate inventory is not valid JSON: #{error.message}")
  end

  def validate_entries!(entries)
    fail_inventory("candidate inventory entries must be a non-empty array") unless entries.is_a?(Array) && !entries.empty?
    fail_inventory("candidate inventory exceeds #{MAX_ENTRY_COUNT} entries") if entries.length > MAX_ENTRY_COUNT
    paths = []
    entries.each do |entry|
      fail_inventory("candidate inventory entry must be an object") unless entry.is_a?(Hash)
      type = entry["type"]
      expected = case type
                 when "directory" then %w[mode path type]
                 when "file" then %w[mode path sha256 size type]
                 when "symlink" then %w[linkTarget mode path type]
                 else fail_inventory("candidate inventory entry has unsupported type")
                 end
      exact_keys!(entry, expected, "candidate inventory entry")
      validate_relative_path!(entry["path"], "candidate inventory path", allow_root: true)
      fail_inventory("candidate inventory mode is invalid") unless entry["mode"].is_a?(Integer) && entry["mode"].between?(0, 0o777)
      if type == "file"
        fail_inventory("candidate file size is invalid") unless entry["size"].is_a?(Integer) && entry["size"] >= 0
        fail_inventory("candidate file exceeds #{MAX_FILE_BYTES} bytes") if entry["size"] > MAX_FILE_BYTES
        fail_inventory("candidate file SHA-256 is invalid") unless entry["sha256"].is_a?(String) && entry["sha256"].match?(/\A[0-9a-f]{64}\z/)
      elsif type == "symlink"
        validate_symlink_target!(entry["path"], entry["linkTarget"])
      end
      paths << entry["path"]
    end
    fail_inventory("candidate inventory entries must be byte-sorted") unless paths == paths.sort_by(&:b)
    fail_inventory("candidate inventory entries contain duplicates") unless paths.uniq.length == paths.length
    fail_inventory("candidate inventory must start with the root directory") unless
      entries.first == { "path" => ".", "type" => "directory", "mode" => entries.first["mode"] }
    enforce_tree_bounds!(entries, "candidate inventory tree")
  end

  def verify_recorded_file(path, record, label, max_bytes:)
    size, sha = stable_digest(path, label, max_bytes: max_bytes)
    fail_inventory("#{label} size mismatch") unless size == record.fetch("size")
    fail_inventory("#{label} SHA-256 mismatch") unless sha == record.fetch("sha256")
  end

  def read_bounded_stream(io, limit, process_id)
    bytes = String.new(capacity: [limit, 64 * 1024].min, encoding: Encoding::BINARY)
    exceeded = false
    begin
      loop do
        chunk = io.readpartial(64 * 1024)
        exceeds_limit = bytes.bytesize + chunk.bytesize > limit
        if bytes.bytesize < limit
          bytes << chunk.byteslice(0, limit - bytes.bytesize)
        end
        next unless !exceeded && exceeds_limit

        exceeded = true
        begin
          Process.kill("TERM", process_id)
        rescue Errno::ESRCH
          nil
        end
      end
    rescue EOFError, IOError
      nil
    ensure
      io.close unless io.closed?
    end
    [bytes, exceeded]
  end

  def run_bounded_command(command, stdout_limit:, stderr_limit:)
    result = nil
    environment = {
      "LANG" => "C",
      "LC_ALL" => "C",
      "TAR_OPTIONS" => nil
    }
    Open3.popen3(environment, *command) do |stdin, stdout, stderr, wait_thread|
      stdin.close
      stdout_reader = Thread.new do
        read_bounded_stream(stdout, stdout_limit, wait_thread.pid)
      end
      stderr_reader = Thread.new do
        read_bounded_stream(stderr, stderr_limit, wait_thread.pid)
      end
      status = wait_thread.value
      stdout_bytes, stdout_exceeded = stdout_reader.value
      stderr_bytes, stderr_exceeded = stderr_reader.value
      result = [stdout_bytes, stderr_bytes, status, stdout_exceeded, stderr_exceeded]
    end
    result
  rescue Errno::ENOENT
    fail_inventory("required archive tool is missing: #{command.first}")
  end

  def archive_listing_lines(bytes)
    lines = bytes.split("\n", -1)
    lines.pop if lines.last == ""
    lines
  end

  def require_zip_archive!(archive)
    before = regular_file!(archive, "staged candidate archive")
    nofollow = File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0
    signature = nil
    File.open(archive, File::RDONLY | File::BINARY | nofollow) do |file|
      opened = file.stat
      fail_inventory("staged candidate archive changed before format validation") unless
        stable_stat_identity(opened) == stable_stat_identity(before)
      signature = file.read(4)
      fail_inventory("staged candidate archive changed during format validation") unless
        stable_stat_identity(file.stat) == stable_stat_identity(opened)
    end
    after = File.lstat(archive)
    fail_inventory("staged candidate archive changed after format validation") unless
      stable_stat_identity(after) == stable_stat_identity(before)
    fail_inventory("candidate archive must be a ZIP archive") unless signature == "PK\x03\x04".b
  rescue Errno::ELOOP
    fail_inventory("staged candidate archive must not be a symlink")
  end

  def preflight_archive_listing(archive)
    archive_stat = regular_file!(archive, "staged candidate archive")
    fail_inventory("candidate archive exceeds #{MAX_ARCHIVE_BYTES} bytes") if
      archive_stat.size > MAX_ARCHIVE_BYTES
    require_zip_archive!(archive)

    stdout, stderr, status, stdout_exceeded, stderr_exceeded = run_bounded_command(
      ["/usr/bin/bsdtar", "-tf", archive],
      stdout_limit: MAX_ARCHIVE_LISTING_BYTES,
      stderr_limit: MAX_COMMAND_OUTPUT_BYTES
    )
    fail_inventory("candidate archive listing is too large") if stdout_exceeded
    fail_inventory("candidate archive listing diagnostics are too large") if stderr_exceeded
    fail_inventory("candidate archive listing failed: #{stderr.strip}") unless status.success?
    names = archive_listing_lines(stdout)
    fail_inventory("candidate archive is empty") if names.empty?
    fail_inventory("candidate archive exceeds #{MAX_ENTRY_COUNT} entries") if names.length > MAX_ENTRY_COUNT
    normalized = names.map do |raw_name|
      name = raw_name.dup.force_encoding(Encoding::UTF_8)
      fail_inventory("candidate archive entry must be valid UTF-8") unless name.valid_encoding?
      name = name.delete_suffix("/")
      validate_relative_path!(name, "candidate archive entry")
      components = name.split("/")
      fail_inventory("candidate archive contains an unexpected top-level entry") unless components.first == "Vifty.app"
      name
    end
    fail_inventory("candidate archive contains duplicate entries") unless normalized.uniq.length == normalized.length

    verbose, verbose_stderr, verbose_status, verbose_exceeded, verbose_stderr_exceeded =
      run_bounded_command(
        ["/usr/bin/bsdtar", "--numeric-owner", "-tvf", archive],
        stdout_limit: MAX_ARCHIVE_LISTING_BYTES,
        stderr_limit: MAX_COMMAND_OUTPUT_BYTES
      )
    fail_inventory("candidate archive verbose listing is too large") if verbose_exceeded
    fail_inventory("candidate archive verbose listing diagnostics are too large") if verbose_stderr_exceeded
    fail_inventory("candidate archive verbose listing failed: #{verbose_stderr.strip}") unless verbose_status.success?
    verbose_lines = archive_listing_lines(verbose)
    fail_inventory("candidate archive listings disagree on entry count") unless
      verbose_lines.length == names.length

    total_expanded = 0
    verbose_lines.each do |line|
      fields = line.split(/\s+/, 9)
      fail_inventory("candidate archive verbose listing is malformed") unless
        fields.length == 9 && fields[4].match?(/\A[0-9]+\z/)
      entry_type = fields[0].slice(0)
      fail_inventory("candidate archive contains an unsupported entry type") unless
        ["-", "d", "l"].include?(entry_type)
      size = Integer(fields[4], 10)
      fail_inventory("candidate archive entry exceeds #{MAX_FILE_BYTES} expanded bytes") if
        size > MAX_FILE_BYTES
      total_expanded += size
      fail_inventory("candidate archive exceeds #{MAX_TOTAL_EXPANDED_BYTES} expanded bytes") if
        total_expanded > MAX_TOTAL_EXPANDED_BYTES
    end
  end

  def stage_verified_archive(source, record, staging_directory)
    source = File.expand_path(source)
    target = File.join(staging_directory, "candidate-archive.zip")
    before = regular_file!(source, "candidate archive")
    fail_inventory("candidate archive exceeds #{MAX_ARCHIVE_BYTES} bytes") if before.size > MAX_ARCHIVE_BYTES
    nofollow = File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : 0
    digest = Digest::SHA256.new
    copied = 0
    completed = false

    File.open(source, File::RDONLY | File::BINARY | nofollow) do |input|
      opened = input.stat
      fail_inventory("candidate archive changed before staging") unless
        stable_stat_identity(opened) == stable_stat_identity(before)
      File.open(
        target,
        File::WRONLY | File::CREAT | File::EXCL | File::BINARY | nofollow,
        0o600
      ) do |output|
        buffer = String.new(capacity: 1024 * 1024, encoding: Encoding::BINARY)
        while input.read(1024 * 1024, buffer)
          copied += buffer.bytesize
          fail_inventory("candidate archive exceeds #{MAX_ARCHIVE_BYTES} bytes") if
            copied > MAX_ARCHIVE_BYTES
          output.write(buffer)
          digest.update(buffer)
        end
        output.flush
        output.fsync
        output.chmod(0o400)
      end
      fail_inventory("candidate archive changed while staging") unless
        stable_stat_identity(input.stat) == stable_stat_identity(opened)
    end

    after = File.lstat(source)
    fail_inventory("candidate archive changed after staging") unless
      stable_stat_identity(after) == stable_stat_identity(before)
    fail_inventory("candidate archive size mismatch") unless copied == record.fetch("size")
    fail_inventory("candidate archive SHA-256 mismatch") unless digest.hexdigest == record.fetch("sha256")
    staged = regular_file!(target, "staged candidate archive")
    fail_inventory("staged candidate archive has unsafe permissions") unless
      (staged.mode & 0o777) == 0o400
    fail_inventory("staged candidate archive size mismatch") unless staged.size == copied
    completed = true
    target
  rescue Errno::ELOOP
    fail_inventory("candidate archive must not be a symlink")
  ensure
    FileUtils.rm_f(target) if defined?(target) && target && !completed && File.exist?(target)
  end

  def with_staged_verified_archive(source, record)
    result = nil
    Dir.mktmpdir("vifty-candidate-stage.") do |staging_directory|
      File.chmod(0o700, staging_directory)
      staged_archive = stage_verified_archive(source, record, staging_directory)
      File.chmod(0o500, staging_directory)
      begin
        result = yield staged_archive
      ensure
        File.chmod(0o700, staging_directory)
      end
    end
    result
  end

  def extract_archive(archive:, destination:)
    destination = File.expand_path(destination)
    stat = File.lstat(destination)
    fail_inventory("candidate extraction destination must be a real directory") unless stat.directory? && !File.symlink?(destination)
    fail_inventory("candidate extraction destination must be empty") unless Dir.children(destination).empty?
    File.chmod(0o700, destination)
    preflight_archive_listing(archive)
    _stdout, stderr, status, stdout_exceeded, stderr_exceeded = run_bounded_command(
      [
        "/usr/bin/bsdtar", "-xkf", archive, "-C", destination,
        "--no-same-owner", "--no-acls", "--no-xattrs", "--no-mac-metadata", "--no-fflags"
      ],
      stdout_limit: MAX_COMMAND_OUTPUT_BYTES,
      stderr_limit: MAX_COMMAND_OUTPUT_BYTES
    )
    fail_inventory("candidate archive extraction output is too large") if stdout_exceeded
    fail_inventory("candidate archive extraction diagnostics are too large") if stderr_exceeded
    fail_inventory("candidate archive extraction failed: #{stderr.strip}") unless status.success?
    fail_inventory("candidate archive must extract only Vifty.app") unless Dir.children(destination) == ["Vifty.app"]
    File.join(destination, "Vifty.app")
  rescue Errno::ENOENT, Errno::ENOTDIR
    fail_inventory("candidate extraction destination is missing: #{destination}")
  end

  def verify_tree(app:, inventory:)
    expected = inventory.fetch("tree").fetch("entries")
    actual = stable_tree(app)
    fail_inventory("candidate tree does not match the complete recorded inventory") unless actual == expected
  end

  def verify_handoff(handoff_dir:, inventory_path:, extract_to:)
    handoff_dir = File.expand_path(handoff_dir)
    inventory_path = File.expand_path(inventory_path)
    inventory = load_inventory(inventory_path)
    archive_record = inventory.fetch("archive")
    supplemental_record = inventory.fetch("supplementalFiles").fetch(0)
    expected_children = [
      archive_record.fetch("name"),
      File.basename(inventory_path),
      supplemental_record.fetch("path")
    ].sort_by(&:b)
    fail_inventory("candidate handoff contains missing or extra entries") unless
      Dir.children(handoff_dir).sort_by(&:b) == expected_children
    archive = File.join(handoff_dir, archive_record.fetch("name"))
    supplemental = File.join(handoff_dir, supplemental_record.fetch("path"))
    verify_recorded_file(
      supplemental,
      supplemental_record,
      "release admission provenance",
      max_bytes: MAX_SUPPLEMENTAL_BYTES
    )
    app = with_staged_verified_archive(archive, archive_record) do |staged_archive|
      extracted_app = extract_archive(archive: staged_archive, destination: extract_to)
      verify_tree(app: extracted_app, inventory: inventory)
      extracted_app
    end
    verify_recorded_file(
      archive,
      archive_record,
      "candidate archive",
      max_bytes: MAX_ARCHIVE_BYTES
    )
    verify_recorded_file(
      supplemental,
      supplemental_record,
      "release admission provenance",
      max_bytes: MAX_SUPPLEMENTAL_BYTES
    )
    fail_inventory("candidate handoff changed during verification") unless
      Dir.children(handoff_dir).sort_by(&:b) == expected_children
    app
  rescue Errno::ENOENT, Errno::ENOTDIR
    fail_inventory("candidate handoff directory is missing: #{handoff_dir}")
  end
end

options = {}
command = ARGV.shift
parser = OptionParser.new do |opts|
  opts.banner = "Usage: scripts/release-candidate-inventory.rb <create|extract|verify-tree> [options]"
  opts.on("--app PATH") { |value| options[:app] = value }
  opts.on("--archive PATH") { |value| options[:archive] = value }
  opts.on("--supplemental PATH") { |value| options[:supplemental] = value }
  opts.on("--output PATH") { |value| options[:output] = value }
  opts.on("--inventory PATH") { |value| options[:inventory] = value }
  opts.on("--handoff-dir PATH") { |value| options[:handoff_dir] = value }
  opts.on("--extract-to PATH") { |value| options[:extract_to] = value }
end

begin
  parser.parse!
  ViftyCandidateInventory.fail_inventory("unexpected positional arguments: #{ARGV.join(' ')}") unless ARGV.empty?
  case command
  when "create"
    %i[app archive supplemental output].each do |key|
      ViftyCandidateInventory.fail_inventory("--#{key} is required") if options[key].to_s.empty?
    end
    inventory = ViftyCandidateInventory.write_inventory(
      app: options[:app],
      archive: options[:archive],
      supplemental: options[:supplemental],
      output: options[:output]
    )
    ViftyCandidateInventory.with_staged_verified_archive(
      options[:archive],
      inventory.fetch("archive")
    ) do |staged_archive|
      Dir.mktmpdir("vifty-candidate-roundtrip.") do |temporary|
        app = ViftyCandidateInventory.extract_archive(
          archive: staged_archive,
          destination: temporary
        )
        ViftyCandidateInventory.verify_tree(app: app, inventory: inventory)
      end
    end
    puts "Candidate inventory created and archive round-trip verified."
  when "extract"
    %i[inventory handoff_dir extract_to].each do |key|
      ViftyCandidateInventory.fail_inventory("--#{key.to_s.tr('_', '-')} is required") if options[key].to_s.empty?
    end
    app = ViftyCandidateInventory.verify_handoff(
      handoff_dir: options[:handoff_dir],
      inventory_path: options[:inventory],
      extract_to: options[:extract_to]
    )
    puts "Candidate handoff verified and extracted: #{app}"
  when "verify-tree"
    %i[app inventory].each do |key|
      ViftyCandidateInventory.fail_inventory("--#{key} is required") if options[key].to_s.empty?
    end
    inventory = ViftyCandidateInventory.load_inventory(options[:inventory])
    ViftyCandidateInventory.verify_tree(app: options[:app], inventory: inventory)
    puts "Candidate tree matches complete inventory."
  else
    ViftyCandidateInventory.fail_inventory("command must be create, extract, or verify-tree")
  end
rescue OptionParser::ParseError, CandidateInventoryError, JSON::ParserError => error
  warn "error: #{error.message}"
  exit 65
end
