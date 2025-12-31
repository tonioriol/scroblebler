import Foundation

enum MediaCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
    case toggleShuffle = 6
    case toggleRepeat = 7
}

class MediaControl {
    static func send(_ command: MediaCommand) {
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
            "send",
            "\(command.rawValue)"
        ]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                if let errorString = String(data: errorData, encoding: .utf8), !errorString.isEmpty {
                    Logger.error("Media command failed: \(errorString)", log: Logger.playback)
                }
            }
        } catch {
            Logger.error("Failed to send media command: \(error.localizedDescription)", log: Logger.playback)
        }
    }
    
    private static func getMediaRemoteAdapterPaths() -> (script: String, framework: String, testClient: String)? {
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
}
