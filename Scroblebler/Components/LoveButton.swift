import SwiftUI

struct LoveButton: View {
    @EnvironmentObject var defaults: Defaults
    @StateObject private var trackRepo = TrackStore.shared
    
    let artist: String
    let trackName: String
    let fontSize: CGFloat
    
    @State private var isAnimating: Bool = false
    
    private var loved: Bool {
        trackRepo.isLoved(artist: artist, track: trackName)
    }
    
    private var hasEnabledServices: Bool {
        !defaults.enabledServices.isEmpty
    }
    
    var body: some View {
        Button(action: toggleLove) {
            Image(systemName: loved ? "heart.fill" : "heart")
                .foregroundColor(hasEnabledServices ? (loved ? .red : .secondary) : .gray)
                .font(.system(size: 11))
                .frame(width: 11, height: 11)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isAnimating)
        }
        .buttonStyle(.borderless)
        .disabled(!hasEnabledServices)
        .opacity(hasEnabledServices ? 1.0 : 0.4)
        .help(hasEnabledServices ? (loved ? "Unlove track" : "Love track") : "No services logged in")
    }
    
    func toggleLove() {
        guard defaults.primaryService != nil else {
            Logger.error("No primary service configured", log: Logger.scrobbling)
            return
        }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            isAnimating = true
        }
        
        Task {
            // Use TrackStore which handles online/offline and state updates
            _ = await trackRepo.toggleLove(artist: artist, track: trackName)
            
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isAnimating = false
                }
            }
        }
    }
}
