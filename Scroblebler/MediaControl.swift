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
    private static weak var controller: MediaController?
    private static var currentShuffleMode: MediaRemoteAdapter.TrackInfo.ShuffleMode = .off
    private static var currentRepeatMode: MediaRemoteAdapter.TrackInfo.RepeatMode = .off
    
    static func setup(controller: MediaController) {
        self.controller = controller
    }
    
    static func updateShuffleMode(_ mode: MediaRemoteAdapter.TrackInfo.ShuffleMode) {
        currentShuffleMode = mode
    }
    
    static func updateRepeatMode(_ mode: MediaRemoteAdapter.TrackInfo.RepeatMode) {
        currentRepeatMode = mode
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
        case .toggleShuffle:
            let newMode: MediaRemoteAdapter.TrackInfo.ShuffleMode = currentShuffleMode == .off ? .songs : .off
            Logger.debug("Toggle shuffle: \(currentShuffleMode) -> \(newMode)", log: Logger.playback)
            controller.setShuffleMode(newMode)
            currentShuffleMode = newMode
        case .toggleRepeat:
            let newMode: MediaRemoteAdapter.TrackInfo.RepeatMode
            switch currentRepeatMode {
            case .off: newMode = .one
            case .one: newMode = .all
            case .all: newMode = .off
            }
            Logger.debug("Toggle repeat: \(currentRepeatMode) -> \(newMode)", log: Logger.playback)
            controller.setRepeatMode(newMode)
            currentRepeatMode = newMode
        }
    }
    
    static func seek(to position: Double) {
        guard let controller = controller else {
            Logger.error("MediaController not initialized", log: Logger.playback)
            return
        }
        
        Logger.debug("Seeking to position: \(position)s", log: Logger.playback)
        controller.setTime(seconds: position)
    }
}
