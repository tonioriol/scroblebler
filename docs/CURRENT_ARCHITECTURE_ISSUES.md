# Current Architecture Issues

## Data Flow

```
Watcher (media player)
  └─> Track (no MBIDs, just metadata)
       └─> NowPlaying (binding)
            ├─> TrackStore lookup (get enriched track with MBIDs)
            ├─> Service.buildURLs() (uses MBIDs from enriched track)
            └─> TrackInfo display
```

## Problems

### 1. **Reactive Chain is Broken**
- Watcher provides original track (no MBIDs) via `@Published currentTrack`
- TrackStore holds enriched version (with MBIDs) via `@Published tracks`  
- NowPlaying does inline lookup to find enriched version
- SwiftUI doesn't track that the lookup result changed

### 2. **The `.id()` Hack**
```swift
.id("\(track.artist)-\(track.name)-\(trackStore.tracks.count)")
```
- Forces rebuild when ANY track is added to store (too broad)
- Adding a history track triggers NowPlaying rebuild (unnecessary)
- Inefficient - rebuilds entire view hierarchy

### 3. **Redundant StateObject**
```swift
@StateObject private var trackStore = TrackStore.shared
```
- TrackStore is a singleton already observed in MainView
- Creates extra observation point unnecessarily

### 4. **Linear Search on Every Render**
```swift
let currentTrack = trackStore.tracks.first { existing in
    TrackIdentity.key(artist: existing.artist, track: existing.name) == trackKey
} ?? track
```
- Runs on every body evaluation
- O(n) search through all tracks

## Better Alternatives

### Option A: Track-specific version (cleanest for current code)
```swift
// TrackStore
private var trackVersions: [String: Int] = [:]

func trackVersion(artist: String, track: String) -> Int {
    let key = TrackIdentity.key(artist: artist, track: track)
    return trackVersions[key] ?? 0
}

// Update version when track is enriched
```

Then in NowPlaying:
```swift
.id("\(track.artist)-\(track.name)-\(trackStore.trackVersion(artist: track.artist, track: track.name))")
```

This only rebuilds when THAT specific track changes, not all tracks.

### Option B: Store-driven (bigger refactor)
- Watcher adds track to store immediately
- Store becomes single source of truth
- View observes store.currentTrack directly
- No lookups needed

### Option C: Explicit state (most explicit)
```swift
@State private var enrichedTrack: Track?

.onChange(of: track) { newTrack in
    enrichedTrack = trackStore.findTrack(artist: newTrack.artist, track: newTrack.name) ?? newTrack
}
.onChange(of: trackStore.lastEnrichedTrack) { _ in
    if let track = track {
        enrichedTrack = trackStore.findTrack(artist: track.artist, track: track.name) ?? track
    }
}
```

## Recommendation

**Option A** is the best balance: minimal change, targeted rebuilds, clear intent.

Current `.id()` with `.tracks.count` is like using a sledgehammer - it works but rebuilds way more than needed.
