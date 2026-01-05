import Foundation
import SwiftUI
@testable import Scroblebler

/// Fake implementation of ScrobbleClient for testing
/// Records all operations instead of making network calls
class FakeScrobbleClient: ScrobbleClient {
    let baseURL: URL
    let authURL: String
    let linkColor: Color
    let service: ScrobbleService
    
    // Recorded operations
    var scrobbledTracks: [Track] = []
    var nowPlayingTracks: [Track] = []
    var lovedTracks: [(artist: String, track: String, loved: Bool)] = []
    var deletedScrobbles: [ScrobbleIdentifier] = []
    var authAttempts: Int = 0
    
    // Stored credentials
    var storedUsername: String?
    var storedSessionKey: String?
    
    // Controllable behavior
    var shouldFailScrobble = false
    var shouldFailAuth = false
    var shouldFailLove = false
    var shouldFailDelete = false
    var shouldFailNowPlaying = false
    var shouldFailGetRecentTracks = false
    var networkDelay: TimeInterval = 0
    var errorToThrow: Error?
    
    // Data to return
    var historyToReturn: [Track] = []
    var userStatsToReturn: UserStats?
    var topArtistsToReturn: [TopArtist] = []
    var topAlbumsToReturn: [TopAlbum] = []
    var topTracksToReturn: [TopTrack] = []
    var trackInfoToReturn: (loved: Bool, playcount: Int?) = (false, nil)
    
    init(
        service: ScrobbleService,
        baseURL: String = "https://fake.api",
        authURL: String = "https://fake.auth",
        linkColor: Color = .blue
    ) {
        self.service = service
        self.baseURL = URL(string: baseURL)!
        self.authURL = authURL
        self.linkColor = linkColor
    }
    
    // MARK: - Authentication
    
    func authenticate() async throws -> (token: String, authURL: URL) {
        authAttempts += 1
        
        if shouldFailAuth {
            throw NSError(domain: "FakeClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Auth failed"])
        }
        
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        return ("fake-token-\(UUID().uuidString)", URL(string: authURL)!)
    }
    
    func completeAuthentication(token: String) async throws -> (username: String, sessionKey: String, profileUrl: String?, isSubscriber: Bool) {
        if shouldFailAuth {
            throw NSError(domain: "FakeClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Auth completion failed"])
        }
        
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        let username = "test_user_\(service.id)"
        let sessionKey = "fake-session-\(UUID().uuidString)"
        let profileUrl = "https://fake.profile/\(username)"
        
        storedUsername = username
        storedSessionKey = sessionKey
        
        return (username, sessionKey, profileUrl, false)
    }
    
    func setCredentials(username: String, sessionKey: String) {
        storedUsername = username
        storedSessionKey = sessionKey
    }
    
    // MARK: - Scrobbling
    
    func updateNowPlaying(track: Track) async throws {
        if shouldFailNowPlaying {
            if let error = errorToThrow {
                throw error
            }
            throw NSError(domain: "FakeClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "Now playing failed"])
        }
        
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        nowPlayingTracks.append(track)
    }
    
    func scrobble(track: Track) async throws {
        if shouldFailScrobble {
            if let error = errorToThrow {
                throw error
            }
            throw NSError(domain: "FakeClient", code: 3, userInfo: [NSLocalizedDescriptionKey: "Scrobble failed"])
        }
        
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        scrobbledTracks.append(track)
    }
    
    func updateLove(artist: String, track: String, loved: Bool) async throws {
        if shouldFailLove {
            if let error = errorToThrow {
                throw error
            }
            throw NSError(domain: "FakeClient", code: 4, userInfo: [NSLocalizedDescriptionKey: "Love update failed"])
        }
        
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        lovedTracks.append((artist, track, loved))
    }
    
    func deleteScrobble(identifier: ScrobbleIdentifier) async throws {
        if shouldFailDelete {
            if let error = errorToThrow {
                throw error
            }
            throw NSError(domain: "FakeClient", code: 5, userInfo: [NSLocalizedDescriptionKey: "Delete failed"])
        }
        
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        deletedScrobbles.append(identifier)
    }
    
    // MARK: - Profile
    
    func getRecentTracks(limit: Int, page: Int) async throws -> [Track] {
        if shouldFailGetRecentTracks {
            if let error = errorToThrow {
                throw error
            }
            throw NSError(domain: "FakeClient", code: 6, userInfo: [NSLocalizedDescriptionKey: "Get tracks failed"])
        }
        
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        // Paginate the history
        let startIndex = (page - 1) * limit
        let endIndex = min(startIndex + limit, historyToReturn.count)
        
        guard startIndex < historyToReturn.count else {
            return []
        }
        
        return Array(historyToReturn[startIndex..<endIndex])
    }
    
    func getRecentTracksByTimeRange(minTs: Int?, maxTs: Int?, limit: Int) async throws -> [Track]? {
        if shouldFailGetRecentTracks {
            throw NSError(domain: "FakeClient", code: 6, userInfo: [NSLocalizedDescriptionKey: "Get tracks failed"])
        }
        
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        var filtered = historyToReturn
        
        if let minTs = minTs {
            filtered = filtered.filter { $0.timestamp >= minTs }
        }
        
        if let maxTs = maxTs {
            filtered = filtered.filter { $0.timestamp <= maxTs }
        }
        
        return Array(filtered.prefix(limit))
    }
    
    func getUserStats() async throws -> UserStats? {
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        return userStatsToReturn
    }
    
    func getTopArtists(period: String, limit: Int) async throws -> [TopArtist] {
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        return Array(topArtistsToReturn.prefix(limit))
    }
    
    func getTopAlbums(period: String, limit: Int) async throws -> [TopAlbum] {
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        return Array(topAlbumsToReturn.prefix(limit))
    }
    
    func getTopTracks(period: String, limit: Int) async throws -> [TopTrack] {
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        return Array(topTracksToReturn.prefix(limit))
    }
    
    func getTrackInfo(artist: String, track: String) async throws -> (loved: Bool, playcount: Int?) {
        if networkDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(networkDelay * 1_000_000_000))
        }
        
        return trackInfoToReturn
    }
    
    // MARK: - Test Helpers
    
    func reset() {
        scrobbledTracks.removeAll()
        nowPlayingTracks.removeAll()
        lovedTracks.removeAll()
        deletedScrobbles.removeAll()
        authAttempts = 0
        shouldFailScrobble = false
        shouldFailAuth = false
        shouldFailLove = false
        shouldFailDelete = false
        shouldFailNowPlaying = false
        shouldFailGetRecentTracks = false
        networkDelay = 0
        errorToThrow = nil
    }
    
    func recordedScrobble(artist: String, track: String) -> Track? {
        scrobbledTracks.first { $0.artist == artist && $0.name == track }
    }
    
    func didScrobble(artist: String, track: String) -> Bool {
        recordedScrobble(artist: artist, track: track) != nil
    }
    
    func didLove(artist: String, track: String, loved: Bool) -> Bool {
        lovedTracks.contains { $0.artist == artist && $0.track == track && $0.loved == loved }
    }
    
    func didDelete(artist: String, track: String) -> Bool {
        deletedScrobbles.contains { $0.artist == artist && $0.track == track }
    }
}
