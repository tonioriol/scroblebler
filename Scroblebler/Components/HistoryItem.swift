import SwiftUI

struct HistoryItem: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    
    let track: Track
    
    private var syncStatus: SyncStatus {
        let enabledServices = Set(defaults.enabledServices.map { $0.service })
        return track.syncStatus(enabledServices: enabledServices)
    }
    
    var body: some View {
        TrackInfo(
            trackName: track.name,
            artist: track.artist,
            album: track.album,
            loved: .constant(track.loved),
            artworkImageUrl: track.imageUrl,
            timestamp: track.timestamp,
            playCount: .constant(track.playcount),
            artistURL: track.artistURL,
            albumURL: track.albumURL,
            trackURL: track.trackURL,
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
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func convertServiceInfoToStringKeys() -> [String: ServiceTrackData] {
        track.serviceInfo.reduce(into: [:]) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
    }
}
