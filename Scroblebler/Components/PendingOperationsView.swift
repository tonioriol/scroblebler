import SwiftUI

/// Displays a banner when there are pending offline operations
struct PendingOperationsView: View {
    @State private var pendingCount = 0
    @State private var failedCount = 0
    @State private var isConnected = true
    
    var body: some View {
        Group {
            if pendingCount > 0 || failedCount > 0 {
                HStack(spacing: 8) {
                    if !isConnected {
                        Image(systemName: "wifi.slash")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundColor(.blue)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if pendingCount > 0 {
                            Text("\(pendingCount) operation\(pendingCount == 1 ? "" : "s") queued")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        
                        if failedCount > 0 {
                            Text("\(failedCount) failed (max attempts)")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        
                        if !isConnected {
                            Text("Will sync when online")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if pendingCount > 0 {
                            Text("Syncing...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if failedCount > 0 {
                        Button("Clear Failed") {
                            Task {
                                try? await OfflineQueue.shared.clearFailed()
                                await updateCounts()
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        .onAppear {
            Task {
                await updateCounts()
                // Update periodically
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    await updateCounts()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NetworkStatusChanged"))) { _ in
            Task {
                await updateCounts()
            }
        }
    }
    
    private var backgroundColor: Color {
        if failedCount > 0 {
            return Color.red.opacity(0.1)
        } else if !isConnected {
            return Color.orange.opacity(0.1)
        } else {
            return Color.blue.opacity(0.1)
        }
    }
    
    @MainActor
    private func updateCounts() async {
        pendingCount = await OfflineQueue.shared.count()
        failedCount = await OfflineQueue.shared.failedCount()
        isConnected = Reachability.shared.isConnected
    }
}

#Preview {
    VStack {
        PendingOperationsView()
        Spacer()
    }
    .frame(width: 400, height: 200)
}
