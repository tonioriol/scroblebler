# Refactor Plan: Clean Service Architecture

## Goal
Clear separation: ServiceManager = API gateway, SyncService = sync logic coordinator.

---

## The Right Separation

### ServiceManager (API Gateway)
**Role**: ONLY interface to ScrobbleClient APIs. No business logic.

```swift
class ServiceManager {
    private let clients: [ScrobbleService: ScrobbleClient]
    
    // Authentication
    func authenticate(service:) async throws -> (token, authURL)
    func completeAuthentication(service:token:) async throws -> ServiceCredentials
    
    // Single-service operations
    func scrobble(service:track:) async throws
    func updateNowPlaying(service:track:) async throws
    func updateLove(service:artist:track:loved:) async throws
    func deleteScrobble(service:identifier:) async throws
    func fetchRecentTracks(service:limit:page:) async throws -> [Track]
    
    // Multi-service operations (parallel execution)
    func scrobbleAll(track:) async
    func updateNowPlayingAll(track:) async -> Track
    func updateLoveAll(artist:track:loved:) async
    func deleteScrobbleAll(artist:track:serviceInfo:) async
}
```

**Responsibilities**:
- ✅ Manage client instances
- ✅ Restore credentials
- ✅ Execute API calls (single or parallel)
- ✅ Handle offline queue (network-aware execution)
- ❌ NO sync logic
- ❌ NO track matching
- ❌ NO deciding what to backfill

### SyncService (Coordination Logic)
**Role**: Decides WHAT to sync, coordinates HOW, delegates execution to ServiceManager.

```swift
class SyncService {
    private let serviceManager: ServiceManager
    
    func enrichTracksWithSecondaryServices(
        tracks: inout [Track],
        primaryService: ScrobbleService,
        secondaryServices: [ServiceCredentials],
        limit: Int,
        page: Int
    ) async {
        // 1. Fetch from secondary services (delegates to ServiceManager)
        let secondaryTracksByService = await fetchFromSecondaries(
            secondaryServices,
            limit: limit,
            page: page
        )
        
        // 2. Match tracks (sync logic - OUR responsibility)
        for i in tracks.indices {
            for (service, secondaryTracks) in secondaryTracksByService {
                if let match = findMatch(tracks[i], in: secondaryTracks) {
                    // Track exists - merge serviceInfo
                    tracks[i].serviceInfo[service] = match.serviceInfo[service]
                } else if shouldBackfill(tracks[i], to: service) {
                    // Track missing - backfill (delegates to ServiceManager)
                    await backfillTrack(tracks[i], to: service)
                    tracks[i].serviceInfo[service] = ServiceTrackData(
                        timestamp: tracks[i].timestamp,
                        id: nil
                    )
                }
            }
        }
    }
    
    // PRIVATE - delegates to ServiceManager
    private func fetchFromSecondaries(...) async -> [ScrobbleService: [Track]] {
        var result: [ScrobbleService: [Track]] = [:]
        
        await withTaskGroup(of: (ScrobbleService, [Track]?).self) { group in
            for creds in secondaryServices {
                group.addTask {
                    let tracks = try? await self.serviceManager.fetchRecentTracks(
                        service: creds.service,
                        limit: limit * 10,  // Over-fetch for matching
                        page: 1
                    )
                    return (creds.service, tracks)
                }
            }
            
            for await (service, tracks) in group {
                if let tracks = tracks {
                    result[service] = tracks
                }
            }
        }
        
        return result
    }
    
    private func backfillTrack(_ track: Track, to service: ScrobbleService) async {
        // Check blacklist
        if await LocalBlacklist.shared.contains(artist: track.artist, track: track.name) {
            return
        }
        
        // Delegate to ServiceManager
        try? await serviceManager.scrobble(service: service, track: track)
        
        // Sync love state
        try? await serviceManager.updateLove(
            service: service,
            artist: track.artist,
            track: track.name,
            loved: track.loved
        )
        
        // Rate limit
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    // Matching logic (NO API calls)
    private func findMatch(_ track: Track, in tracks: [Track]) -> Track? {
        // Exact match first
        if let exact = tracks.first(where: { $0.canonicalKey == track.canonicalKey }) {
            return exact
        }
        
        // Fuzzy match fallback
        return TrackMatcher.findMatch(for: track, in: tracks)
    }
    
    private func shouldBackfill(_ track: Track, to service: ScrobbleService) -> Bool {
        let age = Date().timeIntervalSince1970 - TimeInterval(track.timestamp)
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

**Responsibilities**:
- ✅ Fetch from secondary services (via ServiceManager)
- ✅ Match tracks (fuzzy or exact)
- ✅ Decide what to backfill (age limits, blacklist)
- ✅ Execute backfills (via ServiceManager)
- ✅ Merge serviceInfo into tracks
- ❌ NO direct client access
- ❌ NO authentication logic

### TrackStore (State Management)
**Role**: Owns track state, coordinates loading.

```swift
@MainActor
class TrackStore: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    
    private let serviceManager: ServiceManager
    private let syncService: SyncService
    
    func loadRecent(from service: ServiceCredentials, limit: Int, page: Int) async throws {
        // Fetch from primary via ServiceManager
        var primaryTracks = try await serviceManager.fetchRecentTracks(
            service: service.service,
            limit: limit,
            page: page
        )
        
        // Enrich with secondary services via SyncService
        let otherServices = Defaults.shared.enabledServices.filter { 
            $0.service != service.service 
        }
        
        if !otherServices.isEmpty {
            await syncService.enrichTracksWithSecondaryServices(
                tracks: &primaryTracks,
                primaryService: service.service,
                secondaryServices: otherServices,
                limit: limit,
                page: page
            )
        }
        
        // Update state
        if page == 1 {
            tracks = primaryTracks
        } else {
            tracks.append(contentsOf: primaryTracks.filter { new in
                !tracks.contains(where: { $0.id == new.id })
            })
        }
    }
    
    func scrobble(_ track: Track) async {
        // Delegate to ServiceManager
        await serviceManager.scrobbleAll(track: track)
        
        // Update local state
        update(id: track.id) { t in
            t.scrobbled = true
        }
    }
    
    // ... other operations
}
```

**Responsibilities**:
- ✅ Own track state
- ✅ Coordinate loading (via ServiceManager + SyncService)
- ✅ Coordinate mutations (via ServiceManager)
- ✅ Update local state
- ❌ NO API calls
- ❌ NO sync logic

---

## Clear Boundaries

```
┌─────────────────────────────────────────────┐
│              TrackStore                      │
│  "What tracks do we have?"                   │
│  - Owns: tracks: [Track]                     │
│  - Calls: ServiceManager, SyncService        │
└─────────┬────────────────────┬───────────────┘
          │                    │
          ↓                    ↓
