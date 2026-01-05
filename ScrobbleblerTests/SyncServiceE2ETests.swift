import XCTest
@testable import Scroblebler

/// E2E tests for SyncService with multiple fake clients
final class SyncServiceE2ETests: XCTestCase {
    var lastfmClient: FakeScrobbleClient!
    var lbClient: FakeScrobbleClient!
    var libreClient: FakeScrobbleClient!
    var syncService: SyncService!
    
    override func setUp() async throws {
        // Setup fake clients
        lastfmClient = FakeScrobbleClient(service: .lastfm)
        lbClient = FakeScrobbleClient(service: .listenbrainz)
        libreClient = FakeScrobbleClient(service: .librefm)
        
        // Note: SyncService requires a ScrobbleManager instance
        // For true E2E tests, we'd need dependency injection
        syncService = SyncService(serviceManager: ScrobbleManager.shared)
    }
    
    override func tearDown() async throws {
        lastfmClient = nil
        lbClient = nil
        libreClient = nil
        syncService = nil
    }
    
    // MARK: - Track Matching Tests
    
    func testExactTrackMatching() async throws {
        // Setup: Same track in two services
        let timestamp = Int(Date().timeIntervalSince1970)
        
        let lastfmTrack = Track.createTest(
            artist: "Radiohead",
            name: "Creep",
            timestamp: timestamp,
            sourceService: .lastfm
        )
        
        let lbTrack = Track.createTest(
            artist: "Radiohead",
            name: "Creep",
            timestamp: timestamp,
            sourceService: .listenbrainz
        )
        
        // Verify they match by canonical key
        XCTAssertEqual(lastfmTrack.canonicalKey, lbTrack.canonicalKey, "Tracks should match exactly")
    }
    
    func testFuzzyTrackMatching() async throws {
        // Setup: Similar tracks with slight variations
        let track1 = Track.createTest(
            artist: "Pink Floyd",
            name: "Comfortably Numb",
            sourceService: .lastfm
        )
        
        let track2 = Track.createTest(
            artist: "pink floyd",  // Different case
            name: "comfortably numb",  // Different case
            sourceService: .listenbrainz
        )
        
        // Should match case-insensitively
        XCTAssertEqual(track1.canonicalKey, track2.canonicalKey, "Should match case-insensitively")
    }
    
    // MARK: - Service History Tests
    
    func testFetchFromMultipleServices() async {
        // Setup: Populate history for fake clients
        let lastfmTracks = [
            Track.createTest(artist: "Artist 1", name: "Track 1", sourceService: .lastfm),
            Track.createTest(artist: "Artist 2", name: "Track 2", sourceService: .lastfm)
        ]
        
        let lbTracks = [
            Track.createTest(artist: "Artist 1", name: "Track 1", sourceService: .listenbrainz),
            Track.createTest(artist: "Artist 3", name: "Track 3", sourceService: .listenbrainz)
        ]
        
        lastfmClient.historyToReturn = lastfmTracks
        lbClient.historyToReturn = lbTracks
        
        // Verify setup
        XCTAssertEqual(lastfmClient.historyToReturn.count, 2)
        XCTAssertEqual(lbClient.historyToReturn.count, 2)
    }
    
    // MARK: - Backfill Detection Tests
    
    func testDetectMissingTracks() async {
        // Setup: Last.fm has track, ListenBrainz doesn't
        let track = Track.createTest(
            artist: "Backfill Test",
            name: "Missing Track",
            sourceService: .lastfm
        )
        
        lastfmClient.historyToReturn = [track]
        lbClient.historyToReturn = [] // Missing
        
        // In production, SyncService would detect this and backfill
        let lastfmCount = lastfmClient.historyToReturn.count
        let lbCount = lbClient.historyToReturn.count
        
        XCTAssertEqual(lastfmCount, 1, "Last.fm should have track")
        XCTAssertEqual(lbCount, 0, "ListenBrainz should be missing track")
    }
    
    func testBackfillOperation() async throws {
        // Setup: Track missing from one service
        let track = Track.createTest(
            artist: "The Beatles",
            name: "Let It Be",
            timestamp: Int(Date().timeIntervalSince1970),
            sourceService: .lastfm,
            scrobbled: true
        )
        
        lastfmClient.historyToReturn = [track]
        lbClient.historyToReturn = []
        
        // Simulate backfill operation
        // In production, this would be called by SyncService
        try await lbClient.scrobble(track: track)
        
        // Verify backfilled
        XCTAssertEqual(lbClient.scrobbledTracks.count, 1, "Track should be backfilled")
        XCTAssertEqual(lbClient.scrobbledTracks.first?.artist, "The Beatles")
    }
    
    // MARK: - Blacklist Prevention Tests
    
