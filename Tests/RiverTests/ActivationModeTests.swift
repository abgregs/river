import Testing
@testable import River

@Suite("ActivationMode")
struct ActivationModeTests {
    @Test("table lists all three modes with the default and non-empty copy")
    func tableComplete() {
        #expect(ActivationMode.allCases.count == 3)
        #expect(Settings.activationMode.defaultValue == .hold)
        for mode in ActivationMode.allCases {
            #expect(!mode.label.isEmpty)
            #expect(!mode.description.isEmpty)
        }
    }

    @Test("notice copy names the changed key and mode")
    func noticeCopy() {
        // If the copy stops naming the new key/mode, the user can't tell what now
        // stops the recording — the whole point of the live-apply notice.
        #expect(ActivationNotice.keyChanged(to: .modifier(keyCode: 61)).contains("Right Option"))
        #expect(ActivationNotice.modeChanged(to: .doubleTap).contains("Double-tap"))
    }

    @Test("keyChanged falls back to generic phrasing for an unknown keycode")
    func keyChangedUnknownKeycode() {
        // A keycode `ModifierKey` doesn't know (e.g. the removed Caps Lock) must not
        // crash or emit a blank label — the "the new key" fallback keeps the notice
        // grammatical.
        let notice = ActivationNotice.keyChanged(to: .modifier(keyCode: 57))
        #expect(notice.contains("the new key"))
    }

    @Test("keyChanged names a combination by its keys")
    func keyChangedCombination() {
        // The user must be able to tell which keys now stop the recording, a
        // combination's as much as a lone modifier's.
        let notice = ActivationNotice.keyChanged(to: .combination(keyCode: 49, modifiers: [.control, .option]),
                                                 character: { ShortcutText.usLayout[$0] })
        #expect(notice.contains("Control Option Space"))
    }
}
