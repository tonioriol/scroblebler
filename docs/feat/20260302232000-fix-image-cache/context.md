---
title: "Fix image cache - disk persistence, negative caching, Last.fm fallback"
status: done
tags: [cache, cover-art, images, last-fm, performance]
created: 2026-03-02
---
# Fix image cache - disk persistence, negative caching, Last.fm fallback

## TASK

Fix broken image caching: images reload on every scroll because the cache is in-memory only with a 100-entry LRU limit. Many tracks never get cover art because CoverArtArchive has ~30% failure rate and there's no fallback. Add disk-backed caching, negative caching for 404s, and Last.fm album.getinfo as fallback image source.

## GENERAL CONTEXT

Refer to `AGENTS.md` for project structure description.

### REPO

scroblebler

### RELEVANT FILES

* Scroblebler/ImageCache.swift
* Scroblebler/Components/AlbumArtwork.swift
* Scroblebler/Components/TrackInfo.swift
* Scroblebler/Utilities/CoverArt.swift
* Scroblebler/Views/MainView.swift

## PLAN

- ✅ Analyze current image caching implementation
- ✅ Test CoverArtArchive and Last.fm hit rates with real DB data
- ✅ Implement disk-persistent ImageCache with in-memory + disk layers
- ✅ Add thread-safe negative caching (NSLock-protected Set<String>) for 404 URLs
- ✅ Add Last.fm album.getinfo + track.getinfo fallbacks in CoverArt utility
- ✅ Rewrite AlbumArtwork to read from cache in computed property (no @State for image data)
- ✅ Update all callers (TrackInfo passes artist/album/trackName, MainView preloadImages tries Last.fm)
- ✅ Build succeeds, images survive scroll and app restart

## EVENT LOG

* **2026-03-02 - Analyzed image cache problems**
  * Why: Images reload on scroll, many tracks show no cover art
  * How: Read ImageCache.swift (100-entry in-memory LRU dict), AlbumArtwork.swift (re-fetches on every onAppear), CoverArt.swift, Listen model
  * Key findings:
    * 175,608 listens total: 90.2% have release_mbid, 0.1% have imageUrl, 9.8% have no art source
    * CoverArtArchive: 70% hit, 24% 404, 6% timeout for MBIDs we have
    * Last.fm album.getinfo: recovers 83% of CAA-404s
    * No negative caching → 404s retried on every scroll
    * No disk cache → all images lost on app restart

* **2026-03-02 - Multiple iterations to fix scroll reload**
  * Why: SwiftUI LazyVStack destroys/recreates views on scroll, resetting @State
  * Iteration 1: Replaced with URLSession+URLCache → failed because CoverArtArchive 302 redirects break URLCache.cachedResponse lookup by original URL
  * Iteration 2: Added NSCache → auto-evicts under memory pressure with 175k listens
  * Iteration 3: Plain `[String: Data]` dictionary + pre-populate @State in init() → @State(initialValue:) only used on first identity creation, ignored on scroll-back
  * Iteration 4 (final): Removed @State for image data entirely. `resolvedImage` computed property reads directly from `ImageCache.shared.get()`. Only a `@State loadTrigger` bool toggles to force re-render after async load completes. Cache hits are synchronous — no async needed on scroll-back.

* **2026-03-02 - Added Last.fm fallback chain**
  * Why: ~30% of CoverArtArchive lookups return 404, plus ~10% of tracks have no releaseMbid at all
  * How: CoverArt.swift now has `lastFmImageUrl(artist:album:)` (album.getinfo) and `lastFmTrackImageUrl(artist:track:)` (track.getinfo) as fallbacks. AlbumArtwork chains: CAA → album.getinfo → track.getinfo. When fallback succeeds, data is cached under BOTH the fallback key AND the original URL for instant init() lookup.

* **2026-03-02 - Updated preloadImages in MainView**
  * Why: Preloading only tried CAA, skipped tracks without releaseMbid
  * How: preloadImages now tries Last.fm fallback when CAA 404s, and also preloads tracks without releaseMbid via Last.fm directly

* **2026-03-03 - Added disk persistence to ImageCache**
  * Why: In-memory cache lost on app restart, all images had to re-download
  * How: ImageCache.swift now writes cached images to `~/Library/Application Support/Scroblebler/ImageCache/` as SHA256-hashed filenames. On cache miss, checks disk before network. Disk writes happen on background DispatchQueue. In-memory dict serves as L1 cache, disk as L2.

## Next Steps

COMPLETED
