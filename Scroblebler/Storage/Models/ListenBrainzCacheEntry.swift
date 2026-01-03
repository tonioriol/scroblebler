import GRDB
import Foundation

struct ListenBrainzCacheEntry: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "listenbrainz_cache"
    
    var id: Int?
    var username: String
    var artist: String
    var track: String
    var playcount: Int
    var createdAt: String  // ISO 8601 UTC
    var updatedAt: String  // ISO 8601 UTC
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case artist
        case track
        case playcount
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let username = Column(CodingKeys.username)
        static let artist = Column(CodingKeys.artist)
        static let track = Column(CodingKeys.track)
        static let playcount = Column(CodingKeys.playcount)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
