//
//  HistoryItemView.swift
//  Audioscrobbler
//
//  Created by Victor Gama on 23/12/2024.
//

import SwiftUI

struct HistoryItemView: View {
    let track: WebService.RecentTrack
    
    let redColor = Color(hue: 0, saturation: 0.70, brightness: 0.75)
    
    func urlFor(artist: String) -> URL {
        let artist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return URL(string: "https://www.last.fm/music/\(artist)")!
    }
    
    func urlFor(artist: String, album: String) -> URL {
        let artist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let album = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return URL(string: "https://www.last.fm/music/\(artist)/\(album)")!
    }
    
    func formatDate(_ timestamp: Int?) -> String {
        guard let timestamp = timestamp else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Text("by")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Link(track.artist, destination: urlFor(artist: track.artist))
                        .font(.system(size: 11))
                        .foregroundColor(redColor)
                        .lineLimit(1)
                }
                if !track.album.isEmpty {
                    HStack(spacing: 3) {
                        Text("on")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Link(track.album, destination: urlFor(artist: track.artist, album: track.album))
                            .font(.system(size: 11))
                            .foregroundColor(redColor)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            if let date = track.date {
                Text(formatDate(date))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// Preview removed - RecentTrack uses custom Decodable initializer
