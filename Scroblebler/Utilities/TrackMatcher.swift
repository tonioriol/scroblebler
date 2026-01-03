import Foundation

/// Pure matching logic for tracks across services
struct TrackMatcher {
    /// Find matching track using timestamp-based matching
    /// - Returns: First track within 2-minute window with ≤5s timestamp delta
    static func findMatch(for track: RecentTrack, in candidates: [RecentTrack]) -> RecentTrack? {
        candidates.first { candidate in
            timestampsMatch(track.date, candidate.date) &&
            abs((track.date ?? 0) - (candidate.date ?? 0)) <= 5
        }
    }
    
    private static func timestampsMatch(_ d1: Int?, _ d2: Int?) -> Bool {
        guard let d1 = d1, let d2 = d2 else { return d1 == nil && d2 == nil }
        return abs(d1 - d2) < 120  // 2-minute window
    }
}
