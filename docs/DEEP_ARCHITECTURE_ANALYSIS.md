# Scroblebler - Deep Architecture Analysis

## Executive Summary

Scroblebler is a macOS menu bar application that monitors music playback and scrobbles tracks to multiple services (Last.fm, Libre.fm, ListenBrainz). The architecture follows a **unidirectional data flow** pattern with a **single source of truth** for track data, combined with **reactive state management** using Combine and SwiftUI.

---

## Core Architecture Patterns

### 1. Single Source of Truth: TrackRepository
- **Pattern**: Repository Pattern + Observable State
- **Location**: [`Scroblebler/Services/TrackRepository.swift`](Scroblebler/Services/TrackRepository.swift:1)
- **Responsibility**: Central state container for all track data

```swift
@MainActor
class TrackRepository: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    var nowPlaying: Track? { tracks.first { !$0.scrobbled } }
}
```

### 2. State Management Hierarchy

```
┌─────────────────────────────────────────────────────────────┐
│                     AppDelegate                              │
│  - App lifecycle                                             │
│  - Popover management                                        │
│  - Status bar item                                           │
└────────────────────┬────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────────┐
│                  ContentView                                 │
│  - Root SwiftUI view                                         │
│  - Wire up dependencies as @EnvironmentObject                │
│  - Setup Watcher callbacks                                   │
└─────────────┬──────────────┬───────────────┬────────────────┘
              │              │               │
     ┌────────▼──────┐  ┌───▼──────────┐  ┌─▼──────────────┐
     │    Watcher     │  │ServiceManager│  │  Defaults      │
     │  (Playback)    │  │  (Services)  │  │ (Preferences)  │
     └────────┬───────┘  └───┬──────────┘  └─┬──────────────┘
              │              │               │
              └──────────────┴───────────────┘
                             │
                    ┌────────▼───────────┐
                    │  TrackRepository   │
                    │ (Single Source of  │
                    │      Truth)        │
                    └────────────────────┘
```

---

## Data Models

### 1. Track Model (Unified)

**Location**: [`Scroblebler/Models/Track.swift`](Scroblebler/Models/Track.swift:4)

The `Track` struct is the **central data structure** used across all contexts:

```swift
struct Track: Identifiable, Codable, Equatable {
    // MARK: - Identity
    let id: UUID
    var canonicalKey: String { TrackIdentity.key(artist: artist, track: name) }
    
    // MARK: - Immutable Metadata
    let artist: String
    let album: String
    let name: String
    let timestamp: Int
    let duration: Double
    let sourceService: ScrobbleService
    
    // MARK: - Mutable State
    var loved: Bool = false
    var playcount: Int = 1
    var scrobbled: Bool = false
    var blacklisted: Bool = false
    
    // MARK: - Service Sync
    var serviceInfo: [ScrobbleService: ServiceTrackData] = [:]
    var syncedServices: Set<ScrobbleService> { ... }
    
    // MARK: - UI Metadata
    let artwork: Data?
    var artistURL: URL?
    var albumURL: URL?
    var trackURL: URL?
    let imageUrl: String?
}
```

**Key Design Decisions**:
- **Unified model**: Single struct for now playing, history, and queued tracks
- **Immutable core**: Artist, name, album, timestamp never change after creation
- **Mutable state**: UI-driven properties (loved, playcount, blacklisted) can be updated
- **Service tracking**: `serviceInfo` maps each service to its specific identifiers (timestamp for Last.fm, recording_msid for ListenBrainz)
- **Sync status**: Computed from `serviceInfo` vs `enabledServices`

### 2. ServiceTrackData

**Location**: [`Scroblebler/Models.swift`](Scroblebler/Models.swift:28)

```swift
struct ServiceTrackData: Codable {
    let timestamp: Int?  // Required for Last.fm/Libre.fm
    let id: String?      // Required for ListenBrainz (recording_msid)
    
    static func lastfm(timestamp: Int) -> ServiceTrackData
    static func listenbrainz(recordingMsid: String, timestamp: Int) -> ServiceTrackData
}
```

**Purpose**: Service-specific identifiers needed for operations like deletion and updates.

### 3. SyncStatus

**Location**: [`Scroblebler/Models.swift`](Scroblebler/Models.swift:5)

