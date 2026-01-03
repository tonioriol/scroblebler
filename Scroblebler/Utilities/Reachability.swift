import Foundation
import Network

extension Notification.Name {
    static let queueProcessingComplete = Notification.Name("queueProcessingComplete")
}

/// Monitors network connectivity status
class Reachability: ObservableObject {
    static let shared = Reachability()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.scroblebler.reachability")
    
    @Published private(set) var isConnected = true
    @Published private(set) var connectionType: NWInterface.InterfaceType?
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasConnected = self?.isConnected ?? false
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
                
                // Log connection changes
                if let connected = self?.isConnected {
                    if connected && !wasConnected {
                        Logger.info("Network connected", log: Logger.sync)
                        self?.onNetworkAvailable()
                    } else if !connected && wasConnected {
                        Logger.info("Network disconnected", log: Logger.sync)
                    }
                }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    /// Called when network becomes available
    private func onNetworkAvailable() {
        Task {
            await processOfflineQueue()
        }
    }
    
    /// Process queued operations when network becomes available
    private func processOfflineQueue() async {
        let pendingCount = await OfflineQueue.shared.count()
        guard pendingCount > 0 else { return }
        
        Logger.info("Processing \(pendingCount) queued operations", log: Logger.sync)
        
        let operations = await OfflineQueue.shared.dequeue()
        var succeeded = 0
        var failed = 0
        
        for operation in operations {
            do {
                try await executeOperation(operation)
                try await OfflineQueue.shared.remove(operation.id)
                succeeded += 1
                
                // Rate limiting between operations
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                failed += 1
                let errorMsg = error.localizedDescription
                try? await OfflineQueue.shared.incrementAttempts(operation.id, error: errorMsg)
                Logger.error("Operation failed: \(errorMsg)", log: Logger.sync)
            }
        }
        
        Logger.info("Queue processing complete: \(succeeded) succeeded, \(failed) failed", log: Logger.sync)
        
        // Notify UI to refresh if any operations were processed
        if succeeded > 0 || failed > 0 {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .queueProcessingComplete, object: nil)
            }
        }
    }
    
    /// Execute a queued operation
    private func executeOperation(_ operation: Operation) async throws {
        switch operation {
        case .scrobble(let track, let services):
            for service in services {
                guard let creds = Defaults.shared.credentials(for: service) else {
                    Logger.error("No credentials for \(service.displayName)", log: Logger.sync)
                    continue
                }
                try await ServiceManager.shared.scrobble(credentials: creds, track: track)
            }
            Logger.info("Scrobbled: \(track.artist) - \(track.name)", log: Logger.sync)
            
        case .love(let artist, let track, let loved, let services):
            for service in services {
                guard let creds = Defaults.shared.credentials(for: service) else {
                    Logger.error("No credentials for \(service.displayName)", log: Logger.sync)
                    continue
                }
                try await ServiceManager.shared.updateLove(
                    credentials: creds,
                    artist: artist,
                    track: track,
                    loved: loved
                )
            }
            Logger.info("Updated love: \(artist) - \(track) = \(loved)", log: Logger.sync)
            
        case .delete(let artist, let track, let timestamp, let services):
            for service in services {
                guard let creds = Defaults.shared.credentials(for: service) else {
                    Logger.error("No credentials for \(service.displayName)", log: Logger.sync)
                    continue
                }
                let identifier = ScrobbleIdentifier(
                    artist: artist,
                    track: track,
                    timestamp: timestamp,
                    serviceId: nil
                )
                try await ServiceManager.shared.deleteScrobble(
                    credentials: creds,
                    identifier: identifier
                )
            }
            Logger.info("Deleted: \(artist) - \(track)", log: Logger.sync)
        }
    }
    
    deinit {
        monitor.cancel()
    }
}
