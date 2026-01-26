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
    @Published var currentPosition: Double?
    @Published var maxPosition: Double?
    @Published var musicRunning = false
    @Published var playerState: PlayerState = .unknown
    @Published var running = true
    @Published var currentBundleIdentifier: String?

    private let mediaController = MediaController()
    private var lastSnapshotTime: Date?
    private var lastSnapshotPosition: Double?
    private var currentStatus: MediaControlStatus?
    private var positionTimer: Timer?
    private var lastSeekTime: Date?
    private var pendingResetWorkItem: DispatchWorkItem?
    private let processingQueue = DispatchQueue(label: "com.scroblebler.watcher.processing", qos: .userInitiated)

    // Artwork conversion cache
    private var artworkCache: [String: String] = [:]
    private var lastArtworkHash: Int?

    var onTrackChanged: ((Listen) -> Void)?
    var onScrobbleWanted: ((Listen) -> Void)?

    init(debug: Bool = false) {
        setupMediaController()
        MediaControl.setup(controller: mediaController, watcher: self)
    }

    private func setupMediaController() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            guard let self = self else { return }

            if let trackInfo = trackInfo {
                // Cancel any pending "no media" reset – NIL events are often transient.
                self.pendingResetWorkItem?.cancel()
                self.pendingResetWorkItem = nil

                // Process track info on serial queue to prevent race conditions
                self.processingQueue.async {
                    self.handleTrackInfo(trackInfo)
                }
            } else {
                // MediaRemote can emit transient NIL during track transitions or PID resolution.
                // Debounce before clearing UI state to avoid flicker / stale resets.
                self.scheduleResetAfterNoMedia()
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
        Task { @MainActor in
            if let listen = ListenStore.shared.currentListen, let fn = onTrackChanged {
                DispatchQueue.main.async {
                    fn(listen)
                }
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
              let lastPos = lastSnapshotPosition else {
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastTime)
        let rate = status.playbackRate ?? 1.0
        let rawPosition = lastPos + (elapsed * rate)
        let position = status.duration.map { min(rawPosition, $0) } ?? rawPosition

        setState {
            self.currentPosition = position
            if self.maxPosition == nil || position > (self.maxPosition ?? 0) {
                self.maxPosition = status.duration.map { min(position, $0) } ?? position
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

    private func convertArtworkToBase64(_ artwork: NSImage) -> String? {
        guard let tiffData = artwork.tiffRepresentation else { return nil }

        let artworkHash = String(tiffData.hashValue)
        if let cached = artworkCache[artworkHash] {
            return cached
        }

        guard let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            return nil
        }

        let base64 = pngData.base64EncodedString()
        artworkCache[artworkHash] = base64
        return base64
    }

    private func handleTrackInfo(_ trackInfo: MediaRemoteAdapter.TrackInfo) {
        let payload = trackInfo.payload

        // MediaRemote sometimes fails to resolve the application PID/bundle id for an event.
        // Preserve the last known bundle id so we don't reset to "nothing playing".
        let resolvedBundleIdentifier = payload.bundleIdentifier
            ?? currentStatus?.bundleIdentifier
            ?? currentBundleIdentifier

        // Create unique identifier from artist + title + album to properly detect track changes
        let trackIdentifier = "\(payload.artist ?? "")|\(payload.title ?? "")|\(payload.album ?? "")"
        let trackChanged = currentStatus?.contentItemIdentifier != trackIdentifier

        // Determine artwork: convert if track changed, otherwise reuse
        let artworkData: String?
        if trackChanged {
            artworkData = payload.artwork.flatMap { convertArtworkToBase64($0) }
        } else {
            artworkData = currentStatus?.artworkData
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
            contentItemIdentifier: trackIdentifier,
            trackNumber: nil,
            totalTrackCount: nil,
            bundleIdentifier: resolvedBundleIdentifier
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
        guard let title = status.title, !title.isEmpty else {
            Logger.debug("Skipping incomplete track data (title: \(status.title ?? "nil"))", log: Logger.playback)
            return
        }

        Task { @MainActor in
            try? self.processStatus(status)
        }
    }

    private func scheduleResetAfterNoMedia(delay: TimeInterval = 0.75) {
        pendingResetWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.currentStatus = nil
            self.musicRunning = false
            self.playerState = .stopped
            self.reset()
        }

        pendingResetWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func getPlayerTrack(from status: MediaControlStatus) throws -> Listen {
        let elapsedTime = status.elapsedTime ?? 0
        let startedAt = Int32(Date().timeIntervalSince1970 - elapsedTime)

        let artist = status.artist ?? ""
        let album = status.album ?? ""
        let title = status.title ?? ""

        // Create Listen from media player status
        return Listen(
            id: nil,
            track: title,
            artist: artist,
            album: album,
            year: nil,
            duration: status.duration ?? 0,
            listenedAt: Int(startedAt),
            services: [:],
            loved: false,
            releaseMbid: nil,
            sourceBundle: status.bundleIdentifier,
            createdAt: Date.nowISO8601(),
            updatedAt: Date.nowISO8601()
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
        Task { @MainActor in
            currentTrackID = nil
            currentPosition = nil
            maxPosition = nil
            currentBundleIdentifier = nil
            ListenStore.shared.clearCurrentListen()
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
            // If MediaRemote couldn't resolve bundle id for this event, assume "still running".
            // We have now-playing metadata, so clearing UI here causes frequent false negatives.
            isRunning = true
        }

        guard isRunning else {
            musicRunning = false
            reset()
            return
        }

        musicRunning = true

        // Only overwrite when we actually have a bundle id.
        if let bundleId = status.bundleIdentifier, !bundleId.isEmpty {
            currentBundleIdentifier = bundleId
        }

        // Update player state
        let newState: PlayerState = (status.playing ?? false) ? .playing : .paused
        if newState != playerState {
            playerState = newState
        }

        // Check if track changed first
        let trackID = status.contentItemIdentifier ?? "0"
        let trackChanged = currentTrackID != trackID

        if trackChanged {
            Logger.info("Track changed: \(status.title ?? "Unknown") by \(status.artist ?? "Unknown")", log: Logger.playback)

            // Clear artwork cache on track change to prevent memory buildup
            artworkCache.removeAll()

            // Track changed - scrobble previous if needed
            if let listen = ListenStore.shared.currentListen, let maxPos = maxPosition {
                guard listen.duration > 0 else {
                    // Unknown duration (streams / some players). Don't attempt a percent-based scrobble.
                    return
                }

                let percentPlayed = (maxPos / listen.duration) * 100
                if percentPlayed >= 95 && listen.id == nil && listen.duration >= 30 {
                    if let fn = onScrobbleWanted {
                        DispatchQueue.main.async { fn(listen) }
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

            let listen = try getPlayerTrack(from: status)

            // Route through ListenStore (single source of truth)
            ListenStore.shared.setCurrentListen(listen)

            if let fn = onTrackChanged {
                DispatchQueue.main.async { fn(listen) }
            }
        } else {
            // Same track - check if artwork arrived late
            let hasArtwork = status.artworkData != nil
            let currentHasArtwork = (ListenStore.shared.currentListen?.releaseMbid?.count ?? 0) > 0

            if hasArtwork && !currentHasArtwork {
                let listen = try getPlayerTrack(from: status)
                ListenStore.shared.updateCurrentListen(listen)
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
                    currentPosition = status.duration.map { min(snapshotPos, $0) } ?? snapshotPos
                    if maxPosition == nil || snapshotPos > (maxPosition ?? 0) {
                        maxPosition = status.duration.map { min(snapshotPos, $0) } ?? snapshotPos
                    }
                }
                // Otherwise ignore stale update
            } else {
                // Normal operation - check if we got a fresh snapshot (position changed significantly)
                if abs(snapshotPos - (lastSnapshotPosition ?? 0)) > 0.1 {
                    lastSnapshotTime = Date()
                    lastSnapshotPosition = snapshotPos

                    currentPosition = status.duration.map { min(snapshotPos, $0) } ?? snapshotPos
                    if maxPosition == nil || snapshotPos > (maxPosition ?? 0) {
                        maxPosition = status.duration.map { min(snapshotPos, $0) } ?? snapshotPos
                    }
                }
            }
        }
    }
}
