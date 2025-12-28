import SwiftUI

struct HistoryItem: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    
    let track: RecentTrack
    @State private var loved: Bool
    @State private var playcount: Int?
    @State private var serviceInfo: [String: ServiceTrackData]
    
    init(track: RecentTrack) {
        self.track = track
        self._loved = State(initialValue: track.loved)
        self._playcount = State(initialValue: track.playcount)
        self._serviceInfo = State(initialValue: track.serviceInfo)
    }
    
    private var syncStatus: SyncStatus {
        let enabledServices = Set(defaults.enabledServices.map { $0.service })
        var updatedTrack = track
        updatedTrack.serviceInfo = serviceInfo
        return updatedTrack.syncStatus(enabledServices: enabledServices)
    }
    
    var body: some View {
        TrackInfo(
            trackName: track.name,
            artist: track.artist,
            album: track.album,
            loved: $loved,
            artworkImageUrl: track.imageUrl,
            timestamp: track.date,
            playCount: $playcount,
            artistURL: track.artistURL,
            albumURL: track.albumURL,
            trackURL: track.trackURL,
            actionButtons: {
                HStack(spacing: 4) {
                    // Sync status indicator
                    SyncStatusBadge(
                        syncStatus: syncStatus,
                        serviceInfo: serviceInfo,
                        sourceService: track.sourceService
                    )
                    
                    UndoButton(
                        artist: track.artist,
                        track: track.name,
                        album: track.album,
                        serviceInfo: track.serviceInfo,
                        playcount: $playcount
                    )
                    .id("\(track.artist)-\(track.name)-\(track.date ?? 0)")
                    
                    BlacklistButton(
                        artist: track.artist,
                        track: track.name
                    )
                }
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            fetchLovedState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TrackLoveStateChanged"))) { _ in
            fetchLovedState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TrackBackfillSucceeded"))) { notification in
            updateSyncStatus(from: notification)
        }
    }
    
    private func fetchLovedState() {
        guard let primary = defaults.primaryService,
              primary.service == .lastfm,
              let client = serviceManager.client(for: .lastfm) else {
            return
        }
        
        Task {
            let lovedState = try? await client.getTrackLoved(token: primary.token, artist: track.artist, track: track.name)
            await MainActor.run {
                if let lovedState = lovedState {
                    loved = lovedState
                }
            }
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
              track.date == timestamp else {
            return
        }
        
        // Add the newly synced service to serviceInfo
        if let serviceRawValue = userInfo["service"] as? String,
           let service = ScrobbleService(rawValue: serviceRawValue) {
            // Update serviceInfo - syncStatus will be recomputed automatically
            serviceInfo[service.id] = ServiceTrackData(timestamp: timestamp, id: nil)
        }
    }
}
