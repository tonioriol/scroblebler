//
//  LibreFmClient.swift
//  Scroblebler
//
//  Created by Scroblebler on 24/12/2024.
//

import Foundation
import SwiftUI

class LibreFmClient: LastFmClient {
    override var baseURL: URL {
        URL(string: "https://libre.fm/2.0/")!
    }
    
    override var authURL: String {
        "https://libre.fm/api/auth/"
    }
    
    override var linkColor: Color {
        Color(hue: 0.94, saturation: 0.60, brightness: 0.90)
    }
    
    override func getRecentTracks(username: String, limit: Int, page: Int, token: String?) async throws -> [RecentTrack] {
        let tracks = try await super.getRecentTracks(username: username, limit: limit, page: page, token: token)
        // Replace URLs with Libre.fm specific ones
        return tracks.map { track in
            let encodedArtist = track.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let encodedAlbum = track.album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let encodedTrack = track.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            
            return RecentTrack(
                name: track.name,
                artist: track.artist,
                album: track.album,
                date: track.date,
                isNowPlaying: track.isNowPlaying,
                loved: track.loved,
                imageUrl: track.imageUrl,
                artistURL: URL(string: "https://libre.fm/music/\(encodedArtist)")!,
                albumURL: URL(string: "https://libre.fm/music/\(encodedArtist)/\(encodedAlbum)")!,
                trackURL: URL(string: "https://libre.fm/music/\(encodedArtist)/_/\(encodedTrack)")!,
                playcount: track.playcount,
                serviceInfo: [
                    ScrobbleService.librefm.id: ServiceTrackData.lastfm(timestamp: track.date ?? 0)
                ],
                sourceService: .librefm
            )
        }
    }
    
    override func getRecentTracksByTimeRange(username: String, minTs: Int?, maxTs: Int?, limit: Int, token: String?) async throws -> [RecentTrack]? {
        print("🎵 [Libre.fm] getRecentTracksByTimeRange - minTs: \(minTs ?? 0), maxTs: \(maxTs ?? 0), limit: \(limit)")
        
        // Call parent implementation and update URLs for Libre.fm
        guard let tracks = try await super.getRecentTracksByTimeRange(username: username, minTs: minTs, maxTs: maxTs, limit: limit, token: token) else {
            return nil
        }
        
        return tracks.map { track in
            let encodedArtist = track.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let encodedAlbum = track.album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let encodedTrack = track.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            
            return RecentTrack(
                name: track.name,
                artist: track.artist,
                album: track.album,
                date: track.date,
                isNowPlaying: track.isNowPlaying,
                loved: track.loved,
                imageUrl: track.imageUrl,
                artistURL: URL(string: "https://libre.fm/music/\(encodedArtist)")!,
                albumURL: URL(string: "https://libre.fm/music/\(encodedArtist)/\(encodedAlbum)")!,
                trackURL: URL(string: "https://libre.fm/music/\(encodedArtist)/_/\(encodedTrack)")!,
                playcount: track.playcount,
                serviceInfo: [
                    ScrobbleService.librefm.id: ServiceTrackData.lastfm(timestamp: track.date ?? 0)
                ],
                sourceService: .librefm
            )
        }
    }
}
