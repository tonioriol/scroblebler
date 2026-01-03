import GRDB
import Foundation

struct ListenBrainzCacheEntry: Codable, FetchableRecord, PersistableRecord {
    var id: Int?
    var username: String
    var artist: String
    var track: String
    var playcount: Int
    var createdAt: String  // ISO 8601 UTC
    var updatedAt: String  // ISO 8601 UTC
    
    enum Columns: String, ColumnExpression {
        case id, username, artist, track, playcount
        case createdAt, updatedAt
    }
}
