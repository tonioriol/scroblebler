import Foundation
import SwiftUI

class ListenBrainzClient: ObservableObject, ScrobbleClient {
    enum Error: Swift.Error {
        case invalidToken
        case serverError(String)
    }
    
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
    
    func getRecentTracks(username: String, limit: Int, page: Int) async throws -> [RecentTrack] {
        let offset = (page - 1) * limit
        var components = URLComponents(url: baseURL.appendingPathComponent("user/\(username)/listens"), resolvingAgainstBaseURL: false)!
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
            
            return RecentTrack(
                name: name,
                artist: artist,
                album: album,
                date: listen["listened_at"] as? Int,
                isNowPlaying: false,
                loved: false,
                imageUrl: imageUrl,
                artistURL: self.artistURL(artist: artist, mbid: artistMbid),
                albumURL: self.albumURL(artist: artist, album: album, mbid: releaseMbid),
                trackURL: self.trackURL(artist: artist, track: name, mbid: recordingMbid)
            )
        }
    }
    
    func getUserStats(username: String) async throws -> UserStats? {
        let url = baseURL.appendingPathComponent("user/\(username)/listen-count")
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
        var components = URLComponents(url: baseURL.appendingPathComponent("stats/user/\(username)/artists"), resolvingAgainstBaseURL: false)!
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
        var components = URLComponents(url: baseURL.appendingPathComponent("stats/user/\(username)/releases"), resolvingAgainstBaseURL: false)!
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
        var components = URLComponents(url: baseURL.appendingPathComponent("stats/user/\(username)/recordings"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "count", value: "\(limit)")
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
        default: return "week"
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
}
