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
            // Back button
            HStack {
                Button(action: { 
                    withAnimation {
                        isPresented = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .padding()
                Spacer()
            }
            
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        if let stats = userStats {
                            VStack(spacing: 16) {
                                StatCard(label: "Scrobbles", value: formatNumber(stats.playcount), icon: "music.note.list")
                                StatCard(label: "Artists", value: formatNumber(stats.artistCount), icon: "person.2.fill")
                                StatCard(label: "Tracks", value: formatNumber(stats.lovedCount), icon: "heart.fill")
                                StatCard(label: "Member Since", value: stats.registered, icon: "calendar")
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
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
}

struct StatCard: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 40, height: 40)
                .background(
                    LinearGradient(colors: [
                        Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 61.0/100.0),
                        Color(hue: 1.0/100.0, saturation: 87.0/100.0, brightness: 89.0/100.0),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 16, weight: .semibold))
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(10)
    }
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView(isPresented: .constant(true))
    }
}
