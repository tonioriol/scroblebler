import Foundation

/// Manages playcount caching for ListenBrainz with background fetching and disk persistence
final class ListenBrainzCache {
    // MARK: - State
    
    private struct CacheState {
        var playCountCache: [String: [String: Int]] = [:] // username -> [artist|track -> count]
        var cacheExpiry: [String: Date] = [:]
    }
    
    private let cacheState = Locked(CacheState())
    private let cacheValidityDuration: TimeInterval = 3600 // 1 hour
    private var backgroundFetchTasks: [String: Task<Void, Never>] = [:]
    
    private let baseURL = URL(string: "https://api.listenbrainz.org/1/")!
    
    // MARK: - Public API
    
    func getCachedPlayCount(username: String, artist: String, track: String) -> Int? {
        let normalizedArtist = normalizeForCache(artist)
        let normalizedTrack = normalizeForCache(track)
        let key = "\(normalizedArtist)|\(normalizedTrack)"
        return cacheState.withLock { state in
            state.playCountCache[username]?[key]
        }
    }
    
    func populatePlayCountCache(username: String) async {
        Logger.debug("ListenBrainz populatePlayCountCache for \(username)", log: Logger.cache)
        
        // Load from disk if available
        if let (cachedCounts, continueFromTs, completedAt) = loadCacheFromDisk(username: username) {
            cacheState.withLock { state in
                state.playCountCache[username] = cachedCounts
                state.cacheExpiry[username] = Date().addingTimeInterval(cacheValidityDuration)
            }
            Logger.info("Loaded \(cachedCounts.count) tracks from disk", log: Logger.cache)
            
            if let continueFrom = continueFromTs {
                Logger.info("Incomplete fetch - resuming from timestamp \(continueFrom)", log: Logger.cache)
                startBackgroundCacheFetch(username: username, continueFrom: continueFrom)
            } else if let completedAt = completedAt {
                let age = Date().timeIntervalSince1970 - completedAt
                if age > 300 { // 5 minutes
                    let minTs = Int(completedAt) + 1
                    Logger.info("Cache is \(Int(age/60))min old - triggering incremental update", log: Logger.cache)
                    startIncrementalUpdate(username: username, since: minTs)
                }
            }
            return
        }
        
        // Check if in-memory cache is still valid
        let isCacheValid = cacheState.withLock { state in
            if let expiry = state.cacheExpiry[username], Date() < expiry {
                let count = state.playCountCache[username]?.count ?? 0
                Logger.debug("Cache still valid, skipping fetch. Entries: \(count)", log: Logger.cache)
                return true
            }
            return false
        }
        
        if isCacheValid { return }
        
        // Start fresh background fetch
        Logger.debug("Starting fresh cache fetch from beginning", log: Logger.cache)
        startBackgroundCacheFetch(username: username, continueFrom: nil)
    }
    
    func invalidateCache(username: String) {
        Logger.info("Invalidating cache for \(username)", log: Logger.cache)
        
        // Cancel any ongoing background tasks
        backgroundFetchTasks[username]?.cancel()
        backgroundFetchTasks.removeValue(forKey: username)
        
        // Clear in-memory cache
        cacheState.withLock { state in
            state.playCountCache.removeValue(forKey: username)
            state.cacheExpiry.removeValue(forKey: username)
        }
        
        // Delete disk cache
        if let filePath = getCacheFilePath(username: username) {
            try? FileManager.default.removeItem(at: filePath)
            Logger.info("Deleted cache file for \(username)", log: Logger.cache)
        }
        
        Logger.info("Cache invalidated for \(username)", log: Logger.cache)
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
        
        var playcounts: [String: Int] = cacheState.withLock { state in
            state.playCountCache[username] ?? [:]
        }
        
        do {
            let listens = try await fetchListensPage(username: username, minTs: since, count: 1000)
            let newCount = addListensToCounts(listens: listens, playcounts: &playcounts)
            Logger.info("Added \(newCount) new listens, total: \(playcounts.count)", log: Logger.cache)
            
            cacheState.withLock { state in
                state.playCountCache[username] = playcounts
            }
            
            saveCacheToDisk(username: username, cache: playcounts, continueFromTs: nil, completedAt: Date().timeIntervalSince1970)
            Logger.info("Incremental update complete", log: Logger.cache)
        } catch {
            Logger.error("Incremental update error: \(error)", log: Logger.cache)
        }
        
        backgroundFetchTasks.removeValue(forKey: username)
    }
    
