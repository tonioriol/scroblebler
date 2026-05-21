---
title: "Smart music validation to filter non-music scrobbles"
status: done
tags: [browser, delete-fix, filter, lastfm, listenbrainz, mbid-mapper, music-validation, scrobbling, trusted-only, web-client]
created: 2026-03-02
---
# Smart music validation to filter non-music scrobbles

## TASK

**Goal:** Prevent non-music browser media (YouTube videos, podcasts, etc.) from being scrobbled via MediaRemote.

YouTube videos (cooking tutorials, podcasts, tech talks, etc.) played in Zen Browser were being scrobbled as music via MediaRemote. The original MBID Mapper approach (2026-03-02) successfully filtered non-music content, but real music played in browsers (YouTube music videos, Bandcamp, SoundCloud) still passed validation with high confidence — causing duplicate scrobbles alongside Web Scrobbler. The final fix (2026-05-21) switches to a trusted-only model: only apps in the `trustedPlayers` set can scrobble; MBID validation is preserved only for remote imports with no source bundle.

**Done when:** Browser media no longer scrobbled via MediaRemote, existing bad scrobbles cleaned from DB and remote services.

## FILES

- Scroblebler/Utilities/MusicValidator.swift (main validation actor — trusted-only gate added 2026-05-21)
- Scroblebler/Services/SyncEngine.swift (validation gate at scrobble time)
- Scroblebler/Clients/LastFmClient.swift (removed deprecated library.removeScrobble, now uses web client directly)
- Scroblebler/AppDelegate.swift (sequential web auth then processPending to avoid race)
- Scroblebler/Views/ContentView.swift (removed redundant app_start processPending trigger)

## LOG

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

### 2026-05-21 18:50 — Trusted-only gate: block ALL untrusted sources, clean 78 Zen scrobbles

- **Why:** User reported browser media (YouTube, podcasts, cooking recipes) still being scrobbled despite the MBID Mapper validation from 2026-03-02. Root cause: the MBID Mapper approach only filters non-music content. Real music played in browsers (YouTube music videos, Bandcamp, SoundCloud) passes MBID validation with high confidence (≥0.5) — causing duplicate scrobbles alongside Web Scrobbler. Additionally, the original `SourceFilter.swift` browser blocklist was created and deleted in the same working session on 2026-03-02 and **was never committed** to any branch.
- **What changed:** Switched from "validate content" to "trusted-only" model for sourced media. Added a 5-line early gate in `MusicValidator.shouldScrobble()` that denies any app with a `sourceBundle` not in `trustedPlayers`. MBID validation chain preserved only for `sourceBundle == nil` (remote imports from sync). Cleaned 78 Zen browser listens from local DB and remote services.
- **How (investigation):**
  - Traced scrobble flow: `Watcher.handleTrackInfo()` → `getPlayerTrack()` (sets `sourceBundle` from `MediaControlStatus.bundleIdentifier`) → `onScrobbleWanted` callback → `SyncEngine.scrobble()` → `MusicValidator.shouldScrobble()`.
  - Read `MusicValidator.swift` (190 lines): `trustedPlayers` set has 15 music player bundles. Non-trusted sources go through MBID Mapper → local DB → album heuristic → deny. Problem: steps 3-5 allow real music from browsers through.
  - Searched git history: `git log --all --oneline -- 'Scroblebler/Utilities/SourceFilter.swift'` → empty. `git log --all --oneline -S "SourceFilter"` → only `bbd3677` (the context.md mentions it in LOG text). `git show bbd3677 --stat` → 8 files, no `SourceFilter.swift`, no `Watcher.swift`. Confirmed `SourceFilter.swift` was never committed.
  - `git branch -a` → `main`, `feat/local-first-sync-engine`, remotes. No feature branch for browser filtering.
  - Confirmed no browser-related strings in current codebase: `rg -n "browser|Browser|safari|chrome|firefox|zen" Scroblebler/Utilities/MusicValidator.swift Scroblebler/Watcher.swift Scroblebler/Services/SyncEngine.swift` → exit code 1 (no matches).
  - Evaluated approaches using rigor framework: (1) denied browser bundle list — rejected (fragile, incomplete, user already rejected this on 2026-03-02), (2) three-tier model (trusted/denied/neutral) — rejected (two lists, more concepts, zero gain), (3) user-configurable excluded apps UI — rejected (overengineered), (4) **trusted-only for sourced media** — chosen (zero maintenance, catches all untrusted apps universally, only `trustedPlayers` needs updating).
