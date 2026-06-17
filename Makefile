.PHONY: app install pkg validation-evidence validation-evidence-current-build validation-evidence-review agent-cooling-evidence agent-cooling-evidence-review agent-run-smoke-evidence source-first-release-notes unsigned-dev-artifact source-first-readiness clean-app clean-pkg test verify help clean

CONFIGURATION ?= debug
SIGNING_IDENTITY ?= -
VIFTY_XPC_ALLOWED_TEAM_ID ?=
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
CURRENT_BUILD_SOURCE_REF ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
CURRENT_BUILD_SOURCE_SHA ?= $(shell git rev-parse HEAD 2>/dev/null)
VALIDATION_EVIDENCE_BUNDLE ?=
VALIDATION_EVIDENCE_REVIEW_MODE ?= supported-hardware
VALIDATION_EVIDENCE_REVIEW_SUMMARY ?=
VALIDATION_EVIDENCE_MANUAL_SMOKE_RESULT ?= not-recorded
VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE ?=
VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_RESULT ?= not-recorded
VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SOURCE ?=
VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY ?=
AGENT_EVIDENCE_OUTPUT ?=
AGENT_EVIDENCE_BUNDLE ?=
AGENT_EVIDENCE_REVIEW_SUMMARY ?=
AGENT_RUN_SMOKE_OUTPUT ?=
AGENT_RUN_SMOKE_DURATION ?= 2m
AGENT_RUN_SMOKE_MAX_RPM_PERCENT ?= 55
AGENT_RUN_SMOKE_REASON ?= agent run smoke test
AGENT_RUN_SMOKE_AUDIT_LIMIT ?= 20
APP_NAME := Vifty
APP_DIR := .build/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS := $(CONTENTS)/MacOS
SCHEMAS := $(CONTENTS)/Resources/schemas
APP_ICON := Resources/ViftyIcon.icns
DAEMON_PLIST := $(CONTENTS)/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist

install: CONFIGURATION = release
pkg: CONFIGURATION = release

