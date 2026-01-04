import Foundation
import Combine

/// Single source of truth for all track data
@MainActor
class TrackRepository: ObservableObject {
    static let shared = TrackRepository()
    
    // MARK: - Published State
    
    /// All tracks (recent history + now playing)
    @Published private(set) var tracks: [Track] = []
    
    /// Currently playing track (first non-scrobbled track)
    var nowPlaying: Track? {
        tracks.first { !$0.scrobbled }
    }
    
    // MARK: - Dependencies
    
    private let serviceManager: ServiceManager
    private let offlineQueue = OfflineQueue.shared
    private let blacklist = LocalBlacklist.shared
    private let db = LocalDatabase.shared
    
    private init(serviceManager: ServiceManager = .shared) {
        self.serviceManager = serviceManager
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
        objectWillChange.send()
        var updatedTrack = tracks[index]
        mutation(&updatedTrack)
        tracks[index] = updatedTrack
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
        objectWillChange.send()
        var updatedTrack = tracks[index]
        mutation(&updatedTrack)
        tracks[index] = updatedTrack
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
        // Get recent tracks from ServiceManager (returns RecentTrack for now)
        let recentTracks = try await serviceManager.getAllRecentTracks(limit: limit, page: page)
        
        // Convert RecentTrack to unified Track model
        let convertedTracks = recentTracks.map { apiTrack in
            Track(
                id: UUID(),
                artist: apiTrack.artist,
                album: apiTrack.album,
                name: apiTrack.name,
                timestamp: apiTrack.date ?? 0,
                duration: 0,
                sourceService: apiTrack.sourceService ?? .lastfm,
                loved: apiTrack.loved,
                playcount: apiTrack.playcount ?? 1,
                scrobbled: !apiTrack.isNowPlaying,
                blacklisted: false,
                serviceInfo: apiTrack.serviceInfo.reduce(into: [:]) { result, entry in
                    if let service = ScrobbleService(rawValue: entry.key) {
                        result[service] = entry.value
                    }
                },
                artwork: nil,
                artistURL: apiTrack.artistURL,
                albumURL: apiTrack.albumURL,
                trackURL: apiTrack.trackURL,
                imageUrl: apiTrack.imageUrl
            )
        }
        
        // For first page, replace all tracks
        if page == 1 {
            tracks = convertedTracks
        } else {
            // For subsequent pages, append new tracks that don't exist yet
            for apiTrack in convertedTracks {
                if !tracks.contains(where: { $0.id == apiTrack.id }) {
                    tracks.append(apiTrack)
                }
            }
        }
        
        Logger.info("Loaded \(convertedTracks.count) tracks from \(service.service.displayName)", log: Logger.sync)
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
        Logger.debug("toggleLove: Repository has \(tracks.count) tracks", log: Logger.ui)
        
        guard let existing = tracks.first(where: {
            TrackIdentity.key(artist: $0.artist, track: $0.name) == trackKey
        }) else {
            // Track not in repo yet, just update via service
            Logger.error("toggleLove: Track not found in repository, updating services only", log: Logger.ui)
            let newLoveState = true // Default to loved if not found
            if Reachability.shared.isConnected {
                await serviceManager.updateLoveAll(artist: artist, track: track, loved: newLoveState)
            }
            return newLoveState
        }
        
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
        
        // Update all tracks with this artist/track in repository
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
}
