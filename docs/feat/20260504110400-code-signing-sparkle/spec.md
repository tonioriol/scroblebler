# Spec: Code Signing, Sparkle Auto-Updates & Build Migration

## Overview

Migrate Scroblebler from ad-hoc signing + semantic-release + DMG distribution to Developer ID signing + notarization + Sparkle 2.x auto-updates + Cocogitto versioning + ZIP distribution. The build system moves from `xcodebuild` to `swift build` + Makefile, matching the adrenaline project pattern.

## 1. Build System Migration

### 1.1 Makefile

Create a `Makefile` at project root with these targets:

| Target | Description |
|--------|-------------|
| `build` | `swift build -c $(CONFIGURATION)` |
| `app` | Build + assemble `.app` bundle + sign |
| `sign` | Inside-out codesign of Sparkle + app |
| `release-zip` | `app` + `ditto -c -k` to create ZIP |
| `reinstall` | Kill running instance, copy to `/Applications`, launch |
| `run` | `app` + `open build/Scroblebler.app` |
| `clean` | `rm -rf .build build` |

Variables:
- `CONFIGURATION` — `debug` (default) or `release`
- `TEAM_ID` — `B65K228Z97`
- `CODE_SIGN_IDENTITY` — auto-detected from keychain by Team ID, falls back to ad-hoc (`-`)

### 1.2 App Bundle Assembly (`app` target)

After `swift build`, assemble the `.app` bundle manually:

```
build/Scroblebler.app/
  Contents/
    Info.plist                          ← Resources/Info.plist
    MacOS/
      Scroblebler                       ← .build/$(CONFIGURATION)/Scroblebler
    Resources/
      AppIcon.icns                      ← Resources/AppIcon.icns (converted from xcassets)
      Assets.car                        ← compiled via actool, OR just bundle raw images
    Frameworks/
      Sparkle.framework                 ← .build/$(CONFIGURATION)/Sparkle.framework
```

