import Foundation

// MARK: - Sync Models

enum SyncStatus: Codable {
    case unknown
    case synced           // Present in all enabled services
    case partial          // Not in all enabled services
    
    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .synced: return "checkmark.circle.fill"
        case .partial: return "xmark.circle.fill"
        }
    }
    
    /// Calculate sync status based on which services have the track
    static func calculate(
        presentInServices: Set<ScrobbleService>,
        enabledServices: Set<ScrobbleService>
    ) -> SyncStatus {
        guard !enabledServices.isEmpty else { return .unknown }
        return presentInServices == enabledServices ? .synced : .partial
    }
}

struct ServiceTrackData: Codable {
    let timestamp: Int?     // Required for Last.fm/Libre.fm
    let id: String?         // ListenBrainz recording_msid (for deletion) or recording_mbid
    let artistMbid: String? // ListenBrainz artist MBID (for URLs)
    let releaseMbid: String? // ListenBrainz release MBID (for URLs)
    
    // Factory methods make intent clear
    static func lastfm(timestamp: Int) -> ServiceTrackData {
        ServiceTrackData(timestamp: timestamp, id: nil, artistMbid: nil, releaseMbid: nil)
    }
    
    static func listenbrainz(recordingMsid: String, timestamp: Int) -> ServiceTrackData {
        ServiceTrackData(timestamp: timestamp, id: recordingMsid, artistMbid: nil, releaseMbid: nil)
    }
    
    static func listenbrainzWithMbids(recordingMbid: String, artistMbid: String?, releaseMbid: String?, timestamp: Int) -> ServiceTrackData {
        ServiceTrackData(timestamp: timestamp, id: recordingMbid, artistMbid: artistMbid, releaseMbid: releaseMbid)
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
