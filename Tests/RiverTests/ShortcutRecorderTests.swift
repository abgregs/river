import Carbon.HIToolbox
import Testing
@testable import River

@Suite("ShortcutRecorder")
struct ShortcutRecorderTests {
    @Test("a modifier pressed and released alone records that modifier, with its side")
    func loneModifierRecordsOnRelease() {
        // A lone modifier is only known on its release: until then it may start a combination.
        // The keycode keeps the side, so Right ⌥ never saves as Left ⌥.
        var recorder = ShortcutRecorder()
        #expect(recorder.handle(.modifierChanged(keyCode: 61, isDown: true)) == .none)
        #expect(recorder.held == .option)
        #expect(recorder.handle(.modifierChanged(keyCode: 61, isDown: false)) == .candidate(.modifier(keyCode: 61)))
        #expect(recorder.held.isEmpty)
    }

    @Test("a key pressed with modifiers held records the combination on the press")
    func combinationRecordsOnKeyDown() {
        // The modifiers show as they go down, so ⌃⌥ is visible before the key completes it.
        var recorder = ShortcutRecorder()
        _ = recorder.handle(.modifierChanged(keyCode: 59, isDown: true))
        _ = recorder.handle(.modifierChanged(keyCode: 58, isDown: true))
        #expect(recorder.held == [.control, .option])
        #expect(recorder.handle(.keyDown(keyCode: kVK_Space, modifiers: [.control, .option], isRepeat: false))
                == .candidate(.combination(keyCode: kVK_Space, modifiers: [.control, .option])))
    }

    @Test("letting go of a combination's modifier records nothing more")
    func combinationReleaseIsNotLone() {
        // Without this, ⌃Space followed by releasing ⌃ would also record ⌃ alone.
        var recorder = ShortcutRecorder()
        _ = recorder.handle(.modifierChanged(keyCode: 59, isDown: true))
        _ = recorder.handle(.keyDown(keyCode: kVK_Space, modifiers: .control, isRepeat: false))
        #expect(recorder.handle(.modifierChanged(keyCode: 59, isDown: false)) == .none)
    }

    @Test("two modifiers with no key record nothing, and the next chord starts fresh")
    func twoModifiersAreNotLone() {
        // ⌃⌥ released with no key is half a combination, not a lone modifier.
        var recorder = ShortcutRecorder()
        _ = recorder.handle(.modifierChanged(keyCode: 59, isDown: true))
        _ = recorder.handle(.modifierChanged(keyCode: 58, isDown: true))
        #expect(recorder.handle(.modifierChanged(keyCode: 58, isDown: false)) == .none)
        #expect(recorder.handle(.modifierChanged(keyCode: 59, isDown: false)) == .none)
        _ = recorder.handle(.modifierChanged(keyCode: 61, isDown: true))
        #expect(recorder.handle(.modifierChanged(keyCode: 61, isDown: false)) == .candidate(.modifier(keyCode: 61)))
    }

    @Test("a modifier held before recording began is ignored when it comes up")
    func earlierHeldModifierIgnored() {
        // Its press was never seen, so its release must not read as a lone modifier.
        var recorder = ShortcutRecorder()
        #expect(recorder.handle(.modifierChanged(keyCode: 61, isDown: false)) == .none)
    }

    @Test("Esc stops, Delete clears, and a key with no modifier is refused")
    func plainKeys() {
        // Esc and Delete alone are never shortcuts (spec 0036): they control the recorder.
        var recorder = ShortcutRecorder()
        #expect(recorder.handle(.keyDown(keyCode: kVK_Escape, modifiers: [], isRepeat: false)) == .stop)
        #expect(recorder.handle(.keyDown(keyCode: kVK_Delete, modifiers: [], isRepeat: false)) == .clear)
        #expect(recorder.handle(.keyDown(keyCode: kVK_ForwardDelete, modifiers: [], isRepeat: false)) == .clear)
        #expect(recorder.handle(.keyDown(keyCode: kVK_ANSI_K, modifiers: [], isRepeat: false)) == .bareKey(keyCode: kVK_ANSI_K))
    }

    @Test("Esc and Delete with a modifier are combinations like any other")
    func modifiedEscRecords() {
        // ⌥Esc stays recordable; only the bare key controls the recorder.
        var recorder = ShortcutRecorder()
        #expect(recorder.handle(.keyDown(keyCode: kVK_Escape, modifiers: .option, isRepeat: false))
                == .candidate(.combination(keyCode: kVK_Escape, modifiers: .option)))
    }

    @Test("a held key's repeats are ignored")
    func repeatsIgnored() {
        // A held key would otherwise retry the same refused shortcut many times a second.
        var recorder = ShortcutRecorder()
        #expect(recorder.handle(.keyDown(keyCode: kVK_ANSI_K, modifiers: .control, isRepeat: true)) == .none)
    }

    @Test("the device bits tell the sides apart, fn has its own flag, and Caps Lock is ignored")
    func isDownReadsSides() {
        // Right ⌥ coming up while Left ⌥ is still down leaves the shared ⌥ flag set, so only
        // the device bit says which key moved.
        let leftOptionHeld: UInt = 0x8_0000 | 0x20
        #expect(ShortcutRecorder.isDown(keyCode: 61, rawFlags: leftOptionHeld) == false)
        #expect(ShortcutRecorder.isDown(keyCode: 58, rawFlags: leftOptionHeld) == true)
        #expect(ShortcutRecorder.isDown(keyCode: 63, rawFlags: 0x80_0000) == true)
        #expect(ShortcutRecorder.isDown(keyCode: 57, rawFlags: 0x1_0000) == nil)
    }

    @Test("a saved shortcut that failed at launch says why, and one that registered says nothing")
    func notWorkingLine() {
        // The row keeps the failed shortcut so the user sees what failed and records over it.
        #expect(RecorderLine.notWorking(.takenByAnotherApp)?.text == "Not working: another app uses this shortcut.")
        #expect(RecorderLine.notWorking(.refused(-9868))?.kind == .failure)
        #expect(RecorderLine.notWorking(.registered) == nil)
    }
}
