---
title: "Code signing + Sparkle auto-updates"
status: active
tags: [code-signing, sparkle, notarization, ci, release-automation]
created: 2026-05-04
---
# Code signing + Sparkle auto-updates

## TASK

Set up proper Apple Developer code signing, notarization, and Sparkle auto-updates for Scroblebler. Migrate build system to SPM + Makefile (matching adrenaline), switch versioning to Cocogitto, distribute as ZIP. Currently the app is ad-hoc signed and distributed as a DMG via GitHub Releases with semantic-release.

## SPEC

[spec.md](./spec.md) — Full migration: SPM+Makefile build, Developer ID signing, notarization, Sparkle 2.x auto-updates, Cocogitto versioning, ZIP distribution

## PLAN

[plan.md](./plan.md) — 11 tasks: icon gen → Info.plist → Sparkle integration → Makefile → Cocogitto → EdDSA keypair → GitHub Secrets → gh-pages appcast → CI workflow → Homebrew cask → integration test

**Cursor:** Task 4

## RELEVANT FILES

* `Makefile` (CREATE — build system)
* `cog.toml` (CREATE — versioning)
* `Resources/Info.plist` (CREATE — SPM builds)
* `Resources/AppIcon.icns` (CREATE — app icon)
* `Scripts/generate-app-icon.sh` (CREATE — icon conversion)
* `Scroblebler/SparkleUpdaterController.swift` (CREATE — Sparkle wrapper)
* `.github/workflows/release.yml` (CREATE — CI pipeline)
* `Package.swift` (MODIFY — add Sparkle dep)
* `Scroblebler/AppDelegate.swift` (MODIFY — init Sparkle)
* `scroblebler.rb` (MODIFY — ZIP distribution)
* `.releaserc.json` (DELETE)
* `scripts/build.sh` (DELETE)
* `scripts/release.sh` (DELETE)
* `.github/workflows/update-tap.yml` (DELETE)

## GENERAL CONTEXT

Scroblebler is a macOS menu bar scrobbling app built with Xcode project (`.xcodeproj`) + Swift Package Manager dependencies. It uses `semantic-release` (Node.js) for versioning and produces a DMG. The adrenaline project (same developer) already has a working setup with Developer ID signing, notarization, Sparkle 2.x, Cocogitto for versioning, and a GitHub Actions CI pipeline.

## EVENT LOG

* **2026-05-04 11:04 - Started brainstorming**
  * Explored both projects' build/release setups
  * Adrenaline pattern: Makefile → inside-out codesign → notarize → Sparkle EdDSA sign → appcast update → GitHub Release

* **2026-05-05 15:46 - Spec approved**
  * Key decisions: switch to Cocogitto (consistency, no Node dep), ZIP only (simpler, Sparkle native), SPM+Makefile build (match adrenaline), keep .xcodeproj for IDE
  * Scope: build migration + signing + notarization + Sparkle + CI pipeline + Homebrew cask update

* **2026-05-05 16:10 - Plan generated, 11 tasks**
  * Covers: icon gen, Info.plist, Sparkle integration, Makefile, Cocogitto, EdDSA keypair, GitHub Secrets, gh-pages appcast, CI workflow, Homebrew cask, integration test

* **2026-05-05 16:13 - Task 1 complete: AppIcon.icns generated**
  * Created `Scripts/generate-app-icon.sh` — copies PNGs from xcassets and runs `iconutil` to produce `Resources/AppIcon.icns`
  * Generated `Resources/AppIcon.icns` (all 10 sizes: 16→512@2x)

* **2026-05-05 16:16 - Tasks 2 & 3 complete: Info.plist + Sparkle integration**
  * Created `Resources/Info.plist` — standalone plist with literal values for SPM builds, includes Sparkle keys (SUFeedURL, SUPublicEDKey placeholder, SUScheduledCheckInterval)
  * Added Sparkle 2.7.0+ to `Package.swift` deps and `Scroblebler` target; resolved packages
  * Created `Scroblebler/SparkleUpdaterController.swift` — minimal `@MainActor` wrapper around `SPUStandardUpdaterController`, starts auto-checks on init
  * Wired into `AppDelegate.swift`: added `private var updater: SparkleUpdaterController?` property, init before `NSApp.activate` in `applicationDidFinishLaunching`
  * Added file to Xcode project via xcodeproj tool
  * Build verified: `Build complete! (24.71s)`
  * Commits: `c82b0e9` (Info.plist), `25c10f9` (Sparkle integration)

* **2026-05-05 18:22 - Task 4 complete: Makefile app bundle assembly**
  * Created `Makefile` for SPM-based builds: `swift build`, app bundle assembly, asset catalog compilation, Sparkle framework bundling, signing, reinstall/run, and ZIP packaging
  * Added required runtime bundling for `libMediaRemoteAdapter.dylib` from SwiftPM's triple-specific build output into `Contents/Frameworks`
  * Debug builds ad-hoc sign by default for local launch; release builds use Developer ID when available and expand the Xcode-only `$(AppIdentifierPrefix)` entitlement placeholder before signing
  * Verification: `make app`, `make run`, and `make release-zip && ls -la build/Scroblebler.zip` passed

* **2026-05-05 18:31 - Task 5 complete: Cocogitto versioning**
  * Why: replaced Node-based semantic-release tooling with Cocogitto so release versioning, changelog generation, and tag creation can be driven directly from conventional commits in the CI migration.
  * How: added `cog.toml` with GitHub remote changelog settings and `Resources/Info.plist` pre-bump hooks; removed `.releaserc.json`, `scripts/build.sh`, and `scripts/release.sh` while keeping `scripts/generate-app-icon.sh` in place. Verified config parsing with `cog check`; only historical non-conventional commit warnings were reported.

* **2026-05-05 18:41 - Task 6 complete: Sparkle EdDSA keypair generated**
  * Resolved Sparkle 2.9.1 from `Package.resolved`, downloaded matching Sparkle release tools locally, and used `generate_keys` without printing private key material.
  * Replaced the `SUPublicEDKey` placeholder in `Resources/Info.plist` with the generated public key.
  * Stored the private key locally in macOS Keychain service `scroblebler-sparkle-ed-private-key` for later secret setup.
  * Verification: plist parsing confirmed `SUPublicEDKey` is present, 44 characters long, and the placeholder is gone; Keychain lookup confirmed the storage item exists.
