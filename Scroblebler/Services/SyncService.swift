import Foundation

/// Coordinates synchronization logic across services
/// Decides WHAT to sync and HOW, delegates execution to ScrobbleManager
class SyncService {
    private let serviceManager: ScrobbleManager
    
    init(serviceManager: ScrobbleManager) {
        self.serviceManager = serviceManager
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
                } else if shouldBackfill(tracks[i], to: service) {
                    // Track missing and eligible for backfill
                    Logger.info("[MATCH] ❌ No match for '\(tracks[i].artist) - \(tracks[i].name)' in \(service.displayName)", log: Logger.sync)
                    backfillTasks.append((track: tracks[i], service: service))
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
