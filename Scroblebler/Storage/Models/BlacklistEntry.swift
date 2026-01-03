import GRDB
import Foundation

struct BlacklistEntry: Codable, FetchableRecord, PersistableRecord {
    var id: Int?
    var artist: String
    var track: String
    var createdAt: String  // ISO 8601 UTC
    var updatedAt: String  // ISO 8601 UTC
    
    enum Columns: String, ColumnExpression {
        case id, artist, track, createdAt, updatedAt
    }
}
