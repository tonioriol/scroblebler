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

    private let db = LocalDatabase.shared
    private init() {}

    // MARK: - Current Listen Management

    /// Set current listen (from media player)
    func setCurrentListen(_ listen: Listen) {
        currentListen = listen
        Logger.info("Set current listen: \(listen.track) by \(listen.artist)", log: Logger.playback)
    }

    /// Update current listen with enriched data
    func updateCurrentListen(_ listen: Listen) {
        currentListen = listen
        Logger.debug("Updated current listen: \(listen.track) by \(listen.artist)", log: Logger.ui)
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
        history.append(contentsOf: newListens)
        Logger.info("Appended \(newListens.count) listens to history", log: Logger.sync)
    }

    /// Clear all history
    func clearHistory() {
        history.removeAll()
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
            history[index] = updated
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
            return insertedListen
        }
        Logger.info("Inserted listen: \(inserted.track) by \(inserted.artist)", log: Logger.sync)
        return inserted
    }

    /// Update existing listen
    func update(_ listen: Listen) async throws {
        try await db.asyncWrite { db in
            try listen.update(db)
        }
        Logger.info("Updated listen: \(listen.track) by \(listen.artist)", log: Logger.sync)
    }

    /// Delete listen by ID
    func delete(id: Int64) async throws {
        _ = try await db.asyncWrite { db in
            try Listen.deleteOne(db, key: id)
        }
        Logger.info("Deleted listen with id: \(id)", log: Logger.sync)
    }

    // MARK: - Service State Management

    /// Update service state for a listen
    func updateServiceState(listenId: Int64, service: String, state: ServiceSyncState) async throws {
        try await db.asyncWrite { db in
            if let listen = try Listen.fetchOne(db, key: listenId) {
                var updatedListen = listen
                updatedListen.services[service] = state
                updatedListen.updatedAt = Date.nowISO8601()
                try updatedListen.update(db)
            }
        }
        Logger.info("Updated service state for listen \(listenId) service \(service)", log: Logger.sync)
    }

    /// Mark service as synced
    func markSynced(listenId: Int64, service: String, timestamp: Int?, recordingMsid: String?) async throws {
        let state = ServiceSyncState(status: .synced, timestamp: timestamp, recordingMsid: recordingMsid)
        try await updateServiceState(listenId: listenId, service: service, state: state)
    }

    /// Mark service as failed
    func markFailed(listenId: Int64, service: String, error: String) async throws {
        let state = ServiceSyncState(status: .failed, error: error, retryCount: 0)
        try await updateServiceState(listenId: listenId, service: service, state: state)
    }

    /// Mark service as deleted
    func markDeleted(listenId: Int64, service: String) async throws {
        let state = ServiceSyncState(status: .deleted)
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

    /// Get pending listens for a service
    func getPending(service: String) async throws -> [Listen] {
        try await db.asyncRead { db in
            try Listen
                .filter(sql: "json_extract(services, '$.\"\(service)\".status') = 'pending'")
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
        let listens = try await getRecent(limit: limit)
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
