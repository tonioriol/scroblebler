import XCTest
@testable import Scroblebler

final class OperationTests: XCTestCase {
    
    // MARK: - Operation Type
    
    func testOperationType_Scrobble() {
        let track = createTrack()
        let operation = Operation.scrobble(track: track, services: [.lastfm])
        
        XCTAssertEqual(operation.type, "scrobble")
    }
    
    func testOperationType_Love() {
        let operation = Operation.love(artist: "Artist", track: "Track", loved: true, services: [.lastfm])
        
        XCTAssertEqual(operation.type, "love")
    }
    
    func testOperationType_Delete() {
        let operation = Operation.delete(artist: "Artist", track: "Track", timestamp: 1704441600, services: [.lastfm])
        
        XCTAssertEqual(operation.type, "delete")
    }
    
    // MARK: - Codable
    
    func testScrobbleOperation_Codable() throws {
        let track = createTrack(
            artist: "Kendrick Lamar",
            album: "good kid, m.A.A.d city",
            name: "Swimming Pools (Drank)"
        )
        let original = Operation.scrobble(track: track, services: [.lastfm, .listenbrainz])
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Operation.self, from: encoded)
        
        guard case let .scrobble(decodedTrack, decodedServices) = decoded else {
            XCTFail("Expected scrobble operation")
            return
        }
        
        XCTAssertEqual(decodedTrack.artist, track.artist)
        XCTAssertEqual(decodedTrack.name, track.name)
        XCTAssertEqual(decodedServices, [.lastfm, .listenbrainz])
    }
    
    func testLoveOperation_Codable() throws {
        let original = Operation.love(
            artist: "The Weeknd",
            track: "Blinding Lights",
            loved: true,
            services: [.lastfm, .librefm]
        )
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Operation.self, from: encoded)
        
        guard case let .love(artist, track, loved, services) = decoded else {
            XCTFail("Expected love operation")
            return
        }
        
        XCTAssertEqual(artist, "The Weeknd")
        XCTAssertEqual(track, "Blinding Lights")
        XCTAssertTrue(loved)
        XCTAssertEqual(services, [.lastfm, .librefm])
    }
    
    func testDeleteOperation_Codable() throws {
        let timestamp = 1704441600
        let original = Operation.delete(
            artist: "Nirvana",
            track: "Smells Like Teen Spirit",
            timestamp: timestamp,
            services: [.lastfm]
        )
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Operation.self, from: encoded)
        
        guard case let .delete(artist, track, decodedTimestamp, services) = decoded else {
            XCTFail("Expected delete operation")
            return
        }
        
        XCTAssertEqual(artist, "Nirvana")
        XCTAssertEqual(track, "Smells Like Teen Spirit")
        XCTAssertEqual(decodedTimestamp, timestamp)
        XCTAssertEqual(services, [.lastfm])
    }
    
    func testDeleteOperation_NilTimestamp_Codable() throws {
        let original = Operation.delete(
            artist: "Artist",
            track: "Track",
            timestamp: nil,
            services: [.listenbrainz]
        )
        
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Operation.self, from: encoded)
        
        guard case let .delete(_, _, timestamp, _) = decoded else {
            XCTFail("Expected delete operation")
            return
        }
        
        XCTAssertNil(timestamp)
    }
    
    // MARK: - Multiple Services
    
    func testOperation_MultipleServices() throws {
        let track = createTrack()
        let services: [ScrobbleService] = [.lastfm, .listenbrainz, .librefm]
        let operation = Operation.scrobble(track: track, services: services)
        
        let encoded = try JSONEncoder().encode(operation)
        let decoded = try JSONDecoder().decode(Operation.self, from: encoded)
        
        guard case let .scrobble(_, decodedServices) = decoded else {
            XCTFail("Expected scrobble operation")
            return
        }
        
        XCTAssertEqual(Set(decodedServices), Set(services))
    }
    
    // MARK: - Helper
    
    private func createTrack(
        artist: String = "Test Artist",
        album: String = "Test Album",
        name: String = "Test Track"
    ) -> Track {
        Track(
            id: UUID(),
            artist: artist,
            album: album,
            name: name,
            timestamp: 1704441600,
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
