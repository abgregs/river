import Foundation

/// What the mark is doing (docs/design/kawa-identity.md).
enum MarkActivity: Equatable {
    case rest, listening, transcribing

    /// A status that holds the panel (planning 0004) keeps the mark transcribing after River is
    /// idle, so the panel leaves only once the status has been shown.
    static func of(state: RiverState, holdsPanel: Bool) -> MarkActivity {
        switch state {
        case .recording: return .listening
        case .processing: return .transcribing
        case .idle: return holdsPanel ? .transcribing : .rest
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
    // `.processing` are visible; a pending error toast keeps it visible even at
    // `.idle` — errors surface at end-of-cycle, when the state has already returned
    // to `.idle`, so the toast (planning 0018) must outlive the recording that
    // triggered it. So does a status that holds the panel (planning 0004): a failed
    // load or held text, which River shows once the dictation has ended. Nothing
    // shows while the model loads at launch: the status speaks only after a dictation.
    // No defaults — a call site that forgot one would silently hide the panel (the #27
    // default-param lesson). Pure so the coordinator's show-vs-fade-out branch is tested
    // without a real panel (fade timing and focus behavior stay a documented manual check
    // — planning 0002 AC5).
    static func isOnScreen(state: RiverState, hasToast: Bool, hasStatus: Bool) -> Bool {
        state != .idle || hasToast || hasStatus
    }
}
