import SwiftUI

struct NowPlaying: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    @Binding var track: Track?
    @Binding var currentPosition: Double?
    
    @State private var lovedState: Bool = false

    var body: some View {
        TrackInfo(
            trackName: track!.name,
            artist: track!.artist,
            album: track!.album,
            loved: $lovedState,
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
        .onAppear {
            fetchLovedState()
        }
        .onChange(of: track?.name) { _ in
            fetchLovedState()
        }
        .overlay(
            VStack {
                HStack {
                    Spacer()
                    if let track = track {
                        BlacklistButton(
                            artist: track.artist,
                            track: track.name
                        )
                        .padding([.top, .trailing], 4)
                    }
                }
                Spacer()
            }
        )
    }
    
    private func fetchLovedState() {
        guard let currentTrack = track,
              let primary = defaults.primaryService,
              primary.service == .lastfm,
              let client = serviceManager.client(for: .lastfm) else {
            lovedState = track?.loved ?? false
            return
        }
        
        Task {
            let loved = try? await client.getTrackLoved(token: primary.token, artist: currentTrack.artist, track: currentTrack.name)
            await MainActor.run {
                lovedState = loved ?? currentTrack.loved
            }
        }
    }
}

struct NowPlaying_Previews: PreviewProvider {
    static var previews: some View {
        NowPlaying(track: .constant(.init(artist: "Alexisonfire", album: "Watch Out!", name: "It Was Fear Of Myself That Made Me Odd", length: 123.10293, artwork: nil, year: 2004, loved: true, startedAt: 0)), currentPosition: .constant(61.5))
    }
}
