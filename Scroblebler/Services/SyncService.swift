import Foundation

/// Coordinates synchronization logic across services
/// Decides WHAT to sync and HOW, delegates execution to ScrobbleManager
class SyncService {
    private let serviceManager: ScrobbleManager
    
    /// Track recently deleted scrobbles to prevent immediate re-backfilling
    /// Key: canonical track key (artist|track), Value: deletion timestamp
    private var recentlyDeleted: [String: Date] = [:]
    private let deletionCooldownPeriod: TimeInterval = 300 // 5 minutes
    
    init(serviceManager: ScrobbleManager) {
        self.serviceManager = serviceManager
    }
    
    /// Mark a track as recently deleted to prevent backfilling
    func markAsDeleted(artist: String, track: String) {
        let key = TrackIdentity.key(artist: artist, track: track)
        recentlyDeleted[key] = Date()
        Logger.info("SYNC: Marked '\(artist) - \(track)' as recently deleted (cooldown: \(Int(deletionCooldownPeriod))s)", log: Logger.sync)
        
        // Clean up old entries (older than cooldown period)
        cleanupOldDeletions()
    }
    
    /// Clear deletion tracking for a track (e.g., when redoing a scrobble)
    func clearDeletionTracking(artist: String, track: String) {
        let key = TrackIdentity.key(artist: artist, track: track)
        if recentlyDeleted.removeValue(forKey: key) != nil {
            Logger.info("SYNC: Cleared deletion tracking for '\(artist) - \(track)'", log: Logger.sync)
        }
    }
    
    /// Check if a track was recently deleted
    private func wasRecentlyDeleted(artist: String, track: String) -> Bool {
        let key = TrackIdentity.key(artist: artist, track: track)
        guard let deletionTime = recentlyDeleted[key] else {
            return false
        }
        
        let timeSinceDeletion = Date().timeIntervalSince(deletionTime)
        if timeSinceDeletion < deletionCooldownPeriod {
            Logger.debug("SYNC: Track '\(artist) - \(track)' was deleted \(Int(timeSinceDeletion))s ago, skipping backfill", log: Logger.sync)
            return true
        }
        
        // Cooldown expired, remove from tracking
        recentlyDeleted.removeValue(forKey: key)
        return false
    }
    
    /// Clean up old deletion tracking entries
    private func cleanupOldDeletions() {
        let now = Date()
        recentlyDeleted = recentlyDeleted.filter { _, deletionTime in
            now.timeIntervalSince(deletionTime) < deletionCooldownPeriod
        }
    }
    
    /// Enrich tracks with data from secondary services
    /// Matches tracks and backfills missing ones
    func enrichTracksWithSecondaryServices(
        tracks: inout [Track],
        primaryService: ScrobbleService,
        secondaryServices: [ScrobbleService],
        limit: Int,
        page: Int
    ) async {
        // 1. Fetch from secondary services using timestamp range from primary tracks
        let secondaryTracksByService = await fetchFromSecondaries(
            secondaryServices,
            primaryTracks: tracks,
            limit: limit
        )
        
        // 2. Match tracks and backfill missing ones
        var backfillTasks: [(track: Track, service: ScrobbleService)] = []
        
        for (service, secondaryTracks) in secondaryTracksByService {
            for i in tracks.indices {
                if let match = findMatch(tracks[i], in: secondaryTracks) {
                    // Track exists - merge serviceInfo
                    Logger.info("[MATCH] ✅ Matched '\(tracks[i].artist) - \(tracks[i].name)' in \(service.displayName)", log: Logger.sync)
                    Logger.debug("  Before merge - serviceInfo keys: \(tracks[i].serviceInfo.keys.map { $0.rawValue }.joined(separator: ", "))", log: Logger.sync)
                    Logger.debug("  Merging from \(service.displayName) - keys: \(match.serviceInfo.keys.map { $0.rawValue }.joined(separator: ", "))", log: Logger.sync)
                    tracks[i].serviceInfo.merge(match.serviceInfo) { (_, new) in new }
                    Logger.debug("  After merge - serviceInfo keys: \(tracks[i].serviceInfo.keys.map { $0.rawValue }.joined(separator: ", "))", log: Logger.sync)
                } else {
                    // Track missing - check if eligible for backfill
                    if wasRecentlyDeleted(artist: tracks[i].artist, track: tracks[i].name) {
                        Logger.info("[MATCH] 🚫 No match for '\(tracks[i].artist) - \(tracks[i].name)' in \(service.displayName) - recently deleted, skipping backfill", log: Logger.sync)
                    } else if shouldBackfill(tracks[i], to: service) {
                        Logger.info("[MATCH] ❌ No match for '\(tracks[i].artist) - \(tracks[i].name)' in \(service.displayName)", log: Logger.sync)
                        backfillTasks.append((track: tracks[i], service: service))
                    }
                }
            }
        }
        
        // 3. Execute backfills asynchronously
        if !backfillTasks.isEmpty {
            Task {
                await executeBackfills(tasks: backfillTasks)
            }
        }
    }
    
    // MARK: - Private - Fetch from secondaries
    
