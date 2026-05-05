# Code Signing, Sparkle & Build Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use subagent-driven-development (recommended) or executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate Scroblebler to Developer ID signing, notarization, Sparkle 2.x auto-updates, Cocogitto versioning, and SPM+Makefile builds — matching the adrenaline project pattern.

**Architecture:** `swift build` compiles the binary; a Makefile assembles the `.app` bundle (binary + frameworks + resources + Info.plist), signs it inside-out with Developer ID, and packages as ZIP. GitHub Actions CI handles notarization, Sparkle EdDSA signing, appcast publishing, and GitHub Release creation. Cocogitto drives conventional-commit versioning.

**Tech Stack:** Swift 5.9, SPM, Sparkle 2.7+, Cocogitto, GitHub Actions, `codesign`, `notarytool`, `actool`

---

### Task 1: Generate AppIcon.icns from existing asset catalog

The Makefile build needs a standalone `.icns` file since `swift build` doesn't compile asset catalogs. Convert the existing PNG icons to an `.icns` bundle.

**Files:**
- Create: `Resources/AppIcon.icns`
- Create: `Scripts/generate-app-icon.sh`

- [ ] **Step 1: Create the icon generation script**

```bash
#!/bin/bash
set -e
# Generate AppIcon.icns from existing PNG icons in the asset catalog.
# Usage: ./Scripts/generate-app-icon.sh

ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET_DIR"

SRC="Scroblebler/Assets.xcassets/AppIcon.appiconset"

cp "$SRC/icon_16x16.png"       "$ICONSET_DIR/icon_16x16.png"
cp "$SRC/icon_16x16@2x@2x.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$SRC/icon_32x32.png"       "$ICONSET_DIR/icon_32x32.png"
cp "$SRC/icon_32x32@2x@2x.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$SRC/icon_128x128.png"     "$ICONSET_DIR/icon_128x128.png"
cp "$SRC/icon_128x128@2x@2x.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$SRC/icon_256x256.png"     "$ICONSET_DIR/icon_256x256.png"
cp "$SRC/icon_256x256@2x@2x.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$SRC/icon_512x512.png"     "$ICONSET_DIR/icon_512x512.png"
cp "$SRC/icon_512x512@2x@2x.png" "$ICONSET_DIR/icon_512x512@2x.png"

mkdir -p Resources
iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns
rm -rf "$(dirname "$ICONSET_DIR")"
echo "✓ Generated Resources/AppIcon.icns"
```

- [ ] **Step 2: Run the script to generate the icns file**

Run: `chmod +x Scripts/generate-app-icon.sh && ./Scripts/generate-app-icon.sh`
Expected: `✓ Generated Resources/AppIcon.icns` — file exists at `Resources/AppIcon.icns`

- [ ] **Step 3: Commit**

```bash
git add Scripts/generate-app-icon.sh Resources/AppIcon.icns
git commit -m "chore: generate AppIcon.icns from asset catalog PNGs"
```

---

### Task 2: Create Resources/Info.plist for SPM builds

The SPM build needs a standalone Info.plist with literal values (no Xcode variable expansion). This includes Sparkle keys for auto-update.

**Files:**
- Create: `Resources/Info.plist`

- [ ] **Step 1: Create the Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Scroblebler</string>
	<key>CFBundleExecutable</key>
	<string>Scroblebler</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.tonioriol.scroblebler</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Scroblebler</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1.0.0</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.music</string>
	<key>LSMinimumSystemVersion</key>
	<string>11.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSAppleMusicUsageDescription</key>
	<string>Scroblebler reads your music library to backfill plays from other devices (iPhone, HomePod, CarPlay).</string>
	<key>SUEnableAutomaticChecks</key>
	<true/>
	<key>SUFeedURL</key>
	<string>https://tonioriol.github.io/scroblebler/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>PLACEHOLDER_GENERATE_WITH_SPARKLE_TOOLS</string>
	<key>SUScheduledCheckInterval</key>
	<integer>86400</integer>
