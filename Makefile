SHELL := /bin/zsh
CONFIGURATION ?= debug
SWIFT_BUILD_FLAGS := -c $(CONFIGURATION)
BUILD_DIR := build
APP_DIR := $(BUILD_DIR)/Scroblebler.app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
FRAMEWORKS_DIR := $(CONTENTS_DIR)/Frameworks
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
SWIFT_BIN_DIR := .build/$(CONFIGURATION)
SPARKLE_FRAMEWORK := $(SWIFT_BIN_DIR)/Sparkle.framework
MEDIAREMOTE_DYLIB = $(shell find .build -path '*/$(CONFIGURATION)/libMediaRemoteAdapter.dylib' -type f -print -quit)
TEAM_ID ?= B65K228Z97
ifeq ($(CONFIGURATION),release)
CODE_SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/$(TEAM_ID)/ {print $$2; exit}')
else
CODE_SIGN_IDENTITY ?=
endif
INSTALL_APP_DIR ?= /Applications/Scroblebler.app
RELEASE_ZIP ?= $(BUILD_DIR)/Scroblebler.zip
ENTITLEMENTS := Scroblebler/Scroblebler.entitlements
EXPANDED_ENTITLEMENTS := $(BUILD_DIR)/Scroblebler.entitlements
APP_IDENTIFIER_PREFIX ?= $(TEAM_ID).

.PHONY: build app sign release-zip reinstall run clean

build:
	swift build $(SWIFT_BUILD_FLAGS)

app: build
	rm -rf $(APP_DIR)
	mkdir -p $(MACOS_DIR) $(FRAMEWORKS_DIR) $(RESOURCES_DIR)
	# Binary
	cp $(SWIFT_BIN_DIR)/Scroblebler $(MACOS_DIR)/Scroblebler
	install_name_tool -add_rpath @executable_path/../Frameworks $(MACOS_DIR)/Scroblebler
	# Info.plist
	cp Resources/Info.plist $(CONTENTS_DIR)/Info.plist
	# App icon
	cp Resources/AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns
	# Compile asset catalog (produces Assets.car with all image assets)
	xcrun actool Scroblebler/Assets.xcassets \
		--compile $(RESOURCES_DIR) \
		--platform macosx \
		--minimum-deployment-target 11.0 \
		--app-icon AppIcon \
		--output-partial-info-plist /dev/null 2>/dev/null || true
	# Sparkle framework
	cp -R $(SPARKLE_FRAMEWORK) $(FRAMEWORKS_DIR)/Sparkle.framework
	# MediaRemote adapter dylib
	cp $(MEDIAREMOTE_DYLIB) $(FRAMEWORKS_DIR)/libMediaRemoteAdapter.dylib
	# Sign
	$(MAKE) sign

sign:
	@if [ -z "$(CODE_SIGN_IDENTITY)" ]; then \
		echo "⚠️  No Developer ID found for Team $(TEAM_ID), using ad-hoc signing"; \
		codesign --force --deep --sign - $(APP_DIR); \
	else \
		echo "🔏 Signing with: $(CODE_SIGN_IDENTITY)"; \
		for xpc in "$(FRAMEWORKS_DIR)/Sparkle.framework/Versions/B/XPCServices/"*.xpc; do \
			[ -d "$$xpc" ] && codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" "$$xpc"; \
		done; \
		codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" "$(FRAMEWORKS_DIR)/Sparkle.framework/Versions/B/Autoupdate"; \
		codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" "$(FRAMEWORKS_DIR)/Sparkle.framework/Versions/B/Updater.app"; \
		codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" "$(FRAMEWORKS_DIR)/Sparkle.framework"; \
		codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" "$(FRAMEWORKS_DIR)/libMediaRemoteAdapter.dylib"; \
		sed 's/$$(AppIdentifierPrefix)/$(APP_IDENTIFIER_PREFIX)/g' $(ENTITLEMENTS) > $(EXPANDED_ENTITLEMENTS); \
		codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" --entitlements $(EXPANDED_ENTITLEMENTS) "$(APP_DIR)"; \
	fi

release-zip: app
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(APP_DIR)" "$(RELEASE_ZIP)"

reinstall: app
	@if pgrep -f "$(INSTALL_APP_DIR)/Contents/MacOS/Scroblebler" >/dev/null; then \
		pkill -f "$(INSTALL_APP_DIR)/Contents/MacOS/Scroblebler"; \
		sleep 1; \
	fi
	rm -rf "$(INSTALL_APP_DIR)"
	cp -R "$(APP_DIR)" "$(INSTALL_APP_DIR)"
	open "$(INSTALL_APP_DIR)"

run: app
	open $(APP_DIR)

clean:
	rm -rf .build build
