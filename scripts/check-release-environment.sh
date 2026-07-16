#!/usr/bin/env bash
set -euo pipefail

REPO="Reedtrullz/Vifty"
ENVIRONMENT_NAME="release"
BRANCH_NAME="main"
JSON_FILE=""
BRANCH_PROTECTION_JSON_FILE=""
OUTPUT_PATH=""

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/check-release-environment.sh [options]

Options:
  --repo <owner/repo>       GitHub repository (default: Reedtrullz/Vifty).
  --environment <name>      Environment name (default: release).
  --branch <name>           Required protected dispatch branch (default: main).
  --json-file <path>        Parse an offline/API fixture instead of calling gh.
  --branch-protection-json-file <path>
                            Parse combined branch-summary/full-protection evidence
                            with --json-file.
  --output <path>           Write normalized read-only JSON evidence.

Fails unless the exact environment exists and has at least one directly
verified non-owner User reviewer, self-review prevention enabled, and
administrator bypass disabled. A Team reviewer is retained in the evidence,
but the environment API does not expose team membership and a Team slug alone
is therefore not accepted as proof that another eligible human can approve.
Workflow YAML can declare an environment, but only this settings/API readback
proves its scheduling gate. The required dispatch branch must also enforce the
reviewed CI check, administrator-inclusive pull-request review, stale-review
dismissal, CODEOWNERS review, last-push approval, conversation resolution, and
no force-push, deletion, or review-bypass allowances.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --environment)
      ENVIRONMENT_NAME="${2:-}"
      shift 2
      ;;
    --json-file)
      JSON_FILE="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH_NAME="${2:-}"
      shift 2
      ;;
    --branch-protection-json-file)
      BRANCH_PROTECTION_JSON_FILE="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      exit 64
      ;;
  esac
done

if [[ ! "${REPO}" =~ ^[^/]+/[^/]+$ || -z "${ENVIRONMENT_NAME}" || -z "${BRANCH_NAME}" ]]; then
  echo "error: repository, environment, and branch must be non-empty" >&2
  exit 64
fi

if [[ -n "${JSON_FILE}" ]]; then
  if [[ ! -f "${JSON_FILE}" ]]; then
    echo "error: environment JSON file not found: ${JSON_FILE}" >&2
    exit 66
  fi
  RAW_JSON="$(<"${JSON_FILE}")"
  if [[ -z "${BRANCH_PROTECTION_JSON_FILE}" || ! -f "${BRANCH_PROTECTION_JSON_FILE}" ]]; then
    echo "error: --json-file requires a readable --branch-protection-json-file" >&2
    exit 66
  fi
  BRANCH_PROTECTION_JSON="$(<"${BRANCH_PROTECTION_JSON_FILE}")"
else
  if ! RAW_JSON="$(gh api "repos/${REPO}/environments/${ENVIRONMENT_NAME}" 2>/dev/null)"; then
    echo "error: GitHub environment ${REPO}/${ENVIRONMENT_NAME} is missing or unreadable" >&2
    exit 65
  fi
  if ! BRANCH_SUMMARY_JSON="$(gh api "repos/${REPO}/branches/${BRANCH_NAME}" 2>/dev/null)"; then
    echo "error: required release branch ${REPO}@${BRANCH_NAME} is missing or unreadable" >&2
    exit 65
  fi
  if ! BRANCH_SETTINGS_JSON="$(gh api "repos/${REPO}/branches/${BRANCH_NAME}/protection" 2>/dev/null)"; then
    echo "error: required release branch ${REPO}@${BRANCH_NAME} has no readable strong protection settings" >&2
    exit 65
  fi
  BRANCH_PROTECTION_JSON="$(ruby -rjson -e '
    summary = JSON.parse(ARGV.fetch(0))
    protection = JSON.parse(ARGV.fetch(1))
    puts JSON.generate({
      "name" => summary["name"],
      "protected" => summary["protected"],
      "protection" => protection
    })
  ' "${BRANCH_SUMMARY_JSON}" "${BRANCH_SETTINGS_JSON}")"
fi

