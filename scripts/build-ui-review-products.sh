#!/bin/bash

set -euo pipefail

fail() {
  echo "UI review product build blocked: $*" >&2
  exit 65
}

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"
repository_root="$(CDPATH= cd -- "$script_dir/.." && pwd -P)"
if [[ "${VIFTY_UI_REVIEW_LOCK_HELD:-0}" != "1" ]]; then
  exec /usr/bin/ruby \
    "$repository_root/scripts/with-ui-review-ledger-lock.rb" \
    --repository-root "$repository_root" \
    -- "$0" "$@"
fi
. "$repository_root/scripts/lib/ui_review_product_publication.sh"
git_root="$(/usr/bin/git -C "$repository_root" rev-parse --show-toplevel 2>/dev/null)" ||
  fail "repository root is unavailable"
[[ "$git_root" == "$repository_root" ]] || fail "script must run from the exact Git repository root"

output_root="$repository_root/.build/ui-review-products"
build_parent="$repository_root/.build"
[[ ! -L "$build_parent" ]] || fail ".build must not be a symbolic link"
[[ ! -L "$output_root" ]] || fail "canonical product output must not be a symbolic link"
scratch_root=""
previous=""
publication_started=0
publication_committed=0
publication_rollback_failed=0
publication_restore_in_progress=0
had_previous_output=0
cleanup() {
  local status=$?
  trap - EXIT
  trap '' HUP INT QUIT TERM
  local rollback_status=0
  local scratch_status=0
  ui_review_rollback_product_publication || rollback_status=$?
  if (( rollback_status == 0 )) && [[ -n "$scratch_root" ]]; then
    ui_review_cleanup_product_transaction_scratch "$scratch_root" || scratch_status=$?
  fi
  if (( status == 0 )); then
    if (( rollback_status != 0 )); then
      status="$rollback_status"
    elif (( scratch_status != 0 )); then
      status="$scratch_status"
    fi
  fi
  return "$status"
}
handle_signal() {
  local status="$1"
  trap '' HUP INT QUIT TERM
  exit "$status"
}
trap cleanup EXIT
trap 'handle_signal 129' HUP
trap 'handle_signal 130' INT
trap 'handle_signal 131' QUIT
trap 'handle_signal 143' TERM

verify_source_state() {
  local phase="$1"
  local status current_commit current_tree
  status="$(/usr/bin/git -C "$repository_root" status --porcelain=v1 --untracked-files=all)"
  [[ -z "$status" ]] || fail "the repository must remain clean $phase"
  current_commit="$(/usr/bin/git -C "$repository_root" rev-parse HEAD)"
  current_tree="$(/usr/bin/git -C "$repository_root" rev-parse 'HEAD^{tree}')"
  [[ "$current_commit" == "$source_commit" ]] || fail "HEAD changed $phase"
  [[ "$current_tree" == "$source_tree" ]] || fail "the source tree changed $phase"
}

initial_status="$(/usr/bin/git -C "$repository_root" status --porcelain=v1 --untracked-files=all)"
[[ -z "$initial_status" ]] || fail "the repository must be clean before the build transaction"
source_commit="$(/usr/bin/git -C "$repository_root" rev-parse HEAD)"
source_tree="$(/usr/bin/git -C "$repository_root" rev-parse 'HEAD^{tree}')"
[[ "$source_commit" =~ ^[a-f0-9]{40}$ ]] || fail "HEAD is not a full lowercase Git commit ID"
[[ "$source_tree" =~ ^[a-f0-9]{40}$ ]] || fail "HEAD tree is not a full lowercase Git tree ID"

available_kib="$(/bin/df -Pk /System/Volumes/Data | /usr/bin/awk 'NR == 2 { print $4 }')"
[[ "$available_kib" =~ ^[0-9]+$ ]] || fail "free disk space could not be determined"
(( available_kib >= 30 * 1024 * 1024 )) || fail "less than 30 GiB is free on /System/Volumes/Data"

/bin/mkdir -p "$build_parent"
transaction_id="$(/usr/bin/ruby -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
[[ "$transaction_id" =~ ^[a-f0-9]{64}$ ]] || fail "could not create a build transaction ID"
scratch_root="$build_parent/ui-review-transaction-$transaction_id"
[[ ! -e "$scratch_root" && ! -L "$scratch_root" ]] || fail "transaction scratch path already exists"
/bin/mkdir -m 700 "$scratch_root"
previous="$scratch_root/previous-products"

source_archive="$scratch_root/source.tar"
source_root="$scratch_root/source"
/bin/mkdir -m 700 "$source_root"
/usr/bin/git -C "$repository_root" archive --format=tar --output="$source_archive" "$source_commit"
/usr/bin/tar -xf "$source_archive" -C "$source_root"
/usr/bin/ruby \
  -I "$repository_root/scripts/lib" \
  -rui_review_source_archive \
  -e '
    begin
      ViftyUIReview::SourceArchive.validate_extracted_tree!(ARGV.fetch(0))
    rescue ViftyUIReview::SourceArchive::UnsafeEntryError => error
      warn error.message
      exit 65
    end
  ' "$source_root"
