# frozen_string_literal: true

require "json"
require "minitest/autorun"
require_relative "../../scripts/lib/ui_review_contract"
require_relative "../../scripts/lib/ui_review_build_provenance"

class UIReviewBuildProvenanceTests < Minitest::Test
  COMMIT_A = "a" * 40
  COMMIT_B = "b" * 40
  TREE_A = "c" * 40
  TREE_B = "d" * 40
  TRANSACTION_A = "1" * 64
  TRANSACTION_B = "2" * 64

  def test_exact_three_product_transaction_passes
    result = ViftyUIReview::BuildProvenance.extract_product_set!(
      products(commit: COMMIT_A, tree: TREE_A, transaction: TRANSACTION_A),
      expected_commit: COMMIT_A,
      expected_tree: TREE_A
    )

    assert_equal TRANSACTION_A, result.fetch("buildTransactionID")
    assert_equal ViftyUIReview::BuildProvenance::ROLE_CONFIGURATIONS.keys.sort,
                 result.fetch("products").keys.sort
  end

  def test_clean_commit_b_rejects_products_built_from_commit_a
    error = assert_raises(ViftyUIReview::BuildProvenance::ProvenanceError) do
      ViftyUIReview::BuildProvenance.extract_product_set!(
        products(commit: COMMIT_A, tree: TREE_A, transaction: TRANSACTION_A),
        expected_commit: COMMIT_B,
        expected_tree: TREE_B
      )
    end

    assert_match(/source commit/, error.message)
  end

  def test_mixed_source_commits_and_transactions_fail_closed
    mixed_commit = products(commit: COMMIT_A, tree: TREE_A, transaction: TRANSACTION_A)
    mixed_commit.fetch("release-exclusion")[:data] = macho(
      document("release-exclusion", COMMIT_B, TREE_A, TRANSACTION_A)
    )
    assert_raises(ViftyUIReview::BuildProvenance::ProvenanceError) do
      ViftyUIReview::BuildProvenance.extract_product_set!(
        mixed_commit,
        expected_commit: COMMIT_A,
        expected_tree: TREE_A
      )
    end

    mixed_transaction = products(commit: COMMIT_A, tree: TREE_A, transaction: TRANSACTION_A)
    mixed_transaction.fetch("ax-collector")[:data] = macho(
      document("ax-collector", COMMIT_A, TREE_A, TRANSACTION_B)
    )
    error = assert_raises(ViftyUIReview::BuildProvenance::ProvenanceError) do
      ViftyUIReview::BuildProvenance.extract_product_set!(
        mixed_transaction,
        expected_commit: COMMIT_A,
        expected_tree: TREE_A
      )
    end
    assert_match(/one build transaction/, error.message)
  end

  def test_missing_duplicate_malformed_and_role_mismatch_sections_fail_closed
    assert_raises(ViftyUIReview::BuildProvenance::ProvenanceError) do
      ViftyUIReview::BuildProvenance.extract!(macho(nil), label: "missing")
    end
    assert_raises(ViftyUIReview::BuildProvenance::ProvenanceError) do
      ViftyUIReview::BuildProvenance.extract!(
        macho(document("debug-fixture-app"), duplicate: true),
        label: "duplicate"
      )
    end
    assert_raises(ViftyUIReview::BuildProvenance::ProvenanceError) do
      ViftyUIReview::BuildProvenance.extract!(macho_bytes("{not-json"), label: "malformed")
    end

    mismatched = products(commit: COMMIT_A, tree: TREE_A, transaction: TRANSACTION_A)
    mismatched.fetch("debug-fixture-app")[:data] = macho(
      document("release-exclusion", COMMIT_A, TREE_A, TRANSACTION_A)
    )
    assert_raises(ViftyUIReview::BuildProvenance::ProvenanceError) do
      ViftyUIReview::BuildProvenance.extract_product_set!(
        mismatched,
        expected_commit: COMMIT_A,
        expected_tree: TREE_A
      )
    end
  end

  def test_noncanonical_payload_and_mutable_sidecar_are_not_accepted
    payload = JSON.pretty_generate(document("debug-fixture-app"))
    assert_raises(ViftyUIReview::BuildProvenance::ProvenanceError) do
      ViftyUIReview::BuildProvenance.extract!(macho_bytes(payload), label: "pretty payload")
    end

    binary = macho(document("debug-fixture-app", COMMIT_A, TREE_A, TRANSACTION_A))
    forged_sidecar = document("debug-fixture-app", COMMIT_B, TREE_B, TRANSACTION_B)
    extracted = ViftyUIReview::BuildProvenance.extract!(binary, label: "embedded")
    refute_equal forged_sidecar, extracted
    assert_equal COMMIT_A, extracted.fetch("sourceCommit")
  end

  private

  def products(commit:, tree:, transaction:)
    ViftyUIReview::BuildProvenance::ROLE_CONFIGURATIONS.to_h do |role, configuration|
      [
        role,
        {
          data: macho(document(role, commit, tree, transaction, configuration)),
          label: role
        }
      ]
    end
  end

  def document(
    role,
    commit = COMMIT_A,
    tree = TREE_A,
    transaction = TRANSACTION_A,
    configuration = nil
  )
    {
      "schemaVersion" => 1,
      "schemaID" => ViftyUIReview::BuildProvenance::SCHEMA_ID,
      "sourceCommit" => commit,
      "sourceTree" => tree,
      "productRole" => role,
      "configuration" => configuration ||
        ViftyUIReview::BuildProvenance::ROLE_CONFIGURATIONS.fetch(role),
      "buildTransactionID" => transaction
    }
  end

  def macho(document, duplicate: false)
    payloads = document ? [ViftyUIReview.canonical_json(document)] : []
    payloads << payloads.first if duplicate
    thin_macho(payloads)
  end

  def macho_bytes(payload)
    thin_macho([payload])
  end

  def thin_macho(payloads)
    header_size = 32
    command_size = 72 + (80 * payloads.length)
    data_offset = header_size + command_size
    header = [
      0xfeedfacf,
      0x0100000c,
      0,
      2,
      1,
      command_size,
      0,
      0
    ].pack("V8")
    segment = [0x19, command_size].pack("V2") + fixed_name("__TEXT") +
      [0, 0, data_offset, payloads.sum(&:bytesize)].pack("Q<4") +
      [7, 5, payloads.length, 0].pack("V4")
    offset = data_offset
    sections = payloads.map do |payload|
      section = fixed_name("__vifty_src") + fixed_name("__TEXT") +
        [0, payload.bytesize].pack("Q<2") + [offset, 0, 0, 0, 0, 0, 0, 0].pack("V8")
      offset += payload.bytesize
      section
    end.join
    header + segment + sections + payloads.join
  end

  def fixed_name(value)
    value.b.ljust(16, "\0")
  end
end
