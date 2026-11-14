import Carbon.HIToolbox
import Foundation
import Testing
@testable import River

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
