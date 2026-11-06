# Research: How River's settings panel should record a shortcut

How a shortcut recorder in River's settings panel (an AppKit `NSPanel` with SwiftUI content) should capture a lone modifier or a combination, keep River's own hot keys out of the way, and warn about system-reserved shortcuts. Researched 2026-11-05 on macOS 15.7.5 (build 24G624, Darwin 24.6.0) against the macOS 15.2 SDK. This is the companion to [shortcut-registration.md](shortcut-registration.md), which chooses the registration mechanism. The maintainer ran probe R1 by hand on 2026-11-05 [9]. Sources are numbered in §6. Anything marked **(inferred)** or **(anecdotal)** has no primary-source confirmation.

## 1. Summary

- **Capture with a local monitor** (`NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged])`) while River's panel is key. It sees events "prior to their dispatch", and returning nil stops dispatch, so the panel's controls don't also act on the keys [1][2].
- **A panel can be key.** A panel without a title bar must override `canBecomeKey` [3]. River's existing indicator panel returns `false` on purpose, so the settings panel needs its own subclass [7]. In R1, clicking the panel made the probe the active app, and every key event reached the monitor (`panelKey=true appActive=true`) [9]. Key events in a panel that does not activate its app remain untested; activating River while the panel is open avoids the question.
- **Suspend River's own Carbon hot keys while recording.** With ⌃⌥Space registered, the monitor saw ⌃ and ⌥ go down but never the Space: Carbon took it first [9].
- **Side-specific modifiers** come from the device bits in the event's raw `modifierFlags` (`NX_DEVICERALTKEYMASK` etc.) [4]. Only a lone modifier can keep its side, because Carbon combinations have none [5].
- **System shortcuts can be read but not identified.** `CopySymbolicHotKeys` returns code, modifiers and enabled for each system hot key, with "no way to determine which hotkey ... corresponds to a specific dictionary" [5]. On this Mac it returned 229 entries, 169 enabled [8]. It is enough for a generic "macOS already uses this" warning.

## 2. Capturing keys

- **Monitor.** The local monitor "receives copies of events the system posts to this app prior to their dispatch". It is not called for events "consumed by nested event-tracking loops such as control tracking, menu tracking" [1]. So the recorder must not be inside a menu, and a recording field should not sit in a control that tracks the mouse while it records **(inferred)**. Key repeats are flagged by `isARepeat` [1], and R1 saw them flagged [9]. The recorder ignores repeats.
- **Key window.** `canBecomeKey` is true only when the style mask "includes the titled flag". To make an untitled window key, "override this property in an NSWindow subclass to return true" [3]. `.nonactivatingPanel` is a panel "that does not activate the owning app" [3]. A non-activating panel "becomes key only if the hit view returns true from `needsPanelToBecomeKey`" when `becomesKeyOnlyIfNeeded` is set [3]. Whether a key non-activating panel in an *inactive* app gets `keyDown` through the local monitor is untested: R1's click activated the app [9].
- **Side-specific modifiers.** `NSEvent.modifierFlags` has device-independent bits in its high half (`NSEventModifierFlagDeviceIndependentFlagsMask = 0xffff0000`) [2]. The low half carries the `NX_DEVICE*` bits: L/R Ctrl 0x1/0x2000, Shift 0x2/0x4, Cmd 0x8/0x10, Option 0x20/0x40 [4]. The `flagsChanged` keycode also tells the sides apart, as River does today [7]. R1: Right ⌥ alone gave keycode 61 down and up with `ROpt` and no key between; Right ⌥+K gave a `keyDown` 40 carrying `ROpt` [9].
- **Lone modifier vs start of a combination.** Record a lone modifier on its *release*, when no non-modifier `keyDown` came between its press and release. Record a combination on the first non-modifier `keyDown` while one or more modifiers are down. Then record the device-independent modifiers, minus Caps Lock (§4) **(inferred design)**.
- **Esc cancels and Delete clears.** Both reach the monitor as plain `keyDown`s (53 and 51) [9]. So Esc alone and Delete alone can never be recorded. That's fine: neither is a modifier, and a combination needs one. ⌥Esc, ⌘Delete and similar stay recordable. Esc-while-recording-dictation is a built-in cancel, not a recordable shortcut.

## 3. River's own hot keys and system shortcuts

