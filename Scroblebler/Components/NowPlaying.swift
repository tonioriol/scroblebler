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
                artworkSize: 92,
                artworkImageData: track?.artwork,
                titleFontSize: 18,
                detailFontSize: 13,
                loveFontSize: 12,
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
            
            PlayerControls(
                isPlaying: $isPlaying,
                currentPosition: currentPosition,
                trackLength: track?.length,
                onSeek: { position in
                    MediaControl.seek(to: position)
                    watcher.notifySeek()
                }
            )
            .padding(.bottom, 8)
        }
        .padding()
        .onAppear {
            Logger.debug("NowPlaying onAppear: track artwork size: \(track?.artwork?.count ?? 0) bytes", log: Logger.ui)
            fetchTrackInfo()
        }
        .onChange(of: track?.name) { _ in
            Logger.debug("NowPlaying track changed: '\(track?.name ?? "nil")', artwork size: \(track?.artwork?.count ?? 0) bytes", log: Logger.ui)
            fetchTrackInfo()
        }
        .onChange(of: track?.artwork) { newArtwork in
            Logger.debug("NowPlaying artwork changed: new size: \(newArtwork?.count ?? 0) bytes", log: Logger.ui)
        }
    }
    
    private func fetchTrackInfo() {
        guard let currentTrack = track,
              let primary = defaults.primaryService,
              let client = serviceManager.client(for: primary.service) else {
            lovedState = track?.loved ?? false
            playCount = nil
            return
        }
        
        Task {
            let (loved, count) = (try? await client.getTrackInfo(
                artist: currentTrack.artist,
                track: currentTrack.name
            )) ?? (currentTrack.loved, nil)
            
            await MainActor.run {
                lovedState = loved
                playCount = count
            }
        }
    }
}

struct NowPlaying_Previews: PreviewProvider {
    static var previews: some View {
        NowPlaying(track: .constant(Track(id: UUID(), artist: "Alexisonfire", album: "Watch Out!", name: "It Was Fear Of Myself That Made Me Odd", timestamp: 0, duration: 123.10293, sourceService: .lastfm, artwork: nil, artistURL: nil, albumURL: nil, trackURL: nil, imageUrl: nil)), currentPosition: .constant(61.5), isPlaying: .constant(true))
    }
}
