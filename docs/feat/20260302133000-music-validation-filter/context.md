---
title: "Smart music validation to filter non-music scrobbles"
status: active
tags: [browser, delete-fix, filter, lastfm, listenbrainz, mbid-mapper, music-validation, scrobbling, web-client]
created: 2026-03-02
---
# Smart music validation to filter non-music scrobbles

## TASK

YouTube videos (cooking tutorials, podcasts, tech talks, etc.) played in Zen Browser were being scrobbled as music via MediaRemote. Needed a source-agnostic way to detect and filter non-music content before scrobbling, without maintaining a browser bundle ID blocklist. Also needed to clean up 32 existing bad scrobbles from local DB + remote services.

## GENERAL CONTEXT

Scroblebler is a macOS menu bar app that scrobbles to Last.fm, Libre.fm, and ListenBrainz. It captures now-playing info from any media source via the private MediaRemote framework. Browser extensions (Web Scrobbler in Zen) handle legitimate browser music scrobbling.

### RELEVANT FILES

* Scroblebler/Utilities/MusicValidator.swift (NEW — main validation actor)
* Scroblebler/Services/SyncEngine.swift (modified — validation gate at scrobble time)
* Scroblebler/Watcher.swift (modified — removed old browser blocklist check)
* Scroblebler/Utilities/SourceFilter.swift (DELETED — replaced by MusicValidator)
* Scroblebler/Clients/LastFmClient.swift (modified — removed deprecated library.removeScrobble, now uses web client directly)
* Scroblebler/AppDelegate.swift (modified — sequential web auth then processPending to avoid race)
* Scroblebler/Views/ContentView.swift (modified — removed redundant app_start processPending trigger)

## PLAN

- ✅ Investigate scrobble pipeline and available data (artist, track, album, bundleIdentifier, duration)
- ✅ Evaluate options: browser blocklist vs heuristics vs API validation
- ✅ Research APIs: LB MBID Mapper, Last.fm track.search, MusicBrainz search
- ✅ Test MBID Mapper against real bad scrobbles from local DB
- ✅ Implement MusicValidator using MBID Mapper with fallback chain
- ✅ Wire into SyncEngine.scrobble() (not UI path — no Now Playing delay)
- ✅ Remove SourceFilter browser blocklist approach
- ✅ Build and launch successfully
- ✅ Fix fail-open bug (change to fail-closed for untrusted sources)
- ✅ Fix Last.fm delete flow (deprecated API + web client race condition)
- ✅ Clean up 32 historical non-music scrobbles from local DB + remote services
- ✅ Add periodic processPending timer (60s interval via `SyncEngine.startPeriodicSync()`)

## EVENT LOG

* **2026-03-02 13:30 - Investigated data flow and filtering options**
  * Why: YouTube videos from Zen Browser were being scrobbled as music
  * How: Traced MediaRemote → Watcher → SyncEngine pipeline. Found `bundleIdentifier` available in `MediaControlStatus`. Evaluated 3 approaches: browser blocklist, disable all browser scrobbling, smart music detection.

* **2026-03-02 13:34 - First attempt: browser bundle ID blocklist (SourceFilter)**
  * Why: Quick fix to block known browser bundle IDs
  * How: Created `SourceFilter.swift` with 16 browser bundle IDs including `app.zen-browser.zen`. Added checks in `Watcher.handleTrackInfo()` and `SyncEngine.scrobble()`. Build succeeded.
  * Key info: User rejected this approach — maintaining a browser list is fragile and doesn't scale.

* **2026-03-02 12:55 - Pivoted to MBID Mapper-based music validation**
  * Why: User wanted source-agnostic detection that works regardless of player. Already have `lookupMBIDFromMapper()` in ListenBrainzClient with confidence scores.
  * How: Designed architecture where validation happens at scrobble time (not UI time) to avoid Now Playing latency. Fallback chain: trusted players → cache → MBID Mapper → local DB → heuristic (has album) → allow with warning.

* **2026-03-02 13:20 - Evaluated MBID Mapper against real data**
  * Why: Need to verify accuracy before implementation
  * How: Queried local SQLite DB for Zen-sourced listens. Tested against mapper via curl.
  * Key info: Results perfect — all non-music (Hasan Minhaj, PrimeTime, BloodyNine, travel videos, standup clips) returned 404. All real music (Kangding Ray, Daft Punk, David Bowie) returned 200 with confidence 1.0. Edge case: "David Bowie - Underground (Official Video)" returned 404 due to dirty title — needs cleaning regex.
  * Key info: Some HTTP 000 timeouts observed — confirms need for fallback chain.

