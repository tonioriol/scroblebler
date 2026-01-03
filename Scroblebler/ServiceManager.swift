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
        
        // Restore stored credentials to clients
        restoreCredentials()
    }
    
    private func restoreCredentials() {
        for service in ScrobbleService.allCases {
            if let credentials = Defaults.shared.credentials(for: service),
               let client = clients[service] {
                client.setCredentials(username: credentials.username, sessionKey: credentials.token)
                Logger.info("✅ Restored credentials for \(service.displayName): \(credentials.username)", log: Logger.authentication)
            } else {
                Logger.debug("No credentials to restore for \(service.displayName)", log: Logger.authentication)
            }
        }
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
        try await client.updateNowPlaying(track: track)
    }
    
    func scrobble(credentials: ServiceCredentials, track: Track) async throws {
        guard let client = clients[credentials.service] else {
            Logger.error("No client found for \(credentials.service.displayName)", log: Logger.scrobbling)
            return
        }
        Logger.debug("Scrobbling to \(credentials.service.displayName): '\(track.artist) - \(track.name)' (timestamp: \(track.startedAt))", log: Logger.scrobbling)
        try await client.scrobble(track: track)
        Logger.info("Successfully scrobbled to \(credentials.service.displayName)", log: Logger.scrobbling)
    }
    
    // MARK: - Network-Aware Operation Execution
    
    /// Central method for executing operations with offline queue support
    /// This is the single point where network checks happen
    private func executeOrQueue(
        operation: Operation,
        operationName: String,
        onlineExecution: () async -> Void
    ) async {
        if !Reachability.shared.isConnected {
            // Queue for later execution
            do {
                try await OfflineQueue.shared.enqueue(operation)
                Logger.info("\(operationName) queued (offline)", log: Logger.scrobbling)
            } catch {
                Logger.error("Failed to queue \(operationName): \(error)", log: Logger.scrobbling)
            }
            return
        }
        
        // Online - execute immediately
        await onlineExecution()
    }
    
    func scrobbleAll(track: Track) async {
        if await LocalBlacklist.shared.contains(artist: track.artist, track: track.name) {
            Logger.info("Scrobble skipped (blacklisted): \(track.description)", log: Logger.scrobbling)
            return
        }
        
        let enabledServices = Defaults.shared.enabledServices
        let operation = Operation.scrobble(
            track: track,
            services: enabledServices.map { $0.service }
        )
        
        await executeOrQueue(operation: operation, operationName: "Scrobble '\(track.description)'") {
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
                self.scrobbleCompletedTrigger += 1
            }
        }
    }
    
    func updateNowPlayingAll(track: Track) async -> Track {
        if await LocalBlacklist.shared.contains(artist: track.artist, track: track.name) {
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
    
    func updateLove(credentials: ServiceCredentials, artist: String, track: String, loved: Bool) async throws {
        guard let client = clients[credentials.service] else { return }
        try await client.updateLove(artist: artist, track: track, loved: loved)
    }
    
    func updateLoveAll(artist: String, track: String, loved: Bool) async {
        let enabledServices = Defaults.shared.enabledServices
        let operation = Operation.love(
            artist: artist,
            track: track,
            loved: loved,
            services: enabledServices.map { $0.service }
        )
        
        await executeOrQueue(operation: operation, operationName: "Love update '\(artist) - \(track)'") {
            await withTaskGroup(of: Void.self) { group in
                for credentials in enabledServices {
                    group.addTask {
                        do {
                            try await self.updateLove(credentials: credentials, artist: artist, track: track, loved: loved)
                            Logger.info("Updated love on \(credentials.service.displayName): \(artist) - \(track) = \(loved)", log: Logger.scrobbling)
                        } catch {
                            Logger.error("Failed to update love on \(credentials.service.displayName): \(error)", log: Logger.scrobbling)
                        }
                    }
                }
            }
        }
    }
    
    func deleteScrobble(credentials: ServiceCredentials, identifier: ScrobbleIdentifier) async throws {
        guard let client = clients[credentials.service] else { return }
        try await client.deleteScrobble(identifier: identifier)
    }
    
    func deleteScrobbleAll(artist: String, track: String, serviceInfo: [String: ServiceTrackData]) async {
        let enabledServices = Defaults.shared.enabledServices
        
        Logger.info("🗑️ Deleting scrobble '\(artist) - \(track)' from \(enabledServices.count) enabled services", log: Logger.scrobbling)
        Logger.debug("Available serviceInfo keys: \(serviceInfo.keys.joined(separator: ", "))", log: Logger.scrobbling)
        
        // Extract timestamp from any available service for offline queue
        let timestamp = serviceInfo.values.first?.timestamp
        let operation = Operation.delete(
            artist: artist,
            track: track,
            timestamp: timestamp,
            services: enabledServices.map { $0.service }
        )
        
        await executeOrQueue(operation: operation, operationName: "Delete '\(artist) - \(track)'") {
            await withTaskGroup(of: Void.self) { group in
                for credentials in enabledServices {
                    let info = serviceInfo[credentials.service.id]
                    
                    if info == nil {
                        Logger.error("⚠️ No serviceInfo for \(credentials.service.displayName) - track may not be in this service", log: Logger.scrobbling)
                    } else {
                        Logger.debug("✅ Found serviceInfo for \(credentials.service.displayName): timestamp=\(info?.timestamp ?? 0), id=\(info?.id ?? "none")", log: Logger.scrobbling)
                    }
                    
                    let identifier = ScrobbleIdentifier(
                        artist: artist,
                        track: track,
                        timestamp: info?.timestamp,
                        serviceId: info?.id
                    )
                    
                    group.addTask {
                        do {
                            try await self.deleteScrobble(credentials: credentials, identifier: identifier)
                            Logger.info("✅ Deleted scrobble from \(credentials.service.displayName): \(artist) - \(track)", log: Logger.scrobbling)
                        } catch {
                            Logger.error("❌ Failed to delete scrobble from \(credentials.service.displayName): \(error)", log: Logger.scrobbling)
                        }
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
                limit: limit,
                page: page
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
