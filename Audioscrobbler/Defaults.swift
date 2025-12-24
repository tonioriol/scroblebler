//
//  Defaults.swift
//  Audioscrobbler
//
//  Created by Victor Gama on 25/11/2022.
//

import Foundation
import AppKit

enum ScrobbleService: String, CaseIterable, Codable, Identifiable {
    case lastfm = "Last.fm"
    case librefm = "Libre.fm"
    case listenbrainz = "ListenBrainz"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
}

struct ServiceCredentials: Codable {
    let service: ScrobbleService
    var token: String
    var username: String
    var profileUrl: String?
    var isSubscriber: Bool
    var isEnabled: Bool
    
    init(service: ScrobbleService, token: String, username: String, profileUrl: String? = nil, isSubscriber: Bool = false, isEnabled: Bool = true) {
        self.service = service
        self.token = token
        self.username = username
        self.profileUrl = profileUrl
        self.isSubscriber = isSubscriber
        self.isEnabled = isEnabled
    }
}

class Defaults: ObservableObject {
    static var shared: Defaults = {
        let instance = Defaults()
        return instance
    }()
    
    let defaults: UserDefaults
    
    init() {
        defaults = UserDefaults.standard
        token = defaults.string(forKey: "token")
        name = defaults.string(forKey: "name")
        pro = defaults.bool(forKey: "pro")
        url = defaults.string(forKey: "url")
        picture = defaults.data(forKey: "picture")
        privateSession = defaults.bool(forKey: "privateSession")
        firstRun = defaults.string(forKey: "firstRun") == nil
        
        // Load service credentials
        if let data = defaults.data(forKey: "serviceCredentials"),
           let decoded = try? JSONDecoder().decode([ServiceCredentials].self, from: data) {
            serviceCredentials = decoded
        } else {
            serviceCredentials = []
            // Migrate legacy Libre.fm credentials if they exist
            if let librefmToken = defaults.string(forKey: "librefmToken"),
               let librefmName = defaults.string(forKey: "librefmName") {
                let librefmCreds = ServiceCredentials(
                    service: .librefm,
                    token: librefmToken,
                    username: librefmName,
                    profileUrl: defaults.string(forKey: "librefmUrl"),
                    isEnabled: defaults.bool(forKey: "scrobbleToLibrefm")
                )
                serviceCredentials.append(librefmCreds)
                saveServiceCredentials()
                // Clean up old keys
                defaults.removeObject(forKey: "librefmToken")
                defaults.removeObject(forKey: "librefmName")
                defaults.removeObject(forKey: "librefmUrl")
                defaults.removeObject(forKey: "scrobbleToLibrefm")
            }
        }
    }

    @Published var firstRun: Bool {
        didSet {
            if firstRun {
                defaults.removeObject(forKey: "firstRun")
            } else {
                defaults.set("nope", forKey: "firstRun")
            }
        }
    }
    
    @Published var token: String? {
        didSet {
            defaults.set(token, forKey: "token")
        }
    }
    
    @Published var name: String? {
        didSet {
            defaults.set(name, forKey: "name")
        }
    }
    
    @Published var pro: Bool? {
        didSet {
            defaults.set(pro, forKey: "pro")
        }
    }

    @Published var url: String? {
        didSet {
            defaults.set(url, forKey: "url")
        }
    }

    @Published var picture: Data? {
        didSet {
            defaults.set(picture, forKey: "picture")
        }
    }
    
    @Published var serviceCredentials: [ServiceCredentials] = [] {
        didSet {
            saveServiceCredentials()
        }
    }

    @Published var privateSession: Bool {
        didSet {
            defaults.set(privateSession, forKey: "privateSession")
            let del = NSApplication.shared.delegate as! AppDelegate
            del.updateIcon()
        }
    }

    func reset() {
        token = nil
        name = nil
        pro = false
        url = nil
        picture = nil
        privateSession = false
        serviceCredentials = []
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
}
