# Planning: Where Models Are Saved, and Deleting Them (0038)

**Status: draft for the maintainer's sign-off, planned for `v0.3.0` as PR 7b, `feat/model-storage`, not started.** Raised by the maintainer in the PR 7 smoke test (2026-11-11). It comes after PR 7 ([#92](https://github.com/abgregs/river/pull/92)) and before PR 7a ([0037](0037_fluidaudio-engine.md)), which adds its models to what this PR shows ([current-focus.md](current-focus.md)).

## Why

A model is a 140 MB to 1.6 GB download, and River keeps every model the user has tried: [0021](0021_model-picker.md) chose that for a quick switch back, assuming 240 to 630 MB each (Open items in [_index.md](_index.md), "Model cleanup"). On the maintainer's Mac four models take 3.6 GB. River never says where they are, so someone trying several dictation apps has to search for the files, and deleting River.app leaves them behind.

## Design

- **Where models are saved.** The Model section's note line under the table names the folder, `~/Library/Application Support/River/models`, and the space every model in it takes, with **Show in Finder**, which opens the folder in Finder. The total is measured on disk, not added up from the catalogue's download sizes.
- **Delete…** removes a downloaded model, after a confirmation that names the space it frees: "Delete Whisper Large v3 Turbo?", "This frees 1.5 GB. You can download it again later.", with **Delete model** and **Cancel**.
- **Never the model in use, or one loading beside it.** Delete is not offered for the model in use, nor for a model downloading, preparing or Waiting ([0036](0036_settings-and-shortcuts.md), Model). `TranscriptionManager`, which owns the model files, refuses those too, so a delete can never race a load of the same model.
- **Only the model's own folder.** The tokenizer folders under `models/openai` are a few MB and shared between models, so they stay.
- **After a delete** the row returns to Select without "Downloaded", and the total drops. Choosing the model again downloads it.
- **Not automatic.** Switching keeps the previous model: switching back would download up to 1.6 GB again, and trying a model and returning is what the Model section is for. An opt-in setting can come later if users ask.
- **Testable without real models.** The delete takes the models folder as a parameter, so tests delete from a temporary folder and never touch the user's models.

## Open questions for the maintainer

1. **Where Delete… sits in the row.** The status column (132 pt) already holds "Downloaded" and Select. Candidates: the row's context menu, a trailing ⋯ menu, or Delete… replacing "Downloaded" on hover. A short design round decides.
2. **The "Downloaded" check.** `isModelCached` trusts one file, so a partial download reads as downloaded ([0026](0026_model-switch-availability.md)). Recommended: adopt 0026's full file-set check here, since the total and the Delete offer both rely on it.
3. **WhisperKit's download records.** Each download leaves entries under `models/argmaxinc/whisperkit-coreml/.cache`. Check during the build whether a delete must remove a model's entries, so a later download doesn't skip files it thinks it has.

## Not in this PR

FluidAudio's models: [0037](0037_fluidaudio-engine.md) decides where they live, and adds them to the folder line and Delete. Deleting models from onboarding (PR 12). Removing a model automatically on switch.

## Acceptance criteria

1. The Model section names the models folder and the space its models take; Show in Finder opens it.
2. Every downloaded model except the one in use and one downloading, preparing or Waiting offers Delete…; the confirmation names the space it frees.
3. After a delete the model's folder is gone, the row shows Select without "Downloaded", the total drops, and the model in use keeps working.
4. A deleted model can be chosen again, and downloads.
5. `TranscriptionManager` refuses to delete the model in use or one loading beside it (tested against a temporary folder).
6. The tokenizer folders remain after any delete.

## Related

- [0021](0021_model-picker.md): why switched-away models are kept.
- [0026](0026_model-switch-availability.md): the full file-set check for a downloaded model.
- [0010](0010_relocate-model-cache.md): why models live under Application Support.
- [0036](0036_settings-and-shortcuts.md): the Model section.
- [0037](0037_fluidaudio-engine.md): the second engine and its models' folder.
