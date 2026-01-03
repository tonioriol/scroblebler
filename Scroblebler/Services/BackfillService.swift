import Foundation

/// Handles backfilling missing tracks to services
class BackfillService {
    private let clients: [ScrobbleService: ScrobbleClient]
    
    init(clients: [ScrobbleService: ScrobbleClient]) {
        self.clients = clients
    }
    
    /// Execute backfill tasks asynchronously
    /// - Returns: Array of successful backfill events
    func execute(tasks: [(track: RecentTrack, credentials: ServiceCredentials)]) async -> [BackfillEvent] {
        Logger.info("Backfilling \(tasks.count) missing tracks", log: Logger.sync)
        
        var succeeded = 0
        var failed = 0
        var events: [BackfillEvent] = []
        
        for (index, (recentTrack, credentials)) in tasks.enumerated() {
            Logger.debug("Backfill task \(index + 1)/\(tasks.count): '\(recentTrack.artist) - \(recentTrack.name)' to \(credentials.service.displayName)", log: Logger.sync)
            
            let track = Track(
                artist: recentTrack.artist,
                album: recentTrack.album,
                name: recentTrack.name,
                length: 0,
                artwork: nil,
                loved: recentTrack.loved,
                startedAt: Int32(recentTrack.date ?? 0)
            )
            
            do {
                guard let client = clients[credentials.service] else { continue }
                
                try await client.scrobble(sessionKey: credentials.token, track: track)
                let age = (recentTrack.date.map { Date().timeIntervalSince1970 - TimeInterval($0) } ?? 0) / 86400
                Logger.info("Synced to \(credentials.service.displayName): '\(track.name)' (\(Int(age))d old)", log: Logger.sync)
                succeeded += 1
                
                // Sync love state
                try? await client.updateLove(
                    sessionKey: credentials.token,
                    artist: recentTrack.artist,
                    track: recentTrack.name,
                    loved: recentTrack.loved
                )
                
                // Collect event
                let event = BackfillEvent(
                    artist: recentTrack.artist,
                    track: recentTrack.name,
                    timestamp: recentTrack.date ?? 0,
                    service: credentials.service
                )
                events.append(event)
                
                // Rate limiting
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                Logger.error("Failed \(credentials.service.displayName): '\(track.name)' - \(error)", log: Logger.sync)
                failed += 1
            }
        }
        
        Logger.info("Backfill complete: \(succeeded) succeeded, \(failed) failed", log: Logger.sync)
        return events
    }
    
    /// Check if track is eligible for backfilling to a service
    static func canBackfill(track: RecentTrack, to service: ScrobbleService) -> Bool {
        guard let timestamp = track.date else { return false }
        let age = Date().timeIntervalSince1970 - TimeInterval(timestamp)
        let daysOld = age / 86400
        
        switch service {
        case .lastfm, .librefm:
            return daysOld < 14
        case .listenbrainz:
            return true
        }
    }
}
