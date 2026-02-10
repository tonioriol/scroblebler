# 26-02-10-22-36-50-refresh-now-playing Refresh now playing state

## TASK

Fix Now Playing getting stuck (stale metadata/artwork/state) when playback changes via Apple Music or when starting playback from history.

## GENERAL CONTEXT

Refer to `/Users/tr0n/Code/scroblebler/AGENTS.md` for project structure description.

ALWAYS use absolute paths.

### REPO

/Users/tr0n/Code/scroblebler

### RELEVANT FILES

* /Users/tr0n/Code/scroblebler/Scroblebler/Watcher.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/ScrobbleManager.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Services/ListenStore.swift

## PLAN

- Ensure track-change detection is robust when players reuse identifiers.
- Ensure artwork updates even if it arrives late.
- Avoid overwriting `playerState` when play/pause is unknown.
- Refresh `ListenStore.currentListen` when metadata changes even if identity did not.
- Run tests.
- Commit separately.

## EVENT LOG

* **2026-02-10 - Investigated Now Playing staying stale**
  * Reproduced cases where MediaRemote delivered partial/late updates (especially when starting playback via scripting/history) and UI kept showing previous listen.
  * Identified reliance on identifiers that can be stable across transitions, and logic that only refreshed artwork/state under narrow conditions.

* **2026-02-10 - Improved watcher refresh behavior**
  * Switched to composite identity to detect changes when IDs are reused.
  * Updated artwork logic to accept new artwork whenever it arrives (late artwork).
  * Kept `playerState` stable when play/pause is unknown.
  * Proactively refreshed `currentListen` when metadata/bundle changes.
  * Tests: `swift test -q`
  * Commit: `b49661c fix: refresh now playing state`

## Next Steps

COMPLETED

