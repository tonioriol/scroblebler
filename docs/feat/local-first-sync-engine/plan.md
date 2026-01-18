# Local-First Sync Engine - Architecture Plan

## Executive Summary

Redesign the scrobbling system with a local-first approach:
1. Rename `Track` → `Listen` (semantic correctness)
2. Persist listens to SQLite with per-service sync state
3. Optimistic UI updates with background sync
4. Simple conflict resolution on reconciliation

---

## Current State Analysis

### What Exists

```
┌─────────────────────────────────────────────────────────────────┐
│                     CURRENT ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Watcher ─────► Track (in-memory) ─────► TrackStore (in-memory) │
│     │                  │                        │                │
│     │                  ▼                        │                │
│     │          ScrobbleManager ◄────────────────┘                │
│     │                  │                                         │
│     │                  ▼                                         │
│     │          ┌───────────────┐                                 │
│     │          │ OfflineQueue  │ ◄──── SQLite                   │
│     │          │ (operations)  │                                 │
│     │          └───────────────┘                                 │
│     │                  │                                         │
│     ▼                  ▼                                         │
│  Media APIs    [Last.fm, Libre.fm, ListenBrainz]                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Problems

| Problem | Impact |
|---------|--------|
| `Track` is semantically wrong | Confusing - a "listen" is what we track, not the track itself |
| In-memory only storage | App restart loses all state except queued operations |
| Sync state scattered | `serviceInfo` on Track, `recentlyDeleted` in SyncService |
| No local source of truth | Always depends on API for history |
| Operation queue separate from entity | Redundant data structures |

---

## Proposed Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     NEW ARCHITECTURE                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Watcher ─────► NowPlaying (ephemeral) ───► ListenStore         │
│     │                                            │               │
│     │         ┌──────────────────────────────────┘               │
│     │         │                                                  │
│     │         ▼                                                  │
│     │    ┌─────────────────────────────────────────────┐        │
│     │    │              SQLite                          │        │
│     │    │  ┌─────────────────────────────────────┐    │        │
│     │    │  │ listens                              │    │        │
│     │    │  │ - id, track, artist, album, year    │    │        │
│     │    │  │ - listened_at, duration             │    │        │
│     │    │  │ - services (JSON per-service state) │    │        │
│     │    │  │ - loved, playcount                  │    │        │
│     │    │  └─────────────────────────────────────┘    │        │
│     │    │  ┌─────────────────────────────────────┐    │        │
│     │    │  │ operations (love/delete queue)      │    │        │
│     │    │  └─────────────────────────────────────┘    │        │
│     │    └─────────────────────────────────────────────┘        │
│     │                       │                                    │
│     │                       ▼                                    │
│     │              ┌─────────────────┐                          │
│     │              │   SyncEngine    │                          │
│     │              │ - processPending│                          │
│     │              │ - reconcile     │                          │
│     │              └────────┬────────┘                          │
│     │                       │                                    │
│     ▼                       ▼                                    │
│  Media APIs    [Last.fm, Libre.fm, ListenBrainz]                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Models

### Listen (SQLite Entity)

```swift
struct Listen: Identifiable, Codable, Equatable, FetchableRecord, PersistableRecord {
    // MARK: - Identity
    var id: Int64?  // nil = new, auto-assigned on insert

    // MARK: - Core Metadata
    let track: String
    let artist: String
    let album: String
    let year: Int?
    let duration: Double
    let listenedAt: Int  // Unix timestamp - when the listen occurred

    // MARK: - Per-Service Sync State (JSON)
    var services: [String: ServiceSyncState]

    // MARK: - User State (per-listen)
    var loved: Bool  // Love state for THIS specific listen
    // NOTE: playcount is NOT stored per-listen - it's computed via COUNT query

    // MARK: - Media & Source
    var releaseMbid: String?   // MusicBrainz release ID (for Cover Art Archive)
    var sourceBundle: String?  // Bundle ID of app that played the track
    // NOTE: Images are loaded lazily from Cover Art Archive using releaseMbid
    // We don't store service-specific image URLs - CAA is service-agnostic

    // MARK: - Internal Timestamps
    let createdAt: String  // ISO 8601 - when row was inserted (for debugging)
    var updatedAt: String  // ISO 8601 - when row was last modified (for sync conflict resolution)
    // Note: listenedAt is the actual scrobble timestamp sent to services

    // MARK: - Computed
    var canonicalKey: String {
        ListenIdentity.key(artist: artist, track: track)
    }

    var syncedServices: Set<String> {
        Set(services.filter { $0.value.status == .synced }.keys)
    }