```swift
enum SyncStatus: Codable {
    case unknown
    case synced    // Present in all enabled services
    case partial   // Not in all enabled services
    
    static func calculate(
        presentInServices: Set<ScrobbleService>,
        enabledServices: Set<ScrobbleService>
    ) -> SyncStatus
}
```

**Logic**: A track is "synced" if `presentInServices == enabledServices`

### 4. ServiceCredentials

**Location**: [`Scroblebler/Models.swift`](Scroblebler/Models.swift:94)

```swift
struct ServiceCredentials: Codable {
    let service: ScrobbleService
    var token: String
    var username: String
    var profileUrl: String?
    var isSubscriber: Bool
    var isEnabled: Bool  // Toggle for scrobbling
}
```

---

## State Management

### 1. TrackRepository (@MainActor)

**Responsibilities**:
- Maintain `tracks: [Track]` array (most recent first)
- Provide `nowPlaying: Track?` computed property
- CRUD operations on tracks
- Coordinate with ServiceManager for network ops
- Auto-prune (keep last 200 tracks)

**Key Methods**:

```swift
// Add new track from media player
func add(_ track: Track)

// Update track by ID or artist/track name
func update(id: UUID, mutation: (inout Track) -> Void)
func update(artist: String, track: String, mutation: (inout Track) -> Void)

// Service operations (with offline queue support)
func loadRecent(from service: ServiceCredentials, limit: Int, page: Int) async throws
func scrobble(_ track: Track) async
func toggleLove(artist: String, track: String) async -> Bool
func delete(_ track: Track) async
func toggleBlacklist(artist: String, track: String) async -> Bool
```

**State Updates**: All mutations trigger Combine's `objectWillChange.send()`, causing SwiftUI views to re-render.

### 2. Watcher (Media Playback)

**Location**: [`Scroblebler/Watcher.swift`](Scroblebler/Watcher.swift:26)

**Responsibilities**:
- Monitor media playback via MediaRemoteAdapter
- Track playback position and state
- Detect track changes
- Trigger scrobble when conditions met (95% played, >= 30s duration)

**Published State**:
```swift
@Published var currentTrackID: String?
@Published var currentTrack: Track?
@Published var currentPosition: Double?
@Published var maxPosition: Double?
@Published var musicRunning: Bool
@Published var playerState: PlayerState
```

**Callbacks**:
```swift
var onTrackChanged: ((Track) -> Void)?
var onScrobbleWanted: ((Track) -> Void)?
```

**Flow**:
1. MediaRemoteAdapter receives playback events
2. `handleTrackInfo()` processes raw data on background queue
3. `processStatus()` runs on `@MainActor`
4. Triggers callbacks to ContentView

### 3. ServiceManager (Singleton)

**Location**: [`Scroblebler/ServiceManager.swift`](Scroblebler/ServiceManager.swift:10)

**Responsibilities**:
- Manage ScrobbleClient instances
- Coordinate multi-service operations
- Handle authentication flows
- Offline queue integration
- Cross-service sync orchestration

**Published State**:
```swift
@Published var lastBackfilledTrack: BackfillEvent?
@Published var scrobbleCompletedTrigger = 0  // Increment to trigger refresh
```

**Key Services**:
```swift
private let clients: [ScrobbleService: ScrobbleClient]
private let crossServiceSync: CrossServiceSync
private let backfillService: BackfillService
```

**Network-Aware Execution**:
```swift
private func executeOrQueue(
    operation: Operation,
    operationName: String,
    onlineExecution: () async -> Void
) async {
    if !Reachability.shared.isConnected {
        try await OfflineQueue.shared.enqueue(operation)
    } else {
        await onlineExecution()
    }
}
```

### 4. Defaults (Singleton)

**Location**: [`Scroblebler/Defaults.swift`](Scroblebler/Defaults.swift:4)

**Responsibilities**:
- Persist user preferences via UserDefaults
- Manage service credentials
- Track primary service selection
- Legacy migration

**Published State**:
```swift
@Published var serviceCredentials: [ServiceCredentials]
@Published var mainServicePreference: ScrobbleService?
@Published var picture: Data?
```

**Computed Properties**:
```swift
var enabledServices: [ServiceCredentials]  // Filter isEnabled == true
var primaryService: ServiceCredentials?    // mainServicePreference or first enabled
```

---

## Data Flows

### Flow 1: Track Playback → Scrobble

