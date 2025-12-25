import SwiftUI

struct MainView: View {
    @EnvironmentObject var watcher: Watcher
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    @State private var showProfileView = false
    @State private var loginService: ScrobbleService?
    @State private var tokenInput = ""
    @State private var recentTracks: [RecentTrack] = []
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMoreTracks = true
    @State private var loginState: WaitingLogin.Status = .generatingToken

    var body: some View {
        ZStack(alignment: .bottom) {
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
            // Focus trap
            TextField("", text: .constant(""))
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            
            if watcher.currentTrack != nil {
                NowPlaying(track: $watcher.currentTrack, currentPosition: $watcher.currentPosition)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    Image("nocover")
                        .resizable()
                        .cornerRadius(6)
                        .frame(width: 92, height: 92)
                    VStack(alignment: .leading) {
                        Text("It's silent here... There's nothing playing.")
                    }
                }
                .padding()
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
                                HistoryItem(track: track)
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
            
            // Service management
            VStack(spacing: 8) {
                ForEach(ScrobbleService.allCases) { service in
                    ServiceRow(
                        service: service,
                        credentials: defaults.credentials(for: service),
                        isMainService: defaults.mainServicePreference == service,
                        onLogin: {
                            loginService = service
                            loginState = .generatingToken
                            Task { await doServiceLogin(service: service) }
                        },
                        onLogout: {
                            defaults.removeCredentials(for: service)
                        },
                        onToggle: { enabled in
                            defaults.toggleService(service, enabled: enabled)
                        },
                        onSetMain: {
                            defaults.mainServicePreference = service
                        }
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom)
            .sheet(isPresented: Binding(
                get: { loginService != nil && loginService != .listenbrainz },
                set: { if !$0 { loginService = nil } }
            )) {
                WaitingLogin(status: $loginState, onCancel: { loginService = nil })
            }
            .sheet(isPresented: Binding(
                get: { loginService == .listenbrainz },
                set: { if !$0 { loginService = nil; tokenInput = "" } }
            )) {
                TokenInputSheet(
                    token: $tokenInput,
                    onSubmit: { Task { await submitListenBrainzToken() } },
                    onCancel: { loginService = nil; tokenInput = "" }
                )
            }
        }
        .onAppear {
            loadRecentTracks()
        }
        .onChange(of: watcher.currentTrack?.name) { _ in
            loadRecentTracks()
        }
        .onChange(of: defaults.mainServicePreference) { _ in
            loadRecentTracks()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AudioscrobblerDidShow"))) { _ in
            loadRecentTracks()
        }
    }
    
    private func loadRecentTracks() {
        guard let primary = defaults.primaryService,
              let client = serviceManager.client(for: primary.service) else {
            return
        }
        
        currentPage = 1
        hasMoreTracks = true
        
        Task {
            do {
                let tracks = try await client.getRecentTracks(username: primary.username, limit: 20, page: 1, token: primary.token)
                await MainActor.run {
                    recentTracks = tracks
                    hasMoreTracks = tracks.count >= 20
                }
            } catch {
                print("Failed to load recent tracks: \(error)")
            }
        }
    }
    
    private func loadMoreTracks() {
        guard let primary = defaults.primaryService,
              let client = serviceManager.client(for: primary.service),
              !isLoadingMore, hasMoreTracks else {
            return
        }
        
        isLoadingMore = true
        let nextPage = currentPage + 1
        
        Task {
            do {
                let tracks = try await client.getRecentTracks(username: primary.username, limit: 20, page: nextPage, token: primary.token)
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
    
    private func doServiceLogin(service: ScrobbleService) async {
        guard service != .listenbrainz else { return }
        
        let token: String
        let targetURL: URL
        do {
            (token, targetURL) = try await serviceManager.authenticate(service: service)
            NSWorkspace.shared.open(targetURL)
        } catch {
            await MainActor.run { loginService = nil }
            print("Error preparing \(service.displayName) authentication: \(error)")
            return
        }
        
        await MainActor.run { loginState = .waitingForLogin }
        
        var credentials: ServiceCredentials?
        while loginService != nil {
            guard ((try? await Task.sleep(nanoseconds: 2_000_000_000)) != nil) else { return }
            do {
                credentials = try await serviceManager.completeAuthentication(service: service, token: token)
                break
            } catch LastFmClient.Error.apiError(14, _) {
                continue
            } catch {
                await MainActor.run { loginService = nil }
                print("Error during \(service.displayName) authentication: \(error)")
                return
            }
        }
        
        guard loginService != nil, let credentials = credentials else { return }
        
        await MainActor.run {
            loginState = .finishingUp
            defaults.addOrUpdateCredentials(credentials)
            
            // Auto-set as main if no main service configured
            if defaults.mainServicePreference == nil {
                defaults.mainServicePreference = service
            }
        }
        
        // Fetch profile picture for Last.fm
        if service == .lastfm, let client = serviceManager.client(for: .lastfm) as? LastFmClient {
            if let imageData = try? await client.getUserImage(username: credentials.username) {
                await MainActor.run {
                    defaults.picture = imageData
                }
            }
        }
        
        await MainActor.run {
            loginService = nil
        }
    }
    
    private func submitListenBrainzToken() async {
        guard loginService == .listenbrainz else { return }
        
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        do {
            let credentials = try await serviceManager.completeAuthentication(service: .listenbrainz, token: token)
            await MainActor.run {
                defaults.addOrUpdateCredentials(credentials)
                
                // Auto-set as main if no main service configured
                if defaults.mainServicePreference == nil {
                    defaults.mainServicePreference = .listenbrainz
                }
                
                loginService = nil
                tokenInput = ""
            }
        } catch {
            await MainActor.run {
                loginService = nil
                tokenInput = ""
            }
            print("Error during ListenBrainz token validation: \(error)")
        }
    }
}

struct ServiceRow: View {
    let service: ScrobbleService
    let credentials: ServiceCredentials?
    let isMainService: Bool
    let onLogin: () -> Void
    let onLogout: () -> Void
    let onToggle: (Bool) -> Void
    let onSetMain: () -> Void
    
    var body: some View {
        HStack {
            Button(action: {
                if credentials != nil {
                    onSetMain()
                }
            }) {
                Image(systemName: isMainService ? "circle.fill" : "circle")
                    .foregroundColor(isMainService ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(credentials == nil)
            .help("Set as main client for profile view")
            
            Toggle("", isOn: Binding(
                get: { credentials?.isEnabled ?? false },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .disabled(credentials == nil)
            
            Text("Scrobble to \(service.displayName)")
                .foregroundColor(credentials == nil ? .secondary : .primary)
            
            Spacer()
            
            if let credentials = credentials {
                Text(credentials.username)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Button("Logout") { onLogout() }
                    .buttonStyle(.link)
            } else {
                Button("Login") { onLogin() }
                    .buttonStyle(.link)
            }
        }
    }
}

struct AnimatedHeaderView: View {
    @EnvironmentObject var defaults: Defaults
    @Binding var showProfileView: Bool
    @State private var showSignoutScreen = false
    
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
                                        Alert(
                                            title: Text("Signing out will stop scrobbling on this account and remove all local data. Do you wish to continue?"),
                                            primaryButton: .cancel(),
                                            secondaryButton: .default(Text("Continue")) {
                                                defaults.reset()
                                            }
                                        )
                                    }
                            }
                            .transition(.opacity)
                        }
                        
                        Button(action: {
                            withAnimation {
                                showProfileView.toggle()
                            }
                        }) {
                            if let pictureData = defaults.picture,
                               let nsImage = NSImage(data: pictureData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .frame(width: 42, height: 42)
                                    .cornerRadius(4)
                            } else {
                                Image("avatar")
                                    .resizable()
                                    .frame(width: 42, height: 42)
                                    .cornerRadius(4)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .frame(width: 400, height: 55)
        .background(LinearGradient(
            colors: [
                Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 61.0/100.0),
                Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 89.0/100.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        ))
    }
}
