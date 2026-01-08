import SwiftUI

struct NowPlaying: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @StateObject private var trackStore = TrackStore.shared
    @StateObject private var trackService = TrackService.shared
    @Binding var currentPosition: Double?
    @Binding var isPlaying: Bool
    
    var body: some View {
        if let track = trackStore.currentTrack {  // Read from store (single source of truth)
            let displayService = defaults.mainServicePreference ?? defaults.primaryService?.service ?? .lastfm
            let service = serviceManager.service(for: displayService)
            let urls = service?.buildURLs(for: track)  // Uses enriched track with MBIDs
            
            VStack(spacing: 12) {
                TrackInfo(
                    trackName: track.name,
                    artist: track.artist,
                    album: track.album,
                    loved: Binding(
                        get: { track.loved },
                        set: { _ in }
                    ),
                    artworkSize: 92,
                    artworkImageData: track.artwork,
                    titleFontSize: 18,
                    detailFontSize: 13,
                    loveFontSize: 12,
                    playCount: Binding(
                        get: { track.playcount },
                        set: { _ in }
                    ),
                    artistURL: urls?.artistURL,
                    albumURL: urls?.albumURL,
                    trackURL: urls?.trackURL,
                    actionButtons: {
                        BlacklistButton(artist: track.artist, track: track.name)
                    },
                    artworkOverlay: {
                        EmptyView()
                    }
                )
                
                PlayerControls(
                    isPlaying: $isPlaying,
                    currentPosition: currentPosition,
                    trackLength: track.length,
                    onSeek: { position in MediaControl.seek(to: position) }
                )
            }
            .padding()
            .onChange(of: defaults.mainServicePreference) { _ in
                trackService.refreshCurrentTrack()
            }
        }
    }
}

struct NowPlaying_Previews: PreviewProvider {
    static var previews: some View {
        NowPlaying(currentPosition: .constant(61.5), isPlaying: .constant(true))
    }
}
