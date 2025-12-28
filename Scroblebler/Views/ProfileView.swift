import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var defaults: Defaults
    @EnvironmentObject var serviceManager: ServiceManager
    @State private var userStats: UserStats?
    @State private var topArtists: [TopArtist] = []
    @State private var topAlbums: [TopAlbum] = []
    @State private var topTracks: [TopTrack] = []
    @State private var isLoading = true
    @State private var selectedPeriod = "7day"
    @Binding var isPresented: Bool
    
    let periods = [
        ("7day", "Week"),
        ("1month", "Month"),
        ("3month", "3 Months"),
        ("12month", "Year")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading profile...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if let stats = userStats {
                            // Quick Stats
                            HStack(spacing: 16) {
                                QuickStat(label: "Scrobbles", value: formatNumber(stats.playcount))
                                QuickStat(label: "Artists", value: formatNumber(stats.artistCount))
                                QuickStat(label: "Albums", value: formatNumber(stats.albumCount))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            Divider()
                            
                            // Period Selector
                            HStack(spacing: 8) {
                                ForEach(periods, id: \.0) { period in
                                    Button(action: {
                                        selectedPeriod = period.0
                                        loadTopContent()
                                    }) {
                                        Text(period.1)
                                            .font(.system(size: 11, weight: selectedPeriod == period.0 ? .semibold : .regular))
                                            .foregroundColor(selectedPeriod == period.0 ? .white : .primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                selectedPeriod == period.0 ?
                                                LinearGradient(colors: [
                                                    Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 61.0/100.0),
                                                    Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 89.0/100.0),
                                                ], startPoint: .leading, endPoint: .trailing) :
                                                LinearGradient(colors: [Color.secondary.opacity(0.08)], startPoint: .leading, endPoint: .trailing)
                                            )
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            
                            // Top Artists
                            if !topArtists.isEmpty {
                                SectionHeader(title: "Top Artists")
                                
                                VStack(spacing: 0) {
                                    ForEach(Array(topArtists.prefix(5).enumerated()), id: \.offset) { index, artist in
                                        TopArtistRow(artist: artist, rank: index + 1)
                                        if index < min(4, topArtists.count - 1) {
                                            Divider()
                                                .padding(.leading, 56)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            
                            // Top Albums
                            if !topAlbums.isEmpty {
                                SectionHeader(title: "Top Albums")
                                    .padding(.top, 8)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(Array(topAlbums.prefix(6).enumerated()), id: \.offset) { _, album in
                                            TopAlbumCard(album: album)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                                .frame(height: 160)
                            }
                            
                            // Top Tracks
                            if !topTracks.isEmpty {
                                SectionHeader(title: "Top Tracks")
                                    .padding(.top, 8)
                                
                                VStack(spacing: 0) {
                                    ForEach(Array(topTracks.prefix(10).enumerated()), id: \.offset) { index, track in
                                        TopTrackRow(track: track, rank: index + 1)
                                        if index < min(9, topTracks.count - 1) {
                                            Divider()
                                                .padding(.leading, 40)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 20)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 600)
        .onAppear {
            loadUserData()
        }
        .onChange(of: defaults.mainServicePreference) { _ in
            loadUserData()
        }
    }
    
    private func loadUserData() {
        guard let primary = defaults.primaryService,
              let client = serviceManager.client(for: primary.service) else {
            return
        }
        
        isLoading = true
        Task {
            do {
                async let stats = client.getUserStats(username: primary.username)
                async let artists = client.getTopArtists(username: primary.username, period: selectedPeriod, limit: 10)
                async let albums = client.getTopAlbums(username: primary.username, period: selectedPeriod, limit: 10)
                async let tracks = client.getTopTracks(username: primary.username, period: selectedPeriod, limit: 10)
                
                let (fetchedStats, fetchedArtists, fetchedAlbums, fetchedTracks) = try await (stats, artists, albums, tracks)
                
                await MainActor.run {
                    userStats = fetchedStats
                    topArtists = fetchedArtists
                    topAlbums = fetchedAlbums
                    topTracks = fetchedTracks
                    isLoading = false
                }
            } catch {
                Logger.error("Failed to load user data: \(error)", log: Logger.ui)
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func loadTopContent() {
        guard let primary = defaults.primaryService,
              let client = serviceManager.client(for: primary.service) else {
            return
        }
        
        Task {
            do {
                async let artists = client.getTopArtists(username: primary.username, period: selectedPeriod, limit: 10)
                async let albums = client.getTopAlbums(username: primary.username, period: selectedPeriod, limit: 10)
                async let tracks = client.getTopTracks(username: primary.username, period: selectedPeriod, limit: 10)
                
                let (fetchedArtists, fetchedAlbums, fetchedTracks) = try await (artists, albums, tracks)
                
                await MainActor.run {
                    topArtists = fetchedArtists
                    topAlbums = fetchedAlbums
                    topTracks = fetchedTracks
                }
            } catch {
                Logger.error("Failed to load top content: \(error)", log: Logger.ui)
            }
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1000000 {
            return String(format: "%.1fM", Double(number) / 1000000.0)
        } else if number >= 1000 {
            return String(format: "%.1fK", Double(number) / 1000.0)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

struct QuickStat: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }
}

struct RemoteImage: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let placeholder: String
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .cornerRadius(cornerRadius)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: width, height: height)
                    .overlay(
                        Image(systemName: placeholder)
                            .font(.system(size: width * 0.4))
                            .foregroundColor(.secondary)
                    )
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let url = url, !isLoading else { return }
        isLoading = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                await MainActor.run {
                    self.image = NSImage(data: data)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

struct TopArtistRow: View {
    let artist: TopArtist
    let rank: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            if let imageUrl = artist.imageUrl {
                RemoteImage(
                    url: URL(string: imageUrl),
                    width: 40,
                    height: 40,
                    cornerRadius: 20,
                    placeholder: "music.mic"
                )
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "music.mic")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(artist.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(artist.playcount) scrobbles")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct TopAlbumCard: View {
    let album: TopAlbum
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let imageUrl = album.imageUrl {
                RemoteImage(
                    url: URL(string: imageUrl),
                    width: 100,
                    height: 100,
                    cornerRadius: 6,
                    placeholder: "photo"
                )
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 100, height: 100)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                    )
            }
            
            Text(album.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            
            Text(album.artist)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            
            Text("\(album.playcount) plays")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
}

struct TopTrackRow: View {
    let track: TopTrack
    let rank: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("\(track.playcount)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}
