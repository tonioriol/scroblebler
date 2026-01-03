# Unified Track Architecture - Refactor Plan

## Executive Summary

**Problem**: The app has evolved into a patchwork of overlapping abstractions with multiple sources of truth for track data, redundant matching logic, and complex state synchronization.

**Solution**: Unify `Track` and `RecentTrack` into a single model, consolidate state management into `TrackRepository`, and centralize all track identity/matching logic.

**Impact**: Simpler codebase, single source of truth, easier to maintain, and sets a clean foundation for offline queue and future features.

---

## Current Architecture Problems

### 1. Multiple Track Models

**Two different track representations:**
```swift
// Currently playing
struct Track {
    let artist, album, name: String
    let length: Double
    let artwork: Data?
    var loved: Bool
    let startedAt: Int32
    var scrobbled: Bool
}

// History
struct RecentTrack {
    let name, artist, album: String
    let date: Int?
    let loved: Bool
    let playcount: Int?
    var serviceInfo: [String: ServiceTrackData]
}
```

**Problem**: Same entity, different structures. Forces conversion logic everywhere.

### 2. Four Different Matching/Identity Systems

1. **TrackStateManager**: `"\(artist.lowercased())|\(track.lowercased())"`
2. **LocalBlacklist**: `normalize(string).lowercased().trimmingCharacters(...)`
3. **TrackMatcher**: Timestamp-based with 2-minute windows
4. **RecentTrack.id**: `"\(artist)-\(name)-\(timestamp)-\(source)"`

**Problem**: Same matching logic reimplemented differently. Inconsistent behavior.

### 3. Three State Management Layers

```
┌─────────────────────────────────────┐
│ MainView                            │
│ @State recentTracks: [RecentTrack] │  ← UI state
└───────────────┬─────────────────────┘
                │
        ┌───────▼──────────┐
        │TrackStateManager │  ← Reactive mutable state
        │ (loved, playcount)│
        └───────┬──────────┘
                │
        ┌───────▼──────────┐
        │ServiceManager    │  ← API orchestration
        └──────────────────┘
```

**Problem**: State scattered across three layers. Manual synchronization required. Easy to get out of sync.

### 4. Code Duplication

**Matching logic** appears in:
- `TrackMatcher.swift` (timestamp-based)
- `TrackStateManager.swift` (artist|track key)
- `LocalBlacklist.swift` (normalized lowercase)
- Inline in `MainView` (syncing trackStates)

**Track operations** scattered across:
- `ServiceManager` (API calls)
- `TrackStateManager` (state updates)
- `MainView` (list management)
- `OfflineQueue` (persistence)

---

## Target Architecture

### Unified Track Model

