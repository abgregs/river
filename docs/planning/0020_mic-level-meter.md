# Planning: Mic Level Meter in the HUD (roadmap 0020)

**Landed, then re-rendered.** The bar meter shipped and was replaced on 2026-09-17 by the river indicator ([0028](0028_identity-implementation.md)): `LevelMeterPresentation` and the bar view are deleted, while everything below about *computing* the level inside `MicrophoneCapability` still stands — the indicator consumes the same published level, smoothing it per display frame. The reference RMS moved from 0.2 to 0.08 (`Constants.inputLevelReferenceRMS`) because `AVAudioEngine` delivers a raw signal where a browser applies gain control.

A queued backlog item from the 2026-07-06 UX review. Show a live input-level indicator (pulsing bars / simple waveform) in the recording HUD, so the user can see *during* the recording that audio is actually being captured. **Depends on [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md)** (the HUD is the rendering surface); part of the feedback-layer grouping in [_index.md](_index.md).

## Problem

A muted mic, a dead headset, or the wrong input device produces silence — and today the user finds out only *after* the cycle, as "Couldn't transcribe: Transcription returned no text." That error is technically honest but diagnostically empty: the user re-records into the same silent mic. A live level meter converts this from a post-hoc mystery into immediate feedback ("the bars aren't moving — my mic is muted"), the same way every voice-memo and call app does.

## Design: level computed at the one `AVAudioEngine` site

- **The level tap lives inside `MicrophoneCapability`** — the only place `AVAudioEngine` is touched (load-bearing rule #3). It computes a cheap RMS/peak from the buffers already flowing through the existing `audioBuffers` tap; no second tap, no new OS surface.
- **Published throttled** (~10–15 Hz is plenty for a meter), hopping from the audio callback to the main actor before publishing — the same callback-thread → main-actor discipline as the event tap ([../architecture/threading-invariant.md](../architecture/threading-invariant.md)).
- **`AppState` observes; the HUD renders.** The menu bar is unchanged. The level → visual mapping (how many bars, pulse scale) is a pure function, tested like `MenuBarPresentation`.
- **Sharpening the empty-transcription error (optional, decide during implementation):** if the level stayed near zero for the whole recording, the cycle's empty-result error can say so — "No audio detected — check that your microphone isn't muted" — turning the app's least actionable error into its most actionable one. Composes with [0018_transient-error-toasts.md](0018_transient-error-toasts.md).

## Acceptance criteria

1. While `.recording`, the HUD shows a level indicator that visibly responds to speech and sits at rest in silence. (Met by the river indicator's strands since 0028.)
2. Level computation is unit-tested against synthetic buffers (loud / quiet / silent — the `AudioCaptureManagerTests` fake-buffer pattern); no real mic needed.
3. Publish throttling is unit-tested with an injectable clock; the publisher emits on the main actor.
4. The level → visual mapping is a pure, unit-tested function.
5. `CGEvent`/`AVAudioEngine` one-call-site rules are unchanged — the meter adds no new OS call sites.

## Related

- [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md) — the rendering surface (hard dependency)
- [0018_transient-error-toasts.md](0018_transient-error-toasts.md) — the "no audio detected" error sharpening composes with the toast surface
- [../architecture/capabilities.md](../architecture/capabilities.md) — `MicrophoneCapability`, the single `AVAudioEngine` owner
- [../architecture/threading-invariant.md](../architecture/threading-invariant.md) — the callback → main-actor pattern the level publisher mirrors
