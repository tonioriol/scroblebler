import Foundation

// MARK: - Domain Models

struct RecentTrack: Codable {
    let name: String
    let artist: String
    let album: String
    let date: Int?
    let isNowPlaying: Bool
    let loved: Bool
    let imageUrl: String?
    let artistURL: URL
    let albumURL: URL
    let trackURL: URL
    let playcount: Int?
    var serviceInfo: [String: ServiceTrackData] = [:]
    var sourceService: ScrobbleService? = nil
}

struct ServiceTrackData: Codable {
    let timestamp: Int?
    let id: String?
}

struct UserStats: Codable {
    let playcount: Int
    let artistCount: Int
    let trackCount: Int
    let albumCount: Int
    let lovedCount: Int
    let registered: String
    let country: String?
    let realname: String?
    let gender: String?
    let age: String?
    let playlistCount: Int?
}

struct TopArtist: Codable {
    let name: String
    let playcount: Int
    let imageUrl: String?
}

struct TopAlbum: Codable {
    let artist: String
    let name: String
    let playcount: Int
    let imageUrl: String?
}

struct TopTrack: Codable {
    let artist: String
    let name: String
    let playcount: Int
    let imageUrl: String?
}

// MARK: - Track (currently playing)

struct Track {
    let artist: String
    let album: String
    let name: String
    let length: Double
    let artwork: Data?
    let year: Int32
    var loved: Bool
    let startedAt: Int32
    var scrobbled: Bool = false
    
    var description: String {
        "\(name) - \(artist) on \(album) (\(year))"
    }
}

// MARK: - Service Configuration

enum ScrobbleService: String, CaseIterable, Codable, Identifiable {
    case lastfm = "Last.fm"
    case librefm = "Libre.fm"
    case listenbrainz = "ListenBrainz"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
}

struct ServiceCredentials: Codable {
    let service: ScrobbleService
    var token: String
    var username: String
    var profileUrl: String?
    var isSubscriber: Bool
    var isEnabled: Bool
}

// MARK: - Player State

enum PlayerState {
    case unknown
    case stopped
    case playing
    case paused
    case seeking
}
