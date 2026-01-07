import Foundation
import Combine

/// Single source of truth for all track data
@MainActor
class TrackStore: ObservableObject {
    static let shared = TrackStore()
    
    // MARK: - Published State
    
    /// All tracks (recent history + now playing)
    @Published private(set) var tracks: [Track] = []
    
    /// Currently playing track (single source of truth)
    @Published private(set) var currentTrack: Track?
    
    /// History tracks (filtered from tracks array)
    var history: [Track] {
        tracks.filter { $0.scrobbled }
    }
    
    // MARK: - Dependencies
    
    private let serviceManager: ScrobbleManager
    private let syncService: SyncService
    private let offlineQueue = OfflineQueue.shared
    private let blacklist = LocalBlacklist.shared
    private let db = LocalDatabase.shared
    
    private init(serviceManager: ScrobbleManager = .shared, syncService: SyncService? = nil) {
        self.serviceManager = serviceManager
        self.syncService = syncService ?? SyncService(serviceManager: serviceManager)
    }
    
    // MARK: - CRUD Operations
    
    /// Add a new track (e.g., from media player)
    func add(_ track: Track) {
        // Insert at beginning (most recent first)
        tracks.insert(track, at: 0)
        Logger.info("Added track: \(track.description)", log: Logger.playback)
        
        // Auto-prune old tracks (keep last 200)
        if tracks.count > 200 {
            tracks = Array(tracks.prefix(200))
        }
    }
    