```
┌──────────────────┐
│ Media Player     │ (Music.app, Spotify, etc.)
└────────┬─────────┘
         │ System-level playback events
         │
┌────────▼────────────────────────────────────────────────┐
│ MediaRemoteAdapter (C++ bridge)                         │
│ - Captures playback info via private APIs               │
│ - Converts NSImage artwork to base64                    │
└────────┬────────────────────────────────────────────────┘
         │ JSON + callbacks
         │
┌────────▼─────────┐
│ Watcher          │
│ - Detects track changes                                 │
│ - Tracks position with interpolation                    │
│ - Decides when to scrobble (95% played, >=30s)          │
└────┬─────────┬───┘
     │         │
     │ Track   │ Scrobble
     │ Changed │ Wanted
     │         │
┌────▼─────────▼───────────────────────────────────────────┐
│ ContentView callbacks                                    │
│ onTrackChanged: { track in                              │
│   let enriched = await serviceManager.updateNowPlayingAll│
│   trackRepo.add(enriched)                                │
│ }                                                         │
│ onScrobbleWanted: { track in                             │
│   await serviceManager.scrobbleAll(track)                │
│ }                                                         │
└────────┬─────────────────────────────────────────────────┘
         │
┌────────▼─────────┐
│ ServiceManager   │
│ - Check blacklist                                        │
│ - Check network (Reachability)                           │
│ - Execute or queue operation                             │
└────────┬─────────┘
         │
    ┌────▼────┐
    │ Online? │
    └─┬────┬──┘
      │    │
  Yes │    │ No
      │    │
      │    └──────► OfflineQueue.enqueue(operation)
      │             Store in SQLite for later
      │
┌─────▼────────────────────────────────────────────────┐
│ ScrobbleClient implementations (parallel)            │
│ - LastFmClient.scrobble()                            │
│ - LibreFmClient.scrobble()                           │
│ - ListenBrainzClient.scrobble()                      │
└──────────────────────────────────────────────────────┘
```

### Flow 2: Load Recent Tracks (with Cross-Service Sync)

```
┌──────────────────┐
│ UI: MainView     │
│ .onAppear()      │
│ .onChange(of:    │
│   primaryService)│
└────────┬─────────┘
         │
┌────────▼──────────────────────────────────────────┐
│ TrackRepository.loadRecent(from: primary)        │
└────────┬──────────────────────────────────────────┘
         │
┌────────▼────────────────────────────────────────────┐
│ ServiceManager.getAllRecentTracks(limit, page)     │
│ 1. Fetch from primary service                       │
│ 2. Enrich with other enabled services               │
└────────┬────────────────────────────────────────────┘
         │
    ┌────▼─────────────────────────────────────────┐
    │ Primary Service Client                       │
    │ e.g., LastFmClient.getRecentTracks()         │
    └────┬─────────────────────────────────────────┘
         │
         │ Returns [Track] with sourceService set
         │
    ┌────▼──────────────────────────────────────────┐
    │ CrossServiceSync.reconcile()                  │
    │ 1. Calculate time range from primary tracks   │
    │ 2. Fetch from secondary services in parallel  │
    │ 3. Match tracks using TrackMatcher            │
    │ 4. Merge serviceInfo into primary tracks      │
    │ 5. Collect tracks needing backfill            │
    └────┬──────────────────────────────────────────┘
         │
         │ Returns backfillTasks: [(Track, ServiceCredentials)]
         │
    ┌────▼──────────────────────────────────────────┐
    │ BackfillService.execute(tasks)                │
    │ - Check blacklist before each backfill        │
    │ - Scrobble missing tracks (async)             │
    │ - Rate limit (500ms between scrobbles)        │
    │ - Respect service age limits:                 │
    │   • Last.fm/Libre.fm: < 14 days               │
    │   • ListenBrainz: no limit                    │
    └────┬──────────────────────────────────────────┘
         │
         │ Returns [BackfillEvent]
         │
    ┌────▼──────────────────────────────────────────┐
    │ ServiceManager publishes lastBackfilledTrack  │
    └────┬──────────────────────────────────────────┘
         │
    ┌────▼──────────────────────────────────────────┐
    │ MainView.onChange(of: lastBackfilledTrack)    │
    │ Updates track.serviceInfo in repository       │
    └───────────────────────────────────────────────┘
```

### Flow 3: Offline Queue Processing

