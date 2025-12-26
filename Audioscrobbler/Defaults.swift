import Foundation
import AppKit

class Defaults: ObservableObject {
    static let shared = Defaults()
    
    private let defaults = UserDefaults.standard
    
    @Published var firstRun: Bool {
        didSet {
            if firstRun {
                defaults.removeObject(forKey: "firstRun")
            } else {
                defaults.set("false", forKey: "firstRun")
            }
        }
    }
    
    @Published var serviceCredentials: [ServiceCredentials] = [] {
        didSet {
            saveServiceCredentials()
        }
    }
    
    @Published var mainServicePreference: ScrobbleService? {
        didSet {
            if let service = mainServicePreference {
                defaults.set(service.rawValue, forKey: "mainServicePreference")
            } else {
                defaults.removeObject(forKey: "mainServicePreference")
            }
        }
    }
    
    @Published var blacklistedTracks: [String] = [] {
        didSet {
            defaults.set(blacklistedTracks, forKey: "blacklistedTracks")
        }
    }
    
    init() {
        firstRun = defaults.string(forKey: "firstRun") == nil
        picture = defaults.data(forKey: "picture")
        blacklistedTracks = defaults.stringArray(forKey: "blacklistedTracks") ?? []
        
        if let serviceRaw = defaults.string(forKey: "mainServicePreference"),
           let service = ScrobbleService(rawValue: serviceRaw) {
            mainServicePreference = service
        } else {
            mainServicePreference = nil
        }
        
        if let data = defaults.data(forKey: "serviceCredentials"),
           let decoded = try? JSONDecoder().decode([ServiceCredentials].self, from: data) {
            serviceCredentials = decoded
        } else {
            serviceCredentials = []
            migrateLegacyCredentials()
        }
    }
    
    private func migrateLegacyCredentials() {
        // Migrate legacy Last.fm credentials
        if let token = defaults.string(forKey: "token"),
           let name = defaults.string(forKey: "name") {
            let creds = ServiceCredentials(
                service: .lastfm,
                token: token,
                username: name,
                profileUrl: defaults.string(forKey: "url"),
                isSubscriber: defaults.bool(forKey: "pro"),
                isEnabled: true
            )
            serviceCredentials.append(creds)
            
            // Clean up legacy keys
            defaults.removeObject(forKey: "token")
            defaults.removeObject(forKey: "name")
            defaults.removeObject(forKey: "pro")
            defaults.removeObject(forKey: "url")
            defaults.removeObject(forKey: "picture")
        }
        
        // Migrate legacy Libre.fm credentials
        if let librefmToken = defaults.string(forKey: "librefmToken"),
           let librefmName = defaults.string(forKey: "librefmName") {
            let creds = ServiceCredentials(
                service: .librefm,
                token: librefmToken,
                username: librefmName,
                profileUrl: defaults.string(forKey: "librefmUrl"),
                isSubscriber: false,
                isEnabled: defaults.bool(forKey: "scrobbleToLibrefm")
            )
            serviceCredentials.append(creds)
            
            // Clean up legacy keys
            defaults.removeObject(forKey: "librefmToken")
            defaults.removeObject(forKey: "librefmName")
            defaults.removeObject(forKey: "librefmUrl")
            defaults.removeObject(forKey: "scrobbleToLibrefm")
        }
        
        if !serviceCredentials.isEmpty {
            saveServiceCredentials()
        }
    }
    
    private func saveServiceCredentials() {
        if let encoded = try? JSONEncoder().encode(serviceCredentials) {
            defaults.set(encoded, forKey: "serviceCredentials")
        }
    }
    
    func addOrUpdateCredentials(_ credentials: ServiceCredentials) {
        if let index = serviceCredentials.firstIndex(where: { $0.service == credentials.service }) {
            serviceCredentials[index] = credentials
        } else {
            serviceCredentials.append(credentials)
        }
    }
    
    func removeCredentials(for service: ScrobbleService) {
        serviceCredentials.removeAll { $0.service == service }
        
        // Clear main preference if removing the main service
        if mainServicePreference == service {
            mainServicePreference = nil
        }
    }
    
    func credentials(for service: ScrobbleService) -> ServiceCredentials? {
        serviceCredentials.first { $0.service == service }
    }
    
    func toggleService(_ service: ScrobbleService, enabled: Bool) {
        if let index = serviceCredentials.firstIndex(where: { $0.service == service }) {
            serviceCredentials[index].isEnabled = enabled
        }
    }
    
    var enabledServices: [ServiceCredentials] {
        serviceCredentials.filter { $0.isEnabled }
    }
    
    var primaryService: ServiceCredentials? {
        if let preference = mainServicePreference,
           let credential = serviceCredentials.first(where: { $0.service == preference }) {
            return credential
        }
        return enabledServices.first
    }
    
    // Legacy properties for backward compatibility with views
    var name: String? { primaryService?.username }
    var pro: Bool? { primaryService?.isSubscriber }
    var url: String? { primaryService?.profileUrl }
    
    @Published var picture: Data? {
        didSet {
            if let data = picture {
                defaults.set(data, forKey: "picture")
            } else {
                defaults.removeObject(forKey: "picture")
            }
        }
    }
    
    func reset() {
        serviceCredentials = []
        picture = nil
    }
    
    // MARK: - Blacklist
    
    private let blacklistKeySeparator = "|||"
    
    private func blacklistKey(artist: String, track: String) -> String {
        "\(artist)\(blacklistKeySeparator)\(track)"
    }
    
    func toggleBlacklist(artist: String, track: String) {
        let key = blacklistKey(artist: artist, track: track)
        if blacklistedTracks.contains(key) {
            blacklistedTracks.removeAll { $0 == key }
        } else {
            blacklistedTracks.append(key)
        }
    }
    
    func isBlacklisted(artist: String, track: String) -> Bool {
        let key = blacklistKey(artist: artist, track: track)
        return blacklistedTracks.contains(key)
    }
}
