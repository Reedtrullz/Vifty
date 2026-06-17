.PHONY: app install pkg agent-cooling-evidence agent-cooling-evidence-review agent-run-smoke-evidence source-first-release-notes unsigned-dev-artifact source-first-readiness clean-app clean-pkg test verify help clean

CONFIGURATION ?= debug
SIGNING_IDENTITY ?= -
VIFTY_XPC_ALLOWED_TEAM_ID ?=
RELEASE_VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
RELEASE_REPO ?= Reedtrullz/Vifty
SOURCE_FIRST_SOURCE_REF ?= v$(RELEASE_VERSION)
UNSIGNED_DEV_SOURCE_REF ?= v$(RELEASE_VERSION)
RELEASE_METADATA_MODE ?= source-first
VIFTYCTL ?= /Applications/Vifty.app/Contents/MacOS/viftyctl
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
