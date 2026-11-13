import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation
import Testing
@testable import River

@Suite("HotkeyManager Hold mode")
struct HotkeyManagerHoldTests {
    // The manager interprets the raw TapEvent stream into semantic activate /
    // deactivate. Tests drive it via `handle(_:)` (and via the Combine chain
    // when verifying wiring) — never through a real CGEventTap, which would
    // require an Input Monitoring grant for the test process.

    @MainActor
    @Test("watched key: alternating flagsChanged events fire activate then deactivate")
    func watchedKeyTogglesAndFires() {
        let cap = InputMonitoringCapability()
        let manager = HotkeyManager(
            inputMonitoring: cap, hotKeys: HotKeyRegistry(calls: .inert), initialShortcut: .modifier(keyCode: 62)
        )
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))
        #expect(activates == 1)
        #expect(deactivates == 0)

        manager.handle(.flagsChanged(keyCode: 62, flags: []))
        #expect(activates == 1)
        #expect(deactivates == 1)

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))
        #expect(activates == 2)
    }

    @MainActor
    @Test("non-watched keycode is ignored — no callbacks, no latch change")
    func nonWatchedKeyIgnored() {
        // Left/right modifier variants share a flag mask; disambiguation is by
        // keycode. A Left Control event must NOT trigger when Right Control is
        // the watched key.
        let cap = InputMonitoringCapability()
        let manager = HotkeyManager(
            inputMonitoring: cap, hotKeys: HotKeyRegistry(calls: .inert), initialShortcut: .modifier(keyCode: 62)
        )
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        manager.handle(.flagsChanged(keyCode: 59, flags: .maskControl))  // Left Control
        manager.handle(.flagsChanged(keyCode: 59, flags: []))
        #expect(activates == 0)
        #expect(deactivates == 0)
    }

    @MainActor
    @Test(".tapDisabled is a no-op for the manager (capability self-heals)")
    func tapDisabledIsNoOp() {
        let cap = InputMonitoringCapability()
        let manager = HotkeyManager(
            inputMonitoring: cap, hotKeys: HotKeyRegistry(calls: .inert), initialShortcut: .modifier(keyCode: 62)
        )
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        manager.handle(.tapDisabled)
        #expect(activates == 0)
        #expect(deactivates == 0)
    }

    @MainActor
    @Test("setShortcut resets the press latch")
    func setShortcutResetsLatch() {
        // If the user reconfigures mid-press, the stale "key still down" state
        // must not survive — otherwise the next event for the new key fires a
        // phantom deactivate (anti-pattern #7 in spirit: don't leak cycle state
        // across reconfiguration).
        let cap = InputMonitoringCapability()
        let manager = HotkeyManager(
            inputMonitoring: cap, hotKeys: HotKeyRegistry(calls: .inert), initialShortcut: .modifier(keyCode: 62)
        )
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))  // press old key
        #expect(activates == 1)

        manager.setShortcut(.modifier(keyCode: 59))  // switch to Left Control mid-press

        manager.handle(.flagsChanged(keyCode: 59, flags: .maskControl))  // new press
        #expect(activates == 2)
        #expect(deactivates == 0)  // latch was reset; this is a press, not a release

        manager.handle(.flagsChanged(keyCode: 59, flags: []))             // new release
        #expect(deactivates == 1)
    }

    @MainActor
    @Test("bindEventStream wires capability events to handle (via Combine)")
    func bindEventStreamWiresChain() {
        // End-to-end through the publisher chain without a real tap: the
        // capability's `publishForTest` sends synchronously on the main actor,
        // the manager's sink receives synchronously, and the activate fires.
        let cap = InputMonitoringCapability()
        let manager = HotkeyManager(
            inputMonitoring: cap, hotKeys: HotKeyRegistry(calls: .inert), initialShortcut: .modifier(keyCode: 62)
        )
        manager.bindEventStream()
        var activates = 0
        manager.onActivate = { activates += 1 }

        cap.publishForTest(.flagsChanged(keyCode: 62, flags: .maskControl))
        #expect(activates == 1)
    }
}

