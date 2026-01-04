# Pragmatic Simplification: Keep Features, Cut Complexity

You're absolutely right - let's focus on **implementation complexity** while keeping all current functionality.

And yes: merging ServiceManager + TrackRepository would mix concerns. That was wrong advice.

---

## Separation of Concerns (Correct)

```
TrackRepository:  State management, CRUD operations
ServiceManager:   Network coordination, multi-service operations  
Watcher:          Media player integration
Defaults:         User preferences
```

These are GOOD separations. Keep them.

---

## Actual Unnecessary Complexity

### 1. **Dual Event Publishing** ❌

**Current**:
```swift
// ServiceManager
@Published var lastBackfilledTrack: BackfillEvent?
@Published var scrobbleCompletedTrigger = 0

// MainView observes both
.onChange(of: serviceManager.lastBackfilledTrack) { ... }
.onChange(of: serviceManager.scrobbleCompletedTrigger) { ... }

// Then manually updates TrackRepository
trackRepo.update(artist: event.artist, track: event.track) { ... }
```

**Problem**: ServiceManager publishes, MainView observes, then MainView updates TrackRepository. That's an extra hop.

**Simpler**:
```swift
// ServiceManager directly updates TrackRepository
func scrobbleAll(track: Track) async {
    await performScrobble(track)
    await trackRepo.markScrobbled(track.id)  // Direct update
}
```

**Cut**: ~50 lines of event observation code

---

### 2. **Generic executeOrQueue Wrapper** ❌

**Current**:
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

**Used in 3 places**, each reconstructing the Operation enum.

**Simpler**: Just inline it
```swift
func scrobbleAll(track: Track) async {
    if !Reachability.shared.isConnected {
        try? await OfflineQueue.enqueue(.scrobble(track, services))
        return
    }
    
    // Execute immediately
    await withTaskGroup { ... }
}
```

**Benefit**: Same functionality, but logic is visible at call site. No abstraction layer.

**Cut**: ~30 lines, improved clarity

---

### 3. **Separate CrossServiceSync + BackfillService** ❌

**Current**:
```
ServiceManager.getAllRecentTracks()
  → CrossServiceSync.reconcile()
    → BackfillService.execute()
```

Two separate classes doing one logical operation: "ensure track exists in all services"

**Simpler**: Inline into ServiceManager
```swift
func getAllRecentTracks() async throws -> [Track] {
    let primary = try await fetchFromPrimary()
    
    // Enrich with other services (inline)
    for secondary in otherServices {
        let secondaryTracks = try? await fetchFrom(secondary)
        for track in primary {
            if let match = secondaryTracks?.first(where: { matches(track, $0) }) {
                track.serviceInfo[secondary.service] = match.serviceInfo[secondary.service]
            } else if canBackfill(track, to: secondary.service) {
                // Backfill immediately (inline)
                try? await client.scrobble(track)
            }
        }
    }
    
    return primary
}
```

**Same functionality**, but:
- One method instead of two classes
- Clear sequential logic
- No task collection/event publishing

**Cut**: ~150 lines, 2 files

---

### 4. **Operation Enum with JSON Encoding** ⚠️

**Current**:
```swift
enum Operation: Codable {
    case scrobble(track: Track, services: [ScrobbleService])
    case love(artist: String, track: String, loved: Bool, services: [ScrobbleService])
    case delete(...)
}

// Stored as JSON string in SQLite
let payload = try JSONEncoder().encode(operation)
```

**Problem**: Complex encoding/decoding for something simple

**Simpler**: Direct SQLite columns
```sql
CREATE TABLE operations (
    type TEXT,           -- "scrobble", "love", "delete"
    artist TEXT,
    track TEXT,
    timestamp INT,
    loved INT,
    services TEXT,       -- JSON array: ["lastfm", "listenbrainz"]
    ...
)
```

**Benefit**: 
- No enum codable dance
- Query operations by type directly
- Simpler debugging (can read in DB browser)

**Cut**: ~50 lines

---

### 5. **Redundant Canonical Key Calculation** ❌

**Current**:
```swift
// Track.swift
var canonicalKey: String {
    TrackIdentity.key(artist: artist, track: name)
}

// TrackIdentity.swift
static func key(artist: String, track: String) -> String {
    "\(artist.lowercased())|\(track.lowercased())"
}

// Used everywhere:
let key = TrackIdentity.key(artist: track.artist, track: track.name)
```

**Simpler**: Just inline it
```swift
extension Track {
    var canonicalKey: String {
        "\(artist.lowercased())|\(name.lowercased())"
    }
}
```

**Cut**: 1 utility file, ~40 lines

---

### 6. **Factory Methods on Track** ❌

**Current**:
```swift
Track.fromMediaPlayer(artist:album:name:duration:artwork:startedAt:)
Track.fromAPI(artist:album:name:timestamp:loved:playcount:imageUrl:artistURL:...)
```

**These just call the initializer with defaults**.

**Simpler**: Use the initializer directly, or default parameters
```swift
init(
    artist: String,
    album: String,
    name: String,
    timestamp: Int,
    sourceService: ScrobbleService = .lastfm,
    loved: Bool = false,
    playcount: Int = 1,
    artwork: Data? = nil,
    ...
)
```

**Cut**: ~60 lines

---

### 7. **Position Interpolation Complexity** ⚠️

**Current**: Timer + snapshot tracking + seek detection + 1-second cooldown

**Is this necessary?** YES, if you want smooth progress bar.

