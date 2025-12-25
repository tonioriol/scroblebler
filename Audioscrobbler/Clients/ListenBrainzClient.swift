//
//  ListenBrainzClient.swift
//  Audioscrobbler
//
//  Created by Audioscrobbler on 24/12/2024.
//

import Foundation

class ListenBrainzClient: ObservableObject, ScrobbleClient {
    var baseURL: URL { URL(string: "https://api.listenbrainz.org/1/")! }
    var authURL: String { "https://listenbrainz.org/settings/" }
    
    enum LBError: Error {
        case invalidToken
        case invalidCode
        case serverError(String)
    }
    
    func authenticate() async throws -> (token: String, authURL: URL) {
        // Return the settings page URL where users can copy their personal token
        return ("", URL(string: authURL)!)
    }
    
    func completeAuthentication(token: String) async throws -> (username: String, sessionKey: String, profileUrl: String?, isSubscriber: Bool) {
        // Validate the personal token and get username
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedToken.isEmpty else {
            throw LBError.invalidToken
        }
        
        var request = URLRequest(url: baseURL.appendingPathComponent("validate-token"))
        request.httpMethod = "GET"
        request.setValue("Token \(trimmedToken)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LBError.serverError("Invalid response from validate-token endpoint")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LBError.serverError("Token validation failed (HTTP \(httpResponse.statusCode)): \(errorMsg)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let valid = json?["valid"] as? Bool, valid,
              let username = json?["user_name"] as? String else {
            throw LBError.invalidToken
        }
        
        let profileUrl = "https://listenbrainz.org/user/\(username)/"
        return (username, token, profileUrl, false)
    }
    
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
    
    private func sendRequest(endpoint: String, token: String, payload: [String: Any]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LBError.serverError("Invalid response")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LBError.serverError("HTTP \(httpResponse.statusCode): \(errorMsg)")
        }
    }
    
    // Profile features implementation
    func getRecentTracks(username: String, limit: Int, page: Int) async throws -> [Audioscrobbler.RecentTrack] {
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
            let timestamp = listen["listened_at"] as? Int
            
            return Audioscrobbler.RecentTrack(
                name: name,
                artist: artist,
                album: album,
                date: timestamp,
                isNowPlaying: false,
                loved: false,
                imageUrl: nil
            )
        }
    }
    
    func getUserStats(username: String) async throws -> Audioscrobbler.UserStats? {
        let url = baseURL.appendingPathComponent("user/\(username)/listen-count")
        let (data, _) = try await URLSession.shared.data(from: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let count = payload?["count"] as? Int ?? 0
        
        return Audioscrobbler.UserStats(
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
    
    func getTopArtists(username: String, period: String, limit: Int) async throws -> [Audioscrobbler.TopArtist] {
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
            return Audioscrobbler.TopArtist(name: name, playcount: count, imageUrl: nil)
        }
    }
    
    func getTopAlbums(username: String, period: String, limit: Int) async throws -> [Audioscrobbler.TopAlbum] {
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
            return Audioscrobbler.TopAlbum(artist: artist, name: name, playcount: count, imageUrl: nil)
        }
    }
    
    func getTopTracks(username: String, period: String, limit: Int) async throws -> [Audioscrobbler.TopTrack] {
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
            return Audioscrobbler.TopTrack(artist: artist, name: name, playcount: count, imageUrl: nil)
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
    
    func getTrackUserPlaycount(token: String, artist: String, track: String) async throws -> Int? {
        // ListenBrainz doesn't provide per-track playcount
        return nil
    }
    
    func updateLove(sessionKey: String, artist: String, track: String, loved: Bool) async throws {
        // ListenBrainz doesn't support love/unlove
    }
}
