import Foundation

class LastFmWebClient {
    enum Error: Swift.Error {
        case httpError(Data, HTTPURLResponse)
        case unexpectedResponse
        case missingCookie(String)
        case authenticationFailed(String)
    }
    
    // Web session credentials
    private var csrfToken: String?
    private var sessionId: String?
    private var username: String
    
    // Use a dedicated URLSession instance with persistent cookie storage
    private let session: URLSession
    private let loginURL = "https://www.last.fm/login"
    
    init(username: String) {
        self.username = username
        
        // Create a custom URLSession configuration with cookie persistence
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Authentication
    
    /// Authenticate and obtain web session credentials
    /// This requires username and password for web login
    func authenticate(username: String, password: String) async throws {
        // Step 1: Get initial CSRF token from login page
        let loginPageURL = URL(string: loginURL)!
        var loginPageRequest = URLRequest(url: loginPageURL)
        loginPageRequest.httpMethod = "GET"
        
        let (_, loginPageResponse) = try await session.data(for: loginPageRequest)
        guard loginPageResponse is HTTPURLResponse else {
            throw Error.unexpectedResponse
        }
        
        // Extract CSRF token from cookies
        if let cookies = HTTPCookieStorage.shared.cookies(for: loginPageURL) {
            for cookie in cookies {
                if cookie.name == "csrftoken" {
                    self.csrfToken = cookie.value
                }
            }
        }
        
        guard let csrfToken = self.csrfToken else {
            throw Error.missingCookie("csrftoken")
        }
        
        // Step 2: Perform login POST request
        let loginRequestURL = URL(string: loginURL)!
        var loginRequest = URLRequest(url: loginRequestURL)
        loginRequest.httpMethod = "POST"
        loginRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        loginRequest.setValue(loginURL, forHTTPHeaderField: "Referer")
        
        var formComponents = URLComponents()
        formComponents.queryItems = [
            URLQueryItem(name: "csrfmiddlewaretoken", value: csrfToken),
            URLQueryItem(name: "username_or_email", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        loginRequest.httpBody = formComponents.query?.data(using: .utf8)
        
        let (_, loginResponse) = try await session.data(for: loginRequest)
        guard let loginHttpResponse = loginResponse as? HTTPURLResponse else {
            throw Error.unexpectedResponse
        }
        
        // Check for successful login (redirect or 200)
        if loginHttpResponse.statusCode != 200 {
            throw Error.authenticationFailed("Login failed with status \(loginHttpResponse.statusCode)")
        }
        
        // Extract sessionid cookie
        if let cookies = HTTPCookieStorage.shared.cookies(for: loginRequestURL) {
            for cookie in cookies {
                if cookie.name == "sessionid" {
                    self.sessionId = cookie.value
                }
                // Also refresh csrftoken in case it changed
                if cookie.name == "csrftoken" {
                    self.csrfToken = cookie.value
                }
            }
        }
        
        guard self.sessionId != nil else {
            throw Error.missingCookie("sessionid")
        }
        
        self.username = username
        Logger.info("Last.fm web authentication successful for user: \(username)", log: Logger.authentication)
    }
    
    // MARK: - Scrobble Deletion
    
    /// Delete a scrobble using the Last.fm web endpoint
    func deleteScrobble(username: String, artist: String, track: String, timestamp: Int) async throws {
        // Build the deletion endpoint URL
        let deleteURL = URL(string: "https://www.last.fm/user/\(username)/library/delete")!
        
        // Read CSRF token fresh from cookies (like Go implementation does)
        // This is important because CSRF tokens can change between requests
        guard let cookies = HTTPCookieStorage.shared.cookies(for: deleteURL),
              let csrfCookie = cookies.first(where: { $0.name == "csrftoken" }) else {
            throw Error.missingCookie("csrftoken")
        }
        let currentCsrfToken = csrfCookie.value
        
        var request = URLRequest(url: deleteURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.last.fm", forHTTPHeaderField: "Referer")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        
        // Build form data (cookies are automatically handled by the session)
        var formComponents = URLComponents()
        formComponents.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "timestamp", value: String(timestamp)),
            URLQueryItem(name: "csrfmiddlewaretoken", value: currentCsrfToken),
            URLQueryItem(name: "ajax", value: "1")
        ]
        request.httpBody = formComponents.query?.data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.unexpectedResponse
        }
        
        if httpResponse.statusCode >= 400 {
            throw Error.httpError(data, httpResponse)
        }
        
        // Parse JSON response to validate deletion success
        struct DeleteResponse: Codable {
            let result: Bool
        }
        
        do {
            let deleteResponse = try JSONDecoder().decode(DeleteResponse.self, from: data)
            if !deleteResponse.result {
                throw Error.authenticationFailed("Delete response indicates failure")
            }
        } catch {
            throw Error.authenticationFailed("Failed to parse delete response: \(error.localizedDescription)")
        }
        
        Logger.info("Deleted scrobble via web endpoint: \(artist) - \(track)", log: Logger.scrobbling)
    }
    
    // MARK: - Helper Methods
    
    /// Check if web session is authenticated
    var isAuthenticated: Bool {
        return csrfToken != nil && sessionId != nil
    }
    
    /// Manually set web session credentials (for testing or when obtained elsewhere)
    func setCredentials(csrfToken: String, sessionId: String) {
        self.csrfToken = csrfToken
        self.sessionId = sessionId
    }
}
