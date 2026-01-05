import XCTest
@testable import Scroblebler

/// E2E tests for LocalBlacklist with real database
final class BlacklistE2ETests: XCTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        // Clear ALL blacklist entries before each test
        await clearBlacklist()
    }
    
    override func tearDown() async throws {
        // Clean up after each test
        await clearBlacklist()
        try await super.tearDown()
    }
    
    // Helper to completely clear the blacklist
    private func clearBlacklist() async {
        try? await LocalBlacklist.shared.clear()
    }
    
    // MARK: - Add/Remove Tests
    
    func testAddToBlacklist() async throws {
        // Add entry
        try await LocalBlacklist.shared.add(artist: "Test Artist", track: "Test Track")
        
        // Verify added
        let contains = await LocalBlacklist.shared.contains(artist: "Test Artist", track: "Test Track")
        XCTAssertTrue(contains, "Track should be blacklisted")
        
        // Verify in list (stored normalized/lowercase)
        let entries = await LocalBlacklist.shared.getAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.artist, "test artist")
        XCTAssertEqual(entries.first?.track, "test track")
    }
    
    func testRemoveFromBlacklist() async throws {
        // Add entry
        try await LocalBlacklist.shared.add(artist: "Remove Test", track: "Remove Track")
        
        // Verify added
        var contains = await LocalBlacklist.shared.contains(artist: "Remove Test", track: "Remove Track")
        XCTAssertTrue(contains)
        
        // Remove
        try await LocalBlacklist.shared.remove(artist: "Remove Test", track: "Remove Track")
        
        // Verify removed
        contains = await LocalBlacklist.shared.contains(artist: "Remove Test", track: "Remove Track")
        XCTAssertFalse(contains, "Track should no longer be blacklisted")
    }
    
    // MARK: - Case Sensitivity Tests
    
    func testCaseInsensitiveMatching() async throws {
        // Add with mixed case
        try await LocalBlacklist.shared.add(artist: "Pink Floyd", track: "Comfortably Numb")
        
        // Check with different cases
        var contains = await LocalBlacklist.shared.contains(artist: "PINK FLOYD", track: "COMFORTABLY NUMB")
        XCTAssertTrue(contains, "Should match case-insensitively (uppercase)")
        
        contains = await LocalBlacklist.shared.contains(artist: "pink floyd", track: "comfortably numb")
        XCTAssertTrue(contains, "Should match case-insensitively (lowercase)")
        
        contains = await LocalBlacklist.shared.contains(artist: "PiNk FlOyD", track: "CoMfOrTaBlY nUmB")
        XCTAssertTrue(contains, "Should match case-insensitively (mixed)")
    }
    
    // MARK: - Scrobble Prevention Tests
    
    func testBlacklistPreventsScrobble() async throws {
        // Add to blacklist
        try await LocalBlacklist.shared.add(artist: "Blocked Artist", track: "Blocked Track")
        
        // Create track
        let track = Track.createTest(
            artist: "Blocked Artist",
            name: "Blocked Track"
        )
        
        // Attempt scrobble (this would be called by ScrobbleManager)
        let isBlacklisted = await LocalBlacklist.shared.contains(
            artist: track.artist,
            track: track.name
        )
        
        // Verify prevented
        XCTAssertTrue(isBlacklisted, "Should be blocked from scrobbling")
    }
    
    // MARK: - List Tests
    
    func testListBlacklist() async throws {
        // Add multiple entries
        try await LocalBlacklist.shared.add(artist: "Artist 1", track: "Track 1")
        try await LocalBlacklist.shared.add(artist: "Artist 2", track: "Track 2")
        try await LocalBlacklist.shared.add(artist: "Artist 3", track: "Track 3")
        
        // Get list
        let entries = await LocalBlacklist.shared.getAll()
        
        // Verify (stored normalized/lowercase)
        XCTAssertEqual(entries.count, 3, "Should have 3 blacklisted entries")
        
        let artists = Set(entries.map { $0.artist })
        XCTAssertTrue(artists.contains("artist 1"))
        XCTAssertTrue(artists.contains("artist 2"))
        XCTAssertTrue(artists.contains("artist 3"))
    }
    
    // MARK: - Duplicate Prevention Tests
    
    func testDuplicatePrevention() async throws {
        // Add same entry twice
        try await LocalBlacklist.shared.add(artist: "Duplicate", track: "Track")
        
        do {
            try await LocalBlacklist.shared.add(artist: "Duplicate", track: "Track")
            // May throw or silently ignore - both valid
        } catch {
            // Expected - duplicate constraint
        }
        
        // Verify only one entry (stored normalized/lowercase)
        let entries = await LocalBlacklist.shared.getAll()
        let duplicates = entries.filter { $0.artist == "duplicate" && $0.track == "track" }
        XCTAssertEqual(duplicates.count, 1, "Should have exactly one entry")
    }
    
    // MARK: - Empty State Tests
    
    func testEmptyBlacklist() async {
        let entries = await LocalBlacklist.shared.getAll()
        XCTAssertEqual(entries.count, 0, "Blacklist should be empty initially")
        
        let contains = await LocalBlacklist.shared.contains(artist: "Nobody", track: "Nothing")
        XCTAssertFalse(contains, "Should not contain non-existent entry")
    }
    
    // MARK: - Special Characters Tests
    
    func testSpecialCharacters() async throws {
        // Test with special characters in artist/track names
        let specialArtist = "AC/DC"
        let specialTrack = "T.N.T."
        
        try await LocalBlacklist.shared.add(artist: specialArtist, track: specialTrack)
        
        let contains = await LocalBlacklist.shared.contains(artist: specialArtist, track: specialTrack)
        XCTAssertTrue(contains, "Should handle special characters")
        
        // Clean up
        try await LocalBlacklist.shared.remove(artist: specialArtist, track: specialTrack)
    }
    
    // MARK: - Integration with Track Model Tests
    
    func testWithTrackModel() async throws {
        // Create track
        let track = Track.createTest(
            artist: "Integration Artist",
            name: "Integration Track"
        )
        
        // Add using track properties
        try await LocalBlacklist.shared.add(artist: track.artist, track: track.name)
        
        // Verify
        let contains = await LocalBlacklist.shared.contains(artist: track.artist, track: track.name)
        XCTAssertTrue(contains)
        
        // Blacklist status checked via LocalBlacklist.shared.contains()
        // Track model doesn't have a blacklisted property
    }
}
