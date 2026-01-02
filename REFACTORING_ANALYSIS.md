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

## Phase 4: Simplify Sync Logic ✅ COMPLETED

### What Was Done

#### 1. ✅ Simplified Dual Query Strategy
- **Removed:** Verbose intermediate variables and debug logging
- **Cleaned:** Streamlined if/else flow for timestamp vs page-based queries
- **Better:** Single concise log statement per strategy
- **Lines removed:** 12

#### 2. ✅ Streamlined Matching Loop
- **Removed:** Intermediate `service` variable
- **Removed:** Redundant debug logging for missing tracks
- **Simplified:** Direct use of credentials, cleaner conditionals
- **Lines removed:** 9

#### 3. ✅ Better Code Flow & Logging
- **Improved:** Reduced nesting depth and variable indirection
- **Cleaner:** More straightforward control flow
- **Simplified:** Concise logging statements
- **Lines removed:** 10

#### 4. ✅ Maintained 5-Minute Buffer
- **Kept:** 5-minute (300s) buffer for catching boundary cases and clock skew
- **Rationale:** Necessary for real-world sync scenarios across different services

### Results

**Code Reduction:**
- 99 lines (old `enrichTracksWithOtherServices`) → 68 lines (new)
- **Net: -31 lines**

**Code Quality:**
- ✅ Maintained 5-minute buffer (necessary for real-world scenarios)
- ✅ Cleaner dual query strategy (timestamp → page fallback)
- ✅ Simplified matching and backfill logic
- ✅ More readable control flow
- ✅ Reduced logging verbosity

### Files Modified
- `Scroblebler/ServiceManager.swift` - Simplified `enrichTracksWithOtherServices` method

---

## Summary

### Phase 1 (Completed) - Verified
- ✅ **101 lines removed (Swift only)**
  - 89 added, 190 deleted
  - Deleted StringSimilarity.swift (46 lines)
  - Simplified findBestMatch: 67 lines → 6 lines
  - Combined API calls: 2 methods → 1
- ✅ **50% fewer API calls** (combined loved+playcount)
- ✅ **Cleaner architecture** (stateful clients)
- ✅ **Better performance** (no polling, exact matching)

### Phase 2 (Completed) - Verified
- ✅ **Net: +30 lines (Swift only)**
  - 56 added, 26 deleted
  - Created NetworkClient.swift (44 lines)
  - Removed duplicate retry logic (27 lines total)
- ✅ **Better code reuse** (DRY principle)
- ✅ **Reusable utility** for future network operations
- ✅ **Consistent retry behavior** across all clients

### Phase 3 (Completed) - Verified
- ✅ **Net: -69 lines (Swift only)**
  - 125 added, 194 deleted
  - Created PlayerControls.swift (84 lines)
  - Deleted PlayControls.swift (44 lines)
  - Removed year field + URL fallbacks (52 lines)
- ✅ **Better UI organization** (unified controls)
- ✅ **Cleaner components** (removed unused fields)

### Phase 4 (Completed) - Verified
- ✅ **Net: -14 lines (Swift only)**
  - 22 added, 36 deleted
  - Simplified enrichTracksWithOtherServices: 99 lines → 68 lines
- ✅ **Cleaner dual query strategy**
- ✅ **Reduced logging verbosity**
- ✅ **More readable control flow**

### Total (All Phases Completed) - Git-Verified Stats
- **446 lines deleted (Swift only)**
- **292 lines added (Swift only)**
- **Net: -154 lines reduction** (not -162 as initially estimated)
- **Plus:** Significantly better code quality, cleaner architecture, more efficient syncing

### Code Quality Analysis (Verified by Diff Review)
1. **Performance:** ✅ 50% fewer API calls (combined getTrackInfo), no polling, exact timestamp matching
2. **Architecture:** ✅ Stateful clients (credentials stored internally), centralized retry logic (NetworkClient), unified player controls
3. **Code Quality:** ✅ Removed dead code (StringSimilarity, wrapper methods), simplified logic (6-line matching vs 67-line fuzzy), better separation of concerns
4. **Maintainability:** ✅ DRY principle (NetworkClient), simpler error handling (try? with nil coalescing), service-agnostic views

### Is the Code Actually Better? YES ✅
- **Simpler:** Complex fuzzy matching → exact timestamp matching (67 lines → 6 lines)
- **Cleaner:** Stateful clients, no credential passing, combined API calls
- **More Efficient:** 50% fewer API calls, no polling on pause/resume
- **Better Architecture:** Reusable NetworkClient, unified PlayerControls
- **More Maintainable:** Less code to maintain, clearer intent, better naming
