import GRDB
import Foundation

extension Notification.Name {
    static let blacklistChanged = Notification.Name("blacklistChanged")
}

/// Manages persistent blacklist for tracks that should never be scrobbled
class LocalBlacklist {
    static let shared = LocalBlacklist()
    private let db = LocalDatabase.shared
    
    private init() {}
    
    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .blacklistChanged, object: nil)
        }
    }
    
    /// Normalize string for case-insensitive comparison
    private func normalize(_ string: String) -> String {
        string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Add a track to the blacklist
    func add(artist: String, track: String) async throws {
        let normalizedArtist = normalize(artist)
        let normalizedTrack = normalize(track)
        let now = Date.nowISO8601()
        
        _ = try await db.asyncWrite { db in
            let entry = BlacklistEntry(
                id: nil,
                artist: normalizedArtist,
                track: normalizedTrack,
                createdAt: now,
                updatedAt: now
            )
            try entry.insert(db)
        }
        Logger.info("Blacklisted: \(artist) - \(track)", log: Logger.scrobbling)
        notifyChange()
    }
    
    /// Remove a track from the blacklist
    func remove(artist: String, track: String) async throws {
        let normalizedArtist = normalize(artist)
        let normalizedTrack = normalize(track)
        
        _ = try await db.asyncWrite { db in
            try BlacklistEntry
                .filter(BlacklistEntry.Columns.artist == normalizedArtist)
                .filter(BlacklistEntry.Columns.track == normalizedTrack)
                .deleteAll(db)
        }
        Logger.info("Removed from blacklist: \(artist) - \(track)", log: Logger.scrobbling)
        notifyChange()
    }
    
    /// Check if a track is blacklisted
    func contains(artist: String, track: String) async -> Bool {
        let normalizedArtist = normalize(artist)
        let normalizedTrack = normalize(track)
        
        return (try? await db.asyncRead { db in
            try BlacklistEntry
                .filter(BlacklistEntry.Columns.artist == normalizedArtist)
                .filter(BlacklistEntry.Columns.track == normalizedTrack)
                .fetchCount(db) > 0
        }) ?? false
    }
    
    /// Get all blacklisted tracks, ordered by most recently added
    func getAll() async -> [BlacklistEntry] {
        (try? await db.asyncRead { db in
            try BlacklistEntry
                .order(BlacklistEntry.Columns.createdAt.desc)
                .fetchAll(db)
        }) ?? []
    }
    
    /// Get count of blacklisted tracks
    func count() async -> Int {
        (try? await db.asyncRead { db in
            try BlacklistEntry.fetchCount(db)
        }) ?? 0
    }
    
    /// Clear all blacklist entries
    func clear() async throws {
        _ = try await db.asyncWrite { db in
            try BlacklistEntry.deleteAll(db)
        }
        Logger.info("Cleared all blacklist entries", log: Logger.scrobbling)
    }
}
