import Carbon.HIToolbox
import Testing
@testable import River

@Suite("ShortcutText")
struct ShortcutTextTests {
    // The US layout, so the letters read the same on any Mac running the tests.
    private let us: ShortcutText.KeyCharacter = { ShortcutText.usLayout[$0] }

    @Test("a lone modifier names its side, and fn reads as fn")
    func loneModifiers() {
        // Right ⌥ and Left ⌥ are different shortcuts; the row must say which one is saved.
        #expect(ShortcutText.display(.modifier(keyCode: 61), character: us) == "Right ⌥")
        #expect(ShortcutText.display(.modifier(keyCode: 59), character: us) == "Left ⌃")
        #expect(ShortcutText.display(.modifier(keyCode: 63), character: us) == "fn")
        #expect(ShortcutText.spoken(.modifier(keyCode: 61), character: us) == "Right Option")
    }

    @Test("modifiers read in menu order whatever order they were held in")
    func menuOrder() {
        // macOS writes ⌃ ⌥ ⇧ ⌘ in this order in every menu; another order reads as a
        // different shortcut.
        var modifiers: ShortcutModifiers = [.command]
        modifiers.formUnion([.shift, .option, .control])
        #expect(ShortcutText.display(.combination(keyCode: kVK_ANSI_V, modifiers: modifiers), character: us) == "⌃⌥⇧⌘V")
        #expect(ShortcutText.spoken(.combination(keyCode: kVK_Space, modifiers: [.control, .option]), character: us)
                == "Control Option Space")
    }

    @Test("named keys read as macOS writes them, Esc as River's copy writes it", arguments: [
        (kVK_Space, "Space"), (kVK_Return, "↩"), (kVK_Tab, "⇥"), (kVK_Delete, "⌫"),
        (kVK_Escape, "Esc"), (kVK_F5, "F5"), (kVK_LeftArrow, "←"), (kVK_PageDown, "⇟"),
    ])
    func namedKeys(code: Int, name: String) {
        // These keys type nothing a layout could name; they read the same on every keyboard.
        #expect(ShortcutText.keyName(code, character: us) == name)
    }

    @Test("a letter reads as the key types on this Mac's layout, and as the US layout without one")
    func layoutLetters() {
        // On a German keyboard the key in the US Y position types Z; the row must show the key
        // the user pressed, not its US name.
        let qwertz: ShortcutText.KeyCharacter = { $0 == kVK_ANSI_Y ? "Z" : nil }
        #expect(ShortcutText.display(.combination(keyCode: kVK_ANSI_Y, modifiers: .control), character: qwertz) == "⌃Z")
        #expect(ShortcutText.display(.combination(keyCode: kVK_ANSI_Y, modifiers: .control), character: { _ in nil }) == "⌃Y")
    }
}
