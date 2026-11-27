# Planning: One Owner per Dictation Pipeline Rule (0039)

**Status: A, B and C built 2026-11-23 on `refactor/pipeline-owners`, one PR, smoke-tested on device 2026-11-24, merged as [#100](https://github.com/abgregs/river/pull/100) (2026-11-24). Its review's six items were settled 2026-11-25: three fixed on `fix/pipeline-review`, three decided for D below. D follows.** Designed from an architecture review of the dictation pipeline on PR 11's branch (`feat/preparing-treatment`), after PR 11's smoke test; the maintainer made the four decisions below the same day.

## Why

Each model and each target app has quirks, and River has no place for them. Three found on 2026-11-23:

- **Phonon-2 writes digits against the word before** ("for30", "about10 to15"). FluidAudio 0.18.3 turns the model's pieces into text with no rule of its own (`convertTokensToText`), and River does no cleanup of FluidAudio text, so the glued digits are typed.
- **Claude Code's prompt moved River's last character.** It holds rapid multi-character key events back as a possible paste but takes a single character at once. River types in chunks of 20 UTF-16 units, so a transcript of 421 characters ended on a one-character chunk, its final period, which landed 20 characters early when typed at release and 100 early with Paste last.
- **Loading one encoder window changed FluidAudio's split** of a clip over 15 s from cuts at a pause to overlapping windows ([0037](0037_fluidaudio-engine.md)), and no River test could see it.

The review found three rules with no single owner:

1. **What a transcript is.** Each engine adapter decides. An empty decode stops live streaming under Whisper (`.emptyTranscription`) but drops one segment under FluidAudio (`.noSpeechDetected`), and the callers treat `.emptyTranscription` four ways: loud in the one-piece decode and the tail, quiet for kept recordings, and a stop to streaming mid-dictation.
2. **How text reaches an app.** `RiverSession` owns the hold check, Paste last's task, Copy Last Transcription and the newline rule; `TextInsertionManager` owns the chunks and their pacing. Nothing runs inserts one at a time, and the pacing suspends between chunks, so a second Paste last during a long one mixes their chunks.
3. **What audio each decode gets.** Seven modules each set part of it (capture's trim, the pre-roll, the segmenter's cuts, the stream's overlap and gates, the joiner's second decode, the session's choice of path, the manager's padding). Audio reaches the engine seven ways, the one-piece decode is written three times, and no session test sees the clip an engine gets.

What holds, and stays: one import per engine; every decode through `TranscriptionManager.transcribe`; one `CGEvent.post` site (AGENTS.md rule 3); a pure segmenter and joiner; no model switch mid-dictation, so one dictation's joins never mix engines.

## Decisions (maintainer, 2026-11-23)

1. **An empty result is quiet for every engine.** Either engine returning no words means nothing was said: no error, and live streaming continues. **Why:** this replaces Whisper's loud `.emptyTranscription`. An engine returns nothing when its own gates find no speech in the audio (0023 pins Whisper's), and `FluidAudioModel` already treated that as nothing said. A "no speech heard" notice can come with 0023's planned feedback surface.
2. **No fixes to a model's text for now; a general-purpose linting layer later.** River types each model's text as the model writes it, apart from the joiner's rules where streamed segments meet (0025), which set the spacing and the punctuation at each join. A later phase adds one linting layer for every model's transcript: simple rules, or a fast classifier that judges the transcript, applies the fixes it is sure of, and judges again. Where it runs, on each decode or on the final transcript, is decided with it; on the final transcript, the joiner and the live text still see the raw text. **Why:** this replaces per-model rules keyed by the catalogue, decided earlier the same day: a model's update can fix its own quirks, and quirks such as glued digits are easy to find without knowing which model wrote them.
3. **A long one-piece clip is split by its engine.** River writes each engine's window down behind the seam (Whisper 30 s, FluidAudio 15 s) and tests long clips in the replay harness; River adds no cap. **Why:** the trade is consistency, not speed (maintainer, 2026-11-25, rewording a first Why that rested on speed). A cap would not make a dictation that waited any faster, since the same audio is decoded either way; but a one-piece clip is then split at the engine's window and joined by the engine, not cut at the speaker's pauses and joined by River's joiner, which has not been judged on FluidAudio text. D's `long-03`, about 3 minutes replayed with streaming off on every model, checks that split.
4. **The maintainer records the replay corpus,** about 16 clips (D).

## Design

### A. One meaning of a transcript

