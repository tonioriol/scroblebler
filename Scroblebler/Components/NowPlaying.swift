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
    
    // Get fresh track from repository (includes updated serviceInfo after enrichment)
    private var currentTrackFromRepo: Track? {
        guard let track = track else { return nil }
        let trackKey = TrackIdentity.key(artist: track.artist, track: track.name)
        let displayService = defaults.mainServicePreference ?? defaults.primaryService?.service ?? .lastfm
        
        // Find all matching tracks
        let matches = trackRepo.tracks.filter { existingTrack in
            TrackIdentity.key(artist: existingTrack.artist, track: existingTrack.name) == trackKey
        }
        
        guard !matches.isEmpty else { return track }
        
        // Priority:
        // 1. Unscrobbled tracks with MBIDs for display service
        // 2. Unscrobbled tracks without MBIDs
        // 3. Scrobbled tracks with MBIDs for display service
        // 4. Any scrobbled track
        // 5. Original track
        
        // Helper to check if track has MBIDs for display service
        func hasMBIDs(_ t: Track) -> Bool {
            guard let serviceData = t.serviceInfo[displayService] else { return false }
            switch displayService {
            case .listenbrainz:
                return serviceData.id != nil || serviceData.artistMbid != nil || serviceData.releaseMbid != nil
            default:
                return true // Other services don't use MBIDs
            }
        }
        
        // Prefer unscrobbled with MBIDs
        if let best = matches.first(where: { !$0.scrobbled && hasMBIDs($0) }) {
            return best
        }
        
        // Then unscrobbled without MBIDs
        if let best = matches.first(where: { !$0.scrobbled }) {
            return best
        }
        
        // Then scrobbled with MBIDs
        if let best = matches.first(where: { hasMBIDs($0) }) {
            return best
        }
        
        // Finally any match or original
        return matches.first ?? track
    }

    var body: some View {
        VStack(spacing: 12) {
            if let currentTrack = currentTrackFromRepo,
               let displayService = defaults.mainServicePreference ?? defaults.primaryService?.service,
               let service = serviceManager.service(for: displayService) {
                let urls = service.buildURLs(for: currentTrack)
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
                    artistURL: urls.artistURL,
                    albumURL: urls.albumURL,
                    trackURL: urls.trackURL,
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
                }
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
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
        .onChange(of: defaults.mainServicePreference) { _ in
            Logger.debug("NowPlaying mainServicePreference changed, re-enriching track", log: Logger.ui)
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
        guard let currentTrack = track else { return }
        
        // Use display service (mainServicePreference) for enrichment, not primary
        // This ensures MBIDs match the service being displayed
        let displayService = defaults.mainServicePreference ?? defaults.primaryService?.service ?? .lastfm
        guard let service = serviceManager.service(for: displayService),
              let client = serviceManager.client(for: displayService) else {
            return
        }
        
        Task {
            // Enrich track with service-specific metadata (e.g., MBIDs for ListenBrainz)
            let enrichedTrack = await service.enrichTrack(currentTrack)
            trackRepo.update(artist: currentTrack.artist, track: currentTrack.name) { track in
                track.serviceInfo = enrichedTrack.serviceInfo
            }
            
            // Fetch track info (playcount, loved status)
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
