.PHONY: app clean-app

CONFIGURATION ?= debug
APP_NAME := Vifty
APP_DIR := .build/$(APP_NAME).app
CONTENTS := $(APP_DIR)/Contents
MACOS := $(CONTENTS)/MacOS

app:
	swift build -c $(CONFIGURATION)
	rm -rf "$(APP_DIR)"
	mkdir -p "$(MACOS)"
	mkdir -p "$(CONTENTS)/Library/LaunchDaemons"
	cp ".build/$(CONFIGURATION)/Vifty" "$(MACOS)/Vifty"
	cp ".build/$(CONFIGURATION)/ViftyHelper" "$(MACOS)/ViftyHelper"
	cp ".build/$(CONFIGURATION)/ViftyDaemon" "$(MACOS)/ViftyDaemon"
	cp "Resources/Info.plist" "$(CONTENTS)/Info.plist"
	cp "Resources/tech.reidar.vifty.daemon.plist" "$(CONTENTS)/Library/LaunchDaemons/tech.reidar.vifty.daemon.plist"
	codesign --force --deep --sign - "$(APP_DIR)"
	@echo "Built $(APP_DIR)"

clean-app:
	rm -rf "$(APP_DIR)"
