import Foundation
import SwiftUI

// Helper for thread-safe state access
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
    private struct PaginationState {
        var paginationState: [String: Int] = [:] // username -> last timestamp for pagination
    }
    
    private let paginationState = Locked(PaginationState())
    private let cache = ListenBrainzCache()
    
    var baseURL: URL { URL(string: "https://api.listenbrainz.org/1/")! }
    var authURL: String { "https://listenbrainz.org/settings/" }
    var linkColor: Color { Color(hue: 0.08, saturation: 0.80, brightness: 0.85) }
    
    // MARK: - URL Builders
    
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
        guard let mbid = try await lookupRecordingMBID(artist: artist, track: track) else {
            Logger.info("Could not find MusicBrainz ID for track, skipping love update on ListenBrainz", log: Logger.scrobbling)
            return
        }
        
        let payload: [String: Any] = [
            "recording_mbid": mbid,
            "score": loved ? 1 : 0
        ]
        
        do {
            try await sendRequest(endpoint: "feedback/recording-feedback", token: sessionKey, payload: payload)
            Logger.info("ListenBrainz love status updated: \(loved ? "loved" : "unloved")", log: Logger.scrobbling)
        } catch {
            Logger.error("Failed to update love status on ListenBrainz: \(error)", log: Logger.scrobbling)
            throw error
        }
    }
    
    func deleteScrobble(sessionKey: String, identifier: ScrobbleIdentifier) async throws {
        guard let timestamp = identifier.timestamp, let msid = identifier.serviceId else {
            Logger.info("ListenBrainz delete skipped - requires timestamp AND recording_msid", log: Logger.scrobbling)
            return
        }
        
        let payload: [String: Any] = [
            "listened_at": timestamp,
            "recording_msid": msid
        ]
        
        do {
            try await sendRequest(endpoint: "delete-listen", token: sessionKey, payload: payload)
            Logger.info("ListenBrainz delete request sent", log: Logger.scrobbling)
        } catch {
            Logger.error("ListenBrainz delete failed: \(error)", log: Logger.scrobbling)
        }
    }
    
    private func lookupRecordingMBID(artist: String, track: String) async throws -> String? {
        // Try MBID Mapper 2.0 first (fast fuzzy matching)
        if let mbid = try? await lookupMBIDFromMapper(artist: artist, track: track, album: nil) {
            return mbid.recordingMbid
        }
        
        // Fallback to direct MusicBrainz search
        let query = "artist:\(artist) AND recording:\(track)"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://musicbrainz.org/ws/2/recording/?query=\(encodedQuery)&limit=1&fmt=json") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.setValue("ScrobleblerApp/1.0 (contact@example.com)", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let recordings = json?["recordings"] as? [[String: Any]]
            return recordings?.first?["id"] as? String
        } catch {
            Logger.error("Failed to lookup recording MBID: \(error)", log: Logger.network)
            return nil
        }
    }
    
    struct MapperResult {
        let artistMbid: String?
        let releaseMbid: String?
        let recordingMbid: String?
        let confidence: Double
    }
    
    func lookupMBIDsForTrack(artist: String, track: String, album: String?) async throws -> MapperResult? {
        return try await lookupMBIDFromMapper(artist: artist, track: track, album: album)
    }
    
    private func lookupMBIDFromMapper(artist: String, track: String, album: String?) async throws -> MapperResult? {
        var components = URLComponents(string: "https://mapper.listenbrainz.org/mapping/lookup")!
        var queryItems = [
            URLQueryItem(name: "artist_credit_name", value: artist),
            URLQueryItem(name: "recording_name", value: track)
        ]
        if let album = album, !album.isEmpty {
            queryItems.append(URLQueryItem(name: "release_name", value: album))
        }
        components.queryItems = queryItems
        
        guard let url = components.url else { return nil }
        
        let maxRetries = 3
        let retryDelay: UInt64 = 1_000_000_000 // 1 second
        
        for attempt in 1...maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    Logger.error("MBID Mapper: HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1) for '\(artist) - \(track)'", log: Logger.network)
                    return nil
                }
                
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let confidence = json?["confidence"] as? Double ?? 0.0
                
                guard confidence > 0.5 else {
                    Logger.debug("MBID Mapper: Low confidence (\(String(format: "%.2f", confidence))) for '\(artist) - \(track)'", log: Logger.network)
                    return nil
                }
                
                let artistMbids = json?["artist_credit_mbids"] as? [String]
                let releaseMbid = json?["release_mbid"] as? String
                let recordingMbid = json?["recording_mbid"] as? String
                
                Logger.debug("MBID Mapper: Matched '\(artist) - \(track)' (confidence: \(String(format: "%.2f", confidence)))", log: Logger.network)
                
                return MapperResult(
                    artistMbid: artistMbids?.first,
                    releaseMbid: releaseMbid,
                    recordingMbid: recordingMbid,
                    confidence: confidence
                )
            } catch {
                if attempt < maxRetries {
                    Logger.info("MBID Mapper: Attempt \(attempt) failed, retrying", log: Logger.network)
                    try? await Task.sleep(nanoseconds: retryDelay)
                } else {
                    Logger.error("MBID Mapper lookup failed: \(error)", log: Logger.network)
                    return nil
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Profile Data
    
    func getRecentTracks(username: String, limit: Int, page: Int, token: String?) async throws -> [RecentTrack] {
        Logger.debug("ListenBrainz getRecentTracks - page: \(page), limit: \(limit)", log: Logger.api)
        
        // Populate cache first (only on first page)
        if page == 1 {
            _ = paginationState.withLock { state in
                state.paginationState.removeValue(forKey: username)
            }
            Logger.debug("ListenBrainz page 1 - reset pagination state", log: Logger.api)
            await cache.populatePlayCountCache(username: username)
        }
        
        // ListenBrainz uses timestamp-based pagination
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = URLComponents(url: baseURL.appendingPathComponent("user/\(encodedUsername)/listens"), resolvingAgainstBaseURL: false)!
        
        var queryItems = [URLQueryItem(name: "count", value: "\(limit)")]
        
        if page > 1 {
            let maxTs = paginationState.withLock { state in
                state.paginationState[username]
            }
            if let maxTs = maxTs {
                Logger.debug("ListenBrainz page \(page) - using max_ts: \(maxTs)", log: Logger.api)
                queryItems.append(URLQueryItem(name: "max_ts", value: "\(maxTs)"))
            } else {
                Logger.error("ListenBrainz page \(page) - NO max_ts found in pagination state", log: Logger.api)
            }
        }
        
        components.queryItems = queryItems
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let listens = payload?["listens"] as? [[String: Any]] ?? []
        
        Logger.debug("ListenBrainz received \(listens.count) listens for page \(page)", log: Logger.api)
        
        // Store the last timestamp for next page
        if let lastListen = listens.last,
           let lastTimestamp = lastListen["listened_at"] as? Int {
            paginationState.withLock { state in
                state.paginationState[username] = lastTimestamp
            }
            Logger.debug("ListenBrainz stored pagination timestamp: \(lastTimestamp)", log: Logger.api)
        } else {
            Logger.error("ListenBrainz no timestamp found in last listen - pagination may fail", log: Logger.api)
        }
        
        // First pass: extract data from ListenBrainz response
        let tracks = listens.compactMap { listen -> (metadata: [String: Any], artist: String, name: String, album: String, msid: String?, timestamp: Int?, existingMbids: (String?, String?, String?))? in
            guard let metadata = listen["track_metadata"] as? [String: Any],
                  let artist = metadata["artist_name"] as? String,
                  let name = metadata["track_name"] as? String else { return nil }
            
            let album = metadata["release_name"] as? String ?? ""
            let mbids = extractMbids(from: metadata)
            let msid = listen["recording_msid"] as? String
            let timestamp = listen["listened_at"] as? Int
            
            return (metadata, artist, name, album, msid, timestamp, mbids)
        }
        
        // Second pass: enrich missing MBIDs using MBID Mapper 2.0
        var enrichedCount = 0
        var tracksNeedingLookup = 0
        let result = await withTaskGroup(of: (Int, RecentTrack?, Bool).self) { group in
            for (index, track) in tracks.enumerated() {
                group.addTask {
                    var (artistMbid, releaseMbid, recordingMbid) = track.existingMbids
                    var wasEnriched = false
                    
                    let missingMbids = [
                        artistMbid == nil ? "artist" : nil,
                        releaseMbid == nil ? "release" : nil,
                        recordingMbid == nil ? "recording" : nil
                    ].compactMap { $0 }
                    
                    // Only lookup if we're missing MBIDs from ListenBrainz
                    if recordingMbid == nil || releaseMbid == nil || artistMbid == nil {
                        Logger.debug("MBID Mapper: '\(track.artist) - \(track.name)' missing: \(missingMbids.joined(separator: ", "))", log: Logger.network)
                        if let mapperResult = try? await self.lookupMBIDFromMapper(
                            artist: track.artist,
                            track: track.name,
                            album: track.album.isEmpty ? nil : track.album
                        ) {
                            let hadArtist = artistMbid != nil
                            let hadRelease = releaseMbid != nil
                            let hadRecording = recordingMbid != nil
                            
                            artistMbid = artistMbid ?? mapperResult.artistMbid
                            releaseMbid = releaseMbid ?? mapperResult.releaseMbid
                            recordingMbid = recordingMbid ?? mapperResult.recordingMbid
                            
                            wasEnriched = (!hadArtist && artistMbid != nil) ||
                                        (!hadRelease && releaseMbid != nil) ||
                                        (!hadRecording && recordingMbid != nil)
                        }
                    }
                    
                    let imageUrl = self.extractCoverArtUrl(from: track.metadata)
                    let playcount = self.cache.getCachedPlayCount(username: username, artist: track.artist, track: track.name)
                    
                    let recentTrack = RecentTrack(
                        name: track.name,
                        artist: track.artist,
                        album: track.album,
                        date: track.timestamp,
                        isNowPlaying: false,
                        loved: false,
                        imageUrl: imageUrl,
                        artistURL: self.artistURL(artist: track.artist, mbid: artistMbid),
                        albumURL: self.albumURL(artist: track.artist, album: track.album, mbid: releaseMbid),
                        trackURL: self.trackURL(artist: track.artist, track: track.name, mbid: recordingMbid),
                        playcount: playcount,
                        serviceInfo: [
                            ScrobbleService.listenbrainz.id: ServiceTrackData.listenbrainz(
                                recordingMsid: track.msid ?? "",
                                timestamp: track.timestamp ?? 0
                            )
                        ],
                        sourceService: .listenbrainz
                    )
                    
                    return (index, recentTrack, wasEnriched)
                }
            }
            
            // Collect results and maintain original order
            var results: [(Int, RecentTrack?, Bool)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }
        }
        
        enrichedCount = result.filter { $0.2 }.count
        tracksNeedingLookup = tracks.filter { track in
            let (artistMbid, releaseMbid, recordingMbid) = track.existingMbids
            return recordingMbid == nil || releaseMbid == nil || artistMbid == nil
        }.count
        
        if tracksNeedingLookup > 0 {
            Logger.debug("ListenBrainz MBID Mapper: \(tracksNeedingLookup) tracks needed lookup, \(enrichedCount) enriched", log: Logger.api)
        }
        
        return result.compactMap { $0.1 }
    }
    
    func getRecentTracksByTimeRange(username: String, minTs: Int?, maxTs: Int?, limit: Int, token: String?) async throws -> [RecentTrack]? {
        Logger.debug("ListenBrainz getRecentTracksByTimeRange - minTs: \(minTs ?? 0), maxTs: \(maxTs ?? 0), limit: \(limit)", log: Logger.api)
        
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        var components = URLComponents(url: baseURL.appendingPathComponent("user/\(encodedUsername)/listens"), resolvingAgainstBaseURL: false)!
        
        var queryItems = [URLQueryItem(name: "count", value: "\(limit)")]
        if let minTs = minTs {
            queryItems.append(URLQueryItem(name: "min_ts", value: "\(minTs)"))
        }
        if let maxTs = maxTs {
            queryItems.append(URLQueryItem(name: "max_ts", value: "\(maxTs)"))
        }
        components.queryItems = queryItems
        
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let listens = payload?["listens"] as? [[String: Any]] ?? []
        
        Logger.debug("ListenBrainz received \(listens.count) listens for time range", log: Logger.api)
        
        // Extract and build tracks (simplified version without cache)
        let tracks = listens.compactMap { listen -> RecentTrack? in
            guard let metadata = listen["track_metadata"] as? [String: Any],
                  let artist = metadata["artist_name"] as? String,
                  let name = metadata["track_name"] as? String else { return nil }
            
            let album = metadata["release_name"] as? String ?? ""
            let mbids = extractMbids(from: metadata)
            let msid = listen["recording_msid"] as? String
            let timestamp = listen["listened_at"] as? Int
            let imageUrl = extractCoverArtUrl(from: metadata)
            
            return RecentTrack(
                name: name,
                artist: artist,
                album: album,
                date: timestamp,
                isNowPlaying: false,
                loved: false,
                imageUrl: imageUrl,
                artistURL: artistURL(artist: artist, mbid: mbids.artistMbid),
                albumURL: albumURL(artist: artist, album: album, mbid: mbids.releaseMbid),
                trackURL: trackURL(artist: artist, track: name, mbid: mbids.recordingMbid),
                playcount: nil,
                serviceInfo: [
                    ScrobbleService.listenbrainz.id: ServiceTrackData.listenbrainz(
                        recordingMsid: msid ?? "",
                        timestamp: timestamp ?? 0
                    )
                ],
                sourceService: .listenbrainz
            )
        }
        
        return tracks
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
        return try await getTopTracksWithOffset(username: username, period: period, limit: limit, offset: 0)
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
    
    func getTrackPlaycount(username: String, artist: String, track: String, recordingMbid: String?) async throws -> Int? {
        return cache.getCachedPlayCount(username: username, artist: artist, track: track)
    }
    
    func getTrackUserPlaycount(token: String, artist: String, track: String) async throws -> Int? {
        return nil
    }
    
    func getTrackLoved(token: String, artist: String, track: String) async throws -> Bool {
        return false
    }
    
    // MARK: - Track Enrichment
    
    func enrichTrackWithURLs(_ track: Track) async -> Track {
        var enrichedTrack = track
        
        // Try MBID Mapper for better matching
        if let result = try? await lookupMBIDFromMapper(
            artist: track.artist,
            track: track.name,
            album: track.album.isEmpty ? nil : track.album
        ) {
            enrichedTrack.artistURL = result.artistMbid.map { URL(string: "https://listenbrainz.org/artist/\($0)/")! }
            enrichedTrack.albumURL = result.releaseMbid.map { URL(string: "https://listenbrainz.org/album/\($0)/")! }
            enrichedTrack.trackURL = result.recordingMbid.map { URL(string: "https://listenbrainz.org/track/\($0)/")! }
        }
        
        // Fallback to search URLs if mapper didn't find MBIDs
        if enrichedTrack.artistURL == nil {
            enrichedTrack.artistURL = artistURL(artist: track.artist, mbid: nil)
        }
        if enrichedTrack.albumURL == nil {
            enrichedTrack.albumURL = albumURL(artist: track.artist, album: track.album, mbid: nil)
        }
        if enrichedTrack.trackURL == nil {
            enrichedTrack.trackURL = trackURL(artist: track.artist, track: track.name, mbid: nil)
        }
        
        return enrichedTrack
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
        
        if let mbidMapping = metadata["mbid_mapping"] as? [String: Any] {
            artistMbid = (mbidMapping["artist_mbids"] as? [String])?.first
            releaseMbid = mbidMapping["release_mbid"] as? String
            recordingMbid = mbidMapping["recording_mbid"] as? String
        }
        
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
}
