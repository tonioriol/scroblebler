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
    @StateObject var listenStore = ListenStore.shared

    var body: some View {
        VStack {
            MainView()
                .environmentObject(watcher)
                .environmentObject(serviceManager)
                .environmentObject(defaults)
        }.onLoad {
            watcher.onTrackChanged = { listen in
                Task {
                    let enrichedListen = await serviceManager.updateNowPlayingAll(listen: listen)
                    await MainActor.run {
                        listenStore.setCurrentListen(enrichedListen)
                    }
                }
            }
            watcher.onScrobbleWanted = { listen in
                Task {
                    await MainActor.run {
                        let syncEngine = SyncEngine.makeDefault()
                        Task { await syncEngine.scrobble(listen) }
                    }
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