    var pendingServices: Set<String> {
        Set(services.filter { $0.value.status == .pending }.keys)
    }
}
```

### Playcount (Computed, Not Stored)

Playcount is **not stored on each Listen**. It's computed on-demand:

```swift
// In ListenStore
func playcount(artist: String, track: String) async throws -> Int {
    try await db.asyncRead { db in
        try Listen
            .filter(Listen.Columns.artist.collating(.nocase) == artist)
            .filter(Listen.Columns.track.collating(.nocase) == track)
            .fetchCount(db)
    }
}
```

This replaces the entire ListenBrainz cache system which:
1. Fetched ALL listens from LB API (pages of 1000)
2. Stored (artist, track, playcount) tuples
3. Required incremental updates and cache invalidation

With local listens, we just COUNT rows. Simple.

### ServiceSyncState

```swift
struct ServiceSyncState: Codable, Equatable {
    enum Status: String, Codable {
        case pending   // Waiting to be sent
        case synced    // Successfully sent to service
        case failed    // Max retries reached
        case deleted   // User deleted from this service
    }

    var status: Status
    var timestamp: Int?        // For Last.fm/Libre.fm deletion
    var recordingMsid: String? // For ListenBrainz deletion
    var artistMbid: String?    // For ListenBrainz URLs
    var releaseMbid: String?   // For ListenBrainz URLs
    var error: String?
    var retryCount: Int
    var lastAttemptAt: String? // ISO 8601
}
```

### NowPlaying (Ephemeral)

```swift
struct NowPlaying {
    let id: UUID
    let track: String
    let artist: String
    let album: String
    let duration: Double
    let startedAt: Int
    let artwork: Data?
    let sourceBundle: String?

    // Convert to Listen when scrobble threshold met
    func toListen(enabledServices: [ScrobbleService]) -> Listen
}
```

---

## SQLite Schema

```sql
-- Migration: v4_listens
CREATE TABLE listens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    track TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT NOT NULL DEFAULT '',
    year INTEGER,
    duration REAL NOT NULL DEFAULT 0,
    listened_at INTEGER NOT NULL,

    services TEXT NOT NULL DEFAULT '{}',  -- JSON: per-service sync state

    loved INTEGER NOT NULL DEFAULT 0,
    -- NOTE: playcount is NOT stored - computed via COUNT(*) query

    release_mbid TEXT,          -- For Cover Art Archive images
    source_bundle TEXT,         -- App that played the track

    created_at TEXT NOT NULL,   -- When row was inserted
    updated_at TEXT NOT NULL    -- When row was last modified
);

-- Indexes
CREATE INDEX idx_listens_listened_at ON listens(listened_at DESC);
CREATE INDEX idx_listens_canonical ON listens(artist COLLATE NOCASE, track COLLATE NOCASE);
CREATE UNIQUE INDEX idx_listens_unique ON listens(artist, track, listened_at);

-- Playcount query (used instead of storing):
-- SELECT COUNT(*) FROM listens
-- WHERE artist COLLATE NOCASE = ? AND track COLLATE NOCASE = ?
```

---

## Core Components

### 1. ListenStore (Repository)

```swift
@MainActor
class ListenStore: ObservableObject {
    static let shared = ListenStore()
    private let db = LocalDatabase.shared

    // MARK: - Published State (for SwiftUI)
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var history: [Listen] = []
    @Published private(set) var pendingCount: Int = 0

    // MARK: - Now Playing (ephemeral)
    func setNowPlaying(_ np: NowPlaying)
    func clearNowPlaying()

    // MARK: - CRUD
    func insert(_ listen: Listen) async throws -> Listen
    func update(_ listen: Listen) async throws
    func delete(id: Int64) async throws

    // MARK: - Queries
    func getRecent(limit: Int) async throws -> [Listen]
    func getPending(service: String) async throws -> [Listen]
    func findByCanonicalKey(_ key: String) async throws -> Listen?
    func findByTimestamp(artist: String, track: String, timestamp: Int) async throws -> Listen?

    // MARK: - Playcount (replaces ListenBrainz cache)
    func playcount(artist: String, track: String) async throws -> Int

    // MARK: - Sync State
    func updateServiceState(listenId: Int64, service: String, state: ServiceSyncState) async throws
    func markSynced(listenId: Int64, service: String, timestamp: Int?, recordingMsid: String?) async throws
    func markFailed(listenId: Int64, service: String, error: String) async throws
    func markDeleted(listenId: Int64, service: String) async throws

    // MARK: - Bulk Operations
    func refreshHistory(limit: Int) async throws  // Reload from SQLite
    func pruneOld(keepDays: Int) async throws     // Delete old listens
}
```

### 2. SyncEngine

```swift
class SyncEngine {
    private let store: ListenStore
    private let scrobbleManager: ScrobbleManager
    private let offlineQueue: OfflineQueue