```
┌─────────────────────────────┐
│ Reachability.shared         │
│ - NWPathMonitor             │
│ - Detects network changes   │
└────────┬────────────────────┘
         │
         │ Network becomes available
         │
    ┌────▼─────────────────────────────────┐
    │ onNetworkAvailable()                 │
    │ → processOfflineQueue()              │
    └────┬─────────────────────────────────┘
         │
    ┌────▼─────────────────────────────────┐
    │ OfflineQueue.dequeue()               │
    │ - Fetch operations with attempts < 5 │
    │ - Decode from JSON                   │
    └────┬─────────────────────────────────┘
         │
         │ Returns [Operation]
         │
    ┌────▼─────────────────────────────────────┐
    │ For each operation:                      │
    │   try executeOperation()                 │
    │     Success → remove from queue          │
    │     Failure → incrementAttempts()        │
    │              (max 5 attempts)            │
    └──────────────────────────────────────────┘

Operations:
  • .scrobble(track, services)
  • .love(artist, track, loved, services)
  • .delete(artist, track, timestamp, services)
```

### Flow 4: Love Toggle

```
┌──────────────────┐
│ UI: LoveButton   │ User clicks ❤️
└────────┬─────────┘
         │
┌────────▼────────────────────────────────────────┐
│ TrackRepository.toggleLove(artist, track)      │
│ 1. Find track by canonicalKey                  │
│ 2. Toggle loved state (optimistic update)      │
│ 3. Check network                                │
└────────┬────────────────────────────────────────┘
         │
    ┌────▼────┐
    │ Online? │
    └─┬────┬──┘
      │    │
  Yes │    │ No
      │    │
      │    └──────► OfflineQueue.enqueue(.love(...))
      │
┌─────▼──────────────────────────────────────────┐
│ ServiceManager.updateLoveAll()                 │
│ - Parallel execution to all enabled services   │
└─────┬──────────────────────────────────────────┘
      │
┌─────▼──────────────────────────────────────────┐
│ ScrobbleClient.updateLove() for each service   │
│ - LastFm: track.love / track.unlove API        │
│ - ListenBrainz: feedback API                   │
│ - LibreFm: track.love / track.unlove API       │
└─────────────────────────────────────────────────┘
```

### Flow 5: Delete Scrobble (Undo)

```
┌──────────────────┐
│ UI: UndoButton   │ User clicks undo
└────────┬─────────┘
         │
┌────────▼────────────────────────────────────────┐
│ TrackRepository.delete(track)                  │
│ 1. Convert serviceInfo to [String: ...]        │
│ 2. Check network                                │
└────────┬────────────────────────────────────────┘
         │
    ┌────▼────┐
    │ Online? │
    └─┬────┬──┘
      │    │
  Yes │    │ No
      │    │
      │    └──────► OfflineQueue.enqueue(.delete(...))
      │
┌─────▼──────────────────────────────────────────────┐
│ ServiceManager.deleteScrobbleAll()                 │
│ - Extract serviceInfo for each enabled service     │
│ - Create ScrobbleIdentifier with:                  │
│   • artist, track                                  │
│   • timestamp (Last.fm/Libre.fm)                   │
│   • recording_msid (ListenBrainz)                  │
└─────┬──────────────────────────────────────────────┘
      │
┌─────▼──────────────────────────────────────────────┐
│ ScrobbleClient.deleteScrobble() for each service   │
│ - LastFm: Uses web scraping (requires password)    │
│ - ListenBrainz: DELETE /1/delete-listen API        │
│ - LibreFm: Not implemented                         │
└─────┬──────────────────────────────────────────────┘
      │
┌─────▼────────────────────────────────────────┐
│ TrackRepository updates local state:         │
│   track.playcount = max(0, playcount - 1)    │
└───────────────────────────────────────────────┘
```

---

## Storage Architecture

### 1. Persistent Storage (GRDB/SQLite)

**Location**: [`Scroblebler/Storage/LocalDatabase.swift`](Scroblebler/Storage/LocalDatabase.swift:4)

**Tables**:

#### `operations` (v3_operations migration)
```sql
CREATE TABLE operations (
    id TEXT PRIMARY KEY,           -- UUID
    type TEXT NOT NULL,            -- "scrobble", "love", "delete"
    payload TEXT NOT NULL,         -- JSON-encoded Operation
    attempts INTEGER DEFAULT 0,
    last_error TEXT,
    last_attempt TEXT,             -- ISO 8601
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX idx_operations_pending ON operations(attempts, created_at)
WHERE attempts < 5;
```

