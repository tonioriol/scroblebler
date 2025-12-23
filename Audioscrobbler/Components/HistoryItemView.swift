import SwiftUI

struct HistoryItemView: View {
    let track: WebService.RecentTrack
    @State private var loved: Bool
    
    init(track: WebService.RecentTrack) {
        self.track = track
        self._loved = State(initialValue: track.loved)
    }
    
    func formatDate(_ timestamp: Int?) -> String {
        guard let timestamp = timestamp else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .center, spacing: 12) {
                AlbumArtwork(imageUrl: track.imageUrl, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Link(track.name, destination: .lastFmTrack(artist: track.artist, track: track.name))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.lastFmRed)
                        .lineLimit(1)
                        .padding(.trailing, 24)
                    HStack(spacing: 3) {
                        Text("by")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Link(track.artist, destination: .lastFmArtist(track.artist))
                            .font(.system(size: 11))
                            .foregroundColor(.lastFmRed)
                            .lineLimit(1)
                    }
                    if !track.album.isEmpty {
                        HStack(spacing: 3) {
                            Text("on")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Link(track.album, destination: .lastFmAlbum(artist: track.artist, album: track.album))
                                .font(.system(size: 11))
                                .foregroundColor(.lastFmRed)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatDate(track.date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            LoveButton(loved: $loved, artist: track.artist, trackName: track.name, fontSize: 11)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// Preview removed - RecentTrack uses custom Decodable initializer
