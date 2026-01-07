# Track Data Structure & Flow

## Current Data Model

### Track Structure
```swift
struct Track {
    // Core metadata
    let artist: String, album: String, name: String
    let timestamp: Int, duration: Double
    
    // Multi-service data (KEY INSIGHT: merged from multiple services)
    var serviceInfo: [ScrobbleService: ServiceTrackData]
    // Example: {
    //   .lastfm: ServiceTrackData(timestamp: 123456),
    //   .listenbrainz: ServiceTrackData(id: "mbid-123", artistMbid: "artist-456", ...)
    // }
    
    // UI metadata
    var loved: Bool, var playcount: Int
    var scrobbled: Bool  // false = now playing, true = history
}
```

### Single Unified Array
```
TrackStore.tracks: [Track]
├─ [0] Now Playing (scrobbled: false) ← from Watcher
├─ [1] History Track 1 (scrobbled: true) ← from Last.fm + ListenBrainz merged
├─ [2] History Track 2 (scrobbled: true) ← from Last.fm + ListenBrainz merged
└─ [3] History Track 3 (scrobbled: true)
```

**NOT per-service arrays** - it's a single array where each Track contains data from multiple services.

## Current Flow

### 1. Now Playing (from Watcher)
```
Watcher detects track
  └─> creates Track (no serviceInfo, scrobbled: false)
       └─> MainView binds watcher.currentTrack
            └─> NowPlaying receives binding
                 ├─> adds to TrackStore if new
                 ├─> enriches with MBIDs (updates serviceInfo)
                 └─> looks up enriched version to display URLs
```

**Problem**: Watcher's track and Store's track are separate objects.

### 2. History (from Service API)
```
MainView.loadRecentTracks()
  └─> TrackStore.loadRecent(from: primary)
       ├─> fetch from primary service (e.g., Last.fm)
       ├─> each Track has serviceInfo[.lastfm] only
       └─> SyncService.enrichTracksWithSecondaryServices()
            ├─> fetch from ListenBrainz
            ├─> match tracks by artist/title
            └─> merge: tracks[i].serviceInfo[.listenbrainz] = match.serviceInfo[.listenbrainz]
```

**Result**: Single Track object with merged data from multiple services.

## Option B: Store-Driven Architecture (RECOMMENDED)

### New Structure
```swift
class TrackStore {
    @Published private(set) var tracks: [Track] = []       // ← HISTORY (unchanged!)
    @Published private(set) var currentTrack: Track?       // ← NEW! Now Playing
    
    var history: [Track] {
        tracks.filter { $0.scrobbled }
    }
}
```

### History Handling (UNCHANGED)
The current history system is well-designed and stays as-is:

1. **Single Unified Array**: `tracks` contains merged data from all services
2. **Primary-Driven**: Main service (e.g., Last.fm) defines the canonical list
3. **Smart Matching**: Secondary services over-fetch (10x page size) for better matching
4. **Merge Strategy**: Each Track contains `serviceInfo[.lastfm]`, `serviceInfo[.listenbrainz]`, etc.

```
loadRecent(page: 1, limit: 20)
  ├─> Fetch 20 from Last.fm (primary)
  ├─> Fetch 200 from ListenBrainz (secondary, 10x window)
  ├─> Match by artist/title (handles timestamp drift)
  └─> Merge: tracks[i].serviceInfo[.listenbrainz] = match.serviceInfo
```

**Why the bigger window?** Timestamps don't align perfectly between services, so over-fetching increases match probability.

### What Changes with Option B
**ONLY** the now-playing track handling:
- Before: Watcher owns it, NowPlaying looks it up in store
- After: Store owns it, NowPlaying reads it directly

**History stays exactly the same** - no changes to the multi-service matching logic.

### Benefits
1. **Single Source of Truth**: Store owns currentTrack, not Watcher
2. **No Lookups**: Views read `trackStore.currentTrack` directly
3. **Automatic Reactivity**: When enriched, @Published triggers update
4. **No .id() Hacks**: SwiftUI sees @Published change naturally
5. **History Unchanged**: Proven multi-service matching logic stays intact

### New Flow
```
Watcher detects track
  └─> Watcher.onTrackChanged callback
       └─> TrackStore.setCurrentTrack(track)
            ├─> trackStore.currentTrack = track  // ← Published!
            ├─> add to tracks array if needed
            └─> Task { await enrich() }
                 └─> trackStore.currentTrack = enrichedTrack  // ← Published again!

NowPlaying observes trackStore.currentTrack
  ├─> SwiftUI detects @Published change
  ├─> view rebuilds with enriched data
  └─> URLs built with MBIDs ✅
```

### Implementation Changes

#### 1. TrackStore
```swift
@Published private(set) var currentTrack: Track?

func setCurrentTrack(_ track: Track) {
    currentTrack = track
    
    // Add to history if not exists
    ensureInArray(track)
    
    // Enrich in background
    Task {
        await enrichCurrentTrack()
    }
}

private func enrichCurrentTrack() async {
    guard let track = currentTrack else { return }
    
    // Get display service
    let displayService = Defaults.shared.mainServicePreference 
        ?? Defaults.shared.primaryService?.service 
        ?? .lastfm
    
    // Enrich
    guard let service = serviceManager.service(for: displayService) else { return }
    let enriched = await service.enrichTrack(track)
    
    // Update published property
    currentTrack = enriched
    
    // Also update in tracks array
    updateInArray(enriched)
}
```

#### 2. Watcher (minimal change)
```swift
// Keep @Published currentTrack for backwards compat, but...
// Route through store:
private func processStatus(_ status: MediaControlStatus) throws {
    // ... existing code ...
    let track = try getPlayerTrack(from: status)
    currentTrack = track  // For UI that still uses Watcher
    
    // NEW: Route through store
    Task { @MainActor in
        TrackStore.shared.setCurrentTrack(track)
    }
}
```

#### 3. NowPlaying (MUCH simpler!)
```swift
struct NowPlaying: View {
    @StateObject private var trackStore = TrackStore.shared
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @Binding var currentPosition: Double?
    @Binding var isPlaying: Bool
    
    var body: some View {
        if let track = trackStore.currentTrack {  // ← Direct observation!
            let service = serviceManager.service(for: displayService)
            let urls = service?.buildURLs(for: track)  // ← Uses enriched track!
            
            VStack(spacing: 12) {
                TrackInfo(...)
                PlayerControls(...)
            }
            .padding()
            // NO .id() HACK NEEDED!
        }
    }
}
```

## Comparison

### Current (with .id() hack)
- ❌ Two sources of truth (Watcher + Store)
- ❌ Manual lookup on every render
- ❌ .id() with tracks.count triggers on unrelated changes
- ❌ Rebuilds when history tracks added
- ✅ Works (but inefficient)

### Option A (track-specific versioning)
- ❌ Still has two sources of truth
- ❌ Still requires lookup
- ✅ Targeted rebuilds (only affected track)
- ⚠️ More complexity (version tracking)

### Option B (store-driven) ← BEST
- ✅ Single source of truth
- ✅ No lookups needed
- ✅ Natural SwiftUI reactivity
- ✅ Cleaner code
- ✅ No .id() hacks
- ✅ Efficient (only rebuilds when currentTrack changes)

## Recommendation

**Implement Option B** - it's the cleanest, most SwiftUI-idiomatic approach. The key insight is:

> TrackStore should own currentTrack, not just be a repository that NowPlaying queries.

This makes the reactive chain explicit:
```
Store publishes → View observes → View rebuilds
```

Instead of the current broken chain:
```
Store publishes → ??? → View doesn't know → Manual .id() hack
```
