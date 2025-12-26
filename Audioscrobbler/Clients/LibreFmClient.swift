//
//  LibreFmClient.swift
//  Audioscrobbler
//
//  Created by Audioscrobbler on 24/12/2024.
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
        Color(hue: 0.33, saturation: 0.70, brightness: 0.65)
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
                    ScrobbleService.librefm.id: ServiceTrackData(timestamp: track.date, id: nil)
                ],
                sourceService: .librefm
            )
        }
    }
}