* **2026-03-02 13:22 - Implemented MusicValidator**
  * Why: Replace fragile browser blocklist with smart API-based validation
  * How: Created `MusicValidator.swift` as an actor with: trusted player bypass (Music.app, Spotify, etc.), in-memory cache (both valid/invalid, max 500 entries), MBID Mapper lookup (3s timeout), title cleaning (strips "(Official Video)" etc.), local DB fallback, album heuristic fallback. Wired into `SyncEngine.scrobble()` as the single validation gate. Removed `SourceFilter.swift`. Build succeeded, app launched and scrobbled Music.app tracks correctly.

* **2026-03-02 17:10 - Fixed fail-open bug**
  * Why: "Ibai - XOKAS vs 8 HATERS" YouTube video was scrobbled because MBID Mapper request timed out and the "no signal" last resort allowed it (fail-open).
  * How: Changed last resort behavior: untrusted sources now deny when no signal is available (fail-closed). Increased timeout from 3s to 5s. Rebuilt and relaunched.

* **2026-03-02 18:04 - Manual history cleanup of 32 non-music Zen scrobbles**
  * Why: 48 Zen-sourced listens in DB, 32 were non-music (YouTube videos)
  * How: Used Python script to mark all 32 as `deletePending` in the services JSON. App processed them on relaunch — 25 deleted successfully on first pass. 7 reverted to `synced` due to reconcile re-importing from remote. 5 naked flames entries had LB deleted but Last.fm `deleteFailed`.
  * Key info: Local DB column is `source_bundle` (snake_case), not `sourceBundle`. DB path: `~/Library/Application Support/Scroblebler/scroblebler.db`.

* **2026-03-02 18:28 - Fixed Last.fm delete: deprecated API + web client race**
  * Why: `library.removeScrobble` API always returns "Invalid Method" (deprecated). Web client fallback failed because it wasn't authenticated yet when processPending ran.
  * How: Three changes:
    1. `LastFmClient.deleteScrobble()` — removed deprecated `library.removeScrobble` call, now goes directly to web client with a retryable error if web client not ready
    2. `AppDelegate` — made web auth and processPending sequential (await web auth before scheduling processPending)
    3. `ContentView` — removed redundant `app_start` processPending trigger that raced with AppDelegate's sequential flow
  * Key info: All 32 non-music scrobbles successfully deleted from both Last.fm and ListenBrainz. 16 legitimate music entries remain (Vladimir Cosma, Roberto Carlos, Kangding Ray).

* **2026-03-02 23:05 - Fixed soft-delete resurrection bug: deleted items re-imported by sync**
 * Why: Previously deleted non-music items (Hasan Minhaj, PrimeTime, EspañaXDescubrir) reappeared in DB after sync. Two root causes: (1) `importAndMergeHistoryPage()` merge loop overwrote local `deleted`/`deletePending` states with remote `synced` state. (2) `pruneFullyDeleted()` hard-deleted tombstone rows, so on next sync the remote listen had no local match and got re-inserted as new.
 * How: Four changes:
   1. **Removed `pruneFullyDeleted()` call** in `SyncEngine.processPending()` — soft-deleted rows are now permanent tombstones, never hard-deleted. Soft-delete is the source of truth.
   2. **Protected delete states during merge** in `importAndMergeHistoryPage()` — if any service has a delete-related status (`.deleted`, `.deletePending`, `.deleteFailed`), the entire listen merge is skipped. Individual service states with delete status are also never overwritten.
   3. **Protected delete states in `SyncEngine.reconcile()`** — same skip logic for the reconcile path.
   4. **Added MusicValidator on remote imports** — new listens imported from remote services are validated through MusicValidator before insertion. Non-music content (no MBID match, no album) is blocked.
 * Key info: 7 non-music items had re-appeared (5x Hasan Minhaj, 1x EspañaXDescubrir, 1x The PrimeTime). All marked `deletePending`, app processed them successfully — deleted from LB, marked deleted locally. Rows remain as tombstones.
 * Files: Scroblebler/Services/SyncEngine.swift, Scroblebler/Views/MainView.swift, Scroblebler/Services/ListenStore.swift

## Next Steps

- [x] ~~Add periodic processPending timer~~ — Done: 60s timer in `SyncEngine.startPeriodicSync()`, triggered from `AppDelegate`
- [x] ~~Fix soft-delete resurrection bug~~ — Done: see event log 2026-03-02 23:05
- [ ] Monitor MusicValidator logs for false positives/negatives over time
- [ ] Consider adding Last.fm track.search as secondary validator if MBID Mapper proves unreliable
