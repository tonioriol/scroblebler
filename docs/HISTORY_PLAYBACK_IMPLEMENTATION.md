# History Track Playback Implementation

## Overview
This document describes the implementation for playing tracks from history using MediaRemote track identifiers.

## Changes Made

### 1. MediaRemote Adapter Modifications (Subtree)
Added mediaremote-adapter as a Git subtree and modified it to extract track unique identifiers:

**Files Modified:**
- `Submodules/mediaremote-adapter/Sources/CIMediaRemote/include/MediaRemoteAdapterKeys.h` - Added `kUniqueIdentifier` extern
- `Submodules/mediaremote-adapter/Sources/CIMediaRemote/MediaRemoteAdapterKeys.m` - Added `kUniqueIdentifier` constant
- `Submodules/mediaremote-adapter/Sources/CIMediaRemote/MediaRemote.m` - Added `kMRMediaRemoteNowPlayingInfoUniqueIdentifier` constant
- `Submodules/mediaremote-adapter/Sources/CIMediaRemote/MediaRemoteAdapter.m` - Extract uniqueIdentifier from nowPlayingInfo
- `Submodules/mediaremote-adapter/Sources/MediaRemoteAdapter/TrackInfo.swift` - Added `uniqueIdentifier` property to Payload

### 2. Track Model Updates
**File:** `Scroblebler/Models/Track.swift`

Added two new fields:
- `bundleIdentifier: String?` - The media player bundle ID (e.g., "com.apple.Music")
- `trackId: String?` - MediaRemote's unique identifier for the track

These fields are optional and only populated for tracks played through the media player.

### 3. Watcher Updates
**File:** `Scroblebler/Watcher.swift`

- Updated `MediaControlStatus` struct to include `uniqueIdentifier` field
- Modified track info handling to capture and store the unique identifier
- Updated `getPlayerTrack()` to populate both `bundleIdentifier` and `trackId`

### 4. UI Changes
**File:** `Scroblebler/Components/HistoryItem.swift`

Added a play button that:
- Only shows if the track has a `trackId`
- Uses SF Symbol "play.circle" 
- Currently logs the play action (playback implementation pending)

### 5. Package Dependencies
**File:** `Package.swift`

Changed from remote GitHub dependency to local subtree:
```swift
.package(path: "Submodules/mediaremote-adapter")
```

### 6. Client Updates
Fixed Track initialization in:
- `Scroblebler/Clients/LastFmClient.swift`
- `Scroblebler/Clients/ListenBrainzClient.swift`
- `Scroblebler/Components/UndoButton.swift`

All now include `bundleIdentifier: nil, trackId: nil` for API-fetched tracks.

## Remaining Work

### Critical: Implement Actual Playback

The play button currently only logs. We need to implement one of these approaches:

#### Option A: MediaRemote with Track ID (PREFERRED if possible)
Research if MediaRemote private framework supports:
```objc
MRMediaRemoteSendCommand(kMRPlay, @{
    kMRMediaRemoteOptionTrackID: trackId,
    kMRMediaRemoteOptionSourceID: sourceId
});
```

**Pros:** Native, fast, reliable
**Cons:** May not be supported, needs research

#### Option B: AppleScript (FALLBACK)
```applescript
tell application "Music"
    set theTrack to first track whose artist is "X" and name is "Y"
    play theTrack
end tell
```

**Pros:** Reliable, well-documented
**Cons:** Slower, requires exact artist/title match

### Implementation Steps

1. **Research MediaRemote playback by ID**
   - Check if `kMRMediaRemoteOptionTrackID` exists and works
   - Test with sample track IDs from currently playing tracks

2. **Create playback handler in MediaControl**
   ```swift
   static func playTrack(id: String, bundleIdentifier: String?) {
       // Implementation here
   }
   ```

3. **Wire up HistoryItem button**
   ```swift
   Button(action: {
       MediaControl.playTrack(id: trackId, bundleIdentifier: track.bundleIdentifier)
   })
   ```

4. **Test thoroughly**
   - Test with Apple Music
   - Test with Spotify (if supported)
   - Handle errors gracefully

## Testing Checklist

- [ ] Play button appears for tracks with trackId
- [ ] Play button hidden for API-fetched tracks without trackId
- [ ] Clicking play button triggers playback in correct app
- [ ] Error handling for unavailable tracks
- [ ] Works across app restarts (track IDs persist in database)

## Notes

### About Track IDs
- **Persistence:** MediaRemote unique identifiers may change between app launches
- **Scope:** IDs are player-specific (Apple Music IDs ≠ Spotify IDs)
- **Availability:** Only available for tracks played through the system, not API-fetched tracks

### Database Schema
The Track model already supports these fields through Codable. No database migration needed - existing tracks will have `nil` values.

### Future Enhancements
1. Add "Play in Apple Music" / "Play in Spotify" context menu
2. Cache track search results to improve AppleScript performance
3. Support queue management (add to up next)
4. Support playback in specific player even if different app is active
