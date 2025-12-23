//
//  WebService.swift
//  Audioscrobbler
//
//  Created by Victor Gama on 24/11/2022.
//

import Foundation
import CryptoKit

class WebService: ObservableObject {
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
    }
    
    struct RecentTracksResponse: Decodable {
        let tracks: [RecentTrack]
        
        enum RootKeys: String, CodingKey { case recenttracks }
        enum TracksKeys: String, CodingKey { case track }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RootKeys.self)
            let tracksContainer = try container.nestedContainer(keyedBy: TracksKeys.self, forKey: .recenttracks)
            self.tracks = try tracksContainer.decode([RecentTrack].self, forKey: .track)
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
    
    let apiKey = "227d67ffb2b5f671bcaba9a1b465d8e1"
    let apiSecret = "b85d94beb2f214fba7ef7260bbe522a8"
    let baseURL = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    
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
        formComponents.queryItems = prepareCall(method: method, args: args).map { URLQueryItem(name: $0, value: WebService.escape($1)) }
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

    func prepareAuthenticationToken() async throws -> (String, URL) {
        let data = try await executeRequest(method: "auth.gettoken")
        let json: [String: String] = try parseJSON(data)
        guard let token = json["token"] else {
            throw WSError.ResponseMissingKey("token")
        }
        
        var url = URLComponents(string: "https://www.last.fm/api/auth/")!
        url.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "token", value: token)
        ]
        return (token, url.url!)
    }

    func getAuthenticationResult(token: String) async throws -> AuthenticationResult {
        let data = try await executeRequest(method: "auth.getSession", args: [
            "token": token
        ])
        return try decodeJSON(data)
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

    func updateLove(token: String, artist: String, track: String, loved: Bool) async throws {
        _ = try await executeRequest(method: "track.\(loved ? "" : "un")love", args: [
            "artist": artist,
            "track": track,
            "sk": token
        ])
    }

    func updateNowListening(token: String, track: Track) async throws {
        if Defaults.shared.privateSession { return }
        _ = try await executeRequest(method: "track.updateNowPlaying", args: [
            "artist": track.artist,
            "track": track.name,
            "album": track.album,
            "duration": String(format: "%.0f", track.length),
            "sk": token
        ])
    }

    func doScrobble(token: String, track: Track) async throws {
        if Defaults.shared.privateSession { return }
        _ = try await updateLove(token: token, artist: track.artist, track: track.name, loved: track.loved)
        _ = try await executeRequest(method: "track.scrobble", args: [
            "artist": track.artist,
            "track": track.name,
            "album": track.album,
            "duration": String(format: "%.0f", track.length),
            "timestamp": String(format: "%d", track.startedAt),
            "sk": token
        ])
    }
    
    func getRecentTracks(username: String, limit: Int = 10, page: Int = 1) async throws -> [RecentTrack] {
        let data = try await executeRequestWithRetry(method: "user.getRecentTracks", args: [
            "user": username,
            "limit": String(limit),
            "page": String(page)
        ])
        let response: RecentTracksResponse = try decodeJSON(data)
        return response.tracks.filter { !$0.isNowPlaying }
    }
}
