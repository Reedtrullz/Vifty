#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "pathname"
require_relative "lib/ui_review_contract"
require_relative "lib/ui_review_build_provenance"

module ViftyUIReview
  module CheckpointWriter
    SCHEMA_ID = "https://vifty.app/schemas/ui-review-automated-checkpoint-v1.schema.json"
    SOURCE_COMMIT_PATTERN = /\A[a-f0-9]{40}\z/
    SHA256_PATTERN = /\A[a-f0-9]{64}\z/
    CAPTURE_ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/
    PRIVATE_STRING_MARKERS = ["/Users/", "/private/", "/var/folders/"].freeze
    EXPECTED_COUNTS = {
      "fixture" => 9,
      "visual" => 28,
      "accessibility" => 13,
      "total" => 50
    }.freeze
    HERO_ROW_ID = "main-1180x820-light"
    CHECKPOINT_RELATIVE_PATH = "docs/ui-review/automated-checkpoint.json"
    HERO_RELATIVE_PATH = "docs/images/vifty-screenshot.png"
    SCHEMA_RELATIVE_PATH = "docs/schemas/ui-review-automated-checkpoint-v1.schema.json"
    DEBUG_PRODUCT_RELATIVE_PATH = ".build/ui-review-products/debug/Vifty.app/Contents/MacOS/Vifty"
    RELEASE_PRODUCT_RELATIVE_PATH = ".build/ui-review-products/release/Vifty"
    COLLECTOR_PRODUCT_RELATIVE_PATH = ".build/ui-review-products/debug/ViftyAXCollector"
    MAX_JSON_BYTES = 16 * 1024 * 1024
    MAX_SCHEMA_BYTES = 2 * 1024 * 1024
    MAX_EXECUTABLE_BYTES = 256 * 1024 * 1024
    MAX_IMAGE_BYTES = 96 * 1024 * 1024

    FileSnapshot = Struct.new(
      :path,
      :resolved_path,
      :label,
      :sha256,
      :identity,
      :data,
      :maximum_bytes,
      keyword_init: true
    )

    class CheckpointError < StandardError
      attr_reader :exit_code

      def initialize(message, exit_code: 65)
        super(message)
        @exit_code = exit_code
      end
    end

    module StrictSchema
      ALLOWED_KEYWORDS = %w[
        $schema
        $id
        title
        $defs
        $ref
        type
        const
        pattern
        required
        properties
        additionalProperties
        minItems
        maxItems
        uniqueItems
        items
        oneOf
      ].freeze

      module_function

      def validate!(document, schema)
        errors = validate(document, schema, schema, "$", "$")
        return true if errors.empty?

        raise CheckpointError, "checkpoint schema validation failed: #{errors.first(12).join("; ")}"
      end

      def validate(value, schema, root, location, schema_location)
        return ["#{schema_location} must be an object"] unless schema.is_a?(Hash)

        unknown = schema.keys - ALLOWED_KEYWORDS
        return ["#{schema_location} uses unsupported schema keywords: #{unknown.sort.join(", ")}"] unless unknown.empty?

        if schema.key?("$ref")
          return ["#{schema_location} cannot combine $ref with sibling constraints"] unless schema.keys == ["$ref"]

          referenced = resolve_reference(schema.fetch("$ref"), root)
          return validate(value, referenced, root, location, schema.fetch("$ref"))
        end

        errors = []
        errors << "#{location} must equal the schema constant" if schema.key?("const") && value != schema["const"]
        errors.concat(validate_type(value, schema["type"], location)) if schema.key?("type")
        if schema.key?("pattern")
          unless value.is_a?(String) && Regexp.new(schema.fetch("pattern")).match?(value)
            errors << "#{location} does not match #{schema.fetch("pattern")}"
          end
        end

        if schema.key?("oneOf")
          branches = schema.fetch("oneOf")
          unless branches.is_a?(Array) && !branches.empty?
            errors << "#{schema_location}.oneOf must be a nonempty array"
          else
            branch_results = branches.each_with_index.map do |branch, index|
              validate(value, branch, root, location, "#{schema_location}.oneOf[#{index}]")
            end
            matches = branch_results.count(&:empty?)
            errors << "#{location} must match exactly one oneOf branch (matched #{matches})" unless matches == 1
          end
        end

        errors.concat(validate_object(value, schema, root, location, schema_location)) if value.is_a?(Hash)
        errors.concat(validate_array(value, schema, root, location, schema_location)) if value.is_a?(Array)
        errors
      rescue RegexpError => error
        ["#{schema_location} has an invalid pattern: #{error.message}"]
      rescue KeyError, ArgumentError => error
        ["#{schema_location} is invalid: #{error.message}"]
      end

      def validate_type(value, type, location)
        matches = case type
                  when "object" then value.is_a?(Hash)
                  when "array" then value.is_a?(Array)
                  when "string" then value.is_a?(String)
                  when "integer" then value.is_a?(Integer)
                  when "number" then value.is_a?(Numeric)
                  when "boolean" then value == true || value == false
                  when "null" then value.nil?
                  else false
                  end
        matches ? [] : ["#{location} must have type #{type.inspect}"]
      end

      def validate_object(value, schema, root, location, schema_location)
        errors = []
        required = schema.fetch("required", [])
        unless required.is_a?(Array) && required.all? { |key| key.is_a?(String) }
          return ["#{schema_location}.required must be an array of strings"]
        end
        (required - value.keys).each { |key| errors << "#{location} is missing required property #{key}" }

        properties = schema.fetch("properties", {})
        return errors << "#{schema_location}.properties must be an object" unless properties.is_a?(Hash)

        if schema["additionalProperties"] == false
          (value.keys - properties.keys).each { |key| errors << "#{location} has additional property #{key}" }
        elsif schema.key?("additionalProperties") && schema["additionalProperties"] != true
          errors << "#{schema_location}.additionalProperties must be boolean"
        end
        properties.each do |key, child_schema|
          next unless value.key?(key)

          errors.concat(validate(value[key], child_schema, root, "#{location}.#{key}", "#{schema_location}.properties.#{key}"))
        end
        errors
      end

      def validate_array(value, schema, root, location, schema_location)
        errors = []
        minimum = schema["minItems"]
        maximum = schema["maxItems"]
        errors << "#{location} contains fewer than #{minimum} items" if minimum && value.length < minimum
        errors << "#{location} contains more than #{maximum} items" if maximum && value.length > maximum
        if schema["uniqueItems"] == true
          canonical = value.map { |item| ViftyUIReview.canonical_json(item) }
          errors << "#{location} items must be unique" unless canonical.uniq.length == canonical.length
        elsif schema.key?("uniqueItems") && schema["uniqueItems"] != false
          errors << "#{schema_location}.uniqueItems must be boolean"
        end
        if schema.key?("items")
          value.each_with_index do |item, index|
            errors.concat(validate(item, schema.fetch("items"), root, "#{location}[#{index}]", "#{schema_location}.items"))
          end
        end
        errors
      end

      def resolve_reference(reference, root)
        unless reference.is_a?(String) && reference.start_with?("#/")
          raise ArgumentError, "only local JSON Pointer references are supported"
        end
        reference.delete_prefix("#/").split("/").reduce(root) do |current, component|
          key = component.gsub("~1", "/").gsub("~0", "~")
          raise KeyError, "unresolved reference #{reference}" unless current.is_a?(Hash) && current.key?(key)

          current.fetch(key)
        end
      end
    end

    module_function

    def run(argv)
      options = parse_options(argv)
      source_commit = options.fetch(:source_commit)
      unless SOURCE_COMMIT_PATTERN.match?(source_commit)
        raise CheckpointError.new("--source-commit must be a full lowercase 40-character Git SHA", exit_code: 64)
      end

      repository_root = verified_repository_root(options.fetch(:repository_root))
      output_path = canonical_output_path(options.fetch(:output), repository_root)
      hero_path = canonical_tracked_file(
        options.fetch(:hero),
        repository_root,
        HERO_RELATIVE_PATH,
        "canonical tracked hero"
      )
      schema_path = canonical_tracked_file(
        File.join(repository_root, SCHEMA_RELATIVE_PATH),
        repository_root,
        SCHEMA_RELATIVE_PATH,
        "checkpoint schema"
      )
      source_tree = verify_repository_state!(repository_root, source_commit)

      manifest_path = regular_file(options.fetch(:manifest), "manifest")
      evidence_root = directory(options.fetch(:evidence_dir), "evidence directory")
      debug_executable = canonical_built_product(
        options.fetch(:debug_executable),
        repository_root,
        DEBUG_PRODUCT_RELATIVE_PATH,
        "debug executable"
      )
      release_binary = canonical_built_product(
        options.fetch(:release_binary),
        repository_root,
        RELEASE_PRODUCT_RELATIVE_PATH,
        "release binary"
      )
      collector_executable = canonical_built_product(
        options.fetch(:collector_executable),
        repository_root,
        COLLECTOR_PRODUCT_RELATIVE_PATH,
        "AX collector executable"
      )
      output_precondition = snapshot_optional_output(output_path)

      manifest_snapshot = snapshot_file(
        manifest_path,
        "manifest",
        maximum_bytes: MAX_JSON_BYTES,
        retain_data: true
      )
      manifest = parse_object_bytes(manifest_snapshot.data, "manifest")
      input = snapshot_inputs(
        manifest: manifest,
        evidence_root: evidence_root,
        manifest_snapshot: manifest_snapshot,
        debug_executable: debug_executable,
        release_binary: release_binary,
        collector_executable: collector_executable,
        hero_path: hero_path,
        schema_path: schema_path
      )
      product_provenance = product_provenance!(
        input,
        source_commit: source_commit,
        source_tree: source_tree
      )

      verify_automated!(
        manifest_path: manifest_path,
        evidence_root: evidence_root,
        debug_executable: debug_executable,
        release_binary: release_binary,
        collector_executable: collector_executable
      )
      assert_snapshots_unchanged!(input.fetch(:snapshots), "after automated verification")
      verify_repository_state!(repository_root, source_commit, source_tree)
      assert_output_unchanged!(output_path, output_precondition)

      rows, safety = checkpoint_rows(
        manifest,
        input.fetch(:artifact_snapshots),
        input.fetch(:collector),
        input.fetch(:debug),
        product_provenance
      )
      validate_row_inventory!(rows)
      hero = hero_binding(rows, input.fetch(:hero))
      checkpoint = {
        "schemaVersion" => 1,
        "schemaID" => SCHEMA_ID,
        "status" => "automated-passed",
        "evidenceKind" => "hardware-free-native-container-debug-fixture",
        "source" => {
          "commit" => source_commit,
          "tree" => source_tree,
          "manifestSHA256" => input.fetch(:manifest).sha256
        },
        "products" => {
          "buildTransactionID" => product_provenance.fetch("buildTransactionID"),
          "debugFixtureSHA256" => input.fetch(:debug).sha256,
          "debugFixtureProvenance" => product_provenance.dig("products", "debug-fixture-app"),
          "debugFixtureProvenanceSHA256" => ViftyUIReview::BuildProvenance.canonical_sha256(
            product_provenance.dig("products", "debug-fixture-app")
          ),
          "releaseExclusionSHA256" => input.fetch(:release).sha256,
          "releaseExclusionProvenance" => product_provenance.dig("products", "release-exclusion"),
          "releaseExclusionProvenanceSHA256" => ViftyUIReview::BuildProvenance.canonical_sha256(
            product_provenance.dig("products", "release-exclusion")
          ),
          "axCollectorSHA256" => input.fetch(:collector).sha256,
          "axCollectorProvenance" => product_provenance.dig("products", "ax-collector"),
          "axCollectorProvenanceSHA256" => ViftyUIReview::BuildProvenance.canonical_sha256(
            product_provenance.dig("products", "ax-collector")
          )
        },
        "counts" => EXPECTED_COUNTS,
        "rows" => rows,
        "safetyAggregate" => safety,
        "hero" => hero,
        "reviewGates" => {
          "visual" => {
            "status" => "pending",
            "priorEvidence" => "superseded",
            "claims" => []
          },
          "voiceOver" => {
            "status" => "pending",
            "decision" => "skipped-by-owner",
            "claims" => []
          }
        },
        "nonClaims" => [
          "full-evidence-bundle-not-committed",
          "hardware-compatibility-not-claimed",
          "release-readiness-not-claimed"
        ]
      }
      ensure_portable!(checkpoint)
      schema = parse_object_bytes(input.fetch(:schema).data, "checkpoint schema")
      unless schema["$id"] == SCHEMA_ID
        raise CheckpointError, "checkpoint schema ID does not match #{SCHEMA_ID}"
      end
      StrictSchema.validate!(checkpoint, schema)

      assert_snapshots_unchanged!(input.fetch(:snapshots), "before checkpoint publication")
      verify_repository_state!(repository_root, source_commit, source_tree)
      assert_output_unchanged!(output_path, output_precondition)
      write_atomic(output_path, ViftyUIReview.canonical_json(checkpoint) + "\n")
      0
    end

    def parse_options(argv)
      options = {}
      parser = OptionParser.new do |value|
        value.banner = "Usage: scripts/write-ui-review-checkpoint.rb --repository-root PATH --manifest PATH --evidence-dir DIR --debug-executable PATH --release-binary PATH --collector-executable PATH --source-commit SHA --output PATH --hero PATH"
        value.on("--repository-root PATH") { |item| options[:repository_root] = item }
        value.on("--manifest PATH") { |item| options[:manifest] = item }
        value.on("--evidence-dir PATH") { |item| options[:evidence_dir] = item }
        value.on("--debug-executable PATH") { |item| options[:debug_executable] = item }
        value.on("--release-binary PATH") { |item| options[:release_binary] = item }
        value.on("--collector-executable PATH") { |item| options[:collector_executable] = item }
        value.on("--source-commit SHA") { |item| options[:source_commit] = item }
        value.on("--output PATH") { |item| options[:output] = item }
        value.on("--hero PATH") { |item| options[:hero] = item }
      end
      parser.parse!(argv)
      raise OptionParser::InvalidOption, argv.join(" ") unless argv.empty?

      %i[
        repository_root manifest evidence_dir debug_executable release_binary collector_executable
        source_commit output hero
      ].each do |key|
        raise OptionParser::MissingArgument, "--#{key.to_s.tr("_", "-")}" unless options[key]
      end
      options
    rescue OptionParser::ParseError => error
      raise CheckpointError.new(error.message, exit_code: 64)
    end

    def verified_repository_root(path)
      root = directory(path, "repository root")
      top_level = git_output(root, "rev-parse", "--show-toplevel").strip
      resolved_top_level = File.realpath(top_level)
      unless resolved_top_level == root
        raise CheckpointError, "--repository-root must be the exact Git repository root"
      end
      root
    rescue Errno::ENOENT, Errno::EACCES => error
      raise CheckpointError, "repository root is unavailable: #{error.message}"
    end

    def verify_repository_state!(repository_root, source_commit, expected_tree = nil)
      head = git_output(repository_root, "rev-parse", "HEAD").strip
      unless head == source_commit
        raise CheckpointError, "--source-commit does not match repository HEAD (#{head})"
      end
      tree = git_output(repository_root, "rev-parse", "HEAD^{tree}").strip
      unless SOURCE_COMMIT_PATTERN.match?(tree)
        raise CheckpointError, "repository HEAD tree is not a full lowercase Git object ID"
      end
      if expected_tree && tree != expected_tree
        raise CheckpointError, "repository HEAD tree changed during checkpoint generation"
      end
      allowed = [CHECKPOINT_RELATIVE_PATH, HERO_RELATIVE_PATH]
      status = git_output(
        repository_root,
        "status",
        "--porcelain=v1",
        "-z",
        "--untracked-files=all"
      )
      unexpected = status.split("\0").reject(&:empty?).each_with_object([]) do |record, paths|
        path = record.length >= 4 ? record[3..] : record
        paths << path unless allowed.include?(path)
      end
      return tree if unexpected.empty?

      raise CheckpointError, "repository has source-affecting worktree changes: #{unexpected.join(", ")}"
    end

    def git_output(repository_root, *arguments)
      stdout, stderr, status = Open3.capture3("/usr/bin/git", "-C", repository_root, *arguments)
      return stdout if status.success?

      detail = stderr.strip
      raise CheckpointError, "Git command failed#{detail.empty? ? "" : ": #{detail}"}"
    end

    def canonical_tracked_file(path, repository_root, relative_path, label)
      expected = File.join(repository_root, relative_path)
      supplied = regular_file(path, label)
      unless supplied == expected
        raise CheckpointError, "#{label} must be #{relative_path} in the repository root"
      end
      tracked = git_output(repository_root, "ls-files", "--error-unmatch", "--", relative_path).strip
      raise CheckpointError, "#{label} must be tracked by Git" unless tracked == relative_path

      supplied
    end

    def canonical_output_path(path, repository_root)
      expected = File.join(repository_root, CHECKPOINT_RELATIVE_PATH)
      expanded = File.expand_path(path)
      unless expanded == expected
        raise CheckpointError, "--output must be the canonical checkpoint output #{CHECKPOINT_RELATIVE_PATH}"
      end
      parent = secure_directory_path(File.dirname(expected), repository_root, create: true)
      output = File.join(parent, File.basename(expected))
      if File.symlink?(output) || (File.exist?(output) && !File.file?(output))
        raise CheckpointError, "canonical checkpoint output must be a regular non-symlink file"
      end
      output
    end

    def secure_directory_path(path, repository_root, create: false)
      root = File.realpath(repository_root)
      expanded = File.expand_path(path)
      prefix = root + File::SEPARATOR
      unless expanded == root || expanded.start_with?(prefix)
        raise CheckpointError, "repository output directory escapes the repository root"
      end
      relative = expanded == root ? "" : expanded.delete_prefix(prefix)
      current = root
      Pathname.new(relative).each_filename do |component|
        current = File.join(current, component)
        begin
          status = File.lstat(current)
          unless status.directory? && !status.symlink?
            raise CheckpointError, "repository output directory contains an unsafe path component"
          end
        rescue Errno::ENOENT
          raise CheckpointError, "repository output directory is missing" unless create

          Dir.mkdir(current, 0o755)
        end
        resolved = File.realpath(current)
        unless resolved == root || resolved.start_with?(prefix)
          raise CheckpointError, "repository output directory escapes the repository root"
        end
      end
      File.realpath(expanded)
    end

    def snapshot_inputs(manifest:, evidence_root:, manifest_snapshot:, debug_executable:, release_binary:, collector_executable:, hero_path:, schema_path:)
      debug_snapshot = snapshot_file(
        debug_executable,
        "debug executable",
        maximum_bytes: MAX_EXECUTABLE_BYTES,
        retain_data: true
      )
      release_snapshot = snapshot_file(
        release_binary,
        "release binary",
        maximum_bytes: MAX_EXECUTABLE_BYTES,
        retain_data: true
      )
      collector_snapshot = snapshot_file(
        collector_executable,
        "AX collector executable",
        maximum_bytes: MAX_EXECUTABLE_BYTES,
        retain_data: true
      )
      hero_snapshot = snapshot_file(
        hero_path,
        "canonical hero",
        maximum_bytes: MAX_IMAGE_BYTES
      )
      schema_snapshot = snapshot_file(
        schema_path,
        "checkpoint schema",
        maximum_bytes: MAX_SCHEMA_BYTES,
        retain_data: true
      )
      artifact_snapshots = snapshot_manifest_artifacts(manifest, evidence_root)
      snapshots = [
        manifest_snapshot,
        debug_snapshot,
        release_snapshot,
        collector_snapshot,
        hero_snapshot,
        schema_snapshot,
        *artifact_snapshots.values
      ].uniq { |snapshot| snapshot.path }
      {
        manifest: manifest_snapshot,
        debug: debug_snapshot,
        release: release_snapshot,
        collector: collector_snapshot,
        hero: hero_snapshot,
        schema: schema_snapshot,
        artifact_snapshots: artifact_snapshots,
        snapshots: snapshots
      }
    end

    def snapshot_manifest_artifacts(manifest, evidence_root)
      ledger = manifest["captureLedger"]
      raise CheckpointError, "captureLedger must be an object" unless ledger.is_a?(Hash)

      snapshots = {}
      ordered_requirements(manifest).each do |kind, id, requirement|
        capture_id = requirement["captureID"]
        unless capture_id.is_a?(String) && CAPTURE_ID_PATTERN.match?(capture_id)
          raise CheckpointError, "#{kind} #{id} is not bound to a valid capture ID"
        end
        capture = ledger[capture_id]
        raise CheckpointError, "captureLedger is missing #{capture_id}" unless capture.is_a?(Hash)

        snapshot_artifact!(
          snapshots,
          evidence_root,
          capture["fixtureReportArtifact"],
          "#{id} fixture report",
          MAX_JSON_BYTES,
          retain_data: true
        )
        if kind == "visual"
          screenshot = capture["screenshot"]
          raise CheckpointError, "#{id} screenshot binding is missing" unless screenshot.is_a?(Hash)

          snapshot_artifact!(
            snapshots,
            evidence_root,
            screenshot["artifact"],
            "#{id} screenshot",
            MAX_IMAGE_BYTES
          )
        elsif kind == "accessibility"
          accessibility = capture["accessibility"]
          raise CheckpointError, "#{id} accessibility binding is missing" unless accessibility.is_a?(Hash)

          snapshot_artifact!(
            snapshots,
            evidence_root,
            accessibility["rawArtifact"],
            "#{id} raw accessibility",
            MAX_JSON_BYTES,
            retain_data: true
          )
          snapshot_artifact!(
            snapshots,
            evidence_root,
            accessibility["artifact"],
            "#{id} sealed accessibility",
            MAX_JSON_BYTES,
            retain_data: true
          )
        end
      end
      snapshots
    end

    def snapshot_artifact!(snapshots, evidence_root, artifact, label, maximum_bytes, retain_data: false)
      path = artifact_path(artifact, evidence_root, label)
      snapshot = snapshot_file(
        path,
        label,
        containment_root: evidence_root,
        maximum_bytes: maximum_bytes,
        retain_data: retain_data
      )
      existing = snapshots[artifact]
      if existing && (existing.resolved_path != snapshot.resolved_path || existing.sha256 != snapshot.sha256)
        raise CheckpointError, "#{label} artifact path has inconsistent bindings"
      end
      snapshots[artifact] = existing || snapshot
    end

    def artifact_path(artifact, evidence_root, label)
      unless artifact.is_a?(String) && !artifact.empty?
        raise CheckpointError, "#{label} artifact path is invalid"
      end
      pathname = Pathname.new(artifact)
      if pathname.absolute? || pathname.each_filename.include?("..")
        raise CheckpointError, "#{label} artifact path escapes the evidence directory"
      end
      candidate = File.expand_path(artifact, evidence_root)
      unless candidate.start_with?(evidence_root + File::SEPARATOR)
        raise CheckpointError, "#{label} artifact path escapes the evidence directory"
      end
      candidate
    end

    def snapshot_file(path, label, containment_root: nil, maximum_bytes:, retain_data: false)
      absolute = File.expand_path(path)
      digest = Digest::SHA256.new
      data = retain_data ? +"".b : nil
      resolved = nil
      identity = nil
      File.open(absolute, File::RDONLY | File::NOFOLLOW) do |file|
        before = file.stat
        raise CheckpointError, "#{label} must be a regular file" unless before.file?
        if before.size > maximum_bytes
          raise CheckpointError, "#{label} exceeds the bounded size limit"
        end
        resolved = File.realpath(absolute)
        validate_containment!(resolved, containment_root, label) if containment_root
        path_stat = File.stat(absolute)
        unless same_file_identity?(before, path_stat)
          raise CheckpointError, "#{label} path changed while it was opened"
        end
        total = 0
        while (chunk = file.read(1024 * 1024))
          total += chunk.bytesize
          raise CheckpointError, "#{label} exceeds the bounded size limit" if total > maximum_bytes

          digest.update(chunk)
          data << chunk if retain_data
        end
        after = file.stat
        current = File.stat(absolute)
        unless full_identity(before) == full_identity(after) && same_file_identity?(after, current)
          raise CheckpointError, "#{label} changed while it was read"
        end
        identity = full_identity(after)
      end
      FileSnapshot.new(
        path: absolute,
        resolved_path: resolved,
        label: label,
        sha256: digest.hexdigest,
        identity: identity,
        data: data,
        maximum_bytes: maximum_bytes
      )
    rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => error
      raise CheckpointError, "#{label} is unavailable or unsafe: #{error.message}"
    end

    def validate_containment!(resolved, root, label)
      prefix = root + File::SEPARATOR
      return if resolved.start_with?(prefix)

      raise CheckpointError, "#{label} escapes the evidence directory"
    end

    def same_file_identity?(left, right)
      left.dev == right.dev && left.ino == right.ino && left.file? == right.file?
    end

    def full_identity(stat)
      [
        stat.dev,
        stat.ino,
        stat.mode,
        stat.nlink,
        stat.uid,
        stat.gid,
        stat.size,
        stat.mtime.to_i,
        stat.mtime.nsec,
        stat.ctime.to_i,
        stat.ctime.nsec
      ]
    end

    def assert_snapshots_unchanged!(snapshots, phase)
      snapshots.each do |snapshot|
        current = snapshot_file(
          snapshot.path,
          snapshot.label,
          maximum_bytes: snapshot.maximum_bytes
        )
        next if current.resolved_path == snapshot.resolved_path &&
                current.sha256 == snapshot.sha256 &&
                current.identity == snapshot.identity

        raise CheckpointError, "#{snapshot.label} changed #{phase}"
      rescue CheckpointError => error
        raise error if error.message.include?("changed #{phase}")

        raise CheckpointError, "#{snapshot.label} changed #{phase}: #{error.message}"
      end
      true
    end

    def snapshot_optional_output(path)
      return { exists: false } unless File.exist?(path) || File.symlink?(path)

      {
        exists: true,
        snapshot: snapshot_file(
          path,
          "existing checkpoint output",
          maximum_bytes: MAX_JSON_BYTES
        )
      }
    end

    def assert_output_unchanged!(path, precondition)
      if precondition.fetch(:exists)
        snapshot = precondition.fetch(:snapshot)
        current = snapshot_file(path, "existing checkpoint output", maximum_bytes: MAX_JSON_BYTES)
        unless current.resolved_path == snapshot.resolved_path &&
               current.sha256 == snapshot.sha256 &&
               current.identity == snapshot.identity
          raise CheckpointError, "existing checkpoint output changed before publication"
        end
      elsif File.exist?(path) || File.symlink?(path)
        raise CheckpointError, "checkpoint output appeared before publication"
      end
      true
    rescue CheckpointError => error
      raise error if error.message.include?("before publication")

      raise CheckpointError, "existing checkpoint output changed before publication: #{error.message}"
    end

    def verify_automated!(manifest_path:, evidence_root:, debug_executable:, release_binary:, collector_executable:)
      script = File.expand_path("run-ui-review-fixture.sh", __dir__)
      stdout, stderr, status = Open3.capture3(
        script,
        "--verify-automated",
        "--manifest", manifest_path,
        "--evidence-dir", evidence_root,
        "--debug-executable", debug_executable,
        "--release-binary", release_binary,
        "--collector-executable", collector_executable
      )
      return if status.success?

      detail = [stdout, stderr].reject(&:empty?).join("\n").strip
      raise CheckpointError, "automated UI verification failed#{detail.empty? ? "" : ": #{detail}"}"
    end

    def product_provenance!(input, source_commit:, source_tree:)
      ViftyUIReview::BuildProvenance.extract_product_set!(
        {
          "debug-fixture-app" => {
            data: input.fetch(:debug).data,
            label: "debug fixture executable snapshot"
          },
          "release-exclusion" => {
            data: input.fetch(:release).data,
            label: "release exclusion executable snapshot"
          },
          "ax-collector" => {
            data: input.fetch(:collector).data,
            label: "AX collector executable snapshot"
          }
        },
        expected_commit: source_commit,
        expected_tree: source_tree
      )
    rescue ViftyUIReview::BuildProvenance::ProvenanceError => error
      raise CheckpointError, "product build provenance is invalid: #{error.message}"
    end

    def ordered_requirements(manifest)
      groups = [
        ["fixture", ViftyUIReview.expected_fixture_requests, manifest["fixtureReports"], "state"],
        ["visual", ViftyUIReview.expected_visual_requests, manifest["visualCells"], "id"],
        ["accessibility", ViftyUIReview.expected_ax_requests, manifest["accessibilityChecks"], "id"]
      ]
      groups.flat_map do |kind, expected, requirements, id_key|
        raise CheckpointError, "#{kind} requirements must be an array" unless requirements.is_a?(Array)

        by_id = requirements.group_by { |item| item.is_a?(Hash) ? item[id_key] : nil }
        expected.keys.map do |id|
          matches = by_id.fetch(id, [])
          raise CheckpointError, "#{kind} requirement inventory is missing or duplicates #{id}" unless matches.length == 1

          [kind, id, matches.first]
        end
      end
    end

    def checkpoint_rows(manifest, artifact_snapshots, collector_snapshot, debug_snapshot, product_provenance)
      ledger = manifest.fetch("captureLedger")
      raise CheckpointError, "captureLedger must be an object" unless ledger.is_a?(Hash)

      debug_provenance = product_provenance.dig("products", "debug-fixture-app")
      collector_provenance = product_provenance.dig("products", "ax-collector")
      unless debug_provenance.is_a?(Hash) && collector_provenance.is_a?(Hash)
        raise CheckpointError, "product build provenance is incomplete"
      end
      debug_provenance_sha = ViftyUIReview::BuildProvenance.canonical_sha256(debug_provenance)
      collector_provenance_sha = ViftyUIReview::BuildProvenance.canonical_sha256(collector_provenance)

      rows = []
      raw_capture_ids = []
      safety = {
        "finalReportsPassed" => 0,
        "modelStartSkipped" => 0,
        "attemptedHardwareCommands" => 0,
        "attemptedExternalMutations" => 0,
        "realControlPathConstructions" => 0
      }
      ordered_requirements(manifest).each do |kind, id, requirement|
        capture_id = requirement.fetch("captureID")
        unless capture_id.is_a?(String) && CAPTURE_ID_PATTERN.match?(capture_id)
          raise CheckpointError, "#{id} capture ID is invalid"
        end
        raw_capture_ids << capture_id
        capture = ledger.fetch(capture_id)
        unless capture.fetch("debugExecutableSHA256") == debug_snapshot.sha256 &&
               capture.fetch("debugBuildProvenance") == debug_provenance
          raise CheckpointError, "#{id} debug product binding does not match the embedded product identity"
        end
        fixture_report_sha = required_sha(capture.fetch("fixtureReportSHA256"), "#{id} fixture report")
        report_snapshot = bound_snapshot(
          artifact_snapshots,
          capture.fetch("fixtureReportArtifact"),
          fixture_report_sha,
          "#{id} fixture report"
        )
        row = {
          "kind" => kind,
          "id" => id,
          "captureIDHash" => Digest::SHA256.hexdigest(capture_id),
          "requestSHA256" => required_sha(capture.fetch("requestSHA256"), "#{id} request"),
          "fixtureReportSHA256" => fixture_report_sha,
          "debugFixtureSHA256" => debug_snapshot.sha256,
          "debugBuildProvenanceSHA256" => debug_provenance_sha
        }
        case kind
        when "visual"
          screenshot = capture.fetch("screenshot")
          screenshot_sha = required_sha(screenshot.fetch("sha256"), "#{id} screenshot")
          bound_snapshot(
            artifact_snapshots,
            screenshot.fetch("artifact"),
            screenshot_sha,
            "#{id} screenshot"
          )
          row["screenshotSHA256"] = screenshot_sha
          row["canonicalPixelSHA256"] = required_sha(
            screenshot.fetch("canonicalPixelSHA256"),
            "#{id} canonical pixels"
          )
        when "accessibility"
          accessibility = capture.fetch("accessibility")
          unless accessibility.fetch("collectorExecutablePath") == collector_snapshot.resolved_path &&
                 accessibility.fetch("collectorExecutableSHA256") == collector_snapshot.sha256 &&
                 accessibility.fetch("collectorBuildProvenance") == collector_provenance
            raise CheckpointError, "#{id} AX collector binding does not match the supplied collector"
          end
          raw_sha = required_sha(accessibility.fetch("rawSHA256"), "#{id} raw accessibility")
          sealed_sha = required_sha(accessibility.fetch("sha256"), "#{id} sealed accessibility")
          bound_snapshot(
            artifact_snapshots,
            accessibility.fetch("rawArtifact"),
            raw_sha,
            "#{id} raw accessibility"
          )
          bound_snapshot(
            artifact_snapshots,
            accessibility.fetch("artifact"),
            sealed_sha,
            "#{id} sealed accessibility"
          )
          row["accessibilityRawSHA256"] = raw_sha
          row["accessibilitySealedSHA256"] = sealed_sha
          row["axCollectorSHA256"] = collector_snapshot.sha256
          row["axCollectorBuildProvenanceSHA256"] = collector_provenance_sha

          raw_report = parse_object_bytes(
            artifact_snapshots.fetch(accessibility.fetch("rawArtifact")).data,
            "#{id} raw accessibility"
          )
          sealed_report = parse_object_bytes(
            artifact_snapshots.fetch(accessibility.fetch("artifact")).data,
            "#{id} sealed accessibility"
          )
          unless raw_report["collectorBuildProvenance"] == collector_provenance &&
                 sealed_report["collectorBuildProvenance"] == collector_provenance &&
                 sealed_report["debugBuildProvenance"] == debug_provenance
            raise CheckpointError, "#{id} AX reports do not match the embedded product identities"
          end
        end

        report = parse_object_bytes(report_snapshot.data, "#{id} fixture report")
        unless report["debugBuildProvenance"] == debug_provenance
          raise CheckpointError, "#{id} fixture report does not match embedded debug provenance"
        end
        safety["finalReportsPassed"] += 1 if report["phase"] == "final" && report["passed"] == true
        safety["modelStartSkipped"] += 1 if report["modelStartSkipped"] == true
        recorder = report.fetch("recorder")
        %w[
          attemptedHardwareCommands attemptedExternalMutations realControlPathConstructions
        ].each do |key|
          values = recorder.fetch(key)
          raise CheckpointError, "#{id} #{key} must be an array" unless values.is_a?(Array)

          safety[key] += values.length
        end
        rows << row
      end
      unless raw_capture_ids.uniq.length == raw_capture_ids.length
        raise CheckpointError, "checkpoint capture IDs must be unique"
      end
      [rows, safety]
    rescue KeyError => error
      raise CheckpointError, "verified manifest is missing checkpoint input: #{error.message}"
    end

    def bound_snapshot(artifact_snapshots, artifact, expected_sha, label)
      snapshot = artifact_snapshots[artifact]
      raise CheckpointError, "#{label} snapshot is missing" unless snapshot
      raise CheckpointError, "#{label} checksum changed after snapshot" unless snapshot.sha256 == expected_sha

      snapshot
    end

    def validate_row_inventory!(rows)
      counts = rows.group_by { |row| row.fetch("kind") }.transform_values(&:length)
      %w[fixture visual accessibility].each do |kind|
        unless counts.fetch(kind, 0) == EXPECTED_COUNTS.fetch(kind)
          raise CheckpointError, "checkpoint #{kind} row count drifted"
        end
      end
      raise CheckpointError, "checkpoint total row count drifted" unless rows.length == EXPECTED_COUNTS.fetch("total")

      hashes = rows.map { |row| row.fetch("captureIDHash") }
      unless hashes.all? { |capture_hash| SHA256_PATTERN.match?(capture_hash) } && hashes.uniq.length == rows.length
        raise CheckpointError, "checkpoint capture ID hashes must be unique SHA-256 values"
      end
    end

    def hero_binding(rows, hero_snapshot)
      row = rows.find { |candidate| candidate["kind"] == "visual" && candidate["id"] == HERO_ROW_ID }
      raise CheckpointError, "verified matrix is missing the canonical hero row" unless row

      screenshot_sha = row.fetch("screenshotSHA256")
      unless hero_snapshot.sha256 == screenshot_sha
        raise CheckpointError, "canonical tracked hero does not match the main-1180x820-light screenshot"
      end
      {
        "rowID" => HERO_ROW_ID,
        "captureIDHash" => row.fetch("captureIDHash"),
        "screenshotSHA256" => screenshot_sha,
        "canonicalPixelSHA256" => row.fetch("canonicalPixelSHA256"),
        "heroArtifactSHA256" => hero_snapshot.sha256
      }
    end

    def ensure_portable!(value, location = "checkpoint")
      case value
      when Hash
        value.each do |key, item|
          ensure_portable!(key, "#{location} key")
          ensure_portable!(item, "#{location}.#{key}")
        end
      when Array
        value.each_with_index { |item, index| ensure_portable!(item, "#{location}[#{index}]") }
      when String
        if value.start_with?("/") || PRIVATE_STRING_MARKERS.any? { |marker| value.include?(marker) }
          raise CheckpointError, "non-portable string at #{location}"
        end
      end
      true
    end

    def required_sha(value, label)
      return value if value.is_a?(String) && SHA256_PATTERN.match?(value)

      raise CheckpointError, "#{label} SHA-256 is invalid"
    end

    def parse_object_bytes(data, label)
      parsed = JSON.parse(data)
      raise CheckpointError, "#{label} must be a JSON object" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => error
      raise CheckpointError, "#{label} is unreadable: #{error.message}"
    end

    def regular_file(path, label)
      raise CheckpointError, "#{label} must be a regular non-symlink file" if File.symlink?(path)

      resolved = File.realpath(path)
      unless File.file?(resolved)
        raise CheckpointError, "#{label} must be a regular non-symlink file"
      end
      resolved
    rescue Errno::ENOENT, Errno::EACCES => error
      raise CheckpointError, "#{label} is unavailable: #{error.message}"
    end

    def executable_file(path, label)
      resolved = regular_file(path, label)
      raise CheckpointError, "#{label} must be executable" unless File.executable?(resolved)

      resolved
    end

    def canonical_built_product(path, repository_root, relative_path, label)
      expected = File.join(repository_root, relative_path)
      resolved = executable_file(path, label)
      unless resolved == expected
        raise CheckpointError, "#{label} must be the canonical product #{relative_path}"
      end
      resolved
    end

    def directory(path, label)
      raise CheckpointError, "#{label} must not be a symbolic link" if File.symlink?(path)

      resolved = File.realpath(path)
      raise CheckpointError, "#{label} must be a directory" unless File.directory?(resolved)

      resolved
    rescue Errno::ENOENT, Errno::EACCES => error
      raise CheckpointError, "#{label} is unavailable: #{error.message}"
    end

    def write_atomic(path, contents)
      temporary = "#{path}.tmp-#{Process.pid}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o644) do |file|
        file.write(contents)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
      File.open(File.dirname(path), File::RDONLY) { |directory| directory.fsync }
    ensure
      File.unlink(temporary) if defined?(temporary) && File.exist?(temporary)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit ViftyUIReview::CheckpointWriter.run(ARGV)
  rescue ViftyUIReview::CheckpointWriter::CheckpointError => error
    warn "UI automated checkpoint blocked: #{error.message}"
    exit error.exit_code
  end
end
