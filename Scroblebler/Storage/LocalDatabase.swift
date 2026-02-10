import GRDB
import Foundation

class LocalDatabase {
    static let shared = LocalDatabase()
    private let dbQueue: DatabaseQueue

    init() {
        let path = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scroblebler")
            .appendingPathComponent("scroblebler.db")
            .path

        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )

        dbQueue = try! DatabaseQueue(path: path)
        try! migrator.migrate(dbQueue)
    }

    var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_listenbrainz_cache") { db in
            // Playcount data table
            try db.create(table: "listenbrainz_cache") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("username", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("track", .text).notNull()
                t.column("playcount", .integer).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_lbc_unique ON listenbrainz_cache(username, artist, track)
            """)
            try db.create(index: "idx_lbc_username", on: "listenbrainz_cache", columns: ["username"])
            try db.create(index: "idx_lbc_updated", on: "listenbrainz_cache", columns: ["updated_at"])

            // Metadata table
            try db.create(table: "listenbrainz_cache_meta") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("username", .text).notNull().unique()
                t.column("continue_from_ts", .integer)
                t.column("completed_at", .text)
                t.column("total_tracks", .integer)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }
        }

        migrator.registerMigration("v2_blacklist") { db in
            try db.create(table: "blacklist") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("artist", .text).notNull()
                t.column("track", .text).notNull()
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_blacklist_unique ON blacklist(artist, track)
            """)
            try db.create(index: "idx_blacklist_created", on: "blacklist", columns: ["created_at"])
        }

        migrator.registerMigration("v3_operations") { db in
            try db.create(table: "operations") { t in
                t.column("id", .text).primaryKey()
                t.column("type", .text).notNull()
                t.column("payload", .text).notNull()
                t.column("attempts", .integer).notNull().defaults(to: 0)
                t.column("last_error", .text)
                t.column("last_attempt", .text)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.execute(sql: """
                CREATE INDEX idx_operations_pending ON operations(attempts, created_at)
                WHERE attempts < 5
            """)
        }

        migrator.registerMigration("v4_listens") { db in
            // Listens table
            try db.create(table: "listens") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("track", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("album", .text).notNull().defaults(to: "")
                t.column("year", .integer)
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("listened_at", .integer).notNull()

                t.column("services", .text).notNull().defaults(to: "{}")  // JSON: per-service sync state

                t.column("loved", .integer).notNull().defaults(to: 0)
                // NOTE: playcount is NOT stored - computed via COUNT(*) query

                t.column("release_mbid", .text)          // For Cover Art Archive images
                t.column("image_url", .text)             // Service-provided artwork URL fallback (e.g. Last.fm)
                t.column("source_bundle", .text)         // App that played the track

                t.column("created_at", .text).notNull()   // When row was inserted
                t.column("updated_at", .text).notNull()    // When row was last modified
            }

            // Indexes
            try db.execute(sql: """
                CREATE INDEX idx_listens_listened_at ON listens(listened_at DESC)
            """)
            try db.execute(sql: """
                CREATE INDEX idx_listens_canonical ON listens(artist COLLATE NOCASE, track COLLATE NOCASE)
            """)
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_listens_unique ON listens(artist, track, listened_at)
            """)
        }

        migrator.registerMigration("v6_listens_image_url") { db in
            // Add service-provided artwork URL fallback for history.
            // Kept separate from v4 to avoid forcing a full DB reset.
            try db.alter(table: "listens") { t in
                t.add(column: "image_url", .text)
            }
        }

        migrator.registerMigration("v5_remove_listenbrainz_cache") { db in
            // Remove ListenBrainz cache tables (replaced by local listens)
            try db.drop(table: "listenbrainz_cache")
            try db.drop(table: "listenbrainz_cache_meta")
        }

        return migrator
    }

    // Public interface
    func read<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.read(block)
    }

    func write<T>(_ block: (Database) throws -> T) throws -> T {
        try dbQueue.write(block)
    }

    func asyncRead<T>(_ block: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await dbQueue.read(block)
    }

    func asyncWrite<T>(_ block: @escaping @Sendable (Database) throws -> T) async throws -> T {
        try await dbQueue.write(block)
    }
}

// Helper extension for ISO 8601 formatting
extension Date {
    func toISO8601() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }

    static func nowISO8601() -> String {
        Date().toISO8601()
    }
}
