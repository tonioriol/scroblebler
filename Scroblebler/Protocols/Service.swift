import Foundation

/// Protocol defining a scrobble service (combines client + metadata)
protocol Service {
    /// The scrobble client for this service
    var client: ScrobbleClient { get }
    
    /// Build all URLs for this service from track data
    func buildURLs(for track: Track) -> (artistURL: URL, albumURL: URL, trackURL: URL)
    
    /// Enrich track with service-specific metadata (e.g., MBIDs for ListenBrainz)
    func enrichTrack(_ track: Track) async -> Track
}
