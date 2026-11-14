/// A shortcut River uses besides the dictation shortcut (spec 0036): each has its row in the
/// Shortcuts pane, under its label, and the dictation shortcut may not take its keys. The one
/// list of them: `HotkeyManager` refuses their keys and the pane draws their rows from it.
/// PR 9's rows join it.
enum RiverShortcut: CaseIterable, Equatable {
    case cancelRecording

    /// The row's label, which a refusal names: "Cancel recording uses fn."
    var label: String {
        switch self {
        case .cancelRecording: "Cancel recording"
        }
    }

    var shortcut: Shortcut {
        switch self {
        case .cancelRecording: .modifier(keyCode: Constants.cancelKeyCode)
        }
    }
}
