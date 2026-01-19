import Foundation

/// Pure matching logic for listens across services
/// Delegates canonical key matching to ListenIdentity
struct ListenMatcher {
    /// Find matching listen using timestamp-based matching
    /// - Returns: First listen within 2-minute window with ≤5s timestamp delta
    static func findMatch(for listen: Listen, in candidates: [Listen]) -> Listen? {
        candidates.first { candidate in
            ListenIdentity.matches(listen, candidate) &&
            timestampsMatch(listen.listenedAt, candidate.listenedAt) &&
            abs(listen.listenedAt - candidate.listenedAt) <= 5
        }
    }

    private static func timestampsMatch(_ d1: Int, _ d2: Int) -> Bool {
        return abs(d1 - d2) < 120  // 2-minute window
    }
}
