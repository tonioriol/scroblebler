import SwiftUI

struct NowPlaying: View {
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @StateObject private var listenStore = ListenStore.shared
    @Binding var currentPosition: Double?
    @Binding var isPlaying: Bool

    @State private var playCount: Int?
    @State private var playCountTask: Task<Void, Never>?
    @State private var playCountKey = ""

    var body: some View {
        if let listen = listenStore.currentListen {  // Read from store (single source of truth)
            let displayService = defaults.mainServicePreference ?? defaults.primaryService?.service ?? .lastfm
            let service = serviceManager.service(for: displayService)
            let urls = service?.buildURLs(for: listenAsTrack(listen, displayService: displayService))

            VStack(spacing: 12) {
                TrackInfo(
                    trackName: listen.track,
                    artist: listen.artist,
                    album: listen.album,
                    loved: Binding(
                        get: { listen.loved },
                        set: { _ in }
                    ),
                    artworkSize: 92,
                    artworkImageData: listen.artwork,
                    artworkImageUrl: listen.releaseMbid.map { CoverArt.coverArtArchiveFrontURL(releaseMbid: $0, size: 250) } ?? listen.imageUrl,
                    titleFontSize: 18,
                    detailFontSize: 13,
                    loveFontSize: 12,
                    playCount: $playCount,
                    artistURL: urls?.artistURL,
                    albumURL: urls?.albumURL,
                    trackURL: urls?.trackURL,
                    actionButtons: {
                        BlacklistButton(artist: listen.artist, track: listen.track)
                    },
                    artworkOverlay: {
                        EmptyView()
                    }
                )

                PlayerControls(
                    isPlaying: $isPlaying,
                    currentPosition: currentPosition,
                    trackLength: listen.duration,
                    onSeek: { position in MediaControl.seek(to: position) }
                )
            }
            .padding()
            .onAppear {
                updatePlayCountIfNeeded(forArtist: listen.artist, track: listen.track)
            }
            .onChange(of: listen.artist) { _ in
                updatePlayCountIfNeeded(forArtist: listen.artist, track: listen.track)
            }
            .onChange(of: listen.track) { _ in
                updatePlayCountIfNeeded(forArtist: listen.artist, track: listen.track)
            }
            .onChange(of: listenStore.listensRevision) { _ in
                updatePlayCountIfNeeded(forArtist: listen.artist, track: listen.track)
            }
        }
    }

    private func updatePlayCountIfNeeded(forArtist artist: String, track: String) {
        let key = "\(artist)|\(track)"
        guard key != playCountKey else { return }
        playCountKey = key

        playCountTask?.cancel()
        playCountTask = Task {
            let count = try? await listenStore.playcount(artist: artist, track: track)
            await MainActor.run {
                self.playCount = count
            }
        }
    }

    private func listenAsTrack(_ listen: Listen, displayService: ScrobbleService) -> Track {
        Track(
            id: UUID(),
            artist: listen.artist,
            album: listen.album,
            name: listen.track,
            timestamp: listen.listenedAt,
            duration: listen.duration,
            sourceService: displayService,
            loved: listen.loved,
            playcount: 1,
            scrobbled: true,
            blacklisted: false,
            serviceInfo: listen.services.reduce(into: [ScrobbleService: ServiceTrackData]()) { result, entry in
                if let service = ScrobbleService(rawValue: entry.key) {
                    result[service] = ServiceTrackData(
                        timestamp: entry.value.timestamp ?? listen.listenedAt,
                        id: entry.value.recordingMbid,
                        recordingMsid: entry.value.recordingMsid,
                        artistMbid: entry.value.artistMbid,
                        releaseMbid: entry.value.releaseMbid
                    )
                }
            },
            artwork: nil,
            imageUrl: nil
        )
    }
}

struct NowPlaying_Previews: PreviewProvider {
    static var previews: some View {
        NowPlaying(currentPosition: .constant(61.5), isPlaying: .constant(true))
    }
}
