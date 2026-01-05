import SwiftUI

struct NowPlaying: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @EnvironmentObject var watcher: Watcher
    @StateObject private var trackRepo = TrackStore.shared
    @Binding var track: Track?
    @Binding var currentPosition: Double?
    @Binding var isPlaying: Bool
    
    // Computed properties that will refresh when trackRepo publishes changes
    private var lovedState: Bool {
        guard let track = track else { return false }
        return trackRepo.isLoved(artist: track.artist, track: track.name)
    }
    
    private var playCount: Int? {
        guard let track = track else { return nil }
        return trackRepo.playcount(artist: track.artist, track: track.name)
    }

    var body: some View {
        VStack(spacing: 12) {
            if let currentTrack = track {
                TrackInfo(
                    trackName: currentTrack.name,
                    artist: currentTrack.artist,
                    album: currentTrack.album,
                    loved: Binding(
                        get: {
                            trackRepo.isLoved(artist: currentTrack.artist, track: currentTrack.name)
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
                            trackRepo.playcount(artist: currentTrack.artist, track: currentTrack.name)
                        },
                        set: { _ in }
                    ),
                    artistURL: currentTrack.artistURL,
                    albumURL: currentTrack.albumURL,
                    trackURL: currentTrack.trackURL,
                    actionButtons: {
                        BlacklistButton(
                            artist: currentTrack.artist,
                            track: currentTrack.name
                        )
                    }
                )
            }
            
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
            ensureTrackInRepository()
            fetchTrackInfo()
        }
        .onChange(of: track?.name) { _ in
            Logger.debug("NowPlaying track changed: '\(track?.name ?? "nil")', artwork size: \(track?.artwork?.count ?? 0) bytes", log: Logger.ui)
            ensureTrackInRepository()
            fetchTrackInfo()
        }
        .onChange(of: track?.artwork) { newArtwork in
            Logger.debug("NowPlaying artwork changed: new size: \(newArtwork?.count ?? 0) bytes", log: Logger.ui)
        }
    }
    
    private func ensureTrackInRepository() {
        guard let currentTrack = track else { return }
        
        // Check if track already exists in repository
        let trackKey = TrackIdentity.key(artist: currentTrack.artist, track: currentTrack.name)
        let exists = trackRepo.tracks.contains { existingTrack in
            TrackIdentity.key(artist: existingTrack.artist, track: existingTrack.name) == trackKey
        }
        
        // Add track to repository if it doesn't exist
        if !exists {
            trackRepo.add(currentTrack)
            Logger.debug("Added now playing track to repository: '\(currentTrack.name)'", log: Logger.ui)
        }
    }
    
    private func fetchTrackInfo() {
        guard let currentTrack = track,
              let primary = defaults.primaryService,
              let client = serviceManager.client(for: primary.service) else {
            return
        }
        
        Task {
            if let (loved, count) = try? await client.getTrackInfo(
                artist: currentTrack.artist,
                track: currentTrack.name
            ) {
                // Update repository with fetched metadata
                trackRepo.update(artist: currentTrack.artist, track: currentTrack.name) { track in
                    track.loved = loved
                    if let count = count {
                        track.playcount = count
                    }
                }
            }
        }
    }
}

struct NowPlaying_Previews: PreviewProvider {
    static var previews: some View {
        NowPlaying(track: .constant(Track(id: UUID(), artist: "Alexisonfire", album: "Watch Out!", name: "It Was Fear Of Myself That Made Me Odd", timestamp: 0, duration: 123.10293, sourceService: .lastfm, artwork: nil, artistURL: nil, albumURL: nil, trackURL: nil, imageUrl: nil)), currentPosition: .constant(61.5), isPlaying: .constant(true))
    }
}
