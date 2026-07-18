.PHONY: app package-bundled-schemas release-contract-ruby-tests installer-lifecycle-ruby-tests release-facts run-app install install-public-release install-dev-adhoc repair-helper uninstall-helper pkg validation-evidence validation-evidence-current-build validation-evidence-review manual-smoke-readiness manual-smoke-readiness-current-build agent-cooling-evidence agent-cooling-evidence-review agent-run-smoke-readiness agent-run-smoke-readiness-current-build agent-run-smoke-evidence agent-run-smoke-evidence-current-build ui-review-build-products ui-review-initialize-ledger ui-review-start-session ui-review-ruby-tests ui-review-verify-automated ui-review-write-checkpoint ui-review-verify source-first-release-notes unsigned-dev-artifact source-first-readiness clean-app clean-pkg test test-fast test-full verify verify-full help clean

CONFIGURATION ?= debug
SIGNING_IDENTITY ?= -
VIFTY_XPC_ALLOWED_TEAM_ID ?=
VIFTY_XPC_ADHOC_DEVELOPMENT ?= 0
VIFTY_XPC_ADHOC_ALLOWED_UID ?=
VIFTY_XPC_ADHOC_APP_PATH ?=
VIFTY_XPC_ADHOC_CTL_PATH ?=
VIFTY_XPC_ADHOC_HELPER_PATH ?=
SWIFT_BUILD_PATH ?=
SWIFT_BUILD_EXTRA_ARGS ?=
SWIFT_BUILD_PROVENANCE_FILE ?=
RELEASE_ARCHITECTURE ?= $(shell ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("product", "architectures").fetch(0)' .github/release-manifest.json)
RELEASE_ARCHITECTURES ?= $(shell ruby -rjson -e 'print JSON.parse(File.read(ARGV[0])).dig("product", "architectures").sort.join(" ")' .github/release-manifest.json)
RELEASE_SWIFT_TRIPLE ?= $(RELEASE_ARCHITECTURE)-apple-macosx15.0
RELEASE_SWIFT_PLATFORM_DIR ?= $(RELEASE_ARCHITECTURE)-apple-macosx
SWIFT_TRIPLE_ARGS = $(if $(filter release,$(CONFIGURATION)),--triple "$(RELEASE_SWIFT_TRIPLE)",)
SWIFT_PROVENANCE_ARGS = $(if $(SWIFT_BUILD_PROVENANCE_FILE),-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __vifty_src -Xlinker "$(SWIFT_BUILD_PROVENANCE_FILE)",)
SWIFT_BUILD_ARGS = $(if $(SWIFT_BUILD_PATH),--build-path "$(SWIFT_BUILD_PATH)",) $(SWIFT_TRIPLE_ARGS) $(SWIFT_PROVENANCE_ARGS) $(SWIFT_BUILD_EXTRA_ARGS)
SWIFT_PRODUCTS_DIR = $(if $(filter release,$(CONFIGURATION)),$(if $(SWIFT_BUILD_PATH),$(SWIFT_BUILD_PATH)/$(RELEASE_SWIFT_PLATFORM_DIR)/$(CONFIGURATION),.build/$(RELEASE_SWIFT_PLATFORM_DIR)/$(CONFIGURATION)),$(if $(SWIFT_BUILD_PATH),$(SWIFT_BUILD_PATH)/$(CONFIGURATION),.build/$(CONFIGURATION)))
VERIFY_TEST_TARGET ?= test-fast
SLOW_TEST_SKIP_ARGS := --skip 'ViftyCoreTests\.(AgentCoolingEvidenceScriptTests|AgentRunSmokeEvidenceScriptTests|GuardedRunScriptTests|HelperLifecycleScriptTests|InstallReplacementPreflightScriptTests|ReleaseArtifactScriptTests|ReleaseManifestScriptTests|ReleaseMetadataScriptTests|UIReviewEvidenceScriptTests|ValidationEvidenceReviewScriptTests|ValidationEvidenceScriptTests|ValidationReportSummaryScriptTests)'
RELEASE_VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
RELEASE_REPO ?= Reedtrullz/Vifty
SOURCE_FIRST_SOURCE_REF ?= v$(RELEASE_VERSION)
UNSIGNED_DEV_SOURCE_REF ?= v$(RELEASE_VERSION)
RELEASE_METADATA_MODE ?= developer-id
VIFTYCTL ?= /Applications/Vifty.app/Contents/MacOS/viftyctl
VALIDATION_EVIDENCE_APP ?= /Applications/Vifty.app
VALIDATION_EVIDENCE_OUTPUT ?=
VALIDATION_EVIDENCE_INSTALL_SOURCE ?= not-recorded
VALIDATION_EVIDENCE_SOURCE_REF ?=
VALIDATION_EVIDENCE_SOURCE_SHA ?=
VALIDATION_EVIDENCE_SOURCE_ARTIFACT ?=
VALIDATION_EVIDENCE_RELEASE_SUMMARY ?=
VALIDATION_EVIDENCE_RELEASE_CHECKLIST ?=
VALIDATION_EVIDENCE_INCLUDE_PROBE_LOCAL ?= 0
VALIDATION_EVIDENCE_CURRENT_BUILD_INCLUDE_PROBE_LOCAL ?= 1
REPAIR_HELPER_APP ?= /Applications/Vifty.app
UNINSTALL_HELPER_APP ?= /Applications/Vifty.app
PUBLIC_RELEASE_ARCHIVE ?=
CURRENT_BUILD_SOURCE_REF ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
CURRENT_BUILD_SOURCE_SHA ?= $(shell git rev-parse HEAD 2>/dev/null)
VALIDATION_EVIDENCE_BUNDLE ?=
VALIDATION_EVIDENCE_REVIEW_MODE ?= supported-hardware
VALIDATION_EVIDENCE_REVIEW_SUMMARY ?=
VALIDATION_EVIDENCE_MANUAL_SMOKE_RESULT ?= not-recorded
VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE ?=
VALIDATION_EVIDENCE_MANUAL_SMOKE_READINESS_SUMMARY ?=
VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_RESULT ?= not-recorded
VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SOURCE ?=
VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_READINESS_SUMMARY ?=
VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY ?=
MANUAL_SMOKE_READINESS_JSON ?= 0
MANUAL_SMOKE_READINESS_SUMMARY ?=
MANUAL_SMOKE_EXPECTED_DAEMON ?=
MANUAL_SMOKE_REQUIRE_DAEMON_MATCH ?= 0
AGENT_RUN_SMOKE_READINESS_JSON ?= 0
AGENT_RUN_SMOKE_READINESS_SUMMARY ?=
AGENT_EVIDENCE_OUTPUT ?=
AGENT_EVIDENCE_GUARDED_RUN_STDERR ?=
AGENT_EVIDENCE_BUNDLE ?=
AGENT_EVIDENCE_REVIEW_SUMMARY ?=
AGENT_RUN_SMOKE_OUTPUT ?=
AGENT_RUN_SMOKE_DURATION ?= 2m
AGENT_RUN_SMOKE_MAX_RPM_PERCENT ?= 55
AGENT_RUN_SMOKE_REASON ?= agent run smoke test
AGENT_RUN_SMOKE_AUDIT_LIMIT ?= 20
AGENT_RUN_SMOKE_INSTALL_SOURCE ?= not-recorded
AGENT_RUN_SMOKE_SOURCE_REF ?=
AGENT_RUN_SMOKE_SOURCE_SHA ?=
AGENT_RUN_SMOKE_SOURCE_ARTIFACT ?=
AGENT_RUN_SMOKE_EXPECTED_DAEMON ?=
AGENT_RUN_SMOKE_REQUIRE_DAEMON_MATCH ?= 0
UI_REVIEW_MANIFEST ?= $(CURDIR)/docs/ui-review/evidence-manifest.local.json
UI_REVIEW_EVIDENCE_DIR ?= $(CURDIR)/.build/ui-review-evidence
UI_REVIEW_PRODUCTS_DIR ?= $(CURDIR)/.build/ui-review-products
UI_REVIEW_DEBUG_EXECUTABLE ?= $(UI_REVIEW_PRODUCTS_DIR)/debug/Vifty.app/Contents/MacOS/Vifty
UI_REVIEW_RELEASE_BINARY ?= $(UI_REVIEW_PRODUCTS_DIR)/release/Vifty
UI_REVIEW_AX_COLLECTOR ?= $(UI_REVIEW_PRODUCTS_DIR)/debug/ViftyAXCollector
UI_REVIEW_SOURCE_COMMIT ?=
UI_REVIEW_CHECKPOINT ?= $(CURDIR)/docs/ui-review/automated-checkpoint.json
UI_REVIEW_HERO ?= $(CURDIR)/docs/images/vifty-screenshot.png
UI_REVIEW_REPOSITORY_ROOT ?= $(CURDIR)
APP_NAME := Vifty
APP_DIR ?= .build/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS := $(CONTENTS)/MacOS
SCHEMAS := $(CONTENTS)/Resources/schemas
BUNDLED_SCHEMA_INVENTORY ?= scripts/bundled-schema-inventory.txt
SCHEMA_SOURCE_DIR ?= docs/schemas
WRAPPERS := $(CONTENTS)/Resources/viftyctl-wrappers
APP_ICON := Resources/ViftyIcon.icns
DAEMON_PLIST := $(CONTENTS)/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist

install: CONFIGURATION = release
pkg: CONFIGURATION = release

release-facts: ## Validate the authoritative release identity and artifact facts
	./scripts/check-release-manifest.sh
	./scripts/render-release-facts.sh --check
	ruby scripts/check-workflow-contract.rb

package-bundled-schemas: ## Package the explicit reviewed JSON Schema inventory byte-for-byte
	/usr/bin/ruby scripts/package-bundled-schemas.rb --inventory "$(BUNDLED_SCHEMA_INVENTORY)" --source "$(SCHEMA_SOURCE_DIR)" --destination "$(SCHEMAS)"

release-contract-ruby-tests: ## Run portable release inventory and artifact-contract regressions
	/usr/bin/ruby Tests/Ruby/BundledSchemaInventoryTests.rb
	/usr/bin/ruby Tests/Ruby/ReleaseCandidateInventoryTests.rb
	/usr/bin/ruby Tests/Ruby/ReleaseArtifactContractTests.rb
	/usr/bin/ruby Tests/Ruby/WorkflowContractTests.rb

installer-lifecycle-ruby-tests: ## Run portable installer lifecycle transaction and trust regressions
	/usr/bin/ruby Tests/Ruby/InstallerLifecycleTrustContractTests.rb
	/usr/bin/ruby Tests/Ruby/HelperLifecycleReplacementFixtureTests.rb

app: release-facts ## Build the release app bundle
	VIFTY_XPC_ADHOC_DEVELOPMENT="$(VIFTY_XPC_ADHOC_DEVELOPMENT)" VIFTY_XPC_ADHOC_ALLOWED_UID="$(VIFTY_XPC_ADHOC_ALLOWED_UID)" VIFTY_XPC_ADHOC_APP_PATH="$(VIFTY_XPC_ADHOC_APP_PATH)" VIFTY_XPC_ADHOC_CTL_PATH="$(VIFTY_XPC_ADHOC_CTL_PATH)" VIFTY_XPC_ADHOC_HELPER_PATH="$(VIFTY_XPC_ADHOC_HELPER_PATH)" ./scripts/configure-daemon-plist.sh --configuration "$(CONFIGURATION)" --team-id "$(VIFTY_XPC_ALLOWED_TEAM_ID)" --validate-only
	swift build $(SWIFT_BUILD_ARGS) -c $(CONFIGURATION)
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS)"
	mkdir -p "$(SCHEMAS)"
	mkdir -p "$(WRAPPERS)"
	mkdir -p "$(CONTENTS)/Library/LaunchDaemons"
	cp "$(SWIFT_PRODUCTS_DIR)/Vifty" "$(MACOS)/Vifty"
	cp "$(SWIFT_PRODUCTS_DIR)/ViftyHelper" "$(MACOS)/ViftyHelper"
	cp "$(SWIFT_PRODUCTS_DIR)/ViftyCtl" "$(MACOS)/viftyctl"
	cp "$(SWIFT_PRODUCTS_DIR)/ViftyDaemon" "$(MACOS)/ViftyDaemon"
	$(MAKE) package-bundled-schemas SCHEMAS="$(SCHEMAS)" BUNDLED_SCHEMA_INVENTORY="$(BUNDLED_SCHEMA_INVENTORY)" SCHEMA_SOURCE_DIR="$(SCHEMA_SOURCE_DIR)"
	install -m 755 scripts/collect-agent-cooling-evidence.sh "$(CONTENTS)/Resources/collect-agent-cooling-evidence.sh"
	install -m 755 scripts/check-manual-smoke-readiness.sh "$(CONTENTS)/Resources/check-manual-smoke-readiness.sh"
	install -m 755 scripts/check-agent-run-smoke-readiness.sh "$(CONTENTS)/Resources/check-agent-run-smoke-readiness.sh"
	install -m 755 scripts/collect-agent-run-smoke-evidence.sh "$(CONTENTS)/Resources/collect-agent-run-smoke-evidence.sh"
	install -m 755 scripts/vifty-helper-lifecycle.sh "$(CONTENTS)/Resources/vifty-helper-lifecycle.sh"
	install -m 755 scripts/repair-vifty-helper.sh "$(CONTENTS)/Resources/repair-vifty-helper.sh"
	install -m 755 scripts/uninstall-vifty.sh "$(CONTENTS)/Resources/uninstall-vifty.sh"
	install -m 755 examples/viftyctl/*.sh "$(WRAPPERS)/"
	install -m 644 examples/viftyctl/README.md "$(WRAPPERS)/README.md"
	install -m 644 "$(APP_ICON)" "$(CONTENTS)/Resources/ViftyIcon.icns"
	install -m 644 "Resources/Info.plist" "$(CONTENTS)/Info.plist"
	install -m 644 "Resources/tech.reidar.vifty.daemon.plist" "$(DAEMON_PLIST)"
	VIFTY_XPC_ADHOC_DEVELOPMENT="$(VIFTY_XPC_ADHOC_DEVELOPMENT)" VIFTY_XPC_ADHOC_ALLOWED_UID="$(VIFTY_XPC_ADHOC_ALLOWED_UID)" VIFTY_XPC_ADHOC_APP_PATH="$(VIFTY_XPC_ADHOC_APP_PATH)" VIFTY_XPC_ADHOC_CTL_PATH="$(VIFTY_XPC_ADHOC_CTL_PATH)" VIFTY_XPC_ADHOC_HELPER_PATH="$(VIFTY_XPC_ADHOC_HELPER_PATH)" ./scripts/configure-daemon-plist.sh --plist "$(DAEMON_PLIST)" --configuration "$(CONFIGURATION)" --team-id "$(VIFTY_XPC_ALLOWED_TEAM_ID)"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime --identifier tech.reidar.vifty.helper "$(MACOS)/ViftyHelper"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime --identifier tech.reidar.vifty.daemon "$(MACOS)/ViftyDaemon"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime --identifier tech.reidar.vifty.ctl "$(MACOS)/viftyctl"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime --entitlements Resources/Vifty.entitlements "$(APP_DIR)"
	@if [ "$(CONFIGURATION)" = "release" ]; then \
		expected="$(RELEASE_ARCHITECTURES)"; \
		for binary in "$(MACOS)/Vifty" "$(MACOS)/ViftyHelper" "$(MACOS)/ViftyDaemon" "$(MACOS)/viftyctl"; do \
			actual="$$(lipo -archs "$$binary" | tr ' ' '\n' | sort | xargs)"; \
			if [ "$$actual" != "$$expected" ]; then echo "Architecture mismatch for $$binary: expected $$expected, got $$actual" >&2; exit 1; fi; \
		done; \
	fi
	@test -z "$$(find "$(CONTENTS)" -name 'ViftyAXCollector*' -o -name 'ViftyAXEvidenceCore*' -o -name 'AXReader.swift' -o -name 'AXTraversal.swift' -o -name 'AXEvidenceModels.swift' -o -name 'AXPredicateCatalog.swift' -o -name 'ui-review-ax-*.schema.json')" || { echo "AX evidence tooling must not be bundled in Vifty.app" >&2; exit 1; }
	@echo "Built $(APP_DIR)"

run-app: ## Build and open the local app bundle
	./scripts/build-and-run-vifty.sh

install: ## Build and install to /Applications
	CONFIGURATION="$(CONFIGURATION)" ./scripts/install-vifty.sh

install-public-release: ## Verify and install the exact current published release archive
	@if [ -z "$(PUBLIC_RELEASE_ARCHIVE)" ]; then echo "PUBLIC_RELEASE_ARCHIVE is required and must be an absolute path to the canonical public release zip" >&2; exit 64; fi
	CONFIGURATION=release ./scripts/install-vifty.sh --public-release-archive "$(PUBLIC_RELEASE_ARCHIVE)"

install-dev-adhoc: ## Explicit debug-only install with exact UID/path XPC allowlist
	CONFIGURATION=debug VIFTY_ENABLE_ADHOC_XPC=1 ./scripts/install-vifty.sh

repair-helper: ## Explicitly repair the installed privileged helper
	./scripts/repair-vifty-helper.sh --app "$(REPAIR_HELPER_APP)"

uninstall-helper: ## Safely remove the installed privileged helper
	./scripts/uninstall-vifty.sh --app "$(UNINSTALL_HELPER_APP)"

pkg: ## Build an unsigned installer .pkg
	CONFIGURATION="$(CONFIGURATION)" ./scripts/build-installer-pkg.sh

validation-evidence: ## Collect read-only release/hardware validation evidence
	./scripts/collect-validation-evidence.sh --app "$(VALIDATION_EVIDENCE_APP)" --install-source "$(VALIDATION_EVIDENCE_INSTALL_SOURCE)" $(if $(VALIDATION_EVIDENCE_SOURCE_REF),--source-ref "$(VALIDATION_EVIDENCE_SOURCE_REF)",) $(if $(VALIDATION_EVIDENCE_SOURCE_SHA),--source-sha "$(VALIDATION_EVIDENCE_SOURCE_SHA)",) $(if $(VALIDATION_EVIDENCE_SOURCE_ARTIFACT),--source-artifact "$(VALIDATION_EVIDENCE_SOURCE_ARTIFACT)",) $(if $(VALIDATION_EVIDENCE_RELEASE_SUMMARY),--release-summary "$(VALIDATION_EVIDENCE_RELEASE_SUMMARY)",) $(if $(VALIDATION_EVIDENCE_RELEASE_CHECKLIST),--release-checklist "$(VALIDATION_EVIDENCE_RELEASE_CHECKLIST)",) $(if $(VALIDATION_EVIDENCE_OUTPUT),--output "$(VALIDATION_EVIDENCE_OUTPUT)",) $(if $(filter 1 true yes,$(VALIDATION_EVIDENCE_INCLUDE_PROBE_LOCAL)),--include-probe-local,)

validation-evidence-current-build: ## Build current app and collect read-only local-ad-hoc validation evidence
	@status="$$(git status --porcelain --untracked-files=all 2>/dev/null)"; if [ -n "$$status" ]; then echo "validation-evidence-current-build requires a clean git worktree so source ref/SHA match the built app; commit or stash changes first, or use make validation-evidence with installSource=not-recorded for exploratory local evidence." >&2; exit 65; fi
	$(MAKE) app CONFIGURATION=release SIGNING_IDENTITY="$(SIGNING_IDENTITY)" VIFTY_XPC_ALLOWED_TEAM_ID="$(VIFTY_XPC_ALLOWED_TEAM_ID)"
	$(MAKE) validation-evidence VALIDATION_EVIDENCE_APP="$(APP_DIR)" VALIDATION_EVIDENCE_INSTALL_SOURCE=local-ad-hoc-build VALIDATION_EVIDENCE_SOURCE_REF="$(CURRENT_BUILD_SOURCE_REF)" VALIDATION_EVIDENCE_SOURCE_SHA="$(CURRENT_BUILD_SOURCE_SHA)" VALIDATION_EVIDENCE_INCLUDE_PROBE_LOCAL="$(VALIDATION_EVIDENCE_CURRENT_BUILD_INCLUDE_PROBE_LOCAL)"

validation-evidence-review: ## Review a captured validation evidence bundle
	@if [ -z "$(VALIDATION_EVIDENCE_BUNDLE)" ]; then echo "VALIDATION_EVIDENCE_BUNDLE is required" >&2; exit 64; fi
	./scripts/review-validation-evidence.sh --bundle "$(VALIDATION_EVIDENCE_BUNDLE)" --mode "$(VALIDATION_EVIDENCE_REVIEW_MODE)" $(if $(VALIDATION_EVIDENCE_REVIEW_SUMMARY),--summary "$(VALIDATION_EVIDENCE_REVIEW_SUMMARY)",) --manual-smoke-result "$(VALIDATION_EVIDENCE_MANUAL_SMOKE_RESULT)" $(if $(VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE),--manual-smoke-source "$(VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE)",) $(if $(VALIDATION_EVIDENCE_MANUAL_SMOKE_READINESS_SUMMARY),--manual-smoke-readiness-summary "$(VALIDATION_EVIDENCE_MANUAL_SMOKE_READINESS_SUMMARY)",) --agent-run-smoke-result "$(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_RESULT)" $(if $(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SOURCE),--agent-run-smoke-source "$(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SOURCE)",) $(if $(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_READINESS_SUMMARY),--agent-run-smoke-readiness-summary "$(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_READINESS_SUMMARY)",) $(if $(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY),--agent-run-smoke-summary "$(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY)",)

manual-smoke-readiness: ## Read-only preflight before human Fixed/Curve smoke
	./scripts/check-manual-smoke-readiness.sh --viftyctl "$(VIFTYCTL)" $(if $(MANUAL_SMOKE_EXPECTED_DAEMON),--expected-daemon "$(MANUAL_SMOKE_EXPECTED_DAEMON)",) $(if $(filter 1 true yes,$(MANUAL_SMOKE_REQUIRE_DAEMON_MATCH)),--require-daemon-match,) $(if $(filter 1 true yes,$(MANUAL_SMOKE_READINESS_JSON)),--json,) $(if $(MANUAL_SMOKE_READINESS_SUMMARY),--summary "$(MANUAL_SMOKE_READINESS_SUMMARY)",)

manual-smoke-readiness-current-build: ## Build current app and run read-only manual smoke preflight
	@status="$$(git status --porcelain --untracked-files=all 2>/dev/null)"; if [ -n "$$status" ]; then echo "manual-smoke-readiness-current-build requires a clean git worktree so the preflight uses the built app from the current source ref; commit or stash changes first, or use make manual-smoke-readiness with an explicit VIFTYCTL for exploratory local preflight." >&2; exit 65; fi
	$(MAKE) app CONFIGURATION=release SIGNING_IDENTITY="$(SIGNING_IDENTITY)" VIFTY_XPC_ALLOWED_TEAM_ID="$(VIFTY_XPC_ALLOWED_TEAM_ID)"
	$(MAKE) manual-smoke-readiness VIFTYCTL="$(MACOS)/viftyctl" MANUAL_SMOKE_EXPECTED_DAEMON="$(MACOS)/ViftyDaemon" MANUAL_SMOKE_REQUIRE_DAEMON_MATCH=1

agent-cooling-evidence: ## Collect read-only agent/helper support evidence
	./scripts/collect-agent-cooling-evidence.sh --viftyctl "$(VIFTYCTL)" $(if $(AGENT_EVIDENCE_OUTPUT),--output "$(AGENT_EVIDENCE_OUTPUT)",) $(if $(AGENT_EVIDENCE_GUARDED_RUN_STDERR),--guarded-run-stderr-file "$(AGENT_EVIDENCE_GUARDED_RUN_STDERR)",) $(if $(AGENT_EVIDENCE_GUARDED_RUN_SCRIPT),--guarded-run-script "$(AGENT_EVIDENCE_GUARDED_RUN_SCRIPT)",) $(if $(AGENT_EVIDENCE_GUARDED_RUN_PREFLIGHT),--guarded-run-preflight $(AGENT_EVIDENCE_GUARDED_RUN_PREFLIGHT),)

agent-cooling-evidence-review: ## Review a read-only agent/helper support evidence bundle
	@if [ -z "$(AGENT_EVIDENCE_BUNDLE)" ]; then echo "AGENT_EVIDENCE_BUNDLE is required" >&2; exit 64; fi
	./scripts/review-agent-cooling-evidence.sh --bundle "$(AGENT_EVIDENCE_BUNDLE)" $(if $(AGENT_EVIDENCE_REVIEW_SUMMARY),--summary "$(AGENT_EVIDENCE_REVIEW_SUMMARY)",)

agent-run-smoke-readiness: ## Read-only preflight before supervised viftyctl run smoke
	./scripts/check-agent-run-smoke-readiness.sh --viftyctl "$(VIFTYCTL)" --duration "$(AGENT_RUN_SMOKE_DURATION)" --max-rpm-percent "$(AGENT_RUN_SMOKE_MAX_RPM_PERCENT)" --reason "$(AGENT_RUN_SMOKE_REASON)" $(if $(AGENT_RUN_SMOKE_EXPECTED_DAEMON),--expected-daemon "$(AGENT_RUN_SMOKE_EXPECTED_DAEMON)",) $(if $(filter 1 true yes,$(AGENT_RUN_SMOKE_REQUIRE_DAEMON_MATCH)),--require-daemon-match,) $(if $(filter 1 true yes,$(AGENT_RUN_SMOKE_READINESS_JSON)),--json,) $(if $(AGENT_RUN_SMOKE_READINESS_SUMMARY),--summary "$(AGENT_RUN_SMOKE_READINESS_SUMMARY)",)

agent-run-smoke-readiness-current-build: ## Build current app and run read-only agent smoke preflight
	@status="$$(git status --porcelain --untracked-files=all 2>/dev/null)"; if [ -n "$$status" ]; then echo "agent-run-smoke-readiness-current-build requires a clean git worktree so the preflight uses the built app from the current source ref; commit or stash changes first, or use make agent-run-smoke-readiness with an explicit VIFTYCTL for exploratory local preflight." >&2; exit 65; fi
	$(MAKE) app CONFIGURATION=release SIGNING_IDENTITY="$(SIGNING_IDENTITY)" VIFTY_XPC_ALLOWED_TEAM_ID="$(VIFTY_XPC_ALLOWED_TEAM_ID)"
	$(MAKE) agent-run-smoke-readiness VIFTYCTL="$(MACOS)/viftyctl" AGENT_RUN_SMOKE_EXPECTED_DAEMON="$(MACOS)/ViftyDaemon" AGENT_RUN_SMOKE_REQUIRE_DAEMON_MATCH=1

agent-run-smoke-evidence: ## Collect supervised supported-hardware viftyctl run smoke evidence
	./scripts/collect-agent-run-smoke-evidence.sh --viftyctl "$(VIFTYCTL)" --duration "$(AGENT_RUN_SMOKE_DURATION)" --max-rpm-percent "$(AGENT_RUN_SMOKE_MAX_RPM_PERCENT)" --reason "$(AGENT_RUN_SMOKE_REASON)" --audit-limit "$(AGENT_RUN_SMOKE_AUDIT_LIMIT)" --install-source "$(AGENT_RUN_SMOKE_INSTALL_SOURCE)" $(if $(AGENT_RUN_SMOKE_SOURCE_REF),--source-ref "$(AGENT_RUN_SMOKE_SOURCE_REF)",) $(if $(AGENT_RUN_SMOKE_SOURCE_SHA),--source-sha "$(AGENT_RUN_SMOKE_SOURCE_SHA)",) $(if $(AGENT_RUN_SMOKE_SOURCE_ARTIFACT),--source-artifact "$(AGENT_RUN_SMOKE_SOURCE_ARTIFACT)",) $(if $(AGENT_RUN_SMOKE_EXPECTED_DAEMON),--expected-daemon "$(AGENT_RUN_SMOKE_EXPECTED_DAEMON)",) $(if $(filter 1 true yes,$(AGENT_RUN_SMOKE_REQUIRE_DAEMON_MATCH)),--require-daemon-match,) $(if $(AGENT_RUN_SMOKE_OUTPUT),--output "$(AGENT_RUN_SMOKE_OUTPUT)",)

agent-run-smoke-evidence-current-build: ## Build current app and collect supervised local viftyctl run smoke evidence
	@status="$$(git status --porcelain --untracked-files=all 2>/dev/null)"; if [ -n "$$status" ]; then echo "agent-run-smoke-evidence-current-build requires a clean git worktree so the smoke test uses the built app from the current source ref; commit or stash changes first, or use make agent-run-smoke-evidence with an explicit VIFTYCTL for exploratory local smoke evidence." >&2; exit 65; fi
	$(MAKE) app CONFIGURATION=release SIGNING_IDENTITY="$(SIGNING_IDENTITY)" VIFTY_XPC_ALLOWED_TEAM_ID="$(VIFTY_XPC_ALLOWED_TEAM_ID)"
	$(MAKE) agent-run-smoke-evidence VIFTYCTL="$(MACOS)/viftyctl" AGENT_RUN_SMOKE_INSTALL_SOURCE=local-ad-hoc-build AGENT_RUN_SMOKE_SOURCE_REF="$(CURRENT_BUILD_SOURCE_REF)" AGENT_RUN_SMOKE_SOURCE_SHA="$(CURRENT_BUILD_SOURCE_SHA)" AGENT_RUN_SMOKE_EXPECTED_DAEMON="$(MACOS)/ViftyDaemon" AGENT_RUN_SMOKE_REQUIRE_DAEMON_MATCH=1

ui-review-build-products: ## Build one clean-tree provenance-bound UI review product transaction
	./scripts/build-ui-review-products.sh

ui-review-initialize-ledger: ## Initialize a fresh product-bound ignored UI review ledger
	/usr/bin/ruby ./scripts/initialize-ui-review-ledger.rb --repository-root "$(UI_REVIEW_REPOSITORY_ROOT)"

ui-review-start-session: ## Build exact products and initialize a fresh ignored UI review ledger
	$(MAKE) ui-review-build-products
	$(MAKE) ui-review-initialize-ledger

ui-review-ruby-tests: ## Run portable UI review provenance, publication, and archive safety tests
	/usr/bin/ruby Tests/Ruby/UIReviewBuildProvenanceTests.rb
	/usr/bin/ruby Tests/Ruby/UIReviewLocalLedgerTests.rb
	/usr/bin/ruby Tests/Ruby/UIReviewProductPublicationTests.rb
	/usr/bin/ruby Tests/Ruby/UIReviewSourceArchiveTests.rb

ui-review-verify-automated: ## Verify autonomous native UI/AX evidence while human and system-setting rows remain explicit
	./scripts/run-ui-review-fixture.sh --verify-automated --manifest "$(UI_REVIEW_MANIFEST)" --evidence-dir "$(UI_REVIEW_EVIDENCE_DIR)" --debug-executable "$(UI_REVIEW_DEBUG_EXECUTABLE)" --release-binary "$(UI_REVIEW_RELEASE_BINARY)" --collector-executable "$(UI_REVIEW_AX_COLLECTOR)"

ui-review-write-checkpoint: ## Verify and write the portable exact-50 automated UI checkpoint
	@if [ -z "$(UI_REVIEW_SOURCE_COMMIT)" ]; then echo "UI_REVIEW_SOURCE_COMMIT is required" >&2; exit 64; fi
	./scripts/write-ui-review-checkpoint.rb --repository-root "$(UI_REVIEW_REPOSITORY_ROOT)" --manifest "$(UI_REVIEW_MANIFEST)" --evidence-dir "$(UI_REVIEW_EVIDENCE_DIR)" --debug-executable "$(UI_REVIEW_DEBUG_EXECUTABLE)" --release-binary "$(UI_REVIEW_RELEASE_BINARY)" --collector-executable "$(UI_REVIEW_AX_COLLECTOR)" --source-commit "$(UI_REVIEW_SOURCE_COMMIT)" --output "$(UI_REVIEW_CHECKPOINT)" --hero "$(UI_REVIEW_HERO)"

ui-review-verify: ## Verify the full UI matrix including exact visual and VoiceOver attestations
	./scripts/run-ui-review-fixture.sh --verify-matrix --manifest "$(UI_REVIEW_MANIFEST)" --evidence-dir "$(UI_REVIEW_EVIDENCE_DIR)" --debug-executable "$(UI_REVIEW_DEBUG_EXECUTABLE)" --release-binary "$(UI_REVIEW_RELEASE_BINARY)" --collector-executable "$(UI_REVIEW_AX_COLLECTOR)"

source-first-release-notes: ## Write source-first release notes for the current version
	./scripts/write-release-checklist.sh --mode source-first --version "$(RELEASE_VERSION)" $(if $(SOURCE_FIRST_SOURCE_REF),--source-ref "$(SOURCE_FIRST_SOURCE_REF)",)

unsigned-dev-artifact: ## Build source-first unsigned tester zip and checksum
	./scripts/build-unsigned-dev-artifact.sh --version "$(RELEASE_VERSION)" $(if $(UNSIGNED_DEV_SOURCE_REF),--require-source-ref "$(UNSIGNED_DEV_SOURCE_REF)",)

source-first-readiness: ## Check published source-first release readiness
	./scripts/check-release-readiness.sh --mode source-first --version "$(RELEASE_VERSION)" --repo "$(RELEASE_REPO)" --json

test: test-full ## Run the full XCTest suite

test-fast: ## Run the fast local XCTest suite
	swift test $(SWIFT_BUILD_ARGS) $(SLOW_TEST_SKIP_ARGS)

test-full: ## Run the full XCTest suite, including slow evidence/release script tests
	swift test $(SWIFT_BUILD_ARGS)

verify: ## Run fast local trust gates without installing
	/bin/bash -n scripts/*.sh scripts/lib/*.sh examples/viftyctl/*.sh
	$(MAKE) release-facts
	scripts/check-community-standards.sh
	scripts/validate-release-metadata.sh --mode "$(RELEASE_METADATA_MODE)"
	$(MAKE) $(VERIFY_TEST_TARGET)
	swift build $(SWIFT_BUILD_ARGS) -Xswiftc -warnings-as-errors
	$(MAKE) app CONFIGURATION=release SIGNING_IDENTITY="$(SIGNING_IDENTITY)" VIFTY_XPC_ALLOWED_TEAM_ID="$(VIFTY_XPC_ALLOWED_TEAM_ID)"
	plutil -lint "$(CONTENTS)/Info.plist"
	plutil -lint "$(DAEMON_PLIST)"
	test -x "$(CONTENTS)/Resources/collect-agent-cooling-evidence.sh"
	test -x "$(CONTENTS)/Resources/check-manual-smoke-readiness.sh"
	test -x "$(CONTENTS)/Resources/check-agent-run-smoke-readiness.sh"
	test -x "$(CONTENTS)/Resources/collect-agent-run-smoke-evidence.sh"
	test -x "$(CONTENTS)/Resources/vifty-helper-lifecycle.sh"
	test -x "$(CONTENTS)/Resources/repair-vifty-helper.sh"
	test -x "$(CONTENTS)/Resources/uninstall-vifty.sh"
	test -z "$$(find "$(CONTENTS)" -name 'ViftyAXCollector*' -o -name 'ViftyAXEvidenceCore*' -o -name 'AXReader.swift' -o -name 'AXTraversal.swift' -o -name 'AXEvidenceModels.swift' -o -name 'AXPredicateCatalog.swift' -o -name 'ui-review-ax-*.schema.json')"
	test -x scripts/check-manual-smoke-readiness.sh
	test -x scripts/check-agent-run-smoke-readiness.sh
	test -x scripts/repair-vifty-helper.sh
	test -x scripts/uninstall-vifty.sh
	test -x scripts/configure-daemon-plist.sh
	@for key in VIFTY_XPC_ADHOC_DEVELOPMENT VIFTY_XPC_ADHOC_ALLOWED_UID VIFTY_XPC_ADHOC_APP_PATH VIFTY_XPC_ADHOC_CTL_PATH VIFTY_XPC_ADHOC_HELPER_PATH; do \
		if /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:$$key" "$(DAEMON_PLIST)" >/dev/null 2>&1; then echo "Release LaunchDaemon plist must omit $$key" >&2; exit 1; fi; \
	done
	@source_wrappers="$$(find examples/viftyctl -maxdepth 1 -type f -name '*.sh' -exec basename {} \; | sort)"; \
	bundle_wrappers="$$(find "$(WRAPPERS)" -maxdepth 1 -type f -name '*.sh' -exec basename {} \; | sort)"; \
	if [ "$$source_wrappers" != "$$bundle_wrappers" ]; then \
		echo "Bundled viftyctl wrapper list does not match source examples." >&2; \
		echo "Source wrappers:" >&2; \
		printf '%s\n' "$$source_wrappers" >&2; \
		echo "Bundled wrappers:" >&2; \
		printf '%s\n' "$$bundle_wrappers" >&2; \
		exit 1; \
	fi; \
	for wrapper in $$source_wrappers; do \
		test -x "examples/viftyctl/$$wrapper"; \
		test -x "$(WRAPPERS)/$$wrapper"; \
	done
	test -f "$(WRAPPERS)/README.md"
	codesign --verify --deep --strict "$(APP_DIR)"
	codesign -dvvv "$(MACOS)/ViftyHelper" 2>&1 | grep 'Identifier=tech.reidar.vifty.helper'
	codesign -dvvv "$(MACOS)/ViftyDaemon" 2>&1 | grep 'Identifier=tech.reidar.vifty.daemon'
	codesign -dvvv "$(MACOS)/viftyctl" 2>&1 | grep 'Identifier=tech.reidar.vifty.ctl'

verify-full: VERIFY_TEST_TARGET = test-full
verify-full: verify release-contract-ruby-tests installer-lifecycle-ruby-tests ui-review-ruby-tests ## Run full trust gates, including slow XCTest suites, for CI/release-facing checks

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

clean: clean-app ## Remove all build artifacts
	rm -rf .build/

clean-app:
	rm -rf "$(APP_DIR)"

clean-pkg:
	rm -rf .build/pkg-root .build/$(APP_NAME)-*.pkg
