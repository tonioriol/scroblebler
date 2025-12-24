//
//  ServiceManager.swift
//  Audioscrobbler
//
//  Created by Audioscrobbler on 24/12/2024.
//

import Foundation

class ServiceManager: ObservableObject {
    static let shared = ServiceManager()
    
    private var clients: [ScrobbleService: ScrobbleClient] = [:]
    
    init() {
        clients[.lastfm] = LastFmClient()
        clients[.librefm] = LibreFmClient()
        clients[.listenbrainz] = ListenBrainzClient()
    }
    
    private func getClient(for service: ScrobbleService) -> ScrobbleClient? {
        return clients[service]
    }
    
    func client(for service: ScrobbleService) -> ScrobbleClient? {
        return getClient(for: service)
    }
    
    func authenticate(service: ScrobbleService) async throws -> (token: String, authURL: URL) {
        guard let client = getClient(for: service) else {
            throw NSError(domain: "ServiceManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Service not registered"])
        }
        return try await client.authenticate()
    }
    
    func completeAuthentication(service: ScrobbleService, token: String) async throws -> ServiceCredentials {
        guard let client = getClient(for: service) else {
            throw NSError(domain: "ServiceManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Service not registered"])
        }
        let result = try await client.completeAuthentication(token: token)
        return ServiceCredentials(
            service: service,
            token: result.sessionKey,
            username: result.username,
            profileUrl: result.profileUrl,
            isSubscriber: result.isSubscriber,
            isEnabled: true
        )
    }
    
    func updateNowPlaying(credentials: ServiceCredentials, track: Track) async throws {
        guard let client = getClient(for: credentials.service) else { return }
        try await client.updateNowPlaying(sessionKey: credentials.token, track: track)
    }
    
    func scrobble(credentials: ServiceCredentials, track: Track) async throws {
        guard let client = getClient(for: credentials.service) else { return }
        try await client.scrobble(sessionKey: credentials.token, track: track)
    }
    
    func scrobbleAll(track: Track) async {
        let enabledServices = Defaults.shared.enabledServices
        
        for credentials in enabledServices {
            do {
                try await scrobble(credentials: credentials, track: track)
                print("Scrobbled to \(credentials.service.displayName): \(track.description)")
            } catch {
                print("Failed to scrobble to \(credentials.service.displayName): \(error)")
            }
        }
    }
    
    func updateNowPlayingAll(track: Track) async {
        let enabledServices = Defaults.shared.enabledServices
        
        for credentials in enabledServices {
            do {
                try await updateNowPlaying(credentials: credentials, track: track)
                print("Updated now playing on \(credentials.service.displayName): \(track.description)")
            } catch {
                print("Failed to update now playing on \(credentials.service.displayName): \(error)")
            }
        }
    }
}
