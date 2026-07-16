# frozen_string_literal: true

require "json"
require_relative "ui_review_contract"

module ViftyUIReview
  module BuildProvenance
    SCHEMA_ID = "https://vifty.app/schemas/ui-review-build-provenance-v1.schema.json"
    SECTION_SEGMENT = "__TEXT"
    SECTION_NAME = "__vifty_src"
    MAX_SECTION_BYTES = 4 * 1_024
    MAX_ARCHITECTURES = 32
    MAX_LOAD_COMMANDS = 4_096
    SOURCE_OBJECT_PATTERN = /\A[a-f0-9]{40}\z/
    TRANSACTION_PATTERN = /\A[a-f0-9]{64}\z/
    DOCUMENT_KEYS = %w[
      schemaVersion
      schemaID
      sourceCommit
      sourceTree
      productRole
      configuration
      buildTransactionID
    ].freeze
    ROLE_CONFIGURATIONS = {
      "debug-fixture-app" => "debug",
      "release-exclusion" => "release",
      "ax-collector" => "debug"
    }.freeze

    THIN_MAGICS = {
      "\xCE\xFA\xED\xFE".b => [:little, 32],
      "\xCF\xFA\xED\xFE".b => [:little, 64],
      "\xFE\xED\xFA\xCE".b => [:big, 32],
      "\xFE\xED\xFA\xCF".b => [:big, 64]
    }.freeze
    FAT_MAGICS = {
      "\xCA\xFE\xBA\xBE".b => [:big, 32],
      "\xCA\xFE\xBA\xBF".b => [:big, 64],
      "\xBE\xBA\xFE\xCA".b => [:little, 32],
      "\xBF\xBA\xFE\xCA".b => [:little, 64]
    }.freeze

    class ProvenanceError < StandardError; end

    module_function

    def extract!(data, label: "Mach-O product")
      unless data.is_a?(String) && data.bytesize >= 4
        raise ProvenanceError, "#{label} is not a bounded Mach-O byte string"
      end

      magic = data.byteslice(0, 4)
      documents = if THIN_MAGICS.key?(magic)
                    [extract_thin!(data, label: label)]
                  elsif FAT_MAGICS.key?(magic)
                    extract_fat!(data, label: label)
                  else
                    raise ProvenanceError, "#{label} is not a supported Mach-O binary"
                  end
      canonical = documents.map { |document| ViftyUIReview.canonical_json(document) }
      unless canonical.uniq.length == 1
        raise ProvenanceError, "#{label} architectures do not carry identical embedded provenance"
      end
      documents.first
    end

    def extract_product_set!(products, expected_commit: nil, expected_tree: nil)
      unless products.is_a?(Hash) && products.keys.sort == ROLE_CONFIGURATIONS.keys.sort
        raise ProvenanceError, "product set must contain exactly the three canonical product roles"
      end
      validate_expected_source!(expected_commit, "expected source commit") if expected_commit
      validate_expected_source!(expected_tree, "expected source tree") if expected_tree

      extracted = products.to_h do |expected_role, product|
        unless product.is_a?(Hash) && product[:data].is_a?(String)
          raise ProvenanceError, "#{expected_role} product bytes are missing"
        end
        document = extract!(product.fetch(:data), label: product[:label] || expected_role)
        unless document.fetch("productRole") == expected_role
          raise ProvenanceError,
                "#{expected_role} product role mismatch: #{document.fetch("productRole").inspect}"
        end
        expected_configuration = ROLE_CONFIGURATIONS.fetch(expected_role)
        unless document.fetch("configuration") == expected_configuration
          raise ProvenanceError,
                "#{expected_role} configuration mismatch: #{document.fetch("configuration").inspect}"
        end
        [expected_role, document]
      end

      commits = extracted.values.map { |document| document.fetch("sourceCommit") }.uniq
      trees = extracted.values.map { |document| document.fetch("sourceTree") }.uniq
      transactions = extracted.values.map { |document| document.fetch("buildTransactionID") }.uniq
      raise ProvenanceError, "products do not share one source commit" unless commits.length == 1
      raise ProvenanceError, "products do not share one source tree" unless trees.length == 1
      raise ProvenanceError, "products do not share one build transaction" unless transactions.length == 1
      if expected_commit && commits.first != expected_commit
        raise ProvenanceError,
              "embedded source commit #{commits.first} does not match expected source commit #{expected_commit}"
      end
      if expected_tree && trees.first != expected_tree
        raise ProvenanceError,
              "embedded source tree #{trees.first} does not match expected source tree #{expected_tree}"
      end

      {
        "sourceCommit" => commits.first,
        "sourceTree" => trees.first,
        "buildTransactionID" => transactions.first,
        "products" => extracted
      }
    end

    def canonical_sha256(document)
      ViftyUIReview.sha256_json(document)
    end

    def extract_fat!(data, label:)
      endian, width = FAT_MAGICS.fetch(data.byteslice(0, 4))
      architecture_count = integer_at!(data, 4, 4, endian, "#{label} fat architecture count")
      unless architecture_count.between?(1, MAX_ARCHITECTURES)
        raise ProvenanceError, "#{label} has an invalid fat architecture count"
      end
      entry_size = width == 64 ? 32 : 20
      table_end = 8 + (architecture_count * entry_size)
      raise ProvenanceError, "#{label} has a truncated fat architecture table" if table_end > data.bytesize

      ranges = architecture_count.times.map do |index|
        entry = 8 + (index * entry_size)
        offset = integer_at!(data, entry + 8, width == 64 ? 8 : 4, endian, "#{label} architecture offset")
        size = integer_at!(data, entry + (width == 64 ? 16 : 12), width == 64 ? 8 : 4, endian, "#{label} architecture size")
        unless size.positive? && offset >= table_end && offset <= data.bytesize - size
          raise ProvenanceError, "#{label} architecture #{index} has an invalid byte range"
        end
        (offset...(offset + size))
      end
      sorted = ranges.sort_by(&:begin)
      sorted.each_cons(2) do |left, right|
        if left.end > right.begin
          raise ProvenanceError, "#{label} fat architecture byte ranges overlap"
        end
      end
      ranges.each_with_index.map do |range, index|
        slice = data.byteslice(range.begin, range.size)
        unless THIN_MAGICS.key?(slice.byteslice(0, 4))
          raise ProvenanceError, "#{label} architecture #{index} is not a supported thin Mach-O"
        end
        extract_thin!(slice, label: "#{label} architecture #{index}")
      end
    end

    def extract_thin!(data, label:)
      endian, width = THIN_MAGICS.fetch(data.byteslice(0, 4))
      header_size = width == 64 ? 32 : 28
      raise ProvenanceError, "#{label} has a truncated Mach-O header" if data.bytesize < header_size

      command_count = integer_at!(data, 16, 4, endian, "#{label} load command count")
      command_bytes = integer_at!(data, 20, 4, endian, "#{label} load command size")
      unless command_count.between?(1, MAX_LOAD_COMMANDS)
        raise ProvenanceError, "#{label} has an invalid load command count"
      end
      command_end = header_size + command_bytes
      raise ProvenanceError, "#{label} has truncated load commands" if command_end > data.bytesize

      sections = []
      cursor = header_size
      command_count.times do |command_index|
        if cursor + 8 > command_end
          raise ProvenanceError, "#{label} load command #{command_index} is truncated"
        end
        command = integer_at!(data, cursor, 4, endian, "#{label} load command")
        command_size = integer_at!(data, cursor + 4, 4, endian, "#{label} load command size")
        unless command_size >= 8 && cursor <= command_end - command_size
          raise ProvenanceError, "#{label} load command #{command_index} has an invalid size"
        end
        expected_segment_command = width == 64 ? 0x19 : 0x1
        if command == expected_segment_command
          sections.concat(
            provenance_sections!(
              data,
              cursor: cursor,
              command_size: command_size,
              width: width,
              endian: endian,
              label: label
            )
          )
        end
        cursor += command_size
      end
      unless cursor == command_end
        raise ProvenanceError, "#{label} load command byte count is inconsistent"
      end
      unless sections.length == 1
        raise ProvenanceError,
              "#{label} must contain exactly one #{SECTION_SEGMENT},#{SECTION_NAME} section (found #{sections.length})"
      end

      offset, size = sections.first
      unless size.between?(1, MAX_SECTION_BYTES) && offset <= data.bytesize - size
        raise ProvenanceError, "#{label} embedded provenance section has an invalid byte range"
      end
      validate_document_bytes!(data.byteslice(offset, size), label: label)
    end

    def provenance_sections!(data, cursor:, command_size:, width:, endian:, label:)
      segment_size = width == 64 ? 72 : 56
      section_size = width == 64 ? 80 : 68
      if command_size < segment_size || cursor + segment_size > data.bytesize
        raise ProvenanceError, "#{label} has a truncated segment command"
      end
      segment_name = fixed_name_at(data, cursor + 8)
      section_count_offset = cursor + (width == 64 ? 64 : 48)
      section_count = integer_at!(data, section_count_offset, 4, endian, "#{label} section count")
      expected_size = segment_size + (section_count * section_size)
      unless expected_size == command_size
        raise ProvenanceError, "#{label} segment command section count is inconsistent"
      end
      return [] unless segment_name == SECTION_SEGMENT

      section_count.times.map do |index|
        section = cursor + segment_size + (index * section_size)
        section_name = fixed_name_at(data, section)
        section_segment = fixed_name_at(data, section + 16)
        next unless section_name == SECTION_NAME && section_segment == SECTION_SEGMENT

        size_offset = section + (width == 64 ? 40 : 36)
        file_offset = section + (width == 64 ? 48 : 40)
        size = integer_at!(data, size_offset, width == 64 ? 8 : 4, endian, "#{label} section size")
        offset = integer_at!(data, file_offset, 4, endian, "#{label} section offset")
        [offset, size]
      end.compact
    end

    def validate_document_bytes!(bytes, label:)
      begin
        document = JSON.parse(bytes)
      rescue JSON::ParserError, EncodingError => error
        raise ProvenanceError, "#{label} embedded provenance is invalid JSON: #{error.message}"
      end
      unless document.is_a?(Hash) && document.keys.sort == DOCUMENT_KEYS.sort
        raise ProvenanceError, "#{label} embedded provenance keys do not match the exact contract"
      end
      unless bytes == ViftyUIReview.canonical_json(document).b
        raise ProvenanceError, "#{label} embedded provenance is not exact canonical JSON"
      end
      unless document["schemaVersion"] == 1 && document["schemaID"] == SCHEMA_ID
        raise ProvenanceError, "#{label} embedded provenance schema identity is invalid"
      end
      validate_expected_source!(document["sourceCommit"], "#{label} source commit")
      validate_expected_source!(document["sourceTree"], "#{label} source tree")
      unless TRANSACTION_PATTERN.match?(document["buildTransactionID"].to_s)
        raise ProvenanceError, "#{label} build transaction ID is invalid"
      end
      role = document["productRole"]
      configuration = document["configuration"]
      unless ROLE_CONFIGURATIONS.key?(role) && ROLE_CONFIGURATIONS.fetch(role) == configuration
        raise ProvenanceError, "#{label} product role/configuration is invalid"
      end
      document
    end

    def validate_expected_source!(value, label)
      return if value.is_a?(String) && SOURCE_OBJECT_PATTERN.match?(value)

      raise ProvenanceError, "#{label} must be a full lowercase 40-character Git object ID"
    end

    def fixed_name_at(data, offset)
      bytes = data.byteslice(offset, 16)
      raise ProvenanceError, "Mach-O fixed-width name is truncated" unless bytes&.bytesize == 16

      bytes.split("\0", 2).first.force_encoding(Encoding::BINARY)
    end

    def integer_at!(data, offset, width, endian, label)
      bytes = data.byteslice(offset, width)
      raise ProvenanceError, "#{label} is truncated" unless bytes&.bytesize == width

      directive = case [width, endian]
                  when [4, :little] then "V"
                  when [4, :big] then "N"
                  when [8, :little] then "Q<"
                  when [8, :big] then "Q>"
                  else raise ProvenanceError, "unsupported Mach-O integer encoding"
                  end
      bytes.unpack1(directive)
    end
  end
end
