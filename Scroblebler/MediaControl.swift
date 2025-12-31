import Foundation
import MediaRemoteAdapter

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
    private static let controller = MediaController()
    
    static func send(_ command: MediaCommand) {
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
        case .toggleShuffle:
            // Get current shuffle mode and toggle
            Logger.debug("Toggle shuffle requested", log: Logger.playback)
            // Note: We'd need current state to toggle properly
            // For now, just cycle through modes
            controller.setShuffleMode(.songs)
        case .toggleRepeat:
            // Get current repeat mode and toggle
            Logger.debug("Toggle repeat requested", log: Logger.playback)
            // Note: We'd need current state to toggle properly
            // For now, just cycle through modes
            controller.setRepeatMode(.all)
        }
    }
    
    static func seek(to position: Double) {
        Logger.debug("Seeking to position: \(position)s", log: Logger.playback)
        controller.setTime(seconds: position)
    }
}
