# Conventions: Test harnesses and generated assets

Suites that do more than assert. Two render the art River ships; two measure a real model
against real audio and are env-gated so the normal `swift test` never touches them. The
general test conventions are in [tests.md](tests.md).

## Generated assets are rendered by tests (0028)

River's menu bar glyphs and app icon are drawn from geometry in `Constants` — the slat rows, strokes, dot counts, the icon's squircle grid — by `MenuBarGlyphTests` and `AppIconTests`, in two halves:

- **The writer** is env-gated (`RIVER_WRITE_GLYPHS=1` / `RIVER_WRITE_ICON=1`), exactly the `DictionaryEvalTests` shape: the normal suite writes nothing.
- **The checks always run.** They re-render from `Constants` and compare against the checked-in files (alpha within a tolerance that absorbs antialiasing differences between macOS versions, not a moved slat), and assert the pixel-snapping and centering rules that make the mark crisp.

**Why:** SwiftPM has no asset pipeline for a hand-rolled `.app` (`Bundle.module` resolves to the bundle root, which breaks signing), so the assets are checked-in files copied by `make bundle`. Without the always-on check, editing the geometry would leave the shipped art silently stale — the asset and the number that produced it would drift apart with nothing to catch it. There is no runtime detector for a wrong or missing asset either, so `make verify` asserts they reach the bundle ([../architecture/distribution.md](../architecture/distribution.md)).

The same file also holds the indicator's **snapshot harness** (`RiverIndicatorSnapshotTests`, env-gated by `RIVER_SNAPSHOT_DIR`): it renders the capsule at held levels through `RiverMarkRenderer`, for side-by-side review against the study page and for PR screenshots.

## Transcription eval harness (0022)

`TranscriptionEvalTests` measures a WhisperKit model against a fixed local corpus of dictation clips and writes a per-model scorecard (WER per clip + aggregate, per-clip latency, model load time, on-disk model size). It is the instrument behind the [0021 model-picker](../planning/0021_model-picker.md) decisions — the curated list and default are chosen from *our* short-dictation workload, not published long-form benchmarks. Two layers:

- **`WordErrorRate`** (in `Sources`) is the pure, model-free scorer: the normalization rules (lowercase; drop every non-alphanumeric, non-whitespace character so `"don't"` stays one token; split on whitespace) live there and nowhere else, so scorecards are only ever comparable when scored by the same rules. Fully unit-tested (`WordErrorRateTests`) on synthetic string pairs — it runs in the default suite with no model and no corpus.
- **The harness test** is **env-gated** (`.enabled(if: RIVER_EVAL_CORPUS)`), exactly the `DictionaryEvalTests` shape. The normal `swift test` and CI never download a model and never touch the corpus.

**The corpus is never committed.** Voice recordings are personal data and the repo is public — the same posture that keeps user content out of logs (anti-pattern #4). Recording the corpus is the maintainer's job and out of scope for the harness; the harness fails with an actionable message when the env var is set but the directory or manifest is missing or malformed.

### Corpus directory format

A local directory **outside the repo** (and outside `~/Desktop`|`Documents`|`Downloads`, which TCC blocks — e.g. `~/river-eval-corpus/`) containing the WAV clips and a `manifest.json`:

```json
{
  "clips": [
    { "file": "cmd-01.wav",     "reference": "open the settings panel",        "tags": ["commands"] },
    { "file": "longform-01.wav", "reference": "the full hand-verified transcript…", "tags": ["long-form"] },
    { "file": "silence-01.wav",  "reference": "",                                "tags": ["silence-heavy"] }
  ]
}
```

- `file` — clip filename, relative to the corpus directory.
- `reference` — the hand-verified transcript. Normalization is applied at score time, so casing and punctuation here don't matter.
- `tags` — any of `commands`, `long-form`, `silence-heavy`. **`silence-heavy` clips are scored pass/fail on emptiness, not WER** (an empty output is the correct answer, which WER can't express); give them an empty `reference`. They are [0023](../planning/0023_silence-decoding-hardening.md)'s regression fixtures — a silence clip that produces text fails the run.

The harness mirrors the production front-end: it trims silence ([0023](../planning/0023_silence-decoding-hardening.md)) before decode, so silence clips are judged on the audio the app actually sees.

### Running

```bash
RIVER_EVAL_CORPUS="$HOME/river-eval-corpus" swift test --filter TranscriptionEval
open -e eval-openai_whisper-small.en.txt    # the scorecard, written to the package root
```

- `RIVER_EVAL_MODEL` — WhisperKit model name (default: `Constants.defaultModel`, i.e. `small.en`). Run once per candidate model; the fixed corpus makes scorecards directly comparable.
- `RIVER_EVAL_OUT` — override the scorecard path (default: `./eval-<model>.txt`).

## Related

- [tests.md](tests.md) — the general test conventions and the access seams these harnesses use
- [../architecture/distribution.md](../architecture/distribution.md) — the bundle assertions that back the generated assets
- [../planning/0028_identity-implementation.md](../planning/0028_identity-implementation.md) — the identity build the asset renderers came from
- [../planning/0022_transcription-eval-harness.md](../planning/0022_transcription-eval-harness.md) — the eval harness spec
