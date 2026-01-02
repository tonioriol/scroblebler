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

## Phase 3: Clean Up UI (TODO)

### 3.1 Remove Year Field
**Problem:** `Track.year` is always 0 (MediaRemote doesn't provide it)
- Delete `year: Int32` from Track model
- Remove year display from TrackInfo
- Remove year parameter from Track creation
- **Lines:** -15

### 3.2 Remove URL Fallbacks from TrackInfo
**Problem:** TrackInfo has 37 lines of URL builders that duplicate what clients do
- Clients should ALWAYS provide URLs
- Remove fallback builders from view layer
- **Lines:** -37

### 3.3 Create PlayerControls Component
**Problem:** Progress bar in TrackInfo, controls in separate PlayControls - should be unified
- Create `PlayerControls.swift` with progress bar + buttons
- Add shuffle/repeat buttons (MediaControl already supports them)
- Remove progress bar from TrackInfo
- **Lines:** +38 net (adds shuffle/repeat features)

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

### Remaining Phases (TODO)
- Phase 3: -14 lines (remove year, URL fallbacks) + 38 lines (PlayerControls with shuffle/repeat)
- Phase 4: -30 lines (simplify sync)

### Total Expected (After All Phases)
- **~158 lines removed** (114 + 27 + 44)
- **+76 lines added** (38 NetworkClient + 38 PlayerControls with new features)
- **Net: ~82 lines reduction + significantly better code quality**
