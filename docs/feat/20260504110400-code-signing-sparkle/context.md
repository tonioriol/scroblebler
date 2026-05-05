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

**Cursor:** Task 1

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
