import SwiftUI

struct NowPlaying: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @StateObject private var listenStore = ListenStore.shared
    @Binding var currentPosition: Double?
    @Binding var isPlaying: Bool

    var body: some View {
        if let listen = listenStore.currentListen {  // Read from store (single source of truth)
            // TODO: Build URLs for listen (need to adapt service.buildURLs to work with Listen)
            // let displayService = defaults.mainServicePreference ?? defaults.primaryService?.service ?? .lastfm
            // let service = serviceManager.service(for: displayService)
            // let urls = service?.buildURLs(for: listen)

            VStack(spacing: 12) {
                TrackInfo(
                    trackName: listen.track,
                    artist: listen.artist,
                    album: listen.album,
                    loved: Binding(
                        get: { listen.loved },
                        set: { _ in }
                    ),
                    artworkSize: 92,
                    artworkImageData: nil,  // TODO: Load from releaseMbid
                    titleFontSize: 18,
                    detailFontSize: 13,
                    loveFontSize: 12,
                    playCount: Binding(
                        get: { 0 },  // TODO: Load playcount via ListenStore.playcount()
                        set: { _ in }
                    ),
                    artistURL: nil,  // TODO: Build from service/MBIDs
                    albumURL: nil,
                    trackURL: nil,
                    actionButtons: {
                        BlacklistButton(artist: listen.artist, track: listen.track)
                    },
                    artworkOverlay: {
                        EmptyView()
                    }
                )

                PlayerControls(
                    isPlaying: $isPlaying,
                    currentPosition: currentPosition,
                    trackLength: listen.duration,
                    onSeek: { position in MediaControl.seek(to: position) }
                )
            }
            .padding()
        }
    }
}

struct NowPlaying_Previews: PreviewProvider {
    static var previews: some View {
        NowPlaying(currentPosition: .constant(61.5), isPlaying: .constant(true))
    }
}