@Suite("HotkeyManager cancel gesture")
struct HotkeyManagerCancelTests {
    // The cancel modifier (planning 0017) is interpreted off the same watched
    // `.flagsChanged` stream — no mask widening, no keyDown observation, so the
    // 0006 least-privilege posture is untouched. It fires on the press edge and is
    // independent of activation mode.

    @MainActor
    @Test("cancel key press fires onCancel once, on the down edge")
    func cancelKeyFiresOnPress() {
        let manager = makeManager(mode: .hold, cancelKeyCode: 63)
        var cancels = 0
        manager.onCancel = { cancels += 1 }

        manager.handle(.flagsChanged(keyCode: 63, flags: .maskSecondaryFn))  // press
        #expect(cancels == 1)
        manager.handle(.flagsChanged(keyCode: 63, flags: []))                // release: no re-fire
        #expect(cancels == 1)
        manager.handle(.flagsChanged(keyCode: 63, flags: .maskSecondaryFn))  // second press
        #expect(cancels == 2)
    }

    @MainActor
    @Test("the cancel key does not disturb activation callbacks")
    func cancelKeyDoesNotActivate() {
        let manager = makeManager(mode: .hold, cancelKeyCode: 63)
        var activates = 0
        var deactivates = 0
        var cancels = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }
        manager.onCancel = { cancels += 1 }

        manager.handle(.flagsChanged(keyCode: 63, flags: .maskSecondaryFn))  // cancel press
        manager.handle(.flagsChanged(keyCode: 63, flags: []))                // cancel release
        #expect(cancels == 1)
        #expect(activates == 0)   // activation latch untouched
        #expect(deactivates == 0)

        // The watched key still starts a recording normally afterward.
        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))
        #expect(activates == 1)
    }

    @MainActor
    @Test("Hold: cancelling mid-hold leaves the press latch intact")
    func holdCancelPreservesPressLatch() {
        // Planning 0017. Hold tracks the PHYSICAL key: during a cancel the activation
        // key is still held down, so the eventual release must read as a release. If
        // the cancel path ever cleared `isKeyDown`, that release would toggle the
        // latch to "down" and fire a PHANTOM ACTIVATE — starting a recording as the
        // user lifts off the key. This test fails the moment that happens.
        let manager = makeManager(mode: .hold, cancelKeyCode: 63)
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))       // hold down → start
        #expect(activates == 1)

        manager.handle(.flagsChanged(keyCode: 63, flags: .maskSecondaryFn))   // fn while still held

        manager.handle(.flagsChanged(keyCode: 62, flags: []))                 // release the held key
        #expect(deactivates == 1)   // a genuine release edge...
        #expect(activates == 1)     // ...not a phantom press

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))       // next press
        #expect(activates == 2)     // starts normally — no swallowed keypress
    }

    @MainActor
    @Test("cancel works identically in a tap mode")
    func cancelWorksInTapMode() {
        let manager = makeManager(mode: .singleTap, cancelKeyCode: 63)
        var cancels = 0
        manager.onCancel = { cancels += 1 }

        manager.handle(.flagsChanged(keyCode: 63, flags: .maskSecondaryFn))
        #expect(cancels == 1)
    }

    @MainActor
    private func makeManager(mode: ActivationMode, cancelKeyCode: Int) -> HotkeyManager {
        HotkeyManager(
            inputMonitoring: InputMonitoringCapability(),
            hotKeys: HotKeyRegistry(calls: .inert),
            initialShortcut: .modifier(keyCode: 62),
            initialMode: mode,
            cancelKeyCode: cancelKeyCode
        )
    }
}

@Suite("HotkeyManager tap modes")
struct HotkeyManagerTapTests {
    // Tap modes act only on the completing (key-up) edge of a tap and route
    // start/stop through the embedded TapStateMachine. Double-tap timing itself is
    // covered in TapStateMachineTests; here two *immediate* taps are well within
    // the 400 ms window, so they always pair under the real clock. `wireSession`
    // stands in for RiverSession: it reports a recording between an accepted start
    // and the next stop.

