import SwiftUI

struct MainView: View {
    @EnvironmentObject var watcher: Watcher
    @EnvironmentObject var serviceManager: ScrobbleManager
    @EnvironmentObject var defaults: Defaults
    @StateObject private var listenStore = ListenStore.shared
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
    @State private var showServicesSection = false
    @State private var historySearchQuery = ""
    @State private var isSearchingHistory = false

    @State private var isHistorySearchFocused = false
    @State private var shouldShowHistorySearchBar = true
    @State private var lastHistoryScrollOffsetY: CGFloat = 0

    // History backfill state (remote → local)
    @State private var backfillTask: Task<Void, Never>?
    @State private var isBackfillingHistory = false

    private let uiPageSize = 50
    private let backfillPageSize = 50
    private let maxVisibleHistoryItems = 400

    private var historyTracks: [Listen] {
        listenStore.history
    }

    private var filteredHistoryTracks: [Listen] { historyTracks }

    private var hasHistorySearchText: Bool {
        !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldRenderHistorySearchBar: Bool {
        shouldShowHistorySearchBar || isHistorySearchFocused || hasHistorySearchText
    }

    private func setHistorySearchBarVisible(_ visible: Bool) {
        guard visible != shouldShowHistorySearchBar else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            shouldShowHistorySearchBar = visible
        }
    }

