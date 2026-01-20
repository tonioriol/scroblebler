# Local-First Sync Engine

## TASK

Implement a local-first sync engine with the following requirements:

1. Rename `Track` entity/store/services to `Listen` (proper semantic naming)
2. Add `Listen` SQLite persistence with sync status per service
3. Create unified `ListenStore` backed by SQLite
4. Build sync engine with optimistic updates and conflict resolution
5. Design simple yet well-architected pipeline

## GENERAL CONTEXT

See AGENTS.md for project structure. Key principles:

- Simple, elegant, NEVER overengineer
- Straightforward implementation readable sequentially
- Best long-term maintainable clean architecture

ALWAYS use absolute paths.

### REPO

/Users/tr0n/Code/scroblebler

### RELEVANT FILES

**Current Entity/Store/Service (to rename):**

- /Users/tr0n/Code/scroblebler/Scroblebler/Models/Track.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Services/TrackStore.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Services/TrackService.swift

**Database & Storage:**

- /Users/tr0n/Code/scroblebler/Scroblebler/Storage/LocalDatabase.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Storage/OfflineQueue.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Storage/Models/QueuedOperation.swift

**Sync & Service Layer:**

- /Users/tr0n/Code/scroblebler/Scroblebler/Services/SyncService.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/ScrobbleManager.swift

**Supporting Files:**

- /Users/tr0n/Code/scroblebler/Scroblebler/Models.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Watcher.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Utilities/TrackIdentity.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Utilities/TrackMatcher.swift

**Files to Remove (Phase 6):**

- /Users/tr0n/Code/scroblebler/Scroblebler/Storage/Models/ListenBrainzCacheEntry.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Storage/Models/ListenBrainzCacheMeta.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Clients/ListenBrainzCache.swift

**Project Config:**

- /Users/tr0n/Code/scroblebler/Scroblebler.xcodeproj/project.pbxproj

## PLAN

See detailed plan: [plan.md](./plan.md)

**Key Decisions:**

- Listen entity with per-service sync state in JSON `services` column
- Playcount computed via COUNT(*) - eliminates ListenBrainz cache
- OfflineQueue simplified - scrobbles use Listen.services state
- Cover art via release_mbid → Cover Art Archive (service-agnostic)
- Conflict resolution: local wins for scrobbles, remote wins for love state
- Service links: mainServicePreference determines link targets

## EVENT LOG

- **initial analysis:** Deep analysis of current architecture completed
- **architecture complete:** Full plan with data models, sync engine, conflict resolution, and migration phases

* **2026-01-19 - Regression during rename (TrackService/ListenStore missing) + LLM context blow-up**
  * Observed that the migration temporarily “got worse” with cascading compile errors after partial rename / missing target wiring:
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Components/UndoButton.swift:7:45` `Cannot find 'TrackService' in scope`
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Components/BlacklistButton.swift:8:45` `Cannot find 'TrackService' in scope`
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Components/LoveButton.swift:6:48` `Cannot find 'TrackService' in scope`
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Watcher.swift:104:29` `Cannot find 'ListenStore' in scope`
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Watcher.swift:401:47` `Cannot convert value of type 'Listen' to expected argument type 'Track'`
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Models.swift:50:37` `Cast from 'DatabaseValue' to unrelated type 'String' always fails`
  * During investigation, an LLM provider hard-failed due to excessive accumulated prompt size:
    - `400 {"message":"prompt is too long: 202510 tokens > 200000 maximum"}`
    - This manifested as repeated “API Streaming Failed” errors and blocked further tool-driven analysis in that session.
  * Follow-up approach chosen:
    - Stop trying to load more files into a single prompt; instead, proceed incrementally with targeted reads/patches.
    - Focus first on restoring a clean build baseline (Xcode target wiring + actor isolation), then re-run builds.

