import Foundation
import CryptoKit

class LastFmClient: ObservableObject, ScrobbleClient {
    enum Error: Swift.Error {
        case httpError(Data, HTTPURLResponse)
        case unexpectedResponse
        case invalidResponseType
        case responseMissingKey(String)
        case apiError(Int, String)
    }
    
    private let apiKey = "227d67ffb2b5f671bcaba9a1b465d8e1"
    private let apiSecret = "b85d94beb2f214fba7ef7260bbe522a8"
    
    var baseURL: URL { URL(string: "https://ws.audioscrobbler.com/2.0/")! }
    var authURL: String { "https://www.last.fm/api/auth/" }
    
    // MARK: - Authentication
    
    func authenticate() async throws -> (token: String, authURL: URL) {
        let data = try await executeRequest(method: "auth.gettoken")
        let json: [String: String] = try parseJSON(data)
        guard let token = json["token"] else {
            throw Error.responseMissingKey("token")
        }
        
        var url = URLComponents(string: authURL)!
        url.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token)
        ]
        return (token, url.url!)
    }
    
    func completeAuthentication(token: String) async throws -> (username: String, sessionKey: String, profileUrl: String?, isSubscriber: Bool) {
        let data = try await executeRequest(method: "auth.getSession", args: ["token": token])
        let result = try JSONDecoder().decode(AuthResponse.self, from: data)
        
        let userInfoData = try await executeRequest(method: "user.getInfo", args: ["sk": result.session.key])
        let userInfo = try JSONDecoder().decode(UserInfoResponse.self, from: userInfoData)
        
        return (result.session.name, result.session.key, userInfo.user.url, result.session.subscriber == 1)
    }
    
    // MARK: - Scrobbling
    
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
    
    func updateLove(sessionKey: String, artist: String, track: String, loved: Bool) async throws {
        _ = try await executeRequest(method: "track.\(loved ? "" : "un")love", args: [
            "artist": artist,
            "track": track,
            "sk": sessionKey
        ])
    }
    
    // MARK: - Profile Data
    
    func getRecentTracks(username: String, limit: Int, page: Int) async throws -> [RecentTrack] {
        let data = try await executeRequestWithRetry(method: "user.getRecentTracks", args: [
            "user": username,
            "limit": String(limit),
            "page": String(page)
        ])
        let response = try JSONDecoder().decode(RecentTracksResponse.self, from: data)
        return response.recenttracks.track.filter { $0.attr?.nowplaying != "true" }.map { $0.toDomain() }
    }
    
    func getUserStats(username: String) async throws -> UserStats? {
        let data = try await executeRequest(method: "user.getInfo", args: ["user": username])
        let response = try JSONDecoder().decode(UserInfoResponse.self, from: data)
        return response.user.toDomain()
    }
    
    func getTopArtists(username: String, period: String, limit: Int) async throws -> [TopArtist] {
        let data = try await executeRequest(method: "user.getTopArtists", args: [
            "user": username,
            "period": period,
            "limit": String(limit)
        ])
        let response = try JSONDecoder().decode(TopArtistsResponse.self, from: data)
        return response.topartists.artist.map { $0.toDomain() }
    }
    
    func getTopAlbums(username: String, period: String, limit: Int) async throws -> [TopAlbum] {
        let data = try await executeRequest(method: "user.getTopAlbums", args: [
            "user": username,
            "period": period,
            "limit": String(limit)
        ])
        let response = try JSONDecoder().decode(TopAlbumsResponse.self, from: data)
        return response.topalbums.album.map { $0.toDomain() }
    }
    
    func getTopTracks(username: String, period: String, limit: Int) async throws -> [TopTrack] {
        let data = try await executeRequest(method: "user.getTopTracks", args: [
            "user": username,
            "period": period,
            "limit": String(limit)
        ])
        let response = try JSONDecoder().decode(TopTracksResponse.self, from: data)
        return response.toptracks.track.map { $0.toDomain() }
    }
    
    func getTrackUserPlaycount(token: String, artist: String, track: String) async throws -> Int? {
        do {
            let data = try await executeRequestWithRetry(method: "track.getInfo", args: [
                "artist": artist,
                "track": track,
                "sk": token
            ])
            let response = try JSONDecoder().decode(TrackInfoResponse.self, from: data)
            return response.track.userplaycount.flatMap { Int($0) }
        } catch {
            return nil
        }
    }
    
    func getUserImage(username: String) async throws -> Data? {
        let data = try await executeRequest(method: "user.getInfo", args: ["user": username])
        let response = try JSONDecoder().decode(UserInfoResponse.self, from: data)
        
        guard let imageUrl = response.user.image?.last(where: { !$0.text.isEmpty })?.text,
              let url = URL(string: imageUrl) else {
            return nil
        }
        
        let (imageData, _) = try await URLSession.shared.data(from: url)
        return imageData
    }
    
    // MARK: - Network
    
    private func prepareCall(method: String, args: [String: String]) -> [String: String] {
        var args = args
        args["method"] = method
        args["api_key"] = apiKey
        args["format"] = "json"
        
        let signatureBase = args.keys
            .filter { $0 != "format" }
            .sorted()
            .map { "\($0)\(args[$0]!)" }
            .joined()
        
        let signatureString = "\(signatureBase)\(apiSecret)"
        let digest = Insecure.MD5.hash(data: signatureString.data(using: .utf8) ?? Data())
            .map { String(format: "%02hhx", $0) }
            .joined()
        args["api_sig"] = digest
        
        return args
    }
    
    private func executeRequest(method: String, args: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("appleMusicAudioscrobbler/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var formComponents = URLComponents()
        formComponents.queryItems = prepareCall(method: method, args: args).map {
            URLQueryItem(name: $0, value: Self.escape($1))
        }
        request.httpBody = formComponents.query?.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.unexpectedResponse
        }
        
        if httpResponse.statusCode >= 400 {
            if httpResponse.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") ?? false,
               let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw Error.apiError(apiError.error, apiError.message)
            }
            throw Error.httpError(data, httpResponse)
        }
        
        return data
    }
    
    private func executeRequestWithRetry(method: String, args: [String: String] = [:], maxRetries: Int = 3) async throws -> Data {
        for attempt in 0..<maxRetries {
            do {
                return try await executeRequest(method: method, args: args)
            } catch Error.apiError(8, _) {
                let delay = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)
                print("API call failed (attempt \(attempt + 1)/\(maxRetries)), retrying...")
                try await Task.sleep(nanoseconds: delay)
                continue
            } catch {
                throw error
            }
        }
        throw Error.apiError(8, "Max retries exceeded")
    }
    
    private func parseJSON<T>(_ data: Data) throws -> T {
        guard let result = try JSONSerialization.jsonObject(with: data) as? T else {
            throw Error.invalidResponseType
        }
        return result
    }
    
    private static func escape(_ str: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(" ")
        allowed.remove("+")
        allowed.remove("/")
        allowed.remove("?")
        allowed.remove("&")
        
        return str.replacingOccurrences(of: "\n", with: "\r\n")
            .addingPercentEncoding(withAllowedCharacters: allowed)!
            .replacingOccurrences(of: " ", with: "+")
    }
}

