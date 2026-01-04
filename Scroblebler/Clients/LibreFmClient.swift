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
    
    override func getRecentTracks(limit: Int, page: Int) async throws -> [Track] {
        let tracks = try await super.getRecentTracks(limit: limit, page: page)
        // Replace URLs with Libre.fm specific ones
        return tracks.map { track in
            let encodedArtist = track.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let encodedAlbum = track.album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let encodedTrack = track.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            
            var modifiedTrack = track
            modifiedTrack.artistURL = URL(string: "https://libre.fm/music/\(encodedArtist)")!
            modifiedTrack.albumURL = URL(string: "https://libre.fm/music/\(encodedArtist)/\(encodedAlbum)")!
            modifiedTrack.trackURL = URL(string: "https://libre.fm/music/\(encodedArtist)/_/\(encodedTrack)")!
            modifiedTrack.serviceInfo = [
                .librefm: ServiceTrackData.lastfm(timestamp: track.timestamp)
            ]
            return modifiedTrack
        }
    }
    
    override func getRecentTracksByTimeRange(minTs: Int?, maxTs: Int?, limit: Int) async throws -> [Track]? {
        Logger.debug("Libre.fm getRecentTracksByTimeRange - minTs: \(minTs ?? 0), maxTs: \(maxTs ?? 0), limit: \(limit)", log: Logger.api)
        
        // Call parent implementation and update URLs for Libre.fm
        guard let tracks = try await super.getRecentTracksByTimeRange(minTs: minTs, maxTs: maxTs, limit: limit) else {
            return nil
        }
        
        return tracks.map { track in
            let encodedArtist = track.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let encodedAlbum = track.album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            let encodedTrack = track.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            
            var modifiedTrack = track
            modifiedTrack.artistURL = URL(string: "https://libre.fm/music/\(encodedArtist)")!
            modifiedTrack.albumURL = URL(string: "https://libre.fm/music/\(encodedArtist)/\(encodedAlbum)")!
            modifiedTrack.trackURL = URL(string: "https://libre.fm/music/\(encodedArtist)/_/\(encodedTrack)")!
            modifiedTrack.serviceInfo = [
                .librefm: ServiceTrackData.lastfm(timestamp: track.timestamp)
            ]
            return modifiedTrack
        }
    }
}
