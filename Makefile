.PHONY: app install pkg clean-app clean-pkg

CONFIGURATION ?= debug
APP_NAME := Vifty
APP_DIR := .build/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS := $(CONTENTS)/MacOS

install: CONFIGURATION = release
pkg: CONFIGURATION = release

app:
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
	codesign --force --sign - "$(MACOS)/ViftyHelper"
	codesign --force --sign - "$(MACOS)/ViftyDaemon"
	codesign --force --sign - --identifier tech.reidar.vifty.ctl "$(MACOS)/viftyctl"
	codesign --force --sign - "$(APP_DIR)"
	@echo "Built $(APP_DIR)"

install:
	CONFIGURATION="$(CONFIGURATION)" ./scripts/install-vifty.sh

pkg:
	CONFIGURATION="$(CONFIGURATION)" ./scripts/build-installer-pkg.sh

clean-app:
	rm -rf "$(APP_DIR)"

clean-pkg:
	rm -rf .build/pkg-root .build/$(APP_NAME)-*.pkg
