import SwiftUI

struct HistoryItem: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    
    let track: Track
    @State private var serviceInfo: [ScrobbleService: ServiceTrackData]
    
    init(track: Track) {
        self.track = track
        self._serviceInfo = State(initialValue: track.serviceInfo)
    }
    
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TrackBackfillSucceeded"))) { notification in
            updateSyncStatus(from: notification)
        }
    }
    
    private func convertServiceInfoToStringKeys() -> [String: ServiceTrackData] {
        serviceInfo.reduce(into: [:]) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
    }
    
    private func updateSyncStatus(from notification: Notification) {
        guard let userInfo = notification.userInfo,
              let artist = userInfo["artist"] as? String,
              let trackName = userInfo["track"] as? String,
              let timestamp = userInfo["timestamp"] as? Int else {
            return
        }
        
        // Check if this notification is for our track
        guard track.artist == artist,
              track.name == trackName,
              track.timestamp == timestamp else {
            return
        }
        
        // Add the newly synced service to serviceInfo
        if let serviceRawValue = userInfo["service"] as? String,
           let service = ScrobbleService(rawValue: serviceRawValue) {
            // Update serviceInfo - syncStatus will be recomputed automatically
            serviceInfo[service] = ServiceTrackData(timestamp: timestamp, id: nil)
        }
    }
}
