import AppKit
import Observation
import SwiftUI

/// A borderless panel that can *never* become key or main. Surfacing it during a
/// recording therefore cannot pull focus off the user's frontmost text field, so
/// the paste still lands (planning 0002 acceptance criterion 3 — the load-bearing
/// "never steal focus" constraint). Focus safety is structural: these overrides
/// plus `.nonactivatingPanel` in the style mask, plus the coordinator never calling
/// `makeKey`/`activate` (it uses `orderFrontRegardless` only).
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the recording-indicator HUD panel's lifetime, paralleling
/// `OnboardingCoordinator`'s window-owning pattern so `AppDelegate` stays a thin
/// shell. Observes the shared `AppState` seam (state + toast) and orders the panel
/// in when there is something to show, out (after the fade) when there isn't. The
/// hosted SwiftUI view renders the actual visuals and drives the opacity fade; this
/// layer is deliberately thin — the only decidable logic (visibility) is the pure,
/// unit-tested `RecordingIndicatorPresentation.isOnScreen`.
@MainActor
final class RecordingIndicatorCoordinator {
    private let appState: AppState
    private var panel: NSPanel?
    private var orderOutWork: DispatchWorkItem?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        // Built up front so the first recording fades in instead of appearing already drawn.
        panel = makePanel()
        observeAppState()
        updateVisibility()
    }

    // The HUD's single source of truth is `AppState`. Re-arm the observation on each
    // change (Observation's `onChange` is one-shot) and recompute visibility, so a
    // state transition *or* the toast's own auto-dismiss both flow through the same
    // decision — no timer racing between the two.
    private func observeAppState() {
        withObservationTracking {
            _ = appState.state
            _ = appState.toast
            _ = appState.modelLoadState
            _ = appState.notice
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateVisibility()
                self.observeAppState()
            }
        }
    }

    private func updateVisibility() {
        let shouldShow = RecordingIndicatorPresentation.isOnScreen(
            state: appState.state,
            hasToast: appState.toast != nil,
            modelLoadState: appState.modelLoadState
        )
        if shouldShow {
            orderOutWork?.cancel()
            orderOutWork = nil
            showPanel()
        } else {
            scheduleOrderOut()
        }
    }

    private func showPanel() {
        let panel = panel ?? makePanel()
        self.panel = panel
        positionPanel(panel)
        // `orderFrontRegardless` only — never `makeKey`/`activate`, so focus stays
        // on whatever app the user is dictating into.
        panel.orderFrontRegardless()
    }

    // Delay the actual `orderOut` so the SwiftUI opacity fade completes on screen
    // before the window is removed (planning 0002: "the fade must outlive the state
    // change; animate-then-remove").
    private func scheduleOrderOut() {
        guard panel != nil, orderOutWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.orderOutWork = nil
        }
        orderOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.hudFadeSeconds, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingPanel(
            // One fixed size for every state (the content reserves room for a message),
            // so nothing the view shows can resize or reposition the panel.
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        // Appear over full-screen apps and on every space (planning 0002 AC4).
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: RiverIndicatorView(appState: appState))
        return panel
    }

    static let panelSize = NSSize(
        width: Constants.hudMessageWidth + 2 * Constants.hudShadowMargin,
        height: Constants.hudShadowMargin * 2 + Constants.riverCapsuleHeight
            + Constants.hudStackSpacing + Constants.hudMessageReservedHeight
    )

    // Fixed position (no caret anchoring, so no AX dependency): bottom-center of the
    // active screen's visible frame (planning 0002 "fixed-position, not caret-anchored").
    // The capsule sits a fixed distance below the panel's top edge, so anchoring its
    // bottom edge is arithmetic on constants — a message can never move it.
    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = Self.panelSize
        let capsuleBottomInPanel = size.height - Constants.hudShadowMargin - Constants.riverCapsuleHeight
        panel.setFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.minY + CGFloat(Constants.hudBottomMargin) - capsuleBottomInPanel,
                width: size.width, height: size.height),
            display: false)
    }
}
