import Foundation
import SwiftUI

/// Coordinates listen synchronization across services
/// Implements optimistic updates with background sync
@MainActor
class SyncEngine {
    /// Single long-lived instance so pending processing can be triggered from multiple places
    /// (launch, popover open, network regain) without losing internal debounce/locking state.
    @MainActor
    static let shared = SyncEngine(store: .shared, scrobbleManager: .shared, offlineQueue: .shared)

    private let store: ListenStore
    private let scrobbleManager: ScrobbleManager
    private let offlineQueue: OfflineQueue

    private var isProcessingPending = false
    private var scheduledProcessTask: Task<Void, Never>?
    private let maxRetryCount = 3

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

    /// Debounced entry point for places that may fire frequently (popover open, network flaps).
    func scheduleProcessPending(reason: String, debounceNanoseconds: UInt64 = 350_000_000) {
        Logger.debug("⏳ SyncEngine.scheduleProcessPending: \(reason)", log: Logger.sync)
        if isProcessingPending {
            Logger.debug("⏸️ SyncEngine.scheduleProcessPending: Skipping (already running)", log: Logger.sync)
            return
        }

        if scheduledProcessTask != nil {
            Logger.debug("⏳ SyncEngine.scheduleProcessPending: Already scheduled", log: Logger.sync)
            return
        }

        scheduledProcessTask = Task {
            defer { self.scheduledProcessTask = nil }
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            await self.processPending()
        }
    }

    // MARK: - Main Entry Points

    /// Scrobble a new listen (called when scrobble threshold met)
    func scrobble(_ nowPlaying: Listen) async {
        Logger.info("🎵 SyncEngine.scrobble: \(nowPlaying.track) by \(nowPlaying.artist)", log: Logger.scrobbling)

        let trimmedArtist = nowPlaying.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTrack = nowPlaying.track.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedArtist.isEmpty, !trimmedTrack.isEmpty else {
            Logger.debug("SyncEngine.scrobble skipped (missing artist/track)", log: Logger.scrobbling)
            return
        }

        // 1. Convert to Listen with pending status for all enabled services
        var newListen = nowPlaying
        let enabledServices = Defaults.shared.enabledServices.map { $0.service }

        for service in enabledServices {
            newListen.services[service.rawValue] = ServiceSyncState(
                status: .pending,
                timestamp: nowPlaying.listenedAt
            )
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
        guard Reachability.shared.isConnected else {
            Logger.debug("⏸️ SyncEngine.processPending: Skipping (offline)", log: Logger.sync)
            return
        }

        guard !isProcessingPending else {
            Logger.debug("⏸️ SyncEngine.processPending: Skipping (already running)", log: Logger.sync)
            return
        }

        isProcessingPending = true
        defer { isProcessingPending = false }

        Logger.info("🔄 SyncEngine.processPending: Starting", log: Logger.sync)

        let enabledServices = Defaults.shared.enabledServices.map { $0.service }

        // Keep this conservative to avoid hammering APIs if a user has a large backlog.
        // This will still make progress, and can be invoked again later (e.g. on next app open or
        // when the network becomes available).
        let maxPerService = 25

        let retryAfterSeconds: TimeInterval = 60 * 30

        for service in enabledServices {
            do {
                // Get listens where services[x].status == pending
                let pendingListens = try await store.getPending(service: service.rawValue)
                Logger.info("📋 Found \(pendingListens.count) pending listens for \(service.rawValue)", log: Logger.sync)

                let deletePendingListens = try await store.getDeletePending(
                    service: service.rawValue,
                    maxRetryCount: maxRetryCount,
                    retryAfterSeconds: retryAfterSeconds
                )
                Logger.info("🗑️ Found \(deletePendingListens.count) delete-pending listens for \(service.rawValue)", log: Logger.sync)

                let retryableFailed = try await store.getRetryableFailed(
                    service: service.rawValue,
                    maxRetryCount: maxRetryCount,
                    retryAfterSeconds: retryAfterSeconds
                )
                Logger.info("🔁 Found \(retryableFailed.count) retryable failed listens for \(service.rawValue)", log: Logger.sync)

                // Batch send to service
                for listen in pendingListens.prefix(maxPerService) {
                    await processSingleListen(listen, service: service)
                }

                for listen in retryableFailed.prefix(maxPerService) {
                    if let listenId = listen.id {
                        try? await store.markPending(listenId: listenId, service: service.rawValue)
                    }
                    await processSingleListen(listen, service: service)
                }

                for listen in deletePendingListens.prefix(maxPerService) {
                    guard let listenId = listen.id else { continue }
                    await deleteFromService(listenId: listenId, services: [service])
                }

            } catch {
                Logger.error("❌ Error processing pending for \(service.rawValue): \(error)", log: Logger.sync)
            }
        }

        // Opportunistically clean up rows that are fully deleted across all enabled services.
        await store.pruneFullyDeleted(enabledServices: enabledServices)
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

            // 3. Call service API
            let stringServiceInfo = listen.services.reduce(into: [String: ServiceTrackData]()) { result, entry in
                result[entry.key] = ServiceTrackData(
                    timestamp: entry.value.timestamp,
                    id: entry.value.recordingMbid,
                    recordingMsid: entry.value.recordingMsid,
                    artistMbid: entry.value.artistMbid,
                    releaseMbid: entry.value.releaseMbid
                )
            }

            await scrobbleManager.deleteScrobbleAll(
                artist: listen.artist,
                track: listen.track,
                serviceInfo: stringServiceInfo,
                listenId: listenId
            )

            // 4. Update status on success/failure
            // Service manager will handle status updates

        } catch {
            Logger.error("❌ Failed to delete listen: \(error)", log: Logger.sync)
        }
    }

