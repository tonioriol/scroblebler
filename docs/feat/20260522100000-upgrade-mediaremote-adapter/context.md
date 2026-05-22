---
title: "Upgrade mediaremote-adapter to 5b2c2ab"
status: done
tags: [mediaremote, performance, spm, upgrade]
related: [20260302133000-music-validation-filter]
created: 2026-05-22
---
# Upgrade mediaremote-adapter to 5b2c2ab

## TASK

**Goal:** Upgrade the `ejbills/mediaremote-adapter` SPM dependency from pinned revision `78aae86` to latest `5b2c2ab` (14 commits) to gain stdin transport, artwork preservation, pipe deadlock fixes, and event-driven position tracking.

The adapter was pinned to `78aae86` earlier in this session after discovering that `branch: "master"` silently pulled the breaking `5b2c2ab` version. Now that the breaking change is understood (removal of `onPlaybackTimeUpdate` callback), the upgrade can be done deliberately.

**Done when:** App builds, tests pass, Now Playing works with new adapter version, play/pause buttons don't flicker.

## FILES

- Package.swift (revision `78aae86` → `5b2c2ab`)
- Package.resolved (updated hash)
- Scroblebler/Watcher.swift (removed `onPlaybackTimeUpdate` callback, added `lastCommandTime` grace period for play state)

## LOG

### 2026-05-22 12:03 — Investigate upstream changes

- **Why:** User asked to investigate upgrading after we pinned to old revision to fix the build.
- **What changed:** Investigation only — no code changes.
- **How (investigation):**
  - `git log 78aae86..5b2c2ab --oneline` in `.build/checkouts/mediaremote-adapter/` → 14 commits.
  - `git diff 78aae86..5b2c2ab -- Sources/MediaRemoteAdapter/MediaController.swift` → full diff reviewed (~400 lines).
  - `git diff 78aae86..5b2c2ab -- Sources/MediaRemoteAdapter/TrackInfo.swift` → `artwork` changed from computed to stored property, `currentElapsedTime` now returns raw elapsed on pause (no drift), memberwise init added.
  - Key API changes identified:
    - `onPlaybackTimeUpdate` callback **removed** (was timer-driven 250ms polling, replaced by event-driven via `onTrackInfoReceived`)
    - `init(bundleIdentifier:)` → `init()` (bundle ID filtering removed)
    - `sendCommand()` routes through listener stdin instead of spawning Perl per click
    - `preservingArtworkIfDowngrade()` prevents MediaRemote from replacing larger artwork with smaller thumbnails
    - SIGPIPE ignored, EOF handlers properly nil'd, pipe deadlock fixed
- **Decisions:** Upgrade recommended — only real adaptation needed is removing `onPlaybackTimeUpdate` callback (14 lines). Position tracking already handled by Watcher's own interpolation timer + `handleTrackInfo` event snapshots.
- **Evidence:** 14 commits, 3 breaking API changes (only 1 requires code change), 10+ improvements.

### 2026-05-22 12:04 — Upgrade and adapt

- **Why:** User approved upgrade.
- **What changed:** Updated `Package.swift` to revision `5b2c2ab`, removed 14-line `onPlaybackTimeUpdate` callback from `Watcher.swift`.
- **How (action):**
  - `Package.swift` line 11: `revision: "78aae86..."` → `revision: "5b2c2ab"`
  - `swift package resolve` → resolved successfully.
  - `Watcher.swift` lines 99-112: removed entire `mediaController.onPlaybackTimeUpdate = { ... }` block (14 lines). Position tracking continues via: (1) `handleTrackInfo()` extracts `payload.currentElapsedTime` into `MediaControlStatus.elapsedTime` on every MR event, (2) `processStatus()` updates `lastSnapshotTime`/`lastSnapshotPosition`, (3) `updateInterpolatedPosition()` 500ms timer interpolates between snapshots.
  - `bundleIdentifier` param: `MediaController()` already used without it — no change needed.
  - Makefile `libraryPath` sed patch: upstream did NOT fix `Bundle(for:).executablePath` issue — patch still needed and works unchanged.
- **Evidence:**
  - `swift build -c debug` → Build complete (11.17s) ✅, then (5.18s) on rebuild ✅
  - `swift test` → 104 tests, 0 failures ✅
  - `make app && make reinstall` → installed at `/Applications/Scroblebler.app`
  - `ps aux | grep perl` → Perl subprocess running with correct dylib path ✅
  - Logs: `Track changed: O My God by The Police`, `Updated now playing on Last.fm`, `Updated now playing on ListenBrainz` ✅
  - User tested: "all works so much better and smoother!"
- **Verification:**
  - Build: `swift build` → 0 errors ✅
  - Tests: `swift test` → 104/104 pass ✅
  - Progress bar: user confirmed "smoother"
  - Now Playing: detects tracks, updates services ✅
- **Commit:** `701d815` — `feat: upgrade mediaremote-adapter to 5b2c2ab with stdin transport and event-driven updates`

### 2026-05-22 12:23 — Fix play/pause button flicker

- **Why:** User reported play/pause button "blinks back and forth its state when pressed". Root cause: with stdin transport, commands reach MediaRemote near-instantly. The optimistic UI update in `notifyCommandSent()` sets the correct new state, but then a stale MR event (carrying the **pre-command** state) arrives and reverts it. Sequence: optimistic → paused → MR event (still playing) → playing → MR event (now paused) → paused. The old Perl-subprocess-per-command approach had ~200-500ms latency, naturally debouncing this race.
- **What changed:** Added a 600ms command grace period. After any command, `processStatus()` suppresses player state updates from MR events for 600ms, trusting the optimistic update. After the grace period, MR events resume updating state normally.
- **How (action):**
  - Added `private var lastCommandTime: Date?` property to `Watcher` (line 42).
  - Set `lastCommandTime = Date()` at top of `notifyCommandSent()` (line 216).
  - In `processStatus()` (line 726): added `let inCommandGrace = lastCommandTime.map { Date().timeIntervalSince($0) < 0.6 } ?? false` guard before `playerState` update.
  - In `handleTrackInfo()` stale-event handler (line 572): same grace period guard before updating `playerState` from rejected stale events.
- **Decisions:** 600ms chosen to cover: stdin command dispatch (~10ms) + MediaRemote propagation (~50-200ms) + safety margin. Not too long to miss genuine external state changes (e.g., user pausing from Control Center).
- **Evidence:**
  - `swift build` → 0 errors ✅
  - `swift test` → 104/104 pass ✅
  - `make app && make reinstall` → installed ✅
- **Verification:**
  - Build + tests pass ✅
  - User to test play/pause flicker (pending feedback)
- **Commit:** `cb0139a` — `fix: suppress stale MR play state during command grace period`
