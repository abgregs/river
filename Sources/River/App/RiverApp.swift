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
                cancelWaiting: { appDelegate.session.cancelWaiting() },
                copyLastTranscript: { appDelegate.session.copyLastTranscript() },
                checkForUpdates: { appDelegate.updater.checkForUpdates() },
                openSettings: { appDelegate.settingsWindow.show() }
            )
        } label: {
            MenuBarLabel(appState: appDelegate.appState)
        }
    }
}

private struct MenuBarLabel: View {
    let appState: AppState

    var body: some View {
        let visual = MenuBarPresentation.visual(
            state: appState.state,
            hasError: appState.errorMessage != nil,
            modelLoadState: appState.modelLoadState,
            fraction: appState.downloadFraction
        )
        switch visual.icon {
        case .glyph(let glyph):
            // A glyph PNG has no name of its own, unlike the SF Symbol it replaces.
            Image(nsImage: MenuBarGlyphImages.image(for: glyph))
                .accessibilityLabel("River")
        case .ring(let ring):
            Image(nsImage: MenuBarRingImages.icon(for: ring))
                .accessibilityLabel("River: \(visual.statusLabel)")
        case .symbol(let name):
            Image(systemName: name)
        }
    }
}

/// The model's status ring in the menu bar and its menu (planning 0004): a still frame of the
/// ring the indicator and Settings draw, made at runtime by the same renderer, at both screen
/// scales, and kept per step, so a download redraws the icon eight times at most.
@MainActor
enum MenuBarRingImages {
    private static var cache: [String: NSImage] = [:]

    /// The menu bar's icon: one tone, a failure's sign too, as a template image the bar paints
    /// as it paints the icons beside it.
    static func icon(for ring: MenuBarPresentation.Ring) -> NSImage {
        image(ring, size: Constants.menuBarGlyphSize, ring: Constants.menuBarRingSize, ink: .black, akane: .black, key: "icon")
    }

    /// The glyph beside the menu's status line: a template image in the menu's text colour, or
    /// a failure in akane for the menu's appearance.
    static func statusGlyph(for ring: MenuBarPresentation.Ring, dark: Bool) -> NSImage {
        let size = Constants.menuStatusRingSize
        guard ring.phase == .failed else { return image(ring, size: size, ring: size, ink: .black, akane: .black, key: "status") }
        return image(ring, size: size, ring: size, ink: dark ? Palette.ink : Palette.charcoal,
                     akane: dark ? Palette.akaneOnDark : Palette.akane, key: dark ? "status-dark" : "status-light", template: false)
    }

    private static func image(_ ring: MenuBarPresentation.Ring, size: Double, ring box: Double, ink: NSColor, akane: NSColor,
                              key: String, template: Bool = true) -> NSImage {
        let key = "\(key)-\(ring.phase)-\(ring.eighths ?? -1)"
        if let cached = cache[key] { return cached }
        let frame = ring.frame
        let canvas = Canvas { context, canvasSize in
            let inset = (canvasSize.width - box) / 2
            var context = context
            context.translateBy(x: inset, y: inset)
            StatusRingRenderer.draw(frame, in: &context, size: CGSize(width: box, height: box), ink: ink, akane: akane)
        }
        .frame(width: size, height: size)
        let image = NSImage(size: NSSize(width: size, height: size))
        for scale in [1.0, 2.0] {
            let renderer = ImageRenderer(content: canvas)
            renderer.scale = scale
            guard let cgImage = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            rep.size = image.size
            image.addRepresentation(rep)
        }
        image.isTemplate = template
        cache[key] = image
        return image
    }
}

/// The mark's menu bar images. The PNGs are loaded once from the bundle's Resources, where
/// `make bundle` copies them and `make verify` asserts they ship, as template images, because
/// the menu bar takes its look from the wallpaper behind it, not from Light or Dark mode: a fixed
/// color picked from the system appearance measured about 1.5:1 on a tinted bar (2026-10-15). A
/// template image cannot carry the recording red, so Listening and Transcribing are drawn when the
/// bar draws them, and both their mark and their dot follow the bar's own appearance.
@MainActor
enum MenuBarGlyphImages {
    private static let logger = Logger(subsystem: Constants.loggingSubsystem, category: "menu-bar")
    private static var assets: [String: NSImage] = [:]

