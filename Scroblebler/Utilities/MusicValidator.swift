import Foundation

/// Validates whether a track is real music before scrobbling.
///
/// Uses the ListenBrainz MBID Mapper as the primary oracle — if a track resolves
/// to a MusicBrainz recording, it's music. Falls back to local DB and heuristics
/// when the mapper is unavailable.
actor MusicValidator {
    static let shared = MusicValidator()

    /// Known music player bundles that never need validation.
    private static let trustedPlayers: Set<String> = [
        "com.apple.Music",
        "com.spotify.client",
        "com.roon.Roon",
        "tv.plex.desktop",
        "tv.plex.plexamp",
        "com.plexapp.plexamp",
        "com.tidal.desktop",
        "com.amazon.music",
        "com.deezer.macOS",
        "com.clementine-player.clementine",
        "org.videolan.vlc",
        "com.vox.vox",
        "com.coppertino.Vox",
        "io.foobar2000.player",
        "com.doppler-music.Doppler",
    ]

    // MARK: - Cache

    private var cache: [String: Bool] = [:]  // artist|track → is music
    private let maxCacheSize = 500

    // MARK: - Public API

    /// Returns `true` if the track should be scrobbled.
    ///
    /// - Known music players skip validation entirely.
    /// - Cached results are returned immediately.
    /// - Otherwise queries the MBID Mapper, falling back to local DB + heuristics.
    func shouldScrobble(artist: String, track: String, album: String, sourceBundle: String?) async -> Bool {
        // 1. Trusted music players — always scrobble
        let isTrusted = sourceBundle.map { Self.trustedPlayers.contains($0) } ?? false
        if isTrusted { return true }

        let key = cacheKey(artist: artist, track: track)

        // 2. Cache hit
        if let cached = cache[key] {
            Logger.debug("MusicValidator cache \(cached ? "HIT ✅" : "HIT ❌"): \(artist) - \(track)", log: Logger.playback)
            return cached
        }

        // 3. MBID Mapper lookup (primary oracle)
        let cleaned = cleanTitle(track)
        if let result = await lookupMBIDMapper(artist: artist, track: cleaned, album: album) {
            cacheResult(key: key, isMusic: result)
            return result
        }

        // 4. Fallback: check local listen DB (previously scrobbled = likely music)
        if await checkLocalDB(artist: artist, track: track) {
            Logger.debug("MusicValidator local DB match ✅: \(artist) - \(track)", log: Logger.playback)
            cacheResult(key: key, isMusic: true)
            return true
        }

        // 5. Fallback heuristic: has album from MediaRemote → likely music
        //    (browsers/YouTube rarely provide album metadata)
        if !album.isEmpty {
            Logger.debug("MusicValidator heuristic (has album) ✅: \(artist) - \(track) [\(album)]", log: Logger.playback)
            cacheResult(key: key, isMusic: true)
            return true
        }

        // 6. No signal — deny for untrusted sources, allow only for trusted players
        Logger.info("MusicValidator: no signal for '\(artist) - \(track)' from \(sourceBundle ?? "unknown") — blocking", log: Logger.playback)
        cacheResult(key: key, isMusic: false)
        return false
    }

    // MARK: - MBID Mapper

    private func lookupMBIDMapper(artist: String, track: String, album: String) async -> Bool? {
        guard !artist.isEmpty, !track.isEmpty else { return false }

        var components = URLComponents(string: "https://mapper.listenbrainz.org/mapping/lookup")!
        var queryItems = [
            URLQueryItem(name: "artist_credit_name", value: artist),
            URLQueryItem(name: "recording_name", value: track)
        ]
        if !album.isEmpty {
            queryItems.append(URLQueryItem(name: "release_name", value: album))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5  // Reasonable timeout — mapper is usually fast

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else { return nil }

            if http.statusCode == 404 {
                Logger.debug("MusicValidator MBID Mapper 404 ❌: \(artist) - \(track)", log: Logger.playback)
                return false
            }

            guard http.statusCode == 200 else {
                Logger.debug("MusicValidator MBID Mapper HTTP \(http.statusCode): \(artist) - \(track)", log: Logger.playback)
                return nil  // Unknown — fall through to next check
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let confidence = json?["confidence"] as? Double ?? 0.0

            if confidence >= 0.5 {
                Logger.debug("MusicValidator MBID Mapper ✅ (confidence: \(String(format: "%.2f", confidence))): \(artist) - \(track)", log: Logger.playback)
                return true
            } else {
                Logger.debug("MusicValidator MBID Mapper low confidence ❌ (\(String(format: "%.2f", confidence))): \(artist) - \(track)", log: Logger.playback)
                return false
            }
        } catch {
            Logger.debug("MusicValidator MBID Mapper error: \(error.localizedDescription) for \(artist) - \(track)", log: Logger.playback)
            return nil  // Network error — fall through to fallbacks
        }
    }

    // MARK: - Local DB Check

    private func checkLocalDB(artist: String, track: String) async -> Bool {
        let listen = await MainActor.run {
            ListenStore.shared.findListen(artist: artist, track: track)
        }
        guard let listen else { return false }
        // Only trust if it was previously synced to at least one service
        return !listen.syncedServices.isEmpty
    }

    // MARK: - Title Cleaning

    /// Strip common YouTube suffixes that prevent MBID Mapper matches.
    private func cleanTitle(_ title: String) -> String {
        var cleaned = title

        // Remove patterns like "(Official Video)", "(Lyric Video)", "(Audio)", etc.
        let patterns = [
            #"\s*\(Official\s*(Music\s*)?Video\)"#,
            #"\s*\(Official\s*Audio\)"#,
            #"\s*\(Lyric\s*Video\)"#,
            #"\s*\(Lyrics?\)"#,
            #"\s*\(Audio\)"#,
            #"\s*\(Visuali[sz]er\)"#,
            #"\s*\[Official\s*(Music\s*)?Video\]"#,
            #"\s*\[Official\s*Audio\]"#,
            #"\s*\|\s*Official\s*(Music\s*)?Video"#,
            #"\s*-\s*Official\s*(Music\s*)?Video"#,
        ]

        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Cache Helpers

    private func cacheKey(artist: String, track: String) -> String {
        "\(artist.lowercased())|\(track.lowercased())"
    }

    private func cacheResult(key: String, isMusic: Bool) {
        if cache.count >= maxCacheSize {
            // Evict oldest half (simple approach)
            let keysToRemove = Array(cache.keys.prefix(maxCacheSize / 2))
            for k in keysToRemove { cache.removeValue(forKey: k) }
        }
        cache[key] = isMusic
    }
}
