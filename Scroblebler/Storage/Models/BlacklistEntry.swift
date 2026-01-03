import GRDB
import Foundation

struct BlacklistEntry: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "blacklist"
    
    var id: Int?
    var artist: String
    var track: String
    var createdAt: String  // ISO 8601 UTC
    var updatedAt: String  // ISO 8601 UTC
    
    enum CodingKeys: String, CodingKey {
        case id
        case artist
        case track
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let artist = Column(CodingKeys.artist)
        static let track = Column(CodingKeys.track)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