/bin/rm -f "$source_archive"
/bin/chmod -R a-w "$source_root"
verify_source_state "after creating the isolated source snapshot"

write_provenance() {
  local role="$1"
  local configuration="$2"
  local destination="$3"
  /usr/bin/ruby \
    -I "$source_root/scripts/lib" \
    -rui_review_build_provenance \
    -e '
      role, configuration, commit, tree, transaction, destination = ARGV
      document = {
        "schemaVersion" => 1,
        "schemaID" => ViftyUIReview::BuildProvenance::SCHEMA_ID,
        "sourceCommit" => commit,
        "sourceTree" => tree,
        "productRole" => role,
        "configuration" => configuration,
        "buildTransactionID" => transaction
      }
      ViftyUIReview::BuildProvenance.validate_document_bytes!(
        ViftyUIReview.canonical_json(document),
        label: role
      )
      File.binwrite(destination, ViftyUIReview.canonical_json(document))
    ' "$role" "$configuration" "$source_commit" "$source_tree" "$transaction_id" "$destination"
}

debug_provenance="$scratch_root/debug-provenance.json"
release_provenance="$scratch_root/release-provenance.json"
collector_provenance="$scratch_root/collector-provenance.json"
write_provenance "debug-fixture-app" "debug" "$debug_provenance"
write_provenance "release-exclusion" "release" "$release_provenance"
write_provenance "ax-collector" "debug" "$collector_provenance"

products_stage="$scratch_root/products"
/bin/mkdir -p "$products_stage/debug" "$products_stage/release"

verify_source_state "before the first build"
/usr/bin/make -C "$source_root" app \
  CONFIGURATION=debug \
  SIGNING_IDENTITY=- \
  VIFTY_RELEASE_MANIFEST_BASE_REF= \
  VIFTY_REQUIRE_RELEASE_MANIFEST_BASE=0 \
  APP_DIR="$products_stage/debug/Vifty.app" \
  SWIFT_BUILD_PATH="$scratch_root/swift-debug-app" \
  SWIFT_BUILD_PROVENANCE_FILE="$debug_provenance"
verify_source_state "after the debug app build"

/usr/bin/make -C "$source_root" app \
  CONFIGURATION=release \
  SIGNING_IDENTITY=- \
  VIFTY_RELEASE_MANIFEST_BASE_REF= \
  VIFTY_REQUIRE_RELEASE_MANIFEST_BASE=0 \
  APP_DIR="$scratch_root/release-app/Vifty.app" \
  SWIFT_BUILD_PATH="$scratch_root/swift-release-app" \
  SWIFT_BUILD_PROVENANCE_FILE="$release_provenance"
/usr/bin/install -m 755 \
  "$scratch_root/release-app/Vifty.app/Contents/MacOS/Vifty" \
  "$products_stage/release/Vifty"
verify_source_state "after the release Vifty build"

/usr/bin/swift build \
  --package-path "$source_root" \
  --build-path "$scratch_root/swift-ax-collector" \
  -c debug \
  --product ViftyAXCollector \
  -Xlinker -sectcreate \
  -Xlinker __TEXT \
  -Xlinker __vifty_src \
  -Xlinker "$collector_provenance"
/usr/bin/install -m 755 \
  "$scratch_root/swift-ax-collector/debug/ViftyAXCollector" \
  "$products_stage/debug/ViftyAXCollector"
verify_source_state "after the AX collector build"

debug_binary="$products_stage/debug/Vifty.app/Contents/MacOS/Vifty"
release_binary="$products_stage/release/Vifty"
collector_binary="$products_stage/debug/ViftyAXCollector"
/usr/bin/ruby \
  -I "$source_root/scripts/lib" \
  -rui_review_build_provenance \
  -e '
    debug_path, release_path, collector_path, commit, tree, transaction = ARGV
    products = {
      "debug-fixture-app" => { data: File.binread(debug_path), label: "debug fixture app" },
      "release-exclusion" => { data: File.binread(release_path), label: "release Vifty" },
      "ax-collector" => { data: File.binread(collector_path), label: "AX collector" }
    }
    result = ViftyUIReview::BuildProvenance.extract_product_set!(
      products,
      expected_commit: commit,
      expected_tree: tree
    )
    unless result.fetch("buildTransactionID") == transaction
      raise ViftyUIReview::BuildProvenance::ProvenanceError,
            "embedded build transaction differs from the active transaction"
    end
  ' "$debug_binary" "$release_binary" "$collector_binary" \
    "$source_commit" "$source_tree" "$transaction_id"
verify_source_state "after product provenance validation"

publication_status=0
if ui_review_publish_products \
  "$products_stage" \
  verify_source_state \
  "after product publication"; then
  :
else
  publication_status=$?
  echo "UI review product build blocked: could not publish a source-stable product transaction" >&2
  exit "$publication_status"
fi

echo "Built provenance-bound UI review products from $source_commit ($source_tree), transaction $transaction_id"
echo "Debug fixture app: $output_root/debug/Vifty.app"
echo "Release Vifty: $output_root/release/Vifty"
echo "AX collector: $output_root/debug/ViftyAXCollector"