    private func fetchFromSecondaries(
        _ secondaryServices: [ScrobbleService],
        primaryTracks: [Track],
        limit: Int
    ) async -> [ScrobbleService: [Track]] {
        var result: [ScrobbleService: [Track]] = [:]
        
        // Extract timestamp range from primary tracks
        guard !primaryTracks.isEmpty else {
            Logger.debug("No primary tracks to extract timestamp range from", log: Logger.sync)
            return result
        }
        
        let timestamps = primaryTracks.map { $0.timestamp }
        guard let minTimestamp = timestamps.min(), let maxTimestamp = timestamps.max() else {
            return result
        }
        
        // Add edge buffers (60s before/after) for clock skew between services
        let edgeBuffer = 60 // seconds
        let minTs = minTimestamp - edgeBuffer
        let maxTs = maxTimestamp + edgeBuffer
        
        Logger.debug("Fetching secondaries for timestamp range: \(minTs) - \(maxTs) with \(edgeBuffer)s edge buffer (primary tracks: \(primaryTracks.count))", log: Logger.sync)
        
        await withTaskGroup(of: (ScrobbleService, [Track]?).self) { group in
            for service in secondaryServices {
                group.addTask {
                    // Try timestamp-based fetch first (only ListenBrainz supports this)
                    // Note: getRecentTracksByTimeRange returns [Track]? (nil if not supported)
                    let fetchResult = try? await self.serviceManager.fetchRecentTracksByTimeRange(
                        service: service,
                        minTs: minTs,
                        maxTs: maxTs,
                        limit: limit * 2 // Fetch a bit more to ensure coverage
                    )
                    
                    // Swift flattens double optional [Track]?? to [Track]?
                    if let tracks = fetchResult {
                        Logger.debug("Fetched \(tracks.count) tracks from \(service.displayName) by timestamp range", log: Logger.sync)
                        return (service, tracks)
                    }
                    
                    // Fallback: service doesn't support timestamp queries
                    Logger.debug("\(service.displayName) doesn't support timestamp queries, skipping", log: Logger.sync)
                    return (service, nil)
                }
            }
            
            for await (service, tracks) in group {
                if let tracks = tracks {
                    result[service] = tracks
                }
            }
        }
        
        return result
    }
    
    // MARK: - Private - Backfill execution
    
    private func executeBackfills(tasks: [(track: Track, service: ScrobbleService)]) async {
        Logger.info("Backfilling \(tasks.count) missing tracks", log: Logger.sync)
        
        var succeeded = 0
        var failed = 0
        var skipped = 0
        
        for (index, (track, service)) in tasks.enumerated() {
            Logger.debug("Backfill task \(index + 1)/\(tasks.count): '\(track.artist) - \(track.name)' to \(service.displayName)", log: Logger.sync)
            
            // Check blacklist before backfilling
            if await LocalBlacklist.shared.contains(artist: track.artist, track: track.name) {
                Logger.info("Backfill skipped (blacklisted): '\(track.artist) - \(track.name)' to \(service.displayName)", log: Logger.sync)
                skipped += 1
                continue
            }
            
            do {
                // Delegate to ScrobbleManager - it knows how to get credentials
                guard let credentials = Defaults.shared.credentials(for: service) else {
                    Logger.error("No credentials for \(service.displayName)", log: Logger.sync)
                    failed += 1
                    continue
                }
                
                try await serviceManager.scrobble(credentials: credentials, track: track)
                let age = (Date().timeIntervalSince1970 - TimeInterval(track.timestamp)) / 86400
                Logger.info("Synced to \(service.displayName): '\(track.name)' (\(Int(age))d old)", log: Logger.sync)
                succeeded += 1
                
                // Sync love state
                try? await serviceManager.updateLove(
                    credentials: credentials,
                    artist: track.artist,
                    track: track.name,
                    loved: track.loved
                )
                
                // Publish event immediately to trigger UI update
                let event = BackfillEvent(
                    artist: track.artist,
                    track: track.name,
                    timestamp: track.timestamp,
                    service: service
                )
                await MainActor.run {
                    self.serviceManager.lastBackfilledTrack = event
                }
                
                // Rate limiting
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                Logger.error("Failed \(service.displayName): '\(track.name)' - \(error)", log: Logger.sync)
                failed += 1
            }
        }
        
        Logger.info("Backfill complete: \(succeeded) succeeded, \(failed) failed, \(skipped) skipped (blacklisted)", log: Logger.sync)
    }
    
    // MARK: - Private - Matching logic
    
    private func findMatch(_ track: Track, in tracks: [Track]) -> Track? {
        // Exact match first
        if let exact = tracks.first(where: { $0.canonicalKey == track.canonicalKey }) {
            return exact
        }
        
        // Fuzzy match fallback
        return TrackMatcher.findMatch(for: track, in: tracks)
    }
    
    private func shouldBackfill(_ track: Track, to service: ScrobbleService) -> Bool {
        // Don't backfill recently deleted tracks
        if wasRecentlyDeleted(artist: track.artist, track: track.name) {
            return false
        }
        
        let age = Date().timeIntervalSince1970 - TimeInterval(track.timestamp)
        let daysOld = age / 86400
        
        switch service {
        case .lastfm, .librefm:
            return daysOld < 14
        case .listenbrainz:
            return true
        }
    }
}
