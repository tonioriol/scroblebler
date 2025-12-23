import SwiftUI

struct TrackInfoView: View {
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
        trackLength: Double? = nil
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
    }
    
    func formatDate(_ timestamp: Int?) -> String {
        guard let timestamp = timestamp else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    func formatDuration(_ value: Double) -> String {
        let hours = value / 3600
        let minutes = Int(value.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(value.truncatingRemainder(dividingBy: 60))
        
        if hours >= 1 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else if minutes >= 1 {
            return String(format: "%02d:%02d", minutes, seconds)
        } else {
            return String(format: "00:%02d", seconds)
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let imageData = artworkImageData {
                AlbumArtwork(imageData: imageData, size: artworkSize)
            } else if let imageUrl = artworkImageUrl {
                AlbumArtwork(imageUrl: imageUrl, size: artworkSize)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Track name - always visible
                        Link(trackName, destination: .lastFmTrack(artist: artist, track: trackName))
                            .font(.system(size: titleFontSize, weight: .semibold))
                            .foregroundColor(.lastFmRed)
                            .lineLimit(1)
                        
                        // Artist - always visible
                        HStack(spacing: 3) {
                            Text("by")
                                .font(.system(size: detailFontSize))
                                .foregroundColor(.secondary)
                            Link(artist, destination: .lastFmArtist(artist))
                                .font(.system(size: detailFontSize))
                                .foregroundColor(.lastFmRed)
                                .lineLimit(1)
                        }
                        
                        // Album - always reserve space
                        HStack(spacing: 3) {
                            Text("on")
                                .font(.system(size: detailFontSize))
                                .foregroundColor(.secondary)
                            if !album.isEmpty {
                                Link(album, destination: .lastFmAlbum(artist: artist, album: album))
                                    .font(.system(size: detailFontSize))
                                    .foregroundColor(.lastFmRed)
                                    .lineLimit(1)
                            } else {
                                Text("Unknown Album")
                                    .font(.system(size: detailFontSize))
                                    .opacity(0)
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
                        VStack(alignment: .trailing, spacing: 0) {
                            LoveButton(loved: $loved, artist: artist, trackName: trackName, fontSize: loveFontSize)
                            Spacer()
                            Text(formatDate(timestamp))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        LoveButton(loved: $loved, artist: artist, trackName: trackName, fontSize: loveFontSize)
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
    }
}
