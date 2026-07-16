#!/bin/bash

ui_review_rollback_product_publication() {
  (( publication_committed == 0 )) || return 0

  # The previous directory is itself the durable publication journal. This
  # state check closes the signal window between the atomic rename and the
  # following shell assignment.
  if (( publication_restore_in_progress == 1 )) &&
     [[ ! -e "$previous" && ! -L "$previous" ]]; then
    if [[ -d "$output_root" && ! -L "$output_root" ]]; then
      publication_started=0
      publication_restore_in_progress=0
      publication_rollback_failed=0
      return 0
    fi
    publication_rollback_failed=1
    echo "UI review product rollback cannot locate either restored output or recovery material" >&2
    return 75
  fi

  if [[ -d "$previous" && ! -L "$previous" ]]; then
    if declare -F ui_review_publication_checkpoint >/dev/null; then
      ui_review_publication_checkpoint before-rollback-output-removal
    fi
    if [[ -e "$output_root" || -L "$output_root" ]]; then
      if ! /bin/rm -rf "$output_root"; then
        publication_rollback_failed=1
        echo "UI review product rollback failed; previous products remain at $previous" >&2
        return 75
      fi
    fi
    publication_restore_in_progress=1
    if declare -F ui_review_publication_checkpoint >/dev/null; then
      ui_review_publication_checkpoint before-previous-output-restore
    fi
    if ! /bin/mv "$previous" "$output_root"; then
      publication_rollback_failed=1
      echo "UI review product rollback failed; previous products remain at $previous" >&2
      return 75
    fi
    if declare -F ui_review_publication_checkpoint >/dev/null; then
      ui_review_publication_checkpoint after-previous-output-restore
    fi
    if [[ ! -d "$output_root" || -L "$output_root" || -e "$previous" || -L "$previous" ]]; then
      publication_rollback_failed=1
      echo "UI review product rollback could not verify the restored previous output" >&2
      return 75
    fi
    publication_started=0
    publication_restore_in_progress=0
    publication_rollback_failed=0
    return 0
  fi

  if (( publication_started == 1 )); then
    if [[ -e "$output_root" || -L "$output_root" ]]; then
      if ! /bin/rm -rf "$output_root"; then
        publication_rollback_failed=1
        echo "UI review product rollback could not remove the unverified new output" >&2
        return 75
      fi
    fi
    publication_started=0
  fi
  return 0
}

ui_review_cleanup_product_transaction_scratch() {
  local scratch_root="$1"
  if (( publication_rollback_failed == 1 )); then
    echo "UI review product recovery material is preserved at $scratch_root" >&2
    return 75
  fi
  if [[ -d "$scratch_root" && ! -L "$scratch_root" ]]; then
    /bin/rm -rf "$scratch_root" || return 75
  fi
}

ui_review_publish_products() {
  local products_stage="$1"
  local verifier_function="$2"
  local verifier_phase="$3"
  local previous_output_present=0

  if [[ -e "$output_root" || -L "$output_root" ]]; then
    [[ -d "$output_root" && ! -L "$output_root" ]] || {
      echo "UI review product build blocked: canonical product output is not a regular directory" >&2
      return 65
    }
    previous_output_present=1
  fi

  if (( previous_output_present == 1 )); then
    /bin/mv "$output_root" "$previous" || return 65
    if declare -F ui_review_publication_checkpoint >/dev/null; then
      ui_review_publication_checkpoint after-previous-output-move
    fi
    had_previous_output=1
  fi
  publication_started=1
  /bin/mv "$products_stage" "$output_root" || {
    local rollback_status=0
    ui_review_rollback_product_publication || rollback_status=$?
    (( rollback_status == 0 )) || return "$rollback_status"
    return 65
  }
  local verifier_status=0
  if "$verifier_function" "$verifier_phase"; then
    :
  else
    verifier_status=$?
    local rollback_status=0
    ui_review_rollback_product_publication || rollback_status=$?
    (( rollback_status == 0 )) || return "$rollback_status"
    return "$verifier_status"
  fi
  publication_committed=1
}
