import Foundation

/// Centralized track identity and matching logic
struct TrackIdentity {
    /// Normalize string for matching (lowercase, trimmed)
    private static func normalize(_ string: String) -> String {
        string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Generate canonical key for track matching
    static func key(artist: String, track: String) -> String {
        let normalizedArtist = normalize(artist)
        let normalizedTrack = normalize(track)
        return "\(normalizedArtist)|\(normalizedTrack)"
    }
    
    /// Check if two tracks are the same (ignoring timestamp)
    static func matches(_ t1: Track, _ t2: Track) -> Bool {
        key(artist: t1.artist, track: t1.name) == 
        key(artist: t2.artist, track: t2.name)
    }
    
    /// Find matching track in array by canonical key
    static func find(
        artist: String,
        track: String,
        in tracks: [Track]
    ) -> Track? {
        let searchKey = key(artist: artist, track: track)
        return tracks.first { t in
            key(artist: t.artist, track: t.name) == searchKey
        }
    }
    
    /// Find match by timestamp window (for cross-service sync)
    static func findByTimestamp(
        _ track: Track,
        in candidates: [Track],
        windowSeconds: Int = 120
    ) -> Track? {
        candidates.first { candidate in
            matches(track, candidate) &&
            abs(track.timestamp - candidate.timestamp) <= windowSeconds
        }
    }
}
