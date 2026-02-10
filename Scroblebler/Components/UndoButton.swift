import SwiftUI

struct UndoButton: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @StateObject private var listenStore = ListenStore.shared

    let artist: String
    let track: String
    let album: String
    let serviceInfo: [String: ServiceTrackData]
    let listenId: Int64?

    @State private var isProcessing = false
    @State private var isUndone = false
    @State private var isAnimating = false
    @State private var showError = false
    @State private var alertTitle = ""
    @State private var errorMessage = ""
    @State private var playcount: Int = 0

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
                title: Text(alertTitle.isEmpty ? "Error" : alertTitle),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func undoScrobble() {
        guard !isProcessing else { return }
        isProcessing = true

        let enabledServices = defaults.enabledServices.map { $0.service }
        let enabledKeys = Set(enabledServices.map { $0.rawValue })

        Task {
            Logger.info("🔄 UNDO: Starting undo for '\(artist) - \(track)'", log: Logger.scrobbling)
            Logger.debug("UNDO: serviceInfo keys: \(serviceInfo.keys.sorted().joined(separator: ", "))", log: Logger.scrobbling)

            // Log detailed serviceInfo for each service
            for (serviceId, data) in serviceInfo {
                Logger.debug("UNDO: serviceInfo[\(serviceId)] = timestamp: \(data.timestamp ?? 0), id: \(data.id ?? "nil")", log: Logger.scrobbling)
            }

            // Log enabled services
            Logger.debug("UNDO: Enabled services: \(enabledServices.map { $0.displayName }.joined(separator: ", "))", log: Logger.scrobbling)

            // Delete from all services
            await serviceManager.deleteScrobbleAll(
                artist: artist,
                track: track,
                serviceInfo: serviceInfo,
                listenId: listenId
            )

            // Decide whether this was actually deleted everywhere.
            // We only flip the UI state when ALL enabled services are marked deleted.
            var fullyDeleted = false
            var deleteFailed: [(service: ScrobbleService, error: String?)] = []
            var deletePending: [ScrobbleService] = []

            if let listenId {
                if let updated = try? await listenStore.get(id: listenId) {
                    fullyDeleted = enabledKeys.allSatisfy { key in
                        updated.services[key]?.status == .deleted
                    }

                    for service in enabledServices {
                        let state = updated.services[service.rawValue]
                        switch state?.status {
                        case .deleteFailed:
                            deleteFailed.append((service: service, error: state?.error))
                        case .deletePending:
                            deletePending.append(service)
                        default:
                            break
                        }
                    }
                } else {
                    // Row is gone (pruned) – treat as fully deleted.
                    fullyDeleted = true
                }
            }

            await MainActor.run {
                if fullyDeleted {
                    Logger.info("✅ UNDO: Deleted everywhere", log: Logger.scrobbling)
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
                } else if !deleteFailed.isEmpty {
                    alertTitle = "Delete Failed"
                    errorMessage = deleteFailed
                        .map { "\($0.service.displayName): \($0.error ?? "delete failed")" }
                        .joined(separator: "\n")
                    showError = true
                } else if !deletePending.isEmpty {
                    alertTitle = "Delete Pending"
                    errorMessage = "Retrying in background for: " + deletePending.map { $0.displayName }.joined(separator: ", ")
                    showError = true
                } else {
                    alertTitle = "Delete Not Completed"
                    errorMessage = "Not deleted from all enabled services. Check the sync badge for details."
                    showError = true
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
            let blacklist = LocalBlacklist.shared
            if await blacklist.contains(artist: artist, track: track) {
                await MainActor.run {
                    alertTitle = "Redo Failed"
                    errorMessage = "Cannot redo: track is blacklisted"
                    showError = true
                    isProcessing = false
                }
                return
            }

            // Check if there are enabled services
            if defaults.enabledServices.isEmpty {
                await MainActor.run {
                    alertTitle = "Redo Failed"
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

            // Scrobble to all enabled services
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
        serviceInfo: [:],
        listenId: nil
    )
    .environmentObject(ScrobbleManager.shared)
    .environmentObject(Defaults.shared)
}
