import SwiftUI

struct BlacklistButton: View {
    @EnvironmentObject var defaults: Defaults
    
    let artist: String
    let track: String
    
    @State private var isBlacklisted = false
    @State private var isAnimating = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                defaults.toggleBlacklist(artist: artist, track: track)
                isBlacklisted = defaults.isBlacklisted(artist: artist, track: track)
                isAnimating = true
            }
            
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isAnimating = false
                }
            }
        } label: {
            Image(systemName: "nosign")
                .foregroundColor(isBlacklisted ? .red : .secondary)
                .font(.system(size: 11))
                .frame(width: 11, height: 11)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isAnimating)
        }
        .buttonStyle(.borderless)
        .help(isBlacklisted ? "Un-blacklist Track" : "Blacklist Track")
        .onAppear {
            isBlacklisted = defaults.isBlacklisted(artist: artist, track: track)
        }
    }
}
