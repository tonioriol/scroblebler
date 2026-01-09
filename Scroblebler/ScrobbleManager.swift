import Foundation

struct BackfillEvent: Equatable {
    let artist: String
    let track: String
    let timestamp: Int
    let service: ScrobbleService
}

class ScrobbleManager: ObservableObject {
    static let shared = ScrobbleManager()
    
    @Published var lastBackfilledTrack: BackfillEvent?
    @Published var scrobbleCompletedTrigger = 0
    
    private let services: [ScrobbleService: Service] = [
        .lastfm: LastFmService(client: LastFmClient()),
        .librefm: LibreFmService(client: LibreFmClient()),
        .listenbrainz: ListenBrainzService(client: ListenBrainzClient())
    ]
    
    init() {
        // Restore stored credentials to clients
        restoreCredentials()
    }
    
    private func restoreCredentials() {
        for service in ScrobbleService.allCases {
            if let credentials = Defaults.shared.credentials(for: service),
               let serviceInstance = services[service] {
                serviceInstance.client.setCredentials(username: credentials.username, sessionKey: credentials.token)
                Logger.info("✅ Restored credentials for \(service.displayName): \(credentials.username)", log: Logger.authentication)
            } else {
                Logger.debug("No credentials to restore for \(service.displayName)", log: Logger.authentication)
            }
        }
    }
    
    func service(for scrobbleService: ScrobbleService) -> Service? {
        services[scrobbleService]
    }
    
    func client(for service: ScrobbleService) -> ScrobbleClient? {
        services[service]?.client
    }
    
    func authenticate(service: ScrobbleService) async throws -> (token: String, authURL: URL) {
        guard let serviceInstance = services[service] else {
            throw NSError(domain: "ScrobbleManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Service not found"])
        }
        return try await serviceInstance.client.authenticate()
    }
    
    func completeAuthentication(service: ScrobbleService, token: String) async throws -> ServiceCredentials {
        guard let serviceInstance = services[service] else {
            throw NSError(domain: "ScrobbleManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Service not found"])
        }
        let result = try await serviceInstance.client.completeAuthentication(token: token)
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
            throw NSError(domain: "ScrobbleManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Last.fm not authenticated via API. Please authenticate first."])
        }
        
        guard let lastFmService = services[.lastfm],
              let lastFmClient = lastFmService.client as? LastFmClient else {
            throw NSError(domain: "ScrobbleManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Last.fm client not found"])
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
        guard let service = services[credentials.service] else { return }
        try await service.client.updateNowPlaying(track: track)
    }
    
    func scrobble(credentials: ServiceCredentials, track: Track) async throws {
        guard let service = services[credentials.service] else {
            Logger.error("No service found for \(credentials.service.displayName)", log: Logger.scrobbling)
            return
        }
        Logger.debug("Scrobbling to \(credentials.service.displayName): '\(track.artist) - \(track.name)' (timestamp: \(track.startedAt))", log: Logger.scrobbling)
        try await service.client.scrobble(track: track)
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
        
        let enabledServices = Defaults.shared.enabledServices
        
        await withTaskGroup(of: Void.self) { group in
            for credentials in enabledServices {
                group.addTask {
                    do {
                        try await self.updateNowPlaying(credentials: credentials, track: track)
                        Logger.info("Updated now playing on \(credentials.service.displayName): \(track.description)", log: Logger.playback)
                    } catch {
                        Logger.error("Failed to update now playing on \(credentials.service.displayName): \(error)", log: Logger.playback)
                    }
                }
            }
        }
        
        return track
    }
    
    func updateLove(credentials: ServiceCredentials, artist: String, track: String, loved: Bool) async throws {
        guard let service = services[credentials.service] else { return }
        try await service.client.updateLove(artist: artist, track: track, loved: loved)
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
        guard let service = services[credentials.service] else { return }
        try await service.client.deleteScrobble(identifier: identifier)
    }
    
    func deleteScrobbleAll(artist: String, track: String, serviceInfo: [String: ServiceTrackData]) async {
        let enabledServices = Defaults.shared.enabledServices
        
        Logger.info("🗑️ DELETE_ALL: Deleting scrobble '\(artist) - \(track)' from \(enabledServices.count) enabled services", log: Logger.scrobbling)
        Logger.debug("DELETE_ALL: Available serviceInfo keys: \(serviceInfo.keys.sorted().joined(separator: ", "))", log: Logger.scrobbling)
        Logger.debug("DELETE_ALL: Enabled services: \(enabledServices.map { $0.service.displayName }.joined(separator: ", "))", log: Logger.scrobbling)
        
        // Log detailed serviceInfo for debugging
        for (key, data) in serviceInfo {
            Logger.debug("DELETE_ALL: serviceInfo[\(key)] = timestamp: \(data.timestamp ?? 0), id: \(data.id ?? "nil")", log: Logger.scrobbling)
        }
        
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
                    let serviceId = credentials.service.id
                    let info = serviceInfo[serviceId]
                    
                    Logger.debug("DELETE_ALL: Processing \(credentials.service.displayName) (id: \(serviceId))", log: Logger.scrobbling)
                    
                    if info == nil {
                        Logger.error("DELETE_ALL: ⚠️ No serviceInfo for \(credentials.service.displayName) (id: \(serviceId)) - track may not have been scrobbled to this service", log: Logger.scrobbling)
                    } else {
                        Logger.debug("DELETE_ALL: ✅ Found serviceInfo for \(credentials.service.displayName): timestamp=\(info?.timestamp ?? 0), id=\(info?.id ?? "none")", log: Logger.scrobbling)
                    }
                    
                    let identifier = ScrobbleIdentifier(
                        artist: artist,
                        track: track,
                        timestamp: info?.timestamp,
                        serviceId: info?.id
                    )
                    
                    Logger.debug("DELETE_ALL: Created identifier for \(credentials.service.displayName): artist=\(identifier.artist), track=\(identifier.track), timestamp=\(identifier.timestamp ?? 0), serviceId=\(identifier.serviceId ?? "nil")", log: Logger.scrobbling)
                    
                    group.addTask {
                        Logger.info("DELETE_ALL: 🚀 Starting delete for \(credentials.service.displayName)", log: Logger.scrobbling)
                        do {
                            try await self.deleteScrobble(credentials: credentials, identifier: identifier)
                            Logger.info("DELETE_ALL: ✅ Successfully deleted scrobble from \(credentials.service.displayName): \(artist) - \(track)", log: Logger.scrobbling)
                        } catch {
                            Logger.error("DELETE_ALL: ❌ Failed to delete scrobble from \(credentials.service.displayName): \(error)", log: Logger.scrobbling)
                        }
                    }
                }
            }
            Logger.info("DELETE_ALL: 🏁 Completed all deletion tasks", log: Logger.scrobbling)
        }
    }
    
    // MARK: - Single-Service Operations
    
    func fetchRecentTracks(service: ScrobbleService, limit: Int, page: Int) async throws -> [Track] {
        guard let serviceInstance = services[service] else {
            throw NSError(domain: "ScrobbleManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Service not found for \(service.displayName)"])
        }
        return try await serviceInstance.client.getRecentTracks(limit: limit, page: page)
    }
    
    func fetchRecentTracksByTimeRange(service: ScrobbleService, minTs: Int?, maxTs: Int?, limit: Int) async throws -> [Track]? {
        guard let serviceInstance = services[service] else {
            throw NSError(domain: "ScrobbleManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Service not found for \(service.displayName)"])
        }
        return try await serviceInstance.client.getRecentTracksByTimeRange(minTs: minTs, maxTs: maxTs, limit: limit)
    }
}
