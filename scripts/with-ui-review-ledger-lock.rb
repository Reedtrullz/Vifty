#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "lib/ui_review_local_ledger"

separator = ARGV.index("--")
unless separator
  warn "Usage: scripts/with-ui-review-ledger-lock.rb --repository-root PATH -- command [args...]"
  exit 64
end
option_arguments = ARGV.take(separator)
command = ARGV.drop(separator + 1)
repository_root = nil
timeout_seconds = ViftyUIReview::LocalLedger::LOCK_TIMEOUT_SECONDS
parser = OptionParser.new do |value|
  value.on("--repository-root PATH") { |path| repository_root = path }
  value.on("--timeout-seconds SECONDS", Float) { |seconds| timeout_seconds = seconds }
end

lock = nil
child = nil
forwarded_signals = %w[HUP INT QUIT TERM].freeze
signal_priority = { "INT" => 1, "QUIT" => 2, "HUP" => 3, "TERM" => 4 }.freeze
signal_channels = {}
gate_reader = nil
gate_writer = nil
process_group_alive = lambda do |group_id|
  Process.kill(0, -group_id)
  true
rescue Errno::ESRCH
  false
end
signal_process_group = lambda do |signal, group_id|
  Process.kill(signal, -group_id)
  true
rescue Errno::ESRCH
  false
end
begin
  parser.parse!(option_arguments)
  raise OptionParser::MissingArgument, "--repository-root" unless repository_root
  raise OptionParser::MissingArgument, "command" if command.empty?
  root = ViftyUIReview::LocalLedger.verified_repository_root(repository_root)
  ViftyUIReview::LocalLedger.verify_local_paths_are_ignored!(root)
  lock = ViftyUIReview::LocalLedger.acquire_repository_lock!(
    root,
    timeout_seconds: timeout_seconds
  )
  forwarded_signals.each do |signal|
    reader, writer = IO.pipe
    reader.close_on_exec = true
    writer.close_on_exec = true
    signal_channels[signal] = [reader, writer]
    Signal.trap(signal) do
      begin
        writer.write_nonblock(".", exception: false)
      rescue IOError, Errno::EPIPE
        nil
      end
    end
  end
  gate_reader, gate_writer = IO.pipe
  gate_reader.close_on_exec = true
  gate_writer.close_on_exec = true
  gate_program = <<~'RUBY'
    descriptor = Integer(ENV.delete("VIFTY_UI_REVIEW_GATE_FD"), 10)
    gate = IO.for_fd(descriptor)
    ready = gate.read(1)
    gate.close
    exit 70 unless ready == "."
    exec(*ARGV)
  RUBY
  child = Process.spawn(
    {
      "VIFTY_UI_REVIEW_LOCK_HELD" => "1",
      "VIFTY_UI_REVIEW_GATE_FD" => gate_reader.fileno.to_s
    },
    "/usr/bin/ruby", "-e", gate_program, *command,
    gate_reader.fileno => gate_reader.fileno,
    lock.fileno => lock.fileno,
    pgroup: true
  )
  gate_reader.close
  gate_reader = nil
  status = nil
  direct_child_reaped = false
  direct_shutdown_signal = nil
  direct_shutdown_started_at = nil
  last_direct_forwarded_at = nil
  direct_kill_sent = false
  direct_kill_started_at = nil
  residual_shutdown_started_at = nil
  residual_term_sent = false
  residual_kill_sent = false
  readers_to_signals = signal_channels.to_h { |signal, (reader, _writer)| [reader, signal] }
  gate_writer.write(".")
  gate_writer.close
  gate_writer = nil
  loop do
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    while (ready = IO.select(readers_to_signals.keys, nil, nil, 0))
      ready.first.each do |reader|
        bytes = reader.read_nonblock(1_024, exception: false)
        next if bytes == :wait_readable || bytes.nil? || bytes.empty?

        signal = readers_to_signals.fetch(reader)
        signal_process_group.call(signal, child)
        if direct_shutdown_signal.nil? ||
           signal_priority.fetch(signal) >= signal_priority.fetch(direct_shutdown_signal)
          direct_shutdown_signal = signal
        end
        direct_shutdown_started_at ||= now
        last_direct_forwarded_at = now
      end
    end

    unless direct_child_reaped
      waited, status = Process.wait2(child, Process::WNOHANG)
      direct_child_reaped = !waited.nil?
    end
    group_alive = process_group_alive.call(child)
    break if direct_child_reaped && !group_alive

    if !direct_child_reaped && direct_shutdown_started_at
      if now - direct_shutdown_started_at < 30.0
        if last_direct_forwarded_at.nil? || now - last_direct_forwarded_at >= 0.05
          signal_process_group.call(direct_shutdown_signal, child)
          last_direct_forwarded_at = now
        end
      elsif !direct_kill_sent
        signal_process_group.call("KILL", child)
        direct_kill_sent = true
        direct_kill_started_at = now
      elsif now - direct_kill_started_at >= 1.5
        raise ViftyUIReview::LocalLedger::LedgerError.new(
          "UI review direct child did not terminate after bounded KILL escalation",
          exit_code: 70
        )
      end
    elsif direct_child_reaped && group_alive
      residual_shutdown_started_at ||= now
      unless residual_term_sent
        signal_process_group.call("TERM", child)
        residual_term_sent = true
      end
      if now - residual_shutdown_started_at >= 0.5 && !residual_kill_sent
        signal_process_group.call("KILL", child)
        residual_kill_sent = true
      end
      if now - residual_shutdown_started_at >= 1.5 && process_group_alive.call(child)
        raise ViftyUIReview::LocalLedger::LedgerError.new(
          "UI review residual child process group did not terminate after bounded escalation",
          exit_code: 70
        )
      end
    end
    IO.select(readers_to_signals.keys, nil, nil, 0.01)
  end
  child = nil
  exit(status.exited? ? status.exitstatus : 128 + status.termsig)
rescue OptionParser::ParseError => error
  warn "UI review ledger lock wrapper blocked: #{error.message}"
  exit 64
rescue ViftyUIReview::LocalLedger::LedgerError => error
  warn "UI review ledger lock wrapper blocked: #{error.message}"
  exit error.exit_code
rescue SystemCallError => error
  warn "UI review ledger lock wrapper failed: #{error.message}"
  exit 70
ensure
  gate_reader.close if gate_reader && !gate_reader.closed?
  gate_writer.close if gate_writer && !gate_writer.closed?
  signal_channels.each_value do |reader, writer|
    reader.close unless reader.closed?
    writer.close unless writer.closed?
  end
  lock.close if lock && !lock.closed?
end