    @MainActor
    @Test("single tap: a completed tap starts, the next stops")
    func singleTapToggles() {
        let manager = makeManager(mode: .singleTap)
        var activates = 0
        var deactivates = 0
        wireSession(manager, onActivate: { activates += 1 }, onDeactivate: { deactivates += 1 })

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))  // key-down
        #expect(activates == 0)  // a press alone does nothing in tap modes
        manager.handle(.flagsChanged(keyCode: 62, flags: []))            // key-up → tap → start
        #expect(activates == 1)

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))
        manager.handle(.flagsChanged(keyCode: 62, flags: []))            // tap → stop
        #expect(deactivates == 1)
    }

    @MainActor
    @Test("holding the key in a tap mode is a single tap (fires on release only)")
    func holdIsOneTap() {
        let manager = makeManager(mode: .singleTap)
        var activates = 0
        manager.onActivate = { activates += 1 }

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))  // press and "hold"
        #expect(activates == 0)
        manager.handle(.flagsChanged(keyCode: 62, flags: []))            // release completes the one tap
        #expect(activates == 1)
    }

    @MainActor
    @Test("double tap: two quick taps start, one tap stops")
    func doubleTapStartsAndStops() {
        let manager = makeManager(mode: .doubleTap)
        var activates = 0
        var deactivates = 0
        wireSession(manager, onActivate: { activates += 1 }, onDeactivate: { deactivates += 1 })

        tap(manager)
        #expect(activates == 0)  // first tap: awaiting the second
        tap(manager)
        #expect(activates == 1)  // second tap within the window → start

        tap(manager)
        #expect(deactivates == 1)  // a single tap stops
    }

    @MainActor
    @Test("a live key change preserves the recording: the new key stops it, the old key is ignored")
    func liveKeyChangePreservesRecording() {
        // This is the load-bearing behavior for live-apply (river-session.md):
        // switching the key mid-recording is a refilter and the session still
        // reports the recording, so the new key stops it while the old key falls
        // silent.
        let manager = makeManager(mode: .singleTap)
        var deactivates = 0
        wireSession(manager, onActivate: {}, onDeactivate: { deactivates += 1 })

        tap(manager)                          // start recording on key 62
        manager.setShortcut(.modifier(keyCode: 59))      // live key change to Left Control

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))  // old key…
        manager.handle(.flagsChanged(keyCode: 62, flags: []))            // …now ignored
        #expect(deactivates == 0)

        manager.handle(.flagsChanged(keyCode: 59, flags: .maskControl))  // new key…
        manager.handle(.flagsChanged(keyCode: 59, flags: []))            // …stops the recording
        #expect(deactivates == 1)
    }

    @MainActor
    @Test("switching from Hold to a tap mode resets the press latch")
    func modeSwitchResetsLatch() {
        let manager = makeManager(mode: .hold)
        var activates = 0
        manager.onActivate = { activates += 1 }

        manager.handle(.flagsChanged(keyCode: 62, flags: .maskControl))  // Hold: down → activate
        #expect(activates == 1)
        manager.setActivationMode(.singleTap)  // switch mid-press; latch must reset

        tap(manager)  // a clean tap on the new mode starts a recording
        #expect(activates == 2)
    }

    @MainActor
    @Test("single tap: after a refused start the next tap starts, it is not eaten as a stop")
    func singleTapAfterRefusedStartStarts() {
        // The session refuses a start while the model is preparing, a permission is
        // denied, or a dictation is still transcribing, and stays idle. The next tap
        // must be another start. The tap machine once kept its own "recording" flag
        // and read that tap as a stop the session ignored, costing a keypress.
        let manager = makeManager(mode: .singleTap)
        var activates = 0
        var deactivates = 0
        wireSession(manager, accepts: false, onActivate: { activates += 1 }, onDeactivate: { deactivates += 1 })

        tap(manager)                 // start, refused
        tap(manager)                 // must START again, not stop
        #expect(activates == 2)
        #expect(deactivates == 0)
    }

    @MainActor
    @Test("double tap: after a refused start two quick taps start again")
    func doubleTapAfterRefusedStartStarts() {
        let manager = makeManager(mode: .doubleTap)
        var activates = 0
        var deactivates = 0
        wireSession(manager, accepts: false, onActivate: { activates += 1 }, onDeactivate: { deactivates += 1 })

        tap(manager)
        tap(manager)                 // two quick taps → start, refused
        tap(manager)
        tap(manager)                 // two quick taps → start again
        #expect(activates == 2)
        #expect(deactivates == 0)
    }

    // Stands in for RiverSession: `accepts` decides whether a start begins a
    // recording, and `isRecording` reports it until the next stop.
    @MainActor
    private func wireSession(
        _ manager: HotkeyManager,
        accepts: Bool = true,
        onActivate: @escaping () -> Void,
        onDeactivate: @escaping () -> Void
    ) {
        var recording = false
        manager.isRecording = { recording }
        manager.onActivate = {
            onActivate()
            if accepts { recording = true }
        }
        manager.onDeactivate = {
            onDeactivate()
            recording = false
        }
    }

    @MainActor
    private func makeManager(mode: ActivationMode) -> HotkeyManager {
        HotkeyManager(
            inputMonitoring: InputMonitoringCapability(),
            hotKeys: HotKeyRegistry(calls: .inert),
            initialShortcut: .modifier(keyCode: 62),
            initialMode: mode
        )
    }

    @MainActor
    private func tap(_ manager: HotkeyManager, keyCode: Int64 = 62) {
        manager.handle(.flagsChanged(keyCode: keyCode, flags: .maskControl))
        manager.handle(.flagsChanged(keyCode: keyCode, flags: []))
    }
}

