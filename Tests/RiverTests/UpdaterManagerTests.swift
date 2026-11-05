import Foundation
import Testing
@testable import River

@Suite("UpdaterManager key check")
struct UpdaterManagerTests {
    // Sparkle raises a blocking "updater failed to start" alert on launch when
    // SUPublicEDKey is invalid. The placeholder shipped in Info.plist until the
    // first-release keypair exists must therefore read as unconfigured, while a
    // real key must read as configured with no code change.

    @Test("the Info.plist placeholder is not a usable key")
    func placeholderIsRejected() {
        #expect(!UpdaterManager.isUsableEdDSAPublicKey("REPLACE_WITH_SPARKLE_ED_PUBLIC_KEY"))
    }

    @Test("a missing or empty key is not usable")
    func missingOrEmptyIsRejected() {
        #expect(!UpdaterManager.isUsableEdDSAPublicKey(nil))
        #expect(!UpdaterManager.isUsableEdDSAPublicKey(""))
    }

    @Test("a base64 string of the wrong length is not usable")
    func wrongLengthIsRejected() {
        #expect(!UpdaterManager.isUsableEdDSAPublicKey(Data(count: 16).base64EncodedString()))
    }

    @Test("a 32-byte base64 key is usable")
    func realShapedKeyIsAccepted() {
        #expect(UpdaterManager.isUsableEdDSAPublicKey(Data(count: 32).base64EncodedString()))
    }
}

@Suite("UpdaterManager release gate")
struct UpdaterManagerReleaseGateTests {
    // A dev build has CFBundleVersion 1, so a running updater sees the public
    // release as newer and silently replaces the dev build in /Applications.
    // Only a release build may start the updater, even with a real key.

    private let realKey = Data(count: 32).base64EncodedString()

    @Test("a dev build never starts the updater, even with a real key")
    func devBuildDoesNotStart() {
        #expect(!UpdaterManager.shouldStart(isReleaseBuild: false, publicKey: realKey))
    }

    @Test("a release build with a real key starts the updater")
    func releaseBuildStarts() {
        #expect(UpdaterManager.shouldStart(isReleaseBuild: true, publicKey: realKey))
    }

    @Test("a release build with the placeholder key does not start")
    func releaseBuildWithPlaceholderDoesNotStart() {
        #expect(!UpdaterManager.shouldStart(isReleaseBuild: true, publicKey: "REPLACE_WITH_SPARKLE_ED_PUBLIC_KEY"))
    }

    @Test("the compile condition sets isReleaseBuild")
    func compileConditionSetsFlag() {
        #if RIVER_RELEASE
        #expect(UpdaterManager.isReleaseBuild)
        #else
        #expect(!UpdaterManager.isReleaseBuild)
        #endif
    }
}
