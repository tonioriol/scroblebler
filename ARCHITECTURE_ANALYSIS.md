# Scroblebler - Deep Architecture Analysis

## Table of Contents
1. [Overview](#overview)
2. [Data Structures](#data-structures)
3. [State Management](#state-management)
4. [Data Flows](#data-flows)
5. [Storage Architecture](#storage-architecture)
6. [Network Architecture](#network-architecture)
7. [Key Components](#key-components)

---

## Overview

Scroblebler is a macOS menu bar app for scrobbling music playback to multiple services (Last.fm, Libre.fm, ListenBrainz). It follows a **layered architecture** with clear separation of concerns:

```
┌─────────────────────────────────────────────────┐
│  UI Layer (SwiftUI)                             │
│  - MainView, NowPlaying, HistoryItem            │
└───────────────┬─────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────┐
│  State Management (@Published, ObservableObject)│
│  - Watcher, TrackRepository, ServiceManager     │
└───────────────┬─────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────┐
│  Business Logic Layer                           │
│  - CrossServiceSync, BackfillService            │
└───────────────┬─────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────┐
│  Protocol Layer (ScrobbleClient)                │
│  - LastFmClient, ListenBrainzClient             │
└───────────────┬─────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────┐
│  Storage Layer (GRDB SQLite)                    │
│  - LocalDatabase, OfflineQueue, LocalBlacklist  │
└─────────────────────────────────────────────────┘
```

### Architecture Principles
- **Single Source of Truth**: TrackRepository is the ONLY source of track state
- **Unidirectional Data Flow**: UI → Repository → Services → Storage
- **Protocol-Oriented**: All service clients implement `ScrobbleClient` protocol
- **Reactive State**: SwiftUI `@Published` properties drive UI updates
- **Offline-First**: All operations queue when network unavailable

---

## Data Structures

### Core Models

#### 1. **Track** (Unified Model)
Location: `Scroblebler/Models/Track.swift`

The **central data structure** for all track contexts (now playing, history, queue).

```swift
struct Track: Identifiable, Codable, Equatable {
    // MARK: - Identity
    let id: UUID                          // Unique instance ID
    var canonicalKey: String              // "artist|track" (normalized)
    
    // MARK: - Immutable Metadata
    let artist: String                    // Track artist
    let album: String                     // Album name
    let name: String                      // Track name
    let timestamp: Int                    // Unix timestamp
    let duration: Double                  // Track length in seconds
    let sourceService: ScrobbleService    // Origin service
    
    // MARK: - Mutable State
    var loved: Bool = false               // Loved status
    var playcount: Int = 1                // Total plays
    var scrobbled: Bool = false           // Already scrobbled?
    var blacklisted: Bool = false         // User blacklisted?
    
    // MARK: - Service Sync
    var serviceInfo: [ScrobbleService: ServiceTrackData]  // Per-service data
    
    // MARK: - UI Metadata
    let artwork: Data?                    // Album artwork (PNG)
    var artistURL: URL?                   // Artist profile URL
    var albumURL: URL?                    // Album URL
    var trackURL: URL?                    // Track URL
    let imageUrl: String?                 // Cover art URL
}
```

**Key Characteristics**:
- `id`: Each Track instance has unique UUID (different from canonical key)
- `canonicalKey`: Used for matching tracks across services (normalized)
- `scrobbled`: false = now playing, true = history
- `serviceInfo`: Maps service to service-specific identifiers (timestamps, MSIDs)

**Factory Methods**:
```swift
Track.fromMediaPlayer(...)   // Create from media player
Track.fromAPI(...)           // Create from service API response
```

#### 2. **RecentTrack** (Temporary - Being Eliminated)
Location: `Scroblebler/Models.swift`

**STATUS: Work-in-progress refactor artifact.** Currently used at the API boundary, planned for removal.

```swift
struct RecentTrack: Codable, Identifiable {
    var id: String                        // Composite ID
    let name: String                      // Track name
    let artist: String                    // Artist
    let album: String                     // Album
    let date: Int?                        // Unix timestamp
    let isNowPlaying: Bool                // Now playing flag
    let loved: Bool                       // Loved status
    let imageUrl: String?                 // Cover art URL
    let artistURL: URL                    // Artist URL
    let albumURL: URL                     // Album URL
    let trackURL: URL                     // Track URL
    let playcount: Int?                   // Play count
    var serviceInfo: [String: ServiceTrackData]  // Service metadata
    var sourceService: ScrobbleService?   // Source service
}
```

**Current Usage (Transitional State)**:
- ❌ **API Boundary**: All service clients still return this (needs update)
- ❌ **Cross-Service Sync**: [`CrossServiceSync`](Scroblebler/Services/CrossServiceSync.swift) reconciles `[RecentTrack]` arrays (needs update)
- ❌ **Backfill**: [`BackfillService`](Scroblebler/Services/BackfillService.swift) operates on `RecentTrack` (needs update)
- ⚠️ **Conversion Point**: [`TrackRepository.loadRecent()`](Scroblebler/Services/TrackRepository.swift:89-132) converts to `Track` (temporary bridge)

**Planned Architecture** (See [`plans/unified-track-architecture.md`](plans/unified-track-architecture.md)):
- All clients should return `[Track]` directly
- `RecentTrack` will be deleted
- Simpler data flow: API → Track → UI

**Why It Still Exists**: The refactor to unified `Track` model is **50% complete**. Core infrastructure exists (Track, TrackIdentity, TrackRepository) but API layer hasn't been updated yet.

#### 3. **ServiceTrackData** (Service Identifiers)
Location: `Scroblebler/Models.swift`

Stores service-specific identifiers needed for operations (delete, update).

```swift
struct ServiceTrackData: Codable {
    let timestamp: Int?    // Required for Last.fm/Libre.fm
    let id: String?        // Required for ListenBrainz (recording_msid)
    
    // Factory methods
    static func lastfm(timestamp: Int) -> ServiceTrackData
    static func listenbrainz(recordingMsid: String, timestamp: Int) -> ServiceTrackData
}
```

**Critical for**:
- Scrobble deletion (needs exact timestamp/MSID)
- Cross-service sync (matching tracks)
- Offline queue replay (operation context)

#### 4. **ScrobbleService** (Enum)
Location: `Scroblebler/Models.swift`

```swift
enum ScrobbleService: String, CaseIterable, Codable, Identifiable {
    case lastfm = "Last.fm"
    case librefm = "Libre.fm"
    case listenbrainz = "ListenBrainz"
}
```

#### 5. **ServiceCredentials** (Authentication State)
Location: `Scroblebler/Models.swift`

```swift
struct ServiceCredentials: Codable {
    let service: ScrobbleService          // Which service
    var token: String                     // Session key/token
    var username: String                  // Username
    var profileUrl: String?               // Profile URL
    var isSubscriber: Bool                // Pro/subscriber status
    var isEnabled: Bool                   // Enabled for scrobbling
}
```

Stored in `UserDefaults` by `Defaults.shared`.

#### 6. **Operation** (Offline Queue)
Location: `Scroblebler/Storage/OfflineQueue.swift`

```swift
enum Operation: Codable, Identifiable {
    case scrobble(track: Track, services: [ScrobbleService])
    case love(artist: String, track: String, loved: Bool, services: [ScrobbleService])
    case delete(artist: String, track: String, timestamp: Int?, services: [ScrobbleService])
    
    var id: UUID { UUID() }
    var type: String { "scrobble" | "love" | "delete" }
}
```

Serialized to JSON and stored in SQLite `operations` table.

### Database Models

#### QueuedOperation (SQLite Record)
Location: `Scroblebler/Storage/Models/QueuedOperation.swift`

```swift
struct QueuedOperation: Codable, FetchableRecord, PersistableRecord {
    var id: String                        // UUID string
    var type: String                      // Operation type
    var payload: String                   // JSON-encoded Operation
    var attempts: Int                     // Retry count (max 5)
    var lastError: String?                // Last error message
    var lastAttempt: String?              // ISO8601 timestamp
    var createdAt: String                 // ISO8601 timestamp
    var updatedAt: String                 // ISO8601 timestamp
}
```

#### BlacklistEntry
Location: `Scroblebler/Storage/Models/BlacklistEntry.swift`

```swift
struct BlacklistEntry: Codable, FetchableRecord, PersistableRecord {
    var id: Int?                          // Auto-increment
    var artist: String                    // Normalized (lowercase)
    var track: String                     // Normalized (lowercase)
    var createdAt: String                 // ISO8601
    var updatedAt: String                 // ISO8601
}
```

#### ListenBrainzCacheEntry
Location: `Scroblebler/Storage/Models/ListenBrainzCacheEntry.swift`

Caches playcount data for ListenBrainz (they don't provide per-track playcount API).

```swift
struct ListenBrainzCacheEntry: Codable, FetchableRecord, PersistableRecord {
    var id: Int?                          // Auto-increment
    var username: String                  // LB username
    var artist: String                    // Normalized
    var track: String                     // Normalized
    var playcount: Int                    // Cached count
    var createdAt: String                 // ISO8601
    var updatedAt: String                 // ISO8601
}
```

---

## State Management

### 1. **Root State Objects** (Singletons)

#### Watcher (@Published)
Location: `Scroblebler/Watcher.swift`

**Responsibilities**: Monitor media player state via `MediaRemoteAdapter`.

```swift
class Watcher: ObservableObject {
    @Published var currentTrackID: String?        // Content item ID
    @Published var currentTrack: Track?           // Currently playing
    @Published var currentPosition: Double?       // Playback position
    @Published var maxPosition: Double?           // Max position reached
    @Published var musicRunning = false           // Player running?
    @Published var playerState: PlayerState       // Playing/paused/stopped
    
    var onTrackChanged: ((Track) -> Void)?        // Callback
    var onScrobbleWanted: ((Track) -> Void)?      // Callback
}
```

**State Flow**:
```
MediaRemoteAdapter → handleTrackInfo() → processStatus()
  → currentTrack updated → onTrackChanged callback
  → Triggers ServiceManager.updateNowPlayingAll()
```

#### TrackRepository (@MainActor, @Published)
Location: `Scroblebler/Services/TrackRepository.swift`

**The single source of truth for all track data.**

```swift
@MainActor
class TrackRepository: ObservableObject {
    static let shared = TrackRepository()
    
    @Published private(set) var tracks: [Track] = []  // ALL tracks
    
    var nowPlaying: Track? {                          // First non-scrobbled
        tracks.first { !$0.scrobbled }
    }
}
```

**Responsibilities**:
- Maintain ordered list of tracks (recent first)
- Provide CRUD operations
- Coordinate with ServiceManager for network operations
- Handle offline queueing
- Track state mutations (love, blacklist, playcount)

**Key Methods**:
```swift
func add(_ track: Track)                                    // Add new track
func update(id: UUID, mutation: (inout Track) -> Void)     // Update by ID
func update(artist: String, track: String, ...)            // Update by key
func remove(id: UUID)                                       // Remove track
func loadRecent(from: ServiceCredentials, ...)             // Load from API
func scrobble(_ track: Track)                              // Scrobble track
func toggleLove(artist: String, track: String)             // Toggle love
func delete(_ track: Track)                                // Delete scrobble
func toggleBlacklist(artist: String, track: String)        // Toggle blacklist
```

#### ServiceManager (@Published)
Location: `Scroblebler/ServiceManager.swift`

**Responsibilities**: Coordinate service operations across multiple clients.

```swift
class ServiceManager: ObservableObject {
    static let shared = ServiceManager()
    
    @Published var lastBackfilledTrack: BackfillEvent?       // Latest backfill
    @Published var scrobbleCompletedTrigger = 0              // Trigger UI refresh
    
    private let clients: [ScrobbleService: ScrobbleClient]   // Service clients
    private let crossServiceSync: CrossServiceSync           // Sync coordinator
    private let backfillService: BackfillService             // Backfill handler
}
```

**Key Methods**:
```swift
func scrobbleAll(track: Track)                             // Scrobble to all enabled
func updateNowPlayingAll(track: Track) -> Track            // Update all + enrich
func updateLoveAll(artist: String, track: String, loved: Bool)
func deleteScrobbleAll(artist: String, track: String, serviceInfo: ...)
func getAllRecentTracks(limit: Int, page: Int) -> [RecentTrack]
```

#### Defaults (@Published)
Location: `Scroblebler/Defaults.swift`

**Responsibilities**: Persistent settings and credentials.

```swift
class Defaults: ObservableObject {
    static let shared = Defaults()
    
    @Published var serviceCredentials: [ServiceCredentials] = []
    @Published var mainServicePreference: ScrobbleService?
    @Published var picture: Data?                           // Profile picture
    
    var enabledServices: [ServiceCredentials] { ... }       // Filtered enabled
    var primaryService: ServiceCredentials? { ... }         // Main or first
}
```

**Storage**: `UserDefaults.standard` + Keychain (for passwords).

### 2. **State Propagation Patterns**

#### Pattern 1: Media Player → UI
```
MediaRemoteAdapter.onTrackInfoReceived
  ↓
Watcher.handleTrackInfo()
  ↓
Watcher.currentTrack @Published
  ↓
SwiftUI View re-renders (NowPlaying)
```

#### Pattern 2: User Action → Services → Storage
```
UI Button (Love)
  ↓
TrackRepository.toggleLove()
  ↓ (optimistic update)
Repository.update(id: ...) { $0.loved = !loved }
  ↓ (network request)
ServiceManager.updateLoveAll()
  ↓ (per service)
ScrobbleClient.updateLove()
  ↓ (if offline)
OfflineQueue.enqueue(.love(...))
```

#### Pattern 3: Network Recovery → Queue Processing
```
Reachability.isConnected changes to true
  ↓
Reachability.onNetworkAvailable()
  ↓
OfflineQueue.dequeue()
  ↓
For each operation → executeOperation()
  ↓ (on success)
OfflineQueue.remove(operationId)
  ↓ (on failure, attempts < 5)
OfflineQueue.incrementAttempts(operationId)
```

### 3. **Reactive Bindings**

#### ContentView Setup
Location: `Scroblebler/Views/ContentView.swift`

```swift
struct ContentView: View {
    @StateObject var watcher = Watcher()
    @StateObject var serviceManager = ServiceManager.shared
    @StateObject var defaults = Defaults.shared
    @StateObject var trackRepo = TrackRepository.shared
    
    var body: some View {
        MainView()
            .environmentObject(watcher)
            .environmentObject(serviceManager)
            .environmentObject(defaults)
            .onLoad {
                watcher.onTrackChanged = { track in
                    Task {
                        let enriched = await serviceManager.updateNowPlayingAll(track: track)
                        await MainActor.run {
                            watcher.currentTrack = enriched
                            trackRepo.add(enriched)  // Add to repository
                        }
                    }
                }
                watcher.onScrobbleWanted = { track in
                    Task {
                        await serviceManager.scrobbleAll(track: track)
                    }
                }
                watcher.start()
            }
    }
}
```

**Key Insight**: Callbacks connect independent state objects, maintaining loose coupling.

---

## Data Flows

### Flow 1: **Track Detection & Now Playing**

```
┌─────────────────────────────────────────────────┐
│ 1. Media Player (Music.app, Spotify, etc.)     │
└─────────────────┬───────────────────────────────┘
                  │ (MediaRemote framework)
┌─────────────────▼───────────────────────────────┐
│ 2. MediaRemoteAdapter (Objective-C bridge)      │
│    - Listens to nowPlayingInfoDidChange         │
│    - Extracts: title, artist, album, artwork    │
└─────────────────┬───────────────────────────────┘
                  │ (JSON payload)
┌─────────────────▼───────────────────────────────┐
│ 3. Watcher.handleTrackInfo()                    │
│    - Decodes JSON → MediaControlStatus          │
│    - Converts to Track model                    │
│    - Detects track changes                      │
└─────────────────┬───────────────────────────────┘
                  │ (onTrackChanged callback)
┌─────────────────▼───────────────────────────────┐
│ 4. ServiceManager.updateNowPlayingAll()         │
│    - Parallel API calls to all enabled services │
│    - Enriches track with URLs (ListenBrainz)    │
└─────────────────┬───────────────────────────────┘
                  │ (enriched Track)
┌─────────────────▼───────────────────────────────┐
│ 5. Watcher.currentTrack updated                 │
│    + TrackRepository.add(track)                 │
└─────────────────┬───────────────────────────────┘
                  │ (@Published triggers)
┌─────────────────▼───────────────────────────────┐
│ 6. NowPlaying UI re-renders                     │
└─────────────────────────────────────────────────┘
```

**Key Details**:
- **Position Interpolation**: Timer-based estimation between MediaRemote updates
- **Late Artwork**: Artwork may arrive after initial track info (handled separately)
- **Blacklist Check**: Before updating services, check `LocalBlacklist.shared.contains()`

### Flow 2: **Scrobbling**

```
┌─────────────────────────────────────────────────┐
│ 1. Watcher Position Tracking                    │
│    - maxPosition tracked via interpolation      │
│    - On track change, check if previous should  │
│      be scrobbled (>95% played OR >4min)        │
└─────────────────┬───────────────────────────────┘
                  │ (onScrobbleWanted callback)
┌─────────────────▼───────────────────────────────┐
│ 2. ServiceManager.scrobbleAll(track)            │
│    - Check LocalBlacklist                       │
│    - Create Operation.scrobble                  │
└─────────────────┬───────────────────────────────┘
                  │ (network check)
          ┌───────┴───────┐
          │               │
    ONLINE│               │OFFLINE
          ▼               ▼
┌──────────────────┐  ┌─────────────────────┐
│ Execute Parallel │  │ OfflineQueue.enqueue│
│ withTaskGroup    │  │ (to SQLite)         │
└─────────┬────────┘  └─────────────────────┘
          │
┌─────────▼───────────────────────────────────────┐
│ 3. Per Service: ScrobbleClient.scrobble()       │
│    Last.fm:     POST track.scrobble             │
│    ListenBrainz: POST submit-listens            │
└─────────────────┬───────────────────────────────┘
                  │ (on all complete)
┌─────────────────▼───────────────────────────────┐
│ 4. ServiceManager.scrobbleCompletedTrigger += 1 │
└─────────────────┬───────────────────────────────┘
                  │ (@Published triggers)
┌─────────────────▼───────────────────────────────┐
│ 5. MainView.onChange(scrobbleCompletedTrigger)  │
│    → loadRecentTracks()                         │
│    → TrackRepository.loadRecent()               │
└─────────────────────────────────────────────────┘
```

**Scrobble Criteria** (in Watcher):
```swift
let percentPlayed = (maxPosition / track.length) * 100
if percentPlayed >= 95 && !track.scrobbled && track.length >= 30 {
    onScrobbleWanted?(track)
}
```

### Flow 3: **History Loading & Cross-Service Sync**

```
┌─────────────────────────────────────────────────┐
│ 1. MainView.loadRecentTracks()                  │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│ 2. TrackRepository.loadRecent()                 │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│ 3. ServiceManager.getAllRecentTracks()          │
│    - Fetch from PRIMARY service only            │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│ 4. PrimaryClient.getRecentTracks(limit, page)   │
│    Last.fm:      user.getRecentTracks           │
│    ListenBrainz: user/{username}/listens        │
└─────────────────┬───────────────────────────────┘
                  │ (primaryTracks: [RecentTrack])
┌─────────────────▼───────────────────────────────┐
│ 5. CrossServiceSync.reconcile()                 │
│    A. Calculate time range (min/max timestamps) │
│    B. Fetch from secondary services             │
└─────────────────┬───────────────────────────────┘
                  │
          ┌───────┴────────────┐
          │                    │
    TIMESTAMP QUERY      PAGE-BASED QUERY
      (faster)             (fallback)
          │                    │
          └────────┬───────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│ 6. TrackMatcher.findMatch()                     │
│    - For each primary track, find in secondary  │
│    - Match criteria: timestamp within 2min      │
│      AND delta ≤ 5 seconds                      │
└─────────────────┬───────────────────────────────┘
                  │
          ┌───────┴────────┐
          │                │
       MATCHED          NO MATCH
    (merge info)      (backfill?)
          │                │
          ▼                ▼
┌───────────────┐  ┌──────────────────┐
│ Enrich        │  │ BackfillService  │
│ serviceInfo   │  │ .canBackfill()   │
│ with data     │  │ - Check age      │
└───────────────┘  │ - Last.fm: <14d  │
                   │ - LB: unlimited  │
                   └─────────┬────────┘
                             │
                   ┌─────────▼────────┐
                   │ BackfillService  │
                   │ .execute()       │
                   │ - Async scrobble │
                   │ - Rate limited   │
                   └──────────────────┘
```

**Critical Logic in TrackMatcher**:
```swift
static func findMatch(for track: RecentTrack, in candidates: [RecentTrack]) -> RecentTrack? {
    candidates.first { candidate in
        abs((track.date ?? 0) - (candidate.date ?? 0)) < 120  // 2-min window
        && abs((track.date ?? 0) - (candidate.date ?? 0)) <= 5  // ≤5s delta
    }
}
```

### Flow 4: **Love/Unlove Track**

```
┌─────────────────────────────────────────────────┐
│ 1. User taps Love button in HistoryItem         │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│ 2. TrackRepository.toggleLove(artist, track)    │
│    - Find track by canonical key                │
│    - Optimistic update: loved = !loved          │
└─────────────────┬───────────────────────────────┘
                  │
          ┌───────┴───────┐
          │               │
    ONLINE│               │OFFLINE
          ▼               ▼
┌──────────────────┐  ┌─────────────────────┐
│ ServiceManager   │  │ OfflineQueue        │
│ .updateLoveAll() │  │ .enqueue(.love(...))│
└─────────┬────────┘  └─────────────────────┘
          │
┌─────────▼───────────────────────────────────────┐
│ 3. Parallel execution (withTaskGroup)           │
│    For each enabled service:                    │
│    - LastFmClient.updateLove()                  │
│    - ListenBrainzClient.updateLove()            │
└─────────────────────────────────────────────────┘
```

**Last.fm**: Simple API call (`track.love` / `track.unlove`)
**ListenBrainz**: Requires MusicBrainz ID lookup first, then `feedback/recording-feedback` with score 0/1

### Flow 5: **Undo (Delete Scrobble)**

```
┌─────────────────────────────────────────────────┐
│ 1. User taps Undo button                        │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│ 2. TrackRepository.delete(track)                │
│    - Decrement playcount locally                │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│ 3. ServiceManager.deleteScrobbleAll()           │
│    - Requires serviceInfo (timestamps, MSIDs)   │
└─────────────────┬───────────────────────────────┘
                  │
          ┌───────┴────────────┐
          │                    │
    Last.fm/Libre.fm    ListenBrainz
          │                    │
          ▼                    ▼
┌───────────────────┐  ┌──────────────────┐
│ Try API method:   │  │ Requires both:   │
│ library.remove    │  │ - timestamp      │
│ Scrobble          │  │ - recording_msid │
│                   │  │                  │
│ If fails:         │  │ POST delete-     │
│ LastFmWebClient   │  │ listen           │
│ .deleteScrobble() │  └──────────────────┘
│ (web session)     │
└───────────────────┘
```

**Critical**: `serviceInfo` must contain:
- Last.fm: `timestamp` (exact scrobble time)
- ListenBrainz: `timestamp` + `recording_msid`

Without these, deletion fails.

### Flow 6: **Offline Queue Processing**

```
┌─────────────────────────────────────────────────┐
│ 1. Network connection restored                  │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│ 2. Reachability.onNetworkAvailable()            │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│ 3. OfflineQueue.dequeue()                       │
│    - Fetch operations WHERE attempts < 5        │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│ 4. For each operation:                          │
│    try executeOperation()                       │
└─────────────────┬───────────────────────────────┘
                  │
          ┌───────┴────────┐
          │                │
      SUCCESS          FAILURE
          │                │
          ▼                ▼
┌──────────────────┐  ┌─────────────────────┐
│ OfflineQueue     │  │ OfflineQueue        │
│ .remove(id)      │  │ .incrementAttempts()│
│                  │  │ - attempts++        │
│                  │  │ - lastError saved   │
│                  │  │                     │
│                  │  │ If attempts >= 5:   │
│                  │  │ Mark permanently    │
│                  │  │ failed (not retried)│
└──────────────────┘  └─────────────────────┘
```

**Rate Limiting**: 500ms delay between operations to avoid overwhelming APIs.

---

## Storage Architecture

### SQLite Database (GRDB)
Location: `~/Library/Application Support/Scroblebler/scroblebler.db`

#### Schema (via DatabaseMigrator)

**Table: operations**
```sql
CREATE TABLE operations (
    id TEXT PRIMARY KEY,              -- UUID
    type TEXT NOT NULL,               -- 'scrobble', 'love', 'delete'
    payload TEXT NOT NULL,            -- JSON-encoded Operation
    attempts INTEGER DEFAULT 0,       -- Retry count
    last_error TEXT,                  -- Error message
    last_attempt TEXT,                -- ISO8601 timestamp
    created_at TEXT NOT NULL,         -- ISO8601 timestamp
    updated_at TEXT NOT NULL          -- ISO8601 timestamp
);

CREATE INDEX idx_operations_pending 
ON operations(attempts, created_at) 
WHERE attempts < 5;
```

**Table: blacklist**
```sql
CREATE TABLE blacklist (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    artist TEXT NOT NULL,             -- Normalized (lowercase)
    track TEXT NOT NULL,              -- Normalized (lowercase)
    created_at TEXT NOT NULL,         -- ISO8601
    updated_at TEXT NOT NULL          -- ISO8601
);

CREATE UNIQUE INDEX idx_blacklist_unique ON blacklist(artist, track);
CREATE INDEX idx_blacklist_created ON blacklist(created_at);
```

**Table: listenbrainz_cache**
```sql
CREATE TABLE listenbrainz_cache (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    artist TEXT NOT NULL,             -- Normalized
    track TEXT NOT NULL,              -- Normalized
    playcount INTEGER NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

CREATE UNIQUE INDEX idx_lbc_unique ON listenbrainz_cache(username, artist, track);
CREATE INDEX idx_lbc_username ON listenbrainz_cache(username);
CREATE INDEX idx_lbc_updated ON listenbrainz_cache(updated_at);
```

**Table: listenbrainz_cache_meta**
```sql
CREATE TABLE listenbrainz_cache_meta (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL UNIQUE,
    continue_from_ts INTEGER,         -- Pagination cursor
    completed_at TEXT,                -- Cache build completion
    total_tracks INTEGER,             -- Total tracks cached
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

### UserDefaults Storage

Managed by `Defaults.swift`:

```swift
// Key-value pairs in UserDefaults.standard
"firstRun": Bool                              // nil = first run
"mainServicePreference": String               // ScrobbleService.rawValue
"serviceCredentials": Data                    // JSON-encoded [ServiceCredentials]
"picture": Data                               // Profile picture PNG
"blacklistMigratedToSQLite": Bool             // Migration flag
```

### Keychain Storage

Managed by `KeychainHelper.swift`:

```swift
// Stored per username
kSecAttrService: "com.scroblebler.lastfm"
kSecAttrAccount: username
kSecValueData: password (UTF-8 encoded)
```

**Purpose**: Store Last.fm password for web client authentication (enables scrobble deletion).

---

## Network Architecture

### Protocol Layer

#### ScrobbleClient Protocol
Location: `Scroblebler/Protocols/ScrobbleClient.swift`

```swift
protocol ScrobbleClient {
    var baseURL: URL { get }
    var authURL: String { get }
    var linkColor: Color { get }
    
    // Authentication
    func authenticate() async throws -> (token: String, authURL: URL)
    func completeAuthentication(token: String) async throws -> (username: String, sessionKey: String, profileUrl: String?, isSubscriber: Bool)
    func setCredentials(username: String, sessionKey: String)
    
    // Scrobbling
    func updateNowPlaying(track: Track) async throws
    func scrobble(track: Track) async throws
    func updateLove(artist: String, track: String, loved: Bool) async throws
    func deleteScrobble(identifier: ScrobbleIdentifier) async throws  // Optional
    
    // History
    func getRecentTracks(limit: Int, page: Int) async throws -> [RecentTrack]
    func getRecentTracksByTimeRange(minTs: Int?, maxTs: Int?, limit: Int) async throws -> [RecentTrack]?  // Optional
    func getUserStats() async throws -> UserStats?
    func getTopArtists(period: String, limit: Int) async throws -> [TopArtist]
    func getTopAlbums(period: String, limit: Int) async throws -> [TopAlbum]
    func getTopTracks(period: String, limit: Int) async throws -> [TopTrack]
    func getTrackInfo(artist: String, track: String) async throws -> (loved: Bool, playcount: Int?)
}
```

### Client Implementations

#### LastFmClient
- **API**: REST (POST with URL-encoded form data)
- **Auth**: Token-based (MD5 signature)
- **Base URL**: `https://ws.audioscrobbler.com/2.0/`
- **Rate Limiting**: Retry on error code 8
- **Special**: Web client for deletion (requires password)

#### ListenBrainzClient
- **API**: REST (JSON)
- **Auth**: Token header (`Token {token}`)
- **Base URL**: `https://api.listenbrainz.org/1/`
- **Rate Limiting**: Header-based (`X-RateLimit-*`)
- **Special**: 
  - MBID Mapper for metadata enrichment
  - Playcount cache (manual rebuild needed)
  - Pagination via `max_ts` parameter

#### LibreFmClient
- **API**: Same as Last.fm (compatible)
- **Base URL**: `https://libre.fm/2.0/`

### Network Utilities

#### Reachability
Location: `Scroblebler/Utilities/Reachability.swift`

```swift
class Reachability: ObservableObject {
    @Published private(set) var isConnected = true
    @Published private(set) var connectionType: NWInterface.InterfaceType?
    
    // Monitors network using NWPathMonitor
    // Triggers offline queue processing on reconnect
}
```

#### ListenBrainzRateLimiter
Location: `Scroblebler/Utilities/ListenBrainzRateLimiter.swift`

Implements token bucket algorithm based on response headers:
- `X-RateLimit-Remaining`: Tokens left
- `X-RateLimit-Reset-In`: Seconds until reset
- `Retry-After`: Backoff duration (on 429)

#### NetworkClient
Location: `Scroblebler/Utilities/NetworkClient.swift`

Provides retry logic with exponential backoff:
```swift
static func executeWithRetry<T>(
    maxRetries: Int = 3,
    shouldRetry: ((Error) -> Bool)? = nil,
    operation: () async throws -> T
) async throws -> T
```

---

## Key Components

### 1. MediaRemoteAdapter (Objective-C)
Location: External dependency

**Purpose**: Bridge to private MediaRemote framework.

**Key APIs**:
- `MRMediaRemoteGetNowPlayingInfo`: Get current track metadata
- `MRMediaRemoteRegisterForNowPlayingNotifications`: Listen to changes

**Data Provided**:
- Title, artist, album
- Duration (microseconds)
- Elapsed time
- Playback rate (1.0 = playing, 0.0 = paused)
- Artwork (NSImage)
- Bundle identifier (app playing media)

### 2. CrossServiceSync
Location: `Scroblebler/Services/CrossServiceSync.swift`

**Purpose**: Reconcile track data across multiple services.

**Algorithm**:
1. Fetch primary service tracks
2. Calculate time range (min/max timestamps)
3. Fetch secondary services (timestamp query or page-based)
4. For each primary track:
   - Find match in secondary (timestamp-based)
   - If matched: merge `serviceInfo`
   - If not matched + eligible: queue for backfill
5. Return backfill tasks

**Efficiency**: Uses timestamp queries when supported (ListenBrainz, Last.fm) to fetch only relevant data.

### 3. BackfillService
Location: `Scroblebler/Services/BackfillService.swift`

**Purpose**: Backfill missing tracks to services.

**Rules**:
- Last.fm/Libre.fm: Only tracks <14 days old
- ListenBrainz: No age limit
- Check blacklist before backfilling
- Rate limit: 500ms between operations

**Returns**: Array of `BackfillEvent` for UI updates.

### 4. ListenBrainzCache
Location: `Scroblebler/Clients/ListenBrainzCache.swift`

**Purpose**: Cache playcount data for ListenBrainz (they don't provide per-track API).

**Process**:
1. Fetch entire listen history (paginated)
2. Count occurrences per (artist, track) pair
3. Store in SQLite
4. Use cached counts when displaying tracks

**Invalidation**: Manual (user can trigger rebuild).

### 5. TrackIdentity
Location: `Scroblebler/Utilities/TrackIdentity.swift`

**Purpose**: Centralized track matching logic.

```swift
static func key(artist: String, track: String) -> String {
    "\(artist.lowercased().trimmed())|\(track.lowercased().trimmed())"
}
```

Used throughout app for deduplication and matching.

### 6. TrackMatcher
Location: `Scroblebler/Utilities/TrackMatcher.swift`

**Purpose**: Match tracks across services using timestamps.

**Criteria**:
- Timestamps within 2-minute window
- Exact timestamp delta ≤ 5 seconds

**Why timestamp-based?**: Artist/track names may differ slightly across services (e.g., "feat." vs "ft.").

---

## Critical Insights

### 1. **Dual Track Models (Transitioning)**
- `RecentTrack`: Legacy API model, being phased out
- `Track`: Unified model for all contexts
- **Conversion point**: `TrackRepository.loadRecent()` converts API results

### 2. **ServiceInfo is Critical**
Without proper `serviceInfo`, deletion fails. Tracks must store:
- Last.fm: exact `timestamp`
- ListenBrainz: `timestamp` + `recording_msid`

### 3. **Offline-First Design**
All mutating operations check network first:
```swift
if Reachability.shared.isConnected {
    // Execute immediately
} else {
    // Queue for later
    OfflineQueue.shared.enqueue(operation)
}
```

### 4. **Playcount Caching**
ListenBrainz doesn't provide per-track playcount API. Solution:
- Fetch entire history once
- Count locally
- Cache in SQLite
- Invalidate when needed

### 5. **Cross-Service Sync Complexity**
Matching tracks across services is non-trivial:
- Same track may have slightly different metadata
- Timestamps may differ (clock skew, API delays)
- Solution: 2-minute window + 5-second exact delta

### 6. **Rate Limiting**
- ListenBrainz: Token bucket from headers
- Last.fm: Retry on error code 8
- Backfill: 500ms delay between operations

### 7. **Web Client for Deletion**
Last.fm API doesn't support deletion. Workaround:
- Authenticate via web (username + password)
- Store session cookie
- Use web scraping to delete scrobbles

### 8. **Blacklist Normalization**
All blacklist comparisons use normalized keys:
```swift
func normalize(_ string: String) -> String {
    string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
}
```

Prevents case-sensitive mismatches.

---

## Architectural Patterns

### 1. **Repository Pattern**
`TrackRepository` is the single source of truth for all track data.

### 2. **Strategy Pattern**
Multiple `ScrobbleClient` implementations behind single protocol.

### 3. **Observer Pattern**
SwiftUI `@Published` properties + Combine for reactive updates.

### 4. **Command Pattern**
`Operation` enum encapsulates operations for offline queue.

### 5. **Singleton Pattern**
- `ServiceManager.shared`
- `TrackRepository.shared`
- `Defaults.shared`
- `Reachability.shared`
- `OfflineQueue.shared`
- `LocalBlacklist.shared`

### 6. **Factory Pattern**
Track creation via static factory methods:
- `Track.fromMediaPlayer(...)`
- `Track.fromAPI(...)`

### 7. **Adapter Pattern**
`MediaRemoteAdapter` adapts private framework to Swift.

---

## Data Consistency Guarantees

### 1. **Optimistic Updates**
UI updates immediately, network syncs asynchronously.

### 2. **Eventual Consistency**
Offline operations eventually execute when network returns.

### 3. **Retry Logic**
Failed operations retry up to 5 times with exponential backoff.

### 4. **Transaction Safety**
GRDB provides ACID guarantees for SQLite operations.

### 5. **MainActor Isolation**
`TrackRepository` is `@MainActor` to prevent race conditions.

---

## Performance Considerations

### 1. **Lazy Loading**
History tracks loaded on-demand with pagination.

### 2. **Image Preloading**
Background task preloads album art for visible tracks.

### 3. **Parallel API Calls**
`withTaskGroup` for concurrent service operations.

### 4. **Cached Playcount**
ListenBrainz playcount cached to avoid repeated full history fetches.

### 5. **Track Limit**
Repository auto-prunes to keep last 200 tracks.

### 6. **Serial Processing Queue**
Watcher uses serial DispatchQueue to prevent race conditions in track detection.

---

## Conclusion

Scroblebler follows a **clean, layered architecture** with:
- ✅ Clear separation of concerns
- ✅ Protocol-oriented design
- ✅ Reactive state management
- ✅ Offline-first approach
- ✅ Comprehensive error handling
- ✅ Efficient cross-service sync

The transition from `RecentTrack` to unified `Track` model is ongoing, with the goal of simplifying the codebase and eliminating dual models.