    /// Update track by ID
    func update(id: UUID, mutation: (inout Track) -> Void) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else {
            return
        }
        var updatedTrack = tracks[index]
        mutation(&updatedTrack)
        var newTracks = tracks
        newTracks[index] = updatedTrack
        tracks = newTracks
        Logger.debug("Updated track: \(tracks[index].description)", log: Logger.ui)
    }
    
    /// Update track by canonical key
    func update(artist: String, track: String, mutation: (inout Track) -> Void) {
        guard let index = tracks.firstIndex(where: {
            TrackIdentity.key(artist: $0.artist, track: $0.name) ==
            TrackIdentity.key(artist: artist, track: track)
        }) else {
            return
        }
        var updatedTrack = tracks[index]
        mutation(&updatedTrack)
        var newTracks = tracks
        newTracks[index] = updatedTrack
        tracks = newTracks
    }
    
    /// Remove track
    func remove(id: UUID) {
        tracks.removeAll { $0.id == id }
    }
    
    /// Clear all tracks
    func clear() {
        tracks.removeAll()
        Logger.info("Cleared all tracks", log: Logger.ui)
    }
    
    // MARK: - Service Operations
    
    /// Load recent tracks from primary service
    func loadRecent(
        from service: ServiceCredentials,
        limit: Int = 20,
        page: Int = 1
    ) async throws {
        // Fetch from primary via ScrobbleManager
        var primaryTracks = try await serviceManager.fetchRecentTracks(
            service: service.service,
            limit: limit,
            page: page
        )
        
        Logger.info("Fetched \(primaryTracks.count) tracks from primary service \(service.service.displayName)", log: Logger.sync)
        
        // Enrich with secondary services via SyncService
        let otherServices = Defaults.shared.enabledServices
            .filter { $0.service != service.service }
            .map { $0.service }
        
        if !otherServices.isEmpty {
            await syncService.enrichTracksWithSecondaryServices(
                tracks: &primaryTracks,
                primaryService: service.service,
                secondaryServices: otherServices,
                limit: limit,
                page: page
            )
        }
        
        // Update state
        if page == 1 {
            // Preserve now-playing (unscrobbled) tracks when refreshing history
            let nowPlayingTracks = tracks.filter { !$0.scrobbled }
            
            // Merge: keep now-playing tracks + add new history tracks (match by canonical key, not ID)
            var mergedTracks = nowPlayingTracks
            mergedTracks.append(contentsOf: primaryTracks.filter { new in
                let newKey = TrackIdentity.key(artist: new.artist, track: new.name)
                return !mergedTracks.contains(where: { existing in
                    TrackIdentity.key(artist: existing.artist, track: existing.name) == newKey
                })
            })
            tracks = mergedTracks
        } else {
            tracks.append(contentsOf: primaryTracks.filter { new in
                let newKey = TrackIdentity.key(artist: new.artist, track: new.name)
                return !tracks.contains(where: { existing in
                    TrackIdentity.key(artist: existing.artist, track: existing.name) == newKey
                })
            })
        }
        
        Logger.info("Loaded \(primaryTracks.count) tracks from \(service.service.displayName)", log: Logger.sync)
    }
    
    /// Scrobble a track to all enabled services
    func scrobble(_ track: Track) async {
        // Check blacklist
        if await blacklist.contains(artist: track.artist, track: track.name) {
            Logger.info("Track blacklisted, skipping scrobble", log: Logger.scrobbling)
            return
        }
        
        // Check network - queue if offline
        guard Reachability.shared.isConnected else {
            try? await offlineQueue.enqueue(.scrobble(track: track, services: Defaults.shared.enabledServices.map { $0.service }))
            Logger.info("Queued for offline sync: \(track.description)", log: Logger.scrobbling)
            return
        }
        
        // Scrobble to all enabled services
        await serviceManager.scrobbleAll(track: track)
        
        // Update local state
        update(id: track.id) { t in
            t.scrobbled = true
        }
    }
    
    /// Toggle love status by artist/track name
    func toggleLove(artist: String, track: String) async -> Bool {
        // Find track and toggle
        let trackKey = TrackIdentity.key(artist: artist, track: track)
        Logger.debug("toggleLove: Looking for '\(artist) - \(track)' (key: \(trackKey))", log: Logger.ui)
        Logger.debug("toggleLove: Store has \(tracks.count) tracks", log: Logger.ui)
        
        // Check if track exists in store
        if let existing = tracks.first(where: {
            TrackIdentity.key(artist: $0.artist, track: $0.name) == trackKey
        }) {
            let newLoveState = !existing.loved
            Logger.debug("toggleLove: Found track, toggling from \(existing.loved) to \(newLoveState)", log: Logger.ui)
            
            // Optimistic UI update
            update(id: existing.id) { t in
                t.loved = newLoveState
            }
            
            // Queue or execute
            if Reachability.shared.isConnected {
                await serviceManager.updateLoveAll(
                    artist: artist,
                    track: track,
                    loved: newLoveState
                )
            } else {
                try? await offlineQueue.enqueue(.love(
                    artist: artist,
                    track: track,
                    loved: newLoveState,
                    services: Defaults.shared.enabledServices.map { $0.service }
                ))
            }
            
            return newLoveState
        }
        
        // Track not in store - fetch current state first, then toggle
        Logger.debug("toggleLove: Track not in store, fetching current state", log: Logger.ui)
        
        var currentLoveState = false
        if let primary = Defaults.shared.primaryService,
           let client = serviceManager.client(for: primary.service),
           Reachability.shared.isConnected {
            if let (loved, _) = try? await client.getTrackInfo(artist: artist, track: track) {
                currentLoveState = loved
            }
        }
        
        let newLoveState = !currentLoveState
        Logger.debug("toggleLove: Current state: \(currentLoveState), toggling to: \(newLoveState)", log: Logger.ui)
        
        // Update services
        if Reachability.shared.isConnected {
            await serviceManager.updateLoveAll(artist: artist, track: track, loved: newLoveState)
        } else {
            try? await offlineQueue.enqueue(.love(
                artist: artist,
                track: track,
                loved: newLoveState,
                services: Defaults.shared.enabledServices.map { $0.service }
            ))
        }
        
        return newLoveState
    }
    
    /// Toggle love status for a specific track
    func toggleLove(_ track: Track) async {
        _ = await toggleLove(artist: track.artist, track: track.name)
    }
    
    /// Get loved state for a track
    func isLoved(artist: String, track: String) -> Bool {
        let trackKey = TrackIdentity.key(artist: artist, track: track)
        return tracks.first(where: {
            TrackIdentity.key(artist: $0.artist, track: $0.name) == trackKey
        })?.loved ?? false
    }
    
    /// Delete scrobble from services
    func delete(_ track: Track) async {
        // Convert serviceInfo from [ScrobbleService: ServiceTrackData] to [String: ServiceTrackData]
        let stringServiceInfo = track.serviceInfo.reduce(into: [String: ServiceTrackData]()) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
        
        // Queue or execute
        if Reachability.shared.isConnected {
            await serviceManager.deleteScrobbleAll(
                artist: track.artist,
                track: track.name,
                serviceInfo: stringServiceInfo
            )
        } else {
            try? await offlineQueue.enqueue(.delete(
                artist: track.artist,
                track: track.name,
                timestamp: track.timestamp,
                services: Defaults.shared.enabledServices.map { $0.service }
            ))
        }
        
        // Update local state
        update(id: track.id) { t in
            t.playcount = max(0, t.playcount - 1)
        }
    }
    
    /// Get playcount for a track
    func playcount(artist: String, track: String) -> Int? {
        let trackKey = TrackIdentity.key(artist: artist, track: track)
        return tracks.first(where: {
            TrackIdentity.key(artist: $0.artist, track: $0.name) == trackKey
        })?.playcount
    }
    
    /// Decrement playcount (for undo)
    func decrementPlaycount(artist: String, track: String) {
        update(artist: artist, track: track) { t in
            t.playcount = max(0, t.playcount - 1)
        }
    }
    
    /// Increment playcount (for redo)
    func incrementPlaycount(artist: String, track: String) {
        update(artist: artist, track: track) { t in
            t.playcount += 1
        }
    }
    
    // MARK: - Blacklist Integration
    
    /// Toggle blacklist status by artist/track name
    func toggleBlacklist(artist: String, track: String) async -> Bool {
        let isBlacklisted = await blacklist.contains(artist: artist, track: track)
        
        if isBlacklisted {
            try? await blacklist.remove(artist: artist, track: track)
        } else {
            try? await blacklist.add(artist: artist, track: track)
        }
        
        // Update all tracks with this artist/track in store
        objectWillChange.send()
        let trackKey = TrackIdentity.key(artist: artist, track: track)
        var updatedTracks = tracks
        for (index, existingTrack) in updatedTracks.enumerated() where
            TrackIdentity.key(artist: existingTrack.artist, track: existingTrack.name) == trackKey {
            updatedTracks[index].blacklisted = !isBlacklisted
        }
        tracks = updatedTracks
        
        return !isBlacklisted
    }
    
    /// Toggle blacklist status for a specific track
    func toggleBlacklist(_ track: Track) async {
        _ = await toggleBlacklist(artist: track.artist, track: track.name)
    }
    
    /// Check if track is blacklisted
    func isBlacklisted(artist: String, track: String) async -> Bool {
        // Check persistent storage
        return await blacklist.contains(artist: artist, track: track)
    }
    
    // MARK: - Now Playing Management
    
    private var enrichedTracks: Set<String> = []  // Track which tracks we've enriched
    
    /// Set current track and enrich with metadata (single source of truth for now playing)
    func setCurrentTrack(_ track: Track) {
        let trackKey = TrackIdentity.key(artist: track.artist, track: track.name)
        
        // Check if it's a different track
        if let current = currentTrack,
           TrackIdentity.key(artist: current.artist, track: current.name) == trackKey {
            return  // Same track, nothing to do
        }
        
        currentTrack = track
        
        // Add to tracks array if new
        let exists = tracks.contains { existing in
            TrackIdentity.key(artist: existing.artist, track: existing.name) == trackKey
        }
        if !exists {
            add(track)
        }
        
        // Enrich if not already done
        if !enrichedTracks.contains(trackKey) {
            enrichedTracks.insert(trackKey)
            Task {
                await enrichCurrentTrack()
            }
        }
    }
    
    /// Enrich current track with service-specific metadata
    private func enrichCurrentTrack() async {
        guard let track = currentTrack else { return }
        
        let displayService = Defaults.shared.mainServicePreference
            ?? Defaults.shared.primaryService?.service
            ?? .lastfm
        
        guard let service = serviceManager.service(for: displayService),
              let client = serviceManager.client(for: displayService) else {
            return
        }
        
        // Enrich with service-specific metadata
        var enrichedTrack = await service.enrichTrack(track)
        
        // Fetch additional metadata
        if let (loved, count) = try? await client.getTrackInfo(artist: track.artist, track: track.name) {
            enrichedTrack.loved = loved
            if let count = count {
                enrichedTrack.playcount = count
            }
        }
        
        // Update if changed
        if enrichedTrack.serviceInfo != track.serviceInfo ||
           enrichedTrack.loved != track.loved ||
           enrichedTrack.playcount != track.playcount {
            currentTrack = enrichedTrack
            
            // Sync to tracks array
            update(artist: track.artist, track: track.name) { existing in
                for (service, data) in enrichedTrack.serviceInfo {
                    existing.serviceInfo[service] = data
                }
                existing.loved = enrichedTrack.loved
                existing.playcount = enrichedTrack.playcount
            }
        }
    }
    
    /// Re-enrich current track when display service changes
    func refreshCurrentTrack() {
        guard let track = currentTrack else { return }
        let trackKey = TrackIdentity.key(artist: track.artist, track: track.name)
        enrichedTracks.remove(trackKey)  // Clear enrichment flag
        Task {
            await enrichCurrentTrack()
        }
    }
}
