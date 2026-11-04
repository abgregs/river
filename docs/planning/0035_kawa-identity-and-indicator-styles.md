# The 川 mark, and the Glass recording indicator (0035)

**Status: implemented on `feat/kawa-identity`, smoke-tested on device 2026-11-02 to 2026-11-04; ready for its PR** (maintainer, 2026-11-04). Stream was removed 2026-11-03 (decision 9); the Glass study retuned Glass and gave the floating panels an opaque lit surface (decision 10); the menu bar's Listening and Transcribing glyph became 川 with a dot (decision 11). Planned 2026-11-02, the day the maintainer settled the kawa motion study (v10). The two smoke rounds and the level calibration between them follow the acceptance criteria. The file name keeps "indicator styles" from when two styles were planned. The current identity is described in [../design/kawa-identity.md](../design/kawa-identity.md); the study it came from is committed in [../design/studies/kawa/](../design/studies/kawa/), and its page [kawa-studies-r1.html](../design/studies/kawa/kawa-studies-r1.html) opens on the approved values.

## Problem

The stones mark ([../design/stones-identity.md](../design/stones-identity.md)) is retired. Its successor, 川 (kawa), was chosen on 2026-10-29 and its motion settled in the study on 2026-11-02. The app still draws the stones r in the menu bar Ready glyph, in the app icon, and in the recording panel, where the stones morph into three level bars. This change puts 川 on those surfaces and replaces the stones animation with the motion the study settled.

## Decisions

All by the maintainer, 2026-11-02, unless marked otherwise. Decisions 3 to 6 are kept as planned; decision 9 supersedes their parts that concern Stream, the setting and the picker.

1. **The mark is 川, variant 3C, centred "halfway":** the point halfway between the ink's box centre and its centroid, on both axes, sits at the centre of the space it is drawn in. The mark is monochrome. The accent leaves the panel; it stays as the control tint ([../design/color.md](../design/color.md)).
2. **The menu bar Ready glyph and the app icon become the solid 川.** The menu bar's recording and transcribing glyph **stays the three stones bars** until it is redrawn for 川 (deferred). The exceptional states keep their SF Symbols. *The bars: superseded by decision 11.*
3. **Two recording indicator styles ship: Stream (the default) and Glass.** Stream is a band of cells that carries the level left to right through the strokes, brighter inside them. Glass is a pane of frost over the strokes that the voice ripples and clears. Both are finished treatments with no tuning of their own. The study's third concept, Level, is dropped, and the stones r is retired with its engine, renderer and presentation. *Stream: superseded by decision 9; Glass is the one treatment.*
4. **One setting, `Settings.indicatorStyle`** (`IndicatorStyle`: `stream`, `glass`; default `Constants.defaultIndicatorStyle = .stream`), declared once (rules 4 and 5). *Superseded by decision 9: the setting is removed.*
5. **A temporary "Recording Indicator" picker in the menu bar dropdown**, for trying the styles on device. This is an explicit exception to the settings direction of 2026-10-31 (no new items in the menu bar dropdown or the current Settings window). The picker moves to the custom settings page when that page exists. *Superseded by decision 9: the picker is removed.*
6. **A style change applies to the next recording.** The panel reads the style when it leaves rest. *Superseded by decision 9: there is no style to change.*
7. **Preparing, in the panel, is the muted strokes held still** at 20 %. The full preparing and downloading treatment is deferred.
8. **Every tuned number is an internal tunable in `Constants`, not a setting.**
9. **One treatment: Glass** (maintainer, 2026-11-03). Stream is removed from the app, with the temporary "Recording Indicator" picker, `Settings.indicatorStyle` and the `IndicatorStyle` enum (never shipped, so no migration), `StreamRenderer` and every `kawaStream*` constant. **Why:** the maintainer chose to focus on mastering one concept rather than keep two. Glass's concept is unchanged, and so is the approved level calibration (ceiling −16 dBFS, curve 1.5, peak hold, `inputLevelReferenceRMS` 0.25, threshold 0.164, tiers 0.32 and 0.60). The motion study pages that show Stream stay in [../design/studies/kawa/](../design/studies/kawa/) as the reference record.
10. **Glass retuned, and an opaque lit surface** (maintainer, on the Glass study, 2026-11-03, a page kept local; opaque 2026-11-04). Per-tier rings and cleared windows, ink 0.45 under the frost and 0.9 cleared; every floating surface an opaque sheet lit from the upper left, sharing one light with Glass's ripples ([../design/color.md](../design/color.md)). **Why:** smoke round 2 found the ripples hard to see at a normal voice and frosted and cleared too alike, and the panel needed a crisper, more solid glass look.
11. **The menu bar's recording dot** (maintainer, 2026-11-04). Listening is 川 with a dot in akaneiro, a muted madder red, while River records; Transcribing keeps the dot in the bar's text color at 55 %. The red's values are in [../design/color.md](../design/color.md). **Why:** a red dot is the convention for a device that is recording, and the muted dot reads as related to recording without being on. A 0.15 s fade between them was tried and removed: the menu bar does not redraw for it.

