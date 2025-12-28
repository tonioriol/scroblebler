# Sync Improvements: Native Timestamp-Based Queries for All Services

## Overview
Extended the simplified unidirectional sync mechanism to support **Last.fm and Libre.fm as secondary services** with native timestamp-based queries. All services now support efficient timestamp-based querying!

## Problem Solved
When ListenBrainz was primary and Last.fm/Libre.fm were secondary services, the system fell back to inefficient page-based fetching with a 500-track cap. This caused performance issues on deep pages because it would fetch many irrelevant tracks.

## Solution: Native Timestamp-Based Queries for All Services

### Sync Flow (Unidirectional: Primary → Secondary)
1. **Fetch tracks from PRIMARY service** (e.g., Last.fm page 5)
2. **Extract timestamp range** from primary tracks (oldest → newest)
3. **Query SECONDARY services** using that timestamp range
4. **Match and backfill** missing tracks to secondary services

### Changes Made

#### 1. Last.fm Client (`LastFmClient.swift`)
Added `getRecentTracksByTimeRange()` implementation using **native API parameters**:
- Uses Last.fm's `from` and `to` timestamp parameters
- Queries only the exact time range needed
- Works efficiently on any page depth
- No artificial limits or filtering needed

```swift
func getRecentTracksByTimeRange(username: String, minTs: Int?, maxTs: Int?, limit: Int, token: String?) async throws -> [RecentTrack]? {
    // Use Last.fm's native 'from' and 'to' parameters
    // Query exact timestamp range from PRIMARY service
    // Returns only relevant tracks
}
```

#### 2. Libre.fm Client (`LibreFmClient.swift`)
Added `getRecentTracksByTimeRange()` override:
- Delegates to parent Last.fm implementation (Libre.fm uses same API)
- Updates URLs to Libre.fm-specific endpoints
- Maintains service-specific metadata

## How It Works

### Example: Last.fm Primary, ListenBrainz Secondary (Already Working)
1. Fetch 20 tracks from Last.fm (page 5)
2. Extract timestamp range: `minTs=1000, maxTs=1020`
3. Query ListenBrainz with `min_ts=1000&max_ts=1020` → Gets ~20 relevant tracks
4. Match and backfill missing tracks to ListenBrainz

### Example: ListenBrainz Primary, Last.fm Secondary (Now Working)
1. Fetch 20 tracks from ListenBrainz (page 5)
2. Extract timestamp range: `minTs=1000, maxTs=1020`
3. Query Last.fm with `from=1000&to=1020` → Gets ~20 relevant tracks
4. Match and backfill missing tracks to Last.fm

## Performance Benefits

### Before (Last.fm as Secondary)
- Fetched up to 500 tracks from Last.fm regardless of primary page
- Deep pages: Performance degraded significantly
- Example: Primary page 10 would fetch 500 Last.fm tracks to find ~20 matches

### After (Last.fm as Secondary)
- Queries exact timestamp range using native API parameters
- Consistent performance across all pages
- Example: Primary page 10 queries Last.fm with exact time range → Gets ~20 relevant tracks directly

## Technical Details

### Native Timestamp Query Strategy (Secondary Services)
```
PRIMARY service (any page):
  [Track1(ts:1000), Track2(ts:1010), Track3(ts:1020)]
                     ↓
Extract timestamp range: minTs=1000, maxTs=1020
                     ↓
Query SECONDARY services with this range:
                     ↓
ListenBrainz (secondary): API query with min_ts=1000&max_ts=1020 → Returns matches
Last.fm (secondary): API query with from=1000&to=1020 → Returns matches
Libre.fm (secondary): API query with from=1000&to=1020 → Returns matches
```

### Service Capabilities as Secondary
| Service | Native Timestamp Query | API Parameters |
|---------|----------------------|----------------|
| ListenBrainz | ✅ Yes | `min_ts`, `max_ts` |
| Last.fm | ✅ Yes | `from`, `to` |
| Libre.fm | ✅ Yes | `from`, `to` (same as Last.fm) |

## Code Changes Summary

### Files Modified
1. **`Scroblebler/Clients/LastFmClient.swift`** (+17 lines)
   - Added `getRecentTracksByTimeRange()` method
   - Uses native Last.fm API `from` and `to` parameters
   - Queries exact timestamp range when Last.fm is secondary

2. **`Scroblebler/Clients/LibreFmClient.swift`** (+30 lines)
   - Added `getRecentTracksByTimeRange()` override
   - Delegates to parent Last.fm implementation
   - Updates URLs to Libre.fm-specific endpoints

### Files Already Supporting This
- **`Scroblebler/Protocols/ScrobbleClient.swift`** (no changes needed)
  - Already had optional protocol method
  
- **`Scroblebler/ServiceManager.swift`** (no changes needed)
  - Already uses `getRecentTracksByTimeRange()` for secondary services when available
  - Falls back to page-based for services returning `nil`

- **`Scroblebler/Clients/ListenBrainzClient.swift`** (no changes needed)
  - Already implemented timestamp-based queries for when ListenBrainz is secondary

## Result

✅ **Simplified, elegant, unidirectional sync (Primary → Secondary)** that works efficiently with any service as primary:

| Primary Service | Secondary Services | Status |
|----------------|-------------------|--------|
| ListenBrainz | Last.fm, Libre.fm | ✅ Now efficient (native API) |
| Last.fm | ListenBrainz, Libre.fm | ✅ Already efficient |
| Libre.fm | ListenBrainz, Last.fm | ✅ Already efficient |

**All services now support native timestamp-based queries** with consistent performance across all pages, regardless of depth. No artificial limits, no filtering needed - just direct API queries with the exact time range.
