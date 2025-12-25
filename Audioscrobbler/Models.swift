import Foundation

/// Namespace for all domain model types used throughout the app
enum Audioscrobbler {
    
    /// Represents a recently played track
    struct RecentTrack: Codable {
        let name: String
        let artist: String
        let album: String
        let date: Int?
        let isNowPlaying: Bool
        let loved: Bool
        let imageUrl: String?
        
        init(name: String, artist: String, album: String, date: Int?, isNowPlaying: Bool, loved: Bool, imageUrl: String?) {
            self.name = name
            self.artist = artist
            self.album = album
            self.date = date
            self.isNowPlaying = isNowPlaying
            self.loved = loved
            self.imageUrl = imageUrl
        }
    }
    
    /// User statistics from a scrobbling service
    struct UserStats: Codable {
        let playcount: Int
        let artistCount: Int
        let trackCount: Int
        let albumCount: Int
        let lovedCount: Int
        let registered: String
        let country: String?
        let realname: String?
        let gender: String?
        let age: String?
        let playlistCount: Int?
    }
    
    /// Top artist with playcount
    struct TopArtist: Codable {
        let name: String
        let playcount: Int
        let imageUrl: String?
    }
    
    /// Top album with artist and playcount
    struct TopAlbum: Codable {
        let artist: String
        let name: String
        let playcount: Int
        let imageUrl: String?
    }
    
    /// Top track with artist and playcount
    struct TopTrack: Codable {
        let artist: String
        let name: String
        let playcount: Int
        let imageUrl: String?
    }
}
