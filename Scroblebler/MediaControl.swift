import Foundation
import MediaRemoteAdapter

enum MediaCommand: Int {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
}

class MediaControl {
    private static weak var controller: MediaController?
    private static weak var watcher: Watcher?
    
    static func setup(controller: MediaController, watcher: Watcher) {
        self.controller = controller
        self.watcher = watcher
    }
    
    static func send(_ command: MediaCommand) {
        guard let controller = controller else {
            Logger.error("MediaController not initialized", log: Logger.playback)
            return
        }
        
        switch command {
        case .play:
            controller.play()
        case .pause:
            controller.pause()
        case .togglePlayPause:
            controller.togglePlayPause()
        case .stop:
            controller.stop()
        case .nextTrack:
            controller.nextTrack()
        case .previousTrack:
            controller.previousTrack()
        }
    }
    
    static func seek(to position: Double) {
        guard let controller = controller else {
            Logger.error("MediaController not initialized", log: Logger.playback)
            return
        }
        
        Logger.debug("Seeking to position: \(position)s", log: Logger.playback)
        
        // Immediately update watcher state to prevent UI jank
        watcher?.notifySeek(to: position)
        
        // Send seek command to media player
        controller.setTime(seconds: position)
    }
}
