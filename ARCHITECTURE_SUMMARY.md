# Scroblebler - Architecture Summary

## Core Pattern: Single Source of Truth + Reactive State

```
Media Player → Watcher → TrackRepository → SwiftUI Views
                ↓              ↑
         ServiceManager ←──────┘
                ↓
    [Last.fm, Libre.fm, ListenBrainz]
                ↓
         Offline Queue (SQLite)
```

## State Management (4 Core Components)

### 1. TrackRepository (@MainActor) - Single Source of Truth
```swift
@Published private(set) var tracks: [Track] = []  // All tracks (history + now playing)
var nowPlaying: Track? { tracks.first { !$0.scrobbled } }
```
- Owns all track state
- Coordinates with ServiceManager for network ops
- Auto-prunes to 200 tracks
- All mutations trigger SwiftUI updates

### 2. Watcher - Media Playback Monitor
```swift
@Published var currentTrack: Track?
@Published var currentPosition: Double?
@Published var playerState: PlayerState
```
- Listens to system-wide media events (MediaRemoteAdapter)
- Interpolates playback position (updates every 500ms)
- Triggers scrobble at 95% played + ≥30s duration

### 3. ServiceManager - Multi-Service Coordinator
```swift
private let clients: [ScrobbleService: ScrobbleClient]
@Published var scrobbleCompletedTrigger = 0
```
- Manages 3 service clients (Last.fm, Libre.fm, ListenBrainz)
- Network-aware execution (offline queue if disconnected)
- Parallel operations with TaskGroup
- Cross-service sync + backfilling

### 4. Defaults - User Preferences
```swift
@Published var serviceCredentials: [ServiceCredentials]
@Published var mainServicePreference: ScrobbleService?
var primaryService: ServiceCredentials? { ... }
```
- Persists to UserDefaults
- Tracks enabled services
- Primary service drives UI data

## Data Model: Unified Track

```swift
struct Track: Identifiable, Codable {
    // Immutable
    let id: UUID
    let artist, album, name: String
    let timestamp: Int
    let sourceService: ScrobbleService
    
    // Mutable state
    var loved, scrobbled, blacklisted: Bool
    var playcount: Int
    
    // Cross-service sync
    var serviceInfo: [ScrobbleService: ServiceTrackData]
    // Maps each service to its deletion identifiers:
    //   Last.fm → timestamp
    //   ListenBrainz → recording_msid
}
```

**Why unified?** Same model works for now playing, history, and queue. Transition is just `scrobbled = true`.

## Critical Data Flows

### Flow 1: Track Changes → Scrobble
```
Media Player
  ↓ (system events)
Watcher detects new track
  ↓ (onTrackChanged callback)
ServiceManager.updateNowPlayingAll()
  ↓ (parallel requests)
[Last.fm, Libre.fm, ListenBrainz]
  ↓
TrackRepository.add(track)
  ↓
SwiftUI re-renders

// Later: 95% played
Watcher.onScrobbleWanted
  ↓
ServiceManager.scrobbleAll()
  ↓ (check network)
Online? → Execute immediately
Offline? → OfflineQueue.enqueue()
```

### Flow 2: Load History + Cross-Service Sync
```
TrackRepository.loadRecent(from: primaryService)
  ↓
Fetch from primary (e.g., Last.fm 20 tracks)
  ↓
CrossServiceSync.reconcile()
  ├─ Fetch from secondary services in parallel
  ├─ TrackMatcher.findMatch() (fuzzy string matching)
  ├─ Merge serviceInfo for matched tracks
  └─ Collect missing tracks for backfill
  ↓
BackfillService.execute()
  ├─ Check blacklist
  ├─ Respect age limits (Last.fm <14 days, LB unlimited)
  └─ Scrobble to missing services (500ms rate limit)
```

### Flow 3: Offline Queue
```
Network disconnects
  ↓
ServiceManager.executeOrQueue()
  ↓
OfflineQueue.enqueue(operation) → SQLite
  ↓
[Operations stored with retry counter]
  ↓
Network reconnects
  ↓
Reachability.onNetworkAvailable()
  ↓
OfflineQueue.dequeue() → [Operations]
  ↓
Execute with retry (max 5 attempts)
  ↓
Success → remove from queue
Failure → increment attempts
```

## Storage

