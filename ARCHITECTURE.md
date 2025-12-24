# Multi-Service Scrobbling

```
┌─────────────┐  ┌─────────────┐  ┌──────────────────┐
│ LastFmClient │  │LibreFmClient  │  │ListenBrainzClient│  (implements ScrobbleClient)
└──────┬──────┘  └──────┬──────┘  └────────┬─────────┘
       │                │                   │
       └────────────────┴───────────────────┘
                        ↓
               ┌────────────────┐
               │ ServiceManager │  (coordinates all clients)
               └────────────────┘
```

## Files

**ScrobbleClient** (`Protocols/ScrobbleClient.swift`)  
Interface defining: `authenticate()`, `completeAuthentication()`, `updateNowPlaying()`, `scrobble()`

**LastFmClient** (`Clients/LastFmClient.swift`)  
Last.fm API client - MD5 signatures, form encoding, all API methods

**LibreFmClient** (`Clients/LibreFmClient.swift`)
Extends LastFmClient, overrides URLs to libre.fm

**ListenBrainzClient** (`Clients/ListenBrainzClient.swift`)
ListenBrainz API client - token-based authentication, JSON API

**ServiceManager** (`ServiceManager.swift`)
Maps services to clients, batch operations, auth flow

**Models** (`Defaults.swift`)
`ScrobbleService` enum (.lastfm, .librefm, .listenbrainz), `ServiceCredentials` storage

## Adding a Service

```swift
// 1. Create client
class ListenBrainzClient: ObservableObject, ScrobbleClient {
    var baseURL: URL { URL(string: "https://api.listenbrainz.org/1/")! }
    func authenticate() async throws -> (token: String, authURL: URL) { ... }
    func scrobble(sessionKey: String, track: Track) async throws { ... }
}

// 2. Add to enum (Defaults.swift)
enum ScrobbleService { case lastfm, librefm, listenbrainz }

// 3. Register (ServiceManager.swift)
init() {
    clients[.lastfm] = LastFmClient()
    clients[.librefm] = LibreFmClient()
    clients[.listenbrainz] = ListenBrainzClient()
}
```
