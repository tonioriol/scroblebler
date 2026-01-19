import Foundation

/// Centralized listen identity and matching logic
struct ListenIdentity {
    /// Normalize string for matching (lowercase, trimmed)
    private static func normalize(_ string: String) -> String {
        string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Generate canonical key for listen matching
    static func key(artist: String, track: String) -> String {
        let normalizedArtist = normalize(artist)
        let normalizedTrack = normalize(track)
        return "\(normalizedArtist)|\(normalizedTrack)"
    }

    /// Check if two listens are the same (ignoring timestamp)
    static func matches(_ l1: Listen, _ l2: Listen) -> Bool {
        key(artist: l1.artist, track: l1.track) ==
        key(artist: l2.artist, track: l2.track)
    }

    /// Find matching listen in array by canonical key
    static func find(
        artist: String,
        track: String,
        in listens: [Listen]
    ) -> Listen? {
        let searchKey = key(artist: artist, track: track)
        return listens.first { l in
            key(artist: l.artist, track: l.track) == searchKey
        }
    }

    /// Find match by timestamp window (for cross-service sync)
    static func findByTimestamp(
        _ listen: Listen,
        in candidates: [Listen],
        windowSeconds: Int = 120
    ) -> Listen? {
        candidates.first { candidate in
            matches(listen, candidate) &&
            abs(listen.listenedAt - candidate.listenedAt) <= windowSeconds
        }
    }
}