    private func fetchAllPagesInBackground(username: String, continueFrom: Int?) async {
        Logger.info("Background fetch started", log: Logger.cache)
        
        // Start fresh if no continueFrom, otherwise resume from existing cache
        var playcounts: [String: Int]
        if continueFrom == nil {
            playcounts = [:]
            Logger.debug("Starting fresh playcount cache", log: Logger.cache)
        } else {
            playcounts = cacheState.withLock { state in
                state.playCountCache[username] ?? [:]
            }
            Logger.debug("Resuming with \(playcounts.count) existing entries", log: Logger.cache)
        }
        
        var maxTs: Int? = continueFrom
        var totalListens = 0
        var page = 0
        
        while !Task.isCancelled && page < 1000 {
            page += 1
            
            do {
                let listens = try await fetchListensPage(username: username, maxTs: maxTs, count: 1000)
                if listens.isEmpty { break }
                
                totalListens += addListensToCounts(listens: listens, playcounts: &playcounts)
                maxTs = (listens.last?["listened_at"] as? Int)
                
                cacheState.withLock { state in
                    state.playCountCache[username] = playcounts
                }
                
                // Log progress every page
                Logger.debug("Page \(page): \(listens.count) listens, \(playcounts.count) unique tracks", log: Logger.cache)
                
                if page % 5 == 0 {
                    saveCacheToDisk(username: username, cache: playcounts, continueFromTs: maxTs, completedAt: nil)
                    Logger.info("Progress: \(page) pages, \(totalListens) listens, \(playcounts.count) tracks", log: Logger.cache)
                }
                
                try? await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                // Don't log cancellation errors - they're expected when rebuilding cache
                if (error as NSError).code != NSURLErrorCancelled {
                    Logger.error("Error fetching page \(page): \(error)", log: Logger.cache)
                }
                break
            }
        }
        
        // Early exit if cancelled
        guard !Task.isCancelled else {
            Logger.debug("Background fetch cancelled for \(username)", log: Logger.cache)
            backgroundFetchTasks.removeValue(forKey: username)
            return
        }
        
        cacheState.withLock { state in
            state.playCountCache[username] = playcounts
            state.cacheExpiry[username] = Date().addingTimeInterval(cacheValidityDuration)
        }
        
        saveCacheToDisk(username: username, cache: playcounts, continueFromTs: nil, completedAt: Date().timeIntervalSince1970)
        Logger.info("Background fetch complete: \(page) pages, \(totalListens) listens, \(playcounts.count) tracks", log: Logger.cache)
        
        backgroundFetchTasks.removeValue(forKey: username)
    }
    
    // MARK: - API Fetching
    
    private func fetchListensPage(username: String, maxTs: Int? = nil, minTs: Int? = nil, count: Int) async throws -> [[String: Any]] {
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = URLComponents(url: baseURL.appendingPathComponent("user/\(encodedUsername)/listens"), resolvingAgainstBaseURL: false)!
        
        var queryItems = [URLQueryItem(name: "count", value: "\(count)")]
        if let maxTs = maxTs { queryItems.append(URLQueryItem(name: "max_ts", value: "\(maxTs)")) }
        if let minTs = minTs { queryItems.append(URLQueryItem(name: "min_ts", value: "\(minTs)")) }
        components.queryItems = queryItems
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        return payload?["listens"] as? [[String: Any]] ?? []
    }
    
    private func addListensToCounts(listens: [[String: Any]], playcounts: inout [String: Int]) -> Int {
        var count = 0
        for listen in listens {
            guard let metadata = listen["track_metadata"] as? [String: Any],
                  let artist = metadata["artist_name"] as? String,
                  let name = metadata["track_name"] as? String else { continue }
            
            let key = "\(normalizeForCache(artist))|\(normalizeForCache(name))"
            playcounts[key, default: 0] += 1
            count += 1
        }
        return count
    }
    
    // MARK: - Disk Persistence
    
    private func getCacheFilePath(username: String) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("Scroblebler", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("listenbrainz_cache_\(username).json")
    }
    
    private func saveCacheToDisk(username: String, cache: [String: Int], continueFromTs: Int?, completedAt: TimeInterval?) {
        guard let filePath = getCacheFilePath(username: username) else { return }
        
        var cacheData: [String: Any] = [
            "username": username,
            "save_timestamp": Date().timeIntervalSince1970,
            "continue_from_ts": continueFromTs as Any,
            "data": cache
        ]
        if let completedAt = completedAt { cacheData["completed_at"] = completedAt }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: cacheData, options: [.prettyPrinted])
            try data.write(to: filePath)
        } catch {
            Logger.error("Failed to save cache: \(error)", log: Logger.cache)
        }
    }
    
    private func loadCacheFromDisk(username: String) -> ([String: Int], Int?, TimeInterval?)? {
        guard let filePath = getCacheFilePath(username: username),
              FileManager.default.fileExists(atPath: filePath.path),
              let data = try? Data(contentsOf: filePath),
              let cacheData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let saveTimestamp = cacheData["save_timestamp"] as? TimeInterval,
              let cache = cacheData["data"] as? [String: Int] else { return nil }
        
        let age = Date().timeIntervalSince1970 - saveTimestamp
        if age > 604800 { // 7 days
            try? FileManager.default.removeItem(at: filePath)
            return nil
        }
        
        let continueFromTs = cacheData["continue_from_ts"] as? Int
        let completedAt = cacheData["completed_at"] as? TimeInterval
        return (cache, continueFromTs, completedAt)
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

// MARK: - Thread-Safe Lock Helper

fileprivate final class Locked<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    init(_ state: State) {
        self.state = state
    }

    func withLock<R>(_ body: (inout State) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}
