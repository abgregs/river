# Research: How River should register its keyboard shortcuts

How River should register a recorded dictation key (a lone modifier or a full combination), the new "paste last transcription" and "show or hide live text" shortcuts, and Esc as a cancel key that exists only while recording. Researched 2026-11-05 on macOS 15.7.5 (build 24G624, Darwin 24.6.0), Apple Silicon, against the macOS 15.2 SDK and Swift 6.0.3. Probes are Swift programs in the session scratchpad. Most ran from a shell with no Accessibility, Input Monitoring or post-event grant [16], so they tested return codes only; the maintainer then ran the delivery probe (P1) and the recorder probe by hand, pressing the keys [19]. Sources are numbered in §9. Anything marked **(inferred)** or **(anecdotal)** has no primary-source confirmation. The recorder (settings-panel capture) is in [shortcut-recorder.md](shortcut-recorder.md).

## 1. Summary

- **Carbon `RegisterEventHotKey` needs no TCC grant and no event tap.** The probe registered 18 of 20 hot keys with no permission at all [12][16], and they fired [19]. It is a "global hot key" API [1]. The OS keeps the key from the frontmost app: typing `a`, ⌃⌥Space, `b`, then `c`, ⌥K, `d`, then `e`, ⌘⇧V, `f` into TextEdit left `abcdef` [19].
- **It has a press and a release event** (`kEventHotKeyPressed` = 5, `kEventHotKeyReleased` = 6) [1], both delivered within 1–7 ms [19]. Release fires when the key lifts, with the modifiers still down. Holding ⌘⇧V for 2.2 s gave one press and one release, so hot keys do not autorepeat [19].
- **The ⌥-only restriction was real in macOS 15.0 and was lifted in 15.2.** Apple's engineer: Sequoia "requires that a hotkey registration use at least one modifier that is not shift or option" (Sep 2024), then "addressed in macOS 15.2 Beta 2 (Build: 24C5073e)" (Nov 2024) [9]. On 15.7.5, ⌥K, ⌥Space, ⌥⇧K and ⌥⇧Space all return `noErr` [12], and ⌥K fires [19]. Users on 15.0 or 15.1 can still get a refusal, so River must handle a failed registration.
- **Conflicts are mostly silent.** The same combination twice in one process gives `eventHotKeyExistsErr` (-9878). The same combination in two processes succeeds in both. ⌘Space, ⌘Tab and ⌘⇧3 register with `noErr` [2][12][13], and on a press both fire: ⌘Space opened Spotlight and reached the probe [19]. Only an exclusive registration against another exclusive one is refused, so the API reports few clashes.
- **No left/right distinction and no Caps Lock.** `rightOptionKey` and the other right-side bits are marked "Not supported on Mac OS X" [3]. `alphaLock` as a modifier returns `eventInternalErr` (-9868) [12].
- **Delivery depends on the main thread.** The handler is installed on the application event target, which the main event loop dispatches **(inferred)** [1]. River's tap callback already hops to the main actor, so a main-actor stall delays both paths' handling equally (§2).
- **Not deprecated; nothing newer exists.** The hot key declarations carry only `AVAILABLE_MAC_OS_X_VERSION_10_0_AND_LATER` and sit outside the `#if !__LP64__` blocks [1]. The 15.2 AppKit headers have no global hot key API [8].
- **Recommendation (§6):** a hybrid. A lone modifier stays on today's listen-only `flagsChanged` tap. Combinations, paste-last, copy-last, show/hide and Esc-while-recording use `RegisterEventHotKey`, registered exclusive, owned by one new non-capability type.

## 2. Carbon `RegisterEventHotKey`

