#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "digest"
require "json"
require "open3"

def deep_sort(value)
  case value
  when Hash
    value.keys.sort.each_with_object({}) { |key, sorted| sorted[key] = deep_sort(value[key]) }
  when Array
    value.map { |item| deep_sort(item) }
  else
    value
  end
end

def normalized_step_hash(step)
  Digest::SHA256.hexdigest(JSON.generate(deep_sort(step)))
end

def exact_permissions?(permissions, contents)
  permissions == { "contents" => contents }
end

def secret_context_references(value, path = [], found = {})
  case value
  when Hash
    value.each { |key, child| secret_context_references(child, path + [key], found) }
  when Array
    value.each_with_index { |child, index| secret_context_references(child, path + [index], found) }
  when String
    found[path] = value if value.match?(/\$\{\{(?:(?!\}\}).)*\bsecrets\b(?:(?!\}\}).)*\}\}/m)
  end
  found
end

root = ENV.fetch("VIFTY_WORKFLOW_CONTRACT_ROOT", File.expand_path("..", __dir__))
workflow_paths = Dir.glob(File.join(root, ".github/workflows/*.{yml,yaml}")).sort
abort("error: no GitHub Actions workflows found") if workflow_paths.empty?

expected_workflow_files = %w[ci.yml release.yml]
actual_workflow_files = workflow_paths.map { |path| File.basename(path) }

expected_actions = {
  "actions/checkout" => ["df4cb1c069e1874edd31b4311f1884172cec0e10", "v6"],
  "actions/cache" => ["caa296126883cff596d87d8935842f9db880ef25", "v5"],
  "actions/upload-artifact" => ["043fb46d1a93c77aae656e7c1c64a875d1fc6a0a", "v7"],
  "actions/download-artifact" => ["3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c", "v8"]
}

errors = []
workflows = {}
unless actual_workflow_files == expected_workflow_files
  errors << "workflow file set must be exactly #{expected_workflow_files.join(', ')}"
end