    // MARK: - Private Helpers

    private func updateUIWithNewListen(_ listen: Listen) async {
        // Update history with an animated insertion.
        //
        // IMPORTANT: Do NOT clear now playing here.
        // The current listen is owned by Watcher/ListenStore as the single source of truth for
        // playback state. Clearing it during scrobble causes the Now Playing UI to briefly
        // disappear and then reappear with the next track, which feels jumpy.
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            var currentHistory = store.history
            currentHistory.insert(listen, at: 0)
            store.setHistory(currentHistory)
        }
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
        guard let listenId = listen.id else {
            Logger.error("❌ SyncEngine.processSingleListen: missing listen id", log: Logger.sync)
            return
        }

        guard let credentials = Defaults.shared.credentials(for: service) else {
            Logger.error("❌ No credentials for \(service.rawValue)", log: Logger.sync)
            return
        }

        let trimmedArtist = listen.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTrack = listen.track.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedArtist.isEmpty || trimmedTrack.isEmpty {
            let serviceRaw = service.rawValue
            var updatedState = listen.services[serviceRaw] ?? ServiceSyncState(status: .failed)
            if updatedState.timestamp == nil { updatedState.timestamp = listen.listenedAt }
            updatedState.status = .failed
            updatedState.error = "missing artist or track"
            updatedState.retryCount = maxRetryCount
            updatedState.lastAttemptAt = Date.nowISO8601()
            try? await store.updateServiceState(listenId: listenId, service: serviceRaw, state: updatedState)
            Logger.debug("SyncEngine.processSingleListen skipped (missing artist/track)", log: Logger.sync)
            return
        }

        do {
            // Convert Listen to Track for backward compatibility
            let track = Track(
                id: UUID(),
                artist: trimmedArtist,
                album: listen.album,
                name: trimmedTrack,
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
            var updatedState = listen.services[serviceRaw] ?? ServiceSyncState(status: .synced)
            if updatedState.timestamp == nil { updatedState.timestamp = listen.listenedAt }
            updatedState.status = .synced
            updatedState.error = nil
            updatedState.lastAttemptAt = Date.nowISO8601()

            // Ensure we persist service-specific identifiers needed later for deletion/links.
            // Track.serviceInfo comes from the scrobble client and may include ListenBrainz msid/mbids.
            let info = track.serviceInfo[service]
            if updatedState.recordingMsid == nil {
                updatedState.recordingMsid = info?.recordingMsid
            }
            if updatedState.recordingMbid == nil {
                updatedState.recordingMbid = info?.id
            }
            if updatedState.artistMbid == nil {
                updatedState.artistMbid = info?.artistMbid
            }
            if updatedState.releaseMbid == nil {
                updatedState.releaseMbid = info?.releaseMbid
            }

            try await store.updateServiceState(listenId: listenId, service: serviceRaw, state: updatedState)

            Logger.info("✅ Synced listen \(listen.track) to \(service.rawValue)", log: Logger.sync)

        } catch {
            let isCancellation: Bool = {
                let nsError = error as NSError
                return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
            }()

            if isCancellation {
                Logger.debug("⏸️ Sync cancelled for \(service.rawValue); keeping pending for retry", log: Logger.sync)
                try? await store.markPending(listenId: listenId, service: service.rawValue)
            } else {
                Logger.error("❌ Failed to sync to \(service.rawValue): \(error)", log: Logger.sync)
                try? await store.markFailed(
                    listenId: listenId,
                    service: service.rawValue,
                    error: error.localizedDescription
                )
            }
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
                recordingMbid: remoteServiceData.recordingMbid,
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
                recordingMbid: serviceData.recordingMbid,
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
