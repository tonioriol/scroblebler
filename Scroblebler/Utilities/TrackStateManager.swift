import Foundation
import Combine

/// Centralized state manager for track metadata (loved, playcount, etc.)
/// Provides single source of truth for UI updates without full page reloads
class TrackStateManager: ObservableObject {
    static let shared = TrackStateManager()
    
    /// Track state identified by artist+track key
    struct TrackState {
        var loved: Bool
        var playcount: Int?
        var timestamp: Int?
        var lastUpdated: Date
        
        init(loved: Bool = false, playcount: Int? = nil, timestamp: Int? = nil) {
            self.loved = loved
            self.playcount = playcount
            self.timestamp = timestamp
            self.lastUpdated = Date()
        }
    }
    
    /// Dictionary of track states keyed by "artist|track"
    @Published private(set) var trackStates: [String: TrackState] = [:]
    
    private init() {}
    
    /// Generate unique key for a track
    private func key(artist: String, track: String) -> String {
        return "\(artist.lowercased())|\(track.lowercased())"
    }
    
    /// Get current state for a track
    func state(artist: String, track: String) -> TrackState? {
        return trackStates[key(artist: artist, track: track)]
    }
    
    /// Update track state
    func updateState(artist: String, track: String, loved: Bool? = nil, playcount: Int? = nil, timestamp: Int? = nil) {
        let trackKey = key(artist: artist, track: track)
        var state = trackStates[trackKey] ?? TrackState()
        
        if let loved = loved {
            state.loved = loved
        }
        if let playcount = playcount {
            state.playcount = playcount
        }
        if let timestamp = timestamp {
            state.timestamp = timestamp
        }
        state.lastUpdated = Date()
        
        trackStates[trackKey] = state
        Logger.debug("Updated track state: \(artist) - \(track) -> loved: \(state.loved), playcount: \(state.playcount ?? -1)", log: Logger.ui)
    }
    
    /// Toggle love state
    func toggleLove(artist: String, track: String) -> Bool {
        let trackKey = key(artist: artist, track: track)
        var state = trackStates[trackKey] ?? TrackState()
        state.loved.toggle()
        state.lastUpdated = Date()
        trackStates[trackKey] = state
        return state.loved
    }
    
    /// Increment playcount (for redo)
    func incrementPlaycount(artist: String, track: String) {
        let trackKey = key(artist: artist, track: track)
        var state = trackStates[trackKey] ?? TrackState()
        state.playcount = (state.playcount ?? 0) + 1
        state.lastUpdated = Date()
        trackStates[trackKey] = state
    }
    
    /// Decrement playcount (for undo)
    func decrementPlaycount(artist: String, track: String) {
        let trackKey = key(artist: artist, track: track)
        var state = trackStates[trackKey] ?? TrackState()
        if let currentCount = state.playcount, currentCount > 0 {
            state.playcount = currentCount - 1
        }
        state.lastUpdated = Date()
        trackStates[trackKey] = state
    }
    
    /// Clear all cached states (e.g., on logout)
    func clear() {
        trackStates.removeAll()
        Logger.info("Cleared all track states", log: Logger.ui)
    }
}
