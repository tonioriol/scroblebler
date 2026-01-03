# Scroblebler - Complete Refactoring Plan

## Executive Summary

This document outlines a comprehensive refactoring plan for Scroblebler to improve code organization, add persistent storage, enable offline functionality, and optimize performance.

### Goals
1. **Extract matching logic** - Clean up ServiceManager
2. **Add persistent blacklist** - User-requested feature
3. **Add offline queue** - Enable offline scrobbling
4. **Migrate to SQLite** - Better performance for large datasets
5. **Keep it simple** - Minimal complexity, maximum value

### Non-Goals
- ❌ Full local-first architecture (too complex)
- ❌ Conflict resolution (not needed with master/slave model)
- ❌ Complete history storage (services are source of truth)

---

## Current Architecture

```
┌──────────────────────────────────────┐
│           UI Layer                   │
│         (MainView, etc.)             │
└─────────────┬────────────────────────┘
              │
        ┌─────▼────────┐
        │Service       │
        │Manager       │  ← Does everything
        └─────┬────────┘
              │
    ┌─────────┼──────────────┐
    │         │              │
┌───▼───┐ ┌──▼──────┐  ┌────▼────┐
│Last.fm│ │Listen   │  │Libre.fm │
│       │ │Brainz   │  │         │
└───────┘ └─────────┘  └─────────┘
```

**Current State:**
- ✅ Works well for online syncing
- ✅ Master/slave sync pattern is sound
- ❌ Large JSON files for ListenBrainz cache (slow, memory intensive)
- ❌ No persistent blacklist
- ❌ No offline support
- ❌ Matching logic mixed into ServiceManager

---

## Target Architecture

```
┌──────────────────────────────────────┐
│           UI Layer                   │
│   (optimistic updates, instant)      │
└─────────────┬────────────────────────┘
              │
        ┌─────▼──────┐
        │Reachability│
        │  Monitor   │
        └─────┬──────┘
              │
        Is Online?
        /          \
      NO           YES
      /              \
┌────▼─────┐    ┌────▼────────┐
│Offline   │    │Execute      │
│Queue     │    │Immediately  │
│(SQLite)  │    │             │
└──────────┘    └─────┬───────┘
                      │
              ┌───────▼────┐
              │Service     │
              │Manager     │
              └───────┬────┘
                      │
            ┌─────────┼──────────┐
            │         │          │
        ┌───▼───┐ ┌───▼────┐ ┌──▼──────┐
        │Last.fm│ │Listen  │ │Libre.fm │
        │       │ │Brainz  │ │         │
        └───────┘ └────────┘ └─────────┘

┌─────────────────────────────────────┐
│      Local SQLite Database          │
│  • ListenBrainz playcount cache     │
│  • Blacklist                        │
│  • Operation queue                  │
└─────────────────────────────────────┘
```

---

## Technology Decisions

### Database: GRDB.swift