</dict>
</plist>
```

Note: `LSUIElement = true` makes this a menu bar app (no dock icon). `SUPublicEDKey` will be replaced with the real key in Task 6.

- [ ] **Step 2: Commit**

```bash
git add Resources/Info.plist
git commit -m "chore: add standalone Info.plist for SPM builds with Sparkle keys"
```

---

### Task 3: Add Sparkle dependency and create SparkleUpdaterController

**Files:**
- Modify: `Package.swift`
- Create: `Scroblebler/SparkleUpdaterController.swift`
- Modify: `Scroblebler/AppDelegate.swift`

- [ ] **Step 1: Add Sparkle to Package.swift**

In `Package.swift`, add to the `dependencies` array:

```swift
.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
```

And add to the `Scroblebler` executable target's `dependencies`:

```swift
.product(name: "Sparkle", package: "Sparkle"),
```

- [ ] **Step 2: Resolve packages**

Run: `swift package resolve`
Expected: Sparkle package downloaded successfully.

- [ ] **Step 3: Create SparkleUpdaterController.swift**

```swift
import Foundation
import Sparkle

/// Minimal Sparkle updater wrapper.
/// Starts automatic update checks on init; exposes manual check for future UI.
@MainActor
final class SparkleUpdaterController {
    private var controller: SPUStandardUpdaterController!

