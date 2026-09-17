# Planning: Identity implementation — river indicator, slat glyph, accent (roadmap 0028)

The native build of the identity settled on 2026-09-16 in [../design/identity-studies.md](../design/identity-studies.md), against the brief in [../design/direction.md](../design/direction.md). Three deliverables, one branch (`docs/identity-studies`, which already carries the design record), one PR: the **river recording indicator** replaces the current HUD's status row, the **five-slat template glyph** replaces the menu bar's SF Symbols for the three cycle states, and the **accent palette** becomes app tokens. The study page [../design/studies/river-identity-studies.html](../design/studies/river-identity-studies.html) is the reference implementation: every number below was measured or tuned there, and the finished app is checked against it side by side.

**Out of scope, by decision:** the app icon (dropped until an agent can design a mark), sound cues, the onboarding and Settings layouts, the menu bar dropdown, and the microphone-bar indicator (built on the study page as the alternative, not shipped).

## Problem

The app ships a generic HUD: `mic.fill` in red with a repeating pulse (which ignores Reduce Motion), a green bar meter, a system material panel, and stock SF Symbols in the menu bar. None of it is River's. The studies produced an indicator whose motion is the identity and a glyph set that reads at a glance; this item lands them without touching the architecture seams.

## Design

### Seams (unchanged)

- The indicator remains an observer of `AppState` (`state`, `inputLevel`, `toast`, `notice`, `modelLoadState`). No new callers into `RiverSession`, no new OS call sites (load-bearing rule 3).
- `RecordingIndicatorCoordinator` keeps the non-activating panel, the show/fade-out branch, and the animate-then-order-out timing on `Constants.hudFadeSeconds`. Only its hosted view changes.
- `MenuBarPresentation.visual(state:hasError:modelLoadState:)` keeps its contract; the three cycle states return an asset name instead of a symbol name, the warning, downloading, and loading states keep their SF Symbols.
- `MicrophoneCapability` still publishes the level every `Constants.levelMeterPublishInterval` (0.07 s). The indicator smooths per display frame; it does not ask the capability for more samples.

### The river indicator (replaces the HUD status row)

**Bar.** A capsule 132 by 56 pt: the 108 by 40 pt mark plus 12 pt at the sides and 8 pt above and below, corner radius 28. Fill near-opaque charcoal `#23262B` at 96% on light appearance and 94% on dark; no material, no blur (decided; a material would flip the palette per desktop). Shadows `0 1 2` at 20% and `0 10 24` at 24% black. On dark appearance only, a 1 pt inner hairline of white at 7% following the capsule. Enter and exit: opacity 0 to 1 with a 6 pt rise, 0.22 s, ease-out both ways (`Constants.hudFadeSeconds`); Reduce Motion makes it a plain fade. No word, no timer.

**Toast and loading label.** The capsule carries only the recording state. The error toast (0018) and the model-loading label (0004) keep their content and render in a separate charcoal rounded rectangle (radius 16, padding 12, same fill and shadow) stacked below the capsule with 8 pt between; the capsule hides while `.idle` even when a toast keeps the panel on screen. Confirm the stacking direction with the maintainer at the first screenshot.

**Strands.** Three polylines sampled at 57 points across the 108 pt width, `y = base + A * (meander + ripple)`, drawn with round caps and joins, under a horizontal mask that fades both ends to nothing over the outer 14% of the width:

| Strand | base y | amp | meander length | ripple length | phase | speed | width | ink |
|---|---|---|---|---|---|---|---|---|
| top | 11.5 | 0.7 | 1.9 | 0.62 | 0.4 | 0.55 | 1.6 | 0.70 |
| middle | 20 | 1.0 | 1.45 | 0.41 | 2.1 | 0.72 | 2.6 | 1.00 |
| bottom | 28.5 | 0.8 | 2.3 | 0.53 | 4.0 | 0.61 | 1.4 | 0.55 |

with `A = 11 * motion * amp`, `meander = sin(2π u / meanderLength + phase + 0.6 * speed * clock)`, `ripple = 0.45 * sin(2π u / rippleLength − 1.9 * speed * clock + 1.7 * phase)`, `u` the fraction across the width, stroke width `width + 0.8 * motion`. Ink is `#ECEEF1` on every strand; the accent never touches the mark.

