---
title: "Music library backfill for iPhone/iCloud plays via MusicKit"
status: done
tags: [apple-music, backfill, icloud, musickit, scrobbling]
created: 2026-02-26
---
# Music library backfill for iPhone/iCloud plays via MusicKit

## TASK

Implement a backfill mechanism in the macOS Scroblebler app to capture Apple Music plays from iPhone, HomePod, and CarPlay that sync via iCloud to the local Music library.

## GENERAL CONTEXT

Scroblebler is a macOS menu bar app that scrobbles to Last.fm, ListenBrainz, and Libre.fm using MediaRemote for real-time now-playing detection. This feature adds a secondary polling mechanism to catch plays from other Apple devices that sync via iCloud Music Library.

### RELEVANT FILES

* Scroblebler/Services/MusicLibraryBackfill.swift — MusicKit-based backfill service
* Scroblebler/AppDelegate.swift — Calls MusicLibraryBackfill.shared.start() on launch
* Scroblebler/Info.plist — Added NSAppleMusicUsageDescription for MusicKit authorization
* Scroblebler/Services/SyncEngine.swift — scrobble() used by backfill
* Scroblebler/Services/ListenStore.swift — findByTimestamp() used for dedup
* Scroblebler/Models/Listen.swift — fromMediaPlayer() factory
* AGENTS.md — Added CLI build/run/log commands

## PLAN

✅ 1. Analyzed iOS port feasibility (~75-80% code reusable, blocker: no cross-app now-playing on iOS)
✅ 2. Built Rust server in ~/Code/neumann/scroblebler-server/ (kept but not pursued — Apple Music tokens expire every 6 months)
✅ 3. Discovered AppleScript can read Music.app's played date (synced via iCloud)
✅ 4. Implemented AppleScript-based backfill, fixed Catalan locale issues
✅ 5. Discovered iCloud sync is unreliable/slow for played date metadata
✅ 6. Tested MusicKit framework — MusicRecentlyPlayedRequest (cloud API) needs $99 dev account
✅ 7. MusicLibraryRequest (local library) works without paid account — rewrote backfill to use it
✅ 8. Confirmed MusicKit queries same local library as AppleScript (same iCloud sync limitation)

## EVENT LOG

* **2026-02-26 17:45 - iOS port feasibility analysis**
  * Why: User asked how hard it would be to make an iOS app
  * How: Analyzed all source files feature-by-feature
  * Key info: ~75-80% code reusable, blocker is iOS sandbox

* **2026-02-26 17:00 - Built scroblebler-server Rust project**
  * Why: Server-side approach to poll Apple Music API from VPS
  * How: Created ~/Code/neumann/scroblebler-server/ with tokio, reqwest, etc.
  * Key info: Compiles clean, but Apple Music tokens expire every 6 months with no refresh

* **2026-02-26 18:15 - Verified iCloud sync works (partially)**
  * How: User played "Sun" by Daniel Avery on iPhone, appeared in Music.app after ~10 min
  * Key info: Played date syncs via iCloud but unreliably — only 4 of 10+ tracks synced after 6+ hours

* **2026-02-26 18:20 - Implemented AppleScript-based backfill**
  * How: Created MusicLibraryBackfill.swift using NSAppleScript
  * Key info: Required locale fixes for Catalan (comma decimals, scientific notation, epoch date strings)

* **2026-02-26 20:08 - Discovered iCloud sync unreliability**
  * Why: Only 4 of 10+ iPhone plays synced after hours
  * How: Checked Music.app repeatedly, always showed same 4 tracks
  * Key info: Removed watermark approach, switched to 48h sliding window with dedup

* **2026-02-26 23:24 - Rewrote backfill using MusicKit framework**
  * Why: Cleaner API, no locale hacks, proper typed data
  * How: Replaced AppleScript with `import MusicKit`, `MusicLibraryRequest<Song>`, `MusicAuthorization.request()`
  * Key info: MusicRecentlyPlayedRequest (cloud) needs $99 account — permissionDenied. MusicLibraryRequest (local) works free. Same iCloud sync limitation. Added NSAppleMusicUsageDescription to Info.plist, @available(macOS 14.0, *).

## Next Steps

COMPLETED — Feature works as best-effort delayed backfill. iCloud sync delay is an Apple platform limitation.
Future options for real-time iPhone scrobbling:
- iOS Shortcuts automation (POST to VPS)
- Paid Apple Developer account ($99/yr) for MusicRecentlyPlayedRequest cloud API
- iOS app via AltStore sideloading
