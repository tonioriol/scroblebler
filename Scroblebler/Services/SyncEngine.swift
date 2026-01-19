import Foundation

/// Coordinates listen synchronization across services
/// Implements optimistic updates with background sync
@MainActor
class SyncEngine {
    private let store: ListenStore
    private let scrobbleManager: ScrobbleManager
    private let offlineQueue: OfflineQueue

    init(store: ListenStore, scrobbleManager: ScrobbleManager, offlineQueue: OfflineQueue) {
        self.store = store
        self.scrobbleManager = scrobbleManager
        self.offlineQueue = offlineQueue
    }

    /// Convenience initializer that is safe with MainActor isolation.
    @MainActor
    static func makeDefault() -> SyncEngine {
        SyncEngine(store: .shared, scrobbleManager: .shared, offlineQueue: .shared)
    }

    // MARK: - Main Entry Points

    /// Scrobble a new listen (called when scrobble threshold met)
    func scrobble(_ nowPlaying: Listen) async {
        Logger.info("🎵 SyncEngine.scrobble: \(nowPlaying.track) by \(nowPlaying.artist)", log: Logger.scrobbling)

        // 1. Convert to Listen with pending status for all enabled services
        var newListen = nowPlaying
        let enabledServices = Defaults.shared.enabledServices.map { $0.service }

        for service in enabledServices {
            newListen.services[service.rawValue] = ServiceSyncState(status: .pending)
        }

        // 2. Insert into SQLite (optimistic)
        do {
            let insertedListen = try await store.insert(newListen)
            Logger.info("✅ Optimistically inserted listen with id: \(insertedListen.id ?? -1)", log: Logger.scrobbling)

            // 3. Update UI immediately
            await updateUIWithNewListen(insertedListen)

            // 4. Trigger sync for each pending service
            await processPendingForListen(insertedListen)

        } catch {
            Logger.error("❌ Failed to insert listen: \(error)", log: Logger.scrobbling)
        }
    }

    /// Process all pending syncs
    func processPending() async {
        Logger.info("🔄 SyncEngine.processPending: Starting", log: Logger.sync)

        let enabledServices = Defaults.shared.enabledServices.map { $0.service }

        for service in enabledServices {
            do {
                // Get listens where services[x].status == pending
                let pendingListens = try await store.getPending(service: service.rawValue)
                Logger.info("📋 Found \(pendingListens.count) pending listens for \(service.rawValue)", log: Logger.sync)

                // Batch send to service
                for listen in pendingListens {
                    await processSingleListen(listen, service: service)
                }

            } catch {
                Logger.error("❌ Error processing pending for \(service.rawValue): \(error)", log: Logger.sync)
            }
        }
    }

    /// Reconcile local with remote
    func reconcile(remoteListens: [Listen], service: ScrobbleService) async {
        Logger.info("🔄 SyncEngine.reconcile: Starting for \(service.rawValue)", log: Logger.sync)

        for remoteListen in remoteListens {
            do {
                // 1. Find local match by canonicalKey + timestamp window
                if let localListen = try await findLocalMatch(for: remoteListen) {
                    // 2. Match found - merge service identifiers
                    await mergeServiceIdentifiers(local: localListen, remote: remoteListen, service: service)

                } else {
                    // 3. No match - optionally import (user setting?)
                    if Defaults.shared.importRemoteListens {
                        await importRemoteListen(remoteListen, service: service)
                    }
                }

            } catch {
                Logger.error("❌ Error reconciling listen \(remoteListen.track): \(error)", log: Logger.sync)
            }
        }
    }

    /// Delete scrobble from service(s)
    func deleteFromService(listenId: Int64, services: [ScrobbleService]) async {
        Logger.info("🗑️ SyncEngine.deleteFromService: listenId=\(listenId)", log: Logger.sync)

        do {
            // 1. Get listen first (need it for API call)
            let allListens = try await store.getRecent(limit: 1000)
            guard let listen = allListens.first(where: { $0.id == listenId }) else {
                Logger.error("❌ Listen not found for deletion", log: Logger.sync)
                return
            }

            // 2. Mark as deleted locally (optimistic)
            for service in services {
                try await store.markDeleted(listenId: listenId, service: service.rawValue)
            }

            // 3. Call service API
            let stringServiceInfo = listen.services.reduce(into: [String: ServiceTrackData]()) { result, entry in
                result[entry.key] = ServiceTrackData(
                    timestamp: entry.value.timestamp,
                    id: entry.value.recordingMsid,
                    artistMbid: entry.value.artistMbid,
                    releaseMbid: entry.value.releaseMbid
                )
            }

            await scrobbleManager.deleteScrobbleAll(
                artist: listen.artist,
                track: listen.track,
                serviceInfo: stringServiceInfo
            )

            // 4. Update status on success/failure
            // Service manager will handle status updates

        } catch {
            Logger.error("❌ Failed to delete listen: \(error)", log: Logger.sync)
        }
    }

    // MARK: - Private Helpers

    private func updateUIWithNewListen(_ listen: Listen) async {
        // Update history
        var currentHistory = store.history
        currentHistory.insert(listen, at: 0)
        store.setHistory(currentHistory)

        // Clear now playing
        store.clearCurrentListen()
    }

    private func processPendingForListen(_ listen: Listen) async {
        let enabledServices = Defaults.shared.enabledServices.map { $0.service }

        for service in enabledServices {
            if listen.services[service.rawValue]?.status == .pending {
                await processSingleListen(listen, service: service)
            }
        }
    }

