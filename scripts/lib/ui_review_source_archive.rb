# frozen_string_literal: true

require "find"

module ViftyUIReview
  module SourceArchive
    class UnsafeEntryError < StandardError; end

    module_function

    def validate_extracted_tree!(root)
      expanded_root = File.expand_path(root)
      root_status = File.lstat(expanded_root)
      unless root_status.directory? && !root_status.symlink?
        raise UnsafeEntryError, "extracted Git archive root must be a real directory"
      end

      Find.find(expanded_root) do |path|
        next if path == expanded_root

        status = File.lstat(path)
        relative = path.delete_prefix("#{expanded_root}/")
        if status.symlink?
          raise UnsafeEntryError,
                "extracted Git archive contains a symbolic link: #{relative}"
        end
        next if status.directory? || status.file?

        raise UnsafeEntryError,
              "extracted Git archive contains a non-regular entry: #{relative}"
      end

      true
    rescue SystemCallError => error
      raise UnsafeEntryError,
            "could not inspect extracted Git archive safely: #{error.message}"
    end
  end
end
