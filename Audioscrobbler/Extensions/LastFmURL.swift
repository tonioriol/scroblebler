import SwiftUI

extension URL {
    static func lastFmArtist(_ artist: String) -> URL {
        let encoded = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return URL(string: "https://www.last.fm/music/\(encoded)")!
    }
    
    static func lastFmAlbum(artist: String, album: String) -> URL {
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let encodedAlbum = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return URL(string: "https://www.last.fm/music/\(encodedArtist)/\(encodedAlbum)")!
    }
    
    static func lastFmTrack(artist: String, track: String) -> URL {
        let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let encodedTrack = track.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        return URL(string: "https://www.last.fm/music/\(encodedArtist)/_/\(encodedTrack)")!
    }
}

extension Color {
    static let lastFmRed = Color(hue: 0, saturation: 0.70, brightness: 0.75)
}
