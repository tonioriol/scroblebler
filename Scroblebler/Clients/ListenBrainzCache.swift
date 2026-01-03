import Foundation
import GRDB

/// Manages playcount caching for ListenBrainz with background fetching and SQLite persistence
final class ListenBrainzCache {
    // MARK: - State
    
    private let db = LocalDatabase.shared
    private var backgroundFetchTasks: [String: Task<Void, Never>] = [:]
    private let baseURL = URL(string: "https://api.listenbrainz.org/1/")!
    private let rateLimiter = ListenBrainzRateLimiter()
    
    // MARK: - Public API
    
    func getCachedPlayCount(username: String, artist: String, track: String) async -> Int? {
        let normalizedArtist = normalizeForCache(artist)
        let normalizedTrack = normalizeForCache(track)
        
        return try? await db.asyncRead { db in
            try ListenBrainzCacheEntry
                .filter(ListenBrainzCacheEntry.Columns.username == username)
                .filter(ListenBrainzCacheEntry.Columns.artist == normalizedArtist)
                .filter(ListenBrainzCacheEntry.Columns.track == normalizedTrack)
                .fetchOne(db)?
                .playcount
        }
    }
    
    func populatePlayCountCache(username: String) async {
        Logger.debug("ListenBrainz populatePlayCountCache for \(username)", log: Logger.cache)
        
        // Check if we need to resume an incomplete fetch
        if let meta = try? await db.asyncRead({ db in
            try ListenBrainzCacheMeta
                .filter(ListenBrainzCacheMeta.Columns.username == username)
                .fetchOne(db)
        }) {
            let count = try? await db.asyncRead { db in
                try ListenBrainzCacheEntry
                    .filter(ListenBrainzCacheEntry.Columns.username == username)
                    .fetchCount(db)
            }
            Logger.info("Loaded \(count ?? 0) tracks from database", log: Logger.cache)
            
            if let continueFrom = meta.continueFromTs {
                Logger.info("Incomplete fetch - resuming from timestamp \(continueFrom)", log: Logger.cache)
                startBackgroundCacheFetch(username: username, continueFrom: continueFrom)
            } else if let completedAt = meta.completedAt {
                // Check if we need an incremental update
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: completedAt) {
                    let age = Date().timeIntervalSince(date)
                    if age > 300 { // 5 minutes
                        let minTs = Int(date.timeIntervalSince1970) + 1
                        Logger.info("Cache is \(Int(age/60))min old - triggering incremental update", log: Logger.cache)
                        startIncrementalUpdate(username: username, since: minTs)
                    }
                }
            }
            return
        }
        
