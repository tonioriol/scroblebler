//
//  MainView.swift
//  Audioscrobbler
//
//  Created by Victor Gama on 24/11/2022.
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject var watcher: Watcher
    @EnvironmentObject var webService: WebService
    @EnvironmentObject var defaults: Defaults
    @State var privateSession: Bool = false
    @State var showPrivateSessionPopover: Bool = false
    @State var recentTracks: [WebService.RecentTrack] = []
    @State var trackPlayCounts: [String: Int] = [:]
    @State var currentPage: Int = 1
    @State var isLoadingMore: Bool = false
    @State var hasMoreTracks: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if watcher.currentTrack != nil {
                PlayingItemView(track: $watcher.currentTrack, currentPosition: $watcher.currentPosition)
                    .opacity(defaults.privateSession ? 0.6 : 1)
                    .scaleEffect(defaults.privateSession ? 0.9 : 1)
                    .animation(.easeOut)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    Image("nocover")
                        .resizable()
                        .cornerRadius(6)
                        .frame(width: 92, height: 92)
                    VStack(alignment: .leading) {
                        Text("It's silent here... There's nothing playing.")
                    }
                }.padding()
            }
            Divider()
            
            // History section
            if !recentTracks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recently Scrobbled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(recentTracks.enumerated()), id: \.offset) { index, track in
                                HistoryItemView(track: track, playCount: trackPlayCounts["\(track.artist)|\(track.name)"])
                                    .onAppear {
                                        if index == recentTracks.count - 1 && !isLoadingMore && hasMoreTracks {
                                            loadMoreTracks()
                                        }
                                    }
                                if index < recentTracks.count - 1 {
                                    Divider()
                                        .padding(.horizontal, 16)
                                }
                            }
                            
                            if isLoadingMore {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .padding(.vertical, 8)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 500)
                }
                Divider()
            }
            
            HStack {
                Toggle("", isOn: $defaults.privateSession)
                    .toggleStyle(.switch)
                Text("Private Session")
                Button(action: { showPrivateSessionPopover = true }) {
                    Image(nsImage: NSImage(named: NSImage.Name("NSTouchBarGetInfoTemplate"))!)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showPrivateSessionPopover) {
                    Text("A private session will prevent tracks from being scrobbled as long as it is turned on")
                        .padding()
                }
            }.padding()
            Divider()
            HeaderView()
        }
        .onAppear {
            loadRecentTracks()
        }
        .onChange(of: watcher.currentTrack?.name) { _ in
            loadRecentTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AudioscrobblerDidShow"))) { _ in
            loadRecentTracks()
        }
    }
    
    func loadRecentTracks() {
        guard let username = defaults.name, let token = defaults.token else { return }
        currentPage = 1
        hasMoreTracks = true
        Task {
            do {
                let tracks = try await webService.getRecentTracks(username: username, limit: 20, page: 1)
                await fetchPlayCountsForTracks(tracks, token: token)
                await MainActor.run {
                    recentTracks = tracks
                    hasMoreTracks = tracks.count >= 20
                }
            } catch {
                print("Failed to load recent tracks: \(error)")
            }
        }
    }
    
    func loadMoreTracks() {
        guard let username = defaults.name, let token = defaults.token, !isLoadingMore, hasMoreTracks else { return }
        isLoadingMore = true
        let nextPage = currentPage + 1
        
        Task {
            do {
                let tracks = try await webService.getRecentTracks(username: username, limit: 20, page: nextPage)
                await fetchPlayCountsForTracks(tracks, token: token)
                await MainActor.run {
                    if !tracks.isEmpty {
                        recentTracks.append(contentsOf: tracks)
                        currentPage = nextPage
                        hasMoreTracks = tracks.count >= 20
                    } else {
                        hasMoreTracks = false
                    }
                    isLoadingMore = false
                }
            } catch {
                await MainActor.run {
                    isLoadingMore = false
                }
                print("Failed to load more tracks: \(error)")
            }
        }
    }
    
    func fetchPlayCountsForTracks(_ tracks: [WebService.RecentTrack], token: String) async {
        await withTaskGroup(of: (String, Int?).self) { group in
            for track in tracks {
                group.addTask {
                    let key = "\(track.artist)|\(track.name)"
                    let count = try? await self.webService.getTrackUserPlaycount(token: token, artist: track.artist, track: track.name)
                    return (key, count)
                }
            }
            
            for await (key, count) in group {
                await MainActor.run {
                    if let count = count {
                        trackPlayCounts[key] = count
                    }
                }
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
