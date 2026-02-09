import SwiftUI

struct SyncStatusBadge: View {
    @EnvironmentObject var defaults: Defaults

    let syncStatus: SyncStatus
    /// Per-service sync state for this listen (includes pending/failed/etc).
    let serviceStates: [String: ServiceSyncState]
    let sourceService: ScrobbleService?

    var body: some View {
        let enabledServices = defaults.enabledServices.filter { $0.isEnabled }

        // Hide badge when only one service is enabled
        if enabledServices.count <= 1 {
            EmptyView()
        } else {
            HStack(spacing: 2) {
                Image(systemName: syncStatus.icon)
                    .foregroundColor(statusColor)
                    .font(.system(size: 12))
                    .help(tooltipText)
            }
        }
    }

    private var statusColor: Color {
        // Green for synced, red for not synced
        syncStatus == .synced ? .green : .red
    }

    private var tooltipText: String {
        let enabledServices = defaults.enabledServices.map { $0.service }

        var lines: [String] = []

        for service in ScrobbleService.allCases {
            guard enabledServices.contains(service) else { continue }

            let state = serviceStates[service.rawValue]
            let (icon, suffix): (String, String) = {
                guard let state else { return ("✗", "missing") }

                switch state.status {
                case .synced:
                    return ("✓", "synced")
                case .pending:
                    return ("…", "pending")
                case .failed:
                    return ("⚠︎", "failed")
                case .deletePending:
                    return ("…", "delete pending")
                case .deleted:
                    return ("⦸", "deleted")
                }
            }()

            lines.append("\(icon) \(service.displayName) (\(suffix))")
        }

        let statusText = syncStatus == .synced ? "Synced to All Services" : "Not Fully Synced"

        return "\(statusText)\n\n" + lines.joined(separator: "\n")
    }
}
