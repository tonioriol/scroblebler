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
    
    private let crossServiceSync: CrossServiceSync
    private let backfillService: BackfillService
    
    init() {
        self.crossServiceSync = CrossServiceSync(clients: clients)
        self.backfillService = BackfillService(clients: clients)
    }
    
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
        // Use CrossServiceSync to reconcile tracks
        let backfillTasks = await crossServiceSync.reconcile(
            primaryTracks: &tracks,
            secondaryServices: otherServices,
            limit: limit,
            page: page
        )
        
        // Execute backfills asynchronously
        if !backfillTasks.isEmpty {
            Task {
                let events = await backfillService.execute(tasks: backfillTasks)
                // Publish the last backfill event
                if let lastEvent = events.last {
                    await MainActor.run {
                        self.lastBackfilledTrack = lastEvent
                    }
                }
            }
        }
    }
}
