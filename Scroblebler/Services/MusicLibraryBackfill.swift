import Foundation
import MusicKit

/// Polls the local Music library via MusicKit for recently played tracks
/// and scrobbles any that weren't already captured by the real-time MediaRemote watcher.
/// This catches plays from iPhone, HomePod, CarPlay, etc. that sync via iCloud.
@available(macOS 14.0, *)
class MusicLibraryBackfill {
    static let shared = MusicLibraryBackfill()

    private let listenStore = ListenStore.shared

    private var isRunning = false
    private var timer: Timer?
    private static let pollInterval: TimeInterval = 300 // 5 minutes

    /// Start periodic backfill: runs immediately then every 5 minutes.
    @MainActor
    func start() {
        Task { @MainActor in await self.run() }

        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.run() }
        }
    }

    /// Run a single backfill cycle.
    @MainActor
    private func run() async {
        guard !isRunning else {
            Logger.debug("Music library backfill already running, skipping", log: Logger.sync)
            return
        }
        isRunning = true
        defer { isRunning = false }

        Logger.info("🎵 Music library backfill starting", log: Logger.sync)

        // Request MusicKit authorization if needed
        let status = await MusicAuthorization.request()
        guard status == .authorized else {
            Logger.error("MusicKit authorization denied: \(status)", log: Logger.sync)
            return
        }

        do {
            let tracks = try await fetchRecentlyPlayed()
            if tracks.isEmpty {
                Logger.debug("No new tracks from Music library", log: Logger.sync)
                return
            }

            Logger.info("🎵 Found \(tracks.count) tracks from Music library", log: Logger.sync)

            var scrobbled = 0
            for track in tracks {
                let finishedAt = Int(track.lastPlayedDate.timeIntervalSince1970)
                let startedAt = finishedAt - Int(track.duration)

                // Music.app's lastPlayedDate = when the track finished playing.
                // MediaRemote captures when it started. Check both to dedup.
                if let _ = try await listenStore.findByTimestamp(
                    artist: track.artist,
                    track: track.title,
                    timestamp: finishedAt
                ) {
                    continue
                }
                if let _ = try await listenStore.findByTimestamp(
                    artist: track.artist,
                    track: track.title,
                    timestamp: startedAt
                ) {
                    continue
                }

                let listen = Listen.fromMediaPlayer(
                    artist: track.artist,
                    album: track.album,
                    track: track.title,
                    duration: track.duration,
                    listenedAt: startedAt,
                    sourceBundle: "com.apple.Music"
                )

                await SyncEngine.shared.scrobble(listen)
                scrobbled += 1
            }

            if scrobbled > 0 {
                Logger.info("🎵 Music library backfill: scrobbled \(scrobbled) new tracks", log: Logger.sync)
            }
        } catch {
            Logger.error("Music library backfill failed: \(error)", log: Logger.sync)
        }
    }

    // MARK: - MusicKit

    private struct MusicTrack {
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let lastPlayedDate: Date
    }

    /// Fetch tracks from the local Music library played in the last 48 hours.
    private func fetchRecentlyPlayed() async throws -> [MusicTrack] {
        var request = MusicLibraryRequest<Song>()
        request.sort(by: \.lastPlayedDate, ascending: false)
        request.limit = 100

        let response = try await request.response()
        let cutoff = Date().addingTimeInterval(-172800) // 48 hours

        return response.items.compactMap { song -> MusicTrack? in
            guard let lastPlayed = song.lastPlayedDate, lastPlayed > cutoff else { return nil }

            return MusicTrack(
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle ?? "",
                duration: song.duration ?? 0,
                lastPlayedDate: lastPlayed
            )
        }
    }
}
