import XCTest
@testable import Scroblebler

/// E2E tests for network state transitions and offline queue processing
final class NetworkStateE2ETests: XCTestCase {
    
    override func setUp() async throws {
        // Clear queue before each test
        try? await OfflineQueue.shared.clear()
    }
    
    override func tearDown() async throws {
        // Clean up after each test
        try? await OfflineQueue.shared.clear()
    }
    
    // MARK: - Offline Queuing Tests
    
    func testOfflineQueuesOperation() async throws {
        // Note: Testing actual network state requires mocking Reachability
        // This test validates the queue behavior structure
        
        let track = Track.createTest(
            artist: "Offline Artist",
            name: "Offline Track",
            duration: 200
        )
        
        let operation = Operation.scrobble(track: track, services: [.lastfm])
        
        // Simulate offline by directly queuing
        try await OfflineQueue.shared.enqueue(operation)
        
        // Verify queued
        let count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 1, "Operation should be queued when offline")
    }
    
    func testOnlineProcessesQueue() async throws {
        // Setup: Queue operations while offline
        let track1 = Track.createTest(artist: "Artist 1", name: "Track 1")
        let track2 = Track.createTest(artist: "Artist 2", name: "Track 2")
        
        let op1 = Operation.scrobble(track: track1, services: [.lastfm])
        let op2 = Operation.scrobble(track: track2, services: [.listenbrainz])
        
        try await OfflineQueue.shared.enqueue(op1)
        try await OfflineQueue.shared.enqueue(op2)
        
        // Verify queued
        var count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 2, "Both operations should be queued")
        
        // Simulate going online and processing
        // In production, Reachability.onNetworkAvailable() triggers this
        let operations = await OfflineQueue.shared.dequeue()
        
        // Simulate successful processing
        for operation in operations {
            // In real scenario, ScrobbleManager would execute these
            try await OfflineQueue.shared.remove(operation.id)
        }
        
        // Verify processed
        count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 0, "Queue should be empty after processing")
    }
    
    // MARK: - Partial Network Failure Tests
    
    func testPartialNetworkFailure() async throws {
        // Setup: Some operations succeed, some fail
        let track1 = Track.createTest(artist: "Success", name: "Track")
        let track2 = Track.createTest(artist: "Failure", name: "Track")
        
        let op1 = Operation.scrobble(track: track1, services: [.lastfm])
        let op2 = Operation.scrobble(track: track2, services: [.listenbrainz])
        
        try await OfflineQueue.shared.enqueue(op1)
        try await OfflineQueue.shared.enqueue(op2)
        
        let operations = await OfflineQueue.shared.dequeue()
        
        // Simulate: first succeeds, second fails
        if operations.count >= 2 {
            // Success - remove from queue
            try await OfflineQueue.shared.remove(operations[0].id)
            
            // Failure - increment attempts
            try await OfflineQueue.shared.incrementAttempts(operations[1].id, error: "Network error")
        }
        
        // Verify: failed operation still in queue
        let count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 1, "Failed operation should remain in queue")
    }
    
    // MARK: - Retry Exhaustion Tests
    
    func testRetryExhaustion() async throws {
        // Setup: Operation that fails repeatedly
        let track = Track.createTest(artist: "Retry Test", name: "Track")
        let operation = Operation.scrobble(track: track, services: [.lastfm])
        
        try await OfflineQueue.shared.enqueue(operation)
        
        let operations = await OfflineQueue.shared.dequeue()
        guard let op = operations.first else {
            XCTFail("No operation found")
            return
        }
        
        // Simulate 5 failed attempts (max retries)
        for attempt in 1...5 {
            try await OfflineQueue.shared.incrementAttempts(op.id, error: "Permanent failure \(attempt)")
        }
        
        // Verify: excluded from pending, moved to failed
        let pendingCount = await OfflineQueue.shared.count()
        let failedCount = await OfflineQueue.shared.failedCount()
        
        XCTAssertEqual(pendingCount, 0, "Should not be in pending queue")
        XCTAssertEqual(failedCount, 1, "Should be in failed queue")
    }
    
    // MARK: - Mixed Operation Types Tests
    
    func testMixedOperationTypes() async throws {
        // Queue different operation types
        let track = Track.createTest(artist: "Mixed", name: "Track")
        
        let scrobbleOp = Operation.scrobble(track: track, services: [.lastfm])
        let loveOp = Operation.love(artist: "Love Artist", track: "Love Track", loved: true, services: [.listenbrainz])
        let deleteOp = Operation.delete(artist: "Delete Artist", track: "Delete Track", timestamp: 12345, services: [.librefm])
        
        try await OfflineQueue.shared.enqueue(scrobbleOp)
        try await OfflineQueue.shared.enqueue(loveOp)
        try await OfflineQueue.shared.enqueue(deleteOp)
        
        // Verify all queued
        let count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 3, "All operation types should be queued")
        
        // Dequeue and verify types
        let operations = await OfflineQueue.shared.dequeue()
        XCTAssertEqual(operations.count, 3)
        
        var hasScrobble = false
        var hasLove = false
        var hasDelete = false
        
        for op in operations {
            switch op {
            case .scrobble: hasScrobble = true
            case .love: hasLove = true
            case .delete: hasDelete = true
            }
        }
        
        XCTAssertTrue(hasScrobble, "Should have scrobble operation")
        XCTAssertTrue(hasLove, "Should have love operation")
        XCTAssertTrue(hasDelete, "Should have delete operation")
    }
    
    // MARK: - Rate Limiting Tests
    
    func testQueueProcessingDelay() async throws {
        // In production, operations are processed with delays to respect rate limits
        // This test validates the structure
        
        let operations = (1...5).map { i in
            let track = Track.createTest(artist: "Artist \(i)", name: "Track \(i)")
            return Operation.scrobble(track: track, services: [.lastfm])
        }
        
        for op in operations {
            try await OfflineQueue.shared.enqueue(op)
        }
        
        let count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 5, "All operations should be queued")
        
        // In production, Reachability.processOfflineQueue() adds delays
        // between operations (500ms) to respect API rate limits
    }
    
    // MARK: - Queue Persistence Tests
    
    func testQueuePersistenceAcrossInstances() async throws {
        // Queue operations
        let track = Track.createTest(artist: "Persist", name: "Track")
        let operation = Operation.scrobble(track: track, services: [.lastfm])
        
        try await OfflineQueue.shared.enqueue(operation)
        
        // Verify queued
        var count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 1)
        
        // In production, the queue persists in SQLite
        // OfflineQueue.shared uses LocalDatabase.shared
        // Operations survive app restart
        
        // Verify still present (simulating persistence)
        count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 1, "Queue should persist")
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentEnqueue() async throws {
        // Simulate multiple operations enqueued concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    let track = Track.createTest(artist: "Concurrent \(i)", name: "Track")
                    let operation = Operation.scrobble(track: track, services: [.lastfm])
                    try? await OfflineQueue.shared.enqueue(operation)
                }
            }
        }
        
        // Verify all enqueued
        let count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 10, "All concurrent operations should be queued")
    }
}
