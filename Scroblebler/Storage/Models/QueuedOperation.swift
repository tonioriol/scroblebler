import GRDB
import Foundation

struct QueuedOperation: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var type: String
    var payload: String
    var attempts: Int
    var lastError: String?
    var lastAttempt: String?   // ISO 8601 UTC
    var createdAt: String      // ISO 8601 UTC
    var updatedAt: String      // ISO 8601 UTC
    
    enum Columns: String, ColumnExpression {
        case id, type, payload, attempts, lastError, lastAttempt
        case createdAt, updatedAt
    }
}
