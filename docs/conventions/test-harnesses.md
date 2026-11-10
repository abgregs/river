# Conventions: Test harnesses and generated assets

Suites that do more than assert. Two render the art River ships; two measure a real model
against real audio and one loads a real model offline; those three are env-gated so the normal `swift test` never touches them. The
general test conventions are in [tests.md](tests.md).

## Generated assets are rendered by tests (0028)

River's menu bar glyphs and app icon are re-rendered from the mark's data — 川's outlines and halfway centring point in `KawaMark` (generated from the study, [../design/kawa-identity.md](../design/kawa-identity.md)) — and the sizes in `Constants` — the glyphs' 18 pt box and the sign's place, the icon's squircle grid — by `MenuBarGlyphTests` and `AppIconTests`, in two halves:

- **The writer** is env-gated (`RIVER_WRITE_GLYPHS=1` / `RIVER_WRITE_ICON=1`), exactly the `DictionaryEvalTests` shape: the normal suite writes nothing.
- **The checks always run.** They re-render from the mark's data and `Constants` and compare against the checked-in files (alpha within a tolerance that absorbs antialiasing differences between macOS versions, not a moved stroke), and assert the placement rules: the icon's mark inside the squircle with margin on every side, and centred halfway between its box and its ink.

**Why:** SwiftPM has no asset pipeline for a hand-rolled `.app` (`Bundle.module` resolves to the bundle root, which breaks signing), so the assets are checked-in files copied by `make bundle`. Without the always-on check, editing the geometry would leave the shipped art silently stale — the asset and the number that produced it would drift apart with nothing to catch it. There is no runtime detector for a wrong or missing asset either, so `make verify` asserts they reach the bundle ([../architecture/distribution.md](../architecture/distribution.md)).

The same file also holds the indicator's **snapshot harness** (`RiverIndicatorSnapshotTests`, env-gated by `RIVER_SNAPSHOT_DIR`): it renders the mark's panel with Glass at held frames (the study page's filmstrip times, soft, normal and loud speech, a dead microphone, preparing, Reduce Motion), in light and dark, for side-by-side review against the study page at the same times and for PR screenshots. Each frame is fed the way the app feeds the panel, the microphone's peak reading every 0.07 s through `KawaIndicatorVoice` (seeded) at 60 fps, and drawn through `KawaMarkPanelFace`, the shipped panel. Glass needs its shader, so the harness compiles `KawaGlass.metallib` itself with the Makefile's two `xcrun` steps, into the snapshot directory; without Xcode's Metal compiler it skips Glass with a message. One test in it asserts rather than writes: `frostFormsInOneMove` measures the strokes' CIE L* distance from the ground frame by frame through the frost forming and lifting, and fails if it peaks on the way, the pulse seen on device on 2026-11-04. It also renders the whole floating stack from a real `AppState` (messages, the transcript, and the two together), handing in a mark cycle already under way, to check that the surfaces stack without overlap ([../decisions/0003-floating-ui-one-window-stack.md](../decisions/0003-floating-ui-one-window-stack.md)). The transcript's scroll view is an AppKit view, which `ImageRenderer` draws as a placeholder.

`SettingsWindowSnapshotTests`, under the same variable, renders the Settings window's content, each section and the Model section with a failed switch, in light and dark, through `NSHostingView` in an offscreen window, for review against the settings panel study and for PR screenshots. macOS draws the window's frame and buttons, so they are not in the images.

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

## Offline model load (0004)

`CachedModelOfflineLoadTests` (env-gated by `RIVER_OFFLINE_LOAD`) loads a model River has already downloaded, in a test process that `sandbox-exec` denies network access, and expects it to reach `.ready`. It is the check behind loading a cached model from disk: before that fix, WhisperKit asked Hugging Face for the file list on every launch and an offline start failed. The command is in the test's doc comment; `--disable-sandbox` is required because SwiftPM otherwise applies its own sandbox inside this one, which macOS refuses.

## Related

- [tests.md](tests.md) — the general test conventions and the access seams these harnesses use
- [../architecture/distribution.md](../architecture/distribution.md) — the bundle assertions that back the generated assets
- [../planning/0028_identity-implementation.md](../planning/0028_identity-implementation.md) — the identity build the asset renderers came from
- [../planning/0022_transcription-eval-harness.md](../planning/0022_transcription-eval-harness.md) — the eval harness spec
