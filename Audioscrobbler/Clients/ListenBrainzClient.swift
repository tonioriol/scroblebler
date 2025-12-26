import Foundation
import SwiftUI

// Helper for thread-safe state access (Backward compatible replacement for OSAllocatedUnfairLock)
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

class ListenBrainzClient: ObservableObject, ScrobbleClient {
    enum Error: Swift.Error {
        case invalidToken
        case serverError(String)
    }
    
    // Cache for recording playcounts
    private struct CacheState {
        var playCountCache: [String: [String: Int]] = [:] // username -> [artist|track -> count]
        var cacheExpiry: [String: Date] = [:]
    }
    
    private let cacheState = Locked(CacheState())
    private let cacheValidityDuration: TimeInterval = 3600 // 1 hour (longer since we're caching more)
    private var backgroundFetchTasks: [String: Task<Void, Never>] = [:]
    
    var baseURL: URL { URL(string: "https://api.listenbrainz.org/1/")! }
    var authURL: String { "https://listenbrainz.org/settings/" }
    var linkColor: Color { Color(hue: 0.08, saturation: 0.80, brightness: 0.85) }
    
    // URL building helpers
    private func artistURL(artist: String, mbid: String?) -> URL {
        if let mbid = mbid {
            return URL(string: "https://listenbrainz.org/artist/\(mbid)/")!
        }
        let encoded = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return URL(string: "https://musicbrainz.org/search?query=artist:%22\(encoded)%22&type=artist&limit=1&method=advanced")!
    }
    
    private func albumURL(artist: String, album: String, mbid: String?) -> URL {
        if let mbid = mbid {
            return URL(string: "https://listenbrainz.org/album/\(mbid)/")!
        }
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let encodedAlbum = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return URL(string: "https://musicbrainz.org/search?query=artist:%22\(encodedArtist)%22%20AND%20release:%22\(encodedAlbum)%22&type=release&limit=1&method=advanced")!
    }
    
    private func trackURL(artist: String, track: String, mbid: String?) -> URL {
        if let mbid = mbid {
            return URL(string: "https://listenbrainz.org/track/\(mbid)/")!
        }
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let encodedTrack = track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return URL(string: "https://musicbrainz.org/search?query=artist:%22\(encodedArtist)%22%20AND%20recording:%22\(encodedTrack)%22&type=recording&limit=1&method=advanced")!
    }
    
    // MARK: - Authentication
    
    func authenticate() async throws -> (token: String, authURL: URL) {
        return ("", URL(string: authURL)!)
    }
    
