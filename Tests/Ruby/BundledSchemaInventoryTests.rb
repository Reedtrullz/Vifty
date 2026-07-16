# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../../scripts/lib/bundled_schema_inventory"

class BundledSchemaInventoryTests < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  INVENTORY = File.join(ROOT, "scripts/bundled-schema-inventory.txt")
  SOURCE = File.join(ROOT, "docs/schemas")
  EXCLUDED_AX_SCHEMAS = %w[
    ui-review-ax-collector-error-v1.schema.json
    ui-review-ax-raw-capture-v1.schema.json
    ui-review-ax-sealed-report-v1.schema.json
  ].freeze

  def test_actual_make_packaging_uses_exact_25_schema_inventory_and_excludes_ax_only_contracts
    inventory = ViftyBundledSchemaInventory.load!(INVENTORY)
    all_schemas = Dir.children(SOURCE).grep(/\.schema\.json\z/).sort

    assert_equal 28, all_schemas.length
    assert_equal 25, inventory.length
    assert_equal EXCLUDED_AX_SCHEMAS, all_schemas - inventory

    Dir.mktmpdir("vifty-bundled-schemas-") do |root|
      destination = File.join(root, "schemas")
      _stdout, stderr, status = Open3.capture3(
        "/usr/bin/make",
        "-s",
        "package-bundled-schemas",
        "SCHEMAS=#{destination}",
        chdir: ROOT
      )

      assert status.success?, stderr
      assert_equal inventory, Dir.children(destination).sort
      inventory.each do |name|
        assert_equal File.binread(File.join(SOURCE, name)),
                     File.binread(File.join(destination, name)),
                     "packaged #{name} must byte-match its reviewed source"
      end
      EXCLUDED_AX_SCHEMAS.each do |name|
        refute File.exist?(File.join(destination, name)), "#{name} is AX-only"
      end
    end
  end

  def test_makefile_and_release_verifier_reference_the_same_explicit_inventory
    makefile = File.read(File.join(ROOT, "Makefile"))
    verifier = File.read(File.join(ROOT, "scripts/verify-release-artifact.sh"))

    assert_includes makefile, "BUNDLED_SCHEMA_INVENTORY ?= scripts/bundled-schema-inventory.txt"
    assert_includes makefile, "$(MAKE) package-bundled-schemas"
    refute_includes makefile, 'cp docs/schemas/*.schema.json "$(SCHEMAS)/"'
    assert_includes verifier, "scripts/bundled-schema-inventory.txt"
    assert_includes verifier, "File.binread(path) == File.binread(reviewed_path)"
  end
end