```swift
// Scroblebler/Models/Track.swift
import Foundation

/// Single unified track model for all contexts (now playing, history, queue)
struct Track: Identifiable, Codable, Equatable {
    // MARK: - Identity
    
    let id: UUID  // Unique instance identifier
    
    /// Canonical key for matching (artist|track lowercase)
    var canonicalKey: String {
        TrackIdentity.key(artist: artist, track: name)
    }
    
    // MARK: - Immutable Metadata
    
    let artist: String
    let album: String
    let name: String
    let timestamp: Int           // Unix timestamp when played
    let duration: Double         // Track length in seconds
    let sourceService: ScrobbleService  // Where it was first seen
    
    // MARK: - Mutable State
    
    var loved: Bool = false
    var playcount: Int = 1       // Local count (may differ from service)
    var scrobbled: Bool = false  // Has been submitted to services
    var blacklisted: Bool = false
    
    // MARK: - Service Sync
    
    /// Track identifiers per service (for deletion/updates)
    var serviceInfo: [ScrobbleService: ServiceTrackData] = [:]
    
    /// Which services have this track
    var syncedServices: Set<ScrobbleService> {
        Set([sourceService] + serviceInfo.keys)
    }
    
    /// Computed sync status
    func syncStatus(enabledServices: Set<ScrobbleService>) -> SyncStatus {
        SyncStatus.calculate(
            presentInServices: syncedServices,
            enabledServices: enabledServices
        )
    }
    
    // MARK: - UI Metadata
    
    let artwork: Data?
    let artistURL: URL?
    let albumURL: URL?
    let trackURL: URL?
    
    // MARK: - Computed Properties
    
    var isNowPlaying: Bool {
        !scrobbled
    }
    
    var description: String {
        "\(name) by \(artist) from \(album)"
    }
    
    // MARK: - Factory Methods
    
    /// Create from media player
    static func fromMediaPlayer(
        artist: String,
        album: String,
        name: String,
        duration: Double,
        artwork: Data?,
        startedAt: Int32
    ) -> Track {
        Track(
            id: UUID(),
            artist: artist,
            album: album,
            name: name,
            timestamp: Int(startedAt),
            duration: duration,
            sourceService: .lastfm,  // Default, will be set by watcher
            artwork: artwork,
            artistURL: nil,
            albumURL: nil,
            trackURL: nil
        )
    }
    
    /// Create from API response
    static func fromAPI(
        artist: String,
        album: String,
        name: String,
        timestamp: Int,
        loved: Bool,
        playcount: Int?,
        imageUrl: String?,
        artistURL: URL,
        albumURL: URL,
        trackURL: URL,
        sourceService: ScrobbleService,
        serviceData: ServiceTrackData
    ) -> Track {
        Track(
            id: UUID(),
            artist: artist,
            album: album,
            name: name,
            timestamp: timestamp,
            duration: 0,
            sourceService: sourceService,
            loved: loved,
            playcount: playcount ?? 1,
            scrobbled: true,
            serviceInfo: [sourceService: serviceData],
            artistURL: artistURL,
            albumURL: albumURL,
            trackURL: trackURL
        )
    }
}
```

### TrackIdentity Utility

```swift
// Scroblebler/Utilities/TrackIdentity.swift
import Foundation

/// Centralized track identity and matching logic
struct TrackIdentity {
    /// Normalize string for matching (lowercase, trimmed)
    private static func normalize(_ string: String) -> String {
        string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Generate canonical key for track matching
    static func key(artist: String, track: String) -> String {
        let normalizedArtist = normalize(artist)
        let normalizedTrack = normalize(track)
        return "\(normalizedArtist)|\(normalizedTrack)"
    }
    
    /// Check if two tracks are the same (ignoring timestamp)
    static func matches(_ t1: Track, _ t2: Track) -> Bool {
        key(artist: t1.artist, track: t1.name) == 
        key(artist: t2.artist, track: t2.name)
    }
    
    /// Find matching track in array by canonical key
    static func find(
        artist: String,
        track: String,
        in tracks: [Track]
    ) -> Track? {
        let searchKey = key(artist: artist, track: track)
        return tracks.first { t in
            key(artist: t.artist, track: t.name) == searchKey
        }
    }
    
    /// Find match by timestamp window (for cross-service sync)
    static func findByTimestamp(
        _ track: Track,
        in candidates: [Track],
        windowSeconds: Int = 120
    ) -> Track? {
        candidates.first { candidate in
            matches(track, candidate) &&
            abs(track.timestamp - candidate.timestamp) <= windowSeconds
        }
    }
}
```

### TrackRepository

