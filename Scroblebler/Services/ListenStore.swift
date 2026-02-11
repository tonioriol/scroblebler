import Foundation
import Combine
import GRDB

/// Pure storage layer for listen data (repository pattern)
/// Single source of truth for current listen and history
@MainActor
class ListenStore: ObservableObject {
    static let shared = ListenStore()

    // MARK: - Published State

    /// Currently playing listen (single source of truth)
    @Published private(set) var currentListen: Listen?

    /// History listens (only scrobbled listens from API)
    @Published private(set) var history: [Listen] = []

    /// Bumps whenever the underlying listens table changes in a way that affects derived values
    /// like playcount (COUNT queries).
    @Published private(set) var listensRevision: Int = 0

    private let db = LocalDatabase.shared
    private init() {}

    private func bumpListensRevision() {
        listensRevision += 1
    }

    // MARK: - Current Listen Management

    /// Set current listen (from media player)
    func setCurrentListen(_ listen: Listen) {
        currentListen = listen
        Logger.info("Set current listen: \(listen.track) by \(listen.artist)", log: Logger.playback)
    }

    /// Update current listen with enriched data
    func updateCurrentListen(_ listen: Listen) {
        currentListen = listen
        let artworkBytes = listen.artwork?.count ?? 0
        Logger.debug(
            "Updated current listen: \(listen.track) by \(listen.artist) [artworkBytes=\(artworkBytes)]",
            log: Logger.ui
        )
    }

    /// Clear current listen
    func clearCurrentListen() {
        currentListen = nil
        Logger.info("Cleared current listen", log: Logger.playback)
    }

    // MARK: - History Management

    /// Replace history (for page 1 refresh)
    func setHistory(_ listens: [Listen]) {
        history = listens
        Logger.info("Set history: \(listens.count) listens", log: Logger.sync)
    }

    /// Append to history (for pagination)
    func appendHistory(_ listens: [Listen]) {
        // De-duplicate by canonical key
        let existingKeys = Set(history.map { $0.canonicalKey })
        let newListens = listens.filter { !existingKeys.contains($0.canonicalKey) }
        history = history + newListens
        Logger.info("Appended \(newListens.count) listens to history", log: Logger.sync)
    }

    /// Clear all history
    func clearHistory() {
        history = []
        Logger.info("Cleared history", log: Logger.ui)
    }

    // MARK: - Update Operations

    /// Update listen in history by canonical key
    func updateListen(artist: String, track: String, mutation: (inout Listen) -> Void) {
        let key = ListenIdentity.key(artist: artist, track: track)

        // Update in history
        if let index = history.firstIndex(where: { $0.canonicalKey == key }) {
            var updated = history[index]
            mutation(&updated)
            var copy = history
            copy[index] = updated
            history = copy
            Logger.debug("Updated listen in history: \(artist) - \(track)", log: Logger.ui)
        }

        // Update current listen if it matches
        if let current = currentListen, current.canonicalKey == key {
            var updated = current
            mutation(&updated)
            currentListen = updated
            Logger.debug("Updated current listen: \(artist) - \(track)", log: Logger.ui)
        }
    }

    /// Find listen in history or current listen
    func findListen(artist: String, track: String) -> Listen? {
        let key = ListenIdentity.key(artist: artist, track: track)

        // Check current listen first
        if let current = currentListen, current.canonicalKey == key {
            return current
        }

        // Check history
        return history.first(where: { $0.canonicalKey == key })
    }

    // MARK: - Query Operations

    /// Check if listen is loved
    func isLoved(artist: String, track: String) -> Bool {
        return findListen(artist: artist, track: track)?.loved ?? false
    }

    /// Get playcount for listen (computed via COUNT query)
    func playcount(artist: String, track: String) async throws -> Int {
        return try await db.asyncRead { db in
            try Listen
                .filter(Listen.Columns.artist.collating(.nocase) == artist)
                .filter(Listen.Columns.track.collating(.nocase) == track)
                .fetchCount(db)
        }
    }

    // MARK: - CRUD Operations (SQLite)

    /// Insert new listen
    func insert(_ listen: Listen) async throws -> Listen {
        let inserted = try await db.asyncWrite { db in
            var insertedListen = listen
            try insertedListen.insert(db)
            if insertedListen.id == nil {
                insertedListen.id = db.lastInsertedRowID
            }
            return insertedListen
        }
        Logger.debug("Inserted listen: \(inserted.track) by \(inserted.artist)", log: Logger.sync)
        bumpListensRevision()
        return inserted
    }

