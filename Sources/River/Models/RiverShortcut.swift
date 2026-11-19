import Carbon.HIToolbox

/// An action River runs from a shortcut, as its row in the Shortcuts pane names it (spec 0036).
/// No two of River's shortcuts may share keys: the recorder refuses a shortcut another one
/// uses, naming that row ("Cancel recording uses fn."). `HotkeyManager` holds which keys each
/// one has now.
enum RiverShortcut: CaseIterable, Hashable, Sendable {
    case dictate
    case cancelRecording
    case pasteLast
    case copyLast
    case toggleLiveText

    /// The row's label, which a refusal names.
    var label: String {
        switch self {
        case .dictate: "Dictate"
        case .cancelRecording: "Cancel recording"
        case .pasteLast: "Paste last transcription"
        case .copyLast: "Copy last transcription"
        case .toggleLiveText: "Toggle live text"
        }
    }

    /// Whether its row takes a lone modifier. Only dictation does: the event tap watches one,
    /// and a hot key needs a key with its modifiers.
    var allowsLoneModifier: Bool { self == .dictate }

    /// Whether its row records a combination that runs an action as a hot key: every row but
    /// Dictate, which drives a recording, and Cancel recording, whose keys are fixed.
    var isAction: Bool { self == .pasteLast || self == .copyLast || self == .toggleLiveText }

    /// The fixed keys that cancel a recording: fn, and Esc while a recording runs.
    static let cancelKeys: [Shortcut] = [
        .modifier(keyCode: Constants.cancelKeyCode), .combination(keyCode: kVK_Escape, modifiers: []),
    ]
}
