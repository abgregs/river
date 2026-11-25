# Planning: Model Loading Indicator (roadmap 0004)

**Status:** built 2026-11-21 in PR 11 (`feat/preparing-treatment`): dictation always starts, the status row and its ring beside the indicator, the ring in Settings and the menu bar, and the real download percentage. The decisions are in "Update (2026-09-25)" below. Since 2026-11-24 (`feat/status-surface`) the status shows alone in the mark's place and carries the cycle errors too: see "Update (2026-11-24)". Smoke-tested on device 2026-11-21 and 2026-11-22: everything passed except a download that fails part-way, which waits until after PR 12's onboarding step (maintainer, 2026-11-22).

A queued follow-up, deferred from the M8 custom-dictionary work. Surfaces the
model-loading state in the menu bar so a dictation attempted before the model is
ready gets clear feedback instead of a silent failure.

## Problem

The custom dictionary needs the model fully loaded — including the tokenizer —
before the first transcription, or the prompt is empty (see
[../requirements/custom-dictionary.md](../requirements/custom-dictionary.md)).
`TranscriptionManager.loadModel()` now uses `load: true`, so the model genuinely
loads into memory at launch, and the default `small.en` (~490 MB) makes the
first-ever run longer. During that window `transcribe` fail-fasts with
`.modelNotLoaded` ("Couldn't transcribe. Transcription model is not loaded yet")
and the spoken audio is lost — while the menu bar still shows "Ready," which is a
lie until the model is warm.

The fail-fast itself is deliberate (the cycle returns to `.idle` rather than hang
— see `TranscriptionManagerTests` "with no model loaded"), but with a real load at launch it
is now hit often enough to need a user-visible surface.

## Desired behavior ("warm vs warming up" — the cache-hit analogy)

- **Cold launch** (model not yet downloaded): status shows **"Downloading model…"**
  then **"Loading…"** — never "Ready" — until the model is in memory. First run
  only (~490 MB).
- **Warm launch** (model already downloaded): **no re-download**; a brief
  **"Loading…"** while CoreML loads it into memory, then **"Ready."** (Each process
  start re-loads into memory — a few seconds — so "Ready" follows a short load, not
  literally zero delay.)
- Dictating before "Ready" gives clear feedback (the status already shows it isn't
  ready) and ideally either waits for the load or declines to start recording,
  rather than record-then-error and lose the audio.

## Mechanism (sketch)

- `TranscriptionManager` exposes a load state (e.g. `downloading / loading / ready
  / failed`), distinguishing download from in-memory load.
- `AppState` observes it via the existing Combine→`@Observable` bridge, and
  `MenuBarPresentation` maps it to the icon/label — extending the menu-bar layer
  from the visual-state milestone
  ([../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md)).
- Optionally gate recording start on `ready` (or have `transcribe` await an
  in-flight load) — a deliberate change to the current fail-fast contract; decide
  during implementation.

## Acceptance criteria

1. A launch with an uncached model shows a downloading/loading status, not "Ready,"
   until the model is in memory.
2. A cached launch never re-downloads, shows a brief loading state, and reaches
   "Ready" promptly.
3. Dictating during load produces clear feedback (and no silently lost audio)
   rather than the bare `.modelNotLoaded` error.
4. The load-state → label mapping is unit-tested (pure, like `MenuBarPresentation`).

## Update (2026-09-25): copy, visual, and open follow-ups

Planning [0029](0029_pixel-identity.md) renamed the `.loading` label to "Preparing model…" (HUD) and "Preparing model..." (menu bar), because "Loading" reads as a hang when a first launch compiles for the Neural Engine ([../conventions/local-builds.md](../conventions/local-builds.md)). The HUD shows the pixel r with a slow ink crest above a text-only label, in place of the spinner. Behavior is unchanged. Three follow-ups remain open:

- **When the HUD shows.** It appears for every load, including routine warm launches of about 2.5 s that nobody asked to see. *Decided 2026-11-20 (maintainer), built in PR 11 (`feat/preparing-treatment`):* nothing shows at launch; the load shows only when the user dictates before the model is ready. A launch nobody dictates through shows nothing; the menu bar and the Model section still name the state.
  - **Dictation always starts.** A press before the model is ready, downloading or preparing, records as usual, and the transcript waits for the model and is typed once it is ready. The "Model still loading" toast goes. **Why:** this replaces refusing the press (decided earlier the same day): the user can always dictate, and AC 3's no-lost-audio holds because nothing is refused.
  - **A one-line status beside the recording indicator,** 8 pt to its right: the ring and its words, shown in full from the moment it appears. *Decided 2026-11-21 (maintainer):* every status shows its whole message, downloading, preparing and ready included; there is no icon-only mark and no hover, so the panel keeps ignoring the pointer, as it does today outside the live transcript. VoiceOver announces the status. **Why:** this replaces a small mark that opened its status on hover: the whole message reads at a glance, and nothing needs the pointer. *Words revised 2026-11-22 (maintainer):* "Typing after model download" with its percentage, "Typing once model is ready", and, for held text, "App switched" before the Paste last shortcut; VoiceOver hears the same words. **Why:** the line says what the text waits for, and why it wasn't typed.
  - **Only once the dictation ends.** *Decided 2026-11-21 (maintainer):* while the user speaks, the download and the preparation run unseen. The mark appears only when the dictation ends and the model still isn't ready, half a second after, and a failure during the dictation shows then, already failed. A dictation that outlasts the load shows nothing at all. **Why:** this replaces showing the mark during the dictation, where it was a distraction; the user needs it only when their text can't be typed yet.
  - **The mark is a ring.** *Decided 2026-11-21 (maintainer):* its arc fills with the download's real fraction, a light turns round it while the model is prepared, a check appears when it is ready, and an exclamation mark in an akane ring when it couldn't load. Settings' Model section and the menu bar's menu use the same ring for the same states, in place of the indeterminate bar and today's symbols.
  - **How long a status stays.** *Decided 2026-11-21 (maintainer):* after ready, the status leaves with the panel once the text has typed; a load that fails and an app that changed stay 4 s after they show, then leave with the panel. Once the panel has gone, the menu bar and Settings keep the status: a failed load until the next successful load, held text as the last transcript, for the Paste last shortcut and Copy Last Transcription. **Why:** this replaces opening the message on its own for those two statuses only, decided earlier the same day, since every status now shows its message in full.
  - **A failed load keeps the recording** in memory only, as the last transcript is ([0019](0019_last-transcript-recovery.md)); the status says the model couldn't load, and the next successful load (Try Again in the Model section) transcribes it, joins several with a space and holds the text, never typed. A quit loses them. Settings' subtitle counts them ("1 recording kept").
  - **A changed app holds the text.** If the app dictated into is no longer frontmost when the transcript is ready, River types nothing and keeps the text as the last transcript, and the status points to Paste last and Copy Last Transcription ([0019](0019_last-transcript-recovery.md)).
  - A model switch never shows the mark, since the model in use keeps working until the new one is ready ([0026](0026_model-switch-availability.md)). A model in use whose files are gone, removed outside River, downloads again at launch, as today. The first-run download shows in onboarding (PR 12).
