import SwiftUI

struct PlayerControls: View {
    @Binding var isPlaying: Bool
    let currentPosition: Double?
    let trackLength: Double?
    let onSeek: ((Double) -> Void)?
    
    func formatDuration(_ value: Double) -> String {
        let hours = Int(value / 3600)
        let minutes = Int(value.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = Int(value.truncatingRemainder(dividingBy: 60))
        
        if hours >= 1 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else if minutes >= 1 {
            return String(format: "%d:%02d", minutes, seconds)
        } else {
            return String(format: "0:%02d", seconds)
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Progress bar with time display
            if let currentPosition = currentPosition, let trackLength = trackLength {
                HStack(spacing: 8) {
                    Text(formatDuration(currentPosition))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressBar(value: currentPosition, maxValue: trackLength, onSeek: onSeek)
                        .frame(height: 8)
                    Text(formatDuration(trackLength))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Playback controls
            HStack(spacing: 16) {
                Button(action: {
                    MediaControl.send(.previousTrack)
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Previous Track")
                
                Button(action: {
                    isPlaying.toggle()
                    MediaControl.send(.togglePlayPause)
                }) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .help(isPlaying ? "Pause" : "Play")
                
                Button(action: {
                    MediaControl.send(.nextTrack)
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Next Track")
                
            }
            .foregroundColor(.secondary)
        }
    }
}

struct PlayerControls_Previews: PreviewProvider {
    static var previews: some View {
        PlayerControls(
            isPlaying: .constant(true),
            currentPosition: 61.5,
            trackLength: 180.0,
            onSeek: { _ in }
        )
    }
}
