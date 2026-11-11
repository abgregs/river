import Foundation
import os
import Sparkle

/// Owns the app's single Sparkle updater (planning 0009). The one place
/// `SPUStandardUpdaterController` is constructed — the updater's background
/// scheduler, first-launch consent prompt, and "Check for Updates…" action all
/// route through here, so there is no second update-check surface (mirrors the
/// one-call-site rule the capabilities layer enforces for OS APIs).
@MainActor
final class UpdaterManager {
    private var controller: SPUStandardUpdaterController?
    private let logger = Logger(subsystem: Constants.loggingSubsystem, category: "update")

    /// Whether the release pipeline compiled this binary (`RIVER_RELEASE`). A
    /// local `make install` build has `CFBundleVersion` 1, so a running updater
    /// would see the public release as newer and replace the dev build with it.
    nonisolated static let isReleaseBuild: Bool = {
        #if RIVER_RELEASE
        true
        #else
        false
        #endif
    }()

    /// Whether the updater may start in this build. Known before `start()` runs,
    /// so the menu can decide whether to offer "Check for Updates…" at all.
    static var isEnabled: Bool {
        shouldStart(
            isReleaseBuild: isReleaseBuild,
            publicKey: Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        )
    }

    // internal for testability — only a release build with a usable key starts.
    nonisolated static func shouldStart(isReleaseBuild: Bool, publicKey: String?) -> Bool {
        isReleaseBuild && isUsableEdDSAPublicKey(publicKey)
    }

    // internal for testability — an Ed25519 public key is 32 bytes, base64-encoded.
    // Rejects nil, the placeholder string, and anything that decodes to the wrong size.
    nonisolated static func isUsableEdDSAPublicKey(_ value: String?) -> Bool {
        guard let value, let data = Data(base64Encoded: value) else { return false }
        return data.count == 32
    }

    /// Constructs and starts the updater. Deferred behind `start()` (rather than
    /// running in `init`) so it only spins up in the real app from
    /// `applicationDidFinishLaunching` — never in `swift test`, which never calls
    /// this. `startingUpdater: true` schedules periodic checks and, on first run,
    /// shows Sparkle's built-in "check for updates automatically?" consent prompt,
    /// keeping the second network behaviour transparent (core-feature.md item 6).
    func start() {
        guard controller == nil else { return }
        // A dev build never starts the updater: no scheduled checks, no feed
        // requests, and no chance to overwrite itself with the public release.
        guard Self.isReleaseBuild else {
            logger.info("Sparkle not started: dev build (compiled without RIVER_RELEASE)")
            return
        }
        // Sparkle validates SUPublicEDKey on start and shows a blocking "updater
        // failed to start" alert when it is invalid. If the key is missing or a
        // placeholder (a malformed bundle, or a fork without its own keypair),
        // don't start at all: no alert, no feed requests.
        guard Self.isEnabled else {
            logger.info("Sparkle not started: SUPublicEDKey is missing or a placeholder")
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Sparkle's own "check automatically" preference, behind the Settings toggle (planning
    /// 0036): River declares no key for it, so Sparkle's first-launch answer and this toggle
    /// are one value. `nil` until `start()` has run, so a dev build has no toggle to show.
    var automaticallyChecksForUpdates: Bool? {
        controller?.updater.automaticallyChecksForUpdates
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    /// User-initiated update check, wired to the "Check for Updates…" menu item.
    /// No-op until `start()` has run.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