* **2026-01-19 - Fixed Xcode target integration + Swift 6 actor isolation issues during Track→Listen migration**
  * Root cause of build failures: new files existed in the repo, but were not correctly wired into the Xcode target, and some PBX file references ended up with duplicated paths (e.g. `.../Scroblebler/Models/Scroblebler/Models/Listen.swift`), which produced Xcode “Build input files cannot be found” errors.
  * Investigated by grepping and editing project config at `/Users/tr0n/Code/scroblebler/Scroblebler.xcodeproj/project.pbxproj`.
  * Fixed PBX file references so paths are relative to their group (preventing double-prefixing) for:
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Models/Listen.swift`
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Services/ListenStore.swift`
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Services/SyncEngine.swift`
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Utilities/ListenIdentity.swift`
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Utilities/ListenMatcher.swift`
  * Resolved type-scope errors (`Cannot find type 'Listen' in scope`, `Cannot find type 'ServiceSyncState' in scope`) by ensuring the new Swift files are part of the Xcode build target.
  * Addressed Swift 6 concurrency/actor isolation warnings:
    - Made `SyncEngine` run on `@MainActor` and avoided referencing actor-isolated singletons from nonisolated contexts by introducing a `SyncEngine.makeDefault()` factory and using it from `/Users/tr0n/Code/scroblebler/Scroblebler/Views/ContentView.swift`.
    - Removed invalid `await` usage when accessing main-actor state inside `SyncEngine`.
  * Cleaned up remaining warnings and correctness:
    - Removed unused `displayService` in `/Users/tr0n/Code/scroblebler/Scroblebler/Components/NowPlaying.swift`.
    - Fixed ListenBrainz client issues after removing playcount cache (e.g. removed `??` on non-optional `Int`, removed unused local `username`) in `/Users/tr0n/Code/scroblebler/Scroblebler/Clients/ListenBrainzClient.swift`.
    - Implemented GRDB insert-id propagation cleanly by switching `Listen` to `MutablePersistableRecord` and adding `didInsert(with:for:)` in `/Users/tr0n/Code/scroblebler/Scroblebler/Models.swift`.
  * Verification commands:
    - `xcodebuild -project Scroblebler.xcodeproj -scheme Scroblebler -configuration Debug build`
    - `swift test`
    Both completed successfully (no errors).

* **2026-01-19 16:38-16:49 - Fixed remaining compilation errors after Track→Listen migration**
  * Resolved circular dependency in `/Users/tr0n/Code/scroblebler/Scroblebler/Models.swift`:
    - Removed duplicate `ServiceSyncState` and `Listen` struct definitions that were conflicting with `/Users/tr0n/Code/scroblebler/Scroblebler/Models/Listen.swift`
    - Kept only GRDB helper extensions (Dictionary.jsonString(), etc) in Models.swift
    - Fixed DatabaseValue JSON deserialization by directly extracting String from Row instead of casting
  * Fixed `/Users/tr0n/Code/scroblebler/Scroblebler/Watcher.swift` type confusion:
    - Removed redundant `convertTrackToListen()` function (getPlayerTrack already returns Listen)
    - Removed unused `artwork` variable assignment in getPlayerTrack
    - Fixed calls to ListenStore.shared throughout Watcher
  * Updated all UI components to eliminate TrackService references:
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Components/LoveButton.swift`: Changed from TrackStore+TrackService to ListenStore only
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Components/BlacklistButton.swift`: Replaced TrackService with direct LocalBlacklist.shared calls
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Components/UndoButton.swift`: Removed TrackStore playcount manipulation (no longer needed with SQL COUNT)
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Components/NowPlaying.swift`: Migrated from trackStore.currentTrack to listenStore.currentListen
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Components/HistoryItem.swift`: Changed from Track to Listen, adapted service info conversion
  * Fixed `/Users/tr0n/Code/scroblebler/Scroblebler/Views/ContentView.swift`:
    - Removed non-existent enrichCurrentListen() call
  * Fixed `/Users/tr0n/Code/scroblebler/Scroblebler/Views/MainView.swift`:
    - Migrated from trackStore/trackService to listenStore
    - Split complex mainContent view into smaller @ViewBuilder properties (focusTrap, nowPlayingSection, historySection, servicesSection) to fix SwiftUI type-checker timeout
    - Updated loadRecentTracks() and loadMoreTracks() to use ListenStore.refreshHistory() instead of TrackService.loadHistory()
    - Fixed handleBackfillEvent() to update Listen.services instead of Track.serviceInfo
    - Fixed preloadImages() to use releaseMbid for Cover Art Archive URLs
  * Fixed `/Users/tr0n/Code/scroblebler/Scroblebler/Services/SyncEngine.swift`:
    - Corrected deleteFromService() variable shadowing (fetch listen before trying to use it for canonical key)
  * Fixed `/Users/tr0n/Code/scroblebler/Scroblebler/Services/ListenStore.swift`:
    - Changed Logger.database → Logger.sync (Logger.database category doesn't exist)
    - Fixed getPending() SQL syntax for JSON extraction
  * Build verification: `swift build` completed with 0 errors

* **2026-01-20 - Fixed history regression (SQLite table/column mismatch) + added multi-service local history backfill**
  * Reported regression: UI showed absolutely no history; logs included:
    - `SQLite error 1: no such table: listen` while executing `SELECT * FROM "listen" ORDER BY "listenedAt" DESC LIMIT 20`
  * Root cause #1 (table naming):
    - Migration creates `listens` table in `/Users/tr0n/Code/scroblebler/Scroblebler/Storage/LocalDatabase.swift` (`v4_listens`), but GRDB default table naming used singular `listen`.
    - Fix: explicitly set `Listen.databaseTableName = "listens"` in `/Users/tr0n/Code/scroblebler/Scroblebler/Models.swift`.
  * Root cause #2 (column naming):
    - SQLite schema uses snake_case (`listened_at`, `created_at`, etc.) but GRDB columns were derived from `CodingKeys` (camelCase), producing invalid SQL like `ORDER BY "listenedAt"`.
    - Fix: mapped GRDB columns to the actual SQLite column names in `/Users/tr0n/Code/scroblebler/Scroblebler/Models.swift`.
  * After schema fixes, history still showed `Set history: 0 listens`:
    - Reason: UI reads history purely from SQLite via `/Users/tr0n/Code/scroblebler/Scroblebler/Services/ListenStore.swift::refreshHistory()`, but there was no initial “remote → local” import.
  * Implemented local-first backfill pipeline (remote → local → UI):
    - Added multi-service import+merge+dedup into SQLite in `/Users/tr0n/Code/scroblebler/Scroblebler/Views/MainView.swift`.
    - Fetches recent history from **all enabled services**, converts `Track → Listen`, matches by canonical key + timestamp window, and merges per-service sync state into `Listen.services`.
    - Added background page-by-page backfill to walk back in time until the beginning, without blocking initial UI render.
    - Key behavioral fix: prevent ListenBrainz pagination errors by ensuring page 1 is imported before page 2 (ListenBrainz requires `max_ts` state initialized on page 1).
  * Added DB utility to drive pagination from local reality:
    - `/Users/tr0n/Code/scroblebler/Scroblebler/Services/ListenStore.swift`: added `countListens()` to compute local total and derive `hasMoreTracks` without relying on UI-added count.
  * Build verification: `swift build` completed successfully.

## Next Steps

- [ ] Validate full history backfill completes (all pages until the beginning) for Last.fm + ListenBrainz without rate-limit issues
- [ ] Consider adding a small UI indicator for `isBackfillingHistory` (optional) so users know history is still loading
