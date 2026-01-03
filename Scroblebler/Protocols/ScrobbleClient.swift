import Foundation
import SwiftUI

protocol ScrobbleClient {
    var baseURL: URL { get }
    var authURL: String { get }
    var linkColor: Color { get }
    
    func authenticate() async throws -> (token: String, authURL: URL)
    func completeAuthentication(token: String) async throws -> (username: String, sessionKey: String, profileUrl: String?, isSubscriber: Bool)
    
    // Credential restoration (for app restart)
    func setCredentials(username: String, sessionKey: String)
    
    func updateNowPlaying(track: Track) async throws
    func scrobble(track: Track) async throws
    func updateLove(artist: String, track: String, loved: Bool) async throws
    
    // Profile methods
    func getRecentTracks(limit: Int, page: Int) async throws -> [RecentTrack]
    func getRecentTracksByTimeRange(minTs: Int?, maxTs: Int?, limit: Int) async throws -> [RecentTrack]?
    func getUserStats() async throws -> UserStats?
    func getTopArtists(period: String, limit: Int) async throws -> [TopArtist]
    func getTopAlbums(period: String, limit: Int) async throws -> [TopAlbum]
    func getTopTracks(period: String, limit: Int) async throws -> [TopTrack]
    func getTrackInfo(artist: String, track: String) async throws -> (loved: Bool, playcount: Int?)
    func deleteScrobble(identifier: ScrobbleIdentifier) async throws
}

// Optional features with default implementations
extension ScrobbleClient {
    func updateLove(artist: String, track: String, loved: Bool) async throws {
        // Optional - not all services support this
    }
    
    func deleteScrobble(identifier: ScrobbleIdentifier) async throws {
        // Optional - not all services support this
    }
    
    func getRecentTracksByTimeRange(minTs: Int?, maxTs: Int?, limit: Int) async throws -> [RecentTrack]? {
        // Optional - only services that support timestamp-based queries implement this
        return nil
    }
}
