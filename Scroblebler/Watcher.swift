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
    private let processingQueue = DispatchQueue(label: "com.scroblebler.watcher.processing", qos: .userInitiated)
    
    var onTrackChanged: ((Track) -> Void)?
    var onScrobbleWanted: ((Track) -> Void)?
    
    init(debug: Bool = false) {
        setupMediaController()
        MediaControl.setup(controller: mediaController, watcher: self)
    }
    
    private func setupMediaController() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            guard let self = self else { return }
            
            if let trackInfo = trackInfo {
                // Process track info on serial queue to prevent race conditions
                self.processingQueue.async {
                    self.handleTrackInfo(trackInfo)
                }
            } else {
                // No media playing
                self.currentStatus = nil
                Task { @MainActor in
                    self.reset()
                }
            }
        }
        
        mediaController.onDecodingError = { error, data in
            Logger.error("MediaController JSON decode error: \(error)", log: Logger.playback)
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.debug("Failed JSON: \(jsonString)", log: Logger.playback)
            }
        }
        
        mediaController.onListenerTerminated = { [weak self] in
            Logger.debug("MediaController listener terminated", log: Logger.playback)
            guard let self = self else { return }
            
            if self.running {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
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
    
    func refreshCurrentState() {
        // If we already have a current track, trigger the callback
        // This handles the case where track info arrived before callbacks were set
        if let track = currentTrack, let fn = onTrackChanged {
            DispatchQueue.main.async {
                fn(track)
            }
        }
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
              let lastPos = lastSnapshotPosition,
              let duration = status.duration else {
            return
        }
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)
        let position = min(lastPos + elapsed, duration) // Cap at duration
        
        setState {
            self.currentPosition = position
            if self.maxPosition == nil || position > (self.maxPosition ?? 0) {
                self.maxPosition = min(position, duration) // Cap maxPosition at duration
            }
        }
    }
    
    func notifySeek(to position: Double) {
        lastSeekTime = Date()
        lastSnapshotTime = Date()
        lastSnapshotPosition = position
        
        // Cap position at duration if available
        let cappedPosition = currentStatus?.duration.map { min(position, $0) } ?? position
        
        setState {
            self.currentPosition = cappedPosition
            if self.maxPosition == nil || cappedPosition > (self.maxPosition ?? 0) {
                self.maxPosition = cappedPosition
            }
        }
    }
    
    private func handleTrackInfo(_ trackInfo: MediaRemoteAdapter.TrackInfo) {
        let payload = trackInfo.payload
        
        Logger.debug("handleTrackInfo called for: \(payload.title ?? "Unknown")", log: Logger.playback)
        
        
        // Convert artwork NSImage to base64 if available (on background thread to avoid blocking)
        var artworkData: String?
        if let artwork = payload.artwork {
            Logger.debug("Artwork present, converting to base64...", log: Logger.playback)
            if let tiffData = artwork.tiffRepresentation {
                Logger.debug("Got TIFF data: \(tiffData.count) bytes", log: Logger.playback)
                if let bitmapImage = NSBitmapImageRep(data: tiffData) {
                    Logger.debug("Created bitmap image representation", log: Logger.playback)
                    if let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                        artworkData = pngData.base64EncodedString()
                        Logger.debug("Converted to PNG and base64: \(pngData.count) bytes", log: Logger.playback)
                    } else {
                        Logger.debug("Failed to convert bitmap to PNG", log: Logger.playback)
                    }
                } else {
                    Logger.debug("Failed to create bitmap image from TIFF data", log: Logger.playback)
                }
            } else {
                Logger.debug("Failed to get TIFF representation from artwork", log: Logger.playback)
            }
        } else {
            Logger.debug("No artwork in payload", log: Logger.playback)
        }
        
        // Convert microseconds to seconds
        let durationSeconds = (payload.durationMicros ?? 0) / 1_000_000.0
        let elapsedTimeSeconds = payload.currentElapsedTime ?? ((payload.elapsedTimeMicros ?? 0) / 1_000_000.0)
        
        // Create unique identifier from artist + title + album to properly detect track changes
        let trackIdentifier = "\(payload.artist ?? "")|\(payload.title ?? "")|\(payload.album ?? "")"
        
        let status = MediaControlStatus(
            title: payload.title,
            artist: payload.artist,
            album: payload.album,
            artworkData: artworkData,
            duration: durationSeconds > 0 ? durationSeconds : nil,
            playing: payload.isPlaying,
            playbackRate: payload.playbackRate,
            elapsedTime: elapsedTimeSeconds,
            contentItemIdentifier: trackIdentifier,
            trackNumber: nil,
            totalTrackCount: nil,
            bundleIdentifier: payload.bundleIdentifier
        )
        
        Logger.debug("Status created with artwork: \(artworkData != nil ? "YES" : "NO")", log: Logger.playback)
        
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
    
    private func getPlayerTrack(from status: MediaControlStatus) throws -> Track {
        let artwork = status.artworkData
            .flatMap { Data(base64Encoded: $0) } ?? Data()
        
        Logger.debug("getPlayerTrack: status has artworkData: \(status.artworkData != nil), decoded artwork size: \(artwork.count) bytes", log: Logger.playback)
        
        let elapsedTime = status.elapsedTime ?? 0
        let startedAt = Int32(Date().timeIntervalSince1970 - elapsedTime)
        
        // Skip loved status - it's slow and blocks UI
        let loved = false
        
        // Build Last.fm URLs for now playing tracks
        let artist = status.artist ?? ""
        let album = status.album ?? ""
        let title = status.title ?? ""
        
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? artist
        let encodedAlbum = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? album
        let encodedTrack = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        
        let artistURL = URL(string: "https://www.last.fm/music/\(encodedArtist)")
        let albumURL = URL(string: "https://www.last.fm/music/\(encodedArtist)/\(encodedAlbum)")
        let trackURL = URL(string: "https://www.last.fm/music/\(encodedArtist)/_/\(encodedTrack)")
        
        let track = Track(
            id: UUID(),
            artist: artist,
            album: album,
            name: title,
            timestamp: Int(startedAt),
            duration: status.duration ?? 0,
            sourceService: .lastfm,
            loved: loved,
            playcount: 1,
            scrobbled: false,
            blacklisted: false,
            serviceInfo: [:],
            artwork: artwork,
            artistURL: artistURL,
            albumURL: albumURL,
            trackURL: trackURL,
            imageUrl: nil
        )
        
        Logger.debug("getPlayerTrack: created track with artwork size: \(track.artwork?.count ?? 0) bytes", log: Logger.playback)
        
        return track
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
            Logger.debug("processStatus: Setting currentTrack with artwork size: \(track.artwork?.count ?? 0) bytes", log: Logger.playback)
            currentTrack = track
            
            if let fn = onTrackChanged {
                DispatchQueue.main.async { fn(track) }
            }
        } else {
            // Same track - check if artwork arrived late
            let hasArtwork = status.artworkData != nil
            let currentHasArtwork = (currentTrack?.artwork?.count ?? 0) > 0
            
            if hasArtwork && !currentHasArtwork {
                Logger.debug("Artwork arrived late for same track, updating...", log: Logger.playback)
                let track = try getPlayerTrack(from: status)
                Logger.debug("processStatus: Updating currentTrack with artwork size: \(track.artwork?.count ?? 0) bytes", log: Logger.playback)
                currentTrack = track
            }
            
            // Update position if changed significantly
            let snapshotPos = status.elapsedTime ?? 0
            
            // Ignore stale position updates for 1 second after seeking
            let isInSeekGracePeriod = lastSeekTime.map { Date().timeIntervalSince($0) < 1.0 } ?? false
            if isInSeekGracePeriod {
                // During seek grace period, only accept updates that are close to our expected position
                let expectedPos = lastSnapshotPosition ?? 0
                if abs(snapshotPos - expectedPos) < 2.0 {
                    // Position is close to expected, accept it
                    lastSnapshotTime = Date()
                    lastSnapshotPosition = snapshotPos
                    // Cap position at duration
                    let duration = status.duration ?? Double.infinity
                    currentPosition = min(snapshotPos, duration)
                    if maxPosition == nil || snapshotPos > (maxPosition ?? 0) {
                        maxPosition = min(snapshotPos, duration)
                    }
                }
                // Otherwise ignore stale update
            } else {
                // Normal operation - check if we got a fresh snapshot (position changed significantly)
                if abs(snapshotPos - (lastSnapshotPosition ?? 0)) > 0.1 {
                    Logger.debug("Fresh snapshot from adapter: \(snapshotPos)s", log: Logger.playback)
                    lastSnapshotTime = Date()
                    lastSnapshotPosition = snapshotPos
                    
                    // Cap position at duration
                    let duration = status.duration ?? Double.infinity
                    currentPosition = min(snapshotPos, duration)
                    if maxPosition == nil || snapshotPos > (maxPosition ?? 0) {
                        maxPosition = min(snapshotPos, duration)
                    }
                }
            }
        }
    }
}
