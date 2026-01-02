import SwiftUI

struct PlayControls: View {
    @Binding var isPlaying: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: {
                DispatchQueue.global(qos: .userInitiated).async {
                    MediaControl.send(.previousTrack)
                }
            }) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .help("Previous Track")
            
            Button(action: {
                isPlaying.toggle()
                DispatchQueue.global(qos: .userInitiated).async {
                    MediaControl.send(.togglePlayPause)
                }
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .help(isPlaying ? "Pause" : "Play")
            
            Button(action: {
                DispatchQueue.global(qos: .userInitiated).async {
                    MediaControl.send(.nextTrack)
                }
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

struct PlayControls_Previews: PreviewProvider {
    static var previews: some View {
        PlayControls(isPlaying: .constant(true))
    }
}
