import GRDB
import Foundation
import CommonCrypto

/// Manages offline operation queue for scrobbling when network is unavailable
class OfflineQueue {
    static let shared = OfflineQueue()
    private let db = LocalDatabase.shared
    
    private init() {}
    
    /// Add operation to queue
    func enqueue(_ operation: Operation) async throws {
        let payload = try JSONEncoder().encode(operation)
        let now = Date.nowISO8601()
        
        _ = try await db.asyncWrite { db in
            let queued = QueuedOperation(
                id: operation.id.uuidString,
                type: operation.type,
                payload: String(data: payload, encoding: .utf8)!,
                attempts: 0,
                lastError: nil,
                lastAttempt: nil,
                createdAt: now,
                updatedAt: now
            )
            try queued.insert(db)
        }
        
        Logger.info("Queued operation: \(operation.type)", log: Logger.sync)
    }
    
    /// Get all pending operations (attempts < 5)
    func dequeue() async -> [Operation] {
        let operations = (try? await db.asyncRead { db in
            try QueuedOperation
                .filter(QueuedOperation.Columns.attempts < 5)
                .order(QueuedOperation.Columns.createdAt)
                .fetchAll(db)
        }) ?? []
        
        return operations.compactMap { queued in
            guard let data = queued.payload.data(using: .utf8),
                  let operation = try? JSONDecoder().decode(Operation.self, from: data) else {
                Logger.error("Failed to decode operation: \(queued.id)", log: Logger.sync)
                return nil
            }
            return operation
        }
    }
    
    /// Remove operation from queue (after successful execution)
    func remove(_ operationId: UUID) async throws {
        _ = try await db.asyncWrite { db in
            try QueuedOperation
                .filter(QueuedOperation.Columns.id == operationId.uuidString)
                .deleteAll(db)
        }
        Logger.debug("Removed operation from queue: \(operationId)", log: Logger.sync)
    }
    
    /// Increment attempt counter and record error
    func incrementAttempts(_ operationId: UUID, error: String) async throws {
        let now = Date.nowISO8601()
        try await db.asyncWrite { db in
            if var operation = try QueuedOperation
                .filter(QueuedOperation.Columns.id == operationId.uuidString)
                .fetchOne(db) {
                operation.attempts += 1
                operation.lastAttempt = now
                operation.lastError = error
                operation.updatedAt = now
                try operation.update(db)
                
                if operation.attempts >= 5 {
                    Logger.error("Operation failed permanently after 5 attempts: \(operationId)", log: Logger.sync)
                } else {
                    Logger.debug("Operation attempt \(operation.attempts)/5 failed: \(operationId)", log: Logger.sync)
                }
            }
        }
    }
    
    /// Get count of pending operations
    func count() async -> Int {
        (try? await db.asyncRead { db in
            try QueuedOperation
                .filter(QueuedOperation.Columns.attempts < 5)
                .fetchCount(db)
        }) ?? 0
    }
    
    /// Get count of failed operations (attempts >= 5)
    func failedCount() async -> Int {
        (try? await db.asyncRead { db in
            try QueuedOperation
                .filter(QueuedOperation.Columns.attempts >= 5)
                .fetchCount(db)
        }) ?? 0
    }
    
    /// Clear all operations from queue
    func clear() async throws {
        _ = try await db.asyncWrite { db in
            try QueuedOperation.deleteAll(db)
        }
        Logger.info("Cleared operation queue", log: Logger.sync)
    }
    
    /// Clear only permanently failed operations
    func clearFailed() async throws {
        let count = try await db.asyncWrite { db in
            try QueuedOperation
                .filter(QueuedOperation.Columns.attempts >= 5)
                .deleteAll(db)
        }
        Logger.info("Cleared \(count) failed operations", log: Logger.sync)
    }
}

/// Represents an operation that can be queued for offline execution
enum Operation: Codable, Identifiable {
    case scrobble(track: Track, services: [ScrobbleService])
    case love(artist: String, track: String, loved: Bool, services: [ScrobbleService])
    case delete(artist: String, track: String, timestamp: Int?, services: [ScrobbleService])
    
    var id: UUID {
        // Generate unique ID - stored with operation
        UUID()
    }
    
    var type: String {
        switch self {
        case .scrobble: return "scrobble"
        case .love: return "love"
        case .delete: return "delete"
        }
    }
}