// MARK: - API Response Types

private extension LastFmClient {
    struct APIErrorResponse: Decodable {
        let error: Int
        let message: String
    }
    
    struct AuthResponse: Decodable {
        let session: Session
        struct Session: Decodable {
            let name: String
            let key: String
            let subscriber: Int
        }
    }
    
    struct UserInfoResponse: Decodable {
        let user: User
        struct User: Decodable {
            let url: String
            let playcount: String
            let artist_count: String
            let track_count: String?
            let album_count: String?
            let registered: Registered
            let country: String?
            let realname: String?
            let gender: String?
            let age: String?
            let playlists: String?
            let image: [Image]?
            
            struct Registered: Decodable {
                let unixtime: String
            }
            
            struct Image: Decodable {
                let text: String
                enum CodingKeys: String, CodingKey { case text = "#text" }
            }
            
            func toDomain() -> UserStats {
                let timestamp = Int(registered.unixtime) ?? 0
                let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                
                return UserStats(
                    playcount: Int(playcount) ?? 0,
                    artistCount: Int(artist_count) ?? 0,
                    trackCount: Int(track_count ?? "0") ?? 0,
                    albumCount: Int(album_count ?? "0") ?? 0,
                    lovedCount: Int(track_count ?? "0") ?? 0,
                    registered: formatter.string(from: date),
                    country: country,
                    realname: realname,
                    gender: gender,
                    age: age?.isEmpty == false ? age : nil,
                    playlistCount: playlists.flatMap { Int($0) }
                )
            }
        }
    }
    
