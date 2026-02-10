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

    func updateNowPlayingAll(listen: Listen) async -> Listen {
        if await LocalBlacklist.shared.contains(artist: listen.artist, track: listen.track) {
            Logger.info("Update now playing skipped (blacklisted): \(listen.track) by \(listen.artist)", log: Logger.playback)
            return listen
        }

        let enabledServices = Defaults.shared.enabledServices

        await withTaskGroup(of: Void.self) { group in
            for credentials in enabledServices {
                group.addTask {
                    do {
                        // Convert Listen to Track for compatibility
                        let track = Track(
                            id: UUID(),
                            artist: listen.artist,
                            album: listen.album,
                            name: listen.track,
                            timestamp: listen.listenedAt,
                            duration: listen.duration,
                            sourceService: credentials.service,
                            loved: listen.loved,
                            playcount: 1,
                            scrobbled: false,
                            blacklisted: false,
                            serviceInfo: [:],
                            artwork: listen.artwork,
                            imageUrl: nil
                        )
                        try await self.updateNowPlaying(credentials: credentials, track: track)
                        Logger.info("Updated now playing on \(credentials.service.displayName): \(listen.track) by \(listen.artist)", log: Logger.playback)
                    } catch {
                        Logger.error("Failed to update now playing on \(credentials.service.displayName): \(error)", log: Logger.playback)
                    }
                }
            }
        }

        return listen
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

    func deleteScrobbleAll(artist: String, track: String, serviceInfo: [String: ServiceTrackData], listenId: Int64?) async {
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTrack = track.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabledServices = Defaults.shared.enabledServices

        // Some "non-music" sources (e.g. browsers) can produce listens with an empty artist.
        // If the track title looks like "Artist - Title", split it so delete calls have the
        // minimum data required by services like Last.fm.
        func stripNotificationPrefix(_ text: String) -> String {
            text
                .replacingOccurrences(
                    of: #"^\(\d+\+?\)\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func splitArtistTitleIfNeeded(artist: String, track: String) -> (artist: String, track: String) {
            let cleanedTrack = stripNotificationPrefix(track)
            guard artist.isEmpty else {
                return (artist: artist, track: cleanedTrack)
            }

            for separator in [" - ", " – ", " — "] {
                guard let range = cleanedTrack.range(of: separator) else { continue }
                let left = cleanedTrack[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                let right = cleanedTrack[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !left.isEmpty, !right.isEmpty {
                    return (artist: left, track: right)
                }
            }

            return (artist: artist, track: cleanedTrack)
        }

        let (effectiveArtist, effectiveTrack) = splitArtistTitleIfNeeded(
            artist: trimmedArtist,
            track: trimmedTrack
        )

        Logger.info("🗑️ DELETE_ALL: Deleting scrobble '\(artist) - \(track)' from \(enabledServices.count) enabled services", log: Logger.scrobbling)
        Logger.debug("DELETE_ALL: Available serviceInfo keys: \(serviceInfo.keys.sorted().joined(separator: ", "))", log: Logger.scrobbling)
        Logger.debug("DELETE_ALL: Enabled services: \(enabledServices.map { $0.service.displayName }.joined(separator: ", "))", log: Logger.scrobbling)
        if trimmedArtist != effectiveArtist || trimmedTrack != effectiveTrack {
            Logger.info(
                "DELETE_ALL: Normalized delete metadata artist='\(effectiveArtist)' track='\(effectiveTrack)' (from artist='\(trimmedArtist)' track='\(trimmedTrack)')",
                log: Logger.scrobbling
            )
        }

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
                        artist: effectiveArtist,
                        track: effectiveTrack,
                        timestamp: info?.timestamp,
                        serviceId: info?.recordingMsid
                    )

                    Logger.debug("DELETE_ALL: Created identifier for \(credentials.service.displayName): artist=\(identifier.artist), track=\(identifier.track), timestamp=\(identifier.timestamp ?? 0), serviceId=\(identifier.serviceId ?? "nil")", log: Logger.scrobbling)

                    group.addTask {
                        Logger.info("DELETE_ALL: 🚀 Starting delete for \(credentials.service.displayName)", log: Logger.scrobbling)

                        do {
                            // If we have a listenId, always prefer the latest persisted row values
                            // (the in-memory HistoryItem snapshot may be missing identifiers).
                            var identifier = identifier
                            if let listenId,
                               let latest = try? await ListenStore.shared.get(id: listenId) {
                                let latestArtist = latest.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                                let latestTrack = latest.track.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !latestArtist.isEmpty || !latestTrack.isEmpty {
                                    let (a, t) = splitArtistTitleIfNeeded(artist: latestArtist, track: latestTrack)
                                    identifier = ScrobbleIdentifier(
                                        artist: a,
                                        track: t,
                                        timestamp: identifier.timestamp,
                                        serviceId: identifier.serviceId
                                    )
                                }
                            }

                            // Special case: ListenBrainz deletion requires recording_msid.
                            // If we don't have it yet, try to look it up by timestamp+metadata.
                            if credentials.service == .listenbrainz,
                               identifier.serviceId == nil,
                               let ts = identifier.timestamp,
                               let lbClient = self.client(for: .listenbrainz) as? ListenBrainzClient {
                                if let msid = try? await lbClient.findRecordingMsid(
                                    artist: identifier.artist,
                                    track: identifier.track,
                                    listenedAt: ts
                                ) {
                                    identifier = ScrobbleIdentifier(
                                        artist: identifier.artist,
                                        track: identifier.track,
                                        timestamp: identifier.timestamp,
                                        serviceId: msid
                                    )
                                    if let listenId {
                                        // Persist msid so future retries don't have to re-fetch.
                                        var state = ServiceSyncState(status: .deletePending)
                                        state.timestamp = ts
                                        state.recordingMsid = msid
                                        try? await ListenStore.shared.updateServiceState(
                                            listenId: listenId,
                                            service: credentials.service.rawValue,
                                            state: state
                                        )
                                    }
                                }
                            }

                            // If we lack the required identifiers, treat as a no-op (it was never scrobbled there).
                            let canDelete: Bool = {
                                switch credentials.service {
                                case .listenbrainz:
                                    return identifier.timestamp != nil && identifier.serviceId != nil
                                case .lastfm, .librefm:
                                    let hasTrack = !identifier.track.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    // Some non-music scrobbles can have an empty artist. If the
                                    // remote service has such an entry, the *correct* delete call
                                    // may still need artist="".
                                    return identifier.timestamp != nil && hasTrack
                                }
                            }()

                            if canDelete {
                                if let listenId {
                                    try? await ListenStore.shared.markDeletePending(
                                        listenId: listenId,
                                        service: credentials.service.rawValue
                                    )
                                }

                                try await self.deleteScrobble(credentials: credentials, identifier: identifier)
                                Logger.info("DELETE_ALL: ✅ Successfully deleted scrobble from \(credentials.service.displayName): \(artist) - \(track)", log: Logger.scrobbling)
                            } else {
                                Logger.info("DELETE_ALL: ⏭️ Skip delete for \(credentials.service.displayName) (missing identifiers)", log: Logger.scrobbling)

                                // If we can't even attempt a remote delete, treat it as "not present"
                                // on that service and allow the local history item to be removed.
                                if let listenId {
                                    let reason: String = {
                                        switch credentials.service {
                                        case .listenbrainz:
                                            if identifier.timestamp == nil {
                                                return "missing listened_at timestamp"
                                            }
                                            return "missing recording_msid"
                                        case .lastfm, .librefm:
                                            if identifier.timestamp == nil { return "missing timestamp" }
                                            if identifier.track.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "missing track" }
                                            return "missing identifiers"
                                        }
                                    }()

                                    Logger.info(
                                        "DELETE_ALL: treating as not present on \(credentials.service.displayName) (\(reason)); marking deleted locally",
                                        log: Logger.scrobbling
                                    )
                                    try? await ListenStore.shared.markDeleted(
                                        listenId: listenId,
                                        service: credentials.service.rawValue
                                    )
                                }
                            }

                            // Only mark deleted if we actually performed a remote delete.
                            if canDelete, let listenId {
                                try? await ListenStore.shared.markDeleted(listenId: listenId, service: credentials.service.rawValue)
                            }
                        } catch {
                            Logger.error("DELETE_ALL: ❌ Failed to delete scrobble from \(credentials.service.displayName): \(error)", log: Logger.scrobbling)

                            let nsError = error as NSError
                            let isNetworkError = nsError.domain == NSURLErrorDomain
                            if isNetworkError {
                                do {
                                    try await OfflineQueue.shared.enqueue(operation)
                                    Logger.info("DELETE_ALL: Queued delete retry for \(credentials.service.displayName) (network error)", log: Logger.scrobbling)
                                } catch {
                                    Logger.error("DELETE_ALL: Failed to queue delete retry: \(error)", log: Logger.scrobbling)
                                }
                            } else if let listenId {
                                // Non-network delete failure should be surfaced to the user.
                                try? await ListenStore.shared.markDeleteFailed(
                                    listenId: listenId,
                                    service: credentials.service.rawValue,
                                    error: error.localizedDescription
                                )
                            }
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
