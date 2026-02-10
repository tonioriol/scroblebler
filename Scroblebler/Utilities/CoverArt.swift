import Foundation

enum CoverArt {
    /// Cover Art Archive front image for a MusicBrainz Release MBID.
    static func coverArtArchiveFrontURL(releaseMbid: String, size: Int = 250) -> String {
        // Known sizes: 250, 500, etc. We keep this flexible.
        "https://coverartarchive.org/release/\(releaseMbid)/front-\(size)"
    }
}