    init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
```

- [ ] **Step 4: Wire Sparkle into AppDelegate**

In `Scroblebler/AppDelegate.swift`, add a property after the existing properties (line 17):

```swift
private var updater: SparkleUpdaterController?
```

At the end of `applicationDidFinishLaunching` (before `NSApp.activate`), add:

```swift
// Start Sparkle auto-update checks
updater = SparkleUpdaterController()
```

Also add `import Sparkle` is NOT needed — `SparkleUpdaterController` encapsulates the import.

- [ ] **Step 5: Add SparkleUpdaterController.swift to Xcode project**

The `.xcodeproj` needs to know about the new file for IDE builds. Use the xcode file tool:

```
projectPath: Scroblebler.xcodeproj
targetName: Scroblebler
action: add
files: [{ path: "Scroblebler/SparkleUpdaterController.swift", group: "Scroblebler" }]
```

- [ ] **Step 6: Verify it compiles**

Run: `swift build 2>&1 | tail -5`
Expected: Build succeeds (Sparkle framework links correctly).

- [ ] **Step 7: Commit**

```bash
git add Package.swift Package.resolved Scroblebler/SparkleUpdaterController.swift Scroblebler/AppDelegate.swift Scroblebler.xcodeproj/project.pbxproj
git commit -m "feat: add Sparkle 2.x auto-update support"
```

---

### Task 4: Create the Makefile

This is the core of the build migration. The Makefile assembles a proper `.app` bundle from `swift build` output, compiles the asset catalog, signs everything, and produces a release ZIP.

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Create the Makefile**

```makefile
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
TEAM_ID ?= B65K228Z97
CODE_SIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/$(TEAM_ID)/ {print $$2; exit}')
INSTALL_APP_DIR ?= /Applications/Scroblebler.app
RELEASE_ZIP ?= $(BUILD_DIR)/Scroblebler.zip
ENTITLEMENTS := Scroblebler/Scroblebler.entitlements

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
		codesign --force --options runtime --sign "$(CODE_SIGN_IDENTITY)" --entitlements $(ENTITLEMENTS) "$(APP_DIR)"; \
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
```

- [ ] **Step 2: Test the build locally**

Run: `make app 2>&1 | tail -10`
Expected: Build succeeds, `build/Scroblebler.app` exists. If no Developer ID cert is found, ad-hoc signing is used.

- [ ] **Step 3: Test the app launches**

Run: `make run`
Expected: Scroblebler launches in the menu bar, functions normally.

- [ ] **Step 4: Test release-zip**

Run: `make release-zip && ls -la build/Scroblebler.zip`
Expected: ZIP file exists.

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "feat: add Makefile for SPM-based app bundle assembly and signing"
```

---

### Task 5: Switch versioning to Cocogitto

Replace semantic-release with Cocogitto for conventional-commit driven releases.

**Files:**
- Create: `cog.toml`
- Delete: `.releaserc.json`
- Delete: `scripts/release.sh`
- Delete: `scripts/build.sh`

- [ ] **Step 1: Create cog.toml**

```toml
tag_prefix = "v"
branch_whitelist = ["main"]
ignore_merge_commits = true
skip_ci = "[skip ci]"

pre_bump_hooks = [
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString {{version}}' -c 'Set :CFBundleVersion {{version}}' Resources/Info.plist",
]

[changelog]
path = "CHANGELOG.md"
template = "remote"
remote = "github.com"
owner = "tonioriol"
repository = "scroblebler"
```

- [ ] **Step 2: Remove old release tooling**

```bash
rm -f .releaserc.json scripts/release.sh scripts/build.sh
```

If `scripts/` directory is now empty (only had those two files), remove it:
```bash
rmdir scripts 2>/dev/null || true
```

Note: `Scripts/generate-app-icon.sh` (capital S) was created in Task 1 and stays.

- [ ] **Step 3: Verify cog can read the config**

Run: `cog check 2>&1 | tail -5` (if cocogitto is installed locally)
If not installed: `brew install cocogitto && cog check`

- [ ] **Step 4: Commit**

```bash
git add cog.toml
git rm .releaserc.json scripts/release.sh scripts/build.sh
git commit -m "feat: switch versioning from semantic-release to cocogitto"
```

---

### Task 6: Generate Sparkle EdDSA keypair

Generate the EdDSA keypair for Sparkle update signing. The public key goes into Info.plist, the private key becomes a GitHub Secret.

**Files:**
- Modify: `Resources/Info.plist` (replace placeholder SUPublicEDKey)

- [ ] **Step 1: Download Sparkle tools and generate keys**

```bash
SPARKLE_VERSION=$(python3 -c "
import json
with open('Package.resolved') as f:
    data = json.load(f)
for pin in data['pins']:
    if pin['identity'] == 'sparkle':
        print(pin['state']['version'])
        break
")
curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
  | tar -xJf - -C /tmp/sparkle-tools "./bin/generate_keys" "./bin/sign_update"
/tmp/sparkle-tools/bin/generate_keys
```

Expected output:
```
A]  key: <base64 private key>
B] key: <base64 public key>
```

Save the private key (line A) — it will be added as GitHub Secret `SPARKLE_ED_PRIVATE_KEY`.

- [ ] **Step 2: Update Info.plist with the public key**

Replace the `SUPublicEDKey` placeholder in `Resources/Info.plist` with the actual public key (line B from the generate_keys output):

```bash
sd 'PLACEHOLDER_GENERATE_WITH_SPARKLE_TOOLS' 'THE_ACTUAL_PUBLIC_KEY_HERE' Resources/Info.plist
```

- [ ] **Step 3: Commit**

```bash
git add Resources/Info.plist
git commit -m "feat: add Sparkle EdDSA public key for update verification"
```

- [ ] **Step 4: Store the private key as GitHub Secret**

```bash
gh secret set SPARKLE_ED_PRIVATE_KEY --body "THE_ACTUAL_PRIVATE_KEY_HERE"
```

---

### Task 7: Set up GitHub Secrets for signing and notarization

Configure all the secrets needed by the CI pipeline. These are the same secrets used by adrenaline.

**Files:** None (GitHub Secrets only)

- [ ] **Step 1: Export Developer ID certificate as base64**

On the Mac with the cert in Keychain:
```bash
# Export from Keychain Access as .p12, then:
base64 -i DeveloperID.p12 | pbcopy
```

- [ ] **Step 2: Set all GitHub Secrets**

```bash
gh secret set APPLE_DEVELOPER_ID_CERTIFICATE_BASE64 --body "$(pbpaste)"
gh secret set APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD --body "YOUR_P12_PASSWORD"
gh secret set APPLE_ID --body "your@apple.id"
gh secret set APPLE_TEAM_ID --body "B65K228Z97"
gh secret set APPLE_APP_SPECIFIC_PASSWORD --body "xxxx-xxxx-xxxx-xxxx"
gh secret set APPLE_NOTARYTOOL_PROFILE --body "scroblebler-notarize"
# SPARKLE_ED_PRIVATE_KEY was set in Task 6
# TAP_GITHUB_TOKEN should already exist from the old workflow
```

- [ ] **Step 3: Verify secrets are set**

Run: `gh secret list`
Expected: All 7 secrets listed (APPLE_DEVELOPER_ID_CERTIFICATE_BASE64, APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD, APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_NOTARYTOOL_PROFILE, SPARKLE_ED_PRIVATE_KEY, TAP_GITHUB_TOKEN).

---

### Task 8: Create the gh-pages branch with appcast.xml

Set up the GitHub Pages branch that hosts the Sparkle appcast feed.

**Files:**
- Create: `appcast.xml` (on gh-pages branch)

- [ ] **Step 1: Create the gh-pages branch with appcast scaffold**

```bash
git checkout --orphan gh-pages
git rm -rf .
cat > appcast.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Scroblebler</title>
        <link>https://tonioriol.github.io/scroblebler/appcast.xml</link>
        <description>Scroblebler updates</description>
        <language>en</language>
    </channel>
</rss>
EOF
git add appcast.xml
git commit -m "chore: initialize appcast for Sparkle auto-updates"
git push origin gh-pages
git checkout main
```

- [ ] **Step 2: Enable GitHub Pages**

Go to repo Settings → Pages → Source: "Deploy from a branch" → Branch: `gh-pages` / `/ (root)`.

Or via CLI:
```bash
gh api repos/tonioriol/scroblebler/pages -X POST -f source='{"branch":"gh-pages","path":"/"}' 2>/dev/null || echo "Pages may already be configured"
```

- [ ] **Step 3: Verify the appcast is accessible**

Run: `curl -s https://tonioriol.github.io/scroblebler/appcast.xml | head -5`
Expected: The XML content is returned (may take a minute for Pages to deploy).

---

### Task 9: Create the GitHub Actions release workflow

The main CI pipeline that handles the entire release flow: version bump, build, sign, notarize, Sparkle sign, GitHub Release, appcast update, Homebrew tap.

**Files:**
- Create: `.github/workflows/release.yml`
- Delete: `.github/workflows/update-tap.yml`

- [ ] **Step 1: Delete the old tap-update workflow**

```bash
git rm .github/workflows/update-tap.yml
```

- [ ] **Step 2: Create the release workflow**

Create `.github/workflows/release.yml` with the following content (adapted from adrenaline's workflow, using `make` instead of the adrenaline-specific build):

```yaml
name: Release

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: write

concurrency:
  group: release
  cancel-in-progress: false

jobs:
  decide:
    runs-on: ubuntu-latest
    outputs:
      will_release: ${{ steps.dryrun.outputs.will_release }}
      next_version: ${{ steps.dryrun.outputs.next_version }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install Cocogitto
        uses: cocogitto/cocogitto-action@v3

      - name: Compute next version
        id: dryrun
        shell: bash
        run: |
          set -euo pipefail
          if RAW="$(cog bump --auto --dry-run 2>/dev/null)"; then
            NEXT="${RAW#v}"
            echo "will_release=true" >> "$GITHUB_OUTPUT"
            echo "next_version=$NEXT" >> "$GITHUB_OUTPUT"
            echo "Next version: $NEXT"
          else
            echo "will_release=false" >> "$GITHUB_OUTPUT"
            echo "No releasable commits since last tag"
          fi

  release:
    needs: decide
    if: needs.decide.outputs.will_release == 'true'
    runs-on: macos-14
    env:
      NEXT_VERSION: ${{ needs.decide.outputs.next_version }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          persist-credentials: true

      - name: Install Cocogitto
        run: brew install cocogitto

      - name: Configure git for cog bump
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

      - name: Import Developer ID certificate
        env:
          CERTIFICATE_BASE64: ${{ secrets.APPLE_DEVELOPER_ID_CERTIFICATE_BASE64 }}
          CERTIFICATE_PASSWORD: ${{ secrets.APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD }}
          CERTIFICATE_PATH: ${{ runner.temp }}/certificate.p12
          KEYCHAIN_PATH: ${{ runner.temp }}/build.keychain
          KEYCHAIN_PASSWORD_FILE: ${{ runner.temp }}/keychain-password
        run: |
          set -euo pipefail
          echo "$(uuidgen)" > "$KEYCHAIN_PASSWORD_FILE"
          security create-keychain -p "$(cat "$KEYCHAIN_PASSWORD_FILE")" "$KEYCHAIN_PATH"
          security default-keychain -s "$KEYCHAIN_PATH"
          security unlock-keychain -p "$(cat "$KEYCHAIN_PASSWORD_FILE")" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          echo "$CERTIFICATE_BASE64" | base64 --decode > "$CERTIFICATE_PATH"
          security import "$CERTIFICATE_PATH" -k "$KEYCHAIN_PATH" -P "$CERTIFICATE_PASSWORD" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(cat "$KEYCHAIN_PASSWORD_FILE")" "$KEYCHAIN_PATH"
          CODE_SIGN_IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
          if [ -z "$CODE_SIGN_IDENTITY" ]; then
            echo "No Developer ID Application signing identity found" >&2
            exit 1
          fi
          echo "CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY" >> "$GITHUB_ENV"

      - name: Configure notarytool profile
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
          APPLE_NOTARYTOOL_PROFILE: ${{ secrets.APPLE_NOTARYTOOL_PROFILE }}
        run: |
          set -euo pipefail
          xcrun notarytool store-credentials "$APPLE_NOTARYTOOL_PROFILE" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_SPECIFIC_PASSWORD"

      - name: Bump version
        run: |
          set -euo pipefail
          cog bump --version "${NEXT_VERSION}"
          echo "Bumped to ${NEXT_VERSION}; tag v${NEXT_VERSION} created locally"

      - name: Build signed app
        run: |
          set -euo pipefail
          make release-zip CONFIGURATION=release CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
          codesign --verify --deep --strict --verbose=2 build/Scroblebler.app

      - name: Notarize app zip
        env:
          APPLE_NOTARYTOOL_PROFILE: ${{ secrets.APPLE_NOTARYTOOL_PROFILE }}
        run: |
          set -euo pipefail
          xcrun notarytool submit build/Scroblebler.zip --keychain-profile "$APPLE_NOTARYTOOL_PROFILE" --wait
          xcrun stapler staple build/Scroblebler.app
          xcrun stapler validate build/Scroblebler.app
          spctl --assess --type execute --verbose=4 build/Scroblebler.app
          rm -f build/Scroblebler.zip
          ditto -c -k --keepParent build/Scroblebler.app "build/Scroblebler-v${NEXT_VERSION}.zip"

      - name: Sign update with EdDSA
        shell: bash
        env:
          SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}
        run: |
          set -euo pipefail
          SPARKLE_VERSION=$(python3 -c "
          import json
          with open('Package.resolved') as f:
              data = json.load(f)
          for pin in data['pins']:
              if pin['identity'] == 'sparkle':
                  print(pin['state']['version'])
                  break
          else:
              raise SystemExit('Sparkle pin not found')
          ")
          curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
            | tar -xJf - -C "$RUNNER_TEMP" "./bin/sign_update"
          SIGN_UPDATE="$RUNNER_TEMP/bin/sign_update"
          SIG_AND_LEN=$("$SIGN_UPDATE" --ed-key-file <(printf "%s" "$SPARKLE_ED_PRIVATE_KEY") "build/Scroblebler-v${NEXT_VERSION}.zip")
          echo "SPARKLE_SIG_AND_LEN=$SIG_AND_LEN" >> "$GITHUB_ENV"

      - name: Update cask formula
        env:
          VERSION: ${{ env.NEXT_VERSION }}
        run: |
          set -euo pipefail
          SHA=$(shasum -a 256 "build/Scroblebler-v${VERSION}.zip" | awk '{print $1}')
          /usr/bin/sed -i '' \
            -e 's|^  version ".*"$|  version "'"${VERSION}"'"|' \
            -e 's|^  sha256 ".*"$|  sha256 "'"${SHA}"'"|' \
            scroblebler.rb
          git add scroblebler.rb
          git commit --amend --no-edit
          git tag -f "v${VERSION}" HEAD
          echo "Cask formula updated to ${VERSION} (sha256 ${SHA})"

      - name: Push commit and tag
        run: |
          set -euo pipefail
          git push --force-with-lease origin HEAD
          git push --force origin "v${NEXT_VERSION}"

      - name: Create GitHub Release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        shell: bash
        run: |
          set -euo pipefail
          cog changelog --at "v${NEXT_VERSION}" > release-notes.md
          gh release create "v${NEXT_VERSION}" \
            --title "v${NEXT_VERSION}" \
            --notes-file release-notes.md \
            "build/Scroblebler-v${NEXT_VERSION}.zip"

      - name: Publish appcast entry
        shell: bash
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          VERSION: ${{ env.NEXT_VERSION }}
          GH_REPO: ${{ github.repository }}
        run: |
          set -euo pipefail
          DOWNLOAD_URL="https://github.com/${GH_REPO}/releases/download/v${VERSION}/Scroblebler-v${VERSION}.zip"
          PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")
          RELEASE_NOTES=$(gh release view "v${VERSION}" --json body -q .body | head -c 8000)

          git clone --depth 1 --branch gh-pages \
            "https://x-access-token:${GITHUB_TOKEN}@github.com/${GH_REPO}.git" gh-pages
          cd gh-pages

          if grep -q "<title>Scroblebler ${VERSION}</title>" appcast.xml; then
            echo "Appcast already contains v${VERSION}, skipping"
            exit 0
          fi

          export VERSION DOWNLOAD_URL PUB_DATE RELEASE_NOTES SPARKLE_SIG_AND_LEN
          python3 - <<'PY'
          import os, sys
          version = os.environ['VERSION']
          item = f"""        <item>
              <title>Scroblebler {version}</title>
              <pubDate>{os.environ['PUB_DATE']}</pubDate>
              <sparkle:version>{version}</sparkle:version>
              <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
              <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
              <description><![CDATA[{os.environ['RELEASE_NOTES']}]]></description>
              <enclosure url="{os.environ['DOWNLOAD_URL']}"
                         type="application/octet-stream"
                         {os.environ['SPARKLE_SIG_AND_LEN']} />
          </item>"""
          with open('appcast.xml', 'r') as f:
              content = f.read()
          if '</channel>' not in content:
              sys.exit('appcast.xml has no </channel> close tag')
          content = content.replace('</channel>', item + '\n    </channel>', 1)
          with open('appcast.xml', 'w') as f:
              f.write(content)
          PY

          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add appcast.xml
          git commit -m "appcast: v${VERSION}"
          git push origin gh-pages

      - name: Update Homebrew tap
        env:
          TAP_TOKEN: ${{ secrets.TAP_GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          git clone https://github.com/tonioriol/homebrew-scroblebler.git tap
          mkdir -p tap/Casks
          cp scroblebler.rb tap/Casks/
          cd tap
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Casks/scroblebler.rb
          git commit -m "chore: update scroblebler cask" || exit 0
          git push "https://x-access-token:${TAP_TOKEN}@github.com/tonioriol/homebrew-scroblebler.git" main

      - name: Cleanup signing materials
        if: always()
        env:
          CERTIFICATE_PATH: ${{ runner.temp }}/certificate.p12
          KEYCHAIN_PATH: ${{ runner.temp }}/build.keychain
        run: |
          set -euo pipefail
          rm -f "$CERTIFICATE_PATH"
          security default-keychain -s login.keychain-db || true
          security delete-keychain "$KEYCHAIN_PATH" || true
```

- [ ] **Step 3: Commit**

```bash
git rm .github/workflows/update-tap.yml
git add .github/workflows/release.yml
git commit -m "ci: add full release pipeline with signing, notarization, Sparkle, and appcast"
```

---

### Task 10: Update Homebrew cask for ZIP distribution

Update the cask formula to use ZIP instead of DMG, and remove the `xattr` postflight (not needed for properly signed apps).

**Files:**
- Modify: `scroblebler.rb`

- [ ] **Step 1: Update the cask formula**

Replace the contents of `scroblebler.rb` with:

```ruby
cask "scroblebler" do
  version "1.0.0"
  sha256 "2c8e07c3ed31fbbc511e3fbafa894e77704885e3ac2bb28de52bbc20bb82677a"

  url "https://github.com/tonioriol/scroblebler/releases/download/v#{version}/Scroblebler-v#{version}.zip"
  name "Scroblebler"
  desc "Last.fm scrobbler for macOS Music app"
  homepage "https://github.com/tonioriol/scroblebler"

  livecheck do
    url :homepage
    strategy :github_latest
  end

  app "Scroblebler.app"

  zap trash: [
    "~/Library/Preferences/com.tonioriol.Scroblebler.plist",
    "~/Library/Application Support/Scroblebler",
  ]
end
```

Changes: URL now points to ZIP format (`Scroblebler-v#{version}.zip`), removed `postflight` xattr hack (notarized apps don't need it).

Note: The SHA and version will be updated automatically by the CI pipeline on the next release.

- [ ] **Step 2: Commit**

```bash
git add scroblebler.rb
git commit -m "chore: update Homebrew cask for ZIP distribution"
```

---

### Task 11: Final integration test

Verify the complete local build + sign + launch flow works end-to-end.

**Files:** None (verification only)

- [ ] **Step 1: Clean build**

Run: `make clean && make app CONFIGURATION=release 2>&1 | tail -10`
Expected: Build succeeds, signed app at `build/Scroblebler.app`.

- [ ] **Step 2: Verify app launches and Sparkle initializes**

Run: `make run`
Then check logs:
```bash
log show --predicate 'subsystem == "com.tonioriol.scroblebler"' --info --debug --last 30s 2>&1 | grep -i "sparkle\|updater" | head -5
```
Expected: App launches normally. Sparkle may log about checking for updates (will fail until first release populates the appcast — that's expected).

- [ ] **Step 3: Verify code signing (if Developer ID cert is available)**

Run: `codesign --verify --deep --strict --verbose=2 build/Scroblebler.app 2>&1`
Expected: `valid on disk` / `satisfies its Designated Requirement` (or ad-hoc signing output if no cert).

- [ ] **Step 4: Verify release ZIP**

Run: `make release-zip && ls -lh build/Scroblebler.zip`
Expected: ZIP file exists, reasonable size.

- [ ] **Step 5: Push to trigger first CI release**

Once everything is verified locally, push to main. The CI pipeline will:
1. Detect releasable commits (the `feat:` commits from this plan)
2. Bump version via Cocogitto
3. Build, sign, notarize
4. Create GitHub Release with ZIP
5. Update appcast and Homebrew tap

```bash
git push origin main
```

Monitor: `gh run watch` to follow the CI pipeline.
