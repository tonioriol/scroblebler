# Scroblebler - Refactoring Analysis & Progress

## Phase 1: Critical Performance Fixes ✅ COMPLETED

### What Was Done

#### 1. ✅ Stop Polling (MainView.swift)
- **Removed:** `.onChange(of: watcher.currentTrack?.name)` that reloaded history on every track change
- **Impact:** No more API hammering on pause/resume/seek operations
- **Lines removed:** 3

#### 2. ✅ Simplify Track Matching (ServiceManager.swift)
- **Replaced:** 53-line fuzzy matching with 6-line exact timestamp comparison
- **Removed:** Levenshtein distance algorithm (80% similarity threshold)
- **New:** Exact timestamp matching (±10 seconds)
- **Lines removed:** 45

#### 3. ✅ Delete StringSimilarity Utility
- **Deleted:** `Scroblebler/StringSimilarity.swift` (46 lines, only used for fuzzy matching)
- **Updated:** `Scroblebler.xcodeproj/project.pbxproj` to remove all references
- **Lines removed:** 46

#### 4. ✅ Combine API Calls + Stateful Clients (Major Architectural Improvement)

**Before:**
```swift
func getTrackUserPlaycount(token: String, artist: String, track: String) -> Int?
func getTrackLoved(token: String, artist: String, track: String) -> Bool
// 2 separate API calls, credentials passed through every method
```

**After:**
```swift
func getTrackInfo(artist: String, track: String) -> (loved: Bool, playcount: Int?)
// 1 API call, credentials stored internally
```

**Changes:**
- **LastFmClient:** Stores `username` and `sessionKey` internally
- **ListenBrainzClient:** Stores `username` and `token` internally, proper feedback API implementation
- **LibreFmClient:** Inherits from LastFmClient, same behavior
- **NowPlaying/HistoryItem:** Simplified to call single `getTrackInfo()` method
- **Removed dead code:** Deleted `getTrackUserPlaycount()` and `getTrackLoved()` wrapper methods
- **Lines removed:** 20

#### 5. ✅ Simplified Error Handling

**Before:**
```swift
do {
    let result = try await client.getTrackInfo(...)
    await MainActor.run { updateUI(result) }
} catch {
    await MainActor.run { setDefaults() }
}
```

**After:**
```swift
let result = (try? await client.getTrackInfo(...)) ?? defaults
await MainActor.run { updateUI(result) }
```

**Impact:** Simpler, more readable code

#### 6. ✅ Better Naming
- Renamed `fetchLovedState()` → `fetchTrackInfo()` (accurately reflects it fetches both loved AND playcount)

### Results

**Code Reduction:**
- ~114 lines removed (polling, fuzzy matching, StringSimilarity, dead code, simplified error handling)
- 50% fewer API calls (combined loved+playcount)
- Cleaner architecture (stateful clients, no credential passing)

**Performance:**
- ✅ No polling on pause/resume
- ✅ Exact timestamp matching (faster sync)
- ✅ Combined API calls (50% reduction)
- ✅ Works for all services (Last.fm, Libre.fm, ListenBrainz)

