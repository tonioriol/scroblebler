# open-player open player

## TASK

Open the source player app when clicking the now-playing album artwork.

## GENERAL CONTEXT

Refer to [`AGENTS.md`](AGENTS.md) for project structure description.

ALWAYS use absolute paths.

### REPO

/Users/tr0n/Code/scroblebler

### RELEVANT FILES

* /Users/tr0n/Code/scroblebler/Scroblebler/Watcher.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Components/TrackInfo.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Components/NowPlaying.swift
* /Users/tr0n/Code/scroblebler/Submodules/mediaremote-adapter/Sources/MediaRemoteAdapter/MediaController.swift

## PLAN

* Ensure `Watcher` exposes the current player `bundleIdentifier` derived from MediaRemote.
* Make the now-playing artwork tap-able in `TrackInfo`.
* On tap, resolve app URL via `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` and activate/open it.
* Run tests (`swift test`).

## EVENT LOG

* **2026-01-17 12:15 - Implemented “open player app on artwork click”**
  * **Why:** users expect the now-playing artwork to be an affordance to jump to the currently-playing app (Music/Spotify/etc), not only to service links (Last.fm/ListenBrainz).
  * **How (data flow):** the MediaRemote payload already includes the player `bundleIdentifier`, but the UI (`TrackInfo`) doesn’t have direct access to it from `Track`.
  * **Change:** stored the active player bundle id on the watcher as `@Published var currentBundleIdentifier: String?` in `/Users/tr0n/Code/scroblebler/Scroblebler/Watcher.swift` so SwiftUI views can react without modifying the `Track` model.
  * **Change:** made the artwork in `/Users/tr0n/Code/scroblebler/Scroblebler/Components/TrackInfo.swift` clickable via `onTapGesture`, resolving the app path with `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` and activating/opening it using `NSWorkspace.shared.openApplication(...)`.
  * **UX detail:** added a tooltip (“Open player”) only when a bundle id is available.

* **2026-01-17 12:34 - Fixed test helpers after Track initializer cleanup**
  * **Problem:** tests were still constructing `Track(...)` with legacy URL parameters (`artistURL/albumURL/trackURL`) that no longer exist on the unified `Track` model.
  * **Fix:** removed those arguments in:
    * `/Users/tr0n/Code/scroblebler/ScrobbleblerTests/WatcherLogicTests.swift`
    * `/Users/tr0n/Code/scroblebler/ScrobbleblerTests/TrackIdentityTests.swift`
    * `/Users/tr0n/Code/scroblebler/ScrobbleblerTests/OperationTests.swift`
    * `/Users/tr0n/Code/scroblebler/ScrobbleblerTests/Infrastructure/TestHelpers.swift`
  * **Verification:** tests passing via `swift test` (run from `/Users/tr0n/Code/scroblebler`).

## Next Steps

- COMPLETED
