#!/usr/bin/ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "time"

ENV["GIT_NO_REPLACE_OBJECTS"] = "1"
%w[
  GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_REPLACE_REF_BASE
  GIT_CONFIG GIT_CONFIG_SYSTEM GIT_CONFIG_GLOBAL GIT_CONFIG_COUNT
  GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0
].each { |name| ENV.delete(name) }

class GovernanceEvidenceError < StandardError; end

GOVERNANCE_TOOL_PATH = "scripts/check-release-governance.sh"
GOVERNANCE_DEPENDENCY_PATHS = [
  "scripts/check-release-environment.sh",
  "scripts/check-release-secrets.sh",
  "scripts/verify-release-gh-toolchain.rb",
  ".github/release-gh-toolchain.json"
].freeze
MAX_EVIDENCE_AGE_SECONDS = 15 * 60
EXPECTED_ACTIONS_APP_ID = 15_368

options = {
  repository: "Reedtrullz/Vifty",
  root: File.expand_path("..", __dir__)
}

parser = OptionParser.new do |opts|
  opts.banner = <<~USAGE
    Usage: scripts/validate-release-governance-evidence.rb --evidence <path> --tag <tag> --commit <sha> --tagger-time <UTC time> [options]

    Validates administrator-visible pre-tag or exact-object post-tag governance
    evidence against the exact release commit. The tagger time is the exact
    timestamp used for freshness evaluation by the caller.
  USAGE
  opts.on("--evidence PATH", "Governance evidence JSON") { |value| options[:evidence] = value }
  opts.on("--repository OWNER/REPO", "Expected repository") { |value| options[:repository] = value }
  opts.on("--tag TAG", "Expected v<major>.<minor>.<patch> tag") { |value| options[:tag] = value }
  opts.on("--commit SHA", "Exact 40-character release commit") { |value| options[:commit] = value }
  opts.on("--tagger-time TIME", "Exact UTC tagger time (YYYY-MM-DDTHH:MM:SSZ)") do |value|
    options[:tagger_time] = value
  end
  opts.on("--current-time TIME", "Optional current UTC time for a live 15-minute freshness check") do |value|
    options[:current_time] = value
  end
  opts.on(
    "--expected-existing-tag-object SHA",
    "Require administrator-posttag evidence for this exact annotated tag object"
  ) do |value|
    options[:expected_existing_tag_object] = value
  end
  opts.on("--root PATH", "Repository root (test/tooling override)") { |value| options[:root] = value }
  opts.on("-h", "--help", "Show this help") do
    puts opts
    exit 0
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "error: #{e.message}"
  warn parser
  exit 64
end

def fail_evidence(message)
  raise GovernanceEvidenceError, message
end

def require_hash(value, label)
  fail_evidence("#{label} must be an object") unless value.is_a?(Hash)
  value
end

def require_exact(container, key, expected, label = key)
  fail_evidence("#{label} must be #{expected.inspect}") unless container[key] == expected
end

def require_empty_array(container, key, label = key)
  value = container[key]
  fail_evidence("#{label} must be an explicitly present empty array") unless value.is_a?(Array) && value.empty?
end

def parse_utc_time(value, label)
  unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    fail_evidence("#{label} must be an exact UTC timestamp (YYYY-MM-DDTHH:MM:SSZ)")
  end
  parsed = Time.iso8601(value).utc
  fail_evidence("#{label} must be a canonical UTC timestamp") unless parsed.iso8601 == value
  parsed
rescue ArgumentError
  fail_evidence("#{label} is not a valid UTC timestamp")
end

def git_output(root, *arguments)
  stdout, stderr, status = Open3.capture3("/usr/bin/git", "-C", root, *arguments)
  fail_evidence("git #{arguments.join(' ')} failed: #{stderr.strip}") unless status.success?
  stdout
end

