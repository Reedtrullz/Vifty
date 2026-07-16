# frozen_string_literal: true

require "fileutils"

module ViftyBundledSchemaInventory
  class InventoryError < StandardError; end

  SCHEMA_NAME = /\A[A-Za-z0-9][A-Za-z0-9._-]*\.schema\.json\z/

  module_function

  def load!(path)
    status = File.lstat(path)
    unless status.file? && !status.symlink?
      raise InventoryError, "bundled schema inventory must be a regular non-symlink file"
    end

    names = File.binread(path).lines(chomp: true)
    raise InventoryError, "bundled schema inventory must not be empty" if names.empty?
    if names.any?(&:empty?)
      raise InventoryError, "bundled schema inventory must not contain blank lines"
    end
    invalid = names.reject { |name| name.match?(SCHEMA_NAME) }
    unless invalid.empty?
      raise InventoryError, "invalid bundled schema inventory entry: #{invalid.first.inspect}"
    end
    unless names.uniq.length == names.length
      raise InventoryError, "bundled schema inventory entries must be unique"
    end
    unless names == names.sort
      raise InventoryError, "bundled schema inventory entries must be byte-sorted"
    end

    names.freeze
  rescue SystemCallError => error
    raise InventoryError, "could not read bundled schema inventory safely: #{error.message}"
  end

  def package!(inventory_path:, source_directory:, destination_directory:)
    names = load!(inventory_path)
    source_status = File.lstat(source_directory)
    unless source_status.directory? && !source_status.symlink?
      raise InventoryError, "schema source must be a real directory"
    end

    if File.exist?(destination_directory) || File.symlink?(destination_directory)
      destination_status = File.lstat(destination_directory)
      unless destination_status.directory? && !destination_status.symlink?
        raise InventoryError, "schema destination must be a real directory"
      end
    else
      FileUtils.mkdir_p(destination_directory, mode: 0o755)
    end

    names.each do |name|
      source = File.join(source_directory, name)
      source_file_status = File.lstat(source)
      unless source_file_status.file? && !source_file_status.symlink?
        raise InventoryError, "reviewed schema must be a regular non-symlink file: #{source}"
      end

      destination = File.join(destination_directory, name)
      FileUtils.copy_file(source, destination)
      File.chmod(0o644, destination)
      unless File.binread(source) == File.binread(destination)
        raise InventoryError, "packaged schema does not byte-match reviewed source: #{name}"
      end
    rescue SystemCallError => error
      raise InventoryError, "could not package reviewed schema #{name}: #{error.message}"
    end

    names
  rescue SystemCallError => error
    raise InventoryError, "could not prepare bundled schema destination safely: #{error.message}"
  end
end
