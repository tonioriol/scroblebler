//
//  ContentView.swift
//  Scroblebler
//
//  Created by Victor Gama on 25/11/2022.
//

import SwiftUI

struct ContentView: View {
    @StateObject var watcher = Watcher()
    @StateObject var serviceManager = ScrobbleManager.shared
    @StateObject var defaults = Defaults.shared
    @StateObject var trackStore = TrackStore.shared
    @StateObject var trackService = TrackService.shared

    var body: some View {
        VStack {
            MainView()
                .environmentObject(watcher)
                .environmentObject(serviceManager)
                .environmentObject(defaults)
        }.onLoad {
            watcher.onTrackChanged = { track in
                Task {
                    let enrichedTrack = await serviceManager.updateNowPlayingAll(track: track)
                    await MainActor.run {
                        trackStore.setCurrentTrack(enrichedTrack)
                        // Enrich current track in background
                        Task {
                            await trackService.enrichCurrentTrack()
                        }
                    }
                }
            }
            watcher.onScrobbleWanted = { track in
                Task {
                    await trackService.scrobble(track)
                }
            }
            watcher.start()
            
            // Check if track info arrived before callbacks were set
            watcher.refreshCurrentState()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
