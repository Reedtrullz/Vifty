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
    "run-name" => "Release ${{ inputs.tag }}",
    "concurrency" => {
      "group" => "${{ github.workflow }}-${{ inputs.tag }}",
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
    errors << ".github/workflows/#{workflow_name} run-name must bind the exact dispatch tag input" unless workflow["run-name"] == expected.fetch("run-name")
  end
  errors << ".github/workflows/#{workflow_name} concurrency must match the reviewed mapping" unless workflow["concurrency"] == expected.fetch("concurrency")
  jobs = workflow["jobs"]
  unless jobs.is_a?(Hash) && jobs.keys == expected.fetch("jobs")
    errors << ".github/workflows/#{workflow_name} jobs must be exactly #{expected.fetch("jobs").join(', ')}"
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
  errors << "workflow secret context references must match the reviewed sign-notarize release-environment bindings exactly"
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

release_secret_checker_path = File.join(root, "scripts/check-release-secrets.sh")
if !File.file?(release_secret_checker_path)
  errors << "scripts/check-release-secrets.sh is required"
else
  release_secret_checker_text = File.read(release_secret_checker_path)
  unless release_secret_checker_text.include?('ENVIRONMENT_NAME="release"') &&
         release_secret_checker_text.include?('gh secret list --env "${ENVIRONMENT_NAME}" --repo "${REPO}"')
    errors << "release-secret operator preflight must default to the release environment and list environment secret names"
  end
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
  unless trigger.is_a?(Hash) && trigger.keys == ["workflow_dispatch"] && trigger.dig("workflow_dispatch", "inputs", "tag", "required") == true
    errors << "release workflow must be main-only workflow_dispatch with a required tag input and no tag-push trigger"
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
    unless exact_permissions?(permissions, "read")
      errors << "prepare-candidate permissions must be exactly {contents: read}"
    end
    prepare_text = prepare.to_s
    errors << "prepare-candidate must not receive repository secrets" if prepare_text.include?("secrets.")
    steps = Array(prepare["steps"])
    names = steps.map { |step| step.is_a?(Hash) ? step["name"] : nil }
    context_index = names.index("Require protected default-branch workflow context")
    provenance_index = names.index("Verify remote ancestry and exact-commit CI provenance")
    test_index = names.index("Run full read-only build and test gate")
    build_index = names.index("Assemble ad-hoc candidate with release TeamID policy")
    inventory_index = names.index("Inventory unsigned candidate")
    upload_index = names.index("Upload hash-inventoried unsigned candidate")
    unless [context_index, provenance_index, test_index, build_index, inventory_index, upload_index].all? &&
           context_index < provenance_index && provenance_index < test_index && test_index < build_index && build_index < inventory_index && inventory_index < upload_index
      errors << "prepare-candidate must require main dispatch, prove provenance, test, build, inventory, then upload in order"
    end
    run_text = steps.map { |step| step.is_a?(Hash) ? step["run"] : nil }.compact.join("\n")
    errors << "prepare-candidate must fail closed outside workflow_dispatch on refs/heads/main" unless run_text.include?('test "${GITHUB_EVENT_NAME}" = "workflow_dispatch"') && run_text.include?('test "${GITHUB_REF}" = "refs/heads/main"')
    errors << "prepare-candidate must require a manifest candidate" unless run_text.include?("scripts/check-release-manifest.sh") && run_text.include?('--publication-version "${VERSION}"')
    unless run_text.include?('git fetch --no-tags origin "${GITHUB_SHA}"') &&
           run_text.include?('--base-ref "${GITHUB_SHA}^"') &&
           run_text.include?("--require-base")
      errors << "prepare-candidate must enforce trusted base release-manifest continuity from the exact workflow source first parent"
    end
    errors << "prepare-candidate must cryptographically verify the release tag against github.sha signer policy" unless run_text.include?('git show "${GITHUB_SHA}:.github/release-signers.allowed"') && run_text.include?('gpg.ssh.allowedSignersFile="${TRUSTED_SIGNERS}"') && run_text.include?('verify-tag "${RELEASE_TAG}"')
    errors << "prepare-candidate must verify remote ancestry and exact-main-CI provenance" unless run_text.include?("scripts/check-release-provenance.sh") && run_text.include?('--tag "${RELEASE_TAG}"') && run_text.include?('--main-ref "${GITHUB_SHA}"')
    errors << "prepare-candidate must run the full verification gate" unless run_text.include?('make verify-full SWIFT_BUILD_PATH="${SWIFT_BUILD_PATH}"')
    errors << "prepare-candidate must assemble only an ad-hoc candidate" unless run_text.include?('SIGNING_IDENTITY="-"')
    errors << "prepare-candidate must hash every candidate file" unless run_text.include?("candidate-files.sha256") && run_text.include?("find Vifty.app -type f")
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
    expected_release_tag = "${{ inputs.tag }}"
    errors << "sign-notarize job environment must contain only RELEASE_TAG" unless signed["env"] == { "RELEASE_TAG" => expected_release_tag }
    allowed_job_keys = %w[name needs runs-on timeout-minutes environment permissions env steps]
    unexpected_job_keys = signed.keys - allowed_job_keys
    errors << "sign-notarize contains unreviewed job fields: #{unexpected_job_keys.sort.join(', ')}" unless unexpected_job_keys.empty?
    needs = Array(signed["needs"])
    errors << "sign-notarize must depend on prepare-candidate" unless needs.include?("prepare-candidate")
    steps = Array(signed["steps"])
    names = steps.map { |step| step.is_a?(Hash) ? step["name"] : nil }
    expected_step_names = [
      "Check out trusted release tooling",
      "Inventory trusted release tooling",
      "Verify release environment protection",
      "Download inventoried candidate",
      "Verify candidate and trusted tool inventories before secrets",
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
      "Verify release environment protection" => "ee76c35de77f7b2db4ee538507822f434416acd76a3d1ed06dbc102e44fd549e",
      "Download inventoried candidate" => "3bdfc8684334de0c1da202537d972499fabb75390c7cb15b7f568b9e6b2064ad",
      "Verify candidate and trusted tool inventories before secrets" => "6e4a758101f2f0ea01a6d9d9a472a016eed9cc337bc31e6db615147dae6fe575",
      "Require signing and notarization secrets" => "e5421852d3202b04e2aa2ac167915e6806b53a64a257eb6322f60ebfb1e2d892",
      "Import Developer ID certificate" => "c1d39d72865189a04b4d529ee8ccda1abb42ddff304466d8abcbf45d3bea4147",
      "Revalidate trusted tooling and sign existing candidate" => "310fdc332e88c888824fd19af77771c74a02d2a3c9dad35b0b6665cb06c0e169",
      "Notarize signed candidate" => "9a43a0da7840c749fb8489bef3fcb3a8e3b208f529986437491ec53de59f17e8",
      "Create and verify release assets with trusted tools" => "cfb76881b3c7b8e28365ac5a115a19d28b2ad718dc42480de087684edb528d13",
      "Remove signing material" => "4df2d7fa1538a8e0017e92932873c0bf76dd6984e000ac1bfd9795c6263040c1",
      "Upload verified release assets for publication" => "9fc25f15a32dc4a05e7f24b441fb1dbb2b35b2b6052abf7aea87e920b45d9389"
    }
    expected_step_hashes.each do |step_name, expected_hash|
      step = steps.find { |candidate| candidate.is_a?(Hash) && candidate["name"] == step_name }
      actual_hash = step ? normalized_step_hash(step) : nil
      unless actual_hash == expected_hash
        errors << "sign-notarize step #{step_name.inspect} must match its reviewed normalized step mapping hash"
      end
    end
    environment_index = names.index("Verify release environment protection")
    verify_index = names.index("Verify candidate and trusted tool inventories before secrets")
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
    unless environment_env == { "GH_TOKEN" => "${{ github.token }}" } &&
           environment_run.include?('VIFTY_WORKFLOW_CONTRACT_ROOT="${TRUSTED_ROOT}"') &&
           environment_run.include?('ruby "${TRUSTED_ROOT}/scripts/check-workflow-contract.rb"') &&
           environment_run.include?('bash "${TRUSTED_ROOT}/scripts/check-release-environment.sh"') &&
           environment_run.include?('--environment release') &&
           environment_run.include?('--branch main') &&
           environment_run.include?('--output "${RUNNER_TEMP}/vifty-release-environment-readback.json"') &&
           run_text.include?("scripts/check-release-environment.sh")
      errors << "sign-notarize must validate the exact trusted github.sha workflow contract and fail closed on release-environment API readback before secrets"
    end
    errors << "sign-notarize must verify the candidate before signing" unless run_text.scan("shasum -a 256 -c candidate-files.sha256").length >= 2
    errors << "sign-notarize must rerun trusted github.sha provenance before secrets" unless run_text.include?('bash "${TRUSTED_ROOT}/scripts/check-release-provenance.sh"') && run_text.include?('--trusted-workflow-ref "${GITHUB_SHA}"') && run_text.include?('--allowed-signers "${TRUSTED_ROOT}/.github/release-signers.allowed"')
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
           run_text.include?('environment_evidence["teamReviewerEligibilityAssumed"] == false') &&
           run_text.include?('environment_evidence["requiredBranchProtection"] == expected_branch_protection')
      errors << "sign-notarize must retain and cryptographically bind the normalized strong release-environment readback"
    end
    release_upload = steps.find { |step| step.is_a?(Hash) && step["name"] == "Upload verified release assets for publication" }
    release_upload_with = release_upload.is_a?(Hash) ? release_upload["with"] : nil
    unless release_upload_with.is_a?(Hash) &&
           release_upload_with["path"] == ".build/release-output" &&
           release_upload_with["if-no-files-found"] == "error" &&
           release_upload_with["retention-days"] == 90
      errors << "verified release workflow evidence must retain the complete protected handoff for 90 days"
    end
    unless run_text.scan('bash "${TRUSTED_ROOT}/scripts/check-release-provenance.sh"').length >= 2 &&
           run_text.include?('PROVENANCE_PATH="${RUNNER_TEMP}/vifty-release-provenance-final.json"') &&
           run_text.include?('"tagObjectSHA" => provenance.fetch("tagObjectSHA")') &&
           run_text.include?('"tagCommitSHA" => provenance.fetch("tagCommitSHA")') &&
           run_text.include?('"tagSignatureVerified" => true') &&
           run_text.include?('"protectedTagEnforcementVerified" => true') &&
           run_text.include?("write_immutable_tag_ruleset_evidence()") &&
           run_text.include?('ruleset["bypass_actors"]') &&
           run_text.include?('full_ref = "refs/tags/#{tag}"') &&
           run_text.include?('File.fnmatch?(pattern, full_ref, flags)') &&
           !run_text.include?('File.fnmatch?(pattern, tag, flags)') &&
           run_text.include?('rule_types.include?("update") && rule_types.include?("deletion")') &&
           run_text.include?('"protectedTagRulesetEvidence" => ruleset_evidence') &&
           run_text.include?('ruleset_evidence["apiVisibilityComplete"] == true')
      errors << "sign-notarize must bind final verified annotated-tag object/commit identity and semantic no-bypass update/deletion ruleset evidence into the publication contract"
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
    expected_release_tag = "${{ inputs.tag }}"
    errors << "publish job environment must contain only RELEASE_TAG" unless publish["env"] == { "RELEASE_TAG" => expected_release_tag }
    allowed_job_keys = %w[name needs runs-on timeout-minutes permissions env steps]
    unexpected_job_keys = publish.keys - allowed_job_keys
    errors << "publish contains unreviewed job fields: #{unexpected_job_keys.sort.join(', ')}" unless unexpected_job_keys.empty?
    needs = Array(publish["needs"])
    errors << "publish must depend on sign-notarize" unless needs.include?("sign-notarize")
    steps = Array(publish["steps"])
    expected_step_hashes = {
      "Download verified release assets" => "d12953c395d73a5ed0a2e99b740f15b19dccab2906f4f74d5765508967875880",
      "Recheck downloaded asset identity" => "da835cdce39773e8bc136b585a426d44bbf9a07a7438cb99f199b6a930d15b53",
      "Publish GitHub release" => "0bd659022e31cbead804f0e394bf2c29d587858479742abf191c406231bdf4b5"
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
    publish_run_text = steps.map { |step| step.is_a?(Hash) ? step["run"] : nil }.compact.join("\n")
    errors << "publish must consume the protected manifest-derived publication contract" unless publish_run_text.include?("release-publication-contract.json") && publish_run_text.include?('contract.fetch("runtimeIdentifiers")') && publish_run_text.include?('contract.fetch("architectures")') && publish_run_text.include?('contract.fetch("teamID")') && publish_run_text.include?('data["expectedSHASource"] == contract.fetch("expectedSHASource")')
    unless publish_run_text.include?('contract["releaseTag"] == ARGV.fetch(8)') &&
           publish_run_text.include?('contract["tagObjectSHA"].to_s.match?(oid)') &&
           publish_run_text.include?('contract["tagCommitSHA"].to_s.match?(oid)') &&
           publish_run_text.include?('contract["protectedTagEnforcementVerified"] == true') &&
           publish_run_text.include?('ruleset_evidence = contract["protectedTagRulesetEvidence"]') &&
           publish_run_text.include?('ruleset_evidence["repository"] == ARGV.fetch(9)') &&
           publish_run_text.include?('PROTECTED_TAG_RULESET_ID=#{contract.fetch("protectedTagRulesetEvidence").fetch("rulesetID")}')
      errors << "publish must consume exact tag identity plus semantic ruleset evidence from the protected publication contract"
    end
    unless publish_run_text.include?('ENVIRONMENT_EVIDENCE_PATH=".build/release-assets/release-environment-readback.json"') &&
           publish_run_text.include?('environment_contract = contract["releaseEnvironmentEvidence"]') &&
           publish_run_text.include?('abort("environment evidence SHA-256 mismatch")') &&
           publish_run_text.include?('environment_evidence["requiredBranchProtection"] == expected_branch_protection') &&
           publish_run_text.include?("environment_valid &&")
      errors << "publish must re-read and validate the retained normalized release-environment evidence"
    end
    unless publish_run_text.include?('data["releaseTag"] == contract.fetch("releaseTag")') &&
           publish_run_text.include?('data["releaseSourceCommit"] == contract.fetch("tagCommitSHA")') &&
           publish_run_text.include?('data["releaseManifestEntryKind"] == "candidate"') &&
           publish_run_text.include?('data["releaseManifestSHA256"] == contract.fetch("releaseManifestSHA256")') &&
           publish_run_text.include?('contract["releaseSourceCommit"] == contract["tagCommitSHA"]') &&
           publish_run_text.include?('contract["releaseManifestEntryKind"] == "candidate"')
      errors << "publish must bind verifier summary tag/source/kind/manifest to peeled dispatch contract"
    end
    unless publish_run_text.include?("verify_immutable_tag_ruleset()") &&
           publish_run_text.scan("verify_immutable_tag_ruleset").length >= 4 &&
           publish_run_text.include?('ruleset["bypass_actors"].is_a?(Array) && ruleset["bypass_actors"].empty?') &&
           publish_run_text.include?('full_ref = "refs/tags/#{tag}"') &&
           publish_run_text.include?('File.fnmatch?(pattern, full_ref, flags)') &&
           !publish_run_text.include?('File.fnmatch?(pattern, tag, flags)') &&
           publish_run_text.include?('rule_types.include?("update") && rule_types.include?("deletion")') &&
           publish_run_text.include?('RULESET_ID="$(verify_immutable_tag_ruleset "${PROTECTED_TAG_RULESET_ID}")"') &&
           publish_run_text.scan('verify_immutable_tag_ruleset "${RULESET_ID}"').length >= 2
      errors << "publish must verify a stable active no-bypass tag ruleset that blocks update and deletion before and after promotion"
    end
    unless publish_run_text.include?("verify_remote_tag_identity()") &&
           publish_run_text.scan('verify_remote_tag_identity "${TAG_OBJECT_SHA}" "${TAG_COMMIT_SHA}"').length >= 3 &&
           publish_run_text.include?('CREATE_NONCE="$(/usr/bin/openssl rand -hex 32)"') &&
           publish_run_text.include?('RELEASE_MARKER="<!-- vifty-release-owner:${GITHUB_RUN_ID}:${GITHUB_RUN_ATTEMPT}:${CREATE_NONCE} -->"') &&
           publish_run_text.include?('gh api --method POST') &&
           publish_run_text.include?('"repos/${GITHUB_REPOSITORY}/releases"') &&
           publish_run_text.include?('--input "${CREATE_PAYLOAD}" > "${CREATE_RESPONSE}"') &&
           publish_run_text.include?('RELEASE_ID="$(capture_owned_draft_release_id "${CREATE_RESPONSE}")"') &&
           publish_run_text.include?('query_release_by_id "${RELEASE_ID}" "${PUBLISHED_STATE}"') &&
           publish_run_text.include?('"repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}"') &&
           publish_run_text.include?('-F draft=false') &&
           !publish_run_text.match?(/gh release (?:create|edit|upload|delete)/)
      errors << "publish must REST-create the marked draft, capture its immutable ID directly, and forbid tag-based release mutation"
    end
    unless publish_run_text.include?("upload_release_asset_by_id()") &&
           publish_run_text.include?('https://uploads.github.com/repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}/assets?${query}') &&
           publish_run_text.scan('upload_release_asset_by_id "${').length == 4 &&
           publish_run_text.include?('query_release_by_id "${RELEASE_ID}" "${upload_state}"') &&
           publish_run_text.include?('verify_release_state "${upload_state}" "${RELEASE_ID}" true "${DRAFT_TITLE}"')
      errors << "publish must upload every asset through the captured release ID and query ID-bound state after each upload"
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
           publish_run_text.include?("CONTAINMENT_REQUIRED=1") &&
           publish_run_text.include?("trap containment_guard EXIT") &&
           publish_run_text.include?("trap 'exit 130' INT") &&
           publish_run_text.include?("trap 'exit 143' TERM") &&
           publish_run_text.include?("trap - EXIT") &&
           publish_run_text.include?("trap '' INT TERM") &&
           publish_run_text.include?('rm -f "${UPLOAD_AUTH_CONFIG:-}"') &&
           publish_run_text.include?("temporary GitHub upload authentication material could not be removed") &&
           publish_run_text.include?('-F draft=true') &&
           publish_run_text.include?('query_release_by_id "${RELEASE_ID}" "${containment_state}"') &&
           publish_run_text.include?("exit 97") &&
           !publish_run_text.include?("|| true")
      errors << "publish must re-draft by immutable release ID on every ambiguous failure and hard-fail unless containment readback succeeds"
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

puts "Workflow contract OK: exact workflow/job secret-reference allowlists, immutable action pins, strongly protected-main dispatch, retained environment evidence, exact tag-object/commit and release-ID binding, verified immutable tag ruleset enforcement, hard draft containment, trusted tooling, and isolated publication"
