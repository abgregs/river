import Foundation

/// What the mark is doing. Preparing is the panel while the model gets ready at launch: the
/// muted 川 strokes held still (docs/design/kawa-identity.md).
enum MarkActivity: Equatable {
    case rest, listening, transcribing, preparing

    static func of(state: RiverState, isModelPreparing: Bool) -> MarkActivity {
        switch state {
        case .recording: return .listening
        case .processing: return .transcribing
        case .idle: return isModelPreparing ? .preparing : .rest
        }
    }
}

/// Pure mapping from cycle state to the recording-indicator HUD's variant and
/// on-screen visibility, extracted so the panel layer stays thin and dumb and the
/// only decidable logic (which visual to show, whether the window is on screen) is
/// unit-tested without standing up an `NSPanel` (planning 0002). Mirrors
/// `MenuBarPresentation`: the HUD is another observer of the same state seam.
enum RecordingIndicatorPresentation {
    // The HUD is the *primary* surface for the model-load wait (the menu bar
    // label is the secondary sync): while a load/download gates dictation, the
    // panel says so proactively instead of leaving the user to discover it via a
    // declined activation. `.ready` needs no label; `.failed` stays menu-only —
    // a permanent floating panel for an unrecoverable state would nag (its
    // recovery UX is a recorded follow-up alongside the model-switch work).
    static func loadingLabel(for modelLoadState: ModelLoadState) -> String? {
        switch modelLoadState {
        case .downloading: return "Downloading model…"
        case .loading: return "Preparing model…"
        case .ready, .failed: return nil
        }
    }

    // Whether the HUD panel should be on screen right now. `.recording` /
    // `.processing` are visible; a pending error toast keeps it visible even at
    // `.idle` — errors surface at end-of-cycle, when the state has already returned
    // to `.idle`, so the toast (planning 0018) must outlive the recording that
    // triggered it. An in-flight model load/download also shows the panel (the
    // loading wait is HUD-primary). No default for `modelLoadState` — a call site
    // that forgot it would silently hide the loading window (the #27 default-param
    // lesson). Pure so the coordinator's show-vs-fade-out branch is tested without
    // a real panel (fade timing and focus behavior stay a documented manual check
    // — planning 0002 AC5).
    static func isOnScreen(state: RiverState, hasToast: Bool, modelLoadState: ModelLoadState) -> Bool {
        state != .idle || hasToast || loadingLabel(for: modelLoadState) != nil
    }
}
