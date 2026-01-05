import XCTest
@testable import Scroblebler

/// E2E tests for OfflineQueue with real database persistence
final class OfflineQueueE2ETests: XCTestCase {
    
    override func setUp() async throws {
        // Clear queue before each test
        try? await OfflineQueue.shared.clear()
    }
    
    override func tearDown() async throws {
        // Clean up after each test
        try? await OfflineQueue.shared.clear()
    }
    
    // MARK: - Enqueue and Dequeue Tests
    
    func testEnqueueAndDequeue() async throws {
        // Setup
        let track = Track.createTest(
            artist: "The Beatles",
            name: "Let It Be",
            duration: 243
        )
        
        let operation = Operation.scrobble(
            track: track,
            services: [.lastfm]
        )
        
        // Enqueue
        try await OfflineQueue.shared.enqueue(operation)
        
        // Verify queued
        let count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 1, "Operation should be queued")
        
        // Dequeue
        let operations = await OfflineQueue.shared.dequeue()
        XCTAssertEqual(operations.count, 1, "Should dequeue one operation")
        
        if case .scrobble(_, let dequeuedTrack, let services) = operations.first {
            XCTAssertEqual(dequeuedTrack.artist, "The Beatles")
            XCTAssertEqual(dequeuedTrack.name, "Let It Be")
            XCTAssertEqual(services, [.lastfm])
        } else {
            XCTFail("Expected scrobble operation")
        }
    }
    
    func testMultipleOperations() async throws {
        // Setup multiple operations
        let track1 = Track.createTest(artist: "Artist 1", name: "Track 1")
        let track2 = Track.createTest(artist: "Artist 2", name: "Track 2")
        
        let op1 = Operation.scrobble(track: track1, services: [.lastfm])
        let op2 = Operation.love(artist: "Artist 3", track: "Track 3", loved: true, services: [.listenbrainz])
        let op3 = Operation.scrobble(track: track2, services: [.librefm])
        
        // Enqueue all
        try await OfflineQueue.shared.enqueue(op1)
        try await OfflineQueue.shared.enqueue(op2)
        try await OfflineQueue.shared.enqueue(op3)
        
        // Verify count
        let count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 3, "Should have 3 operations queued")
        
        // Dequeue all
        let operations = await OfflineQueue.shared.dequeue()
        XCTAssertEqual(operations.count, 3, "Should dequeue all operations")
    }
    
    // MARK: - Retry Logic Tests
    
    func testIncrementAttemptsAndRetry() async throws {
        // Setup
        let track = Track.createTest(artist: "Test Artist", name: "Test Track")
        let operation = Operation.scrobble(track: track, services: [.lastfm])
        let storedId = operation.id // Capture ID at enqueue time
        
        // Enqueue
        try await OfflineQueue.shared.enqueue(operation)
        
        // Simulate 3 failed attempts using stored ID
        for attempt in 1...3 {
            try await OfflineQueue.shared.incrementAttempts(storedId, error: "Test error \(attempt)")
            
            // Verify still in queue (< 5 attempts)
            let count = await OfflineQueue.shared.count()
            XCTAssertEqual(count, 1, "Operation should still be in queue after \(attempt) attempts")
        }
    }
    
    func testFailedOperationExcluded() async throws {
        // Setup
        let track = Track.createTest(artist: "Failed Artist", name: "Failed Track")
        let operation = Operation.scrobble(track: track, services: [.lastfm])
        let storedId = operation.id // Capture ID at enqueue time
        
        // Enqueue
        try await OfflineQueue.shared.enqueue(operation)
        
        // Simulate 5 failed attempts (max) using the stored ID
        for _ in 1...5 {
            try await OfflineQueue.shared.incrementAttempts(storedId, error: "Permanent failure")
        }
        
        // Verify excluded from pending queue
        let pendingCount = await OfflineQueue.shared.count()
        XCTAssertEqual(pendingCount, 0, "Failed operation should not appear in pending queue")
        
        // Verify in failed queue
        let failedCount = await OfflineQueue.shared.failedCount()
        XCTAssertEqual(failedCount, 1, "Should have one failed operation")
    }
    
    // MARK: - Remove Tests
    
    func testRemoveOperation() async throws {
        // Setup
        let track = Track.createTest(artist: "Remove Test", name: "Remove Track")
        let operation = Operation.scrobble(track: track, services: [.lastfm])
        let storedId = operation.id // Capture ID at enqueue time
        
        // Enqueue
        try await OfflineQueue.shared.enqueue(operation)
        
        // Verify queued
        var count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 1)
        
        // Remove using stored ID
        try await OfflineQueue.shared.remove(storedId)
        
        // Verify removed
        count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 0, "Operation should be removed")
    }
    
    // MARK: - Clear Tests
    
    func testClearAllOperations() async throws {
        // Setup multiple operations
        for i in 1...5 {
            let track = Track.createTest(artist: "Artist \(i)", name: "Track \(i)")
            let operation = Operation.scrobble(track: track, services: [.lastfm])
            try await OfflineQueue.shared.enqueue(operation)
        }
        
        // Verify queued
        var count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 5)
        
        // Clear
        try await OfflineQueue.shared.clear()
        
        // Verify cleared
        count = await OfflineQueue.shared.count()
        XCTAssertEqual(count, 0, "All operations should be cleared")
    }
    
    func testClearFailedOperations() async throws {
        // Setup: Add one pending and one failed operation
        let track1 = Track.createTest(artist: "Pending", name: "Track")
        let track2 = Track.createTest(artist: "Failed", name: "Track")
        
        let op1 = Operation.scrobble(track: track1, services: [.lastfm])
        let op2 = Operation.scrobble(track: track2, services: [.lastfm])
        let op2Id = op2.id // Capture ID before enqueue
        
        try await OfflineQueue.shared.enqueue(op1)
        try await OfflineQueue.shared.enqueue(op2)
        
        // Make second operation fail using stored ID
        for _ in 1...5 {
            try await OfflineQueue.shared.incrementAttempts(op2Id, error: "Failed")
        }
        
        // Clear failed only
        try await OfflineQueue.shared.clearFailed()
        
        // Verify: pending should remain, failed should be cleared
        let pendingCount = await OfflineQueue.shared.count()
        let failedCount = await OfflineQueue.shared.failedCount()
        
        XCTAssertEqual(pendingCount, 1, "Pending operation should remain")
        XCTAssertEqual(failedCount, 0, "Failed operations should be cleared")
    }
    
    // MARK: - Operation Type Tests
    
    func testScrobbleOperation() async throws {
        let track = Track.createTest(artist: "Scrobble Test", name: "Track")
        let operation = Operation.scrobble(track: track, services: [.lastfm, .listenbrainz])
        
        try await OfflineQueue.shared.enqueue(operation)
        
        let operations = await OfflineQueue.shared.dequeue()
        XCTAssertEqual(operations.count, 1)
        
        if case .scrobble(_, let t, let services) = operations.first {
            XCTAssertEqual(t.artist, "Scrobble Test")
            XCTAssertEqual(services.count, 2)
        } else {
            XCTFail("Expected scrobble operation")
        }
    }
    
    func testLoveOperation() async throws {
        let operation = Operation.love(
            artist: "Love Test",
            track: "Love Track",
            loved: true,
            services: [.lastfm]
        )
        
        try await OfflineQueue.shared.enqueue(operation)
        
        let operations = await OfflineQueue.shared.dequeue()
        XCTAssertEqual(operations.count, 1)
        
        if case .love(_, let artist, let track, let loved, let services) = operations.first {
            XCTAssertEqual(artist, "Love Test")
            XCTAssertEqual(track, "Love Track")
            XCTAssertTrue(loved)
            XCTAssertEqual(services, [.lastfm])
        } else {
            XCTFail("Expected love operation")
        }
    }
    
    func testDeleteOperation() async throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let operation = Operation.delete(
            artist: "Delete Test",
            track: "Delete Track",
            timestamp: timestamp,
            services: [.listenbrainz]
        )
        
        try await OfflineQueue.shared.enqueue(operation)
        
        let operations = await OfflineQueue.shared.dequeue()
        XCTAssertEqual(operations.count, 1)
        
        if case .delete(_, let artist, let track, let ts, let services) = operations.first {
            XCTAssertEqual(artist, "Delete Test")
            XCTAssertEqual(track, "Delete Track")
            XCTAssertEqual(ts, timestamp)
            XCTAssertEqual(services, [.listenbrainz])
        } else {
            XCTFail("Expected delete operation")
        }
    }
}
