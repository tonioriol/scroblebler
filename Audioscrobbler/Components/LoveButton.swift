import SwiftUI

struct LoveButton: View {
    @EnvironmentObject var webService: WebService
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
        guard let token = defaults.token else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            loved.toggle()
            isAnimating = true
        }
        
        Task {
            do {
                try await webService.updateLove(token: token, artist: artist, track: trackName, loved: loved)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isAnimating = false
                }
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    loved.toggle()
                    isAnimating = false
                }
                print("Failed to toggle love: \(error)")
            }
        }
    }
}
