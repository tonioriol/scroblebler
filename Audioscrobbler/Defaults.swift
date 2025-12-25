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
    
    @Published var privateSession: Bool {
        didSet {
            defaults.set(privateSession, forKey: "privateSession")
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                appDelegate.updateIcon()
            }
        }
    }
    
    @Published var serviceCredentials: [ServiceCredentials] = [] {
        didSet {
            saveServiceCredentials()
        }
    }
    
    init() {
        firstRun = defaults.string(forKey: "firstRun") == nil
        privateSession = defaults.bool(forKey: "privateSession")
        picture = defaults.data(forKey: "picture")
        
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
        let enabled = enabledServices
        // Priority: Last.fm > Libre.fm > ListenBrainz
        return enabled.first { $0.service == .lastfm }
            ?? enabled.first { $0.service == .librefm }
            ?? enabled.first { $0.service == .listenbrainz }
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
        privateSession = false
        serviceCredentials = []
        picture = nil
    }
}
