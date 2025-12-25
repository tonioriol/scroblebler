import SwiftUI

struct TrackInfo: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    
    let trackName: String
    let artist: String
    let album: String
    let year: Int?
    let artworkSize: CGFloat
    let artworkImageData: Data?
    let artworkImageUrl: String?
    let titleFontSize: CGFloat
    let detailFontSize: CGFloat
    @Binding var loved: Bool
    let loveFontSize: CGFloat
    
    // For history items
    let timestamp: Int?
    
    // For now playing
    let currentPosition: Double?
    let trackLength: Double?
    
    // Pre-built URLs (from RecentTrack)
    let artistURL: URL?
    let albumURL: URL?
    let trackURL: URL?
    
    @State private var playCount: Int? = nil
    
    init(
        trackName: String,
        artist: String,
        album: String,
        loved: Binding<Bool>,
        year: Int? = nil,
        artworkSize: CGFloat = 48,
        artworkImageData: Data? = nil,
        artworkImageUrl: String? = nil,
        titleFontSize: CGFloat = 13,
        detailFontSize: CGFloat = 11,
        loveFontSize: CGFloat = 11,
        timestamp: Int? = nil,
        currentPosition: Double? = nil,
        trackLength: Double? = nil,
        playCount: Int? = nil,
        artistURL: URL? = nil,
        albumURL: URL? = nil,
        trackURL: URL? = nil
    ) {
        self.trackName = trackName
        self.artist = artist
        self.album = album
        self.year = year
        self._loved = loved
        self.artworkSize = artworkSize
        self.artworkImageData = artworkImageData
        self.artworkImageUrl = artworkImageUrl
        self.titleFontSize = titleFontSize
        self.detailFontSize = detailFontSize
        self.loveFontSize = loveFontSize
        self.timestamp = timestamp
        self.currentPosition = currentPosition
        self.trackLength = trackLength
        self._playCount = State(initialValue: playCount)
        self.artistURL = artistURL
        self.albumURL = albumURL
        self.trackURL = trackURL
    }
    
    func formatDate(_ timestamp: Int?) -> String {
        guard let timestamp = timestamp else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    func formatDuration(_ value: Double) -> String {
        let hours = Int(value / 3600)
        let minutes = Int(value.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(value.truncatingRemainder(dividingBy: 60))
        
        if hours >= 1 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes >= 1 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
    
    var body: some View {
        let primaryService = defaults.primaryService?.service ?? .lastfm
        let client = serviceManager.client(for: primaryService)
        let linkColor = client?.linkColor ?? Color.primary
        
        // Build URLs on the fly if not provided (for NowPlaying)
        let finalTrackURL = trackURL ?? buildTrackURL(client: client)
        let finalArtistURL = artistURL ?? buildArtistURL(client: client)
        let finalAlbumURL = albumURL ?? buildAlbumURL(client: client)
        
        HStack(alignment: .top, spacing: 12) {
            if let imageData = artworkImageData {
                AlbumArtwork(imageData: imageData, size: artworkSize)
            } else {
                AlbumArtwork(imageUrl: artworkImageUrl, size: artworkSize)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Track name
                        Link(destination: finalTrackURL) {
                            MarqueeText(
                                text: trackName,
                                font: .system(size: titleFontSize, weight: .semibold),
                                foregroundColor: linkColor,
                                fontSize: titleFontSize,
                                fontWeight: .semibold
                            )
                        }
                        
                        // Artist
                        HStack(spacing: 3) {
                            if !artist.isEmpty {
                                Text("by")
                                    .font(.system(size: detailFontSize))
                                    .foregroundColor(.secondary)
                                Link(destination: finalArtistURL) {
                                    MarqueeText(
                                        text: artist,
                                        font: .system(size: detailFontSize),
                                        foregroundColor: linkColor,
                                        fontSize: detailFontSize,
                                        fontWeight: .regular
                                    )
                                }
                            } else {
                                Text("")
                                    .font(.system(size: detailFontSize))
                            }
                        }
                        
                        // Album
                        HStack(spacing: 3) {
                            if !album.isEmpty {
                                Text("on")
                                    .font(.system(size: detailFontSize))
                                    .foregroundColor(.secondary)
                                Link(destination: finalAlbumURL) {
                                    MarqueeText(
                                        text: album,
                                        font: .system(size: detailFontSize),
                                        foregroundColor: linkColor,
                                        fontSize: detailFontSize,
                                        fontWeight: .regular
                                    )
                                }
                            } else {
                                Text("")
                                    .font(.system(size: detailFontSize))
                            }
                        }
                        
                        // Year - only show if we have data
                        if let year = year {
                            HStack(spacing: 3) {
                                Text("released")
                                    .font(.system(size: detailFontSize))
                                    .foregroundColor(.secondary)
                                Text("\(String(format: "%04d", year))")
                                    .font(.system(size: detailFontSize))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if let timestamp = timestamp {
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 4) {
                                let count = playCount ?? 0
                                Text("\(count) \(count == 1 ? "scrobble" : "scrobbles")")
                                    .font(.system(size: loveFontSize - 1))
                                    .foregroundColor(.secondary)
                                Text("·")
                                    .font(.system(size: loveFontSize - 1))
                                    .foregroundColor(.secondary)
                                LoveButton(loved: $loved, artist: artist, trackName: trackName, fontSize: loveFontSize)
                            }
                            Spacer()
                            Text(formatDate(timestamp))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            let count = playCount ?? 0
                            Text("\(count) \(count == 1 ? "scrobble" : "scrobbles")")
                                .font(.system(size: loveFontSize - 1))
                                .foregroundColor(.secondary)
                            Text("·")
                                .font(.system(size: loveFontSize - 1))
                                .foregroundColor(.secondary)
                            LoveButton(loved: $loved, artist: artist, trackName: trackName, fontSize: loveFontSize)
                        }
                    }
                }
                
                // Progress bar or timestamp placeholder - always reserve space
                if let currentPosition = currentPosition, let trackLength = trackLength {
                    HStack(spacing: 8) {
                        Text(formatDuration(currentPosition))
                            .font(.caption)
                        ProgressBar(value: currentPosition, maxValue: trackLength)
                            .frame(height: 8)
                        Text(formatDuration(trackLength))
                            .font(.caption)
                    }
                } else if timestamp == nil {
                    // Reserve space for progress bar even if not present
                    HStack(spacing: 8) {
                        Text("00:00")
                            .font(.caption)
                            .opacity(0)
                        Rectangle()
                            .frame(height: 8)
                            .opacity(0)
                        Text("00:00")
                            .font(.caption)
                            .opacity(0)
                    }
                }
            }
        }
        .onAppear {
            if playCount == nil {
                fetchPlayCount()
            }
        }
        .onChange(of: trackName) { _ in
            if playCount == nil {
                fetchPlayCount()
            }
        }
    }
    
    func fetchPlayCount() {
        guard let primary = defaults.primaryService,
              primary.service == .lastfm else { return }
        guard let client = serviceManager.client(for: .lastfm) else { return }
        Task {
            let count = try? await client.getTrackUserPlaycount(token: primary.token, artist: artist, track: trackName)
            await MainActor.run {
                playCount = count
            }
        }
    }
    
    // Fallback URL builders for NowPlaying (when URLs not pre-built)
    private func buildArtistURL(client: ScrobbleClient?) -> URL {
        guard let service = defaults.primaryService?.service else {
            return URL(string: "https://www.last.fm")!
        }
        let encoded = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        switch service {
        case .lastfm:
            return URL(string: "https://www.last.fm/music/\(encoded)")!
        case .librefm:
            return URL(string: "https://libre.fm/music/\(encoded)")!
        case .listenbrainz:
            return URL(string: "https://musicbrainz.org/search?query=artist:%22\(encoded)%22&type=artist&limit=1&method=advanced")!
        }
    }
    
    private func buildAlbumURL(client: ScrobbleClient?) -> URL {
        guard let service = defaults.primaryService?.service else {
            return URL(string: "https://www.last.fm")!
        }
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let encodedAlbum = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        switch service {
        case .lastfm:
            return URL(string: "https://www.last.fm/music/\(encodedArtist)/\(encodedAlbum)")!
        case .librefm:
            return URL(string: "https://libre.fm/music/\(encodedArtist)/\(encodedAlbum)")!
        case .listenbrainz:
            return URL(string: "https://musicbrainz.org/search?query=artist:%22\(encodedArtist)%22%20AND%20release:%22\(encodedAlbum)%22&type=release&limit=1&method=advanced")!
        }
    }
    
    private func buildTrackURL(client: ScrobbleClient?) -> URL {
        guard let service = defaults.primaryService?.service else {
            return URL(string: "https://www.last.fm")!
        }
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let encodedTrack = trackName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        switch service {
        case .lastfm:
            return URL(string: "https://www.last.fm/music/\(encodedArtist)/_/\(encodedTrack)")!
        case .librefm:
            return URL(string: "https://libre.fm/music/\(encodedArtist)/_/\(encodedTrack)")!
        case .listenbrainz:
            return URL(string: "https://musicbrainz.org/search?query=artist:%22\(encodedArtist)%22%20AND%20recording:%22\(encodedTrack)%22&type=recording&limit=1&method=advanced")!
        }
    }
}
