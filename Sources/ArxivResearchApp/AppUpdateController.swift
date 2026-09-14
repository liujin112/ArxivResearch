import Foundation
import Sparkle

@MainActor
final class AppUpdateController: ObservableObject {
    let standardUpdaterController: SPUStandardUpdaterController
    let isConfigured: Bool

    init(bundle: Bundle = .main) {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        isConfigured = feedURL?.isEmpty == false && publicKey?.isEmpty == false
        standardUpdaterController = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var currentVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (shortVersion, build) {
        case let (.some(shortVersion), .some(build)) where shortVersion != build:
            return "\(shortVersion) (\(build))"
        case let (.some(shortVersion), _):
            return shortVersion
        case let (_, .some(build)):
            return build
        default:
            return "Development build"
        }
    }

    var automaticallyChecksForUpdates: Bool {
        isConfigured && standardUpdaterController.updater.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        isConfigured && standardUpdaterController.updater.automaticallyDownloadsUpdates
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        objectWillChange.send()
        standardUpdaterController.updater.automaticallyChecksForUpdates = enabled
        if !enabled, automaticallyDownloadsUpdates {
            standardUpdaterController.updater.automaticallyDownloadsUpdates = false
        }
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        objectWillChange.send()
        if enabled {
            standardUpdaterController.updater.automaticallyChecksForUpdates = true
        }
        standardUpdaterController.updater.automaticallyDownloadsUpdates = enabled
    }

    func checkForUpdates() {
        guard isConfigured else { return }
        standardUpdaterController.checkForUpdates(nil)
    }
}
