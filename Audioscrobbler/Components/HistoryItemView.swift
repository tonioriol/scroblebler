//
//  HistoryItemView.swift
//  Audioscrobbler
//
//  Created by Victor Gama on 23/12/2024.
//

import SwiftUI

struct HistoryItemView: View {
    @EnvironmentObject var webService: WebService
    @EnvironmentObject var defaults: Defaults
    let track: WebService.RecentTrack
    @State private var loved: Bool
    
    init(track: WebService.RecentTrack) {
        self.track = track
        self._loved = State(initialValue: track.loved)
    }
    
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
            HStack(spacing: 8) {
                Button(action: toggleLove) {
                    Image(systemName: loved ? "heart.fill" : "heart")
                        .foregroundColor(loved ? .red : .secondary)
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help(loved ? "Unlove track" : "Love track")
                
                if let date = track.date {
                    Text(formatDate(date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    func toggleLove() {
        guard let token = defaults.token else { return }
        
        Task {
            do {
                loved.toggle()
                try await webService.updateLove(token: token, artist: track.artist, track: track.name, loved: loved)
            } catch {
                loved.toggle()
                print("Failed to toggle love: \(error)")
            }
        }
    }
}

// Preview removed - RecentTrack uses custom Decodable initializer