### SQLite (GRDB)
- **operations**: Offline queue (scrobble, love, delete)
- **blacklist**: Tracks to never scrobble (normalized artist|track)
- **listenbrainz_cache**: Playcount cache (LB API doesn't provide it)
- **listenbrainz_cache_meta**: Cache rebuild progress

### UserDefaults
- Service credentials (JSON-encoded)
- Main service preference
- Profile picture

### Keychain
- Last.fm password (for web scraping delete API)

### NSCache
- Album artwork images

## Key Design Decisions

### 1. @MainActor for TrackRepository
**Why?** All track mutations must be on main thread to ensure:
- SwiftUI views update synchronously
- No race conditions on tracks array
- Smooth animations

### 2. Service-Specific Identifiers
**Problem**: Different delete APIs:
- Last.fm: needs artist+track+timestamp
- ListenBrainz: needs recording_msid

**Solution**: `ServiceTrackData` with optional fields
```swift
struct ServiceTrackData {
    let timestamp: Int?  // For Last.fm/Libre.fm
    let id: String?      // For ListenBrainz
}
```

### 3. Offline Queue Persistence
**Why SQLite?** Network failures shouldn't lose scrobbles. Queue persists across app restarts with automatic retry on network restore.

### 4. Cross-Service Sync
**Why?** User adds new service → wants historical tracks backfilled. Solution: fetch from all services, fuzzy match, backfill gaps (respecting age limits).

### 5. Position Interpolation
**Why?** MediaRemoteAdapter doesn't send continuous position updates. Watcher interpolates based on last snapshot + elapsed time + playback rate.

## Concurrency

- **Main thread (@MainActor)**: All UI updates, TrackRepository mutations
- **Background queues**: Network requests, media processing (serial queue)
- **Coordination**: async/await with Task groups for parallel service operations

## Network Resilience

1. **Reachability monitoring** (NWPathMonitor)
2. **Automatic offline queue** on network failure
3. **Automatic retry** when network returns
4. **Max 5 attempts** per operation (then permanently failed)

## Cross-Service Synchronization Strategy

**Goal**: Keep all enabled services in sync

**Approach**:
1. Primary service = source of truth for UI
2. Load recent tracks from primary
3. Query secondary services by time range (faster than pagination)
4. Fuzzy match tracks (handles slight metadata differences)
5. Merge `serviceInfo` for matched tracks
6. Backfill missing tracks to secondary services
7. Publish backfill events to update UI

**Age limits**:
- Last.fm/Libre.fm: Can only backfill tracks <14 days old
- ListenBrainz: No age limit

## Performance Optimizations

1. **Auto-prune**: Keep max 200 tracks in memory
2. **Image preloading**: Background task for album artwork
3. **Position throttling**: Update every 500ms (not real-time)
4. **Rate limiting**: 500ms between backfill operations
5. **Database indexing**: Composite indexes on frequent queries

## Security

- **Passwords**: Keychain only (encrypted by OS)
- **API tokens**: UserDefaults (app sandbox)
- **HTTPS only**: All network requests
- **No credential logging**: Redacted from logs

## Key Files

| File | Purpose |
|------|---------|
| [`TrackRepository.swift`](Scroblebler/Services/TrackRepository.swift:1) | Single source of truth |
| [`ServiceManager.swift`](Scroblebler/ServiceManager.swift:1) | Service coordination |
| [`Watcher.swift`](Scroblebler/Watcher.swift:1) | Media playback monitoring |
| [`Track.swift`](Scroblebler/Models/Track.swift:1) | Unified data model |
| [`OfflineQueue.swift`](Scroblebler/Storage/OfflineQueue.swift:1) | Persistent operation queue |
| [`CrossServiceSync.swift`](Scroblebler/Services/CrossServiceSync.swift:1) | Multi-service reconciliation |
| [`Reachability.swift`](Scroblebler/Utilities/Reachability.swift:1) | Network monitoring |

## Architecture Strengths

✅ **Simple**: Single Track model, clear data flow  
✅ **Reliable**: Offline queue, automatic retries  
✅ **Performant**: Main-thread UI, background processing  
✅ **Reactive**: SwiftUI + Combine for automatic updates  
✅ **Resilient**: Network-aware with graceful degradation  

## Potential Improvements

1. **Dependency injection** instead of singletons (testability)
2. **Explicit state machine** for track lifecycle
3. **Unit tests** for core logic (currently none)
4. **Event sourcing** for sync state (better audit trail)
5. **Repository pattern** for all services (consistency)
