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
                            // Stats Section Header
                            Text("Your Stats")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                            
                            // Stats Grid
                            VStack(spacing: 12) {
                                HStack(spacing: 12) {
                                    StatCard(
                                        label: "Scrobbles",
                                        value: formatNumber(stats.playcount),
                                        icon: "music.note"
                                    )
                                    
                                    StatCard(
                                        label: "Artists",
                                        value: formatNumber(stats.artistCount),
                                        icon: "person.2"
                                    )
                                }
                                
                                HStack(spacing: 12) {
                                    StatCard(
                                        label: "Tracks",
                                        value: formatNumber(stats.lovedCount),
                                        icon: "music.quarternote.3"
                                    )
                                    
                                    StatCard(
                                        label: "Avg/Day",
                                        value: calculateAvgPerDay(stats.playcount, since: stats.registered),
                                        icon: "chart.line.uptrend.xyaxis"
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            
                            // Member Info Section
                            VStack(spacing: 12) {
                                Divider()
                                    .padding(.vertical, 8)
                                
                                Text("Member Info")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                
                                InfoRow(icon: "calendar", label: "Member Since", value: stats.registered)
                                InfoRow(icon: "music.note.list", label: "Total Plays", value: formatNumber(stats.playcount))
                                
                                if let url = defaults.url {
                                    Divider()
                                        .padding(.horizontal, 16)
                                    
                                    Link(destination: URL(string: url)!) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "safari")
                                                .font(.system(size: 14))
                                                .foregroundColor(.accentColor)
                                                .frame(width: 24)
                                            
                                            Text("View Full Profile on Last.fm")
                                                .font(.system(size: 13))
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            Image(systemName: "arrow.up.forward")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.bottom, 20)
                        }
                    }
                }
            }
        }
        .frame(height: 600)
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
    
    private func calculateAvgPerDay(_ totalScrobbles: Int, since registeredDate: String) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        guard let date = formatter.date(from: registeredDate) else {
            return "—"
        }
        
        let daysSince = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 1
        let avgPerDay = daysSince > 0 ? Double(totalScrobbles) / Double(daysSince) : 0
        
        if avgPerDay >= 100 {
            return String(format: "%.0f", avgPerDay)
        } else if avgPerDay >= 10 {
            return String(format: "%.1f", avgPerDay)
        } else {
            return String(format: "%.1f", avgPerDay)
        }
    }
}

struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(colors: [
                        Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 61.0/100.0),
                        Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 89.0/100.0),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .cornerRadius(10)
            
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)
            
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(12)
    }
}

struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(isPresented: .constant(true))
    }
}
