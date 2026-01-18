# Local-First Sync Engine

## TASK

Implement a local-first sync engine with the following requirements:

1. Rename `Track` entity/store/services to `Listen` (proper semantic naming)
2. Add `Listen` SQLite persistence with sync status per service
3. Create unified `ListenStore` backed by SQLite
4. Build sync engine with optimistic updates and conflict resolution
5. Design simple yet well-architected pipeline

## GENERAL CONTEXT

See AGENTS.md for project structure. Key principles:

- Simple, elegant, NEVER overengineer
- Straightforward implementation readable sequentially
- Best long-term maintainable clean architecture

ALWAYS use absolute paths.

### REPO

/Users/tr0n/Code/scroblebler

### RELEVANT FILES

**Current Entity/Store/Service (to rename):**

- /Users/tr0n/Code/scroblebler/Scroblebler/Models/Track.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Services/TrackStore.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Services/TrackService.swift

**Database & Storage:**

- /Users/tr0n/Code/scroblebler/Scroblebler/Storage/LocalDatabase.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Storage/OfflineQueue.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Storage/Models/QueuedOperation.swift

**Sync & Service Layer:**

- /Users/tr0n/Code/scroblebler/Scroblebler/Services/SyncService.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/ScrobbleManager.swift

**Supporting Files:**

- /Users/tr0n/Code/scroblebler/Scroblebler/Models.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Watcher.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Utilities/TrackIdentity.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Utilities/TrackMatcher.swift

**Files to Remove (Phase 6):**

- /Users/tr0n/Code/scroblebler/Scroblebler/Storage/Models/ListenBrainzCacheEntry.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Storage/Models/ListenBrainzCacheMeta.swift
- /Users/tr0n/Code/scroblebler/Scroblebler/Clients/ListenBrainzCache.swift

**Project Config:**

- /Users/tr0n/Code/scroblebler/Scroblebler.xcodeproj/project.pbxproj

## PLAN

See detailed plan: [plan.md](./plan.md)

**Key Decisions:**

- Listen entity with per-service sync state in JSON `services` column
- Playcount computed via COUNT(*) - eliminates ListenBrainz cache
- OfflineQueue simplified - scrobbles use Listen.services state
- Cover art via release_mbid → Cover Art Archive (service-agnostic)
- Conflict resolution: local wins for scrobbles, remote wins for love state
- Service links: mainServicePreference determines link targets

## EVENT LOG

- **initial analysis:** Deep analysis of current architecture completed
- **architecture complete:** Full plan with data models, sync engine, conflict resolution, and migration phases
