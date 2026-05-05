import Foundation
import Sparkle

/// Minimal Sparkle updater wrapper.
/// Starts automatic update checks on init; exposes manual check for future UI.
@MainActor
final class SparkleUpdaterController {
    private var controller: SPUStandardUpdaterController!

    init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