    // MARK: - Main Entry Points

    /// Called when scrobble threshold met
    func scrobble(_ nowPlaying: NowPlaying) async {
        // 1. Convert to Listen with pending status for all enabled services
        // 2. Insert into SQLite (optimistic)
        // 3. Update UI immediately
        // 4. Trigger sync for each pending service
    }

    /// Process all pending syncs
    func processPending() async {
        // For each enabled service:
        //   1. Get listens where services[x].status == pending
        //   2. Batch send to service
        //   3. Update status to synced/failed
    }

    /// Reconcile local with remote
    func reconcile(remoteTracks: [Listen], service: ScrobbleService) async {
        // For each remote track:
        //   1. Find local match by canonicalKey + timestamp window
        //   2. If match: merge service identifiers
        //   3. If no match: optionally import (user setting?)
    }

    /// Delete scrobble from service(s)
    func deleteFromService(listenId: Int64, services: [ScrobbleService]) async {
        // 1. Mark as deleted locally (optimistic)
        // 2. Call service API
        // 3. Update status on success/failure
    }
}
```

### 3. Conflict Resolution

```
┌─────────────────────────────────────────────────────────────────┐
│                    CONFLICT SCENARIOS                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ 1. LOCAL EXISTS, REMOTE DOESN'T                                 │
│    ├─ Local pending → Send to remote                            │
│    ├─ Local synced → User deleted remotely → Mark deleted       │
│    └─ Local failed → Keep failed state                          │
│                                                                  │
│ 2. REMOTE EXISTS, LOCAL DOESN'T                                 │
│    ├─ Import to local with synced status                        │
│    └─ Check other services for same listen                      │
│                                                                  │
│ 3. BOTH EXIST, DIFFERENT STATE                                  │
│    ├─ Merge service identifiers                                 │
│    ├─ Use remote loved status (remote = truth for UI)           │
│    └─ Update playcount from local count                         │
│                                                                  │
│ 4. TIMESTAMP MISMATCH (same track, ±60s)                        │
│    └─ Treat as same listen (clock skew between services)        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Migration Path

### Phase 1: Rename Track → Listen

**Scope:** Global rename, no functional changes

**Files to modify:**
- `Models/Track.swift` → `Models/Listen.swift`
- `Services/TrackStore.swift` → `Services/ListenStore.swift`
- `Services/TrackService.swift` → `Services/ListenService.swift`
- `Utilities/TrackIdentity.swift` → `Utilities/ListenIdentity.swift`
- `Utilities/TrackMatcher.swift` → `Utilities/ListenMatcher.swift`
- All references in ~30 files

**Approach:**
1. Rename files
2. Global search/replace with case sensitivity
3. Update Xcode project references
4. Run tests to verify

### Phase 2: Add SQLite Schema

**Scope:** Database migration only

**Changes:**
- Add `v4_listens` migration to `LocalDatabase.swift`
- Add `Listen` GRDB conformance
- Add `ServiceSyncState` model

### Phase 3: Implement ListenStore

**Scope:** Replace in-memory TrackStore with SQLite-backed ListenStore

**Changes:**
- Rewrite `ListenStore` to use SQLite
- Keep @Published properties for SwiftUI
- Add async CRUD methods
- Migrate nowPlaying handling

### Phase 4: Implement SyncEngine

**Scope:** New sync logic with optimistic updates

**Changes:**
- Create `SyncEngine.swift`
- Integrate with `ScrobbleManager`
- Handle pending queue processing
- Add reconciliation logic

### Phase 5: Update Watcher Integration

**Scope:** Connect Watcher to new system

**Changes:**
- Update `Watcher.onScrobbleWanted` to use SyncEngine
- Update `Watcher.onTrackChanged` to use ListenStore
- Ensure smooth NowPlaying → Listen transition

### Phase 6: Remove ListenBrainz Cache

**Scope:** Eliminate redundant playcount caching

**Why:** With persistent local listens, playcount is simply:
```sql
SELECT COUNT(*) FROM listens WHERE artist = ? AND track = ?
```

**Files to remove:**
- `Storage/Models/ListenBrainzCacheEntry.swift`
- `Storage/Models/ListenBrainzCacheMeta.swift`
- `Clients/ListenBrainzCache.swift`

**Database cleanup:**
- Remove `listenbrainz_cache` table
- Remove `listenbrainz_cache_meta` table

