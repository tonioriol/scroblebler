import SwiftUI

struct MainView: View {
    @EnvironmentObject var watcher: Watcher
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    @State private var showProfileView = false
    @State private var loginService: ScrobbleService?
    @State private var tokenInput = ""
    @State private var passwordInput = ""
    @State private var showPasswordSheet = false
    @State private var pendingLastFmUsername: String?
    @State private var recentTracks: [RecentTrack] = []
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMoreTracks = true
    @State private var loginState: WaitingLogin.Status = .generatingToken

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                mainContent
                    .frame(height: recentTracks.isEmpty ? nil : 600, alignment: .top)
                    .frame(maxHeight: recentTracks.isEmpty ? .infinity : 600)
                
                Divider()
                
                if !showProfileView {
                    Header(showProfileView: $showProfileView)
                        .environmentObject(defaults)
                        .zIndex(10)
                }
            }
            .frame(height: recentTracks.isEmpty ? nil : 655)
            .fixedSize(horizontal: false, vertical: recentTracks.isEmpty)
            .offset(y: showProfileView ? (recentTracks.isEmpty ? -655 : -655) : 0)
            
            if showProfileView {
                VStack(spacing: 0) {
                    Header(showProfileView: $showProfileView)
                        .environmentObject(defaults)
                        .zIndex(10)
                    
                    ProfileView(isPresented: $showProfileView)
                        .frame(height: 600)
                }
                .frame(height: 655)
                .transition(.move(edge: .bottom))
            }
        }
        .frame(width: 400)
        .frame(height: recentTracks.isEmpty ? nil : 655)
        .fixedSize(horizontal: false, vertical: recentTracks.isEmpty)
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
                                        let isLastItem = index == recentTracks.count - 1
                                        print("📊 Track \(index + 1)/\(recentTracks.count) appeared. isLast: \(isLastItem), isLoadingMore: \(isLoadingMore), hasMore: \(hasMoreTracks)")
                                        if isLastItem && !isLoadingMore && hasMoreTracks {
                                            print("🔄 Triggering loadMoreTracks()")
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
            .sheet(isPresented: $showPasswordSheet) {
                if let username = pendingLastFmUsername {
                    PasswordInputSheet(
                        password: $passwordInput,
                        username: username,
                        onSubmit: { Task { await submitPassword() } },
                        onSkip: {
                            showPasswordSheet = false
                            pendingLastFmUsername = nil
                            passwordInput = ""
                        }
                    )
                }
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrobleblerDidShow"))) { _ in
            loadRecentTracks()
        }
    }
    
    private func loadRecentTracks() {
        currentPage = 1
        hasMoreTracks = true
        
        Task {
            do {
                let tracks = try await serviceManager.getAllRecentTracks(limit: 20, page: 1)
                await MainActor.run {
                    recentTracks = tracks
                    // Don't stop pagination based on count - merging can reduce it
                    // Keep trying until we get an empty result
                    hasMoreTracks = !tracks.isEmpty
                    print("📊 Loaded \(tracks.count) tracks, hasMoreTracks: \(hasMoreTracks)")
                }
            } catch {
                print("Failed to load recent tracks: \(error)")
            }
        }
    }
    
    private func loadMoreTracks() {
        guard !isLoadingMore, hasMoreTracks else {
            return
        }
        
        isLoadingMore = true
        let nextPage = currentPage + 1
        
        Task {
            do {
                let tracks = try await serviceManager.getAllRecentTracks(limit: 20, page: nextPage)
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
        
        // Show the popover when auth succeeds
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate,
           let button = appDelegate.statusBarItem.button,
           !appDelegate.popover.isShown {
            await MainActor.run {
                appDelegate.popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
                if let popoverWindow = appDelegate.popover.contentViewController?.view.window {
                    popoverWindow.level = .floating
                    popoverWindow.collectionBehavior = .fullScreenAuxiliary
                    popoverWindow.makeKey()
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        
        // Fetch profile picture for Last.fm
        if service == .lastfm, let client = serviceManager.client(for: .lastfm) as? LastFmClient {
            if let imageData = try? await client.getUserImage(username: credentials.username) {
                await MainActor.run {
                    defaults.picture = imageData
                }
            }
            
            // Prompt for password to enable web deletion
            await MainActor.run {
                pendingLastFmUsername = credentials.username
                loginService = nil
                showPasswordSheet = true
            }
        } else {
            await MainActor.run {
                loginService = nil
            }
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
    
    private func submitPassword() async {
        let password = passwordInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty, let username = pendingLastFmUsername else {
            await MainActor.run {
                showPasswordSheet = false
                pendingLastFmUsername = nil
                passwordInput = ""
            }
            return
        }
        
        do {
            try await serviceManager.setupLastFmWebClient(password: password)
            
            // Store password in Keychain for future use
            try KeychainHelper.shared.savePassword(username: username, password: password)
            print("✓ Last.fm web client setup successful - undo functionality enabled")
            print("✓ Password securely saved to Keychain")
            
            await MainActor.run {
                showPasswordSheet = false
                pendingLastFmUsername = nil
                passwordInput = ""
            }
        } catch {
            print("✗ Failed to setup Last.fm web client: \(error)")
            await MainActor.run {
                showPasswordSheet = false
                pendingLastFmUsername = nil
                passwordInput = ""
            }
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

