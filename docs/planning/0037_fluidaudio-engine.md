# Planning: A Second Speech Engine (FluidAudio)

**Status: built for `v0.3.0` as PR 7a, `feat/fluidaudio-engine` (2026-11-19), and smoke-tested on device by the maintainer the same day; merged as [#97](https://github.com/abgregs/river/pull/97) (2026-11-20).** Agreed with the maintainer on 2026-11-10, after a spike the same day. It adds the two new models in [0036](0036_settings-and-shortcuts.md)'s Model section, NVIDIA Parakeet TDT v2 and Fermion Research's Phonon-2, which WhisperKit cannot run. It is built alongside PRs 8 to 10 and lands before PR 11 (the preparing look) and PR 12 (the onboarding model step) ([current-focus.md](current-focus.md)).

## What the spike showed

FluidAudio 0.18.3 (FluidInference, Apache-2.0, a Swift package) on macOS 15.6, Apple Silicon, 2026-11-10:

- **It builds with only the Command Line Tools** (Swift 6.1.2), and River with it passes `make verify`, signed with the hardened runtime. Its prebuilt text-processing library is static, so nothing new is embedded or signed.
- **Parakeet TDT v2 inside the signed River.app:** a 12 s clip typed exactly in 99 ms. The first load in the app took 19 s with the model already downloaded: Core ML preparing it for this Mac, once per model per app. In a test program a prepared model loaded in under 0.4 s.
- **Phonon-2, in a test program:** exact text with punctuation in about 100 ms for 11.6 s of audio. 374 MB on disk; the first download and load took 3 min 53 s, most of it the first preparation's compiles (below), not the download as the spike first read it.
- **Live text:** re-reading the growing recording from the start, as River's live view does, took 54 ms at 1 s of audio and 123 ms at 29 s with Parakeet, and 30 to 95 ms over 11 s with Phonon-2.
- **Size:** River's release binary grew from about 3 MB to 17 MB, mostly the text-processing library. A clean release build took about 3 minutes.

Not measured in the spike: accuracy on the maintainer's own voice (the spike used synthesised speech), and Phonon-2 inside the app. Both were tried in the smoke test below.

## Design

- **One import boundary per engine.** Today only `TranscriptionManager` imports WhisperKit. A new file is the only one that imports FluidAudio. `TranscriptionManager` picks the engine from the model's catalogue entry, and `RiverSession` keeps calling `transcribe(audioSamples:)`, so the dictation cycle and the live text's `DictationStream` don't change.
- **One loader per engine, beneath the switching logic.** PR 7's switching (a model loading beside the one in use, taking over at `.idle`, the `ModelSelection` it publishes) does not depend on the engine, but its code is mixed with WhisperKit's: creating the model, its folder, and the downloaded check. This PR moves those three behind one loader per engine, so the switching logic is written and tested once, and tests use a fake loader in place of `skipLoadForTesting` and `stageFailsForTesting`. This is the revisit [ADR 0001](../decisions/0001-defer-cycle-protocol-seams.md) names for a second transcription backend (architecture review of PR #92, 2026-11-11).
- **Pinned exactly**, as WhisperKit is: FluidAudio is pre-1.0, and a minor version may change its API. Raise it on purpose, after testing.
- **The catalogue entry** carries each model's engine, minimum macOS and credit. PR 7 adds the fields with the Whisper models; this PR adds the two rows.
- **The same load states.** Downloading, then Preparing, then Ready, as for Whisper. The 19 s first preparation shows as Preparing.
- **Phonon-2 needs macOS 15.** On macOS 14 its row says so and cannot be selected. River still supports macOS 14.
- **The custom dictionary is Whisper's.** Prompt biasing and the retry without the prompt (`resolveWithEmptyPromptRetry`) are Whisper features. The FluidAudio path takes no dictionary terms; nothing in `v0.3.0` lets the user set any ([0036](0036_settings-and-shortcuts.md), "Not in `v0.3.0`").
- **Where models live: River's one models folder.** FluidAudio's download folder can be set (`AsrModels.download(to:)`), so its models go in `~/Library/Application Support/River/models/FluidInference/<folder>` (`parakeet-tdt-0.6b-v2`, `phonon-2`), beside the Whisper models, and [0038](0038_model-storage.md)'s folder total, Show in Finder and Delete cover them with no change. Like FluidAudio's own default, the folder is under Application Support, so it raises no permission prompt ([0010](0010_relocate-model-cache.md)). The downloaded check is per engine: FluidAudio's own load-ready check (`AsrModels.modelsExist`), which a cut-off download's `.partial` files fail.

## Built (2026-11-19)

- **The seam.** `ModelLoader` (`isDownloaded`, `folder(of:)`, `files(of:)`, `load`) has two adapters in `Managers/`: `WhisperKitLoader`, which took over WhisperKit's folder, file-set check, tokenizer check and load from `TranscriptionManager`, and `FluidAudioLoader`. `load` returns a `LoadedModel` that transcribes; Whisper's prompt, retry and annotation check moved with it into `WhisperKitModel`. `TranscriptionManager` no longer imports WhisperKit. Tests pass `FakeModelLoader`. Since 2026-11-20 `ModelStore` holds the loaders and the models folder: the manager and the Model section both go through it, and a test checks that every FluidAudio model in the catalogue is one `FluidAudioLoader` knows.
- **Names.** A FluidAudio model's catalogue name is its FluidAudio 0.18.3 repo name (`parakeet-tdt-0.6b-v2-coreml`, `phonon-2-coreml`), which `FluidAudioLoader` maps to FluidAudio's version and repo. FluidAudio keeps the version-to-repo link internal, so a version bump must check the pairs. The folder on disk is the repo's public `folderName`, which drops "-coreml": a folder guessed from the name left Show in Finder and Delete pointing at nothing (smoke test, 2026-11-19).
- **No words is no speech.** Parakeet and Phonon write nothing for audio with no words, where Whisper writes "[BLANK_AUDIO]"; each adapter returns nil for its engine's way of saying it, nothing said, quiet for every engine ([0023](0023_silence-decoding-hardening.md), [0039](0039_pipeline-rule-owners.md)).
- **Short clips.** FluidAudio refuses audio under 0.3 s. Each adapter pads a clip under 1.2 s with 0.5 s of silence on each side (`ShortClip.padded`), which lifts any clip past that.
- **A saved model this Mac can't run** (a name an older catalogue listed, or Phonon-2 on macOS 14) loads the default instead, which the session then saves once ready; `switchModel` ignores such a choice.
- **River loads one encoder window, so a first preparation is one Neural Engine compile** (measured on device 2026-11-21 and 2026-11-22, an 8 GB M3, macOS 15, FluidAudio 0.18.3).
  - **The cost.** Phonon-2's encoder holds three windows, 15, 10 and 5 s. With no compiled copy in Core ML's cache, each is a Neural Engine compile of 61 to 84 s, and each loaded window holds about 350 MB. FluidAudio's own `AsrModels.load` loads all three: 3 min 30 s from an empty cache, on `main` and on this branch alike, and 2.2 s once compiled.
  - **What River does.** It loads the 15 s window alone, through FluidAudio's public `AsrModels.loadLocal`: 75.5 s from an empty cache, 0.8 s once compiled, and about 675 MB less memory held. The two shorter windows would save a short dictation about 16 ms (an encoder pass takes 24 ms on the 15 s window, 7.8 ms on the 5 s one). Parakeet's encoder has one window (19 s from an empty cache). They also change how FluidAudio splits a clip over 15 s: with them it cuts each window at a pause, without them into overlapping windows whose words it merges. Streamed segments stay under about 12 s, so only a clip decoded in one piece (a dictation that waited for the model, a kept recording, streaming off) is split, and River adds no cap ([0039](0039_pipeline-rule-owners.md), decision 3); a 30 s Phonon-2 dictation typed in full on device (2026-11-23).
  - **When the cache is empty.** After a download, and after anything clears `~/Library/Caches/com.river.app`, where Core ML keeps the compiled copies: a cleaning tool did on 2026-11-22. A new build of River reuses them. FluidAudio's download ends by compiling each model once to check it, which shows as Preparing ([0004](0004_model-loading-indicator.md)), and the load that follows finds that copy.
  - **One compile at a time.** The Neural Engine compiles one program at a time, so another model's load waits behind a compile, and a load River no longer needs still finishes its compile.
  - **What `loadLocal` leaves out.** It reads the files as they are. If they won't load, River falls back to `AsrModels.load`, which downloads them again. It also skips FluidAudio's check of the files' revision, so a FluidAudio upgrade that changes a model's files needs that looked at.
  - **Why this changed.** On 2026-11-21 the three-window load was kept, on the belief that one window meant copying FluidAudio's private file names and vocabulary parsing. That was wrong: `loadLocal` is public. On 2026-11-22 an emptied cache blocked the maintainer's dictation for the full 3.5 minutes, twice.
- **The model in the log.** Each decode and each dictation's release-to-text line names the model, so models compare from the log ([../conventions/logging.md](../conventions/logging.md)).

## Smoke test (2026-11-19)

- **Passed on device:** each new model downloads, prepares and takes over (AC 1, AC 2 on macOS 15); a model chosen mid-dictation waits and takes over when the dictation ends. The maintainer dictated with both models through the session and found both quick; a judgement of their text (AC 8) is not yet recorded.
- **Fixed during it:** the Model section could stay on "*model* is ready. River switches to it after this dictation." after the switch. The session committed an idle switch inside the delivery of the "ready" value, so subscribers after it, the Settings view among them, received the stale value last. The commit now waits for the delivery to end (`RiverSession`), with a test. The bug dates from PR 7, which added Waiting.
- **Fixed during it:** Show in Finder and Delete pointed at a folder guessed from the catalogue name (see Names above).
- **Changed during it:** the delete confirmation shows the trash symbol in place of River's icon ([0038](0038_model-storage.md)), and the app icon's tile is `deepCharcoal`, so it stands out in a Dark mode alert ([../design/kawa-identity.md](../design/kawa-identity.md)).
- **Measured:** Phonon-2's release-to-text was 0.10 and 0.11 s in the app. Parakeet's is not yet compared: the log named the model only from this build.
- **Checked last, on the fixed build:** deleting Parakeet removed its folder (an earlier delete had run before the folder fix and removed nothing); the maintainer reported the remaining on-device checks done.

## Licences

- **Credits.** PR 7's About window and notices file ([0036](0036_settings-and-shortcuts.md), "The panel ends with the version line") gain FluidAudio (Apache-2.0) and the text-processing library it links into River, `text-processing-rs` (Apache-2.0), with the Apache and MIT libraries built into it, as listed in FluidAudio's `ThirdPartyLicenses`. The build adds one more: FluidAudio compiles fastcluster (BSD 2-Clause) into River, so its notice ships too.
- **The models are CC-BY-4.0.** The credit names the creator (NVIDIA; Fermion Research), links the licence, and says the model was converted to Core ML. Phonon-2 is Fermion Research's retraining of NVIDIA's Parakeet TDT 0.6B v3 (also CC-BY-4.0), so its credit names that model too (`ModelOption.basedOn`), and the notices file carries Fermion's change list and training-data attribution (CHiME-6, CC-BY-SA-4.0; SPGISpeech, Kensho's terms) from its NOTICE. FluidInference made both Core ML conversions (checked against the model cards and NOTICE files, 2026-11-19).
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