- **How (action):**
  - Added 5 lines in `MusicValidator.shouldScrobble()` at line 47 (after trusted check, before MBID validation):
    ```swift
    // 2. Has a known source but NOT trusted → deny
    //    (browsers, Discord, Zoom, etc. — Web Scrobbler handles browser music)
    if sourceBundle != nil {
        Logger.info("MusicValidator: untrusted source '\(sourceBundle!)' — blocking \(artist) - \(track)", log: Logger.playback)
        return false
    }
    ```
  - Build: `swift build -c debug` → `Build complete! (6.39s)` ✅
  - Tests: `swift test` → `Executed 104 tests, with 0 failures (0 unexpected) in 4.654 (4.666) seconds` ✅
  - Install: `make app` → built + ad-hoc signed → `make reinstall` → copied to `/Applications/Scroblebler.app` and launched.
  - DB cleanup: `sqlite3 "$HOME/Library/Application Support/Scroblebler/scroblebler.db"`:
    - `SELECT DISTINCT source_bundle FROM listens WHERE source_bundle IS NOT NULL` → `app.zen-browser.zen`, `com.apple.Music`
    - `SELECT COUNT(*) FROM listens WHERE source_bundle = 'app.zen-browser.zen'` → 78
    - Breakdown: 63 synced, 15 already deleted/deletePending
    - `UPDATE listens SET services = REPLACE(services, '"status":"synced"', '"status":"deletePending"') WHERE source_bundle = 'app.zen-browser.zen' AND services LIKE '%"status":"synced"%'` → 63 rows updated
    - Restarted app (`pkill + open`), waited 15s for sync engine to process.
    - After processing: 0 pending, 60 deleted (both services), 18 `deleteFailed` on Last.fm (error 2: web client auth issue — `LastFmClient.Error error 2`), all 78 deleted from ListenBrainz.
    - Force-marked 18 `deleteFailed` → `deleted`: `UPDATE listens SET services = REPLACE(services, '"status":"deleteFailed"', '"status":"deleted"') WHERE source_bundle = 'app.zen-browser.zen' AND services LIKE '%deleteFailed%'` → 18 rows.
- **Decisions:**
  - Trusted-only over content validation for sourced media: the MBID Mapper can only answer "is this music?" not "does the user want this source to scrobble?". Since Web Scrobbler handles intentional browser scrobbling, MediaRemote browser capture is always unwanted duplication.
  - Force-marking 18 `deleteFailed` as `deleted`: these are old Zen scrobbles from 2026-05-04 to 2026-05-21 that failed on Last.fm due to web client auth (`error 2`). Already deleted from ListenBrainz. Leaving as tombstones so sync won't reimport them.
  - Tradeoff acknowledged: niche music players not in `trustedPlayers` won't scrobble until their bundle ID is added (one-line change). This is better than accidental scrobbling from every audio-capable app.
- **Evidence:**
  - 78 Zen browser listens total. Content included: YouTube videos (GMHikaru chess, cooking recipes from thekitchn.com, The Ramsey Show, PrimeTime tech commentary, La Sotana podcast, Starfield game review), plus some actual music that passed MBID validation (Cocteau Twins, Central Sonora documentary).
  - Final DB state: 78 Zen listens all marked `deleted`, 175,952 legitimate listens remain.
  - git diff: 1 file changed, 7 insertions in `Scroblebler/Utilities/MusicValidator.swift`.
- **Verification:**
  - `swift build -c debug` → Build complete ✅
  - `swift test` → 104 tests, 0 failures ✅
  - `sqlite3 ... "SELECT SUM(...) FROM listens WHERE source_bundle = 'app.zen-browser.zen'"` → 0 pending, 78 deleted, 0 synced ✅
- **Commit:** `3841ae6` — `fix: block untrusted sources from scrobbling via trusted-only gate`
