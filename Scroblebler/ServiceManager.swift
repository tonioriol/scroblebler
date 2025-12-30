import Foundation

struct BackfillEvent: Equatable {
    let artist: String
    let track: String
    let timestamp: Int
    let service: ScrobbleService
}

class ServiceManager: ObservableObject {
    static let shared = ServiceManager()
    
    @Published var lastBackfilledTrack: BackfillEvent?
    @Published var scrobbleCompletedTrigger = 0
    
    private let clients: [ScrobbleService: ScrobbleClient] = [
        .lastfm: LastFmClient(),
        .librefm: LibreFmClient(),
        .listenbrainz: ListenBrainzClient()
    ]
    
    func client(for service: ScrobbleService) -> ScrobbleClient? {
        clients[service]
    }
    
    func authenticate(service: ScrobbleService) async throws -> (token: String, authURL: URL) {
        guard let client = clients[service] else {
            throw NSError(domain: "ServiceManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Service not found"])
        }
        return try await client.authenticate()
    }
    
    func completeAuthentication(service: ScrobbleService, token: String) async throws -> ServiceCredentials {
        guard let client = clients[service] else {
            throw NSError(domain: "ServiceManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Service not found"])
        }
        let result = try await client.completeAuthentication(token: token)
        return ServiceCredentials(
            service: service,
            token: result.sessionKey,
            username: result.username,
            profileUrl: result.profileUrl,
            isSubscriber: result.isSubscriber,
            isEnabled: true
        )
    }
    
    // MARK: - Web Client Setup (for Last.fm deletion)
    
    /// Setup Last.fm web client to enable scrobble deletion
    /// This requires the user's Last.fm password for web authentication
    func setupLastFmWebClient(password: String) async throws {
        // Get username from stored Last.fm credentials
        guard let username = Defaults.shared.credentials(for: .lastfm)?.username else {
            throw NSError(domain: "ServiceManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Last.fm not authenticated via API. Please authenticate first."])
        }
        
        guard let lastFmClient = clients[.lastfm] as? LastFmClient else {
            throw NSError(domain: "ServiceManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Last.fm client not found"])
        }
        
        try await lastFmClient.authenticateWebClient(username: username, password: password)
        Logger.info("Last.fm web client authenticated for \(username)", log: Logger.authentication)
    }
    
    /// Attempt to auto-authenticate web client using stored Keychain password
    /// Call this on app startup to enable undo functionality automatically
    func autoAuthenticateLastFmWebClient() async {
        guard let username = Defaults.shared.credentials(for: .lastfm)?.username else {
            return // Last.fm not authenticated
        }
        
        do {
            guard let password = try KeychainHelper.shared.getPassword(username: username) else {
                return // No stored password
            }
            
            try await setupLastFmWebClient(password: password)
            Logger.info("Auto-authenticated Last.fm web client for \(username)", log: Logger.authentication)
        } catch {
            Logger.error("Failed to auto-authenticate Last.fm web client: \(error)", log: Logger.authentication)
        }
    }
    
    func updateNowPlaying(credentials: ServiceCredentials, track: Track) async throws {
        guard let client = clients[credentials.service] else { return }
        try await client.updateNowPlaying(sessionKey: credentials.token, track: track)
    }
    
    func scrobble(credentials: ServiceCredentials, track: Track) async throws {
        guard let client = clients[credentials.service] else {
            Logger.error("No client found for \(credentials.service.displayName)", log: Logger.scrobbling)
            return
        }
        Logger.debug("Scrobbling to \(credentials.service.displayName): '\(track.artist) - \(track.name)' (timestamp: \(track.startedAt))", log: Logger.scrobbling)
        try await client.scrobble(sessionKey: credentials.token, track: track)
        Logger.info("Successfully scrobbled to \(credentials.service.displayName)", log: Logger.scrobbling)
    }
    
    func scrobbleAll(track: Track) async {
        if Defaults.shared.isBlacklisted(artist: track.artist, track: track.name) {
            Logger.info("Scrobble skipped (blacklisted): \(track.description)", log: Logger.scrobbling)
            return
        }
        
        let enabledServices = Defaults.shared.enabledServices
        
        await withTaskGroup(of: Void.self) { group in
            for credentials in enabledServices {
                group.addTask {
                    do {
                        try await self.scrobble(credentials: credentials, track: track)
                        Logger.info("Scrobbled to \(credentials.service.displayName): \(track.description)", log: Logger.scrobbling)
                    } catch {
                        Logger.error("Failed to scrobble to \(credentials.service.displayName): \(error)", log: Logger.scrobbling)
                    }
                }
            }
        }
        
        await MainActor.run {
            scrobbleCompletedTrigger += 1
        }
    }
    
    func updateNowPlayingAll(track: Track) async -> Track {
        if Defaults.shared.isBlacklisted(artist: track.artist, track: track.name) {
            Logger.info("Update now playing skipped (blacklisted): \(track.description)", log: Logger.playback)
            return track
        }
        
        // Enrich track with URLs if ListenBrainz is the primary service
        var enrichedTrack = track
        if let primary = Defaults.shared.primaryService,
           primary.service == .listenbrainz,
           let lbClient = clients[.listenbrainz] as? ListenBrainzClient {
            enrichedTrack = await lbClient.enrichTrackWithURLs(track)
        }
        
        let enabledServices = Defaults.shared.enabledServices
        
        await withTaskGroup(of: Void.self) { group in
            for credentials in enabledServices {
                group.addTask {
                    do {
                        try await self.updateNowPlaying(credentials: credentials, track: enrichedTrack)
                        Logger.info("Updated now playing on \(credentials.service.displayName): \(enrichedTrack.description)", log: Logger.playback)
                    } catch {
                        Logger.error("Failed to update now playing on \(credentials.service.displayName): \(error)", log: Logger.playback)
                    }
                }
            }
        }
        
        return enrichedTrack
    }
    
    func deleteScrobble(credentials: ServiceCredentials, identifier: ScrobbleIdentifier) async throws {
        guard let client = clients[credentials.service] else { return }
        try await client.deleteScrobble(sessionKey: credentials.token, identifier: identifier)
    }
    
    func deleteScrobbleAll(artist: String, track: String, serviceInfo: [String: ServiceTrackData]) async {
        let enabledServices = Defaults.shared.enabledServices
        
        await withTaskGroup(of: Void.self) { group in
            for credentials in enabledServices {
                let info = serviceInfo[credentials.service.id]
                let identifier = ScrobbleIdentifier(
                    artist: artist,
                    track: track,
                    timestamp: info?.timestamp,
                    serviceId: info?.id
                )
                
                group.addTask {
                    do {
                        try await self.deleteScrobble(credentials: credentials, identifier: identifier)
                        Logger.info("Deleted scrobble from \(credentials.service.displayName): \(artist) - \(track)", log: Logger.scrobbling)
                    } catch {
                        Logger.error("Failed to delete scrobble from \(credentials.service.displayName): \(error)", log: Logger.scrobbling)
                    }
                }
            }
        }
    }
    
    func getAllRecentTracks(limit: Int = 20, page: Int = 1) async throws -> [RecentTrack] {
        // New approach: render tracks from the main/primary service only
        guard let primaryService = Defaults.shared.primaryService else {
            Logger.error("No primary service configured", log: Logger.sync)
            return []
        }
        
        guard let client = self.client(for: primaryService.service) else {
            Logger.error("No client available for primary service", log: Logger.sync)
            return []
        }
        
        // Fetch tracks from primary service
        var primaryTracks: [RecentTrack]
        do {
            primaryTracks = try await client.getRecentTracks(
                username: primaryService.username,
                limit: limit,
                page: page,
                token: primaryService.token
            )
        } catch {
            Logger.error("Failed to fetch history from primary service \(primaryService.service.displayName): \(error)", log: Logger.sync)
            return []
        }
        
        Logger.info("Fetched \(primaryTracks.count) tracks from primary service \(primaryService.service.displayName)", log: Logger.sync)
        
        // Enrich with data from other enabled services for undo/love actions
        let otherServices = Defaults.shared.enabledServices.filter { $0.service != primaryService.service }
        
        if !otherServices.isEmpty {
            await enrichTracksWithOtherServices(tracks: &primaryTracks, otherServices: otherServices, limit: limit, page: page)
        }
        
        return primaryTracks
    }
    
    private func enrichTracksWithOtherServices(tracks: inout [RecentTrack], otherServices: [ServiceCredentials], limit: Int, page: Int) async {
        guard Defaults.shared.primaryService != nil else { return }
        
        var otherServiceTracks: [[RecentTrack]] = []
        
        // Get timestamp range from primary tracks with buffer
        // Add 5 minutes (300s) buffer on each side to catch boundary cases and clock skew
        let minTs = tracks.compactMap { $0.date }.min()
        let maxTs = tracks.compactMap { $0.date }.max()
        let timeBuffer = 300 // 5 minutes in seconds
        
        let oldestTimestamp = minTs.map { $0 - timeBuffer }
        let newestTimestamp = maxTs.map { $0 + timeBuffer }
        
        Logger.debug("Primary timestamp range: \(minTs ?? 0) to \(maxTs ?? 0) (with buffer: \(oldestTimestamp ?? 0) to \(newestTimestamp ?? 0))", log: Logger.sync)
        
        await withTaskGroup(of: (Int, [RecentTrack]?).self) { group in
            for (index, credentials) in otherServices.enumerated() {
                guard let client = self.client(for: credentials.service) else { continue }
                group.addTask {
                    do {
                        var allTracks: [RecentTrack] = []
                        
                        Logger.debug("Attempting timestamp query for \(credentials.service.displayName) (min: \(oldestTimestamp ?? 0), max: \(newestTimestamp ?? 0))", log: Logger.sync)
                        
                        // Try timestamp-based query first (Last.fm and ListenBrainz support this)
                        if let timeRangeTracks = try await client.getRecentTracksByTimeRange(
                            username: credentials.username,
                            minTs: oldestTimestamp,
                            maxTs: newestTimestamp,
                            limit: 1000,
                            token: credentials.token
                        ), !timeRangeTracks.isEmpty {
                            allTracks = timeRangeTracks
                            Logger.debug("Fetched \(allTracks.count) tracks from \(credentials.service.displayName) using timestamp range", log: Logger.sync)
                        } else {
                            Logger.debug("Timestamp query returned nil/empty for \(credentials.service.displayName), falling back to page-based", log: Logger.sync)
                            // Fallback to page-based (Libre.fm or if timestamp query returns nil/empty)
                            let fetchLimit = min(limit * 10 * page, 1000)
                            allTracks = try await client.getRecentTracks(
                                username: credentials.username,
                                limit: fetchLimit,
                                page: 1,
                                token: credentials.token
                            )
                            Logger.debug("Fell back to page-based for \(credentials.service.displayName) (up to \(fetchLimit))", log: Logger.sync)
                        }
                        
                        return (index, allTracks)
                    } catch {
                        Logger.error("Failed to fetch history from \(credentials.service.displayName): \(error)", log: Logger.sync)
                        return (index, nil)
                    }
                }
            }
            
            for await (index, fetchedTracks) in group {
                while otherServiceTracks.count <= index {
                    otherServiceTracks.append([])
                }
                if let fetchedTracks = fetchedTracks {
                    otherServiceTracks[index] = fetchedTracks
                }
            }
        }
        
        // Match primary tracks with other services and backfill missing
        var tracksToBackfill: [(track: RecentTrack, credentials: ServiceCredentials)] = []
        
        for serviceIndex in otherServiceTracks.indices {
            let serviceTracks = otherServiceTracks[serviceIndex]
            let service = otherServices[serviceIndex].service
            let credentials = otherServices[serviceIndex]
            
            Logger.debug("Matching primary tracks with \(service.displayName)", log: Logger.sync)
            
            for primaryIndex in tracks.indices {
                if let matchedTrack = findBestMatch(for: tracks[primaryIndex], in: serviceTracks, serviceName: service.displayName) {
                    // Track exists in both - enrich with service info
                    tracks[primaryIndex].serviceInfo.merge(matchedTrack.serviceInfo) { (_, new) in new }
                } else {
                    // Track missing in secondary service - queue for backfill
                    Logger.debug("Missing in \(service.displayName): '\(tracks[primaryIndex].artist) - \(tracks[primaryIndex].name)'", log: Logger.sync)
                    
                    // Check if backfill is allowed
                    if canBackfill(track: tracks[primaryIndex], to: service) {
                        tracksToBackfill.append((track: tracks[primaryIndex], credentials: credentials))
                    }
                }
            }
        }
        
        // Backfill missing tracks asynchronously
        if !tracksToBackfill.isEmpty {
            Task {
                await backfillMissingTracks(tracksToBackfill)
            }
        }
    }
    
    private func canBackfill(track: RecentTrack, to service: ScrobbleService) -> Bool {
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
    
    private func backfillMissingTracks(_ tasks: [(track: RecentTrack, credentials: ServiceCredentials)]) async {
        Logger.info("Backfilling \(tasks.count) missing tracks", log: Logger.sync)
        
        var succeeded = 0
        var failed = 0
        
        for (index, (recentTrack, credentials)) in tasks.enumerated() {
            Logger.debug("Backfill task \(index + 1)/\(tasks.count): '\(recentTrack.artist) - \(recentTrack.name)' to \(credentials.service.displayName)", log: Logger.sync)
            
            let track = Track(
                artist: recentTrack.artist,
                album: recentTrack.album,
                name: recentTrack.name,
                length: 0,
                artwork: nil,
                year: 0,
                loved: recentTrack.loved,
                startedAt: Int32(recentTrack.date ?? 0)
            )
            
            do {
                try await scrobble(credentials: credentials, track: track)
                let age = (recentTrack.date.map { Date().timeIntervalSince1970 - TimeInterval($0) } ?? 0) / 86400
                Logger.info("Synced to \(credentials.service.displayName): '\(track.name)' (\(Int(age))d old)", log: Logger.sync)
                succeeded += 1
                
                // Sync love state from primary service to secondary service
                if let client = clients[credentials.service] {
                    try? await client.updateLove(sessionKey: credentials.token, artist: recentTrack.artist, track: recentTrack.name, loved: recentTrack.loved)
                }
                
                // Publish backfill event
                await MainActor.run {
                    self.lastBackfilledTrack = BackfillEvent(
                        artist: recentTrack.artist,
                        track: recentTrack.name,
                        timestamp: recentTrack.date ?? 0,
                        service: credentials.service
                    )
                }
                
                // Rate limiting
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                Logger.error("Failed \(credentials.service.displayName): '\(track.name)' - \(error)", log: Logger.sync)
                failed += 1
            }
        }
        
        Logger.info("Backfill complete: \(succeeded) succeeded, \(failed) failed", log: Logger.sync)
    }
    
    private func findBestMatch(for track: RecentTrack, in candidates: [RecentTrack], serviceName: String) -> RecentTrack? {
        var bestMatch: RecentTrack?
        var bestScore: Double = 0
        var candidatesChecked = 0
        var candidatesSkippedTimestamp = 0
        var candidatesSkippedSimilarity = 0
        
        Logger.debug("Trying to match: '\(track.artist) - \(track.name)' (timestamp: \(track.date ?? 0))", log: Logger.sync)
        
        for candidate in candidates {
            candidatesChecked += 1
            
            // First check timestamp proximity
            guard timestampsMatch(track.date, candidate.date) else {
                candidatesSkippedTimestamp += 1
                continue
            }
            
            let timestampDelta = abs((track.date ?? 0) - (candidate.date ?? 0))
            
            // Exact or near-exact timestamp match (within 5s) - accept immediately
            if timestampDelta <= 5 {
                Logger.debug("Exact match found: '\(candidate.artist) - \(candidate.name)' (TS Δ: \(timestampDelta)s)", log: Logger.sync)
                bestMatch = candidate
                bestScore = 1.0
                break  // No need to check more candidates
            }
            
            // Normalize strings for fuzzy matching
            let normalizedTrackArtist = normalize(track.artist)
            let normalizedTrackName = normalize(track.name)
            let normalizedCandidateArtist = normalize(candidate.artist)
            let normalizedCandidateName = normalize(candidate.name)
            
            // Calculate similarity score using Levenshtein distance
            let artistScore = StringSimilarity.similarity(normalizedTrackArtist, normalizedCandidateArtist)
            let trackScore = StringSimilarity.similarity(normalizedTrackName, normalizedCandidateName)
            
            // Combined score (weighted average)
            let score = (artistScore * 0.5 + trackScore * 0.5)
            
            // Require at least 80% similarity
            if score >= 0.8 {
                if score > bestScore {
                    bestScore = score
                    bestMatch = candidate
                }
            } else {
                candidatesSkippedSimilarity += 1
            }
        }
        
        return bestMatch
    }
    
    private func normalize(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespaces).lowercased()
    }
    
    private func timestampsMatch(_ d1: Int?, _ d2: Int?) -> Bool {
        if d1 == nil && d2 == nil { return true }
        guard let d1 = d1, let d2 = d2 else { return false }
        return abs(d1 - d2) < 120  // Within 2 minutes
    }
}
