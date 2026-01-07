import SwiftUI

struct NowPlaying: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @EnvironmentObject var watcher: Watcher
    @StateObject private var trackStore = TrackStore.shared
    @Binding var track: Track?
    @Binding var currentPosition: Double?
    @Binding var isPlaying: Bool

    var body: some View {
        VStack(spacing: 12) {
            if let track = track {
                NowPlayingContent(
                    track: track,
                    currentPosition: $currentPosition,
                    isPlaying: $isPlaying
                )
                .id("\(track.artist)-\(track.name)-\(trackStore.tracks.count)")  // Force rebuild when store changes
            }
        }
        .padding()
    }
}

private struct NowPlayingContent: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @StateObject private var trackStore = TrackStore.shared
    
    let track: Track
    @Binding var currentPosition: Double?
    @Binding var isPlaying: Bool
    
    // Get enriched track from store
    private var currentTrack: Track {
        let trackKey = TrackIdentity.key(artist: track.artist, track: track.name)
        return trackStore.tracks.first { existing in
            TrackIdentity.key(artist: existing.artist, track: existing.name) == trackKey
        } ?? track
    }
    
    var body: some View {
        let displayService = defaults.mainServicePreference ?? defaults.primaryService?.service ?? .lastfm
        let service = serviceManager.service(for: displayService)
        let urls = service?.buildURLs(for: currentTrack)
                
        VStack(spacing: 12) {
            TrackInfo(
                trackName: currentTrack.name,
                artist: currentTrack.artist,
                album: currentTrack.album,
                loved: Binding(
                    get: {
                        trackStore.isLoved(artist: currentTrack.artist, track: currentTrack.name)
                    },
                    set: { _ in }
                ),
                artworkSize: 92,
                artworkImageData: currentTrack.artwork,
                titleFontSize: 18,
                detailFontSize: 13,
                loveFontSize: 12,
                playCount: Binding(
                    get: {
                        trackStore.playcount(artist: currentTrack.artist, track: currentTrack.name)
                    },
                    set: { _ in }
                ),
                artistURL: urls?.artistURL,
                albumURL: urls?.albumURL,
                trackURL: urls?.trackURL,
                actionButtons: {
                    BlacklistButton(
                        artist: currentTrack.artist,
                        track: currentTrack.name
                    )
                }
            )
            
            PlayerControls(
                isPlaying: $isPlaying,
                currentPosition: currentPosition,
                trackLength: track.length,
                onSeek: { position in
                    MediaControl.seek(to: position)
                }
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .onAppear {
            Task {
                await trackStore.ensureTrackExists(track, for: displayService)
            }
        }
        .onChange(of: track.name) { _ in
            Task {
                await trackStore.ensureTrackExists(track, for: displayService)
            }
        }
        .onChange(of: defaults.mainServicePreference) { _ in
            Task {
                await trackStore.enrichTrack(track, for: displayService)
            }
        }
    }
}

struct NowPlaying_Previews: PreviewProvider {
    static var previews: some View {
        NowPlaying(track: .constant(Track(id: UUID(), artist: "Alexisonfire", album: "Watch Out!", name: "It Was Fear Of Myself That Made Me Odd", timestamp: 0, duration: 123.10293, sourceService: .lastfm, artwork: nil, imageUrl: nil)), currentPosition: .constant(61.5), isPlaying: .constant(true))
    }
}
