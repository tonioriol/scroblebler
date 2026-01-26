# [fix-history-stable-row-ids] Fix history view blank gaps

## TASK

Fix intermittent large whitespace/gaps between items in the History (Recently Scrobbled) list.

## GENERAL CONTEXT

[Refer to AGENTS.md for project structure description]

ALWAYS use absolute paths.

### REPO

/Users/tr0n/Code/scroblebler

### RELEVANT FILES

* /Users/tr0n/Code/scroblebler/Scroblebler/Views/MainView.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Models/Listen.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Components/TrackInfo.swift

## PLAN

- Confirm the gaps are caused by SwiftUI list diffing/layout (repro with scrolling + background refresh).
- Ensure History list rows use a stable, unique identity for `ForEach`.
- Avoid unconstrained vertical expanders (e.g., `Spacer`) inside row layouts under `ScrollView`/`LazyVStack`.
- Build and manually verify the history list no longer shows missing rows/large whitespace.

## EVENT LOG

* **2026-01-26 - Investigated history whitespace artifacts and fixed SwiftUI diffing instability**
  * Symptom: History list would intermittently show large blank gaps between rows (appearing like missing items), especially after refresh/pagination/backfill.
  * Initial hypothesis: row layout was expanding vertically due to an unconstrained spacer inside a row rendered within a `ScrollView` + `LazyVStack`.
    * Change: removed `Spacer(minLength: 0)` inside the history row’s right-side column so the row can’t claim extra vertical space.
    * File: `/Users/tr0n/Code/scroblebler/Scroblebler/Components/TrackInfo.swift`
  * Root cause: unstable/duplicate identity for SwiftUI `ForEach`.
    * Evidence: History `ForEach` used `id: \.element.id`, but `Listen.id` is an optional `Int64?` and can be `nil`/non-stable during refresh/merge paths, which breaks SwiftUI diffing and can manifest as “holes” in `LazyVStack`.
    * Fix: introduced deterministic `Listen.historyIdentity` derived from `listenedAt` + `canonicalKey`, ensuring a stable unique ID for list rendering.
    * Updated history list to use `id: \.element.historyIdentity`.
    * Files:
      * `/Users/tr0n/Code/scroblebler/Scroblebler/Models/Listen.swift`
      * `/Users/tr0n/Code/scroblebler/Scroblebler/Views/MainView.swift`
  * Build validation:
    * Ran: `xcodebuild -project Scroblebler.xcodeproj -scheme Scroblebler -destination 'platform=macOS' build`
    * Result: BUILD SUCCEEDED.

## Next Steps

- [ ] Manual verification: scroll history while background refresh/backfill runs; confirm no blank gaps remain.
- [ ] If gaps persist, add temporary logging for duplicate `historyIdentity` values (likely collisions on same-second `listenedAt`) and adjust identity to include an additional discriminator (e.g., DB `id` when present).
