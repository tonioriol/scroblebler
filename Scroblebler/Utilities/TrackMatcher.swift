import Foundation

/// Pure matching logic for tracks across services
/// Delegates canonical key matching to TrackIdentity
struct TrackMatcher {
    /// Find matching track using timestamp-based matching
    /// - Returns: First track within 2-minute window with ≤5s timestamp delta
    static func findMatch(for track: Track, in candidates: [Track]) -> Track? {
        candidates.first { candidate in
            TrackIdentity.matches(track, candidate) &&
            timestampsMatch(track.timestamp, candidate.timestamp) &&
            abs(track.timestamp - candidate.timestamp) <= 5
        }
    }
    
    private static func timestampsMatch(_ d1: Int, _ d2: Int) -> Bool {
        return abs(d1 - d2) < 120  // 2-minute window
    }
}