    /// Update existing listen
    func update(_ listen: Listen) async throws {
        try await db.asyncWrite { db in
            try listen.update(db)
        }
        Logger.debug("Updated listen: \(listen.track) by \(listen.artist)", log: Logger.sync)
    }

    /// Delete listen by ID
    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { db in
            try Listen.deleteOne(db, key: id)
        }

        // Keep in-memory published state in sync.
        if let index = history.firstIndex(where: { $0.id == id }) {
            var copy = history
            copy.remove(at: index)
            history = copy
        }
        if currentListen?.id == id {
            currentListen = nil
        }

        Logger.debug("Deleted listen with id: \(id)", log: Logger.sync)
        bumpListensRevision()
    }

    /// Fetch a single listen by row id.
    func get(id: Int64) async throws -> Listen? {
        try await db.asyncRead { db in
            try Listen.fetchOne(db, key: id)
        }
    }

    // MARK: - Service State Management

    /// Update service state for a listen
    func updateServiceState(listenId: Int64, service: String, state: ServiceSyncState) async throws {
        let updatedListen: Listen? = try await db.asyncWrite { db in
            guard var listen = try Listen.fetchOne(db, key: listenId) else {
                return nil
            }

            listen.services[service] = state
            listen.updatedAt = Date.nowISO8601()
            try listen.update(db)
            return listen
        }

        // Keep in-memory published state in sync so SwiftUI updates immediately.
        if let updatedListen {
            if let index = history.firstIndex(where: { $0.id == listenId }) {
                var copy = history
                copy[index] = updatedListen
                history = copy
            }
            if currentListen?.id == listenId {
                currentListen = updatedListen
            }
        }

        Logger.info("Updated service state for listen \(listenId) service \(service)", log: Logger.sync)
    }

    /// Mark service as synced
    func markSynced(listenId: Int64, service: String, timestamp: Int?, recordingMsid: String?) async throws {
        // Preserve identifiers if we already have them, but always update the status.
        // This avoids accidentally dropping timestamp/MSID on sync completion.
        let existingState: ServiceSyncState? = try? await db.asyncRead { db in
            guard let listen = try Listen.fetchOne(db, key: listenId) else { return nil }
            return listen.services[service]
        }

        var state = existingState ?? ServiceSyncState(status: .synced)
        state.status = .synced
        if state.timestamp == nil { state.timestamp = timestamp }
        if state.recordingMsid == nil { state.recordingMsid = recordingMsid }
        state.error = nil
        state.retryCount = 0
        state.lastAttemptAt = Date.nowISO8601()
        try await updateServiceState(listenId: listenId, service: service, state: state)
    }

    /// Mark service as failed
    func markFailed(listenId: Int64, service: String, error: String) async throws {
        let existingState: ServiceSyncState? = try? await db.asyncRead { db in
            guard let listen = try Listen.fetchOne(db, key: listenId) else { return nil }
            return listen.services[service]
        }

        var state = existingState ?? ServiceSyncState(status: .failed)
        state.status = .failed
        state.error = error
        state.retryCount = (existingState?.retryCount ?? 0) + 1
        state.lastAttemptAt = Date.nowISO8601()
        try await updateServiceState(listenId: listenId, service: service, state: state)
    }

    /// Mark service deletion as failed (no more retries; user may need to delete manually).
    func markDeleteFailed(listenId: Int64, service: String, error: String) async throws {
        let existingState: ServiceSyncState? = try? await db.asyncRead { db in
            guard let listen = try Listen.fetchOne(db, key: listenId) else { return nil }
            return listen.services[service]
        }

        var state = existingState ?? ServiceSyncState(status: .deleteFailed)
        state.status = .deleteFailed
        state.error = error
        state.retryCount = (existingState?.retryCount ?? 0) + 1
        state.lastAttemptAt = Date.nowISO8601()
        try await updateServiceState(listenId: listenId, service: service, state: state)
    }

    /// Mark service as pending (used for retries)
    func markPending(listenId: Int64, service: String) async throws {
        let existingState: ServiceSyncState? = try? await db.asyncRead { db in
            guard let listen = try Listen.fetchOne(db, key: listenId) else { return nil }
            return listen.services[service]
        }

        var state = existingState ?? ServiceSyncState(status: .pending)
        state.status = .pending
        state.error = nil
        state.lastAttemptAt = Date.nowISO8601()
        try await updateServiceState(listenId: listenId, service: service, state: state)
    }

    /// Mark service as deleted
    func markDeleted(listenId: Int64, service: String) async throws {
        let state = ServiceSyncState(status: .deleted)
        try await updateServiceState(listenId: listenId, service: service, state: state)
    }

    /// Delete listens that are fully deleted across all currently-enabled services.
    ///
    /// This keeps the DB tidy and ensures the UI history list eventually drops items the user
    /// successfully deleted everywhere.
    func pruneFullyDeleted(enabledServices: [ScrobbleService], limit: Int = 200) async {
        guard !enabledServices.isEmpty else { return }

        do {
            let candidates = try await getRecent(limit: 2000)
            let enabledKeys = Set(enabledServices.map { $0.rawValue })

            var deletedCount = 0
            for listen in candidates {
                guard deletedCount < limit else { break }
                guard let id = listen.id else { continue }

                let isFullyDeleted = enabledKeys.allSatisfy { key in
                    listen.services[key]?.status == .deleted
                }

                if isFullyDeleted {
                    try? await delete(id: id)
                    deletedCount += 1
                }
            }

            // Also refresh the published history so the UI drops pruned rows.
            // Best-effort and conservative; history is always derived from SQLite.
            if deletedCount > 0 {
                let currentLimit = history.count
                if currentLimit > 0 {
                    try? await refreshHistory(limit: currentLimit)
                }
            }

            if deletedCount > 0 {
                Logger.info("Pruned \(deletedCount) fully-deleted listens", log: Logger.sync)
            }
        } catch {
            Logger.error("Failed to prune fully-deleted listens: \(error)", log: Logger.sync)
        }
    }

    /// Mark service as delete pending (used for delete retries)
    func markDeletePending(listenId: Int64, service: String) async throws {
        let existingState: ServiceSyncState? = try? await db.asyncRead { db in
            guard let listen = try Listen.fetchOne(db, key: listenId) else { return nil }
            return listen.services[service]
        }

        var state = existingState ?? ServiceSyncState(status: .deletePending)
        state.status = .deletePending
        state.error = nil
        state.retryCount = (existingState?.retryCount ?? 0) + 1
        state.lastAttemptAt = Date.nowISO8601()
        try await updateServiceState(listenId: listenId, service: service, state: state)
    }

    // MARK: - Bulk Operations

    /// Get recent listens
    func getRecent(limit: Int) async throws -> [Listen] {
        try await db.asyncRead { db in
            try Listen
                .order(Listen.Columns.listenedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Get recent listens, excluding listens that are fully deleted across all enabled services.
    func getRecentVisible(limit: Int, enabledServices: [ScrobbleService]) async throws -> [Listen] {
        let listens = try await getRecent(limit: max(100, limit * 3)) // over-fetch a bit to account for filtering
        let enabledKeys = Set(enabledServices.map { $0.rawValue })

        let visible = listens.filter { listen in
            // Only consider enabled services when deciding if the listen should be visible.
            for serviceKey in enabledKeys {
                let status = listen.services[serviceKey]?.status
                if status != .deleted {
                    return true
                }
            }
            // If there are no enabled services, keep it visible.
            return enabledKeys.isEmpty
        }

        return Array(visible.prefix(limit))
    }

    /// Search listens by artist/track/album in SQLite.
    ///
    /// Note: we still apply the same "fully deleted across enabled services" visibility rule.
    func search(query: String, limit: Int, enabledServices: [ScrobbleService]) async throws -> [Listen] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return try await getRecentVisible(limit: limit, enabledServices: enabledServices)
        }

        // Escape LIKE wildcards so the query behaves as a literal substring match.
        let escaped = q
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")

        let pattern = "%\(escaped)%"
        let enabledKeys = Set(enabledServices.map { $0.rawValue })

        let listens = try await db.asyncRead { db in
            try Listen
                .filter(
                    sql: "(artist LIKE ? ESCAPE '\\' OR track LIKE ? ESCAPE '\\' OR album LIKE ? ESCAPE '\\')",
                    arguments: [pattern, pattern, pattern]
                )
                .order(Listen.Columns.listenedAt.desc)
                .limit(max(100, limit * 3))
                .fetchAll(db)
        }

        let visible = listens.filter { listen in
            for serviceKey in enabledKeys {
                let status = listen.services[serviceKey]?.status
                if status != .deleted {
                    return true
                }
            }
            return enabledKeys.isEmpty
        }

        return Array(visible.prefix(limit))
    }

    /// Total listens in local database
    func countListens() async throws -> Int {
        try await db.asyncRead { db in
            try Listen.fetchCount(db)
        }
    }

    /// Get pending listens for a service
    func getPending(service: String) async throws -> [Listen] {
        try await db.asyncRead { db in
            try Listen
                .filter(sql: "json_extract(services, '$.\"\(service)\".status') = 'pending'")
                .order(Listen.Columns.listenedAt.desc)
                .fetchAll(db)
        }
    }

    /// Get delete-pending listens for a service
    func getDeletePending(service: String, maxRetryCount: Int, retryAfterSeconds: TimeInterval) async throws -> [Listen] {
        let cutoff = Date(timeIntervalSinceNow: -retryAfterSeconds).toISO8601()
        let statusPath = "$.\"\(service)\".status"
        let retryPath = "$.\"\(service)\".retryCount"
        let lastAttemptPath = "$.\"\(service)\".lastAttemptAt"

        return try await db.asyncRead { db in
            try Listen
                .filter(sql: "json_extract(services, '\(statusPath)') = 'deletePending'")
                .filter(sql: "COALESCE(json_extract(services, '\(retryPath)'), 0) < ?", arguments: [maxRetryCount])
                .filter(sql: "json_extract(services, '\(lastAttemptPath)') IS NULL OR json_extract(services, '\(lastAttemptPath)') <= ?", arguments: [cutoff])
                .order(Listen.Columns.listenedAt.desc)
                .fetchAll(db)
        }
    }

    /// Get failed listens that are eligible for retry
    func getRetryableFailed(service: String, maxRetryCount: Int, retryAfterSeconds: TimeInterval) async throws -> [Listen] {
        let cutoff = Date(timeIntervalSinceNow: -retryAfterSeconds).toISO8601()
        let statusPath = "$.\"\(service)\".status"
        let retryPath = "$.\"\(service)\".retryCount"
        let lastAttemptPath = "$.\"\(service)\".lastAttemptAt"

        return try await db.asyncRead { db in
            try Listen
                .filter(sql: "json_extract(services, '\(statusPath)') = 'failed'")
                .filter(sql: "COALESCE(json_extract(services, '\(retryPath)'), 0) < ?", arguments: [maxRetryCount])
                .filter(sql: "json_extract(services, '\(lastAttemptPath)') IS NULL OR json_extract(services, '\(lastAttemptPath)') <= ?", arguments: [cutoff])
                .order(Listen.Columns.listenedAt.desc)
                .fetchAll(db)
        }
    }

    /// Find by canonical key
    func findByCanonicalKey(_ key: String) async throws -> Listen? {
        let parts = key.components(separatedBy: "|")
        guard parts.count == 2 else { return nil }
        let artist = parts[0]
        let track = parts[1]

        return try await db.asyncRead { db in
            try Listen
                .filter(Listen.Columns.artist.collating(.nocase) == artist)
                .filter(Listen.Columns.track.collating(.nocase) == track)
                .fetchOne(db)
        }
    }

    /// Find by timestamp
    func findByTimestamp(artist: String, track: String, timestamp: Int) async throws -> Listen? {
        try await db.asyncRead { db in
            try Listen
                .filter(Listen.Columns.artist.collating(.nocase) == artist)
                .filter(Listen.Columns.track.collating(.nocase) == track)
                .filter(abs(Listen.Columns.listenedAt - timestamp) <= 60)
                .fetchOne(db)
        }
    }

    /// Refresh history from SQLite
    func refreshHistory(limit: Int) async throws {
        let enabled = Defaults.shared.enabledServices.map { $0.service }
        let listens = try await getRecentVisible(limit: limit, enabledServices: enabled)
        await MainActor.run {
            self.setHistory(listens)
        }
    }

    /// Prune old listens
    func pruneOld(keepDays: Int) async throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -keepDays, to: Date())!
        let cutoffTimestamp = Int(cutoffDate.timeIntervalSince1970)

        _ = try await db.asyncWrite { db in
            try Listen
                .filter(Listen.Columns.listenedAt < cutoffTimestamp)
                .deleteAll(db)
        }
        Logger.info("Pruned listens older than \(keepDays) days", log: Logger.sync)
    }
}