app: ## Build the release app bundle
	swift build -c $(CONFIGURATION)
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS)"
	mkdir -p "$(SCHEMAS)"
	mkdir -p "$(CONTENTS)/Library/LaunchDaemons"
	cp ".build/$(CONFIGURATION)/Vifty" "$(MACOS)/Vifty"
	cp ".build/$(CONFIGURATION)/ViftyHelper" "$(MACOS)/ViftyHelper"
	cp ".build/$(CONFIGURATION)/ViftyCtl" "$(MACOS)/viftyctl"
	cp ".build/$(CONFIGURATION)/ViftyDaemon" "$(MACOS)/ViftyDaemon"
	cp docs/schemas/*.schema.json "$(SCHEMAS)/"
	install -m 755 scripts/collect-agent-cooling-evidence.sh "$(CONTENTS)/Resources/collect-agent-cooling-evidence.sh"
	install -m 755 scripts/collect-agent-run-smoke-evidence.sh "$(CONTENTS)/Resources/collect-agent-run-smoke-evidence.sh"
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

pkg: ## Build an unsigned installer .pkg
	CONFIGURATION="$(CONFIGURATION)" ./scripts/build-installer-pkg.sh

validation-evidence: ## Collect read-only release/hardware validation evidence
	./scripts/collect-validation-evidence.sh --app "$(VALIDATION_EVIDENCE_APP)" --install-source "$(VALIDATION_EVIDENCE_INSTALL_SOURCE)" $(if $(VALIDATION_EVIDENCE_SOURCE_REF),--source-ref "$(VALIDATION_EVIDENCE_SOURCE_REF)",) $(if $(VALIDATION_EVIDENCE_SOURCE_SHA),--source-sha "$(VALIDATION_EVIDENCE_SOURCE_SHA)",) $(if $(VALIDATION_EVIDENCE_SOURCE_ARTIFACT),--source-artifact "$(VALIDATION_EVIDENCE_SOURCE_ARTIFACT)",) $(if $(VALIDATION_EVIDENCE_RELEASE_SUMMARY),--release-summary "$(VALIDATION_EVIDENCE_RELEASE_SUMMARY)",) $(if $(VALIDATION_EVIDENCE_RELEASE_CHECKLIST),--release-checklist "$(VALIDATION_EVIDENCE_RELEASE_CHECKLIST)",) $(if $(VALIDATION_EVIDENCE_OUTPUT),--output "$(VALIDATION_EVIDENCE_OUTPUT)",) $(if $(filter 1 true yes,$(VALIDATION_EVIDENCE_INCLUDE_PROBE_LOCAL)),--include-probe-local,)

validation-evidence-current-build: ## Build current app and collect read-only local-ad-hoc validation evidence
	@status="$$(git status --porcelain --untracked-files=all 2>/dev/null)"; if [ -n "$$status" ]; then echo "validation-evidence-current-build requires a clean git worktree so source ref/SHA match the built app; commit or stash changes first, or use make validation-evidence with installSource=not-recorded for exploratory local evidence." >&2; exit 65; fi
	$(MAKE) app CONFIGURATION=release SIGNING_IDENTITY="$(SIGNING_IDENTITY)" VIFTY_XPC_ALLOWED_TEAM_ID="$(VIFTY_XPC_ALLOWED_TEAM_ID)"
	$(MAKE) validation-evidence VALIDATION_EVIDENCE_APP="$(APP_DIR)" VALIDATION_EVIDENCE_INSTALL_SOURCE=local-ad-hoc-build VALIDATION_EVIDENCE_SOURCE_REF="$(CURRENT_BUILD_SOURCE_REF)" VALIDATION_EVIDENCE_SOURCE_SHA="$(CURRENT_BUILD_SOURCE_SHA)"

validation-evidence-review: ## Review a captured validation evidence bundle
	@if [ -z "$(VALIDATION_EVIDENCE_BUNDLE)" ]; then echo "VALIDATION_EVIDENCE_BUNDLE is required" >&2; exit 64; fi
	./scripts/review-validation-evidence.sh --bundle "$(VALIDATION_EVIDENCE_BUNDLE)" --mode "$(VALIDATION_EVIDENCE_REVIEW_MODE)" $(if $(VALIDATION_EVIDENCE_REVIEW_SUMMARY),--summary "$(VALIDATION_EVIDENCE_REVIEW_SUMMARY)",) --manual-smoke-result "$(VALIDATION_EVIDENCE_MANUAL_SMOKE_RESULT)" $(if $(VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE),--manual-smoke-source "$(VALIDATION_EVIDENCE_MANUAL_SMOKE_SOURCE)",) --agent-run-smoke-result "$(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_RESULT)" $(if $(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SOURCE),--agent-run-smoke-source "$(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SOURCE)",) $(if $(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY),--agent-run-smoke-summary "$(VALIDATION_EVIDENCE_AGENT_RUN_SMOKE_SUMMARY)",)

agent-cooling-evidence: ## Collect read-only agent/helper support evidence
	./scripts/collect-agent-cooling-evidence.sh --viftyctl "$(VIFTYCTL)" $(if $(AGENT_EVIDENCE_OUTPUT),--output "$(AGENT_EVIDENCE_OUTPUT)",)

agent-cooling-evidence-review: ## Review a read-only agent/helper support evidence bundle
	@if [ -z "$(AGENT_EVIDENCE_BUNDLE)" ]; then echo "AGENT_EVIDENCE_BUNDLE is required" >&2; exit 64; fi
	./scripts/review-agent-cooling-evidence.sh --bundle "$(AGENT_EVIDENCE_BUNDLE)" $(if $(AGENT_EVIDENCE_REVIEW_SUMMARY),--summary "$(AGENT_EVIDENCE_REVIEW_SUMMARY)",)

agent-run-smoke-evidence: ## Collect supervised supported-hardware viftyctl run smoke evidence
	./scripts/collect-agent-run-smoke-evidence.sh --viftyctl "$(VIFTYCTL)" --duration "$(AGENT_RUN_SMOKE_DURATION)" --max-rpm-percent "$(AGENT_RUN_SMOKE_MAX_RPM_PERCENT)" --reason "$(AGENT_RUN_SMOKE_REASON)" --audit-limit "$(AGENT_RUN_SMOKE_AUDIT_LIMIT)" $(if $(AGENT_RUN_SMOKE_OUTPUT),--output "$(AGENT_RUN_SMOKE_OUTPUT)",)

source-first-release-notes: ## Write source-first release notes for the current version
	./scripts/write-release-checklist.sh --mode source-first --version "$(RELEASE_VERSION)" $(if $(SOURCE_FIRST_SOURCE_REF),--source-ref "$(SOURCE_FIRST_SOURCE_REF)",)

unsigned-dev-artifact: ## Build source-first unsigned tester zip and checksum
	./scripts/build-unsigned-dev-artifact.sh --version "$(RELEASE_VERSION)" $(if $(UNSIGNED_DEV_SOURCE_REF),--require-source-ref "$(UNSIGNED_DEV_SOURCE_REF)",)

source-first-readiness: ## Check published source-first release readiness
	./scripts/check-release-readiness.sh --mode source-first --version "$(RELEASE_VERSION)" --repo "$(RELEASE_REPO)" --json

test: ## Run the XCTest suite
	swift test

verify: ## Run local trust gates without installing
	/bin/bash -n scripts/*.sh examples/viftyctl/*.sh
	scripts/check-community-standards.sh
	scripts/validate-release-metadata.sh --mode "$(RELEASE_METADATA_MODE)"
	swift test
	swift build -Xswiftc -warnings-as-errors
	$(MAKE) app CONFIGURATION=release SIGNING_IDENTITY="$(SIGNING_IDENTITY)" VIFTY_XPC_ALLOWED_TEAM_ID="$(VIFTY_XPC_ALLOWED_TEAM_ID)"
	plutil -lint "$(CONTENTS)/Info.plist"
	plutil -lint "$(DAEMON_PLIST)"
	test -x "$(CONTENTS)/Resources/collect-agent-cooling-evidence.sh"
	test -x "$(CONTENTS)/Resources/collect-agent-run-smoke-evidence.sh"
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
