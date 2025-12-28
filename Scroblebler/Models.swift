import Foundation

// MARK: - Domain Models

struct RecentTrack: Codable, Identifiable {
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
    var syncStatus: SyncStatus = .unknown
    let uniqueId: UUID
    
    // Unique ID for SwiftUI
    var id: String {
        // For tracks with timestamps, use timestamp-based ID for merging
        // For tracks without timestamps, use UUID to ensure uniqueness
        if let date = date, date > 0 {
            let serviceKeys = serviceInfo.keys.sorted().joined(separator: ",")
            let sourceKey = sourceService?.rawValue ?? "unknown"
            return "\(date)_\(artist)_\(name)_\(sourceKey)_\(serviceKeys)"
        } else {
            return uniqueId.uuidString
        }
    }
    
    init(name: String, artist: String, album: String, date: Int?, isNowPlaying: Bool, loved: Bool, imageUrl: String?, artistURL: URL, albumURL: URL, trackURL: URL, playcount: Int?, serviceInfo: [String: ServiceTrackData] = [:], sourceService: ScrobbleService? = nil, syncStatus: SyncStatus = .unknown, uniqueId: UUID = UUID()) {
        self.name = name
        self.artist = artist
        self.album = album
        self.date = date
        self.isNowPlaying = isNowPlaying
        self.loved = loved
        self.imageUrl = imageUrl
        self.artistURL = artistURL
        self.albumURL = albumURL
        self.trackURL = trackURL
        self.playcount = playcount
        self.serviceInfo = serviceInfo
        self.sourceService = sourceService
        self.syncStatus = syncStatus
        self.uniqueId = uniqueId
    }
}

// MARK: - Sync Models

enum SyncStatus: Codable {
    case unknown
    case synced           // Present in all enabled services
    case partial          // Present in some services
    case primaryOnly      // Only in primary service
    
    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .synced: return "checkmark.circle.fill"
        case .partial: return "exclamationmark.circle.fill"
        case .primaryOnly: return "xmark.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .unknown: return "gray"
        case .synced: return "green"
        case .partial: return "orange"
        case .primaryOnly: return "red"
        }
    }
}

struct BackfillTask {
    let track: RecentTrack
    let targetService: ScrobbleService
    let targetCredentials: ServiceCredentials
    let sourceServices: [ScrobbleService]
    
    var canBackfill: Bool {
        // Check age constraints based on service
        guard let timestamp = track.date else { return false }
        let age = Date().timeIntervalSince1970 - TimeInterval(timestamp)
        let daysOld = age / 86400
        
        switch targetService {
        case .lastfm, .librefm:
            // Last.fm/Libre.fm: only allow backfill if <14 days old
            return daysOld < 14
        case .listenbrainz:
            // ListenBrainz: no time restriction
            return true
        }
    }
}

struct ServiceTrackData: Codable {
    let timestamp: Int?  // Required for Last.fm/Libre.fm
    let id: String?      // Required for ListenBrainz (recording_msid)
    
    // Factory methods make intent clear
    static func lastfm(timestamp: Int) -> ServiceTrackData {
        ServiceTrackData(timestamp: timestamp, id: nil)
    }
    
    static func listenbrainz(recordingMsid: String, timestamp: Int) -> ServiceTrackData {
        ServiceTrackData(timestamp: timestamp, id: recordingMsid)
    }
}

struct ScrobbleIdentifier {
    let artist: String
    let track: String
    let timestamp: Int?
    let serviceId: String?
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
    
    // URLs for linking (enriched by services)
    var artistURL: URL?
    var albumURL: URL?
    var trackURL: URL?
    
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
