#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require_relative "lib/bundled_schema_inventory"

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: package-bundled-schemas.rb --inventory PATH --source DIRECTORY --destination DIRECTORY"
  parser.on("--inventory PATH") { |value| options[:inventory_path] = value }
  parser.on("--source DIRECTORY") { |value| options[:source_directory] = value }
  parser.on("--destination DIRECTORY") { |value| options[:destination_directory] = value }
end.parse!

missing = %i[inventory_path source_directory destination_directory].reject { |key| options.key?(key) }
abort("error: missing required option(s): #{missing.join(", ")}") unless missing.empty?

begin
  ViftyBundledSchemaInventory.package!(**options)
rescue ViftyBundledSchemaInventory::InventoryError => error
  warn "error: #{error.message}"
  exit 65
end