Key steps:
1. Copy binary, add `@executable_path/../Frameworks` rpath via `install_name_tool`
2. Copy `Sparkle.framework` to `Frameworks/`
3. Copy `Info.plist` from `Resources/`
4. Handle app icon: convert existing `AppIcon.appiconset` to `.icns` file stored in `Resources/` (one-time, like adrenaline's `generate-app-icon.swift`), or compile via `actool`
5. Call `make sign`

### 1.3 Asset Catalog Strategy

**Simplify**: Convert the current `Assets.xcassets` icon set to a single `AppIcon.icns` file stored at `Resources/AppIcon.icns`. Other image assets (logos, nocover) that are referenced in SwiftUI code can be loaded from bundle resources directly. The `.xcodeproj` remains for IDE use and still references the xcassets.

### 1.4 Info.plist

Move the canonical `Info.plist` to `Resources/Info.plist` (outside the `Scroblebler/` source directory). This version uses literal values (no `$(VARIABLE)` substitutions since `swift build` doesn't expand them):

```xml
<key>CFBundleIdentifier</key>
<string>com.tonioriol.scroblebler</string>
<key>CFBundleExecutable</key>
<string>Scroblebler</string>
```

The existing `Scroblebler/Info.plist` with Xcode variables stays for IDE builds.

### 1.5 Entitlements

The entitlements file stays at `Scroblebler/Scroblebler.entitlements`. Referenced by `codesign --entitlements` in the `sign` target.

### 1.6 Package.swift Changes

Add Sparkle dependency:

```swift
dependencies: [
    .package(url: "https://github.com/ejbills/mediaremote-adapter.git", branch: "master"),
    .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
],
```

Add to the `Scroblebler` executable target dependencies:

```swift
.product(name: "Sparkle", package: "Sparkle"),
```

## 2. Code Signing & Notarization

### 2.1 Makefile `sign` Target

Inside-out signing order (same as adrenaline):

1. Sparkle XPC services (`Sparkle.framework/Versions/B/XPCServices/*.xpc`)
2. Sparkle `Autoupdate` binary
3. Sparkle `Updater.app`
4. `Sparkle.framework` itself
5. `Scroblebler.app` (top-level, includes entitlements)

All with `codesign --force --options runtime --sign "$CODE_SIGN_IDENTITY"`. The app-level sign also passes `--entitlements Scroblebler/Scroblebler.entitlements`.

### 2.2 Notarization (CI only)

After signing and creating the ZIP:
1. `xcrun notarytool submit build/Scroblebler.zip --keychain-profile "$PROFILE" --wait`
2. `xcrun stapler staple build/Scroblebler.app`
3. `xcrun stapler validate build/Scroblebler.app`
4. `spctl --assess --type execute --verbose=4 build/Scroblebler.app`
5. Re-create ZIP after stapling: `ditto -c -k --keepParent build/Scroblebler.app "build/Scroblebler-v${VERSION}.zip"`

### 2.3 Local Development

Local `make app` uses ad-hoc signing if no Developer ID cert is found in the keychain. This keeps the dev experience unchanged.

## 3. Sparkle Integration

### 3.1 SparkleUpdaterController.swift

Minimal wrapper (simplified from adrenaline — no status publisher, no complex delegate):

```swift
import Sparkle

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

### 3.2 AppDelegate Integration

Add property and init in `AppDelegate`:

```swift
private var updater: SparkleUpdaterController?

// In applicationDidFinishLaunching or equivalent:
updater = SparkleUpdaterController()
```

### 3.3 Info.plist Keys

Add to `Resources/Info.plist`:

```xml
<key>SUEnableAutomaticChecks</key>
<true/>
<key>SUFeedURL</key>
<string>https://tonioriol.github.io/scroblebler/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>GENERATED_PUBLIC_KEY_HERE</string>
<key>SUScheduledCheckInterval</key>
<integer>86400</integer>
```

### 3.4 EdDSA Keypair

Generate once using Sparkle's `generate_keys` tool:
- Public key → `Info.plist` `SUPublicEDKey`
- Private key → GitHub Secret `SPARKLE_ED_PRIVATE_KEY`

## 4. Versioning (Cocogitto)

### 4.1 cog.toml

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

### 4.2 Remove semantic-release

Delete `.releaserc.json`. No `package.json` or `node_modules` exist in this project (semantic-release was invoked via `npx` in `scripts/release.sh`).

### 4.3 Remove old scripts

- Delete `scripts/release.sh` (replaced by CI workflow)
- Rewrite `scripts/build.sh` or remove it (Makefile replaces it)

## 5. CI Pipeline

### 5.1 `.github/workflows/release.yml`

Two-job structure (copy from adrenaline, adapt for xcodebuild→Makefile and Scroblebler naming):

**Job 1: `decide`** (ubuntu-latest)
- Install Cocogitto
- `cog bump --auto --dry-run` → outputs `will_release` and `next_version`

**Job 2: `release`** (macos-14, conditional on `will_release == true`)
1. Checkout with full history
2. Install Cocogitto (`brew install cocogitto`)
3. Configure git for cog
4. Import Developer ID certificate (base64 → keychain)
5. Configure notarytool profile
6. `cog bump --version $NEXT_VERSION` (commits changelog + plist, creates tag)
7. `make release-zip CONFIGURATION=release CODE_SIGN_IDENTITY="$IDENTITY"`
8. `codesign --verify` the built app
9. Notarize + staple
10. Re-zip after stapling: `Scroblebler-v${VERSION}.zip`
11. Sparkle EdDSA sign the ZIP
12. Update Homebrew cask (`scroblebler.rb` SHA + version)
13. Amend cog's version commit to include cask changes, re-tag
14. Push commit + tag
15. Create GitHub Release with ZIP attached
16. Clone gh-pages, inject appcast `<item>`, push
17. Push cask to `tonioriol/homebrew-scroblebler` tap
18. Cleanup signing materials

### 5.2 GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` | Developer ID Application cert (.p12) base64 |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | .p12 password |
| `APPLE_ID` | Apple ID email |
| `APPLE_TEAM_ID` | `B65K228Z97` |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for notarytool |
| `APPLE_NOTARYTOOL_PROFILE` | Profile name for stored credentials |
| `SPARKLE_ED_PRIVATE_KEY` | EdDSA private key for Sparkle signing |
| `TAP_GITHUB_TOKEN` | PAT for pushing to homebrew-scroblebler repo |

### 5.3 gh-pages Branch

Create a `gh-pages` branch with initial `appcast.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Scroblebler</title>
        <link>https://tonioriol.github.io/scroblebler/appcast.xml</link>
        <description>Scroblebler updates</description>
        <language>en</language>
    </channel>
</rss>
```

### 5.4 Remove Old Workflow

Replace `.github/workflows/update-tap.yml` — tap update is now part of the release workflow.

## 6. Homebrew Cask Update

Update `scroblebler.rb` to point to ZIP instead of DMG:

```ruby
cask "scroblebler" do
  version "VERSION"
  sha256 "SHA256"

  url "https://github.com/tonioriol/scroblebler/releases/download/v#{version}/Scroblebler-v#{version}.zip"
  name "Scroblebler"
  homepage "https://github.com/tonioriol/scroblebler"

  app "Scroblebler.app"
end
```

## 7. Files Changed Summary

| Action | File |
|--------|------|
| Create | `Makefile` |
| Create | `cog.toml` |
| Create | `Resources/Info.plist` (literal values, Sparkle keys) |
| Create | `Resources/AppIcon.icns` (converted from xcassets) |
| Create | `Scroblebler/SparkleUpdaterController.swift` |
| Create | `.github/workflows/release.yml` |
| Modify | `Package.swift` (add Sparkle dependency) |
| Modify | `Scroblebler/AppDelegate.swift` (init Sparkle updater) |
| Modify | `scroblebler.rb` (ZIP instead of DMG) |
| Delete | `.releaserc.json` |
| Delete | `scripts/release.sh` |
| Delete | `scripts/build.sh` (replaced by Makefile) |
| Delete | `.github/workflows/update-tap.yml` (merged into release.yml) |

## 8. Out of Scope

- UI for "Check for Updates" menu item (can be added later)
- Removing `.xcodeproj` (kept for IDE development)
- Mac App Store distribution
- Code signing for debug builds