**Changes:**
- Add `ListenStore.playcount(artist:track:)` method
- Update `ListenBrainzService` to use local playcount
- Remove cache population code from reconciliation

### Phase 7: Remove Legacy Code

**Scope:** Final cleanup

**Changes:**
- Remove old `ListenService` if fully replaced by SyncEngine
- Clean up unused `SyncService` code
- Remove redundant references
- Update documentation

---

## Key Design Decisions

### 1. Eliminate OfflineQueue for Scrobbles

**Why:** With per-service sync state on each Listen, the separate operations queue for scrobbles becomes redundant.

**Current approach:**
```swift
// OLD: Separate queue
OfflineQueue.enqueue(.scrobble(track: track, services: [...]))
```

**New approach:**
```swift
// NEW: Built into Listen
listen.services["lastfm"] = ServiceSyncState(status: .pending, ...)
ListenStore.insert(listen)  // Persists with pending state
SyncEngine.processPending() // Queries pending and syncs
```

**What stays in OfflineQueue:**
- Love/unlove operations (apply to ALL listens of a track, not single listen)
- Delete operations (need timestamp/msid from original listen)

### 2. JSON for Per-Service State

**Why:** Flexible schema for service-specific fields (recordingMsid, artistMbid, etc.) without schema changes. GRDB has good JSON support.

### 3. Optimistic UI Updates

**Why:** User sees immediate feedback. Sync happens in background. Failures are rare and can be retried.

### 4. Conflict Resolution Without Remote updated_at

**Challenge:** Services don't return `updated_at` timestamps, so we can't do last-write-wins.

**Solution - Intent-Based Resolution:**

| Scenario | Resolution | Rationale |
|----------|------------|-----------|
| **Scrobble** | Local wins | We created it, we know when |
| **Love state** | Remote wins (on sync) | User may have changed via web |
| **Deletion** | Local intent wins | Explicit user action in app |
| **Import** | Remote is truth | We're backfilling local |

**How it works:**
```swift
func reconcile(local: Listen?, remote: Listen, service: ScrobbleService) {
    if local == nil {
        // Import from remote
        store.insert(remote.withSyncedStatus(for: service))
    } else if local.services[service]?.status == .pending {
        // We haven't sent it yet - send it
        continue // will be sent by processPending()
    } else if local.services[service]?.status == .synced {
        // Already synced - update loved status from remote
        local.loved = remote.loved
        store.update(local)
    }
}
```

### 5. Timestamp-Based Matching (±60s window)

**Why:** Different services may record slightly different timestamps. 60-second window handles clock skew while being specific enough to match correctly.

### 6. No "Now Playing" Persistence

**Why:** Now playing is inherently ephemeral. Persisting it adds complexity with no real benefit. On app restart, we just don't show anything until media plays.

### 7. Local Playcount Calculation

**Why:** With all listens stored locally, we can calculate playcount with a simple COUNT query instead of maintaining a separate cache table. This eliminates the ListenBrainz cache entirely.

### 8. Cover Art via MusicBrainz/CAA

**Strategy:** Store `release_mbid` on Listen, load images lazily from Cover Art Archive.

**Why not service-specific URLs?**
- Last.fm returns `lastfm.freetls.fastly.net/...` URLs (service-specific)
- ListenBrainz constructs CAA URLs from `release_mbid`
- Local-first means we don't depend on any service for images

**Implementation:**
```swift
// On Listen
var releaseMbid: String?

// Image loading
func coverArtUrl() -> URL? {
    guard let mbid = releaseMbid else { return nil }
    return URL(string: "https://coverartarchive.org/release/\(mbid)/front-250")
}
```

**Enrichment:** Use MBID Mapper 2.0 to get `release_mbid` when missing.

### 9. Service Links Preference

**Challenge:** With unified local history, which service should links point to?

**Solution:** Keep `mainServicePreference` setting.

```swift
// User preference: which service's web pages to open
Defaults.shared.mainServicePreference // .lastfm | .listenbrainz | .librefm

// URL building uses the preferred service
func artistUrl(for listen: Listen) -> URL {
    let preference = Defaults.shared.mainServicePreference ?? .lastfm
    switch preference {
    case .lastfm:
        return URL(string: "https://last.fm/music/\(listen.artist)")!
    case .listenbrainz:
        if let mbid = listen.services["listenbrainz"]?.artistMbid {
            return URL(string: "https://listenbrainz.org/artist/\(mbid)")!
        }
        return URL(string: "https://listenbrainz.org/search/?...")!
    }
}
```

**Note:** MBIDs stored in `services` JSON enable direct LB links without search fallback.

---

## API Flow Diagrams

### Scrobble Flow