**Purpose**: Offline operation queue

#### `blacklist` (v2_blacklist migration)
```sql
CREATE TABLE blacklist (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    artist TEXT NOT NULL,          -- Normalized (lowercase)
    track TEXT NOT NULL,           -- Normalized (lowercase)
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_blacklist_unique ON blacklist(artist, track);
```

**Purpose**: Persistent blacklist for tracks that should never scrobble

#### `listenbrainz_cache` (v1_listenbrainz_cache migration)
```sql
CREATE TABLE listenbrainz_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    artist TEXT NOT NULL,
    track TEXT NOT NULL,
    playcount INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_lbc_unique ON listenbrainz_cache(username, artist, track);
```

**Purpose**: Cache playcount data from ListenBrainz (they don't provide it in recent tracks API)

#### `listenbrainz_cache_meta` (v1_listenbrainz_cache migration)
```sql
CREATE TABLE listenbrainz_cache_meta (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    continue_from_ts INTEGER,      -- Resume point for pagination
    completed_at TEXT,
    total_tracks INTEGER,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

**Purpose**: Track cache rebuild progress

### 2. UserDefaults

**Location**: [`Scroblebler/Defaults.swift`](Scroblebler/Defaults.swift:7)

**Keys**:
- `firstRun`: Bool (launch at startup prompt)
- `serviceCredentials`: Data (JSON-encoded [ServiceCredentials])
- `mainServicePreference`: String (ScrobbleService.rawValue)
- `picture`: Data (profile picture)
- `blacklistMigratedToSQLite`: Bool (migration flag)

### 3. Keychain

**Location**: [`Scroblebler/KeychainHelper.swift`](Scroblebler/KeychainHelper.swift)

**Purpose**: Store Last.fm password for web client (enables undo functionality)

**Keys**: `com.scroblebler.password.<username>`

### 4. In-Memory Caching

#### ImageCache
**Location**: [`Scroblebler/ImageCache.swift`](Scroblebler/ImageCache.swift)

```swift
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, NSData>()
    
    func get(_ url: String) -> Data?
    func set(_ url: String, data: Data)
}
```

**Purpose**: Cache album artwork images to avoid repeated network requests

---

## Critical Design Decisions

### 1. Why Single Track Model?

**Previous**: Separate `NowPlayingTrack` and `HistoryTrack` models  
**Current**: Unified `Track` model

**Benefits**:
- Simplified data flow
- Easy transition from now playing → history (just set `scrobbled = true`)
- Consistent love/blacklist operations across contexts
- Reduced code duplication

**Trade-off**: Some fields unused in certain contexts (e.g., `artwork` not needed for history)

### 2. Why @MainActor for TrackRepository?

**Reason**: All track state updates must happen on main thread to ensure:
- SwiftUI view updates are synchronous
- No race conditions on `tracks` array
- Smooth UI animations

**Pattern**:
```swift
@MainActor
class TrackRepository: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    // All mutations happen on MainActor
}
```

### 3. Why Service-Specific Identifiers?

**Problem**: Different services use different identifiers for deletion:
- Last.fm: artist + track + timestamp
- ListenBrainz: recording_msid
- Libre.fm: artist + track + timestamp

**Solution**: `ServiceTrackData` struct with optional fields:
```swift
struct ServiceTrackData {
    let timestamp: Int?  // For timestamp-based services
    let id: String?      // For ID-based services
}
```

### 4. Why Offline Queue?

**Problem**: Network failures should not lose scrobble data

**Solution**: Persistent queue in SQLite with:
- Retry logic (max 5 attempts)
- Automatic processing when network returns
- Support for all operations (scrobble, love, delete)

### 5. Why Cross-Service Sync?

**Problem**: User may add services later and want historical data backfilled

**Solution**: When loading recent tracks:
1. Fetch from primary service (source of truth)
2. Query secondary services in parallel
3. Match tracks using fuzzy string matching
4. Backfill missing tracks (respecting age limits)
5. Merge service identifiers for undo functionality

---

## Concurrency Model

### Threading Strategy

1. **Main Thread (@MainActor)**:
   - All UI updates
   - TrackRepository mutations
   - Published property changes

2. **Background Queues**:
   - Network requests (async/await)
   - Media playback processing (`processingQueue`)
   - Database operations (GRDB handles internally)

3. **Coordination**:
   - Use `async/await` for asynchronous operations
   - `@MainActor` ensures UI code runs on main thread
   - `Task { @MainActor in ... }` for cross-context updates

### Example: Watcher Processing

```swift
// Background thread (serial queue)
private let processingQueue = DispatchQueue(
    label: "com.scroblebler.watcher.processing",
    qos: .userInitiated
)

