import Foundation

class ServiceManager: ObservableObject {
    static let shared = ServiceManager()
    
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
    
    func updateNowPlayingAll(track: Track) async {
        if Defaults.shared.isBlacklisted(artist: track.artist, track: track.name) {
            print("🚫 Update now playing skipped (blacklisted): \(track.description)")
            return
        }
        
        let enabledServices = Defaults.shared.enabledServices
        
        await withTaskGroup(of: Void.self) { group in
            for credentials in enabledServices {
                group.addTask {
                    do {
                        try await self.updateNowPlaying(credentials: credentials, track: track)
                        print("✓ Updated now playing on \(credentials.service.displayName): \(track.description)")
                    } catch {
                        print("✗ Failed to update now playing on \(credentials.service.displayName): \(error)")
                    }
                }
            }
        }
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
        var otherServiceTracks: [[RecentTrack]] = []
        
        // Fetch from other services in parallel
        await withTaskGroup(of: (Int, [RecentTrack]?).self) { group in
            for (index, credentials) in otherServices.enumerated() {
                guard let client = self.client(for: credentials.service) else { continue }
                group.addTask {
                    do {
                        let tracks = try await client.getRecentTracks(
                            username: credentials.username,
                            limit: limit,
                            page: page,
                            token: credentials.token
                        )
                        return (index, tracks)
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
                    print("📊 Fetched \(fetchedTracks.count) tracks from \(otherServices[index].service.displayName)")
                }
            }
        }
        
        // Match and enrich primary tracks with serviceInfo from other services
        for serviceIndex in otherServiceTracks.indices {
            let serviceTracks = otherServiceTracks[serviceIndex]
            let service = otherServices[serviceIndex].service
            
            for primaryIndex in tracks.indices {
                if let matchedTrack = findBestMatch(for: tracks[primaryIndex], in: serviceTracks) {
                    print("🔗 Matched '\(tracks[primaryIndex].name)' from primary with \(service.displayName)")
                    tracks[primaryIndex].serviceInfo.merge(matchedTrack.serviceInfo) { (_, new) in new }
                }
            }
        }
    }
    
    private func findBestMatch(for track: RecentTrack, in candidates: [RecentTrack]) -> RecentTrack? {
        var bestMatch: RecentTrack?
        var bestScore: Double = 0
        
        for candidate in candidates {
            // First check timestamp proximity
            guard timestampsMatch(track.date, candidate.date) else { continue }
            
            // Calculate similarity score using Levenshtein distance
            let artistScore = StringSimilarity.similarity(normalize(track.artist), normalize(candidate.artist))
            let trackScore = StringSimilarity.similarity(normalize(track.name), normalize(candidate.name))
            
            // Combined score (weighted average)
            let score = (artistScore * 0.5 + trackScore * 0.5)
            
            // Require at least 80% similarity
            if score >= 0.8 && score > bestScore {
                bestScore = score
                bestMatch = candidate
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
