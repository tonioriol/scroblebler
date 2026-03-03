import Foundation

enum CoverArt {
    /// Cover Art Archive front image for a MusicBrainz Release MBID.
    static func coverArtArchiveFrontURL(releaseMbid: String, size: Int = 250) -> String {
        "https://coverartarchive.org/release/\(releaseMbid)/front-\(size)"
    }

    /// Fetch album cover art URL from Last.fm (no auth required).
    /// Tries album.getinfo first, then track.getinfo as fallback.
    /// Returns nil if nothing is found.
    static func lastFmImageUrl(artist: String, album: String) async -> String? {
        let apiKey = "22a3fbbb7d1a1d6a16998ae02556dad2"

        // Try album.getinfo if we have an album name
        if !album.isEmpty {
            if let url = await fetchLastFmAlbumImage(artist: artist, album: album, apiKey: apiKey) {
                return url
            }
        }

        return nil
    }

    /// Fetch cover art by looking up a track on Last.fm (discovers album + image).
    /// Useful when album name is empty or album.getinfo returned no image.
    static func lastFmTrackImageUrl(artist: String, track: String) async -> String? {
        let apiKey = "22a3fbbb7d1a1d6a16998ae02556dad2"

        var components = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        components.queryItems = [
            URLQueryItem(name: "method", value: "track.getInfo"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "track", value: track),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let trackDict = json?["track"] as? [String: Any]
            // track.getInfo returns album.image array
            let albumDict = trackDict?["album"] as? [String: Any]
            let images = albumDict?["image"] as? [[String: Any]] ?? []
            return images.last(where: { ($0["#text"] as? String)?.isEmpty == false })?["#text"] as? String
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private static func fetchLastFmAlbumImage(artist: String, album: String, apiKey: String) async -> String? {
        var components = URLComponents(string: "https://ws.audioscrobbler.com/2.0/")!
        components.queryItems = [
            URLQueryItem(name: "method", value: "album.getinfo"),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "artist", value: artist),
            URLQueryItem(name: "album", value: album),
            URLQueryItem(name: "format", value: "json"),
        ]

        guard let url = components.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let albumDict = json?["album"] as? [String: Any]
            let images = albumDict?["image"] as? [[String: Any]] ?? []
            return images.last(where: { ($0["#text"] as? String)?.isEmpty == false })?["#text"] as? String
        } catch {
            return nil
        }
    }
}
