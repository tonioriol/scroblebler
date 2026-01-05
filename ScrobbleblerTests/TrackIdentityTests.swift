import XCTest
@testable import Scroblebler

final class TrackIdentityTests: XCTestCase {
    
    // MARK: - Key Generation
    
    func testKeyGeneration_Normalized() {
        let key1 = TrackIdentity.key(artist: "The Beatles", track: "Hey Jude")
        let key2 = TrackIdentity.key(artist: "THE BEATLES", track: "HEY JUDE")
        let key3 = TrackIdentity.key(artist: "  the beatles  ", track: "  hey jude  ")
        
        XCTAssertEqual(key1, key2)
        XCTAssertEqual(key2, key3)
        XCTAssertEqual(key1, "the beatles|hey jude")
    }
    
    func testKeyGeneration_DifferentTracks() {
        let key1 = TrackIdentity.key(artist: "The Beatles", track: "Hey Jude")
        let key2 = TrackIdentity.key(artist: "The Beatles", track: "Let It Be")
        
        XCTAssertNotEqual(key1, key2)
    }
    
    func testKeyGeneration_DifferentArtists() {
        let key1 = TrackIdentity.key(artist: "The Beatles", track: "Yesterday")
        let key2 = TrackIdentity.key(artist: "Bob Dylan", track: "Yesterday")
        
        XCTAssertNotEqual(key1, key2)
    }
    
    // MARK: - Track Matching
    
    func testMatches_SameTrack() {
        let track1 = createTrack(artist: "Pink Floyd", track: "Comfortably Numb")
        let track2 = createTrack(artist: "PINK FLOYD", track: "comfortably numb")
        
        XCTAssertTrue(TrackIdentity.matches(track1, track2))
    }
    
    func testMatches_DifferentTracks() {
        let track1 = createTrack(artist: "Pink Floyd", track: "Comfortably Numb")
        let track2 = createTrack(artist: "Pink Floyd", track: "Wish You Were Here")
        
        XCTAssertFalse(TrackIdentity.matches(track1, track2))
    }
    
    // MARK: - Find in Array
    
    func testFind_Success() {
        let tracks = [
            createTrack(artist: "Queen", track: "Bohemian Rhapsody"),
            createTrack(artist: "Led Zeppelin", track: "Stairway to Heaven"),
            createTrack(artist: "The Beatles", track: "Hey Jude")
        ]
        
        let found = TrackIdentity.find(
            artist: "LED ZEPPELIN",
            track: "stairway to heaven",
            in: tracks
        )
        
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.artist, "Led Zeppelin")
    }
    
    func testFind_NotFound() {
        let tracks = [
            createTrack(artist: "Queen", track: "Bohemian Rhapsody")
        ]
        
        let found = TrackIdentity.find(
            artist: "The Beatles",
            track: "Hey Jude",
            in: tracks
        )
        
        XCTAssertNil(found)
    }
    
    // MARK: - Timestamp Window Matching
    
    func testFindByTimestamp_WithinWindow() {
        let baseTime = 1704441600 // 2024-01-05 10:00:00
        let track = createTrack(artist: "Radiohead", track: "Creep", timestamp: baseTime)
        
        let candidates = [
            createTrack(artist: "Other", track: "Song", timestamp: baseTime - 200),
            createTrack(artist: "Radiohead", track: "Creep", timestamp: baseTime + 60), // 60s difference
            createTrack(artist: "Another", track: "Track", timestamp: baseTime + 200)
        ]
        
        let found = TrackIdentity.findByTimestamp(track, in: candidates, windowSeconds: 120)
        
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.timestamp, baseTime + 60)
    }
    
    func testFindByTimestamp_OutsideWindow() {
        let baseTime = 1704441600
        let track = createTrack(artist: "Radiohead", track: "Creep", timestamp: baseTime)
        
        let candidates = [
            createTrack(artist: "Radiohead", track: "Creep", timestamp: baseTime + 300) // 300s difference
        ]
        
        let found = TrackIdentity.findByTimestamp(track, in: candidates, windowSeconds: 120)
        
        XCTAssertNil(found)
    }
    
    func testFindByTimestamp_SameTrackDifferentName() {
        let baseTime = 1704441600
        let track = createTrack(artist: "Radiohead", track: "Creep", timestamp: baseTime)
        
        let candidates = [
            createTrack(artist: "Radiohead", track: "Karma Police", timestamp: baseTime + 10)
        ]
        
        let found = TrackIdentity.findByTimestamp(track, in: candidates, windowSeconds: 120)
        
        XCTAssertNil(found, "Should not match different tracks even within time window")
    }
    
    // MARK: - Helper
    
    private func createTrack(artist: String, track: String, timestamp: Int = 1704441600) -> Track {
        Track(
            id: UUID(),
            artist: artist,
            album: "Test Album",
            name: track,
            timestamp: timestamp,
            duration: 240.0,
            sourceService: .lastfm,
            artwork: nil,
            artistURL: nil,
            albumURL: nil,
            trackURL: nil,
            imageUrl: nil
        )
    }
}
