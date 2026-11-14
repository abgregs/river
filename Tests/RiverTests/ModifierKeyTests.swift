import CoreGraphics
import Testing
@testable import River

@Suite("ModifierKey")
struct ModifierKeyTests {
    @Test("8 keys can be the dictation shortcut alone, the default among them")
    func loneKeys() {
        // A dropped key would vanish from the recorder's accepted keys and from a stored
        // setting's validation without any other error.
        let alone = ModifierKey.allCases.filter(\.canBeAlone).map(\.keyCode)
        #expect(Set(alone) == [62, 59, 61, 58, 54, 55, 60, 56])
        #expect(Shortcut.loneModifierKeyCodes == Set(alone))
        #expect(alone.contains(Constants.defaultActivationKeyCode))   // 61, Right Option
    }

    @Test("Caps Lock is not a modifier River watches")
    func capsLockExcluded() {
        // Why: River's tap sees one event per Caps Lock press and none on release, so
        // Hold never sees the release and a tap mode needs two presses per tap. Offering
        // it would hand the user a key that cannot work in any mode.
        #expect(ModifierKey(rawValue: 57) == nil)
    }

    @Test("fn is not a dictation key")
    func fnExcluded() {
        // Why: fn cancels a recording (spec 0036). As the dictation key its press would
        // have to start and stop instead, leaving a recording with no cancel key.
        #expect(ModifierKey(rawValue: Constants.cancelKeyCode)?.canBeAlone == false)
        #expect(!Shortcut.loneModifierKeyCodes.contains(Constants.cancelKeyCode))
    }

    @Test("each key's own bit says it is down, so one side lifting leaves the other down")
    func deviceBitsTellSidesApart() {
        // Right ⌥ coming up while Left ⌥ is still down leaves the shared ⌥ flag set; only the
        // device bit says which key moved.
        let leftOptionHeld = CGEventFlags.maskAlternate.rawValue | 0x20
        #expect(!ModifierKey.rightOption.isDown(rawFlags: leftOptionHeld))
        #expect(ModifierKey.leftOption.isDown(rawFlags: leftOptionHeld))
        #expect(ModifierKey.rightControl.isDown(rawFlags: CGEventFlags.maskControl.rawValue | 0x2000))
        #expect(!ModifierKey.rightOption.isDown(rawFlags: 0))
    }

    @Test("fn reads its own flag")
    func fnFlag() {
        #expect(ModifierKey.function.isDown(rawFlags: CGEventFlags.maskSecondaryFn.rawValue))
        #expect(!ModifierKey.function.isDown(rawFlags: CGEventFlags.maskAlternate.rawValue | 0x40))
    }

    @Test("an event with no device bit at all reads the family flag")
    func noDeviceBits() {
        // Another app can post modifier events with only the family flag; River would
        // otherwise never see such a key go down.
        #expect(ModifierKey.rightOption.isDown(rawFlags: CGEventFlags.maskAlternate.rawValue))
        #expect(!ModifierKey.rightOption.isDown(rawFlags: CGEventFlags.maskControl.rawValue))
    }

    @Test("a combination counts each key by its family, and fn not at all")
    func families() {
        // ⌃⌥Space is the same shortcut with either Control or Option (activation-key-and-mode.md).
        #expect(ModifierKey.leftControl.family == .control)
        #expect(ModifierKey.rightCommand.family == .command)
        #expect(ModifierKey.function.family.isEmpty)
    }
}
