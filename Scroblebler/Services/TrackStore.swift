import Foundation
import Combine

/// Pure storage layer for track data (repository pattern)
/// Single source of truth for current track and history
@MainActor
class TrackStore: ObservableObject {
    static let shared = TrackStore()
    
    // MARK: - Published State
    
    /// Currently playing track (single source of truth)
    @Published private(set) var currentTrack: Track?
    
    /// History tracks (only scrobbled tracks from API)
    @Published private(set) var history: [Track] = []
    
    private init() {}
    
    // MARK: - Current Track Management
    
    /// Set current track (from media player)
    func setCurrentTrack(_ track: Track) {
        currentTrack = track
        Logger.info("Set current track: \(track.description)", log: Logger.playback)
    }
    
    /// Update current track with enriched data
    func updateCurrentTrack(_ track: Track) {
        currentTrack = track
        Logger.debug("Updated current track: \(track.description)", log: Logger.ui)
    }
    
    /// Clear current track
    func clearCurrentTrack() {
        currentTrack = nil
        Logger.info("Cleared current track", log: Logger.playback)
    }
    
    // MARK: - History Management
    
    /// Replace history (for page 1 refresh)
    func setHistory(_ tracks: [Track]) {
        history = tracks
        Logger.info("Set history: \(tracks.count) tracks", log: Logger.sync)
    }
    
    /// Append to history (for pagination)
    func appendHistory(_ tracks: [Track]) {
        // De-duplicate by canonical key
        let existingKeys = Set(history.map { $0.canonicalKey })
        let newTracks = tracks.filter { !existingKeys.contains($0.canonicalKey) }
        history.append(contentsOf: newTracks)
        Logger.info("Appended \(newTracks.count) tracks to history", log: Logger.sync)
    }
    
    /// Clear all history
    func clearHistory() {
        history.removeAll()
        Logger.info("Cleared history", log: Logger.ui)
    }
    
    // MARK: - Update Operations
    
    /// Update track in history by canonical key
    func updateTrack(artist: String, track: String, mutation: (inout Track) -> Void) {
        let key = TrackIdentity.key(artist: artist, track: track)
        
        // Update in history
        if let index = history.firstIndex(where: { $0.canonicalKey == key }) {
            var updated = history[index]
            mutation(&updated)
            history[index] = updated
            Logger.debug("Updated track in history: \(artist) - \(track)", log: Logger.ui)
        }
        
        // Update current track if it matches
        if let current = currentTrack, current.canonicalKey == key {
            var updated = current
            mutation(&updated)
            currentTrack = updated
            Logger.debug("Updated current track: \(artist) - \(track)", log: Logger.ui)
        }
    }
    
    /// Find track in history or current track
    func findTrack(artist: String, track: String) -> Track? {
        let key = TrackIdentity.key(artist: artist, track: track)
        
        // Check current track first
        if let current = currentTrack, current.canonicalKey == key {
            return current
        }
        
        // Check history
        return history.first(where: { $0.canonicalKey == key })
    }
    
    // MARK: - Query Operations
    
    /// Check if track is loved
    func isLoved(artist: String, track: String) -> Bool {
        return findTrack(artist: artist, track: track)?.loved ?? false
    }
    
    /// Get playcount for track
    func playcount(artist: String, track: String) -> Int? {
        return findTrack(artist: artist, track: track)?.playcount
    }
    
    /// Decrement playcount (for undo)
    func decrementPlaycount(artist: String, track: String) {
        updateTrack(artist: artist, track: track) { t in
            t.playcount = max(0, t.playcount - 1)
        }
    }
    
    /// Increment playcount (for redo)
    func incrementPlaycount(artist: String, track: String) {
        updateTrack(artist: artist, track: track) { t in
            t.playcount += 1
        }
    }
}