**Code Quality:**
- ✅ Stateful clients with internal credentials
- ✅ Service-agnostic views (don't need to know about tokens)
- ✅ Proper ListenBrainz feedback API integration
- ✅ Simpler error handling (try? with nil coalescing)
- ✅ No dead code (removed unused wrapper methods)
- ✅ Better naming (methods named for what they do)

### Files Modified
- `Scroblebler/Views/MainView.swift` - Removed polling
- `Scroblebler/ServiceManager.swift` - Simplified matching
- `Scroblebler/Protocols/ScrobbleClient.swift` - Simplified protocol, removed dead code
- `Scroblebler/Clients/LastFmClient.swift` - Stateful, removed wrappers
- `Scroblebler/Clients/ListenBrainzClient.swift` - Stateful, real implementation, removed wrappers
- `Scroblebler/Components/NowPlaying.swift` - Simplified error handling
- `Scroblebler/Components/HistoryItem.swift` - Simplified error handling, better naming
- `Scroblebler/StringSimilarity.swift` - **DELETED**
- `Scroblebler.xcodeproj/project.pbxproj` - Removed StringSimilarity references

---

## Phase 2: Add NetworkClient ✅ COMPLETED

### What Was Done

#### 1. ✅ Created NetworkClient Utility
- **Created:** `Scroblebler/Utilities/NetworkClient.swift` (38 lines)
- **Features:** Generic retry logic with exponential backoff
- **Configurable:** Supports custom retry strategies via `shouldRetry` closure
- **Clean API:** Simple `executeWithRetry()` function

#### 2. ✅ Updated LastFmClient
- **Replaced:** 15-line `executeRequestWithRetry()` with 8-line version using NetworkClient
- **Added:** Specific retry logic for API error 8 (rate limiting)
- **Lines removed:** 7

#### 3. ✅ Updated ListenBrainzClient
- **Replaced:** 57-line `lookupMBIDFromMapper()` with 37-line version using NetworkClient
- **Simplified:** Removed manual retry loop and delay logic
- **Lines removed:** 20

#### 4. ✅ Updated Xcode Project
- **Updated:** `Scroblebler.xcodeproj/project.pbxproj` to include NetworkClient in Utilities group
- **Added:** File references and build phase entries

### Results

**Code Reduction:**
- ~27 lines removed (from LastFmClient and ListenBrainzClient)
- +38 lines added (NetworkClient utility)
- **Net:** +11 lines

**Code Quality:**
- ✅ DRY principle (Don't Repeat Yourself) - retry logic in one place
- ✅ Reusable utility for future network operations
- ✅ Consistent retry behavior across all clients
- ✅ Better testability (centralized retry logic)
- ✅ Configurable retry strategy per use case

### Files Modified
- `Scroblebler/Utilities/NetworkClient.swift` - **CREATED**
- `Scroblebler/Clients/LastFmClient.swift` - Simplified retry logic
- `Scroblebler/Clients/ListenBrainzClient.swift` - Simplified retry logic
- `Scroblebler.xcodeproj/project.pbxproj` - Added NetworkClient references

---

## Phase 3: Clean Up UI ✅ COMPLETED

### What Was Done

#### 1. ✅ Removed Year Field
- **Deleted:** `year: Int32` from Track model
- **Removed:** Year display from TrackInfo (11 lines)
- **Removed:** Year parameter from all Track initializations (Watcher, ServiceManager, UndoButton, NowPlaying)
- **Updated:** Track description to not include year
- **Lines removed:** 15

#### 2. ✅ Removed URL Fallback Builders
- **Deleted:** `buildArtistURL()`, `buildAlbumURL()`, `buildTrackURL()` methods (37 lines)
- **Simplified:** Direct use of provided URLs with simple fallback to Last.fm homepage
- **Impact:** View layer no longer duplicates client URL building logic
- **Lines removed:** 37

#### 3. ✅ Unified Player Controls
- **Created:** `Scroblebler/Components/PlayerControls.swift` (68 lines)
- **Deleted:** `Scroblebler/Components/PlayControls.swift` (44 lines)
- **Features:**
  - Unified progress bar + playback controls
  - Previous/Play-Pause/Next buttons
  - Time display with progress bar
  - Seek support
- **Note:** Shuffle/repeat buttons attempted but removed (MediaRemote framework can't control these)
- **Lines added:** 68
- **Lines removed:** 44

#### 4. ✅ Updated Xcode Project
- **Updated:** `Scroblebler.xcodeproj/project.pbxproj` to include PlayerControls
- **Added:** File references and build phase entries

### Results

**Code Reduction:**
- ~96 lines removed (52 year/URL fallbacks + 44 PlayControls)
- +68 lines added (PlayerControls)
- **Net:** -28 lines removed

**Code Quality:**
- ✅ Removed unused year field (always 0)
- ✅ Eliminated duplicate URL building logic
- ✅ Unified player controls in single component
- ✅ Cleaner separation of concerns

### Files Modified
- `Scroblebler/Models.swift` - Removed year field
- `Scroblebler/Watcher.swift` - Removed year parameter
- `Scroblebler/ServiceManager.swift` - Removed year parameter
- `Scroblebler/Components/UndoButton.swift` - Removed year parameter
- `Scroblebler/Components/TrackInfo.swift` - Removed year display and URL fallbacks
- `Scroblebler/Components/NowPlaying.swift` - Removed year parameter, uses PlayerControls
- `Scroblebler/Components/PlayerControls.swift` - **CREATED**
- `Scroblebler/Components/PlayControls.swift` - **DELETED**
- `Scroblebler.xcodeproj/project.pbxproj` - Added PlayerControls, removed PlayControls

---

## Phase 4: Simplify Sync Logic (TODO)

### Goal
Simplify `enrichTracksWithOtherServices` (99 lines → ~70 lines)

**Simplifications after exact matching:**
- Remove arbitrary 5-minute buffer
- Use exact timestamp matching (much simpler)
- Clean up dual query strategy
- Better logging

**Lines:** -30

---

## Summary

### Phase 1 (Completed)
- ✅ **~114 lines removed**
- ✅ **50% fewer API calls**
- ✅ **Cleaner architecture**
- ✅ **Better performance**

### Phase 2 (Completed)
- ✅ **~27 lines removed** (duplicate retry logic)
- ✅ **+38 lines added** (NetworkClient utility)
- ✅ **Net: +11 lines**
- ✅ **Better code reuse and maintainability**

### Phase 3 (Completed)
- ✅ **~96 lines removed** (52 year/URL fallbacks + 44 PlayControls)
- ✅ **+68 lines added** (PlayerControls)
- ✅ **Net: -28 lines**
- ✅ **Better UI organization, unified controls**

### Remaining Phases (TODO)
- Phase 4: -30 lines (simplify sync)

### Total So Far (Phases 1-3 Completed)
- **~237 lines removed** (114 + 27 + 96)
- **+106 lines added** (38 NetworkClient + 68 PlayerControls)
- **Net: ~131 lines reduction**
- **Plus:** Significantly better code quality, cleaner architecture

### Total Expected (After All Phases)
- **~267 lines removed** (114 + 27 + 96 + 30)
- **+106 lines added** (38 NetworkClient + 68 PlayerControls)
- **Net: ~161 lines reduction + significantly better code quality**
