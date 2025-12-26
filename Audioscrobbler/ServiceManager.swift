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
    
    func deleteScrobble(credentials: ServiceCredentials, artist: String, track: String, timestamp: Int?, serviceId: String?) async throws {
        guard let client = clients[credentials.service] else { return }
        try await client.deleteScrobble(sessionKey: credentials.token, artist: artist, track: track, timestamp: timestamp, serviceId: serviceId)
    }
    
    func deleteScrobbleAll(artist: String, track: String, serviceInfo: [String: ServiceTrackData]) async {
        let enabledServices = Defaults.shared.enabledServices
        
        await withTaskGroup(of: Void.self) { group in
            for credentials in enabledServices {
                let info = serviceInfo[credentials.service.id]
                
                group.addTask {
                    do {
                        try await self.deleteScrobble(credentials: credentials, artist: artist, track: track, timestamp: info?.timestamp, serviceId: info?.id)
                        print("✓ Deleted scrobble from \(credentials.service.displayName): \(artist) - \(track)")
                    } catch {
                        print("✗ Failed to delete scrobble from \(credentials.service.displayName): \(error)")
                    }
                }
            }
        }
    }
    
    func getAllRecentTracks(limit: Int = 20, page: Int = 1) async throws -> [RecentTrack] {
        let enabledServices = Defaults.shared.enabledServices
        var allTracks: [RecentTrack] = []
        
        // Fetch in parallel
        await withTaskGroup(of: [RecentTrack]?.self) { group in
            for credentials in enabledServices {
                guard let client = self.client(for: credentials.service) else { continue }
                group.addTask {
                    do {
                        return try await client.getRecentTracks(username: credentials.username, limit: limit, page: page, token: credentials.token)
                    } catch {
                        print("✗ Failed to fetch history from \(credentials.service.displayName): \(error)")
                        return nil
                    }
                }
            }
            
            for await tracks in group {
                if let tracks = tracks {
                    allTracks.append(contentsOf: tracks)
                }
            }
        }
        
        // Merge Logic: Sort by date desc
        let preferred = Defaults.shared.mainServicePreference
        allTracks.sort { (t1, t2) in
            let d1 = t1.date ?? Int.max
            let d2 = t2.date ?? Int.max
            
            // If timestamps are close (2 mins), prioritize preferred service
            if abs(d1 - d2) < 120 {
                if let p = preferred {
                    if t1.sourceService == p && t2.sourceService != p { return true }
                    if t1.sourceService != p && t2.sourceService == p { return false }
                }
            }
            
            return d1 > d2
        }
        
        let lfmCount = allTracks.filter { $0.sourceService == .lastfm }.count
        let lbCount = allTracks.filter { $0.sourceService == .listenbrainz }.count
        let libreCount = allTracks.filter { $0.sourceService == .librefm }.count
        let nilCount = allTracks.filter { $0.sourceService == nil }.count
        
        print("DEBUG: All tracks: \(allTracks.count). LFM: \(lfmCount), LB: \(lbCount), Libre: \(libreCount), Nil: \(nilCount). Preferred: \(preferred?.id ?? "None")")
        
        var mergedTracks: [RecentTrack] = []
        
        for track in allTracks {
            if let index = mergedTracks.lastIndex(where: { tracksMatch(track, $0) }) {
                mergedTracks[index] = mergeTrack(track, into: mergedTracks[index])
            } else {
                mergedTracks.append(track)
            }
        }
        
        return mergedTracks
    }
    
    private func normalize(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespaces).lowercased()
    }
    
    private func tracksMatch(_ t1: RecentTrack, _ t2: RecentTrack) -> Bool {
        normalize(t1.artist) == normalize(t2.artist) &&
        normalize(t1.name) == normalize(t2.name) &&
        timestampsMatch(t1.date, t2.date)
    }
    
    private func timestampsMatch(_ d1: Int?, _ d2: Int?) -> Bool {
        if d1 == nil && d2 == nil { return true }
        guard let d1 = d1, let d2 = d2 else { return false }
        return abs(d1 - d2) < 120
    }
    
    private func mergeTrack(_ track: RecentTrack, into existing: RecentTrack) -> RecentTrack {
        let preferred = Defaults.shared.mainServicePreference
        
        if let source = track.sourceService, source == preferred {
            print("MERGE: Swapping \(existing.sourceService?.id ?? "nil") with preferred \(source.id) for \(track.name)")
            var result = track
            result.serviceInfo.merge(existing.serviceInfo) { (_, new) in new }
            return result
        } else {
            if let source = track.sourceService, let preferred = preferred {
                print("MERGE: Keeping \(existing.sourceService?.id ?? "nil") over \(source.id) (Preferred: \(preferred.id)) for \(track.name)")
            }
            var result = existing
            result.serviceInfo.merge(track.serviceInfo) { (_, new) in new }
            return result
        }
    }
}