- **Shape.** `RegisterEventHotKey(keyCode, modifiers, EventHotKeyID, target, options, &ref)`. You install a handler for `kEventClassKeyboard` / `kEventHotKeyPressed` and `kEventHotKeyReleased` with `InstallEventHandler`, and remove the key with `UnregisterEventHotKey` [1]. Every call is marked "Not thread safe" [1].
- **Permission.** The header names no permission. The probe process had every grant denied (`CGPreflightListenEventAccess`, `CGPreflightPostEventAccess` and `AXIsProcessTrusted` all false) and registration still succeeded [12][16]. That an unprivileged registration also *fires* is **(inferred)** until the delivery probe runs (§8).
- **Press and release.** Both events exist [1] and both arrive [19]. No header says when release fires; P1 shows it fires on the key's key-up, whichever order the keys lift in, with the modifiers still held (`hid=[LCtl+LOpt]` on the release line). A 2.2 s hold sent no repeated press [19].
- **⌥-only restriction.** macOS 15.0 refused registrations whose only modifiers were ⌥ or ⌥⇧, an intentional anti-keylogger change: "shift+option can be used to generate alternate characters in passwords, such as Ø" [9]. The original poster reported -9868 (`eventInternalErr`). Apple did not state the code **(anecdotal)** [9]. Apple says the rule was relaxed in 15.2 Beta 2 [9], and the probe on 15.7.5 agrees [12]. macOS 14 predates the change **(inferred)**. Later non-Apple reports of it coming back are **(anecdotal)** [9]. ⌥K fires on 15.7.5 and is kept from TextEdit [19].
- **Already-registered combinations (probe [12][13]):**
  - Same process, same key and modifiers: -9878 `eventHotKeyExistsErr`, as documented [2].
  - Two processes, both non-exclusive: both succeed. The header says both are notified [1][13].
  - Two processes, both `kEventHotKeyExclusive`: the second gets -9878 [2][13].
  - Exclusive after another process's non-exclusive: succeeds [13]. This agrees with `CarbonEventsCore.h` [2] but not with the `HotKeyOptions` comment in `CarbonEvents.h`, which says it should fail [1].
  - System shortcuts: ⌘Space (Spotlight), ⌘Tab and ⌘⇧3 all return `noErr` [12]. On a press both fire: Spotlight opened and the probe logged ⌘Space [19].
  - So an exclusive registration is refused only when another process holds the same combination exclusively [2][13]. Against a non-exclusive holder it succeeds silently and, per the header, that holder stops receiving the key [1]. Against a system shortcut both run [19].
- **Esc with modifiers 0.** Allowed since 10.3 ("you may pass zero") [1], and the probe returned `noErr` [12]. The catch, **(inferred)** from the global semantics: while it is registered, Esc goes to River and not to the frontmost app. River registers it only during a recording, so an Esc pressed then cancels the recording and nothing else. That is the intended trade, but the spec should say so. Esc pressed to close Spotlight never reached the probe [19], so whether Spotlight took it first or Esc did not fire there is unknown. A cancel path besides Esc is still needed (fn and the menu item).
- **Left/right and Fn.** `Events.h` defines `rightShiftKey`, `rightOptionKey` and `rightControlKey` as "Not supported on Mac OS X" [3]. The probe's `controlKey|rightOptionKey` registration returned `noErr` [12], so the bit is accepted, but either ignored or never matched (P1, id 6). `kEventKeyModifierFnMask` (bit 17) "Indicates that the Fn key was pressed" [1]. ⌃fn+K registers [12], but delivery is unverified (P1, id 7). The system's own symbolic hot keys carry the fn bit on F-keys and arrows (for example code 120 with ⌃fn) [14]. So the fn bit marks a key's own layout as well as a held Fn key **(inferred)**.
- **Secure Event Input.** It stops keyboard events going to "keyboard intercept" processes, which explicitly include event taps, "whether that process is in the foreground or background" [11][2]. TN2150 doesn't mention hot keys [11], so whether Carbon hot keys fire under secure input is unverified (P1 prints `IsSecureEventInputEnabled`). Whether a listen-only `flagsChanged` tap still sees modifier changes is also unverified. The technote says "keyboard events" without saying whether modifier-only events count (P3). A `keyDown` tap would lose keys under secure input per [11].
- **Thread.** `GetApplicationEventTarget` is the application's target, and `GetEventDispatcherTarget` is for apps that "pick events off the event queue" themselves [1]. So hot key handlers run in the main event loop **(inferred)**, and a stalled main actor delays them. Today the tap thread receives an event promptly but immediately hops to the main actor too [17]. Only the receipt time differs, and a Carbon event carries its own timestamp (`GetEventTime`), so hold timing can still be measured (P1 `block` mode prints the lag).
- **Status.** No deprecation macros on `RegisterEventHotKey`, `UnregisterEventHotKey`, `CopySymbolicHotKeys` or `IsSecureEventInputEnabled` [1][2]. The 15.2 AppKit and SwiftUI headers have only window-local shortcuts (`keyboardShortcut`) and the context-menu hotkey, with no global registration [8].

