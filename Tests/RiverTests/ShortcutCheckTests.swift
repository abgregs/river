import Carbon.HIToolbox
import Foundation
import Testing
@testable import River

@Suite("ShortcutCheck")
struct ShortcutCheckTests {
    private let us: ShortcutText.KeyCharacter = { ShortcutText.usLayout[$0] }
    private let controlOptionSpace = Shortcut.combination(keyCode: kVK_Space, modifiers: [.control, .option])
    private let sequoia = OperatingSystemVersion(majorVersion: 15, minorVersion: 2, patchVersion: 0)

    @Test("fn is refused as the key River cancels with, before macOS is asked")
    func fnIsRiversOwn() {
        // fn as the dictation key would leave a recording with no cancel key (spec 0036).
        var asked = false
        let check = ShortcutCheck.check(.modifier(keyCode: 63), registration: { _ in asked = true; return .registered },
                                        system: [], osVersion: sequoia, character: us)
        #expect(check == .refuse("Cancel recording uses fn. Choose another."))
        #expect(!asked)
    }

    @Test("a combination another app holds is refused, and nothing is saved")
    func takenByAnotherApp() {
        // Saving it would leave a dictation shortcut that does nothing (spec 0036, AC 6).
        let check = ShortcutCheck.check(controlOptionSpace, registration: { _ in .takenByAnotherApp },
                                        system: [], osVersion: sequoia, character: us)
        #expect(check == .refuse("Another app uses this shortcut. Choose another."))
    }

    @Test("macOS 15.0 and 15.1 name themselves when they refuse an ⌥-only combination")
    func optionOnlyRefusalNamesTheVersion() {
        // The fix is a modifier the user can add, so the line says which one, and the version
        // tells them it is this Mac, not River.
        let optionK = Shortcut.combination(keyCode: kVK_ANSI_K, modifiers: .option)
        let fifteenZero = OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        let fifteenOne = OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0)
        #expect(ShortcutCheck.refusal(of: optionK, osVersion: fifteenZero) == "macOS 15.0 needs ⌃ or ⌘ in this shortcut. Choose another.")
        #expect(ShortcutCheck.refusal(of: .combination(keyCode: kVK_ANSI_K, modifiers: [.option, .shift]), osVersion: fifteenOne)
                == "macOS 15.1 needs ⌃ or ⌘ in this shortcut. Choose another.")
        #expect(ShortcutCheck.refusal(of: optionK, osVersion: sequoia) == "macOS refused this shortcut. Choose another.")
        #expect(ShortcutCheck.refusal(of: controlOptionSpace, osVersion: fifteenZero) == "macOS refused this shortcut. Choose another.")
    }

    @Test("a combination macOS also uses is saved with its warning")
    func systemShortcutWarns() {
        // Inform, don't block: both run, and the user decides (spec 0036, Conflicts).
        let commandSpace = Shortcut.combination(keyCode: kVK_Space, modifiers: .command)
        let system = [SystemShortcuts.Entry(keyCode: kVK_Space, modifiers: .command)]
        #expect(ShortcutCheck.check(commandSpace, registration: { _ in .registered }, system: system, osVersion: sequoia, character: us)
                == .saveWithWarning)
        #expect(ShortcutCheck.check(controlOptionSpace, registration: { _ in .registered }, system: system, osVersion: sequoia, character: us)
                == .save)
    }
}

@Suite("SystemShortcuts")
struct SystemShortcutsTests {
    @Test("only enabled entries count, and the fn bit is not a modifier")
    func readsEnabledEntries() {
        // F-keys and arrows carry the fn bit in macOS's list; reading it as a modifier would
        // miss that ⌘F5 is taken.
        let entries = SystemShortcuts.entries(from: [
            [kHISymbolicHotKeyCode as String: kVK_F5, kHISymbolicHotKeyModifiers as String: cmdKey | 0x20000,
             kHISymbolicHotKeyEnabled as String: true],
            [kHISymbolicHotKeyCode as String: kVK_Space, kHISymbolicHotKeyModifiers as String: controlKey,
             kHISymbolicHotKeyEnabled as String: false],
        ])
        #expect(entries == [SystemShortcuts.Entry(keyCode: kVK_F5, modifiers: .command)])
        #expect(SystemShortcuts.contains(.combination(keyCode: kVK_F5, modifiers: .command), in: entries))
        #expect(!SystemShortcuts.contains(.combination(keyCode: kVK_Space, modifiers: .control), in: entries))
    }

    @Test("a lone modifier never matches macOS's list")
    func loneModifierNeverMatches() {
        // The list holds keys with modifiers; a lone modifier can't be among them.
        #expect(!SystemShortcuts.contains(.modifier(keyCode: 61), in: [SystemShortcuts.Entry(keyCode: 61, modifiers: [])]))
    }
}
