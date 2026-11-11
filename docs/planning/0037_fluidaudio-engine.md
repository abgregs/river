# Planning: A Second Speech Engine (FluidAudio)

**Status: planned for `v0.3.0` as PR 7a, `feat/fluidaudio-engine`, not started.** Agreed with the maintainer on 2026-11-10, after a spike the same day. It adds the two new models in [0036](0036_settings-and-shortcuts.md)'s Model section, NVIDIA Parakeet TDT v2 and Fermion Research's Phonon-2, which WhisperKit cannot run. It is built alongside PRs 8 to 10 and lands before PR 11 (the preparing look) and PR 12 (the onboarding model step) ([current-focus.md](current-focus.md)).

## What the spike showed

FluidAudio 0.18.3 (FluidInference, Apache-2.0, a Swift package) on macOS 15.6, Apple Silicon, 2026-11-10:

- **It builds with only the Command Line Tools** (Swift 6.1.2), and River with it passes `make verify`, signed with the hardened runtime. Its prebuilt text-processing library is static, so nothing new is embedded or signed.
- **Parakeet TDT v2 inside the signed River.app:** a 12 s clip typed exactly in 99 ms. The first load in the app took 19 s with the model already downloaded: Core ML preparing it for this Mac, once per model per app. In a test program a prepared model loaded in under 0.4 s.
- **Phonon-2, in a test program:** exact text with punctuation in about 100 ms for 11.6 s of audio. 374 MB on disk; the first download and load took 3 min 53 s, nearly all of it the download.
- **Live text:** re-reading the growing recording from the start, as River's live view does, took 54 ms at 1 s of audio and 123 ms at 29 s with Parakeet, and 30 to 95 ms over 11 s with Phonon-2.
- **Size:** River's release binary grew from about 3 MB to 17 MB, mostly the text-processing library. A clean release build took about 3 minutes.

Not yet measured: accuracy on the maintainer's own voice (the spike used synthesised speech), and Phonon-2 inside the app.

## Design

- **One import boundary per engine.** Today only `TranscriptionManager` imports WhisperKit. A new file is the only one that imports FluidAudio. `TranscriptionManager` picks the engine from the model's catalogue entry, and `RiverSession` keeps calling `transcribe(audioSamples:)`, so the dictation cycle and the live text's `DictationStream` don't change.
- **One loader per engine, beneath the switching logic.** PR 7's switching (a model loading beside the one in use, taking over at `.idle`, the `ModelSelection` it publishes) does not depend on the engine, but its code is mixed with WhisperKit's: creating the model, its folder, and the downloaded check. This PR moves those three behind one loader per engine, so the switching logic is written and tested once, and tests use a fake loader in place of `skipLoadForTesting` and `stageFailsForTesting`. This is the revisit [ADR 0001](../decisions/0001-defer-cycle-protocol-seams.md) names for a second transcription backend (architecture review of PR #92, 2026-11-11).
- **Pinned exactly**, as WhisperKit is: FluidAudio is pre-1.0, and a minor version may change its API. Raise it on purpose, after testing.
- **The catalogue entry** carries each model's engine, minimum macOS and credit. PR 7 adds the fields with the Whisper models; this PR adds the two rows.
- **The same load states.** Downloading, then Preparing, then Ready, as for Whisper. The 19 s first preparation shows as Preparing.
- **Phonon-2 needs macOS 15.** On macOS 14 its row says so and cannot be selected. River still supports macOS 14.
- **The custom dictionary is Whisper's.** Prompt biasing and the retry without the prompt (`resolveWithEmptyPromptRetry`) are Whisper features. The FluidAudio path takes no dictionary terms; nothing in `v0.3.0` lets the user set any ([0036](0036_settings-and-shortcuts.md), "Not in `v0.3.0`").
- **Where models live: open.** By default FluidAudio keeps its models in its own folder under Application Support, which raises no permission prompt (the concern in [0010](0010_relocate-model-cache.md)). [0038](0038_model-storage.md) shows River's models folder and deletes models from it, so this PR either points FluidAudio's downloads into `River/models` or makes 0038's folder line and Delete cover both folders. Check whether FluidAudio's download location can be set before choosing. The downloaded check is per engine either way.

## Licences

- **Credits.** PR 7's About window and notices file ([0036](0036_settings-and-shortcuts.md), "The panel ends with the version line") gain FluidAudio (Apache-2.0) and the text-processing library it links into River, `text-processing-rs` (Apache-2.0), with the Apache and MIT libraries built into it, as listed in FluidAudio's `ThirdPartyLicenses`.
- **The models are CC-BY-4.0.** The credit names the creator (NVIDIA; Fermion Research), links the licence, and says the model was converted to Core ML.
- **No text-to-speech data ships.** FluidAudio carries pronunciation data for its text-to-speech, derived from GPL-3.0-or-later and CC-BY-SA-4.0 sources, and its notes say apps that don't use text-to-speech can leave it out. River's `make bundle` copies only the files it names, so the data stays out; `make verify` fails if it is ever in the bundle. FluidAudio's Swift 6.2 manifest can drop the text-processing library too, but the Command Line Tools' Swift 6.1 reads the other manifest, which always links it.

## Not in this PR

Parakeet TDT v3, Phonon-2.5 and Phonon-2.5 English (0036); languages. Deleting downloaded models is [0038](0038_model-storage.md), which lands first; this PR adds its two models to 0038's folder line and Delete.

## Acceptance criteria

1. Selecting Parakeet TDT v2 downloads it, prepares it and switches to it once it is ready, while the current model keeps working until then; dictation then types its text.
2. The same holds for Phonon-2 on macOS 15. On macOS 14 its row says it needs macOS 15 and cannot be selected.
3. The live text shows and updates with each new model.
4. The Whisper models behave as before, the dictionary prompt included, and every existing test passes.
5. `make verify` passes, and fails without the notices file or with FluidAudio's text-to-speech data in the bundle.
6. The About window credits both models (creator, licence link, conversion note), FluidAudio and the text-processing library.
7. River still builds with only the Command Line Tools, apart from the Glass shader, which already needs Xcode's `metal`.
8. On device, the maintainer dictates everyday sentences with each new model and judges the text.
9. Model switching is tested once, through a fake loader; only each engine's loader imports its engine.
10. The two new models count in 0038's folder total and can be deleted like the Whisper models.

## Related

- [0036](0036_settings-and-shortcuts.md): the Model section and its catalogue.
- [0026](0026_model-switch-availability.md): per-model download state, which switching when ready needs.
- [0010](0010_relocate-model-cache.md): why models stay out of Documents.
- [0038](0038_model-storage.md): where models are saved, and deleting them.
- [ADR 0001](../decisions/0001-defer-cycle-protocol-seams.md): the deferred protocol seams this PR revisits for model loading.
