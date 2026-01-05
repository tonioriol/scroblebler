import Foundation
@testable import Scroblebler

/// Simulates media playback for testing Watcher behavior
/// Provides controllable track info, position updates, and playback control
class PlaybackSimulator {
    private var currentStatus: MediaControlStatus?
    private var currentPosition: Double = 0
    private var startTime: Date?
    private var isPaused = false
    
    /// Simulate playing a track
    func playTrack(
        artist: String,
        title: String,
        duration: Double,
        album: String = "Test Album",
        startAt: Double = 0
    ) -> MediaControlStatus {
        currentPosition = startAt
        startTime = Date()
        isPaused = false
        
        let status = MediaControlStatus(
            title: title,
            artist: artist,
            album: album,
            artworkData: nil,
            duration: duration,
            playing: true,
            playbackRate: 1.0,
            elapsedTime: startAt,
            contentItemIdentifier: "\(artist)-\(title)",
            trackNumber: 1,
            totalTrackCount: 10,
            bundleIdentifier: "com.apple.Music"
        )
        
        currentStatus = status
        Logger.debug("PlaybackSimulator: Playing '\(artist) - \(title)' (duration: \(duration)s)", log: Logger.playback)
        return status
    }
    
    /// Advance time by specified seconds
    func advanceTime(_ seconds: Double) {
        guard !isPaused else {
            Logger.debug("PlaybackSimulator: Cannot advance time while paused", log: Logger.playback)
            return
        }
        
        currentPosition += seconds
        
        // Update start time to reflect new position
        startTime = Date().addingTimeInterval(-currentPosition)
        
        Logger.debug("PlaybackSimulator: Advanced to \(currentPosition)s", log: Logger.playback)
    }
    
    /// Get current playback position
    func getCurrentPosition() -> Double {
        if isPaused || startTime == nil {
            return currentPosition
        }
        
        let elapsed = Date().timeIntervalSince(startTime ?? Date())
        return currentPosition + elapsed
    }
    
    /// Pause playback
    func pause() {
        guard var status = currentStatus, !isPaused else { return }
        
        // Lock current position
        currentPosition = getCurrentPosition()
        isPaused = true
        
        status = MediaControlStatus(
            title: status.title,
            artist: status.artist,
            album: status.album,
            artworkData: status.artworkData,
            duration: status.duration,
            playing: false,
            playbackRate: 0.0,
            elapsedTime: currentPosition,
            contentItemIdentifier: status.contentItemIdentifier,
            trackNumber: status.trackNumber,
            totalTrackCount: status.totalTrackCount,
            bundleIdentifier: status.bundleIdentifier
        )
        
        currentStatus = status
        Logger.debug("PlaybackSimulator: Paused at \(currentPosition)s", log: Logger.playback)
    }
    
    /// Resume playback
    func resume() {
        guard var status = currentStatus, isPaused else { return }
        
        isPaused = false
        startTime = Date().addingTimeInterval(-currentPosition)
        
        status = MediaControlStatus(
            title: status.title,
            artist: status.artist,
            album: status.album,
            artworkData: status.artworkData,
            duration: status.duration,
            playing: true,
            playbackRate: 1.0,
            elapsedTime: currentPosition,
            contentItemIdentifier: status.contentItemIdentifier,
            trackNumber: status.trackNumber,
            totalTrackCount: status.totalTrackCount,
            bundleIdentifier: status.bundleIdentifier
        )
        
        currentStatus = status
        Logger.debug("PlaybackSimulator: Resumed at \(currentPosition)s", log: Logger.playback)
    }
    
    /// Seek to specific position
    func seekTo(_ position: Double) {
        guard let status = currentStatus else { return }
        
        currentPosition = position
        if !isPaused {
            startTime = Date()
        }
        
        Logger.debug("PlaybackSimulator: Seeked to \(position)s", log: Logger.playback)
        
        // Update status with new position
        let newStatus = MediaControlStatus(
            title: status.title,
            artist: status.artist,
            album: status.album,
            artworkData: status.artworkData,
            duration: status.duration,
            playing: status.playing,
            playbackRate: status.playbackRate,
            elapsedTime: position,
            contentItemIdentifier: status.contentItemIdentifier,
            trackNumber: status.trackNumber,
            totalTrackCount: status.totalTrackCount,
            bundleIdentifier: status.bundleIdentifier
        )
        
        currentStatus = newStatus
    }
    
    /// Stop playback and clear state
    func stop() {
        currentStatus = nil
        currentPosition = 0
        startTime = nil
        isPaused = false
        Logger.debug("PlaybackSimulator: Stopped", log: Logger.playback)
    }
    
    /// Get current status
    func getStatus() -> MediaControlStatus? {
        guard var status = currentStatus else { return nil }
        
        // Update elapsed time if playing
        if !isPaused {
            let elapsed = getCurrentPosition()
            status = MediaControlStatus(
                title: status.title,
                artist: status.artist,
                album: status.album,
                artworkData: status.artworkData,
                duration: status.duration,
                playing: status.playing,
                playbackRate: status.playbackRate,
                elapsedTime: elapsed,
                contentItemIdentifier: status.contentItemIdentifier,
                trackNumber: status.trackNumber,
                totalTrackCount: status.totalTrackCount,
                bundleIdentifier: status.bundleIdentifier
            )
        }
        
        return status
    }
    
    /// Reset simulator state
    func reset() {
        stop()
    }
}
