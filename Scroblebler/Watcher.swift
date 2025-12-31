import Foundation
import AppKit
import OSAKit
import MediaRemoteAdapter

struct MediaControlStatus: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: String?
    let duration: Double?
    let playing: Bool?
    let playbackRate: Double?
    let elapsedTime: Double?
    let contentItemIdentifier: String?
    let trackNumber: Int?
    let totalTrackCount: Int?
    let bundleIdentifier: String?
    
    enum CodingKeys: String, CodingKey {
        case title, artist, album, artworkData, duration, playing, playbackRate
        case elapsedTime, contentItemIdentifier, trackNumber, totalTrackCount, bundleIdentifier
    }
}

class Watcher: ObservableObject {
    @Published var currentTrackID: String?
    @Published var currentTrack: Track?
    @Published var currentPosition: Double?
    @Published var maxPosition: Double?
    @Published var musicRunning = false
    @Published var playerState: PlayerState = .unknown
    @Published var running = true
    
    private let mediaController = MediaController()
    private var lastSnapshotTime: Date?
    private var lastSnapshotPosition: Double?
    private var currentStatus: MediaControlStatus?
    private var positionTimer: Timer?
    private var lastSeekTime: Date?
    
    var onTrackChanged: ((Track) -> Void)?
    var onScrobbleWanted: ((Track) -> Void)?
    
    init(debug: Bool = false) {
        setupMediaController()
    }
    
    private func setupMediaController() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            guard let self = self else { return }
            
