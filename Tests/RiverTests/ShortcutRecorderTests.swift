import Carbon.HIToolbox
import Foundation
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

    @Test("a refusal names River's row, another app, or the Mac's own version; a save has no line")
    func refusalLines() {
        // The line tells the user what to change: another shortcut, or a ⌃ or ⌘ on macOS 15.0
        // and 15.1, which refuse ⌥-only combinations (spec 0036, Accepted limits).
        let us: ShortcutText.KeyCharacter = { ShortcutText.usLayout[$0] }
        let sequoia = OperatingSystemVersion(majorVersion: 15, minorVersion: 2, patchVersion: 0)
        let fifteenOne = OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0)
        let optionK = Shortcut.combination(keyCode: kVK_ANSI_K, modifiers: .option)
        #expect(RecorderLine.refusal(.usedByRiver(.cancelRecording), of: .modifier(keyCode: 63), osVersion: sequoia, character: us)
                == .refused("Cancel recording uses fn. Choose another."))
        #expect(RecorderLine.refusal(.takenByAnotherApp, of: optionK, osVersion: sequoia, character: us)
                == .refused("Another app uses this shortcut. Choose another."))
        #expect(RecorderLine.refusal(.refusedByMacOS, of: optionK, osVersion: fifteenOne, character: us)
                == .refused("macOS 15.1 needs ⌃ or ⌘ in this shortcut. Choose another."))
        #expect(RecorderLine.refusal(.refusedByMacOS, of: .combination(keyCode: kVK_ANSI_K, modifiers: [.option, .shift]),
                                     osVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0), character: us)
                == .refused("macOS 15.0 needs ⌃ or ⌘ in this shortcut. Choose another."))
        #expect(RecorderLine.refusal(.refusedByMacOS, of: optionK, osVersion: sequoia, character: us)
                == .refused("macOS refused this shortcut. Choose another."))
        #expect(RecorderLine.refusal(.alsoUsedByMacOS, of: optionK, osVersion: sequoia, character: us) == nil)
        #expect(RecorderLine.refusal(.available, of: optionK, osVersion: sequoia, character: us) == nil)
    }

    @Test("a saved shortcut that failed at launch says why, and one that registered says nothing")
    func notWorkingLine() {
        // The row keeps the failed shortcut so the user sees what failed and records over it.
        #expect(RecorderLine.notWorking(.takenByAnotherApp)?.text == "Not working: another app uses this shortcut.")
        #expect(RecorderLine.notWorking(.refused(-9868))?.kind == .failure)
        #expect(RecorderLine.notWorking(.registered) == nil)
    }
}
