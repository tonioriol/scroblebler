import SwiftUI
import AppKit

struct TrackInfo<ActionButtons: View, ArtworkOverlay: View>: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @EnvironmentObject var watcher: Watcher

    let trackName: String
    let artist: String
    let album: String
    let artworkSize: CGFloat
    let artworkImageData: Data?
    let artworkImageUrl: String?
    let titleFontSize: CGFloat
    let detailFontSize: CGFloat
    @Binding var loved: Bool
    let loveFontSize: CGFloat

    // For history items
    let timestamp: Int?

    // For now playing (progress bar moved to PlayerControls)
    let currentPosition: Double?
    let trackLength: Double?

    private var sourceBundleIdentifier: String? {
        watcher.currentBundleIdentifier
    }

    // Pre-built URLs (from RecentTrack or Track)
    let artistURL: URL?
    let albumURL: URL?
    let trackURL: URL?

    // Seek callback (moved to PlayerControls)
    let onSeek: ((Double) -> Void)?

    // Optional action buttons
    let actionButtons: ActionButtons?

    // Optional artwork overlay
    let artworkOverlay: ArtworkOverlay?

    @Binding var playCount: Int?

    init(
        trackName: String,
        artist: String,
        album: String,
        loved: Binding<Bool>,
        artworkSize: CGFloat = 48,
        artworkImageData: Data? = nil,
        artworkImageUrl: String? = nil,
        titleFontSize: CGFloat = 13,
        detailFontSize: CGFloat = 11,
        loveFontSize: CGFloat = 11,
        timestamp: Int? = nil,
        currentPosition: Double? = nil,
        trackLength: Double? = nil,
        playCount: Binding<Int?>,
        artistURL: URL? = nil,
        albumURL: URL? = nil,
        trackURL: URL? = nil,
        onSeek: ((Double) -> Void)? = nil,
        @ViewBuilder actionButtons: () -> ActionButtons = { EmptyView() as! ActionButtons },
        @ViewBuilder artworkOverlay: () -> ArtworkOverlay = { EmptyView() as! ArtworkOverlay }
    ) {
        self.trackName = trackName
        self.artist = artist
        self.album = album
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
        self._playCount = playCount
        self.artistURL = artistURL
        self.albumURL = albumURL
        self.trackURL = trackURL
        self.onSeek = onSeek
        self.actionButtons = actionButtons()
        self.artworkOverlay = artworkOverlay()
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
        let displayService = defaults.mainServicePreference ?? defaults.primaryService?.service ?? .lastfm
        let client = serviceManager.client(for: displayService)
        let linkColor = client?.linkColor ?? Color.primary

        // Service-specific fallback homepage
        let fallbackURL: URL = {
            switch displayService {
            case .lastfm:
                return URL(string: "https://www.last.fm")!
            case .librefm:
                return URL(string: "https://libre.fm")!
            case .listenbrainz:
                return URL(string: "https://listenbrainz.org")!
            }
        }()

        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .center) {
                Group {
                    if let imageData = artworkImageData {
                        AlbumArtwork(imageData: imageData, size: artworkSize)
                    } else {
                        AlbumArtwork(imageUrl: artworkImageUrl, size: artworkSize)
                    }
                }
                .onTapGesture { openSourceAppIfPossible() }
                .modifier(HelpIfAvailable(text: "Open player", isEnabled: sourceBundleIdentifier?.isEmpty == false))

                if let overlay = artworkOverlay {
                    overlay
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Track name
                        Link(destination: trackURL ?? fallbackURL) {
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
                                Link(destination: artistURL ?? fallbackURL) {
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
                                Link(destination: albumURL ?? fallbackURL) {
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
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            if let count = playCount {
                                Text("\(count) \(count == 1 ? "scrobble" : "scrobbles")")
                                    .font(.system(size: loveFontSize - 1))
                                    .foregroundColor(.secondary)
                                Text("·")
                                    .font(.system(size: loveFontSize - 1))
                                    .foregroundColor(.secondary)
                            }
                            LoveButton(artist: artist, trackName: trackName, fontSize: loveFontSize)
                        }
                        if let actionButtons = actionButtons {
                            actionButtons
                        }
                        if let timestamp = timestamp {
                            Text(formatDate(timestamp))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func openSourceAppIfPossible() {
        guard let bundleId = sourceBundleIdentifier, !bundleId.isEmpty else { return }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
    }
}

private struct HelpIfAvailable: ViewModifier {
    let text: String
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.help(text)
        } else {
            content
        }
    }
}
