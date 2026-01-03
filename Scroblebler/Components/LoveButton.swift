import SwiftUI

struct LoveButton: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    
    @Binding var loved: Bool
    let artist: String
    let trackName: String
    let fontSize: CGFloat
    
    @State private var isAnimating: Bool = false
    
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
            loved.toggle()
            isAnimating = true
        }
        
        Task {
            // Use centralized ServiceManager method (handles online/offline)
            await serviceManager.updateLoveAll(artist: artist, track: trackName, loved: loved)
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isAnimating = false
            }
            
            // Notify that love state changed so history can refresh
            NotificationCenter.default.post(name: NSNotification.Name("TrackLoveStateChanged"), object: nil)
        }
    }
}
