SHELL := /bin/zsh
CONFIGURATION ?= debug
# Oldest supported macOS, matching .macOS(.v11) in Package.swift. Xcode 26 and later can't
# deploy below macOS 12 and silently raise it, so releases are built with Xcode 16.4.
MACOS_MIN := 11.0
# Optional, git-ignored per-machine overrides (see Local.mk.example).
-include Local.mk
# Universal build.
SWIFT_BUILD_FLAGS := -c $(CONFIGURATION) --arch arm64 --arch x86_64
BUILD_DIR := build
APP_DIR := $(BUILD_DIR)/Scroblebler.app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
FRAMEWORKS_DIR := $(CONTENTS_DIR)/Frameworks
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
# The products directory differs between toolchains, so ask SwiftPM for it.
SWIFT_BIN_DIR := $(shell swift build $(SWIFT_BUILD_FLAGS) --show-bin-path)
# macOS 11 has no Swift concurrency runtime in the OS; embed the toolchain's back-deployment copy.
SWIFT_BACKDEPLOY_LIBS := $(shell dirname "$$(xcrun --find swift)")/../lib/swift-5.5/macosx
MEDIAREMOTE_CONTROLLER := .build/checkouts/mediaremote-adapter/Sources/MediaRemoteAdapter/MediaController.swift
TEAM_ID ?= B65K228Z97
# Developer ID keeps the same code identity across builds, so keychain and other permissions
# survive rebuilds. Without the certificate (e.g. CI builds of branches) the app is signed ad hoc.
CODE_SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application.*$(TEAM_ID)/ {print $$2; exit}')
INSTALL_APP_DIR ?= /Applications/Scroblebler.app
RELEASE_ZIP ?= $(BUILD_DIR)/Scroblebler.zip
ENTITLEMENTS := Scroblebler/Scroblebler.entitlements
EXPANDED_ENTITLEMENTS := $(BUILD_DIR)/Scroblebler.entitlements
APP_IDENTIFIER_PREFIX ?= $(TEAM_ID).

.PHONY: test build app sign verify release-zip reinstall run clean

test:
	swift test

build:
	swift package resolve
	@# MediaRemoteAdapter passes its own executable to a Perl helper, but Bundle(for:) finds the
	@# app instead of the dylib. Point it at the dylib in the app's Frameworks folder.
	perl -0pi -e 's|(private var libraryPath: String\? \{\n)|$$1        if let fw = Bundle.main.privateFrameworksPath {\n            let p = (fw as NSString).appendingPathComponent("libMediaRemoteAdapter.dylib")\n            if FileManager.default.fileExists(atPath: p) { return p }\n        }\n| unless /privateFrameworksPath/' $(MEDIAREMOTE_CONTROLLER)
	grep -q privateFrameworksPath $(MEDIAREMOTE_CONTROLLER)
	swift build $(SWIFT_BUILD_FLAGS)

app: build
	rm -rf $(APP_DIR)
	mkdir -p $(MACOS_DIR) $(FRAMEWORKS_DIR) $(RESOURCES_DIR)
	# Binary
	cp $(SWIFT_BIN_DIR)/Scroblebler $(MACOS_DIR)/Scroblebler
	install_name_tool -add_rpath @executable_path/../Frameworks $(MACOS_DIR)/Scroblebler
	# Info.plist
	cp Resources/Info.plist $(CONTENTS_DIR)/Info.plist
	plutil -replace LSMinimumSystemVersion -string $(MACOS_MIN) $(CONTENTS_DIR)/Info.plist
	# App icon
	cp Resources/AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns
	# Compile asset catalog (produces Assets.car with all image assets)
	xcrun actool Scroblebler/Assets.xcassets \
		--compile $(RESOURCES_DIR) \
		--platform macosx \
		--minimum-deployment-target $(MACOS_MIN) \
		--app-icon AppIcon \
		--output-partial-info-plist /dev/null 2>/dev/null || true
	# Sparkle framework
	cp -R $(SWIFT_BIN_DIR)/Sparkle.framework $(FRAMEWORKS_DIR)/Sparkle.framework
	# MediaRemote adapter dylib
	cp $(SWIFT_BIN_DIR)/libMediaRemoteAdapter.dylib $(FRAMEWORKS_DIR)/libMediaRemoteAdapter.dylib
	# MediaRemote adapter SPM resource bundle (contains run.pl for Perl subprocess)
	cp -R $(SWIFT_BIN_DIR)/MediaRemoteAdapter_MediaRemoteAdapter.bundle $(RESOURCES_DIR)/
	# Swift runtime libraries missing from the oldest supported macOS
	xcrun swift-stdlib-tool --copy --platform macosx \
		--source-libraries "$(SWIFT_BACKDEPLOY_LIBS)" \
		--scan-executable $(MACOS_DIR)/Scroblebler \
		--scan-executable $(FRAMEWORKS_DIR)/libMediaRemoteAdapter.dylib \
		--destination $(FRAMEWORKS_DIR)
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
		for dylib in "$(FRAMEWORKS_DIR)/"*.dylib; do \
			codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" "$$dylib"; \
		done; \
		sed 's/$$(AppIdentifierPrefix)/$(APP_IDENTIFIER_PREFIX)/g' $(ENTITLEMENTS) > $(EXPANDED_ENTITLEMENTS); \
		codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" --entitlements $(EXPANDED_ENTITLEMENTS) "$(APP_DIR)"; \
	fi

# Releases must run on Intel and Apple silicon Macs with the oldest macOS in Info.plist.
verify:
	codesign --verify --deep --strict $(APP_DIR)
	for bin in $(MACOS_DIR)/Scroblebler $(FRAMEWORKS_DIR)/libMediaRemoteAdapter.dylib $(FRAMEWORKS_DIR)/Sparkle.framework/Sparkle; do \
		{ lipo "$$bin" -verify_arch x86_64 && lipo "$$bin" -verify_arch arm64; } || { echo "$$bin is not universal"; exit 1; }; \
	done
	APP_MIN=$$(plutil -extract LSMinimumSystemVersion raw $(CONTENTS_DIR)/Info.plist); \
	SPARKLE_MIN=$$(plutil -extract LSMinimumSystemVersion raw $(FRAMEWORKS_DIR)/Sparkle.framework/Resources/Info.plist); \
	vtool -arch x86_64 -show-build $(MACOS_DIR)/Scroblebler | grep -q "minos $$APP_MIN$$" \
		|| { echo "The x86_64 slice does not target macOS $$APP_MIN"; exit 1; }; \
	[ "$$(printf '%s\n' $$SPARKLE_MIN $$APP_MIN | sort -V | tail -1)" = "$$APP_MIN" ] \
		|| { echo "Sparkle needs macOS $$SPARKLE_MIN, the app supports $$APP_MIN"; exit 1; }; \
	echo "Universal app for macOS $$APP_MIN (Sparkle needs $$SPARKLE_MIN)"

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
