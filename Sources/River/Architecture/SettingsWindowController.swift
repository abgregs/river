import AppKit
import Combine
import Observation
import SwiftUI

/// Owns the Settings window (planning 0036, The panel): one native window, built on first use
/// and kept for the session, so it reopens where the user left it and on the section shown
/// last. macOS draws its frame, corner, shadow and window buttons; minimise and zoom are dimmed,
/// as a settings window's should be. It opens on Permissions while one is missing, grows for
/// the Model section, and rechecks the permissions each time it comes forward, since the user
/// grants them in System Settings and comes back.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: SettingsWindowModel
    private var window: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    init(appState: AppState, capabilities: [any Capability], updater: UpdaterManager, selectModel: @escaping (String) -> Void) {
        model = SettingsWindowModel(appState: appState, capabilities: capabilities, updater: updater, selectModel: selectModel)
    }

    /// Follows the permissions for the rail's badge. Idempotent.
    func start() {
        guard subscriptions.isEmpty else { return }
        Publishers.MergeMany(model.capabilities.map { $0.status.map { _ in () } })
            .sink { [weak self] in
                guard let self else { return }
                self.model.permissionMissing = OnboardingGate.shouldPresent(for: self.model.capabilities)
            }
            .store(in: &subscriptions)
    }

    /// "Settings…": shows the window, or brings it forward, and makes River the active app so
    /// the window can take key presses.
    func show() {
        model.section = SettingsSection.opening(lastShown: model.section, permissionMissing: model.permissionMissing)
        let window = self.window ?? makeWindow()
        resize(window, for: model.section, animate: false)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Constants.settingsWindowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Palette.windowTint
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SettingsWindowView(model: model))
        window.center()
        self.window = window
        observeSection()
        return window
    }

    // The window's title is the section shown: hidden on screen, read by VoiceOver and the
    // window list. Its size follows the section.
    private func observeSection() {
        withObservationTracking { _ = model.section } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, let window = self.window else { return }
                self.resize(window, for: self.model.section, animate: true)
                self.observeSection()
            }
        }
    }

    // Keeps the top-left corner where it is, so the rail stays under the pointer as the window
    // grows for the Model section and shrinks back.
    private func resize(_ window: NSWindow, for section: SettingsSection, animate: Bool) {
        window.title = section.label
        let size = section == .model ? Constants.settingsModelWindowSize : Constants.settingsWindowSize
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        guard frame.size != window.frame.size else { return }
        let origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(NSRect(origin: origin, size: frame.size), display: true, animate: animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        let capabilities = model.capabilities
        Task { @MainActor in
            for capability in capabilities { await capability.recheck() }
        }
    }
}
