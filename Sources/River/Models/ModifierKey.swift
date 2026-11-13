import CoreGraphics

/// A modifier key River knows by keycode (requirements/activation-key-and-mode.md): which side it
/// is on, the family a combination counts it in, and whether it is down in an event. Left and
/// right share a family flag, so the keycode names the key, and the key's own device bit
/// (`NX_DEVICE*KEYMASK`; fn has its own flag) says whether it is down. Reading the bit rather than
/// flipping on each event means a missed or repeated event can't leave River's idea of a key
/// wrong. Caps Lock is not one: River's tap sees one event per Caps Lock press and none on release.
enum ModifierKey: Int, CaseIterable {
    case rightControl = 62
    case leftControl = 59
    case rightOption = 61
    case leftOption = 58
    case rightCommand = 54
    case leftCommand = 55
    case rightShift = 60
    case leftShift = 56
    case function = 63

    enum Side {
        case left
        case right
    }

    var keyCode: Int { rawValue }

    /// Nil for fn, which has one key.
    var side: Side? {
        switch self {
        case .rightControl, .rightOption, .rightCommand, .rightShift: .right
        case .leftControl, .leftOption, .leftCommand, .leftShift: .left
        case .function: nil
        }
    }

    /// The modifier a combination counts it as; none for fn, which is not a combination modifier.
    var family: ShortcutModifiers {
        switch self {
        case .rightControl, .leftControl: .control
        case .rightOption, .leftOption: .option
        case .rightCommand, .leftCommand: .command
        case .rightShift, .leftShift: .shift
        case .function: []
        }
    }

    /// Whether it can be the dictation shortcut on its own. fn can't: it cancels a recording
    /// (spec 0036).
    var canBeAlone: Bool { self != .function }

    /// Whether this key is down in an event's raw modifier flags, a tap's `CGEventFlags` or a
    /// window's `NSEvent.ModifierFlags` alike. An event that carries no device bit at all, as
    /// one another app posts can, has only the family flag to go by.
    func isDown(rawFlags: UInt64) -> Bool {
        if self == .function || rawFlags & Self.deviceBits != 0 { return rawFlags & deviceBit != 0 }
        return rawFlags & family.eventFlags.rawValue != 0
    }

    private var deviceBit: UInt64 {
        switch self {
        case .leftControl: 0x0001
        case .leftShift: 0x0002
        case .rightShift: 0x0004
        case .leftCommand: 0x0008
        case .rightCommand: 0x0010
        case .leftOption: 0x0020
        case .rightOption: 0x0040
        case .rightControl: 0x2000
        case .function: CGEventFlags.maskSecondaryFn.rawValue
        }
    }

    private static let deviceBits: UInt64 = 0x207F
}
