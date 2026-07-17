#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require_relative "lib/ui_review_local_ledger"

repository_root = File.expand_path("..", __dir__)
parser = OptionParser.new do |value|
  value.banner = "Usage: scripts/initialize-ui-review-ledger.rb [--repository-root PATH]"
  value.on("--repository-root PATH") { |path| repository_root = path }
end

begin
  parser.parse!(ARGV)
  raise OptionParser::InvalidOption, ARGV.join(" ") unless ARGV.empty?
  result = ViftyUIReview::LocalLedger.initialize!(repository_root: repository_root)
  puts JSON.generate(result)
rescue OptionParser::ParseError => error
  warn "UI review ledger initialization blocked: #{error.message}"
  exit 64
rescue ViftyUIReview::LocalLedger::LedgerError => error
  warn "UI review ledger initialization blocked: #{error.message}"
  exit error.exit_code
end
