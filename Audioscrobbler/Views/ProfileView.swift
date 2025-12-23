//
//  ProfileView.swift
//  Audioscrobbler
//
//  Created by Audioscrobbler on 23/12/2024.
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var defaults: Defaults
    @EnvironmentObject var webService: WebService
    @State private var userStats: WebService.UserStats?
    @State private var isLoading = true
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: { isPresented = false }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Profile")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(alignment: .center, spacing: 16) {
                        if defaults.picture == nil {
                            Image("avatar")
                                .resizable()
                                .frame(width: 80, height: 80)
                                .cornerRadius(8)
                        } else {
                            Image(nsImage: NSImage(data: defaults.picture!) ?? NSImage(named: "avatar")!)
                                .resizable()
                                .frame(width: 80, height: 80)
                                .cornerRadius(8)
                        }
                        
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Text(defaults.name ?? "")
                                    .font(.system(size: 18, weight: .semibold))
                                if defaults.pro ?? false {
                                    Text("PRO")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.red)
                                        .cornerRadius(3)
                                }
                            }
                            
                            if let url = defaults.url {
                                Link("View on Last.fm", destination: URL(string: url)!)
                                    .font(.system(size: 12))
                            }
                        }
                        .padding(.bottom, 8)
                        
                        if let stats = userStats {
                            VStack(spacing: 12) {
                                StatRow(label: "Scrobbles", value: formatNumber(stats.playcount))
                                Divider()
                                StatRow(label: "Artists", value: formatNumber(stats.artistCount))
                                Divider()
                                StatRow(label: "Tracks", value: formatNumber(stats.lovedCount))
                                Divider()
                                StatRow(label: "Member Since", value: stats.registered)
                            }
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
        .frame(width: 400, height: 600)
        .onAppear {
            loadUserStats()
        }
    }
    
    private func loadUserStats() {
        guard let username = defaults.name else { return }
        isLoading = true
        Task {
            do {
                let stats = try await webService.getUserStats(username: username)
                await MainActor.run {
                    userStats = stats
                    isLoading = false
                }
            } catch {
                print("Failed to load user stats: \(error)")
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
        }
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(isPresented: .constant(true))
    }
}
