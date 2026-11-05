# Live text and microphone settings (0034)

**Status: planned for `v0.3.0` (PR 10), not started.** Collects the maintainer's direction on what the user controls around streaming, the live text and the microphone, agreed in chat from 2026-10-16 to 2026-10-31 and amended for `v0.3.0` on 2026-11-04. The microphone switch shipped in PR #79 ([0033](0033_warm-microphone-pre-roll.md)); the rest is unbuilt. Every other setting, and how shortcuts are registered and recorded, is in [0036](0036_settings-and-shortcuts.md).

## Problem

River now streams: it decodes speech while the user talks and shows the text above the indicator (PR #62). Settings still exposes the pipeline itself, "Transcribe while I speak", which mixes up two things the user actually cares about: whether the live text is on screen, and when the microphone is open. Neither is a question about how River transcribes.

## Decisions

1. **Streaming is the only pipeline, with no setting.** Every dictation streams, whether the live text is shown or hidden and whatever the microphone switch says. The text is typed once, at release, as before. The "Transcribe while I speak" toggle is removed, not renamed. `Settings.streamingDictation` stays as a hidden `defaults write` fallback until the gate below is passed. (Decided 2026-10-22.)
2. **Showing the live text is the user's opt-in.** Whether the live text shows is one remembered state, `showLiveText`, **hidden by default, first run included** (maintainer, 2026-10-31; earlier drafts said shown on first run). In `v0.3.0` the user shows or hides it **with a shortcut only**; the hover menu and the click toggle are cut from this release (maintainer, 2026-11-04; see "Panel controls"). There is no Settings toggle for it.
3. **Hidden and shown behave differently, and both are cheap.**
   - Hidden: the panel shows the mark only; the word count is cut from `v0.3.0`. No provisional (preview) decodes run; committed segments are still decoded, so release stays fast.
   - Shown: preview decodes run, gated by a runtime flag on `DictationStream`.
   - On hide, the last preview is kept and new ones stop; a decode already in flight finishes and its result is dropped. Showing again never forces a decode, so toggling back and forth costs no more than leaving the text shown.
4. **Settings holds two entries for this area, and only two.**
   - **"Show or hide live text":** a shortcut recorder in the Shortcuts section, **default ⌃⌥L**, which the user can record over or clear. Amended 2026-11-04 from "empty by default": the shortcut is now the only way to show the text, so it ships set. Registered as a hot key and fired on press ([0036](0036_settings-and-shortcuts.md)).
   - **"Only use the microphone while dictating":** on/off, default off, in the Dictation section. Shipped in PR #79, merged 2026-10-29; see [0033](0033_warm-microphone-pre-roll.md), decision 3. It controls only when the microphone is open, never whether River streams or what the panel shows.
5. **Privacy is unchanged by streaming.** Streaming captures nothing beyond the press-to-release window. The only extra audio is the warm microphone's 0.5 s pre-roll before the press, held in memory and discarded continuously, and the user is told so plainly ([0033](0033_warm-microphone-pre-roll.md), "What the user is told"). Nothing is kept after release.

## Gate

**Real-speech accuracy parity before the one-shot path goes.** The streaming review measured no segmentation cost, but only on synthetic clips cut at quiet points. Replay a few long real dictations both ways (the untracked `StreamingReplayTests.swift` compares against one-shot). Until that passes, the toggle may stay and `streamingDictation` stays a working fallback.

## Panel controls (deferred past `v0.3.0`)

Direction from 2026-10-21, not final. The maintainer deferred all of it past `v0.3.0` on 2026-11-04 (Open items in [_index.md](_index.md)); only the animation below applies to the shortcut in `v0.3.0`:

- A hover menu on the recording indicator opens after a short dwell, only once the pointer has moved (a cursor resting where the panel appears does not open it), or on a click. It stays open while the pointer is over the indicator, the menu, or the gap between them, with a grace timer for leaving all three.
- Items: Show/Hide transcript, and Settings (gear).
- A shortcut-driven show/hide gets a short animation, about 150 ms in and 120 ms out, strong ease-out, opacity plus a small rise, driven from state so a reversal mid-way retargets. The maintainer chose this over "no motion on keyboard actions" (2026-10-21).

## Out of scope

- The rest of the settings panel and the other shortcuts: [0036](0036_settings-and-shortcuts.md).
- The hover menu, the click toggle and the word count (deferred, above).
- A microphone picker.

## Acceptance criteria

1. Settings shows no streaming toggle and no live-text visibility toggle.
2. A fresh install starts with the live text hidden; the panel shows the mark only.
3. Showing the live text with the shortcut takes effect during a recording and is remembered for the next one.
4. With the live text hidden, no preview decode runs (log), and release-to-text time matches the shown case.
5. ⌃⌥L toggles the live text on a fresh install; a recorded shortcut replaces it; with the shortcut cleared, nothing is bound and the text stays as last set.
6. "Only use the microphone while dictating" behaves as 0033 specifies, with the live text shown or hidden.

## Related

- [0033](0033_warm-microphone-pre-roll.md): the microphone switch and the pre-roll.
- [0036](0036_settings-and-shortcuts.md): the settings panel, every setting, and how shortcuts are registered and recorded.
- [0030](0030_floating-ui-visibility.md): the floating UI's window lifecycle, which any show/hide work must keep intact.