```swift
// Scroblebler/Services/TrackRepository.swift
import Foundation
import Combine

/// Single source of truth for all track data
@MainActor
class TrackRepository: ObservableObject {
    static let shared = TrackRepository()
    
    // MARK: - Published State
    
    /// All tracks (recent history + now playing)
    @Published private(set) var tracks: [Track] = []
    
    /// Currently playing track (first non-scrobbled track)
    var nowPlaying: Track? {
        tracks.first { !$0.scrobbled }
    }
    
    // MARK: - Dependencies
    
    private let serviceManager: ServiceManager
    private let offlineQueue = OfflineQueue.shared
    private let blacklist = LocalBlacklist.shared
    private let db = LocalDatabase.shared
    
    private init(serviceManager: ServiceManager = .shared) {
        self.serviceManager = serviceManager
    }
    
    // MARK: - CRUD Operations
    
    /// Add a new track (e.g., from media player)
    func add(_ track: Track) {
        // Insert at beginning (most recent first)
        tracks.insert(track, at: 0)
        Logger.info("Added track: \(track.description)", log: Logger.playback)
        
        // Auto-prune old tracks (keep last 200)
        if tracks.count > 200 {
            tracks = Array(tracks.prefix(200))
        }
    }
    
    /// Update track by ID
    func update(id: UUID, mutation: (inout Track) -> Void) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutation(&tracks[index])
        Logger.debug("Updated track: \(tracks[index].description)", log: Logger.ui)
    }
    
    /// Update track by canonical key
    func update(artist: String, track: String, mutation: (inout Track) -> Void) {
        guard let index = tracks.firstIndex(where: {
            TrackIdentity.key(artist: $0.artist, track: $0.name) ==
            TrackIdentity.key(artist: artist, track: track)
        }) else {
            return
        }
        mutation(&tracks[index])
    }
    
    /// Remove track
    func remove(id: UUID) {
        tracks.removeAll { $0.id == id }
    }
    
    /// Clear all tracks
    func clear() {
        tracks.removeAll()
        Logger.info("Cleared all tracks", log: Logger.ui)
    }
    
    // MARK: - Service Operations
    
    /// Load recent tracks from primary service
    func loadRecent(
        from service: ServiceCredentials,
        limit: Int = 20,
        page: Int = 1
    ) async throws {
        let recentTracks = try await serviceManager.getRecentTracks(
            credentials: service,
            limit: limit,
            page: page
        )
        
        // Merge with existing tracks
        for apiTrack in recentTracks {
            if let existing = TrackIdentity.find(
                artist: apiTrack.artist,
                track: apiTrack.name,
                in: tracks
            ) {
                // Update existing track
                update(id: existing.id) { track in
                    track.loved = apiTrack.loved
                    track.playcount = apiTrack.playcount ?? track.playcount
                    track.serviceInfo.merge(apiTrack.serviceInfo) { _, new in new }
                }
            } else {
                // Add new track
                add(apiTrack)
            }
        }
        
        Logger.info("Loaded \(recentTracks.count) tracks from \(service.service.displayName)", log: Logger.sync)
    }
    
    /// Scrobble a track to all enabled services
    func scrobble(_ track: Track) async {
        // Check blacklist
        if await blacklist.contains(artist: track.artist, track: track.name) {
            Logger.info("Track blacklisted, skipping scrobble", log: Logger.scrobbling)
            return
        }
        
        // Check network - queue if offline
        guard Reachability.isConnected else {
            try? await offlineQueue.enqueue(.scrobble(track: track))
            Logger.info("Queued for offline sync: \(track.description)", log: Logger.scrobbling)
            return
        }
        
        // Scrobble to all enabled services
        await serviceManager.scrobbleAll(track: track)
        
        // Update local state
        update(id: track.id) { t in
            t.scrobbled = true
        }
    }
    
    /// Toggle love status
    func toggleLove(_ track: Track) async {
        let newLoveState = !track.loved
        
        // Optimistic UI update
        update(id: track.id) { t in
            t.loved = newLoveState
        }
        
        // Queue or execute
        if Reachability.isConnected {
            await serviceManager.updateLoveAll(
                artist: track.artist,
                track: track.name,
                loved: newLoveState
            )
        } else {
            try? await offlineQueue.enqueue(.love(
                artist: track.artist,
                track: track.name,
                loved: newLoveState
            ))
        }
    }
    
    /// Delete scrobble from services
    func delete(_ track: Track) async {
        // Queue or execute
        if Reachability.isConnected {
            await serviceManager.deleteScrobbleAll(track: track)
        } else {
            try? await offlineQueue.enqueue(.delete(
                artist: track.artist,
                track: track.name,
                timestamp: track.timestamp
            ))
        }
        
        // Update local state
        update(id: track.id) { t in
            t.playcount = max(0, t.playcount - 1)
        }
    }
    
    // MARK: - Blacklist Integration
    
    func toggleBlacklist(_ track: Track) async {
        let isBlacklisted = await blacklist.contains(
            artist: track.artist,
            track: track.name
        )
        
        if isBlacklisted {
            try? await blacklist.remove(
                artist: track.artist,
                track: track.name
            )
        } else {
            try? await blacklist.add(
                artist: track.artist,
                track: track.name
            )
        }
        
        // Update local state
        update(id: track.id) { t in
            t.blacklisted = !isBlacklisted
        }
    }
}
```

