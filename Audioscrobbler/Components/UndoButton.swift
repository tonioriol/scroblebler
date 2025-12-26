import SwiftUI

struct UndoButton: View {
    @EnvironmentObject var serviceManager: ServiceManager
    
    let artist: String
    let track: String
    let album: String
    let serviceInfo: [String: ServiceTrackData]
    
    @State private var isProcessing = false
    @State private var isUndone = false
    @State private var isAnimating = false
    
    var body: some View {
        Button {
            if isUndone {
                redoScrobble()
            } else {
                undoScrobble()
            }
        } label: {
            Image(systemName: isUndone ? "plus.circle" : "minus.circle")
                .foregroundColor(isUndone ? .blue : .secondary)
                .font(.system(size: 11))
                .frame(width: 11, height: 11)
                .scaleEffect(isAnimating ? 1.3 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: isAnimating)
        }
        .buttonStyle(.borderless)
        .help(isUndone ? "Redo Scrobble" : "Undo Scrobble")
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.5 : 1.0)
    }
    
    private func undoScrobble() {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            await serviceManager.deleteScrobbleAll(artist: artist, track: track, serviceInfo: serviceInfo)
            
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isUndone = true
                    isAnimating = true
                }
                
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isAnimating = false
                    }
                }
                
                isProcessing = false
            }
        }
    }
    
    private func redoScrobble() {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            // Get the timestamp from serviceInfo or use current time
            let timestamp = Int32(serviceInfo.values.first?.timestamp ?? Int(Date().timeIntervalSince1970))
            
            // Create a Track for re-scrobbling with original metadata
            let trackToScrobble = Track(
                artist: artist,
                album: album,
                name: track,
                length: 0,
                artwork: nil,
                year: 0,
                loved: false,
                startedAt: timestamp,
                scrobbled: false
            )
            
            await serviceManager.scrobbleAll(track: trackToScrobble)
            
            await MainActor.run {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isUndone = false
                    isAnimating = true
                }
                
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isAnimating = false
                    }
                }
                
                isProcessing = false
            }
        }
    }
}