mediaController.onTrackInfoReceived = { [weak self] trackInfo in
    // Background processing
    self?.processingQueue.async {
        self?.handleTrackInfo(trackInfo)
    }
}

// Switch to MainActor for state updates
@MainActor
private func processStatus(_ status: MediaControlStatus) throws {
    currentTrack = track  // Published property
}
```

---

## Network Architecture

### Request Flow

```
┌──────────────────────────────────────────────────────┐
│ ScrobbleClient protocol                              │
│ - authenticate(), scrobble(), updateLove(), etc.     │
└────────┬─────────────────────────────────────────────┘
         │
    ┌────▼────────────────────────────────────────┐
    │ Concrete implementations:                   │
    │ - LastFmClient                              │
    │ - LibreFmClient                             │
    │ - ListenBrainzClient                        │
    └────────┬────────────────────────────────────┘
             │
        ┌────▼────────────────────────────┐
        │ NetworkClient (URLSession)      │
        │ - Shared instance               │
        │ - Common error handling         │
        └─────────────────────────────────┘
```

### Rate Limiting

**ListenBrainz**: Custom rate limiter
**Location**: [`Scroblebler/Utilities/ListenBrainzRateLimiter.swift`](Scroblebler/Utilities/ListenBrainzRateLimiter.swift)

- Sliding window algorithm
- 5 requests per second limit
- Per-token buckets
- Async/await integration

**Others**: Simple delays between operations (500ms)

---

## Testing Considerations

### Current State
- No unit tests found in project
- Manual testing via UI

### Recommended Test Structure

```
Tests/
├── Models/
│   └── TrackTests.swift
│       - Test canonical key generation
│       - Test sync status calculation
│       - Test factory methods
├── Services/
│   ├── TrackRepositoryTests.swift
│   │   - Test CRUD operations
│   │   - Test optimistic updates
│   │   - Mock ServiceManager
│   ├── ServiceManagerTests.swift
│   │   - Test multi-service coordination
│   │   - Mock network clients
│   └── CrossServiceSyncTests.swift
│       - Test track matching
│       - Test backfill logic
├── Storage/
│   ├── OfflineQueueTests.swift
│   │   - Test enqueue/dequeue
│   │   - Test retry logic
│   └── LocalBlacklistTests.swift
│       - Test case-insensitive matching
└── Utilities/
    └── TrackMatcherTests.swift
        - Test fuzzy string matching
