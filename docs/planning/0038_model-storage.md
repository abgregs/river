# Planning: Where Models Are Saved, and Deleting Them (0038)

**Status: signed off by the maintainer (2026-11-11) and built in PR 7b, `feat/model-storage`; merged as [#94](https://github.com/abgregs/river/pull/94) (2026-11-15).** Raised by the maintainer in the PR 7 smoke test (2026-11-11). It comes after PR 7 ([#92](https://github.com/abgregs/river/pull/92)) and before PR 7a ([0037](0037_fluidaudio-engine.md)), which adds its models to what this PR shows ([current-focus.md](current-focus.md)).

## Why

A model is a 140 MB to 1.6 GB download, and River keeps every model the user has tried: [0021](0021_model-picker.md) chose that for a quick switch back, assuming 240 to 630 MB each (Open items in [_index.md](_index.md), "Model cleanup"). On the maintainer's Mac four models take 3.6 GB. River never says where they are, so someone trying several dictation apps has to search for the files, and deleting River.app leaves them behind.

## Design

- **Where models are saved.** Under the table's note, a second line names the folder and the space every file in it takes: "Models are saved in ~/Library/Application Support/River/models and take 3.8 GB.", with **Show in Finder**, which opens the folder in Finder. The total is measured on disk (the blocks allocated to each file), not added up from the catalogue's download sizes, and reads in decimal units as Finder shows it. It counts the whole folder, tokenizers and download records included, since that is what the folder costs.
- **Delete…** removes a downloaded model, after a confirmation that names the space it frees, measured the same way: "Delete Whisper Large v3 Turbo?", "This frees 1.6 GB. You can download it again later.", with **Delete model** and **Cancel**. The confirmation shows the trash symbol in place of River's icon, and Return does not delete. **Why:** above a delete, River's icon read as deleting River (maintainer, 2026-11-19).
- **Never the model in use, or one loading beside it.** Delete is not offered for the model in use, nor for a model downloading, preparing or Waiting ([0036](0036_settings-and-shortcuts.md), Model). `TranscriptionManager`, which owns the model files, refuses those too, so a delete can never race a load of the same model.
- **A refused or failed delete says so.** If the model became busy after the menu opened, or the files can't be removed, an alert reads "Couldn’t delete *model*" with the reason, and the row stays as it was.
- **Only the model's own folder, and its download records** (decision 3). The tokenizer folders under `models/openai` are a few MB and shared between models, so they stay.
- **After a delete** the row returns to Select without "Downloaded", and the total drops. Choosing the model again downloads it.
- **Not automatic.** Switching keeps the previous model: switching back would download up to 1.6 GB again, and trying a model and returning is what the Model section is for. An opt-in setting can come later if users ask.
- **Testable without real models.** `TranscriptionManager` reads the models folder from the `ModelStore` it is given, so tests pass a store with a temporary folder and never touch the user's models. **Why:** the folder was first a parameter of the delete alone, while the Model section read the real folder on its own (2026-11-20, [#98](https://github.com/abgregs/river/pull/98)).

## Decisions (maintainer, 2026-11-11)

1. **Where Delete… sits: a trailing ⋯ menu on the row.** It appears while the pointer is over the row, or while the keyboard is on the row's Select or ⋯ (Full Keyboard Access), and VoiceOver always finds it ("Actions for *model*"). It opens a menu with **Show in Finder**, which reveals that model's folder, and, under a divider, **Delete…**; right-clicking the row opens the same menu. The status column keeps its layout ("Downloaded" and Select): the ⋯ takes its own 16 pt column 4 pt after it, and the name column narrows from 136 to 116 pt so the descriptions keep their width (the longest name still wraps in two lines). Build choices: the ⋯ is there only for a downloaded model, since both items need its folder; Delete… is in the menu only where it can be taken (a downloaded model River is neither using nor loading: not in use, downloading, preparing, Waiting, or failed), absent rather than dimmed, as context menus leave out what can't be done.
2. **"Downloaded" is the full file-set check** from [0026](0026_model-switch-availability.md) (finding 3), built here, replacing `isModelCached`'s one-file trust. A model reads as downloaded when its folder holds `config.json`, `generation_config.json`, and, for each of `MelSpectrogram`, `AudioEncoder` and `TextDecoder`, a `.mlmodelc` with `coremldata.bin`, `metadata.json`, `model.mil`, `weights/weight.bin` and `analytics/coremldata.bin`; when a `TextDecoderContextPrefill.mlmodelc` folder is there (Large v3 Turbo), it must be complete too, since WhisperKit loads it whenever its folder exists. The set is what `argmaxinc/whisperkit-coreml` ships for every catalogue model (checked against the four on the maintainer's Mac). Presence is enough: swift-transformers' `Downloader` writes each file under `.cache/…/<file>.<etag>.incomplete` and moves it into the model folder only once it is whole, so a cut-off download is missing files, never holding a short one. `.mlpackage` folders, which the old check accepted, are no longer read as downloaded: no catalogue model ships one.
3. **WhisperKit's download records: a stale record does not make a later download skip files, and Delete removes the model's records anyway.** Found in swift-transformers 1.1.9 (`Sources/Hub/HubApi.swift`, `HubFileDownloader.download`), the version WhisperKit 0.18.0 resolves to: a file is skipped only when it exists in the model folder *and* its `.metadata` record exists *and* the record's commit hash matches the remote one (`downloaded && localMetadata != nil && localCommitHash == remoteCommitHash`), where `downloaded` is `FileManager.fileExists` on the file itself. With the model folder gone, every file downloads again and its record is rewritten. The offline branch of `snapshot` walks the files that exist and looks up each one's record, so a record without a file is never read. Delete still removes `models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/<model>`: the records are the model's own, and the same folder holds any `.incomplete` part of a cut-off download, which the `Downloader` resumes with a `Range` request and which can be large. On the maintainer's Mac the records for four models take 324 KB.

## Not in this PR

FluidAudio's models: [0037](0037_fluidaudio-engine.md) decides where they live, and adds them to the folder line and Delete. Deleting models from onboarding (PR 12). Removing a model automatically on switch.

## Acceptance criteria

1. The Model section names the models folder and the space its models take; Show in Finder opens it.
2. Every downloaded model except the one in use and one downloading, preparing or Waiting offers Delete…; the confirmation names the space it frees.
3. After a delete the model's folder is gone, the row shows Select without "Downloaded", the total drops, and the model in use keeps working.
4. A deleted model can be chosen again, and downloads.
5. `TranscriptionManager` refuses to delete the model in use or one loading beside it (tested against a temporary folder). It also refuses a model a superseded load is still reading, since cancelling a load does not stop a Core ML load already under way, and any name the catalogue doesn't list.
6. The tokenizer folders remain after any delete.

## Related

- [0021](0021_model-picker.md): why switched-away models are kept.
- [0026](0026_model-switch-availability.md): the full file-set check for a downloaded model.
- [0010](0010_relocate-model-cache.md): why models live under Application Support.
- [0036](0036_settings-and-shortcuts.md): the Model section.
- [0037](0037_fluidaudio-engine.md): the second engine and its models' folder.
