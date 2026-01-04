import SwiftUI

struct MainView: View {
    @EnvironmentObject var watcher: Watcher
    @EnvironmentObject var serviceManager: ServiceManager
    @EnvironmentObject var defaults: Defaults
    @StateObject private var trackRepo = TrackStore.shared
    @State private var showProfileView = false
    @State private var loginService: ScrobbleService?
    @State private var tokenInput = ""
    @State private var passwordInput = ""
    @State private var showPasswordSheet = false
    @State private var pendingLastFmUsername: String?
    @State private var showWebClientPasswordSheet = false
    @State private var currentPage = 1
    @State private var isLoadingMore = false
    @State private var hasMoreTracks = true
    @State private var loginState: WaitingLogin.Status = .generatingToken
    @State private var isPlaying = false
    
    private var historyTracks: [Track] {
        trackRepo.tracks.filter { $0.scrobbled }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                mainContent
                    .frame(height: historyTracks.isEmpty ? nil : 600, alignment: .top)
                    .frame(maxHeight: historyTracks.isEmpty ? .infinity : 600)
                
                Divider()
                
                if !showProfileView {
                    Header(showProfileView: $showProfileView)
                        .environmentObject(defaults)
                        .zIndex(10)
                }
            }
            .frame(height: historyTracks.isEmpty ? nil : 655)
            .fixedSize(horizontal: false, vertical: historyTracks.isEmpty)
            .offset(y: showProfileView ? (historyTracks.isEmpty ? -655 : -655) : 0)
            
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
        .frame(height: historyTracks.isEmpty ? nil : 655)
        .fixedSize(horizontal: false, vertical: historyTracks.isEmpty)
        .background(Color(NSColor.windowBackgroundColor))
        .clipped()
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: showProfileView)
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
        .sheet(isPresented: $showWebClientPasswordSheet) {
            PasswordInputSheet(
                password: $passwordInput,
                username: pendingLastFmUsername ?? "",
                onSubmit: { Task { await submitWebClientPassword() } },
                onSkip: {
                    showWebClientPasswordSheet = false
                    pendingLastFmUsername = nil
                    passwordInput = ""
                }
            )
        }
    }
    
    var mainContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Focus trap
            TextField("", text: .constant(""))
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
            
            if watcher.currentTrack != nil {
                NowPlaying(track: $watcher.currentTrack, currentPosition: $watcher.currentPosition, isPlaying: $isPlaying)
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
            
            // Pending operations indicator
            PendingOperationsView()
            
            // History section
            if !historyTracks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Recently Scrobbled")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        // Cache rebuild button (ListenBrainz only)
                        if defaults.primaryService?.service == .listenbrainz {
                            Button(action: invalidateCache) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Rebuild playcount cache")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(historyTracks.enumerated()), id: \.element.id) { index, track in
                                HistoryItem(track: track)
                                    .id("\(track.id)-\(track.serviceInfo.keys.map { $0.rawValue }.sorted().joined(separator: ","))")
                                    .onAppear {
                                        let isLastItem = index == historyTracks.count - 1
                                        if isLastItem && !isLoadingMore && hasMoreTracks {
                                            loadMoreTracks()
                                        }
                                    }
                                if index < historyTracks.count - 1 {
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
                        },
                        onSetupWebClient: service == .lastfm ? {
                            pendingLastFmUsername = defaults.credentials(for: .lastfm)?.username
                            showWebClientPasswordSheet = true
                        } : nil
                    )
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .padding(.bottom)
        }
        .onAppear {
            loadRecentTracks()
        }
        .onChange(of: watcher.playerState) { newState in
            isPlaying = newState == .playing
        }
        .onChange(of: defaults.mainServicePreference) { _ in
            loadRecentTracks()
        }
        .onChange(of: serviceManager.lastBackfilledTrack) { event in
            guard let event = event else { return }
            handleBackfillEvent(event)
        }
        .onChange(of: serviceManager.scrobbleCompletedTrigger) { _ in
            loadRecentTracks()
        }
    }
    
    private func loadRecentTracks() {
        currentPage = 1
        hasMoreTracks = true
        
        Task {
            guard let primary = defaults.primaryService else { return }
            
            do {
                try await trackRepo.loadRecent(from: primary, limit: 20, page: 1)
                await MainActor.run {
                    hasMoreTracks = !historyTracks.isEmpty
                }
                // Preload in background without blocking
                Task.detached {
                    await self.preloadImages(for: self.historyTracks)
                }
            } catch {
                Logger.error("Failed to load recent tracks: \(error)", log: Logger.ui)
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
            guard let primary = defaults.primaryService else {
                await MainActor.run { isLoadingMore = false }
                return
            }
            
            do {
                let countBefore = historyTracks.count
                try await trackRepo.loadRecent(from: primary, limit: 20, page: nextPage)
                
                await MainActor.run {
                    let countAfter = historyTracks.count
                    let newTracksCount = countAfter - countBefore
                    
                    if newTracksCount > 0 {
                        currentPage = nextPage
                        hasMoreTracks = newTracksCount >= 20
                    } else {
                        hasMoreTracks = false
                    }
                    isLoadingMore = false
                }
                // Preload in background without blocking
                Task.detached {
                    await self.preloadImages(for: self.historyTracks)
                }
            } catch {
                await MainActor.run {
                    isLoadingMore = false
                }
                Logger.error("Failed to load more tracks: \(error)", log: Logger.ui)
            }
        }
    }
    
    private func preloadImages(for tracks: [Track]) async {
        await withTaskGroup(of: Void.self) { group in
            for track in tracks {
                guard let imageUrl = track.imageUrl else { continue }
                
                group.addTask {
                    // Check if already cached
                    let cached = await MainActor.run { ImageCache.shared.get(imageUrl) }
                    if cached != nil {
                        return
                    }
                    
                    // Load from network
                    guard let url = URL(string: imageUrl) else { return }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        await MainActor.run {
                            ImageCache.shared.set(imageUrl, data: data)
                        }
                    } catch {
                        // Silently fail - not critical
                    }
                }
            }
        }
    }
    
    private func handleBackfillEvent(_ event: BackfillEvent) {
        Logger.info("🔄 UI: Handling backfill event for '\(event.artist) - \(event.track)' to \(event.service.displayName)", log: Logger.ui)
        // Update track in repository
        trackRepo.update(artist: event.artist, track: event.track) { track in
            Logger.debug("  Before update - serviceInfo keys: \(track.serviceInfo.keys.map { $0.rawValue }.joined(separator: ", "))", log: Logger.ui)
            track.serviceInfo[event.service] = ServiceTrackData(
                timestamp: event.timestamp,
                id: nil
            )
            Logger.debug("  After update - serviceInfo keys: \(track.serviceInfo.keys.map { $0.rawValue }.joined(separator: ", "))", log: Logger.ui)
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
            Logger.error("Error preparing \(service.displayName) authentication: \(error)", log: Logger.authentication)
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
                Logger.error("Error during \(service.displayName) authentication: \(error)", log: Logger.authentication)
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
            Logger.error("Error during ListenBrainz token validation: \(error)", log: Logger.authentication)
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
            Logger.info("Last.fm web client setup successful - undo functionality enabled", log: Logger.authentication)
            
            await MainActor.run {
                showPasswordSheet = false
                pendingLastFmUsername = nil
                passwordInput = ""
            }
        } catch {
            Logger.error("Failed to setup Last.fm web client: \(error)", log: Logger.authentication)
            await MainActor.run {
                showPasswordSheet = false
                pendingLastFmUsername = nil
                passwordInput = ""
            }
        }
    }
    
    private func submitWebClientPassword() async {
        let password = passwordInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty, let username = pendingLastFmUsername else {
            await MainActor.run {
                showWebClientPasswordSheet = false
                pendingLastFmUsername = nil
                passwordInput = ""
            }
            return
        }
        
        do {
            try await serviceManager.setupLastFmWebClient(password: password)
            
            // Store password in Keychain for future use
            try KeychainHelper.shared.savePassword(username: username, password: password)
            Logger.info("Last.fm web client setup successful - undo functionality enabled", log: Logger.authentication)
            
            await MainActor.run {
                showWebClientPasswordSheet = false
                pendingLastFmUsername = nil
                passwordInput = ""
            }
        } catch {
            Logger.error("Failed to setup Last.fm web client: \(error)", log: Logger.authentication)
            await MainActor.run {
                showWebClientPasswordSheet = false
                pendingLastFmUsername = nil
                passwordInput = ""
            }
        }
    }
    
    private func invalidateCache() {
        guard let primary = defaults.primaryService,
              primary.service == .listenbrainz,
              let client = serviceManager.client(for: .listenbrainz) as? ListenBrainzClient else {
            return
        }
        
        Logger.info("Cache rebuild triggered", log: Logger.ui)
        Task {
            await client.invalidateAndRebuildCache(username: primary.username)
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
    let onSetupWebClient: (() -> Void)?
    
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
                
                // Show web client setup button for Last.fm
                if let setupAction = onSetupWebClient {
                    Button(action: setupAction) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .help("Setup password for undo functionality")
                }
                
                Button("Logout") { onLogout() }
                    .buttonStyle(.link)
            } else {
                Button("Login") { onLogin() }
                    .buttonStyle(.link)
            }
        }
    }
}

