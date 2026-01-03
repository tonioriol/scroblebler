import GRDB
import Foundation

struct ListenBrainzCacheMeta: Codable, FetchableRecord, PersistableRecord {
    var id: Int?
    var username: String
    var continueFromTs: Int?       // Unix timestamp (API format)
    var completedAt: String?       // ISO 8601 UTC
    var totalTracks: Int?
    var createdAt: String          // ISO 8601 UTC
    var updatedAt: String          // ISO 8601 UTC
    
    enum Columns: String, ColumnExpression {
        case id, username, continueFromTs, completedAt, totalTracks
        case createdAt, updatedAt
    }
}