            if let trackInfo = trackInfo {
                self.handleTrackInfo(trackInfo)
            } else {
                // No media playing
                self.currentStatus = nil
                Task { @MainActor in
                    self.reset()
                }
            }
        }
        
        mediaController.onListenerTerminated = { [weak self] in
            Logger.debug("MediaController listener terminated", log: Logger.playback)
            guard let self = self else { return }
            
            if self.running {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.running {
                        Logger.debug("Restarting MediaController", log: Logger.playback)
                        self.mediaController.startListening()
                    }
                }
            }
        }
    }
    
    func start() {
        mediaController.startListening()
        startPositionTimer()
    }
    
    func stop() {
        running = false
        mediaController.stopListening()
        stopPositionTimer()
    }
    
    private func startPositionTimer() {
        positionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateInterpolatedPosition()
        }
    }
    
    private func stopPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = nil
    }
    
    private func updateInterpolatedPosition() {
        // Don't update position for 1 second after a seek to allow it to settle
        if let seekTime = lastSeekTime, Date().timeIntervalSince(seekTime) < 1.0 {
            return
        }
        
        guard let status = currentStatus,
              status.playing == true,
              (status.playbackRate ?? 0) > 0,
              let lastTime = lastSnapshotTime,
              let lastPos = lastSnapshotPosition else {
            return
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)
        let position = lastPos + elapsed
        
        setState {
            self.currentPosition = position
            if self.maxPosition == nil || position > (self.maxPosition ?? 0) {
                self.maxPosition = position
            }
        }
    }
    
    func notifySeek() {
        lastSeekTime = Date()
    }
    
    private func handleTrackInfo(_ trackInfo: MediaRemoteAdapter.TrackInfo) {
        let payload = trackInfo.payload
        
        // Convert artwork NSImage to base64 if available
        var artworkData: String?
        if let artwork = payload.artwork {
            if let tiffData = artwork.tiffRepresentation,
               let bitmapImage = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                artworkData = pngData.base64EncodedString()
            }
        }
        
        // Convert microseconds to seconds
        let durationSeconds = (payload.durationMicros ?? 0) / 1_000_000.0
        let elapsedTimeSeconds = payload.currentElapsedTime ?? ((payload.elapsedTimeMicros ?? 0) / 1_000_000.0)
        
        let status = MediaControlStatus(
            title: payload.title,
            artist: payload.artist,
            album: payload.album,
            artworkData: artworkData,
            duration: durationSeconds > 0 ? durationSeconds : nil,
            playing: payload.isPlaying,
            playbackRate: payload.playbackRate,
            elapsedTime: elapsedTimeSeconds,
            contentItemIdentifier: payload.title,
            trackNumber: nil,
            totalTrackCount: nil,
            bundleIdentifier: payload.bundleIdentifier
        )
        
        // Handle missing or incomplete duration - preserve from previous if same track
        var newStatus = status
        let hasDuration = newStatus.duration != nil && (newStatus.duration ?? 0) > 0
        
        if !hasDuration,
           let current = currentStatus,
           current.contentItemIdentifier == newStatus.contentItemIdentifier,
           let currentDuration = current.duration,
           currentDuration > 0 {
            // Same track, missing/invalid duration - use previous
            newStatus = MediaControlStatus(
                title: newStatus.title,
                artist: newStatus.artist,
                album: newStatus.album,
                artworkData: newStatus.artworkData,
                duration: currentDuration,
                playing: newStatus.playing,
                playbackRate: newStatus.playbackRate,
                elapsedTime: newStatus.elapsedTime,
                contentItemIdentifier: newStatus.contentItemIdentifier,
                trackNumber: newStatus.trackNumber,
                totalTrackCount: newStatus.totalTrackCount,
                bundleIdentifier: newStatus.bundleIdentifier
            )
        }
        
        currentStatus = newStatus
        
        guard let status = currentStatus else { return }
        
        // Validate minimum required fields for a valid track
        guard let title = status.title, !title.isEmpty,
              let bundleId = status.bundleIdentifier, !bundleId.isEmpty,
              let duration = status.duration, duration > 0 else {
            Logger.debug("Skipping incomplete track data (title: \(status.title ?? "nil"), bundle: \(status.bundleIdentifier ?? "nil"), duration: \(status.duration ?? 0))", log: Logger.playback)
            return
        }
        
        Task { @MainActor in
            try? self.processStatus(status)
        }
    }
    
    private func getLovedStatus() -> Bool {
        let lovedProperties = ["favorited", "loved"]
        
        for propertyName in lovedProperties {
            let script = """
                tell application "Music" to get \(propertyName) of the current track
            """
            
            guard let appleScript = NSAppleScript(source: script) else { continue }
            
            var error: NSDictionary?
            let result = appleScript.executeAndReturnError(&error)
            
            if error == nil {
                return result.booleanValue
            }
        }
        
        return false
    }
    
    private func getPlayerTrack(from status: MediaControlStatus) throws -> Track {
        let artwork = status.artworkData
            .flatMap { Data(base64Encoded: $0) } ?? Data()
        
        let elapsedTime = status.elapsedTime ?? 0
        let startedAt = Int32(Date().timeIntervalSince1970 - elapsedTime)
        
        // Only fetch loved status for Apple Music
        let loved = (status.bundleIdentifier ?? "") == "com.apple.Music" ? getLovedStatus() : false
        
        return Track(
            artist: status.artist ?? "",
            album: status.album ?? "",
            name: status.title ?? "",
            length: status.duration ?? 0,
            artwork: artwork,
            year: 0,
            loved: loved,
            startedAt: startedAt
        )
    }
    
    private func isMusicRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Music"
        }
    }
    
    private func setState(_ changes: @escaping () -> Void) {
        if Thread.isMainThread {
            changes()
        } else {
            DispatchQueue.main.async {
                changes()
            }
        }
    }
    
    private func reset() {
        if Thread.isMainThread {
            currentTrackID = nil
            currentTrack = nil
            currentPosition = nil
            maxPosition = nil
        } else {
            DispatchQueue.main.async {
                self.currentTrackID = nil
                self.currentTrack = nil
                self.currentPosition = nil
                self.maxPosition = nil
            }
        }
    }
    
    @MainActor
    private func processStatus(_ status: MediaControlStatus) throws {
        // Check if the media player app is running (any player, not just Music)
        let isRunning: Bool
        if let bundleId = status.bundleIdentifier, !bundleId.isEmpty {
            isRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == bundleId
            }
        } else {
            isRunning = false
        }
        
        guard isRunning else {
            musicRunning = false
            reset()
            return
        }
        
        musicRunning = true
        
        // Update player state
        let newState: PlayerState = (status.playing ?? false) ? .playing : .paused
        if newState != playerState {
            playerState = newState
        }
        
        // Check if track changed first
        let trackID = status.contentItemIdentifier ?? "0"
        let trackChanged = currentTrackID != trackID
        
        if trackChanged {
            Logger.debug("Track changed to: \(status.title ?? "Unknown") by \(status.artist ?? "Unknown")", log: Logger.playback)
            
            // Track changed - scrobble previous if needed
            if let track = currentTrack, let maxPos = maxPosition {
                let percentPlayed = (maxPos / track.length) * 100
                if percentPlayed >= 95 && !track.scrobbled && track.length >= 30 {
                    if let fn = onScrobbleWanted {
                        DispatchQueue.main.async { fn(track) }
                    }
                }
            }
            
            // Reset position tracking for new track
            let newPosition = status.elapsedTime ?? 0
            lastSnapshotTime = Date()
            lastSnapshotPosition = newPosition
            
            maxPosition = newPosition
            currentPosition = newPosition
            currentTrackID = trackID
            
            let track = try getPlayerTrack(from: status)
            currentTrack = track
            
            if let fn = onTrackChanged {
                DispatchQueue.main.async { fn(track) }
            }
        } else {
            // Same track - update position if changed significantly
            let snapshotPos = status.elapsedTime ?? 0
            
            // Check if we got a fresh snapshot (position changed significantly)
            if abs(snapshotPos - (lastSnapshotPosition ?? 0)) > 0.1 {
                Logger.debug("Fresh snapshot from adapter: \(snapshotPos)s", log: Logger.playback)
                lastSnapshotTime = Date()
                lastSnapshotPosition = snapshotPos
                
                currentPosition = snapshotPos
                if maxPosition == nil || snapshotPos > (maxPosition ?? 0) {
                    maxPosition = snapshotPos
                }
            }
        }
    }
}
