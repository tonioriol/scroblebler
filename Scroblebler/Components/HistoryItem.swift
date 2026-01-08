import SwiftUI

struct HistoryItem: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    
    let track: Track
    @State private var isHovered = false
    @State private var playbackState: PlaybackState = .idle
    
    private enum PlaybackState {
        case idle
        case success
        case failed
    }
    
    private var syncStatus: SyncStatus {
        let enabledServices = Set(defaults.enabledServices.map { $0.service })
        return track.syncStatus(enabledServices: enabledServices)
    }
    
    var body: some View {
        let displayService = defaults.mainServicePreference ?? defaults.primaryService?.service ?? .lastfm
        let service = serviceManager.service(for: displayService)
        let urls = service?.buildURLs(for: track)
        
        TrackInfo(
            trackName: track.name,
            artist: track.artist,
            album: track.album,
            loved: .constant(track.loved),
            artworkImageUrl: track.imageUrl,
            timestamp: track.timestamp,
            playCount: .constant(track.playcount),
            artistURL: urls?.artistURL,
            albumURL: urls?.albumURL,
            trackURL: urls?.trackURL,
            actionButtons: {
                HStack(spacing: 4) {
                    // Sync status indicator
                    SyncStatusBadge(
                        syncStatus: syncStatus,
                        serviceInfo: convertServiceInfoToStringKeys(),
                        sourceService: track.sourceService
                    )
                    
                    UndoButton(
                        artist: track.artist,
                        track: track.name,
                        album: track.album,
                        serviceInfo: convertServiceInfoToStringKeys()
                    )
                    .id("\(track.artist)-\(track.name)-\(track.timestamp)")
                    
                    BlacklistButton(
                        artist: track.artist,
                        track: track.name
                    )
                }
            },
            artworkOverlay: {
                if isHovered || playbackState != .idle {
                    Button(action: playTrack) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: iconName)
                                .foregroundColor(iconColor)
                                .font(.system(size: 14))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(tooltipText)
                }
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var iconName: String {
        switch playbackState {
        case .idle: return "play.fill"
        case .success: return "checkmark"
        case .failed: return "xmark"
        }
    }
    
    private var iconColor: Color {
        switch playbackState {
        case .idle, .success: return .white
        case .failed: return .red
        }
    }
    
    private var tooltipText: String {
        switch playbackState {
        case .idle: return "Play in Apple Music"
        case .success: return "Playing..."
        case .failed: return "Track not found in library"
        }
    }
    
    private func playTrack() {
        playbackState = .success
        
        Task {
            do {
                try HistoryPlay.playTrack(artist: track.artist, track: track.name)
                Logger.info("Successfully initiated playback for '\(track.name)' by '\(track.artist)'")
                playbackState = .success
                
                // Reset icon after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                playbackState = .idle
            } catch {
                Logger.error("Failed to play track '\(track.name)' by '\(track.artist)': \(error)")
                playbackState = .failed
                
                // Reset icon after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                playbackState = .idle
            }
        }
    }
    
    private func convertServiceInfoToStringKeys() -> [String: ServiceTrackData] {
        track.serviceInfo.reduce(into: [:]) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
    }
}