@Suite("HotkeyManager combination")
struct HotkeyManagerCombinationTests {
    // A combination arrives as hot key presses and releases from `HotKeyRegistry`,
    // driven here through `publishForTest`; the inert calls register nothing real.
    // ⌃⌥Space: keycode 49 with Control and Option.
    private let combination = Shortcut.combination(keyCode: 49, modifiers: [.control, .option])
    private let heldFlags: CGEventFlags = [.maskControl, .maskAlternate]

    @MainActor
    @Test("Hold: the key's release stops, and a modifier lifting afterwards does nothing")
    func holdStopsOnKeyReleaseFirst() {
        // Releasing the key before the modifiers is the usual order. The stop must
        // fire once: a second deactivate would end the next recording early.
        let (manager, hotKeys) = makeManager(mode: .hold)
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        hotKeys.publishForTest(.pressed(.dictation))
        #expect(activates == 1)
        hotKeys.publishForTest(.released(.dictation))
        #expect(deactivates == 1)
        manager.handle(.flagsChanged(keyCode: 58, flags: .maskControl))   // ⌥ lifts
        manager.handle(.flagsChanged(keyCode: 59, flags: []))             // ⌃ lifts
        #expect(deactivates == 1)
    }

    @MainActor
    @Test("Hold: a modifier lifting stops at once, and the key's later release does nothing")
    func holdStopsOnModifierLiftFirst() {
        // Letting go of ⌥ while still holding Space means the shortcut is no longer
        // held, so dictation stops then, not when Space comes up.
        let (manager, hotKeys) = makeManager(mode: .hold)
        var deactivates = 0
        manager.onDeactivate = { deactivates += 1 }

        hotKeys.publishForTest(.pressed(.dictation))
        manager.handle(.flagsChanged(keyCode: 58, flags: .maskControl))   // ⌥ lifts, ⌃ held
        #expect(deactivates == 1)
        hotKeys.publishForTest(.released(.dictation))
        #expect(deactivates == 1)
    }

    @MainActor
    @Test("Hold: pressing another modifier during the hold does not stop it")
    func holdIgnoresAddedModifier() {
        // Only a modifier of the combination lifting ends the hold; adding Shift
        // still leaves ⌃⌥ held.
        let (manager, hotKeys) = makeManager(mode: .hold)
        var deactivates = 0
        manager.onDeactivate = { deactivates += 1 }

        hotKeys.publishForTest(.pressed(.dictation))
        manager.handle(.flagsChanged(keyCode: 56, flags: heldFlags.union(.maskShift)))
        #expect(deactivates == 0)
    }

