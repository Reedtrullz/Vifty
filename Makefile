.PHONY: app install pkg clean-app clean-pkg test help clean

CONFIGURATION ?= debug
SIGNING_IDENTITY ?= -
APP_NAME := Vifty
APP_DIR := .build/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS := $(CONTENTS)/MacOS

install: CONFIGURATION = release
pkg: CONFIGURATION = release

app: ## Build the release app bundle
	swift build -c $(CONFIGURATION)
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS)"
	mkdir -p "$(CONTENTS)/Library/LaunchDaemons"
	cp ".build/$(CONFIGURATION)/Vifty" "$(MACOS)/Vifty"
	cp ".build/$(CONFIGURATION)/ViftyHelper" "$(MACOS)/ViftyHelper"
	cp ".build/$(CONFIGURATION)/ViftyCtl" "$(MACOS)/viftyctl"
	cp ".build/$(CONFIGURATION)/ViftyDaemon" "$(MACOS)/ViftyDaemon"
	cp "Resources/Info.plist" "$(CONTENTS)/Info.plist"
	cp "Resources/tech.reidar.vifty.daemon.plist" "$(CONTENTS)/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime "$(MACOS)/ViftyHelper"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime "$(MACOS)/ViftyDaemon"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime --identifier tech.reidar.vifty.ctl "$(MACOS)/viftyctl"
	codesign --force --sign "$(SIGNING_IDENTITY)" --options runtime --entitlements Resources/Vifty.entitlements "$(APP_DIR)"
	@echo "Built $(APP_DIR)"

install: ## Build and install to /Applications
	CONFIGURATION="$(CONFIGURATION)" ./scripts/install-vifty.sh

pkg: ## Build an unsigned installer .pkg
	CONFIGURATION="$(CONFIGURATION)" ./scripts/build-installer-pkg.sh

test: ## Run the XCTest suite
	swift test

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

clean: clean-app ## Remove all build artifacts
	rm -rf .build/

clean-app:
	rm -rf "$(APP_DIR)"

clean-pkg:
	rm -rf .build/pkg-root .build/$(APP_NAME)-*.pkg
