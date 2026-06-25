.PHONY: app install repair-helper pkg validation-evidence validation-evidence-current-build validation-evidence-review manual-smoke-readiness manual-smoke-readiness-current-build agent-cooling-evidence agent-cooling-evidence-review agent-run-smoke-readiness agent-run-smoke-readiness-current-build agent-run-smoke-evidence agent-run-smoke-evidence-current-build source-first-release-notes unsigned-dev-artifact source-first-readiness clean-app clean-pkg test verify help clean

CONFIGURATION ?= debug
SIGNING_IDENTITY ?= -
VIFTY_XPC_ALLOWED_TEAM_ID ?=
SWIFT_BUILD_PATH ?=
SWIFT_BUILD_ARGS = $(if $(SWIFT_BUILD_PATH),--build-path "$(SWIFT_BUILD_PATH)",)
SWIFT_PRODUCTS_DIR = $(if $(SWIFT_BUILD_PATH),$(SWIFT_BUILD_PATH)/$(CONFIGURATION),.build/$(CONFIGURATION))
RELEASE_VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
RELEASE_REPO ?= Reedtrullz/Vifty
SOURCE_FIRST_SOURCE_REF ?= v$(RELEASE_VERSION)
UNSIGNED_DEV_SOURCE_REF ?= v$(RELEASE_VERSION)
RELEASE_METADATA_MODE ?= source-first
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
VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY ?=
MANUAL_SMOKE_READINESS_JSON ?= 0
MANUAL_SMOKE_READINESS_SUMMARY ?=
MANUAL_SMOKE_EXPECTED_DAEMON ?=
MANUAL_SMOKE_REQUIRE_DAEMON_MATCH ?= 0
AGENT_RUN_SMOKE_READINESS_JSON ?= 0
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
APP_NAME := Vifty
APP_DIR := .build/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS := $(CONTENTS)/MacOS
SCHEMAS := $(CONTENTS)/Resources/schemas
WRAPPERS := $(CONTENTS)/Resources/viftyctl-wrappers
APP_ICON := Resources/ViftyIcon.icns
DAEMON_PLIST := $(CONTENTS)/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist

install: CONFIGURATION = release
pkg: CONFIGURATION = release

