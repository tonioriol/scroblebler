import Foundation

/// Coordinates track operations (load, scrobble, love, delete)
/// Business logic layer that orchestrates between storage and services
@MainActor
class TrackService: ObservableObject {
    static let shared = TrackService()
    
    private let store = TrackStore.shared
    private let serviceManager = ScrobbleManager.shared
    private let syncService: SyncService
    private let offlineQueue = OfflineQueue.shared
    private let blacklist = LocalBlacklist.shared
    
    private var enrichedTracks: Set<String> = []  // Track which tracks we've enriched
    
    private init() {
        self.syncService = SyncService(serviceManager: serviceManager)
    }
    
    // MARK: - Load History
    
    /// Load recent tracks from primary service
    func loadHistory(
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
        
        // Update store
        if page == 1 {
            store.setHistory(primaryTracks)
        } else {
            store.appendHistory(primaryTracks)
        }
        
        Logger.info("Loaded \(primaryTracks.count) tracks from \(service.service.displayName)", log: Logger.sync)
    }
    
    // MARK: - Scrobble
    
    /// Scrobble a track to all enabled services
    func scrobble(_ track: Track) async {
        // Check blacklist
        if await blacklist.contains(artist: track.artist, track: track.name) {
            Logger.info("Track blacklisted, skipping scrobble", log: Logger.scrobbling)
            return
        }
        
        // Check network - queue if offline
        guard Reachability.shared.isConnected else {
            try? await offlineQueue.enqueue(.scrobble(
                track: track,
                services: Defaults.shared.enabledServices.map { $0.service }
            ))
            Logger.info("Queued for offline sync: \(track.description)", log: Logger.scrobbling)
            return
        }
        
        // Scrobble to all enabled services
        await serviceManager.scrobbleAll(track: track)
    }
    
    // MARK: - Love
    
    /// Toggle love status by artist/track name
    func toggleLove(artist: String, track: String) async -> Bool {
        let key = TrackIdentity.key(artist: artist, track: track)
        Logger.debug("toggleLove: Looking for '\(artist) - \(track)' (key: \(key))", log: Logger.ui)
        
        // Check if track exists in store
        if let existing = store.findTrack(artist: artist, track: track) {
            let newLoveState = !existing.loved
            Logger.debug("toggleLove: Found track, toggling from \(existing.loved) to \(newLoveState)", log: Logger.ui)
            
            // Optimistic UI update
            store.updateTrack(artist: artist, track: track) { t in
                t.loved = newLoveState
            }
            
            // Execute or queue
            await executeOrQueueLove(artist: artist, track: track, loved: newLoveState)
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
        
        // Execute or queue
        await executeOrQueueLove(artist: artist, track: track, loved: newLoveState)
        return newLoveState
    }
    
    private func executeOrQueueLove(artist: String, track: String, loved: Bool) async {
        if Reachability.shared.isConnected {
            await serviceManager.updateLoveAll(artist: artist, track: track, loved: loved)
        } else {
            try? await offlineQueue.enqueue(.love(
                artist: artist,
                track: track,
                loved: loved,
                services: Defaults.shared.enabledServices.map { $0.service }
            ))
        }
    }
    
    // MARK: - Delete
    
    /// Delete scrobble from services
    func delete(_ track: Track) async {
        // Convert serviceInfo
        let stringServiceInfo = track.serviceInfo.reduce(into: [String: ServiceTrackData]()) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
        
        // Execute or queue
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
        store.updateTrack(artist: track.artist, track: track.name) { t in
            t.playcount = max(0, t.playcount - 1)
        }
    }
    
    // MARK: - Blacklist
    
    /// Toggle blacklist status by artist/track name
    func toggleBlacklist(artist: String, track: String) async -> Bool {
        let isBlacklisted = await blacklist.contains(artist: artist, track: track)
        
        if isBlacklisted {
            try? await blacklist.remove(artist: artist, track: track)
        } else {
            try? await blacklist.add(artist: artist, track: track)
        }
        
        let newState = !isBlacklisted
        
        // Update tracks in store
        store.updateTrack(artist: artist, track: track) { t in
            t.blacklisted = newState
        }
        
        return newState
    }
    
    /// Check if track is blacklisted
    func isBlacklisted(artist: String, track: String) async -> Bool {
        return await blacklist.contains(artist: artist, track: track)
    }
    
    // MARK: - Current Track Enrichment
    
    /// Enrich current track with service-specific metadata
    func enrichCurrentTrack() async {
        guard let track = store.currentTrack else { return }
        
        let trackKey = track.canonicalKey
        
        // Skip if already enriched
        guard !enrichedTracks.contains(trackKey) else { return }
        enrichedTracks.insert(trackKey)
        
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
            store.updateCurrentTrack(enrichedTrack)
        }
    }
    
    /// Re-enrich current track when display service changes
    func refreshCurrentTrack() {
        guard let track = store.currentTrack else { return }
        enrichedTracks.remove(track.canonicalKey)
        Task {
            await enrichCurrentTrack()
        }
    }
    
    /// Clear enrichment cache (e.g., on track change)
    func clearEnrichmentCache() {
        enrichedTracks.removeAll()
    }
}
