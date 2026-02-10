# 26-02-10-22-36-49-persist-image-url Persist history image URLs

## TASK

Fix broken history artwork after local-first history by persisting a service-provided image URL fallback in SQLite and preserving it during merges.

## GENERAL CONTEXT

Refer to `/Users/tr0n/Code/scroblebler/AGENTS.md` for project structure description.

ALWAYS use absolute paths.

### REPO

/Users/tr0n/Code/scroblebler

### RELEVANT FILES

* /Users/tr0n/Code/scroblebler/Scroblebler/Models/Listen.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Models.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Storage/LocalDatabase.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Views/MainView.swift

## PLAN

- Add `imageUrl` to the local listen model as a service-provided fallback.
- Add an `image_url` column and migration so existing installs upgrade cleanly.
- Update GRDB encode/decode so SQLite stores/loads the new field.
- Ensure history import/merge keeps the first-known `imageUrl` when MBIDs are missing.
- Run tests.
- Commit separately.

## EVENT LOG

* **2026-02-10 - Investigated broken history artwork after local-history refactor**
  * Confirmed UI now renders from SQLite `Listen` rows, but those rows had no persisted image pointer when `releaseMbid` was missing.
  * Historical behavior used remote `Track.imageUrl` directly; local-first history lost that unless stored.

* **2026-02-10 - Persisted image URL fallback and preserved it on merge**
  * Added `Listen.imageUrl` and ensured it is stored/loaded via GRDB.
  * Added DB migration to add `image_url` column without requiring a reset.
  * Updated history import merge to retain `imageUrl` (first non-nil wins).
  * Tests: `swift test -q`
  * Commit: `9245850 fix: persist history image url`

## Next Steps

COMPLETED

