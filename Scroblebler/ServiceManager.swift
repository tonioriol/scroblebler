import Foundation

// MARK: - BackfillQueue Actor

actor BackfillQueue {
    private var queue: [BackfillTask] = []
    private var isProcessing = false
    private var processedTracks: Set<String> = [] // Track timestamp+artist+track to avoid re-backfilling
    
    func enqueue(_ task: BackfillTask) {
        // Create unique ID for this track+service combination
        let trackId = "\(task.track.date ?? 0)_\(task.track.artist)_\(task.track.name)_\(task.targetService.rawValue)"
        
        // Skip if already processed
        if processedTracks.contains(trackId) {
            print("[SYNC] ⏭️ Skipping already backfilled: '\(task.track.artist) - \(task.track.name)' → \(task.targetService.displayName)")
            return
        }
        
        queue.append(task)
        print("[SYNC] 📥 Queued backfill: '\(task.track.artist) - \(task.track.name)' → \(task.targetService.displayName)")
    }
    
    func processQueue(using serviceManager: ServiceManager) async {
        guard !isProcessing else {
            print("[SYNC] ⚠️ Queue already processing")
            return
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        guard !queue.isEmpty else { return }
        
        print("[SYNC] 🔄 Processing \(queue.count) backfill tasks...")
        
        var succeeded = 0
        var skipped = 0
        var failed = 0
        
        for task in queue {
            // Check if can backfill
            guard task.canBackfill else {
                let age = (task.track.date.map { Date().timeIntervalSince1970 - TimeInterval($0) } ?? 0) / 86400
                print("[SYNC]   ⏭️ Skipped \(task.targetService.displayName): '\(task.track.name)' (too old: \(Int(age))d)")
                skipped += 1
                continue
            }
            
            // Create Track from RecentTrack
            let track = Track(
                artist: task.track.artist,
                album: task.track.album,
                name: task.track.name,
                length: 0, // Not needed for backfill
                artwork: nil,
                year: 0,
                loved: task.track.loved,
                startedAt: Int32(task.track.date ?? 0)
            )
            
            do {
                try await serviceManager.scrobble(credentials: task.targetCredentials, track: track)
                let age = (task.track.date.map { Date().timeIntervalSince1970 - TimeInterval($0) } ?? 0) / 86400
                print("[SYNC]   ✓ Synced to \(task.targetService.displayName): '\(task.track.name)' (\(Int(age))d old)")
                succeeded += 1
                
                // Mark as processed to avoid re-backfilling
                let trackId = "\(task.track.date ?? 0)_\(task.track.artist)_\(task.track.name)_\(task.targetService.rawValue)"
                processedTracks.insert(trackId)
                
                // Rate limiting: wait between requests
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            } catch {
                print("[SYNC]   ✗ Failed \(task.targetService.displayName): '\(task.track.name)' - \(error)")
                failed += 1
            }
        }
        
        print("[SYNC] 📊 Complete: \(succeeded) succeeded, \(skipped) skipped, \(failed) failed")
        
        // Clear queue
        queue.removeAll()
        
        // Notify UI to refresh if any backfills succeeded
        if succeeded > 0 {
            await MainActor.run {
                NotificationCenter.default.post(name: NSNotification.Name("BackfillCompleted"), object: nil)
            }
        }
    }
}

class ServiceManager: ObservableObject {
    static let shared = ServiceManager()
    
    private let clients: [ScrobbleService: ScrobbleClient] = [
        .lastfm: LastFmClient(),
        .librefm: LibreFmClient(),
        .listenbrainz: ListenBrainzClient()
    ]
    
    private let backfillQueue = BackfillQueue()
    
    // Per-service buffers: stores the NEXT page for cross-service matching
    private var serviceBuffers: [ScrobbleService: [RecentTrack]] = [:]
    private var lastFetchedPage: Int = 0
    
    func resetBuffers() {
        serviceBuffers.removeAll()
        lastFetchedPage = 0
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
    
    func getAllRecentTracks(limit: Int = 20, page: Int = 1, skipBackfill: Bool = false) async throws -> [RecentTrack] {
        let enabledServices = Defaults.shared.enabledServices
        
        guard !enabledServices.isEmpty else {
            print("📊 No enabled services")
            return []
        }
        
        // Reset buffers if starting fresh (page 1)
        if page == 1 {
            resetBuffers()
        }
        
        print("[SYNC] 📊 Fetching page \(page) from ALL \(enabledServices.count) enabled services...")
        
        // PHASE 1: Fetch current page + next page buffer from all services
        var currentPageResults: [ScrobbleService: [RecentTrack]] = [:]
        var newBuffers: [ScrobbleService: [RecentTrack]] = [:]
        
        await withTaskGroup(of: (ScrobbleService, [RecentTrack]?, [RecentTrack]?).self) { group in
            for credentials in enabledServices {
                guard let client = self.client(for: credentials.service) else { continue }
                
                group.addTask {
                    do {
                        // Fetch current page
                        let currentPage = try await client.getRecentTracks(
                            username: credentials.username,
                            limit: limit,
                            page: page,
                            token: credentials.token
                        )
                        
                        // Fetch next page as buffer for cross-service matching
                        let nextPage = try await client.getRecentTracks(
                            username: credentials.username,
                            limit: limit,
                            page: page + 1,
                            token: credentials.token
                        )
                        
                        print("[SYNC] ✅ Fetched page \(page) (\(currentPage.count) tracks) + buffer (\(nextPage.count) tracks) from \(credentials.service.displayName)")
                        
                        return (credentials.service, currentPage, nextPage)
                    } catch {
                        print("[SYNC] ✗ Failed to fetch from \(credentials.service.displayName): \(error)")
                        return (credentials.service, nil, nil)
                    }
                }
            }
            
            for await (service, currentPage, nextPage) in group {
                if let currentPage = currentPage {
                    currentPageResults[service] = currentPage
                }
                if let nextPage = nextPage {
                    newBuffers[service] = nextPage
                }
            }
        }
        
        // PHASE 2: Merge current page tracks, using buffers ONLY for matching
        let mergedTracks = mergeTracksWithBuffers(
            currentPageResults: currentPageResults,
            buffers: serviceBuffers,
            newBuffers: newBuffers,
            enabledServices: enabledServices
        )
        
        print("[SYNC] 📊 Merged into \(mergedTracks.count) tracks")
        
        // PHASE 3: Update buffers for next iteration
        serviceBuffers = newBuffers
        lastFetchedPage = page
        
        // Return only the first `limit` tracks
        let currentPageTracks = Array(mergedTracks.prefix(limit))
        print("[SYNC] 📊 Returning \(currentPageTracks.count) tracks for page \(page)")
        
        // PHASE 4: Detect backfill opportunities
        if !skipBackfill && page >= 2 {
            await detectAndQueueBackfills(mergedTracks: currentPageTracks, enabledServices: enabledServices)
            
            Task {
                await backfillQueue.processQueue(using: self)
            }
        } else if !skipBackfill && page < 2 {
            print("[SYNC] ⏭️ Skipping backfill detection on page \(page) (waiting for page 2+)")
        }
        
        return currentPageTracks
    }
    
    /// Merge current page tracks, using buffers from other services for matching
    private func mergeTracksWithBuffers(
        currentPageResults: [ScrobbleService: [RecentTrack]],
        buffers: [ScrobbleService: [RecentTrack]],
        newBuffers: [ScrobbleService: [RecentTrack]],
        enabledServices: [ServiceCredentials]
    ) -> [RecentTrack] {
        var mergedTracks: [RecentTrack] = []
        var processedIds: Set<String> = []
        
        // Collect ONLY current page tracks to process
        var tracksToProcess: [(track: RecentTrack, service: ScrobbleService)] = []
        for (service, tracks) in currentPageResults {
            for track in tracks {
                tracksToProcess.append((track, service))
            }
        }
        
        // Sort by timestamp descending
        tracksToProcess.sort { ($0.track.date ?? 0) > ($1.track.date ?? 0) }
        
        print("[SYNC] 🔄 Processing \(tracksToProcess.count) current page tracks")
        
        // Process each track
        for (track, service) in tracksToProcess {
            let trackServiceId = "\(track.date ?? 0)_\(track.artist)_\(track.name)_\(service.rawValue)"
            
            if processedIds.contains(trackServiceId) {
                continue
            }
            
            var merged = track
            merged.sourceService = service
            processedIds.insert(trackServiceId)
            
            var matchCount = 0
            
            // Build comparison pool: current page from other services + their buffers
            var comparisonTracks: [(track: RecentTrack, service: ScrobbleService)] = []
            
            for (otherService, otherTracks) in currentPageResults where otherService != service {
                for otherTrack in otherTracks {
                    comparisonTracks.append((otherTrack, otherService))
                }
            }
            
            // Add buffers from OTHER services (previous page's next-page buffer)
            for (otherService, buffer) in buffers where otherService != service {
                for bufferTrack in buffer {
                    comparisonTracks.append((bufferTrack, otherService))
                }
            }
            
            // Add new buffers from OTHER services (current page's next-page buffer)
            for (otherService, buffer) in newBuffers where otherService != service {
                for bufferTrack in buffer {
                    comparisonTracks.append((bufferTrack, otherService))
                }
            }
            
            // Try to match against comparison pool
            for (otherTrack, otherService) in comparisonTracks {
                let otherTrackServiceId = "\(otherTrack.date ?? 0)_\(otherTrack.artist)_\(otherTrack.name)_\(otherService.rawValue)"
                
                if processedIds.contains(otherTrackServiceId) {
                    continue
                }
                
                if tracksMatch(track, otherTrack) {
                    print("[SYNC] ✅ MATCHED '\(track.artist) - \(track.name)' between \(service.displayName) and \(otherService.displayName)")
                    
                    // Merge serviceInfo
                    merged.serviceInfo.merge(otherTrack.serviceInfo) { (_, new) in new }
                    
                    // Mark as processed
                    processedIds.insert(otherTrackServiceId)
                    matchCount += 1
                }
            }
            
            // Calculate sync status
            let enabledServiceSet = Set(enabledServices.map { $0.service })
            let presentInServices = Set([service] + merged.serviceInfo.keys.compactMap { ScrobbleService(rawValue: $0) })
            
            if presentInServices == enabledServiceSet {
                merged.syncStatus = .synced
            } else if presentInServices.count == 1 {
                merged.syncStatus = .primaryOnly
            } else {
                merged.syncStatus = .partial
            }
            
            mergedTracks.append(merged)
        }
        
        return mergedTracks
    }
    
    
    /// Detect tracks that need backfilling and queue them
    private func detectAndQueueBackfills(mergedTracks: [RecentTrack], enabledServices: [ServiceCredentials]) async {
        let enabledServiceSet = Set(enabledServices.map { $0.service })
        
        for track in mergedTracks {
            let presentInServices = Set([track.sourceService].compactMap { $0 } + track.serviceInfo.keys.compactMap { ScrobbleService(rawValue: $0) })
            let missingServices = enabledServiceSet.subtracting(presentInServices)
            
            if !missingServices.isEmpty {
                print("[SYNC] 🔍 Track '\(track.artist) - \(track.name)' missing from: \(missingServices.map { $0.displayName }.joined(separator: ", "))")
                
                // Queue backfill tasks for missing services
                for service in missingServices {
                    guard let credentials = enabledServices.first(where: { $0.service == service }) else { continue }
                    
                    let task = BackfillTask(
                        track: track,
                        targetService: service,
                        targetCredentials: credentials,
                        sourceServices: Array(presentInServices)
                    )
                    
                    if task.canBackfill {
                        await backfillQueue.enqueue(task)
                    }
                }
            }
        }
    }
    
    /// Check if two tracks match using timestamp + fuzzy matching
    private func tracksMatch(_ track1: RecentTrack, _ track2: RecentTrack) -> Bool {
        let t1 = track1.date ?? 0
        let t2 = track2.date ?? 0
        let timeDiff = abs(t1 - t2)
        
        // Check name similarity
        let artistScore = StringSimilarity.similarity(normalize(track1.artist), normalize(track2.artist))
        let trackScore = StringSimilarity.similarity(normalize(track1.name), normalize(track2.name))
        let combinedScore = (artistScore + trackScore) / 2.0
        
        // Require exact timestamp match (within 30 seconds for network delays)
        // AND high similarity score (>= 95% for case differences like "Of" vs "of")
        let matches = timeDiff <= 30 && combinedScore >= 0.95
        
        if matches {
            print("[SYNC] ✓ Matched '\(track1.artist) - \(track1.name)' vs '\(track2.artist) - \(track2.name)' | Score: \(String(format: "%.2f", combinedScore)), TS diff: \(timeDiff)s")
        }
        
        return matches
    }
    
    private func normalize(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespaces).lowercased()
    }
    
    private func timestampsMatch(_ d1: Int?, _ d2: Int?) -> Bool {
        if d1 == nil && d2 == nil { return true }
        guard let d1 = d1, let d2 = d2 else { return false }
        return abs(d1 - d2) <= 30  // Within 30 seconds - allows for network delays
    }
}
