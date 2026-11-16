import Cocoa
import Sparkle

/// Sparkle owns downloading, signature verification, replacement, rollback and relaunch.
/// All interaction with its user driver happens on the main thread.
final class VersionChecker: NSObject {
    static let shared = VersionChecker()
    let updaterController: SPUStandardUpdaterController

    private override init() {
        precondition(Thread.isMainThread)
        updaterController = SPUStandardUpdaterController(startingUpdater: true,
                                                         updaterDelegate: nil,
                                                         userDriverDelegate: nil)
        super.init()
        // The published feed is fixed in Info.plist, rather than a cached development feed.
        updaterController.updater.clearFeedURLFromUserDefaults()
    }

    func configure(menuItem: NSMenuItem) {
        precondition(Thread.isMainThread)
        menuItem.title = NSLocalizedString("Check and Install Updates…", comment: "")
        menuItem.target = updaterController
        menuItem.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
    }

    func checkForUpdates(userInitiated: Bool) {
        precondition(Thread.isMainThread)
        guard updaterController.updater.canCheckForUpdates else { return }
        if userInitiated {
            updaterController.checkForUpdates(nil)
        } else {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }
}