    struct RecentTracksResponse: Decodable {
        let recenttracks: RecentTracks
        struct RecentTracks: Decodable {
            let track: [Track]
        }
        struct Track: Decodable {
            let name: String
            let artist: TextContainer
            let album: TextContainer
            let date: Date?
            let loved: String?
            let image: [Image]?
            let attr: Attr?
            
            struct TextContainer: Decodable {
                let text: String
                enum CodingKeys: String, CodingKey { case text = "#text" }
            }
            struct Date: Decodable { let uts: String }
            struct Image: Decodable {
                let text: String
                enum CodingKeys: String, CodingKey { case text = "#text" }
            }
            struct Attr: Decodable { let nowplaying: String }
            
            enum CodingKeys: String, CodingKey {
                case name, artist, album, date, loved, image, attr = "@attr"
            }
            
            func toDomain() -> RecentTrack {
                RecentTrack(
                    name: name,
                    artist: artist.text,
                    album: album.text,
                    date: date.flatMap { Int($0.uts) },
                    isNowPlaying: false,
                    loved: loved == "1",
                    imageUrl: image?.last(where: { !$0.text.isEmpty })?.text
                )
            }
        }
    }
    
    struct TopArtistsResponse: Decodable {
        let topartists: TopArtists
        struct TopArtists: Decodable {
            let artist: [Artist]
        }
        struct Artist: Decodable {
            let name: String
            let playcount: String
            let image: [Image]?
            struct Image: Decodable {
                let text: String
                enum CodingKeys: String, CodingKey { case text = "#text" }
            }
            func toDomain() -> TopArtist {
                TopArtist(
                    name: name,
                    playcount: Int(playcount) ?? 0,
                    imageUrl: image?.last(where: { !$0.text.isEmpty })?.text
                )
            }
        }
    }
    
    struct TopAlbumsResponse: Decodable {
        let topalbums: TopAlbums
        struct TopAlbums: Decodable {
            let album: [Album]
        }
        struct Album: Decodable {
            let name: String
            let artist: Artist
            let playcount: String
            let image: [Image]?
            struct Artist: Decodable { let name: String }
            struct Image: Decodable {
                let text: String
                enum CodingKeys: String, CodingKey { case text = "#text" }
            }
            func toDomain() -> TopAlbum {
                TopAlbum(
                    artist: artist.name,
                    name: name,
                    playcount: Int(playcount) ?? 0,
                    imageUrl: image?.last(where: { !$0.text.isEmpty })?.text
                )
            }
        }
    }
    
    struct TopTracksResponse: Decodable {
        let toptracks: TopTracks
        struct TopTracks: Decodable {
            let track: [Track]
        }
        struct Track: Decodable {
            let name: String
            let artist: Artist
            let playcount: String
            struct Artist: Decodable { let name: String }
            func toDomain() -> TopTrack {
                TopTrack(
                    artist: artist.name,
                    name: name,
                    playcount: Int(playcount) ?? 0,
                    imageUrl: nil
                )
            }
        }
    }
    
    struct TrackInfoResponse: Decodable {
        let track: Track
        struct Track: Decodable {
            let userplaycount: String?
        }
    }
}
