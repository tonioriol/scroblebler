---
title: "Play history item from Apple Music catalog (not in library)"
status: done
tags: [apple-music, applescript, history, musickit, playback]
created: 2026-03-13
---
# Play history item from Apple Music catalog (not in library)

## TASK

When clicking the play button on a history item that was originally played from Apple Music (but not added to the user's library), playback fails silently. The play button shows "Track not found in library" because the AppleScript-based search only looks in the local Music library.

## GENERAL CONTEXT

`HistoryPlay.swift` uses AppleScript to search and play tracks in Apple Music. The `search` command and `every track whose...` queries only operate on the local library — they cannot access the Apple Music catalog.

### RELEVANT FILES

* `Scroblebler/HistoryPlay.swift` — AppleScript-based track playback
* `Scroblebler/Components/HistoryItem.swift` — Play button UI and click handler

## PLAN

1. ✅ Investigate AppleScript `search` command — only searches local library, not catalog
2. ✅ Try `music://` URL scheme — does not work on macOS for catalog search
3. ✅ Try MusicKit `MusicCatalogSearchRequest` + `ApplicationMusicPlayer` — fails because the app's bundle ID is not registered with Apple's Music API Token Service
4. ⬜ Register bundle ID with Apple Developer for MusicKit token (requires Apple Developer portal action)
5. ⬜ Or: Accept limitation and show a better error / open Apple Music search in browser

## EVENT LOG

* **2026-03-13 09:02 - Investigated play button failure for non-library tracks**
  * Why: User reported play button doesn't work for tracks originally from Apple Music catalog
  * How: Read `HistoryPlay.swift` — uses AppleScript `every track whose name is X and artist is Y` which only searches local library
  * Key info: `Scroblebler/HistoryPlay.swift:30` — exact match query, line 46 — fuzzy match by artist

* **2026-03-13 09:36 - Tested AppleScript `search` command**
  * Why: Attempted to add catalog search fallback via AppleScript
  * How: Ran `osascript` with `search "query" for songs` — got error `-1708` ("doesn't understand the search message")
  * Key info: AppleScript's `search` requires `search <playlist> for <term>` syntax — e.g., `search library playlist 1 for "query"` — but this ONLY searches the local library, not the Apple Music catalog

* **2026-03-13 09:36 - Tested `music://` URL scheme**
  * Why: Attempted to open Apple Music search via URL scheme
  * How: Tried `open "music://search?term=..."` and `open "music://music.apple.com/us/search?term=..."` — neither worked on macOS
  * Key info: `music://` URL scheme does not support search on macOS. `https://music.apple.com/search?term=...` opens in browser, not Music.app, and redirects to homepage

* **2026-03-13 09:37 - Implemented MusicKit catalog search fallback**
  * Why: MusicKit's `MusicCatalogSearchRequest` + `ApplicationMusicPlayer` should be the proper way to search and play catalog tracks
  * How: Rewrote `HistoryPlay.swift` to try library first (AppleScript), then fall back to MusicKit catalog search. Added `@available(macOS 14.0, *)` guards.
  * Key info: `MusicCatalogSearchRequest(term:types:)` with `[Song.self]`, then `ApplicationMusicPlayer.shared.queue = [song]; try await player.play()`

* **2026-03-13 10:01 - MusicKit catalog search fails: developer token not registered**
  * Why: MusicKit requires the app's bundle ID to be registered with Apple's Music API Token Service
  * How: Tested with real track — logs showed `MusicAuthorization` succeeded (`.authorized`), but `MusicCatalogSearchRequest.response()` failed
  * Key info: Error from MusicKit: `"Media API Token Service responded with status code: Not Found (404). This suggests that 'com.tonioriol.scroblebler' was likely not registered as a valid client identifier."` — throws `.developerTokenRequestFailed`
  * Root cause: The bundle ID `com.tonioriol.scroblebler` needs to be registered in Apple Developer portal with MusicKit capability enabled for the App ID

* **2026-03-13 10:29 - Reverted all changes**
  * Why: No viable approach works without Apple Developer portal changes
  * How: `git checkout -- Scroblebler/HistoryPlay.swift Scroblebler/Components/HistoryItem.swift`

## Next Steps

- [ ] Register `com.tonioriol.scroblebler` App ID in Apple Developer portal with MusicKit capability enabled — this would allow `MusicCatalogSearchRequest` to work
- [ ] Once registered, re-implement the MusicKit fallback (code was tested and correct, only token registration is missing)
- [ ] Alternative: if registration is not desired, hide the play button for tracks not in the local library, or show a "Search in Apple Music" button that opens `https://music.apple.com/search?term=...` in the default browser