        // Start fresh background fetch
        Logger.debug("Starting fresh cache fetch from beginning", log: Logger.cache)
        startBackgroundCacheFetch(username: username, continueFrom: nil)
    }
    
    func invalidateCache(username: String) {
        Logger.info("Invalidating cache for \(username)", log: Logger.cache)
        
        // Cancel any ongoing background tasks
        backgroundFetchTasks[username]?.cancel()
        backgroundFetchTasks.removeValue(forKey: username)
        
        // Clear database entries
        Task {
            try? await db.asyncWrite { db in
                try ListenBrainzCacheEntry
                    .filter(ListenBrainzCacheEntry.Columns.username == username)
                    .deleteAll(db)
                try ListenBrainzCacheMeta
                    .filter(ListenBrainzCacheMeta.Columns.username == username)
                    .deleteAll(db)
            }
            Logger.info("Cache invalidated for \(username)", log: Logger.cache)
        }
    }
    
    // MARK: - Background Fetching
    
    private func startBackgroundCacheFetch(username: String, continueFrom: Int?) {
        if let existingTask = backgroundFetchTasks[username], !existingTask.isCancelled {
            Logger.debug("Duplicate prevented: Background task already running for \(username)", log: Logger.cache)
            return
        }
        
        backgroundFetchTasks[username]?.cancel()
        
        Logger.debug("Starting background fetch task", log: Logger.cache)
        let task = Task {
            await fetchAllPagesInBackground(username: username, continueFrom: continueFrom)
        }
        backgroundFetchTasks[username] = task
    }
    
    private func startIncrementalUpdate(username: String, since: Int) {
        if let existingTask = backgroundFetchTasks[username], !existingTask.isCancelled {
            Logger.debug("Duplicate prevented: Background task already running for \(username)", log: Logger.cache)
            return
        }
        
        backgroundFetchTasks[username]?.cancel()
        
        Logger.debug("Starting incremental update task", log: Logger.cache)
        let task = Task {
            await fetchNewListens(username: username, since: since)
        }
        backgroundFetchTasks[username] = task
    }
    
    private func fetchNewListens(username: String, since: Int) async {
        Logger.info("Incremental update started", log: Logger.cache)
        
        do {
            let listens = try await fetchListensPage(username: username, minTs: since, count: 1000)
            
            // Batch insert into database
            let now = Date.nowISO8601()
            let newCount = try await db.asyncWrite { [self] db in
                var count = 0
                for listen in listens {
                    guard let metadata = listen["track_metadata"] as? [String: Any],
                          let artist = metadata["artist_name"] as? String,
                          let name = metadata["track_name"] as? String else { continue }
                    
                    let normalizedArtist = self.normalizeForCache(artist)
                    let normalizedTrack = self.normalizeForCache(name)
                    
                    // Upsert playcount
                    if var existing = try ListenBrainzCacheEntry
                        .filter(ListenBrainzCacheEntry.Columns.username == username)
                        .filter(ListenBrainzCacheEntry.Columns.artist == normalizedArtist)
                        .filter(ListenBrainzCacheEntry.Columns.track == normalizedTrack)
                        .fetchOne(db) {
                        existing.playcount += 1
                        existing.updatedAt = now
                        try existing.update(db)
                    } else {
                        let newEntry = ListenBrainzCacheEntry(
                            id: nil,
                            username: username,
                            artist: normalizedArtist,
                            track: normalizedTrack,
                            playcount: 1,
                            createdAt: now,
                            updatedAt: now
                        )
                        try newEntry.insert(db)
                    }
                    count += 1
                }
                return count
            }
            
            let totalCount = try? await db.asyncRead { db in
                try ListenBrainzCacheEntry
                    .filter(ListenBrainzCacheEntry.Columns.username == username)
                    .fetchCount(db)
            }
            
            Logger.info("Added \(newCount) new listens, total: \(totalCount ?? 0) tracks", log: Logger.cache)
            
            // Update metadata - mark as complete
            try await db.asyncWrite { db in
                if var existing = try ListenBrainzCacheMeta
                    .filter(ListenBrainzCacheMeta.Columns.username == username)
                    .fetchOne(db) {
                    existing.completedAt = now
                    existing.totalTracks = totalCount
                    existing.updatedAt = now
                    try existing.update(db)
                } else {
                    let meta = ListenBrainzCacheMeta(
                        id: nil,
                        username: username,
                        continueFromTs: nil,
                        completedAt: now,
                        totalTracks: totalCount,
                        createdAt: now,
                        updatedAt: now
                    )
                    try meta.insert(db)
                }
            }
            
            Logger.info("Incremental update complete", log: Logger.cache)
        } catch {
            Logger.error("Incremental update error: \(error)", log: Logger.cache)
        }
        
        backgroundFetchTasks.removeValue(forKey: username)
    }
    
    private func fetchAllPagesInBackground(username: String, continueFrom: Int?) async {
        Logger.info("Background fetch started", log: Logger.cache)
        
        var maxTs: Int? = continueFrom
        var totalListens = 0
        var page = 0
        
        while !Task.isCancelled && page < 1000 {
            page += 1
            
            do {
                let listens = try await fetchListensPage(username: username, maxTs: maxTs, count: 1000)
                if listens.isEmpty { break }
                
                // Batch insert into database
                let now = Date.nowISO8601()
                let pageCount = try await db.asyncWrite { [self] db in
                    var count = 0
                    for listen in listens {
                        guard let metadata = listen["track_metadata"] as? [String: Any],
                              let artist = metadata["artist_name"] as? String,
                              let name = metadata["track_name"] as? String else { continue }
                        
                        let normalizedArtist = self.normalizeForCache(artist)
                        let normalizedTrack = self.normalizeForCache(name)
                        
                        // Upsert playcount
                        if var existing = try ListenBrainzCacheEntry
                            .filter(ListenBrainzCacheEntry.Columns.username == username)
                            .filter(ListenBrainzCacheEntry.Columns.artist == normalizedArtist)
                            .filter(ListenBrainzCacheEntry.Columns.track == normalizedTrack)
                            .fetchOne(db) {
                            existing.playcount += 1
                            existing.updatedAt = now
                            try existing.update(db)
                        } else {
                            let newEntry = ListenBrainzCacheEntry(
                                id: nil,
                                username: username,
                                artist: normalizedArtist,
                                track: normalizedTrack,
                                playcount: 1,
                                createdAt: now,
                                updatedAt: now
                            )
                            try newEntry.insert(db)
                        }
                        count += 1
                    }
                    return count
                }
                
                totalListens += pageCount
                maxTs = (listens.last?["listened_at"] as? Int)
                
                // Log progress
                Logger.debug("Page \(page): \(listens.count) listens processed", log: Logger.cache)
                
                // Update metadata every 5 pages
                if page % 5 == 0 {
                    let count = try? await db.asyncRead { db in
                        try ListenBrainzCacheEntry
                            .filter(ListenBrainzCacheEntry.Columns.username == username)
                            .fetchCount(db)
                    }
                    
                    // Save progress to metadata
                    let currentMaxTs = maxTs
                    try? await db.asyncWrite { db in
                        if var existing = try ListenBrainzCacheMeta
                            .filter(ListenBrainzCacheMeta.Columns.username == username)
                            .fetchOne(db) {
                            existing.continueFromTs = currentMaxTs
                            existing.totalTracks = count
                            existing.updatedAt = Date.nowISO8601()
                            try existing.update(db)
                        } else {
                            let meta = ListenBrainzCacheMeta(
                                id: nil,
                                username: username,
                                continueFromTs: currentMaxTs,
                                completedAt: nil,
                                totalTracks: count,
                                createdAt: Date.nowISO8601(),
                                updatedAt: Date.nowISO8601()
                            )
                            try meta.insert(db)
                        }
                    }
                    
                    Logger.info("Progress: \(page) pages, \(totalListens) listens, \(count ?? 0) tracks", log: Logger.cache)
                }
                
                try? await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                if (error as NSError).code != NSURLErrorCancelled {
                    Logger.error("Error fetching page \(page): \(error)", log: Logger.cache)
                }
                break
            }
        }
        
        guard !Task.isCancelled else {
            Logger.debug("Background fetch cancelled for \(username)", log: Logger.cache)
            backgroundFetchTasks.removeValue(forKey: username)
            return
        }
        
        // Mark as complete
        let now = Date.nowISO8601()
        try? await db.asyncWrite { db in
            let totalTracks = try ListenBrainzCacheEntry
                .filter(ListenBrainzCacheEntry.Columns.username == username)
                .fetchCount(db)
            
            // Upsert metadata
            if var existing = try ListenBrainzCacheMeta
                .filter(ListenBrainzCacheMeta.Columns.username == username)
                .fetchOne(db) {
                existing.continueFromTs = nil
                existing.completedAt = now
                existing.totalTracks = totalTracks
                existing.updatedAt = now
                try existing.update(db)
            } else {
                let meta = ListenBrainzCacheMeta(
                    id: nil,
                    username: username,
                    continueFromTs: nil,
                    completedAt: now,
                    totalTracks: totalTracks,
                    createdAt: now,
                    updatedAt: now
                )
                try meta.insert(db)
            }
        }
        
        Logger.info("Background fetch complete: \(page) pages, \(totalListens) listens", log: Logger.cache)
        backgroundFetchTasks.removeValue(forKey: username)
    }
    
    // MARK: - API Fetching
    
    private func fetchListensPage(username: String, maxTs: Int? = nil, minTs: Int? = nil, count: Int) async throws -> [[String: Any]] {
        // Wait for rate limiter
        await rateLimiter.waitIfNeeded()
        
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = URLComponents(url: baseURL.appendingPathComponent("user/\(encodedUsername)/listens"), resolvingAgainstBaseURL: false)!
        
        var queryItems = [URLQueryItem(name: "count", value: "\(count)")]
        if let maxTs = maxTs { queryItems.append(URLQueryItem(name: "max_ts", value: "\(maxTs)")) }
        if let minTs = minTs { queryItems.append(URLQueryItem(name: "min_ts", value: "\(minTs)")) }
        components.queryItems = queryItems
        
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        
        // Update rate limiter from response headers
        if let httpResponse = response as? HTTPURLResponse {
            await rateLimiter.updateFromHeaders(httpResponse)
            
            // Handle rate limit exceeded
            if httpResponse.statusCode == 429 {
                Logger.error("Rate limit exceeded (429), backing off", log: Logger.network)
                await rateLimiter.handle429Response(httpResponse)
                // Retry once after backoff
                return try await fetchListensPage(username: username, maxTs: maxTs, minTs: minTs, count: count)
            }
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        return payload?["listens"] as? [[String: Any]] ?? []
    }
    
    // MARK: - Helpers
    
    private func normalizeForCache(_ text: String) -> String {
        return text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{200E}", with: "")
            .replacingOccurrences(of: "\u{200F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
