import Foundation
import AppKit

/// Utility for playing tracks from history using AppleScript
enum HistoryPlay {
    enum PlaybackError: Error {
        case trackNotFound
        case musicNotRunning
        case scriptExecutionFailed(String)
    }
    
    /// Play a track in Apple Music by artist and title
    /// - Parameters:
    ///   - artist: The artist name
    ///   - track: The track name
    /// - Throws: PlaybackError if the track cannot be played
    static func playTrack(artist: String, track: String) throws {
        Logger.info("🎵 MusicPlayer: Searching for track='\(track)' artist='\(artist)'", log: Logger.playback)
        
        // Escape single quotes in artist and track names for AppleScript
        let escapedArtist = artist.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedTrack = track.replacingOccurrences(of: "\"", with: "\\\"")
        
        let script = """
        tell application "Music"
            set trackName to "\(escapedTrack)"
            set artistName to "\(escapedArtist)"
            
            -- First try exact match (fast path)
            set exactResults to (every track whose name is trackName and artist is artistName)
            if (count of exactResults) > 0 then
                play (item 1 of exactResults)
                return "SUCCESS"
            end if
            
            -- Get significant words from track name for fuzzy matching
            set trackWords to words of trackName
            set significantWords to {}
            repeat with w in trackWords
                if length of (w as text) > 2 then -- Skip short words like "a", "of", "the"
                    set end of significantWords to (w as text)
                end if
            end repeat
            
            -- Search by artist with fuzzy name matching
            set artistTracks to (every track whose artist is artistName)
            repeat with aTrack in artistTracks
                set aTrackName to name of aTrack as text
                set matchCount to 0
                
                -- Count how many significant words match
                repeat with w in significantWords
                    if aTrackName contains w then
                        set matchCount to matchCount + 1
                    end if
                end repeat
                
                -- If most words match, it's probably the right track
                if matchCount ≥ (count of significantWords) * 0.7 then
                    play aTrack
                    return "SUCCESS"
                end if
            end repeat
            
            return "NOT_FOUND"
        end tell
        """
        
        var error: NSDictionary?
        guard let scriptObject = NSAppleScript(source: script) else {
            throw PlaybackError.scriptExecutionFailed("Failed to create AppleScript")
        }
        
        let result = scriptObject.executeAndReturnError(&error)
        
        if let error = error {
            let errorMessage = error["NSAppleScriptErrorMessage"] as? String ?? "Unknown error"
            Logger.error("AppleScript error: \(errorMessage)", log: Logger.playback)
            
            if errorMessage.contains("Music") && errorMessage.contains("not running") {
                throw PlaybackError.musicNotRunning
            }
            throw PlaybackError.scriptExecutionFailed(errorMessage)
        }
        
        let resultString = result.stringValue ?? ""
        
        if resultString == "NOT_FOUND" {
            throw PlaybackError.trackNotFound
        }
        
        let source = resultString.contains("LIBRARY") ? "Library" : "Apple Music"
        Logger.info("✅ Playing track from \(source): \(artist) - \(track)", log: Logger.playback)
    }
}