---

## Migration Strategy

### Phase 1: Create New Structures (Non-Breaking)

1. Create `Track` model with unified fields
2. Create `TrackIdentity` utility
3. Create `TrackRepository` (parallel to ServiceManager)

**Files:**
- ✅ `Scroblebler/Models/Track.swift` (new unified model)
- ✅ `Scroblebler/Utilities/TrackIdentity.swift`
- ✅ `Scroblebler/Services/TrackRepository.swift`

### Phase 2: Update Components

Update UI components to use `TrackRepository` instead of `@State` + `TrackStateManager`:

**MainView.swift**:
```swift
struct MainView: View {
    @StateObject private var repository = TrackRepository.shared
    
    var body: some View {
        List(repository.tracks) { track in
            HistoryItem(track: track)
        }
        .task {
            await repository.loadRecent(from: primaryService)
        }
    }
}
```

**HistoryItem.swift**:
```swift
struct HistoryItem: View {
    let track: Track
    @StateObject private var repository = TrackRepository.shared
    
    var body: some View {
        HStack {
            // Track info
            
            LoveButton(track: track)
            UndoButton(track: track)
            BlacklistButton(track: track)
        }
    }
}
```

**Files Modified:**
- `Scroblebler/Views/MainView.swift`
- `Scroblebler/Components/HistoryItem.swift`
- `Scroblebler/Components/LoveButton.swift`
- `Scroblebler/Components/UndoButton.swift`
- `Scroblebler/Components/BlacklistButton.swift`
- `Scroblebler/Components/NowPlaying.swift`

### Phase 3: Update ServiceManager

Simplify ServiceManager to focus only on API calls, delegate state to `TrackRepository`:

```swift
class ServiceManager {
    // Remove @Published state
    // Keep only API client references and orchestration
    
    func getRecentTracks(...) async throws -> [Track] {
        // Convert API responses to unified Track model
    }
}
```

### Phase 4: Update OfflineQueue

```swift
// Update Operation enum to use unified Track
enum Operation: Codable {
    case scrobble(track: Track)
    case love(artist: String, track: String, loved: Bool)
    case delete(artist: String, track: String, timestamp: Int)
}
```

### Phase 5: Cleanup

1. Delete `Scroblebler/Utilities/TrackStateManager.swift`
2. Remove `RecentTrack` struct from `Models.swift`
3. Update `TrackMatcher` to use `TrackIdentity`
4. Remove redundant matching logic from `LocalBlacklist`

---

## Implementation Steps

### Step 1: Create Unified Track Model
- [ ] Create `Scroblebler/Models/Track.swift` with unified model
- [ ] Add factory methods for different sources
- [ ] Ensure Codable, Identifiable, Equatable conformance

### Step 2: Create TrackIdentity
- [ ] Create `Scroblebler/Utilities/TrackIdentity.swift`
- [ ] Implement `key()`, `matches()`, `find()` methods
- [ ] Add timestamp-based matching for sync

### Step 3: Create TrackRepository
- [ ] Create `Scroblebler/Services/TrackRepository.swift`
- [ ] Implement `@Published var tracks: [Track]`
- [ ] Add CRUD operations
- [ ] Add service operations (scrobble, love, delete)
- [ ] Integrate with OfflineQueue, LocalBlacklist

