import SwiftUI

struct AlbumArtwork: View {
    let imageUrl: String?
    let imageData: Data?
    let size: CGFloat
    let artist: String
    let album: String
    let trackName: String

    /// Toggled after an async load completes to force a re-render.
    /// The actual image data lives in ImageCache, not in @State.
    @State private var loadTrigger = false
    @State private var didLoad = false

    init(imageUrl: String?, size: CGFloat, artist: String = "", album: String = "", trackName: String = "") {
        self.imageUrl = imageUrl
        self.imageData = nil
        self.size = size
        self.artist = artist
        self.album = album
        self.trackName = trackName
    }

    init(imageData: Data?, size: CGFloat) {
        self.imageUrl = nil
        self.imageData = imageData
        self.size = size
        self.artist = ""
        self.album = ""
        self.trackName = ""
    }

    /// Always reads from cache — never depends on @State for image data.
    private var resolvedImage: Image {
        // Touch trigger so SwiftUI knows this view depends on it
        let _ = loadTrigger

        if let data = imageData, let img = NSImage(data: data) {
            return Image(nsImage: img)
        }
        if let url = imageUrl, let cached = ImageCache.shared.get(url), let img = NSImage(data: cached) {
            return Image(nsImage: img)
        }
        // Check Last.fm album cache
        if !artist.isEmpty, !album.isEmpty {
            let key = "lastfm:\(artist)|\(album)"
            if let cached = ImageCache.shared.get(key), let img = NSImage(data: cached) {
                return Image(nsImage: img)
            }
        }
        // Check Last.fm track cache
        if !artist.isEmpty, !trackName.isEmpty {
            let key = "lastfm-track:\(artist)|\(trackName)"
            if let cached = ImageCache.shared.get(key), let img = NSImage(data: cached) {
                return Image(nsImage: img)
            }
        }
        return Image("nocover")
    }

    func loadArtwork() async {
        guard !didLoad else { return }
        didLoad = true

        guard let imageUrl = imageUrl else {
            await tryFallbacks(cacheAlsoAs: nil)
            return
        }

        if ImageCache.shared.get(imageUrl) != nil {
            await MainActor.run { loadTrigger.toggle() }
            return
        }

        if ImageCache.shared.isFailed(imageUrl) {
            await tryFallbacks(cacheAlsoAs: imageUrl)
            return
        }

        guard let url = URL(string: imageUrl) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                ImageCache.shared.markFailed(imageUrl)
                await tryFallbacks(cacheAlsoAs: imageUrl)
                return
            }
            ImageCache.shared.set(imageUrl, data: data)
            await MainActor.run { loadTrigger.toggle() }
        } catch {
            didLoad = false
        }
    }

    /// Chain of fallbacks: Last.fm album.getinfo → Last.fm track.getinfo
    private func tryFallbacks(cacheAlsoAs originalUrl: String?) async {
        // 1) Try Last.fm album lookup
        if await tryLastFmAlbum(cacheAlsoAs: originalUrl) { return }
        // 2) Try Last.fm track lookup (discovers album + image)
        if await tryLastFmTrack(cacheAlsoAs: originalUrl) { return }
    }

    private func tryLastFmAlbum(cacheAlsoAs originalUrl: String?) async -> Bool {
        guard !artist.isEmpty, !album.isEmpty else { return false }

        let cacheKey = "lastfm:\(artist)|\(album)"
        if ImageCache.shared.isFailed(cacheKey) { return false }

        if ImageCache.shared.get(cacheKey) != nil {
            if let key = originalUrl { ImageCache.shared.set(key, data: ImageCache.shared.get(cacheKey)!) }
            await MainActor.run { loadTrigger.toggle() }
            return true
        }

        guard let fallbackUrl = await CoverArt.lastFmImageUrl(artist: artist, album: album),
              let url = URL(string: fallbackUrl) else {
            ImageCache.shared.markFailed(cacheKey)
            return false
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            ImageCache.shared.set(cacheKey, data: data)
            if let key = originalUrl { ImageCache.shared.set(key, data: data) }
            await MainActor.run { loadTrigger.toggle() }
            return true
        } catch {
            return false
        }
    }

    private func tryLastFmTrack(cacheAlsoAs originalUrl: String?) async -> Bool {
        guard !artist.isEmpty, !trackName.isEmpty else { return false }

        let cacheKey = "lastfm-track:\(artist)|\(trackName)"
        if ImageCache.shared.isFailed(cacheKey) { return false }

        if ImageCache.shared.get(cacheKey) != nil {
            if let key = originalUrl { ImageCache.shared.set(key, data: ImageCache.shared.get(cacheKey)!) }
            await MainActor.run { loadTrigger.toggle() }
            return true
        }

        guard let fallbackUrl = await CoverArt.lastFmTrackImageUrl(artist: artist, track: trackName),
              let url = URL(string: fallbackUrl) else {
            ImageCache.shared.markFailed(cacheKey)
            return false
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            ImageCache.shared.set(cacheKey, data: data)
            if let key = originalUrl { ImageCache.shared.set(key, data: data) }
            await MainActor.run { loadTrigger.toggle() }
            return true
        } catch {
            return false
        }
    }

    var body: some View {
        resolvedImage
            .resizable()
            .cornerRadius(3)
            .frame(width: size, height: size)
            .onAppear {
                // If cache already has data, resolvedImage will find it — no async needed
                if let url = imageUrl, ImageCache.shared.get(url) != nil { return }
                if !artist.isEmpty, !album.isEmpty, ImageCache.shared.get("lastfm:\(artist)|\(album)") != nil { return }
                if !artist.isEmpty, !trackName.isEmpty, ImageCache.shared.get("lastfm-track:\(artist)|\(trackName)") != nil { return }
                if imageData != nil { return }
                Task {
                    await loadArtwork()
                }
            }
    }
}
