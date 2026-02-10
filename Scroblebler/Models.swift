import Foundation
import GRDB

// MARK: - Helper Extensions for JSON Serialization

extension Dictionary where Key == String, Value == ServiceSyncState {
    func jsonString() -> String {
        let data = try! JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

// MARK: - Sync Models

enum SyncStatus: Codable {
    case unknown
    case synced           // Present in all enabled services
    case partial          // Not in all enabled services

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .synced: return "checkmark.circle.fill"
        case .partial: return "xmark.circle.fill"
        }
    }

    /// Calculate sync status based on which services have the track
    static func calculate(
        presentInServices: Set<ScrobbleService>,
        enabledServices: Set<ScrobbleService>
    ) -> SyncStatus {
        guard !enabledServices.isEmpty else { return .unknown }

        // A track can be present in *more* services than the user currently has enabled
        // (e.g. user disables Libre.fm later). In that case we still consider it "synced".
        return enabledServices.isSubset(of: presentInServices) ? .synced : .partial
    }
}

struct ServiceTrackData: Codable, Equatable {
    let timestamp: Int?     // Required for Last.fm/Libre.fm
    /// ListenBrainz recording MBID (used for ListenBrainz track URLs).
    ///
    /// Note: this is NOT the identifier needed for ListenBrainz deletion.
    var id: String?

    /// ListenBrainz recording MSID (required for ListenBrainz deletion).
    var recordingMsid: String?
    var artistMbid: String? // ListenBrainz artist MBID (for URLs)
    var releaseMbid: String? // ListenBrainz release MBID (for URLs)

    init(
        timestamp: Int?,
        id: String? = nil,
        recordingMsid: String? = nil,
        artistMbid: String? = nil,
        releaseMbid: String? = nil
    ) {
        self.timestamp = timestamp
        self.id = id
        self.recordingMsid = recordingMsid
        self.artistMbid = artistMbid
        self.releaseMbid = releaseMbid
    }

    // Factory methods make intent clear
    static func lastfm(timestamp: Int) -> ServiceTrackData {
        ServiceTrackData(timestamp: timestamp)
    }

    static func listenbrainz(recordingMsid: String, timestamp: Int) -> ServiceTrackData {
        ServiceTrackData(timestamp: timestamp, recordingMsid: recordingMsid)
    }

    static func listenbrainzWithMbids(recordingMbid: String, artistMbid: String?, releaseMbid: String?, timestamp: Int) -> ServiceTrackData {
        ServiceTrackData(timestamp: timestamp, id: recordingMbid, artistMbid: artistMbid, releaseMbid: releaseMbid)
    }
}

// MARK: - Listen Extensions for GRDB

extension Listen: FetchableRecord, MutablePersistableRecord {
    static var databaseTableName: String { "listens" }

    enum Columns {
        // NOTE: Column names must match the SQLite schema (snake_case)
        static let id = Column("id")
        static let track = Column("track")
        static let artist = Column("artist")
        static let album = Column("album")
        static let year = Column("year")
        static let duration = Column("duration")
        static let listenedAt = Column("listened_at")
        static let services = Column("services")
        static let loved = Column("loved")
        static let releaseMbid = Column("release_mbid")
        static let imageUrl = Column("image_url")
        static let sourceBundle = Column("source_bundle")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id
        container[Columns.track] = track
        container[Columns.artist] = artist
        container[Columns.album] = album
        container[Columns.year] = year
        container[Columns.duration] = duration
        container[Columns.listenedAt] = listenedAt
        container[Columns.services] = services.jsonString()
        container[Columns.loved] = loved
        container[Columns.releaseMbid] = releaseMbid
        container[Columns.imageUrl] = imageUrl
        container[Columns.sourceBundle] = sourceBundle
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }

    init(row: Row) {
        id = row[Columns.id]
        track = row[Columns.track]
        artist = row[Columns.artist]
        album = row[Columns.album]
        year = row[Columns.year]
        duration = row[Columns.duration]
        listenedAt = row[Columns.listenedAt]
        // Decode JSON services from TEXT column
        if let jsonString: String = row[Columns.services] {
            let data = jsonString.data(using: .utf8) ?? Data()
            services = (try? JSONDecoder().decode([String: ServiceSyncState].self, from: data)) ?? [:]
        } else {
            services = [:]
        }
        loved = row[Columns.loved]
        releaseMbid = row[Columns.releaseMbid]
        imageUrl = row[Columns.imageUrl]
        artwork = nil
        sourceBundle = row[Columns.sourceBundle]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
    }

    mutating func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
    }
}

struct ScrobbleIdentifier {
    let artist: String
    let track: String
    let timestamp: Int?
    let serviceId: String?
}

struct UserStats: Codable {
    let playcount: Int
    let artistCount: Int
    let trackCount: Int
    let albumCount: Int
    let lovedCount: Int
    let registered: String
    let country: String?
    let realname: String?
    let gender: String?
    let age: String?
    let playlistCount: Int?
}

struct TopArtist: Codable {
    let name: String
    let playcount: Int
    let imageUrl: String?
}

struct TopAlbum: Codable {
    let artist: String
    let name: String
    let playcount: Int
    let imageUrl: String?
}

struct TopTrack: Codable {
    let artist: String
    let name: String
    let playcount: Int
    let imageUrl: String?
}

// MARK: - Service Configuration

enum ScrobbleService: String, CaseIterable, Codable, Identifiable {
    case lastfm = "Last.fm"
    case librefm = "Libre.fm"
    case listenbrainz = "ListenBrainz"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

struct ServiceCredentials: Codable {
    let service: ScrobbleService
    var token: String
    var username: String
    var profileUrl: String?
    var isSubscriber: Bool
    var isEnabled: Bool
}

// MARK: - Player State

enum PlayerState {
    case unknown
    case stopped
    case playing
    case paused
    case seeking
}
