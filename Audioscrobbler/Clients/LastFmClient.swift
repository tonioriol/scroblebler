//
//  LastFmClient.swift
//  Audioscrobbler
//
//  Created by Victor Gama on 24/11/2022.
//

import Foundation
import CryptoKit

typealias ProtocolRecentTrack = Audioscrobbler.RecentTrack

class LastFmClient: ObservableObject, ScrobbleClient {
    public enum WSError: Error {
        case HTTPError(Data, HTTPURLResponse)
        case UnexpectedResponse
        case InvalidResponseType
        case ResponseMissingKey(String)
        case APIError(APIError)
    }
    
    struct APIError: Decodable {
        let message: String
        let code: Int
        
        enum CodingKeys: String, CodingKey {
            case code = "error"
            case message
        }
    }

    struct UserInfo: Decodable {
        struct Image: Decodable {
            let size: String
            let url: String
            enum CodingKeys: String, CodingKey {
                case size
                case url = "#text"
            }
        }

        let url: String
        let images: [Image]

        enum RootKeys: String, CodingKey { case user }
        enum UserKeys: String, CodingKey { case url, image }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RootKeys.self)
            let userContainer = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
            self.url = try userContainer.decode(String.self, forKey: .url)
            self.images = try userContainer.decode([Image].self, forKey: .image)
        }
    }
    
    struct RecentTrack: Decodable {
        let name: String
        let artist: String
        let album: String
        let date: Int?
        let isNowPlaying: Bool
        let loved: Bool
        let imageUrl: String?
        
        struct Artist: Decodable {
            let name: String
            enum CodingKeys: String, CodingKey {
                case name = "#text"
            }
        }
        
        struct Album: Decodable {
            let name: String
            enum CodingKeys: String, CodingKey {
                case name = "#text"
            }
        }
        
        struct Image: Decodable {
            let size: String
            let url: String
            enum CodingKeys: String, CodingKey {
                case size
                case url = "#text"
            }
        }
        
        struct Date: Decodable {
            let uts: String
        }
        
        struct Attr: Decodable {
            let nowplaying: String
        }
        
        enum CodingKeys: String, CodingKey {
            case name, artist, album, date, loved, image
            case attr = "@attr"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            
            let artistContainer = try container.decode(Artist.self, forKey: .artist)
            self.artist = artistContainer.name
            
            let albumContainer = try container.decode(Album.self, forKey: .album)
            self.album = albumContainer.name
            
            if let dateContainer = try? container.decode(Date.self, forKey: .date) {
                self.date = Int(dateContainer.uts)
            } else {
                self.date = nil
            }
            
            if let attrContainer = try? container.decode(Attr.self, forKey: .attr) {
                self.isNowPlaying = attrContainer.nowplaying == "true"
            } else {
                self.isNowPlaying = false
            }
            
            // Last.fm API returns "1" for loved, "0" for not loved
            if let lovedString = try? container.decode(String.self, forKey: .loved) {
                self.loved = lovedString == "1"
            } else {
                self.loved = false
            }
            
            // Get the largest image URL
            if let images = try? container.decode([Image].self, forKey: .image) {
                self.imageUrl = images.last(where: { !$0.url.isEmpty })?.url
            } else {
                self.imageUrl = nil
            }
        }
        
        func toProtocolType() -> ProtocolRecentTrack {
            return ProtocolRecentTrack(
                name: name,
                artist: artist,
                album: album,
                date: date,
                isNowPlaying: isNowPlaying,
                loved: loved,
                imageUrl: imageUrl
            )
        }
    }
    
    struct RecentTracksResponse: Decodable {
        let tracks: [LastFmClient.RecentTrack]
        
        enum RootKeys: String, CodingKey { case recenttracks }
        enum TracksKeys: String, CodingKey { case track }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RootKeys.self)
            let tracksContainer = try container.nestedContainer(keyedBy: TracksKeys.self, forKey: .recenttracks)
            self.tracks = try tracksContainer.decode([LastFmClient.RecentTrack].self, forKey: .track)
        }
    }
    
    struct AuthenticationResult: Decodable {
        let name: String
        let key: String
        let subscriber: Bool
        
        enum RootKeys: String, CodingKey { case session }
        enum SessionKeys: String, CodingKey { case name, key, subscriber }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RootKeys.self)
            let sessionContainer = try container.nestedContainer(keyedBy: SessionKeys.self, forKey: .session)
            
            self.name = try sessionContainer.decode(String.self, forKey: .name)
            self.key = try sessionContainer.decode(String.self, forKey: .key)
            self.subscriber = try sessionContainer.decode(Int.self, forKey: .subscriber) == 1
        }
    }
    
    struct TrackInfo: Decodable {
        let userPlaycount: Int?
        let playcount: Int?
        
        enum RootKeys: String, CodingKey { case track }
        enum TrackKeys: String, CodingKey { case userplaycount, playcount }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RootKeys.self)
            let trackContainer = try container.nestedContainer(keyedBy: TrackKeys.self, forKey: .track)
            
            if let userPlaycountString = try? trackContainer.decode(String.self, forKey: .userplaycount) {
                self.userPlaycount = Int(userPlaycountString)
            } else {
                self.userPlaycount = nil
            }
            
            if let playcountString = try? trackContainer.decode(String.self, forKey: .playcount) {
                self.playcount = Int(playcountString)
            } else {
                self.playcount = nil
            }
        }
    }
    
    struct UserStats: Decodable {
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
        
        enum RootKeys: String, CodingKey { case user }
        enum UserKeys: String, CodingKey {
            case playcount, artist_count, track_count, album_count, registered, country, realname, gender, age, playlists
        }
        enum RegisteredKeys: String, CodingKey { case unixtime }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RootKeys.self)
            let userContainer = try container.nestedContainer(keyedBy: UserKeys.self, forKey: .user)
            
            let playcountString = try userContainer.decode(String.self, forKey: .playcount)
            self.playcount = Int(playcountString) ?? 0
            
            let artistCountString = try userContainer.decode(String.self, forKey: .artist_count)
            self.artistCount = Int(artistCountString) ?? 0
            
            if let trackCountString = try? userContainer.decode(String.self, forKey: .track_count) {
                self.trackCount = Int(trackCountString) ?? 0
            } else {
                self.trackCount = 0
            }
            
            if let albumCountString = try? userContainer.decode(String.self, forKey: .album_count) {
                self.albumCount = Int(albumCountString) ?? 0
            } else {
                self.albumCount = 0
            }
            
            // For backwards compatibility, lovedCount is set to trackCount
            self.lovedCount = self.trackCount
            
            let registeredContainer = try userContainer.nestedContainer(keyedBy: RegisteredKeys.self, forKey: .registered)
            let timestampString = try registeredContainer.decode(String.self, forKey: .unixtime)
            if let timestamp = Int(timestampString) {
                let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                self.registered = formatter.string(from: date)
            } else {
                self.registered = "Unknown"
            }
            
            self.country = try? userContainer.decode(String.self, forKey: .country)
            self.realname = try? userContainer.decode(String.self, forKey: .realname)
            self.gender = try? userContainer.decode(String.self, forKey: .gender)
            
            if let ageString = try? userContainer.decode(String.self, forKey: .age), !ageString.isEmpty {
                self.age = ageString
            } else {
                self.age = nil
            }
            
            if let playlistsString = try? userContainer.decode(String.self, forKey: .playlists) {
                self.playlistCount = Int(playlistsString)
            } else {
                self.playlistCount = nil
            }
        }
    }
    
    struct TopArtist: Decodable {
        let name: String
        let playcount: Int
        let imageUrl: String?
        
        struct Image: Decodable {
            let size: String
            let url: String
            enum CodingKeys: String, CodingKey {
                case size
                case url = "#text"
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case name, playcount, image
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            
            let playcountString = try container.decode(String.self, forKey: .playcount)
            self.playcount = Int(playcountString) ?? 0
            
            if let images = try? container.decode([Image].self, forKey: .image) {
                self.imageUrl = images.last(where: { !$0.url.isEmpty })?.url
            } else {
                self.imageUrl = nil
            }
        }
    }
    
    struct TopAlbum: Decodable {
        let name: String
        let artist: String
        let playcount: Int
        let imageUrl: String?
        
        struct Artist: Decodable {
            let name: String
        }
        
        struct Image: Decodable {
            let size: String
            let url: String
            enum CodingKeys: String, CodingKey {
                case size
                case url = "#text"
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case name, artist, playcount, image
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            
            let artistContainer = try container.decode(Artist.self, forKey: .artist)
            self.artist = artistContainer.name
            
            let playcountString = try container.decode(String.self, forKey: .playcount)
            self.playcount = Int(playcountString) ?? 0
            
            if let images = try? container.decode([Image].self, forKey: .image) {
                self.imageUrl = images.last(where: { !$0.url.isEmpty })?.url
            } else {
                self.imageUrl = nil
            }
        }
    }
    
    struct TopTrack: Decodable {
        let name: String
        let artist: String
        let playcount: Int
        
        struct Artist: Decodable {
            let name: String
        }
        
        enum CodingKeys: String, CodingKey {
            case name, artist, playcount
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            
            let artistContainer = try container.decode(Artist.self, forKey: .artist)
            self.artist = artistContainer.name
            
            let playcountString = try container.decode(String.self, forKey: .playcount)
            self.playcount = Int(playcountString) ?? 0
        }
    }
    
    struct TopArtistsResponse: Decodable {
        let artists: [TopArtist]
        
        enum RootKeys: String, CodingKey { case topartists }
        enum ArtistsKeys: String, CodingKey { case artist }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RootKeys.self)
            let artistsContainer = try container.nestedContainer(keyedBy: ArtistsKeys.self, forKey: .topartists)
            self.artists = try artistsContainer.decode([TopArtist].self, forKey: .artist)
        }
    }
    
    struct TopAlbumsResponse: Decodable {
        let albums: [TopAlbum]
        
        enum RootKeys: String, CodingKey { case topalbums }
        enum AlbumsKeys: String, CodingKey { case album }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RootKeys.self)
            let albumsContainer = try container.nestedContainer(keyedBy: AlbumsKeys.self, forKey: .topalbums)
            self.albums = try albumsContainer.decode([TopAlbum].self, forKey: .album)
        }
    }
    
    struct TopTracksResponse: Decodable {
        let tracks: [TopTrack]
        
        enum RootKeys: String, CodingKey { case toptracks }
        enum TracksKeys: String, CodingKey { case track }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RootKeys.self)
            let tracksContainer = try container.nestedContainer(keyedBy: TracksKeys.self, forKey: .toptracks)
            self.tracks = try tracksContainer.decode([TopTrack].self, forKey: .track)
        }
    }
    
    let apiKey = "227d67ffb2b5f671bcaba9a1b465d8e1"
    let apiSecret = "b85d94beb2f214fba7ef7260bbe522a8"
    var baseURL: URL { URL(string: "https://ws.audioscrobbler.com/2.0/")! }
    var authURL: String { "https://www.last.fm/api/auth/" }
    
    private func prepareCall(method: String, args: [String:String]) -> [String:String] {
        var args = args
        args["method"] = method
        args["api_key"] = apiKey
        args["format"] = "json"
        
        let signatureBase = args.keys
            .filter { $0 != "format" }
            .sorted()
            .map { "\($0)\(args[$0]!)" }.joined()
        let signatureString = "\(signatureBase)\(apiSecret)"
        let digest = Insecure.MD5.hash(data: signatureString.data(using: .utf8) ?? Data())
            .map { String(format: "%02hhx", $0) }.joined()
        args["api_sig"] = digest
        
        return args
    }
    
    private func executeRequest(method: String) async throws -> Data {
        try await executeRequest(method: method, args: [:])
    }
    
    private func executeRequestWithRetry(method: String, args: [String:String] = [:], maxRetries: Int = 3) async throws -> Data {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await executeRequest(method: method, args: args)
            } catch let error as WSError {
                lastError = error
                
                // Only retry on specific error codes (backend failures)
                if case .APIError(let apiError) = error, apiError.code == 8 {
                    let delay = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000) // Exponential backoff
                    print("API call failed (attempt \(attempt + 1)/\(maxRetries)), retrying in \(Int(delay / 1_000_000_000))s...")
                    try await Task.sleep(nanoseconds: delay)
                    continue
                }
                
                // Don't retry other errors
                throw error
            } catch {
                throw error
            }
        }
        
        throw lastError ?? WSError.UnexpectedResponse
    }

    private static let percentEncodingAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(" ")
        allowed.remove("+")
        allowed.remove("/")
        allowed.remove("?")
        allowed.remove("&")
        return allowed
    }()

    private static func escape(_ str: String) -> String {
        return str.replacingOccurrences(of: "\n", with: "\r\n")
            .addingPercentEncoding(withAllowedCharacters: percentEncodingAllowedCharacters)!
            .replacingOccurrences(of: " ", with: "+")
    }
    
    private func executeRequest(method: String, args: [String:String]) async throws -> Data {
        var request = URLRequest(url: baseURL)
        // print("executing \(method) with args: \(args)")
        request.httpMethod = "POST"
        request.setValue("appleMusicAudioscrobbler/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var formComponents = URLComponents()
        formComponents.queryItems = prepareCall(method: method, args: args).map { URLQueryItem(name: $0, value: LastFmClient.escape($1)) }
        request.httpBody = formComponents.query?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        if httpResponse.statusCode >= 400 {
            if httpResponse.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") ?? false {
                let apiError: APIError
                do {
                    // Try to decode it as an API error, perhaps?
                    apiError = try JSONDecoder().decode(APIError.self, from: data)
                } catch {
                    print("Failed decoding API error: \(error)")
                    throw WSError.HTTPError(data, httpResponse)
                }
                
                throw WSError.APIError(apiError)
            }

            throw WSError.HTTPError(data, httpResponse)
        }
        
        return data
    }
    
    private func parseJSON<T>(_ data: Data) throws -> T {
        guard let result = try JSONSerialization.jsonObject(with: data) as? T else {
            throw WSError.InvalidResponseType
        }
        return result
    }
    
    
    private func decodeJSON<T>(_ data: Data) throws -> T where T: Decodable {
        return try JSONDecoder().decode(T.self, from: data)
    }

    func authenticate() async throws -> (token: String, authURL: URL) {
        let data = try await executeRequest(method: "auth.gettoken")
        let json: [String: String] = try parseJSON(data)
        guard let token = json["token"] else {
            throw WSError.ResponseMissingKey("token")
        }
        
        var url = URLComponents(string: authURL)!
        url.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token)
        ]
        return (token, url.url!)
    }

    func completeAuthentication(token: String) async throws -> (username: String, sessionKey: String, profileUrl: String?, isSubscriber: Bool) {
        let data = try await executeRequest(method: "auth.getSession", args: [
            "token": token
        ])
        let authResult: AuthenticationResult = try decodeJSON(data)
        
        let userInfoData = try await executeRequest(method: "user.getInfo", args: [
            "sk": authResult.key
        ])
        let userInfo: UserInfo = try decodeJSON(userInfoData)
        
        return (authResult.name, authResult.key, userInfo.url, authResult.subscriber)
    }

    func getUserInfo(token: String) async throws -> UserInfo {
        let data = try await executeRequest(method: "user.getInfo", args: [
            "sk": token
        ])
        return try decodeJSON(data)
    }

    func getUserImage(_ img: UserInfo.Image) async throws -> Data? {
        guard let url = URL(string: img.url) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("appleMusicAudioscrobbler/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { return nil }
        guard response.statusCode == 200 else { return nil }
        return data
    }

    func updateLove(sessionKey: String, artist: String, track: String, loved: Bool) async throws {
        _ = try await executeRequest(method: "track.\(loved ? "" : "un")love", args: [
            "artist": artist,
            "track": track,
            "sk": sessionKey
        ])
    }

    func updateNowPlaying(sessionKey: String, track: Track) async throws {
        if Defaults.shared.privateSession { return }
        _ = try await executeRequest(method: "track.updateNowPlaying", args: [
            "artist": track.artist,
            "track": track.name,
            "album": track.album,
            "duration": String(format: "%.0f", track.length),
            "sk": sessionKey
        ])
    }

    func scrobble(sessionKey: String, track: Track) async throws {
        if Defaults.shared.privateSession { return }
        _ = try await updateLove(sessionKey: sessionKey, artist: track.artist, track: track.name, loved: track.loved)
        _ = try await executeRequest(method: "track.scrobble", args: [
            "artist": track.artist,
            "track": track.name,
            "album": track.album,
            "duration": String(format: "%.0f", track.length),
            "timestamp": String(format: "%d", track.startedAt),
            "sk": sessionKey
        ])
    }
    
    func getRecentTracks(username: String, limit: Int, page: Int) async throws -> [ProtocolRecentTrack] {
        print("✅ LastFmClient.getRecentTracks called!")
        let data = try await executeRequestWithRetry(method: "user.getRecentTracks", args: [
            "user": username,
            "limit": String(limit),
            "page": String(page)
        ])
        let response: RecentTracksResponse = try decodeJSON(data)
        print("API returned \(response.tracks.count) tracks total")
        return response.tracks.filter { !$0.isNowPlaying }.map { $0.toProtocolType() }
    }
    
    func getTrackUserPlaycount(token: String, artist: String, track: String) async throws -> Int? {
        do {
            let data = try await executeRequestWithRetry(method: "track.getInfo", args: [
                "artist": artist,
                "track": track,
                "sk": token
            ])
            let trackInfo: TrackInfo = try decodeJSON(data)
            return trackInfo.userPlaycount
        } catch {
            // Track not found or other API error - return nil instead of throwing
            return nil
        }
    }
    
    func getUserStats(username: String) async throws -> Audioscrobbler.UserStats? {
        let data = try await executeRequest(method: "user.getInfo", args: [
            "user": username
        ])
        let stats: UserStats = try decodeJSON(data)
        return Audioscrobbler.UserStats(
            playcount: stats.playcount,
            artistCount: stats.artistCount,
            trackCount: stats.trackCount,
            albumCount: stats.albumCount,
            lovedCount: stats.lovedCount,
            registered: stats.registered,
            country: stats.country,
            realname: stats.realname,
            gender: stats.gender,
            age: stats.age,
            playlistCount: stats.playlistCount
        )
    }
    
    func getTopArtists(username: String, period: String, limit: Int) async throws -> [Audioscrobbler.TopArtist] {
        let data = try await executeRequest(method: "user.getTopArtists", args: [
            "user": username,
            "period": period,
            "limit": String(limit)
        ])
        let response: TopArtistsResponse = try decodeJSON(data)
        return response.artists.map { Audioscrobbler.TopArtist(name: $0.name, playcount: $0.playcount, imageUrl: $0.imageUrl) }
    }
    
    func getTopAlbums(username: String, period: String, limit: Int) async throws -> [Audioscrobbler.TopAlbum] {
        let data = try await executeRequest(method: "user.getTopAlbums", args: [
            "user": username,
            "period": period,
            "limit": String(limit)
        ])
        let response: TopAlbumsResponse = try decodeJSON(data)
        return response.albums.map { Audioscrobbler.TopAlbum(artist: $0.artist, name: $0.name, playcount: $0.playcount, imageUrl: $0.imageUrl) }
    }
    
    func getTopTracks(username: String, period: String, limit: Int) async throws -> [Audioscrobbler.TopTrack] {
        let data = try await executeRequest(method: "user.getTopTracks", args: [
            "user": username,
            "period": period,
            "limit": String(limit)
        ])
        let response: TopTracksResponse = try decodeJSON(data)
        return response.tracks.map { Audioscrobbler.TopTrack(artist: $0.artist, name: $0.name, playcount: $0.playcount, imageUrl: nil) }
    }
    
}