- `TranscriptionManager.transcribe` returns text or nothing said, and throws only for a real failure (`.transcriptionFailed`, `.modelNotLoaded`). `.emptyTranscription` and `.noSpeechDetected` go.
- **Each adapter says nothing said its engine's way:** Whisper's empty output, or output made only of annotations (0023's whole-output rule; annotations inside speech stay), and FluidAudio's empty output. No adapter changes a word.
- **What each engine needs from its audio** moves behind the seam too: the short-clip padding (Whisper's context, which also meets FluidAudio's 0.3 s minimum), and each engine's window, written down in its adapter.
- **Callers.** The stream's segments and tail, the one-piece decode and kept recordings stop catching engine errors, and read nothing said the same way.
- Unchanged: each engine imported only by its adapter ([0037](0037_fluidaudio-engine.md)); the Whisper adapter's retry without the custom-dictionary prompt.
- **Tests.** Each adapter's nothing said is tested on raw text, with no model loaded. `FakeModel` returns given text, or nothing said, and replaces `transcribeResultForTesting` (the PR #97 review's "Retire the last two test flags"); [ADR 0001](../decisions/0001-defer-cycle-protocol-seams.md) gets a 2026-11-23 note after its 2026-11-19 one.

### B. One delivery module

- `TextInsertionManager.deliver(_:to:while:)` takes the text and the app it was meant for, and reports typed or held; a field that isn't editable and a lost grant still throw. It owns the turn, the hold check, the insertion guard, the chunk plan, the pacing and the newline rule. The session keeps the last transcript ([0019](0019_last-transcript-recovery.md)), the state, Paste last's guard, and Copy Last Transcription. **Why Copy stays out** (maintainer, 2026-11-23, replacing this plan's first draft): [0011](0011_keystroke-injection.md) requires no pasteboard APIs in `TextInsertionManager`, so typing can never touch the clipboard by structure, and 0019 keeps the copy a user command outside the typing path.
- **One insert at a time.** A second insert waits for the first, so Paste last pressed twice types the text twice, in order.
- **The app in front is read again before each chunk.** If it changed, typing stops and the text is held, as when it changes before typing starts. The first read comes before the insertion guard, so a switch to an app with no text field holds the text rather than reporting no field. A Paste last stopped this way shows nothing: at `.idle` the panel draws a status only during a dictation.
- **A newline is typed as a space.** **Why:** Return sends a message in most chat apps, and River's own joins already avoid newlines.
- **The last two chunks share the remainder,** so a plan of several chunks ends on one character only near a long grapheme, such as a family emoji, which English text doesn't hold ([0031](0031_terminal-insert-fidelity.md)). Checked on device in Claude Code at 21, 41 and 61 characters, the 20n+1 lengths where the bug appeared (2026-11-24); a transcript of 20n+2 never ended on one character, before or after.
- Unchanged: the one post in `AccessibilityCapability`; Paste last's wait for the shortcut's keys in `HotkeyManager`; keystrokes, never the clipboard, for typing ([0011](0011_keystroke-injection.md)).
- **Tests.** Chunk plans for every length; queue order with the injected pause; each outcome, with no polling; a change of app mid-insert.
- *Since `fix/pipeline-review` (2026-11-25 to 2026-11-27):* `deliver` takes its caller's condition as `while:`, read when the turn comes and before each chunk, and a condition that fails holds the text like a change of app. Paste last passes "no Hold dictation is recording" ([0036](0036_settings-and-shortcuts.md)). The turn is a `Turn`, which `TranscriptionManager` also takes for each decode, so decodes run one at a time, in order.

### C. One module decides what audio each decode gets

- `DictationStream` turns a recording into text on every path: the segments cut while the user speaks, the tail at release, the live text, and every one-piece case (no cut, a failed segment, a kept recording, streaming off); a capture failure finishes the same way, with the audio that did arrive. The session hands it the recording and gets text back; a kept recording becomes a request to the same module (`DictationStream.transcribe(_:decode:)`).
- It takes the silence trim from `AudioCaptureManager` and runs it on each clip right before its decode. The recording is converted to 16 kHz once, live, where there were two conversions: `AudioCaptureManager` resamples each buffer as it arrives, finishes each format run's resampler at its end so no sample is held back, and keeps no copy. The one-piece decode is written once. **Why the conversion stays in capture** (built 2026-11-23, in place of the stream converting): `AudioCaptureManager` owns the device formats and their runs ([0032](0032_first-recording-device-switch.md)), and the stream's input stays plain 16 kHz samples, which D's replay feeds from files.
- **The wait for the model moves to the decode.** The stream asks the session to wait (`finish(whenReady:)`) just before a one-piece decode, and only for a clip that holds speech after the trim, so a stray tap never waits; the clip it hands over is what a failed load keeps. The tail needs no wait: a segment decoded before it.
- The hidden `streamingDictation` switch stays, as one path inside the module.
- **What a user can see change.** With streaming off, a recording cut short now types what was heard, as it does with streaming on; before, it typed nothing. With no cut, the live text ends on the typed text rather than on the last provisional decode. A one-piece transcript is joined like a streamed one, so the spacing between its words is one space, and output with no words, only punctuation such as "(", types nothing, as a streamed segment's already did (0023 recorded a stray "(" typed from a near-silent clip).
- Unchanged: the cut, overlap and join rules (0025, [0034](0034_live-text-and-microphone-settings.md)); the wait for the model ([0004](0004_model-loading-indicator.md)).
- **Tests.** A fake decoder records every clip the stream hands the engine, on every path, and a fake wait records what a failed load keeps; `FakeModel` records the clips session tests reach. Session tests keep held loads only where the wait for the model is what they test.

### D. Replay harness

- `TranscriptionEvalTests` becomes one on-device replay: each clip goes through C's module, with streaming on and off, and through each real model behind A. It scores word errors as today (`WordErrorRate`) and, apart, reports each model's text shape against the reference as written (digits, punctuation, capitals), so a model's update or the later linting layer is judged against it. It is rerun after any engine or model upgrade, the check 0037 asks for after a FluidAudio upgrade.
- Gated by `RIVER_EVAL_CORPUS` and `RIVER_EVAL_MODEL` as today; it loads real models, so it runs on its own, never beside a build.
- **A silence clip reports what each model typed; it doesn't fail the run** (maintainer, 2026-11-25). The report sits beside each empty clip's reason (`DictationStream.Outcome.emptyReason`), and [test-harnesses.md](../conventions/test-harnesses.md) changes with D's code. **Why:** this replaces the rule that a silence clip producing text fails the run. Silent taps typing a word with Phonon-2 are the model's behavior, left for the later linting layer (Findings explored), so a failed run would only repeat that; the report shows how far a key click is from a short word (`breath-01`, `short-01`).
- **The corpus** (`~/river-eval-corpus`, format in [test-harnesses.md](../conventions/test-harnesses.md)) is recorded through River. A debug-only switch, compiled out of release builds, saves each recording to the corpus folder while the maintainer dictates each script as written, noting any change in its reference (maintainer, 2026-11-25). **Why:** this replaces recording in QuickTime Player, planned 2026-11-23: only River's recordings carry its pre-roll and the key's clicks, which the silent-tap question turns on, and the app otherwise saves no audio ([0033](0033_warm-microphone-pre-roll.md)).
  1. `numbers-01`: "Dictating for 30 seconds, then about 10 to 15 seconds more."
  2. `numbers-02`: "The call moved from 3:45 to 4:15 on November 23, 2026."
  3. `numbers-03`: "It costs $20, about 15 percent of the 140 we budgeted."
  4. `long-01`: a paragraph of 40 s or more, read without pausing.
  5. `long-02`: a paragraph of 45 s or more, with pauses of 1 to 2 s between sentences.
  6. `pauses-01`: "The best option is… to move the launch… to next week because… the build isn't ready."
  7. `short-01`: "Yes."
  8. `short-02`: "Send it."
  9. `questions-01`: "Can you check the logs? Then fix the test, update the docs, and push."
  10. `names-01`: "Open River's settings, pick Phonon-2, and check GitHub for the FluidAudio release."
  11. `contractions-01`: "We'll see. It's fine, they're done, and I don't mind."
  12. `commands-01`: "Run git status, then cd into the worktree and run swift test."
  13. `mixed-01`: a sentence with a laugh or a cough in the middle.
  14. `silence-01`: 5 s of room tone (`silence-heavy`, empty reference).
  15. `breath-01`: breathing and a key tap, no words (`silence-heavy`, empty reference).
  16. `long-03`: about 3 minutes of natural speech with pauses, replayed with streaming off on every model, so each engine splits it in one piece (decision 3).

## Findings explored

- **The joiner and FluidAudio text.** The joiner matches words with case and punctuation removed, but a number must be written the same way in both decodes: "for30" against "for 30" or "for thirty" fails. A failed match decodes the segment again on its own and joins it by rule: no word is lost or doubled, but it costs an extra decode and gives a rougher join. Phonon-2's glued digits fail it too, until a model update or the later linting layer fixes them, and so does a number written as digits in one decode and as words in the other. River's history can't show how often, since macOS does not keep info-level log lines; D measures it.
- **No cap on one decode.** Decision 3.
- **Silent taps type words with Phonon-2** (maintainer's smoke, 2026-11-23). Three of nine taps with no speech typed "So, I think", "Okay." and "Yeah.". The key's clicks pass the silence trim, which keeps any sound above its gate ([0023](0023_silence-decoding-hardening.md)'s relative gate), and the pre-roll puts the press click 0.5 s in, at the trim's lead margin, so the whole tap reaches the engine. Two of the three reached Phonon-2 whole and unpadded, through a conversion bit-identical to the one before C, so the words are the model's response to clicks and room tone. **Left for the later linting layer** (maintainer, 2026-11-23): what a model does by default is that layer's to handle, not a River gate's. Not checked: whether FluidAudio's encoder ladder, which River no longer loads, does the same. *2026-11-25:* the PR #100 review asked whether River should gate them, since the streamed tail needs 0.25 s of speech (`streamingTailMinVoicedSeconds`) and a one-piece clip only one window above the trim's gate. That minimum applies only once words are typed, to room tone after the last phrase (`DictationStream.decodeTail`), so applying it to a whole dictation would be a new rule and could drop a real one-word reply. The decision stands, and D reports what each model types for silence (maintainer, 2026-11-25).

## Order

1. **A first.** B and C read its one result.
2. **B.** Small, and it fixes the two faults a user can meet today: chunks mixing and the moved last character.
3. **C.** The largest, and simpler once nothing said means one thing.
4. **D.** Once C is in, so it replays the module the app runs; the corpus can be recorded any time before.

A, B and C ship as one PR, `refactor/pipeline-owners`, with a commit series per part, each part planned and approved before its code; D is its own PR once the corpus is recorded (maintainer, 2026-11-23). Each commit builds and passes on its own and updates the docs it changes (`river-pipeline.md`, `river-session.md`, `test-seams.md`, `test-harnesses.md`). They follow PR 11 ([#99](https://github.com/abgregs/river/pull/99), merged 2026-11-23) directly and come before PR 12's onboarding step (maintainer, 2026-11-23). No release is planned around them: work continues until the maintainer decides to release.

## Acceptance criteria

1. **A.** An empty result from either engine types nothing, shows no error, and keeps live streaming. No caller catches an engine's own error, and session tests reach typed text through `FakeModel`, with `transcribeResultForTesting` gone.
2. **B.** Paste last pressed twice types the text twice, in order (tested). The last two chunks share the remainder (tested), and on device transcripts of 20n+1 characters, such as 421, type in order in Claude Code (21, 41 and 61 checked, 2026-11-24). A change of app mid-insert stops typing and holds the text.
3. **C.** Tests see every clip an engine gets, on every path; the one-piece decode exists once; the conversion runs once per recording, and the trim in one place, the module, before each decode.
4. **D.** The replay runs a model over the corpus with streaming on and off and writes word errors, text-shape results, and what each model typed for a silence clip, with the reason each empty clip came back empty; a clip over 30 s, `long-03` included, types in full on every model.

## Not in this plan

- Fixing a model's text, such as Phonon-2's glued digits: the later linting layer (decision 2).
- Stripping annotations inside speech: 0023 keeps them.
- Pasting long transcripts, about 1,000 characters and up: 0031's agreed direction. Its pasteboard write would need its own home, outside `TextInsertionManager`, as Copy has.
- A "no speech heard" notice: 0023's feedback surface.
- Rules per app beyond the one-character rule: [0031](0031_terminal-insert-fidelity.md) turned down a strategy per terminal.

## Related

- [../architecture/river-pipeline.md](../architecture/river-pipeline.md), [../architecture/river-session.md](../architecture/river-session.md), [../architecture/capabilities.md](../architecture/capabilities.md) — the pipeline, the session and the capabilities these PRs change
- [ADR 0001](../decisions/0001-defer-cycle-protocol-seams.md) — the model-loading seam A deepens
- [0022](0022_transcription-eval-harness.md) — the eval harness D extends; [0023](0023_silence-decoding-hardening.md) — the silence rules A keeps