app: ## Build the release app bundle
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
	cp docs/schemas/*.schema.json "$(SCHEMAS)/"
	install -m 755 scripts/collect-agent-cooling-evidence.sh "$(CONTENTS)/Resources/collect-agent-cooling-evidence.sh"
	install -m 755 scripts/check-manual-smoke-readiness.sh "$(CONTENTS)/Resources/check-manual-smoke-readiness.sh"
	install -m 755 scripts/check-agent-run-smoke-readiness.sh "$(CONTENTS)/Resources/check-agent-run-smoke-readiness.sh"
	install -m 755 scripts/collect-agent-run-smoke-evidence.sh "$(CONTENTS)/Resources/collect-agent-run-smoke-evidence.sh"
	install -m 755 examples/viftyctl/*.sh "$(WRAPPERS)/"
	install -m 644 examples/viftyctl/README.md "$(WRAPPERS)/README.md"
	cp "$(APP_ICON)" "$(CONTENTS)/Resources/ViftyIcon.icns"
	cp "Resources/Info.plist" "$(CONTENTS)/Info.plist"
	cp "Resources/tech.reidar.vifty.daemon.plist" "$(DAEMON_PLIST)"
	if [ -n "$(VIFTY_XPC_ALLOWED_TEAM_ID)" ]; then /usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:VIFTY_XPC_ALLOWED_TEAM_ID $(VIFTY_XPC_ALLOWED_TEAM_ID)" "$(DAEMON_PLIST)"; fi
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime --identifier tech.reidar.vifty.helper "$(MACOS)/ViftyHelper"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime --identifier tech.reidar.vifty.daemon "$(MACOS)/ViftyDaemon"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime --identifier tech.reidar.vifty.ctl "$(MACOS)/viftyctl"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime --entitlements Resources/Vifty.entitlements "$(APP_DIR)"
	@echo "Built $(APP_DIR)"

install: ## Build and install to /Applications
	CONFIGURATION="$(CONFIGURATION)" ./scripts/install-vifty.sh

repair-helper: ## Explicitly repair the installed privileged helper
	./scripts/repair-vifty-helper.sh --app "$(REPAIR_HELPER_APP)"

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
	./scripts/review-validation-evidence.sh --bundle "$(VALIDATION_EVIDENCE_BUNDLE)" --mode "$(VALIDATION_EVIDENCE_REVIEW_MODE)" $(if $(VALIDATION_EVIDENCE_REVIEW_SUMMARY),--summary "$(VALIDATION_EVIDENCE_REVIEW_SUMMARY)",) --manual-smoke-result "$(VALIDATION_EVIDENCE_MANUAL_SMOKE_RESULT)" $(if $(VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE),--manual-smoke-source "$(VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE)",) $(if $(VALIDATION_EVIDENCE_MANUAL_SMOKE_READINESS_SUMMARY),--manual-smoke-readiness-summary "$(VALIDATION_EVIDENCE_MANUAL_SMOKE_READINESS_SUMMARY)",) --agent-run-smoke-result "$(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_RESULT)" $(if $(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SOURCE),--agent-run-smoke-source "$(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SOURCE)",) $(if $(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY),--agent-run-smoke-summary "$(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY)",)

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
	./scripts/check-agent-run-smoke-readiness.sh --viftyctl "$(VIFTYCTL)" --duration "$(AGENT_RUN_SMOKE_DURATION)" --max-rpm-percent "$(AGENT_RUN_SMOKE_MAX_RPM_PERCENT)" --reason "$(AGENT_RUN_SMOKE_REASON)" $(if $(AGENT_RUN_SMOKE_EXPECTED_DAEMON),--expected-daemon "$(AGENT_RUN_SMOKE_EXPECTED_DAEMON)",) $(if $(filter 1 true yes,$(AGENT_RUN_SMOKE_REQUIRE_DAEMON_MATCH)),--require-daemon-match,) $(if $(filter 1 true yes,$(AGENT_RUN_SMOKE_READINESS_JSON)),--json,)

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

source-first-release-notes: ## Write source-first release notes for the current version
	./scripts/write-release-checklist.sh --mode source-first --version "$(RELEASE_VERSION)" $(if $(SOURCE_FIRST_SOURCE_REF),--source-ref "$(SOURCE_FIRST_SOURCE_REF)",)

unsigned-dev-artifact: ## Build source-first unsigned tester zip and checksum
	./scripts/build-unsigned-dev-artifact.sh --version "$(RELEASE_VERSION)" $(if $(UNSIGNED_DEV_SOURCE_REF),--require-source-ref "$(UNSIGNED_DEV_SOURCE_REF)",)

source-first-readiness: ## Check published source-first release readiness
	./scripts/check-release-readiness.sh --mode source-first --version "$(RELEASE_VERSION)" --repo "$(RELEASE_REPO)" --json

test: ## Run the XCTest suite
	swift test $(SWIFT_BUILD_ARGS)

verify: ## Run local trust gates without installing
	/bin/bash -n scripts/*.sh examples/viftyctl/*.sh
	scripts/check-community-standards.sh
	scripts/validate-release-metadata.sh --mode "$(RELEASE_METADATA_MODE)"
	swift test $(SWIFT_BUILD_ARGS)
	swift build $(SWIFT_BUILD_ARGS) -Xswiftc -warnings-as-errors
	$(MAKE) app CONFIGURATION=release SIGNING_IDENTITY="$(SIGNING_IDENTITY)" VIFTY_XPC_ALLOWED_TEAM_ID="$(VIFTY_XPC_ALLOWED_TEAM_ID)"
	plutil -lint "$(CONTENTS)/Info.plist"
	plutil -lint "$(DAEMON_PLIST)"
	test -x "$(CONTENTS)/Resources/collect-agent-cooling-evidence.sh"
	test -x "$(CONTENTS)/Resources/check-manual-smoke-readiness.sh"
	test -x "$(CONTENTS)/Resources/check-agent-run-smoke-readiness.sh"
	test -x "$(CONTENTS)/Resources/collect-agent-run-smoke-evidence.sh"
	test -x scripts/check-manual-smoke-readiness.sh
	test -x scripts/check-agent-run-smoke-readiness.sh
	test -x scripts/repair-vifty-helper.sh
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

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

clean: clean-app ## Remove all build artifacts
	rm -rf .build/

clean-app:
	rm -rf "$(APP_DIR)"

clean-pkg:
	rm -rf .build/pkg-root .build/$(APP_NAME)-*.pkg
