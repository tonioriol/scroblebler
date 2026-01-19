import SwiftUI

struct HistoryItem: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults

    let track: Listen
    @State private var isHovered = false
    @State private var playbackState: PlaybackState = .idle

    // Cache only the immutable dictionary conversion
    private let serviceInfoKeys: [String: ServiceTrackData]

    init(track: Listen) {
        self.track = track
        // Pre-compute service info from Listen.services
        self.serviceInfoKeys = track.services.reduce(into: [:]) { result, entry in
            result[entry.key] = ServiceTrackData(
                timestamp: entry.value.timestamp,
                id: entry.value.recordingMsid,
                artistMbid: entry.value.artistMbid,
                releaseMbid: entry.value.releaseMbid
            )
        }
    }

    private enum PlaybackState {
        case idle
        case success
        case failed
    }

    // Reactive but optimized - only computes when defaults actually change
    private var syncStatus: SyncStatus {
        let enabledServices = Set(defaults.enabledServices.map { $0.service })
        let syncedServiceStrings = track.syncedServices
        let syncedServices = Set(syncedServiceStrings.compactMap { ScrobbleService(rawValue: $0) })
        return SyncStatus.calculate(presentInServices: syncedServices, enabledServices: enabledServices)
    }

    var body: some View {
        // TODO: Build URLs from Listen (need to adapt service.buildURLs or build directly from MBIDs)

        TrackInfo(
            trackName: track.track,
            artist: track.artist,
            album: track.album,
            loved: .constant(track.loved),
            artworkImageUrl: nil,  // TODO: Build from releaseMbid
            timestamp: track.listenedAt,
            playCount: .constant(0),  // TODO: Load from ListenStore.playcount()
            artistURL: nil,  // TODO: Build from service/MBIDs
            albumURL: nil,
            trackURL: nil,
            actionButtons: {
                HStack(spacing: 4) {
                    // Sync status indicator
                    SyncStatusBadge(
                        syncStatus: syncStatus,
                        serviceInfo: serviceInfoKeys,
                        sourceService: nil  // TODO: Determine from services
                    )

                    UndoButton(
                        artist: track.artist,
                        track: track.track,
                        album: track.album,
                        serviceInfo: serviceInfoKeys
                    )

                    BlacklistButton(
                        artist: track.artist,
                        track: track.track
                    )
                }
            },
            artworkOverlay: {
                if isHovered || playbackState != .idle {
                    Button(action: playTrack) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 32, height: 32)

                            Image(systemName: iconName)
                                .foregroundColor(iconColor)
                                .font(.system(size: 14))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(tooltipText)
                }
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var iconName: String {
        switch playbackState {
        case .idle: return "play.fill"
        case .success: return "checkmark"
        case .failed: return "xmark"
        }
    }

    private var iconColor: Color {
        switch playbackState {
        case .idle, .success: return .white
        case .failed: return .red
        }
    }

    private var tooltipText: String {
        switch playbackState {
        case .idle: return "Play in Apple Music"
        case .success: return "Playing..."
        case .failed: return "Track not found in library"
        }
    }

    private func playTrack() {
        playbackState = .success

        Task {
            do {
                try HistoryPlay.playTrack(artist: track.artist, track: track.track)
                Logger.info("Successfully initiated playback for '\(track.track)' by '\(track.artist)'")
                playbackState = .success

                // Reset icon after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                playbackState = .idle
            } catch {
                Logger.error("Failed to play track '\(track.track)' by '\(track.artist)': \(error)")
                playbackState = .failed

                // Reset icon after 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                playbackState = .idle
            }
        }
    }
}
