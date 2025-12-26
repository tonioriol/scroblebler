import Foundation

/// Manages playcount caching for ListenBrainz with background fetching and disk persistence
final class ListenBrainzCache {
    // MARK: - State
    
    private struct CacheState {
        var playCountCache: [String: [String: Int]] = [:] // username -> [artist|track -> count]
        var cacheExpiry: [String: Date] = [:]
        var paginationState: [String: Int] = [:] // username -> last timestamp for pagination
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
        
        let (count, cache) = cacheState.withLock { state in
            (state.playCountCache[username]?[key], state.playCountCache[username])
        }
        
        if count == nil && cache != nil {
            let similarKeys = cache?.keys.filter { cacheKey in
                cacheKey.contains(normalizedArtist.prefix(10)) || cacheKey.contains(normalizedTrack.prefix(10))
            }.prefix(3)
            
            if let similar = similarKeys, !similar.isEmpty {
                print("🎵 [ListenBrainz] No match for '\(key)', similar keys: \(similar.joined(separator: ", "))")
            } else {
                print("🎵 [ListenBrainz] No match for '\(key)' and no similar keys found")
            }
        } else if count != nil {
            print("🎵 [ListenBrainz] Found playcount for '\(key)': \(count ?? 0)")
        }
        
        return count
    }
    
    func populatePlayCountCache(username: String, getTopTracks: @escaping (String, String, Int, Int) async throws -> [TopTrack]) async throws {
        print("🎵 [ListenBrainz] ========== populatePlayCountCache TRIGGERED ==========")
        print("🎵 [ListenBrainz] Username: \(username)")
        
        // Try to load from disk first
        if let (cachedCounts, continueFromTs, completedAt) = loadCacheFromDisk(username: username) {
            cacheState.withLock { state in
                state.playCountCache[username] = cachedCounts
                state.cacheExpiry[username] = Date().addingTimeInterval(cacheValidityDuration)
            }
            print("🎵 [ListenBrainz] ✅ Loaded \(cachedCounts.count) tracks from disk")
            
            if let continueFrom = continueFromTs {
                print("🎵 [ListenBrainz] ⚠️ INCOMPLETE FETCH - will resume from timestamp \(continueFrom)")
                startBackgroundCacheFetch(username: username, continueFrom: continueFrom)
            } else if let completedAt = completedAt {
                let age = Date().timeIntervalSince1970 - completedAt
                if age > 300 { // 5 minutes
                    let minTs = Int(completedAt) + 1
                    print("🎵 [ListenBrainz] 🔄 Cache is \(Int(age/60))min old (>5min threshold)")
                    print("🎵 [ListenBrainz] 🚀 AUTO-TRIGGERING incremental update from timestamp \(minTs)")
                    startIncrementalUpdate(username: username, since: minTs)
                } else {
                    print("🎵 [ListenBrainz] ✅ Cache is FRESH (\(Int(age))s old, <5min threshold)")
                }
            } else {
                print("🎵 [ListenBrainz] ✅ Cache is COMPLETE (all history fetched)")
            }
            return
        }
        
        print("🎵 [ListenBrainz] No cache on disk, will fetch from beginning")
        
        let isCacheValid = cacheState.withLock { state in
            if let expiry = state.cacheExpiry[username], Date() < expiry {
                let count = state.playCountCache[username]?.count ?? 0
                print("🎵 [ListenBrainz] Cache still valid, skipping fetch. Entries: \(count)")
                return true
            }
            return false
        }
        
        if isCacheValid { return }
        
        // Fetch first page quickly for immediate use
        print("🎵 [ListenBrainz] Fetching first page (1000 tracks) for immediate use...")
        let firstPage = try await getTopTracks(username, "all_time", 1000, 0)
        
        var cache: [String: Int] = [:]
        for track in firstPage {
            let key = "\(normalizeForCache(track.artist))|\(normalizeForCache(track.name))"
            cache[key] = track.playcount
        }
        
        cacheState.withLock { state in
            state.playCountCache[username] = cache
            state.cacheExpiry[username] = Date().addingTimeInterval(cacheValidityDuration)
        }
        print("🎵 [ListenBrainz] Initial cache populated with \(cache.count) entries")
        
        startBackgroundCacheFetch(username: username, continueFrom: nil)
    }
    