    func completeAuthentication(token: String) async throws -> (username: String, sessionKey: String, profileUrl: String?, isSubscriber: Bool) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw Error.invalidToken
        }
        
        var request = URLRequest(url: baseURL.appendingPathComponent("validate-token"))
        request.httpMethod = "GET"
        request.setValue("Token \(trimmedToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.serverError("Invalid response from validate-token endpoint")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw Error.serverError("Token validation failed (HTTP \(httpResponse.statusCode)): \(errorMsg)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let valid = json?["valid"] as? Bool, valid,
              let username = json?["user_name"] as? String else {
            throw Error.invalidToken
        }
        
        let profileUrl = "https://listenbrainz.org/user/\(username)/"
        return (username, token, profileUrl, false)
    }
    
    // MARK: - Scrobbling
    
    func updateNowPlaying(sessionKey: String, track: Track) async throws {
        let payload: [String: Any] = [
            "listen_type": "playing_now",
            "payload": [[
                "track_metadata": [
                    "artist_name": track.artist,
                    "track_name": track.name,
                    "release_name": track.album
                ]
            ]]
        ]
        try await sendRequest(endpoint: "submit-listens", token: sessionKey, payload: payload)
    }
    
    func scrobble(sessionKey: String, track: Track) async throws {
        let payload: [String: Any] = [
            "listen_type": "single",
            "payload": [[
                "listened_at": Int(track.startedAt),
                "track_metadata": [
                    "artist_name": track.artist,
                    "track_name": track.name,
                    "release_name": track.album
                ]
            ]]
        ]
        try await sendRequest(endpoint: "submit-listens", token: sessionKey, payload: payload)
    }
    
    func updateLove(sessionKey: String, artist: String, track: String, loved: Bool) async throws {
        print("🎵 ListenBrainz updateLove called - artist: \(artist), track: \(track), loved: \(loved)")
        
        // ListenBrainz requires recording_mbid or recording_msid to submit feedback
        // We need to look up the recording first to get the MusicBrainz ID
        guard let mbid = try await lookupRecordingMBID(artist: artist, track: track) else {
            print("⚠️ Could not find MusicBrainz ID for track, skipping love update on ListenBrainz")
            return
        }
        
        // Score: 1 (love), 0 (remove feedback)
        let score = loved ? 1 : 0
        
        let payload: [String: Any] = [
            "recording_mbid": mbid,
            "score": score
        ]
        
        do {
            try await sendRequest(endpoint: "feedback/recording-feedback", token: sessionKey, payload: payload)
            print("✓ Love status updated successfully on ListenBrainz: \(loved ? "loved" : "unloved")")
        } catch {
            print("✗ Failed to update love status on ListenBrainz: \(error)")
            throw error
        }
    }
    
    private func lookupRecordingMBID(artist: String, track: String) async throws -> String? {
        // Query MusicBrainz API to find the recording MBID
        let query = "artist:\(artist) AND recording:\(track)"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://musicbrainz.org/ws/2/recording/?query=\(encodedQuery)&limit=1&fmt=json") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("AudioscrobblerApp/1.0 (contact@example.com)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let recordings = json?["recordings"] as? [[String: Any]]
            return recordings?.first?["id"] as? String
        } catch {
            print("⚠️ Failed to lookup recording MBID: \(error)")
            return nil
        }
    }
    
    // MARK: - Profile Data
    
    func getRecentTracks(username: String, limit: Int, page: Int, token: String?) async throws -> [RecentTrack] {
        // Populate cache first (only on first page)
        if page == 1 {
            do {
                try await populatePlayCountCache(username: username)
            } catch {
                print("⚠️ [ListenBrainz] Failed to populate cache: \(error)")
            }
        }
        
        let offset = (page - 1) * limit
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = URLComponents(url: baseURL.appendingPathComponent("user/\(encodedUsername)/listens"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "count", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let listens = payload?["listens"] as? [[String: Any]] ?? []
        
        return listens.compactMap { listen in
            guard let metadata = listen["track_metadata"] as? [String: Any],
                  let artist = metadata["artist_name"] as? String,
                  let name = metadata["track_name"] as? String else { return nil }
            
            let album = metadata["release_name"] as? String ?? ""
            let imageUrl = extractCoverArtUrl(from: metadata)
            let (artistMbid, releaseMbid, recordingMbid) = extractMbids(from: metadata)
            
            // Get playcount from cache (top 1000 all-time tracks only)
            let playcount = getCachedPlayCount(username: username, artist: artist, track: name)
            
            return RecentTrack(
                name: name,
                artist: artist,
                album: album,
                date: listen["listened_at"] as? Int,
                isNowPlaying: false,
                loved: false,
                imageUrl: imageUrl,
                artistURL: artistURL(artist: artist, mbid: artistMbid),
                albumURL: albumURL(artist: artist, album: album, mbid: releaseMbid),
                trackURL: trackURL(artist: artist, track: name, mbid: recordingMbid),
                playcount: playcount
            )
        }
    }
    
    
    func getUserStats(username: String) async throws -> UserStats? {
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let url = baseURL.appendingPathComponent("user/\(encodedUsername)/listen-count")
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let count = payload?["count"] as? Int ?? 0
        
        return UserStats(
            playcount: count,
            artistCount: 0,
            trackCount: 0,
            albumCount: 0,
            lovedCount: 0,
            registered: "",
            country: nil,
            realname: nil,
            gender: nil,
            age: nil,
            playlistCount: nil
        )
    }
    
    func getTopArtists(username: String, period: String, limit: Int) async throws -> [TopArtist] {
        let range = convertPeriodToRange(period)
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = URLComponents(url: baseURL.appendingPathComponent("stats/user/\(encodedUsername)/artists"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "count", value: "\(limit)")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let artists = payload?["artists"] as? [[String: Any]] ?? []
        
        return artists.compactMap { artist in
            guard let name = artist["artist_name"] as? String,
                  let count = artist["listen_count"] as? Int else { return nil }
            
            let imageUrl = (artist["artist_mbids"] as? [String])?.first.flatMap { mbid in
                "https://coverartarchive.org/release-group/\(mbid)/front-250"
            }
            
            return TopArtist(name: name, playcount: count, imageUrl: imageUrl)
        }
    }
    
    func getTopAlbums(username: String, period: String, limit: Int) async throws -> [TopAlbum] {
        let range = convertPeriodToRange(period)
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = URLComponents(url: baseURL.appendingPathComponent("stats/user/\(encodedUsername)/releases"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "count", value: "\(limit)")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let releases = payload?["releases"] as? [[String: Any]] ?? []
        
        return releases.compactMap { release in
            guard let name = release["release_name"] as? String,
                  let artist = release["artist_name"] as? String,
                  let count = release["listen_count"] as? Int else { return nil }
            
            let imageUrl = (release["release_mbid"] as? String).flatMap { mbid in
                "https://coverartarchive.org/release/\(mbid)/front-250"
            }
            
            return TopAlbum(artist: artist, name: name, playcount: count, imageUrl: imageUrl)
        }
    }
    
    func getTopTracks(username: String, period: String, limit: Int) async throws -> [TopTrack] {
        let range = convertPeriodToRange(period)
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = URLComponents(url: baseURL.appendingPathComponent("stats/user/\(encodedUsername)/recordings"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "count", value: "\(limit)")
        ]
        
        print("🎵 [ListenBrainz] getTopTracks URL: \(components.url!.absoluteString)")
        print("🎵 [ListenBrainz] Requesting \(limit) tracks for range: \(range)")
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        
        if let jsonString = String(data: data, encoding: .utf8) {
            let preview = jsonString.prefix(500)
            print("🎵 [ListenBrainz] Response preview: \(preview)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let recordings = payload?["recordings"] as? [[String: Any]] ?? []
        
        print("🎵 [ListenBrainz] Parsed \(recordings.count) recordings from response")
        
        return recordings.compactMap { recording in
            guard let name = recording["track_name"] as? String,
                  let artist = recording["artist_name"] as? String,
                  let count = recording["listen_count"] as? Int else { return nil }
            
            let imageUrl = (recording["release_mbid"] as? String).flatMap { mbid in
                "https://coverartarchive.org/release/\(mbid)/front-250"
            }
            
            return TopTrack(artist: artist, name: name, playcount: count, imageUrl: imageUrl)
        }
    }
    
    // MARK: - Helpers
    
    private func sendRequest(endpoint: String, token: String, payload: [String: Any]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.serverError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw Error.serverError("HTTP \(httpResponse.statusCode): \(errorMsg)")
        }
    }
    
    private func convertPeriodToRange(_ period: String) -> String {
        switch period {
        case "7day": return "week"
        case "1month": return "month"
        case "3month": return "quarter"
        case "12month": return "year"
        case "all_time": return "all_time"
        default: return "all_time"
        }
    }
    
    private func extractCoverArtUrl(from metadata: [String: Any]) -> String? {
        // Try to get release MBID from additional_info or mbid_mapping
        if let additionalInfo = metadata["additional_info"] as? [String: Any],
           let releaseMbid = additionalInfo["release_mbid"] as? String {
            return "https://coverartarchive.org/release/\(releaseMbid)/front-250"
        }
        
        if let mbidMapping = metadata["mbid_mapping"] as? [String: Any],
           let releaseMbid = mbidMapping["release_mbid"] as? String {
            return "https://coverartarchive.org/release/\(releaseMbid)/front-250"
        }
        
        return nil
    }
    
    private func extractMbids(from metadata: [String: Any]) -> (artistMbid: String?, releaseMbid: String?, recordingMbid: String?) {
        var artistMbid: String?
        var releaseMbid: String?
        var recordingMbid: String?
        
        // Check mbid_mapping first (preferred)
        if let mbidMapping = metadata["mbid_mapping"] as? [String: Any] {
            artistMbid = (mbidMapping["artist_mbids"] as? [String])?.first
            releaseMbid = mbidMapping["release_mbid"] as? String
            recordingMbid = mbidMapping["recording_mbid"] as? String
        }
        
        // Fallback to additional_info
        if let additionalInfo = metadata["additional_info"] as? [String: Any] {
            if artistMbid == nil {
                artistMbid = (additionalInfo["artist_mbids"] as? [String])?.first
            }
            if releaseMbid == nil {
                releaseMbid = additionalInfo["release_mbid"] as? String
            }
            if recordingMbid == nil {
                recordingMbid = additionalInfo["recording_mbid"] as? String
            }
        }
        
        return (artistMbid, releaseMbid, recordingMbid)
    }
    
    // MARK: - Track Playcount
    
    func getTrackPlaycount(username: String, artist: String, track: String, recordingMbid: String?) async throws -> Int? {
        // Use cache only - ListenBrainz doesn't provide per-track playcount API
        return getCachedPlayCount(username: username, artist: artist, track: track)
    }
    
    func getTrackUserPlaycount(token: String, artist: String, track: String) async throws -> Int? {
        // This method is called by Last.fm compatibility layer
        // Not directly usable for ListenBrainz without username and mbid
        return nil
    }
    
    func getTrackLoved(token: String, artist: String, track: String) async throws -> Bool {
        return false
    }
    
    // Helper to normalize strings for cache keys
    private func normalizeForCache(_ text: String) -> String {
        return text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{200E}", with: "") // Remove left-to-right mark
            .replacingOccurrences(of: "\u{200F}", with: "") // Remove right-to-left mark
            .replacingOccurrences(of: "\u{00A0}", with: " ") // Replace non-breaking space
            .trimmingCharacters(in: .whitespaces)
    }
    
    // Helper method to populate playcount cache - should be called when loading profile/history
    func populatePlayCountCache(username: String) async throws {
        print("🎵 [ListenBrainz] ========== populatePlayCountCache TRIGGERED ==========")
        print("🎵 [ListenBrainz] Username: \(username)")
        print("🎵 [ListenBrainz] Called from: app visibility or profile load")
        
        // Try to load from disk first
        if let (cachedCounts, continueFromTs, completedAt) = loadCacheFromDisk(username: username) {
            cacheState.withLock { state in
                state.playCountCache[username] = cachedCounts
                state.cacheExpiry[username] = Date().addingTimeInterval(cacheValidityDuration)
            }
            print("🎵 [ListenBrainz] ✅ Loaded \(cachedCounts.count) tracks from disk")
            
            // Check if we need to continue fetching
            if let continueFrom = continueFromTs {
                print("🎵 [ListenBrainz] ⚠️ INCOMPLETE FETCH - will resume from timestamp \(continueFrom)")
                print("🎵 [ListenBrainz] Starting background task to continue...")
                startBackgroundCacheFetch(username: username, continueFrom: continueFrom)
            } else if let completedAt = completedAt {
                // Cache is complete, but check if we need to fetch NEW listens
                let age = Date().timeIntervalSince1970 - completedAt
                if age > 300 { // 5 minutes
                    let minTs = Int(completedAt) + 1 // Start from 1 second after completion
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
        
        // Check if cache is still valid in memory
        let isCacheValid = cacheState.withLock { state in
            if let expiry = state.cacheExpiry[username], Date() < expiry {
                let count = state.playCountCache[username]?.count ?? 0
                print("🎵 [ListenBrainz] Cache still valid, skipping fetch. Entries: \(count)")
                return true
            }
            return false
        }
        
        if isCacheValid {
            return
        }
        
        // Fetch first page quickly for immediate use
        print("🎵 [ListenBrainz] Fetching first page (1000 tracks) for immediate use...")
        let firstPage = try await getTopTracksWithOffset(
            username: username,
            period: "all_time",
            limit: 1000,
            offset: 0
        )
        
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
        
        // Start background fetch from beginning
        startBackgroundCacheFetch(username: username, continueFrom: nil)
    }
    
    private func startBackgroundCacheFetch(username: String, continueFrom: Int?) {
        // Check if task already running (DUPLICATE PREVENTION)
        if let existingTask = backgroundFetchTasks[username], !existingTask.isCancelled {
            print("⏸️ [ListenBrainz] ⚠️ DUPLICATE PREVENTED: Background task already running for \(username)")
            return
        }
        
        // Cancel any cancelled task
        backgroundFetchTasks[username]?.cancel()
        
        // Start new background task
        print("🎵 [ListenBrainz] 🚀 Starting background fetch task")
        let task = Task {
            await fetchAllPagesInBackground(username: username, continueFrom: continueFrom)
        }
        backgroundFetchTasks[username] = task
    }
    
    private func startIncrementalUpdate(username: String, since: Int) {
        // Check if task already running (DUPLICATE PREVENTION)
        if let existingTask = backgroundFetchTasks[username], !existingTask.isCancelled {
            print("⏸️ [ListenBrainz] ⚠️ DUPLICATE PREVENTED: Background task already running for \(username)")
            return
        }
        
        // Cancel any cancelled task
        backgroundFetchTasks[username]?.cancel()
        
        // Start incremental update task
        print("🎵 [ListenBrainz] 🚀 Starting incremental update task")
        let task = Task {
            await fetchNewListens(username: username, since: since)
        }
        backgroundFetchTasks[username] = task
    }
    
    private func fetchNewListens(username: String, since: Int) async {
        print("🎵 [ListenBrainz] ========== INCREMENTAL UPDATE STARTED ==========")
        print("🎵 [ListenBrainz] Fetching NEW listens since timestamp: \(since)")
        
        // Load existing cache
        var playcounts: [String: Int] = cacheState.withLock { state in
            state.playCountCache[username] ?? [:]
        }
        
        let perPage = 1000
        var totalNewListens = 0
        
        do {
            let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
            var components = URLComponents(url: baseURL.appendingPathComponent("user/\(encodedUsername)/listens"), resolvingAgainstBaseURL: false)!
            
            components.queryItems = [
                URLQueryItem(name: "count", value: "\(perPage)"),
                URLQueryItem(name: "min_ts", value: "\(since)")
            ]
            
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let payload = json?["payload"] as? [String: Any]
            let listens = payload?["listens"] as? [[String: Any]] ?? []
            
            print("🎵 [ListenBrainz] Found \(listens.count) new listens")
            
            // Count new listens
            for listen in listens {
                guard let metadata = listen["track_metadata"] as? [String: Any],
                      let artist = metadata["artist_name"] as? String,
                      let name = metadata["track_name"] as? String else { continue }
                
                let key = "\(normalizeForCache(artist))|\(normalizeForCache(name))"
                playcounts[key, default: 0] += 1
                totalNewListens += 1
            }
            
            print("🎵 [ListenBrainz] Added \(totalNewListens) new listens, total unique tracks: \(playcounts.count)")
            
            // Update cache
            cacheState.withLock { state in
                state.playCountCache[username] = playcounts
            }
            
            // Save updated cache with new completion time
            let newCompletionTimestamp = Date().timeIntervalSince1970
            saveCacheToDisk(username: username, cache: playcounts, continueFromTs: nil, completedAt: newCompletionTimestamp)
            
            print("🎵 [ListenBrainz] ✅ Incremental update complete, cache updated")
            print("🎵 [ListenBrainz] ========================================")
        } catch {
            print("⚠️ [ListenBrainz] Error during incremental update: \(error)")
        }
        
        // Clean up task reference
        backgroundFetchTasks.removeValue(forKey: username)
    }
    
    private func fetchAllPagesInBackground(username: String, continueFrom: Int?) async {
        print("🎵 [ListenBrainz] ========== BACKGROUND LISTENS FETCH STARTED ==========")
        if let continueFrom = continueFrom {
            print("🎵 [ListenBrainz] Resuming from timestamp: \(continueFrom)")
        } else {
            print("🎵 [ListenBrainz] Starting from beginning")
        }
        print("🎵 [ListenBrainz] Username: \(username)")
        
        // Load existing cache
        var playcounts: [String: Int] = cacheState.withLock { state in
            state.playCountCache[username] ?? [:]
        }
        
        let perPage = 1000
        var maxTs: Int? = continueFrom // Start from where we left off
        var totalListens = 0
        var page = 0
        
        while true {
            // Check if task was cancelled
            if Task.isCancelled {
                print("🎵 [ListenBrainz] Background fetch cancelled at page \(page + 1)")
                return
            }
            
            page += 1
            print("🎵 [ListenBrainz] Fetching listens page \(page) (max_ts: \(maxTs?.description ?? "none"), count: \(perPage))")
            
            do {
                let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
                var components = URLComponents(url: baseURL.appendingPathComponent("user/\(encodedUsername)/listens"), resolvingAgainstBaseURL: false)!
                
                var queryItems = [URLQueryItem(name: "count", value: "\(perPage)")]
                if let maxTs = maxTs {
                    queryItems.append(URLQueryItem(name: "max_ts", value: "\(maxTs)"))
                }
                components.queryItems = queryItems
                
                let (data, _) = try await URLSession.shared.data(from: components.url!)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let payload = json?["payload"] as? [String: Any]
                let listens = payload?["listens"] as? [[String: Any]] ?? []
                
                print("🎵 [ListenBrainz] Page \(page): Received \(listens.count) listens")
                
                if listens.isEmpty {
                    print("🎵 [ListenBrainz] No more listens, stopping")
                    break
                }
                
                // Count each track
                for listen in listens {
                    guard let metadata = listen["track_metadata"] as? [String: Any],
                          let artist = metadata["artist_name"] as? String,
                          let name = metadata["track_name"] as? String else { continue }
                    
                    let key = "\(normalizeForCache(artist))|\(normalizeForCache(name))"
                    playcounts[key, default: 0] += 1
                }
                
                totalListens += listens.count
                
                // Get the oldest timestamp for next page (go backwards through history)
                if let lastListen = listens.last,
                   let timestamp = lastListen["listened_at"] as? Int {
                    maxTs = timestamp
                }
                
                print("🎵 [ListenBrainz] Total listens processed: \(totalListens), unique tracks: \(playcounts.count)")
                
                // Update memory cache
                cacheState.withLock { state in
                    state.playCountCache[username] = playcounts
                }
                
                // Save progress to disk every 5 pages (more frequent saves)
                if page % 5 == 0 {
                    saveCacheToDisk(username: username, cache: playcounts, continueFromTs: maxTs, completedAt: nil)
                    print("🎵 [ListenBrainz] 💾 Progress saved to disk (page \(page), can resume from ts \(maxTs ?? 0))")
                }
                
                // Safety limit: Stop after 100 pages (100,000 listens) to avoid excessive processing
                if page >= 100 {
                    print("🎵 [ListenBrainz] Reached page limit (100 pages), stopping")
                    break
                }
                
                // Small delay to avoid rate limiting
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            } catch {
                print("⚠️ [ListenBrainz] Error fetching page \(page): \(error.localizedDescription)")
                print("⚠️ [ListenBrainz] Error details: \(error)")
                break
            }
        }
        
        print("🎵 [ListenBrainz] ========== BACKGROUND FETCH COMPLETE ==========")
        print("🎵 [ListenBrainz] Total pages fetched: \(page)")
        print("🎵 [ListenBrainz] Total listens processed: \(totalListens)")
        print("🎵 [ListenBrainz] Unique tracks with playcounts: \(playcounts.count)")
        
        cacheState.withLock { state in
            state.playCountCache[username] = playcounts
            state.cacheExpiry[username] = Date().addingTimeInterval(cacheValidityDuration)
        }
        
        // Save final complete cache to disk (no continueFromTs = complete)
        let completionTimestamp = Date().timeIntervalSince1970
        saveCacheToDisk(username: username, cache: playcounts, continueFromTs: nil, completedAt: completionTimestamp)
        
        print("🎵 [ListenBrainz] ✅ COMPLETE cache saved to disk (continue_from_ts: null, completed_at: \(Int(completionTimestamp)))")
        print("🎵 [ListenBrainz] ========================================")
        
        // Clean up task reference
        backgroundFetchTasks.removeValue(forKey: username)
    }
    
    private func getCacheFilePath(username: String) -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let audioscrobblerDir = appSupport.appendingPathComponent("Audioscrobbler", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: audioscrobblerDir, withIntermediateDirectories: true)
        
        return audioscrobblerDir.appendingPathComponent("listenbrainz_cache_\(username).json")
    }
    
    private func saveCacheToDisk(username: String, cache: [String: Int], continueFromTs: Int?, completedAt: TimeInterval?) {
        guard let filePath = getCacheFilePath(username: username) else {
            print("⚠️ [ListenBrainz] Could not get cache file path")
            return
        }
        
        var cacheData: [String: Any] = [
            "username": username,
            "save_timestamp": Date().timeIntervalSince1970,
            "continue_from_ts": continueFromTs as Any, // nil = complete, Int = needs to continue
            "data": cache
        ]
        
        // Add completion timestamp if fetch is complete
        if let completedAt = completedAt {
            cacheData["completed_at"] = completedAt
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: cacheData, options: [.prettyPrinted])
            try data.write(to: filePath)
            
            // Get file size for logging
            let attrs = try FileManager.default.attributesOfItem(atPath: filePath.path)
            let fileSize = attrs[.size] as? Int ?? 0
            let sizeMB = Double(fileSize) / 1_048_576.0
            print("🎵 [ListenBrainz] Cache saved to file (\(String(format: "%.2f", sizeMB)) MB)")
        } catch {
            print("⚠️ [ListenBrainz] Failed to save cache: \(error)")
        }
    }
    
    private func loadCacheFromDisk(username: String) -> ([String: Int], Int?, TimeInterval?)? {
        guard let filePath = getCacheFilePath(username: username) else {
            return nil
        }
        
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: filePath)
            guard let cacheData = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let saveTimestamp = cacheData["save_timestamp"] as? TimeInterval,
                  let cache = cacheData["data"] as? [String: Int] else {
                return nil
            }
            
            // Check if cache is too old (more than 7 days)
            let age = Date().timeIntervalSince1970 - saveTimestamp
            if age > 604800 { // 7 days
                print("🎵 [ListenBrainz] Cache file too old (\(Int(age/86400)) days), ignoring")
                // Delete old file
                try? FileManager.default.removeItem(at: filePath)
                return nil
            }
            
            // Get file size for logging
            let attrs = try FileManager.default.attributesOfItem(atPath: filePath.path)
            let fileSize = attrs[.size] as? Int ?? 0
            let sizeMB = Double(fileSize) / 1_048_576.0
            
            let continueFromTs = cacheData["continue_from_ts"] as? Int
            let completedAt = cacheData["completed_at"] as? TimeInterval
            
            // Enhanced logging
            if let completedAt = completedAt {
                let completedDate = Date(timeIntervalSince1970: completedAt)
                let age = Date().timeIntervalSince1970 - completedAt
                print("🎵 [ListenBrainz] Loaded cache from file (\(String(format: "%.2f", sizeMB)) MB, completed: \(completedDate), age: \(Int(age))s)")
            } else if continueFromTs != nil {
                print("🎵 [ListenBrainz] Loaded cache from file (\(String(format: "%.2f", sizeMB)) MB, IN PROGRESS)")
            } else {
                print("🎵 [ListenBrainz] Loaded cache from file (\(String(format: "%.2f", sizeMB)) MB, status unknown)")
            }
            
            return (cache, continueFromTs, completedAt)
        } catch {
            print("⚠️ [ListenBrainz] Failed to load cache: \(error)")
            return nil
        }
    }
    
    private func getTopTracksWithOffset(username: String, period: String, limit: Int, offset: Int) async throws -> [TopTrack] {
        let range = convertPeriodToRange(period)
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = URLComponents(url: baseURL.appendingPathComponent("stats/user/\(encodedUsername)/recordings"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "count", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "\(offset)")
        ]
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let recordings = payload?["recordings"] as? [[String: Any]] ?? []
        
        return recordings.compactMap { recording in
            guard let name = recording["track_name"] as? String,
                  let artist = recording["artist_name"] as? String,
                  let count = recording["listen_count"] as? Int else { return nil }
            
            let imageUrl = (recording["release_mbid"] as? String).flatMap { mbid in
                "https://coverartarchive.org/release/\(mbid)/front-250"
            }
            
            return TopTrack(artist: artist, name: name, playcount: count, imageUrl: imageUrl)
        }
    }
    
    // Method to lookup playcount from cache
    func getCachedPlayCount(username: String, artist: String, track: String) -> Int? {
        let normalizedArtist = normalizeForCache(artist)
        let normalizedTrack = normalizeForCache(track)
        let key = "\(normalizedArtist)|\(normalizedTrack)"
        
        let (count, cache) = cacheState.withLock { state in
            (state.playCountCache[username]?[key], state.playCountCache[username])
        }
        
        if count == nil && cache != nil {
            // Try to find similar keys for debugging
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
}