**Could it be simpler?** Marginally - remove seek detection, just always update.

**Recommendation**: Keep as-is (complexity justified by UX)

---

### 8. **Separate BackfillEvent + Manual Update** ❌

**Current**:
```swift
// BackfillService returns events
let events = await backfillService.execute(tasks)

// ServiceManager publishes last event
self.lastBackfilledTrack = events.last

// MainView observes and manually updates
.onChange(of: serviceManager.lastBackfilledTrack) { event in
    trackRepo.update(artist: event.artist, track: event.track) { track in
        track.serviceInfo[event.service] = ...
    }
}
```

**Simpler**: Update during backfill
```swift
// In backfill loop
for (track, service) in tasks {
    try await client.scrobble(track)
    await trackRepo.update(track.id) { t in
        t.serviceInfo[service] = ServiceTrackData(...)
    }
}
```

**Cut**: Event struct, event publishing, event observation logic (~60 lines)

---

### 9. **TrackMatcher Fuzzy Logic** ⚠️

**Current**: String similarity algorithm for matching tracks across services

**Is this necessary?** Depends on real-world mismatch rate.

**Test**: 
- Try exact matching for 1 week
- If <5% of tracks fail to match, fuzzy logic unnecessary
- If >10% fail, fuzzy logic justified

**Potential Cut**: ~100 lines if exact matching sufficient

---

### 10. **Service-Specific Identifier Complexity** ⚠️

**Current**:
```swift
var serviceInfo: [ScrobbleService: ServiceTrackData] = [:]

struct ServiceTrackData {
    let timestamp: Int?
    let id: String?
}
```

**Is this necessary?** Only if delete/undo feature matters.

**If you keep undo**: This is minimal necessary complexity.

**If you drop undo**: Can delete entirely.

**Recommendation**: Keep (delete is user-facing feature)

---

## Recommended Refactors (No Feature Loss)

### 1. Inline Small Abstractions
```diff
- TrackIdentity utility class
- executeOrQueue wrapper
+ Direct implementation at call site
```
**Lines saved**: ~70

### 2. Merge CrossServiceSync + BackfillService
```diff
- Two separate service classes
+ Inline into ServiceManager.getAllRecentTracks()
```
**Lines saved**: ~150  
**Files deleted**: 2

### 3. Direct Repository Updates
```diff
- ServiceManager publishes events
- MainView observes events
- MainView updates TrackRepository
+ ServiceManager updates TrackRepository directly
```
**Lines saved**: ~50  
**Complexity reduced**: Remove circular observation

### 4. Simplify Offline Queue Storage
```diff
- Operation enum with Codable
- JSON encoding/decoding
+ Direct SQLite columns
```
**Lines saved**: ~50  
**Debuggability**: Improved

### 5. Remove Factory Methods
```diff
- Track.fromMediaPlayer()
- Track.fromAPI()
+ Use init() with default parameters
```
**Lines saved**: ~60

---

## Proposed Architecture (Same Features, Less Complexity)

### Clean Dependencies
```
┌──────────────┐
│   Watcher    │  Monitors playback
└──────┬───────┘
       │
       ↓
┌──────────────────────────┐
│  TrackRepository         │  State management
│  @MainActor              │  
└──────┬───────────────────┘
       │ (calls for network ops)
       ↓
┌──────────────────────────┐
│  ServiceManager          │  Network coordination
│  - Has TrackRepository   │  
│  - Updates repo directly │
└──────┬───────────────────┘
       │
       ↓
┌──────────────────────────┐
│  ScrobbleClient Protocol │  Service APIs
│  - LastFmClient          │
│  - ListenBrainzClient    │
│  - LibreFmClient         │
└──────────────────────────┘
```

### Key Change: Direct Updates
```swift
class ServiceManager {
    private let trackRepo: TrackRepository  // Injected
    
    func scrobbleAll(track: Track) async {
        // Network operation
        for service in enabledServices {
            try? await client.scrobble(track)
        }
        
        // Update state directly
        await trackRepo.markScrobbled(track.id)
    }
}
```

No event publishing, no MainView coordination needed.

---

## Summary: Complexity Cuts Without Feature Loss

| Refactor | Lines Saved | Files Deleted | Feature Impact |
|----------|-------------|---------------|----------------|
| Inline small abstractions | 70 | 1 | None |
| Merge sync + backfill | 150 | 2 | None |
| Direct repo updates | 50 | 0 | None |
| Simplify queue storage | 50 | 0 | None |
| Remove factory methods | 60 | 0 | None |
| **Total** | **380** | **3** | **None** |

**Current complexity**: ~2690 lines  
**After refactor**: ~2310 lines  
**Reduction**: 14% less code, **same functionality**

---

## What NOT to Change

✅ **Keep separate**: TrackRepository, ServiceManager, Watcher (good separation of concerns)  
✅ **Keep**: Offline queue (prevents data loss)  
✅ **Keep**: Service-specific identifiers (enables undo)  
✅ **Keep**: Multi-service support (core feature)  
✅ **Keep**: Position interpolation (smooth UX)  
✅ **Keep**: Unified Track model (already simple)  

---

## Next Steps

Want me to implement these refactors? They're all non-breaking changes that reduce complexity while preserving behavior.

Priority order:
1. **Merge CrossServiceSync + BackfillService** (biggest win)
2. **Direct repository updates** (removes event ping-pong)
3. **Inline small abstractions** (reduces indirection)
4. **Simplify queue storage** (better debuggability)
5. **Remove factory methods** (use init directly)
