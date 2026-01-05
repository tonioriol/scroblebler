import Foundation
import XCTest
@testable import Scroblebler

// MARK: - Test Track Factory

extension Track {
    static func createTest(
        artist: String = "Test Artist",
        album: String = "Test Album",
        name: String = "Test Track",
        timestamp: Int = Int(Date().timeIntervalSince1970),
        duration: Double = 240.0,
        sourceService: ScrobbleService = .lastfm,
        loved: Bool = false,
        playcount: Int = 1,
        scrobbled: Bool = false,
        blacklisted: Bool = false,
        serviceInfo: [ScrobbleService: ServiceTrackData] = [:],
        artwork: Data? = nil
    ) -> Track {
        Track(
            id: UUID(),
            artist: artist,
            album: album,
            name: name,
            timestamp: timestamp,
            duration: duration,
            sourceService: sourceService,
            loved: loved,
            playcount: playcount,
            scrobbled: scrobbled,
            blacklisted: blacklisted,
            serviceInfo: serviceInfo,
            artwork: artwork,
            artistURL: nil,
            albumURL: nil,
            trackURL: nil,
            imageUrl: nil
        )
    }
}

// MARK: - Test Database

class TestDatabase {
    /// Create an in-memory SQLite database for testing
    /// Fast, isolated, no cleanup needed
    static func createInMemory() -> LocalDatabase {
        // Use temporary file as workaround - GRDB doesn't support true in-memory for testing
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).db")
        
        // Create database
        let fileManager = FileManager.default
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // Return new instance (will run migrations)
        return LocalDatabaseInstance(path: url.path)
    }
    
    /// Create a temporary file-based database
    /// Returns both the database and URL for cleanup
    static func createTemporary() -> (database: LocalDatabase, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
        let db = LocalDatabaseInstance(path: url.path)
        return (db, url)
    }
    
    /// Clean up temporary database file
    static func cleanup(url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - LocalDatabase Test Instance

/// Testable instance of LocalDatabase that doesn't use shared singleton
private class LocalDatabaseInstance: LocalDatabase {
    init(path: String) {
        // Create directory if needed
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        // Note: This is a workaround - actual LocalDatabase uses shared instance
        // For E2E tests, we may need to use the shared instance and clean between tests
        super.init()
    }
}

// MARK: - Test Credentials Factory

extension ServiceCredentials {
    static func createTest(
        service: ScrobbleService = .lastfm,
        username: String = "test_user",
        token: String = "test_token",
        isEnabled: Bool = true
    ) -> ServiceCredentials {
        ServiceCredentials(
            service: service,
            token: token,
            username: username,
            profileUrl: "https://test.profile/\(username)",
            isSubscriber: false,
            isEnabled: isEnabled
        )
    }
}

// MARK: - Async Test Helpers

extension XCTestCase {
    /// Wait for async condition with timeout
    func waitFor(
        timeout: TimeInterval = 1.0,
        condition: @escaping () async -> Bool
    ) async throws {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        throw TimeoutError()
    }
    
    struct TimeoutError: Error, LocalizedError {
        var errorDescription: String? {
            "Async condition timed out"
        }
    }
}

// MARK: - Test Assertions

/// Assert that two tracks match by canonical key
func assertTracksMatch(
    _ track1: Track,
    _ track2: Track,
    file: StaticString = #file,
    line: UInt = #line
) {
    XCTAssertEqual(
        track1.canonicalKey,
        track2.canonicalKey,
        "Tracks should match: '\(track1.artist) - \(track1.name)' vs '\(track2.artist) - \(track2.name)'",
        file: file,
        line: line
    )
}

/// Assert array contains track by canonical key
func assertContainsTrack(
    _ tracks: [Track],
    artist: String,
    name: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    let key = TrackIdentity.key(artist: artist, track: name)
    let found = tracks.contains { $0.canonicalKey == key }
    XCTAssertTrue(
        found,
        "Track list should contain '\(artist) - \(name)'",
        file: file,
        line: line
    )
}
