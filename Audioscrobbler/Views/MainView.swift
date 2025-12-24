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
    @State var showProfileView: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content with footer at bottom - slides up
            VStack(spacing: 0) {
                mainContent
                    .frame(height: 600)
                
                Divider()
                
                if !showProfileView {
                    AnimatedHeaderView(showProfileView: $showProfileView)
                        .zIndex(10)
                }
            }
            .frame(height: 655)
            .offset(y: showProfileView ? -655 : 0)
            
            // Profile view slides up from bottom
            if showProfileView {
                VStack(spacing: 0) {
                    AnimatedHeaderView(showProfileView: $showProfileView)
                        .zIndex(10)
                    
                    ProfileView(isPresented: $showProfileView)
                        .frame(height: 600)
                }
                .frame(height: 655)
                .transition(.move(edge: .bottom))
            }
        }
        .frame(width: 400, height: 655)
        .clipped()
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: showProfileView)
    }
    
    var mainContent: some View {
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

struct AnimatedHeaderView: View {
    @EnvironmentObject var defaults: Defaults
    @Binding var showProfileView: Bool
    @State var showSignoutScreen = false
    
    var body: some View {
        VStack(alignment: .center) {
            HStack {
                Image("as-logo")
                    .resizable()
                    .frame(width: 46.25, height: 25)
                
                Spacer()
                
                if defaults.name != nil {
                    HStack(spacing: 12) {
                        if showProfileView {
                            VStack(alignment: .trailing, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(defaults.name ?? "")
                                        .font(.system(size: 14, weight: .semibold))
                                    if defaults.pro ?? false {
                                        Text("PRO")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 2)
                                            .background(Color.red)
                                            .cornerRadius(2)
                                    }
                                }
                                
                                if let url = defaults.url {
                                    Link("View on Last.fm", destination: URL(string: url)!)
                                        .font(.system(size: 11))
                                }
                            }
                            .transition(.opacity)
                        } else {
                            VStack(spacing: 2) {
                                HStack(spacing: 0) {
                                    Text(defaults.name ?? "")
                                    if defaults.pro ?? false {
                                        Text("PRO")
                                            .fontWeight(.light)
                                            .font(.system(size: 9))
                                            .offset(y: -5)
                                    }
                                }
                                Button("Sign Out") { showSignoutScreen = true }
                                    .buttonStyle(.link)
                                    .foregroundColor(.white.opacity(0.7))
                                    .alert(isPresented: $showSignoutScreen) {
                                        Alert(title: Text("Signing out will stop scrobbling on this account and remove all local data. Do you wish to continue?"),
                                              primaryButton: .cancel(),
                                              secondaryButton: .default(Text("Continue")) {
                                            defaults.reset()
                                        })
                                    }
                            }
                            .transition(.opacity)
                        }
                        
                        Button(action: {
                            withAnimation {
                                showProfileView.toggle()
                            }
                        }) {
                            if defaults.picture == nil {
                                Image("avatar")
                                    .resizable()
                                    .frame(width: 42, height: 42)
                                    .cornerRadius(4)
                            } else {
                                Image(nsImage: NSImage(data: defaults.picture!) ?? NSImage(named: "avatar")!)
                                    .resizable()
                                    .frame(width: 42, height: 42)
                                    .cornerRadius(4)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }.padding()
        }
        .frame(width: 400, height: 55)
        .background(LinearGradient(colors: [
            Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 61.0/100.0),
            Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 89.0/100.0),
        ], startPoint: .top, endPoint: .bottom))
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
