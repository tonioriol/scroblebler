import Foundation

/// Single unified track model for all contexts (now playing, history, queue)
struct Track: Identifiable, Codable, Equatable {
    // MARK: - Identity
    
    let id: UUID
    
    /// Canonical key for matching (artist|track lowercase)
    var canonicalKey: String {
        TrackIdentity.key(artist: artist, track: name)
    }
    
    // MARK: - Immutable Metadata
    
    let artist: String
    let album: String
    let name: String
    let timestamp: Int
    let duration: Double
    let sourceService: ScrobbleService
    let bundleIdentifier: String? // Media player that was playing this track
    
    // MARK: - Mutable State
    
    var loved: Bool = false
    var playcount: Int = 1
    var scrobbled: Bool = false
    var blacklisted: Bool = false
    
    // MARK: - Service Sync
    
    /// Track identifiers per service (for deletion/updates)
    var serviceInfo: [ScrobbleService: ServiceTrackData] = [:]
    
    /// Which services have this track
    var syncedServices: Set<ScrobbleService> {
        Set([sourceService] + serviceInfo.keys)
    }
    
    /// Computed sync status
    func syncStatus(enabledServices: Set<ScrobbleService>) -> SyncStatus {
        SyncStatus.calculate(
            presentInServices: syncedServices,
            enabledServices: enabledServices
        )
    }
    
    // MARK: - UI Metadata
    
    let artwork: Data?
    let imageUrl: String?
    
    // MARK: - Computed Properties
    
    var isNowPlaying: Bool {
        !scrobbled
    }
    
    var date: Int? {
        timestamp
    }
    
    // Compatibility properties for old code
    var length: Double { duration }
    var startedAt: Int32 { Int32(timestamp) }
    
    var description: String {
        "\(name) by \(artist) from \(album)"
    }
    
    // MARK: - Equatable
    
    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - Codable Keys
    
    enum CodingKeys: String, CodingKey {
        case id
        case artist
        case album
        case name
        case timestamp
        case duration
        case sourceService
        case bundleIdentifier
        case loved
        case playcount
        case scrobbled
        case blacklisted
        case serviceInfo
        case artwork
        case imageUrl
    }
    
    // MARK: - Factory Methods
    
    /// Create from media player
    static func fromMediaPlayer(
        artist: String,
        album: String,
        name: String,
        duration: Double,
        artwork: Data?,
        startedAt: Int32,
        bundleIdentifier: String? = nil
    ) -> Track {
        return Track(
            id: UUID(),
            artist: artist,
            album: album,
            name: name,
            timestamp: Int(startedAt),
            duration: duration,
            sourceService: .lastfm,
            bundleIdentifier: bundleIdentifier,
            artwork: artwork,
            imageUrl: nil
        )
    }
    
    /// Create from API response
    static func fromAPI(
        artist: String,
        album: String,
        name: String,
        timestamp: Int,
        loved: Bool,
        playcount: Int?,
        imageUrl: String?,
        sourceService: ScrobbleService,
        serviceData: ServiceTrackData
    ) -> Track {
        Track(
            id: UUID(),
            artist: artist,
            album: album,
            name: name,
            timestamp: timestamp,
            duration: 0,
            sourceService: sourceService,
            bundleIdentifier: nil,
            loved: loved,
            playcount: playcount ?? 1,
            scrobbled: true,
            serviceInfo: [sourceService: serviceData],
            artwork: nil,
            imageUrl: imageUrl
        )
    }
}

// MARK: - ServiceTrackData Extension

extension ServiceTrackData {
    var codingKey: ScrobbleService? {
        // Helper to convert back to service enum if needed
        return nil
    }
}
