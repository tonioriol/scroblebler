import SwiftUI

struct HistoryItem: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    
    let track: RecentTrack
    @State private var loved: Bool
    @State private var playcount: Int?
    
    init(track: RecentTrack) {
        self.track = track
        self._loved = State(initialValue: track.loved)
        self._playcount = State(initialValue: track.playcount)
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
}