```

---

## Performance Considerations

### 1. Track Repository Size Limit
- Auto-prune to 200 tracks to prevent memory bloat
- Location: [`TrackRepository.add()`](Scroblebler/Services/TrackRepository.swift:39)

### 2. Image Preloading
- Asynchronous background loading
- NSCache for automatic memory management
- Location: [`MainView.preloadImages()`](Scroblebler/Views/MainView.swift:307)

### 3. Database Indexing
- Unique indexes on blacklist (artist, track)
- Composite index on operations (attempts, created_at)
- Username indexes on cache tables

### 4. Debouncing
- Position updates throttled to 500ms
- 1-second cooldown after seeks

---

## Security Considerations

### 1. Credentials Storage
- **API tokens**: UserDefaults (JSON-encoded)
- **Passwords**: Keychain (encrypted by OS)
- **Session keys**: In-memory only after restore

### 2. Network Security
- All API calls use HTTPS
- No credential logging
- Tokens never exposed in logs

### 3. Web Scraping (Last.fm Delete)
- Password required for web client
- Stored in Keychain, not UserDefaults
- Optional feature (user must explicitly enable)

---

## Error Handling Strategy

### 1. Network Errors
- Automatic offline queue on failure
- User-visible error messages only for auth failures
- Silent retry for transient errors

### 2. Database Errors
- Try/catch with optional fallbacks
- Logger.error() for debugging
- Graceful degradation (e.g., blacklist check returns false on error)

### 3. Media Playback Errors
- Auto-restart listener if terminated
- Invalid track data silently skipped
- Missing duration preserved from previous updates

---

## Future Architecture Improvements

### 1. Explicit State Machine for Track Lifecycle
```swift
enum TrackState {
    case nowPlaying
    case scrobbling
    case scrobbled
    case failed(Error)
}
```

### 2. Dependency Injection
- Replace singletons with injectable instances
- Enable proper unit testing
- Better separation of concerns

### 3. Repository Pattern for All Services
```swift
protocol ServiceRepository {
    func loadRecent() async throws -> [Track]
    func scrobble(_ track: Track) async throws
}
```

### 4. Event Sourcing for Sync State
- Store all sync events (backfills, deletions)
- Rebuild state from event log
- Better debugging and audit trail

### 5. Core Data Migration
- Replace GRDB with Core Data
- Better SwiftUI integration
- CloudKit sync support

---

## Glossary

- **Scrobble**: Submit a track play to a service
- **Now Playing**: Update current track without incrementing playcount
- **Backfill**: Retroactively scrobble old tracks to a new service
- **Canonical Key**: Normalized `artist|track` identifier for matching
- **Service Info**: Per-service metadata (timestamp, recording_msid) for operations
- **Sync Status**: Whether track exists in all enabled services
- **Offline Queue**: Persistent storage for operations when network unavailable
- **Cross-Service Sync**: Matching and merging tracks across multiple services

---

## Key Files Reference

### Core
- [`Scroblebler/AppDelegate.swift`](Scroblebler/AppDelegate.swift:1) - App lifecycle
- [`Scroblebler/Views/ContentView.swift`](Scroblebler/Views/ContentView.swift:1) - Root view, dependency wiring
- [`Scroblebler/Views/MainView.swift`](Scroblebler/Views/MainView.swift:1) - Main UI

### State Management
- [`Scroblebler/Services/TrackRepository.swift`](Scroblebler/Services/TrackRepository.swift:1) - Single source of truth
- [`Scroblebler/ServiceManager.swift`](Scroblebler/ServiceManager.swift:1) - Service coordination
- [`Scroblebler/Watcher.swift`](Scroblebler/Watcher.swift:1) - Media playback monitoring
- [`Scroblebler/Defaults.swift`](Scroblebler/Defaults.swift:1) - User preferences

### Models
- [`Scroblebler/Models/Track.swift`](Scroblebler/Models/Track.swift:1) - Unified track model
- [`Scroblebler/Models.swift`](Scroblebler/Models.swift:1) - Supporting models

### Storage
- [`Scroblebler/Storage/LocalDatabase.swift`](Scroblebler/Storage/LocalDatabase.swift:1) - GRDB wrapper
- [`Scroblebler/Storage/OfflineQueue.swift`](Scroblebler/Storage/OfflineQueue.swift:1) - Operation queue
- [`Scroblebler/Storage/LocalBlacklist.swift`](Scroblebler/Storage/LocalBlacklist.swift:1) - Blacklist storage

### Services
- [`Scroblebler/Services/CrossServiceSync.swift`](Scroblebler/Services/CrossServiceSync.swift:1) - Multi-service coordination
- [`Scroblebler/Services/BackfillService.swift`](Scroblebler/Services/BackfillService.swift:1) - Retroactive scrobbling

### Utilities
- [`Scroblebler/Utilities/Reachability.swift`](Scroblebler/Utilities/Reachability.swift:1) - Network monitoring
- [`Scroblebler/Utilities/TrackMatcher.swift`](Scroblebler/Utilities/TrackMatcher.swift) - Fuzzy track matching
- [`Scroblebler/Utilities/TrackIdentity.swift`](Scroblebler/Utilities/TrackIdentity.swift) - Canonical key generation

---

## Conclusion

Scroblebler's architecture successfully balances:
- **Simplicity**: Single unified Track model, clear data flows
- **Reliability**: Offline queue, automatic retries, network monitoring
- **Performance**: Main-thread-only UI updates, background processing, caching
- **Maintainability**: Clear separation of concerns, observable state patterns

The **TrackRepository as single source of truth** combined with **reactive SwiftUI** creates a predictable, testable architecture that handles the complexity of multi-service scrobbling while maintaining a simple mental model for developers.
