import SwiftUI

struct NowPlaying: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    @EnvironmentObject var watcher: Watcher
    @Binding var track: Track?
    @Binding var currentPosition: Double?
    @Binding var isPlaying: Bool
    
    @State private var lovedState: Bool = false
    @State private var playCount: Int? = nil

    var body: some View {
        VStack(spacing: 12) {
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
            onSeek: { position in
                MediaControl.seek(to: position)
                watcher.notifySeek()
            },
                actionButtons: {
                    if let track = track {
                        BlacklistButton(
                            artist: track.artist,
                            track: track.name
                        )
                    }
                }
            )
            
            PlayControls(isPlaying: $isPlaying)
                .padding(.bottom, 8)
        }
        .padding()
        .onAppear {
            Logger.debug("NowPlaying onAppear: track artwork size: \(track?.artwork?.count ?? 0) bytes", log: Logger.ui)
            fetchLovedState()
            fetchPlayCount()
        }
        .onChange(of: track?.name) { _ in
            Logger.debug("NowPlaying track changed: '\(track?.name ?? "nil")', artwork size: \(track?.artwork?.count ?? 0) bytes", log: Logger.ui)
            fetchLovedState()
            fetchPlayCount()
        }
        .onChange(of: track?.artwork) { newArtwork in
            Logger.debug("NowPlaying artwork changed: new size: \(newArtwork?.count ?? 0) bytes", log: Logger.ui)
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
        NowPlaying(track: .constant(.init(artist: "Alexisonfire", album: "Watch Out!", name: "It Was Fear Of Myself That Made Me Odd", length: 123.10293, artwork: nil, year: 2004, loved: true, startedAt: 0)), currentPosition: .constant(61.5), isPlaying: .constant(true))
    }
}