- **A network check on every launch.** *Done 2026-09-28: a cached model now loads from its folder with downloading off, falling back to the download path if the folder won't load; offline check in [../conventions/test-harnesses.md](../conventions/test-harnesses.md).* Before `loadModels`, `WhisperKit(model:downloadBase:load: false)` asks Hugging Face for the model's file list and compares it with the cache, even when the files are present. On the maintainer's warm launch this took 2.1 s of a 2.5 s wait (the CoreML load was 0.38 s). Passing the cached model folder to WhisperKit would skip it, making warm launches sub-second and offline, as `PRODUCT.md` says they are.
- **Download progress.** *Decided 2026-11-21, built in PR 11:* WhisperKit's `download(variant:…, progressCallback:)` and FluidAudio's `AsrModels.download(to:…, progressHandler:)` both report it, and River passes it on, so the ring and the Model section show the real percentage. **Why:** this replaces filling the pixel r by sixteenths, an idea for a mark River no longer uses.

## Update (2026-11-24): one status surface

Decided by the maintainer over three design rounds (2026-11-24); where they differ from the 2026-11-21 decisions above, these replace them.

- **The status shows alone.** The mark's panel leaves on its ordinary exit, and the status enters in its place, centred, bottom edges aligned, 0.12 s after the panel has gone (`statusEntryBeatSeconds`), on the HUD's fade. **Why:** this replaces the row 8 pt to the panel's right, which held the panel up through the wait: one floating shape at a time reads as orchestrated, not crowded.
- **When.** A dictation that waits for the model lets the panel go at once; its status is revealed `KawaIndicatorTimeline.statusHandOff` after the release (the panel's 0.78 s exit plus the beat, 0.90 s), replacing the 0.5 s reveal, and a load that finishes sooner still shows nothing. A status set while a panel may still be up (an error, held text, a load that failed while the user spoke, or Paste last failing just after a dictation) waits for the panel, and its 4 s hold adds the hand-off, so it stays at least 4 s on screen (at most 4.9 s). Ready stays `statusReadyHoldSeconds` (0.6 s) once its check is drawn, or until the text has typed if that is later, so something shows through the decode. A new recording while a status shows fades it out over 0.5 s (`statusInterruptedFadeSeconds`), easing in and out, as the panel comes in over it (maintainer, 2026-11-25: 0.1 s read as jarring on device).
- **Size B.** 36 pt tall: the 26 pt tile padded 5 pt inside the surface, a hairline on the tile's edge, the words at 13 pt, the outer corner 11 pt, the mark's panel's. **Why:** the 26 pt row put the tile's border against the surface's edge; the maintainer wanted it larger, with the tile sitting inside.
- **Errors are statuses** ([0018](0018_transient-error-toasts.md)): one line, a headline then a short detail. Every error takes Couldn't load the model's mark, the akane ring round the exclamation mark, except a permission refused, which takes a lock (the held sheet's build: shackle in outline, body solid, keyhole cut out). **Why:** the maintainer judged the per-error glyphs of round 2 unnecessary; one failure mark reads at once.
- **App switched's held sheet** moves 0.75 pt up, so its ink centres in the tile (`StatusGlyphTests`).
- **No notices in the floating UI.** The message rectangle is gone; the mid-recording notice stays a menu line, and Settings turns off Start by during a dictation, as it already did the shortcut rows ([../requirements/activation-key-and-mode.md](../requirements/activation-key-and-mode.md), Live apply).

## Related

- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — the status surface this extends
- [../requirements/custom-dictionary.md](../requirements/custom-dictionary.md) — why the model (tokenizer) must be loaded before the first prompt
- [milestones.md](milestones.md) — the roadmap this is queued in
- [0021_model-picker.md](0021_model-picker.md) — depends on this item: a model switch re-enters exactly the download/load window this makes visible, so this lands first
- [_index.md](_index.md) — the feedback-layer grouping; this is an independent rider of the same `AppState` seam as [0002](0002_recording-indicator-hud.md)/[0016](0016_recording-sound-cues.md)
