---
title: "Fix history pagination limited to ~1 month and UI jumping at boundary"
status: active
tags: [history, pagination, swiftui, backfill, ui]
created: 2026-03-03
---
# Fix history pagination limited to ~1 month and UI jumping at boundary

## TASK

Two related bugs in the history view:
1. History only shows up to ~1 month of data, even though APIs have more
2. When reaching the end of loaded history, the UI jumps erratically

## GENERAL CONTEXT

macOS menu bar scrobbler app (SwiftUI). History is stored in SQLite (via GRDB), fetched from remote services (Last.fm, ListenBrainz) via background backfill, and displayed in a paginated ScrollView.

### RELEVANT FILES

* Scroblebler/Views/MainView.swift
* Scroblebler/Services/ListenStore.swift
* Scroblebler/Defaults.swift

## PLAN

- ✅ Analyze history pagination flow
- ✅ Identify root causes
- ✅ Fix 1: Replace one-shot backfill guard with `historyBackfillComplete` flag
- ✅ Fix 2: Fix backfill trigger condition (count-based edge detection instead of broken `totalListens <= visibleCount`)
- ✅ Fix 3: Eliminate double `setHistory` in `loadMoreTracks` — single atomic refresh with trim
- ✅ Fix 4: Set `isLoadingMore` synchronously before async Task to prevent re-entrant onAppear
- ✅ Fix 5: Skip `setHistory` when ID sequence unchanged to avoid unnecessary SwiftUI diffs
- ✅ Build verification
- ✅ Fix 6: Defer `isLoadingMore` reset via `DispatchQueue.main.async` to break cascade loop
- ⬜ Manual testing — verify deep history scrolling and no UI jumping

## EVENT LOG

* **2026-03-03 12:00 - Root cause analysis completed**
  * Why: User reported history limited to ~1 month and UI jumping at boundary
  * How: Traced pagination flow through MainView.swift → ListenStore.swift → Defaults.swift
  * Key info: Two root causes for 1-month limit:
    1. `startHistoryBackfillIfNeeded()` line 508 had `guard defaults.historyBackfillLastSuccessAt == nil` — once backfill runs once (even partially), it never runs again
    2. `startBackfillIfNeeded()` line 846 had `guard totalListens <= visibleCount` — broken when `maxVisibleHistoryItems=400` caps visible count while totalListens grows
  * Key info: Three root causes for UI jumping:
    1. `loadMoreTracks()` called `setHistory` twice per pagination (refresh + trim) causing two SwiftUI layout passes
    2. `isLoadingMore` was set inside async Task, allowing re-entrant `onAppear` triggers
    3. `setHistory` always replaced the array even when data unchanged, triggering unnecessary diffs

* **2026-03-03 12:00 - Applied 5 fixes across 3 files**
  * Why: All identified root causes needed fixing
  * How:
    * `ListenStore.swift`: Added ID-sequence check in `setHistory()` to skip when unchanged; added `oldestTimestamp()` query helper
    * `Defaults.swift`: Added `historyBackfillComplete` boolean key (replaces broken `historyBackfillLastSuccessAt` guard)
    * `MainView.swift`:
      * `startHistoryBackfillIfNeeded()` — changed guard from `historyBackfillLastSuccessAt == nil` to `!historyBackfillComplete`
      * `backfillAllHistory()` — sets `historyBackfillComplete = true` only when `fetchedCount < limitPerPage` (truly exhausted)
      * `loadMoreTracks()` — uses `min(nextPage * uiPageSize, maxVisibleHistoryItems)` as limit (single setHistory); sets `isLoadingMore = true` synchronously before Task
      * `startBackfillIfNeeded()` — replaced broken `totalListens <= visibleCount` with edge detection: `visibleCount >= totalListens || totalListens - visibleCount < uiPageSize`
  * Key info: Build succeeded, test scheme not configured

* **2026-03-03 13:10 - Fixed cascade infinite-loading bug in loadMoreTracks**
  * Why: `trimHistoryFront()` removes old items from the SwiftUI list, causing the new last item's `onAppear` to fire immediately. If `isLoadingMore` is already reset to `false` by that point, the `onAppear` handler calls `loadMoreTracks()` again → trim → onAppear → infinite loop
  * How: Deferred `isLoadingMore = false` by one run-loop cycle using `DispatchQueue.main.async` inside the `MainActor.run` block. The trim-induced `onAppear` fires during the same render pass and sees `isLoadingMore == true`, blocking re-entry. Only after the render settles does the flag clear on the next run-loop tick.
  * Key info: Change at `Scroblebler/Views/MainView.swift` line ~760. Build succeeded.

- **2026-03-03T14:21Z – Simplify: extract visibility filter, remove redundant MainActor.run, trim stale comments**
  * Extracted duplicate imperative visibility filter loop into `isVisible(_:enabledKeys:)` private helper using `contains` — used by both `getRecentVisible()` and `search()` in `ListenStore.swift`.
  * Removed redundant `await MainActor.run {}` wrappers in `refreshHistory()` and `loadMoreHistory()` — the class is already `@MainActor` so all methods run on MainActor.
  * Simplified `loadMoreHistory()` dedup filter to a single-line closure with early `guard`.
  * Replaced 10-line stale doc comment on `loadMoreTracks()` (referencing old API fetchedCount approach) with a single-line summary — pagination now uses SQLite offsets, not API counts.
  * Build succeeded.

## Next Steps

- [ ] Manual testing: verify scrolling past 1 month loads older history
- [ ] Manual testing: verify no UI jumping at pagination boundary
- [ ] Reset `historyBackfillLastSuccessAt` in existing installs (old flag may block new logic)
