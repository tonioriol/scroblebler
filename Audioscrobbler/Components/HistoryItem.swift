import SwiftUI

struct HistoryItem: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    
    let track: RecentTrack
    let playCount: Int?
    @State private var loved: Bool
    
    init(track: RecentTrack, playCount: Int? = nil) {
        self.track = track
        self.playCount = playCount
        self._loved = State(initialValue: track.loved)
    }
    
    var body: some View {
        TrackInfo(
            trackName: track.name,
            artist: track.artist,
            album: track.album,
            loved: $loved,
            artworkImageUrl: track.imageUrl,
            timestamp: track.date,
            playCount: playCount,
            artistURL: track.artistURL,
            albumURL: track.albumURL,
            trackURL: track.trackURL
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
