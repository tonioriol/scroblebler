import SwiftUI

struct HistoryItemView: View {
    let track: Audioscrobbler.RecentTrack
    let playCount: Int?
    @State private var loved: Bool
    
    init(track: Audioscrobbler.RecentTrack, playCount: Int? = nil) {
        self.track = track
        self.playCount = playCount
        self._loved = State(initialValue: track.loved)
    }
    
    var body: some View {
        TrackInfoView(
            trackName: track.name,
            artist: track.artist,
            album: track.album,
            loved: $loved,
            artworkImageUrl: track.imageUrl,
            timestamp: track.date,
            playCount: playCount
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
