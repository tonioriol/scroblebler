# 26-02-10-22-36-51-playcount-remove-cache-rebuild Remove cache rebuild + fix playcount

## TASK

Remove obsolete ListenBrainz cache rebuild plumbing and restore working playcount behavior under the local-first model.

## GENERAL CONTEXT

Refer to `/Users/tr0n/Code/scroblebler/AGENTS.md` for project structure description.

ALWAYS use absolute paths.

### REPO

/Users/tr0n/Code/scroblebler

### RELEVANT FILES

* /Users/tr0n/Code/scroblebler/Scroblebler/Clients/ListenBrainzClient.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Views/MainView.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Services/ListenStore.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Components/TrackInfo.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Components/NowPlaying.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Components/HistoryItem.swift

## PLAN

- Remove ListenBrainz cache rebuild UI/methods now that playcount is computed from local listens.
- Restore UI playcount rendering by wiring `ListenStore.playcount()` into Now Playing + History views.
- Verify behavior with tests and manual run.
- Commit in a dedicated change.

## EVENT LOG

* **2026-02-10 - Removed dead cache rebuild hook**
  * Verified `ListenBrainzClient.invalidateAndRebuildCache()` was a no-op after local-first.
  * Removed the dead method to reduce confusion.
  * Tests: `swift test -q`
  * Commit: `2647c81 chore: remove listenbrainz cache rebuild`

* **2026-02-10 - Playcount still broken under local-first**
  * Confirmed UI was rendering `0`/placeholder playcount values rather than querying SQLite counts.
  * Identified needed fix: integrate `/Users/tr0n/Code/scroblebler/Scroblebler/Services/ListenStore.swift` `playcount()` into `/Users/tr0n/Code/scroblebler/Scroblebler/Components/TrackInfo.swift` call sites.

## Next Steps

- [ ] Implement Now Playing playcount display using `ListenStore.playcount()`.
- [ ] Implement History row playcount display using `ListenStore.playcount()`.
- [ ] Add a lightweight caching/debouncing layer if needed to avoid excessive COUNT queries while scrolling.
- [ ] Run `swift test -q` and verify manually.

