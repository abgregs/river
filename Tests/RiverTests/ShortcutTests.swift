import Carbon.HIToolbox
import CoreGraphics
import Testing
@testable import River

@Suite("Shortcut")
struct ShortcutTests {
    @Test("a shortcut survives the round trip through its stored string", arguments: [
        Shortcut.modifier(keyCode: 61),
        .combination(keyCode: 49, modifiers: [.control, .option]),
        .combination(keyCode: 9, modifiers: [.control, .option, .shift, .command]),
    ])
    func roundTrips(_ shortcut: Shortcut) {
        // `@AppStorage` and `SettingsStore` both persist the raw value; a shortcut that
        // does not read back as itself would change the user's key on relaunch.
        #expect(Shortcut(rawValue: shortcut.rawValue) == shortcut)
    }

    @Test("one combination always writes one string, whatever order its modifiers were added in")
    func storageIsCanonical() {
        // Two strings for one shortcut would make an unchanged setting look changed,
        // and reconfigure the hot key for nothing.
        var modifiers: ShortcutModifiers = [.command]
        modifiers.insert(.control)
        #expect(Shortcut.combination(keyCode: 49, modifiers: modifiers).rawValue == "key:49:ctrl,cmd")
        #expect(Shortcut.modifier(keyCode: 61).rawValue == "mod:61")
    }

    @Test("values that are not a dictation shortcut read as nothing", arguments: [
        "",                 // cleared; the dictation shortcut falls back to its default
        "mod:57",           // Caps Lock: no mode works on it
        "mod:63",           // fn: it cancels a recording
        "mod:49",           // not a modifier
        "key:49:",          // a key with no modifier
        "key:58:ctrl",      // a modifier as the key
        "key:49:fn",        // fn is not a combination modifier
        "key:49:ctrl,caps",
        "key:200:ctrl",
        "61",
        "garbage",
    ])
    func rejectsInvalid(_ raw: String) {
        // Anything unreadable must fall back to the default rather than register a
        // hot key macOS refuses or watch a key that can never work.
        #expect(Shortcut(rawValue: raw) == nil)
    }

    @Test("Carbon bits read back as the same modifiers, and the fn bit is not one")
    func carbonFlagsReadBack() {
        // macOS's own shortcut list reports Carbon bits, and its F-keys and arrows carry the fn
        // bit; reading it as a modifier would miss that ⌘F5 is taken.
        let all: ShortcutModifiers = [.control, .option, .shift, .command]
        #expect(ShortcutModifiers(carbonFlags: Int(all.carbonFlags)) == all)
        #expect(ShortcutModifiers(carbonFlags: cmdKey | 0x20000) == .command)
    }

    @Test("modifiers map to Carbon's hot key bits and to the tap's device-independent flags")
    func modifierMappings() {
        // Carbon bits are what `RegisterEventHotKey` matches; the tap flags are how a
        // Hold sees one of the combination's modifiers lift. Both sides of a modifier
        // set the same flag, which is why a combination keeps no side.
        let all: ShortcutModifiers = [.control, .option, .shift, .command]
        #expect(all.carbonFlags == UInt32(controlKey | optionKey | shiftKey | cmdKey))
        #expect(all.eventFlags == [.maskControl, .maskAlternate, .maskShift, .maskCommand])
        #expect(ShortcutModifiers.option.carbonFlags == UInt32(optionKey))
    }
}