### Approved tuning

Tuned on the study page and approved on 2026-11-02, then ported as is. Values changed since are marked; Glass's current values are in [../design/kawa-identity.md](../design/kawa-identity.md). Stream's tuning is kept as the record of what was built; it left `Constants` with Stream (decision 9).

- **Shared.** The muted strokes fade in over 0.45 s on a sine ease-in-out (cubic-bezier 0.37, 0, 0.63, 1). The Glass layer starts 0.20 s before the strokes are in. Muted strokes sit at 20 %, one value while recording and while preparing. On release the layer leaves first (0.05 s after release, over 0.4 s); the strokes hold while transcribing, then fade; the panel fades last, over 0.3 s. Reduce Motion turns every envelope into a 0.2 s linear fade.
- **Stream** (removed 2026-11-03, decision 9).
  - *Form:* a grid of square cells that undulates with the voice; no whole cells.
  - *Proportions:* cell pitch 2.4 pt, side room 4 pt, flow 20 pt/s, so the 48 pt panel shows the last 2 s of level. Band height **40 pt** (approved at 32 pt; raised on 2026-11-02 at the maintainer's request in smoke round 1, so raised speech rises past the 30 pt mark: 8 rows a side, 38.4 pt of cells).
  - *Strength:* 30 % outside the strokes, full inside; no glow.
  - *Silence:* one cell either side of the centre line, so a quiet microphone looks quiet, not dead.
  - *Release:* the band collapses.
- **Glass.**
  - *Ripples:* drops on the strokes at a steady 2 per second while the level is above the firing threshold; size 1.6.
  - *Shader:* refraction 0.6, highlights 0.6 (0.4 and 0.8 since the Glass study, decision 10).
  - *Firing threshold:* sensitivity 0.6, a threshold of 0.32 − 0.26 × 0.6 = 0.164 on the 0–1 loudness scale.
  - *Three strengths:* 0.32, 0.60 and 0.84, picked by the peak level since the last ripple: normal from 0.32, loud from 0.60 (since decision 10: ring strengths 0.6, 1.2 and 1.4, each clearing a window of 12, 20 or 28 pt).
  - *Frost:* 0.72, returning over 1.0 s; ink under the glass 0.9; still in silence. Frost forms and ink rises over 0.40 s each (since decision 10: windows hold 1.2 s and fade over 0.6 s; ink 0.45 under the frost, 0.9 cleared; 0.6 s each).
- **The level scale** (calibrated after smoke round 1; see "Results"). Loudness is the input level in dBFS between a floor and a ceiling, raised to a curve: floor −50 dBFS (`markMeterFloorDecibels`, the capture trim's floor `silenceTrimFloor` 0.0032), ceiling −16 dBFS (`markMeterCeilingDecibels`), curve 1.5 (`markMeterCurve`). The microphone reports the loudest buffer of each ~70 ms reading (`inputLevelPublishInterval` 0.07), and the level clips at `inputLevelReferenceRMS` 0.25, about −12 dBFS. On this scale Glass fires from about −40 dBFS, its normal strength starts near −34 dBFS and its loud strength near −26 dBFS (before the engine's smoothing and ±18 % jitter).

## How

- **Mark data.** `KawaMark+Outlines.swift` is generated by `docs/design/studies/kawa/kawa-swift.mjs` from the study's paths: the three strokes as cubic outlines, their spines, the mark's box and the halfway point. `KawaMark` gives the paths, the halfway transform and points along a spine (for Glass drops). `StoneMarkPresentation` and its tests are deleted (and `StoneMark` with the menu bar's bars, decision 11), and `MarkActivity` moved to `RecordingIndicatorPresentation.swift`.
- **Glyph and icon.** `MenuBarGlyphTests` renders `MenuBarReady` from `KawaMark`, 16 pt tall in the 18 pt image; `AppIconTests` renders 川 in ink on the charcoal squircle at `appIconMarkFraction` 0.56. Both are halfway-centred, and a test checks the centring. The PNGs and `River.icns` are regenerated by the env-gated writers; the always-on checks catch drift ([../conventions/test-harnesses.md](../conventions/test-harnesses.md)).
- **Timeline and engine, pure and seeded.** `KawaIndicatorTimeline` ports the study's choreography: input events (press, audio flowing, release, typed) to envelopes (panel, rise, muted, the Stream and Glass layers, collapse, clearing). `KawaIndicatorEngine` ports the study's voice: a shared smoothed level stepped at 240 Hz, Stream's level history, and Glass ripple emission with drops placed along a spine. Golden values from the study's own code pin the port.
- **Audio flowing.** `AppState.isAudioFlowing` turns true on the first level event during `.recording` and false in any other state. A dead microphone therefore never starts the layer, and only the muted strokes show.
- **Exit window.** The mark stays in the panel stack until its exit ends; `RecordingIndicatorCoordinator` orders the window out after `max(hudFadeSeconds, KawaIndicatorTimeline.longestExit)`. The panel stays one bottom-anchored stack in one window ([ADR 0003](../decisions/0003-floating-ui-one-window-stack.md), [0030](0030_floating-ui-visibility.md)). The transcript and message surfaces keep their transitions.
- **Renderers.** `StreamRenderer` draws the grid on a `Canvas` over the whole 48 pt panel. `GlassRenderer` draws the strokes and applies the study's fragment shader, ported to a Metal `[[stitchable]]` layer effect (`Sources/River/Shaders/KawaGlass.metal`). If the shader library fails to load, it logs once at `.error` and draws the muted strokes, so the panel is never blank.
- **Shader build.** `KawaGlass.metal` is excluded from the SwiftPM target. The Makefile compiles it with `xcrun metal` and `xcrun metallib`, copies `KawaGlass.metallib` into `Contents/Resources`, and `make verify` asserts it is there (rule 2, [../architecture/distribution.md](../architecture/distribution.md)).
- **Stream removed (2026-11-03).** `StreamRenderer`, `IndicatorStyle`, `Settings.indicatorStyle`, the menu bar picker, the `kawaStream*` constants and Stream's tests and snapshots are deleted; the timeline and engine drop Stream's parts. The bullets above describe the build as first made.
- **Ripple log.** Each Glass ripple is logged at debug level with its peak and strength (subsystem `com.river.app`, category `indicator`), for AC 4.
- **Seams (2026-11-04).** `KawaIndicatorTimeline.isOn` is the one statement of when the voice drives the layer; under Reduce Motion the engine holds its clearing from the release. `GlassRenderer.arguments` is the shader's whole interface, tested against `KawaGlass.metal`'s signature, with Glass's tuning in `Constants`, its colors in `Palette.HUD` and the light from `HUDSurface.lightDirection`. `KawaIndicatorVoice` turns each level reading into the frame's engine, and the panel and the snapshot harness both draw through it and `KawaMarkPanelFace`. The mark's panel reads the input level itself, so the stack above it does not redraw.
- **Menu bar (decision 11).** `MenuBarReady` and `MenuBarWithDot` (川 beside the dot's place) are template PNGs; `MenuBarGlyphImages.withDot` draws the red or muted dot over the second when the bar draws it, in the bar's own appearance.

## Deferred to the next PR

- The full preparing and downloading treatment in the panel.
- A model-selection step in onboarding, so the first model is chosen by the user and never downloaded silently.

## Acceptance criteria

Smoke test on device, after `make install`.

1. The app icon in Finder and the Dock, and the menu bar Ready glyph, show 川 in monochrome, centred halfway. The glyph follows the menu bar's template tint over light and dark wallpapers.
2. ~~A fresh install records with Stream. Switching the menu picker to Glass applies at the next recording.~~ Dropped with Stream (decision 9): a fresh install records with Glass, and there is no picker.
3. The indicator runs the study's sequence:
   - press → panel → muted strokes → the Glass layer once audio flows;
   - on release, the layer leaves first; the strokes hold while transcribing, then fade; the panel finishes last.
4. Glass ripples at about 2 per second while speaking, and soft, normal and raised speech give visibly different strengths. The debug log of the peak level per ripple shows where real speech falls, and the tier boundaries get retuned if needed.
5. Silence: Glass is still. A dead microphone shows the muted strokes only. (The Stream half, its band lying flat, is dropped with Stream.)
6. Preparing shows the muted strokes held still. The menu bar shows 川 with a red dot while recording and the dot in muted ink while transcribing (2026-11-04; was the three stones bars).
7. Reduce Motion renders the reduced variant; Reduce Transparency changes nothing, the surface being opaque (decision 10); the panel is never blank.

### Results (on device)

**Build checks (2026-11-02).** `swift build` clean (its `River.icns` "unhandled file" warning is pre-existing on `main`); `swift test` all passing; `make verify` passed, including the glyphs, the icon and the Glass metallib.

**Smoke round 1 (2026-11-02).** The maintainer ran the build with `make install` on a MacBook Air with the built-in microphone.

- **AC 4 failed as tuned.** The hum of the room's air conditioning registered as soft or normal speech in both styles, so the indicator was never still; once the air conditioning stopped, the indicator sat still. Low speech drove both styles most of the way, normal and raised speech were barely distinct, and Stream was bounded by the mark's height.
- **Glass:** frosted (silence) and cleared (speech) were not distinct enough at 1×.

**Measured levels.** To find where real speech falls, a temporary log wrote every buffer's level, and the trace was replayed through the real engine offline (both removed before commit). Per-buffer RMS, buffers of about 10 ms, the built-in microphone, eight recordings: silence, low, normal and raised speech, two of each.

| Recording | Level (dBFS) |
|---|---|
| Quiet room | p50 −62, p90 −60 |
| Low speech | p90 −41 / −37 |
| Normal speech | p90 −36 / −31.5 |
| Raised speech | p90 −22; p99 −14 to −16 |

The maintainer noted that the raised takes are the least reliable: they were spoken closer to the microphone, at a varying volume. The only ripples in the silent recordings came from the key click just before release.

**Causes found.**

- The ceiling, −28 dBFS, sat below normal speech, so normal speech filled the scale.
- `inputLevelReferenceRMS` 0.08 clipped the level at about −22 dBFS, below raised speech.
- The 14 Hz throttle emitted whichever ~10 ms buffer came last, often the gap between syllables rather than the syllable.
- The Glass tiers were tuned on the study's simulated 0–1 voice; on the old scale the loud tier began at about −37 dBFS, and the firing threshold sat at about −46 dBFS.

**Calibration (2026-11-02).** Chosen by replaying the trace through the real engine; approved by the maintainer.

- Ceiling −16 dBFS (was −28); curve 1.5 (new; was linear).
- Peak hold: each emission carries the loudest buffer since the last (`MicrophoneCapability.emitLevel`).
- `inputLevelReferenceRMS` 0.25 (was 0.08), so the level clips at about −12 dBFS, above the ceiling.
- The floor (−50 dBFS) and the Glass tier boundaries (0.32, 0.60) are unchanged. The firing threshold now sits at about −40 dBFS.
- The replay predicted: low speech mostly soft ripples (11 of 13), Stream about ⅓ of the band; normal mostly normal (11 of 15), about ½; raised mostly loud (15 of 23), about 90 %, past the mark.
- Stream's band rose from 32 to 40 pt so raised speech rises past the 30 pt mark (maintainer's request).
- A Stream silence variant, a dim centre row drawn inside the strokes only, was tried after round 1. The maintainer rejected it in round 2 (it looked worse); silence stays one cell either side.

**Smoke round 2 (2026-11-03).** Run on the calibrated build. The maintainer judged the thresholds for low, normal and raised speech "excellent". The air-conditioning hum was not present, so the new firing threshold was not verified against it.

**Menu bar dots (2026-11-04).** The maintainer judged the red and the muted dot good; the fade between them did not show, and was removed.

**Not yet recorded on device:** AC 1 (the icon check), the dead-microphone half of AC 5, preparing (AC 6) and AC 7.

## Tests (swift-testing)

- **Mark:** the glyph and icon match their generated art, and the icon is centred halfway (`markIsCentredHalfway`); every Glass drop lands on a stroke's spine.
- **Timeline:** the envelopes at key times (with a press at 0.3 s the strokes rise from 0.38 to 0.83 s; the layer starts 0.2 s before the strokes are in; the exit mirrors the entry; the strokes hold until typed); a dead microphone never starts the layer; a re-press during the exit continues the panel's opacity.
- **Engine:** about 2 ripples per second above the threshold and none below; the strength from the peak since the last ripple; golden values from the study's code.
- **Level scale:** a quiet room reads silence, and soft, normal and raised speech (−37, −31 and −22 dBFS from the trace) take the three Glass strengths (`voicesReadApart`); the level does not clip below the ceiling; `emitLevel` holds the peak (`emitLevelHoldsPeak`).
- **Stream** (deleted with Stream, 2026-11-03): cells inside the strokes are brighter than outside; silence rests at one cell (`silenceRestsAtOneCell`); the band outgrows the mark (`bandOutgrowsMark`); the band collapses on release.
- **Glass's interface and voice (2026-11-04):** every shader argument matches `KawaGlass.metal`'s parameters by name, kind and place; drops pack at its stride; the ripple life and the light are the engine's and the surface's; Reduce Motion's clearing holds through release; each new cycle starts a fresh engine.
- **Menu bar (2026-11-04):** the dot never touches the mark at 1x or 2x; it is the appearance's red while listening and the text color at 55 % while transcribing; each red holds 3:1 on a modelled bar.
- **Plumbing:** `AppState.isAudioFlowing` follows the first level; the coordinator outlives the mark's exit. (The `indicatorStyle` default and round-trip test went with the setting, 2026-11-03.)
- **Snapshots** (env-gated, [../conventions/test-harnesses.md](../conventions/test-harnesses.md)): Glass (both styles until 2026-11-03) at the study's filmstrip times plus soft, normal and loud speech, a dead microphone, preparing and Reduce Motion, in light and dark, fed through `KawaIndicatorVoice` at 60 fps and drawn through `KawaMarkPanelFace`, as the app does.

## Docs updated in the same change

- New [../design/kawa-identity.md](../design/kawa-identity.md), the current identity; [../design/stones-identity.md](../design/stones-identity.md) marked superseded.
- `color.md` (the accent leaves the panel), `app-state-and-menu-bar.md` (the Ready glyph is 川; the bars stay for now), `test-harnesses.md`, `distribution.md` and `anti-patterns.md` #3 (the metallib), `configuration.md` (the `indicatorStyle` row, added, then removed with Stream on 2026-11-03), `design/_index.md`.
- `CHANGELOG.md`: the new mark and the Glass recording indicator under Unreleased.
- 2026-11-04 (decisions 10 and 11): `kawa-identity.md`, `color.md` (the opaque lit surface, the recording red), `app-state-and-menu-bar.md`, `core-feature.md` item 5, `direction.md`, `stones-identity.md` (fully superseded), `distribution.md`, `tests.md`, `test-harnesses.md`, the design and planning indexes, `current-focus.md`.

## Open items

- **Increase Contrast.** Whether the 20 % muted strokes need a lift. Not handled in this change.
- **Frosted ink on the light tint.** 0.45 measures 2.65:1 on `mist` before the frost's blur and veil, below 3:1 ([../design/color.md](../design/color.md)). (The Glass contrast item of 2026-11-03 was closed by decision 10.)
- **A room-adaptive floor**, if a steady room noise such as air conditioning still shows above the new firing threshold. Not reproducible in round 2, so unverified.

## Status and delivery

One PR from `main` on `feat/kawa-identity`, **ready** (maintainer, 2026-11-04). The hold of 2026-11-03 waited on the surface and Glass study, now settled (decision 10). `HUDSurface` is shared by the mark's panel, the message rectangle and the transcript panel, and the settings panel will share it later.
