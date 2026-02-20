# 26-02-10-22-36-48-coverart-helper Cover art URL helper

## TASK

Centralize Cover Art Archive URL construction and use it consistently in the UI.

## GENERAL CONTEXT

Refer to `/Users/tr0n/Code/scroblebler/AGENTS.md` for project structure description.

ALWAYS use absolute paths.

### REPO

/Users/tr0n/Code/scroblebler

### RELEVANT FILES

* /Users/tr0n/Code/scroblebler/Scroblebler/Utilities/CoverArt.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Components/NowPlaying.swift
* /Users/tr0n/Code/scroblebler/Scroblebler/Components/HistoryItem.swift
* /Users/tr0n/Code/scroblebler/Scroblebler.xcodeproj/project.pbxproj

## PLAN

- Add a small helper for Cover Art Archive front URLs (release MBID → URL).
- Replace inline string concatenation in UI with the helper.
- Add the new Swift file to Xcode project sources.
- Run tests.
- Commit separately.

## EVENT LOG

* **2026-02-10 - Added Cover Art Archive URL helper**
  * Added `/Users/tr0n/Code/scroblebler/Scroblebler/Utilities/CoverArt.swift`.
  * Updated UI to use helper instead of hardcoded `https://coverartarchive.org/...` strings.
  * Updated Xcode project file to include the new source.
  * Tests: `swift test -q`
  * Commit: `b0d9595 feat: add cover art url helper`

## Next Steps

COMPLETED

