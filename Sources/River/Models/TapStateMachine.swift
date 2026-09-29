import Foundation

/// Interprets completed taps into start/stop actions for the two tap activation
/// modes. Pure and clock-injectable so the double-tap timing is unit-testable
/// without a real `CGEventTap` (the reason it's extracted from `HotkeyManager`).
/// `HotkeyManager` owns the trivial key-down→key-up pairing and calls `handleTap`
/// on each completed tap; Hold mode never routes here. See
/// requirements/activation-key-and-mode.md.
///
/// It keeps only the double-tap timing. Whether a recording is live is the
/// session's state, passed in on every tap: a start the session refuses (model not
/// ready, permission denied, a dictation still transcribing) leaves nothing here
/// to undo, so the user's next tap is never read as a stop.
@MainActor
final class TapStateMachine {
    enum Action: Equatable { case start, stop, none }

    enum State: Equatable {
        case idle
        case awaitingSecondTap(since: TimeInterval)  // double-tap only
    }

    private(set) var state: State = .idle
    private var mode: ActivationMode
    private let windowMs: Int
    private let now: () -> TimeInterval

    init(
        mode: ActivationMode,
        windowMs: Int,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.mode = mode
        self.windowMs = windowMs
        self.now = now
    }

    /// Advances on one completed tap (key-down then key-up) and returns the action
    /// the hotkey should fire. `isRecording` is the session's own state.
    func handleTap(isRecording: Bool) -> Action {
        switch mode {
        case .hold:
            return .none  // Hold is handled inline by HotkeyManager, never here.
        case .singleTap:
            return isRecording ? .stop : .start
        case .doubleTap:
            if isRecording {
                state = .idle
                return .stop
            }
            let t = now()
            if case .awaitingSecondTap(let since) = state, (t - since) * 1000 <= Double(windowMs) {
                state = .idle
                return .start
            }
            // The first tap, or a second one too slow to pair: this tap starts a new pair.
            state = .awaitingSecondTap(since: t)
            return .none
        }
    }

    /// Adopts a new mode mid-session and clears a half-finished double-tap
    /// detection. An in-flight recording needs nothing here: the next tap reads it
    /// from the session and stops it. See architecture/river-session.md on live-apply.
    func setMode(_ newMode: ActivationMode) {
        mode = newMode
        state = .idle
    }
}
