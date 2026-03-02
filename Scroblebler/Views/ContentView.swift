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
    private let syncEngine = SyncEngine.shared

    var body: some View {
        VStack {
            MainView()
                .environmentObject(watcher)
                .environmentObject(serviceManager)
                .environmentObject(defaults)
        }.onLoad {
            watcher.onTrackChanged = { listen in
                Task {
                    // Watcher is the source of truth for current listen state.
                    // Avoid writing it again here, or a delayed network task can overwrite
                    // fresher artwork/metadata updates that arrived meanwhile.
                    _ = await serviceManager.updateNowPlayingAll(listen: listen)
                }
            }
            watcher.onScrobbleWanted = { listen in
                Task {
                    await MainActor.run {
                        Task { await syncEngine.scrobble(listen) }
                    }
                }
            }
            watcher.start()

            // Check if track info arrived before callbacks were set
            watcher.refreshCurrentState()

            // processPending is triggered from AppDelegate after web auth completes
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
