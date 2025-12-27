import SwiftUI

struct NowPlaying: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    @Binding var track: Track?
    @Binding var currentPosition: Double?
    
    @State private var lovedState: Bool = false
    @State private var playCount: Int? = nil

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
            trackLength: track!.length,
            playCount: $playCount,
            artistURL: track?.artistURL,
            albumURL: track?.albumURL,
            trackURL: track?.trackURL,
            actionButtons: {
                if let track = track {
                    BlacklistButton(
                        artist: track.artist,
                        track: track.name
                    )
                }
            }
        )
        .padding()
        .onAppear {
            fetchLovedState()
            fetchPlayCount()
        }
        .onChange(of: track?.name) { _ in
            fetchLovedState()
            fetchPlayCount()
        }
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
    
    private func fetchPlayCount() {
        guard let currentTrack = track,
              let primary = defaults.primaryService,
              primary.service == .lastfm,
              let client = serviceManager.client(for: .lastfm) else {
            playCount = nil
            return
        }
        
        Task {
            let count = try? await client.getTrackUserPlaycount(token: primary.token, artist: currentTrack.artist, track: currentTrack.name)
            await MainActor.run {
                playCount = count
            }
        }
    }
}

struct NowPlaying_Previews: PreviewProvider {
    static var previews: some View {
        NowPlaying(track: .constant(.init(artist: "Alexisonfire", album: "Watch Out!", name: "It Was Fear Of Myself That Made Me Odd", length: 123.10293, artwork: nil, year: 2004, loved: true, startedAt: 0)), currentPosition: .constant(61.5))
    }
}
