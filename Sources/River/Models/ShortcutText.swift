import Carbon.HIToolbox
import Foundation

/// How River writes a shortcut (spec 0036, The recorder): as macOS writes key equivalents in
/// its menus, ⌃ ⌥ ⇧ ⌘ in that order and then the key, with a lone modifier naming its side
/// ("Right ⌥"). Letter and symbol keys read from the keyboard layout, so a key shows what it
/// types on this Mac; `character` is injected so tests read the US layout on any Mac.
enum ShortcutText {
    typealias KeyCharacter = (Int) -> String?

    /// A shortcut as its outline lays it out: a lone modifier's side apart from its glyph, and
    /// each key apart, so the keys can be spaced without spreading the letters of "Space".
    struct Keys: Equatable {
        var side: String?
        var keys: [String]
    }

    /// The shortcut as one line of text, for a message: "Right ⌥", "⌃⌥Space", "fn".
    static func display(_ shortcut: Shortcut, character: KeyCharacter = layoutCharacter) -> String {
        let parts = keys(shortcut, character: character)
        return [parts.side, parts.keys.joined()].compactMap { $0 }.joined(separator: " ")
    }

    static func keys(_ shortcut: Shortcut, character: KeyCharacter = layoutCharacter) -> Keys {
        switch shortcut {
        case .modifier(let code):
            guard let lone = loneModifiers[code] else { return Keys(keys: []) }
            return Keys(side: lone.side.isEmpty ? nil : lone.side, keys: [lone.glyph])
        case .combination(let code, let modifiers):
            return Keys(keys: keys(modifiers).keys + [keyName(code, character: character)])
        }
    }

    /// Held modifiers as keys, in menu order.
    static func keys(_ modifiers: ShortcutModifiers) -> Keys {
        Keys(keys: order.filter { modifiers.contains($0.modifier) }.map(\.glyph))
    }

    /// The shortcut as VoiceOver reads it: "Right Option", "Control Option Space".
    static func spoken(_ shortcut: Shortcut, character: KeyCharacter = layoutCharacter) -> String {
        switch shortcut {
        case .modifier(let code):
            guard let lone = loneModifiers[code] else { return "" }
            return lone.side.isEmpty ? lone.name : "\(lone.side) \(lone.name)"
        case .combination(let code, let modifiers):
            let names = order.filter { modifiers.contains($0.modifier) }.map(\.name)
            return (names + [spokenKeyName(code, character: character)]).joined(separator: " ")
        }
    }

    /// A non-modifier key: a named key ("Space", "↩", "F5"), else what it types ("V").
    static func keyName(_ code: Int, character: KeyCharacter = layoutCharacter) -> String {
        if let named = namedKeys[code] { return named.glyph }
        return character(code) ?? usLayout[code] ?? "Key \(code)"
    }

    private static func spokenKeyName(_ code: Int, character: KeyCharacter) -> String {
        namedKeys[code]?.spoken ?? keyName(code, character: character)
    }

    private static let order: [(modifier: ShortcutModifiers, glyph: String, name: String)] = [
        (.control, "⌃", "Control"), (.option, "⌥", "Option"), (.shift, "⇧", "Shift"), (.command, "⌘", "Command"),
    ]

    // Every key the flags-changed path reports, fn included so a refused fn still reads.
    private static let loneModifiers: [Int: (side: String, glyph: String, name: String)] = [
        62: ("Right", "⌃", "Control"), 59: ("Left", "⌃", "Control"),
        61: ("Right", "⌥", "Option"), 58: ("Left", "⌥", "Option"),
        54: ("Right", "⌘", "Command"), 55: ("Left", "⌘", "Command"),
        60: ("Right", "⇧", "Shift"), 56: ("Left", "⇧", "Shift"),
        63: ("", "fn", "Function"),
    ]

    private static let namedKeys: [Int: (glyph: String, spoken: String)] = [
        kVK_Space: ("Space", "Space"), kVK_Return: ("↩", "Return"), kVK_ANSI_KeypadEnter: ("⌅", "Enter"),
        kVK_Tab: ("⇥", "Tab"), kVK_Delete: ("⌫", "Delete"), kVK_ForwardDelete: ("⌦", "Forward Delete"),
        kVK_Escape: ("Esc", "Escape"), kVK_LeftArrow: ("←", "Left Arrow"), kVK_RightArrow: ("→", "Right Arrow"),
        kVK_UpArrow: ("↑", "Up Arrow"), kVK_DownArrow: ("↓", "Down Arrow"), kVK_Home: ("↖", "Home"),
        kVK_End: ("↘", "End"), kVK_PageUp: ("⇞", "Page Up"), kVK_PageDown: ("⇟", "Page Down"),
        kVK_Help: ("Help", "Help"), kVK_ANSI_KeypadClear: ("⌧", "Clear"),
        kVK_F1: ("F1", "F1"), kVK_F2: ("F2", "F2"), kVK_F3: ("F3", "F3"), kVK_F4: ("F4", "F4"),
        kVK_F5: ("F5", "F5"), kVK_F6: ("F6", "F6"), kVK_F7: ("F7", "F7"), kVK_F8: ("F8", "F8"),
        kVK_F9: ("F9", "F9"), kVK_F10: ("F10", "F10"), kVK_F11: ("F11", "F11"), kVK_F12: ("F12", "F12"),
        kVK_F13: ("F13", "F13"), kVK_F14: ("F14", "F14"), kVK_F15: ("F15", "F15"), kVK_F16: ("F16", "F16"),
        kVK_F17: ("F17", "F17"), kVK_F18: ("F18", "F18"), kVK_F19: ("F19", "F19"), kVK_F20: ("F20", "F20"),
    ]

    // What each character key types on a US layout: the fallback when the layout can't say.
    static let usLayout: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Backslash: "\\", kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`", kVK_ISO_Section: "§",
        kVK_ANSI_Keypad0: "0", kVK_ANSI_Keypad1: "1", kVK_ANSI_Keypad2: "2", kVK_ANSI_Keypad3: "3",
        kVK_ANSI_Keypad4: "4", kVK_ANSI_Keypad5: "5", kVK_ANSI_Keypad6: "6", kVK_ANSI_Keypad7: "7",
        kVK_ANSI_Keypad8: "8", kVK_ANSI_Keypad9: "9", kVK_ANSI_KeypadDecimal: ".", kVK_ANSI_KeypadMultiply: "*",
        kVK_ANSI_KeypadPlus: "+", kVK_ANSI_KeypadDivide: "/", kVK_ANSI_KeypadMinus: "-", kVK_ANSI_KeypadEquals: "=",
    ]

    /// What `code` types with no modifiers on the current keyboard layout, capitalised as
    /// menus show letters; nil when the layout can't say.
    static func layoutCharacter(_ code: Int) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters
            )
            guard status == noErr, length > 0 else { return nil }
            let text = String(utf16CodeUnits: characters, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text.uppercased()
        }
    }
}
