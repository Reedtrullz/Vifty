#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "time"
require_relative "ui_review_contract"
require_relative "ui_review_ax_predicates"
require_relative "ui_review_build_provenance"
require_relative "ui_review_local_ledger"

module ViftyUIReview
  module Verifier
    MAX_JSON_ARTIFACT_BYTES = 16 * 1024 * 1024
    MAX_EXECUTABLE_BYTES = 256 * 1024 * 1024
    RELEASE_BINARY_ARTIFACT = ".build/ui-review-products/release/Vifty"
    RELEASE_FORBIDDEN_MARKERS = ["--ui-review-fixture", "ViftyReviewFixture"].freeze
    MACH_O_MAGICS = [
      "\xFE\xED\xFA\xCE", "\xFE\xED\xFA\xCF",
      "\xCE\xFA\xED\xFE", "\xCF\xFA\xED\xFE",
      "\xCA\xFE\xBA\xBE", "\xCA\xFE\xBA\xBF",
      "\xBE\xBA\xFE\xCA", "\xBF\xBA\xFE\xCA"
    ].map(&:b).freeze
    SYSTEM_SETTING_VISUAL_IDS = %w[
      main-increase-contrast
      main-reduce-transparency
    ].freeze

    module_function

    def run(manifest_path:, evidence_dir:, release_binary:, debug_executable:, collector_executable:, mode: "contract")
      errors = []
      manifest = parse_json_file(manifest_path, "manifest", errors)
      return finish(errors) unless manifest

      errors << "schemaVersion must be 3" unless manifest["schemaVersion"] == SCHEMA_VERSION
      expected_status = mode == "matrix" ? "passed" : "pending"
      unless manifest["status"] == expected_status
        if mode == "initialized"
          errors << "manifest status must remain pending after local-ledger initialization (got #{manifest["status"].inspect})"
        elsif mode == "contract"
          errors << "manifest status must remain pending for request/ledger contract verification (got #{manifest["status"].inspect})"
        elsif mode == "automated"
          errors << "manifest status must remain pending after autonomous-subset verification (got #{manifest["status"].inspect})"
        else
          errors << "manifest status must be passed for full matrix verification (got #{manifest["status"].inspect})"
        end
      end
      errors << "unknown verifier mode: #{mode}" unless %w[initialized contract automated matrix].include?(mode)
      if mode == "initialized"
        begin
          ViftyUIReview::LocalLedger.verify_initialized_document!(manifest)
        rescue ViftyUIReview::LocalLedger::LedgerError => error
          errors << "initialized ledger is not the exact empty request: #{error.message}"
        end
      end

      evidence_root = verified_evidence_root(evidence_dir, errors)
      return finish(errors) unless evidence_root
      debug_binary = verified_macho_executable(debug_executable, "debug executable", errors)
      debug_sha = debug_binary && debug_binary.fetch(:sha256)
      debug_path = debug_binary && debug_binary.fetch(:path)
      release_product = verified_macho_executable(release_binary, "release binary", errors)
      collector_binary = verified_macho_executable(collector_executable, "AX collector executable", errors)
      collector_sha = collector_binary && collector_binary.fetch(:sha256)
      collector_path = collector_binary && collector_binary.fetch(:path)
      product_provenance = verified_product_provenance(
        debug_binary,
        release_product,
        collector_binary,
        errors
      )
      debug_provenance = product_provenance&.dig("products", "debug-fixture-app")
      release_provenance = product_provenance&.dig("products", "release-exclusion")
      collector_provenance = product_provenance&.dig("products", "ax-collector")
      validate_fixture_states(manifest, errors)
      canonical_pixels = Hash.new { |hash, key| hash[key] = [] }

      rows = []
      rows.concat(validate_rows(
        manifest["fixtureReports"],
        EXPECTED_FIXTURE_REQUESTS,
        id_key: "state",
        label: "fixture report",
        allowed_pending_ids: mode == "initialized" ? EXPECTED_FIXTURE_REQUESTS.keys : [],
        errors: errors
      ))
      rows.concat(validate_rows(
        manifest["visualCells"],
        EXPECTED_VISUAL_REQUESTS,
        id_key: "id",
        label: "visual cell",
        allowed_pending_ids: if mode == "initialized"
                               EXPECTED_VISUAL_REQUESTS.keys
                             elsif mode == "automated"
                               SYSTEM_SETTING_VISUAL_IDS
                             else
                               []
                             end,
        errors: errors
      ))
      rows.concat(validate_rows(
        manifest["accessibilityChecks"],
        EXPECTED_AX_REQUESTS,
        id_key: "id",
        label: "accessibility check",
        allowed_pending_ids: mode == "initialized" ? EXPECTED_AX_REQUESTS.keys : [],
        errors: errors
      ))

      ledger = manifest["captureLedger"]
      unless ledger.is_a?(Hash)
        errors << "captureLedger must be an object"
        ledger = {}
      end
      ledger.each do |capture_id, capture|
        unless capture_id.is_a?(String) && /\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/.match?(capture_id)
          errors << "captureLedger key is invalid: #{capture_id.inspect}"
        end
        errors << "captureLedger entry #{capture_id} must be an object" unless capture.is_a?(Hash)
      end

      capture_ids = rows.map { |row| row["captureID"] if row.is_a?(Hash) }.compact
      duplicate_capture_ids = capture_ids.group_by(&:itself).select { |_id, values| values.length > 1 }.keys
      errors << "capture IDs must be unique: #{duplicate_capture_ids.join(", ")}" unless duplicate_capture_ids.empty?

      missing = capture_ids.uniq - ledger.keys
      orphaned = ledger.keys - capture_ids.uniq
      missing.each { |capture_id| errors << "captureLedger is missing #{capture_id}" }
      orphaned.each { |capture_id| errors << "captureLedger contains unused capture #{capture_id}" }

      rows.each do |row|
        next unless row.is_a?(Hash)
        capture_id = row["captureID"]
        next unless capture_id.is_a?(String) && !capture_id.empty?
        capture = ledger[capture_id]
        next unless capture.is_a?(Hash)

        validate_capture(
          row: row,
          capture_id: capture_id,
          capture: capture,
          evidence_root: evidence_root,
          debug_path: debug_path,
          debug_sha: debug_sha,
          debug_provenance: debug_provenance,
          collector_path: collector_path,
          collector_sha: collector_sha,
          collector_provenance: collector_provenance,
          canonical_pixels: canonical_pixels,
          mode: mode,
          errors: errors
        )
      end

      canonical_pixels.each_value do |visual_ids|
        next unless visual_ids.length > 1

        errors << "duplicate canonical pixels across visual cells: #{visual_ids.sort.join(", ")}"
      end

      validate_release_exclusion(
        manifest,
        manifest_path,
        release_product,
        release_provenance,
        errors
      )
      validate_human_attestations(manifest, evidence_root, errors) if mode == "matrix" && evidence_root
      success = case mode
                when "initialized"
                  "Initialized UI review ledger passed empty-request and exact product-binding verification."
                when "automated"
                  "Automated UI review autonomous subset passed. main-increase-contrast and main-reduce-transparency may remain pending for observed macOS setting captures; human visual and VoiceOver attestations remain pending."
                when "matrix"
                  "Full UI review matrix passed with exact visual-inspection and voiceover-session attestations."
                else
                  "UI request/ledger verifier checks passed for the supplied populated fixture: #{EXPECTED_FIXTURE_REQUESTS.length} fixture requests, #{EXPECTED_VISUAL_REQUESTS.length} visual requests, and #{EXPECTED_AX_REQUESTS.length} accessibility requests passed the implemented request/ledger/checksum/identity-shape/safety/release-exclusion checks. This does not validate the complete schema or constitute visual, AX, or human evidence."
                end
      finish(errors, success: success)
    end

    def validate_fixture_states(manifest, errors)
      errors << "fixtureStates do not match the required inventory" unless manifest["fixtureStates"] == STATES
    end

    def validate_rows(entries, expected, id_key:, label:, allowed_pending_ids:, errors:)
      unless entries.is_a?(Array)
        errors << "#{label}s must be an array"
        return []
      end
      entries.each_with_index do |entry, index|
        errors << "#{label} row must be an object at index #{index}" unless entry.is_a?(Hash)
        next unless entry.is_a?(Hash)
        expected_keys = [id_key, "status", "captureID", "request"].sort
        unless entry.keys.sort == expected_keys
          errors << "#{label} row keys do not match the bounded contract at index #{index}"
        end
      end
      unless entries.length == expected.length
        errors << "#{label} count must be exactly #{expected.length} (got #{entries.length})"
      end

      actual_ids = entries.map { |entry| entry[id_key] if entry.is_a?(Hash) }.compact
      missing = expected.keys - actual_ids
      extra = actual_ids - expected.keys
      duplicates = actual_ids.group_by(&:itself).select { |_id, values| values.length > 1 }.keys
      missing.each { |id| errors << "#{label} missing: #{id}" }
      extra.each { |id| errors << "#{label} unexpected: #{id}" }
      duplicates.each { |id| errors << "#{label} duplicated: #{id}" }

      entries.each do |entry|
        next unless entry.is_a?(Hash)
        id = entry[id_key]
        unless id.is_a?(String) && !id.empty?
          errors << "#{label} #{id_key} must be a non-empty string"
          next
        end
        expected_request = expected[id]
        next unless expected_request
        if allowed_pending_ids.include?(id) && entry["status"] == "pending"
          errors << "#{label} #{id} captureID must be null while pending" unless entry["captureID"].nil?
        else
          errors << "#{label} #{id} status must be passed" unless entry["status"] == "passed"
        end
        errors << "#{label} #{id} semantic request mismatch" unless entry["request"] == expected_request
        capture_id = entry["captureID"]
        unless allowed_pending_ids.include?(id) && entry["status"] == "pending"
          unless capture_id.is_a?(String) && /\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/.match?(capture_id)
            errors << "#{label} #{id} captureID is missing"
          end
        end
      end
      entries
    end

    def validate_capture(row:, capture_id:, capture:, evidence_root:, debug_path:, debug_sha:, debug_provenance:, collector_path:, collector_sha:, collector_provenance:, canonical_pixels:, mode:, errors:)
      id = row["id"] || row["state"] || capture_id
      label = "#{id} capture #{capture_id}"
      expected_keys = %w[
        request
        requestSHA256
        fixtureReportArtifact
        fixtureReportSHA256
        debugExecutablePath
        debugExecutableSHA256
        debugBuildProvenance
        runtimeIdentity
      ]
      if row.key?("id") && EXPECTED_VISUAL_REQUESTS.key?(row["id"])
        expected_keys << "screenshot"
      elsif row.key?("id") && EXPECTED_AX_REQUESTS.key?(row["id"])
        expected_keys << "accessibility"
      end
      unless capture.keys.sort == expected_keys.sort
        errors << "#{label} capture record keys do not match the bounded contract"
      end
      request = row["request"]
      unless request.is_a?(Hash)
        errors << "#{label} request must be an object"
        return
      end
      expected_request = if row.key?("state") && !row.key?("id")
                           EXPECTED_FIXTURE_REQUESTS[row["state"]]
                         else
                           EXPECTED_VISUAL_REQUESTS[row["id"]] || EXPECTED_AX_REQUESTS[row["id"]]
                         end
      return unless request == expected_request

      errors << "#{label} request mismatch" unless capture["request"] == request
      expected_request_sha = ViftyUIReview.sha256_json(request)
      errors << "#{label} request checksum mismatch" unless capture["requestSHA256"] == expected_request_sha
      errors << "#{label} debug executable path mismatch" unless capture["debugExecutablePath"] == debug_path
      errors << "#{label} debug executable checksum mismatch" unless capture["debugExecutableSHA256"] == debug_sha
      errors << "#{label} debug build provenance mismatch" unless capture["debugBuildProvenance"] == debug_provenance

      identity = capture["runtimeIdentity"]
      validate_runtime_identity(
        identity,
        request,
        capture_id,
        debug_path,
        debug_sha,
        label,
        errors
      )

      report_artifact = verified_json_artifact(
        capture["fixtureReportArtifact"],
        capture["fixtureReportSHA256"],
        evidence_root,
        "#{label} fixture report",
        errors
      )
      report_path, report = report_artifact if report_artifact
      validate_fixture_report(
        report,
        capture_id: capture_id,
        request: request,
        request_sha: expected_request_sha,
        debug_path: debug_path,
        debug_sha: debug_sha,
        debug_provenance: debug_provenance,
        identity: identity,
        requires_screenshot: row.key?("id") && EXPECTED_VISUAL_REQUESTS.key?(row["id"]),
        screenshot_binding: capture["screenshot"],
        label: "#{label} fixture report",
        errors: errors
      ) if report

      if row.key?("id") && EXPECTED_VISUAL_REQUESTS.key?(row["id"])
        validate_screenshot(
          capture,
          identity,
          evidence_root,
          label,
          row["id"],
          canonical_pixels,
          errors
        )
      elsif row.key?("id") && EXPECTED_AX_REQUESTS.key?(row["id"])
        validate_sealed_accessibility(
          capture,
          row,
          identity,
          evidence_root,
          label,
          collector_path,
          collector_sha,
          collector_provenance,
          errors
        )
      end
    end

    def validate_runtime_identity(identity, request, capture_id, debug_path, debug_sha, label, errors)
      unless identity.is_a?(Hash)
        errors << "#{label} runtime identity is missing"
        return
      end

      expected_keys = %w[
        processIdentifier executablePath executableSHA256 provenance windowNumber
        windowIdentifier accessibilityIdentifier windowClass containerKind isVisible
        contentWidth contentHeight backingScaleFactor
      ]
      unless identity.keys.sort == expected_keys.sort
        errors << "#{label} runtime identity keys do not match the bounded contract"
      end

      process_id = identity["processIdentifier"]
      errors << "#{label} process identifier is invalid" unless process_id.is_a?(Integer) && process_id.positive?
      errors << "#{label} runtime executable path mismatch" unless identity["executablePath"] == debug_path
      errors << "#{label} runtime executable checksum mismatch" unless identity["executableSHA256"] == debug_sha
      window_number = identity["windowNumber"]
      errors << "#{label} window number is invalid" unless window_number.is_a?(Integer) && window_number.positive?
      %w[windowIdentifier accessibilityIdentifier windowClass].each do |key|
        value = identity[key]
        errors << "#{label} #{key} is missing" unless value.is_a?(String) && !value.empty?
      end

      expected_window_identifier = "vifty-ui-review-window-#{capture_id}"
      expected_accessibility_identifier = "vifty-ui-review-ax-window-#{capture_id}"
      unless identity["windowIdentifier"] == expected_window_identifier
        errors << "#{label} window identifier mismatch"
      end
      unless identity["accessibilityIdentifier"] == expected_accessibility_identifier
        errors << "#{label} accessibility identifier mismatch"
      end

      expected_provenance = ViftyUIReview.expected_provenance(request)
      errors << "#{label} window provenance mismatch" unless identity["provenance"] == expected_provenance
      errors << "#{label} window is not visible" unless identity["isVisible"] == true

      expected_container = ViftyUIReview.expected_container_kind(request)
      errors << "#{label} window container mismatch" unless identity["containerKind"] == expected_container

      width = identity["contentWidth"]
      height = identity["contentHeight"]
      scale = identity["backingScaleFactor"]
      errors << "#{label} window width is invalid" unless width.is_a?(Integer) && width.positive?
      errors << "#{label} window height is invalid" unless height.is_a?(Integer) && height.positive?
      errors << "#{label} backing scale is invalid" unless scale.is_a?(Numeric) && scale.to_f.finite? && scale.positive? && scale <= 4

      expected_width, expected_height = ViftyUIReview.expected_geometry(request)
      if request["window"] == "native"
        expected_width = 600
        expected_height = 420
      end
      errors << "#{label} window width does not match request geometry" if expected_width && width != expected_width
      errors << "#{label} window height does not match request geometry" if expected_height && height != expected_height
    end

    def validate_fixture_report(report, capture_id:, request:, request_sha:, debug_path:, debug_sha:, debug_provenance:, identity:, requires_screenshot:, screenshot_binding:, label:, errors:)
      identity = {} unless identity.is_a?(Hash)
      errors << "#{label} schemaVersion must be 3" unless report["schemaVersion"] == SCHEMA_VERSION
      errors << "#{label} captureID mismatch" unless report["captureID"] == capture_id
      errors << "#{label} semantic request mismatch" unless report["request"] == request
      errors << "#{label} request checksum mismatch" unless report["requestSHA256"] == request_sha
      errors << "#{label} debug executable path mismatch" unless report["debugExecutablePath"] == debug_path
      errors << "#{label} debug executable checksum mismatch" unless report["debugExecutableSHA256"] == debug_sha
      errors << "#{label} debug build provenance mismatch" unless report["debugBuildProvenance"] == debug_provenance
      errors << "#{label} runtime process/window identity mismatch" unless report["runtimeIdentity"] == identity
      errors << "#{label} must be final" unless report["phase"] == "final"
      errors << "#{label} did not skip model.start" unless report["modelStartSkipped"] == true
      errors << "#{label} runtimeFailure must be null" unless report["runtimeFailure"].nil?
      errors << "#{label} did not pass" unless report["passed"] == true

      observed = report["observed"]
      environment = observed.is_a?(Hash) ? observed["environment"] : nil
      window = observed.is_a?(Hash) ? observed["window"] : nil
      expected_environment = {
        "source" => "swiftui-environment",
        "appearance" => request["appearance"],
        "contrast" => request["contrast"],
        "transparency" => request["transparency"],
        "textSize" => request["textSize"]
      }
      if environment.is_a?(Hash)
        errors << "#{label} environment source must be swiftui-environment" unless environment["source"] == "swiftui-environment"
      else
        errors << "#{label} observed environment is missing"
      end
      errors << "#{label} observed environment does not equal the semantic request" unless environment == expected_environment
      expected_window = identity.reject do |key, _value|
        %w[processIdentifier executablePath executableSHA256].include?(key)
      end.merge("source" => "nswindow-content-layout-rect")
      if window.is_a?(Hash)
        errors << "#{label} window source must be nswindow-content-layout-rect" unless window["source"] == "nswindow-content-layout-rect"
      else
        errors << "#{label} observed NSWindow is missing"
      end
      errors << "#{label} observed NSWindow does not equal runtime identity" unless window == expected_window

      screenshot = report["screenshot"]
      if requires_screenshot
        scale = identity["backingScaleFactor"]
        width = identity["contentWidth"]
        height = identity["contentHeight"]
        valid_geometry = width.is_a?(Integer) && width.positive? &&
          height.is_a?(Integer) && height.positive? &&
          scale.is_a?(Numeric) && scale.to_f.finite? && scale.positive? && scale <= 4
        if valid_geometry
          expected_screenshot = {
            "method" => "native-window-screencapture-crop",
            "artifactPath" => "screenshot.png",
            "sha256" => screenshot_binding.is_a?(Hash) ? screenshot_binding["sha256"] : nil,
            "pointWidth" => width,
            "pointHeight" => height,
            "pixelWidth" => (width * scale).round,
            "pixelHeight" => (height * scale).round,
            "backingScaleFactor" => scale
          }
          unless screenshot == expected_screenshot
            errors << "#{label} screenshot report does not bind the captured PNG and geometry"
          end
        else
          errors << "#{label} screenshot report geometry is invalid"
        end
      elsif !screenshot.nil?
        errors << "#{label} non-visual report screenshot must be null"
      end

      recorder = report["recorder"]
      ViftyUIReview.fixture_recorder_errors(recorder).each do |error|
        errors << "#{label} #{error}"
      end
    end

    def validate_screenshot(capture, identity, evidence_root, label, visual_id, canonical_pixels, errors)
      screenshot = capture["screenshot"]
      unless screenshot.is_a?(Hash)
        errors << "#{label} screenshot binding is missing"
        return
      end
      data = verified_artifact_bytes(
        screenshot["artifact"],
        screenshot["sha256"],
        evidence_root,
        "#{label} screenshot",
        errors
      )
      return unless data
      return unless identity.is_a?(Hash)
      width = identity["contentWidth"]
      height = identity["contentHeight"]
      scale = identity["backingScaleFactor"]
      return unless width.is_a?(Integer) && height.is_a?(Integer) && scale.is_a?(Numeric)
      return unless width.positive? && height.positive? && scale.to_f.finite? && scale.positive? && scale <= 4
      expected = [
        (width * scale).round,
        (height * scale).round
      ]
      analysis = ViftyUIReview.analyze_png_bytes(
        data,
        expected_width: expected.fetch(0),
        expected_height: expected.fetch(1)
      )
      canonical_sha = analysis.fetch(:canonical_pixel_sha256)
      unless screenshot["canonicalPixelSHA256"].is_a?(String) &&
             screenshot["canonicalPixelSHA256"] == canonical_sha
        errors << "#{label} canonical pixel checksum mismatch"
      end
      canonical_pixels[canonical_sha] << visual_id
    rescue ViftyUIReview::PNGError => error
      errors << "#{label} #{error.message}"
    end

    def validate_sealed_accessibility(capture, row, identity, evidence_root, label, collector_path, collector_sha, collector_provenance, errors)
      accessibility = capture["accessibility"]
      expected_keys = %w[
        rawArtifact
        rawSHA256
        artifact
        sha256
        collectorExecutablePath
        collectorExecutableSHA256
        collectorBuildProvenance
      ]
      unless accessibility.is_a?(Hash) && accessibility.keys.sort == expected_keys.sort
        errors << "#{label} accessibility binding must contain exact raw, sealed, and collector provenance"
        return
      end
      unless accessibility["collectorExecutablePath"] == collector_path
        errors << "#{label} AX collector executable path mismatch"
      end
      unless accessibility["collectorExecutableSHA256"] == collector_sha
        errors << "#{label} AX collector executable checksum mismatch"
      end
      unless accessibility["collectorBuildProvenance"] == collector_provenance
        errors << "#{label} AX collector build provenance mismatch"
      end
      raw_artifact = verified_json_artifact(
        accessibility["rawArtifact"],
        accessibility["rawSHA256"],
        evidence_root,
        "#{label} raw accessibility capture",
        errors
      )
      sealed_artifact = verified_json_artifact(
        accessibility["artifact"],
        accessibility["sha256"],
        evidence_root,
        "#{label} sealed accessibility report",
        errors
      )
      return unless raw_artifact && sealed_artifact
      raw_path, raw = raw_artifact
      sealed_path, sealed = sealed_artifact

      identity = {} unless identity.is_a?(Hash)
      request = row["request"]
      request_sha = ViftyUIReview.sha256_json(request)
      expected_root_identifier = "vifty.ax.fixture.root.#{row["captureID"]}"
      expected_target = {
        "processIdentifier" => identity["processIdentifier"],
        "windowIdentifier" => identity["accessibilityIdentifier"],
        "rootIdentifier" => expected_root_identifier
      }
      evidence_request = raw["request"]
      errors << "#{label} raw schemaVersion must be 1" unless raw["schemaVersion"] == 1
      unless raw["schemaID"] == "https://vifty.app/schemas/ui-review-ax-raw-capture-v1.schema.json"
        errors << "#{label} raw schema ID mismatch"
      end
      unless raw["collectorBuildProvenance"] == collector_provenance
        errors << "#{label} raw AX collector build provenance mismatch"
      end
      unless evidence_request.is_a?(Hash) &&
             evidence_request["checkID"] == row["id"] &&
             evidence_request["captureID"] == row["captureID"] &&
             evidence_request["processIdentifier"] == identity["processIdentifier"] &&
             evidence_request["windowIdentifier"] == identity["accessibilityIdentifier"] &&
             evidence_request["rootIdentifier"] == expected_root_identifier &&
             evidence_request["semanticRequest"] == request &&
             evidence_request["requestSHA256"] == request_sha
        errors << "#{label} raw AX request binding mismatch"
      end
      errors << "#{label} raw source must be macos-accessibility-api" unless raw["source"] == "macos-accessibility-api"
      errors << "#{label} raw permission must be trusted" unless raw["permissionTrusted"] == true
      errors << "#{label} raw promptRequested must be false" unless raw["promptRequested"] == false
      errors << "#{label} initial AX target mismatch" unless raw["initialTarget"] == expected_target
      errors << "#{label} final AX target mismatch" unless raw["finalTarget"] == expected_target
      errors << "#{label} raw actionsPerformed must be empty" unless raw["actionsPerformed"] == []
      errors << "#{label} raw readErrors must be empty" unless raw["readErrors"] == []

      traversal = raw["traversal"]
      observations = raw["observations"]
      unless traversal.is_a?(Hash) &&
             traversal["complete"] == true &&
             traversal["truncationReasons"] == [] &&
             traversal["nodeCount"].is_a?(Integer) &&
             traversal["nodeCount"].positive? &&
             observations.is_a?(Array) &&
             traversal["nodeCount"] == observations.length
        errors << "#{label} raw traversal must be complete and internally bounded"
      end
      observation_paths = Array(observations).map do |observation|
        observation["path"] if observation.is_a?(Hash)
      end.compact
      errors << "#{label} raw observation paths must be unique" unless observation_paths.uniq.length == observation_paths.length

      errors << "#{label} sealed schemaVersion must be 1" unless sealed["schemaVersion"] == 1
      unless sealed["schemaID"] == "https://vifty.app/schemas/ui-review-ax-sealed-report-v1.schema.json"
        errors << "#{label} sealed schema ID mismatch"
      end
      errors << "#{label} sealed AX request differs from raw capture" unless sealed["request"] == evidence_request
      unless sealed.dig("rawCapture", "sha256") == accessibility["rawSHA256"]
        errors << "#{label} sealed raw capture checksum mismatch"
      end
      unless artifact_binding_matches?(sealed.dig("rawCapture", "artifact"), raw_path, evidence_root)
        errors << "#{label} sealed raw capture artifact mismatch"
      end
      unless sealed.dig("fixtureReport", "sha256") == capture["fixtureReportSHA256"]
        errors << "#{label} sealed fixture report checksum mismatch"
      end
      fixture_report_path = File.join(evidence_root, capture["fixtureReportArtifact"].to_s)
      unless artifact_binding_matches?(sealed.dig("fixtureReport", "artifact"), fixture_report_path, evidence_root)
        errors << "#{label} sealed fixture report artifact mismatch"
      end
      unless sealed["debugExecutableSHA256"] == capture["debugExecutableSHA256"]
        errors << "#{label} sealed debug executable checksum mismatch"
      end
      unless sealed["debugBuildProvenance"] == capture["debugBuildProvenance"]
        errors << "#{label} sealed debug build provenance mismatch"
      end
      unless sealed["collectorBuildProvenance"] == collector_provenance
        errors << "#{label} sealed collector build provenance mismatch"
      end
      errors << "#{label} sealed runtime AX target mismatch" unless sealed["runtimeIdentity"] == expected_target
      errors << "#{label} sealed actionsPerformed must be empty" unless sealed["actionsPerformed"] == []
      assertion = sealed["assertion"]
      unless assertion.is_a?(Hash) &&
             assertion["id"] == row["id"] &&
             assertion["passed"] == true &&
             assertion["failures"] == [] &&
             assertion["observationPaths"].is_a?(Array) &&
             !assertion["observationPaths"].empty? &&
             (assertion["observationPaths"] - observation_paths).empty?
        errors << "#{label} sealed semantic assertion did not pass against raw observations"
      end
      recomputed_assertion = ViftyUIReview::AXPredicates.evaluate(row["id"], raw)
      unless recomputed_assertion["passed"] == true
        recomputed_assertion.fetch("failures", []).each do |failure|
          errors << "#{label} independently recomputed AX predicate failed: #{failure}"
        end
      end
      unless assertion == recomputed_assertion
        errors << "#{label} sealed semantic assertion does not match the independently recomputed AX predicate"
      end
    end

    def artifact_binding_matches?(binding, expected_path, evidence_root)
      return false unless binding.is_a?(String) && !binding.empty? && expected_path
      candidate = if Pathname.new(binding).absolute?
                    File.expand_path(binding)
                  else
                    File.expand_path(binding, evidence_root)
                  end
      File.realpath(expected_path) == File.realpath(candidate)
    rescue SystemCallError
      false
    end

    def validate_human_attestations(manifest, evidence_root, errors)
      human = manifest["humanAttestations"]
      unless human.is_a?(Hash) && human.keys.sort == %w[visual voiceOver].sort
        errors << "humanAttestations must contain exact visual and voiceOver bindings"
        return
      end
      ledger = manifest["captureLedger"]
      ledger = {} unless ledger.is_a?(Hash)
      validate_human_attestation(
        binding_name: "visual",
        binding: human["visual"],
        expected_method: "visual-inspection",
        rows: manifest["visualCells"],
        ledger: ledger,
        evidence_root: evidence_root,
        expected_step_ids: %w[clipping overlap legibility hierarchy transient-state],
        expected_step_row_ids: nil,
        errors: errors
      )
      validate_human_attestation(
        binding_name: "voiceOver",
        binding: human["voiceOver"],
        expected_method: "voiceover-session",
        rows: manifest["accessibilityChecks"],
        ledger: ledger,
        evidence_root: evidence_root,
        expected_step_ids: VOICEOVER_STEP_ROW_IDS.keys,
        expected_step_row_ids: VOICEOVER_STEP_ROW_IDS,
        errors: errors
      )
    end

    def validate_human_attestation(
      binding_name:,
      binding:,
      expected_method:,
      rows:,
      ledger:,
      evidence_root:,
      expected_step_ids:,
      expected_step_row_ids:,
      errors:
    )
      label = "#{binding_name} attestation"
      unless binding.is_a?(Hash) && binding.keys.sort == %w[status artifact sha256].sort
        errors << "#{label} binding keys do not match the bounded contract"
        return
      end
      errors << "#{label} status must be passed" unless binding["status"] == "passed"
      artifact = verified_json_artifact(binding["artifact"], binding["sha256"], evidence_root, label, errors)
      return unless artifact
      _path, attestation = artifact

      expected_keys = %w[
        schemaVersion
        method
        reviewer
        reviewedAt
        coveredRowIDs
        captureBindings
        steps
        overallStatus
      ]
      if expected_method == "voiceover-session"
        expected_keys.concat(%w[
          actionSequence
          inspectOnlyControlGroups
          disallowedActionsPerformed
        ])
      end
      unless attestation.keys.sort == expected_keys.sort
        errors << "#{label} keys do not match the bounded v1 contract"
      end
      errors << "#{label} schemaVersion must be 1" unless attestation["schemaVersion"] == 1
      unless attestation["method"] == expected_method
        errors << "#{label} method must be #{expected_method}"
      end
      reviewer = attestation["reviewer"]
      errors << "#{label} reviewer must be nonempty" unless reviewer.is_a?(String) && !reviewer.strip.empty?
      if reviewer.is_a?(String) && reviewer.strip == ATTESTATION_REVIEWER_PLACEHOLDER
        errors << "#{label} reviewer must replace the template placeholder"
      end
      reviewed_at = attestation["reviewedAt"]
      unless valid_iso8601_time?(reviewed_at)
        errors << "#{label} reviewedAt must be an ISO-8601 timestamp"
      end
      if reviewed_at == ATTESTATION_REVIEWED_AT_PLACEHOLDER
        errors << "#{label} reviewedAt must replace the template placeholder"
      end
      errors << "#{label} overallStatus must be passed" unless attestation["overallStatus"] == "passed"
      validate_voiceover_action_contract(label: label, attestation: attestation, errors: errors) if expected_method == "voiceover-session"

      rows = [] unless rows.is_a?(Array)
      expected_rows = rows.select { |row| row.is_a?(Hash) }.sort_by { |row| row["id"].to_s }
      expected_ids = expected_rows.map { |row| row["id"] }
      unless attestation["coveredRowIDs"] == expected_ids
        errors << "#{label} covered row IDs do not match the exact required rows"
      end
      validate_attestation_capture_bindings(
        label: label,
        bindings: attestation["captureBindings"],
        rows: expected_rows,
        ledger: ledger,
        errors: errors
      )
      validate_attestation_steps(
        label: label,
        steps: attestation["steps"],
        expected_step_ids: expected_step_ids,
        expected_row_ids: expected_ids,
        expected_step_row_ids: expected_step_row_ids,
        errors: errors
      )
    end

    def validate_voiceover_action_contract(label:, attestation:, errors:)
      unless attestation["actionSequence"] == VOICEOVER_SAFE_ACTION_SEQUENCE
        errors << "#{label} actionSequence must match the exact safe UI-only sequence"
      end
      unless attestation["inspectOnlyControlGroups"] == VOICEOVER_INSPECT_ONLY_CONTROLS
        errors << "#{label} inspectOnlyControlGroups must match the exact announce-only groups"
      end
      unless attestation["disallowedActionsPerformed"] == []
        errors << "#{label} disallowedActionsPerformed must be empty"
      end
    end

    def validate_attestation_capture_bindings(label:, bindings:, rows:, ledger:, errors:)
      unless bindings.is_a?(Array)
        errors << "#{label} captureBindings must be an array"
        return
      end
      unless bindings.length == rows.length
        errors << "#{label} capture binding count mismatch"
      end
      by_row = bindings.select { |binding| binding.is_a?(Hash) }.to_h do |binding|
        [binding["rowID"], binding]
      end
      rows.each do |row|
        row_id = row["id"]
        binding = by_row[row_id]
        unless binding.is_a?(Hash)
          errors << "#{label} capture binding is missing for #{row_id}"
          next
        end
        expected_keys = %w[
          rowID
          captureID
          requestSHA256
          debugExecutableSHA256
          fixtureReportSHA256
          screenshotSHA256
          screenshotCanonicalPixelSHA256
          accessibilityRawSHA256
          accessibilitySealedSHA256
        ]
        unless binding.keys.sort == expected_keys.sort
          errors << "#{label} capture binding keys mismatch for #{row_id}"
        end
        capture_id = row["captureID"]
        capture = ledger[capture_id]
        unless capture.is_a?(Hash)
          errors << "#{label} capture ledger entry is missing for #{row_id}"
          next
        end
        errors << "#{label} capture ID binding mismatch for #{row_id}" unless binding["captureID"] == capture_id
        errors << "#{label} request checksum binding mismatch for #{row_id}" unless binding["requestSHA256"] == capture["requestSHA256"]
        unless binding["debugExecutableSHA256"] == capture["debugExecutableSHA256"]
          errors << "#{label} debug executable checksum binding mismatch for #{row_id}"
        end
        unless binding["fixtureReportSHA256"] == capture["fixtureReportSHA256"]
          errors << "#{label} fixture report checksum binding mismatch for #{row_id}"
        end
        expected_screenshot_sha = capture.dig("screenshot", "sha256")
        unless binding["screenshotSHA256"] == expected_screenshot_sha
          errors << "#{label} PNG checksum binding mismatch for #{row_id}"
        end
        expected_pixel_sha = capture.dig("screenshot", "canonicalPixelSHA256")
        unless binding["screenshotCanonicalPixelSHA256"] == expected_pixel_sha
          errors << "#{label} canonical pixel checksum binding mismatch for #{row_id}"
        end
        expected_accessibility_raw_sha = capture.dig("accessibility", "rawSHA256")
        unless binding["accessibilityRawSHA256"] == expected_accessibility_raw_sha
          errors << "#{label} raw AX checksum binding mismatch for #{row_id}"
        end
        expected_accessibility_sealed_sha = capture.dig("accessibility", "sha256")
        unless binding["accessibilitySealedSHA256"] == expected_accessibility_sealed_sha
          errors << "#{label} sealed AX checksum binding mismatch for #{row_id}"
        end
      end
    end

    def validate_attestation_steps(
      label:,
      steps:,
      expected_step_ids:,
      expected_row_ids:,
      expected_step_row_ids:,
      errors:
    )
      unless steps.is_a?(Array)
        errors << "#{label} steps must be an array"
        return
      end
      actual_ids = steps.map { |step| step["id"] if step.is_a?(Hash) }
      unless actual_ids == expected_step_ids
        errors << "#{label} scripted step IDs do not match the required method"
      end
      steps.each do |step|
        next unless step.is_a?(Hash)
        unless step.keys.sort == %w[id status coveredRowIDs notes].sort
          errors << "#{label} step #{step["id"].inspect} keys do not match the bounded contract"
        end
        errors << "#{label} step #{step["id"]} status must be passed" unless step["status"] == "passed"
        expected_rows = if expected_step_row_ids
                          expected_step_row_ids.fetch(step["id"], [])
                        else
                          expected_row_ids
                        end
        unless step["coveredRowIDs"] == expected_rows
          errors << "#{label} step #{step["id"]} covered rows mismatch"
        end
        notes = step["notes"]
        unless notes.is_a?(String) && notes.strip.length >= MINIMUM_ATTESTATION_OBSERVATION_LENGTH
          errors << "#{label} step #{step["id"]} notes must record a specific observed result"
          next
        end
        if notes.strip.start_with?(ATTESTATION_OBSERVATION_PLACEHOLDER_PREFIX) ||
           /\ACompleted the scripted (?:visual-inspection|voiceover-session) check\.?\z/i.match?(notes.strip)
          errors << "#{label} step #{step["id"]} notes must record a specific observed result"
        end
      end
    end

    def valid_iso8601_time?(value)
      return false unless value.is_a?(String) && !value.empty?
      Time.iso8601(value)
      true
    rescue ArgumentError
      false
    end

    def validate_release_exclusion(manifest, manifest_path, binary, release_provenance, errors)
      release = manifest["releaseExclusion"]
      release = {} unless release.is_a?(Hash)
      unless release.keys.sort == %w[status binary sha256 buildProvenance forbiddenMarkers].sort
        errors << "release exclusion keys do not match the bounded contract"
      end
      errors << "release exclusion status must be passed" unless release["status"] == "passed"
      unless release["binary"] == RELEASE_BINARY_ARTIFACT
        errors << "release exclusion binary must be #{RELEASE_BINARY_ARTIFACT}"
      end
      unless release["forbiddenMarkers"] == RELEASE_FORBIDDEN_MARKERS
        errors << "release exclusion forbiddenMarkers do not match the authoritative marker set"
      end
      unless release["buildProvenance"] == release_provenance
        errors << "release exclusion build provenance mismatch"
      end

      repository_root = repository_root_for_manifest(manifest_path)
      expected_path = File.expand_path(RELEASE_BINARY_ARTIFACT, repository_root)
      return unless binary
      unless binary.fetch(:path) == File.realpath(expected_path)
        errors << "release binary path does not match the manifest-declared repository release artifact"
      end
      errors << "release binary checksum mismatch" unless release["sha256"] == binary.fetch(:sha256)
      (RELEASE_FORBIDDEN_MARKERS + STATES).each do |marker|
        if binary.fetch(:data).include?(marker.b)
          errors << "release binary contains debug fixture marker: #{marker}"
        end
      end
    rescue SystemCallError => error
      errors << "release binary cannot be resolved against the manifest: #{error.message}"
    end

    def verified_product_provenance(debug_binary, release_binary, collector_binary, errors)
      return nil unless debug_binary && release_binary && collector_binary

      ViftyUIReview::BuildProvenance.extract_product_set!(
        {
          "debug-fixture-app" => {
            data: debug_binary.fetch(:data),
            label: "debug fixture executable"
          },
          "release-exclusion" => {
            data: release_binary.fetch(:data),
            label: "release exclusion executable"
          },
          "ax-collector" => {
            data: collector_binary.fetch(:data),
            label: "AX collector executable"
          }
        }
      )
    rescue ViftyUIReview::BuildProvenance::ProvenanceError => error
      errors << "product build provenance is invalid: #{error.message}"
      nil
    end

    def repository_root_for_manifest(manifest_path)
      manifest_directory = File.dirname(File.realpath(manifest_path))
      if File.basename(manifest_directory) == "ui-review" &&
         File.basename(File.dirname(manifest_directory)) == "docs"
        File.dirname(File.dirname(manifest_directory))
      else
        manifest_directory
      end
    end

    def verified_macho_executable(path, label, errors)
      payload = safely_read_regular_file(
        path,
        label,
        errors,
        maximum_bytes: MAX_EXECUTABLE_BYTES,
        executable: true
      )
      return nil unless payload
      unless MACH_O_MAGICS.include?(payload.fetch(:data).byteslice(0, 4))
        errors << "#{label} is not a Mach-O executable"
        return nil
      end
      payload
    end

    def safely_read_regular_file(path, label, errors, maximum_bytes:, containment_root: nil, executable: false)
      unless path.is_a?(String) && !path.empty?
        errors << "#{label} path is missing"
        return nil
      end
      expanded = File.expand_path(path)
      if File.symlink?(expanded)
        errors << "#{label} must not be a symbolic link"
        return nil
      end

      payload = nil
      File.open(expanded, File::RDONLY | File::NOFOLLOW) do |file|
        descriptor_stat = file.stat
        resolved = File.realpath(expanded)
        resolved_stat = File.stat(resolved)
        valid_identity = descriptor_stat.file? &&
          descriptor_stat.dev == resolved_stat.dev &&
          descriptor_stat.ino == resolved_stat.ino
        if containment_root
          prefix = containment_root + File::SEPARATOR
          valid_identity &&= resolved.start_with?(prefix)
        end
        unless valid_identity
          errors << "#{label} changed while it was being verified: #{path}"
          return nil
        end
        if executable && (descriptor_stat.mode & 0o111).zero?
          errors << "#{label} is not executable: #{path}"
          return nil
        end
        if descriptor_stat.size > maximum_bytes
          errors << "#{label} exceeds the bounded size limit"
          return nil
        end
        data = file.read(maximum_bytes + 1)
        if data.bytesize > maximum_bytes
          errors << "#{label} exceeds the bounded size limit"
          return nil
        end
        payload = {
          path: resolved,
          data: data.b,
          sha256: Digest::SHA256.hexdigest(data)
        }
      end
      payload
    rescue Errno::ENOENT
      errors << "#{label} is missing: #{path}"
      nil
    rescue SystemCallError => error
      errors << "#{label} cannot be read safely: #{path} (#{error.message})"
      nil
    end

    def verified_evidence_root(path, errors)
      expanded = File.expand_path(path)
      unless File.directory?(expanded)
        errors << "evidence directory is missing: #{path}"
        return nil
      end
      File.realpath(expanded)
    rescue SystemCallError => error
      errors << "evidence directory cannot be resolved: #{path} (#{error.message})"
      nil
    end

    def verified_json_artifact(path, checksum, evidence_root, label, errors)
      absolute = verified_artifact_path(path, evidence_root, label, errors)
      return nil unless absolute
      payload = safely_read_regular_file(
        absolute,
        label,
        errors,
        maximum_bytes: MAX_JSON_ARTIFACT_BYTES,
        containment_root: evidence_root
      )
      return nil unless payload
      errors << "#{label} checksum mismatch for #{path}" unless checksum == payload.fetch(:sha256)
      document = parse_json_bytes(payload.fetch(:data), label, errors)
      return nil unless document
      [payload.fetch(:path), document]
    end

    def verified_artifact_bytes(path, checksum, evidence_root, label, errors)
      absolute = verified_artifact_path(path, evidence_root, label, errors)
      return nil unless absolute
      payload = safely_read_regular_file(
        absolute,
        label,
        errors,
        maximum_bytes: ViftyUIReview::MAX_PNG_FILE_BYTES,
        containment_root: evidence_root
      )
      return nil unless payload
      errors << "#{label} checksum mismatch for #{path}" unless checksum == payload.fetch(:sha256)
      payload.fetch(:data)
    end

    def verified_artifact_path(path, evidence_root, label, errors)
      unless path.is_a?(String) && !path.empty?
        errors << "#{label} artifact path is missing"
        return nil
      end
      if Pathname.new(path).absolute? || path.split(File::SEPARATOR).include?("..")
        errors << "#{label} artifact path escapes the evidence directory: #{path}"
        return nil
      end
      absolute = File.expand_path(path, evidence_root)
      unless absolute.start_with?(evidence_root + File::SEPARATOR)
        errors << "#{label} artifact path escapes the evidence directory: #{path}"
        return nil
      end
      unless File.file?(absolute)
        errors << "#{label} artifact is missing: #{path}"
        return nil
      end
      if File.symlink?(absolute)
        errors << "#{label} artifact must not be a symbolic link: #{path}"
        return nil
      end
      begin
        resolved = File.realpath(absolute)
      rescue SystemCallError => error
        errors << "#{label} artifact cannot be resolved: #{path} (#{error.message})"
        return nil
      end
      unless resolved.start_with?(evidence_root + File::SEPARATOR)
        errors << "#{label} artifact path escapes the evidence directory: #{path}"
        return nil
      end
      absolute
    end

    def parse_json_file(path, label, errors)
      return nil unless path
      data = File.binread(path)
      parse_json_bytes(data, label, errors)
    rescue Errno::ENOENT
      errors << "#{label} is missing: #{path}"
      nil
    end

    def parse_json_bytes(data, label, errors)
      document = JSON.parse(data)
      unless document.is_a?(Hash)
        errors << "#{label} must be a JSON object"
        return nil
      end
      document
    rescue JSON::ParserError => error
      errors << "#{label} is invalid JSON: #{error.message}"
      nil
    end

    def finish(errors, success: nil)
      unless errors.empty?
        errors.each { |error| warn "UI request/ledger contract blocked: #{error}" }
        return 1
      end
      puts success if success
      0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  unless [5, 6].include?(ARGV.length)
    warn "Usage: ui_review_verifier.rb <manifest> <evidence-dir> <release-binary> <debug-executable> <collector-executable> [initialized|contract|automated|matrix]"
    exit 64
  end
  exit ViftyUIReview::Verifier.run(
    manifest_path: ARGV[0],
    evidence_dir: ARGV[1],
    release_binary: ARGV[2],
    debug_executable: ARGV[3],
    collector_executable: ARGV[4],
    mode: ARGV[5] || "contract"
  )
end
