---
title: "Fix slow startup (10+ seconds to load)"
status: done
tags: [performance, startup, ui]
created: 2026-03-02
---
# Fix slow startup (10+ seconds to load)

## TASK

The app was taking 10+ seconds to show the UI after opening the popover. The root cause was that `loadRecentTracks()` blocked the initial render on network calls (artwork refresh from remote services, history backfill). Additionally, `autoAuthenticateLastFmWebClient()` in AppDelegate blocked `processPending` on a web login flow to last.fm.

## GENERAL CONTEXT

Scroblebler is a macOS menu bar app. History is stored locally in SQLite (local-first architecture). On popover open, `MainView.loadRecentTracks()` reads from SQLite and renders history. However, it also synchronously awaited network calls to refresh artwork metadata and start backfill before the user saw anything.

### RELEVANT FILES

* Scroblebler/Views/MainView.swift
* Scroblebler/AppDelegate.swift
* README.md

## PLAN

- ✅ Investigate startup flow to identify bottlenecks
- ✅ Decouple initial SQLite render from network-dependent artwork refresh and backfill
- ✅ Make Last.fm web auth non-blocking on startup
- ✅ Build and verify

## EVENT LOG

* **2026-03-02 22:54 - Decoupled initial render from network calls in MainView**
  * Why: `loadRecentTracks()` awaited `importAndMergeHistoryPage()` (fetches from all enabled services sequentially, including Last.fm `track.getInfo` enrichment — up to 20 extra API calls) before rendering anything from SQLite.
  * How: Split `loadRecentTracks()` into two phases:
    1. Instant: SQLite read → render → preload cached images (no network)
    2. Background: `backgroundArtworkAndBackfill()` handles artwork metadata refresh and history backfill without blocking the UI
  * File: Scroblebler/Views/MainView.swift

* **2026-03-02 22:55 - Made Last.fm web auth non-blocking on startup**
  * Why: `AppDelegate.applicationDidFinishLaunching` awaited `autoAuthenticateLastFmWebClient()` (network round-trip to last.fm) before scheduling `processPending`. This delayed scrobble retries and sync.
  * How: Moved `scheduleProcessPending` and `startPeriodicSync` to run immediately. Web auth now runs in a separate detached Task. Deletes needing the web client will be retried by the periodic sync (60s timer) once auth completes.
  * File: Scroblebler/AppDelegate.swift

* **2026-03-02 22:55 - Build succeeded, README TODO updated**
  * Marked "Taking 10+ seconds to load" as done in README.md
  * Also marked "Local-first storage + sync engine" as done (was already implemented).

## Next Steps

- COMPLETED
