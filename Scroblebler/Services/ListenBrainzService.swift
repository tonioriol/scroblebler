import Foundation

/// ListenBrainz service implementation
class ListenBrainzService: Service {
    let client: ScrobbleClient
    
    init(client: ScrobbleClient) {
        self.client = client
    }
    
    func buildURLs(for track: Track) -> (artistURL: URL, albumURL: URL, trackURL: URL) {
        let encodedArtist = track.artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.artist
        let encodedAlbum = track.album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.album
        let encodedTrack = track.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? track.name
        
        let serviceInfo = track.serviceInfo[.listenbrainz]
        
        // Artist URL: use artist MBID if available, otherwise search
        let artistURL: URL
        if let artistMbid = serviceInfo?.artistMbid {
            artistURL = URL(string: "https://listenbrainz.org/artist/\(artistMbid)/")!
        } else {
            artistURL = URL(string: "https://listenbrainz.org/search/?search_term=\(encodedArtist)&search_type=artist")!
        }
        
        // Album URL: use release MBID if available, otherwise search
        let albumURL: URL
        if let releaseMbid = serviceInfo?.releaseMbid {
            albumURL = URL(string: "https://listenbrainz.org/release/\(releaseMbid)/")!
        } else {
            albumURL = URL(string: "https://listenbrainz.org/search/?search_term=\(encodedArtist)%20\(encodedAlbum)&search_type=release")!
        }
        
        // Track URL: use recording MBID if available, otherwise search
        let trackURL: URL
        if let recordingMbid = serviceInfo?.id {
            trackURL = URL(string: "https://listenbrainz.org/track/\(recordingMbid)/")!
        } else {
            trackURL = URL(string: "https://listenbrainz.org/search/?search_term=\(encodedArtist)%20\(encodedTrack)&search_type=recording")!
        }
        
        return (artistURL: artistURL, albumURL: albumURL, trackURL: trackURL)
    }
    
    func enrichTrack(_ track: Track) async -> Track {
        // If track already has all MBIDs, no need to enrich
        let existing = track.serviceInfo[.listenbrainz]
        if existing?.id != nil && existing?.artistMbid != nil && existing?.releaseMbid != nil {
            return track
        }
        
        // Lookup MBIDs via MBID Mapper API
        guard let lbClient = client as? ListenBrainzClient,
              let mbids = try? await lbClient.lookupMBIDsForTrack(
                artist: track.artist,
                track: track.name,
                album: track.album.isEmpty ? nil : track.album
              ),
              let recordingMbid = mbids.recordingMbid else {
            return track
        }
        
        // Update track with all MBIDs (recording, artist, release)
        var enrichedTrack = track
        enrichedTrack.serviceInfo[.listenbrainz] = ServiceTrackData.listenbrainzWithMbids(
            recordingMbid: recordingMbid,
            artistMbid: mbids.artistMbid,
            releaseMbid: mbids.releaseMbid,
            timestamp: track.timestamp
        )
        
        Logger.debug("ListenBrainz enriched '\(track.name)' with MBIDs - recording: \(recordingMbid), artist: \(mbids.artistMbid ?? "none"), release: \(mbids.releaseMbid ?? "none")", log: Logger.ui)
        return enrichedTrack
    }
}
