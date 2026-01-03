import GRDB
import Foundation

struct ListenBrainzCacheMeta: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "listenbrainz_cache_meta"
    
    var id: Int?
    var username: String
    var continueFromTs: Int?       // Unix timestamp (API format)
    var completedAt: String?       // ISO 8601 UTC
    var totalTracks: Int?
    var createdAt: String          // ISO 8601 UTC
    var updatedAt: String          // ISO 8601 UTC
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case continueFromTs = "continue_from_ts"
        case completedAt = "completed_at"
        case totalTracks = "total_tracks"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let username = Column(CodingKeys.username)
        static let continueFromTs = Column(CodingKeys.continueFromTs)
        static let completedAt = Column(CodingKeys.completedAt)
        static let totalTracks = Column(CodingKeys.totalTracks)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
