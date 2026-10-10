import AppKit
import Observation
import SwiftUI

/// Owns the streaming transcript panel's window (0025 prototype): a separate surface from the
/// recording indicator, fixed in size and place, just above the mark. Mirrors
/// `RecordingIndicatorCoordinator`: it observes `AppState`, orders the window in when there is
/// text to show and out after the fade. Unlike the indicator it takes scroll events, so a long
/// transcript can be scrolled; it still can never become key, so the dictation's target keeps
/// focus and the text lands there at release.
@MainActor
final class TranscriptPanelCoordinator {
    private let appState: AppState
    private var panel: NSPanel?
    private var orderOutWork: DispatchWorkItem?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        panel = makePanel()
        observeAppState()
        updateVisibility()
    }

    private func observeAppState() {
        withObservationTracking {
            _ = appState.state
            _ = appState.liveTranscript
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateVisibility()
                self.observeAppState()
            }
        }
    }

    private func updateVisibility() {
        if TranscriptPanelView.isVisible(state: appState.state, text: appState.liveTranscript) {
            orderOutWork?.cancel()
            orderOutWork = nil
            let panel = panel ?? makePanel()
            self.panel = panel
            position(panel)
            // `orderFrontRegardless` only — never `makeKey`/`activate`.
            panel.orderFrontRegardless()
        } else {
            guard panel != nil, orderOutWork == nil else { return }
            // Replaced once it has been on screen, like the indicator's panel: a shown
            // panel can lose every Space when a full-screen Space closes (planning 0030).
            let work = DispatchWorkItem { [weak self] in
                guard let self, let panel = self.panel else { return }
                self.orderOutWork = nil
                let wasShown = panel.isVisible
                panel.orderOut(nil)
                if wasShown {
                    panel.close()
                    self.panel = self.makePanel()
                }
            }
            orderOutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.hudFadeSeconds, execute: work)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // Takes the scroll wheel so a long transcript can be read back; never key.
        panel.ignoresMouseEvents = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: TranscriptPanelView(appState: appState))
        return panel
    }

    static let windowSize = NSSize(
        width: Constants.transcriptPanelWidth + 2 * Constants.hudShadowMargin,
        height: Constants.transcriptPanelHeight + 2 * Constants.hudShadowMargin
    )

    // Centered over the mark, `hudStackSpacing` above its panel, on the active screen.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let surfaceBottom = visible.minY + Constants.hudBottomMargin + Constants.indicatorPanelHeight + Constants.hudStackSpacing
        panel.setFrame(
            NSRect(
                x: visible.midX - Self.windowSize.width / 2,
                y: surfaceBottom - Constants.hudShadowMargin,
                width: Self.windowSize.width, height: Self.windowSize.height),
            display: false)
    }
}
