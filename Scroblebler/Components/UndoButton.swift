import SwiftUI

struct UndoButton: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @StateObject private var trackStore = TrackStore.shared
    @StateObject private var trackService = TrackService.shared
    
    let artist: String
    let track: String
    let album: String
    let serviceInfo: [String: ServiceTrackData]
    
    @State private var isProcessing = false
    @State private var isUndone = false
    @State private var isAnimating = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var playcount: Int? {
        trackStore.playcount(artist: artist, track: track)
    }
    
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
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Redo Failed"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private func undoScrobble() {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            Logger.info("🔄 UNDO: Starting undo for '\(artist) - \(track)'", log: Logger.scrobbling)
            Logger.debug("UNDO: serviceInfo keys: \(serviceInfo.keys.sorted().joined(separator: ", "))", log: Logger.scrobbling)
            
            // Log detailed serviceInfo for each service
            for (serviceId, data) in serviceInfo {
                Logger.debug("UNDO: serviceInfo[\(serviceId)] = timestamp: \(data.timestamp ?? 0), id: \(data.id ?? "nil")", log: Logger.scrobbling)
            }
            
            // Log enabled services
            let enabled = defaults.enabledServices
            Logger.debug("UNDO: Enabled services: \(enabled.map { $0.service.displayName }.joined(separator: ", "))", log: Logger.scrobbling)
            
            // Update track store
            trackStore.decrementPlaycount(artist: artist, track: track)
            Logger.debug("UNDO: Decremented playcount in store", log: Logger.scrobbling)
            
            await serviceManager.deleteScrobbleAll(artist: artist, track: track, serviceInfo: serviceInfo)
            
            // Mark as recently deleted to prevent immediate backfill
            trackService.markTrackAsDeleted(artist: artist, track: track)
            
            Logger.info("✅ UNDO: Completed undo operation", log: Logger.scrobbling)
            
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
            // Check if track is blacklisted
            if await trackService.isBlacklisted(artist: artist, track: track) {
                await MainActor.run {
                    errorMessage = "Cannot redo: track is blacklisted"
                    showError = true
                    isProcessing = false
                }
                return
            }
            
            // Check if there are enabled services
            if defaults.enabledServices.isEmpty {
                await MainActor.run {
                    errorMessage = "Cannot redo: no services enabled"
                    showError = true
                    isProcessing = false
                }
                return
            }
            
            // Get the timestamp from serviceInfo, preferring Last.fm timestamp
            // Use the original timestamp to maintain scrobble history order
            let timestamp: Int32
            if let lastfmData = serviceInfo[ScrobbleService.lastfm.id],
               let lastfmTimestamp = lastfmData.timestamp {
                timestamp = Int32(lastfmTimestamp)
            } else if let firstTimestamp = serviceInfo.values.first?.timestamp {
                timestamp = Int32(firstTimestamp)
            } else {
                timestamp = Int32(Date().timeIntervalSince1970)
            }
            
            Logger.debug("Redoing scrobble: \(artist) - \(track) with timestamp: \(timestamp)", log: Logger.scrobbling)
            
            // Create a Track for re-scrobbling with original metadata
            let trackToScrobble = Track(
                id: UUID(),
                artist: artist,
                album: album,
                name: track,
                timestamp: Int(timestamp),
                duration: 0,
                sourceService: .lastfm,
                loved: false,
                playcount: 1,
                scrobbled: false,
                blacklisted: false,
                serviceInfo: [:],
                artwork: nil,
                imageUrl: nil
            )
            
            // Clear deletion tracking so this track can be backfilled again if needed
            trackService.clearDeletionTracking(artist: artist, track: track)
            
            // Scrobble to all enabled services and update store
            trackStore.incrementPlaycount(artist: artist, track: track)
            
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

#Preview {
    UndoButton(
        artist: "Test Artist",
        track: "Test Track",
        album: "Test Album",
        serviceInfo: [:]
    )
    .environmentObject(ScrobbleManager.shared)
    .environmentObject(Defaults.shared)
}
