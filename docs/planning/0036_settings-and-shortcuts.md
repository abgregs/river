# Settings and shortcuts (0036)

**Status: PR 7 built and in review as [#92](https://github.com/abgregs/river/pull/92) (2026-11-11); PRs 8 to 10 not started.** Every setting River offers in `v0.3.0`, how the settings panel groups and labels them, and how River registers and records its shortcuts. Agreed with the maintainer on 2026-11-04 and 2026-11-05. PRs 7 to 10 of the `v0.3.0` plan ([current-focus.md](current-focus.md)) build it. The panel's visual design (layout, icons, size) is PR 7's design rounds, not this spec. The live text and microphone decisions are in [0034](0034_live-text-and-microphone-settings.md). The mechanism rests on [../research/shortcut-registration.md](../research/shortcut-registration.md) and [../research/shortcut-recorder.md](../research/shortcut-recorder.md).

## The panel

- **One settings window replaces today's.** It is an ordinary macOS window with River's tint inside, one section per area below (maintainer, 2026-11-09, settings panel study round 11). macOS draws its frame: corner, edge, shadow and window buttons. Minimise and zoom are dimmed, and the window's title is the section shown, hidden on screen. **Why:** Apple's guidelines say to avoid custom window frames and controls, and to dim a settings window's minimise and zoom buttons. It does not use `HUDSurface`; the floating surfaces take its edge instead ([../design/color.md](../design/color.md)). PR 7 removes the SwiftUI `Settings` scene and `SettingsView`.
- **It stays open behind other apps** (maintainer, 2026-11-10). It is a normal-level window: it neither floats over the app in front nor closes when River loses focus, so you can grant a permission in System Settings and come back to it.
- **Pop-up menus are the system's.** Their highlight is the user's accent colour, as are the keyboard focus ring and selected text; only River's own controls are monochrome (maintainer, 2026-11-10). **Why:** AppKit draws its menus in the system's colours, and recolouring them means River drawing every item itself, which is the custom control Apple's guidelines warn against.
- **It opens from "Settings…" in the menu bar menu** (⌘, while the menu is open, as today). One panel at a time; choosing "Settings…" again brings it forward.
- **It makes River the active app while it is open**, as "Settings…" does today. Unlike the indicator's panel, it can become key, so the recorder receives key presses. **Why:** the recorder probe saw every key once the panel was key in an active app; a panel that leaves its app inactive was not tested, and settings need no such thing ([../research/shortcut-recorder.md](../research/shortcut-recorder.md), §2).
- Labels are sentence case and name what the user controls. A toggle describes its on state.

## Every setting

| Section | Label | Control | Key | Default | PR |
|---|---|---|---|---|---|
| Shortcuts | Dictation shortcut | recorder | `dictationShortcut` (new; migrates `activationKeyCode`) | Right ⌥ | 8 |
| Shortcuts | Start by | Hold / Tap / Double-tap | `activationMode` | Hold | 7 |
| Shortcuts | Paste last transcription | recorder, clearable | `pasteLastShortcut` (new) | ⌃⌥V | 9 |
| Shortcuts | Copy last transcription | recorder, clearable | `copyLastShortcut` (new) | none | 9 |
| Shortcuts | Show or hide live text | recorder, clearable | `liveTextShortcut` (new) | ⌃⌥L | 10 |
| Dictation | Play sounds when dictation starts and stops | toggle | `playFeedbackSounds` | off | 7 |
| Dictation | Keep the microphone ready | toggle | `keepMicrophoneReady` (new; replaces `micOnlyWhileDictating`, inverted) | on | 7 |
| Model | Model | catalogue: the model in use with its status, search, a provider filter, a table with a Select button per row | `selectedModel` | `openai_whisper-small.en` | 7 |
| General | Open River at login | toggle | `launchAtLogin` | off | 7 |
| General | Check for updates automatically | toggle, release builds only | Sparkle's `automaticallyChecksForUpdates` | on | 7 |
| Permissions | Microphone · Input Monitoring · Accessibility | "Granted", or an "Open System Settings…" button | none (the capabilities' status) | | 7 |

- **Cancel line:** "Cancel a recording with fn or Esc." follows the Start by description, in the same text (maintainer, 2026-11-09; it was the Shortcuts footer). When fn is the dictation shortcut, it reads "Cancel a recording with Esc."
- **Start by** keeps today's three modes under shorter labels, each with today's one-line description, worded for a shortcut ("Hold the shortcut while speaking; release to finish.").
- **Dictation** shows the microphone switch's description from [0033](0033_warm-microphone-pre-roll.md) ("What the user is told"). The switch is turned around from PR #79's "Only use the microphone while dictating" (maintainer, 2026-11-09): on by default and named for its on state. `micOnlyWhileDictating` never shipped in a release, so the new key replaces it with no migration.
- **Model** (maintainer, 2026-11-09, settings panel study round 13):
  - The window grows to 820 × 540 for this section and returns to 600 × 380 for the others.
  - Choosing another model switches only once it is ready. Until then, dictation keeps using the current model. This needs per-model download state ([0026](0026_model-switch-availability.md)).
  - A choice made during a dictation starts loading at once, beside the model in use. If it is ready before the dictation ends, its row reads Waiting and the line above the table says "*Model* is ready. River switches to it after this dictation." It takes over when the dictation ends (maintainer, 2026-11-11).
  - Each row's button says "Select".
  - No model is marked "Recommended" in `v0.3.0`, and the build adds no setting for it (maintainer, 2026-11-09, round 14).
  - Rows don't list languages, because River writes English only in `v0.3.0`; languages are deferred.
  - New models in `v0.3.0` must be English-only, unless a multilingual model is clearly better at English. The two new rows are NVIDIA Parakeet TDT v2 and Fermion Research's Phonon-2 (English-only; it needs macOS 15, and on macOS 14 its row says so).
  - Left out: Parakeet TDT v3 and Phonon-2.5, which differ mainly in their languages, and Phonon-2.5 English, which has no Core ML build yet.
  - Both new models run through a second engine, FluidAudio, which PR 7a adds ([0037](0037_fluidaudio-engine.md)). PR 7 shows the Whisper models and builds the catalogue with the fields the new rows need. The model list is approved (maintainer, 2026-11-10), after a spike ran both models through FluidAudio 0.18.3 on macOS 15: Parakeet TDT v2 inside the signed app, Phonon-2 in a test program.
- **The update toggle** binds to Sparkle's own property, so River declares no key string for it (rule 4). Without it, the answer to Sparkle's first-launch prompt could never be changed. Dev builds hide it, as they hide "Check for Updates…".
- **Permissions** reuses each capability's live status and its `openSystemSettings()`; no new mechanism. First-run onboarding is unchanged. While any permission is missing, the Permissions item in the sidebar carries a badge and the window opens on Permissions. Each permission has a one-line description of what River uses it for (maintainer, 2026-11-10; the wording can change in review).
- **The panel ends with the version line**, "River 0.3.0 (build)". Clicking it opens the standard macOS About window, whose Credits area names each model and open-source package River ships, with its licence (maintainer, 2026-11-10). The same notices ship as a plain-text file in the app's resources, and `make verify` fails without it. **Why:** River ships MIT and Apache-2.0 packages and MIT-licensed Whisper models, and both licences require their notice to travel with every copy; no release so far has carried one. The menu bar menu gains no item.
- **No row, by decision:**
  - `streamingDictation` stays a hidden `defaults write` fallback (0034, decision 1).
  - `showLiveText` (new, Bool, default off) is the remembered live text state. Only its shortcut changes it (0034, decision 2).
- **Interim rows.** PR 7 shows today's Activation Key picker until PR 8 replaces it with the recorder, and today's "Transcribe while I speak" toggle in Dictation until PR 10 removes it.
- **Not in `v0.3.0`:** custom words (out of scope since [0008](0008_custom-dictionary-redesign.md)), a sound volume slider, a microphone picker, and the live text's panel controls (Open items in [_index.md](_index.md)). There is no Transcription section until it has rows of its own.

## The menu bar menu

PR 7 removes "Permissions…", since the Permissions section replaces it. The menu becomes: the status line (with an error or notice when there is one), "Cancel Recording" (only while recording), "Copy Last Transcription", "Check for Updates…" (release builds only), "Settings…" and "Quit River". Nothing is added.

"Copy Last Transcription" stays for now as the clipboard fallback: if typing failed in the target app, a real paste may still work ([0031](0031_terminal-insert-fidelity.md)). This is a current choice, not a requirement; a later change may drop it.

The menu's ⌘. / ⌘, / ⌘Q are menu key equivalents that work only while the menu is open. They are Mac conventions, not River shortcuts.

## How River registers each shortcut

| Shortcut | Mechanism | Fires |
|---|---|---|
| Dictation, a lone modifier | today's listen-only `flagsChanged` tap | as today, in all three modes |
| Dictation, a combination | `RegisterEventHotKey` | Hold: starts on press, stops on the key's release or any of its modifiers lifting, whichever is first. Tap modes: on the key's release |
| Paste last transcription | `RegisterEventHotKey` | once every key is up |
| Copy last transcription, show or hide live text | `RegisterEventHotKey` | on press |
| Cancel | the fn tap (today); Esc via `RegisterEventHotKey`, registered at each recording's start and removed at its end | on press |

**Why the hybrid:** a registered combination needs no permission, reaches River within a few milliseconds, never repeats while held, and is kept from the app in front (probe: TextEdit showed `abcdef`). The event tap stays listen-only and never sees ordinary typing, so [0006](0006_runtime-security-hardening.md) stands. Esc needs no tap change, which settles [0017](0017_cancel-recording.md)'s concern. An active `keyDown` tap would pass every keystroke on the Mac through River and lose keys in password fields. See [../research/shortcut-registration.md](../research/shortcut-registration.md), §6.

- **Exclusive registration.** Every River hot key passes `kEventHotKeyExclusive`, so another app's non-exclusive registration of the same combination does not also act on the press. Only another exclusive holder is reported, as `eventHotKeyExistsErr`. macOS's own shortcuts still fire alongside River's (⌘Space opened Spotlight in the probe).
- **Paste last waits for every key to lift.** Carbon's release arrives with the modifiers still held, and typed text arriving under a held ⌘ could become shortcuts in the target app. River waits until the tap shows no modifiers down, with a short timeout, then types the last transcription through the existing insertion path; the clipboard is never touched. With no last transcription, or while a dictation is recording or processing, it does nothing.
- **Copy last** does what the menu item does.
- **Show or hide** toggles `showLiveText`, during a recording or between recordings (0034).
- **One owner (rule 3).** A new type in `Architecture/` owns `RegisterEventHotKey`, `UnregisterEventHotKey` and their `InstallEventHandler`, and emits a typed event stream with a test seam, as `InputMonitoringCapability` emits `TapEvent`. It is not a `Capability`, since it guards no permission. `HotkeyManager` interprets both streams. PR 8 builds it and adds it to rule 3 in `AGENTS.md` and to [../architecture/capabilities.md](../architecture/capabilities.md).
- **Accepted limits:** a combination does not tell left from right modifiers (a lone modifier still does); Caps Lock is not a dictation key (see Mode warnings); macOS 15.0 and 15.1 refuse combinations whose only modifiers are ⌥ or ⌥⇧; while a recording runs, Esc goes to River and not to the app in front; and a lone modifier in Hold mode still can't tell a hold from typing with it, as today.

## The recorder

- **Capture.** A local `NSEvent` monitor for `keyDown` and `flagsChanged` while the panel is key. Repeats are ignored.
- **Lone modifier or combination.** A modifier pressed and released with no other key between records that modifier, left or right. A non-modifier key pressed while modifiers are held records the combination. A key with no modifier is not recordable.
- **Esc stops recording; Delete clears the shortcut**, so Esc and Delete alone are never recorded. The dictation shortcut cannot be cleared.
- **River's shortcuts are off while recording.** Its hot keys are unregistered and the tap's actions ignored, then restored. **Why:** a registered hot key takes the key before the panel sees it (recorder probe). Recording is unavailable while a dictation is recording or processing.
- **Conflicts:**
  - A combination River already uses is refused, naming the shortcut that has it.
  - A combination another app holds exclusively is refused: "Another app uses this shortcut. Choose another."
  - A combination in macOS's own list (`CopySymbolicHotKeys`, enabled entries) is saved with a warning: "macOS also uses this shortcut. Both will run." Inform, don't block.
  - A refusal at registration, such as macOS 15.0 refusing an ⌥-only combination, is shown in the same place.
  - A saved shortcut that fails at launch shows "Not working: another app uses this shortcut." on its row.
- **Fn as the dictation shortcut** turns the fn cancel off, as today, and the cancel line says so; Esc and the menu item still cancel.
- **A River combination pressed during a lone-modifier hold** (Right ⌥ as the Hold key, then ⌃⌥V) discards the recording that hold started, with no cue, and the combination's action runs.
- **Mode warnings.** PR 8 checked what River's tap sees for Caps Lock: one event per press and none on release, so Hold never stops and a tap mode needs two presses. Caps Lock is no longer a dictation key, and a saved one migrates to the default. No other recorded key is unreliable in a mode, so the Caps Lock + Hold warning goes and no mode warning remains.
- **Changes apply** as today for the dictation shortcut and mode ([../requirements/activation-key-and-mode.md](../requirements/activation-key-and-mode.md), "Live apply"). The other shortcuts apply at once.
- **Migration.** On first launch of `v0.3.0`, a saved `activationKeyCode` becomes the same lone modifier in `dictationShortcut`, once, and the old key is dropped. A shortcut is stored as one string value, so `@AppStorage` can bind it; an empty value means cleared.

## Acceptance criteria

1. "Settings…" opens the panel with the five sections and rows above; the old Settings window, the Activation Key picker, "Transcribe while I speak" and the "Permissions…" menu item are gone.
2. A recorded lone modifier and a recorded combination each start and stop dictation in Hold, Tap and Double-tap, and a combination never types into the app in front.
3. An existing `activationKeyCode` survives the update as the same dictation key.
4. ⌃⌥V types the last transcription at the cursor with no modifier leaking into it and no clipboard change; ⌃⌥L shows or hides the live text; both can be recorded over or cleared.
5. Esc cancels a recording and reaches other apps normally between recordings.
6. Each conflict case shows its message, and a refused combination is not saved.
7. The tap is still created with `.listenOnly` and `flagsChanged` only.

## Related

- [0034](0034_live-text-and-microphone-settings.md): the live text and the microphone switch.
- [../requirements/activation-key-and-mode.md](../requirements/activation-key-and-mode.md), [../requirements/supported-keys-and-limitations.md](../requirements/supported-keys-and-limitations.md): rewritten by PR 8 for a recorded key.
- [../architecture/settings-store.md](../architecture/settings-store.md): the typed keys.
