import SwiftUI

struct UndoButton: View {
    @EnvironmentObject var serviceManager: ServiceManager
    
    let artist: String
    let track: String
    let serviceInfo: [String: ServiceTrackData]
    
    @State private var isProcessing = false
    @State private var isUndone = false
    
    var body: some View {
        Button {
            undoScrobble()
        } label: {
            Image(systemName: isUndone ? "minus.circle.fill" : "minus.circle")
                .resizable()
                .scaledToFit()
                .foregroundColor(isUndone ? .red : .secondary)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isUndone ? "Scrobble Undone" : "Undo Scrobble")
        .disabled(isProcessing || isUndone)
        .opacity(isProcessing ? 0.5 : 1.0)
    }
    
    private func undoScrobble() {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            await serviceManager.deleteScrobbleAll(artist: artist, track: track, serviceInfo: serviceInfo)
            
            await MainActor.run {
                withAnimation {
                    isUndone = true
                }
                isProcessing = false
            }
        }
    }
}
