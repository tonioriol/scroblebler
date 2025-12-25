//
//  ScrobbleClient.swift
//  Audioscrobbler
//
//  Created by Audioscrobbler on 24/12/2024.
//

import Foundation

protocol ScrobbleClient {
    var baseURL: URL { get }
    var authURL: String { get }
    
    func authenticate() async throws -> (token: String, authURL: URL)
    func completeAuthentication(token: String) async throws -> (username: String, sessionKey: String, profileUrl: String?, isSubscriber: Bool)
    func updateNowPlaying(sessionKey: String, track: Track) async throws
    func scrobble(sessionKey: String, track: Track) async throws
    
    // Profile methods - return types from Audioscrobbler namespace
    func getRecentTracks(username: String, limit: Int, page: Int) async throws -> [Audioscrobbler.RecentTrack]
    func getUserStats(username: String) async throws -> Audioscrobbler.UserStats?
    func getTopArtists(username: String, period: String, limit: Int) async throws -> [Audioscrobbler.TopArtist]
    func getTopAlbums(username: String, period: String, limit: Int) async throws -> [Audioscrobbler.TopAlbum]
    func getTopTracks(username: String, period: String, limit: Int) async throws -> [Audioscrobbler.TopTrack]
    func getTrackUserPlaycount(token: String, artist: String, track: String) async throws -> Int?
}

// Default implementations for truly optional features
extension ScrobbleClient {
    func updateLove(sessionKey: String, artist: String, track: String, loved: Bool) async throws {
        // Optional - not all services support this
    }
    
    func getTrackUserPlaycount(token: String, artist: String, track: String) async throws -> Int? {
        // Optional - not all services support this
        return nil
    }
}