    private func processSingleListen(_ listen: Listen, service: ScrobbleService) async {
        guard let credentials = Defaults.shared.credentials(for: service) else {
            Logger.error("❌ No credentials for \(service.rawValue)", log: Logger.sync)
            return
        }

        do {
            // Convert Listen to Track for backward compatibility
            let track = Track(
                id: UUID(),
                artist: listen.artist,
                album: listen.album,
                name: listen.track,
                timestamp: listen.listenedAt,
                duration: listen.duration,
                sourceService: service,
                loved: listen.loved,
                playcount: 1,
                scrobbled: true,
                serviceInfo: convertServicesToServiceInfo(listen.services),
                artwork: nil,
                imageUrl: nil
            )

            // Send to service
            try await scrobbleManager.scrobble(credentials: credentials, track: track)

            // Mark as synced
            let serviceRaw = service.rawValue
            if let timestamp = listen.services[serviceRaw]?.timestamp,
               let recordingMsid = listen.services[serviceRaw]?.recordingMsid {
                try await store.markSynced(
                    listenId: listen.id ?? -1,
                    service: serviceRaw,
                    timestamp: timestamp,
                    recordingMsid: recordingMsid
                )
            } else {
                try await store.markSynced(
                    listenId: listen.id ?? -1,
                    service: serviceRaw,
                    timestamp: nil,
                    recordingMsid: nil
                )
            }

            Logger.info("✅ Synced listen \(listen.track) to \(service.rawValue)", log: Logger.sync)

        } catch {
            Logger.error("❌ Failed to sync to \(service.rawValue): \(error)", log: Logger.sync)
            try? await store.markFailed(
                listenId: listen.id ?? -1,
                service: service.rawValue,
                error: error.localizedDescription
            )
        }
    }

    private func convertServicesToServiceInfo(_ services: [String: ServiceSyncState]) -> [ScrobbleService: ServiceTrackData] {
        var serviceInfo: [ScrobbleService: ServiceTrackData] = [:]

        for (serviceString, syncState) in services {
            if let service = ScrobbleService(rawValue: serviceString) {
                serviceInfo[service] = ServiceTrackData(
                    timestamp: syncState.timestamp,
                    id: syncState.recordingMsid,
                    artistMbid: syncState.artistMbid,
                    releaseMbid: syncState.releaseMbid
                )
            }
        }

        return serviceInfo
    }

    private func findLocalMatch(for remoteListen: Listen) async throws -> Listen? {
        // Try exact timestamp match first
        if let exactMatch = try await store.findByTimestamp(
            artist: remoteListen.artist,
            track: remoteListen.track,
            timestamp: remoteListen.listenedAt
        ) {
            return exactMatch
        }

        // Try timestamp window (±60 seconds)
        let windowMatches = try await store.getRecent(limit: 100)
        return ListenIdentity.findByTimestamp(remoteListen, in: windowMatches)
    }

    private func mergeServiceIdentifiers(local: Listen, remote: Listen, service: ScrobbleService) async {
        var updatedLocal = local

        // Merge service identifiers
        if let remoteServiceData = remote.services[service.rawValue] {
            updatedLocal.services[service.rawValue] = ServiceSyncState(
                status: remoteServiceData.status,
                timestamp: remoteServiceData.timestamp,
                recordingMsid: remoteServiceData.recordingMsid,
                artistMbid: remoteServiceData.artistMbid,
                releaseMbid: remoteServiceData.releaseMbid,
                error: remoteServiceData.error,
                retryCount: remoteServiceData.retryCount,
                lastAttemptAt: remoteServiceData.lastAttemptAt
            )
        }

        // Use remote loved status (remote = truth for UI)
        updatedLocal.loved = remote.loved

        // Update
        try? await store.update(updatedLocal)
        Logger.info("🔄 Merged service identifiers for \(local.track)", log: Logger.sync)
    }

    private func importRemoteListen(_ remoteListen: Listen, service: ScrobbleService) async {
        var listenToImport = remoteListen

        // Mark as synced with this service
        let serviceRaw = service.rawValue
        if let serviceData = remoteListen.services[serviceRaw] {
            listenToImport.services[serviceRaw] = ServiceSyncState(
                status: .synced,
                timestamp: serviceData.timestamp,
                recordingMsid: serviceData.recordingMsid,
                artistMbid: serviceData.artistMbid,
                releaseMbid: serviceData.releaseMbid,
                error: serviceData.error,
                retryCount: serviceData.retryCount,
                lastAttemptAt: serviceData.lastAttemptAt
            )
        }

        // Mark other services as not present
        let allServices: [ScrobbleService] = [.lastfm, .librefm, .listenbrainz]
        for otherService in allServices where otherService != service {
            if listenToImport.services[otherService.rawValue] == nil {
                listenToImport.services[otherService.rawValue] = ServiceSyncState(status: .pending)
            }
        }

        // Insert
        do {
            let inserted = try await store.insert(listenToImport)
            Logger.info("📥 Imported remote listen: \(inserted.track)", log: Logger.sync)

            // Update UI
            var currentHistory = store.history
            currentHistory.insert(inserted, at: 0)
            store.setHistory(currentHistory)

        } catch {
            Logger.error("❌ Failed to import remote listen: \(error)", log: Logger.sync)
        }
    }
}