**Level engine, per display frame.** `smoothed += (target − smoothed) * min(1, rate * dt)` with attack rate 10 and release rate 5 per second (round two's timing). `motion = max(smoothed, 0.35)`: amplitude and width never fall below the level-0.35 shape. `k = smoothstep(smoothed / 0.5)` drives ink and speed: strand opacity `restInk + (ink − restInk) * k`, the strand clock advancing at `0.45 + 0.55 * k` of real time. `restInk = 0.44 + 0.06 * sin(0.9 * t)` (a seven-second breath; held at 0.44 under Reduce Motion). Level 0 at rest, the live input while `.recording`, 0.4 while `.processing`.

**Transcribing.** The lines are untouched; the ink moves. Each strand's stroke is a gradient in mark coordinates: a raised-cosine window 70 pt wide sampled at 17 stops, stop opacity `base + (1 − base) * (0.5 − 0.5 cos(2π k / 16))`, padded to the base beyond the window, translated from −70 to 178 pt once every 2.0 s, each strand offset by 0.18 of the period. `base` blends from 1 (listening) to 0.55 (transcribing) over 0.2 s. Only the stop opacities and the translation change: no overlay stroke, no second shape. Under Reduce Motion `base` stays 1 (the calm lines at full ink).

**Rendering.** `TimelineView(.animation, paused: appState.state == .idle)` over a `Canvas` (or a `Shape` per strand with the gradient as a `ShapeStyle`), all on the main actor; no `Timer`, no `Task` for frames. Everything above is pure `RiverIndicatorPresentation` functions (level smoothing, motion, k, clock rate, ink, crest window, strand y) so the view is thin and the numbers are unit-tested.

**Accessibility.** `accessibilityLabel` "Listening" or "Transcribing", `accessibilityValue` as the elapsed time (spoken only), `accessibilityHidden` on the decorative strands. Reduce Motion as above. The states differ without color: rest is dim and calm, listening is full ink following the voice, transcribing is dim with ink flowing through it.

### The menu bar glyph set

Three template images generated from the slat geometry: five rows at x from 5.5/4/3.5/4/5.5 to the mirrored right end in a 16-unit box. **Ready:** middle slat full ink, the other four at 55%, stroke 1.1. **Listening:** all full, stroke 1.3. **Transcribing:** each slat a row of dots (3, 4, 5, 4, 3) whose first and last centers sit exactly on the slat's endpoints, radius 0.55. For the 16 px asset the rows are snapped to device-pixel centers at 1x and 2x (the 48 pt indicator on the study page keeps the 2.6-unit pitch; the asset uses whatever pitch puts every stroke edge on a device pixel, 2.5 at 2x), so the slats render crisp. Shipped as PNG at 1x and 2x with `isTemplate = true`, built by a checked-in script from the same numbers; `RiverApp` sets the image by asset name from `MenuBarPresentation.Visual`.

### The accent

Tokens in one place (`Palette`): charcoal `#23262B`, raised charcoal `#2E3238`, ink `#ECEEF1`, accent vivid turquoise `#148284` on light appearance and `#31C8CA` on dark (OKLCH hue 196), as dynamic `NSColor`s. Apply as the tint of the app's SwiftUI roots so pressed controls, toggles, and links in Settings and onboarding take it; prominent buttons take white text on the light value and charcoal on the dark value (white on `#31C8CA` measures 2.05:1). No layout changes.

### Constants

Every number that matters lives in `Constants` (rule 5), named for its role: capsule size and padding, fill opacities, hairline opacity, fade rise, attack and release rates, rest level and rest speed, ink span, rest ink and breath depth and rate, transcribing level, crest period, width, stagger, and base, the strand table, and the 16 px asset geometry.

## Acceptance criteria

1. While `.recording`, the capsule shows the three strands responding to the live level; in silence they rest dim and calm, never flat and never sub-pixel; at speech they brighten and widen with the tuned timing. Side by side with the study page at the same level, the shapes match.
2. On `.processing` the strands hold the transcribing motion and the ink crest flows along them with no visible band edge; on `.idle` the capsule fades out with the 6 pt drop and the panel orders out after the fade.
3. The error toast and the loading label still appear, in their own rounded rectangle, with their existing content and timing.
4. Reduce Motion: no crest, no breath, plain fade; every state still distinguishable. VoiceOver reads the state and the elapsed time.
5. The menu bar shows the slat glyph in Ready, Listening, and Transcribing, crisp at 1x and 2x on light and dark bars; the warning, downloading, and loading states are unchanged.
6. The accent tints controls in Settings and onboarding with the right label color per appearance; the recording indicator and the menu bar carry no accent.
7. Unit tests: the pure presentation functions (smoothing rates, motion floor, k, clock rate, ink, crest window, strand y at known inputs, transcribing target) under `@Test(arguments:)`; `MenuBarPresentation` asset names per state; capsule and padding constants. `swift build` and `swift test` pass.
8. No new `CGEvent.post`, `AVAudioEngine.start`, or `CGEvent.tapCreate` call sites; `Info.plist` and entitlements untouched; the bundle still passes `make verify`.
9. Manual smoke on device (the maintainer): light, dark, and a near-black desktop; Reduce Motion and Increase Contrast; all three activation modes; a cancel; a toast.

## Sequence

1. `Palette` tokens and `Constants` entries; tests for the constants that encode decisions.
2. `RiverIndicatorPresentation` (pure) with tests, ported number for number from the study page's river block.
3. `RiverIndicatorView` on `TimelineView` + `Canvas`; the capsule, hairline, fade; toast and label stacking; accessibility.
4. Swap it into `RecordingIndicatorCoordinator`; remove `LevelMeterView`, the pulse, and the material.
5. Glyph asset script and the three template images at 1x and 2x; `MenuBarPresentation` and `RiverApp` wiring; tests.
6. Accent tint on the SwiftUI roots; prominent-button label color per appearance.
7. Build, test, `make install`, on-device smoke against the study page; screenshots into the PR.

## Related

- [../design/identity-studies.md](../design/identity-studies.md) — every decision and every rejected attempt; the working rules
- [../design/direction.md](../design/direction.md) — the brief and the sequence this item starts
- [../design/studies/river-identity-studies.html](../design/studies/river-identity-studies.html) — the reference implementation; `bar-shape.py`, `bar-shapes.json`, and `turquoise-variants.json` beside it
- [0002_recording-indicator-hud.md](0002_recording-indicator-hud.md), [0018](0018_transient-error-toasts.md), [0020](0020_mic-level-meter.md), [0004](0004_model-loading-indicator.md) — the HUD surfaces this item re-renders
- [../architecture/app-state-and-menu-bar.md](../architecture/app-state-and-menu-bar.md) — the seam the indicator and the glyph observe
