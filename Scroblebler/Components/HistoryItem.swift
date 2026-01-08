import SwiftUI

struct HistoryItem: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    
    let track: Track
    @State private var isHovered = false
    @State private var isPlayingTrack = false
    
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
                if isHovered || isPlayingTrack {
                    Button(action: playTrack) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: isPlayingTrack ? "checkmark" : "play.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 14))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Play in Apple Music")
                }
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func playTrack() {
        isPlayingTrack = true
        
        Task {
            do {
                try HistoryPlay.playTrack(artist: track.artist, track: track.name)
                Logger.info("Successfully initiated playback for '\(track.name)' by '\(track.artist)'")
                
                // Reset icon after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                isPlayingTrack = false
            } catch {
                Logger.error("Failed to play track '\(track.name)' by '\(track.artist)': \(error)")
                isPlayingTrack = false
            }
        }
    }
    
    private func convertServiceInfoToStringKeys() -> [String: ServiceTrackData] {
        track.serviceInfo.reduce(into: [:]) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
    }
}
