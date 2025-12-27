import SwiftUI

struct SyncStatusBadge: View {
    @EnvironmentObject var defaults: Defaults
    
    let syncStatus: SyncStatus
    let serviceInfo: [String: ServiceTrackData]
    let sourceService: ScrobbleService?
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: syncStatus.icon)
                .foregroundColor(statusColor)
                .font(.system(size: 12))
                .help(tooltipText)
        }
    }
    
    private var statusColor: Color {
        switch syncStatus {
        case .unknown:
            return .gray
        case .synced:
            return .green
        case .partial:
            return .orange
        case .primaryOnly:
            return .red
        }
    }
    
    private var tooltipText: String {
        let enabledServices = defaults.enabledServices.map { $0.service }
        let presentIn = Set(serviceInfo.keys.compactMap { ScrobbleService(rawValue: $0) })
        
        var lines: [String] = []
        
        for service in ScrobbleService.allCases {
            guard enabledServices.contains(service) else { continue }
            
            let icon = presentIn.contains(service) ? "✓" : "✗"
            lines.append("\(icon) \(service.displayName)")
        }
        
        let statusText: String
        switch syncStatus {
        case .unknown:
            statusText = "Sync Status Unknown"
        case .synced:
            statusText = "Synced to All Services"
        case .partial:
            statusText = "Partially Synced"
        case .primaryOnly:
            statusText = "Primary Service Only"
        }
        
        return "\(statusText)\n\n" + lines.joined(separator: "\n")
    }
}
