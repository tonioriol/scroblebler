import Foundation

/// Coordinates synchronization of track data across multiple scrobble services
class CrossServiceSync {
    private let clients: [ScrobbleService: ScrobbleClient]
    
    init(clients: [ScrobbleService: ScrobbleClient]) {
        self.clients = clients
    }
    
    /// Reconcile primary tracks with secondary services
    /// - Returns: List of tracks that need backfilling
    func reconcile(
        primaryTracks: inout [RecentTrack],
        secondaryServices: [ServiceCredentials],
        limit: Int,
        page: Int
    ) async -> [(track: RecentTrack, credentials: ServiceCredentials)] {
        // Calculate time range for efficient fetching
        let timeRange = calculateTimeRange(from: primaryTracks)
        
        // Fetch from all secondary services in parallel
        let secondaryTracks = await fetchTracks(
            from: secondaryServices,
            timeRange: timeRange,
            limit: limit,
            page: page
        )
        
        // Match and merge, collecting tracks that need backfilling
        return matchAndMerge(
            primary: &primaryTracks,
            secondary: secondaryTracks,
            services: secondaryServices
        )
    }
    
    // MARK: - Private
    
    private func calculateTimeRange(from tracks: [RecentTrack]) -> TimeRange {
        let timestamps = tracks.compactMap { $0.date }
        let buffer = 300  // 5-minute buffer for clock skew
        
        return TimeRange(
            min: timestamps.min().map { $0 - buffer },
            max: timestamps.max().map { $0 + buffer }
        )
    }
    
    private func fetchTracks(
        from services: [ServiceCredentials],
        timeRange: TimeRange,
        limit: Int,
        page: Int
    ) async -> [(credentials: ServiceCredentials, tracks: [RecentTrack])] {
        var results: [(credentials: ServiceCredentials, tracks: [RecentTrack])] = []
        
        await withTaskGroup(of: (ServiceCredentials, [RecentTrack]?).self) { group in
            for creds in services {
                guard let client = clients[creds.service] else { continue }
                
                group.addTask {
                    // Try time-range query first (faster, more accurate)
                    if let tracks = try? await client.getRecentTracksByTimeRange(
                        minTs: timeRange.min,
                        maxTs: timeRange.max,
                        limit: 1000
                    ), !tracks.isEmpty {
                        Logger.debug("Fetched \(tracks.count) tracks from \(creds.service.displayName) (timestamp query)", log: Logger.sync)
                        return (creds, tracks)
                    }
                    
                    // Fallback to page-based fetch
                    let fetchLimit = min(limit * 10 * page, 1000)
                    let tracks = try? await client.getRecentTracks(
                        limit: fetchLimit,
                        page: 1
                    )
                    Logger.debug("Fetched \(tracks?.count ?? 0) tracks from \(creds.service.displayName) (page query)", log: Logger.sync)
                    return (creds, tracks)
                }
            }
            
            for await (creds, tracks) in group {
                if let tracks = tracks { results.append((credentials: creds, tracks: tracks)) }
            }
        }
        
        return results
    }
    
    private func matchAndMerge(
        primary: inout [RecentTrack],
        secondary: [(credentials: ServiceCredentials, tracks: [RecentTrack])],
        services: [ServiceCredentials]
    ) -> [(track: RecentTrack, credentials: ServiceCredentials)] {
        var backfillTasks: [(track: RecentTrack, credentials: ServiceCredentials)] = []
        
        for result in secondary {
            for index in primary.indices {
                if let match = TrackMatcher.findMatch(for: primary[index], in: result.tracks) {
                    // Track exists - merge service info
                    Logger.info("[MATCH] ✅ Matched '\(primary[index].artist) - \(primary[index].name)' in \(result.credentials.service.displayName)", log: Logger.sync)
                    primary[index].serviceInfo.merge(match.serviceInfo) { (_, new) in new }
                } else if BackfillService.canBackfill(track: primary[index], to: result.credentials.service) {
                    // Track missing and eligible for backfill
                    Logger.info("[MATCH] ❌ No match for '\(primary[index].artist) - \(primary[index].name)' in \(result.credentials.service.displayName)", log: Logger.sync)
                    backfillTasks.append((track: primary[index], credentials: result.credentials))
                }
            }
        }
        
        return backfillTasks
    }
}

// Supporting types
struct TimeRange {
    let min: Int?
    let max: Int?
}
