import GRDB
import Foundation

struct QueuedOperation: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "operations"
    
    var id: String
    var type: String
    var payload: String
    var attempts: Int
    var lastError: String?
    var lastAttempt: String?   // ISO 8601 UTC
    var createdAt: String      // ISO 8601 UTC
    var updatedAt: String      // ISO 8601 UTC
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case payload
        case attempts
        case lastError = "last_error"
        case lastAttempt = "last_attempt"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let type = Column(CodingKeys.type)
        static let payload = Column(CodingKeys.payload)
        static let attempts = Column(CodingKeys.attempts)
        static let lastError = Column(CodingKeys.lastError)
        static let lastAttempt = Column(CodingKeys.lastAttempt)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}
