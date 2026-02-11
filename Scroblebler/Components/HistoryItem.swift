import SwiftUI

struct HistoryItem: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults

    let track: Listen
    @State private var isHovered = false
    @State private var playbackState: PlaybackState = .idle
    @State private var playCount: Int?
    @State private var playCountTask: Task<Void, Never>?
    @State private var playCountKey = ""

    // Cache only the immutable dictionary conversion
    private let serviceInfoKeys: [String: ServiceTrackData]

    @StateObject private var listenStore = ListenStore.shared

    init(track: Listen) {
        self.track = track
        // Pre-compute service info from Listen.services
        self.serviceInfoKeys = track.services.reduce(into: [:]) { result, entry in
            result[entry.key] = ServiceTrackData(
                timestamp: entry.value.timestamp ?? track.listenedAt,
                id: entry.value.recordingMbid,
                recordingMsid: entry.value.recordingMsid,
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
        let displayService = defaults.mainServicePreference ?? defaults.primaryService?.service ?? .lastfm
        let service = serviceManager.service(for: displayService)
        let urls = service?.buildURLs(for: listenAsTrack(displayService: displayService))

            TrackInfo(
                trackName: track.track,
                artist: track.artist,
                album: track.album,
                loved: .constant(track.loved),
                artworkImageUrl: track.releaseMbid.map { CoverArt.coverArtArchiveFrontURL(releaseMbid: $0, size: 250) } ?? track.imageUrl,
                timestamp: track.listenedAt,
                playCount: $playCount,
            artistURL: urls?.artistURL,
            albumURL: urls?.albumURL,
            trackURL: urls?.trackURL,
            actionButtons: {
                HStack(spacing: 4) {
                    // Sync status indicator
                    SyncStatusBadge(
                        syncStatus: syncStatus,
                        serviceStates: track.services,
                        sourceService: nil  // TODO: Determine from services
                    )

                    UndoButton(
                        artist: track.artist,
                        track: track.track,
                        album: track.album,
                        serviceInfo: serviceInfoKeys,
                        listenId: track.id
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
        .onAppear {
            updatePlayCountIfNeeded(forArtist: track.artist, track: track.track)
        }
        .onChange(of: track.artist) { _ in
            updatePlayCountIfNeeded(forArtist: track.artist, track: track.track)
        }
        .onChange(of: track.track) { _ in
            updatePlayCountIfNeeded(forArtist: track.artist, track: track.track)
        }
        .onChange(of: listenStore.listensRevision) { _ in
            updatePlayCountIfNeeded(forArtist: track.artist, track: track.track)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func updatePlayCountIfNeeded(forArtist artist: String, track: String) {
        let key = "\(artist)|\(track)"
        guard key != playCountKey else { return }
        playCountKey = key

        playCountTask?.cancel()
        playCountTask = Task {
            let count = try? await ListenStore.shared.playcount(artist: artist, track: track)
            await MainActor.run {
                self.playCount = count
            }
        }
    }

    private func listenAsTrack(displayService: ScrobbleService) -> Track {
        Track(
            id: UUID(),
            artist: track.artist,
            album: track.album,
            name: track.track,
            timestamp: track.listenedAt,
            duration: track.duration,
            sourceService: displayService,
            loved: track.loved,
            playcount: 1,
            scrobbled: true,
            blacklisted: false,
            serviceInfo: serviceInfoKeys.reduce(into: [ScrobbleService: ServiceTrackData]()) { result, entry in
                if let service = ScrobbleService(rawValue: entry.key) {
                    result[service] = entry.value
                }
            },
            artwork: nil,
            imageUrl: nil
        )
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
