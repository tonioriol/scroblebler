import SwiftUI

struct PlayingItemView: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    @Binding var track: Track?
    @Binding var currentPosition: Double?

    var body: some View {
        TrackInfoView(
            trackName: track!.name,
            artist: track!.artist,
            album: track!.album,
            loved: Binding(
                get: { track?.loved ?? false },
                set: { track?.loved = $0 }
            ),
            year: Int(track!.year),
            artworkSize: 92,
            artworkImageData: track?.artwork,
            titleFontSize: 18,
            detailFontSize: 13,
            loveFontSize: 12,
            currentPosition: currentPosition,
            trackLength: track!.length
        )
        .padding()
        .animation(nil)
    }
}

struct PlayingItemView_Previews: PreviewProvider {
    static var previews: some View {
        PlayingItemView(track: .constant(.init(artist: "Alexisonfire", album: "Watch Out!", name: "It Was Fear Of Myself That Made Me Odd", length: 123.10293, artwork: nil, year: 2004, loved: true, startedAt: 0)), currentPosition: .constant(61.5))
    }
}
