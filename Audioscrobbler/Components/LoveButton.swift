import SwiftUI

struct LoveButton: View {
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    
    @Binding var loved: Bool
    let artist: String
    let trackName: String
    let fontSize: CGFloat
    
    @State private var isAnimating: Bool = false
    
    var body: some View {
        Button(action: toggleLove) {
            Image(systemName: loved ? "heart.fill" : "heart")
                .foregroundColor(loved ? .red : .secondary)
                .font(.system(size: fontSize))
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isAnimating)
        }
        .buttonStyle(.borderless)
        .help(loved ? "Unlove track" : "Love track")
    }
    
    func toggleLove() {
        print("❤️ LoveButton clicked - artist: \(artist), track: \(trackName)")
        
        guard let primary = defaults.primaryService else {
            print("✗ No primary service configured")
            return
        }
        
        print("✓ Primary service: \(primary.service)")
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            loved.toggle()
            isAnimating = true
        }
        
        print("UI updated - new loved state: \(loved)")
        
        Task {
            do {
                guard let client = serviceManager.client(for: primary.service) else {
                    print("✗ No client available for \(primary.service)")
                    return
                }
                print("✓ Client found for \(primary.service), calling updateLove...")
                try await client.updateLove(sessionKey: primary.token, artist: artist, track: trackName, loved: loved)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isAnimating = false
                }
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    loved.toggle()
                    isAnimating = false
                }
                print("✗ Failed to toggle love: \(error)")
            }
        }
    }
}
