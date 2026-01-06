import Foundation

/// Last.fm service implementation
class LastFmService: Service {
    let client: ScrobbleClient
    
    init(client: ScrobbleClient) {
        self.client = client
    }
    
    func buildURLs(for track: Track) -> (artistURL: URL, albumURL: URL, trackURL: URL) {
        let encodedArtist = track.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.artist
        let encodedAlbum = track.album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.album
        let encodedTrack = track.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.name
        
        return (
            artistURL: URL(string: "https://www.last.fm/music/\(encodedArtist)")!,
            albumURL: URL(string: "https://www.last.fm/music/\(encodedArtist)/\(encodedAlbum)")!,
            trackURL: URL(string: "https://www.last.fm/music/\(encodedArtist)/_/\(encodedTrack)")!
        )
    }
    
    func enrichTrack(_ track: Track) async -> Track {
        // Last.fm doesn't need enrichment - URLs are built from artist/track/album names
        return track
    }
}
