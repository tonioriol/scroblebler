# Bidirectional Sync Implementation

## Overview
Implemented true bidirectional sync that automatically detects and backfills missing tracks across all enabled services. The system is service-agnostic and treats all services equally.

## Architecture

### 1. Data Models (`Models.swift`)

#### SyncStatus Enum
```swift
enum SyncStatus: Codable {
    case unknown      // Sync status not yet determined
    case synced       // Present in all enabled services
    case partial      // Present in some services
    case primaryOnly  // Only in primary service
}
```

#### BackfillTask Struct
```swift
struct BackfillTask {
    let track: RecentTrack
    let targetService: ScrobbleService
    let targetCredentials: ServiceCredentials
    let sourceServices: [ScrobbleService]
    
    var canBackfill: Bool {
        // Age constraints:
        // - Last.fm/Libre.fm: <14 days old
        // - ListenBrainz: no restriction
    }
}
```

### 2. BackfillQueue Actor (`ServiceManager.swift`)

Thread-safe actor that manages the backfill queue:
- Enqueues tasks when gaps are detected
- Processes queue with rate limiting (0.5s between requests)
- Logs success/skip/failure for each backfill attempt
- Respects service-specific age constraints

### 3. Sync Engine (`ServiceManager.enrichTracksWithOtherServices()`)

#### Phase 1: Fetch All Services
- Fetches tracks from ALL enabled services in parallel
- Already implemented infrastructure, no changes needed

#### Phase 2: Match & Detect Gaps (Primary → Secondary)
For each track in primary service:
- Match against each secondary service using existing algorithm
- If NO match found → queue backfill to that secondary service
- If match found → merge serviceInfo as before

#### Phase 3: Reverse Gap Detection (Secondary → Primary)
For each secondary service:
- Find tracks that don't match any primary track
- Queue backfill to primary service if missing

#### Phase 4: Calculate Sync Status
For each track:
- Determine which services have it (from serviceInfo)
- Set syncStatus: `.synced`, `.partial`, or `.primaryOnly`

#### Phase 5: Process Queue Asynchronously
- Process backfill queue in background
- Rate limited to avoid API throttling
- Logs detailed progress

### 4. UI Indicator (`SyncStatusBadge.swift`)

Visual badge component showing sync status:
- 🟢 Checkmark (green) = Synced to all services
- 🟡 Warning (orange) = Partially synced
- 🔴 X mark (red) = Primary only
- ⚫ Question mark (gray) = Unknown

**Tooltip on hover** shows:
```
Synced to All Services

✓ ListenBrainz
✓ Last.fm
✗ Libre.fm
```

## Example Scenario

User has 3 services enabled:
- **ListenBrainz** (primary)
- **Last.fm**
- **Libre.fm**

### Console Output
```
📊 Fetched 20 tracks from primary service ListenBrainz
📊 Fetched 20 tracks from Last.fm
📊 Fetched 20 tracks from Libre.fm

[MATCH] 🔍 Starting matching for Last.fm with 20 candidates
[MATCH] ✓ Matched 'Beck - Profanity Prayers' from primary with Last.fm
[MATCH] ✗ No match found for 'Deftones - Birthmark' in Last.fm

[SYNC] 📥 Queued backfill: 'Deftones - Birthmark' → Last.fm

[SYNC] 🔍 Checking for tracks in Last.fm not in primary
[SYNC] 📥 Track in Last.fm not in primary: 'Old Track - Artist'
[SYNC] 📥 Queued backfill: 'Old Track - Artist' → ListenBrainz

[SYNC] 🔄 Processing 2 backfill tasks...
[SYNC]   ✓ Synced to Last.fm: 'Deftones - Birthmark' (4d old)
[SYNC]   ✓ Synced to ListenBrainz: 'Old Track - Artist' (12d old)
[SYNC] 📊 Complete: 2 succeeded, 0 skipped, 0 failed
```

## Key Features

### ✅ Implemented
- [x] Fetch all enabled services in parallel
- [x] Match tracks bidirectionally
- [x] Detect gaps in all directions (primary ↔ secondary)
- [x] Queue backfill tasks with age validation
- [x] Process queue with rate limiting
- [x] Calculate sync status for UI
- [x] Display sync indicators with tooltips

### 🔒 Safety Features
- Age constraints prevent backfilling very old tracks to Last.fm/Libre.fm
- Rate limiting (0.5s between requests) prevents API throttling
- Actor-based queue ensures thread safety
- Asynchronous processing doesn't block UI

### 📊 Observability
- Detailed logging at every step
- Match success/failure per service
- Queue processing summary
- Backfill success/skip/failure stats

## Configuration

### Service-Specific Age Limits
Defined in `BackfillTask.canBackfill`:
```swift
switch targetService {
case .lastfm, .librefm:
    return daysOld < 14  // 14-day limit
case .listenbrainz:
    return true          // No limit
}
```

### Rate Limiting
Defined in `BackfillQueue.processQueue()`:
```swift
try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
```

## Conflict Resolution

When same track exists in multiple services with different metadata:
- **Track metadata** (artist, name, album) comes from PRIMARY service
- **Service-specific data** (IDs, timestamps, loved status) merged from all services
- **Merge strategy**: `{ (_, new) in new }` = newer value wins

## Future Enhancements

Potential improvements (not currently implemented):
1. User configurable age limits per service
2. Adjustable rate limiting based on service
3. Manual sync trigger in UI
4. Sync history/log viewer
5. Conflict resolution options in settings
6. Batch mode for initial sync of large libraries