## 3. Extending the event tap with `keyDown`/`keyUp`

- **What it gains.** Every key, with side-specific modifiers from the device bits (`NX_DEVICELALTKEYMASK` 0x20, `NX_DEVICERALTKEYMASK` 0x40, and likewise for Ctrl, Shift and Cmd) [7].
- **What it costs.** Swallowing the combination needs an active filter: "An active filter may pass an event through unmodified, modify an event, or discard an event" [4]. `.listenOnly` cannot [5], and 0006 chose listen-only on purpose [17]. With an active tap, every key press in the session passes through River's callback before it reaches any app, so a stalled callback delays all typing **(inferred from [4])**. The system disables a slow tap with `kCGEventTapDisabledByTimeout` [5].
- **Permission.** Taps that receive key up/down need the caller "enabled for assistive device access" [4]. Apple DTS says listening has its own TCC service (`ListenEvent`, checked with `CGPreflightListenEventAccess`) and "Neither requires the full Accessibility privilege" for listen or post [10][4]. Developers report that an active (`defaultTap`) tap prompts for Accessibility and a listen-only tap for Input Monitoring **(anecdotal)** [18]. River already holds Accessibility for insertion, so the grant is not the blocker. The 0006 posture is.
- **Secure input.** A keyboard tap is a "keyboard intercept process" and goes deaf to keys in password fields [11].

## 4. Modifier-only (today's `flagsChanged` path)

- **Can express:** any one of the 10 modifier keys by keycode (54/55, 56/60, 58/61, 59/62, 57, 63), side-specific [17]. Combinations of modifiers only are also possible, side-specific too: each `flagsChanged` event carries the device bits [7][5], so for example Right ⌥ + Right ⌘ would work **(inferred)**.
- **Cannot express:** a modifier plus a non-modifier key, because the mask has no `keyDown`. It cannot see whether a key was pressed during a modifier hold, so a lone-modifier shortcut fires even when the user is typing ⌥-characters with it. That is today's behaviour too [17].
- **Coexistence.** A lone modifier on the tap and a Carbon combination can coexist. If the combination contains the same modifier, both fire **(inferred)**. River can suppress the lone-modifier action when a Carbon press arrives during the hold, which works in the tap modes (they act on release). Hold mode would already have started recording (§6 tradeoffs).
- **`NSEvent.addGlobalMonitorForEvents`** is no fit: "you can only observe the event; you cannot modify or otherwise prevent the event from being delivered", key events need Accessibility, and events sent to River itself are not reported [8].

## 5. Paste last and Hold mode for a combination