    private var shouldShowHistorySection: Bool {
        !historyTracks.isEmpty || !historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleHistoryScroll(offsetY newOffsetY: CGFloat) {
        let delta = newOffsetY - lastHistoryScrollOffsetY
        let threshold: CGFloat = 2

        // Always show at the very top.
        if newOffsetY <= 0 {
            setHistorySearchBarVisible(true)
            lastHistoryScrollOffsetY = newOffsetY
            return
        }

        guard abs(delta) > threshold else {
            lastHistoryScrollOffsetY = newOffsetY
            return
        }

        // Scroll down → hide. Scroll up → show.
        if delta > 0 {
            if !hasHistorySearchText && !isHistorySearchFocused {
                setHistorySearchBarVisible(false)
            }
        } else {
            setHistorySearchBarVisible(true)
        }

        lastHistoryScrollOffsetY = newOffsetY
    }

    private struct HistoryScrollOffsetPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    private struct HistoryScrollOffsetEmitter: View {
        let offsetY: CGFloat

        var body: some View {
            Color.clear
                .preference(key: HistoryScrollOffsetPreferenceKey.self, value: offsetY)
        }
    }

    /// Emits a positive `offsetY` where 0 = top, increasing as you scroll down.
    private struct ScrollOffsetReader: View {
        let onChange: (CGFloat) -> Void

        var body: some View {
            GeometryReader { geo in
                let minY = geo.frame(in: .named("historyScroll")).minY
                HistoryScrollOffsetEmitter(offsetY: max(0, -minY))
            }
            .frame(height: 0)
            // Read preference one level above the GeometryReader to avoid
            // "tried to update multiple times per frame" warnings.
            .onPreferenceChange(HistoryScrollOffsetPreferenceKey.self, perform: onChange)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ClickToResignFirstResponder()

            VStack(spacing: 0) {
                mainContent
                    .frame(height: historyTracks.isEmpty ? nil : 600, alignment: .top)
                    .frame(maxHeight: historyTracks.isEmpty ? .infinity : 600)

                Divider()

                if !showProfileView {
                    Header(showProfileView: $showProfileView, showServicesSection: $showServicesSection)
                        .environmentObject(defaults)
                        .zIndex(10)
                }
            }
            .frame(height: historyTracks.isEmpty ? nil : 655)
            .fixedSize(horizontal: false, vertical: historyTracks.isEmpty)
            .offset(y: showProfileView ? (historyTracks.isEmpty ? -655 : -655) : 0)

            if showProfileView {
                VStack(spacing: 0) {
                    Header(showProfileView: $showProfileView, showServicesSection: $showServicesSection)
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
            nowPlayingSection
            Divider()
            PendingOperationsView()
            historySection
            servicesSection
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

    @ViewBuilder
    private var nowPlayingSection: some View {
        if listenStore.currentListen != nil {
            NowPlaying(currentPosition: $watcher.currentPosition, isPlaying: $isPlaying)
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
    }

    @ViewBuilder
    private var historySection: some View {
        if shouldShowHistorySection {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Recently Scrobbled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Cache rebuild button removed.
                    // Playcount is computed from local listens, so there's no cache to rebuild.
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if shouldRenderHistorySearchBar {
                    // Full SQLite search.
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        FocusableTextField(
                            text: $historySearchQuery,
                            placeholder: "Search history",
                            onFocusChange: { focused in
                                isHistorySearchFocused = focused
                            }
                        )
                        .frame(maxWidth: CGFloat.infinity)

                        if !historySearchQuery.isEmpty {
                            Button {
                                historySearchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                            .help("Clear")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onChange(of: historySearchQuery) { newValue in
                        let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !q.isEmpty else {
                            isSearchingHistory = false
                            Task {
                                try? await listenStore.refreshHistory(limit: max(uiPageSize, currentPage * uiPageSize))
                                let total = try? await listenStore.countListens()
                                await MainActor.run {
                                    hasMoreTracks = (total ?? 0) > historyTracks.count || isBackfillingHistory
                                }
                            }
                            return
                        }

                        // Search full SQLite history.
                        isSearchingHistory = true
                        let token = q.lowercased()
                        Task {
                            // Small debounce to avoid querying on every keystroke.
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            // If the query has changed since the debounce started, drop this run.
                            if historySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != token {
                                return
                            }

                            let enabled = Defaults.shared.enabledServices.map { $0.service }
                            if let results = try? await listenStore.search(query: q, limit: maxVisibleHistoryItems, enabledServices: enabled) {
                                await MainActor.run {
                                    listenStore.setHistory(results)
                                    // Disable pagination while searching.
                                    hasMoreTracks = false
                                }
                            }
                        }
                    }
                }

                ScrollView {
                    ScrollOffsetReader { offsetY in
                        handleHistoryScroll(offsetY: offsetY)
                    }

                    LazyVStack(alignment: .leading, spacing: 0) {
                        let visible = filteredHistoryTracks

                        if visible.isEmpty {
                            VStack(alignment: .center) {
                                Text(isSearchingHistory ? "No matches" : "No history yet")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 24)
                                    .frame(maxWidth: .infinity)
                            }
                        }

                        ForEach(Array(visible.enumerated()), id: \.element.historyIdentity) { index, track in
                            HistoryItem(track: track)
                                .onAppear {
                                    // Only auto-paginate when not filtering.
                                    let isFiltering = isSearchingHistory
                                    let isLastItem = index == visible.count - 1
                                    if !isFiltering && isLastItem && !isLoadingMore && hasMoreTracks {
                                        loadMoreTracks()
                                    }
                                }
                            if index < visible.count - 1 {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                        }

                        if !isSearchingHistory && isLoadingMore {
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
                .coordinateSpace(name: "historyScroll")
                .onChange(of: isHistorySearchFocused) { focused in
                    if focused {
                        setHistorySearchBarVisible(true)
                    } else if !hasHistorySearchText {
                        setHistorySearchBarVisible(false)
                    }
                }
                .onChange(of: hasHistorySearchText) { hasText in
                    if hasText {
                        setHistorySearchBarVisible(true)
                    }
                }
            }
            Divider()
        }
    }

    @ViewBuilder
    private var servicesSection: some View {
        if showServicesSection {
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
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func loadRecentTracks() {
        currentPage = 1
        hasMoreTracks = true

        Task {
            do {
                try await listenStore.refreshHistory(limit: uiPageSize)

                // Restore pre-local-history behavior: history artwork came from the service response.
                // Now that history is local-first, older DB rows may be missing `releaseMbid` and/or
                // `imageUrl` until we merge a fresh page from the enabled services.
                let needsArtworkRefresh = listenStore.history.prefix(uiPageSize).contains { listen in
                    let hasRelease = (listen.releaseMbid?.isEmpty == false)
                    let hasImageUrl = (listen.imageUrl?.isEmpty == false)
                    return !hasRelease && !hasImageUrl
                }
                if needsArtworkRefresh {
                    _ = try? await importAndMergeHistoryPage(page: 1, limit: min(20, uiPageSize))
                    try? await listenStore.refreshHistory(limit: uiPageSize)
                }

                // Render from SQLite immediately, then run background backfill until the beginning.
                let total = try await listenStore.countListens()
                let startPage = backfillStartPage(totalListens: total)
                await MainActor.run {
                    hasMoreTracks = total > historyTracks.count || isBackfillingHistory
                    startHistoryBackfillIfNeeded(startPage: startPage, limitPerPage: backfillPageSize)
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

    @MainActor
    private func startHistoryBackfillIfNeeded(startPage: Int, limitPerPage: Int) {
        guard !isBackfillingHistory else { return }

        // If we've already completed a full backfill in a previous session, don't keep hammering
        // remote APIs on every app/popup open. Users can still refresh the visible UI page from
        // SQLite; backfill is a one-time import.
        guard defaults.historyBackfillLastSuccessAt == nil else { return }

        if let task = backfillTask, !task.isCancelled {
            return
        }

        defaults.historyBackfillLastAttemptAt = Date.nowISO8601()
        defaults.historyBackfillLastError = nil
        isBackfillingHistory = true
        backfillTask = Task {
            defer {
                Task { @MainActor in
                    self.isBackfillingHistory = false
                }
            }

            do {
                try await backfillAllHistory(startPage: startPage, limitPerPage: limitPerPage)
                defaults.historyBackfillLastSuccessAt = Date.nowISO8601()
                defaults.historyBackfillLastError = nil
            } catch {
                Logger.error("History backfill failed: \(error)", log: Logger.sync)
                defaults.historyBackfillLastError = String(describing: error)
            }
        }
    }

    /// Import+merge history from ALL enabled services, page-by-page, until we hit the beginning.
    /// This runs in the background; the UI always reads from SQLite.
    @MainActor
    private func backfillAllHistory(startPage: Int, limitPerPage: Int) async throws {
        // Always fetch page 1 first to initialize ListenBrainz pagination state (max_ts).
        _ = try await importAndMergeHistoryPage(page: 1, limit: limitPerPage)

        var page = startPage

        while true {
            let fetchedCount = try await importAndMergeHistoryPage(page: page, limit: limitPerPage)

            // Keep UI in sync without shrinking the list.
            let visibleLimit = max(uiPageSize, currentPage * uiPageSize)
            try? await listenStore.refreshHistory(limit: visibleLimit)
            let total = try? await listenStore.countListens()
            if let total {
                hasMoreTracks = total > historyTracks.count
            }

            if fetchedCount < limitPerPage {
                break
            }

            page += 1

            // Gentle pacing to avoid hammering APIs.
            try await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    /// Fetch one history page from all enabled services, merge/dedup into SQLite, and return the
    /// maximum fetched count (pre-dedup) across services.
    @MainActor
    private func importAndMergeHistoryPage(page: Int, limit: Int) async throws -> Int {
        let enabledServices = defaults.enabledServices
        guard !enabledServices.isEmpty else {
            Logger.debug("No enabled services; skipping history import", log: Logger.sync)
            return 0
        }

        var remoteListens: [Listen] = []
        var maxFetchedCount = 0

        // Simple + predictable: fetch sequentially. (Avoids Swift 6 Sendable issues when capturing
        // non-Sendable ObservableObjects inside concurrent task groups.)
        for credentials in enabledServices {
            let service = credentials.service
            let tracks = try await serviceManager.fetchRecentTracks(service: service, limit: limit, page: page)
            maxFetchedCount = max(maxFetchedCount, tracks.count)

            for track in tracks {
                let info = track.serviceInfo[service]
                var services: [String: ServiceSyncState] = [:]
                services[service.rawValue] = ServiceSyncState(
                    status: .synced,
                    timestamp: info?.timestamp ?? track.timestamp,
                    recordingMsid: info?.recordingMsid,
                    recordingMbid: info?.id,
                    artistMbid: info?.artistMbid,
                    releaseMbid: info?.releaseMbid,
                    error: nil,
                    retryCount: 0,
                    lastAttemptAt: nil
                )

                remoteListens.append(
                    Listen.fromAPI(
                        artist: track.artist,
                        album: track.album,
                        track: track.name,
                        year: nil,
                        duration: track.duration,
                        listenedAt: track.timestamp,
                        loved: track.loved,
                        releaseMbid: info?.releaseMbid,
                        imageUrl: track.imageUrl,
                        sourceBundle: nil,
                        services: services
                    )
                )
            }
        }

        // Merge/dedup into SQLite
        for listen in remoteListens {
            do {
                if let existing = try await listenStore.findByTimestamp(
                    artist: listen.artist,
                    track: listen.track,
                    timestamp: listen.listenedAt
                ) {
                    var updated = existing

                    var didChange = false

                    // Merge per-service states
                    for (service, state) in listen.services {
                        if updated.services[service] != state {
                            updated.services[service] = state
                            didChange = true
                        }
                    }

                    // Conflict rule: remote wins for love state
                    if updated.loved != listen.loved {
                        updated.loved = listen.loved
                        didChange = true
                    }

                    // Prefer first non-nil MBID for cover art
                    if updated.releaseMbid == nil, listen.releaseMbid != nil {
                        updated.releaseMbid = listen.releaseMbid
                        didChange = true
                    }

                    // Preserve old behavior (pre local-history): keep service-provided image URL
                    // when we don't have a release MBID (or when the row was created before we
                    // started persisting it).
                    if updated.imageUrl == nil, listen.imageUrl != nil {
                        updated.imageUrl = listen.imageUrl
                        didChange = true
                    }

                    if didChange {
                        updated.updatedAt = Date.nowISO8601()
                        try await listenStore.update(updated)
                    }
                } else {
                    _ = try await listenStore.insert(listen)
                }
            } catch {
                Logger.debug("History merge skipped for '\(listen.artist) - \(listen.track)': \(error)", log: Logger.sync)
            }
        }

        return maxFetchedCount
    }

    /// Load more tracks for pagination
    ///
    /// IMPORTANT: Pagination logic must use fetchedCount from API, NOT the number of tracks added to UI.
    /// When multiple services are enabled (e.g., Last.fm + ListenBrainz), tracks are merged/deduplicated,
    /// so fewer tracks may be added to the UI than were fetched from the API.
    ///
    /// Example:
    /// - API returns 20 tracks from Last.fm
    /// - After merging with ListenBrainz, only 19 unique tracks are added to UI (1 was duplicate)
    /// - If we check UI count (19 < 20), pagination stops incorrectly
    /// - We must check API count (20 >= 20) to continue pagination correctly
    private func loadMoreTracks() {
        guard !isLoadingMore, hasMoreTracks else {
            Logger.debug("Pagination blocked: isLoadingMore=\(isLoadingMore), hasMoreTracks=\(hasMoreTracks)", log: Logger.ui)
            return
        }

        Logger.info("Loading more tracks - page \(currentPage + 1)", log: Logger.ui)
        isLoadingMore = true
        let nextPage = currentPage + 1

        Task {
            do {
                let countBefore = historyTracks.count
                let oldestBefore = historyTracks.last?.listenedAt
                Logger.debug("Before load: \(countBefore) tracks in UI", log: Logger.ui)

                // Load more from local store
                let newLimit = nextPage * uiPageSize
                try await listenStore.refreshHistory(limit: newLimit)

                // Prevent unbounded UI growth: keep at most N items visible.
                // We keep the *oldest* items currently loaded (suffix), so the user can continue
                // scrolling further back in time.
                await MainActor.run {
                    if historyTracks.count > maxVisibleHistoryItems {
                        let trimmed = Array(historyTracks.suffix(maxVisibleHistoryItems))
                        listenStore.setHistory(trimmed)
                    }
                }

                let oldestAfter = historyTracks.last?.listenedAt
                let advancedToOlderHistory: Bool = {
                    guard let oldestBefore, let oldestAfter else { return false }
                    return oldestAfter < oldestBefore
                }()

                let total = try await listenStore.countListens()

                await MainActor.run {
                    let countAfter = historyTracks.count
                    let addedToUI = countAfter - countBefore

                    Logger.info("After load: \(countAfter) tracks in UI (added \(addedToUI))", log: Logger.ui)

                    if addedToUI > 0 || advancedToOlderHistory {
                        currentPage = nextPage

                        startBackfillIfNeeded(totalListens: total, visibleCount: countAfter)

                        hasMoreTracks = total > countAfter || isBackfillingHistory
                        Logger.debug("Updated: currentPage=\(currentPage), hasMoreTracks=\(hasMoreTracks)", log: Logger.ui)
                    } else {
                        startBackfillIfNeeded(totalListens: total, visibleCount: countAfter)

                        hasMoreTracks = isBackfillingHistory
                        Logger.debug("No more tracks available in SQLite; waiting for backfill", log: Logger.ui)
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

    private func preloadImages(for listens: [Listen]) async {
        await withTaskGroup(of: Void.self) { group in
            for listen in listens {
                guard let releaseMbid = listen.releaseMbid else { continue }
                let imageUrl = CoverArt.coverArtArchiveFrontURL(releaseMbid: releaseMbid, size: 250)

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

    private func backfillStartPage(totalListens: Int) -> Int {
        // Pages are fetched in chunks of backfillPageSize.
        // If we already have N listens locally, start backfill around where we'd expect older pages.
        max(2, (totalListens / backfillPageSize) + 1)
    }

    @MainActor
    private func startBackfillIfNeeded(totalListens: Int, visibleCount: Int) {
        guard !isBackfillingHistory else { return }
        guard totalListens <= visibleCount else { return }

        let startPage = backfillStartPage(totalListens: totalListens)
        Logger.info(
            "Reached end of local history (total=\(totalListens)). Starting background backfill at page \(startPage)",
            log: Logger.sync
        )
        startHistoryBackfillIfNeeded(startPage: startPage, limitPerPage: backfillPageSize)
    }

    private func handleBackfillEvent(_ event: BackfillEvent) {
        Logger.info("🔄 UI: Handling backfill event for '\(event.artist) - \(event.track)' to \(event.service.displayName)", log: Logger.ui)
        // Update listen in store
        Task {
            await MainActor.run {
                listenStore.updateListen(artist: event.artist, track: event.track) { listen in
                    Logger.debug("  Before update - service keys: \(listen.services.keys.joined(separator: ", "))", log: Logger.ui)
                    listen.services[event.service.rawValue] = ServiceSyncState(
                        status: .synced,
                        timestamp: event.timestamp,
                        recordingMsid: nil,
                        recordingMbid: nil,
                        artistMbid: nil,
                        releaseMbid: nil,
                        error: nil,
                        retryCount: 0,
                        lastAttemptAt: nil
                    )
                    Logger.debug("  After update - service keys: \(listen.services.keys.joined(separator: ", "))", log: Logger.ui)
                }
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

    // invalidateCache() removed (no longer needed)
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
