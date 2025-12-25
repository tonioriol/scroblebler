//
//  ContentView.swift
//  Audioscrobbler
//
//  Created by Victor Gama on 25/11/2022.
//

import SwiftUI

struct ContentView: View {
    @StateObject var watcher = Watcher()
    @StateObject var serviceManager = ServiceManager.shared
    @StateObject var defaults = Defaults.shared

    var body: some View {
        VStack {
            MainView()
                .environmentObject(watcher)
                .environmentObject(serviceManager)
                .environmentObject(defaults)
        }.onLoad {
            watcher.onTrackChanged = { track in
                Task {
                    await serviceManager.updateNowPlayingAll(track: track)
                }
            }
            watcher.onScrobbleWanted = { track in
                Task {
                    await serviceManager.scrobbleAll(track: track)
                }
            }
            watcher.start()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
