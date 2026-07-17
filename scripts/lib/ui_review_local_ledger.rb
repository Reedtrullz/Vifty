# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "securerandom"
require "time"
require_relative "ui_review_contract"
require_relative "ui_review_build_provenance"

module ViftyUIReview
  module LocalLedger
    TEMPLATE_RELATIVE_PATH = "docs/ui-review/evidence-manifest.json"
    OUTPUT_RELATIVE_PATH = "docs/ui-review/evidence-manifest.local.json"
    ARCHIVE_RELATIVE_ROOT = ".build/ui-review-evidence-archive/local-ledgers"
    TEMPORARY_RELATIVE_ROOT = ".build/ui-review-ledger-tmp"
    LOCK_RELATIVE_PATH = ".build/ui-review-ledger.lock"
    DEBUG_RELATIVE_PATH = ".build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty"
    RELEASE_RELATIVE_PATH = ".build/ui-review-products/release/Vifty"
    COLLECTOR_RELATIVE_PATH = ".build/ui-review-products/debug/ViftyAXCollector"
    MAX_TEMPLATE_BYTES = 2 * 1_024 * 1_024
    MAX_LEDGER_BYTES = 16 * 1_024 * 1_024
    MAX_EXECUTABLE_BYTES = 256 * 1_024 * 1_024
    RELEASE_FORBIDDEN_MARKERS = ["--ui-review-fixture", "ViftyReviewFixture"].freeze
    SOURCE_OBJECT_PATTERN = /\A[a-f0-9]{40}\z/
    SHA256_PATTERN = /\A[a-f0-9]{64}\z/
    LOCK_TIMEOUT_SECONDS = 5.0
    LOCK_POLL_SECONDS = 0.02

    class LedgerError < StandardError
      attr_reader :exit_code

      def initialize(message, exit_code: 65)
        super(message)
        @exit_code = exit_code
      end
    end

    Snapshot = Struct.new(:path, :data, :sha256, :device, :inode, :mode, keyword_init: true)

    module_function

    def initialize!(repository_root:, now: Time.now.utc)
      root = verified_repository_root(repository_root)
      verify_local_paths_are_ignored!(root)
      lock = acquire_repository_lock!(root)
      begin
        initialize_locked!(root, now: now)
      ensure
        release_lock(lock)
      end
    rescue BuildProvenance::ProvenanceError => error
      raise LedgerError, "UI review product provenance is invalid: #{error.message}"
    rescue JSON::ParserError => error
      raise LedgerError, "UI review template is invalid JSON: #{error.message}"
    rescue SystemCallError => error
      raise LedgerError, "local UI review ledger initialization failed: #{error.message}"
    end

    def initialize_locked!(root, now:)
      head, tree = verified_repository_state(root)
      template_path = File.join(root, TEMPLATE_RELATIVE_PATH)
      output_path = File.join(root, OUTPUT_RELATIVE_PATH)
      template = snapshot_regular_file(template_path, "tracked UI review template", MAX_TEMPLATE_BYTES)
      verify_tracked_template!(root, template)
      template_document = parse_object(template.data, "tracked UI review template")
      verify_empty_template!(template_document)

      products = canonical_product_snapshots(root)
      provenance = extract_product_provenance!(products, expected_commit: head, expected_tree: tree)
      verify_release_marker_exclusion!(products.fetch("release-exclusion").data)

      document = deep_copy(template_document)
      release = products.fetch("release-exclusion")
      document["releaseExclusion"] = {
        "status" => "passed",
        "binary" => RELEASE_RELATIVE_PATH,
        "sha256" => release.sha256,
        "buildProvenance" => provenance.dig("products", "release-exclusion"),
        "forbiddenMarkers" => RELEASE_FORBIDDEN_MARKERS
      }
      verify_capture_binding!(
        manifest: document,
        debug_provenance: provenance.dig("products", "debug-fixture-app"),
        collector_provenance: provenance.dig("products", "ax-collector")
      )
      verify_initialized_document!(document)
      contents = ViftyUIReview.canonical_json(document) + "\n"

      output_before = optional_snapshot(output_path, "existing local UI review ledger", MAX_LEDGER_BYTES)
      archive_path = archive_existing!(root, output_before, now: now) if output_before
      temporary = write_temporary!(root, output_path, contents)
      begin
        verified_repository_state(root, expected_head: head, expected_tree: tree)
        assert_snapshot_unchanged!(template, "tracked UI review template")
        products.each_value { |snapshot| assert_snapshot_unchanged!(snapshot, "UI review product") }
        assert_optional_snapshot_unchanged!(output_path, output_before)
        verify_tracked_template!(root, template)
        File.rename(temporary, output_path)
        temporary = nil
        fsync_directory(File.dirname(output_path))
        published = snapshot_regular_file(output_path, "published local UI review ledger", MAX_LEDGER_BYTES)
        unless published.data == contents && published.mode & 0o777 == 0o600
          raise LedgerError, "published local UI review ledger failed content or permission readback"
        end
      ensure
        File.unlink(temporary) if temporary && File.exist?(temporary) && !File.symlink?(temporary)
      end

      {
        "status" => "initialized",
        "sourceCommit" => head,
        "sourceTree" => tree,
        "buildTransactionID" => provenance.fetch("buildTransactionID"),
        "manifest" => OUTPUT_RELATIVE_PATH,
        "manifestSHA256" => Digest::SHA256.hexdigest(contents),
        "archivedPreviousLedger" => archive_path && Pathname.new(archive_path).relative_path_from(Pathname.new(root)).to_s
      }
    end

    def verify_capture_binding!(manifest:, debug_provenance:, collector_provenance: nil)
      unless manifest.is_a?(Hash)
        raise LedgerError, "local UI review ledger must be a JSON object"
      end
      release = manifest["releaseExclusion"]
      expected_keys = %w[status binary sha256 buildProvenance forbiddenMarkers].sort
      unless release.is_a?(Hash) && release.keys.sort == expected_keys
        raise LedgerError, "local UI review ledger release exclusion is malformed"
      end
      raise LedgerError, "local UI review ledger release exclusion is not passed" unless release["status"] == "passed"
      unless release["binary"] == RELEASE_RELATIVE_PATH
        raise LedgerError, "local UI review ledger release binary path is not canonical"
      end
      unless release["forbiddenMarkers"] == RELEASE_FORBIDDEN_MARKERS
        raise LedgerError, "local UI review ledger release marker contract is stale"
      end
      unless SHA256_PATTERN.match?(release["sha256"].to_s)
        raise LedgerError, "local UI review ledger release checksum is invalid"
      end

      release_provenance = release["buildProvenance"]
      verify_product_document!(release_provenance, "release-exclusion", "release")
      verify_product_document!(debug_provenance, "debug-fixture-app", "debug")
      verify_matching_identity!(release_provenance, debug_provenance, "debug fixture")
      if collector_provenance
        verify_product_document!(collector_provenance, "ax-collector", "debug")
        verify_matching_identity!(release_provenance, collector_provenance, "AX collector")
      end
      true
    end

    def verify_initialized_document!(document)
      unless document.is_a?(Hash)
        raise LedgerError, "initialized local UI review ledger must be a JSON object"
      end
      release = document["releaseExclusion"]
      expected_release_keys = %w[status binary sha256 buildProvenance forbiddenMarkers].sort
      unless release.is_a?(Hash) && release.keys.sort == expected_release_keys &&
             release["status"] == "passed" &&
             release["binary"] == RELEASE_RELATIVE_PATH &&
             SHA256_PATTERN.match?(release["sha256"].to_s) &&
             release["forbiddenMarkers"] == RELEASE_FORBIDDEN_MARKERS
        raise LedgerError, "initialized local UI review ledger release exclusion is malformed"
      end
      verify_product_document!(release["buildProvenance"], "release-exclusion", "release")

      pending_shape = deep_copy(document)
      pending_shape["releaseExclusion"] = {
        "status" => "pending",
        "binary" => RELEASE_RELATIVE_PATH,
        "sha256" => nil,
        "buildProvenance" => nil,
        "forbiddenMarkers" => RELEASE_FORBIDDEN_MARKERS
      }
      verify_empty_template!(pending_shape)
      true
    end

    def verify_actual_product_binding!(
      manifest_path:,
      manifest:,
      debug_path:,
      debug_sha256:,
      debug_provenance:,
      collector_path: nil,
      collector_sha256: nil,
      collector_provenance: nil
    )
      root = canonical_repository_root_for_manifest(manifest_path)
      unless root
        return verify_capture_binding!(
          manifest: manifest,
          debug_provenance: debug_provenance,
          collector_provenance: collector_provenance
        )
      end

      head, tree = verified_repository_state(root)
      products = canonical_product_snapshots(root)
      actual = extract_product_provenance!(
        products,
        expected_commit: head,
        expected_tree: tree
      )
      verify_release_marker_exclusion!(products.fetch("release-exclusion").data)
      actual_debug = products.fetch("debug-fixture-app")
      actual_release = products.fetch("release-exclusion")
      actual_collector = products.fetch("ax-collector")
      unless actual_debug.path == debug_path && actual_debug.sha256 == debug_sha256 &&
             actual.dig("products", "debug-fixture-app") == debug_provenance
        raise LedgerError, "debug fixture does not match the canonical current product transaction"
      end
      release = manifest["releaseExclusion"]
      unless release.is_a?(Hash) && release["sha256"] == actual_release.sha256
        raise LedgerError, "local UI review ledger release checksum does not match the actual canonical binary"
      end
      if collector_path || collector_sha256 || collector_provenance
        unless actual_collector.path == collector_path &&
               actual_collector.sha256 == collector_sha256 &&
               actual.dig("products", "ax-collector") == collector_provenance
          raise LedgerError, "AX collector does not match the canonical current product transaction"
        end
      end
      verify_capture_binding!(
        manifest: manifest,
        debug_provenance: actual.dig("products", "debug-fixture-app"),
        collector_provenance: actual.dig("products", "ax-collector")
      )
      true
    rescue BuildProvenance::ProvenanceError => error
      raise LedgerError, "UI review product provenance is invalid: #{error.message}"
    end

    def verify_empty_template!(document)
      expected_top_level = %w[
        schemaVersion status evidenceKind fixtureStates fixtureReports visualCells
        accessibilityChecks captureLedger safetyContract releaseExclusion
        humanAttestations nonClaims
      ].sort
      unless document.keys.sort == expected_top_level
        raise LedgerError, "tracked UI review template keys do not match the bounded contract"
      end
      raise LedgerError, "tracked UI review template schemaVersion must be 3" unless document["schemaVersion"] == SCHEMA_VERSION
      raise LedgerError, "tracked UI review template must remain pending" unless document["status"] == "pending"
      unless document["evidenceKind"] == "hardware-free-native-container-debug-fixture"
        raise LedgerError, "tracked UI review template evidence kind is stale"
      end
      unless document["fixtureStates"] == STATES
        raise LedgerError, "tracked UI review template fixture states are stale"
      end
      verify_pending_rows!(document["fixtureReports"], EXPECTED_FIXTURE_REQUESTS, "state", "fixture")
      verify_pending_rows!(document["visualCells"], EXPECTED_VISUAL_REQUESTS, "id", "visual")
      verify_pending_rows!(document["accessibilityChecks"], EXPECTED_AX_REQUESTS, "id", "accessibility")
      raise LedgerError, "tracked UI review template capture ledger must be empty" unless document["captureLedger"] == {}
      expected_release = {
        "status" => "pending",
        "binary" => RELEASE_RELATIVE_PATH,
        "sha256" => nil,
        "buildProvenance" => nil,
        "forbiddenMarkers" => RELEASE_FORBIDDEN_MARKERS
      }
      unless document["releaseExclusion"] == expected_release
        raise LedgerError, "tracked UI review template release exclusion must be empty and pending"
      end
      expected_human = {
        "visual" => { "status" => "pending", "artifact" => "attestations/visual-attestation.json", "sha256" => nil },
        "voiceOver" => { "status" => "pending", "artifact" => "attestations/voiceover-attestation.json", "sha256" => nil }
      }
      unless document["humanAttestations"] == expected_human
        raise LedgerError, "tracked UI review template human attestations must be empty and pending"
      end
      safety = document["safetyContract"]
      unless safety.is_a?(Hash) &&
             safety["attemptedHardwareCommands"] == 0 &&
             safety["attemptedExternalMutations"] == 0 &&
             safety["realControlPathConstructions"] == 0 &&
             safety["modelStartSkipped"] == true &&
             safety["finalReportRequired"] == true &&
             safety["captureLinkRequired"] == true &&
             safety["observedEnvironmentRequired"] == true &&
             safety["observedNSWindowRequired"] == true
        raise LedgerError, "tracked UI review template safety contract is not fail-closed"
      end
      true
    end

    def verified_repository_root(path)
      expanded = File.expand_path(path.to_s)
      status = File.lstat(expanded)
      raise LedgerError, "repository root must be a non-symlink directory" unless status.directory? && !status.symlink?
      root = File.realpath(expanded)
      top = git_output(root, "rev-parse", "--show-toplevel").strip
      unless File.realpath(top) == root
        raise LedgerError, "--repository-root must be the exact Git repository root"
      end
      root
    end

    def verified_repository_state(root, expected_head: nil, expected_tree: nil)
      head = git_output(root, "rev-parse", "HEAD").strip
      tree = git_output(root, "rev-parse", "HEAD^{tree}").strip
      unless SOURCE_OBJECT_PATTERN.match?(head) && SOURCE_OBJECT_PATTERN.match?(tree)
        raise LedgerError, "repository HEAD and tree must be full lowercase Git object IDs"
      end
      raise LedgerError, "repository HEAD changed during initialization" if expected_head && head != expected_head
      raise LedgerError, "repository tree changed during initialization" if expected_tree && tree != expected_tree
      status = git_output(root, "status", "--porcelain=v1", "-z", "--untracked-files=all")
      unless status.empty?
        raise LedgerError, "repository must be clean before initializing local UI evidence"
      end
      [head, tree]
    end

    def git_output(root, *arguments)
      stdout, stderr, status = Open3.capture3("/usr/bin/git", "-C", root, *arguments)
      return stdout if status.success?

      detail = stderr.strip
      raise LedgerError, "Git command failed#{detail.empty? ? "" : ": #{detail}"}"
    end

    def verify_tracked_template!(root, snapshot)
      tracked = git_output(root, "ls-files", "--error-unmatch", "--", TEMPLATE_RELATIVE_PATH).strip
      raise LedgerError, "UI review template must be tracked at #{TEMPLATE_RELATIVE_PATH}" unless tracked == TEMPLATE_RELATIVE_PATH
      head_bytes = git_output(root, "show", "HEAD:#{TEMPLATE_RELATIVE_PATH}").b
      unless snapshot.data == head_bytes
        raise LedgerError, "tracked UI review template differs from HEAD"
      end
    end

    def verify_local_paths_are_ignored!(root)
      [OUTPUT_RELATIVE_PATH, ARCHIVE_RELATIVE_ROOT, TEMPORARY_RELATIVE_ROOT, LOCK_RELATIVE_PATH].each do |relative|
        _stdout, _stderr, status = Open3.capture3(
          "/usr/bin/git", "-C", root, "check-ignore", "--quiet", "--", relative
        )
        raise LedgerError, "local UI review path must remain ignored by Git: #{relative}" unless status.success?
      end
    end

    def acquire_manifest_lock!(manifest_path, fallback_root: nil, timeout_seconds: LOCK_TIMEOUT_SECONDS)
      root = canonical_repository_root_for_manifest(manifest_path)
      return acquire_repository_lock!(root, timeout_seconds: timeout_seconds) if root
      unless fallback_root
        raise LedgerError, "a noncanonical local UI review ledger requires an explicit lock directory"
      end
      expanded = File.expand_path(fallback_root.to_s)
      status = File.lstat(expanded)
      unless status.directory? && !status.symlink? && File.realpath(expanded) == expanded
        raise LedgerError, "local UI review fallback lock directory is unsafe"
      end
      acquire_lock_file!(
        File.join(expanded, ".ui-review-ledger.lock"),
        timeout_seconds: timeout_seconds
      )
    end

    def verify_manifest_repository_binding!(manifest_path:, product_provenance:)
      root = canonical_repository_root_for_manifest(manifest_path)
      return true unless root
      head, tree = verified_repository_state(root)
      unless product_provenance["sourceCommit"] == head && product_provenance["sourceTree"] == tree
        raise LedgerError, "UI review products do not match the clean current repository HEAD/tree"
      end
      true
    end

    def canonical_repository_root_for_manifest(manifest_path)
      expanded = File.expand_path(manifest_path.to_s)
      directory = File.dirname(expanded)
      return nil unless File.basename(expanded) == File.basename(OUTPUT_RELATIVE_PATH)
      return nil unless File.basename(directory) == "ui-review"
      docs = File.dirname(directory)
      return nil unless File.basename(docs) == "docs"

      root = verified_repository_root(File.dirname(docs))
      expected = File.join(root, OUTPUT_RELATIVE_PATH)
      raise LedgerError, "local UI review ledger path is not canonical" unless expanded == expected
      root
    end

    def acquire_repository_lock!(root, timeout_seconds: LOCK_TIMEOUT_SECONDS)
      root = verified_repository_root(root)
      build = secure_directory(File.join(root, ".build"), root, create: true, mode: 0o700)
      path = File.join(build, File.basename(LOCK_RELATIVE_PATH))
      acquire_lock_file!(path, timeout_seconds: timeout_seconds)
    end

    def acquire_lock_file!(path, timeout_seconds: LOCK_TIMEOUT_SECONDS)
      unless timeout_seconds.is_a?(Numeric) && timeout_seconds.finite? && timeout_seconds.positive? && timeout_seconds <= 30
        raise LedgerError, "local UI review ledger lock timeout is outside the bounded range"
      end
      if File.symlink?(path) || (File.exist?(path) && !File.file?(path))
        raise LedgerError, "local UI review ledger lock must be a regular non-symlink file"
      end
      lock = File.open(path, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds.to_f
      until lock.flock(File::LOCK_EX | File::LOCK_NB)
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          lock.close
          raise LedgerError.new(
            "local UI review ledger is busy; retry after the active build, initialization, or seal finishes",
            exit_code: 75
          )
        end
        sleep LOCK_POLL_SECONDS
      end
      status = lock.stat
      unless status.file? && status.mode & 0o777 == 0o600
        release_lock(lock)
        raise LedgerError, "local UI review ledger lock permissions must be 0600"
      end
      lock
    rescue Errno::ELOOP
      raise LedgerError, "local UI review ledger lock must not be a symbolic link"
    end

    def release_lock(lock)
      return unless lock
      lock.flock(File::LOCK_UN) unless lock.closed?
      lock.close unless lock.closed?
    end

    def canonical_product_snapshots(root)
      {
        "debug-fixture-app" => snapshot_regular_file(File.join(root, DEBUG_RELATIVE_PATH), "debug fixture executable", MAX_EXECUTABLE_BYTES, executable: true),
        "release-exclusion" => snapshot_regular_file(File.join(root, RELEASE_RELATIVE_PATH), "release exclusion executable", MAX_EXECUTABLE_BYTES, executable: true),
        "ax-collector" => snapshot_regular_file(File.join(root, COLLECTOR_RELATIVE_PATH), "AX collector executable", MAX_EXECUTABLE_BYTES, executable: true)
      }
    end

    def extract_product_provenance!(snapshots, expected_commit:, expected_tree:)
      BuildProvenance.extract_product_set!(
        snapshots.transform_values { |snapshot| { data: snapshot.data, label: snapshot.path } },
        expected_commit: expected_commit,
        expected_tree: expected_tree
      )
    end

    def verify_release_marker_exclusion!(data)
      (RELEASE_FORBIDDEN_MARKERS + STATES).each do |marker|
        raise LedgerError, "release exclusion executable contains fixture marker #{marker.inspect}" if data.include?(marker.b)
      end
    end

    def snapshot_regular_file(path, label, maximum_bytes, executable: false)
      expanded = File.expand_path(path)
      status = File.lstat(expanded)
      unless status.file? && !status.symlink?
        raise LedgerError, "#{label} must be a regular non-symlink file"
      end
      if executable && status.mode & 0o111 == 0
        raise LedgerError, "#{label} must be executable"
      end
      unless status.size.positive? && status.size <= maximum_bytes
        raise LedgerError, "#{label} is empty or exceeds the bounded size"
      end
      data = nil
      File.open(expanded, File::RDONLY | File::NOFOLLOW) do |file|
        opened = file.stat
        unless opened.file? && opened.dev == status.dev && opened.ino == status.ino && opened.size == status.size
          raise LedgerError, "#{label} changed while opening"
        end
        data = file.read(maximum_bytes + 1)
      end
      unless data && data.bytesize == status.size && data.bytesize <= maximum_bytes
        raise LedgerError, "#{label} changed while reading"
      end
      resolved = File.realpath(expanded)
      unless resolved == expanded
        raise LedgerError, "#{label} path contains a symbolic-link component"
      end
      Snapshot.new(
        path: expanded,
        data: data.b,
        sha256: Digest::SHA256.hexdigest(data),
        device: status.dev,
        inode: status.ino,
        mode: status.mode
      )
    rescue Errno::ENOENT
      raise LedgerError, "#{label} is missing: #{expanded}"
    end

    def optional_snapshot(path, label, maximum_bytes)
      if File.symlink?(path)
        raise LedgerError, "#{label} must not be a symbolic link"
      end
      return nil unless File.exist?(path)

      snapshot_regular_file(path, label, maximum_bytes)
    end

    def assert_snapshot_unchanged!(snapshot, label)
      current = snapshot_regular_file(snapshot.path, label, [snapshot.data.bytesize, 1].max, executable: snapshot.mode & 0o111 != 0)
      unless current.device == snapshot.device && current.inode == snapshot.inode &&
             current.sha256 == snapshot.sha256 && current.data == snapshot.data
        raise LedgerError, "#{label} changed during initialization"
      end
    end

    def assert_optional_snapshot_unchanged!(path, snapshot)
      current = optional_snapshot(path, "existing local UI review ledger", MAX_LEDGER_BYTES)
      if snapshot.nil?
        raise LedgerError, "local UI review ledger appeared during initialization" if current
      elsif current.nil? || current.device != snapshot.device || current.inode != snapshot.inode || current.data != snapshot.data
        raise LedgerError, "existing local UI review ledger changed during initialization"
      end
    end

    def archive_existing!(root, snapshot, now:)
      archive_root = secure_directory(File.join(root, ARCHIVE_RELATIVE_ROOT), root, create: true, mode: 0o700)
      stamp = now.utc.strftime("%Y%m%dT%H%M%S.%6NZ")
      directory = File.join(archive_root, "#{stamp}-#{snapshot.sha256}")
      Dir.mkdir(directory, 0o700)
      archive_path = File.join(directory, File.basename(OUTPUT_RELATIVE_PATH))
      write_exclusive_file!(archive_path, snapshot.data, 0o600)
      archived = snapshot_regular_file(archive_path, "archived local UI review ledger", MAX_LEDGER_BYTES)
      unless archived.data == snapshot.data && archived.sha256 == snapshot.sha256
        raise LedgerError, "archived local UI review ledger failed readback"
      end
      fsync_directory(directory)
      fsync_directory(archive_root)
      archive_path
    rescue Errno::EEXIST
      raise LedgerError, "local UI review ledger archive path already exists"
    end

    def secure_directory(path, root, create:, mode:)
      root = File.realpath(root)
      expanded = File.expand_path(path)
      prefix = root + File::SEPARATOR
      unless expanded.start_with?(prefix)
        raise LedgerError, "local UI review archive escapes the repository"
      end
      relative = expanded.delete_prefix(prefix)
      current = root
      Pathname.new(relative).each_filename do |component|
        current = File.join(current, component)
        begin
          status = File.lstat(current)
          unless status.directory? && !status.symlink?
            raise LedgerError, "local UI review archive contains an unsafe path component"
          end
        rescue Errno::ENOENT
          raise LedgerError, "local UI review archive directory is missing" unless create
          Dir.mkdir(current, mode)
        end
        unless current == File.join(root, ".build")
          permissions = File.lstat(current).mode & 0o777
          unless permissions == mode
            raise LedgerError, "local UI review archive directory permissions must be #{format("%04o", mode)}"
          end
        end
      end
      File.realpath(expanded)
    end

    def write_temporary!(root, output_path, contents)
      output_parent = File.dirname(output_path)
      parent_status = File.lstat(output_parent)
      unless parent_status.directory? && !parent_status.symlink?
        raise LedgerError, "local UI review ledger directory is unsafe"
      end
      temporary_root = secure_directory(
        File.join(root, TEMPORARY_RELATIVE_ROOT),
        root,
        create: true,
        mode: 0o700
      )
      temporary = File.join(
        temporary_root,
        ".#{File.basename(output_path)}.tmp-#{Process.pid}-#{SecureRandom.hex(8)}"
      )
      write_exclusive_file!(temporary, contents, 0o600)
      written = snapshot_regular_file(temporary, "temporary local UI review ledger", MAX_LEDGER_BYTES)
      raise LedgerError, "temporary local UI review ledger failed readback" unless written.data == contents
      temporary
    end

    def write_exclusive_file!(path, contents, mode)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, mode) do |file|
        file.write(contents)
        file.flush
        file.fsync
      end
    end

    def fsync_directory(path)
      File.open(path, File::RDONLY) { |directory| directory.fsync }
    rescue Errno::EINVAL, Errno::ENOTSUP
      nil
    end

    def verify_pending_rows!(entries, expected, id_key, label)
      unless entries.is_a?(Array) && entries.length == expected.length
        raise LedgerError, "tracked UI review template #{label} row count is stale"
      end
      expected_rows = expected.map do |id, request|
        { id_key => id, "status" => "pending", "captureID" => nil, "request" => request }
      end
      unless entries == expected_rows
        raise LedgerError, "tracked UI review template #{label} rows are not the exact empty request inventory"
      end
    end

    def verify_product_document!(document, role, configuration)
      unless document.is_a?(Hash) &&
             document.keys.sort == BuildProvenance::DOCUMENT_KEYS.sort &&
             document["schemaVersion"] == 1 &&
             document["schemaID"] == BuildProvenance::SCHEMA_ID &&
             document["productRole"] == role &&
             document["configuration"] == configuration &&
             SOURCE_OBJECT_PATTERN.match?(document["sourceCommit"].to_s) &&
             SOURCE_OBJECT_PATTERN.match?(document["sourceTree"].to_s) &&
             SHA256_PATTERN.match?(document["buildTransactionID"].to_s)
        raise LedgerError, "#{role} embedded provenance is malformed"
      end
    end

    def verify_matching_identity!(release, other, label)
      %w[sourceCommit sourceTree buildTransactionID].each do |key|
        unless release[key] == other[key]
          raise LedgerError, "local UI review ledger and #{label} do not share one #{key}"
        end
      end
    end

    def parse_object(data, label)
      document = JSON.parse(data)
      raise LedgerError, "#{label} must be a JSON object" unless document.is_a?(Hash)
      document
    end

    def deep_copy(value)
      Marshal.load(Marshal.dump(value))
    end
  end
end
