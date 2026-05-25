import Foundation
import SwiftUI
import Sparkle

/// Wraps `SPUStandardUpdaterController` so SwiftUI views can drive
/// "Check for updates…" without us having to roll our own delegate plumbing.
///
/// Sparkle config lives in Info.plist (`SUFeedURL`, `SUPublicEDKey`,
/// `SUEnableAutomaticChecks`). The release engineer:
///
///   1. Runs `generate_keys` (Sparkle binary) once. Stores the printed
///      EdDSA public key in `SUPublicEDKey`. Private key stays in their
///      login keychain.
///   2. Publishes notarized .zips and signs each one with `sign_update`,
///      pasting the resulting `edSignature="..."` into the appcast.xml.
///   3. Uploads appcast.xml + .zip to the hosting URL.
///
/// In Debug builds we initialise with `startingUpdater: false` so dev
/// builds don't fire daily update checks at the placeholder URL.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    let controller: SPUStandardUpdaterController

    override init() {
        #if DEBUG
        let startNow = false
        #else
        let startNow = true
        #endif
        self.controller = SPUStandardUpdaterController(
            startingUpdater: startNow,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
