import Foundation
@testable import Scroblebler

/// Fake implementation of Reachability for testing
/// Provides controllable network state simulation
class FakeReachability {
    var isConnected = true
    private(set) var processCallCount = 0
    
    /// Simulate going offline
    func goOffline() {
        isConnected = false
        Logger.debug("FakeReachability: Network disconnected", log: Logger.sync)
    }
    
    /// Simulate going online
    func goOnline() {
        isConnected = true
        Logger.debug("FakeReachability: Network connected", log: Logger.sync)
    }
    
    /// Simulate network becoming available and trigger processing
    func triggerNetworkAvailable() async {
        isConnected = true
        processCallCount += 1
        Logger.debug("FakeReachability: Network available triggered", log: Logger.sync)
    }
    
    /// Reset state
    func reset() {
        isConnected = true
        processCallCount = 0
    }
}