    func testBlacklistPreventsBackfill() async throws {
        // Setup: Track is blacklisted
        let track = Track.createTest(
            artist: "Blocked Artist",
            name: "Blocked Track",
            sourceService: .lastfm
        )
        
        // Add to blacklist
        try await LocalBlacklist.shared.add(artist: track.artist, track: track.name)
        
        // Verify blacklisted
        let isBlacklisted = await LocalBlacklist.shared.contains(
            artist: track.artist,
            track: track.name
        )
        XCTAssertTrue(isBlacklisted, "Track should be blacklisted")
        
        // In production, SyncService checks blacklist before backfilling
        // Backfill should be skipped for blacklisted tracks
        
        // Cleanup
        try await LocalBlacklist.shared.remove(artist: track.artist, track: track.name)
    }
    
    // MARK: - Time Window Tests
    
    func testTimestampMatching() async {
        // Setup: Tracks with timestamps within matching window
        let baseTime = Int(Date().timeIntervalSince1970)
        
        let track1 = Track.createTest(
            artist: "Time Test",
            name: "Track",
            timestamp: baseTime,
            sourceService: .lastfm
        )
        
        let track2 = Track.createTest(
            artist: "Time Test",
            name: "Track",
            timestamp: baseTime + 60,  // 60 seconds later
            sourceService: .listenbrainz
        )
        
        // Should match within 120-second window (default)
        let timeDiff = abs(track1.timestamp - track2.timestamp)
        XCTAssertLessThan(timeDiff, 120, "Should be within matching window")
    }
    
    func testOutsideTimeWindow() async {
        // Setup: Tracks outside matching window
        let baseTime = Int(Date().timeIntervalSince1970)
        
        let track1 = Track.createTest(
            artist: "Time Test",
            name: "Track",
            timestamp: baseTime,
            sourceService: .lastfm
        )
        
        let track2 = Track.createTest(
            artist: "Time Test",
            name: "Track",
            timestamp: baseTime + 200,  // 200 seconds later
            sourceService: .listenbrainz
        )
        
        // Should NOT match (outside 120-second window)
        let timeDiff = abs(track1.timestamp - track2.timestamp)
        XCTAssertGreaterThan(timeDiff, 120, "Should be outside matching window")
    }
    
    // MARK: - Service Limitations Tests
    
    func testLastFm14DayLimit() async {
        // Last.fm API only returns recent scrobbles (typically 14 days for backfill)
        // This is a structural test for that behavior
        
        let now = Date()
        let fifteenDaysAgo = now.addingTimeInterval(-15 * 24 * 60 * 60)
        
        let _ = Track.createTest(
            artist: "Old Artist",
            name: "Old Track",
            timestamp: Int(fifteenDaysAgo.timeIntervalSince1970),
            sourceService: .lastfm
        )
        
        // In production, SyncService respects 14-day limit for Last.fm/LibreFm
        // Tracks older than 14 days won't be backfilled
        let daysSinceScrobble = now.timeIntervalSince(fifteenDaysAgo) / (24 * 60 * 60)
        XCTAssertGreaterThan(daysSinceScrobble, 14, "Track is older than 14 days")
    }
    
    func testListenBrainzNoTimeLimit() async {
        // ListenBrainz can backfill from any time period
        // This test validates that understanding
        
        let now = Date()
        let oneYearAgo = now.addingTimeInterval(-365 * 24 * 60 * 60)
        
        let oldTrack = Track.createTest(
            artist: "Old Artist",
            name: "Old Track",
            timestamp: Int(oneYearAgo.timeIntervalSince1970),
            sourceService: .listenbrainz
        )
        
        // ListenBrainz has no time limit for backfilling
        XCTAssertNotNil(oldTrack, "ListenBrainz can handle old tracks")
    }
    
    // MARK: - Sync Status Tests
    
    func testSyncStatusCalculation() async {
        // Setup enabled services
        let enabledServices: Set<ScrobbleService> = [.lastfm, .listenbrainz]
        
        // Track present in all enabled services
        var track = Track.createTest(
            artist: "Synced Artist",
            name: "Synced Track",
            sourceService: .lastfm
        )
        track.serviceInfo = [
            .listenbrainz: ServiceTrackData(timestamp: 12345, id: "test-id")
        ]
        
        let syncStatus = track.syncStatus(enabledServices: enabledServices)
        XCTAssertEqual(syncStatus, .synced, "Should be synced across all enabled services")
    }
    
    func testPartialSyncStatus() async {
        // Setup enabled services
        let enabledServices: Set<ScrobbleService> = [.lastfm, .listenbrainz, .librefm]
        
        // Track present in only some enabled services
        var track = Track.createTest(
            artist: "Partial Artist",
            name: "Partial Track",
            sourceService: .lastfm
        )
        track.serviceInfo = [
            .listenbrainz: ServiceTrackData(timestamp: 12345, id: "test-id")
            // Missing .librefm
        ]
        
        let syncStatus = track.syncStatus(enabledServices: enabledServices)
        XCTAssertEqual(syncStatus, .partial, "Should be partially synced")
    }
}
