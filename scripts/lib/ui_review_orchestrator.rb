#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "securerandom"
require "shellwords"
require "time"
require_relative "ui_review_contract"
require_relative "ui_review_build_provenance"

module ViftyUIReview
  class OrchestrationError < StandardError
    attr_reader :code, :exit_code

    def initialize(code, message, exit_code: 75)
      super(message)
      @code = code
      @exit_code = exit_code
    end
  end

  module Orchestrator
    SESSION_SCHEMA_VERSION = 1
    CAPTURE_ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z/
    ROW_KINDS = %w[fixture visual accessibility].freeze
    POLL_INTERVAL_SECONDS = 0.02
    FIXTURE_HOLD_SECONDS = 120.0
    COLLECTOR_WALL_TIMEOUT_SECONDS = 30.0
    TRANSIENT_WINDOW_CAPTURE_PATTERN = /\Awindow-capture-[0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\.png\z/

    Outcome = Struct.new(:document, :exit_code, keyword_init: true)

    module_function

    def run(mode, argv)
      options = parse_options(mode, argv)
      case mode
      when "capture" then capture(options)
      when "collect-ax" then collect_ax(options)
      when "seal" then seal(options)
      else
        raise OrchestrationError.new("USAGE", "unknown orchestration mode: #{mode}", exit_code: 64)
      end
    rescue OptionParser::ParseError, ArgumentError => error
      Outcome.new(
        document: failure_document(mode, "USAGE", error.message),
        exit_code: 64
      )
    rescue OrchestrationError => error
      Outcome.new(
        document: failure_document(mode, error.code, error.message),
        exit_code: error.exit_code
      )
    rescue StandardError => error
      Outcome.new(
        document: failure_document(mode, "INTERNAL_ERROR", error.message),
        exit_code: 70
      )
    end

    def parse_options(mode, argv)
      options = {
        timeout_seconds: 5.0,
        fixture_hold_seconds: FIXTURE_HOLD_SECONDS,
        collector_wall_timeout_seconds: COLLECTOR_WALL_TIMEOUT_SECONDS,
        maximum_nodes: 2_048,
        maximum_depth: 32
      }
      parser = OptionParser.new do |value|
        value.on("--manifest PATH") { |item| options[:manifest] = item }
        value.on("--evidence-dir PATH") { |item| options[:evidence_dir] = item }
        value.on("--debug-executable PATH") { |item| options[:debug_executable] = item }
        value.on("--collector-executable PATH") { |item| options[:collector_executable] = item }
        value.on("--row-kind KIND") { |item| options[:row_kind] = item }
        value.on("--row-id ID") { |item| options[:row_id] = item }
        value.on("--capture-id ID") { |item| options[:capture_id] = item }
        value.on("--timeout-seconds SECONDS", Float) { |item| options[:timeout_seconds] = item }
        value.on("--fixture-hold-seconds SECONDS", Float) { |item| options[:fixture_hold_seconds] = item }
        value.on("--collector-wall-timeout-seconds SECONDS", Float) { |item| options[:collector_wall_timeout_seconds] = item }
        value.on("--maximum-nodes COUNT", Integer) { |item| options[:maximum_nodes] = item }
        value.on("--maximum-depth DEPTH", Integer) { |item| options[:maximum_depth] = item }
      end
      parser.parse!(argv)
      raise OptionParser::InvalidOption, argv.join(" ") unless argv.empty?

      %i[manifest evidence_dir debug_executable].each do |key|
        raise OptionParser::MissingArgument, "--#{key.to_s.tr("_", "-")}" unless options[key]
      end
      case mode
      when "capture"
        %i[row_kind row_id].each do |key|
          raise OptionParser::MissingArgument, "--#{key.to_s.tr("_", "-")}" unless options[key]
        end
      when "collect-ax"
        %i[capture_id collector_executable].each do |key|
          raise OptionParser::MissingArgument, "--#{key.to_s.tr("_", "-")}" unless options[key]
        end
      when "seal"
        raise OptionParser::MissingArgument, "--capture-id" unless options[:capture_id]
      end
      maximum_timeout = mode == "collect-ax" ? 10.0 : 120.0
      unless options[:timeout_seconds].finite? && options[:timeout_seconds] >= 0.1 && options[:timeout_seconds] <= maximum_timeout
        raise OptionParser::InvalidArgument, "--timeout-seconds must be between 0.1 and #{maximum_timeout.to_i}"
      end
      unless options[:fixture_hold_seconds].finite? && options[:fixture_hold_seconds] >= 30 && options[:fixture_hold_seconds] <= 300
        raise OptionParser::InvalidArgument, "--fixture-hold-seconds must be between 30 and 300"
      end
      unless options[:collector_wall_timeout_seconds].finite? && options[:collector_wall_timeout_seconds] >= 0.1 && options[:collector_wall_timeout_seconds] <= 120
        raise OptionParser::InvalidArgument, "--collector-wall-timeout-seconds must be between 0.1 and 120"
      end
      unless options[:maximum_nodes].between?(1, 16_384)
        raise OptionParser::InvalidArgument, "--maximum-nodes is outside the bounded range"
      end
      unless options[:maximum_depth].between?(1, 128)
        raise OptionParser::InvalidArgument, "--maximum-depth is outside the bounded range"
      end
      options
    end

    def capture(options)
      manifest_path = verified_file(options.fetch(:manifest), "manifest")
      evidence_root = verified_directory(options.fetch(:evidence_dir), create: true)
      debug_path = verified_executable(options.fetch(:debug_executable), "debug executable")
      debug_sha = Digest::SHA256.file(debug_path).hexdigest
      debug_provenance = embedded_provenance!(
        debug_path,
        role: "debug-fixture-app",
        configuration: "debug",
        label: "debug executable"
      )
      kind = options.fetch(:row_kind)
      raise OrchestrationError.new("INVALID_ROW_KIND", "unknown row kind: #{kind}", exit_code: 64) unless ROW_KINDS.include?(kind)

      manifest = parse_json(manifest_path, "manifest")
      row, request = verified_requirement(manifest, kind, options.fetch(:row_id))
      capture_id = generated_capture_id(kind, options.fetch(:row_id))
      captures_root = ensure_directory_within!(File.join(evidence_root, "captures"), evidence_root)
      capture_root = ensure_directory_within!(File.join(captures_root, capture_id), evidence_root)
      fixture_root = ensure_directory_within!(File.join(capture_root, "fixture"), evidence_root)
      completion_path = File.join(fixture_root, "completion.signal")
      report_path = File.join(fixture_root, "fixture-report.json")
      screenshot_path = kind == "visual" ? File.join(fixture_root, "screenshot.png") : nil
      process_log_path = File.join(capture_root, "process.log")
      session_path = File.join(capture_root, "session.json")
      request_sha = ViftyUIReview.sha256_json(request)
      session = {
        "schemaVersion" => SESSION_SCHEMA_VERSION,
        "mode" => "capture",
        "status" => "launching",
        "rowKind" => kind,
        "rowID" => requirement_id(row, kind),
        "captureID" => capture_id,
        "request" => request,
        "requestSHA256" => request_sha,
        "debugExecutablePath" => debug_path,
        "debugExecutableSHA256" => debug_sha,
        "debugBuildProvenance" => debug_provenance,
        "fixtureReportArtifact" => relative_artifact(report_path, evidence_root),
        "screenshotArtifact" => screenshot_path && relative_artifact(screenshot_path, evidence_root),
        "completionArtifact" => relative_artifact(completion_path, evidence_root),
        "processLogArtifact" => relative_artifact(process_log_path, evidence_root),
        "timeoutSeconds" => options.fetch(:timeout_seconds),
        "fixtureHoldSeconds" => options.fetch(:fixture_hold_seconds),
        "fixtureDeadlineEpochSeconds" => Time.now.to_f + options.fetch(:fixture_hold_seconds),
        "completionSignalSent" => false,
        "processIdentifier" => nil,
        "failureCode" => nil,
        "error" => nil
      }
      write_json_atomic(session_path, session, containment_root: evidence_root)

      readiness_deadline = monotonic_now + options.fetch(:timeout_seconds)
      fixture_arguments = fixture_arguments(
        request: request,
        capture_id: capture_id,
        output_path: fixture_root,
        screenshot_path: screenshot_path,
        completion_path: completion_path,
        executable_sha: debug_sha,
        timeout_seconds: options.fetch(:fixture_hold_seconds),
        readiness_deadline: readiness_deadline
      )
      process_log = open_output_file(
        process_log_path,
        evidence_root,
        flags: File::WRONLY | File::CREAT | File::EXCL
      )
      pid = Process.spawn(
        debug_path,
        *fixture_arguments,
        out: process_log,
        err: process_log,
        pgroup: true
      )
      process_log.close
      session["processIdentifier"] = pid
      write_json_atomic(session_path, session, containment_root: evidence_root)

      deadline = readiness_deadline
      report = wait_for_report(
        path: report_path,
        phase: "ready",
        pid: pid,
        deadline: deadline,
        timeout_code: "READY_TIMEOUT"
      )
      validate_fixture_report!(
        report,
        phase: "ready",
        capture_id: capture_id,
        request: request,
        request_sha: request_sha,
        debug_path: debug_path,
        debug_sha: debug_sha,
        debug_provenance: debug_provenance,
        pid: pid,
        requires_screenshot: kind == "visual"
      )
      cleanup_transient_window_captures!(fixture_root, evidence_root)

      if kind == "accessibility"
        session["status"] = "ready"
        write_json_atomic(session_path, session, containment_root: evidence_root)
        return Outcome.new(document: session, exit_code: 0)
      end

      signal_completion(completion_path, evidence_root)
      session["completionSignalSent"] = true
      report = wait_for_report(
        path: report_path,
        phase: "final",
        pid: pid,
        deadline: monotonic_now + options.fetch(:timeout_seconds),
        timeout_code: "FINAL_TIMEOUT"
      )
      validate_fixture_report!(
        report,
        phase: "final",
        capture_id: capture_id,
        request: request,
        request_sha: request_sha,
        debug_path: debug_path,
        debug_sha: debug_sha,
        debug_provenance: debug_provenance,
        pid: pid,
        requires_screenshot: kind == "visual"
      )
      wait_for_process_exit(pid, monotonic_now + options.fetch(:timeout_seconds))
      cleanup_transient_window_captures!(fixture_root, evidence_root)
      session["status"] = "passed"
      write_json_atomic(session_path, session, containment_root: evidence_root)
      Outcome.new(document: session, exit_code: 0)
    rescue OrchestrationError => error
      termination_succeeded = !defined?(pid) || !pid || terminate_owned_process_group(pid)
      if defined?(session) && session
        cleanup_error = if termination_succeeded
                          capture_cleanup_error(fixture_root, evidence_root)
                        else
                          OrchestrationError.new(
                            "PROCESS_GROUP_TERMINATION_FAILED",
                            "fixture process group remained alive after TERM and KILL"
                          )
                        end
        session["status"] = "failed"
        session["failureCode"] = if cleanup_error&.respond_to?(:code)
                                   cleanup_error.code
                                 elsif cleanup_error
                                   "TRANSIENT_CAPTURE_CLEANUP_FAILED"
                                 else
                                   error.code
                                 end
        session["error"] = cleanup_error ? "#{error.code}: #{error.message}; cleanup failed: #{cleanup_error.message}" : error.message
        write_json_atomic(session_path, session, containment_root: evidence_root) if defined?(session_path) && session_path
        write_json_atomic(File.join(capture_root, "orchestration.json"), session, containment_root: evidence_root) if defined?(capture_root) && capture_root
        return Outcome.new(document: session, exit_code: error.exit_code)
      end
      raise
    rescue StandardError => error
      termination_succeeded = !defined?(pid) || !pid || terminate_owned_process_group(pid)
      if defined?(session) && session
        cleanup_error = if termination_succeeded
                          capture_cleanup_error(fixture_root, evidence_root)
                        else
                          OrchestrationError.new(
                            "PROCESS_GROUP_TERMINATION_FAILED",
                            "fixture process group remained alive after TERM and KILL"
                          )
                        end
        session["status"] = "failed"
        session["failureCode"] = if cleanup_error&.respond_to?(:code)
                                   cleanup_error.code
                                 elsif cleanup_error
                                   "TRANSIENT_CAPTURE_CLEANUP_FAILED"
                                 else
                                   "INTERNAL_ERROR"
                                 end
        session["error"] = cleanup_error ? "INTERNAL_ERROR: #{error.message}; cleanup failed: #{cleanup_error.message}" : error.message
        write_json_atomic(session_path, session, containment_root: evidence_root) if defined?(session_path) && session_path
        write_json_atomic(File.join(capture_root, "orchestration.json"), session, containment_root: evidence_root) if defined?(capture_root) && capture_root
        return Outcome.new(document: session, exit_code: 70)
      end
      raise
    end

    def collect_ax(options)
      trusted_fixture_pid = nil
      manifest_path = verified_file(options.fetch(:manifest), "manifest")
      evidence_root = verified_directory(options.fetch(:evidence_dir))
      debug_path = verified_executable(options.fetch(:debug_executable), "debug executable")
      debug_sha = Digest::SHA256.file(debug_path).hexdigest
      debug_provenance = embedded_provenance!(
        debug_path,
        role: "debug-fixture-app",
        configuration: "debug",
        label: "debug executable"
      )
      collector_path = verified_executable(options.fetch(:collector_executable), "AX collector")
      collector_sha = Digest::SHA256.file(collector_path).hexdigest
      collector_provenance = embedded_provenance!(
        collector_path,
        role: "ax-collector",
        configuration: "debug",
        label: "AX collector"
      )
      validate_one_build_transaction!(debug_provenance, collector_provenance)
      capture_id = verified_capture_id(options.fetch(:capture_id))
      session_artifact = File.join("captures", capture_id, "session.json")
      session_path = verified_artifact_path(session_artifact, evidence_root, "capture session")
      session = parse_json(session_path, "capture session")
      validate_session!(
        session,
        capture_id: capture_id,
        debug_path: debug_path,
        debug_sha: debug_sha,
        debug_provenance: debug_provenance,
        required_status: "ready"
      )
      unless session["rowKind"] == "accessibility"
        raise OrchestrationError.new("WRONG_ROW_KIND", "--collect-ax requires an accessibility capture", exit_code: 64)
      end
      pid = session.fetch("processIdentifier")
      trusted_fixture_pid = verified_live_fixture_process!(
        pid,
        debug_path,
        capture_id: capture_id,
        fixture_root: File.join(File.dirname(session_path), "fixture")
      )
      pid = trusted_fixture_pid
      manifest = parse_json(manifest_path, "manifest")
      row, request = verified_requirement(manifest, "accessibility", session.fetch("rowID"))
      unless request == session["request"]
        raise OrchestrationError.new("REQUEST_MISMATCH", "capture request no longer matches the verifier-owned row")
      end
      session["collectorExecutablePath"] = collector_path
      session["collectorExecutableSHA256"] = collector_sha
      session["collectorBuildProvenance"] = collector_provenance
      write_json_atomic(session_path, session, containment_root: evidence_root)
      fixture_deadline = session["fixtureDeadlineEpochSeconds"]
      required_remaining = options.fetch(:collector_wall_timeout_seconds) +
        (2 * options.fetch(:timeout_seconds)) + POLL_INTERVAL_SECONDS
      unless fixture_deadline.is_a?(Numeric) && fixture_deadline.to_f.finite? &&
             fixture_deadline - Time.now.to_f > required_remaining
        raise OrchestrationError.new(
          "FIXTURE_HOLD_INSUFFICIENT",
          "fixture hold has insufficient time for collector wall timeout and finalization"
        )
      end

      capture_root = File.dirname(session_path)
      ax_root = ensure_directory_within!(File.join(capture_root, "ax"), evidence_root)
      request_path = File.join(ax_root, "request.json")
      raw_path = File.join(ax_root, "raw.json")
      collector_log_path = File.join(ax_root, "collector.log")
      write_json_atomic(request_path, request, containment_root: evidence_root)
      prepare_output_path!(raw_path, evidence_root)
      prepare_output_path!(collector_log_path, evidence_root)
      collector_arguments = [
        "collect",
        "--pid", pid.to_s,
        "--capture-id", capture_id,
        "--check-id", requirement_id(row, "accessibility"),
        "--window-identifier", "vifty-ui-review-ax-window-#{capture_id}",
        "--root-identifier", "vifty.ax.fixture.root.#{capture_id}",
        "--request-json", request_path,
        "--output", raw_path,
        "--timeout-seconds", options.fetch(:timeout_seconds).to_s,
        "--maximum-nodes", options.fetch(:maximum_nodes).to_s,
        "--maximum-depth", options.fetch(:maximum_depth).to_s
      ]
      collector_status = run_bounded_process(
        collector_path,
        collector_arguments,
        collector_log_path,
        timeout_seconds: options.fetch(:collector_wall_timeout_seconds),
        timeout_code: "AX_COLLECTOR_TIMEOUT",
        containment_root: evidence_root
      )
      ensure_executable_unchanged!(
        collector_path,
        collector_sha,
        code: "AX_COLLECTOR_MISMATCH",
        label: "AX collector"
      )

      completion_path = verified_artifact_path(
        session.fetch("completionArtifact"),
        evidence_root,
        "completion signal",
        allow_missing: true
      )
      signal_completion(completion_path, evidence_root)
      session["completionSignalSent"] = true
      report_path = verified_artifact_path(
        session.fetch("fixtureReportArtifact"),
        evidence_root,
        "fixture report"
      )
      report = wait_for_report(
        path: report_path,
        phase: "final",
        pid: pid,
        deadline: monotonic_now + options.fetch(:timeout_seconds),
        timeout_code: "FINAL_TIMEOUT"
      )
      validate_fixture_report!(
        report,
        phase: "final",
        capture_id: capture_id,
        request: request,
        request_sha: session.fetch("requestSHA256"),
        debug_path: debug_path,
        debug_sha: session.fetch("debugExecutableSHA256"),
        debug_provenance: debug_provenance,
        pid: pid,
        requires_screenshot: false
      )
      wait_for_process_exit(pid, monotonic_now + options.fetch(:timeout_seconds))
      session["rawAccessibilityArtifact"] = relative_artifact(raw_path, evidence_root) if File.file?(raw_path)
      session["collectorLogArtifact"] = relative_artifact(collector_log_path, evidence_root)

      if collector_status.zero?
        raise OrchestrationError.new("AX_RAW_MISSING", "AX collector succeeded without writing raw evidence") unless File.file?(raw_path)
        raw = parse_json(raw_path, "raw AX capture")
        unless raw["collectorBuildProvenance"] == collector_provenance
          raise OrchestrationError.new(
            "AX_COLLECTOR_MISMATCH",
            "raw AX capture does not match the collector embedded build provenance"
          )
        end

        session["status"] = "collected"
        session["failureCode"] = nil
        session["error"] = nil
      elsif collector_status == 77
        session["status"] = "permission-blocked"
        session["failureCode"] = "AX_PERMISSION_MISSING"
        session["error"] = structured_collector_error(raw_path) || "Accessibility permission is missing"
      else
        session["status"] = "failed"
        session["failureCode"] = "AX_COLLECTION_FAILED"
        session["error"] = structured_collector_error(raw_path) || "AX collector exited #{collector_status}"
      end
      write_json_atomic(session_path, session, containment_root: evidence_root)
      Outcome.new(document: session, exit_code: collector_status)
    rescue OrchestrationError => error
      if defined?(session) && session
        begin
          completion = verified_artifact_path(
            session.fetch("completionArtifact"),
            evidence_root,
            "completion signal",
            allow_missing: true
          )
          signal_completion(completion, evidence_root)
          session["completionSignalSent"] = true
        rescue StandardError
          nil
        end
        session["status"] = "failed"
        session["failureCode"] = error.code
        session["error"] = error.message
        write_json_atomic(session_path, session, containment_root: evidence_root) if defined?(session_path) && session_path
        if trusted_fixture_pid && !terminate_owned_process_group(trusted_fixture_pid)
          session["failureCode"] = "PROCESS_GROUP_TERMINATION_FAILED"
          session["error"] = "fixture process group remained alive after TERM and KILL"
          write_json_atomic(session_path, session, containment_root: evidence_root) if defined?(session_path) && session_path
        end
        return Outcome.new(document: session, exit_code: error.exit_code)
      end
      raise
    end

    def seal(options)
      manifest_path = verified_file(options.fetch(:manifest), "manifest")
      evidence_root = verified_directory(options.fetch(:evidence_dir))
      debug_path = verified_executable(options.fetch(:debug_executable), "debug executable")
      debug_sha = Digest::SHA256.file(debug_path).hexdigest
      debug_provenance = embedded_provenance!(
        debug_path,
        role: "debug-fixture-app",
        configuration: "debug",
        label: "debug executable"
      )
      capture_id = verified_capture_id(options.fetch(:capture_id))
      session_artifact = File.join("captures", capture_id, "session.json")
      session_path = verified_artifact_path(session_artifact, evidence_root, "capture session")
      session = parse_json(session_path, "capture session")
      acceptable_statuses = session["rowKind"] == "accessibility" ? ["collected", "sealed"] : ["passed", "sealed"]
      unless acceptable_statuses.include?(session["status"])
        raise OrchestrationError.new("CAPTURE_NOT_FINAL", "capture is not ready to seal (#{session["status"].inspect})")
      end
      validate_session!(
        session,
        capture_id: capture_id,
        debug_path: debug_path,
        debug_sha: debug_sha,
        debug_provenance: debug_provenance
      )
      unless session["debugExecutableSHA256"] == debug_sha
        raise OrchestrationError.new("EXECUTABLE_MISMATCH", "debug executable checksum changed before sealing")
      end

      manifest = parse_json(manifest_path, "manifest")
      kind = session.fetch("rowKind")
      row, request = verified_requirement(manifest, kind, session.fetch("rowID"))
      unless request == session["request"]
        raise OrchestrationError.new("REQUEST_MISMATCH", "capture request no longer matches the verifier-owned row")
      end
      report_path = verified_artifact_path(
        session.fetch("fixtureReportArtifact"),
        evidence_root,
        "final fixture report"
      )
      report = parse_json(report_path, "final fixture report")
      validate_fixture_report!(
        report,
        phase: "final",
        capture_id: capture_id,
        request: request,
        request_sha: session.fetch("requestSHA256"),
        debug_path: debug_path,
        debug_sha: debug_sha,
        debug_provenance: debug_provenance,
        pid: session.fetch("processIdentifier"),
        requires_screenshot: kind == "visual"
      )
      report_sha = Digest::SHA256.file(report_path).hexdigest
      entry = {
        "request" => request,
        "requestSHA256" => session.fetch("requestSHA256"),
        "fixtureReportArtifact" => session.fetch("fixtureReportArtifact"),
        "fixtureReportSHA256" => report_sha,
        "debugExecutablePath" => debug_path,
        "debugExecutableSHA256" => debug_sha,
        "debugBuildProvenance" => debug_provenance,
        "runtimeIdentity" => report.fetch("runtimeIdentity")
      }

      if kind == "visual"
        screenshot_path = verified_artifact_path(
          session.fetch("screenshotArtifact"),
          evidence_root,
          "screenshot"
        )
        screenshot_report = report.fetch("screenshot")
        screenshot_sha = Digest::SHA256.file(screenshot_path).hexdigest
        unless screenshot_report.is_a?(Hash) && screenshot_report["sha256"] == screenshot_sha
          raise OrchestrationError.new("SCREENSHOT_MISMATCH", "fixture screenshot binding does not match the captured PNG")
        end
        identity = report.fetch("runtimeIdentity")
        pixel_width = (identity.fetch("contentWidth") * identity.fetch("backingScaleFactor")).round
        pixel_height = (identity.fetch("contentHeight") * identity.fetch("backingScaleFactor")).round
        analysis = ViftyUIReview.analyze_png(
          screenshot_path,
          expected_width: pixel_width,
          expected_height: pixel_height
        )
        entry["screenshot"] = {
          "artifact" => session.fetch("screenshotArtifact"),
          "sha256" => screenshot_sha,
          "canonicalPixelSHA256" => analysis.fetch(:canonical_pixel_sha256)
        }
      elsif kind == "accessibility"
        collector_path = verified_executable(options[:collector_executable], "AX collector") if options[:collector_executable]
        unless collector_path
          raise OrchestrationError.new("USAGE", "--collector-executable is required to seal AX evidence", exit_code: 64)
        end
        collector_sha = Digest::SHA256.file(collector_path).hexdigest
        collector_provenance = embedded_provenance!(
          collector_path,
          role: "ax-collector",
          configuration: "debug",
          label: "AX collector"
        )
        validate_one_build_transaction!(debug_provenance, collector_provenance)
        unless session["collectorExecutablePath"] == collector_path &&
               session["collectorExecutableSHA256"] == collector_sha &&
               session["collectorBuildProvenance"] == collector_provenance
          raise OrchestrationError.new(
            "AX_COLLECTOR_MISMATCH",
            "AX collector path and checksum must match the executable used for collection"
          )
        end
        raw_artifact = session.fetch("rawAccessibilityArtifact")
        raw_path = verified_artifact_path(raw_artifact, evidence_root, "raw AX capture")
        raw_sha = Digest::SHA256.file(raw_path).hexdigest
        sealed_path = File.join(File.dirname(raw_path), "sealed.json")
        seal_log_path = File.join(File.dirname(raw_path), "seal.log")
        prepare_output_path!(sealed_path, evidence_root)
        prepare_output_path!(seal_log_path, evidence_root)
        collector_status = run_bounded_process(
          collector_path,
          [
            "seal",
            "--raw-capture", raw_path,
            "--raw-capture-sha256", raw_sha,
            "--fixture-report", report_path,
            "--fixture-report-sha256", report_sha,
            "--debug-executable", debug_path,
            "--debug-executable-sha256", debug_sha,
            "--output", sealed_path
          ],
          seal_log_path,
          timeout_seconds: options.fetch(:timeout_seconds),
          timeout_code: "AX_SEAL_TIMEOUT",
          containment_root: evidence_root
        )
        ensure_executable_unchanged!(
          collector_path,
          collector_sha,
          code: "AX_COLLECTOR_MISMATCH",
          label: "AX collector"
        )
        unless collector_status.zero? && File.file?(sealed_path)
          raise OrchestrationError.new("AX_SEAL_FAILED", "AX collector seal exited #{collector_status}")
        end
        validate_sealed_ax!(
          parse_json(sealed_path, "sealed AX report"),
          row_id: requirement_id(row, kind),
          capture_id: capture_id,
          request: request,
          raw_sha: raw_sha,
          raw_path: raw_path,
          report_sha: report_sha,
          report_path: report_path,
          debug_sha: debug_sha,
          debug_provenance: debug_provenance,
          collector_provenance: collector_provenance,
          pid: session.fetch("processIdentifier")
        )
        entry["accessibility"] = {
          "rawArtifact" => raw_artifact,
          "rawSHA256" => raw_sha,
          "artifact" => relative_artifact(sealed_path, evidence_root),
          "sha256" => Digest::SHA256.file(sealed_path).hexdigest,
          "collectorExecutablePath" => collector_path,
          "collectorExecutableSHA256" => collector_sha,
          "collectorBuildProvenance" => collector_provenance
        }
      end

      install_ledger_entry!(manifest, kind, session.fetch("rowID"), capture_id, entry)
      write_json_atomic(manifest_path, manifest)
      ledger_artifact = File.join(File.dirname(session_path), "sealed-ledger-entry.json")
      write_json_atomic(ledger_artifact, entry, containment_root: evidence_root)
      session["status"] = "sealed"
      session["sealedLedgerEntryArtifact"] = relative_artifact(ledger_artifact, evidence_root)
      write_json_atomic(session_path, session, containment_root: evidence_root)
      Outcome.new(document: session, exit_code: 0)
    rescue ViftyUIReview::PNGError => error
      raise OrchestrationError.new("INVALID_PNG", error.message)
    end

    def verified_requirement(manifest, kind, id)
      expected = expected_requests(kind)[id]
      raise OrchestrationError.new("UNKNOWN_ROW", "unknown #{kind} row: #{id}", exit_code: 64) unless expected

      rows = manifest[rows_key(kind)]
      raise OrchestrationError.new("MANIFEST_INVALID", "#{rows_key(kind)} must be an array") unless rows.is_a?(Array)
      matches = rows.select { |row| row.is_a?(Hash) && requirement_id(row, kind) == id }
      raise OrchestrationError.new("MANIFEST_INVALID", "manifest must contain exactly one #{kind} row #{id}") unless matches.length == 1
      row = matches.first
      raise OrchestrationError.new("REQUEST_MISMATCH", "manifest request differs from verifier-owned request for #{id}") unless row["request"] == expected

      [row, expected]
    end

    def expected_requests(kind)
      case kind
      when "fixture" then ViftyUIReview.expected_fixture_requests
      when "visual" then ViftyUIReview.expected_visual_requests
      when "accessibility" then ViftyUIReview.expected_ax_requests
      else {}
      end
    end

    def rows_key(kind)
      {
        "fixture" => "fixtureReports",
        "visual" => "visualCells",
        "accessibility" => "accessibilityChecks"
      }.fetch(kind)
    end

    def requirement_id(row, kind)
      row[kind == "fixture" ? "state" : "id"]
    end

    def fixture_arguments(request:, capture_id:, output_path:, screenshot_path:, completion_path:, executable_sha:, timeout_seconds:, readiness_deadline:)
      arguments = [
        "-ApplePersistenceIgnoreState", "YES",
        "--ui-review-fixture", request.fetch("state"),
        "--ui-review-surface", request.fetch("surface"),
        "--ui-review-window", request.fetch("window"),
        "--ui-review-appearance", request.fetch("appearance"),
        "--ui-review-contrast", request.fetch("contrast"),
        "--ui-review-transparency", request.fetch("transparency"),
        "--ui-review-text-size", request.fetch("textSize"),
        "--ui-review-interaction", request.fetch("interaction"),
        "--ui-review-capture-id", capture_id,
        "--ui-review-output", output_path,
        "--ui-review-completion-file", completion_path,
        "--ui-review-timeout-seconds", timeout_seconds.to_s,
        "--ui-review-readiness-deadline-uptime", readiness_deadline.to_s,
        "--ui-review-executable-sha256", executable_sha
      ]
      arguments.concat(["--ui-review-screenshot", screenshot_path]) if screenshot_path
      arguments
    end

    def generated_capture_id(kind, id)
      prefix = "#{kind}-#{id}".gsub(/[^A-Za-z0-9._-]/, "-")[0, 80]
      "#{prefix}-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{SecureRandom.hex(6)}"
    end

    def verified_capture_id(value)
      unless value.is_a?(String) && CAPTURE_ID_PATTERN.match?(value)
        raise OrchestrationError.new("INVALID_CAPTURE_ID", "capture ID is invalid", exit_code: 64)
      end
      value
    end

    def wait_for_report(path:, phase:, pid:, deadline:, timeout_code:)
      loop do
        report = parse_json_if_complete(path)
        return report if report && report["phase"] == phase
        if report && report["phase"] == "final" && phase != "final"
          failure = report["runtimeFailure"]
          detail = failure.is_a?(String) && !failure.empty? ? ": #{failure}" : ""
          raise OrchestrationError.new(
            "FIXTURE_REPORTED_FAILURE",
            "fixture reported final before #{phase}#{detail}"
          )
        end
        if process_exited?(pid)
          raise OrchestrationError.new("PROCESS_EXITED", "fixture process exited before #{phase}")
        end
        if monotonic_now >= deadline
          raise OrchestrationError.new(timeout_code, "timed out waiting for fixture phase #{phase}")
        end
        sleep POLL_INTERVAL_SECONDS
      end
    end

    def validate_fixture_report!(report, phase:, capture_id:, request:, request_sha:, debug_path:, debug_sha:, debug_provenance:, pid:, requires_screenshot:)
      unless report.is_a?(Hash) && report["schemaVersion"] == 3
        raise OrchestrationError.new("REPORT_INVALID", "fixture report schema mismatch")
      end
      checks = {
        "capture ID" => report["captureID"] == capture_id,
        "semantic request" => report["request"] == request,
        "request checksum" => report["requestSHA256"] == request_sha,
        "debug executable path" => report["debugExecutablePath"] == debug_path,
        "debug executable checksum" => report["debugExecutableSHA256"] == debug_sha,
        "debug build provenance" => report["debugBuildProvenance"] == debug_provenance,
        "phase" => report["phase"] == phase,
        "model start guard" => report["modelStartSkipped"] == true,
        "runtime failure" => report["runtimeFailure"].nil?,
        "pass status" => report["passed"] == true
      }
      failed = checks.select { |_label, passed| !passed }.keys
      unless failed.empty?
        raise OrchestrationError.new("REPORT_BINDING_MISMATCH", "fixture report mismatch: #{failed.join(", ")}")
      end
      identity = report["runtimeIdentity"]
      validate_runtime_identity!(
        identity,
        request: request,
        capture_id: capture_id,
        debug_path: debug_path,
        debug_sha: debug_sha,
        pid: pid
      )
      validate_observed_fixture_contract!(report, identity, request, requires_screenshot: requires_screenshot)
      recorder = report["recorder"]
      recorder_errors = ViftyUIReview.fixture_recorder_errors(recorder)
      unless recorder_errors.empty?
        raise OrchestrationError.new("UNSAFE_FIXTURE", "fixture recorder contract failed: #{recorder_errors.join("; ")}")
      end
      report
    end

    def validate_runtime_identity!(identity, request:, capture_id:, debug_path:, debug_sha:, pid:)
      expected_keys = %w[
        processIdentifier executablePath executableSHA256 provenance windowNumber
        windowIdentifier accessibilityIdentifier windowClass containerKind isVisible
        contentWidth contentHeight backingScaleFactor
      ]
      unless identity.is_a?(Hash) && identity.keys.sort == expected_keys.sort
        raise OrchestrationError.new("RUNTIME_IDENTITY_MISMATCH", "fixture runtime identity keys are invalid")
      end
      checks = {
        "process identifier" => identity["processIdentifier"] == pid,
        "executable path" => identity["executablePath"] == debug_path,
        "executable checksum" => identity["executableSHA256"] == debug_sha,
        "window identifier" => identity["windowIdentifier"] == "vifty-ui-review-window-#{capture_id}",
        "accessibility identifier" => identity["accessibilityIdentifier"] == "vifty-ui-review-ax-window-#{capture_id}",
        "provenance" => identity["provenance"] == ViftyUIReview.expected_provenance(request),
        "container" => identity["containerKind"] == ViftyUIReview.expected_container_kind(request),
        "visibility" => identity["isVisible"] == true,
        "window number" => identity["windowNumber"].is_a?(Integer) && identity["windowNumber"].positive?,
        "window class" => identity["windowClass"].is_a?(String) && !identity["windowClass"].empty?,
        "content width" => identity["contentWidth"].is_a?(Integer) && identity["contentWidth"].positive?,
        "content height" => identity["contentHeight"].is_a?(Integer) && identity["contentHeight"].positive?,
        "backing scale" => identity["backingScaleFactor"].is_a?(Numeric) &&
          identity["backingScaleFactor"].to_f.finite? &&
          identity["backingScaleFactor"].positive? &&
          identity["backingScaleFactor"] <= 4
      }
      expected_width, expected_height = exact_runtime_geometry(request)
      checks["content width"] &&= identity["contentWidth"] == expected_width if expected_width
      checks["content height"] &&= identity["contentHeight"] == expected_height if expected_height
      failed = checks.select { |_label, passed| !passed }.keys
      unless failed.empty?
        raise OrchestrationError.new("RUNTIME_IDENTITY_MISMATCH", "fixture runtime identity mismatch: #{failed.join(", ")}")
      end
    end

    def exact_runtime_geometry(request)
      case request.fetch("window")
      when "native" then [600, 420]
      when "320xauto" then [320, nil]
      else ViftyUIReview.expected_geometry(request)
      end
    end

    def validate_observed_fixture_contract!(report, identity, request, requires_screenshot:)
      observed = report["observed"]
      environment = observed.is_a?(Hash) ? observed["environment"] : nil
      expected_environment = {
        "source" => "swiftui-environment",
        "appearance" => request["appearance"],
        "contrast" => request["contrast"],
        "transparency" => request["transparency"],
        "textSize" => request["textSize"]
      }
      unless environment == expected_environment
        raise OrchestrationError.new("OBSERVED_ENVIRONMENT_MISMATCH", "observed SwiftUI environment does not match the request")
      end
      expected_window = identity.reject do |key, _value|
        %w[processIdentifier executablePath executableSHA256].include?(key)
      end.merge("source" => "nswindow-content-layout-rect")
      unless observed["window"] == expected_window
        raise OrchestrationError.new("OBSERVED_WINDOW_MISMATCH", "observed NSWindow does not equal the runtime identity")
      end

      screenshot = report["screenshot"]
      unless requires_screenshot
        unless screenshot.nil?
          raise OrchestrationError.new("SCREENSHOT_UNEXPECTED", "non-visual fixture report contains screenshot evidence")
        end
        return
      end
      scale = identity.fetch("backingScaleFactor")
      expected_screenshot = {
        "method" => "native-window-screencapture-crop",
        "pointWidth" => identity.fetch("contentWidth"),
        "pointHeight" => identity.fetch("contentHeight"),
        "pixelWidth" => (identity.fetch("contentWidth") * scale).round,
        "pixelHeight" => (identity.fetch("contentHeight") * scale).round,
        "backingScaleFactor" => scale
      }
      unless screenshot.is_a?(Hash) &&
             expected_screenshot.all? { |key, value| screenshot[key] == value } &&
             screenshot["artifactPath"] == "screenshot.png" &&
             screenshot["sha256"].is_a?(String) && /\A[a-f0-9]{64}\z/.match?(screenshot["sha256"])
        raise OrchestrationError.new("SCREENSHOT_REPORT_MISMATCH", "screenshot report dimensions or capture method are invalid")
      end
    end

    def validate_session!(session, capture_id:, debug_path:, debug_sha:, debug_provenance:, required_status: nil)
      unless session["schemaVersion"] == SESSION_SCHEMA_VERSION && session["captureID"] == capture_id
        raise OrchestrationError.new("SESSION_MISMATCH", "capture session identity mismatch")
      end
      if required_status && session["status"] != required_status
        raise OrchestrationError.new("SESSION_STATE", "capture session must be #{required_status}")
      end
      unless session["debugExecutablePath"] == debug_path
        raise OrchestrationError.new("EXECUTABLE_MISMATCH", "capture session debug executable path mismatch")
      end
      unless session["debugExecutableSHA256"] == debug_sha
        raise OrchestrationError.new("EXECUTABLE_MISMATCH", "capture session debug executable checksum mismatch")
      end
      unless session["debugBuildProvenance"] == debug_provenance
        raise OrchestrationError.new("EXECUTABLE_MISMATCH", "capture session debug build provenance mismatch")
      end
      request = session["request"]
      unless request.is_a?(Hash) && session["requestSHA256"] == ViftyUIReview.sha256_json(request)
        raise OrchestrationError.new("SESSION_INTEGRITY_MISMATCH", "capture session request checksum mismatch")
      end
      unless valid_process_identifier?(session["processIdentifier"])
        raise OrchestrationError.new(
          "SESSION_INTEGRITY_MISMATCH",
          "capture session processIdentifier must be a safe positive process ID"
        )
      end
      true
    end

    def validate_sealed_ax!(sealed, row_id:, capture_id:, request:, raw_sha:, raw_path:, report_sha:, report_path:, debug_sha:, debug_provenance:, collector_provenance:, pid:)
      unless sealed["schemaVersion"] == 1 &&
             sealed["schemaID"] == "https://vifty.app/schemas/ui-review-ax-sealed-report-v1.schema.json"
        raise OrchestrationError.new("AX_SEAL_INVALID", "sealed AX schema mismatch")
      end
      evidence_request = sealed["request"]
      expected_window_identifier = "vifty-ui-review-ax-window-#{capture_id}"
      expected_root_identifier = "vifty.ax.fixture.root.#{capture_id}"
      unless evidence_request.is_a?(Hash) &&
             evidence_request["checkID"] == row_id &&
             evidence_request["captureID"] == capture_id &&
             evidence_request["processIdentifier"] == pid &&
             evidence_request["windowIdentifier"] == expected_window_identifier &&
             evidence_request["rootIdentifier"] == expected_root_identifier &&
             evidence_request["semanticRequest"] == request &&
             evidence_request["requestSHA256"] == ViftyUIReview.sha256_json(request)
        raise OrchestrationError.new("AX_SEAL_INVALID", "sealed AX request binding mismatch")
      end
      unless sealed.dig("rawCapture", "sha256") == raw_sha &&
             sealed.dig("rawCapture", "artifact") == raw_path &&
             sealed.dig("fixtureReport", "sha256") == report_sha &&
             sealed.dig("fixtureReport", "artifact") == report_path &&
             sealed["debugExecutableSHA256"] == debug_sha &&
             sealed["debugBuildProvenance"] == debug_provenance &&
             sealed["collectorBuildProvenance"] == collector_provenance
        raise OrchestrationError.new("AX_SEAL_INVALID", "sealed AX artifact binding mismatch")
      end
      expected_target = {
        "processIdentifier" => pid,
        "windowIdentifier" => expected_window_identifier,
        "rootIdentifier" => expected_root_identifier
      }
      unless sealed["runtimeIdentity"] == expected_target
        raise OrchestrationError.new("AX_SEAL_INVALID", "sealed AX runtime identity mismatch")
      end
      assertion = sealed["assertion"]
      unless assertion.is_a?(Hash) &&
             assertion["id"] == row_id &&
             assertion["passed"] == true &&
             Array(assertion["failures"]).empty? &&
             sealed["actionsPerformed"] == []
        raise OrchestrationError.new("AX_SEMANTIC_FAILURE", "sealed AX predicate did not pass read-only")
      end
    end

    def install_ledger_entry!(manifest, kind, row_id, capture_id, entry)
      conflicting = %w[fixture visual accessibility].any? do |candidate|
        Array(manifest[rows_key(candidate)]).any? do |row|
          row.is_a?(Hash) && row["captureID"] == capture_id &&
            (candidate != kind || requirement_id(row, candidate) != row_id)
        end
      end
      raise OrchestrationError.new("CAPTURE_REUSED", "capture ID is already bound to another row") if conflicting

      rows = manifest.fetch(rows_key(kind))
      index = rows.index { |row| row.is_a?(Hash) && requirement_id(row, kind) == row_id }
      raise OrchestrationError.new("MANIFEST_INVALID", "target row disappeared before sealing") unless index
      existing_capture = rows[index]["captureID"]
      if existing_capture && existing_capture != capture_id
        raise OrchestrationError.new("ROW_ALREADY_SEALED", "target row is already bound to another capture")
      end
      rows[index]["status"] = "passed"
      rows[index]["captureID"] = capture_id
      ledger = manifest["captureLedger"]
      raise OrchestrationError.new("MANIFEST_INVALID", "captureLedger must be an object") unless ledger.is_a?(Hash)
      if ledger.key?(capture_id) && ledger[capture_id] != entry
        raise OrchestrationError.new("LEDGER_CONFLICT", "capture ledger entry already exists with different content")
      end
      ledger[capture_id] = entry
    end

    def verified_live_fixture_process!(pid, debug_path, capture_id:, fixture_root:)
      unless valid_process_identifier?(pid)
        raise OrchestrationError.new("PID_IDENTITY_MISMATCH", "fixture PID is outside the safe process range")
      end
      raise OrchestrationError.new("PROCESS_EXITED", "fixture process is no longer running") unless process_alive?(pid)
      unless Process.getpgid(pid) == pid
        raise OrchestrationError.new(
          "PID_IDENTITY_MISMATCH",
          "fixture PID is not the leader of its dedicated process group"
        )
      end
      command = IO.popen(["/bin/ps", "-ww", "-p", pid.to_s, "-o", "command="], &:read).to_s.strip
      tokens = Shellwords.split(command)
      argument_offset = if tokens.first == debug_path
                          1
                        elsif tokens.length >= 2 &&
                              File.basename(tokens.first).start_with?("ruby") &&
                              tokens[1] == debug_path
                          2
                        end
      unless argument_offset
        raise OrchestrationError.new("PID_IDENTITY_MISMATCH", "live PID no longer belongs to the captured executable")
      end
      arguments = tokens.drop(argument_offset)
      unless command_argument(arguments, "--ui-review-capture-id") == capture_id &&
             command_argument(arguments, "--ui-review-output") == fixture_root
        raise OrchestrationError.new(
          "PID_IDENTITY_MISMATCH",
          "live PID command line does not match the captured fixture identity"
        )
      end
      pid
    rescue Errno::ESRCH
      raise OrchestrationError.new("PROCESS_EXITED", "fixture process is no longer running")
    rescue ArgumentError
      raise OrchestrationError.new("PID_IDENTITY_MISMATCH", "live PID command line cannot be parsed safely")
    end

    def command_argument(arguments, flag)
      index = arguments.index(flag)
      index && arguments[index + 1]
    end

    def run_bounded_process(executable, arguments, log_path, timeout_seconds:, timeout_code:, containment_root:)
      log = open_output_file(
        log_path,
        containment_root,
        flags: File::WRONLY | File::CREAT | File::TRUNC
      )
      pid = Process.spawn(executable, *arguments, out: log, err: log, pgroup: true)
      log.close
      deadline = monotonic_now + timeout_seconds
      loop do
        waited = Process.waitpid(pid, Process::WNOHANG)
        return $?.exitstatus if waited
        if monotonic_now >= deadline
          unless terminate_owned_process_group(pid)
            raise OrchestrationError.new(
              "PROCESS_GROUP_TERMINATION_FAILED",
              "bounded subprocess group remained alive after TERM and KILL"
            )
          end
          raise OrchestrationError.new(timeout_code, "bounded subprocess timed out")
        end
        sleep POLL_INTERVAL_SECONDS
      end
    rescue Errno::ECHILD
      $?&.exitstatus || 70
    end

    def wait_for_process_exit(pid, deadline)
      leader_reaped = false
      loop do
        leader_reaped ||= reap_process_nonblocking(pid)
        return if leader_reaped && !process_group_alive?(pid)
        if monotonic_now >= deadline
          unless terminate_owned_process_group(pid)
            raise OrchestrationError.new(
              "PROCESS_GROUP_TERMINATION_FAILED",
              "fixture process group remained alive after TERM and KILL"
            )
          end
          raise OrchestrationError.new("PROCESS_EXIT_TIMEOUT", "fixture process did not exit after final report")
        end
        sleep POLL_INTERVAL_SECONDS
      end
    end

    def terminate_owned_process_group(pid)
      return false unless valid_process_identifier?(pid)
      return true unless process_alive?(pid) || process_group_alive?(pid)

      begin
        Process.kill("TERM", -pid)
      rescue Errno::ESRCH, Errno::EPERM
        begin
          Process.kill("TERM", pid)
        rescue Errno::ESRCH, Errno::EPERM
          return false if process_alive?(pid) || process_group_alive?(pid)
        end
      end

      leader_reaped = false
      deadline = monotonic_now + 0.75
      while monotonic_now < deadline
        leader_reaped ||= reap_process_nonblocking(pid)
        break unless process_group_alive?(pid) || (!leader_reaped && process_alive?(pid))
        sleep POLL_INTERVAL_SECONDS
      end

      if process_group_alive?(pid)
        begin
          Process.kill("KILL", -pid)
        rescue Errno::ESRCH, Errno::EPERM
          begin
            Process.kill("KILL", pid)
          rescue Errno::ESRCH, Errno::EPERM
            nil
          end
        end
      elsif !leader_reaped && process_alive?(pid)
        begin
          Process.kill("KILL", pid)
        rescue Errno::ESRCH, Errno::EPERM
          nil
        end
      end

      kill_deadline = monotonic_now + 2.0
      while monotonic_now < kill_deadline
        leader_reaped ||= reap_process_nonblocking(pid)
        return true unless process_group_alive?(pid) || (!leader_reaped && process_alive?(pid))
        sleep POLL_INTERVAL_SECONDS
      end
      false
    end

    def reap_process_nonblocking(pid)
      !Process.waitpid(pid, Process::WNOHANG).nil?
    rescue Errno::ECHILD
      true
    end

    def valid_process_identifier?(pid)
      pid.is_a?(Integer) && pid > 1 && pid <= 2_147_483_647
    end

    def process_group_alive?(pid)
      Process.kill(0, -pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def capture_cleanup_error(fixture_root, evidence_root)
      return nil unless fixture_root && evidence_root

      cleanup_transient_window_captures!(fixture_root, evidence_root)
      nil
    rescue StandardError => error
      error
    end

    def cleanup_transient_window_captures!(fixture_root, evidence_root)
      fixture = ensure_directory_within!(fixture_root, evidence_root, create: false)
      Dir.children(fixture).sort.each do |name|
        next unless TRANSIENT_WINDOW_CAPTURE_PATTERN.match?(name)

        path = File.join(fixture, name)
        status = File.lstat(path)
        unless status.file? && !status.symlink?
          raise OrchestrationError.new(
            "UNSAFE_PATH",
            "transient window capture must be a regular non-symbolic-link file: #{path}"
          )
        end
        File.unlink(path)
      end
    rescue Errno::ENOENT => error
      raise OrchestrationError.new(
        "TRANSIENT_CAPTURE_CLEANUP_FAILED",
        "transient window capture changed during cleanup: #{error.message}"
      )
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end

    def process_exited?(pid)
      return true if Process.waitpid(pid, Process::WNOHANG)

      !process_alive?(pid)
    rescue Errno::ECHILD
      !process_alive?(pid)
    end

    def signal_completion(path, containment_root)
      verified_write_parent!(path, containment_root)
      File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) {}
    rescue Errno::EEXIST
      nil
    end

    def structured_collector_error(path)
      return nil unless File.file?(path)
      document = JSON.parse(File.read(path))
      document.dig("error", "code") || document["code"]
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def verified_file(path, label)
      raise OrchestrationError.new("MISSING_FILE", "#{label} is missing: #{path}", exit_code: 66) unless path && File.file?(path)
      raise OrchestrationError.new("UNSAFE_PATH", "#{label} must not be a symbolic link") if File.symlink?(path)
      File.realpath(path)
    rescue Errno::ENOENT
      raise OrchestrationError.new("MISSING_FILE", "#{label} is missing: #{path}", exit_code: 66)
    end

    def verified_executable(path, label)
      resolved = verified_file(path, label)
      raise OrchestrationError.new("NOT_EXECUTABLE", "#{label} is not executable: #{path}", exit_code: 66) unless File.executable?(resolved)
      resolved
    end

    def embedded_provenance!(path, role:, configuration:, label:)
      document = ViftyUIReview::BuildProvenance.extract!(
        File.binread(path),
        label: label
      )
      unless document["productRole"] == role && document["configuration"] == configuration
        raise OrchestrationError.new(
          "BUILD_PROVENANCE_MISMATCH",
          "#{label} embedded role/configuration does not match #{role}/#{configuration}"
        )
      end
      document
    rescue ViftyUIReview::BuildProvenance::ProvenanceError, SystemCallError => error
      raise OrchestrationError.new(
        "BUILD_PROVENANCE_MISMATCH",
        "#{label} embedded build provenance is invalid: #{error.message}"
      )
    end

    def validate_one_build_transaction!(*documents)
      commits = documents.map { |document| document["sourceCommit"] }.uniq
      trees = documents.map { |document| document["sourceTree"] }.uniq
      transactions = documents.map { |document| document["buildTransactionID"] }.uniq
      return true if commits.length == 1 && trees.length == 1 && transactions.length == 1

      raise OrchestrationError.new(
        "BUILD_PROVENANCE_MISMATCH",
        "UI review products must come from one source commit/tree and one build transaction"
      )
    end

    def ensure_executable_unchanged!(path, expected_sha, code:, label:)
      resolved = verified_executable(path, label)
      actual_sha = Digest::SHA256.file(resolved).hexdigest
      return true if resolved == path && actual_sha == expected_sha

      raise OrchestrationError.new(code, "#{label} path or checksum changed while evidence was collected")
    end

    def verified_directory(path, create: false)
      FileUtils.mkdir_p(path, mode: 0o700) if create
      raise OrchestrationError.new("MISSING_DIRECTORY", "evidence directory is missing: #{path}", exit_code: 66) unless File.directory?(path)
      raise OrchestrationError.new("UNSAFE_PATH", "evidence directory must not be a symbolic link") if File.symlink?(path)
      File.realpath(path)
    end

    def ensure_directory_within!(path, evidence_root, create: true)
      root = File.realpath(evidence_root)
      expanded = File.expand_path(path)
      prefix = root + File::SEPARATOR
      unless expanded == root || expanded.start_with?(prefix)
        raise OrchestrationError.new("ARTIFACT_ESCAPE", "directory escapes the evidence directory")
      end

      relative = expanded == root ? "" : expanded.delete_prefix(prefix)
      current = root
      Pathname.new(relative).each_filename do |component|
        current = File.join(current, component)
        begin
          status = File.lstat(current)
          if status.symlink?
            raise OrchestrationError.new("UNSAFE_PATH", "evidence directory component must not be a symbolic link: #{current}")
          end
          unless status.directory?
            raise OrchestrationError.new("UNSAFE_PATH", "evidence directory component is not a directory: #{current}")
          end
        rescue Errno::ENOENT
          unless create
            raise OrchestrationError.new("MISSING_DIRECTORY", "evidence directory component is missing: #{current}", exit_code: 66)
          end
          Dir.mkdir(current, 0o700)
        end
        resolved = File.realpath(current)
        unless resolved == root || resolved.start_with?(prefix)
          raise OrchestrationError.new("ARTIFACT_ESCAPE", "evidence directory component escapes the evidence directory: #{current}")
        end
      end
      File.realpath(expanded)
    rescue Errno::ENOENT
      raise OrchestrationError.new("MISSING_DIRECTORY", "evidence directory is missing: #{path}", exit_code: 66)
    end

    def verified_write_parent!(path, evidence_root)
      parent = ensure_directory_within!(File.dirname(path), evidence_root, create: false)
      candidate = File.expand_path(path)
      prefix = File.realpath(evidence_root) + File::SEPARATOR
      unless candidate.start_with?(prefix)
        raise OrchestrationError.new("ARTIFACT_ESCAPE", "output path escapes the evidence directory")
      end
      if File.symlink?(candidate)
        raise OrchestrationError.new("UNSAFE_PATH", "output path must not be a symbolic link: #{candidate}")
      end
      parent
    end

    def prepare_output_path!(path, evidence_root)
      verified_write_parent!(path, evidence_root)
      return path unless File.exist?(path)
      status = File.lstat(path)
      unless status.file? && !status.symlink?
        raise OrchestrationError.new("UNSAFE_PATH", "output path must be a regular non-symbolic-link file: #{path}")
      end
      path
    end

    def open_output_file(path, evidence_root, flags:)
      prepare_output_path!(path, evidence_root)
      File.open(path, flags | File::NOFOLLOW, 0o600)
    rescue Errno::ELOOP
      raise OrchestrationError.new("UNSAFE_PATH", "output path must not be a symbolic link: #{path}")
    end

    def verified_artifact_path(artifact, evidence_root, label, allow_missing: false)
      unless artifact.is_a?(String) && !artifact.empty?
        raise OrchestrationError.new("ARTIFACT_PATH_INVALID", "#{label} artifact path is missing")
      end
      pathname = Pathname.new(artifact)
      if pathname.absolute? || pathname.each_filename.include?("..")
        raise OrchestrationError.new("ARTIFACT_ESCAPE", "#{label} artifact path escapes the evidence directory")
      end
      candidate = File.expand_path(artifact, evidence_root)
      prefix = evidence_root + File::SEPARATOR
      unless candidate.start_with?(prefix)
        raise OrchestrationError.new("ARTIFACT_ESCAPE", "#{label} artifact path escapes the evidence directory")
      end
      ensure_directory_within!(File.dirname(candidate), evidence_root, create: false)
      if File.symlink?(candidate)
        raise OrchestrationError.new("UNSAFE_PATH", "#{label} artifact must not be a symbolic link")
      end
      if File.exist?(candidate)
        resolved = File.realpath(candidate)
        unless resolved.start_with?(prefix)
          raise OrchestrationError.new("ARTIFACT_ESCAPE", "#{label} artifact escapes the evidence directory")
        end
        return resolved
      end
      unless allow_missing
        raise OrchestrationError.new("MISSING_FILE", "#{label} artifact is missing: #{artifact}", exit_code: 66)
      end
      candidate
    end

    def relative_artifact(path, evidence_root)
      expanded = File.expand_path(path)
      prefix = evidence_root + File::SEPARATOR
      unless expanded.start_with?(prefix)
        raise OrchestrationError.new("ARTIFACT_ESCAPE", "artifact escapes the evidence directory")
      end
      expanded.delete_prefix(prefix)
    end

    def parse_json(path, label)
      document = JSON.parse(File.read(path))
      raise OrchestrationError.new("INVALID_JSON", "#{label} must be a JSON object") unless document.is_a?(Hash)
      document
    rescue JSON::ParserError => error
      raise OrchestrationError.new("INVALID_JSON", "#{label} is invalid JSON: #{error.message}")
    end

    def parse_json_if_complete(path)
      return nil unless File.file?(path)
      document = JSON.parse(File.read(path))
      document if document.is_a?(Hash)
    rescue JSON::ParserError, Errno::ENOENT
      nil
    end

    def write_json_atomic(path, value, containment_root: nil)
      if containment_root
        verified_write_parent!(path, containment_root)
      else
        parent = File.dirname(path)
        raise OrchestrationError.new("MISSING_DIRECTORY", "JSON output parent is missing: #{parent}") unless File.directory?(parent)
        raise OrchestrationError.new("UNSAFE_PATH", "JSON output must not be a symbolic link: #{path}") if File.symlink?(path)
      end
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
        file.write(JSON.pretty_generate(value, allow_nan: false))
        file.write("\n")
        file.flush
        file.fsync
      end
      verified_write_parent!(path, containment_root) if containment_root
      File.rename(temporary, path)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary) && temporary
    end

    def failure_document(mode, code, message)
      {
        "schemaVersion" => SESSION_SCHEMA_VERSION,
        "mode" => mode,
        "status" => "failed",
        "failureCode" => code,
        "error" => message
      }
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  mode = ARGV.shift.to_s
  outcome = ViftyUIReview::Orchestrator.run(mode, ARGV)
  STDOUT.write(JSON.generate(outcome.document))
  STDOUT.write("\n")
  exit outcome.exit_code
end