```
┌─────────┐     ┌──────────┐     ┌────────────┐     ┌─────────────┐
│ Watcher │     │  Engine  │     │ListenStore │     │ SQLite      │
└────┬────┘     └────┬─────┘     └─────┬──────┘     └──────┬──────┘
     │               │                 │                   │
     │ onScrobbleWanted(nowPlaying)    │                   │
     │──────────────►│                 │                   │
     │               │                 │                   │
     │               │ toListen()      │                   │
     │               │────────────────►│                   │
     │               │                 │                   │
     │               │                 │ INSERT            │
     │               │                 │──────────────────►│
     │               │                 │                   │
     │               │                 │ Listen(id: 42)    │
     │               │                 │◄──────────────────│
     │               │                 │                   │
     │               │ @Published history updated          │
     │               │◄────────────────│                   │
     │               │                 │                   │
     │               │ processPending(service: lastfm)     │
     │               │─────────────────────────────────────┼───────►
     │               │                                     │ API
     │               │                 │                   │
     │               │                 │ UPDATE services   │
     │               │                 │──────────────────►│
     │               │                 │                   │
```

### Reconciliation Flow

```
┌────────┐     ┌──────────┐     ┌────────────┐     ┌─────────┐
│  View  │     │  Engine  │     │ListenStore │     │ API     │
└───┬────┘     └────┬─────┘     └─────┬──────┘     └────┬────┘
    │               │                 │                 │
    │ loadHistory() │                 │                 │
    │──────────────►│                 │                 │
    │               │                 │                 │
    │               │ getRecent(50)   │                 │
    │               │──────────────►  │                 │
    │               │                 │                 │
    │               │ [local listens] │                 │
    │               │◄────────────────│                 │
    │               │                 │                 │
    │               │                 │ fetch(limit:50) │
    │               │─────────────────┼────────────────►│
    │               │                 │                 │
    │               │                 │ [remote tracks] │
    │               │◄────────────────┼─────────────────│
    │               │                 │                 │
    │               │ reconcile(local, remote)         │
    │               │─────────────────►                 │
    │               │                 │                 │
    │               │ [merged listens]│                 │
    │◄──────────────│◄────────────────│                 │
    │               │                 │                 │
```

---

## Testing Strategy

### Unit Tests

1. `ListenTests` - Model serialization, canonicalKey
2. `ListenStoreTests` - CRUD operations, queries, playcount
3. `SyncEngineTests` - Pending processing, conflict resolution
4. `ServiceSyncStateTests` - Status transitions

### Integration Tests

1. Full scrobble flow (Watcher → SQLite → API mock)
2. Offline queue persistence and recovery
3. Reconciliation with mock API responses

### E2E Tests

1. Scrobble while offline → come online → verify sync
2. Delete scrobble → verify removed from all services
3. Multi-service sync (listen exists in LB but not Last.fm)

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Large rename breaks things | Incremental commits, run tests after each phase |
| SQLite migration data loss | No existing listen data to migrate (new table) |
| Performance with large history | Index on listened_at, pagination, pruning |
| Complex conflict resolution | Start simple, log conflicts for later analysis |

---

## Success Criteria

- [ ] All `Track` references renamed to `Listen`
- [ ] Listens persist across app restarts
- [ ] Sync state visible in UI per service
- [ ] Offline scrobbles sync when online
- [ ] Local playcount replaces ListenBrainz cache
- [ ] No regression in existing functionality
- [ ] Tests pass

---

## Resolved Decisions

| Question | Decision |
|----------|----------|
| Import remote-only listens? | Yes, mark with `sourceBundle: nil` or `sourceBundle: "imported"` |
| How long to keep locally? | 90 days default, configurable via `Defaults.shared.listenRetentionDays` |
| Soft or hard delete? | Per-service soft delete (mark `status: .deleted`), prune after retention period |
| Image storage? | Store `release_mbid`, load from Cover Art Archive lazily |
| Service links? | Keep `mainServicePreference` for link target selection |
| Playcount storage? | Compute via COUNT query, don't store |
| OfflineQueue for scrobbles? | No - use per-service sync state on Listen |

## Open Questions

1. **Should we batch scrobble submissions?**
   - Pro: More efficient API usage
   - Con: Added complexity
   - Proposal: Start with single submissions, optimize later if needed

2. **How to handle duplicate detection from imports?**
   - Same artist + track + timestamp(±60s) = duplicate
   - What if imported from multiple services with different timestamps?
   - Proposal: Create single Listen, merge service identifiers

3. **What about NowPlaying sync failures?**
   - Currently fire-and-forget
   - Proposal: Keep fire-and-forget (NowPlaying is inherently transient)
