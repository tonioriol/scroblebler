import Foundation
import SwiftUI

protocol ScrobbleClient {
    var baseURL: URL { get }
    var authURL: String { get }
    var linkColor: Color { get }
    
    func authenticate() async throws -> (token: String, authURL: URL)
    func completeAuthentication(token: String) async throws -> (username: String, sessionKey: String, profileUrl: String?, isSubscriber: Bool)
    func updateNowPlaying(sessionKey: String, track: Track) async throws
    func scrobble(sessionKey: String, track: Track) async throws
    func updateLove(sessionKey: String, artist: String, track: String, loved: Bool) async throws
    
    // Profile methods
    func getRecentTracks(username: String, limit: Int, page: Int, token: String?) async throws -> [RecentTrack]
    func getUserStats(username: String) async throws -> UserStats?
    func getTopArtists(username: String, period: String, limit: Int) async throws -> [TopArtist]
    func getTopAlbums(username: String, period: String, limit: Int) async throws -> [TopAlbum]
    func getTopTracks(username: String, period: String, limit: Int) async throws -> [TopTrack]
    func getTrackUserPlaycount(token: String, artist: String, track: String) async throws -> Int?
    func getTrackLoved(token: String, artist: String, track: String) async throws -> Bool
    func deleteScrobble(sessionKey: String, identifier: ScrobbleIdentifier) async throws
}

// Optional features with default implementations
extension ScrobbleClient {
    func updateLove(sessionKey: String, artist: String, track: String, loved: Bool) async throws {
        // Optional - not all services support this
    }
    
    func deleteScrobble(sessionKey: String, identifier: ScrobbleIdentifier) async throws {
        // Optional - not all services support this
    }
    
    func getTrackUserPlaycount(token: String, artist: String, track: String) async throws -> Int? {
        return nil
    }
    
    func getTrackLoved(token: String, artist: String, track: String) async throws -> Bool {
        return false
    }
    
    func getRecentTracksByTimeRange(username: String, minTs: Int?, maxTs: Int?, limit: Int, token: String?) async throws -> [RecentTrack]? {
        // Optional - only services that support timestamp-based queries implement this
        return nil
    }
}