begin
  %i[evidence tag commit tagger_time].each do |key|
    fail_evidence("--#{key.to_s.tr('_', '-')} is required") if options[key].to_s.empty?
  end
  fail_evidence("unexpected positional arguments: #{ARGV.join(' ')}") unless ARGV.empty?
  fail_evidence("--repository must be OWNER/REPO") unless options[:repository].match?(%r{\A[^/\s]+/[^/\s]+\z})
  fail_evidence("--tag must be v<major>.<minor>.<patch>") unless options[:tag].match?(/\Av\d+\.\d+\.\d+\z/)
  fail_evidence("--commit must be a full lowercase commit SHA") unless options[:commit].match?(/\A[0-9a-f]{40}\z/)
  unless options[:expected_existing_tag_object].to_s.empty? ||
         options[:expected_existing_tag_object].match?(/\A[0-9a-f]{40}\z/)
    fail_evidence("--expected-existing-tag-object must be a full lowercase tag-object SHA")
  end

  root = File.expand_path(options[:root])
  evidence_path = File.expand_path(options[:evidence])
  fail_evidence("governance evidence file is missing: #{evidence_path}") unless File.file?(evidence_path)

  resolved_commit = git_output(root, "rev-parse", "--verify", "#{options[:commit]}^{commit}").strip
  require_exact({ "resolved" => resolved_commit }, "resolved", options[:commit], "resolved release commit")
  committed_governance_tool = git_output(root, "show", "#{options[:commit]}:#{GOVERNANCE_TOOL_PATH}").b
  committed_governance_sha = Digest::SHA256.hexdigest(committed_governance_tool)
  committed_dependency_shas = GOVERNANCE_DEPENDENCY_PATHS.to_h do |path|
    [path, Digest::SHA256.hexdigest(git_output(root, "show", "#{options[:commit]}:#{path}").b)]
  end

  evidence_bytes = File.binread(evidence_path)
  evidence = JSON.parse(evidence_bytes)
  require_hash(evidence, "governance evidence")

  require_exact(evidence, "schemaVersion", 1)
  require_exact(evidence, "status", "passed")
  require_exact(evidence, "releaseAuthorized", true)
  require_exact(evidence, "apiHost", "github.com")
  require_exact(evidence, "dataSource", "github-api-live")
  require_exact(evidence, "liveAuthenticatedGitHubReadback", true)
  require_exact(evidence, "repository", options[:repository])
  require_exact(evidence, "releaseTag", options[:tag])
  require_exact(evidence, "expectedMainSHA", options[:commit])
  require_exact(evidence, "repositoryAdminVerified", true)
  authenticated_actor = require_hash(evidence["authenticatedActor"], "authenticatedActor")
  actor_id = authenticated_actor["id"]
  actor_login = authenticated_actor["login"]
  fail_evidence("authenticatedActor.id must be a positive integer") unless actor_id.is_a?(Integer) && actor_id.positive?
  fail_evidence("authenticatedActor.login must be non-empty") unless actor_login.is_a?(String) && !actor_login.empty?
  unless authenticated_actor.keys.sort == %w[id login]
    fail_evidence("authenticatedActor must contain only id and login")
  end
  posttag_mode = !options[:expected_existing_tag_object].to_s.empty?
  unless posttag_mode
    require_exact(evidence, "evidenceScope", "administrator-pretag")
    require_exact(evidence, "tagAbsentVerified", true)
    require_exact(evidence, "existingTagVerified", false)
    require_exact(evidence, "existingTagObjectSHA", nil)
  else
    require_exact(evidence, "evidenceScope", "administrator-posttag")
    require_exact(evidence, "tagAbsentVerified", false)
    require_exact(evidence, "existingTagVerified", true)
    require_exact(
      evidence,
      "existingTagObjectSHA",
      options[:expected_existing_tag_object]
    )
  end
  require_exact(evidence, "readOnly", true)

  tagger_time = parse_utc_time(options[:tagger_time], "tagger time")
  observation_started_at = parse_utc_time(evidence["observationStartedAt"], "observationStartedAt")
  observed_at = parse_utc_time(evidence["observedAt"], "observedAt")
  observation_duration = observed_at.to_i - observation_started_at.to_i
  fail_evidence("observedAt must not be earlier than observationStartedAt") if observation_duration.negative?
  if observation_duration > MAX_EVIDENCE_AGE_SECONDS
    fail_evidence("governance observation took #{observation_duration} seconds; maximum is #{MAX_EVIDENCE_AGE_SECONDS} seconds")
  end
  if posttag_mode
    evidence_age = observation_started_at.to_i - tagger_time.to_i
    fail_evidence("observationStartedAt must not be earlier than the tagger time") if evidence_age.negative?
  else
    evidence_age = tagger_time.to_i - observation_started_at.to_i
    fail_evidence("observationStartedAt must not be later than the tagger time") if evidence_age.negative?
    fail_evidence("observedAt must not be later than the tagger time") if observed_at > tagger_time
  end
  if !posttag_mode && evidence_age > MAX_EVIDENCE_AGE_SECONDS
    fail_evidence(
      "observationStartedAt is #{evidence_age} seconds old; maximum is #{MAX_EVIDENCE_AGE_SECONDS} seconds"
    )
  end
  current_freshness_verified = false
  validated_at = nil
  current_evidence_age = nil
  unless options[:current_time].to_s.empty?
    current_time = parse_utc_time(options[:current_time], "current time")
    current_evidence_age = current_time.to_i - observation_started_at.to_i
    fail_evidence("current time must not be earlier than observationStartedAt") if current_evidence_age.negative?
    if current_evidence_age > MAX_EVIDENCE_AGE_SECONDS
      fail_evidence(
        "observationStartedAt is #{current_evidence_age} seconds old at current time; maximum is #{MAX_EVIDENCE_AGE_SECONDS} seconds"
      )
    end
    fail_evidence("current time must not be earlier than the tagger time") if current_time < tagger_time
    fail_evidence("current time must not be earlier than observedAt") if current_time < observed_at
    current_freshness_verified = true
    validated_at = options[:current_time]
  end
  if posttag_mode && !current_freshness_verified
    fail_evidence("--current-time is required for administrator-posttag evidence")
  end

  governance_tool = require_hash(evidence["governanceTool"], "governanceTool")
  require_exact(governance_tool, "path", GOVERNANCE_TOOL_PATH, "governanceTool.path")
  recorded_tool_sha = governance_tool["sha256"]
  unless recorded_tool_sha.is_a?(String) && recorded_tool_sha.match?(/\A[0-9a-f]{64}\z/)
    fail_evidence("governanceTool.sha256 must be a lowercase SHA-256 digest")
  end
  require_exact(
    governance_tool,
    "sha256",
    committed_governance_sha,
    "governanceTool.sha256 for #{options[:commit]}"
  )

  dependencies = evidence["governanceDependencies"]
  unless dependencies.is_a?(Array) && dependencies.length == GOVERNANCE_DEPENDENCY_PATHS.length
    fail_evidence("governanceDependencies must contain the exact committed checker dependencies")
  end
  dependency_paths = dependencies.map do |entry|
    dependency = require_hash(entry, "governanceDependencies entry")
    path = dependency["path"]
    digest = dependency["sha256"]
    fail_evidence("governanceDependencies path must be a string") unless path.is_a?(String)
    unless digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)
      fail_evidence("governanceDependencies sha256 must be a lowercase SHA-256 digest")
    end
    expected_digest = committed_dependency_shas[path]
    fail_evidence("unexpected governance dependency path: #{path}") unless expected_digest
    require_exact(dependency, "sha256", expected_digest, "governance dependency #{path} sha256")
    path
  end
  unless dependency_paths == GOVERNANCE_DEPENDENCY_PATHS
    fail_evidence("governanceDependencies must use the exact expected order and paths")
  end

  environment = require_hash(evidence["releaseEnvironmentEvidence"], "releaseEnvironmentEvidence")
  require_exact(environment, "schemaVersion", 5, "releaseEnvironmentEvidence.schemaVersion")
  require_exact(environment, "status", "passed", "releaseEnvironmentEvidence.status")
  require_exact(environment, "releaseAuthorized", true, "releaseEnvironmentEvidence.releaseAuthorized")
  require_exact(environment, "dataSource", "github-api-live", "releaseEnvironmentEvidence.dataSource")
  require_exact(environment, "evidenceScope", "administrator-full", "releaseEnvironmentEvidence.evidenceScope")
  require_exact(environment, "privilegedSettingsVerified", true, "releaseEnvironmentEvidence.privilegedSettingsVerified")
  require_exact(environment, "environment", "release", "releaseEnvironmentEvidence.environment")
  require_exact(environment, "releaseGovernanceMode", "solo-maintainer", "releaseEnvironmentEvidence.releaseGovernanceMode")
  require_exact(environment, "requiredReviewerGate", false, "releaseEnvironmentEvidence.requiredReviewerGate")
  require_empty_array(environment, "requiredReviewers", "releaseEnvironmentEvidence.requiredReviewers")
  require_exact(environment, "preventSelfReview", false, "releaseEnvironmentEvidence.preventSelfReview")
  require_exact(environment, "administratorsCanBypass", false, "releaseEnvironmentEvidence.administratorsCanBypass")
  require_exact(environment, "requiredBranch", "main", "releaseEnvironmentEvidence.requiredBranch")
  require_exact(
    environment,
    "requiredBranchCommitSHA",
    options[:commit],
    "releaseEnvironmentEvidence.requiredBranchCommitSHA"
  )
  require_exact(environment, "requiredBranchProtected", true, "releaseEnvironmentEvidence.requiredBranchProtected")
  require_exact(environment, "readOnly", true, "releaseEnvironmentEvidence.readOnly")

  branch_policy = require_hash(environment["deploymentBranchPolicy"], "releaseEnvironmentEvidence.deploymentBranchPolicy")
  require_exact(branch_policy, "protected_branches", false, "deploymentBranchPolicy.protected_branches")
  require_exact(branch_policy, "custom_branch_policies", true, "deploymentBranchPolicy.custom_branch_policies")

  tag_policy = require_hash(
    environment["releaseTagDeploymentPolicy"],
    "releaseEnvironmentEvidence.releaseTagDeploymentPolicy"
  )
  require_exact(tag_policy, "policyCount", 1, "releaseTagDeploymentPolicy.policyCount")
  require_exact(tag_policy, "branchPolicyCount", 0, "releaseTagDeploymentPolicy.branchPolicyCount")
  require_exact(tag_policy, "tagPolicyCount", 1, "releaseTagDeploymentPolicy.tagPolicyCount")
  require_exact(tag_policy, "requiredTagPattern", "v*", "releaseTagDeploymentPolicy.requiredTagPattern")
  require_exact(
    tag_policy,
    "policies",
    [{"type" => "tag", "name" => "v*"}],
    "releaseTagDeploymentPolicy.policies"
  )

  branch = require_hash(environment["requiredBranchProtection"], "releaseEnvironmentEvidence.requiredBranchProtection")
  require_exact(branch, "strictStatusChecks", true, "requiredBranchProtection.strictStatusChecks")
  require_exact(branch, "enforceAdministrators", true, "requiredBranchProtection.enforceAdministrators")
  require_exact(branch, "pullRequestRequired", true, "requiredBranchProtection.pullRequestRequired")
  require_exact(branch, "peerApprovalRequired", false, "requiredBranchProtection.peerApprovalRequired")
  require_exact(branch, "requiredApprovingReviewCount", 0, "requiredBranchProtection.requiredApprovingReviewCount")
  require_exact(branch, "codeOwnerReviewRequired", false, "requiredBranchProtection.codeOwnerReviewRequired")
  require_exact(branch, "lastPushApprovalRequired", false, "requiredBranchProtection.lastPushApprovalRequired")
  require_empty_array(branch, "pullRequestBypassActors", "requiredBranchProtection.pullRequestBypassActors")
  require_exact(branch, "requireConversationResolution", true, "requiredBranchProtection.requireConversationResolution")
  require_exact(branch, "allowForcePushes", false, "requiredBranchProtection.allowForcePushes")
  require_exact(branch, "allowDeletions", false, "requiredBranchProtection.allowDeletions")
  required_check = require_hash(branch["requiredStatusCheck"], "requiredBranchProtection.requiredStatusCheck")
  require_exact(required_check, "context", "SwiftPM checks", "requiredStatusCheck.context")
  require_exact(required_check, "appID", EXPECTED_ACTIONS_APP_ID, "requiredStatusCheck.appID")

  ruleset = require_hash(evidence["tagRulesetEvidence"], "tagRulesetEvidence")
  require_exact(ruleset, "schemaVersion", 1, "tagRulesetEvidence.schemaVersion")
  require_exact(ruleset, "repository", options[:repository], "tagRulesetEvidence.repository")
  require_exact(ruleset, "releaseTag", options[:tag], "tagRulesetEvidence.releaseTag")
  require_exact(ruleset, "releaseRef", "refs/tags/#{options[:tag]}", "tagRulesetEvidence.releaseRef")
  ruleset_id = ruleset["rulesetID"]
  fail_evidence("tagRulesetEvidence.rulesetID must be a positive integer") unless ruleset_id.is_a?(Integer) && ruleset_id.positive?
  fail_evidence("tagRulesetEvidence.rulesetName must be non-empty") unless ruleset["rulesetName"].is_a?(String) && !ruleset["rulesetName"].empty?
  ruleset_updated_at = parse_utc_time(
    ruleset["rulesetUpdatedAt"],
    "tagRulesetEvidence.rulesetUpdatedAt"
  )
  fail_evidence("tagRulesetEvidence.rulesetUpdatedAt must not be later than observedAt") if ruleset_updated_at > observed_at
  require_exact(
    ruleset,
    "rulesetUpdatedAt",
    ruleset_updated_at.iso8601,
    "tagRulesetEvidence.rulesetUpdatedAt"
  )
  require_exact(ruleset, "currentUserCanBypass", "never", "tagRulesetEvidence.currentUserCanBypass")
  require_exact(ruleset, "target", "tag", "tagRulesetEvidence.target")
  require_exact(ruleset, "enforcement", "active", "tagRulesetEvidence.enforcement")
  require_exact(ruleset, "bypassActorsVerified", true, "tagRulesetEvidence.bypassActorsVerified")
  require_empty_array(ruleset, "bypassActors", "tagRulesetEvidence.bypassActors")
  require_exact(ruleset, "preventsUpdate", true, "tagRulesetEvidence.preventsUpdate")
  require_exact(ruleset, "preventsDeletion", true, "tagRulesetEvidence.preventsDeletion")
  require_exact(ruleset, "excludePatternsVerified", true, "tagRulesetEvidence.excludePatternsVerified")
  require_exact(ruleset, "readOnly", true, "tagRulesetEvidence.readOnly")
  require_empty_array(ruleset, "matchedExcludePatterns", "tagRulesetEvidence.matchedExcludePatterns")
  require_exact(
    ruleset,
    "matchedIncludePatterns",
    ["refs/tags/v*"],
    "tagRulesetEvidence.matchedIncludePatterns"
  )
  rule_types = ruleset["ruleTypes"]
  unless rule_types.is_a?(Array) && rule_types.all? { |value| value.is_a?(String) } && rule_types.sort == %w[deletion update]
    fail_evidence("tagRulesetEvidence.ruleTypes must contain exactly deletion and update")
  end

  secrets = require_hash(evidence["releaseSecrets"], "releaseSecrets")
  require_exact(secrets, "storageScope", "repository", "releaseSecrets.storageScope")
  require_exact(secrets, "requiredNamesVerified", true, "releaseSecrets.requiredNamesVerified")
  require_empty_array(secrets, "environmentShadowNames", "releaseSecrets.environmentShadowNames")
  require_exact(secrets, "valuesRead", false, "releaseSecrets.valuesRead")

  puts JSON.generate({
    "schemaVersion" => 1,
    "status" => "passed",
    "repository" => options[:repository],
    "releaseTag" => options[:tag],
    "releaseCommitSHA" => options[:commit],
    "authenticatedActor" => {
      "id" => actor_id,
      "login" => actor_login
    },
    "evidenceScope" => evidence.fetch("evidenceScope"),
    "tagAbsentVerified" => evidence.fetch("tagAbsentVerified"),
    "existingTagVerified" => evidence.fetch("existingTagVerified"),
    "existingTagObjectSHA" => evidence.fetch("existingTagObjectSHA"),
    "rulesetID" => ruleset_id,
    "rulesetUpdatedAt" => ruleset.fetch("rulesetUpdatedAt"),
    "currentUserCanBypass" => ruleset.fetch("currentUserCanBypass"),
    "observationStartedAt" => evidence.fetch("observationStartedAt"),
    "observedAt" => evidence.fetch("observedAt"),
    "observationDurationSeconds" => observation_duration,
    "taggerTime" => options[:tagger_time],
    "evidenceAgeSeconds" => evidence_age,
    "currentFreshnessVerified" => current_freshness_verified,
    "validatedAt" => validated_at,
    "currentEvidenceAgeSeconds" => current_evidence_age,
    "governanceToolSHA256" => committed_governance_sha,
    "governanceDependencySHA256" => committed_dependency_shas,
    "evidenceSHA256" => Digest::SHA256.hexdigest(evidence_bytes),
    "readOnly" => true
  })
rescue JSON::ParserError => e
  warn "error: governance evidence is not valid JSON: #{e.message}"
  exit 65
rescue GovernanceEvidenceError, KeyError => e
  warn "error: governance evidence validation failed: #{e.message}"
  exit 65
end