if ! NORMALIZED="$(ruby -rjson -e '
  data = JSON.parse(STDIN.read)
  expected_name = ARGV.fetch(0)
  expected_branch = ARGV.fetch(1)
  branch = JSON.parse(ARGV.fetch(2))
  repository_owner = ARGV.fetch(3)
  actual_name = data["name"]
  abort("environment name #{actual_name.inspect} does not match #{expected_name}") unless actual_name == expected_name
  rule = Array(data["protection_rules"]).find { |item| item["type"] == "required_reviewers" }
  abort("required_reviewers protection rule is missing") unless rule
  reviewers = Array(rule["reviewers"]).map do |entry|
    reviewer = entry["reviewer"] || {}
    type = entry["type"]
    identity = type == "User" ? reviewer["login"] : reviewer["slug"]
    {
      "type" => type,
      "identity" => identity,
      "login" => type == "User" ? identity : nil,
      "slug" => type == "Team" ? identity : nil,
      "id" => reviewer["id"]
    }.compact
  end
  abort("required_reviewers rule has no reviewers") if reviewers.empty?
  abort("required_reviewers contains incomplete reviewer evidence") unless reviewers.all? do |reviewer|
    %w[User Team].include?(reviewer["type"]) && reviewer["identity"].is_a?(String) &&
      !reviewer["identity"].empty? && reviewer["id"].is_a?(Integer) && reviewer["id"].positive?
  end
  eligible_non_owner_users = reviewers.select do |reviewer|
    reviewer["type"] == "User" && !reviewer.fetch("login").casecmp?(repository_owner)
  end
  if eligible_non_owner_users.empty?
    abort("required_reviewers has no directly verified non-owner User reviewer; Team membership is not present in this API readback and is not eligibility proof")
  end
  abort("required_reviewers must prevent self review") unless rule["prevent_self_review"] == true
  abort("administrators must not be allowed to bypass environment protection rules") unless data["can_admins_bypass"] == false
  policy = data["deployment_branch_policy"]
  abort("deployment branch policy must require protected branches only") unless
    policy.is_a?(Hash) && policy["protected_branches"] == true && policy["custom_branch_policies"] == false
  abort("required release branch name does not match #{expected_branch}") unless branch.is_a?(Hash) && branch["name"] == expected_branch
  abort("required release branch #{expected_branch} is not protected") unless branch["protected"] == true

  protection = branch["protection"]
  abort("required release branch #{expected_branch} is missing full protection evidence") unless protection.is_a?(Hash)
  status_checks = protection["required_status_checks"]
  abort("required release branch #{expected_branch} must require strict status checks") unless
    status_checks.is_a?(Hash) && status_checks["strict"] == true
  checks = Array(status_checks["checks"])
  trusted_ci_check = checks.find do |check|
    check.is_a?(Hash) && check["context"] == "SwiftPM checks" && check["app_id"] == 15_368
  end
  abort("required release branch #{expected_branch} must require SwiftPM checks from the GitHub Actions app") unless trusted_ci_check

  enforce_admins = protection.dig("enforce_admins", "enabled")
  abort("required release branch #{expected_branch} must enforce protection for administrators") unless enforce_admins == true

  pull_request_reviews = protection["required_pull_request_reviews"]
  abort("required release branch #{expected_branch} must require pull-request reviews") unless pull_request_reviews.is_a?(Hash)
  approval_count = pull_request_reviews["required_approving_review_count"]
  abort("required release branch #{expected_branch} must require at least one approving review") unless
    approval_count.is_a?(Integer) && approval_count >= 1
  abort("required release branch #{expected_branch} must dismiss stale reviews") unless
    pull_request_reviews["dismiss_stale_reviews"] == true
  abort("required release branch #{expected_branch} must require CODEOWNERS review") unless
    pull_request_reviews["require_code_owner_reviews"] == true
  abort("required release branch #{expected_branch} must require approval after the latest push") unless
    pull_request_reviews["require_last_push_approval"] == true
  bypass_allowances = pull_request_reviews["bypass_pull_request_allowances"]
  bypass_empty = bypass_allowances.is_a?(Hash) &&
    %w[users teams apps].all? { |kind| bypass_allowances[kind].is_a?(Array) && bypass_allowances[kind].empty? }
  abort("required release branch #{expected_branch} must have no pull-request bypass allowances") unless bypass_empty

  conversation_resolution = protection.dig("required_conversation_resolution", "enabled")
  abort("required release branch #{expected_branch} must require conversation resolution") unless conversation_resolution == true
  abort("required release branch #{expected_branch} must forbid force pushes") unless
    protection.dig("allow_force_pushes", "enabled") == false
  abort("required release branch #{expected_branch} must forbid deletion") unless
    protection.dig("allow_deletions", "enabled") == false

  puts JSON.pretty_generate({
    "schemaVersion" => 2,
    "status" => "passed",
    "environment" => actual_name,
    "requiredReviewers" => reviewers,
    "eligibleNonOwnerUsers" => eligible_non_owner_users,
    "eligibleNonOwnerReviewer" => true,
    "teamReviewerEligibilityAssumed" => false,
    "preventSelfReview" => true,
    "administratorsCanBypass" => false,
    "deploymentBranchPolicy" => policy,
    "requiredBranch" => expected_branch,
    "requiredBranchProtected" => true,
    "requiredBranchProtection" => {
      "strictStatusChecks" => true,
      "requiredStatusCheck" => {
        "context" => trusted_ci_check.fetch("context"),
        "appID" => trusted_ci_check.fetch("app_id")
      },
      "enforceAdministrators" => true,
      "requiredApprovingReviewCount" => approval_count,
      "dismissStaleReviews" => true,
      "requireCodeOwnerReviews" => true,
      "requireLastPushApproval" => true,
      "pullRequestBypassAllowances" => {
        "users" => [],
        "teams" => [],
        "apps" => []
      },
      "requireConversationResolution" => true,
      "allowForcePushes" => false,
      "allowDeletions" => false
    },
    "readOnly" => true
  })
' "${ENVIRONMENT_NAME}" "${BRANCH_NAME}" "${BRANCH_PROTECTION_JSON}" "${REPO%%/*}" <<< "${RAW_JSON}" 2>&1)"; then
  echo "error: release environment protection failed: ${NORMALIZED}" >&2
  exit 65
fi

if [[ -n "${OUTPUT_PATH}" ]]; then
  mkdir -p "$(dirname "${OUTPUT_PATH}")"
  printf '%s\n' "${NORMALIZED}" > "${OUTPUT_PATH}"
fi
printf '%s\n' "${NORMALIZED}"