- **What River's insertion events carry.** `TextInsertionManager` builds each event with `CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown:)` and `keyboardSetUnicodeString`, sets no flags and no source state, and posts at `.cghidEventTap` [17]. With no key held, a freshly created event's flags are `0x20000000`, an undocumented bit with no modifier bits set. A `.combinedSessionState` source and a `.privateState` source give the same value [15]. `CGEventCreateKeyboardEvent` says the modifiers needed "must be entered" as their own key events [4]. Whether a held physical ⌘ is copied into a new event (P2) or merged in when the window server delivers it is not documented. The second needs a probe with post access (P4).
- **So paste-last should act after release, not on press.** If held modifiers do leak in, typed text arriving while ⌘ is down could turn into ⌘-shortcuts in the target app **(inferred risk)**. Waiting removes the question. `kEventHotKeyReleased` alone is not enough: it fires with the modifiers still down [19]. Wait until `CGEventSource.flagsState(.hidSystemState)` (or the tap's next `flagsChanged`) shows no modifier bits [6][15], with a short timeout. Whether `flagsState` reports held keys without a listen grant is part of P2.
- **Show/hide** types nothing, so acting on press is fine.
- **Hold for a combination.** Start on `kEventHotKeyPressed`. Stop on whichever comes first: `kEventHotKeyReleased`, or any of the recorded modifiers lifting on the existing `flagsChanged` tap. Carbon reports the key's release only [19], so the modifier half must come from the tap **(design)**.

## 6. Comparison and recommendation

| | Carbon hot key | Active keyDown tap | `flagsChanged` tap (today) |
|---|---|---|---|
| Combos with a letter/F-key | yes | yes | no |
| Keeps key from frontmost app | yes [19] | yes (active filter) | no (listen-only) |
| Left/right in combo | no [3] | yes [7] | modifiers only [7] |
| Lone modifier | no | yes | yes |
| Extra TCC | none [16] | Accessibility | Input Monitoring (held) |
| Sees all typing | no | yes | no |
| Thread | main event loop | tap thread, then main actor | tap thread, then main actor |
| Secure input | unverified | blocked [11] | unverified |

**Recommend the hybrid.** A recorded lone modifier keeps the listen-only `flagsChanged` tap and all three modes, unchanged. A recorded combination, paste-last (on full release), copy-last and show/hide (on press) and Esc (modifiers 0, registered at recording start and unregistered at its end) use `RegisterEventHotKey`, each with `kEventHotKeyExclusive`, so another app's non-exclusive registration does not also act on the press and another exclusive holder is reported (-9878). Tradeoffs to accept:

- No left/right distinction for a combination's modifiers.
- Users on macOS 15.0 and 15.1 can't register ⌥-only or ⌥⇧-only combinations, and River must show the failure.
- Conflicts with non-exclusive apps are not reported, and system shortcuts fire alongside River's, so the recorder warns from `CopySymbolicHotKeys` (see the recorder note).
- Delivery waits on the main thread, as tap handling already does.
- Caps Lock can't be a combination modifier.
- Esc is taken from every app while a recording runs.
- Hold mode with a lone modifier still can't tell typing from a hold.

**Owner (rule 3).** `RegisterEventHotKey`, `UnregisterEventHotKey` and the `InstallEventHandler` call need exactly one owner. Make it a new type in `Architecture/` that emits a typed event stream, the way `InputMonitoringCapability` emits `TapEvent`, with a test seam. It should not conform to `Capability`, because there is no TCC status to report, and `capabilities.md` defines a capability by the permission it owns [17]. Keep it out of `HotkeyManager`, which stays pure interpretation of both streams. Saved `activationKeyCode` values (the 10 modifier keycodes) migrate to lone-modifier shortcuts unchanged.

## 7. Open questions

- Whether a registered Esc fires while a system panel such as Spotlight is up (P1 saw no event).
- Whether `rightOptionKey` is ignored or never matches, and whether ⌃fn+K fires (P1).
- Carbon hot keys and the `flagsChanged` tap under Secure Event Input (P1, P3).
- Whether held modifiers leak into River's posted Unicode events (P2, P4).

## 8. Maintainer-run probes

All are in `/private/tmp/claude-501/-Users-abgregs-Developer-river/48da0173-71d4-46f4-8005-aa87365c3ea6/scratchpad/shortcut-probes/`, compiled, each with a usage comment.

- **P1 `./delivery 30` (then `./delivery 30 block`), run 2026-11-05 without `block` [19]:** registers ⌃⌥Space, ⌥K, Esc, ⌘Space, ⌘⇧V, ⌃+rOpt-bit+K, ⌃fn+K, ⌥⇧K and ⌃F19, and logs each press and release with the live side-specific HID flags, handler lag and secure-input state. Try release in both orders, a long hold, ⌘Space, Esc in another app, and a press with a password field focused.
- **P2 `./heldflags 8`:** hold ⌘ while it runs. It shows whether `flagsState` sees held keys without a grant and whether a new event copies them.
- **P3:** focus a password field and use River's Right ⌥ in Hold mode. Does it record?
- **P4:** in a build with paste-last on press, hold ⌘ in a text editor and watch for ⌘-shortcuts firing.

## 9. Sources

1. Apple, `MacOSX15.2.sdk/.../HIToolbox.framework/Headers/CarbonEvents.h`: `RegisterEventHotKey`, `UnregisterEventHotKey`, `HotKeyOptions`, `kEventHotKeyPressed`/`Released`, `kEventKeyModifierFnBit`, `CopySymbolicHotKeys`, `GetApplicationEventTarget`, `GetEventDispatcherTarget`.
2. Apple, `HIToolbox.framework/Headers/CarbonEventsCore.h`: `eventHotKeyExistsErr` (-9878), `eventInternalErr` (-9868), `EnableSecureEventInput`, `IsSecureEventInputEnabled`.
3. Apple, `HIToolbox.framework/Headers/Events.h`: modifier bits; right-side bits "Not supported on Mac OS X".
4. Apple, `CoreGraphics.framework/Headers/CGEvent.h`: event tap overview, `CGEventCreateKeyboardEvent`, `CGPreflight/Request{Listen,Post}EventAccess`.
5. Apple, `CoreGraphics.framework/Headers/CGEventTypes.h`: `kCGEventTapOptionListenOnly`, `kCGEventTapDisabledByTimeout`, `CGEventSourceStateID`, flag masks.
6. Apple, `CoreGraphics.framework/Headers/CGEventSource.h`: source state tables.
7. Apple, `IOKit.framework/Headers/hidsystem/IOLLEvent.h`: `NX_DEVICE*KEYMASK` side bits.
8. Apple, `AppKit.framework/Headers/NSEvent.h` and [addGlobalMonitorForEvents(matching:handler:)](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:)); grep of the 15.2 AppKit/SwiftUI headers for global hot key APIs (none).
9. Apple Developer Forums, [thread 763878](https://developer.apple.com/forums/thread/763878): Frameworks Engineer replies (Sep 2024, Nov 2024); the -9868 code and later regressions come from non-Apple posters **(anecdotal)**.
10. Apple Developer Forums, [thread 735204](https://developer.apple.com/forums/thread/735204): Quinn (DTS), Aug 2023, `ListenEvent`/`PostEvent` services.
11. Apple, [TN2150: Using Secure Event Input Fairly](https://developer.apple.com/library/archive/technotes/tn2150/_index.html) (2007, archived).
12. Probe `register`: 20 registrations, one process, no event loop. Printed `noErr` for all except the duplicate ⌃⌥Space (-9878) and `alphaLock`+⌃Space (-9868).
13. Probe `holdreg`, two processes on ⌃⌥⇧F19: non-exclusive + non-exclusive both 0. Exclusive then non-exclusive 0. Exclusive then exclusive -9878. Non-exclusive then exclusive 0.
14. Probe `symbolic`: `CopySymbolicHotKeys` returned 0, 229 entries (169 enabled), including code 49/⌘ and 48/⌘. Output in `symbolic-output.txt`.
15. Probe `heldflags`, run with no key held: `flagsState` 0 for both states; new events' flags `0x20000000` for nil, combined and private sources.
16. Probe `perms`: listen/post preflight false, `AXIsProcessTrusted` false, `IOHIDCheckAccess` denied for listen and post.
17. River: `Sources/River/Architecture/InputMonitoringCapability.swift`, `Sources/River/Managers/HotkeyManager.swift`, `Sources/River/Managers/TextInsertionManager.swift` (`makeUnicodeKeyEvent`), `Sources/River/Architecture/AccessibilityCapability.swift` (`postKeyEvent`), `docs/architecture/capabilities.md`, `docs/planning/0006_runtime-security-hardening.md`, `docs/planning/0017_cancel-recording.md`.
18. Apple Developer Forums, [thread 122492](https://developer.apple.com/forums/thread/122492): developer replies, no Apple staff **(anecdotal)**.
19. Probe `delivery 60`, run by the maintainer 2026-11-05 with TextEdit frontmost: ⌃⌥Space, ⌥K, ⌘⇧V and ⌘Space each logged one press and one release, lag 1–7 ms, on the main thread, the release with the modifiers still held; TextEdit showed `abcdef`; Spotlight opened on ⌘Space; no Esc event was logged.
