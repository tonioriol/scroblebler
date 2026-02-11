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
    private var seekTargetPosition: Double?
    private var currentStatus: MediaControlStatus?
    private var positionTimer: Timer?
    private var lastSeekTime: Date?
    private var pendingResetWorkItem: DispatchWorkItem?
    private var pendingSnapshotRefreshItems: [DispatchWorkItem] = []
    private let processingQueue = DispatchQueue(label: "com.scroblebler.watcher.processing", qos: .userInitiated)

    // Artwork conversion cache
    private var artworkCache: [String: String] = [:]
    private var lastArtworkHash: Int?
    private var lastUIUpdateSignature: String?
    private var pendingArtworkPollItems: [DispatchWorkItem] = []
    private var currentArtworkPollIdentity: String?
    private var playbackEventSequence: Int = 0
    private var lastTrackChangeTime: Date?
    private var previousTrackID: String?
    private let verboseSnapshotLogs = false
    private let enableAppleScriptDiagnostics = false

    var onTrackChanged: ((Listen) -> Void)?
    var onScrobbleWanted: ((Listen) -> Void)?

    init(debug: Bool = false) {
        setupMediaController()
        MediaControl.setup(controller: mediaController, watcher: self)
    }

    private func setupMediaController() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            guard let self = self else { return }
            self.playbackEventSequence += 1
            let eventId = self.playbackEventSequence

            if let trackInfo = trackInfo {
                // Cancel any pending "no media" reset – NIL events are often transient.
                self.pendingResetWorkItem?.cancel()
                self.pendingResetWorkItem = nil

                let payload = trackInfo.payload
                Logger.debug(
                    "MR_EVENT #\(eventId): title='\(payload.title ?? "")' artist='\(payload.artist ?? "")' album='\(payload.album ?? "")' playing=\(payload.isPlaying.map(String.init(describing:)) ?? "nil") rate=\(payload.playbackRate.map(String.init(describing:)) ?? "nil") elapsed=\(payload.currentElapsedTime.map { String(format: "%.3f", $0) } ?? "nil") durMicros=\(payload.durationMicros.map(String.init(describing:)) ?? "nil") bundle='\(payload.bundleIdentifier ?? "")'",
                    log: Logger.playback
                )

                // Process track info on serial queue to prevent race conditions
                self.processingQueue.async {
                    self.handleTrackInfo(trackInfo)
                }
            } else {
                Logger.debug("MR_EVENT #\(eventId): NIL", log: Logger.playback)
                // MediaRemote can emit transient NIL during track transitions or PID resolution.
                // Debounce before clearing UI state to avoid flicker / stale resets.
                self.scheduleResetAfterNoMedia()
            }

            if self.enableAppleScriptDiagnostics {
                self.logAppleMusicSnapshot(context: "event_\(eventId)")
            }
        }

        mediaController.onPlaybackTimeUpdate = { [weak self] elapsedTime in
            guard let self = self else { return }

            self.lastSnapshotTime = Date()
            self.lastSnapshotPosition = elapsedTime

            let capped = self.currentStatus?.duration.map { min(elapsedTime, $0) } ?? elapsedTime
            self.setState {
                self.currentPosition = capped
                if self.maxPosition == nil || capped > (self.maxPosition ?? 0) {
                    self.maxPosition = capped
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
        running = true
        mediaController.startListening()
        startPositionTimer()
        requestCurrentSnapshotBurst(reason: "watcher_start")
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
        pendingResetWorkItem?.cancel()
        pendingResetWorkItem = nil
        pendingSnapshotRefreshItems.forEach { $0.cancel() }
        pendingSnapshotRefreshItems.removeAll()
        pendingArtworkPollItems.forEach { $0.cancel() }
        pendingArtworkPollItems.removeAll()
        currentArtworkPollIdentity = nil
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
        seekTargetPosition = position

        // Cap position at duration if available
        let cappedPosition = currentStatus?.duration.map { min(position, $0) } ?? position

        setState {
            self.currentPosition = cappedPosition
            if self.maxPosition == nil || cappedPosition > (self.maxPosition ?? 0) {
                self.maxPosition = cappedPosition
            }
        }

        requestCurrentSnapshotBurst(reason: "seek")
    }

    func notifyCommandSent(_ command: MediaCommand) {
        Logger.debug("UI_COMMAND: \(command)", log: Logger.playback)

        // Optimistic UI update for play/pause/stop so the button reflects instantly.
        // The real state will arrive via MR_EVENT or the delayed snapshot burst.
        setState {
            switch command {
            case .play:
                self.playerState = .playing
                self.musicRunning = true
            case .pause:
                self.playerState = .paused
            case .togglePlayPause:
                if self.playerState == .playing {
                    self.playerState = .paused
                } else {
                    self.playerState = .playing
                    self.musicRunning = true
                }
            case .stop:
                self.playerState = .stopped
                self.musicRunning = false
            case .nextTrack, .previousTrack:
                self.musicRunning = true
            }
        }

        guard running else { return }
        requestCurrentSnapshotBurst(reason: "command_\(command.rawValue)")
    }

    private func snapshotBurstDelays(reason: String) -> [TimeInterval] {
        if reason == "command_4" || reason == "command_5" {
            // Track changes take time: Perl subprocess + Music app transition.
            return [0.35, 0.8, 1.5]
        }
        if reason.hasPrefix("command_") {
            // Play/pause/stop: command goes through Perl subprocess (~200-500ms).
            // Snapshot must fire AFTER the command has propagated to MediaRemote.
            return [0.4, 0.9]
        }
        if reason == "seek" {
            return [0.15, 0.5]
        }
        if reason == "watcher_start" {
            return [0.0, 0.30]
        }
        return [0.0, 0.3]
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

    private func requestCurrentSnapshotBurst(reason: String) {
        pendingSnapshotRefreshItems.forEach { $0.cancel() }
        pendingSnapshotRefreshItems.removeAll()

        let delays = snapshotBurstDelays(reason: reason)
        for delay in delays {
            let item = DispatchWorkItem { [weak self] in
                self?.requestCurrentSnapshot(reason: reason)
            }
            pendingSnapshotRefreshItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    private func requestCurrentSnapshot(reason: String) {
        guard running else { return }

        mediaController.getTrackInfo { [weak self] trackInfo in
            guard let self = self else { return }
            guard self.running else { return }

            if let trackInfo = trackInfo {
                self.pendingResetWorkItem?.cancel()
                self.pendingResetWorkItem = nil

                let payload = trackInfo.payload
                let shouldLogGet = self.verboseSnapshotLogs || reason.hasPrefix("command_") || reason == "watcher_start"
                if shouldLogGet {
                    Logger.debug(
                        "MR_GET(\(reason)): title='\(payload.title ?? "")' artist='\(payload.artist ?? "")' album='\(payload.album ?? "")' playing=\(payload.isPlaying.map(String.init(describing:)) ?? "nil") rate=\(payload.playbackRate.map(String.init(describing:)) ?? "nil") elapsed=\(payload.currentElapsedTime.map { String(format: "%.3f", $0) } ?? "nil") bundle='\(payload.bundleIdentifier ?? "")'",
                        log: Logger.playback
                    )
                }

                self.processingQueue.async {
                    self.handleTrackInfo(trackInfo)
                }
            } else {
                if self.verboseSnapshotLogs || reason.hasPrefix("command_") {
                    Logger.debug("Snapshot refresh returned NIL (reason=\(reason))", log: Logger.playback)
                }
            }

            if self.enableAppleScriptDiagnostics,
               (self.verboseSnapshotLogs || reason.hasPrefix("command_") || reason == "watcher_start") {
                self.logAppleMusicSnapshot(context: "mr_get_\(reason)")
            }
        }
    }

    private func logAppleMusicSnapshot(context: String) {
        DispatchQueue.global(qos: .utility).async {
            let script = #"""
tell application "Music"
if not running then
    return "running=false"
end if
set pstate to (get player state) as text
set t to ""
set a to ""
set al to ""
set pos to 0
set dur to 0
try
    set t to (name of current track)
    set a to (artist of current track)
    set al to (album of current track)
    set pos to (player position)
    set dur to (duration of current track)
end try
return "running=true state=" & pstate & " title=" & t & " artist=" & a & " album=" & al & " pos=" & (pos as text) & " dur=" & (dur as text)
end tell
"""#

            var error: NSDictionary?
            guard let scriptObject = NSAppleScript(source: script) else {
                Logger.debug("AS_SNAPSHOT(\(context)): failed to create script", log: Logger.playback)
                return
            }
            let result = scriptObject.executeAndReturnError(&error)
            if let error {
                let msg = error["NSAppleScriptErrorMessage"] as? String ?? "unknown"
                Logger.debug("AS_SNAPSHOT(\(context)): error='\(msg)'", log: Logger.playback)
                return
            }

            Logger.debug("AS_SNAPSHOT(\(context)): \(result.stringValue ?? "")", log: Logger.playback)
        }
    }

    private func clearArtworkPollTasks() {
        pendingArtworkPollItems.forEach { $0.cancel() }
        pendingArtworkPollItems.removeAll()
        currentArtworkPollIdentity = nil
    }

    @MainActor
    private func maybeScheduleArtworkPoll(for status: MediaControlStatus, identity: String) {
        guard running else { return }

        let alreadyHasArtwork = (status.artworkData?.isEmpty == false)
            || (ListenStore.shared.currentListen?.artwork?.isEmpty == false)
        if alreadyHasArtwork {
            return
        }

        if currentArtworkPollIdentity == identity, !pendingArtworkPollItems.isEmpty {
            return
        }

        clearArtworkPollTasks()
        currentArtworkPollIdentity = identity

        // Short and bounded poll: artwork usually arrives shortly after metadata.
        let pollDelays: [TimeInterval] = [0.18, 0.45, 0.9, 1.4]
        for delay in pollDelays {
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                guard self.running else { return }
                guard self.currentTrackID == identity else { return }

                let hasArtworkNow = (self.currentStatus?.artworkData?.isEmpty == false)
                    || (ListenStore.shared.currentListen?.artwork?.isEmpty == false)
                if hasArtworkNow {
                    self.clearArtworkPollTasks()
                    return
                }

                self.requestCurrentSnapshot(reason: "artwork_poll")
            }
            pendingArtworkPollItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
    }

    @MainActor
    private func updateListenIfNeeded(_ listen: Listen) {
        let current = ListenStore.shared.currentListen

        let changed: Bool = {
            guard let current else { return true }
            if current.track != listen.track { return true }
            if current.artist != listen.artist { return true }
            if current.album != listen.album { return true }
            if current.sourceBundle != listen.sourceBundle { return true }
            if abs(current.duration - listen.duration) > 0.001 { return true }
            if current.releaseMbid != listen.releaseMbid { return true }
            if current.imageUrl != listen.imageUrl { return true }

            let currentArtworkSize = current.artwork?.count ?? 0
            let newArtworkSize = listen.artwork?.count ?? 0
            if currentArtworkSize != newArtworkSize { return true }

            return false
        }()

        guard changed else { return }

        let signature = [
            listen.artist,
            listen.track,
            listen.album,
            listen.sourceBundle ?? "",
            String(Int((listen.duration * 10).rounded())),
            listen.releaseMbid ?? "",
            listen.imageUrl ?? "",
            String(listen.artwork?.count ?? 0)
        ].joined(separator: "|")

        guard signature != lastUIUpdateSignature else { return }
        lastUIUpdateSignature = signature

        if current == nil {
            ListenStore.shared.setCurrentListen(listen)
        } else {
            ListenStore.shared.updateCurrentListen(listen)
        }
    }

    @MainActor
    private func enrichListenWithLocalArtworkHints(_ listen: Listen) -> Listen {
        var enriched = listen

        guard let existing = ListenStore.shared.findListen(artist: listen.artist, track: listen.track) else {
            return enriched
        }

        if enriched.releaseMbid == nil {
            enriched.releaseMbid = existing.releaseMbid
        }
        if enriched.imageUrl == nil {
            enriched.imageUrl = existing.imageUrl
        }
        if enriched.artwork == nil {
            enriched.artwork = existing.artwork
        }

        return enriched
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

        let isSameTrackAsCurrent = (currentStatus?.contentItemIdentifier == trackIdentifier)

        // Determine artwork:
        // - Use fresh artwork when present.
        // - For SAME track, fall back to previous artwork to avoid flicker.
        // - For DIFFERENT track, do NOT carry over old artwork (wrong album art bug).
        let freshArtwork: String? = payload.artwork.flatMap { convertArtworkToBase64($0) }
        let artworkData: String? = freshArtwork ?? (isSameTrackAsCurrent ? currentStatus?.artworkData : nil)

        // Convert microseconds to seconds
        let durationSeconds = (payload.durationMicros ?? 0) / 1_000_000.0

        let hasElapsedInPayload = payload.currentElapsedTime != nil || payload.elapsedTimeMicros != nil
        let elapsedTimeSeconds = payload.currentElapsedTime ?? ((payload.elapsedTimeMicros ?? 0) / 1_000_000.0)
        let effectiveElapsedTime: Double? = hasElapsedInPayload
            ? elapsedTimeSeconds
            : (isSameTrackAsCurrent ? currentStatus?.elapsedTime : nil)

        let effectivePlaying = payload.isPlaying ?? (isSameTrackAsCurrent ? currentStatus?.playing : nil)
        let effectivePlaybackRate = payload.playbackRate ?? (isSameTrackAsCurrent ? currentStatus?.playbackRate : nil)

        let status = MediaControlStatus(
            title: payload.title,
            artist: payload.artist,
            album: payload.album,
            artworkData: artworkData,
            duration: durationSeconds > 0 ? durationSeconds : nil,
            playing: effectivePlaying,
            playbackRate: effectivePlaybackRate,
            elapsedTime: effectiveElapsedTime,
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

        // Reject stale events that would revert to a track we already moved past.
        // When rapidly skipping tracks, late MR_EVENTs for the old track arrive after
        // a snapshot has already established the new track.
        if let currentID = currentTrackID, let prevID = previousTrackID,
           let changeTime = lastTrackChangeTime,
           Date().timeIntervalSince(changeTime) < 3.0 {
            let incomingIdentity: String = {
                let baseID = newStatus.contentItemIdentifier ?? ""
                let metaID = "\(newStatus.title ?? "")|\(newStatus.artist ?? "")|\(newStatus.album ?? "")"
                return baseID.isEmpty ? metaID : "\(baseID)|\(metaID)"
            }()

            // If this event matches the PREVIOUS track (not current), it's stale.
            if incomingIdentity != currentID && incomingIdentity == prevID {
                Logger.debug("Rejecting stale event for '\(newStatus.title ?? "")' — already moved to '\(currentStatus?.title ?? "")'", log: Logger.playback)
                // Still update play state from this event (it may carry correct play/pause info)
                if let playing = newStatus.playing {
                    Task { @MainActor in
                        let newState: PlayerState = playing ? .playing : .paused
                        if newState != self.playerState {
                            self.playerState = newState
                        }
                    }
                }
                return
            }
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

    private func scheduleResetAfterNoMedia(delay: TimeInterval = 0.45) {
        pendingResetWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.running else { return }

            // Confirm with one direct snapshot before clearing UI, because MediaRemote NIL can be transient.
            self.mediaController.getTrackInfo { [weak self] trackInfo in
                guard let self = self else { return }
                guard self.running else { return }

                if let trackInfo = trackInfo {
                    self.pendingResetWorkItem?.cancel()
                    self.pendingResetWorkItem = nil
                    self.processingQueue.async {
                        self.handleTrackInfo(trackInfo)
                    }
                    return
                }

                Logger.debug("Confirmed NIL after debounce -> reset", log: Logger.playback)
                self.logAppleMusicSnapshot(context: "confirmed_nil_reset")

                self.currentStatus = nil
                self.musicRunning = false
                self.playerState = .stopped
                self.reset()
            }
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

        // Convert artwork (base64 PNG) into bytes for UI rendering.
        // This is ephemeral (not persisted).
        let artworkData: Data? = status.artworkData
            .flatMap { Data(base64Encoded: $0) }

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
            imageUrl: nil,
            artwork: artworkData,
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
            lastUIUpdateSignature = nil
            previousTrackID = nil
            lastTrackChangeTime = nil
            clearArtworkPollTasks()
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

        // Update player state.
        // If we can't determine play/pause, keep the previous state to avoid flip-flopping.
        if let playing = status.playing {
            let newState: PlayerState = playing ? .playing : .paused
            if newState != playerState {
                playerState = newState
            }
        }

        // Check if track changed first
        // Some players keep `contentItemIdentifier` stable across track transitions.
        // Use a composite identity so artwork/metadata refresh correctly.
        let baseID = status.contentItemIdentifier ?? ""
        let metaID = "\(status.title ?? "")|\(status.artist ?? "")|\(status.album ?? "")"
        let identity = baseID.isEmpty ? metaID : "\(baseID)|\(metaID)"
        let trackChanged = currentTrackID != identity

        if trackChanged {
            let now = Date()

            // Record previous track so we can reject stale events for it
            previousTrackID = currentTrackID
            lastTrackChangeTime = now

            Logger.info("Track changed: \(status.title ?? "Unknown") by \(status.artist ?? "Unknown")", log: Logger.playback)

            // Clear artwork cache on track change to prevent memory buildup
            artworkCache.removeAll()
            clearArtworkPollTasks()

            // Track changed - scrobble previous if needed
            if let listen = ListenStore.shared.currentListen,
               let maxPos = maxPosition,
               listen.duration > 0 {
                let percentPlayed = (maxPos / listen.duration) * 100
                if percentPlayed >= 95 && listen.id == nil && listen.duration >= 30 {
                    if let fn = onScrobbleWanted {
                        DispatchQueue.main.async { fn(listen) }
                    }
                }
            }

            // Reset position tracking for new track
            let newPosition = status.elapsedTime ?? 0
            lastSnapshotTime = now
            lastSnapshotPosition = newPosition

            maxPosition = newPosition
            currentPosition = newPosition
            currentTrackID = identity

            let listen = enrichListenWithLocalArtworkHints(try getPlayerTrack(from: status))

            // Route through ListenStore only when metadata/artwork actually changed
            updateListenIfNeeded(listen)
            maybeScheduleArtworkPoll(for: status, identity: identity)

            if let fn = onTrackChanged {
                DispatchQueue.main.async { fn(listen) }
            }
        } else {
            // Same track - check if artwork arrived late
            let hasArtwork = (status.artworkData?.isEmpty == false)
            let currentHasArtwork = (ListenStore.shared.currentListen?.artwork?.isEmpty == false)

            if hasArtwork && !currentHasArtwork {
                let listen = try getPlayerTrack(from: status)
                updateListenIfNeeded(listen)
                clearArtworkPollTasks()
            }

            // Keep metadata fresh even if the track identity didn't change (some players update
            // title/album/bundle id late, or reuse IDs when starting playback via scripting).
            if let current = ListenStore.shared.currentListen {
                let sameIdentity = current.canonicalKey == ListenIdentity.key(artist: status.artist ?? "", track: status.title ?? "")
                let titleChanged = (status.title ?? "") != current.track
                let artistChanged = (status.artist ?? "") != current.artist
                let albumChanged = (status.album ?? "") != current.album
                let bundleChanged = (status.bundleIdentifier ?? "") != (current.sourceBundle ?? "")
                if sameIdentity || titleChanged || artistChanged || albumChanged || bundleChanged {
                    let updated = enrichListenWithLocalArtworkHints(try getPlayerTrack(from: status))
                    updateListenIfNeeded(updated)
                    if (updated.artwork?.isEmpty ?? true) {
                        maybeScheduleArtworkPoll(for: status, identity: identity)
                    } else {
                        clearArtworkPollTasks()
                    }
                }
            }

            // Update position if changed significantly
            let snapshotPos = status.elapsedTime ?? 0

            let shouldIgnoreStaleSeekSnapshot: Bool = {
                guard let seekTarget = seekTargetPosition else { return false }

                // Snapshot converged to seek target; resume normal tracking.
                if abs(snapshotPos - seekTarget) <= 2.0 {
                    seekTargetPosition = nil
                    return false
                }

                // Shortly after seek, ignore backward/stale snapshots that contradict our target.
                if let seekTime = lastSeekTime,
                   Date().timeIntervalSince(seekTime) < 3.0,
                   snapshotPos < (seekTarget - 2.0) {
                    return true
                }

                // Give up on strict seek tracking after a while.
                if let seekTime = lastSeekTime,
                   Date().timeIntervalSince(seekTime) >= 3.0 {
                    seekTargetPosition = nil
                }

                return false
            }()

            if shouldIgnoreStaleSeekSnapshot {
                return
            }

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