    @MainActor
    @Test("single tap: the press does nothing; each release is a tap")
    func singleTapActsOnRelease() {
        // Acting on the release keeps a held combination one tap, as a held lone
        // modifier is, and keeps the press from racing its own release.
        let (manager, hotKeys) = makeManager(mode: .singleTap)
        var activates = 0
        var deactivates = 0
        var recording = false
        manager.isRecording = { recording }
        manager.onActivate = { activates += 1; recording = true }
        manager.onDeactivate = { deactivates += 1; recording = false }

        hotKeys.publishForTest(.pressed(.dictation))
        #expect(activates == 0)
        hotKeys.publishForTest(.released(.dictation))
        #expect(activates == 1)
        hotKeys.publishForTest(.pressed(.dictation))
        hotKeys.publishForTest(.released(.dictation))
        #expect(deactivates == 1)
    }

    @MainActor
    @Test("double tap: two quick releases start")
    func doubleTapActsOnTwoReleases() {
        let (manager, hotKeys) = makeManager(mode: .doubleTap)
        var activates = 0
        manager.onActivate = { activates += 1 }

        hotKeys.publishForTest(.pressed(.dictation))
        hotKeys.publishForTest(.released(.dictation))
        #expect(activates == 0)
        hotKeys.publishForTest(.pressed(.dictation))
        hotKeys.publishForTest(.released(.dictation))
        #expect(activates == 1)
    }

    @MainActor
    @Test("with a combination set, the old lone modifier no longer activates")
    func loneModifierIgnoredForCombination() {
        // The tap still delivers every modifier edge; only the combination may start
        // dictation, or Right Option would keep working after the user changed it.
        let (manager, _) = makeManager(mode: .hold)
        var activates = 0
        manager.onActivate = { activates += 1 }

        manager.handle(.flagsChanged(keyCode: 61, flags: .maskAlternate))
        manager.handle(.flagsChanged(keyCode: 61, flags: []))
        #expect(activates == 0)
    }

    @MainActor
    @Test("the shortcut's hot key follows the setting: registered for a combination, gone for a lone modifier")
    func registrationFollowsShortcut() {
        // An exclusive hot key left registered would keep swallowing that keystroke
        // in every app after the user moved dictation off it.
        let (manager, hotKeys) = makeManager(mode: .hold)
        #expect(hotKeys.registeredIDs == [.dictation])
        #expect(manager.dictationRegistration == .registered)

        manager.setShortcut(.modifier(keyCode: 61))
        #expect(hotKeys.registeredIDs.isEmpty)
        #expect(manager.dictationRegistration == nil)
    }

    @MainActor
    @Test("a combination another app holds is reported, not silently dead")
    func takenCombinationIsReported() {
        // The recorder shows this result to the user; without it the shortcut
        // would simply never fire.
        var calls = HotKeyRegistry.Calls.inert
        calls.register = { _, _, _ in (OSStatus(eventHotKeyExistsErr), nil) }
        let manager = HotkeyManager(
            inputMonitoring: InputMonitoringCapability(), hotKeys: HotKeyRegistry(calls: calls),
            initialShortcut: combination, initialMode: .hold
        )
        manager.bindEventStream()
        manager.setShortcut(.combination(keyCode: 9, modifiers: [.control, .option]))
        #expect(manager.dictationRegistration == .takenByAnotherApp)
    }

    @MainActor
    @Test("fn cancels whatever the dictation shortcut is")
    func fnAlwaysCancels() {
        // fn is never the dictation shortcut (spec 0036), so its press is always the
        // cancel gesture, under a combination and under a lone modifier alike.
        let (manager, hotKeys) = makeManager(mode: .hold)
        var cancels = 0
        manager.onCancel = { cancels += 1 }
        hotKeys.publishForTest(.pressed(.dictation))
        manager.handle(.flagsChanged(keyCode: 63, flags: heldFlags.union(.maskSecondaryFn)))
        manager.handle(.flagsChanged(keyCode: 63, flags: heldFlags))
        #expect(cancels == 1)

        manager.setShortcut(.modifier(keyCode: 61))
        manager.handle(.flagsChanged(keyCode: 63, flags: .maskSecondaryFn))
        #expect(cancels == 2)
    }

