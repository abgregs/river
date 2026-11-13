import Foundation

/// What the recorder does with a shortcut it heard (spec 0036, Conflicts): save it, save it
/// with macOS's warning, or refuse it with the reason. River's own shortcuts are checked
/// first, then whether macOS will register a combination, then macOS's own list. A refusal
/// keeps the recorder listening, so the next key press tries again.
enum ShortcutCheck: Equatable {
    case save
    case saveWithWarning
    case refuse(String)

    /// A shortcut River already uses, under the label of the row that shows it.
    struct Owned {
        let label: String
        let shortcut: Shortcut
    }

    /// The keys River uses besides the dictation shortcut. fn cancels a recording; PR 9's
    /// rows join it.
    static let riverShortcuts = [Owned(label: "Cancel recording", shortcut: .modifier(keyCode: Constants.cancelKeyCode))]

    static func check(
        _ candidate: Shortcut,
        owned: [Owned] = riverShortcuts,
        registration: (Shortcut) -> HotKeyRegistration,
        system: [SystemShortcuts.Entry],
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        character: ShortcutText.KeyCharacter = ShortcutText.layoutCharacter
    ) -> ShortcutCheck {
        if let owner = owned.first(where: { $0.shortcut == candidate }) {
            return .refuse("\(owner.label) uses \(ShortcutText.display(candidate, character: character)). Choose another.")
        }
        switch registration(candidate) {
        case .registered: break
        case .takenByAnotherApp: return .refuse("Another app uses this shortcut. Choose another.")
        case .refused: return .refuse(refusal(of: candidate, osVersion: osVersion))
        }
        return SystemShortcuts.contains(candidate, in: system) ? .saveWithWarning : .save
    }

    // macOS 15.0 and 15.1 refuse a combination whose only modifiers are ⌥ or ⌥⇧ (spec 0036,
    // Accepted limits); the line names the Mac's own version.
    static func refusal(of candidate: Shortcut, osVersion: OperatingSystemVersion) -> String {
        if case .combination(_, let modifiers) = candidate, modifiers.contains(.option),
           modifiers.isSubset(of: [.option, .shift]), osVersion.majorVersion == 15, osVersion.minorVersion < 2 {
            return "macOS 15.\(osVersion.minorVersion) needs ⌃ or ⌘ in this shortcut. Choose another."
        }
        return "macOS refused this shortcut. Choose another."
    }
}
