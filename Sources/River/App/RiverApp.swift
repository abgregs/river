import AppKit
import os
import SwiftUI

@main
struct RiverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                appState: appDelegate.appState,
                cancel: { appDelegate.session.handleCancel() },
                copyLastTranscript: { appDelegate.session.copyLastTranscript() },
                openPermissions: { appDelegate.onboarding.forcePresent() },
                checkForUpdates: { appDelegate.updater.checkForUpdates() }
            )
        } label: {
            MenuBarLabel(appState: appDelegate.appState)
        }

        SwiftUI.Settings {
            SettingsView()
                .tint(Color(nsColor: Palette.accent))
        }
    }
}

private struct MenuBarLabel: View {
    let appState: AppState

    var body: some View {
        switch MenuBarPresentation.visual(
            state: appState.state,
            hasError: appState.errorMessage != nil,
            modelLoadState: appState.modelLoadState
        ).icon {
        case .glyph(let glyph):
            // A template PNG has no name of its own, unlike the SF Symbol it replaces.
            Image(nsImage: MenuBarGlyphImages.image(for: glyph))
                .accessibilityLabel("River")
        case .symbol(let name):
            Image(systemName: name)
        }
    }
}

/// The slat glyph's template images, loaded once from the bundle's Resources, where
/// `make bundle` copies them and `make verify` asserts they ship.
@MainActor
private enum MenuBarGlyphImages {
    private static let logger = Logger(subsystem: Constants.loggingSubsystem, category: "menu-bar")
    private static var cache: [MenuBarPresentation.Glyph: NSImage] = [:]

    static func image(for glyph: MenuBarPresentation.Glyph) -> NSImage {
        if let cached = cache[glyph] { return cached }
        let image: NSImage
        if let loaded = Bundle.main.image(forResource: glyph.rawValue) {
            loaded.isTemplate = true
            image = loaded
        } else {
            // Only an unbundled `swift run` gets here; a bundle without the glyphs fails `make verify`.
            logger.fault("Menu bar glyph \(glyph.rawValue, privacy: .public) missing from the bundle")
            image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil) ?? NSImage()
            image.isTemplate = true
        }
        cache[glyph] = image
        return image
    }
}

private struct MenuBarContent: View {
    let appState: AppState
    /// Discards the in-flight recording (planning 0017). The always-available,
    /// discoverable path to cancel — the mouse-free counterpart is the fn-key
    /// gesture in `HotkeyManager`. Both call the same `RiverSession.handleCancel`.
    let cancel: () -> Void
    /// Writes the last retained transcript to the clipboard (planning 0019).
    /// User-initiated write — the automated cycle never touches the clipboard.
    let copyLastTranscript: () -> Void
    /// Re-opens the permissions window on demand (planning 0012). Wired to
    /// `OnboardingCoordinator.forcePresent()` so users can inspect or refresh
    /// their grants at any time without relaunching.
    let openPermissions: () -> Void
    /// Triggers a user-initiated Sparkle update check (planning 0009). Wired to
    /// `UpdaterManager.checkForUpdates()`; automatic background checks run on
    /// Sparkle's own schedule after the first-launch consent prompt.
    let checkForUpdates: () -> Void
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(MenuBarPresentation.visual(
            state: appState.state,
            hasError: appState.errorMessage != nil,
            modelLoadState: appState.modelLoadState
        ).statusLabel)
        if let errorMessage = appState.errorMessage {
            Text(errorMessage)
        }
        if let notice = appState.notice {
            Text(notice)
        }
        // Only actionable while recording (the session guards it anyway); shown
        // conditionally so it isn't dead UI the rest of the time.
        if appState.state == .recording {
            Divider()
            Button("Cancel Recording", role: .destructive, action: cancel)
                .keyboardShortcut(".")
        }
        Divider()
        // Disabled before the first cycle; enabled after any successful transcription
        // (including when paste fails, which is exactly the recovery case).
        Button("Copy Last Transcription", action: copyLastTranscript)
            .disabled(!appState.hasLastTranscript)
        Divider()
        // Hidden until a real Sparkle key is configured — a menu item that does
        // nothing, or raises an error alert, is worse than no item.
        if UpdaterManager.isConfigured {
            Button("Check for Updates…", action: checkForUpdates)
        }
        Button("Permissions…", action: openPermissions)
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit River") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