    static func image(for glyph: MenuBarPresentation.Glyph) -> NSImage {
        let asset = asset(named: glyph.assetName)
        switch glyph {
        case .ready: return asset
        case .listening: return withDot(asset, muted: false)
        case .transcribing: return withDot(asset, muted: true)
        }
    }

    private static func asset(named name: String) -> NSImage {
        if let cached = assets[name] { return cached }
        let image: NSImage
        if let loaded = Bundle.main.image(forResource: name) {
            image = loaded
        } else {
            // Only an unbundled `swift run` gets here; a bundle without the glyphs fails `make verify`.
            logger.fault("Menu bar glyph \(name, privacy: .public) missing from the bundle")
            image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil) ?? NSImage()
        }
        image.isTemplate = true
        assets[name] = image
        return image
    }

    // internal for testability: the drawing is checked in each appearance without a menu bar.
    /// `mark` in the menu bar's text color with the dot at its place: the recording red, or
    /// the text color at `menuBarMutedDotOpacity` while River transcribes. Drawn each time the
    /// bar draws it, under the bar's appearance, so a wallpaper that turns the bar dark turns
    /// the mark white and the red to its dark-bar value, as the template icons beside it turn.
    static func withDot(_ mark: NSImage, muted: Bool) -> NSImage {
        let size = NSSize(width: Constants.menuBarGlyphSize, height: Constants.menuBarGlyphSize)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.labelColor.setFill()
            rect.fill()
            mark.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1, respectFlipped: true, hints: nil)
            // Resolved here, in the drawing's appearance.
            let ink = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
            (muted ? ink.withAlphaComponent(ink.alphaComponent * Constants.menuBarMutedDotOpacity) : Palette.recording).setFill()
            NSBezierPath(ovalIn: Constants.menuBarSign).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

private struct MenuBarContent: View {
    let appState: AppState
    /// Discards the in-flight recording (planning 0017). The always-available,
    /// discoverable path to cancel — the mouse-free counterpart is the fn-key
    /// gesture in `HotkeyManager`. Both call the same `RiverSession.handleCancel`.
    let cancel: () -> Void
    /// Throws away a dictation waiting for the model (planning 0004): the way out of a long
    /// wait. The model keeps loading.
    let cancelWaiting: () -> Void
    /// Writes the last retained transcript to the clipboard (planning 0019).
    /// User-initiated write — the automated cycle never touches the clipboard.
    let copyLastTranscript: () -> Void
    /// Triggers a user-initiated Sparkle update check (planning 0009). Wired to
    /// `UpdaterManager.checkForUpdates()`; automatic background checks run on
    /// Sparkle's own schedule after the first-launch consent prompt.
    let checkForUpdates: () -> Void
    /// Opens the Settings window (planning 0036), which holds the Permissions section that
    /// replaced the "Permissions…" item.
    let openSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let visual = MenuBarPresentation.visual(
            state: appState.state,
            hasError: appState.errorMessage != nil,
            modelLoadState: appState.modelLoadState,
            fraction: appState.downloadFraction
        )
        if let ring = visual.statusRing {
            Label {
                Text(visual.statusLabel)
            } icon: {
                Image(nsImage: MenuBarRingImages.statusGlyph(for: ring, dark: colorScheme == .dark))
            }
        } else {
            Text(visual.statusLabel)
        }
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
        // Only while a dictation waits for the model: a new one would wait for the same model,
        // so cancelling, not keeping, is the way out of a long wait.
        if appState.isDictationWaiting {
            Divider()
            Button("Cancel Dictation", role: .destructive, action: cancelWaiting)
                .keyboardShortcut(".")
        }
        Divider()
        // Disabled before the first cycle; enabled after any successful transcription
        // (including when paste fails, which is exactly the recovery case).
        Button("Copy Last Transcription", action: copyLastTranscript)
            .disabled(!appState.hasLastTranscript)
        Divider()
        // Hidden in dev builds and until a real Sparkle key is configured — a
        // menu item that does nothing, or raises an error alert, is worse than
        // no item.
        if UpdaterManager.isEnabled {
            Button("Check for Updates…", action: checkForUpdates)
        }
        Button("Settings…", action: openSettings)
            .keyboardShortcut(",")
        Divider()
        Button("Quit River") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
