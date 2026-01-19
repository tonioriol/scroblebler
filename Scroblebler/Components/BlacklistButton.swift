import SwiftUI

struct BlacklistButton: View {
    let artist: String
    let track: String

    @State private var isBlacklisted = false
    @State private var isAnimating = false
    private let blacklist = LocalBlacklist.shared

    // Unique identifier for this artist+track combination
    private var trackId: String {
        "\(artist)|\(track)"
    }

    var body: some View {
        Button {
            Task {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isAnimating = true
                }

                // Toggle via LocalBlacklist
                let newState = await toggleBlacklistStatus()

                await MainActor.run {
                    isBlacklisted = newState
                }

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
        .id(trackId)  // Force view recreation when track changes
        .onAppear {
            Task { @MainActor in
                await updateBlacklistStatus()
            }
        }
        .onChange(of: trackId) { _ in
            Task { @MainActor in
                await updateBlacklistStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .blacklistChanged)) { _ in
            // Update when any blacklist change occurs (syncs all button instances)
            Task { @MainActor in
                await updateBlacklistStatus()
            }
        }
    }

    @MainActor
    private func updateBlacklistStatus() async {
        isBlacklisted = await blacklist.contains(artist: artist, track: track)
    }

    private func toggleBlacklistStatus() async -> Bool {
        do {
            let currentlyBlacklisted = await blacklist.contains(artist: artist, track: track)
            if currentlyBlacklisted {
                try await blacklist.remove(artist: artist, track: track)
                return false
            } else {
                try await blacklist.add(artist: artist, track: track)
                return true
            }
        } catch {
            Logger.error("Failed to toggle blacklist: \(error)", log: Logger.ui)
            return false
        }
    }
}
