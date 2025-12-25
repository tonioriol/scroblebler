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
    
    // Profile methods implemented by each client
    func getRecentTracks(username: String, limit: Int, page: Int) async throws -> [RecentTrack]
    func getUserStats(username: String) async throws -> UserStats?
    func getTopArtists(username: String, period: String, limit: Int) async throws -> [TopArtist]
    func getTopAlbums(username: String, period: String, limit: Int) async throws -> [TopAlbum]
    func getTopTracks(username: String, period: String, limit: Int) async throws -> [TopTrack]
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

// Data types for profile features (mainly used by Last.fm)
struct RecentTrack: Codable {
    let name: String
    let artist: String
    let album: String
    let date: Int?
    let isNowPlaying: Bool
    let loved: Bool
    let imageUrl: String?
    
    init(name: String, artist: String, album: String, date: Int?, isNowPlaying: Bool, loved: Bool, imageUrl: String?) {
        self.name = name
        self.artist = artist
        self.album = album
        self.date = date
        self.isNowPlaying = isNowPlaying
        self.loved = loved
        self.imageUrl = imageUrl
    }
}

struct UserStats: Codable {
    let playcount: Int
    let artistCount: Int
    let trackCount: Int
    let albumCount: Int
    let lovedCount: Int?
    let registered: String?
    let country: String?
    let realname: String?
    let gender: String?
    let age: String?
    let playlistCount: Int?
}

struct TopArtist: Codable {
    let name: String
    let playcount: Int
    let imageUrl: String?
}

struct TopAlbum: Codable {
    let artist: String
    let name: String
    let playcount: Int
    let imageUrl: String?
}

struct TopTrack: Codable {
    let artist: String
    let name: String
    let playcount: Int
    let imageUrl: String?
}
