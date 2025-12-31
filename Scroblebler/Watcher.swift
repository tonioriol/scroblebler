import Foundation
import AppKit
import OSAKit

struct MediaControlStatus: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: String?
    let duration: Double?
    let playing: Bool
    let playbackRate: Double
    let elapsedTime: Double?
    let contentItemIdentifier: String?
    let trackNumber: Int?
    let totalTrackCount: Int?
    let bundleIdentifier: String
    
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
    
    private var timer: Timer?
    private let debug: Bool
    private var lastSnapshotTime: Date?
    private var lastSnapshotPosition: Double?
    var onTrackChanged: ((Track) -> Void)?
    var onScrobbleWanted: ((Track) -> Void)?
    
    init(debug: Bool = false) {
        self.debug = debug
    }
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                try? self?.update()
            }
        }
    }
    
    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
    }
    
    
    private func getMediaControlStatus() throws -> MediaControlStatus? {
        let process = Process()
        
        let possiblePaths = [
            "/opt/homebrew/bin/media-control",
            "/usr/local/bin/media-control",
            "/usr/bin/media-control"
        ]
        
        guard let path = possiblePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            Logger.error("media-control not found", log: Logger.playback)
            return nil
        }
        
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["get"]
        
        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            
            // Read pipes before waiting to avoid deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            process.waitUntilExit()
            
            if !errorData.isEmpty, let errorStr = String(data: errorData, encoding: .utf8) {
                Logger.error("media-control error: \(errorStr)", log: Logger.playback)
            }
            
            guard process.terminationStatus == 0, !data.isEmpty else {
                return nil
            }
            
            return try JSONDecoder().decode(MediaControlStatus.self, from: data)
        } catch {
            Logger.error("media-control failed: \(error.localizedDescription)", log: Logger.playback)
            return nil
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
        let loved = status.bundleIdentifier == "com.apple.Music" ? getLovedStatus() : false
        
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
            DispatchQueue.main.sync {
                changes()
            }
        }
    }
    
    private func reset() {
        DispatchQueue.main.sync {
            currentTrackID = nil
            currentTrack = nil
            currentPosition = nil
            maxPosition = nil
        }
    }
    
    func update() throws {
        let isRunning = isMusicRunning()
        
        guard isRunning else {
            setState { self.musicRunning = false }
            reset()
            return
        }
        
        setState { self.musicRunning = true }
        
        guard let status = try getMediaControlStatus() else {
            reset()
            return
        }
        
        
        // Update player state
        let newState: PlayerState = status.playing ? .playing : .paused
        if newState != playerState {
            setState { self.playerState = newState }
        }
        
        // Check if track changed first
        let trackID = status.contentItemIdentifier ?? "0"
        let trackChanged = currentTrackID != trackID
        
        if trackChanged {
            // Track changed - scrobble previous if needed
            if let track = currentTrack, let maxPos = maxPosition {
                let percentPlayed = (maxPos / track.length) * 100
                if percentPlayed >= 95 && !track.scrobbled && track.length >= 30 {
                    if let fn = onScrobbleWanted {
                        DispatchQueue.main.async { fn(track) }
                    }
                }
            }
            
            // Update track and reset position tracking
            lastSnapshotTime = Date()
            lastSnapshotPosition = status.elapsedTime ?? 0
            
            setState {
                self.maxPosition = 0
                self.currentTrackID = trackID
            }
            
            let track = try getPlayerTrack(from: status)
            setState { self.currentTrack = track }
            
            if let fn = onTrackChanged {
                DispatchQueue.main.async { fn(track) }
            }
        }
        
        // Update position - interpolate if playing, otherwise use snapshot
        let now = Date()
        let snapshotPos = status.elapsedTime ?? 0
        
        // Check if we got a fresh snapshot (position changed)
        if snapshotPos != lastSnapshotPosition {
            Logger.debug("Fresh snapshot from media-control: \(snapshotPos)s", log: Logger.playback)
            lastSnapshotTime = now
            lastSnapshotPosition = snapshotPos
        }
        
        // Calculate interpolated position
        let position: Double
        if status.playing && status.playbackRate > 0,
           let lastTime = lastSnapshotTime,
           let lastPos = lastSnapshotPosition {
            // Interpolate based on time elapsed since last snapshot
            let elapsed = now.timeIntervalSince(lastTime)
            position = lastPos + elapsed
        } else {
            // Use snapshot when paused or no tracking data
            position = snapshotPos
        }
        
        setState {
            self.currentPosition = position
            if self.maxPosition == nil || position > (self.maxPosition ?? 0) {
                self.maxPosition = position
            }
        }
    }
}
