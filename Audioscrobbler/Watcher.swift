import Foundation
import AppKit
import OSAKit

enum ScriptError: Error {
    case initializationError
    case internalError(String)
}

class Watcher: ObservableObject {
    @Published var currentTrackID: Int32?
    @Published var currentTrack: Track?
    @Published var currentPosition: Double?
    @Published var maxPosition: Double?
    @Published var musicRunning = false
    @Published var playerState: PlayerState = .unknown
    @Published var running = true
    
    private var timer: Timer?
    private let debug: Bool
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
    
    private func log(_ message: String) {
        guard debug else { return }
        print(message)
    }
    
    private func runScript<T>(_ script: String) throws -> T {
        if !isMusicRunning() {
            switch T.self {
            case is String.Type: return "" as! T
            case is Bool.Type: return false as! T
            case is Int32.Type: return 0 as! T
            case is Double.Type: return 0.0 as! T
            case is Data.Type: return Data() as! T
            default: throw ScriptError.initializationError
            }
        }
        
        return try autoreleasepool {
            var error: NSDictionary?
            let scriptObject = OSAScript(source: script)
            let output = scriptObject.executeAndReturnError(&error)
            if error != nil {
                throw ScriptError.internalError(String(describing: error))
            }
            
            switch T.self {
            case is String.Type: return "\(output!.stringValue!)" as! T
            case is Bool.Type: return output!.booleanValue as! T
            case is Int32.Type: return output!.int32Value as! T
            case is Double.Type: return output!.doubleValue as! T
            case is Data.Type: return NSData(data: output!.data) as! T
            default: throw ScriptError.initializationError
            }
        }
    }
    
    private func getPlayerPosition() throws -> Double {
        try runScript("""
            tell application id "com.apple.Music" to get the player position
        """)
    }
    
    private func getPlayerTrack() throws -> Track {
        let name: String = try runScript("""
            tell application id "com.apple.Music" to get the name of the current track
        """)
        let artist: String = try runScript("""
            tell application id "com.apple.Music" to get the artist of the current track
        """)
        let album: String = try runScript("""
            tell application id "com.apple.Music" to get the album of the current track
        """)
        let artwork: Data = try runScript("""
            tell application id "com.apple.Music" to get the data of the first artwork of the current track
        """)
        let length: Double = try runScript("""
            tell application id "com.apple.Music" to get the duration of the current track
        """)
        let year: Int32 = try runScript("""
            tell application id "com.apple.Music" to get the year of the current track
        """)
        
        // Try different property names for loved/favorited across macOS versions
        let lovedPropertyNames = ["favorited", "loved"]
        var loved = false
        for propertyName in lovedPropertyNames {
            do {
                loved = try runScript("""
                    tell application "Music" to get \(propertyName) of the current track
                """)
                break
            } catch {
                continue
            }
        }
        
        let startedAt = Int32(Date().timeIntervalSince1970 - (currentPosition ?? 0))
        return Track(
            artist: artist,
            album: album,
            name: name,
            length: length,
            artwork: artwork,
            year: year,
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
        setState { self.musicRunning = isRunning }
        log("musicRunning = \(musicRunning)")
        
        guard musicRunning else {
            reset()
            return
        }
        
        // Get player state
        let stringState: String = try runScript("""
            tell application id "com.apple.Music" to get player state
        """)
        
        let newState: PlayerState = switch stringState {
        case "kPSP": .playing
        case "kPSp": .paused
        case "kPSS": .stopped
        case "kPSF", "kPSR": .seeking
        default: .unknown
        }
        
        if newState == .stopped {
            reset()
            return
        }
        
        if newState != playerState {
            setState { self.playerState = newState }
        }
        
        log("playerState = \(playerState)")
        
        // Get current position
        let rawCurrentPosition: Data = try runScript("""
            tell application id "com.apple.Music" to get the player position
        """)
        
        if rawCurrentPosition.count == 4 && rawCurrentPosition.starts(with: [103, 110, 115, 109]) {
            reset()
            return
        }
        
        let position = rawCurrentPosition.withUnsafeBytes { $0.load(as: Double.self) }
        setState {
            self.currentPosition = position
            if self.maxPosition == nil || position > (self.maxPosition ?? 0) {
                self.maxPosition = position
            }
        }
        
        log("currentPosition = \(position)")
        
        // Get track ID
        let trackID: Int32 = try runScript("""
            tell application id "com.apple.Music" to get the database ID of the current track
        """)
        
        guard currentTrackID != trackID else {
            return
        }
        
        // Track changed - check if we should scrobble the previous one
        if let track = currentTrack, let maxPos = maxPosition {
            let percentPlayed = (maxPos / track.length) * 100
            if percentPlayed >= 95 && !track.scrobbled && track.length >= 30 {
                if let fn = onScrobbleWanted {
                    DispatchQueue.main.async {
                        fn(track)
                    }
                }
                log("Scrobble: \(track)")
            }
        }
        
        setState { self.maxPosition = 0 }
        setState { self.currentTrackID = trackID }
        
        let track = try getPlayerTrack()
        setState { self.currentTrack = track }
        log("Current track: \(track.description)")
        
        if let fn = onTrackChanged {
            DispatchQueue.main.async {
                fn(track)
            }
        }
    }
}
