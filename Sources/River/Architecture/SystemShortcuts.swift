import Carbon.HIToolbox
import Foundation

/// macOS's own shortcuts (Spotlight, input sources, screenshots and the rest), as
/// `CopySymbolicHotKeys` lists them: the one place River reads that list. A combination on it
/// is saved with a warning, since both run (spec 0036, Conflicts). The list says which keys,
/// not which feature, and holds no other app's shortcuts.
enum SystemShortcuts {
    struct Entry: Equatable, Sendable {
        let keyCode: Int
        let modifiers: ShortcutModifiers
    }

    /// The enabled entries, read now. Empty if macOS won't say.
    static func enabled() -> [Entry] {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr,
              let items = list?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return entries(from: items)
    }

    // internal for testability — the pure read of the list's dictionaries.
    static func entries(from items: [[String: Any]]) -> [Entry] {
        items.compactMap { item in
            guard (item[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = item[kHISymbolicHotKeyCode as String] as? Int,
                  let flags = item[kHISymbolicHotKeyModifiers as String] as? Int else { return nil }
            return Entry(keyCode: code, modifiers: ShortcutModifiers(carbonFlags: flags))
        }
    }

    /// Whether macOS also uses `shortcut`. Only a combination can match: the list holds keys
    /// with modifiers.
    static func contains(_ shortcut: Shortcut, in entries: [Entry]) -> Bool {
        guard case .combination(let code, let modifiers) = shortcut else { return false }
        return entries.contains { $0.keyCode == code && $0.modifiers == modifiers }
    }
}
