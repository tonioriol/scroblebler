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
        print("✓ Last.fm web client authenticated for \(username)")
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
            print("✓ Auto-authenticated Last.fm web client for \(username)")
        } catch {
            print("⚠️ Failed to auto-authenticate Last.fm web client: \(error)")
        }
    }
    
    func updateNowPlaying(credentials: ServiceCredentials, track: Track) async throws {
        guard let client = clients[credentials.service] else { return }
        try await client.updateNowPlaying(sessionKey: credentials.token, track: track)
    }
    
    func scrobble(credentials: ServiceCredentials, track: Track) async throws {
        guard let client = clients[credentials.service] else { return }
        try await client.scrobble(sessionKey: credentials.token, track: track)
    }
    
    func scrobbleAll(track: Track) async {
        if Defaults.shared.isBlacklisted(artist: track.artist, track: track.name) {
            print("🚫 Scrobble skipped (blacklisted): \(track.description)")
            return
        }
        
        let enabledServices = Defaults.shared.enabledServices
        
        await withTaskGroup(of: Void.self) { group in
            for credentials in enabledServices {
                group.addTask {
                    do {
                        try await self.scrobble(credentials: credentials, track: track)
                        print("✓ Scrobbled to \(credentials.service.displayName): \(track.description)")
                    } catch {
                        print("✗ Failed to scrobble to \(credentials.service.displayName): \(error)")
                    }
                }
            }
        }
    }
    
    func updateNowPlayingAll(track: Track) async -> Track {
        if Defaults.shared.isBlacklisted(artist: track.artist, track: track.name) {
            print("🚫 Update now playing skipped (blacklisted): \(track.description)")
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
                        print("✓ Updated now playing on \(credentials.service.displayName): \(enrichedTrack.description)")
                    } catch {
                        print("✗ Failed to update now playing on \(credentials.service.displayName): \(error)")
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
                        print("✓ Deleted scrobble from \(credentials.service.displayName): \(artist) - \(track)")
                    } catch {
                        print("✗ Failed to delete scrobble from \(credentials.service.displayName): \(error)")
                    }
                }
            }
        }
    }
    
    func getAllRecentTracks(limit: Int = 20, page: Int = 1) async throws -> [RecentTrack] {
        // New approach: render tracks from the main/primary service only
        guard let primaryService = Defaults.shared.primaryService else {
            print("No primary service configured")
            return []
        }
        
        guard let client = self.client(for: primaryService.service) else {
            print("No client available for primary service")
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
            print("✗ Failed to fetch history from primary service \(primaryService.service.displayName): \(error)")
            return []
        }
        
        print("📊 Fetched \(primaryTracks.count) tracks from primary service \(primaryService.service.displayName)")
        
        // Enrich with data from other enabled services for undo/love actions
        let otherServices = Defaults.shared.enabledServices.filter { $0.service != primaryService.service }
        
        if !otherServices.isEmpty {
            await enrichTracksWithOtherServices(tracks: &primaryTracks, otherServices: otherServices, limit: limit, page: page)
        }
        
        return primaryTracks
    }
    
    private func enrichTracksWithOtherServices(tracks: inout [RecentTrack], otherServices: [ServiceCredentials], limit: Int, page: Int) async {
        guard let primaryService = Defaults.shared.primaryService else { return }
        
        var otherServiceTracks: [[RecentTrack]] = []
        
        // Get timestamp range from primary tracks with buffer
        // Add 5 minutes (300s) buffer on each side to catch boundary cases and clock skew
        let minTs = tracks.compactMap { $0.date }.min()
        let maxTs = tracks.compactMap { $0.date }.max()
        let timeBuffer = 300 // 5 minutes in seconds
        
        let oldestTimestamp = minTs.map { $0 - timeBuffer }
        let newestTimestamp = maxTs.map { $0 + timeBuffer }
        
        print("[SYNC] 📅 Primary timestamp range: \(minTs ?? 0) to \(maxTs ?? 0) (with buffer: \(oldestTimestamp ?? 0) to \(newestTimestamp ?? 0))")
        
        await withTaskGroup(of: (Int, [RecentTrack]?).self) { group in
            for (index, credentials) in otherServices.enumerated() {
                guard let client = self.client(for: credentials.service) else { continue }
                group.addTask {
                    do {
                        var allTracks: [RecentTrack] = []
                        
                        print("[SYNC] 🔍 Attempting timestamp query for \(credentials.service.displayName) (min: \(oldestTimestamp ?? 0), max: \(newestTimestamp ?? 0))")
                        
                        // Try timestamp-based query first (Last.fm and ListenBrainz support this)
                        if let timeRangeTracks = try await client.getRecentTracksByTimeRange(
                            username: credentials.username,
                            minTs: oldestTimestamp,
                            maxTs: newestTimestamp,
                            limit: 1000,
                            token: credentials.token
                        ), !timeRangeTracks.isEmpty {
                            allTracks = timeRangeTracks
                            print("[SYNC] ✓ Fetched \(allTracks.count) tracks from \(credentials.service.displayName) using timestamp range (\(oldestTimestamp ?? 0)-\(newestTimestamp ?? 0))")
                        } else {
                            print("[SYNC] ⚠️ Timestamp query returned nil/empty for \(credentials.service.displayName), falling back to page-based")
                            // Fallback to page-based (Libre.fm or if timestamp query returns nil/empty)
                            let fetchLimit = min(limit * 10 * page, 1000)
                            allTracks = try await client.getRecentTracks(
                                username: credentials.username,
                                limit: fetchLimit,
                                page: 1,
                                token: credentials.token
                            )
                            print("[SYNC] ⚠️ Fell back to page-based for \(credentials.service.displayName) (up to \(fetchLimit))")
                        }
                        
                        return (index, allTracks)
                    } catch {
                        print("✗ Failed to fetch history from \(credentials.service.displayName): \(error)")
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
            
            print("[SYNC] 🔍 Matching primary tracks with \(service.displayName)")
            
            for primaryIndex in tracks.indices {
                if let matchedTrack = findBestMatch(for: tracks[primaryIndex], in: serviceTracks, serviceName: service.displayName) {
                    // Track exists in both - enrich with service info
                    tracks[primaryIndex].serviceInfo.merge(matchedTrack.serviceInfo) { (_, new) in new }
                } else {
                    // Track missing in secondary service - queue for backfill
                    print("[SYNC] ✗ Missing in \(service.displayName): '\(tracks[primaryIndex].artist) - \(tracks[primaryIndex].name)'")
                    
                    // Check if backfill is allowed
                    if canBackfill(track: tracks[primaryIndex], to: service) {
                        tracksToBackfill.append((track: tracks[primaryIndex], credentials: credentials))
                    }
                }
            }
        }
        
        // Calculate sync status
        let allEnabledServices = Set([primaryService.service] + otherServices.map { $0.service })
        for index in tracks.indices {
            let presentIn = Set([primaryService.service] + tracks[index].serviceInfo.keys.compactMap { ScrobbleService(rawValue: $0) })
            
            if presentIn == allEnabledServices {
                tracks[index].syncStatus = .synced
            } else if presentIn.count == 1 {
                tracks[index].syncStatus = .primaryOnly
            } else {
                tracks[index].syncStatus = .partial
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
        print("[SYNC] 🔄 Backfilling \(tasks.count) missing tracks...")
        
        var succeeded = 0
        var failed = 0
        
        for (recentTrack, credentials) in tasks {
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
                print("[SYNC]   ✓ Synced to \(credentials.service.displayName): '\(track.name)' (\(Int(age))d old)")
                succeeded += 1
                
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
                print("[SYNC]   ✗ Failed \(credentials.service.displayName): '\(track.name)' - \(error)")
                failed += 1
            }
        }
        
        print("[SYNC] 📊 Backfill complete: \(succeeded) succeeded, \(failed) failed")
    }
    
    private func findBestMatch(for track: RecentTrack, in candidates: [RecentTrack], serviceName: String) -> RecentTrack? {
        var bestMatch: RecentTrack?
        var bestScore: Double = 0
        var candidatesChecked = 0
        var candidatesSkippedTimestamp = 0
        var candidatesSkippedSimilarity = 0
        
        print("[MATCH] 🔎 Trying to match: '\(track.artist) - \(track.name)' (timestamp: \(track.date ?? 0))")
        
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
                print("[MATCH]   • Candidate: '\(candidate.artist) - \(candidate.name)' | TS Δ: \(timestampDelta)s → EXACT MATCH")
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
            
            print("[MATCH]   • Candidate: '\(candidate.artist) - \(candidate.name)' | Artist: \(String(format: "%.2f", artistScore)) | Track: \(String(format: "%.2f", trackScore)) | Total: \(String(format: "%.2f", score)) | TS Δ: \(timestampDelta)s")
            
            // Require at least 80% similarity
            if score >= 0.8 {
                if score > bestScore {
                    bestScore = score
                    bestMatch = candidate
                    print("[MATCH]     ✓ New best match (score: \(String(format: "%.2f", score)))")
                }
            } else {
                candidatesSkippedSimilarity += 1
            }
        }
        
        print("[MATCH] 📊 Summary: Checked \(candidatesChecked), Skipped (timestamp: \(candidatesSkippedTimestamp), similarity: \(candidatesSkippedSimilarity)), Best score: \(String(format: "%.2f", bestScore))")
        
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
