# Unified Scrobble Actions Feature Spec

## Overview
This feature provides unified controls to **Undo** past scrobbles and **Blacklist** tracks from future scrobbling across all connected services (Last.fm, ListenBrainz, Libre.fm). It ensures consistent behavior regardless of which service is selected as the primary view source.

## Core Features

### 1. Unified History View
*   **Aggregation**: Recent tracks are fetched from **all** enabled services in parallel.
*   **Smart Merging**: Duplicate tracks (matching Artist/Title within 2 minutes) are merged into a single `RecentTrack` entry.
*   **Prioritization**: The track metadata (URLs, images) displayed corresponds to the user's **Main Service Preference**. If the preferred service has the track, it wins; otherwise, it falls back to others.
*   **Service-Awareness**: Each merged track retains a hidden map (`serviceInfo`) containing the specific IDs and timestamps for every service it was found on.

### 2. Scrobble Actions

#### Undo Scrobble
*   **Visual**: `minus.circle` icon (gray).
*   **Behavior**:
    *   Deletes the scrobble from **all** connected services where it exists.
    *   Uses service-specific IDs (e.g., `recording_msid` for ListenBrainz, `timestamp` for Last.fm) retrieved from the merged `serviceInfo`.
    *   **Feedback**: On success, the button turns **Red** (`minus.circle.fill`) and becomes disabled, indicating the "Undone" state.

#### Blacklist Track
*   **Visual**: `nosign` icon (gray -> red when active).
*   **Behavior**:
    *   Toggles the track (Artist + Name) in a local blocklist.
    *   Prevents **future** scrobbles of this song.
    *   Cancels any pending "Now Playing" scrobble for the current track.

## Architecture & Implementation

### Models
*   **`RecentTrack`**: Enhanced to include `serviceInfo: [String: ServiceTrackData]` and `sourceService: ScrobbleService?`.
*   **`ServiceTrackData`**: Stores `timestamp` and `id` (e.g., MSID) for a specific service.

### Service Layer
*   **`ServiceManager.getAllRecentTracks`**:
    *   Fetches from all clients.
    *   Sorts by Date Descending + Preference Priority.
    *   Merges duplicates, prioritizing the Main Service for the base object.
*   **`ServiceManager.deleteScrobbleAll`**:
    *   Fans out delete requests to all enabled services.
    *   Extracts the correct ID/timestamp for each service from the `serviceInfo` map.

### Clients
*   **`LastFmClient` / `LibreFmClient`**: Populates `sourceService` and `serviceInfo` (using `uts`).
*   **`ListenBrainzClient`**: Populates `sourceService` and `serviceInfo` (extracting `recording_msid`).

### UI Components
*   **`UndoButton`**: Handles the delete action and state transition.
*   **`BlacklistButton`**: Handles the local blocklist toggle.
*   **`HistoryItem`**: Displays both buttons for past tracks.
*   **`NowPlaying`**: Displays only the Blacklist button.
