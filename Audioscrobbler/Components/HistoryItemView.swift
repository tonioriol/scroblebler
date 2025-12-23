import SwiftUI

struct HistoryItemView: View {
    let track: WebService.RecentTrack
    @State private var loved: Bool
    
    init(track: WebService.RecentTrack) {
        self.track = track
        self._loved = State(initialValue: track.loved)
    }
    
    var body: some View {
        TrackInfoView(
            trackName: track.name,
            artist: track.artist,
            album: track.album,
            loved: $loved,
            artworkImageUrl: track.imageUrl,
            timestamp: track.date
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
