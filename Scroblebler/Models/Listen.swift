import Foundation

/// Single unified listen model for all contexts (history, sync state)
struct Listen: Identifiable, Codable, Equatable {
    // MARK: - Identity

    var id: Int64?  // nil = new, auto-assigned on insert

    /// Canonical key for matching (artist|track lowercase)
    var canonicalKey: String {
        ListenIdentity.key(artist: artist, track: track)
    }

    /// Stable, unique identifier for UI lists.
    ///
    /// `id` can be nil for non-persisted listens; for history rendering we need a deterministic key
    /// to avoid SwiftUI diffing glitches (missing rows / large blank gaps) when the backing array
    /// is refreshed.
    var historyIdentity: String {
        "\(listenedAt)|\(canonicalKey)"
    }

    // MARK: - Core Metadata

    let track: String
    let artist: String
    let album: String
    let year: Int?
    let duration: Double
    let listenedAt: Int  // Unix timestamp - when the listen occurred

    // MARK: - Per-Service Sync State (JSON)
    var services: [String: ServiceSyncState]

    // MARK: - User State (per-listen)
    var loved: Bool  // Love state for THIS specific listen
    // NOTE: playcount is NOT stored per-listen - it's computed via COUNT query

    // MARK: - Media & Source
    var releaseMbid: String?   // MusicBrainz release ID (for Cover Art Archive)
    var sourceBundle: String?  // Bundle ID of app that played the track
    // NOTE: Images are loaded lazily from Cover Art Archive using releaseMbid
    // We don't store service-specific image URLs - CAA is service-agnostic

    // MARK: - Internal Timestamps
    let createdAt: String  // ISO 8601 - when row was inserted (for debugging)
    var updatedAt: String  // ISO 8601 - when row was last modified (for sync conflict resolution)
    // Note: listenedAt is the actual scrobble timestamp sent to services

    // MARK: - Computed

    var syncedServices: Set<String> {
        Set(services.filter { $0.value.status == .synced }.keys)
    }

    var pendingServices: Set<String> {
        Set(services.filter { $0.value.status == .pending }.keys)
    }

    var deletePendingServices: Set<String> {
        Set(services.filter { $0.value.status == .deletePending }.keys)
    }

    // MARK: - Equatable

    static func == (lhs: Listen, rhs: Listen) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Codable Keys

    enum CodingKeys: String, CodingKey {
        case id
        case track
        case artist
        case album
        case year
        case duration
        case listenedAt
        case services
        case loved
        case releaseMbid
        case sourceBundle
        case createdAt
        case updatedAt
    }

    // MARK: - Factory Methods

    /// Create from media player
    static func fromMediaPlayer(
        artist: String,
        album: String,
        track: String,
        duration: Double,
        listenedAt: Int,
        sourceBundle: String?
    ) -> Listen {
        return Listen(
            id: nil,
            track: track,
            artist: artist,
            album: album,
            year: nil,
            duration: duration,
            listenedAt: listenedAt,
            services: [:],
            loved: false,
            releaseMbid: nil,
            sourceBundle: sourceBundle,
            createdAt: Date.nowISO8601(),
            updatedAt: Date.nowISO8601()
        )
    }

    /// Create from API response
    static func fromAPI(
        artist: String,
        album: String,
        track: String,
        year: Int?,
        duration: Double,
        listenedAt: Int,
        loved: Bool,
        releaseMbid: String?,
        sourceBundle: String?,
        services: [String: ServiceSyncState]
    ) -> Listen {
        Listen(
            id: nil,
            track: track,
            artist: artist,
            album: album,
            year: year,
            duration: duration,
            listenedAt: listenedAt,
            services: services,
            loved: loved,
            releaseMbid: releaseMbid,
            sourceBundle: sourceBundle,
            createdAt: Date.nowISO8601(),
            updatedAt: Date.nowISO8601()
        )
    }
}

// MARK: - ServiceSyncState

struct ServiceSyncState: Codable, Equatable {
    enum Status: String, Codable {
        case pending   // Waiting to be sent
        case synced    // Successfully sent to service
        case failed    // Max retries reached
        case deletePending // Delete requested, retrying
        case deleted   // User deleted from this service
    }

    var status: Status
    var timestamp: Int?        // For Last.fm/Libre.fm deletion
    var recordingMsid: String? // For ListenBrainz deletion
    var artistMbid: String?    // For ListenBrainz URLs
    var releaseMbid: String?   // For ListenBrainz URLs
    var error: String?
    var retryCount: Int
    var lastAttemptAt: String? // ISO 8601

    init(status: Status, timestamp: Int? = nil, recordingMsid: String? = nil, artistMbid: String? = nil, releaseMbid: String? = nil, error: String? = nil, retryCount: Int = 0, lastAttemptAt: String? = nil) {
        self.status = status
        self.timestamp = timestamp
        self.recordingMsid = recordingMsid
        self.artistMbid = artistMbid
        self.releaseMbid = releaseMbid
        self.error = error
        self.retryCount = retryCount
        self.lastAttemptAt = lastAttemptAt
    }
}
