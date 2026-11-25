import Foundation

/// What the mark is doing (docs/design/kawa-identity.md).
enum MarkActivity: Equatable {
    case rest, listening, transcribing

    /// A dictation that waits for the model, or one with a status to show, lets the panel go
    /// while River is still processing: the status shows in its place once it has gone
    /// (planning 0004).
    static func of(state: RiverState, hidesPanel: Bool) -> MarkActivity {
        switch state {
        case .recording: return .listening
        case .processing: return hidesPanel ? .rest : .transcribing
        case .idle: return .rest
        }
    }
}

/// Pure mapping from cycle state to the recording-indicator HUD's variant and
/// on-screen visibility, extracted so the panel layer stays thin and dumb and the
/// only decidable logic (which visual to show, whether the window is on screen) is
/// unit-tested without standing up an `NSPanel` (planning 0002). Mirrors
/// `MenuBarPresentation`: the HUD is another observer of the same state seam.
enum RecordingIndicatorPresentation {
    // Whether the HUD panel should be on screen right now. `.recording` /
    // `.processing` are visible; a status keeps it visible even at `.idle`: an error or held text
    // arrives at the end of the cycle and shows once the mark has left, and a failed load stays
    // after River is idle (planning 0004, 0018). Nothing shows while the model loads at launch:
    // the status speaks only after a dictation. No defaults — a call site that forgot one would
    // silently hide the panel (the #27 default-param lesson). Pure so the coordinator's
    // show-vs-fade-out branch is tested without a real panel (fade timing and focus behavior stay
    // a documented manual check — planning 0002 AC5).
    static func isOnScreen(state: RiverState, hasStatus: Bool) -> Bool {
        state != .idle || hasStatus
    }
}