- **Suspend before recording.** A registered hot key is global [5]. The recorder has to see the user re-press River's current shortcut, so unregister River's combinations while the recorder is active, and register them again on exit **(inferred)**. Also ignore the lone-modifier tap's actions while recording. R1 confirms it: only CARBON saw ⌃⌥Space while the panel was key [9].
- **System shortcuts.** `CopySymbolicHotKeys` (macOS 10.3+, no deprecation macro) returns each system hot key's `kHISymbolicHotKeyCode`, `kHISymbolicHotKeyModifiers` and `kHISymbolicHotKeyEnabled`. It "does not include customized application-specific command keys", and Apple warns it is O(number of hot keys) [5]. The probe returned ⌘Space (code 49, 0x100) and ⌘Tab (48, 0x100) among 169 enabled entries [8]. Call it once when the recorder opens, then compare the recorded code and modifiers against the enabled entries. It can't detect another app's `RegisterEventHotKey`.
- **What a system-taken combination does on registration.** ⌘Space, ⌘Tab and ⌘⇧3 all registered with `noErr` [6]. Registration therefore can't be the warning. On a press both run: ⌘Space opened Spotlight and reached River's probe (registration note, source 19). The warning says so.
- **`PushSymbolicHotKeyMode(kHIHotKeyModeAllDisabled)`** would let the recorder capture keys the system normally takes. It needs the Accessibility grant, and it only stays in effect while the pushing app is frontmost [5]. River's panel does not activate River, so whether it applies is **(inferred: probably not)**. Don't rely on it.

## 4. Caps Lock and Fn

- **Caps Lock.** As a combination modifier, `alphaLock` returns `eventInternalErr` (-9868) [6], so it can't be part of a combination. As a lone key it is keycode 57 on the `flagsChanged` path. It toggles state, so the recorder should treat it as a lone key only, and every use also toggles Caps Lock, because a listen-only tap can't swallow the key **(inferred)**. R1 saw one `flagsChanged` per *press*: the first sets `alphaShift`, the second clears it, with no event on release [9]. If River's tap sees the same, a tap mode needs two Caps Lock presses per tap, because `HotkeyManager` toggles its latch once per event [7]. The tap was not probed, so this is open.
- **Fn / Globe.** As a lone key it is keycode 63, which River already uses for cancel [7]. A combination with the fn bit registers [6], but delivery is unverified. The system's own hot keys set the fn bit on F-keys and arrows [8], so the recorder must not treat that bit as a held Fn key on those keys **(inferred)**. Recording Fn alone as the dictation key would collide with cancel. The spec decides which wins.

## 5. Open questions and maintainer probe

- **R1 `./recorder 40`** (run 2026-11-05 [9]; still open: a panel in an inactive app) in `/private/tmp/claude-501/-Users-abgregs-Developer-river/48da0173-71d4-46f4-8005-aa87365c3ea6/scratchpad/shortcut-probes/`: opens a titled non-activating floating panel with a local `keyDown`/`keyUp`/`flagsChanged` monitor and registers ⌃⌥Space. Click the panel, then press ⌃⌥Space, Esc, Delete, Right ⌥ alone, Right ⌥+K and a held key. It answers whether the key panel in an inactive accessory app gets key events, whether Carbon takes ⌃⌥Space before the monitor, what side bits arrive, and how repeats are flagged.
- Whether `PushSymbolicHotKeyMode` has any effect from a non-activating panel.

## 6. Sources

1. Apple, [NSEvent.addLocalMonitorForEvents(matching:handler:)](https://developer.apple.com/documentation/appkit/nsevent/addlocalmonitorforevents(matching:handler:)) and `AppKit.framework/Headers/NSEvent.h` (monitor comment).
2. Apple, `MacOSX15.2.sdk/.../AppKit.framework/Headers/NSEvent.h`: `NSEventModifierFlags`, `NSEventModifierFlagDeviceIndependentFlagsMask`.
3. Apple, [NSWindow.canBecomeKey](https://developer.apple.com/documentation/appkit/nswindow/canbecomekey), [NSWindow.StyleMask.nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel), [NSPanel.becomesKeyOnlyIfNeeded](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded).
4. Apple, `IOKit.framework/Headers/hidsystem/IOLLEvent.h`: `NX_DEVICE*KEYMASK`.
5. Apple, `HIToolbox.framework/Headers/CarbonEvents.h`: `RegisterEventHotKey`, `CopySymbolicHotKeys`, `kHISymbolicHotKey*`, `PushSymbolicHotKeyMode`; `Events.h`: right-side bits "Not supported on Mac OS X".
6. Probe `register` (see the registration note, source 12): `alphaLock`+⌃Space -9868; ⌘Space, ⌘Tab, ⌘⇧3 `noErr`.
7. River: `Sources/River/Architecture/RecordingIndicatorCoordinator.swift` (`NonActivatingPanel.canBecomeKey = false`), `Sources/River/Managers/HotkeyManager.swift`, `Sources/River/Utilities/Constants.swift` (`cancelKeyCode = 63`).
8. Probe `symbolic`: 229 entries, 169 enabled; F-key and arrow entries carry the fn bit (0x20000). Output in `symbolic-output.txt`.
9. Probe `recorder 90`, run by the maintainer 2026-11-05: clicked the panel, then pressed ⌃⌥Space, Esc, Delete, Right ⌥, Right ⌥+K, Caps Lock twice and a held letter. Output kept in the session scratchpad.