    // MARK: - Background Fetching
    
    private func startBackgroundCacheFetch(username: String, continueFrom: Int?) {
        if let existingTask = backgroundFetchTasks[username], !existingTask.isCancelled {
            print("⏸️ [ListenBrainz] ⚠️ DUPLICATE PREVENTED: Background task already running for \(username)")
            return
        }
        
        backgroundFetchTasks[username]?.cancel()
        
        print("🎵 [ListenBrainz] 🚀 Starting background fetch task")
        let task = Task {
            await fetchAllPagesInBackground(username: username, continueFrom: continueFrom)
        }
        backgroundFetchTasks[username] = task
    }
    
    private func startIncrementalUpdate(username: String, since: Int) {
        if let existingTask = backgroundFetchTasks[username], !existingTask.isCancelled {
            print("⏸️ [ListenBrainz] ⚠️ DUPLICATE PREVENTED: Background task already running for \(username)")
            return
        }
        
        backgroundFetchTasks[username]?.cancel()
        
        print("🎵 [ListenBrainz] 🚀 Starting incremental update task")
        let task = Task {
            await fetchNewListens(username: username, since: since)
        }
        backgroundFetchTasks[username] = task
    }
    
    private func fetchNewListens(username: String, since: Int) async {
        print("🎵 [ListenBrainz] ========== INCREMENTAL UPDATE STARTED ==========")
        
        var playcounts: [String: Int] = cacheState.withLock { state in
            state.playCountCache[username] ?? [:]
        }
        
        do {
            let listens = try await fetchListensPage(username: username, minTs: since, count: 1000)
            print("🎵 [ListenBrainz] Found \(listens.count) new listens")
            
            let newCount = addListensToCounts(listens: listens, playcounts: &playcounts)
            print("🎵 [ListenBrainz] Added \(newCount) new listens, total: \(playcounts.count)")
            
            cacheState.withLock { state in
                state.playCountCache[username] = playcounts
            }
            
            saveCacheToDisk(username: username, cache: playcounts, continueFromTs: nil, completedAt: Date().timeIntervalSince1970)
            print("🎵 [ListenBrainz] ✅ Incremental update complete")
        } catch {
            print("⚠️ [ListenBrainz] Error: \(error)")
        }
        
        backgroundFetchTasks.removeValue(forKey: username)
    }
    
    private func fetchAllPagesInBackground(username: String, continueFrom: Int?) async {
        print("🎵 [ListenBrainz] ========== BACKGROUND FETCH STARTED ==========")
        
        var playcounts: [String: Int] = cacheState.withLock { state in
            state.playCountCache[username] ?? [:]
        }
        
        var maxTs: Int? = continueFrom
        var totalListens = 0
        var page = 0
        
        while !Task.isCancelled && page < 100 {
            page += 1
            
            do {
                let listens = try await fetchListensPage(username: username, maxTs: maxTs, count: 1000)
                if listens.isEmpty { break }
                
                totalListens += addListensToCounts(listens: listens, playcounts: &playcounts)
                maxTs = (listens.last?["listened_at"] as? Int)
                
                cacheState.withLock { state in
                    state.playCountCache[username] = playcounts
                }
                
                if page % 5 == 0 {
                    saveCacheToDisk(username: username, cache: playcounts, continueFromTs: maxTs, completedAt: nil)
                }
                
                try? await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                print("⚠️ [ListenBrainz] Error page \(page): \(error)")
                break
            }
        }
        
        cacheState.withLock { state in
            state.playCountCache[username] = playcounts
            state.cacheExpiry[username] = Date().addingTimeInterval(cacheValidityDuration)
        }
        
        saveCacheToDisk(username: username, cache: playcounts, continueFromTs: nil, completedAt: Date().timeIntervalSince1970)
        print("🎵 [ListenBrainz] ✅ Complete: \(page) pages, \(totalListens) listens, \(playcounts.count) tracks")
        
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
        let dir = appSupport.appendingPathComponent("Audioscrobbler", isDirectory: true)
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
            print("⚠️ [ListenBrainz] Save failed: \(error)")
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
