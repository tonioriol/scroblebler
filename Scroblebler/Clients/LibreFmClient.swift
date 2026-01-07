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
        // Update serviceInfo to mark these as Libre.fm tracks
        return tracks.map { track in
            var modifiedTrack = track
            modifiedTrack.serviceInfo = [
                .librefm: ServiceTrackData.lastfm(timestamp: track.timestamp)
            ]
            return modifiedTrack
        }
    }
    
    override func getRecentTracksByTimeRange(minTs: Int?, maxTs: Int?, limit: Int) async throws -> [Track]? {
        Logger.debug("Libre.fm getRecentTracksByTimeRange - minTs: \(minTs ?? 0), maxTs: \(maxTs ?? 0), limit: \(limit)", log: Logger.api)
        
        guard let tracks = try await super.getRecentTracksByTimeRange(minTs: minTs, maxTs: maxTs, limit: limit) else {
            return nil
        }
        
        // Update serviceInfo to mark these as Libre.fm tracks
        return tracks.map { track in
            var modifiedTrack = track
            modifiedTrack.serviceInfo = [
                .librefm: ServiceTrackData.lastfm(timestamp: track.timestamp)
            ]
            return modifiedTrack
        }
    }
}