┌─────────────────────┐  ┌────────────────────┐
│   ServiceManager    │  │   SyncService      │
│  "How to talk to    │  │  "What to sync"    │
│   services?"        │  │                    │
│  - Owns: clients    │  │  - Uses: Manager   │
│  - Does: API calls  │  │  - Does: Logic     │
└─────────────────────┘  └────────────────────┘
```

### Who Does What?

| Operation | TrackStore | ServiceManager | SyncService |
|-----------|------------|----------------|-------------|
| Load recent tracks | Coordinates | Fetches from API | Enriches with secondaries |
| Scrobble | Coordinates | Executes API call | - |
| Match tracks | - | - | Matches (fuzzy/exact) |
| Decide to backfill | - | - | Checks age limits |
| Execute backfill | - | Executes scrobble | Coordinates |
| Update state | Updates | - | - |

---

## Implementation

### Phase 1: Update ServiceManager
Add explicit fetch method:
```swift
func fetchRecentTracks(service: ScrobbleService, limit: Int, page: Int) async throws -> [Track] {
    guard let client = clients[service] else {
        throw ServiceError.clientNotFound
    }
    return try await client.getRecentTracks(limit: limit, page: page)
}
```

Move `getAllRecentTracks()` logic to TrackStore.

### Phase 2: Create SyncService
```swift
class SyncService {
    private let serviceManager: ServiceManager
    
    init(serviceManager: ServiceManager) {
        self.serviceManager = serviceManager
    }
    
    // Merge CrossServiceSync + BackfillService logic
    func enrichTracksWithSecondaryServices(...) async { ... }
}
```

### Phase 3: Update TrackStore
Inject dependencies:
```swift
init(serviceManager: ServiceManager = .shared, syncService: SyncService) {
    self.serviceManager = serviceManager
    self.syncService = syncService
}
```

Add `loadRecent()` method.

### Phase 4: Wire Dependencies
In `ContentView` or app initialization:
```swift
let serviceManager = ServiceManager.shared
let syncService = SyncService(serviceManager: serviceManager)
let trackStore = TrackStore(serviceManager: serviceManager, syncService: syncService)
```

### Phase 5: Delete Old Files
- Delete `CrossServiceSync.swift`
- Delete `BackfillService.swift`
- Remove from project.pbxproj

---

## Benefits

✅ **Single Responsibility**: Each class has ONE clear job  
✅ **No Overlap**: ServiceManager = gateway, SyncService = logic  
✅ **Clear Dependencies**: SyncService depends on ServiceManager (one direction)  
✅ **Testable**: Easy to mock ServiceManager for testing SyncService  
✅ **Same Features**: All functionality preserved  

Want me to implement this clean separation?