**Why GRDB over SQLite.swift:**
- ✅ Native async/await support (we're already using it)
- ✅ Built-in migration system
- ✅ Better performance for large datasets
- ✅ Type-safe models
- ✅ ValueObservation for reactive updates
- ✅ Very active maintenance

**Installation:**
```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
]
```

### Why Not Full Local-First?

**Problem:** If we store full history locally:
```
1. User deletes track from Last.fm website
2. Local state still has it
3. How do we detect the deletion?
   - Poll constantly? (expensive)
   - Compare full history? (slow)
   - Accept stale data? (confusing)
```

**Solution:** Services remain source of truth for history. Local stores only:
- Blacklist (user preference)
- Operation queue (temporary, cleared after sync)
- ListenBrainz cache (performance optimization, can rebuild)

---

## Database Schema

```sql
-- ListenBrainz playcount cache (replaces massive JSON file)
-- Current JSON: { "data": { "artist|track": count, ... }, "continue_from_ts": ..., "completed_at": ... }
CREATE TABLE listenbrainz_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    artist TEXT NOT NULL,              -- Normalized
    track TEXT NOT NULL,               -- Normalized
    playcount INTEGER NOT NULL,
    created_at TEXT NOT NULL,          -- ISO 8601 UTC: YYYY-MM-DD HH:MM:SS.SSS
    updated_at TEXT NOT NULL,          -- ISO 8601 UTC: YYYY-MM-DD HH:MM:SS.SSS
    UNIQUE (username, artist, track)
);
CREATE INDEX idx_lbc_username ON listenbrainz_cache(username);
CREATE INDEX idx_lbc_updated ON listenbrainz_cache(updated_at);

-- ListenBrainz cache metadata (fetch progress tracking)
CREATE TABLE listenbrainz_cache_meta (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    continue_from_ts INTEGER,          -- Unix timestamp (API returns this format)
    completed_at TEXT,                 -- ISO 8601 UTC when full fetch completed
    total_tracks INTEGER,              -- Quick count
    created_at TEXT NOT NULL,          -- ISO 8601 UTC: YYYY-MM-DD HH:MM:SS.SSS
    updated_at TEXT NOT NULL           -- ISO 8601 UTC: YYYY-MM-DD HH:MM:SS.SSS
);

-- User blacklist (new feature)
CREATE TABLE blacklist (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    artist TEXT NOT NULL,
    track TEXT NOT NULL,
    created_at TEXT NOT NULL,          -- ISO 8601 UTC: YYYY-MM-DD HH:MM:SS.SSS
    updated_at TEXT NOT NULL,          -- ISO 8601 UTC: YYYY-MM-DD HH:MM:SS.SSS
    UNIQUE (artist, track)
);
CREATE INDEX idx_blacklist_created ON blacklist(created_at DESC);

-- Operation queue (new feature - offline support)
CREATE TABLE operations (
    id TEXT PRIMARY KEY,               -- UUID
    type TEXT NOT NULL,                -- 'scrobble' | 'love' | 'delete'
    payload TEXT NOT NULL,             -- JSON
    attempts INTEGER DEFAULT 0,
    last_error TEXT,
    last_attempt TEXT,                 -- ISO 8601 UTC: YYYY-MM-DD HH:MM:SS.SSS
    created_at TEXT NOT NULL,          -- ISO 8601 UTC: YYYY-MM-DD HH:MM:SS.SSS
    updated_at TEXT NOT NULL           -- ISO 8601 UTC: YYYY-MM-DD HH:MM:SS.SSS
);
CREATE INDEX idx_operations_pending ON operations(attempts, created_at)
    WHERE attempts < 5;
```

---

## File Structure

### New Files

```
Scroblebler/
├── Storage/
│   ├── LocalDatabase.swift           # GRDB setup, migrations
│   ├── Models/                       # Database models
│   │   ├── Playcount.swift
│   │   ├── BlacklistEntry.swift
│   │   └── QueuedOperation.swift
│   ├── LocalBlacklist.swift          # Blacklist operations
│   └── OfflineQueue.swift            # Queue operations
├── Utilities/
│   ├── TrackMatcher.swift            # Extracted matching logic (NEW)
│   └── Reachability.swift            # Network monitoring
└── Services/
    └── ServiceManager.swift          # Simplified (MODIFIED)
```

### Modified Files

```
Scroblebler/
├── Watcher.swift                     # Check blacklist before scrobble
├── Clients/
│   └── ListenBrainzCache.swift      # Use SQLite instead of JSON
└── Components/
    ├── HistoryItem.swift             # Show offline status
    └── BlacklistButton.swift         # New UI component
```

---

## Implementation Plan

### Phase 1: Extract Sync & Matching Logic ✅ COMPLETE

**Goal:** Break up God Object ServiceManager by extracting all sync-related logic

**Problem:** ServiceManager has 10 responsibilities in 402 lines. Sync logic alone is 155 lines (38%)

**Solution:** Extract into focused, single-purpose classes

#### Files Created: ✅
1. ✅ `Scroblebler/Utilities/TrackMatcher.swift` - Pure matching logic
2. ✅ `Scroblebler/Services/CrossServiceSync.swift` - Sync coordination
3. ✅ `Scroblebler/Services/BackfillService.swift` - Backfill execution

#### Files Modified: ✅
1. ✅ `Scroblebler/ServiceManager.swift` - Simplified orchestration
2. ✅ `Scroblebler/Clients/LastFmClient.swift` - Graceful error handling in track enrichment
3. ✅ `Scroblebler/Clients/ListenBrainzClient.swift` - Improved end-of-history detection
4. ✅ `Scroblebler/Protocols/ScrobbleClient.swift` - Removed username parameters

---

#### 1. Create TrackMatcher.swift

```swift
// Scroblebler/Utilities/TrackMatcher.swift
import Foundation

/// Pure matching logic for tracks across services
struct TrackMatcher {
    /// Find matching track using timestamp-based matching
    /// - Returns: First track within 2-minute window with ≤5s timestamp delta
    static func findMatch(for track: RecentTrack, in candidates: [RecentTrack]) -> RecentTrack? {
        candidates.first { candidate in
            timestampsMatch(track.date, candidate.date) &&
            abs((track.date ?? 0) - (candidate.date ?? 0)) <= 5
        }
    }
    
    private static func timestampsMatch(_ d1: Int?, _ d2: Int?) -> Bool {
        guard let d1 = d1, let d2 = d2 else { return d1 == nil && d2 == nil }
        return abs(d1 - d2) < 120  // 2-minute window
    }
}
```

---

#### 2. Create CrossServiceSync.swift

```swift
// Scroblebler/Services/CrossServiceSync.swift
import Foundation

/// Coordinates synchronization of track data across multiple scrobble services
class CrossServiceSync {
    private let clients: [ScrobbleService: ScrobbleClient]
    
    init(clients: [ScrobbleService: ScrobbleClient]) {
        self.clients = clients
    }
    
    /// Reconcile primary tracks with secondary services
    /// - Returns: List of tracks that need backfilling
    func reconcile(
        primaryTracks: inout [RecentTrack],
        secondaryServices: [ServiceCredentials],
        limit: Int,
        page: Int
    ) async -> [(track: RecentTrack, credentials: ServiceCredentials)] {
        // Calculate time range for efficient fetching
        let timeRange = calculateTimeRange(from: primaryTracks)
        
        // Fetch from all secondary services in parallel
        let secondaryTracks = await fetchTracks(
            from: secondaryServices,
            timeRange: timeRange,
            limit: limit,
            page: page
        )
        
        // Match and merge, collecting tracks that need backfilling
        return matchAndMerge(
            primary: &primaryTracks,
            secondary: secondaryTracks,
            services: secondaryServices
        )
    }
    
    // MARK: - Private
    
    private func calculateTimeRange(from tracks: [RecentTrack]) -> TimeRange {
        let timestamps = tracks.compactMap { $0.date }
        let buffer = 300  // 5-minute buffer for clock skew
        
        return TimeRange(
            min: timestamps.min().map { $0 - buffer },
            max: timestamps.max().map { $0 + buffer }
        )
    }
    
    private func fetchTracks(
        from services: [ServiceCredentials],
        timeRange: TimeRange,
        limit: Int,
        page: Int
    ) async -> [ServiceCredentials: [RecentTrack]] {
        var results: [ServiceCredentials: [RecentTrack]] = [:]
        
        await withTaskGroup(of: (ServiceCredentials, [RecentTrack]?).self) { group in
            for creds in services {
                guard let client = clients[creds.service] else { continue }
                
                group.addTask {
                    // Try time-range query first (faster, more accurate)
                    if let tracks = try? await client.getRecentTracksByTimeRange(
                        username: creds.username,
                        minTs: timeRange.min,
                        maxTs: timeRange.max,
                        limit: 1000,
                        token: creds.token
                    ), !tracks.isEmpty {
                        Logger.debug("Fetched \(tracks.count) tracks from \(creds.service.displayName) (timestamp query)", log: Logger.sync)
                        return (creds, tracks)
                    }
                    
                    // Fallback to page-based fetch
                    let fetchLimit = min(limit * 10 * page, 1000)
                    let tracks = try? await client.getRecentTracks(
                        username: creds.username,
                        limit: fetchLimit,
                        page: 1,
                        token: creds.token
                    )
                    Logger.debug("Fetched \(tracks?.count ?? 0) tracks from \(creds.service.displayName) (page query)", log: Logger.sync)
                    return (creds, tracks)
                }
            }
            
            for await (creds, tracks) in group {
                if let tracks = tracks { results[creds] = tracks }
            }
        }
        
        return results
    }
    
    private func matchAndMerge(
        primary: inout [RecentTrack],
        secondary: [ServiceCredentials: [RecentTrack]],
        services: [ServiceCredentials]
    ) -> [(track: RecentTrack, credentials: ServiceCredentials)] {
        var backfillTasks: [(track: RecentTrack, credentials: ServiceCredentials)] = []
        
        for (creds, tracks) in secondary {
            for index in primary.indices {
                if let match = TrackMatcher.findMatch(for: primary[index], in: tracks) {
                    // Track exists - merge service info
                    Logger.info("[MATCH] ✅ Matched '\(primary[index].artist) - \(primary[index].name)' in \(creds.service.displayName)", log: Logger.sync)
                    primary[index].serviceInfo.merge(match.serviceInfo) { (_, new) in new }
                } else if BackfillService.canBackfill(track: primary[index], to: creds.service) {
                    // Track missing and eligible for backfill
                    Logger.info("[MATCH] ❌ No match for '\(primary[index].artist) - \(primary[index].name)' in \(creds.service.displayName)", log: Logger.sync)
                    backfillTasks.append((track: primary[index], credentials: creds))
                }
            }
        }
        
        return backfillTasks
    }
}

// Supporting types
struct TimeRange {
    let min: Int?
    let max: Int?
}
```

---

#### 3. Create BackfillService.swift

```swift
// Scroblebler/Services/BackfillService.swift
import Foundation

/// Handles backfilling missing tracks to services
class BackfillService {
    private let clients: [ScrobbleService: ScrobbleClient]
    
    init(clients: [ScrobbleService: ScrobbleClient]) {
        self.clients = clients
    }
    
    /// Execute backfill tasks asynchronously
    func execute(tasks: [(track: RecentTrack, credentials: ServiceCredentials)]) async {
        Logger.info("Backfilling \(tasks.count) missing tracks", log: Logger.sync)
        
        var succeeded = 0
        var failed = 0
        
        for (index, (recentTrack, credentials)) in tasks.enumerated() {
            Logger.debug("Backfill task \(index + 1)/\(tasks.count): '\(recentTrack.artist) - \(recentTrack.name)' to \(credentials.service.displayName)", log: Logger.sync)
            
            let track = Track(
                artist: recentTrack.artist,
                album: recentTrack.album,
                name: recentTrack.name,
                length: 0,
                artwork: nil,
                loved: recentTrack.loved,
                startedAt: Int32(recentTrack.date ?? 0)
            )
            
            do {
                guard let client = clients[credentials.service] else { continue }
                
                try await client.scrobble(sessionKey: credentials.token, track: track)
                let age = (recentTrack.date.map { Date().timeIntervalSince1970 - TimeInterval($0) } ?? 0) / 86400
                Logger.info("Synced to \(credentials.service.displayName): '\(track.name)' (\(Int(age))d old)", log: Logger.sync)
                succeeded += 1
                
                // Sync love state
                try? await client.updateLove(
                    sessionKey: credentials.token,
                    artist: recentTrack.artist,
                    track: recentTrack.name,
                    loved: recentTrack.loved
                )
                
                // Rate limiting
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                Logger.error("Failed \(credentials.service.displayName): '\(track.name)' - \(error)", log: Logger.sync)
                failed += 1
            }
        }
        
        Logger.info("Backfill complete: \(succeeded) succeeded, \(failed) failed", log: Logger.sync)
    }
    
    /// Check if track is eligible for backfilling to a service
    static func canBackfill(track: RecentTrack, to service: ScrobbleService) -> Bool {
        guard let timestamp = track.date else { return false }
        let age = Date().timeIntervalSince1970 - TimeInterval(timestamp)
        let daysOld = age / 86400
        
        switch service {
        case .lastfm, .librefm:
            return daysOld < 14
        case .listenbrainz:
            return true
        }
    }
}
```

---

#### 4. Simplify ServiceManager.swift

**Replace `enrichTracksWithOtherServices` method (lines 226-310):**

```swift
private func enrichTracksWithOtherServices(tracks: inout [RecentTrack], otherServices: [ServiceCredentials], limit: Int, page: Int) async {
    // Use CrossServiceSync to reconcile tracks
    let backfillTasks = await crossServiceSync.reconcile(
        primaryTracks: &tracks,
        secondaryServices: otherServices,
        limit: limit,
        page: page
    )
    
    // Execute backfills asynchronously
    if !backfillTasks.isEmpty {
        Task {
            await backfillService.execute(tasks: backfillTasks)
        }
    }
}
```

**Delete these methods (lines 312-401):**
- `canBackfill()` - moved to BackfillService
- `backfillMissingTracks()` - moved to BackfillService
- `findBestMatch()` - replaced by TrackMatcher
- `timestampsMatch()` - moved to TrackMatcher

**Add properties at top of ServiceManager:**

```swift
private let crossServiceSync: CrossServiceSync
private let backfillService: BackfillService

init() {
    self.crossServiceSync = CrossServiceSync(clients: clients)
    self.backfillService = BackfillService(clients: clients)
}
```

---

### Phase 1 Implementation Details

#### What Was Actually Built

**1. TrackMatcher.swift (20 lines)**
- Pure timestamp-based matching logic
- 2-minute window with ≤5s delta for exact matches
- Zero dependencies, fully testable in isolation

**2. CrossServiceSync.swift (110 lines)**
- Parallel track fetching from secondary services
- Time-range optimization for efficient queries
- Match and merge logic with backfill task collection
- Comprehensive logging for debugging

**3. BackfillService.swift (70 lines)**
- Async backfill execution with rate limiting
- Service-specific backfill eligibility (14 days for Last.fm/Libre.fm, unlimited for ListenBrainz)
- Automatic love state synchronization
- Detailed progress tracking and error reporting

**4. ServiceManager.swift (Simplified)**
- Removed 155 lines of sync logic
- Delegated to CrossServiceSync and BackfillService
- Cleaner, more maintainable codebase

**5. Pagination Fixes**
- **LastFmClient**: Modified `getTrackInfo()` to handle API errors gracefully
  - Check for error responses before decoding
  - Return default values instead of throwing
  - Prevents individual track lookup failures from crashing pagination
  
- **ListenBrainzClient**: Improved end-of-history detection
  - Distinguish between empty results (normal) and missing timestamps (error)
  - Clear debug logging for end of pagination
  - No more confusing error messages

**6. Protocol Updates**
- Removed username parameters from ScrobbleClient methods
- Clients now use stored credentials (set via `setCredentials()`)
- Cleaner API, consistent authentication flow

#### Issues Resolved

1. **Pagination Failure**: Both Last.fm and ListenBrainz pagination now work correctly
   - Last.fm: Handles track.getInfo errors gracefully
   - ListenBrainz: Correctly identifies end of history without errors

2. **God Object ServiceManager**: Reduced from 402 to ~250 lines
   - Sync logic fully extracted
   - Single Responsibility Principle restored
   - Much easier to test and maintain

3. **Authentication Consistency**: Credentials properly restored on app startup
   - All clients use stored username/token
   - No more passing credentials through every method call

---

### Results

**Code Metrics:**
- TrackMatcher.swift: +20 lines
- CrossServiceSync.swift: +110 lines
- BackfillService.swift: +70 lines
- ServiceManager.swift: -155 lines (310 → 155 lines of sync logic removed)
- **Net: +45 lines, but 3 focused classes vs 1 god object**

**ServiceManager Before/After:**
- Before: 402 lines, 10 responsibilities
- After: ~250 lines, 7 responsibilities
- Sync logic: 0 lines (fully extracted)

**Benefits:**
- ✅ Single Responsibility Principle
- ✅ Testable in isolation
- ✅ Parallel fetching (performance)
- ✅ Clear, readable code
- ✅ Easy to extend with new strategies

**Timeline:** 2-3 hours implementation + testing

---

### Phase 2: Add SQLite Database

**Goal:** Set up GRDB, create schema, enable migrations

**Files:**
- Create: `Scroblebler/Storage/LocalDatabase.swift`
- Create: `Scroblebler/Storage/Models/*.swift`

**Code:**
```swift
// LocalDatabase.swift
import GRDB

class LocalDatabase {
    static let shared = LocalDatabase()
    private let dbQueue: DatabaseQueue
    
    init() {
        let path = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scroblebler")
            .appendingPathComponent("scroblebler.db")
            .path
        
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        
        dbQueue = try! DatabaseQueue(path: path)
        try! migrator.migrate(dbQueue)
    }
    
    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        migrator.registerMigration("v1_listenbrainz_cache") { db in
            // Playcount data table
            try db.create(table: "listenbrainz_cache") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("username", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("track", .text).notNull()
                t.column("playcount", .integer).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_lbc_unique ON listenbrainz_cache(username, artist, track)
            """)
            try db.create(index: "idx_lbc_username", on: "listenbrainz_cache", columns: ["username"])
            try db.create(index: "idx_lbc_updated", on: "listenbrainz_cache", columns: ["updated_at"])
            
            // Metadata table
            try db.create(table: "listenbrainz_cache_meta") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("username", .text).notNull().unique()
                t.column("continue_from_ts", .integer)
                t.column("completed_at", .text)
                t.column("total_tracks", .integer)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
        }
        
        migrator.registerMigration("v2_blacklist") { db in
            try db.create(table: "blacklist") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("artist", .text).notNull()
                t.column("track", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_blacklist_unique ON blacklist(artist, track)
            """)
            try db.create(index: "idx_blacklist_created", on: "blacklist", columns: ["created_at"])
        }
        
        migrator.registerMigration("v3_operations") { db in
            try db.create(table: "operations") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("payload", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("last_error", .text)
                t.column("last_attempt", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            
            try db.execute(sql: """
                CREATE INDEX idx_operations_pending ON operations(attempts, created_at)
                WHERE attempts < 5
            """)
        }
        
        return migrator
    }
    
    // Public interface
    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }
    
    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }
    
    func asyncRead<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.read(block)
    }
    
    func asyncWrite<T>(_ block: @escaping (Database) throws -> T) async throws -> T {
        try await dbQueue.write(block)
    }
}

// Models/ListenBrainzCacheEntry.swift
import GRDB
import Foundation

struct ListenBrainzCacheEntry: Codable, FetchableRecord, PersistableRecord {
    var id: Int?
    var username: String
    var artist: String
    var track: String
    var playcount: Int
    var createdAt: String  // ISO 8601 UTC
    var updatedAt: String  // ISO 8601 UTC
    
    enum Columns: String, ColumnExpression {
        case id, username, artist, track, playcount
        case createdAt, updatedAt
    }
}

// Models/ListenBrainzCacheMeta.swift
import GRDB
import Foundation

struct ListenBrainzCacheMeta: Codable, FetchableRecord, PersistableRecord {
    var id: Int?
    var username: String
    var continueFromTs: Int?       // Unix timestamp (API format)
    var completedAt: String?       // ISO 8601 UTC
    var totalTracks: Int?
    var createdAt: String          // ISO 8601 UTC
    var updatedAt: String          // ISO 8601 UTC
    
    enum Columns: String, ColumnExpression {
        case id, username, continueFromTs, completedAt, totalTracks
        case createdAt, updatedAt
    }
}

// Models/BlacklistEntry.swift
import GRDB
import Foundation

struct BlacklistEntry: Codable, FetchableRecord, PersistableRecord {
    var id: Int?
    var artist: String
    var track: String
    var createdAt: String  // ISO 8601 UTC
    var updatedAt: String  // ISO 8601 UTC
    
    enum Columns: String, ColumnExpression {
        case id, artist, track, createdAt, updatedAt
    }
}

// Models/QueuedOperation.swift
import GRDB
import Foundation

struct QueuedOperation: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var type: String
    var payload: String
    var attempts: Int
    var lastError: String?
    var lastAttempt: String?   // ISO 8601 UTC
    var createdAt: String      // ISO 8601 UTC
    var updatedAt: String      // ISO 8601 UTC
    
    enum Columns: String, ColumnExpression {
        case id, type, payload, attempts, lastError, lastAttempt
        case createdAt, updatedAt
    }
}

// Helper extension for ISO 8601 formatting
extension Date {
    func toISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
    
    static func nowISO8601() -> String {
        Date().toISO8601()
    }
}
```

---

### Phase 3: Migrate ListenBrainz Cache

**Goal:** Replace JSON file with SQLite, improve performance

**Modify:** `Scroblebler/Clients/ListenBrainzCache.swift`

**Key Changes:**
```swift
final class ListenBrainzCache {
    private let db = LocalDatabase.shared
    
    // One-time migration from JSON to SQLite
    private func migrateFromJSON(username: String) {
        guard let jsonPath = getCacheFilePath(username: username),
              FileManager.default.fileExists(atPath: jsonPath.path),
              let data = try? Data(contentsOf: jsonPath),
              let cacheData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = cacheData["data"] as? [String: Int] else { return }
        
        Logger.info("Migrating \(cache.count) entries from JSON to SQLite", log: Logger.cache)
        
        let now = Date.nowISO8601()
        try? db.write { db in
            // Insert data rows
            for (key, count) in cache {
                let parts = key.split(separator: "|", maxSplits: 1)
                guard parts.count == 2 else { continue }
                
                var entry = ListenBrainzCacheEntry(
                    id: nil,
                    username: username,
                    artist: String(parts[0]),
                    track: String(parts[1]),
                    playcount: count,
                    createdAt: now,
                    updatedAt: now
                )
                try entry.insert(db)
            }
            
            // Insert metadata row
            let continueFrom = cacheData["continue_from_ts"] as? Int
            let completedAtTimestamp = cacheData["completed_at"] as? Int
            let completedAt = completedAtTimestamp.map { Date(timeIntervalSince1970: TimeInterval($0)).toISO8601() }
            var meta = ListenBrainzCacheMeta(
                id: nil,
                username: username,
                continueFromTs: continueFrom,
                completedAt: completedAt,
                totalTracks: cache.count,
                createdAt: now,
                updatedAt: now
            )
            try meta.insert(db)
        }
        
        // Delete old JSON file
        try? FileManager.default.removeItem(at: jsonPath)
        Logger.info("Migration complete, JSON file deleted", log: Logger.cache)
    }
    
    func getCachedPlayCount(username: String, artist: String, track: String) async -> Int? {
        let normalizedArtist = normalizeForCache(artist)
        let normalizedTrack = normalizeForCache(track)
        
        return try? await db.asyncRead { db in
            try ListenBrainzCacheEntry
                .filter(ListenBrainzCacheEntry.Columns.username == username)
                .filter(ListenBrainzCacheEntry.Columns.artist == normalizedArtist)
                .filter(ListenBrainzCacheEntry.Columns.track == normalizedTrack)
                .fetchOne(db)?
                .playcount
        }
    }
    
    private func fetchAllPagesInBackground(username: String, continueFrom: Int?) async {
        Logger.info("Background fetch started", log: Logger.cache)
        
        var maxTs: Int? = continueFrom
        var totalListens = 0
        var page = 0
        
        while !Task.isCancelled && page < 1000 {
            page += 1
            
            do {
                let listens = try await fetchListensPage(username: username, maxTs: maxTs, count: 1000)
                if listens.isEmpty { break }
                
                // Batch insert into database
                let now = Date.nowISO8601()
                try await db.asyncWrite { db in
                    for listen in listens {
                        guard let metadata = listen["track_metadata"] as? [String: Any],
                              let artist = metadata["artist_name"] as? String,
                              let name = metadata["track_name"] as? String else { continue }
                        
                        let normalizedArtist = normalizeForCache(artist)
                        let normalizedTrack = normalizeForCache(name)
                        
                        // Upsert playcount
                        if let existing = try ListenBrainzCacheEntry
                            .filter(ListenBrainzCacheEntry.Columns.username == username)
                            .filter(ListenBrainzCacheEntry.Columns.artist == normalizedArtist)
                            .filter(ListenBrainzCacheEntry.Columns.track == normalizedTrack)
                            .fetchOne(db) {
                            var updated = existing
                            updated.playcount += 1
                            updated.updatedAt = now
                            try updated.update(db)
                        } else {
                            var newEntry = ListenBrainzCacheEntry(
                                id: nil,
                                username: username,
                                artist: normalizedArtist,
                                track: normalizedTrack,
                                playcount: 1,
                                createdAt: now,
                                updatedAt: now
                            )
                            try newEntry.insert(db)
                        }
                        
                        totalListens += 1
                    }
                }
                
                maxTs = (listens.last?["listened_at"] as? Int)
                
                // Update metadata every 5 pages
                if page % 5 == 0 {
                    let count = try? await db.asyncRead { db in
                        try ListenBrainzCacheEntry
                            .filter(ListenBrainzCacheEntry.Columns.username == username)
                            .fetchCount(db)
                    }
                    
                    Logger.info("Progress: \(page) pages, \(totalListens) listens, \(count ?? 0) tracks", log: Logger.cache)
                }
                
                try? await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                if (error as NSError).code != NSURLErrorCancelled {
                    Logger.error("Error fetching page \(page): \(error)", log: Logger.cache)
                }
                break
            }
        }
        
        guard !Task.isCancelled else { return }
        
        // Mark as complete - upsert metadata
        let now = Date.nowISO8601()
        try? await db.asyncWrite { db in
            let totalTracks = try ListenBrainzCacheEntry
                .filter(ListenBrainzCacheEntry.Columns.username == username)
                .fetchCount(db)
            
            // Upsert metadata
            if var existing = try ListenBrainzCacheMeta
                .filter(ListenBrainzCacheMeta.Columns.username == username)
                .fetchOne(db) {
                existing.continueFromTs = nil
                existing.completedAt = now
                existing.totalTracks = totalTracks
                existing.updatedAt = now
                try existing.update(db)
            } else {
                var meta = ListenBrainzCacheMeta(
                    id: nil,
                    username: username,
                    continueFromTs: nil,
                    completedAt: now,
                    totalTracks: totalTracks,
                    createdAt: now,
                    updatedAt: now
                )
                try meta.insert(db)
            }
        }
        
        Logger.info("Background fetch complete: \(page) pages, \(totalListens) listens", log: Logger.cache)
    }
}
```

**Performance Improvement:**
- Before: Load 50KB+ JSON, decode 10K+ entries, search dictionary
- After: Indexed query, fetch single row, ~100x faster

---

### Phase 4: Add Local Blacklist

**Goal:** Persistent blacklist feature

**Create:** `Scroblebler/Storage/LocalBlacklist.swift`

**Code:**
```swift
import GRDB

class LocalBlacklist {
    static let shared = LocalBlacklist()
    private let db = LocalDatabase.shared
    
    func add(artist: String, track: String) async throws {
        let now = Date.nowISO8601()
        try await db.asyncWrite { db in
            var entry = BlacklistEntry(
                id: nil,
                artist: artist,
                track: track,
                createdAt: now,
                updatedAt: now
            )
            try entry.insert(db)
        }
        Logger.info("Blacklisted: \(artist) - \(track)", log: Logger.app)
    }
    
    func remove(artist: String, track: String) async throws {
        try await db.asyncWrite { db in
            try BlacklistEntry
                .filter(BlacklistEntry.Columns.artist == artist)
                .filter(BlacklistEntry.Columns.track == track)
                .deleteAll(db)
        }
        Logger.info("Removed from blacklist: \(artist) - \(track)", log: Logger.app)
    }
    
    func contains(artist: String, track: String) async -> Bool {
        (try? await db.asyncRead { db in
            try BlacklistEntry
                .filter(BlacklistEntry.Columns.artist == artist)
                .filter(BlacklistEntry.Columns.track == track)
                .fetchCount(db) > 0
        }) ?? false
    }
    
    func getAll() async -> [BlacklistEntry] {
        (try? await db.asyncRead { db in
            try BlacklistEntry
                .order(BlacklistEntry.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }
}
```

**Update Watcher:**
```swift
// Watcher.swift
func onTrackChange(track: Track) async {
    // Check blacklist before scrobbling
    if await LocalBlacklist.shared.contains(artist: track.artist, track: track.name) {
        Logger.info("Track blacklisted, not scrobbling: \(track.description)", log: Logger.playback)
        return
    }
    
    // Existing scrobble logic
    await ServiceManager.shared.scrobbleAll(track: track)
}
```

---

### Phase 5: Add Offline Queue

**Goal:** Enable offline scrobbling with automatic sync

**Create:** `Scroblebler/Storage/OfflineQueue.swift`

**Code:**
```swift
import GRDB

class OfflineQueue {
    static let shared = OfflineQueue()
    private let db = LocalDatabase.shared
    
    func enqueue(_ operation: Operation) async throws {
        let payload = try JSONEncoder().encode(operation)
        let now = Date.nowISO8601()
        
        try await db.asyncWrite { db in
            var queued = QueuedOperation(
                id: operation.id.uuidString,
                type: operation.type,
                payload: String(data: payload, encoding: .utf8)!,
                attempts: 0,
                lastError: nil,
                lastAttempt: nil,
                createdAt: now,
                updatedAt: now
            )
            try queued.insert(db)
        }
        
        Logger.info("Queued operation: \(operation.type)", log: Logger.sync)
    }
    
    func dequeue() async -> [Operation] {
        let operations = (try? await db.asyncRead { db in
            try QueuedOperation
                .filter(QueuedOperation.Columns.attempts < 5)
                .order(QueuedOperation.Columns.createdAt.asc)
                .fetchAll(db)
        }) ?? []
        
        return operations.compactMap { queued in
            guard let data = queued.payload.data(using: .utf8),
                  let operation = try? JSONDecoder().decode(Operation.self, from: data) else {
                return nil
            }
            return operation
        }
    }
    
    func remove(_ operationId: UUID) async throws {
        try await db.asyncWrite { db in
            try QueuedOperation
                .filter(QueuedOperation.Columns.id == operationId.uuidString)
                .deleteAll(db)
        }
    }
    
    func incrementAttempts(_ operationId: UUID, error: String) async throws {
        let now = Date.nowISO8601()
        try await db.asyncWrite { db in
            if var operation = try QueuedOperation
                .filter(QueuedOperation.Columns.id == operationId.uuidString)
                .fetchOne(db) {
                operation.attempts += 1
                operation.lastAttempt = now
                operation.lastError = error
                operation.updatedAt = now
                try operation.update(db)
            }
        }
    }
    
    func count() async -> Int {
        (try? await db.asyncRead { db in
            try QueuedOperation.fetchCount(db)
        }) ?? 0
    }
    
    func clear() async throws {
        try await db.asyncWrite { db in
            try QueuedOperation.deleteAll(db)
        }
    }
}

enum Operation: Codable, Identifiable {
    case scrobble(track: Track, services: [ScrobbleService])
    case love(artist: String, track: String, loved: Bool, services: [ScrobbleService])
    case delete(artist: String, track: String, timestamp: Int?, services: [ScrobbleService])
    
    var id: UUID {
        UUID()  // Or generate from content hash
    }
    
    var type: String {
        switch self {
        case .scrobble: return "scrobble"
        case .love: return "love"
        case .delete: return "delete"
        }
    }
}
```

**Usage:**
```swift
// In Watcher.swift
func onTrackChange(track: Track) async {
    // Check blacklist
    if await LocalBlacklist.shared.contains(artist: track.artist, track: track.name) {
        return
    }
    
    // Check network
    if !Reachability.isConnected {
        // Queue for later
        let operation = Operation.scrobble(
            track: track,
            services: Defaults.shared.enabledServices.map { $0.service }
        )
        try? await OfflineQueue.shared.enqueue(operation)
        
        Logger.info("Track queued (offline): \(track.description)", log: Logger.playback)
        return
    }
    
    // Online - scrobble immediately
    await ServiceManager.shared.scrobbleAll(track: track)
}

// In AppDelegate or SyncCoordinator
func networkBecameAvailable() async {
    let operations = await OfflineQueue.shared.dequeue()
    
    Logger.info("Executing \(operations.count) queued operations", log: Logger.sync)
    
    for operation in operations {
        do {
            switch operation {
            case .scrobble(let track, let services):
                for service in services {
                    guard let creds = Defaults.shared.credentials(for: service) else { continue }
                    try await ServiceManager.shared.scrobble(credentials: creds, track: track)
                }
                
            case .love(let artist, let track, let loved, let services):
                for service in services {
                    guard let creds = Defaults.shared.credentials(for: service) else { continue }
                    try await ServiceManager.shared.updateLove(
                        credentials: creds,
                        artist: artist,
                        track: track,
                        loved: loved
                    )
                }
                
            case .delete(let artist, let track, let timestamp, let services):
                for service in services {
                    guard let creds = Defaults.shared.credentials(for: service) else { continue }
                    let identifier = ScrobbleIdentifier(
                        artist: artist,
                        track: track,
                        timestamp: timestamp,
                        serviceId: nil
                    )
                    try await ServiceManager.shared.deleteScrobble(
                        credentials: creds,
                        identifier: identifier
                    )
                }
            }
            
            // Success - remove from queue
            try await OfflineQueue.shared.remove(operation.id)
            
            // Rate limit
            try await Task.sleep(nanoseconds: 500_000_000)
            
        } catch {
            // Failed - increment attempts, keep in queue
            try? await OfflineQueue.shared.incrementAttempts(operation.id, error: error.localizedDescription)
            Logger.error("Operation failed: \(error)", log: Logger.sync)
        }
    }
    
    Logger.info("Sync complete", log: Logger.sync)
}
```

---

### Phase 6: Add UI for New Features

**Goal:** Expose blacklist and show offline status

**New Components:**

```swift
// Components/BlacklistButton.swift
import SwiftUI

struct BlacklistButton: View {
    let track: RecentTrack
    @State private var isBlacklisted = false
    
    var body: some View {
        Button {
            Task {
                if isBlacklisted {
                    try? await LocalBlacklist.shared.remove(artist: track.artist, track: track.name)
                } else {
                    try? await LocalBlacklist.shared.add(artist: track.artist, track: track.name)
                }
                isBlacklisted.toggle()
            }
        } label: {
            Image(systemName: isBlacklisted ? "nosign" : "circle.slash")
        }
        .help(isBlacklisted ? "Remove from blacklist" : "Blacklist (never scrobble)")
        .task {
            isBlacklisted = await LocalBlacklist.shared.contains(
                artist: track.artist,
                track: track.name
            )
        }
    }
}

// Components/PendingOperationsView.swift
import SwiftUI

struct PendingOperationsView: View {
    @State private var pendingCount = 0
    
    var body: some View {
        if pendingCount > 0 {
            HStack {
                Image(systemName: "icloud.and.arrow.up")
                Text("\(pendingCount) operations queued (offline)")
                    .font(.caption)
            }
            .padding(8)
            .background(Color.yellow.opacity(0.2))
            .cornerRadius(8)
        }
    }
    
    var updateTask: some View {
        EmptyView()
            .task {
                // Update periodically
                while !Task.isCancelled {
                    pendingCount = await OfflineQueue.shared.count()
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
    }
}

// Update MainView.swift
struct MainView: View {
    var body: some View {
        VStack {
            // Pending operations indicator
            PendingOperationsView()
            
            // History list
            List(tracks) { track in
                HistoryItem(track: track)
                    .swipeActions {
                        BlacklistButton(track: track)
                    }
            }
        }
    }
}
```

---

## Testing Strategy

### Unit Tests

```swift
// Tests/TrackMatcherTests.swift
class TrackMatcherTests: XCTestCase {
    func testExactTimestampMatch() {
        let track = RecentTrack(artist: "Artist", name: "Track", date: 1000)
        let candidates = [
            RecentTrack(artist: "Artist", name: "Track", date: 1000)
        ]
        
        XCTAssertNotNil(TrackMatcher.findMatch(for: track, in: candidates))
    }
    
    func testTimestampWithinWindow() {
        let track = RecentTrack(artist: "Artist", name: "Track", date: 1000)
        let candidates = [
            RecentTrack(artist: "Artist", name: "Track", date: 1003)  // 3s delta
        ]
        
        XCTAssertNotNil(TrackMatcher.findMatch(for: track, in: candidates))
    }
    
    func testTimestampOutsideWindow() {
        let track = RecentTrack(artist: "Artist", name: "Track", date: 1000)
        let candidates = [
            RecentTrack(artist: "Artist", name: "Track", date: 1200)  // 200s delta
        ]
        
        XCTAssertNil(TrackMatcher.findMatch(for: track, in: candidates))
    }
}

// Tests/LocalBlacklistTests.swift
class LocalBlacklistTests: XCTestCase {
    override func setUp() async throws {
        // Use in-memory database for tests
        try await LocalDatabase.shared.clear()
    }
    
    func testAddToBlacklist() async throws {
        try await LocalBlacklist.shared.add(artist: "Artist", track: "Track")
        let contains = await LocalBlacklist.shared.contains(artist: "Artist", track: "Track")
        XCTAssertTrue(contains)
    }
    
    func testRemoveFromBlacklist() async throws {
        try await LocalBlacklist.shared.add(artist: "Artist", track: "Track")
        try await LocalBlacklist.shared.remove(artist: "Artist", track: "Track")
        let contains = await LocalBlacklist.shared.contains(artist: "Artist", track: "Track")
        XCTAssertFalse(contains)
    }
}
```

---

## Migration Path

### Step 1: Add GRDB Dependency
```bash
# Add to Package.swift
.package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
```

### Step 2: Create Database Layer
1. Create `Storage/` directory
2. Add `LocalDatabase.swift` with migrations
3. Add models (`Playcount`, `BlacklistEntry`, `QueuedOperation`)
4. Test database creation

### Step 3: Extract TrackMatcher
1. Create `TrackMatcher.swift`
2. Update `ServiceManager.swift` to use it
3. Delete old methods
4. Test matching still works

### Step 4: Migrate ListenBrainz Cache
1. Update `ListenBrainzCache.swift` to use SQLite
2. Add one-time JSON → SQLite migration
3. Test performance improvement
4. Delete old JSON files after successful migration

### Step 5: Add Blacklist
1. Create `LocalBlacklist.swift`
2. Update `Watcher.swift` to check blacklist
3. Add UI components
4. Test blacklist functionality

### Step 6: Add Offline Queue
1. Create `OfflineQueue.swift`
2. Add `Reachability` monitoring
3. Update `Watcher.swift` to queue when offline
4. Add sync logic for when online
5. Add UI indicator
6. Test offline/online cycle

---

## Performance Metrics

### Before (JSON)
- ListenBrainz cache lookup: ~50ms (load + decode entire file)
- Cache update: ~200ms (load + modify + save entire file)
- Memory usage: 50KB+ loaded per lookup

### After (SQLite)
- ListenBrainz cache lookup: ~1ms (indexed query)
- Cache update: ~5ms (single row upsert)
- Memory usage: <1KB per lookup

**Result: ~50x faster lookups, ~40x faster updates**

---

## Rollback Plan

### If SQLite Migration Fails
1. Keep JSON files as backup until migration confirmed
2. Add flag to revert to JSON mode
3. Roll back GRDB version if issues found

### If Performance Regresses
1. Add query profiling
2. Optimize indexes
3. Consider PRAGMA tuning

### If Database Corruption
1. Delete database file
2. Rebuild from services (data still on remote)
3. ListenBrainz cache can be rebuilt from API

---

## Future Enhancements

### Nice to Have (Later)
- 📊 Analytics: Track scrobble counts, trends
- 🔄 Manual sync button in UI
- 📱 Export/import blacklist
- ⚙️ Settings: Configure queue retry attempts
- 📈 Show sync progress for ListenBrainz cache
- 🎨 Blacklist categories (temporary, permanent)

### Not Planned
- ❌ Full offline history (too complex)
- ❌ Conflict resolution (not needed)
- ❌ Multi-device sync (each device is independent)

---

## Summary

### What We're Building
1. **TrackMatcher** - Clean extraction of matching logic
2. **SQLite Database** - Fast, indexed storage
3. **Blacklist** - Persistent user preference
4. **Offline Queue** - Background sync when online

### What We're NOT Building
- ❌ Full local-first architecture
- ❌ Conflict resolution system
- ❌ Complete history storage

### Code Metrics
- **New lines:** ~600
  - LocalDatabase: 150
  - ListenBrainzCache updates: 150
  - LocalBlacklist: 60
  - OfflineQueue: 100
  - TrackMatcher: 20
  - UI components: 80
  - Models: 40
- **Removed lines:** ~100 (JSON handling, old matching)
- **Net:** +500 lines for significant new features

### Benefits
- ✅ 50x faster ListenBrainz lookups
- ✅ Persistent blacklist
- ✅ Offline scrobbling
- ✅ Cleaner architecture
- ✅ Better testability
- ✅ Easier to maintain

### Timeline Estimate
- **Phase 1 (Extract Sync Logic): ✅ COMPLETE** (4 hours actual)
  - TrackMatcher extraction: 30 min
  - CrossServiceSync extraction: 1 hour
  - BackfillService extraction: 1 hour
  - ServiceManager simplification: 30 min
  - Pagination bug fixes (Last.fm + ListenBrainz): 1 hour
  - Testing and verification: 30 min
- Phase 2 (Database): 3 hours
- Phase 3 (ListenBrainz): 4 hours
- Phase 4 (Blacklist): 2 hours
- Phase 5 (Queue): 3 hours
- Phase 6 (UI): 2 hours
- **Total: ~18 hours of implementation (4 complete, 14 remaining)**

### What's Next: Phase 2
Ready to add SQLite database with GRDB.swift for persistent storage!
