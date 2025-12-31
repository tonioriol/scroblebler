import Foundation
import AppKit
import OSAKit

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

struct StreamUpdate: Codable {
    let type: String
    let diff: Bool
    let payload: MediaControlStatus
}

class Watcher: ObservableObject {
    @Published var currentTrackID: String?
    @Published var currentTrack: Track?
    @Published var currentPosition: Double?
    @Published var maxPosition: Double?
    @Published var musicRunning = false
    @Published var playerState: PlayerState = .unknown
    @Published var running = true
    
    private var streamProcess: Process?
    private var streamPipe: Pipe?
    private var lastSnapshotTime: Date?
    private var lastSnapshotPosition: Double?
    private var currentStatus: MediaControlStatus?
    private var positionTimer: Timer?
    private var lineBuffer = ""
    
    var onTrackChanged: ((Track) -> Void)?
    var onScrobbleWanted: ((Track) -> Void)?
    
    init(debug: Bool = false) {
    }
    
    func start() {
        startStreaming()
        startPositionTimer()
    }
    
    func stop() {
        running = false
        stopStreaming()
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
    
    private func startStreaming() {
        guard let paths = getMediaRemoteAdapterPaths() else {
            Logger.error("MediaRemote adapter not found", log: Logger.playback)
            return
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            paths.script,
            paths.framework,
            paths.testClient,
            "stream",
            "--no-diff",
            "--debounce=100"
        ]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        streamProcess = process
        streamPipe = pipe
        
        // Handle output in background thread - buffer lines to handle split JSON
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self, self.running else { return }
            
            let data = handle.availableData
            if data.isEmpty {
                Logger.debug("Stream ended", log: Logger.playback)
                return
            }
            
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            
            // Add to buffer and process complete lines
            self.lineBuffer += chunk
            let lines = self.lineBuffer.components(separatedBy: "\n")
            
            // Keep the last incomplete line in buffer
            self.lineBuffer = lines.last ?? ""
            
            // Process all complete lines
            for line in lines.dropLast() {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                
                if let jsonData = trimmed.data(using: .utf8) {
                    self.handleStreamUpdate(jsonData)
                }
            }
        }
        
        // Handle errors
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let errorStr = String(data: data, encoding: .utf8) {
                Logger.error("MediaRemote adapter error: \(errorStr)", log: Logger.playback)
            }
        }
        
        // Handle process termination
        process.terminationHandler = { [weak self] process in
            Logger.debug("Stream process terminated with status: \(process.terminationStatus)", log: Logger.playback)
            if let self = self, self.running {
                // Restart after a delay if we're still supposed to be running
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    if self.running {
                        Logger.debug("Restarting stream", log: Logger.playback)
                        self.startStreaming()
                    }
                }
            }
        }
        
        do {
            try process.run()
            Logger.debug("Started MediaRemote adapter stream", log: Logger.playback)
        } catch {
            Logger.error("Failed to start stream: \(error.localizedDescription)", log: Logger.playback)
        }
    }
    
    private func stopStreaming() {
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        streamProcess?.terminate()
        streamProcess = nil
        streamPipe = nil
    }
    
    private func handleStreamUpdate(_ data: Data) {
        do {
            let update = try JSONDecoder().decode(StreamUpdate.self, from: data)
            
            // Skip empty payloads (no keys means no media playing)
            let hasAnyData = update.payload.title != nil ||
                            update.payload.bundleIdentifier != nil ||
                            update.payload.playing != nil
            
            guard hasAnyData else {
                // No media playing
                currentStatus = nil
                Task { @MainActor in
                    self.reset()
                }
                return
            }
            
            // Handle missing or incomplete duration - preserve from previous if same track
            var newStatus = update.payload
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
            
        } catch {
            Logger.error("Failed to decode stream update: \(error.localizedDescription)", log: Logger.playback)
            if let jsonString = String(data: data, encoding: .utf8) {
                Logger.debug("Failed JSON: \(jsonString)", log: Logger.playback)
            }
        }
    }
    
    
    private func getMediaRemoteAdapterPaths() -> (script: String, framework: String, testClient: String)? {
        guard let resourcePath = Bundle.main.resourceURL?.appendingPathComponent("mediaremote-adapter") else {
            return nil
        }
        
        let scriptPath = resourcePath.appendingPathComponent("bin/mediaremote-adapter.pl").path
        let frameworkPath = resourcePath.appendingPathComponent("build/MediaRemoteAdapter.framework").path
        let testClientPath = resourcePath.appendingPathComponent("build/MediaRemoteAdapterTestClient").path
        
        let fm = FileManager.default
        guard fm.fileExists(atPath: scriptPath),
              fm.fileExists(atPath: frameworkPath),
              fm.fileExists(atPath: testClientPath) else {
            return nil
        }
        
        return (scriptPath, frameworkPath, testClientPath)
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
        let isRunning = isMusicRunning()
        
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