    // Started through `bindEventStream`, which a test can call, and `setShortcut`,
    // which registers once the streams are bound.
    @MainActor
    private func makeManager(mode: ActivationMode) -> (HotkeyManager, HotKeyRegistry) {
        let hotKeys = HotKeyRegistry(calls: .inert)
        let manager = HotkeyManager(
            inputMonitoring: InputMonitoringCapability(), hotKeys: hotKeys,
            initialShortcut: .modifier(keyCode: 61), initialMode: mode
        )
        manager.bindEventStream()
        manager.setShortcut(combination)
        return (manager, hotKeys)
    }
}

@Suite("HotkeyManager discard")
struct HotkeyManagerDiscardTests {
    // A River hot key pressed while the lone-modifier dictation key is down: the
    // modifier is part of that shortcut (spec 0036). Unreachable until PR 9 adds the
    // other shortcuts, so a synthetic ID stands in for one.
    private let otherShortcut = HotKeyID(rawValue: 99)

    @MainActor
    @Test("Hold: the recording is discarded and the modifier's release is not a stop")
    func holdDiscardsAndSkipsRelease() {
        // A stop would transcribe and type the few words caught before the shortcut.
        let (manager, hotKeys) = makeManager(mode: .hold)
        var activates = 0
        var deactivates = 0
        var discards = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }
        manager.onDiscard = { discards += 1 }

        manager.handle(.flagsChanged(keyCode: 61, flags: .maskAlternate))
        hotKeys.publishForTest(.pressed(otherShortcut))
        hotKeys.publishForTest(.released(otherShortcut))
        hotKeys.publishForTest(.pressed(otherShortcut))   // pressed again, same hold
        manager.handle(.flagsChanged(keyCode: 61, flags: []))
        #expect(activates == 1)
        #expect(discards == 1)
        #expect(deactivates == 0)

        manager.handle(.flagsChanged(keyCode: 61, flags: .maskAlternate))   // the next hold works
        manager.handle(.flagsChanged(keyCode: 61, flags: []))
        #expect(activates == 2)
        #expect(deactivates == 1)
    }

    @MainActor
    @Test("tap modes: that press is not a tap, and nothing is discarded")
    func tapModeSkipsTheTap() {
        // In a tap mode the modifier's release is what counts, so skipping it is
        // enough: no recording starts, and one already running keeps going.
        let (manager, hotKeys) = makeManager(mode: .singleTap)
        var activates = 0
        var discards = 0
        manager.onActivate = { activates += 1 }
        manager.onDiscard = { discards += 1 }

        manager.handle(.flagsChanged(keyCode: 61, flags: .maskAlternate))
        hotKeys.publishForTest(.pressed(otherShortcut))
        manager.handle(.flagsChanged(keyCode: 61, flags: []))
        #expect(activates == 0)
        #expect(discards == 0)

        manager.handle(.flagsChanged(keyCode: 61, flags: .maskAlternate))   // the next tap works
        manager.handle(.flagsChanged(keyCode: 61, flags: []))
        #expect(activates == 1)
    }

    @MainActor
    @Test("a hot key pressed while the modifier is up changes nothing")
    func hotKeyWithModifierUpIsIgnored() {
        // Only a shortcut that uses the held modifier is in conflict; any other leaves
        // the next dictation alone.
        let (manager, hotKeys) = makeManager(mode: .hold)
        var activates = 0
        var deactivates = 0
        manager.onActivate = { activates += 1 }
        manager.onDeactivate = { deactivates += 1 }

        hotKeys.publishForTest(.pressed(otherShortcut))
        manager.handle(.flagsChanged(keyCode: 61, flags: .maskAlternate))
        manager.handle(.flagsChanged(keyCode: 61, flags: []))
        #expect(activates == 1)
        #expect(deactivates == 1)
    }

    @MainActor
    private func makeManager(mode: ActivationMode) -> (HotkeyManager, HotKeyRegistry) {
        let hotKeys = HotKeyRegistry(calls: .inert)
        let manager = HotkeyManager(
            inputMonitoring: InputMonitoringCapability(), hotKeys: hotKeys,
            initialShortcut: .modifier(keyCode: 61), initialMode: mode
        )
        manager.bindEventStream()
        return (manager, hotKeys)
    }
}
