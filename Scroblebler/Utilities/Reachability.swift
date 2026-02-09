import Foundation
import Network

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

            // Also flush any locally-stored pending listens (SyncEngine pipeline).
            // This addresses cases where we have pending DB state but no queued operations.
            await MainActor.run {
                SyncEngine.shared.scheduleProcessPending(reason: "network_available")
            }
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
    }

    /// Execute a queued operation
    private func executeOperation(_ operation: Operation) async throws {
        switch operation {
        case .scrobble(_, let track, let services):
            for service in services {
                guard let creds = Defaults.shared.credentials(for: service) else {
                    Logger.error("No credentials for \(service.displayName)", log: Logger.sync)
                    continue
                }
                try await ScrobbleManager.shared.scrobble(credentials: creds, track: track)
            }
            Logger.info("Scrobbled: \(track.artist) - \(track.name)", log: Logger.sync)

        case .love(_, let artist, let track, let loved, let services):
            for service in services {
                guard let creds = Defaults.shared.credentials(for: service) else {
                    Logger.error("No credentials for \(service.displayName)", log: Logger.sync)
                    continue
                }
                try await ScrobbleManager.shared.updateLove(
                    credentials: creds,
                    artist: artist,
                    track: track,
                    loved: loved
                )
            }
            Logger.info("Updated love: \(artist) - \(track) = \(loved)", log: Logger.sync)

        case .delete(_, let artist, let track, let timestamp, let services):
            for service in services {
                guard let creds = Defaults.shared.credentials(for: service) else {
                    Logger.error("No credentials for \(service.displayName)", log: Logger.sync)
                    continue
                }

                guard let listen = try? await ListenStore.shared.findByTimestamp(artist: artist, track: track, timestamp: timestamp ?? 0),
                      let listenId = listen.id else {
                    Logger.error("Delete retry: missing listen id for '\(artist) - \(track)'", log: Logger.sync)
                    continue
                }

                let identifier = ScrobbleIdentifier(
                    artist: artist,
                    track: track,
                    timestamp: timestamp,
                    serviceId: listen.services[service.rawValue]?.recordingMsid
                )

                try await ScrobbleManager.shared.deleteScrobble(
                    credentials: creds,
                    identifier: identifier
                )
                try? await ListenStore.shared.markDeleted(listenId: listenId, service: service.rawValue)
            }
            Logger.info("Deleted: \(artist) - \(track)", log: Logger.sync)
        }
    }

    deinit {
        monitor.cancel()
    }
}