workflow_paths.each do |path|
  relative_path = path.delete_prefix("#{root}/")
  text = File.read(path)
  begin
    workflow = YAML.safe_load(
      text,
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
  rescue StandardError => error
    errors << "#{relative_path} is not valid YAML: #{error.message}"
    next
  end
  unless workflow.is_a?(Hash)
    errors << "#{relative_path} must decode to a mapping"
    next
  end
  workflows[File.basename(path)] = workflow

  expected_top_level_keys = %w[name on permissions env concurrency jobs]
  expected_top_level_keys << "run-name" if File.basename(path) == "release.yml"
  unless workflow.keys.sort == expected_top_level_keys.sort
    errors << "#{relative_path} top-level fields must be exactly #{expected_top_level_keys.join(', ')}"
  end
  unless workflow["env"] == { "FORCE_JAVASCRIPT_ACTIONS_TO_NODE24" => "true" }
    errors << "#{relative_path} top-level env must contain only the pinned Node.js actions runtime opt-in"
  end

  permissions = workflow["permissions"]
  unless exact_permissions?(permissions, "read")
    errors << "#{relative_path} top-level permissions must be exactly {contents: read}"
  end

  jobs = workflow["jobs"]
  unless jobs.is_a?(Hash) && !jobs.empty?
    errors << "#{relative_path} must contain jobs"
    next
  end

  jobs.each do |job_name, job|
    next unless job.is_a?(Hash)
    if job.key?("uses") || job.key?("secrets")
      errors << "#{relative_path} job #{job_name} must not call a reusable workflow or inherit secrets"
    end
    steps = Array(job["steps"])
    steps.each do |step|
      if step.is_a?(Hash) && step["run"].is_a?(String)
        _stdout, stderr, status = Open3.capture3("/bin/bash", "-n", stdin_data: step.fetch("run"))
        unless status.success?
          detail = stderr.lines.first.to_s.strip
          errors << "#{relative_path} job #{job_name} step #{step["name"].inspect} has invalid shell syntax#{detail.empty? ? "" : ": #{detail}"}"
        end
      end
      next unless step.is_a?(Hash) && step["uses"]
      action, reference = step.fetch("uses").split("@", 2)
      expected = expected_actions[action]
      if expected.nil?
        errors << "#{relative_path} job #{job_name} uses unapproved action #{action}"
        next
      end
      expected_sha, release_label = expected
      unless reference == expected_sha
        errors << "#{relative_path} job #{job_name} must pin #{action}@#{expected_sha} (#{release_label})"
      end
      comment_pattern = /uses:\s*#{Regexp.escape(action)}@#{Regexp.escape(expected_sha)}\s+#\s*#{Regexp.escape(release_label)}\b/
      unless text.match?(comment_pattern)
        errors << "#{relative_path} must comment #{action} pin as #{release_label}"
      end
      if action == "actions/checkout"
        with = step["with"]
        unless with.is_a?(Hash) && with["persist-credentials"] == false
          errors << "#{relative_path} job #{job_name} checkout must set persist-credentials: false"
        end
        unless with.is_a?(Hash) && with["fetch-depth"] == 0
          errors << "every approved checkout must fetch complete history for immutable release verification"
        end
      end
    end
  end
end

expected_top_level_contracts = {
  "ci.yml" => {
    "name" => "CI",
    "concurrency" => {
      "group" => "${{ github.workflow }}-${{ github.ref }}",
      "cancel-in-progress" => true
    },
    "jobs" => ["swiftpm"]
  },
  "release.yml" => {
    "name" => "Release",
    "run-name" => "Release ${{ github.ref_name }}",
    "concurrency" => {
      "group" => "${{ github.workflow }}-${{ github.ref_name }}",
      "cancel-in-progress" => false
    },
    "jobs" => %w[prepare-candidate sign-notarize publish]
  }
}

expected_top_level_contracts.each do |workflow_name, expected|
  workflow = workflows[workflow_name]
  next unless workflow.is_a?(Hash)
  errors << ".github/workflows/#{workflow_name} name must remain #{expected.fetch("name").inspect}" unless workflow["name"] == expected.fetch("name")
  if expected.key?("run-name")
    errors << ".github/workflows/#{workflow_name} run-name must bind the exact pushed tag ref name" unless workflow["run-name"] == expected.fetch("run-name")
  end
  errors << ".github/workflows/#{workflow_name} concurrency must match the reviewed mapping" unless workflow["concurrency"] == expected.fetch("concurrency")
  jobs = workflow["jobs"]
  unless jobs.is_a?(Hash) && jobs.keys == expected.fetch("jobs")
    errors << ".github/workflows/#{workflow_name} jobs must be exactly #{expected.fetch("jobs").join(', ')}"
  end
end

expected_job_wrappers = {
  "ci.yml" => {
    "swiftpm" => {
      "name" => "SwiftPM checks",
      "runs-on" => "macos-15",
      "timeout-minutes" => 35
    }
  },
  "release.yml" => {
    "prepare-candidate" => {
      "name" => "Build and inventory unsigned candidate",
      "runs-on" => "macos-15",
      "timeout-minutes" => 35,
      "permissions" => { "actions" => "read", "contents" => "read" },
      "env" => {
        "RELEASE_TAG" => "${{ github.ref_name }}"
      }
    },
    "sign-notarize" => {
      "name" => "Sign and notarize inventoried candidate",
      "needs" => "prepare-candidate",
      "if" => "${{ github.run_attempt == 1 }}",
      "runs-on" => "macos-15",
      "timeout-minutes" => 25,
      "environment" => "release",
      "permissions" => { "actions" => "read", "contents" => "read" },
      "env" => { "RELEASE_TAG" => "${{ github.ref_name }}" }
    },
    "publish" => {
      "name" => "Publish verified GitHub release",
      "needs" => "sign-notarize",
      "if" => "${{ github.run_attempt == 1 }}",
      "runs-on" => "macos-15",
      "timeout-minutes" => 10,
      "permissions" => { "contents" => "write" },
      "env" => { "RELEASE_TAG" => "${{ github.ref_name }}" }
    }
  }
}.freeze

expected_job_wrappers.each do |workflow_name, expected_jobs|
  workflow = workflows[workflow_name]
  next unless workflow.is_a?(Hash) && workflow["jobs"].is_a?(Hash)
  expected_jobs.each do |job_name, expected_wrapper|
    job = workflow["jobs"][job_name]
    next unless job.is_a?(Hash)
    actual_wrapper = job.reject { |key, _value| key == "steps" }
    unless actual_wrapper == expected_wrapper
      errors << ".github/workflows/#{workflow_name} job #{job_name} wrapper must match the reviewed runner, timeout, dependencies, permissions, environment, and fields exactly"
    end
  end
end

expected_secret_bindings = {}
release_workflow = workflows["release.yml"]
if release_workflow.is_a?(Hash)
  signing_steps = Array(release_workflow.dig("jobs", "sign-notarize", "steps"))
  binding_specification = {
    "Require signing and notarization secrets" => {
      "APPLE_TEAM_ID" => "APPLE_TEAM_ID",
      "APPLE_ID" => "APPLE_ID",
      "APPLE_APP_SPECIFIC_PASSWORD" => "APPLE_APP_SPECIFIC_PASSWORD",
      "DEVELOPER_ID_APPLICATION_IDENTITY" => "DEVELOPER_ID_APPLICATION_IDENTITY",
      "DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64" => "DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64",
      "DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD" => "DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD"
    },
    "Import Developer ID certificate" => {
      "CERTIFICATE_BASE64" => "DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64",
      "CERTIFICATE_PASSWORD" => "DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD"
    },
    "Revalidate trusted tooling and sign existing candidate" => {
      "SIGNING_IDENTITY" => "DEVELOPER_ID_APPLICATION_IDENTITY",
      "APPLE_TEAM_ID" => "APPLE_TEAM_ID"
    },
    "Notarize signed candidate" => {
      "APPLE_ID" => "APPLE_ID",
      "APPLE_TEAM_ID" => "APPLE_TEAM_ID",
      "APPLE_APP_SPECIFIC_PASSWORD" => "APPLE_APP_SPECIFIC_PASSWORD"
    },
    "Create and verify release assets with trusted tools" => {
      "APPLE_TEAM_ID" => "APPLE_TEAM_ID"
    }
  }
  binding_specification.each do |step_name, bindings|
    step_index = signing_steps.index { |step| step.is_a?(Hash) && step["name"] == step_name }
    next unless step_index
    bindings.each do |environment_name, secret_name|
      path = ["release.yml", "jobs", "sign-notarize", "steps", step_index, "env", environment_name]
      expected_secret_bindings[path] = "${{ secrets.#{secret_name} }}"
    end
  end
end

actual_secret_bindings = workflows.each_with_object({}) do |(workflow_name, workflow), found|
  secret_context_references(workflow).each do |path, value|
    found[[workflow_name] + path] = value
  end
end
unless actual_secret_bindings == expected_secret_bindings
  errors << "workflow secret context references must match the reviewed sign-notarize bindings exactly"
end

actionlint_path = File.join(root, "scripts/run-actionlint.sh")
if !File.file?(actionlint_path)
  errors << "scripts/run-actionlint.sh is required"
else
  actionlint_text = File.read(actionlint_path)
  errors << "actionlint must be pinned to version 1.7.12" unless actionlint_text.include?('ACTIONLINT_VERSION="1.7.12"')
  errors << "actionlint archive must use its pinned SHA-256" unless actionlint_text.include?('ACTIONLINT_DARWIN_ARM64_SHA256="aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f"')
  errors << "actionlint runner must verify the downloaded archive" unless actionlint_text.include?('actual_sha') && actionlint_text.include?('ACTIONLINT_DARWIN_ARM64_SHA256')
end

candidate_inventory_path = File.join(root, "scripts/release-candidate-inventory.rb")
if !File.file?(candidate_inventory_path)
  errors << "scripts/release-candidate-inventory.rb is required"
else
  candidate_inventory_text = File.read(candidate_inventory_path)
  unless candidate_inventory_text.include?("File.lstat") &&
         candidate_inventory_text.include?('"type" => "directory"') &&
         candidate_inventory_text.include?('"type" => "symlink"') &&
         candidate_inventory_text.include?("candidate tree contains unsupported file type") &&
         candidate_inventory_text.include?("/usr/bin/bsdtar") &&
         candidate_inventory_text.include?('"--no-same-owner"') &&
         candidate_inventory_text.include?("candidate handoff contains missing or extra entries")
    errors << "candidate inventory must cover complete file types, modes, links, special-file rejection, exact handoff identity, and safe extraction"
  end
end

gh_toolchain_verifier_path = File.join(root, "scripts/verify-release-gh-toolchain.rb")
gh_toolchain_policy_path = File.join(root, ".github/release-gh-toolchain.json")
if !File.file?(gh_toolchain_verifier_path) || !File.executable?(gh_toolchain_verifier_path) ||
   !File.file?(gh_toolchain_policy_path)
  errors << "pinned release gh verifier and policy are required"
else
  gh_verifier_text = File.read(gh_toolchain_verifier_path)
  begin
    gh_policy = JSON.parse(File.read(gh_toolchain_policy_path))
  rescue JSON::ParserError
    gh_policy = nil
  end
  expected_gh_policy = {
    "platform" => "darwin-arm64",
    "schemaVersion" => 1,
    "sha256" => "282ec2bb5c6abb6cee50cbfa5f8c04ac2fd6b8523693970a5cab331b121f5430",
    "tool" => "gh",
    "version" => "2.93.0"
  }
  unless gh_policy == expected_gh_policy &&
         gh_verifier_text.start_with?("#!/usr/bin/ruby\n") &&
         gh_verifier_text.include?('%i[policy source destination]') &&
         gh_verifier_text.include?('fail_toolchain("--#{key} must be an absolute path")') &&
         gh_verifier_text.include?('File.open(source_path, "rb")') &&
         gh_verifier_text.include?("File::WRONLY | File::CREAT | File::EXCL") &&
         gh_verifier_text.include?('digest.hexdigest == policy["sha256"]') &&
         gh_verifier_text.include?('expected_prefix = "gh version #{policy.fetch(\'version\')} ("') &&
         gh_verifier_text.include?('unsetenv_others: true') &&
         gh_verifier_text.include?('uname_s.strip == "Darwin" && uname_m.strip == "arm64"')
    errors << "release gh toolchain must pin the reviewed Darwin arm64 gh 2.93.0 bytes before token access"
  end
end

release_environment_checker_path = File.join(root, "scripts/check-release-environment.sh")
release_environment_checker_text =
  File.file?(release_environment_checker_path) ? File.read(release_environment_checker_path) : ""

release_secret_checker_path = File.join(root, "scripts/check-release-secrets.sh")
if !File.file?(release_secret_checker_path)
  errors << "scripts/check-release-secrets.sh is required"
else
  release_secret_checker_text = File.read(release_secret_checker_path)
  secret_pin_index = release_secret_checker_text.index('verify-release-gh-toolchain.rb')
  secret_live_index = release_secret_checker_text.index("else\n  if [ -n \"${GH_HOST:-}\"")
  secret_auth_index = secret_live_index &&
    release_secret_checker_text.index("assert_safe_gh_config", secret_live_index)
  unless release_secret_checker_text.include?('safe_gh secret list --repo "github.com/${REPO}"') &&
         release_secret_checker_text.include?('safe_gh secret list --env "${ENVIRONMENT_NAME}" --repo "github.com/${REPO}"') &&
         release_secret_checker_text.include?("GH_CONFIG_DIR=/var/empty") &&
         release_secret_checker_text.include?('Environment secret shadows repository release secret') &&
         secret_pin_index && secret_auth_index && secret_pin_index < secret_auth_index
    errors << "release-secret operator preflight must require repository names and reject same-name environment shadows"
  end
end

release_governance_checker_path = File.join(root, "scripts/check-release-governance.sh")
if !File.file?(release_governance_checker_path)
  errors << "scripts/check-release-governance.sh is required"
else
  release_governance_checker_text = File.read(release_governance_checker_path)
  unless release_governance_checker_text.include?('posttag_mode ? "administrator-posttag" : "administrator-pretag"') &&
         release_governance_checker_text.include?('"apiHost" => "github.com"') &&
         release_governance_checker_text.include?('"status" => fixture_mode ? "test-fixture" : "passed"') &&
         release_governance_checker_text.include?('"releaseAuthorized" => !fixture_mode') &&
         release_governance_checker_text.include?('"dataSource" => fixture_mode ? "test-fixture" : "github-api-live"') &&
         release_governance_checker_text.include?('repo.dig("permissions", "admin") == true') &&
         release_governance_checker_text.include?('canonical_updated_at = Time.iso8601(updated_at).utc.iso8601(9)') &&
         release_governance_checker_text.include?('"rulesetUpdatedAt" => canonical_updated_at') &&
         release_governance_checker_text.include?('"currentUserCanBypass" => current_user_can_bypass') &&
         release_governance_checker_text.include?('current_user_can_bypass == "never"') &&
         release_governance_checker_text.include?('includes == ["refs/tags/v*"] && excludes == []') &&
         !release_governance_checker_text.include?("FNM_EXTGLOB") &&
         release_governance_checker_text.include?('safe_gh api --hostname github.com user') &&
         release_governance_checker_text.include?('"authenticatedActor" => actor && {') &&
         release_governance_checker_text.include?('"tagAbsentVerified" => !fixture_mode && !posttag_mode') &&
         release_governance_checker_text.include?('"existingTagVerified" => !fixture_mode && posttag_mode') &&
         release_governance_checker_text.include?('"existingTagObjectSHA" => posttag_mode ? existing_tag_object : nil') &&
         release_governance_checker_text.include?('--expected-existing-tag-object') &&
         release_governance_checker_text.include?('"repos/${REPO}/git/ref/tags/${TAG}"') &&
         !release_governance_checker_text.include?("matching-refs") &&
         release_governance_checker_text.include?('"governanceTool" => {') &&
         release_governance_checker_text.include?('"governanceDependencies" => [') &&
         release_governance_checker_text.include?('--hostname github.com') &&
         release_governance_checker_text.include?("GH_CONFIG_DIR=/var/empty") &&
         release_governance_checker_text.include?("assert_safe_gh_config") &&
         release_governance_checker_text.include?('check-release-environment.sh') &&
         release_governance_checker_text.include?('check-release-secrets.sh') &&
         release_governance_checker_text.include?('scripts/verify-release-gh-toolchain.rb') &&
         release_governance_checker_text.include?('.github/release-gh-toolchain.json') &&
         release_governance_checker_text.include?('VIFTY_RELEASE_PINNED_GH="${GH_BIN}"')
    errors << "administrator governance checker must bind exact-main, exact-ref pre-tag absence or exact-object post-tag presence, committed-tool, no-bypass ruleset, and anti-shadow secret evidence"
  end
end

governance_validator_path = File.join(root, "scripts/validate-release-governance-evidence.rb")
signed_tag_creator_path = File.join(root, "scripts/create-signed-release-tag.sh")
push_dispatch_helper_path = File.join(root, "scripts/push-and-dispatch-signed-release-tag.sh")
release_provenance_path = File.join(root, "scripts/check-release-provenance.sh")
release_checklist_writer_path = File.join(root, "scripts/write-release-checklist.sh")
if !File.file?(governance_validator_path) || !File.file?(signed_tag_creator_path) ||
   !File.file?(push_dispatch_helper_path) || !File.file?(release_provenance_path)
  errors << "signed governance validator, signed release-tag creator, signed-tag push helper, and release provenance checker are required"
else
  governance_validator_text = File.read(governance_validator_path)
  signed_tag_creator_text = File.read(signed_tag_creator_path)
  push_dispatch_helper_text = File.read(push_dispatch_helper_path)
  release_provenance_text = File.read(release_provenance_path)
  unless governance_validator_text.include?("MAX_EVIDENCE_AGE_SECONDS = 15 * 60") &&
         governance_validator_text.include?('"administrator-pretag"') &&
         governance_validator_text.include?('"administrator-posttag"') &&
         governance_validator_text.include?('--expected-existing-tag-object') &&
         governance_validator_text.include?('require_exact(evidence, "tagAbsentVerified", true)') &&
         governance_validator_text.include?('require_exact(evidence, "tagAbsentVerified", false)') &&
         governance_validator_text.include?('require_exact(evidence, "existingTagVerified", false)') &&
         governance_validator_text.include?('require_exact(evidence, "existingTagVerified", true)') &&
         governance_validator_text.include?('"existingTagObjectSHA"') &&
         governance_validator_text.include?("--current-time is required for administrator-posttag evidence") &&
         governance_validator_text.include?('"github-api-live"') &&
         governance_validator_text.include?('GOVERNANCE_DEPENDENCY_PATHS') &&
         governance_validator_text.include?('currentFreshnessVerified') &&
         governance_validator_text.include?('"administrator-full"') &&
         governance_validator_text.include?('requiredBranchCommitSHA') &&
         governance_validator_text.include?('"rulesetUpdatedAt" => ruleset.fetch("rulesetUpdatedAt")') &&
         governance_validator_text.include?('"currentUserCanBypass" => ruleset.fetch("currentUserCanBypass")') &&
         governance_validator_text.include?('["refs/tags/v*"]') &&
         !governance_validator_text.include?("FNM_EXTGLOB") &&
         governance_validator_text.include?('authenticated_actor = require_hash(evidence["authenticatedActor"]') &&
         governance_validator_text.include?('committed_governance_sha')
    errors << "governance validator must bind explicit pre-tag/post-tag state tuples, chronology, administrator scopes, exact branch commit, and committed checker SHA"
  end
  unless signed_tag_creator_text.include?('Vifty-Release-Governance-Base64:') &&
         signed_tag_creator_text.include?('GIT_COMMITTER_DATE="${tagger_time}"') &&
         signed_tag_creator_text.include?('safe_gh api --hostname github.com') &&
         signed_tag_creator_text.include?('"repos/${REPOSITORY}/branches/main"') &&
         signed_tag_creator_text.include?('"repos/${REPOSITORY}/git/ref/tags/${TAG}"') &&
         signed_tag_creator_text.include?('"${EXACT_TAG_HTTP_STATUS}" == "404"') &&
         signed_tag_creator_text.include?("GH_CONFIG_DIR=/var/empty") &&
         signed_tag_creator_text.include?("GIT_EXEC_PATH GIT_CONFIG_PARAMETERS") &&
         signed_tag_creator_text.include?("export GIT_CONFIG_COUNT=12") &&
         signed_tag_creator_text.include?("GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null") &&
         signed_tag_creator_text.include?("GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1=false") &&
         signed_tag_creator_text.include?("GIT_CONFIG_KEY_8=gpg.ssh.program") &&
         signed_tag_creator_text.include?("GIT_CONFIG_KEY_9=user.signingkey") &&
         signed_tag_creator_text.include?("evidence output must not be inside Git metadata") &&
         signed_tag_creator_text.include?("evidence output must not replace a tracked worktree path") &&
         signed_tag_creator_text.include?("retained evidence changed at completion") &&
         signed_tag_creator_text.scan('"${committed_root}/${GOVERNANCE_TOOL_PATH}"').length >= 2 &&
         !signed_tag_creator_text.include?('--evidence <path>') &&
         signed_tag_creator_text.include?('--current-time "${final_time}"') &&
         signed_tag_creator_text.include?('"${GIT_BIN}" archive --format=tar "${COMMIT}"') &&
         signed_tag_creator_text.include?('/usr/bin/cmp -s "${commit_signers}" "${parent_signers}"') &&
         signed_tag_creator_text.include?('verify-tag "${created_tag_object}"') &&
         signed_tag_creator_text.include?('no successful completed push CI run on main for exact commit') &&
         signed_tag_creator_text.include?('/Applications/1Password.app/Contents/MacOS/op-ssh-sign') &&
         signed_tag_creator_text.include?('-c gpg.ssh.program=/usr/bin/ssh-keygen') &&
         signed_tag_creator_text.include?('The tag was not pushed.')
    errors << "release-tag creator must embed exact fresh governance evidence and create only an unpushed signed tag"
  end
  canonical_helper_source =
    push_dispatch_helper_text.include?('SELF_PATH="scripts/push-and-dispatch-signed-release-tag.sh"') &&
    push_dispatch_helper_text.include?('REPOSITORY="Reedtrullz/Vifty"') &&
    push_dispatch_helper_text.include?('if [[ "${REPOSITORY}" != "Reedtrullz/Vifty" ]]') &&
    push_dispatch_helper_text.include?("release helper must run from the canonical committed repository path") &&
    push_dispatch_helper_text.scan('"${SELF_PATH}"').length >= 2 &&
    push_dispatch_helper_text.include?('VIFTY_WORKFLOW_CONTRACT_ROOT="${committed_root}"') &&
    !push_dispatch_helper_text.include?("VIFTY_RELEASE_PUSH_ROOT")
  unless canonical_helper_source
    errors << "signed-tag push helper must bind the canonical Reedtrullz/Vifty source and exact committed release tooling"
  end

  pinned_operator_gh =
    release_environment_checker_text.include?('verify-release-gh-toolchain.rb') &&
    release_environment_checker_text.include?('--destination "${GH_BIN}"') &&
    release_secret_checker_text.include?('--destination "${GH_BIN}"') &&
    signed_tag_creator_text.include?('release gh toolchain policy must be byte-identical to the exact first parent') &&
    signed_tag_creator_text.include?('"${committed_root}/${GH_TOOLCHAIN_VERIFIER_PATH}"') &&
    push_dispatch_helper_text.include?('release gh toolchain policy must be byte-identical to the exact first parent') &&
    push_dispatch_helper_text.include?('"${committed_root}/${GH_TOOLCHAIN_VERIFIER_PATH}"') &&
    governance_validator_text.include?('"scripts/verify-release-gh-toolchain.rb"') &&
    governance_validator_text.include?('".github/release-gh-toolchain.json"') &&
    signed_tag_creator_text.include?('certificate leaf[subject.OU] = "2BUA8C4S2C"') &&
    signed_tag_creator_text.include?('approved SSH signing program changed before tag signing')
  unless pinned_operator_gh
    errors << "release operator entrypoints must verify the first-parent-pinned gh binary before token access and bind it into governance evidence"
  end

  protected_release_tool_paths = %w[
    .github/release-gh-toolchain.json
    .github/release-signers.allowed
    .github/workflows/ci.yml
    .github/workflows/release.yml
    scripts/check-release-environment.sh
    scripts/check-release-governance.sh
    scripts/check-release-manifest-history-from-git.sh
    scripts/check-release-manifest-history.rb
    scripts/check-release-manifest.sh
    scripts/check-release-prep-diff.sh
    scripts/check-release-provenance.sh
    scripts/check-release-secrets.sh
    scripts/check-workflow-contract.rb
    scripts/create-signed-release-tag.sh
    scripts/lib/release_artifact_contract.rb
    scripts/push-and-dispatch-signed-release-tag.sh
    scripts/release-candidate-inventory.rb
    scripts/render-release-facts.sh
    scripts/run-actionlint.sh
    scripts/sign-release-candidate.sh
    scripts/validate-release-governance-evidence.rb
    scripts/validate-release-metadata.sh
    scripts/verify-release-artifact.sh
    scripts/verify-release-gh-toolchain.rb
    scripts/write-release-checklist.sh
  ]
  protected_tool_continuity =
    File.file?(File.join(root, "scripts/check-release-prep-diff.sh")) &&
    File.executable?(File.join(root, "scripts/check-release-prep-diff.sh")) &&
    signed_tag_creator_text.include?("protected_release_paths=(") &&
    push_dispatch_helper_text.include?("protected_release_paths=(") &&
    signed_tag_creator_text.include?("protected release tooling must be byte-identical to the exact first parent") &&
    push_dispatch_helper_text.include?("protected release tooling must be byte-identical to the exact first parent") &&
    protected_release_tool_paths.all? do |path|
      signed_tag_creator_text.include?(%Q{"#{path}"}) &&
        push_dispatch_helper_text.include?(%Q{"#{path}"})
    end
  unless protected_tool_continuity
    errors << "release prep must keep the complete reviewed release-tool set byte-identical to its exact first parent"
  end

  release_prep_diff_admission =
    signed_tag_creator_text.include?('RELEASE_PREP_DIFF_CHECKER_PATH="scripts/check-release-prep-diff.sh"') &&
    push_dispatch_helper_text.include?('RELEASE_PREP_DIFF_CHECKER_PATH="scripts/check-release-prep-diff.sh"') &&
    signed_tag_creator_text.include?('"${committed_root}/${RELEASE_PREP_DIFF_CHECKER_PATH}"') &&
    push_dispatch_helper_text.include?('"${committed_root}/${RELEASE_PREP_DIFF_CHECKER_PATH}"') &&
    signed_tag_creator_text.include?('--commit "${COMMIT}"') &&
    push_dispatch_helper_text.include?('--commit "${COMMIT}"')
  unless release_prep_diff_admission
    errors << "tag creation and push must execute the first-parent-protected release-prep diff checker"
  end

  actor_and_token_binding =
    signed_tag_creator_text.include?("unset GH_TOKEN GITHUB_TOKEN") &&
    push_dispatch_helper_text.include?("unset GH_TOKEN GITHUB_TOKEN") &&
    signed_tag_creator_text.include?('exec 9<<<"${release_token}"') &&
    push_dispatch_helper_text.include?('exec 9<<<"${release_token}"') &&
    signed_tag_creator_text.include?('VIFTY_GH_TOKEN_FD=9') &&
    push_dispatch_helper_text.include?('VIFTY_GH_TOKEN_FD=9') &&
    signed_tag_creator_text.include?('IFS= read -r INHERITED_GH_TOKEN <&9') &&
    push_dispatch_helper_text.include?('IFS= read -r INHERITED_GH_TOKEN <&9') &&
    signed_tag_creator_text.include?('run_clean_script_with_token "${committed_root}/${GOVERNANCE_TOOL_PATH}"') &&
    push_dispatch_helper_text.include?('run_clean_script_with_token "${committed_root}/${GOVERNANCE_TOOL_PATH}"') &&
    release_governance_checker_text.include?('run_pinned_tool_with_token "${ENVIRONMENT_TOOL_PATH}"') &&
    release_governance_checker_text.include?('run_pinned_tool_with_token "${SECRETS_TOOL_PATH}"') &&
    !signed_tag_creator_text.include?('GH_TOKEN="${SAFE_GH_TOKEN}" GITHUB_TOKEN=') &&
    !push_dispatch_helper_text.include?('GH_TOKEN="${SAFE_GH_TOKEN}" GITHUB_TOKEN=') &&
    !release_governance_checker_text.include?('GH_TOKEN="${SAFE_GH_TOKEN}" GITHUB_TOKEN=') &&
    release_governance_checker_text.include?('"authenticatedActor" => actor && {') &&
    governance_validator_text.include?('authenticated_actor = require_hash(evidence["authenticatedActor"]') &&
    push_dispatch_helper_text.include?('post["authenticatedActor"] == signed["authenticatedActor"]') &&
    push_dispatch_helper_text.include?('run.dig("actor", "login") == signed_actor["login"]') &&
    push_dispatch_helper_text.include?('run.dig("actor", "id") == signed_actor["id"]')
  unless actor_and_token_binding
    errors << "release governance, tag push, and run evidence must use one recorded authenticated actor while keeping tokens out of the signer and clean-shell argv"
  end

  exact_tag_transaction =
    push_dispatch_helper_text.include?('"repos/${REPOSITORY}/git/ref/${namespace}/${name}"') &&
    !push_dispatch_helper_text.include?("matching-refs") &&
    push_dispatch_helper_text.include?("require_remote_tag_absent") &&
    push_dispatch_helper_text.scan("require_remote_branch_absent").length >= 4 &&
    push_dispatch_helper_text.scan("require_release_absent").length >= 2 &&
    push_dispatch_helper_text.include?('--paginate --slurp') &&
    push_dispatch_helper_text.include?('"repos/${REPOSITORY}/releases?per_page=100"') &&
    push_dispatch_helper_text.include?('matches = releases.select { |release| release["tag_name"] == tag }') &&
    push_dispatch_helper_text.include?('abort("an existing draft or published release already owns #{tag}") unless matches.empty?') &&
    !push_dispatch_helper_text.include?('releases/tags/${TAG}') &&
    push_dispatch_helper_text.include?('--force-with-lease="refs/tags/${TAG}:"') &&
    push_dispatch_helper_text.include?('"${TAG_OBJECT}:refs/tags/${TAG}"') &&
    push_dispatch_helper_text.include?('fields[0] == "*"') &&
    push_dispatch_helper_text.include?('fields[2] == "[new tag]"') &&
    push_dispatch_helper_text.include?('PUSH_OWNERSHIP="created-by-this-transaction"') &&
    push_dispatch_helper_text.include?('"repos/${REPOSITORY}/git/tags/${TAG_OBJECT}"') &&
    push_dispatch_helper_text.include?('tag["sha"] == expected_object') &&
    push_dispatch_helper_text.include?('tag.dig("object", "sha") == expected_commit')
  unless exact_tag_transaction
    errors << "signed-tag push helper must prove exact absent-ref compare-and-swap creation, exact tag-object readback, strict new-tag ownership, and same-named branch absence"
  end

  posttag_checker_index = push_dispatch_helper_text.index(
    'postpush_evidence="${scratch}/postpush-governance-evidence.json"'
  )
  posttag_validator_index = push_dispatch_helper_text.index(
    '> "${scratch}/postpush-governance-validation.json"'
  )
  run_observation_index = push_dispatch_helper_text.index(
    'CURRENT_STAGE="tag-push-run-observation"'
  )
  posttag_governance =
    posttag_checker_index &&
    posttag_validator_index &&
    run_observation_index &&
    posttag_checker_index < posttag_validator_index &&
    posttag_validator_index < run_observation_index &&
    push_dispatch_helper_text.include?('"${committed_root}/${GOVERNANCE_TOOL_PATH}"') &&
    push_dispatch_helper_text.include?('"${committed_root}/${VALIDATOR_PATH}"') &&
    push_dispatch_helper_text.scan('--expected-existing-tag-object "${TAG_OBJECT}"').length >= 2 &&
    push_dispatch_helper_text.include?('post["evidenceScope"] == "administrator-posttag"') &&
    push_dispatch_helper_text.include?('post["existingTagVerified"] == true') &&
    push_dispatch_helper_text.include?('post["existingTagObjectSHA"] == object') &&
    push_dispatch_helper_text.include?('%w[releaseEnvironmentEvidence tagRulesetEvidence releaseSecrets]')
  unless posttag_governance
    errors << "signed-tag push helper must run the exact committed checker and validator in exact-object post-tag mode before accepting the tag-push run"
  end

  marker_index = push_dispatch_helper_text.index("create_retirement_marker\n")
  push_receipt_index = push_dispatch_helper_text.index(
    'write_receipt "push-started-remote-outcome-unknown"'
  )
  push_index = push_dispatch_helper_text.index(
    'safe_bare_git "${bare_root}" push'
  )
  canonical_home_index = push_dispatch_helper_text.index(
    'CANONICAL_HOME="$("${RUBY_BIN}" -retc -e'
  )
  canonical_home_export_index = push_dispatch_helper_text.index(
    "HOME=\"${CANONICAL_HOME}\"\nexport HOME\n"
  )
  transaction_home_index = push_dispatch_helper_text.index(
    'library_dir="${HOME}/Library"'
  )
  one_shot_tag_push =
    push_dispatch_helper_text.include?('/usr/bin/shlock -f "${LOCK_PATH}" -p "$$"') &&
    marker_index && push_receipt_index && push_index &&
    marker_index < push_receipt_index && push_receipt_index < push_index &&
    canonical_home_index && canonical_home_export_index && transaction_home_index &&
    canonical_home_index < canonical_home_export_index &&
    canonical_home_export_index < transaction_home_index &&
    push_dispatch_helper_text.include?('passwd_home = Etc.getpwuid(Process.uid).dir') &&
    push_dispatch_helper_text.include?('resolved_home = File.realpath(passwd_home)') &&
    push_dispatch_helper_text.scan('safe_bare_git "${bare_root}" push').length == 1 &&
    push_dispatch_helper_text.include?('application_support_dir="${library_dir}/Application Support"') &&
    push_dispatch_helper_text.include?('transactions_dir="${vifty_state_dir}/ReleaseTransactions"') &&
    push_dispatch_helper_text.include?('RETIREMENT_MARKER_PATH="${receipt_dir}/retired.json"') &&
    push_dispatch_helper_text.include?('File::WRONLY | File::CREAT | File::EXCL') &&
    push_dispatch_helper_text.include?('"retiredTag" => true') &&
    push_dispatch_helper_text.include?('"authorizesRetry" => false') &&
    push_dispatch_helper_text.include?('durable retired-tag marker blocks') &&
    push_dispatch_helper_text.include?('"receiptAuthorizesRetry" => false') &&
    push_dispatch_helper_text.include?('prior_receipt_result=') &&
    push_dispatch_helper_text.include?('receipt["status"] == "validated-pre-push"') &&
    push_dispatch_helper_text.include?('"retired-after-mutation-boundary"') &&
    push_dispatch_helper_text.include?("existing release receipt blocks this transaction") &&
    push_dispatch_helper_text.include?('askpass_token_path="${askpass_dir}/token"') &&
    push_dispatch_helper_text.include?('builtin printf \'%s\\n\' "${SAFE_GH_TOKEN}" > "${askpass_token_path}"') &&
    push_dispatch_helper_text.include?('/bin/chmod 600 "${askpass_token_path}"') &&
    push_dispatch_helper_text.include?('VIFTY_GIT_TOKEN_FILE="${askpass_token_path}"') &&
    push_dispatch_helper_text.include?('IFS= read -r token < "${token_file}"') &&
    push_dispatch_helper_text.include?('/bin/unlink "${askpass_token_path}" "${askpass_path}"') &&
    !push_dispatch_helper_text.include?('VIFTY_GIT_TOKEN="${SAFE_GH_TOKEN}"') &&
    push_dispatch_helper_text.include?("never authorizes retry") &&
    !push_dispatch_helper_text.include?("--resume") &&
    !push_dispatch_helper_text.match?(/(?:^|[[:space:]])(?:safe_gh|gh|\"\$\{GH_BIN\}\")[[:space:]]+workflow[[:space:]]+run(?:[[:space:]]|$)/) &&
    !push_dispatch_helper_text.include?("workflow_dispatch") &&
    !push_dispatch_helper_text.include?("DISPATCH_NONCE") &&
    !push_dispatch_helper_text.include?("dispatch_nonce")
  unless one_shot_tag_push
    errors << "signed-tag push helper must durably retire the tag before its one compare-and-swap push, never manually dispatch or rerun, and never authorize retry or resume"
  end

  strict_run_correlation =
    push_dispatch_helper_text.include?('matches.length == 1') &&
    push_dispatch_helper_text.include?('--event push') &&
    push_dispatch_helper_text.include?('--workflow "${WORKFLOW_ID}"') &&
    push_dispatch_helper_text.include?("--all") &&
    push_dispatch_helper_text.include?('"repos/${REPOSITORY}/actions/runs/${RUN_ID}"') &&
    push_dispatch_helper_text.include?('run["id"] == run_id.to_i') &&
    push_dispatch_helper_text.include?('run["workflow_id"] == workflow_id.to_i') &&
    push_dispatch_helper_text.include?('workflow["name"] == "Release"') &&
    push_dispatch_helper_text.include?('run["name"] == "Release #{tag}"') &&
    push_dispatch_helper_text.include?('run["path"] == ".github/workflows/release.yml"') &&
    push_dispatch_helper_text.include?('run["display_title"] == "Release #{tag}"') &&
    push_dispatch_helper_text.include?('run["event"] == "push"') &&
    push_dispatch_helper_text.include?('run["head_branch"] == tag') &&
    push_dispatch_helper_text.include?('run["head_sha"] == commit') &&
    push_dispatch_helper_text.include?('run["run_attempt"] == 1') &&
    push_dispatch_helper_text.include?('run.dig("actor", "login") == signed_actor["login"]') &&
    push_dispatch_helper_text.include?('run.dig("actor", "id") == signed_actor["id"]') &&
    push_dispatch_helper_text.include?('run.dig("repository", "full_name") == repository') &&
    push_dispatch_helper_text.include?('run["html_url"] == expected_url') &&
    push_dispatch_helper_text.include?('created_at < journaled - 60')
  unless strict_run_correlation
    errors << "signed-tag push helper must correlate exactly one first-attempt push-triggered Release run to the exact actor, repository, workflow, tag, commit, time, and URL"
  end
  unless release_provenance_text.include?('Vifty-Release-Governance-Base64:') &&
         release_provenance_text.include?('validate-release-governance-evidence.rb') &&
         release_provenance_text.include?('-c gpg.ssh.program=/usr/bin/ssh-keygen') &&
         release_provenance_text.include?('verify-tag "${TAG_OBJECT}"') &&
         release_provenance_text.include?('/usr/bin/cmp -s "${COMMITTED_SIGNERS_PATH}" "${PARENT_SIGNERS_PATH}"') &&
         release_provenance_text.include?("GH_CONFIG_DIR=/var/empty") &&
         release_provenance_text.include?("GIT_EXEC_PATH GIT_CONFIG_PARAMETERS") &&
         release_provenance_text.include?("export GIT_CONFIG_COUNT=7") &&
         release_provenance_text.include?("GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null") &&
         release_provenance_text.include?("GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1=false") &&
         release_provenance_text.include?('"${GIT_BIN}" diff --no-ext-diff') &&
         release_provenance_text.include?("governance evidence output must not be inside Git metadata") &&
         release_provenance_text.include?("governance evidence output must not replace a tracked worktree path") &&
         release_provenance_text.include?("retained evidence changed at completion") &&
         release_provenance_text.include?('"status" => data_source == "test-fixture" ? "test-fixture" : "passed"') &&
         release_provenance_text.include?('"authoritative" => data_source == "github-api-live"') &&
         release_provenance_text.include?("Release provenance TEST FIXTURE only:") &&
         release_provenance_text.include?('"dataSource" => data_source') &&
         release_provenance_text.include?('must resolve to exact signed tag commit') &&
         release_provenance_text.include?('"administratorGovernanceEvidence" => governance_evidence') &&
         release_provenance_text.include?('"administratorGovernanceValidation" => governance_validation')
    errors << "release provenance must decode and validate the administrator evidence carried by the signed tag"
  end
end

release_entrypoint_paths = %w[
  scripts/check-release-environment.sh
  scripts/check-release-secrets.sh
  scripts/check-release-governance.sh
  scripts/create-signed-release-tag.sh
  scripts/push-and-dispatch-signed-release-tag.sh
  scripts/check-release-provenance.sh
]
release_entrypoint_paths.each do |relative_path|
  path = File.join(root, relative_path)
  unless File.file?(path)
    errors << "#{relative_path} is a required protected release entrypoint"
    next
  end
  text = File.read(path)
  unless File.executable?(path) &&
         text.start_with?("#!/bin/bash -p\n") &&
         text.include?("exec /usr/bin/env -i") &&
         text.include?('/bin/bash -p -c \'source "$1" "${@:2}"\' vifty-release-clean "$0" "$@"') &&
         text.include?('inherited_functions="$(builtin declare -F)"') &&
         text.include?("error: inherited shell functions are not allowed") &&
         text.include?("GH_CONFIG_DIR XDG_CONFIG_HOME GH_PATH GH_FORCE_TTY GITHUB_API_URL") &&
         text.include?('PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"') &&
         text.include?('config get http_unix_socket --host github.com') &&
         text.include?("GH_CONFIG_DIR=/var/empty")
    errors << "#{relative_path} must be executable, relaunch in a clean privileged shell, reject inherited functions, and isolate authenticated gh calls from mutable configuration"
  end
end
release_workflow = workflows["release.yml"]
if release_workflow.is_a?(Hash)
  release_run_text = release_workflow.fetch("jobs", {}).values
    .flat_map { |job| Array(job.is_a?(Hash) ? job["steps"] : nil) }
    .map { |step| step.is_a?(Hash) ? step["run"] : nil }
    .compact
    .join("\n")
  protected_entrypoint = /
    (?:^|[[:space:]])(?:\/bin\/)?bash[[:space:]]+
    [^\n]*
    (?:
      check-release-(?:environment|secrets|governance|provenance)\.sh |
      create-signed-release-tag\.sh |
      push-and-dispatch-signed-release-tag\.sh
    )
  /x
  if release_run_text.match?(protected_entrypoint)
    errors << "release workflow must execute protected release entrypoints directly so their privileged-shell shebang cannot be bypassed"
  end
end
if !File.file?(release_checklist_writer_path)
  errors << "release checklist writer is required"
elsif !File.read(release_checklist_writer_path).include?('# Vifty ${VERSION} Release Checklist')
  errors << "release checklist writer title must match the publication contract"
end

%w[ci.yml release.yml].each do |workflow_name|
  workflow = workflows[workflow_name]
  next unless workflow.is_a?(Hash)
  run_text = workflow.fetch("jobs", {}).values.flat_map { |job| Array(job.is_a?(Hash) ? job["steps"] : nil) }
    .map { |step| step.is_a?(Hash) ? step["run"] : nil }
    .compact
    .join("\n")
  errors << ".github/workflows/#{workflow_name} must run pinned actionlint" unless run_text.include?("scripts/run-actionlint.sh")
end

ci_workflow = workflows["ci.yml"]
if ci_workflow.is_a?(Hash)
  ci_steps = Array(ci_workflow.dig("jobs", "swiftpm", "steps"))
  expected_ci_step_hashes = {
    "Check out" => "7394ed43b5af02da158a4b5c6d309e86ebd54f33856af1d1661b81035a28014d",
    "Verify trusted base release-manifest continuity" => "b07fe57aa599746749b973711c1da3a643efa161234d0d755f69ec0a7516f175",
    "Configure SwiftPM build path" => "403ff2137f240911db4030914d39a253197ed6225b7d63727207f19da07db400",
    "Cache SPM build artifacts" => "ceb4fc110a0a33b119033a8226b022736fc2411604e9b108b4443de5f178389e",
    "Show toolchain" => "247dd98d3e2bf4ef8ec191a47dede52c9a41657fc89b39723224ba530b74ae62",
    "Lint workflows with pinned actionlint" => "a029874b5f979fb52fb1d1934ee6fc78a35b77c79cd2fadcf0eaf0e5f6554f53",
    "Run full verification" => "76dac556e5ba2d273a4cb482d91ca6dbacac235caed926f8e642a71ac1305d8a",
    "Verify install script in temporary Applications directory" => "4b52eed1a00f94fb66af9a6ed0b9a210d67c6e606e767746f9e273bd6272fe55",
    "Archive app bundle" => "12a494d6e187595f47918b08eb01432eb8eb513f972550f6d0a46db8a228812a",
    "Upload app artifact" => "01d5ae3f2f47d370e4b211f49d562518c0172ceb0c2617c3e56928ffafc219ea"
  }
  ci_names = ci_steps.map { |step| step.is_a?(Hash) ? step["name"] : nil }
  errors << "CI step set must match the reviewed exact-main gate allowlist" unless ci_names == expected_ci_step_hashes.keys
  expected_ci_step_hashes.each do |step_name, expected_hash|
    step = ci_steps.find { |candidate| candidate.is_a?(Hash) && candidate["name"] == step_name }
    errors << "CI step #{step_name.inspect} must match its reviewed normalized step mapping hash" unless
      step && normalized_step_hash(step) == expected_hash
  end
  continuity_step = ci_steps.find do |step|
    step.is_a?(Hash) && step["name"] == "Verify trusted base release-manifest continuity"
  end
  continuity_run = continuity_step.is_a?(Hash) ? continuity_step["run"].to_s : ""
  continuity_env = continuity_step.is_a?(Hash) ? continuity_step["env"] : nil
  unless continuity_env == {
           "EVENT_BASE_SHA" => "${{ github.event.pull_request.base.sha || github.event.before || '' }}"
         } &&
         continuity_run.include?('scripts/check-release-manifest.sh') &&
         continuity_run.include?('--base-ref "${BASE_SHA}"') &&
         continuity_run.include?("--require-base") &&
         continuity_run.include?('BASE_SHA="$(git rev-parse HEAD^)"')
    errors << "CI must enforce trusted base release-manifest continuity from the PR base, push-before SHA, or exact first parent"
  end
end

release = workflows["release.yml"] || workflows["release.yaml"]
if release.nil?
  errors << ".github/workflows/release.yml is required"
else
  trigger = release["on"]
  expected_release_trigger = {
    "push" => { "tags" => ["v*"] }
  }
  unless trigger == expected_release_trigger
    errors << "release workflow must trigger only on pushed tags matching v*"
  end
  jobs = release.fetch("jobs", {})
  prepare = jobs["prepare-candidate"]
  signed = jobs["sign-notarize"]
  publish = jobs["publish"]
  unless prepare.is_a?(Hash)
    errors << "release workflow requires prepare-candidate job"
  end
  unless signed.is_a?(Hash)
    errors << "release workflow requires sign-notarize job"
  end
  unless publish.is_a?(Hash)
    errors << "release workflow requires separate publish job"
  end

  if prepare.is_a?(Hash)
    errors << "prepare-candidate must not use a protected environment" if prepare.key?("environment")
    permissions = prepare["permissions"]
    unless permissions == { "actions" => "read", "contents" => "read" }
      errors << "prepare-candidate permissions must be exactly {actions: read, contents: read}"
    end
    prepare_text = prepare.to_s
    errors << "prepare-candidate must not receive repository secrets" if prepare_text.include?("secrets.")
    steps = Array(prepare["steps"])
    names = steps.map { |step| step.is_a?(Hash) ? step["name"] : nil }
    expected_prepare_step_hashes = {
      "Require immutable signed-tag workflow context" => "a29a0115b44d597e118bd3c867f0ae822f67776f48dbe0fd9ab632b7a474b132",
      "Check out signed release tag without credentials" => "8348fc77a1ad2fdcb15cddf17c1f43201c4683db236b2b2285e3113fc1a612b2",
      "Show toolchain" => "247dd98d3e2bf4ef8ec191a47dede52c9a41657fc89b39723224ba530b74ae62",
      "Configure SwiftPM build path" => "c5524ea3241ecab9b0a5fbe560a3de517d397f70033b22ce9295afad4c9ad9d5",
      "Validate candidate version and signed tag" => "ae2437c0eecf8c9da23e29b88dd71a42fa63ac7e22b389175e3a25747ec0787c",
      "Verify remote ancestry and exact-commit CI provenance" => "8edb1b7ee78a075b71b9ce08ea3a00bcd77c55933ce35643ed9ea7544bc53e61",
      "Validate release metadata and workflow contract" => "a6f5ddbd334bf4802d35e41829489813962415feb2d6c77d53d7cf478c8b1dd8",
      "Lint workflows with pinned actionlint" => "a029874b5f979fb52fb1d1934ee6fc78a35b77c79cd2fadcf0eaf0e5f6554f53",
      "Run full read-only build and test gate" => "3ebdbadc8b49faabd95393d7f2f8ce7a1a8bfcf5aebe63e0b453fa603b41b338",
      "Assemble ad-hoc candidate with release TeamID policy" => "55918c6b689196f082b655c8d6b0d04dc36372b74d85f0afb4f864b03a3a81fe",
      "Inventory unsigned candidate" => "529d1ce8416f485fc6ef08093d48f89999bff79c7541906bbab28bc8d294bd86",
      "Upload hash-inventoried unsigned candidate" => "fb37259cf21ce04554a1cd596a0dc4503b31a6680076bb1a3966ea315b7ebc51"
    }
    errors << "prepare-candidate step set must match the reviewed allowlist exactly" unless names == expected_prepare_step_hashes.keys
    expected_prepare_step_hashes.each do |step_name, expected_hash|
      step = steps.find { |candidate| candidate.is_a?(Hash) && candidate["name"] == step_name }
      actual_hash = step ? normalized_step_hash(step) : nil
      unless actual_hash == expected_hash
        errors << "prepare-candidate step #{step_name.inspect} must match its reviewed normalized step mapping hash"
      end
    end
    context_index = names.index("Require immutable signed-tag workflow context")
    provenance_index = names.index("Verify remote ancestry and exact-commit CI provenance")
    test_index = names.index("Run full read-only build and test gate")
    build_index = names.index("Assemble ad-hoc candidate with release TeamID policy")
    inventory_index = names.index("Inventory unsigned candidate")
    upload_index = names.index("Upload hash-inventoried unsigned candidate")
    unless [context_index, provenance_index, test_index, build_index, inventory_index, upload_index].all? &&
           context_index < provenance_index && provenance_index < test_index && test_index < build_index && build_index < inventory_index && inventory_index < upload_index
      errors << "prepare-candidate must require an immutable signed-tag push, prove provenance, test, build, inventory, then upload in order"
    end
    run_text = steps.map { |step| step.is_a?(Hash) ? step["run"] : nil }.compact.join("\n")
    unless run_text.include?('test "${GITHUB_EVENT_NAME}" = "push"') &&
           run_text.include?('test "${GITHUB_RUN_ATTEMPT}" = "1"') &&
           run_text.include?('test "${GITHUB_REF_TYPE}" = "tag"') &&
           run_text.include?('test "${GITHUB_REF_NAME}" = "${RELEASE_TAG}"') &&
           run_text.include?('test "${GITHUB_REF}" = "refs/tags/${RELEASE_TAG}"') &&
           run_text.include?('[[ "${GITHUB_SHA}" =~ ^[0-9a-f]{40}$ ]]')
      errors << "prepare-candidate must fail closed outside the first attempt of an exact immutable signed-tag push"
    end
    checkout_step = steps.find { |step| step.is_a?(Hash) && step["name"] == "Check out signed release tag without credentials" }
    checkout_with = checkout_step.is_a?(Hash) ? checkout_step["with"] : nil
    unless checkout_with == {
      "ref" => "refs/tags/${{ github.ref_name }}",
      "fetch-depth" => 0,
      "persist-credentials" => false
    }
      errors << "prepare-candidate checkout must bind the exact immutable pushed tag with full history and no persisted credentials"
    end
    errors << "prepare-candidate must require a manifest candidate" unless run_text.include?("scripts/check-release-manifest.sh") && run_text.include?('--publication-version "${VERSION}"')
    unless run_text.include?('git fetch --no-tags origin "${GITHUB_SHA}"') &&
           run_text.include?('--base-ref "${GITHUB_SHA}^"') &&
           run_text.include?("--require-base")
      errors << "prepare-candidate must enforce trusted base release-manifest continuity from the exact workflow source first parent"
    end
    errors << "prepare-candidate must cryptographically verify the release tag against first-parent-continuous github.sha signer policy" unless
      run_text.include?('git show "${GITHUB_SHA}:.github/release-signers.allowed"') &&
      run_text.include?('git show "${GITHUB_SHA}^:.github/release-signers.allowed"') &&
      run_text.include?('cmp -s "${TRUSTED_SIGNERS}" "${PARENT_SIGNERS}"') &&
      run_text.include?('TAG_OBJECT="$(git rev-parse --verify "refs/tags/${RELEASE_TAG}^{tag}")"') &&
      run_text.include?('gpg.ssh.allowedSignersFile="${TRUSTED_SIGNERS}"') &&
      run_text.include?('verify-tag "${TAG_OBJECT}"')
    candidate_validation = steps.find { |step| step.is_a?(Hash) && step["name"] == "Validate candidate version and signed tag" }
    candidate_validation_run = candidate_validation.is_a?(Hash) ? candidate_validation["run"].to_s : ""
    verify_tag_index = candidate_validation_run.index('verify-tag "${TAG_OBJECT}"')
    manifest_index = candidate_validation_run.index("scripts/check-release-manifest.sh")
    unless verify_tag_index && manifest_index && verify_tag_index < manifest_index
      errors << "prepare-candidate must authenticate the signed tag before executing candidate checkout scripts"
    end
    errors << "prepare-candidate must verify remote ancestry and exact-main-CI provenance" unless run_text.include?("scripts/check-release-provenance.sh") && run_text.include?('--tag "${RELEASE_TAG}"') && run_text.include?('--main-ref "${GITHUB_SHA}"')
    unless run_text.include?('--require-current-governance-freshness') &&
           run_text.include?('vifty-release-admission-provenance.json') &&
           run_text.include?('--supplemental release-admission-provenance.json') &&
           run_text.include?('--output candidate-inventory.json')
      errors << "prepare-candidate must persist current-fresh signed governance admission in the hashed candidate handoff"
    end
    unless run_text.include?('actor = provenance.dig("administratorGovernanceEvidence", "authenticatedActor")') &&
           run_text.include?('actor["id"].to_s == ARGV.fetch(1)') &&
           run_text.include?('actor["login"] == ARGV.fetch(2)') &&
           run_text.include?('"${GITHUB_ACTOR_ID}" "${GITHUB_ACTOR}"')
      errors << "prepare-candidate must bind signed administrator actor ID and login to the tag-push actor"
    end
    unless candidate_validation_run.include?('scripts/check-release-prep-diff.sh') &&
           candidate_validation_run.include?('--root "${GITHUB_WORKSPACE}"') &&
           candidate_validation_run.include?('--commit "${GITHUB_SHA}"')
      errors << "prepare-candidate must enforce the exact protected release-prep diff before candidate scripts"
    end
    errors << "prepare-candidate must run the full verification gate" unless run_text.include?('make verify-full SWIFT_BUILD_PATH="${SWIFT_BUILD_PATH}"')
    errors << "prepare-candidate must assemble only an ad-hoc candidate" unless run_text.include?('SIGNING_IDENTITY="-"')
    unless run_text.include?('scripts/release-candidate-inventory.rb" create') &&
           run_text.include?("--norsrc --noextattr --noqtn --noacl") &&
           run_text.include?("candidate-inventory.json") &&
           !run_text.include?("candidate-files.sha256") &&
           !run_text.include?("find Vifty.app -type f")
      errors << "prepare-candidate must inventory the complete candidate tree, archive, modes, links, and admission provenance"
    end
    candidate_upload = steps.find { |step| step.is_a?(Hash) && step["name"] == "Upload hash-inventoried unsigned candidate" }
    candidate_upload_with = candidate_upload.is_a?(Hash) ? candidate_upload["with"] : nil
    unless candidate_upload_with.is_a?(Hash) &&
           candidate_upload_with["name"] == "vifty-candidate-${{ github.run_id }}" &&
           candidate_upload_with["overwrite"] == true
      errors << "candidate artifact handoff must use one rerun-stable run ID name with overwrite enabled"
    end
    errors << "prepare-candidate must upload only candidate bytes/inventory, never candidate-supplied release tools" if run_text.include?("release-tools.sha256") || run_text.include?("release-tools/scripts") || run_text.include?("TOOL_ROOT")
  end

  if signed.is_a?(Hash)
    environment = signed["environment"]
    environment_name = environment.is_a?(Hash) ? environment["name"] : environment
    errors << "sign-notarize must declare the release environment gate" unless environment_name == "release"
    permissions = signed["permissions"]
    unless permissions == { "actions" => "read", "contents" => "read" }
      errors << "sign-notarize permissions must be exactly {actions: read, contents: read}"
    end
    expected_release_tag = "${{ github.ref_name }}"
    errors << "sign-notarize job environment must contain only RELEASE_TAG" unless signed["env"] == { "RELEASE_TAG" => expected_release_tag }
    allowed_job_keys = %w[name needs if runs-on timeout-minutes environment permissions env steps]
    unexpected_job_keys = signed.keys - allowed_job_keys
    errors << "sign-notarize contains unreviewed job fields: #{unexpected_job_keys.sort.join(', ')}" unless unexpected_job_keys.empty?
    errors << "sign-notarize must refuse workflow reruns" unless signed["if"] == "${{ github.run_attempt == 1 }}"
    needs = Array(signed["needs"])
    errors << "sign-notarize must depend on prepare-candidate" unless needs.include?("prepare-candidate")
    steps = Array(signed["steps"])
    names = steps.map { |step| step.is_a?(Hash) ? step["name"] : nil }
    expected_step_names = [
      "Check out trusted release tooling",
      "Inventory trusted release tooling",
      "Verify release environment protection",
      "Download inventoried candidate",
      "Verify candidate and trusted tool inventories before secret-consuming steps",
      "Require signing and notarization secrets",
      "Import Developer ID certificate",
      "Revalidate trusted tooling and sign existing candidate",
      "Notarize signed candidate",
      "Create and verify release assets with trusted tools",
      "Remove signing material",
      "Upload verified release assets for publication"
    ]
    errors << "sign-notarize step set must match the reviewed allowlist exactly" unless names == expected_step_names

    expected_step_hashes = {
      "Check out trusted release tooling" => "b513361ad57276908ad99e1cf84fe4d93af1cad5e81363a7b22c8487980b9021",
      "Inventory trusted release tooling" => "f8bf25f7e3bba872bcb11b2f0aea575cb502e9f534f372298d3d50efbadf1ffc",
      "Verify release environment protection" => "8a8583cbe1bf9b64edc0f2176cfd016a767e050b5692432a0d32d170a3ad4b7a",
      "Download inventoried candidate" => "48f99fd7a3190b1f735782e9d60f242586636e8a999f4aad431ce9681c1ea829",
      "Verify candidate and trusted tool inventories before secret-consuming steps" => "78e3046f2cb66c12079b9d9fe2a27d343d47cdaa6355959ee1ec535e5801ade2",
      "Require signing and notarization secrets" => "e5421852d3202b04e2aa2ac167915e6806b53a64a257eb6322f60ebfb1e2d892",
      "Import Developer ID certificate" => "c1d39d72865189a04b4d529ee8ccda1abb42ddff304466d8abcbf45d3bea4147",
      "Revalidate trusted tooling and sign existing candidate" => "ba4561b4ab6926f6dd028f634b2f0c79a36d24aba14cc12a1386f6eec929401f",
      "Notarize signed candidate" => "f5050e48f720d04083c7d15f22bf82f72cc2f822d23ef08d0761a09fe3a316a7",
      "Create and verify release assets with trusted tools" => "0619d4252a470afea71054a535385dd864d98656c06ad9e3849f404a4d94c238",
      "Remove signing material" => "4df2d7fa1538a8e0017e92932873c0bf76dd6984e000ac1bfd9795c6263040c1",
      "Upload verified release assets for publication" => "ce920891b00c02cc279f139e1823cbdb94f025d8588d771b607747c77eb09e34"
    }
    expected_step_hashes.each do |step_name, expected_hash|
      step = steps.find { |candidate| candidate.is_a?(Hash) && candidate["name"] == step_name }
      actual_hash = step ? normalized_step_hash(step) : nil
      unless actual_hash == expected_hash
        errors << "sign-notarize step #{step_name.inspect} must match its reviewed normalized step mapping hash"
      end
    end
    environment_index = names.index("Verify release environment protection")
    verify_index = names.index("Verify candidate and trusted tool inventories before secret-consuming steps")
    import_index = names.index("Import Developer ID certificate")
    sign_index = names.index("Revalidate trusted tooling and sign existing candidate")
    notarize_index = names.index("Notarize signed candidate")
    artifact_index = names.index("Create and verify release assets with trusted tools")
    unless [environment_index, verify_index, import_index, sign_index, notarize_index, artifact_index].all? &&
           environment_index < verify_index && verify_index < import_index && import_index < sign_index &&
           sign_index < notarize_index && notarize_index < artifact_index
      errors << "sign-notarize must verify the environment and candidate, import, sign, notarize, then package in order"
    end
    cleanup = steps.find { |step| step.is_a?(Hash) && step["name"] == "Remove signing material" }
    unless cleanup && cleanup["if"].to_s == "always()" && cleanup["run"].to_s.include?("security delete-keychain")
      errors << "release workflow must always delete the temporary signing keychain"
    end
    run_text = steps.map { |step| step.is_a?(Hash) ? step["run"] : nil }.compact.join("\n")
    trusted_checkout = steps.find { |step| step.is_a?(Hash) && step["name"] == "Check out trusted release tooling" }
    trusted_checkout_with = trusted_checkout.is_a?(Hash) ? trusted_checkout["with"] : nil
    unless trusted_checkout_with.is_a?(Hash) && trusted_checkout_with["ref"] == "${{ github.sha }}" && trusted_checkout_with["path"] == ".build/trusted-release-source" && trusted_checkout_with["fetch-depth"] == 0 && trusted_checkout_with["persist-credentials"] == false
      errors << "sign-notarize must check out exact github.sha trusted release source without persisted credentials"
    end
    trusted_inventory = steps.find { |step| step.is_a?(Hash) && step["name"] == "Inventory trusted release tooling" }
    trusted_inventory_run = trusted_inventory.is_a?(Hash) ? trusted_inventory["run"].to_s : ""
    unless trusted_inventory_run.include?('trusted_status="$(git status --porcelain=v1 --untracked-files=all)"') &&
           trusted_inventory_run.include?('test -z "${trusted_status}"') &&
           trusted_inventory_run.include?("git ls-files -z | xargs -0 shasum -a 256") &&
           trusted_inventory_run.include?('test -s "${RUNNER_TEMP}/vifty-trusted-release-tools.sha256"')
      errors << "sign-notarize trusted inventory must hash every tracked file from a clean exact-SHA worktree"
    end
    unless run_text.scan('shasum -a 256 -c "${RUNNER_TEMP}/vifty-trusted-release-tools.sha256"').length >= 4 &&
           run_text.scan('trusted_status="$(git status --porcelain=v1 --untracked-files=all)"').length >= 5 &&
           run_text.scan('test -z "${trusted_status}"').length >= 5
      errors << "sign-notarize must verify the clean trusted worktree and all tracked-file hashes around protected execution"
    end
    environment_step = steps.find { |step| step.is_a?(Hash) && step["name"] == "Verify release environment protection" }
    environment_run = environment_step.is_a?(Hash) ? environment_step["run"].to_s : ""
    environment_env = environment_step.is_a?(Hash) ? environment_step["env"] : nil
    trusted_environment_invocation = <<~'SHELL'.strip
      (
        cd "${TRUSTED_ROOT}"
        GH_TOKEN="${RELEASE_GH_TOKEN}" \
          "${TRUSTED_ROOT}/scripts/check-release-environment.sh" \
    SHELL
    unless environment_run.include?(trusted_environment_invocation)
      errors << "sign-notarize release-environment checker must execute from the exact trusted worktree"
    end
    unless environment_env == { "GH_TOKEN" => "${{ github.token }}" } &&
           environment_run.include?('VIFTY_WORKFLOW_CONTRACT_ROOT="${TRUSTED_ROOT}"') &&
           environment_run.include?('ruby "${TRUSTED_ROOT}/scripts/check-workflow-contract.rb"') &&
           environment_run.include?('cd "${TRUSTED_ROOT}"') &&
           environment_run.include?('"${TRUSTED_ROOT}/scripts/check-release-environment.sh"') &&
           environment_run.include?('--environment release') &&
           environment_run.include?('--branch main') &&
           environment_run.include?('--workflow-public') &&
           environment_run.include?('--expected-branch-sha "${GITHUB_SHA}"') &&
           environment_run.include?('--output "${RUNNER_TEMP}/vifty-release-environment-readback.json"') &&
           environment_run.include?('check-release-environment.sh') &&
           run_text.include?("scripts/check-release-environment.sh")
      errors << "sign-notarize must validate exact trusted github.sha tooling and fail closed on public release-governance readback before secret-consuming steps"
    end
    unless run_text.include?('scripts/release-candidate-inventory.rb" extract') &&
           run_text.include?('--handoff-dir "${INPUT_DIR}"') &&
           run_text.include?('--extract-to "${EXTRACT_DIR}"') &&
           run_text.include?('scripts/release-candidate-inventory.rb" verify-tree') &&
           run_text.include?('--inventory "${GITHUB_WORKSPACE}/.build/release-input/candidate-inventory.json"') &&
           !run_text.include?("candidate-files.sha256") &&
           !run_text.include?("ditto -x -k")
      errors << "sign-notarize must safely extract and verify the complete trusted candidate inventory before secrets and signing"
    end
    candidate_download = steps.find { |step| step.is_a?(Hash) && step["name"] == "Download inventoried candidate" }
    candidate_download_with = candidate_download.is_a?(Hash) ? candidate_download["with"] : nil
    unless candidate_download_with.is_a?(Hash) &&
           candidate_download_with["name"] == "vifty-candidate-${{ github.run_id }}"
      errors << "candidate artifact consumer must use the same rerun-stable run ID handoff name"
    end
    errors << "sign-notarize must rerun trusted github.sha provenance before secret-consuming steps" unless run_text.include?('"${TRUSTED_ROOT}/scripts/check-release-provenance.sh"') && run_text.include?('--trusted-workflow-ref "${GITHUB_SHA}"') && run_text.include?('--allowed-signers "${TRUSTED_ROOT}/.github/release-signers.allowed"')
    candidate_verification = steps.find do |step|
      step.is_a?(Hash) && step["name"] == "Verify candidate and trusted tool inventories before secret-consuming steps"
    end
    candidate_verification_run = candidate_verification.is_a?(Hash) ? candidate_verification["run"].to_s : ""
    prep_diff_index = candidate_verification_run.index('"${TRUSTED_ROOT}/scripts/check-release-prep-diff.sh"')
    manifest_check_index = candidate_verification_run.index('bash "${TRUSTED_ROOT}/scripts/check-release-manifest.sh"')
    unless prep_diff_index && manifest_check_index && prep_diff_index < manifest_check_index &&
           candidate_verification_run.include?('--root "${TRUSTED_ROOT}"') &&
           candidate_verification_run.include?('--commit "${GITHUB_SHA}"')
      errors << "sign-notarize must independently enforce the exact protected release-prep diff before manifest and provenance checks"
    end
    unless run_text.scan("--require-current-governance-freshness").empty?
      errors << "sign-notarize must consume the hashed fresh-admission record without extending the 15-minute preflight window through signing and notarization"
    end
    errors << "sign-notarize must use the trusted signing script" unless run_text.include?('bash "${TRUSTED_ROOT}/scripts/sign-release-candidate.sh"')
    errors << "sign-notarize must use the trusted artifact verifier" unless run_text.include?('bash "${TRUSTED_ROOT}/scripts/verify-release-artifact.sh"')
    unless run_text.include?('bash "${TRUSTED_ROOT}/scripts/check-release-manifest.sh"') &&
           run_text.include?('load File.expand_path("../scripts/lib/release_artifact_contract.rb", File.dirname(manifest_path))') &&
           run_text.include?('VIFTY_RELEASE_MANIFEST_BASE_REF="${GITHUB_SHA}^"') &&
           run_text.include?("VIFTY_REQUIRE_RELEASE_MANIFEST_BASE=1")
      errors << "sign-notarize trusted inventory and invocations must preserve trusted base release-manifest continuity and the canonical artifact contract"
    end
    errors << "sign-notarize must not execute candidate-supplied release scripts" if run_text.include?("release-tools/scripts") || run_text.match?(/bash\s+[^\n]*release-input/)
    errors << "sign-notarize must bind codesign to the temporary keychain" unless run_text.include?('--keychain "${KEYCHAIN_PATH}"')
    unless run_text.include?("release-publication-contract.json") &&
           run_text.include?('product.fetch("architectures")') &&
           run_text.include?('policy.fetch("developerTeamID")') &&
           run_text.include?("sha_resolution = ViftyReleaseArtifactContract.resolve_expected_sha(") &&
           run_text.include?('current_sha: candidate["sha256"]') &&
           run_text.include?('tagged_sha: tagged_candidate["sha256"]') &&
           run_text.include?("tagged_snapshot = ViftyReleaseArtifactContract.tagged_manifest_snapshot(") &&
           run_text.include?('"releaseManifestSHA256" => Digest::SHA256.hexdigest(tagged_manifest_bytes)') &&
           run_text.include?('candidate[field] == tagged_candidate[field]') &&
           run_text.include?('"expectedSHASource" => sha_resolution.fetch(:source)')
      errors << "sign-notarize must emit a manifest-derived publication contract with the resolved candidate SHA source"
    end
    unless run_text.include?('ENVIRONMENT_EVIDENCE_PATH="${OUTPUT_DIR}/release-environment-readback.json"') &&
           run_text.include?('cp "${ENVIRONMENT_EVIDENCE_SOURCE}" "${ENVIRONMENT_EVIDENCE_PATH}"') &&
           run_text.include?('"releaseEnvironmentEvidence" => {') &&
           run_text.include?('"sha256" => Digest::SHA256.file(environment_path).hexdigest') &&
           run_text.include?('environment_evidence["schemaVersion"] == 5') &&
           run_text.include?('environment_evidence["releaseAuthorized"] == true') &&
           run_text.include?('environment_evidence["dataSource"] == "github-api-live"') &&
           run_text.include?('environment_evidence["evidenceScope"] == "workflow-public"') &&
           run_text.include?('environment_evidence["privilegedSettingsVerified"] == false') &&
           run_text.include?('environment_evidence["releaseGovernanceMode"] == "solo-maintainer"') &&
           run_text.include?('environment_evidence["requiredReviewerGate"] == false') &&
           run_text.include?('"protected_branches" => false') &&
           run_text.include?('"custom_branch_policies" => true') &&
           run_text.include?('environment_evidence["releaseTagDeploymentPolicy"] == expected_release_tag_deployment_policy') &&
           run_text.include?('environment_evidence["requiredBranchProtection"] == expected_public_branch_protection')
      errors << "sign-notarize must retain and cryptographically bind the honest public-scope release-environment readback"
    end
    unless run_text.include?('GOVERNANCE_EVIDENCE_PATH="${OUTPUT_DIR}/administrator-governance-evidence.json"') &&
           run_text.include?('--governance-evidence-output "${GOVERNANCE_EVIDENCE_PATH}"') &&
           run_text.include?('provenance["administratorGovernanceEvidence"] == governance_evidence') &&
           run_text.include?('governance_validation["evidenceAgeSeconds"].between?(0, 900)') &&
           run_text.include?('governance_validation["rulesetUpdatedAt"].is_a?(String)') &&
           run_text.include?('governance_validation["currentUserCanBypass"] == "never"') &&
           run_text.include?('governance_validation["evidenceSHA256"] == governance_sha') &&
           run_text.include?('governance_evidence["evidenceScope"] == "administrator-pretag"') &&
           run_text.include?('governance_evidence.dig("releaseEnvironmentEvidence", "requiredBranchCommitSHA") == provenance["tagCommitSHA"]') &&
           run_text.include?('governance_evidence.dig("tagRulesetEvidence", "rulesetUpdatedAt") == governance_validation["rulesetUpdatedAt"]') &&
           run_text.include?('governance_evidence.dig("tagRulesetEvidence", "currentUserCanBypass") == "never"') &&
           run_text.include?('governance_evidence.dig("releaseSecrets", "environmentShadowNames") == []') &&
           run_text.include?('"administratorGovernanceVerified" => true') &&
           run_text.include?('"administratorGovernanceEvidence" => {')
      errors << "sign-notarize must preserve, validate, and cryptographically bind exact signed administrator-pretag evidence"
    end
    unless run_text.include?('ADMISSION_PROVENANCE_PATH="${OUTPUT_DIR}/release-admission-provenance.json"') &&
           run_text.include?('admission["schemaVersion"] == 3') &&
           run_text.include?('admission["dataSource"] == "github-api-live"') &&
           run_text.include?('admission["liveRemoteTagReadback"] == true') &&
           run_text.include?('admission["liveSourceCIReadback"] == true') &&
           run_text.include?('admission_validation["currentFreshnessVerified"] == true') &&
           run_text.include?('admission_validation["currentEvidenceAgeSeconds"].between?(0, 900)') &&
           run_text.include?('admission_validation["evidenceSHA256"] == governance_sha') &&
           run_text.include?('"releaseAdmissionProvenance" => {')
      errors << "sign-notarize must bind the hashed current-fresh admission provenance into the publication contract"
    end
    asset_step = steps.find { |step| step.is_a?(Hash) && step["name"] == "Create and verify release assets with trusted tools" }
    asset_run = asset_step.is_a?(Hash) ? asset_step["run"].to_s : ""
    unless asset_run.include?('CANDIDATE_APP=".build/release-candidate/Vifty.app"') &&
           asset_run.include?('"${CANDIDATE_APP}" "${ZIP_PATH}"')
      errors << "release asset creation must define and package the verified candidate app in the same shell step"
    end
    release_upload = steps.find { |step| step.is_a?(Hash) && step["name"] == "Upload verified release assets for publication" }
    release_upload_with = release_upload.is_a?(Hash) ? release_upload["with"] : nil
    unless release_upload_with.is_a?(Hash) &&
           release_upload_with["name"] == "vifty-release-${{ github.run_id }}" &&
           release_upload_with["path"] == ".build/release-output" &&
           release_upload_with["if-no-files-found"] == "error" &&
           release_upload_with["retention-days"] == 90 &&
           release_upload_with["overwrite"] == true
      errors << "verified release workflow evidence must retain the complete protected handoff for 90 days"
    end
    unless run_text.scan('"${TRUSTED_ROOT}/scripts/check-release-provenance.sh"').length >= 2 &&
           run_text.include?('PROVENANCE_PATH="${RUNNER_TEMP}/vifty-release-provenance-final.json"') &&
           run_text.include?('"tagObjectSHA" => provenance.fetch("tagObjectSHA")') &&
           run_text.include?('"tagCommitSHA" => provenance.fetch("tagCommitSHA")') &&
           run_text.include?('"tagSignatureVerified" => true') &&
           run_text.include?('"publicTagRuleCoverageVerified" => true') &&
           run_text.include?("write_public_tag_rule_coverage_evidence()") &&
           run_text.include?('write_public_tag_rule_coverage_evidence "${SIGNED_RULESET_ID}"') &&
           run_text.include?('ruleset_evidence["rulesetID"] == governance_validation["rulesetID"]') &&
           run_text.include?('ruleset_evidence["rulesetUpdatedAt"] == governance_validation["rulesetUpdatedAt"]') &&
           run_text.include?('ruleset_evidence["currentUserCanBypass"] == "never"') &&
           run_text.include?('live_updated_at = Time.iso8601(raw_updated_at).utc.iso8601(9)') &&
           run_text.include?('live_updated_at == expected_updated_at') &&
           run_text.include?('ruleset["current_user_can_bypass"] == "never"') &&
           run_text.include?('"bypassActorsVerified" => false') &&
           run_text.include?('full_ref = "refs/tags/#{tag}"') &&
           run_text.include?('includes == ["refs/tags/v*"]') &&
           run_text.include?('excludes == []') &&
           !run_text.include?('FNM_EXTGLOB') &&
           run_text.include?('rule_types.include?("update") && rule_types.include?("deletion")') &&
           run_text.include?('"updateRulePresent" => true') &&
           run_text.include?('"deletionRulePresent" => true') &&
           !run_text.include?('"preventsUpdate"') &&
           !run_text.include?('"preventsDeletion"') &&
           run_text.include?('"protectedTagRulesetEvidence" => ruleset_evidence') &&
           run_text.include?('ruleset_evidence["publicRuleCoverageVerified"] == true')
      errors << "sign-notarize must bind final annotated-tag identity and honest public update/deletion ruleset evidence into the publication contract"
    end
    unless run_text.scan("/usr/bin/curl --disable").length == 2 &&
           run_text.scan("https://api.github.com/repos/${GITHUB_REPOSITORY}/rulesets").length == 2 &&
           !run_text.include?('${GITHUB_API_URL}') &&
           run_text.scan("builtin printf 'Authorization: Bearer %s").length == 2 &&
           run_text.scan('--header @-').length == 2 &&
           !run_text.include?('-H "Authorization: Bearer') &&
           run_text.include?('RELEASE_GH_TOKEN="${GH_TOKEN:?}"') &&
           run_text.include?('unset GH_TOKEN GITHUB_TOKEN') &&
           run_text.scan("-H 'Cache-Control: no-cache'").length >= 2 &&
           run_text.scan("-H 'Pragma: no-cache'").length >= 2
      errors << "sign-notarize public governance readbacks must pin api.github.com, disable ambient curl config, send authentication only on stdin, and bypass caches"
    end

    if import_index
      post_import_text = steps.drop(import_index + 1).map { |step| step.is_a?(Hash) ? step["run"] : nil }.compact.join("\n")
      %w[swift xcodebuild].each do |forbidden_command|
        errors << "sign-notarize must not run #{forbidden_command} after certificate import" if post_import_text.match?(/(^|\s)#{Regexp.escape(forbidden_command)}(\s|$)/)
      end
      errors << "sign-notarize must not run make after certificate import" if post_import_text.match?(/(^|\s)make(\s|$)/)
    end
  end

  if publish.is_a?(Hash)
    permissions = publish["permissions"]
    unless exact_permissions?(permissions, "write")
      errors << "publish permissions must be exactly {contents: write}"
    end
    expected_release_tag = "${{ github.ref_name }}"
    errors << "publish job environment must contain only RELEASE_TAG" unless publish["env"] == { "RELEASE_TAG" => expected_release_tag }
    allowed_job_keys = %w[name needs if runs-on timeout-minutes permissions env steps]
    unexpected_job_keys = publish.keys - allowed_job_keys
    errors << "publish contains unreviewed job fields: #{unexpected_job_keys.sort.join(', ')}" unless unexpected_job_keys.empty?
    errors << "publish must refuse workflow reruns" unless publish["if"] == "${{ github.run_attempt == 1 }}"
    needs = Array(publish["needs"])
    errors << "publish must depend on sign-notarize" unless needs.include?("sign-notarize")
    steps = Array(publish["steps"])
    expected_step_hashes = {
      "Download verified release assets" => "2efd54639fbb126e0ce7aa6fcb477987a276e7b0a98d6ecfb745a1b25df99dc8",
      "Recheck downloaded asset identity" => "aa5a51382d16e1ad1b73abec06a173c75673c05b43bad9ccf55e664aa7573c00",
      "Publish GitHub release" => "6cfcb858c1f9e062754cd855400f815626db74295c828e4ec5fdfd5c977570ae"
    }
    names = steps.map { |step| step.is_a?(Hash) ? step["name"] : nil }
    errors << "publish step set must match the reviewed allowlist exactly" unless names == expected_step_hashes.keys
    expected_step_hashes.each do |step_name, expected_hash|
      step = steps.find { |candidate| candidate.is_a?(Hash) && candidate["name"] == step_name }
      actual_hash = step ? normalized_step_hash(step) : nil
      unless actual_hash == expected_hash
        errors << "publish step #{step_name.inspect} must match its reviewed normalized step mapping hash"
      end
    end
    steps.each do |step|
      next unless step.is_a?(Hash) && step["uses"].to_s.start_with?("actions/checkout@")
      errors << "publish job must not check out repository credentials"
    end
    release_download = steps.find { |step| step.is_a?(Hash) && step["name"] == "Download verified release assets" }
    release_download_with = release_download.is_a?(Hash) ? release_download["with"] : nil
    unless release_download_with.is_a?(Hash) &&
           release_download_with["name"] == "vifty-release-${{ github.run_id }}"
      errors << "release artifact consumer must use the same rerun-stable run ID handoff name"
    end
    publish_run_text = steps.map { |step| step.is_a?(Hash) ? step["run"] : nil }.compact.join("\n")
    errors << "publish must consume the protected manifest-derived publication contract" unless publish_run_text.include?("release-publication-contract.json") && publish_run_text.include?('contract.fetch("runtimeIdentifiers")') && publish_run_text.include?('contract.fetch("architectures")') && publish_run_text.include?('contract.fetch("teamID")') && publish_run_text.include?('data["expectedSHASource"] == contract.fetch("expectedSHASource")')
    unless publish_run_text.include?('contract["releaseTag"] == ARGV.fetch(8)') &&
           publish_run_text.include?('contract["tagObjectSHA"].to_s.match?(oid)') &&
           publish_run_text.include?('contract["tagCommitSHA"].to_s.match?(oid)') &&
           publish_run_text.include?('contract["publicTagRuleCoverageVerified"] == true') &&
           publish_run_text.include?('ruleset_evidence = contract["protectedTagRulesetEvidence"]') &&
           publish_run_text.include?('ruleset_evidence["repository"] == ARGV.fetch(9)') &&
           publish_run_text.include?('ruleset_evidence["rulesetUpdatedAt"] == governance_validation["rulesetUpdatedAt"]') &&
           publish_run_text.include?('ruleset_evidence["currentUserCanBypass"] == "never"') &&
           publish_run_text.include?('PROTECTED_TAG_RULESET_ID=#{contract.fetch("protectedTagRulesetEvidence").fetch("rulesetID")}') &&
           publish_run_text.include?('PROTECTED_TAG_RULESET_UPDATED_AT=#{contract.fetch("protectedTagRulesetEvidence").fetch("rulesetUpdatedAt")}')
      errors << "publish must consume exact tag identity plus semantic ruleset evidence from the protected publication contract"
    end
    unless publish_run_text.include?('ENVIRONMENT_EVIDENCE_PATH=".build/release-assets/release-environment-readback.json"') &&
           publish_run_text.include?('environment_contract = contract["releaseEnvironmentEvidence"]') &&
           publish_run_text.include?('abort("environment evidence SHA-256 mismatch")') &&
           publish_run_text.include?('environment_evidence["schemaVersion"] == 5') &&
           publish_run_text.include?('environment_evidence["releaseAuthorized"] == true') &&
           publish_run_text.include?('environment_evidence["dataSource"] == "github-api-live"') &&
           publish_run_text.include?('environment_evidence["releaseGovernanceMode"] == "solo-maintainer"') &&
           publish_run_text.include?('environment_evidence["requiredReviewerGate"] == false') &&
           publish_run_text.include?('environment_evidence["evidenceScope"] == "workflow-public"') &&
           publish_run_text.include?('environment_evidence["privilegedSettingsVerified"] == false') &&
           publish_run_text.include?('"requiredTagPattern" => "v*"') &&
           publish_run_text.include?('"policies" => [{"type" => "tag", "name" => "v*"}]') &&
           publish_run_text.include?('environment_evidence["requiredBranchProtection"] == expected_public_branch_protection') &&
           publish_run_text.include?("environment_valid &&")
      errors << "publish must re-read and validate retained public-scope release-governance evidence"
    end
    unless publish_run_text.include?('GOVERNANCE_EVIDENCE_PATH=".build/release-assets/administrator-governance-evidence.json"') &&
           publish_run_text.include?('governance_contract = contract["administratorGovernanceEvidence"]') &&
           publish_run_text.include?('governance_contract["sha256"] == governance_sha') &&
           publish_run_text.include?('governance_validation["evidenceAgeSeconds"].between?(0, 900)') &&
           publish_run_text.include?('governance_validation["rulesetUpdatedAt"].is_a?(String)') &&
           publish_run_text.include?('governance_validation["currentUserCanBypass"] == "never"') &&
           publish_run_text.include?('governance_evidence["evidenceScope"] == "administrator-pretag"') &&
           publish_run_text.include?('governance_evidence.dig("releaseEnvironmentEvidence", "requiredBranchCommitSHA") == contract["tagCommitSHA"]') &&
           publish_run_text.include?('governance_evidence.dig("releaseSecrets", "environmentShadowNames") == []') &&
           publish_run_text.include?('contract["administratorGovernanceVerified"] == true') &&
           publish_run_text.include?("governance_valid &&")
      errors << "publish must re-read exact signed administrator governance evidence and enforce its digest, tagger-time, commit, and anti-shadow binding"
    end
    unless publish_run_text.include?('ADMISSION_PROVENANCE_PATH=".build/release-assets/release-admission-provenance.json"') &&
           publish_run_text.include?('admission_contract = contract["releaseAdmissionProvenance"]') &&
           publish_run_text.include?('admission_validation["currentFreshnessVerified"] == true') &&
           publish_run_text.include?('admission_validation["currentEvidenceAgeSeconds"].between?(0, 900)') &&
           publish_run_text.include?('admission_contract["sha256"] == admission_sha') &&
           publish_run_text.include?('admission["schemaVersion"] == 3') &&
           publish_run_text.include?('admission["dataSource"] == "github-api-live"') &&
           publish_run_text.include?('admission["liveRemoteTagReadback"] == true') &&
           publish_run_text.include?('admission["liveSourceCIReadback"] == true') &&
           publish_run_text.include?("admission_valid &&")
      errors << "publish must re-read and validate the current-fresh release-admission provenance"
    end
    unless publish_run_text.include?('data["releaseTag"] == contract.fetch("releaseTag")') &&
           publish_run_text.include?('data["releaseSourceCommit"] == contract.fetch("tagCommitSHA")') &&
           publish_run_text.include?('data["releaseManifestEntryKind"] == "candidate"') &&
           publish_run_text.include?('data["releaseManifestSHA256"] == contract.fetch("releaseManifestSHA256")') &&
           publish_run_text.include?('contract["releaseSourceCommit"] == contract["tagCommitSHA"]') &&
           publish_run_text.include?('contract["releaseManifestEntryKind"] == "candidate"')
      errors << "publish must bind verifier summary tag/source/kind/manifest to peeled pushed-tag contract"
    end
    unless publish_run_text.include?("verify_immutable_tag_ruleset()") &&
           publish_run_text.scan("verify_immutable_tag_ruleset").length >= 4 &&
           !publish_run_text.include?('ruleset["bypass_actors"]') &&
           publish_run_text.include?('live_updated_at = Time.iso8601(raw_updated_at).utc.iso8601(9)') &&
           publish_run_text.include?('live_updated_at == expected_updated_at') &&
           publish_run_text.include?('ruleset["current_user_can_bypass"] == "never"') &&
           publish_run_text.include?('full_ref = "refs/tags/#{tag}"') &&
           publish_run_text.include?('includes == ["refs/tags/v*"]') &&
           publish_run_text.include?('excludes == []') &&
           !publish_run_text.include?('FNM_EXTGLOB') &&
           publish_run_text.include?('rule_types.include?("update") && rule_types.include?("deletion")') &&
           publish_run_text.include?('RULESET_ID="$(verify_immutable_tag_ruleset "${PROTECTED_TAG_RULESET_ID}" "${PROTECTED_TAG_RULESET_UPDATED_AT}")"') &&
           publish_run_text.scan('verify_immutable_tag_ruleset "${RULESET_ID}" "${PROTECTED_TAG_RULESET_UPDATED_AT}"').length >= 2
      errors << "publish must verify stable public update/deletion tag-rule coverage before and after promotion"
    end
    unless publish_run_text.scan("/usr/bin/curl --disable").length == 4 &&
           publish_run_text.scan("https://api.github.com/repos/${GITHUB_REPOSITORY}/rulesets").length == 2 &&
           publish_run_text.include?('https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}/assets?${query}') &&
           !publish_run_text.include?('${GITHUB_API_URL}') &&
           publish_run_text.scan("builtin printf 'Authorization: Bearer %s").length == 4 &&
           publish_run_text.scan('--header @-').length == 4 &&
           !publish_run_text.include?('-H "Authorization: Bearer') &&
           !publish_run_text.include?('--config "${UPLOAD_AUTH_CONFIG}"') &&
           publish_run_text.include?('RELEASE_GH_TOKEN="${GH_TOKEN:?}"') &&
           publish_run_text.include?('unset GH_TOKEN GITHUB_TOKEN') &&
           publish_run_text.include?('GH_TOKEN="${RELEASE_GH_TOKEN}" gh "$@"') &&
           publish_run_text.scan("-H 'Cache-Control: no-cache'").length >= 2 &&
           publish_run_text.scan("-H 'Pragma: no-cache'").length >= 2
      errors << "publish network calls must pin GitHub API hosts, disable ambient curl config, scope gh authentication, send curl authentication only on stdin, and bypass caches"
    end
    unless publish_run_text.include?("verify_remote_tag_identity()") &&
           publish_run_text.scan('verify_remote_tag_identity "${TAG_OBJECT_SHA}" "${TAG_COMMIT_SHA}"').length >= 3 &&
           publish_run_text.include?('CREATE_NONCE="$(/usr/bin/openssl rand -hex 32)"') &&
           publish_run_text.include?('RELEASE_MARKER="<!-- vifty-release-owner:${GITHUB_RUN_ID}:${GITHUB_RUN_ATTEMPT}:${CREATE_NONCE} -->"') &&
           publish_run_text.include?('gh api --hostname github.com --method POST') &&
           publish_run_text.include?('"repos/${GITHUB_REPOSITORY}/releases"') &&
           publish_run_text.include?('--input "${CREATE_PAYLOAD}" > "${CREATE_RESPONSE}"') &&
           publish_run_text.include?('body.b.start_with?(submitted_body.b)') &&
           publish_run_text.include?('release["prerelease"] == false') &&
           publish_run_text.include?('RELEASE_ID="$(capture_owned_draft_release_id "${CREATE_RESPONSE}")"') &&
           publish_run_text.include?('wait_for_release_state_by_id "${PUBLISHED_STATE}" "${RELEASE_ID}" false "${FINAL_TITLE}"') &&
           publish_run_text.include?('"repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}"') &&
           publish_run_text.include?('-F draft=false') &&
           publish_run_text.include?('-F prerelease=false') &&
           !publish_run_text.match?(/gh release (?:create|edit|upload|delete)/)
      errors << "publish must REST-create the marked draft, capture its immutable ID directly, and forbid tag-based release mutation"
    end
    errors << "publish must pin every GitHub CLI API call to github.com" if publish_run_text.scan(/gh api(?! --hostname github\.com)/).any?
    unless publish_run_text.include?("upload_release_asset_by_id()") &&
           publish_run_text.include?('https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}/assets?${query}') &&
           publish_run_text.scan('upload_release_asset_by_id "${').length == 4 &&
           publish_run_text.include?('wait_for_release_state_by_id "${upload_state}" "${RELEASE_ID}" true "${DRAFT_TITLE}"') &&
           publish_run_text.include?('verify_release_state "${upload_state}" "${RELEASE_ID}" true "${DRAFT_TITLE}"')
      errors << "publish must upload every asset through the captured release ID and query ID-bound state after each upload"
    end
    convergence_start = publish_run_text.index("query_release_by_id_for_convergence()")
    convergence_end = publish_run_text.index("verify_release_owned_for_containment()")
    convergence_text = if convergence_start && convergence_end && convergence_start < convergence_end
                         publish_run_text[convergence_start...convergence_end]
                       else
                         ""
                       end
    unless publish_run_text.include?("wait_for_release_state_by_id()") &&
           publish_run_text.scan('wait_for_release_state_by_id "${').length == 3 &&
           convergence_text.include?('local deadline=$((SECONDS + 60))') &&
           convergence_text.include?('404|429|5??)') &&
           convergence_text.include?('/bin/sleep 2') &&
           convergence_text.include?('verify_release_convergence_identity') &&
           convergence_text.include?('release["id"] == Integer(ARGV.fetch(1), 10)') &&
           convergence_text.include?('release["tag_name"] == ARGV.fetch(2)') &&
           convergence_text.include?('body.scan(Regexp.escape(marker)).length == 1') &&
           !convergence_text.include?('--method POST') &&
           !convergence_text.include?('--method PATCH') &&
           !convergence_text.include?('--request POST') &&
           publish_run_text.scan('release_gh api --hostname github.com --method POST').length == 1 &&
           publish_run_text.scan('release_gh api --hostname github.com --method PATCH').length == 2 &&
           publish_run_text.scan('--request POST').length == 1
      errors << "publish must use bounded GET-only immutable-ID convergence polling after create, upload, and promotion without retrying mutations"
    end
    unless publish_run_text.include?('response["state"] == "uploaded" && response["digest"] == digest') &&
           publish_run_text.include?('"id" => id') &&
           publish_run_text.include?('"size" => size') &&
           publish_run_text.include?('release["body"].b == expected_body') &&
           publish_run_text.include?('PREPROMOTION_STATE="${RUNNER_TEMP}/vifty-release-prepromotion-state.json"') &&
           publish_run_text.include?('verify_release_state "${PREPROMOTION_STATE}"') &&
           publish_run_text.include?('verify_release_state "${PUBLISHED_STATE}"')
      errors << "publish must bind exact returned body plus immutable asset IDs, sizes, states, and digests through promotion readback"
    end
    unless publish_run_text.include?("discover_owned_draft_by_tag()") &&
           publish_run_text.include?("capture_owned_draft_release_id()") &&
           publish_run_text.include?('body.scan(Regexp.escape(marker)).length == 1') &&
           publish_run_text.include?('release["name"] == ARGV.fetch(2)') &&
           publish_run_text.include?('Array(release["assets"]).empty?') &&
           publish_run_text.include?('verify_release_owned_for_containment "${ownership_state}" "${RELEASE_ID}"') &&
           publish_run_text.include?("no mutation was attempted")
      errors << "publish may discover an ambiguous draft by tag only with exact immutable-ID/tag/draft/title/marker ownership proof"
    end
    unless publish_run_text.include?("contain_release_by_id()") &&
           publish_run_text.include?("verify_release_contained()") &&
           publish_run_text.include?("wait_for_release_contained_by_id()") &&
           publish_run_text.include?("CONTAINMENT_REQUIRED=1") &&
           publish_run_text.include?("trap containment_guard EXIT") &&
           publish_run_text.include?("trap 'exit 130' INT") &&
           publish_run_text.include?("trap 'exit 143' TERM") &&
           publish_run_text.include?("trap - EXIT") &&
           publish_run_text.include?("trap '' INT TERM") &&
           !publish_run_text.include?("UPLOAD_AUTH_CONFIG") &&
           publish_run_text.include?('-F draft=true') &&
           publish_run_text.include?('wait_for_release_contained_by_id "${containment_state}" "${RELEASE_ID}"') &&
           publish_run_text.include?("exit 97") &&
           !publish_run_text.include?("|| true")
      errors << "publish must re-draft by immutable release ID on every ambiguous failure and hard-fail unless containment readback succeeds"
    end
    containment_wait_start = publish_run_text.index("wait_for_release_contained_by_id()")
    containment_wait_end = publish_run_text.index("upload_release_asset_by_id()")
    containment_wait_text = if containment_wait_start && containment_wait_end && containment_wait_start < containment_wait_end
                              publish_run_text[containment_wait_start...containment_wait_end]
                            else
                              ""
                            end
    unless containment_wait_text.include?('local containment_deadline=$((SECONDS + 60))') &&
           containment_wait_text.include?('query_release_by_id_for_convergence "${release_id}" "${destination}"') &&
           containment_wait_text.include?('verify_release_owned_for_containment "${destination}" "${release_id}"') &&
           containment_wait_text.include?('verify_release_contained "${destination}" "${release_id}"') &&
           containment_wait_text.include?('/bin/sleep 2') &&
           !containment_wait_text.include?('--method POST') &&
           !containment_wait_text.include?('--method PATCH') &&
           !containment_wait_text.include?('--request POST')
      errors << "publish containment must use bounded GET-only immutable-ID ownership polling without requiring expected body or asset files"
    end
    %w[tech.reidar.vifty X88J3853S2].each do |literal|
      errors << "publish must not hardcode manifest identity literal #{literal}" if publish_run_text.include?(literal)
    end
    errors << "publish must not hardcode the manifest architecture" if publish_run_text.match?(/\barm64\b/)
  end

  jobs.each do |job_name, job|
    next unless job.is_a?(Hash)
    permissions = job["permissions"]
    next unless permissions.is_a?(Hash) && permissions["contents"] == "write"
    errors << "only publish job may receive contents: write (found #{job_name})" unless job_name == "publish"
  end
end

unless errors.empty?
  errors.each { |error| warn "error: #{error}" }
  exit 1
end

puts "Workflow contract OK: exact secret-reference allowlists, immutable action pins, first-attempt signed-tag push admission, custom tag-only release-environment admission, signed administrator-pretag governance evidence, honest authenticated public readback, exact tag/release-ID binding, same-ID update/deletion rule coverage, hard draft containment, durable tag retirement, trusted tooling, and isolated publication"
