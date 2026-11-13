import Carbon.HIToolbox
import CoreGraphics

/// The key that starts and stops dictation (spec 0036). A lone modifier is watched
/// on the listen-only event tap and keeps its side, told apart by keycode. A
/// combination is a key plus modifiers, registered as an exclusive hot key, so it
/// cannot tell left from right modifiers. Which mode it drives is a separate
/// setting (`ActivationMode`).
///
/// Persisted as one string so `@AppStorage` can bind it: `mod:61` for a lone
/// modifier, `key:49:ctrl,opt` for a combination. An empty string is the cleared
/// form; the dictation shortcut can never be cleared, so a cleared or unreadable
/// value falls back to the default.
enum Shortcut: Hashable, Sendable {
    case modifier(keyCode: Int)
    case combination(keyCode: Int, modifiers: ShortcutModifiers)

    /// The keycodes a lone modifier may use: the `ModifierKey`s that can be alone.
    /// Caps Lock (57) is not among them: River's tap sees one event per Caps Lock
    /// press and none on release, so no mode can work on it. Nor is fn (63): it
    /// cancels a recording.
    static let loneModifierKeyCodes = Set(ModifierKey.allCases.filter(\.canBeAlone).map(\.keyCode))

    // Every modifier keycode, Caps Lock included. None of them is the key of a
    // combination: the tap watches them, and a hot key needs a non-modifier key.
    private static let modifierKeyCodes: ClosedRange<Int> = 54...63
}

extension Shortcut: RawRepresentable {
    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.first {
        case "mod":
            guard parts.count == 2, let code = Int(parts[1]),
                  Self.loneModifierKeyCodes.contains(code) else { return nil }
            self = .modifier(keyCode: code)
        case "key":
            guard parts.count == 3, let code = Int(parts[1]),
                  (0...127).contains(code), !Self.modifierKeyCodes.contains(code),
                  let modifiers = ShortcutModifiers(storageNames: parts[2]),
                  !modifiers.isEmpty else { return nil }
            self = .combination(keyCode: code, modifiers: modifiers)
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .modifier(let code): "mod:\(code)"
        case .combination(let code, let modifiers): "key:\(code):\(modifiers.storageNames)"
        }
    }
}

/// The modifiers of a combination. Device-independent: a combination does not
/// keep a side. No Caps Lock (macOS refuses it as a hot key modifier) and no fn.
struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
    static let command = ShortcutModifiers(rawValue: 1 << 3)

    // Storage order is fixed, so one combination always writes one string.
    private static let named: [(ShortcutModifiers, String)] = [
        (.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd"),
    ]

    var storageNames: String {
        Self.named.filter { contains($0.0) }.map(\.1).joined(separator: ",")
    }

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init?(storageNames: Substring) {
        var modifiers: ShortcutModifiers = []
        for name in storageNames.split(separator: ",") {
            guard let match = Self.named.first(where: { $0.1 == name }) else { return nil }
            modifiers.insert(match.0)
        }
        self = modifiers
    }

    /// Reads Carbon modifier bits, as macOS's own shortcut list reports them. Other bits,
    /// such as the fn bit F-keys and arrows carry, are not modifiers of a combination.
    init(carbonFlags: Int) {
        var modifiers: ShortcutModifiers = []
        if carbonFlags & controlKey != 0 { modifiers.insert(.control) }
        if carbonFlags & optionKey != 0 { modifiers.insert(.option) }
        if carbonFlags & shiftKey != 0 { modifiers.insert(.shift) }
        if carbonFlags & cmdKey != 0 { modifiers.insert(.command) }
        self = modifiers
    }

    /// The modifier mask `RegisterEventHotKey` takes.
    var carbonFlags: UInt32 {
        var flags = 0
        if contains(.control) { flags |= controlKey }
        if contains(.option) { flags |= optionKey }
        if contains(.shift) { flags |= shiftKey }
        if contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }

    /// The same modifiers as event-tap flags, to see one of them lift.
    var eventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.command) { flags.insert(.maskCommand) }
        return flags
    }
}