### Step 4: Update MainView
- [ ] Replace `@State recentTracks` with `@StateObject repository`
- [ ] Remove TrackStateManager references
- [ ] Simplify load logic (just call `repository.loadRecent()`)

### Step 5: Update Components
- [ ] HistoryItem: Pass `Track` instead of `RecentTrack`
- [ ] LoveButton: Use `repository.toggleLove(track)`
- [ ] UndoButton: Use `repository.delete(track)`
- [ ] BlacklistButton: Use `repository.toggleBlacklist(track)`
- [ ] NowPlaying: Use `repository.nowPlaying`

### Step 6: Update ServiceManager
- [ ] Remove `@Published` state
- [ ] Change return types to `[Track]`
- [ ] Convert API responses to unified Track model
- [ ] Delegate state management to TrackRepository

### Step 7: Update OfflineQueue
- [ ] Change `Operation` enum to use unified `Track`
- [ ] Update serialization logic
- [ ] Update sync execution to work with TrackRepository

### Step 8: Cleanup
- [ ] Delete `TrackStateManager.swift`
- [ ] Remove `RecentTrack` from `Models.swift`
- [ ] Update `TrackMatcher` to use `TrackIdentity`
- [ ] Remove redundant matching from `LocalBlacklist`

### Step 9: Testing
- [ ] Verify UI updates correctly
- [ ] Test love/unlove synchronization
- [ ] Test undo/redo operations
- [ ] Test blacklist toggling
- [ ] Test offline queue
- [ ] Test pagination
- [ ] Test cross-service sync

---

## Benefits

### 1. Single Source of Truth
✅ One `Track` model for everything
✅ One `tracks` array in `TrackRepository`
✅ No manual synchronization needed

### 2. Centralized Logic
✅ All matching in `TrackIdentity`
✅ All state operations in `TrackRepository`
✅ All API calls in `ServiceManager`

### 3. Simpler Components
```swift
// Before (93 lines of sync logic in TrackStateManager + manual sync in MainView)
@StateObject private var trackState = TrackStateManager.shared
trackState.updateState(artist: track.artist, track: track.name, loved: true)

// After (one line)
await repository.toggleLove(track)
```

### 4. Automatic UI Updates
SwiftUI observes `@Published var tracks` → all views update automatically

### 5. Memory Efficient
Auto-pruning keeps only last 200 tracks. No unbounded growth.

### 6. Easier Testing
```swift
let repository = TrackRepository()
repository.add(mockTrack)
XCTAssertEqual(repository.tracks.count, 1)
```

---

## Risks & Mitigation

### Risk 1: Breaking Changes
**Mitigation**: Incremental migration. Keep old code working while new code is built.

### Risk 2: Data Loss
**Mitigation**: 
- Services remain source of truth
- Can reload from API if local state corrupted
- No persistent local history (only cache)

### Risk 3: Performance
**Mitigation**:
- Auto-pruning to 200 tracks
- Lazy loading with pagination
- Indexed database queries

### Risk 4: Complexity During Migration
**Mitigation**:
- Clear step-by-step plan
- One component at a time
- Keep commits small and atomic

---

## Timeline Estimate

- **Step 1-3 (New structures)**: 3 hours
- **Step 4-5 (Update UI)**: 3 hours
- **Step 6-7 (Update services)**: 2 hours
- **Step 8-9 (Cleanup & testing)**: 2 hours

**Total: ~10 hours**

---

## Conclusion

**Recommendation**: Discard current uncommitted work (TrackStateManager, OfflineQueue updates) and proceed with unified refactor.

**Why**:
1. Technical debt eliminated early
2. Simpler foundation for future features
3. Offline queue will be easier with unified model
4. Only ~10 hours vs accumulating complexity forever

**Next Steps**:
1. User approval of this plan
2. Discard uncommitted changes (`git reset --hard`)
3. Create new branch: `refactor/unified-track-model`
4. Execute steps 1-9
5. Test thoroughly
6. Merge to main
